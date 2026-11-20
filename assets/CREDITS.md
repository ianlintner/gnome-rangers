# Credits

Licence terms are in [`LICENSE-ASSETS.md`](LICENSE-ASSETS.md) (CC-BY-4.0 unless listed here).

## Generated assets

| Asset | Source | Notes |
| --- | --- | --- |
| `characters/gnome_ranger/` | Meshy (text-to-3d `meshy-7.1`, PBR refine, auto-rig, animation library) | Prompt in `manifest.yaml`. |
| `characters/grukk_orc_brute/` | Meshy (same pipeline) | Prompt in `manifest.yaml`. |
| `characters/cat_mount/` | Meshy (text-to-3d `meshy-7.1`, PBR refine; mesh + barding in one) rigged and animated headlessly in Blender by `tools/blender/rig_cat.py` | Meshy cannot rig quadrupeds. Source mesh in `source/`. No third-party rigged-cat fallback was used. |

Meshy output is used under the terms of the Meshy plan that generated it. Every paid task is
recorded in [`meshy-ledger.jsonl`](meshy-ledger.jsonl); clip substitutions are noted per clip in
[`manifest.yaml`](manifest.yaml).

## Third-party

None yet.
