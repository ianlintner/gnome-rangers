# Meshy asset pipeline

`tools/meshy/meshy.py` turns `assets/manifest.yaml` into rigged, animated GLBs using the
[Meshy API](https://docs.meshy.ai). Stdlib + PyYAML, Python 3.10+.

```
text-to-3d preview(s) -> pick one -> refine (PBR texture) -> rig -> animate -> assets/characters/<name>/<name>.glb
```

## Setup

```sh
pip install pyyaml
export MESHY_API_KEY=$(tr -d '[:space:]' < ~/meshy.txt)   # never print, log or commit it
```

## Commands

| Command | Spends? | What it does |
| --- | --- | --- |
| `balance [--record NOTE]` | no | Show credits (optionally log a balance line in the ledger). |
| `plan [names] [--max-credits N]` | no | Task list, state from the ledger, credit estimate. Needs no key. |
| `library [search]` | no | List the free biped animation library (find `action_id`s). |
| `generate <names>` | yes | Previews (`previews:` of them), then refine once `pick:` is set. |
| `rig <name>` | yes | Auto-rig the textured model at `height_meters`. |
| `animate <name>` | yes | Apply `animations:` (batched by 10), write the final GLB + `import.json`. |
| `status <task_id>` | no | Poll one task. |
| `supersede <task_id>` | no | Stop reusing a task so its stage regenerates (spend stays counted). |
| `reconcile <asset> <stage> [variant]` | no | Resolve a paid create whose outcome was unknown. |

`--max-credits` (default `budget.max_credits` in the manifest, 900) is a hard guard: a task is
never created if ledger spend plus its estimate would exceed it. Every created task and its result
is appended to `assets/meshy-ledger.jsonl` immediately, so an interrupted run resumes the recorded
task instead of paying again, and finished stages are skipped.

## Costs (meshy-7.1 + PBR 2K, as used here)

| Stage | Credits |
| --- | --- |
| Preview mesh | 20 each |
| Refine / texture | 10 |
| Rig | 5 |
| Animation | 3 per clip |

Per hero, 2 previews + refine + rig + 10-14 clips is ~95 credits. Card 2 spent 185 in total
(see the ledger and the PR for start/end balances).

## Workflow

1. Edit the asset in `assets/manifest.yaml` (prompt, `ai_model`, `target_polycount`,
   `height_meters`, `animations`). Look up ids with `meshy.py library <keyword>`.
2. `python3 tools/meshy/meshy.py plan` and check the estimate.
3. `generate <name>`; with `pick: null` this only makes previews. Inspect
   `assets/characters/<name>/work/preview_N.png|glb` (gitignored), then set `pick: N`.
4. `generate <name>` (refine), `rig <name>`, `animate <name>`.
5. Import into Godot and set up retargeting:

   ```sh
   godot --headless --import --path .
   godot --headless -s tools/import/configure_humanoid_import.gd --path . -- res://assets/characters/<name>/<name>.glb
   godot --headless --import --path .
   godot --headless -s tools/inspect_asset.gd --path . -- res://assets/characters/<name>/<name>.glb
   ```

   `configure_humanoid_import.gd` writes the Mixamo -> `SkeletonProfileHumanoid` BoneMap and the
   post-import script into the `.import` sidecar (committed). `tools/import/humanoid_post_import.gd`
   then renames clips from `import.json` and sets loops.

## Regenerate one asset

The ledger is append-only history, so never edit it by hand. To redo a stage, supersede its task;
the task is no longer reused, but its credits **stay counted** against `--max-credits` (Meshy
refunds nothing):

```sh
python3 tools/meshy/meshy.py supersede <task_id> --reason "new prompt"
python3 tools/meshy/meshy.py animate gnome_ranger
```

To start an asset over completely (new prompt), change the manifest entry, set `pick: null`,
supersede the old preview/refine/rig/animate tasks the same way, and follow the workflow above.
Because history counts, a full redo may need a higher `--max-credits`; raise it deliberately.

## Safety behaviour

- **Fixed origin.** Requests go only to `https://api.meshy.ai/openapi/...`; status URLs are built
  from the stage and a validated task id (never from ledger text) and redirects are refused, so the
  bearer token cannot be sent elsewhere.
- **No blind retry of paid creates.** A paid POST is retried only after a 429 (rejected). On a
  timeout, network error or 5xx the outcome is unknown, so the CLI stops. The `intent` line it wrote
  before sending keeps the credits reserved and blocks re-creating that stage. Check the Meshy
  dashboard, then either `reconcile <asset> <stage> [variant] --task-id <id>` (adopt the task) or
  `reconcile <asset> <stage> [variant] --none` (nothing was created; releases the credits).
- **Atomic cap.** Budget check and reservation happen under an exclusive lock on the ledger file,
  so concurrent runs cannot both pass the guard.
- **Resume never loses output.** Outputs are downloaded before a task is recorded finished; a
  finished task whose file is missing is re-fetched by id (free GET), and `animate` fails if a batch
  is absent instead of silently doing nothing.
- **Canceled and failed tasks** are never reused; the next run creates a fresh task (a canceled
  task is counted at its estimate, conservatively).

## Conventions and notes

- **Scale**: 1 unit = 1 m at gnome scale; gnome 1.0 m, Grukk 4.0 m (`height_meters`). Meshy rescales
  the rigged GLB to that height, feet at y = 0, facing +Z.
- **Models**: `meshy-5` is retired. `meshy-7.1` is the current standard model.
- **Substitutions**: the library has no horse/cat mount clips, a separate bow draw/release, an orc
  roar or a true overhead slam; nearest clips are recorded with a `note:` per clip in the manifest.
- Meshy GLB skeletons are Mixamo-named (`mixamorig_*`); Godot retargets them to the humanoid profile.
- Tests: `python3 tools/meshy/test_meshy.py` (offline).
