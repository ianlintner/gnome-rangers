# Architecture

These rules bind every change in this repository. They use mainstream Godot 4 patterns so that
any contributor, human or agent, can predict where code lives. **Extend the existing shared
modules; do not create parallel plumbing.** If a rule blocks you, change this file in the same
PR and explain why.

## Engine and language

- Godot **4.7.2-stable** (pinned in `tools/godot-version.txt`), standard build. Forward+ renderer,
  Jolt physics.
- **GDScript only**, fully typed (`var hp: int`, typed function signatures, typed signals,
  typed arrays). Project setting `untyped_declaration` is a warning promoted to an error.
- One `class_name` per file. snake_case for files, functions and variables; PascalCase for
  classes and nodes.
- Keep scripts under about 400 lines. Split by responsibility (a new state, a new component)
  rather than adding helpers to a large file.

## Module map (where new X belongs)

| You are adding… | It goes in | Pattern |
|---|---|---|
| A reusable gameplay capability (health, stamina, poise, hitbox, hurtbox, lock-on target, interactable) | `core/components/` | Node component with typed signals; attach as a child of the entity scene |
| State machine plumbing | `core/state_machine/` | `StateMachine` node + `State` base (`enter`, `exit`, `update`, `physics_update`, `handle_input`) |
| A behaviour state for an actor | `actors/<actor>/states/<state_name>_state.gd` | One state per file, extending `State` |
| Tunable numbers (damage, timings, speeds, costs, phase thresholds) | `.tres` files using Resource scripts in `core/data/` | `AttackData`, `BossPhaseData`, `CharacterStats`, `MountStats`; no magic numbers in gameplay scripts |
| A new actor (enemy, boss, mount, NPC) | `actors/<kind>/<name>/` | Scene per entity composed from components plus a state machine |
| Cross-system events | `autoload/event_bus.gd` | Add a typed signal; emit and connect there. "Call down, signal up" inside a scene tree |
| Global run state (checkpoint, respawn) | `autoload/game_state.gd` | Keep it small; no other gameplay singletons |
| Camera behaviour | `camera/` | `SpringArm3D` orbit rig; lock-on and aim are camera modes |
| Projectiles | `actors/projectiles/` | Pooled scenes; hits go through `HitboxComponent` |
| A level | `levels/<level_name>/` | Uses the shared `fx/environment/*.tres` and checkpoint scene |
| UI | `ui/hud/`, `ui/menus/`; theme in `ui/theme/` | Control scenes styled only through `game_theme.tres` and `Palette` tokens; HUD listens to signals and never polls |
| Shaders, particles, environments | `fx/` | Reuse `fx/shaders/rim_light.gdshader` and the shared environment |
| Imported 3D/2D assets | `assets/<category>/<name>/` | Declared in `assets/manifest.yaml`; generated via `tools/meshy/` or `tools/blender/` |
| Dev tooling | `tools/` | Python 3 scripts with `--help`; no secrets in the repo |
| Tests | `tests/unit/`, `tests/integration/` | GUT; one test file per script under test |

## Core patterns

- **Composition over inheritance.** Actors are scenes that assemble components. Shared behaviour
  belongs in a component or a state, not in a deep base-class chain.
- **State machines** drive the player, the mount and the boss AI. Transitions are explicit and
  testable.
- **Data-driven combat.** `AttackData` describes damage, poise damage, stamina cost, windup,
  active and recovery timing, hitbox shape and animation name. Animations enable and disable
  hitboxes with method tracks, so hit windows are authored in data and animation, not
  hard-coded timers.
- **Input** uses named InputMap actions only, never raw keycodes. KB/M and gamepad bindings live
  in `project.godot`.
- **Animation:** `AnimationTree` (state machine with `BlendSpace2D` locomotion). Humanoids share
  `SkeletonProfileHumanoid` retargeting so clips can be swapped between rigs.
- **Physics layers** are named in `project.godot`: `world`, `player`, `enemy`, `mount`,
  `player_hitbox`, `enemy_hitbox`, `hurtbox`, `projectile`, `interact`. Never use bare layer
  numbers in code.

## Testing and checks (required before every PR)

```sh
tools/get_godot.sh                          # installs the pinned Godot if missing
godot --headless --import --path .          # import pass; no errors
godot --headless --quit --path .            # parse check
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
gdlint . && gdformat --check .
```

Card 1 finalizes the exact commands, and CI runs the same set. Visual changes also attach
captures produced by `tools/capture/`.

## Assets and secrets

- Meshy API key: read from the environment variable `MESHY_API_KEY`. It is never committed,
  logged or printed. Every generation appends to `assets/meshy-ledger.jsonl`.
- Only CC0 third-party assets, credited in `assets/CREDITS.md`. No Mixamo.
- glTF/GLB faces +Z forward with its pivot at the feet. Scale is 1 unit = 1 m at gnome scale
  (gnome about 1.0 m, cat about 0.9 m at the shoulder, orc brute about 4.0 m).
