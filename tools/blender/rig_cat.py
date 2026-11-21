"""Headless quadruped rig and core clips for the black cat mount.

Meshy cannot rig quadrupeds, so card 3 generates the armoured cat as an unrigged mesh
(`tools/meshy/meshy.py generate cat_mount`) and this script rigs and animates it in Blender:

    ~/.local/opt/blender/blender -b -P tools/blender/rig_cat.py -- \
        --in assets/characters/cat_mount/source/cat_mount_source.glb \
        --out assets/characters/cat_mount/cat_mount.glb

Steps (all deterministic, so the GLB is reproducible from this script + the source GLB):

1. Import the GLB, weld split vertices, orient the cat (head toward -Y, feet on z = 0, glTF +Z
   after export) and scale it so the back stands `--shoulder-height` metres tall.
2. Build the armature from landmarks measured on the mesh (feet, back line, head, tail): root,
   spine (pelvis, spine_01..03), neck, head, jaw, four 4-bone legs ending in paw bones, a 6-bone
   tail and a non-deforming `saddle` socket bone for the rider.
3. Bind with Blender's automatic (heat) weights. Vertices the solver leaves unweighted fall back to
   distance weights; every vertex is then limited to 4 influences and normalised.
4. Author the clips procedurally (idle, walk, run, gallop, pounce, hit, flee, sit) as Blender
   Actions, one glTF animation each.
5. Report deformation metrics per clip, export the GLB and write `import.json` beside it (clip
   loop flags and the rim-light request read by tools/import/humanoid_post_import.gd).

Axis convention in Blender: the cat faces -Y (glTF +Z), up is +Z, its left is +X.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Quaternion, Vector

FPS = 30
MAX_INFLUENCES = 4
MAX_TRIS = 30000

# Bone names (Godot-friendly: no dots). Legs: front = shoulder/upper/lower/paw,
# rear = thigh/shin/foot/paw. Suffix _l = cat's left (+X), _r = right (-X).
SPINE = ["pelvis", "spine_01", "spine_02", "spine_03"]
NECK = ["neck_01", "neck_02", "head"]
TAIL = [f"tail_{i:02d}" for i in range(1, 7)]
FRONT_LEG = ["front_shoulder_{s}", "front_upper_{s}", "front_lower_{s}", "front_paw_{s}"]
REAR_LEG = ["rear_thigh_{s}", "rear_shin_{s}", "rear_foot_{s}", "rear_paw_{s}"]
PAW_BONES = ["front_paw_l", "front_paw_r", "rear_paw_l", "rear_paw_r"]
NON_DEFORM = ["root", "saddle"]

LOOPING = {"idle", "walk", "run", "gallop", "flee", "sit"}


def log(message: str) -> None:
    print(f"[rig_cat] {message}", flush=True)


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(prog="rig_cat.py", description=__doc__.split("\n")[0])
    parser.add_argument("--in", dest="src", required=True, help="unrigged cat GLB (Meshy output)")
    parser.add_argument("--out", required=True, help="rigged GLB to write")
    parser.add_argument("--shoulder-height", type=float, default=0.9, help="back height in metres")
    parser.add_argument("--blend", help="also save a .blend (debugging; not committed)")
    parser.add_argument("--ascii", action="store_true", help="print a bone overlay of the side view")
    parser.add_argument("--no-clips", action="store_true", help="rig only (skip animation)")
    return parser.parse_args(argv)


# --------------------------------------------------------------------------- mesh preparation


def coords(mesh: bpy.types.Mesh) -> np.ndarray:
    flat = np.empty(len(mesh.vertices) * 3)
    mesh.vertices.foreach_get("co", flat)
    return flat.reshape(-1, 3)


def set_coords(mesh: bpy.types.Mesh, verts: np.ndarray) -> None:
    mesh.vertices.foreach_set("co", verts.ravel())
    mesh.update()


def import_cat(path: str) -> bpy.types.Object:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit(f"{path}: no mesh in the GLB")
    for obj in bpy.context.scene.objects:
        obj.select_set(obj in meshes)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.data.transform(obj.matrix_world)  # bake any node transform into the vertices
    obj.matrix_world = Matrix.Identity(4)
    obj.parent = None
    for other in [o for o in bpy.context.scene.objects if o is not obj]:
        bpy.data.objects.remove(other, do_unlink=True)
    obj.name = "Cat"
    obj.data.name = "Cat"
    return obj


def weld(obj: bpy.types.Object) -> None:
    """The importer splits vertices at UV/normal seams; weld them so skin weights are continuous."""
    before = len(obj.data.vertices)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    log(f"welded vertices {before} -> {len(obj.data.vertices)}")


def grid_components(points: np.ndarray, cell: float) -> list[np.ndarray]:
    """Connected components of points on a coarse XY grid (8-neighbourhood); returns index arrays."""
    keys = np.floor(points[:, :2] / cell).astype(int)
    cells: dict[tuple[int, int], list[int]] = {}
    for index, key in enumerate(map(tuple, keys)):
        cells.setdefault(key, []).append(index)
    seen: set[tuple[int, int]] = set()
    groups: list[np.ndarray] = []
    for start in cells:
        if start in seen:
            continue
        stack, members = [start], []
        while stack:
            cur = stack.pop()
            if cur in seen:
                continue
            seen.add(cur)
            members += cells[cur]
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    nxt = (cur[0] + dx, cur[1] + dy)
                    if nxt in cells and nxt not in seen:
                        stack.append(nxt)
        groups.append(np.array(members))
    return groups


def normalise(obj: bpy.types.Object, shoulder_height: float) -> dict:
    """Orient (head -Y, feet z=0, centred on the paws), scale, and measure landmarks."""
    mesh = obj.data
    v = coords(mesh)
    # 1. yaw: long horizontal axis -> Y, head (highest points: ears/ruff) toward -Y.
    flat = v[:, :2] - v[:, :2].mean(axis=0)
    _, vecs = np.linalg.eigh(np.cov(flat.T))
    axis = vecs[:, 1]
    top = v[:, 2] > np.percentile(v[:, 2], 97)
    if (v[top, :2].mean(axis=0) - v[:, :2].mean(axis=0)) @ axis < 0:
        axis = -axis
    yaw = -math.pi / 2 - math.atan2(axis[1], axis[0])
    v = v @ Matrix.Rotation(yaw, 3, "Z").transposed()
    # 2. feet: the four biggest low XY components (the tail tip may also touch down).
    height = v[:, 2].max() - v[:, 2].min()
    low = np.where(v[:, 2] < v[:, 2].min() + 0.04 * height)[0]
    groups = sorted(grid_components(v[low], 0.04 * height), key=len, reverse=True)
    for g in groups[:8]:
        c = v[low[g]].mean(axis=0)
        log(f"contact patch: {len(g)} verts at x={c[0]:.2f} y={c[1]:.2f}")
    if len(groups) < 4:
        raise SystemExit(f"expected four paws on the ground, found {len(groups)} contact patches")
    feet = [v[low[g]].mean(axis=0) for g in groups[:4]]
    feet.sort(key=lambda p: p[1])  # front (most -Y) first
    front = sorted(feet[:2], key=lambda p: -p[0])  # +X = left first
    rear = sorted(feet[2:], key=lambda p: -p[0])
    # 3. recentre on the paws, ground at z=0.
    centre = np.array(
        [np.mean([p[0] for p in feet]), np.mean([p[1] for p in feet]), v[:, 2].min()]
    )
    v = v - centre
    front = [p - centre for p in front]
    rear = [p - centre for p in rear]
    wheel_y = (np.mean([p[1] for p in front]) + np.mean([p[1] for p in rear])) / 2
    torso = (np.abs(v[:, 1] - wheel_y) < 0.15 * abs(rear[0][1] - front[0][1])) & (
        np.abs(v[:, 0]) < 0.35 * abs(front[0][0] - front[1][0])
    )
    back_height = float(np.percentile(v[torso, 2], 98))
    scale = shoulder_height / back_height
    v *= scale
    front = [p * scale for p in front]
    rear = [p * scale for p in rear]
    set_coords(mesh, v)
    log(f"yaw {math.degrees(yaw):.1f} deg, scale {scale:.4f}, back height {shoulder_height} m")
    return {"v": v, "front": front, "rear": rear, "scale": scale}


def measure(v: np.ndarray, front: list, rear: list, back: float) -> dict:
    """Landmarks derived from the oriented mesh (all metres, armature space)."""
    fy = float(np.mean([p[1] for p in front]))
    ry = float(np.mean([p[1] for p in rear]))
    ymin, ymax = float(v[:, 1].min()), float(v[:, 1].max())
    # Back line: top of the torso in slices between the paws, smoothed with a quadratic fit so
    # fur tufts and the blanket do not zig-zag the spine.
    sample_y = np.linspace(ry + 0.05, fy - 0.05, 10)
    tops = []
    for y in sample_y:
        sel = np.abs(v[:, 1] - y) < 0.06
        tops.append(np.percentile(v[sel, 2], 96) if sel.any() else back)
    fit = np.polynomial.Polynomial.fit(sample_y, tops, 2)

    def back_z(y: float, win: float = 0.05) -> float:
        return float(fit(np.clip(y, sample_y.min(), sample_y.max())))

    head_sel = (v[:, 1] < fy - 0.10) & (v[:, 2] > 0.55 * back)
    head = v[head_sel]
    head_c = head.mean(axis=0)
    nose = head[np.argmin(head[:, 1])]
    tail_sel = v[:, 1] > ry + 0.20
    slices = []
    for y0 in np.linspace(ry + 0.20, ymax - 0.02, 8):
        sel = tail_sel & (np.abs(v[:, 1] - y0) < 0.05)
        if sel.any():
            slices.append(np.array([v[sel, 0].mean(), y0, v[sel, 2].mean()]))
    tip = v[tail_sel][np.argsort(v[tail_sel][:, 1])[-30:]].mean(axis=0)
    return {
        "fy": fy,
        "ry": ry,
        "ymin": ymin,
        "ymax": ymax,
        "back_z": back_z,
        "head_c": head_c,
        "nose": nose,
        "tail_pts": slices,
        "tail_tip": tip,
        "saddle_y": (fy + ry) / 2 - 0.02,
    }


# --------------------------------------------------------------------------- armature


def leg_path(v: np.ndarray, paw: np.ndarray, height: float):
    """Centreline of the leg standing on `paw`: follow the vertices upward slice by slice.

    Returns f(z) -> (x, y, z), linear inside the traced range and extrapolated above it."""
    side = 1.0 if paw[0] > 0 else -1.0
    centre = np.array([paw[0], paw[1]])
    zs, xs, ys = [], [], []
    for z in np.arange(0.02, 0.62 * height, 0.04):
        sel = (np.abs(v[:, 2] - z) < 0.03) & (v[:, 0] * side > 0.02)
        sel &= np.linalg.norm(v[:, :2] - centre, axis=1) < 0.13
        if sel.sum() < 8:
            continue
        centre = v[sel, :2].mean(axis=0)
        zs.append(z)
        xs.append(centre[0])
        ys.append(centre[1])
    zs, xs, ys = np.array(zs), np.array(xs), np.array(ys)

    def at(z: float):
        x = np.interp(z, zs, xs)
        y = np.interp(z, zs, ys)
        if z > zs[-1]:  # extrapolate along the top of the traced leg, damped
            k = max(0, len(zs) - 4)
            span = zs[-1] - zs[k]
            x = xs[-1] + (xs[-1] - xs[k]) / span * (z - zs[-1]) * 0.5
            y = ys[-1] + (ys[-1] - ys[k]) / span * (z - zs[-1]) * 0.5
        return (float(x), float(y), float(z))

    return at


def build_armature(obj: bpy.types.Object, nm: dict) -> bpy.types.Object:
    v = nm["v"]
    front, rear = nm["front"], nm["rear"]
    height = 0.9 if v is None else float(np.percentile(v[:, 2], 98))
    lm = measure(v, front, rear, height)
    back_z = lm["back_z"]
    arm_data = bpy.data.armatures.new("Armature")
    arm = bpy.data.objects.new("Armature", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    edit = arm_data.edit_bones
    made: dict[str, tuple] = {}

    def bone(name: str, head, tail, parent: str | None, deform: bool = True) -> None:
        b = edit.new(name)
        b.head, b.tail = Vector(head), Vector(tail)
        b.use_deform = deform
        if parent:
            b.parent = edit[parent]
        made[name] = (tuple(head), tuple(tail))

    body_depth = 0.14
    y_rear = lm["ry"] + 0.10
    y_front = lm["fy"] - 0.02
    ys = [y_rear + (y_front - y_rear) * k / 4 for k in range(5)]
    zs = [back_z(y) - body_depth for y in ys]
    bone("root", (0, 0, 0), (0, 0.15, 0), None, deform=False)
    parents = ["root", "pelvis", "spine_01", "spine_02"]
    for i, name in enumerate(SPINE):
        bone(name, (0, ys[i], zs[i]), (0, ys[i + 1], zs[i + 1]), parents[i])
    neck_base = Vector((0, ys[4], zs[4]))
    hc = Vector(lm["head_c"])
    head_back = Vector((0, hc.y + 0.06, hc.z))
    nose = Vector((0, lm["nose"][1], lm["nose"][2]))
    mid = neck_base.lerp(head_back, 0.5)
    bone("neck_01", neck_base, mid, "spine_03")
    bone("neck_02", mid, head_back, "neck_01")
    bone("head", head_back, nose, "neck_02")
    jaw_head = Vector((0, hc.y - 0.02, hc.z - 0.05))
    bone("jaw", jaw_head, jaw_head + Vector((0, -0.09, -0.03)), "head")
    # Tail: from the rump along the measured centreline to the tip.
    base = Vector((0, y_rear + 0.04, zs[0] + 0.02))
    pts = [base] + [Vector(p) for p in lm["tail_pts"]] + [Vector(lm["tail_tip"])]
    dist = [0.0]
    for a, b in zip(pts, pts[1:]):
        dist.append(dist[-1] + (b - a).length)
    nodes = []
    for k in range(len(TAIL) + 1):
        target = dist[-1] * k / len(TAIL)
        j = max(i for i, d in enumerate(dist) if d <= target + 1e-9)
        j = min(j, len(pts) - 2)
        seg = dist[j + 1] - dist[j]
        t = 0.0 if seg < 1e-9 else (target - dist[j]) / seg
        nodes.append(pts[j].lerp(pts[j + 1], t))
    nodes = [Vector((0.0, p.y, p.z)) for p in nodes]
    for i, name in enumerate(TAIL):
        bone(name, nodes[i], nodes[i + 1], "pelvis" if i == 0 else TAIL[i - 1])
    # Legs follow the measured leg centreline, so a leg modelled mid-stride keeps its slope.
    for side, fpos, rpos in (("l", front[0], rear[0]), ("r", front[1], rear[1])):
        path = leg_path(v, fpos, height)
        sh, el, wr = (path(f * height) for f in (0.72, 0.42, 0.14))
        paw0 = path(0.03 * height)
        toe = (paw0[0], paw0[1] - 0.07, 0.02)
        names = [n.format(s=side) for n in FRONT_LEG]
        bone(names[0], (sh[0] * 0.35, sh[1] + 0.03, 0.88 * height), sh, "spine_03")
        bone(names[1], sh, el, names[0])
        bone(names[2], el, wr, names[1])
        bone(names[3], wr, toe, names[2])
        path = leg_path(v, rpos, height)
        hip, knee, hock, ankle = (path(f * height) for f in (0.78, 0.50, 0.22, 0.07))
        paw0 = path(0.02 * height)
        toe_r = (paw0[0], paw0[1] - 0.06, 0.02)
        names = [n.format(s=side) for n in REAR_LEG]
        bone(names[0], hip, knee, "pelvis")
        bone(names[1], knee, hock, names[0])
        bone(names[2], hock, ankle, names[1])
        bone(names[3], ankle, toe_r, names[2])
    # Saddle socket: identity-oriented (points +Y, roll 0) so a BoneAttachment3D is world-aligned.
    sy = lm["saddle_y"]
    sz = back_z(sy, 0.08) - 0.01
    bone("saddle", (0, sy, sz), (0, sy + 0.10, sz), "spine_02", deform=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    lm["bones"] = made
    lm["saddle_z"] = sz
    return arm, lm


def ascii_overlay(v: np.ndarray, bones: dict) -> None:
    h, w = 36, 110
    y0, y1 = v[:, 1].min(), v[:, 1].max()
    z0, z1 = 0.0, v[:, 2].max()
    grid = [[" "] * w for _ in range(h)]

    def cell(y: float, z: float) -> tuple[int, int]:
        return (
            h - 1 - int((z - z0) / (z1 - z0 + 1e-9) * (h - 1)),
            int((y - y0) / (y1 - y0 + 1e-9) * (w - 1)),
        )

    for y, z in zip(v[:, 1], v[:, 2]):
        r, c = cell(y, z)
        if 0 <= r < h and 0 <= c < w:
            grid[r][c] = "."
    for name, (a, b) in bones.items():
        for t in np.linspace(0, 1, 12):
            r, c = cell(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)
            if 0 <= r < h and 0 <= c < w:
                grid[r][c] = name[0].upper() if t < 0.99 else "o"
    log("side view (head left, '.' mesh, letters = first letter of each bone):")
    for row in grid:
        log("".join(row))


# --------------------------------------------------------------------------- skinning


def bind_weights(obj: bpy.types.Object, arm: bpy.types.Object) -> dict:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    mesh = obj.data
    names = {g.index: g.name for g in obj.vertex_groups}
    deform = {b.name for b in arm.data.bones if b.use_deform}
    total = np.zeros(len(mesh.vertices))
    for vert in mesh.vertices:
        total[vert.index] = sum(g.weight for g in vert.groups if names[g.group] in deform)
    missing = np.where(total < 0.5)[0]
    log(f"auto weights: {len(missing)} of {len(mesh.vertices)} vertices unweighted")
    if len(missing):
        fallback_weights(obj, arm, missing)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.vertex_group_limit_total(group_select_mode="BONE_DEFORM", limit=MAX_INFLUENCES)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="BONE_DEFORM", lock_active=False)
    return {"unweighted": int(len(missing))}


def fallback_weights(obj: bpy.types.Object, arm: bpy.types.Object, indices: np.ndarray) -> None:
    """Distance-to-bone-segment weights for vertices the heat solver skipped."""
    segs = [
        (b.name, np.array(b.head_local), np.array(b.tail_local))
        for b in arm.data.bones
        if b.use_deform
    ]
    mesh = obj.data
    verts = coords(mesh)
    for index in indices:
        p = verts[index]
        scored = []
        for name, a, b in segs:
            ab = b - a
            t = float(np.clip(((p - a) @ ab) / (ab @ ab + 1e-12), 0.0, 1.0))
            scored.append((np.linalg.norm(p - (a + ab * t)), name))
        scored.sort()
        near = scored[:3]
        for dist, name in near:
            group = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
            group.add([int(index)], 1.0 / (dist + 0.02), "REPLACE")


def weight_report(obj: bpy.types.Object, arm: bpy.types.Object) -> None:
    """Per bone: vertices it dominates, their centroid and distance to the bone midpoint.

    A bone whose dominated vertices sit far from it is mis-placed or mis-weighted."""
    names = {g.index: g.name for g in obj.vertex_groups}
    verts = coords(obj.data)
    owner = np.full(len(verts), "", dtype=object)
    for vert in obj.data.vertices:
        if vert.groups:
            owner[vert.index] = names[max(vert.groups, key=lambda g: g.weight).group]
    for b in arm.data.bones:
        sel = owner == b.name
        if not sel.any():
            log(f"weights {b.name:<20} dominates 0 vertices")
            continue
        centre = verts[sel].mean(axis=0)
        mid = (np.array(b.head_local) + np.array(b.tail_local)) / 2
        log(
            f"weights {b.name:<20} n={int(sel.sum()):5d} centroid=({centre[0]:+.2f},{centre[1]:+.2f},"
            f"{centre[2]:.2f}) bone_mid=({mid[0]:+.2f},{mid[1]:+.2f},{mid[2]:.2f}) "
            f"off={np.linalg.norm(centre - mid):.2f}"
        )


# --------------------------------------------------------------------------- pose helpers


class Rig:
    """Pose authoring in armature-rest axes: a rotation of `rx` about the cat's lateral axis
    swings a hanging bone toward +Y (backward); positive `rx` on a leg moves the paw back."""

    def __init__(self, arm: bpy.types.Object) -> None:
        self.arm = arm
        self.rest = {b.name: b.matrix_local.to_quaternion() for b in arm.data.bones}
        for pb in arm.pose.bones:
            pb.rotation_mode = "QUATERNION"

    def apply(self, pose: dict, loc: dict | None = None) -> None:
        """Set every pose bone from `pose` {bone: (rx, ry, rz) degrees}; others return to rest."""
        for pb in self.arm.pose.bones:
            rx, ry, rz = pose.get(pb.name, (0.0, 0.0, 0.0))
            delta = Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ")
            rest = self.rest[pb.name]
            pb.rotation_quaternion = rest.inverted() @ delta.to_quaternion() @ rest
            offset = (loc or {}).get(pb.name)
            pb.location = rest.inverted() @ Vector(offset) if offset else Vector((0, 0, 0))

    def key(self, frame: int, bones: set[str]) -> None:
        for name in bones:
            pb = self.arm.pose.bones[name]
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            pb.keyframe_insert("location", frame=frame)


def add(pose: dict, name: str, rx: float = 0.0, ry: float = 0.0, rz: float = 0.0) -> None:
    cur = pose.get(name, (0.0, 0.0, 0.0))
    pose[name] = (cur[0] + rx, cur[1] + ry, cur[2] + rz)


def leg(pose: dict, kind: str, side: str, upper: float, lower: float, paw: float, top: float = 0.0):
    """Pitch the four bones of a leg (degrees about the lateral axis)."""
    names = [n.format(s=side) for n in (FRONT_LEG if kind == "front" else REAR_LEG)]
    add(pose, names[0], rx=top)
    add(pose, names[1], rx=upper)
    add(pose, names[2], rx=lower)
    add(pose, names[3], rx=paw)


def tail_wave(pose: dict, t: float, amp: float, lift: float = 0.0, speed: float = 1.0) -> None:
    for i, name in enumerate(TAIL):
        add(pose, name, rx=lift, rz=amp * (0.4 + 0.25 * i) * math.sin(2 * math.pi * speed * t - 0.7 * i))


def stride_leg(pose: dict, kind: str, side: str, p: float, amp: float, fold: float, bias: float = 0):
    """One leg of a cyclic gait. p in [0,1): 0 = touchdown (paw furthest forward), stance first."""
    swing = max(0.0, -math.sin(2 * math.pi * p))
    upper = -amp * math.cos(2 * math.pi * p) + bias
    lower = fold * swing
    paw = -0.75 * (upper + lower) + 12.0 * swing
    leg(pose, kind, side, upper, lower, paw, top=0.25 * upper if kind == "front" else 0.0)


def make_cycle(name: str, frames: int, builder) -> tuple[str, int, list]:
    # frames + 1 samples: the last key repeats the first pose at t = frames / FPS, so the
    # exported clip length is the full cycle and the wrap is seamless (Godot loops at length).
    return name, frames + 1, [builder(f / frames) for f in range(frames + 1)]


def walk_pose(t: float) -> tuple[dict, dict]:
    pose: dict = {}
    for kind, side, off in (("rear", "l", 0.0), ("front", "l", 0.25), ("rear", "r", 0.5), ("front", "r", 0.75)):
        stride_leg(pose, kind, side, (t + off) % 1.0, 22 if kind == "front" else 20, 40)
    s = math.sin(2 * math.pi * t)
    for i, bone_name in enumerate(SPINE):
        add(pose, bone_name, rz=3.0 * math.sin(2 * math.pi * t + 0.6 * i))
    add(pose, "neck_01", rz=-2 * s, rx=2)
    add(pose, "head", rz=-3 * s, rx=-2)
    tail_wave(pose, t, 5.0, lift=-2)
    return pose, {"root": (0, 0, -0.03 + 0.008 * math.cos(4 * math.pi * t))}


def run_pose(t: float) -> tuple[dict, dict]:
    pose: dict = {}
    for kind, side, off in (("front", "l", 0.0), ("rear", "r", 0.0), ("front", "r", 0.5), ("rear", "l", 0.5)):
        stride_leg(pose, kind, side, (t + off) % 1.0, 30 if kind == "front" else 28, 58)
    c = math.cos(4 * math.pi * t)
    for i, bone_name in enumerate(SPINE):
        add(pose, bone_name, rx=-2.5 * c, rz=2.0 * math.sin(2 * math.pi * t + 0.6 * i))
    add(pose, "neck_01", rx=2.5 * c + 4)
    add(pose, "head", rx=2.5 * c - 4)
    tail_wave(pose, t, 3.0, lift=-6)
    return pose, {"root": (0, 0, -0.05 + 0.02 * c)}


def gallop_pose(t: float) -> tuple[dict, dict]:
    pose: dict = {}
    for kind, side, off in (("front", "l", 0.0), ("front", "r", 0.08), ("rear", "r", 0.5), ("rear", "l", 0.58)):
        stride_leg(pose, kind, side, (t + off) % 1.0, 40 if kind == "front" else 36, 80)
    flex = math.sin(2 * math.pi * (t + 0.25))
    for i, bone_name in enumerate(SPINE):
        add(pose, bone_name, rx=-7.0 * flex * (0.6 + 0.2 * i))
    add(pose, "neck_01", rx=5.0 * flex + 5)
    add(pose, "head", rx=4.0 * flex - 6)
    tail_wave(pose, t, 2.0, lift=-8 + 3 * flex)
    return pose, {"root": (0, 0, -0.04 + 0.06 * math.cos(2 * math.pi * (t + 0.1)))}


def idle_pose(t: float) -> tuple[dict, dict]:
    pose: dict = {}
    breath = math.sin(2 * math.pi * t)
    add(pose, "spine_02", rx=-0.8 * breath)
    add(pose, "spine_03", rx=-1.4 * breath)
    add(pose, "neck_01", rx=1.0 * breath, rz=4.0 * math.sin(2 * math.pi * t))
    add(pose, "neck_02", rz=3.0 * math.sin(2 * math.pi * t))
    add(pose, "head", rx=2.0 * math.sin(4 * math.pi * t + 1.0), rz=6.0 * math.sin(2 * math.pi * t - 0.4))
    add(pose, "jaw", rx=1.0 + 0.5 * breath)
    tail_wave(pose, t, 6.0, lift=-3)
    return pose, {"root": (0, 0, 0.004 * breath)}


def flee_pose(t: float) -> tuple[dict, dict]:
    """Hurt run: head low, tail tucked, front-left paw held up (limp)."""
    pose: dict = {}
    for kind, side, off in (("front", "r", 0.0), ("rear", "l", 0.0), ("rear", "r", 0.5)):
        stride_leg(pose, kind, side, (t + off) % 1.0, 24 if kind == "front" else 26, 55)
    leg(pose, "front", "l", -28 - 6 * math.sin(2 * math.pi * t), 85, 25, top=-6)
    c = math.cos(4 * math.pi * t)
    for i, bone_name in enumerate(SPINE):
        add(pose, bone_name, rx=3.0 + 2.0 * c, rz=2.0 * math.sin(2 * math.pi * t + 0.5 * i))
    add(pose, "neck_01", rx=14)
    add(pose, "neck_02", rx=8)
    add(pose, "head", rx=6)
    tail_wave(pose, t, 2.0, lift=14)
    return pose, {"root": (0, 0, -0.06 + 0.025 * c)}


# --------------------------------------------------------------------------- key-pose clips

REST: dict = {}


def crouch_pose(depth: float = 1.0) -> dict:
    pose: dict = {}
    add(pose, "pelvis", rx=-4 * depth)
    for name, v in (("spine_01", 3), ("spine_02", 7), ("spine_03", 10)):
        add(pose, name, rx=v * depth)
    add(pose, "neck_01", rx=8 * depth)
    add(pose, "neck_02", rx=-6 * depth)
    add(pose, "head", rx=-14 * depth)
    for side in ("l", "r"):
        leg(pose, "front", side, 38 * depth, -72 * depth, 20 * depth, top=14 * depth)
        leg(pose, "rear", side, -52 * depth, 100 * depth, -45 * depth, 0)
        add(pose, f"rear_paw_{side}", rx=0)
    for i, name in enumerate(TAIL):
        add(pose, name, rx=6 * depth, rz=0)
    return pose


def launch_pose() -> dict:
    pose: dict = {}
    add(pose, "pelvis", rx=-16)
    for name in ("spine_01", "spine_02", "spine_03"):
        add(pose, name, rx=-5)
    add(pose, "neck_01", rx=6)
    add(pose, "head", rx=-4)
    for side in ("l", "r"):
        leg(pose, "front", side, -38, -14, -8, top=-18)
        leg(pose, "rear", side, 40, -12, -30)
    for name in TAIL:
        add(pose, name, rx=-8)
    return pose


def apex_pose() -> dict:
    pose: dict = {}
    add(pose, "pelvis", rx=-4)
    add(pose, "spine_01", rx=-4)
    add(pose, "spine_02", rx=-3)
    add(pose, "spine_03", rx=-3)
    add(pose, "neck_01", rx=4)
    add(pose, "head", rx=-6)
    for side in ("l", "r"):
        leg(pose, "front", side, -52, -6, -18, top=-24)
        leg(pose, "rear", side, 58, 10, 14)
    for name in TAIL:
        add(pose, name, rx=-16)
    return pose


def descend_pose() -> dict:
    pose: dict = {}
    add(pose, "pelvis", rx=-2)
    for name in ("spine_01", "spine_02", "spine_03"):
        add(pose, name, rx=6)
    add(pose, "neck_01", rx=4)
    add(pose, "head", rx=-8)
    for side in ("l", "r"):
        leg(pose, "front", side, -32, -18, 6, top=-14)
        leg(pose, "rear", side, 22, 30, -20)
    for name in TAIL:
        add(pose, name, rx=-10)
    return pose


def land_pose() -> dict:
    pose = crouch_pose(0.8)
    add(pose, "head", rx=-8)
    for name in TAIL:
        add(pose, name, rx=-8)
    return pose


def hit_pose(strength: float) -> dict:
    pose: dict = {}
    add(pose, "pelvis", rx=6 * strength)
    for name, v in (("spine_01", -8), ("spine_02", -10), ("spine_03", -12)):
        add(pose, name, rx=v * strength)
    add(pose, "neck_01", rx=-10 * strength)
    add(pose, "head", rx=-16 * strength, rz=10 * strength)
    add(pose, "jaw", rx=22 * strength)
    for side in ("l", "r"):
        leg(pose, "front", side, -14 * strength, 24 * strength, 8 * strength, top=-6 * strength)
        leg(pose, "rear", side, 10 * strength, 10 * strength, -10 * strength)
    for i, name in enumerate(TAIL):
        add(pose, name, rx=-22 * strength, rz=10 * strength * (i % 2 * 2 - 1))
    return pose


def sit_pose() -> dict:
    pose: dict = {}
    add(pose, "pelvis", rx=-15)
    add(pose, "spine_01", rx=10)
    add(pose, "spine_02", rx=10)
    add(pose, "spine_03", rx=8)
    add(pose, "neck_01", rx=8)
    add(pose, "head", rx=6)
    for side in ("l", "r"):
        leg(pose, "front", side, 6, 0, 0, top=4)
        leg(pose, "rear", side, -42, 140, -150, 0)
    for i, name in enumerate(TAIL):
        add(pose, name, rx=-10 if i == 0 else 4, rz=10 if i > 1 else 0)
    return pose


def blend(a: dict, b: dict, w: float) -> dict:
    out: dict = {}
    for name in set(a) | set(b):
        pa = a.get(name, (0, 0, 0))
        pb = b.get(name, (0, 0, 0))
        out[name] = tuple(x + (y - x) * w for x, y in zip(pa, pb))
    return out


def keyed_clip(name: str, keys: list[tuple[int, dict, float]]) -> tuple[str, int, list]:
    """Key table [(frame, pose, root_z_offset)] -> dense frames with smooth interpolation."""
    last = keys[-1][0]
    frames = []
    for f in range(last + 1):
        for (f0, p0, z0), (f1, p1, z1) in zip(keys, keys[1:]):
            if f0 <= f <= f1:
                w = 0.0 if f1 == f0 else (f - f0) / (f1 - f0)
                w = w * w * (3 - 2 * w)  # smoothstep
                frames.append((blend(p0, p1, w), {"root": (0, 0, z0 + (z1 - z0) * w)}))
                break
    return name, last, frames


# --------------------------------------------------------------------------- actions


def ground_offset(rig: Rig, obj: bpy.types.Object, grounded: np.ndarray, pose: dict) -> float:
    """Root z that puts the lowest paw vertex of `pose` on z = 0."""
    rig.apply(pose)
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(deps)
    mesh = ev.to_mesh()
    z = coords(mesh)[:, 2]
    ev.to_mesh_clear()
    return float(-z[grounded].min())


def paw_vertices(obj: bpy.types.Object) -> np.ndarray:
    """Indices of vertices mostly weighted to a paw bone (the ground contact set)."""
    names = {g.index: g.name for g in obj.vertex_groups}
    picked = []
    for vert in obj.data.vertices:
        if not vert.groups:
            continue
        best = max(vert.groups, key=lambda g: g.weight)
        if names[best.group] in PAW_BONES:
            picked.append(vert.index)
    return np.array(picked, dtype=int)


def author_clips(rig: Rig, obj: bpy.types.Object) -> list[tuple[str, int, bool]]:
    grounded = paw_vertices(obj)
    log(f"ground-contact vertices: {len(grounded)}")
    crouch_z = ground_offset(rig, obj, grounded, crouch_pose())
    land_z = ground_offset(rig, obj, grounded, land_pose())
    # Seated: rump and front paws both rest on the ground, so snap on every vertex.
    sit_z = ground_offset(rig, obj, np.arange(len(obj.data.vertices)), sit_pose())
    log(f"ground snap root z: crouch {crouch_z:+.3f} land {land_z:+.3f} sit {sit_z:+.3f}")
    clips = [
        make_cycle("idle", 90, idle_pose),
        make_cycle("walk", 36, walk_pose),
        make_cycle("run", 24, run_pose),
        make_cycle("gallop", 18, gallop_pose),
        keyed_clip(
            "pounce",
            [
                (0, REST, 0.0),
                (10, crouch_pose(), crouch_z),
                (16, blend(crouch_pose(), crouch_pose(1.1), 0.5), crouch_z),
                (20, crouch_pose(1.1), crouch_z - 0.01),
                (25, launch_pose(), 0.06),
                (31, apex_pose(), 0.30),
                (38, descend_pose(), 0.14),
                (43, land_pose(), land_z),
                (54, REST, 0.0),
            ],
        ),
        keyed_clip(
            "hit",
            [(0, REST, 0.0), (3, hit_pose(1.0), -0.02), (8, hit_pose(0.6), -0.01), (16, REST, 0.0)],
        ),
        make_cycle("flee", 24, flee_pose),
    ]
    sit_rest = sit_pose()

    # `sit` is a seated wait loop (starts and ends seated, so the wrap never pops upright);
    # `sit_down` is the one-shot stand -> seated transition that holds its final pose.
    def sit_wait(t: float) -> tuple[dict, dict]:
        pose = dict(sit_rest)
        breath = math.sin(2 * math.pi * t)
        add(pose, "spine_03", rx=-1.2 * breath)
        add(pose, "neck_01", rx=0.8 * breath, rz=3.0 * breath)
        add(pose, "head", rz=5.0 * math.sin(2 * math.pi * t - 0.4))
        tail_wave(pose, t, 4.0)
        return pose, {"root": (0, 0, sit_z)}

    clips.append(make_cycle("sit", 60, sit_wait))
    clips.append(keyed_clip("sit_down", [(0, REST, 0.0), (22, sit_rest, sit_z)]))
    arm = rig.arm
    arm.animation_data_create()
    summary = []
    for name, frames, data in clips:
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        arm.animation_data.action = action
        every = {pb.name for pb in arm.pose.bones}  # key all bones: no stale pose between clips
        for index, (pose, loc) in enumerate(data):
            rig.apply(pose, loc)
            rig.key(index, every)
        summary.append((name, len(data), name in LOOPING))
    arm.animation_data.action = None
    rig.apply({})
    return summary


# --------------------------------------------------------------------------- validation


def deformation_report(rig: Rig, obj: bpy.types.Object, clips: list) -> list[dict]:
    """Per clip: lowest/highest vertex and worst edge stretch vs rest (exploding-vertex check)."""
    mesh = obj.data
    edges = np.empty(len(mesh.edges) * 2, dtype=np.int64)
    mesh.edges.foreach_get("vertices", edges)
    edges = edges.reshape(-1, 2)
    rest = coords(mesh)
    rest_len = np.linalg.norm(rest[edges[:, 0]] - rest[edges[:, 1]], axis=1) + 1e-9
    arm = rig.arm
    report = []
    for name, count, _ in clips:
        action = bpy.data.actions[name]
        arm.animation_data.action = action
        worst, p999, zmin, zmax, drift, grow, long_edges = 0.0, 0.0, 9.0, -9.0, 0.0, 0.0, 0
        for frame in range(0, count, max(1, count // 12)):
            bpy.context.scene.frame_set(frame)
            deps = bpy.context.evaluated_depsgraph_get()
            ev = obj.evaluated_get(deps)
            posed_mesh = ev.to_mesh()
            posed = coords(posed_mesh)
            ev.to_mesh_clear()
            length = np.linalg.norm(posed[edges[:, 0]] - posed[edges[:, 1]], axis=1)
            ratio = length / rest_len
            worst = max(worst, float(ratio.max()))
            p999 = max(p999, float(np.percentile(ratio, 99.9)))
            grow = max(grow, float((length - rest_len).max()))
            long_edges = max(long_edges, int(((length - rest_len) > 0.04).sum()))
            zmin, zmax = min(zmin, float(posed[:, 2].min())), max(zmax, float(posed[:, 2].max()))
            drift = max(drift, float(np.abs(posed - rest).max()))
        report.append(
            {"clip": name, "frames": count, "max_edge_growth_m": round(grow, 3),
             "edges_grown_over_4cm": long_edges, "max_edge_ratio": round(worst, 1),
             "p99.9_ratio": round(p999, 2), "z_range": [round(zmin, 3), round(zmax, 3)],
             "max_vertex_travel_m": round(drift, 3)}
        )
    arm.animation_data.action = None
    arm.pose.bones[0].location = Vector((0, 0, 0))
    return report


# --------------------------------------------------------------------------- export


def export(obj: bpy.types.Object, arm: bpy.types.Object, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(out),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_skins=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_optimize_animation_size=False,
        export_anim_single_armature=True,
        export_all_influences=False,
        export_image_format="AUTO",
        export_materials="EXPORT",
    )


def main() -> None:
    args = parse_args()
    obj = import_cat(args.src)
    weld(obj)
    nm = normalise(obj, args.shoulder_height)
    arm, lm = build_armature(obj, nm)
    if args.ascii:
        ascii_overlay(coords(obj.data), lm["bones"])
    stats = bind_weights(obj, arm)
    if args.ascii:
        weight_report(obj, arm)
    bpy.context.view_layer.objects.active = arm
    rig = Rig(arm)
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    log(f"head centre {np.round(lm['head_c'],2)} nose {np.round(lm['nose'],2)} tail tip {np.round(lm['tail_tip'],2)}")
    log(f"mesh: {len(obj.data.vertices)} verts, {tris} tris (budget {MAX_TRIS})")
    if tris > MAX_TRIS:
        raise SystemExit(f"{tris} triangles exceed the {MAX_TRIS} hero budget")
    clip_list: list = []
    if not args.no_clips:
        bpy.ops.object.mode_set(mode="POSE")
        clip_list = author_clips(rig, obj)
        bpy.ops.object.mode_set(mode="OBJECT")
        for row in deformation_report(rig, obj, clip_list):
            log("deformation " + json.dumps(row))
    out = Path(args.out)
    export(obj, arm, out)
    document = {
        "rim_light": True,
        "clips": [
            {"name": name, "meshy_clip": name, "loop": loop, "frames": frames, "fps": FPS}
            for name, frames, loop in clip_list
        ],
        "bones": sorted(b.name for b in arm.data.bones),
        "saddle": {"bone": "saddle", "height_m": round(lm["saddle_z"], 3)},
    }
    (out.parent / "import.json").write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=args.blend)
    log(f"wrote {out} ({out.stat().st_size // 1024} KiB), {len(clip_list)} clips, {stats}")


if __name__ == "__main__":
    main()
