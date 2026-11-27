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

CI (`.github/workflows/ci.yml`) runs the same set. Visual changes also attach
captures produced by `tools/capture/`.

## Assets and secrets

- Meshy API key: read from the environment variable `MESHY_API_KEY`. It is never committed,
  logged or printed. Every generation appends to `assets/meshy-ledger.jsonl`.
- Only CC0 third-party assets, credited in `assets/CREDITS.md`. No Mixamo.
- glTF/GLB faces +Z forward with its pivot at the feet. Scale is 1 unit = 1 m at gnome scale
  (gnome about 1.0 m, cat about 0.9 m at the shoulder, orc brute about 4.0 m).

## Combat conventions (card 5)

- **Data first.** Every combat number lives in a `.tres`: `AttackData` (damage, poise,
  stamina cost, timings, hitbox shape, animation, hit-stop, charge scaling), `CombatStats`
  (health and poise tuning), `BowData` (draw, flight, sticking), `MeleeMoveset` (chain,
  heavy, input buffer). Scripts hold no combat constants.
- **Components.** `HealthComponent`, `PoiseComponent`, `HurtboxComponent` (routes hits,
  `damage_multiplier` for weak points, `invulnerable` for i-frames, `faction` to avoid friendly
  fire) and `HitboxComponent` (one hit per target per swing). Bosses and the mount reuse them
  unchanged; an actor only wires signals (`died`, `poise_broken`, `damaged`).
- **Hit windows.** `AttackRunner` plays one `AttackData`. If the clip has a call-method track
  for `open_hit_window` / `close_hit_window` on the runner, the animation drives the window;
  otherwise the `windup` / `active` / `recovery` timings do. Stamina is paid on `start`.
- **Hit-stop.** One standard approach: `HitStop.request` dips `Engine.time_scale` for a short
  real-time duration (set per attack in `AttackData`). No per-actor freezes.
- **Bow.** `BowComponent` owns draw time and fires pooled `Arrow` scenes (`ArrowPool`). Arrows
  sweep a ray each tick (no tunnelling), hit through the hitbox, then reparent to the hit
  hurtbox's stick anchor and despawn after `stuck_lifetime`; the pool caps stuck arrows.
  Aim state publishes `EventBus.aim_changed` / `bow_draw_changed` for the camera and HUD.
- **EventBus.** `damage_dealt`, `actor_died`, `actor_staggered`, `hit_feedback(DamageInfo)`
  (VFX and SFX hook).

## Module map (what is where today)

- `main.tscn` / `main.gd`: scene-flow controller (title, gameplay, pause, settings, death,
  victory). The level is a separate scene under `LevelHost`.
- `autoload/`: `EventBus` (typed cross-system signals) and `GameState` (checkpoint, run reset).
- `actors/player/`: `Player` (CharacterBody3D), its states, `LockOnSelector`, moveset and stats `.tres`.
- `actors/mount/`: `CatMount`, mount states, pounce attack, `MountStats`.
- `actors/bosses/boss_base/`: reusable boss: `BossBase`, `BossBrain` (weighted move choice),
  `BossPhaseController`, boss states, `BossMoveData`, `BossPhaseData`.
- `actors/bosses/orc_brute/`: Grukk: scene, `grukk.gd` (presentation only), stats, moves, phases.
- `actors/projectiles/`: `Arrow`, `ArrowPool`. `actors/enemies/`: the training dummy.
- `core/components/`, `core/data/`, `core/state_machine/`, `core/combat/`: shared components,
  Resource types, state machine, hit-stop.
- `camera/`: third-person orbit camera with lock-on and aim modes.
- `levels/rootfall_hollow/`: the level, `FogGate` (boss spawn, engage, seal, reset),
  layout and foliage scatter. `levels/checkpoint/`, `levels/sandbox/`.
- `ui/hud/`, `ui/menus/`, `ui/theme/`: HUD (signal-driven), menus, theme and `Palette`.
- `fx/`: shared environment, shaders, materials.
- `tools/`: capture, perf, Meshy, Blender, level building. `tests/`: unit, integration, helpers
  (the `FightBot` and its tactics).

## Adding a new boss

You do not need to read the orc code; `BossBase` does the work and a boss is data plus a scene.

1. **Moves:** create `actors/bosses/<name>/attacks/*.tres` (`AttackData`: damage, poise, windup,
   active, recovery, hitbox shape, animation) and `moves/*.tres` (`BossMoveData`: `min_range`,
   `max_range`, `weight`, `cooldown`, `attack`, optional `followup_attack`).
2. **Stats and phases:** add a `CombatStats` `.tres` (health, poise) and one `BossPhaseData`
   `.tres` per extra phase (health threshold, extra moves, speed and recovery multipliers).
3. **Scene:** duplicate `actors/bosses/orc_brute/grukk.tscn` into `actors/bosses/<name>/<name>.tscn`.
   Swap the model, hurtboxes (set `damage_multiplier` for weak points) and hitbox shapes, then
   assign `stats`, `base_moves`, `phases` and the brain's `moves`. The root script is `BossBase`,
   or a thin subclass for presentation only (`class_name` in its own file).
4. **Animations:** the model's `AnimationPlayer` needs the clips named by your `AttackData`
   plus idle, walk, hit and death. Hit windows come from the data timings or from
   `open_hit_window` / `close_hit_window` call-method tracks.
5. **Arena:** put a `FogGate` (`levels/rootfall_hollow/fog_gate.tscn`) in the level, set its
   `boss_scene`, and the gate spawns, engages, seals, resets on player death and reopens on
   defeat. The HUD boss bar shows the boss node's name, so name the node accordingly.
6. **Tests:** copy `tests/integration/test_grukk.gd` (framework behaviour) and add a
   bot-fight test; extend `FightBot` tactics only if the boss needs new telegraph handling
   (`tests/helpers/bot_threat.gd`).
7. **Gates:** run the commands in "Testing and checks" above and attach captures.

New cross-system events go on `EventBus`, never as direct references from the boss to the HUD.
