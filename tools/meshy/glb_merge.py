#!/usr/bin/env python3
"""Small stdlib GLB helpers for the Meshy pipeline.

``info``   print bounds, triangle count, nodes and animation clips of a GLB.
``merge``  copy the animation clips of several GLBs that share one rig into the first GLB.

Meshy's Animation API accepts at most 10 actions per request, so characters with more clips
need several requests; this stitches the resulting clips into one file. Bones are matched by
node name, which is identical across tasks that animate the same rig task.

    python3 tools/meshy/glb_merge.py info model.glb
    python3 tools/meshy/glb_merge.py merge out.glb base.glb extra1.glb [extra2.glb ...]
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path
from typing import Any

MAGIC = 0x46546C67  # "glTF"
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


def read_glb(path: Path) -> tuple[dict[str, Any], bytearray]:
    raw = path.read_bytes()
    magic, _version, _length = struct.unpack_from("<III", raw, 0)
    if magic != MAGIC:
        raise ValueError(f"{path}: not a GLB")
    offset = 12
    doc: dict[str, Any] = {}
    binary = bytearray()
    while offset < len(raw):
        size, kind = struct.unpack_from("<II", raw, offset)
        chunk = raw[offset + 8 : offset + 8 + size]
        if kind == CHUNK_JSON:
            doc = json.loads(chunk)
        elif kind == CHUNK_BIN:
            binary = bytearray(chunk)
        offset += 8 + size
    return doc, binary


def write_glb(path: Path, doc: dict[str, Any], binary: bytearray) -> None:
    while len(binary) % 4:
        binary.append(0)
    doc.setdefault("buffers", [{}])[0]["byteLength"] = len(binary)
    body = json.dumps(doc, separators=(",", ":")).encode()
    body += b" " * (-len(body) % 4)
    total = 12 + 8 + len(body) + 8 + len(binary)
    out = struct.pack("<III", MAGIC, 2, total)
    out += struct.pack("<II", len(body), CHUNK_JSON) + body
    out += struct.pack("<II", len(binary), CHUNK_BIN) + bytes(binary)
    path.write_bytes(out)


def merge_animations(base: Path, extras: list[Path], out: Path) -> None:
    doc, binary = read_glb(base)
    names = {node.get("name"): i for i, node in enumerate(doc["nodes"])}
    doc.setdefault("animations", [])
    for extra in extras:
        other, other_bin = read_glb(extra)
        accessor_map: dict[int, int] = {}
        view_map: dict[int, int] = {}

        def copy_accessor(index: int) -> int:
            if index in accessor_map:
                return accessor_map[index]
            acc = dict(other["accessors"][index])
            view = other["bufferViews"][acc["bufferView"]]
            if acc["bufferView"] not in view_map:
                while len(binary) % 4:
                    binary.append(0)
                start = view.get("byteOffset", 0)
                chunk = other_bin[start : start + view["byteLength"]]
                new_view = {"buffer": 0, "byteOffset": len(binary), "byteLength": len(chunk)}
                binary.extend(chunk)
                doc["bufferViews"].append(new_view)
                view_map[acc["bufferView"]] = len(doc["bufferViews"]) - 1
            acc["bufferView"] = view_map[acc["bufferView"]]
            doc["accessors"].append(acc)
            accessor_map[index] = len(doc["accessors"]) - 1
            return accessor_map[index]

        for anim in other.get("animations", []):
            samplers = [
                {
                    **s,
                    "input": copy_accessor(s["input"]),
                    "output": copy_accessor(s["output"]),
                }
                for s in anim["samplers"]
            ]
            channels = []
            for ch in anim["channels"]:
                node_name = other["nodes"][ch["target"]["node"]].get("name")
                if node_name not in names:
                    raise ValueError(f"{extra}: bone '{node_name}' missing from {base}")
                channels.append(
                    {
                        "sampler": ch["sampler"],
                        "target": {"node": names[node_name], "path": ch["target"]["path"]},
                    }
                )
            doc["animations"].append(
                {"name": anim.get("name", "clip"), "samplers": samplers, "channels": channels}
            )
    write_glb(out, doc, binary)


def info(path: Path) -> None:
    doc, binary = read_glb(path)
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    tris = 0
    for mesh in doc.get("meshes", []):
        for prim in mesh["primitives"]:
            pos = doc["accessors"][prim["attributes"]["POSITION"]]
            lo = [min(a, b) for a, b in zip(lo, pos.get("min", lo))]
            hi = [max(a, b) for a, b in zip(hi, pos.get("max", hi))]
            idx = prim.get("indices")
            count = doc["accessors"][idx]["count"] if idx is not None else pos["count"]
            tris += count // 3
    print(f"{path.name}: {tris} tris, {len(doc.get('nodes', []))} nodes, "
          f"{len(doc.get('skins', []))} skins, {len(binary) // 1024} KiB bin")
    print("  bounds min", [round(v, 3) for v in lo], "max", [round(v, 3) for v in hi])
    print("  size   ", [round(h - l, 3) for h, l in zip(hi, lo)])
    for anim in doc.get("animations", []):
        print(f"  clip: {anim.get('name')}")
    for image in doc.get("images", []):
        view = doc["bufferViews"][image["bufferView"]] if "bufferView" in image else None
        print(f"  image {image.get('name')} {image.get('mimeType')} {view['byteLength'] // 1024 if view else '?'} KiB")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("info")
    p.add_argument("glb", type=Path)
    p = sub.add_parser("merge")
    p.add_argument("out", type=Path)
    p.add_argument("base", type=Path)
    p.add_argument("extras", type=Path, nargs="+")
    args = parser.parse_args()
    if args.cmd == "info":
        info(args.glb)
    else:
        merge_animations(args.base, args.extras, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
