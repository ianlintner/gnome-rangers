# Credits

Licence terms are in [`LICENSE-ASSETS.md`](LICENSE-ASSETS.md) (CC-BY-4.0 unless listed here).

## Generated assets

| Asset | Source | Notes |
| --- | --- | --- |
| `characters/gnome_ranger/` | Meshy (text-to-3d `meshy-7.1`, PBR refine, auto-rig, animation library) | Prompt in `manifest.yaml`. |
| `characters/grukk_orc_brute/` | Meshy (same pipeline) | Prompt in `manifest.yaml`. |
| `props/trunk_giant_a`, `trunk_giant_b`, `root_arch`, `fallen_log`, `fern_cluster`, `mushroom_ring`, `rock_mossy` | Meshy (text-to-3d `meshy-7.1`, PBR refine; static, no rig) | Rootfall Hollow props (card 8). Prompts in `manifest.yaml`. |

Meshy output is used under the terms of the Meshy plan that generated it. Every paid task is
recorded in [`meshy-ledger.jsonl`](meshy-ledger.jsonl); clip substitutions are noted per clip in
[`manifest.yaml`](manifest.yaml).

## Third-party

All CC0 (public domain dedication), downloaded at 1K from [Poly Haven](https://polyhaven.com):

| Asset | Author | Used for |
| --- | --- | --- |
| [`forrest_ground_01`](https://polyhaven.com/a/forrest_ground_01) | Rob Tuytel | Rootfall Hollow terrain (`assets/textures/forrest_ground_01/`) |
| [`leaves_forest_ground`](https://polyhaven.com/a/leaves_forest_ground) | Dario Barresi (processing), Dimitrios Savva (photography) | Leaf-litter decals along the path (`assets/textures/leaves_forest_ground/`) |

## Generated audio

`audio/forest_ambient_loop.wav` is synthesised by `tools/audio/make_ambient_loop.py` (filtered noise,
original work, CC-BY-4.0). It is a placeholder for a CC0 recording.
