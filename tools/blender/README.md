# tools/blender

Headless Blender scripts (Blender 5.3, official Linux tarball in `~/.local/opt/blender/`, no sudo).

| Script | Purpose |
| --- | --- |
| `rig_cat.py` | Rig and animate the Meshy cat mount: quadruped armature (spine, neck, head, jaw, 4 legs with paw bones, 6-bone tail, `saddle` socket), automatic weights, procedural clips `idle walk run gallop pounce hit flee sit`, GLB + `import.json` export. |

```sh
~/.local/opt/blender/blender -b -P tools/blender/rig_cat.py -- \
  --in assets/characters/cat_mount/source/cat_mount_source.glb \
  --out assets/characters/cat_mount/cat_mount.glb
```

Options: `--shoulder-height M` (default 0.9), `--blend FILE` (save a .blend), `--ascii` (print a
side-view bone overlay and per-bone weight report), `--no-clips`. The log ends with a per-clip
deformation report (largest edge growth, edges grown by > 4 cm) and the export summary.

The saddle bone is a non-deforming socket at the top of the back, rest-oriented along the body; in
Godot attach the rider with `BoneAttachment3D` (`bone_name = "saddle"`), see
`levels/sandbox/mount_showcase.gd`.
