# Gnome Rangers — PLAN

Working title: **Gnome Rangers**. Third-person fantasy action RPG in Godot. You play a tiny
gnome ranger who rides an armoured black cat. At gnome scale, the low-level mobs of an ordinary
fantasy RPG (orcs, goblins, giant rats, wolves, spiders) are the bosses. Combat follows standard
third-person action-RPG patterns (Elden Ring / Dark Souls / Skyrim): lock-on, stamina, dodge
i-frames, light and heavy attacks, bow aiming, telegraphed boss moves, checkpoint respawn.

Concept art: `docs/concept/gnome-rangers-concept.png` shows three gnome rangers on armoured black
cats harrying a hulking, arrow-studded orc brute in a sunbeam-lit old-growth forest.

## Summary

- **Problem/goal:** a playable vertical slice that proves the fantasy: "tiny cavalry versus a giant
  mob", with tight, familiar Souls-like combat.
- **Target player:** fans of third-person action RPGs; keyboard/mouse and gamepad on desktop.
- **Core loop (MVP):** spawn at the Mushroom Ring checkpoint → explore a short forest approach →
  call your cat, ride, and dismount → enter the boss arena → fight Grukk the Orc Brute (on foot or
  mounted, bow and blade) → die and retry from the checkpoint, or win and see the victory screen.
- **Success signal:** a full boss fight runs start to finish on desktop at 60 fps on the dev box.
  An automated headless "bot fight" test proves the loop: damage, phases, death, respawn, victory.

## Assumptions (decided by default)

- **Engine:** Godot **4.7.2-stable**, pinned in `tools/godot-version.txt`. Move to 4.8 once it
  ships stable (see Later). Standard build, **GDScript only** (typed), no C#/.NET, so
  agents can parse-check and test it headlessly.
- **Renderer:** Forward+ (needed for volumetric fog, SDFGI/SSIL and the target look).
  **Physics:** Jolt, the 4.4+ built-in.
- **Platform:** desktop Linux, Windows and macOS. Input supports KB/M and gamepad from day one.
  Single-player only.
- **Scale:** 1 unit = 1 m at **gnome scale**. Gnome ≈ 1.0 m, cat ≈ 0.9 m at the shoulder,
  Orc Brute ≈ 4.0 m. The scale gap is the hook: bosses are 3–6× the player.
- **Licence:** MIT for code (`LICENSE`); CC-BY-4.0 for generated art, audio and concept art
  (`assets/LICENSE-ASSETS.md`, with a Meshy attribution note).
- **Secrets:** the Meshy API key stays in `~/meshy.txt` on the host. Tools read
  `MESHY_API_KEY` from env (`export MESHY_API_KEY=$(tr -d '[:space:]' < ~/meshy.txt)`), and the key
  is never committed or printed. The balance was ~2,930 credits at planning time.
- **Meshy budget:** ≤ 2,000 credits for the MVP total (per-card caps below). Every generation is
  logged in `assets/meshy-ledger.jsonl` (task id, prompt, model, credits, output path).
- **Heavy 3D tooling:** Blender runs headless (`blender -b -P script.py`), installed on the dev
  box from the official tarball under `~/.local/opt/blender`. The Mac Mini
  (`ianlintner@192.168.50.194`, 64 GB) is the fallback for heavy bakes via `brew install --cask blender`.
- **Third-party assets:** CC0 only (Quaternius, Kenney, Poly Haven, ambientCG), recorded in
  `assets/CREDITS.md`. **No Mixamo**: its licence forbids redistribution in a public repo.
- **PR flow:** every card ships one PR through the IkitClaw App → CI green → Copilot review/fix →
  Ian approves → guarded squash merge.

## Architecture: standard Godot patterns, chosen for clean agentic development

All patterns are mainstream Godot 4 idioms. Workers must extend them, not invent parallels.
`ARCHITECTURE.md` is the binding version of this section.

| Concern | Pattern |
|---|---|
| Entities | **Scene-per-entity** (`player.tscn`, `cat_mount.tscn`, `orc_brute.tscn`) built by **composition of component nodes**, not deep inheritance |
| Components | `HealthComponent`, `StaminaComponent`, `PoiseComponent`, `HitboxComponent` (Area3D, deals damage), `HurtboxComponent` (Area3D, receives damage), `LockOnTarget`, `Interactable`; each one `class_name`, one file, typed signals |
| Behaviour | **Node-based finite state machine** (`StateMachine` + `State` nodes with `enter/exit/update/physics_update/handle_input`). Used by the player, the mount and boss AI. One state per file. |
| Data | **Custom `Resource`s** (`.tres`): `AttackData` (damage, poise damage, stamina cost, windup/active/recovery frames, hitbox shape, anim name), `BossPhaseData`, `CharacterStats`, `MountStats`. Gameplay tuning lives in data, not code. |
| Decoupling | **Autoload `EventBus`** with typed signals for cross-system events (`player_died`, `boss_engaged`, `boss_defeated`, `checkpoint_rested`). Parent→child uses direct calls; child→parent uses signals ("call down, signal up"). |
| Animation | `AnimationTree` with state machine + `BlendSpace2D` locomotion. **Animation-driven hit windows**: method/call tracks enable and disable hitboxes. Humanoids share Godot's `SkeletonProfileHumanoid` retargeting so CC0/Meshy clips are interchangeable. |
| Camera | `SpringArm3D` third-person orbit camera; lock-on mode frames player + target; collision-aware |
| Movement | `CharacterBody3D` with camera-relative input, acceleration/friction curves, root-motion-free for MVP |
| Input | Named actions in the InputMap only (`attack_light`, `attack_heavy`, `dodge`, `lock_on`, `aim`, `fire`, `call_mount`, `interact`, `sprint`, `pause`); no raw keycodes in gameplay code |
| UI | `Control` scenes themed by one `ui/theme/game_theme.tres`; HUD subscribes to components through signals and never polls |
| Persistence | None in MVP beyond settings (`ConfigFile` at `user://settings.cfg`) |
| Tests | **GUT** (latest release compatible with 4.7) under `tests/unit` and `tests/integration`; headless bot-fight integration test |
| Lint/format | `gdtoolkit` (`gdlint`, `gdformat --check`) pinned in `requirements-dev.txt` |
| Assets | `tools/meshy/` Python CLI driven by `assets/manifest.yaml` → GLB in `assets/<category>/<name>/`; import settings via `.import` sidecars committed; `tools/blender/` headless scripts for cleanup, rigging and LOD |

### Directory layout (target)

```
project.godot
addons/gut/                     # vendored test framework
autoload/event_bus.gd, game_state.gd
core/components/                # health, stamina, poise, hitbox, hurtbox, lock_on_target
core/state_machine/             # state_machine.gd, state.gd
core/data/                      # AttackData, BossPhaseData, CharacterStats, MountStats (Resource scripts)
actors/player/                  # player.tscn + states/
actors/mount/                   # cat_mount.tscn + states/
actors/bosses/orc_brute/        # orc_brute.tscn + states/ + attacks/*.tres + phases/*.tres
actors/projectiles/arrow.tscn
camera/third_person_camera.tscn
levels/rootfall_hollow/         # MVP arena level
ui/theme/, ui/hud/, ui/menus/
fx/                             # shaders (rim light, foliage wind), particles, environment .tres
assets/<category>/<name>/       # imported GLBs, textures; manifest.yaml; meshy-ledger.jsonl
tools/meshy/, tools/blender/, tools/capture/, tools/godot-version.txt, tools/get_godot.sh
tests/unit/, tests/integration/
docs/concept/, docs/art-direction.md
```

Rules: ≤ ~400 LOC per script; one `class_name` per file; typed GDScript everywhere
(`untyped_declaration` warnings promoted to errors); no magic numbers in gameplay (tune them in `.tres`);
no gameplay singletons besides `EventBus` and `GameState`.

## Combat design (MVP)

Standard action-RPG mechanics:

- **Stamina:** attacks, dodges, sprinting and drawing the bow cost stamina. Regen pauses briefly
  after use. At zero, actions are refused and the player is briefly winded.
- **Dodge roll:** i-frames (data-driven, about 0.2–0.4 s window), recovery, directional with
  camera-relative input. Backstep when there is no input.
- **Lock-on:** toggle to the nearest target in a view cone, flick to switch, auto-break on distance or
  line-of-sight loss. Strafing locomotion while locked.
- **Melee (on foot, gnome short sword):** light chain (3 hits), heavy (chargeable), both with
  animation-driven hit windows, poise damage and hit-stop (~60 ms).
- **Bow (on foot and mounted):** hold `aim` for an over-the-shoulder camera and a reticle. Draw time
  scales damage. Release fires a physics arrow that **sticks into the target** (as in the concept
  art) and despawns after N seconds. Headshot/weak-point multiplier comes from a `HurtboxComponent`
  flag.
- **Poise/stagger:** accumulating poise damage staggers the enemy, opening a riposte window
  (bonus damage) on the boss.
- **Health and death:** death → "YOU WERE SQUASHED" screen → respawn at the last Mushroom Ring
  checkpoint with full HP; the boss resets.
- **Cat mount:** `call_mount` whistles the cat to run to you; `interact` mounts and dismounts.
  Mounted: faster locomotion, sprint (stamina), mounted bow (no melee), and **Pounce** (a charge
  that leaps onto the target, dealing heavy poise damage, on a cooldown). Being hit hard while
  mounted can knock you off. The cat has its own HP; at zero it flees and returns after a cooldown.

### Boss: Grukk the Ironjaw (Orc Brute), about 4 m tall

- **Moves** (each an `AttackData` with clear windup telegraphs): overhead mace slam (with a ground
  shock ring), horizontal sweep (jump/roll through), stomp (AoE around the feet, which punishes
  standing under him), grab-and-throw attempt (dodgeable), roar (stagger + phase transition).
- **Phase 2 at 50 % HP:** enraged. Faster recoveries, adds a 3-hit combo and a leaping slam.
- **Weak point:** the head takes ×2 arrow damage; the back takes bonus damage while he is staggered.
- **AI:** FSM with weighted move selection by distance band (close/mid/far) and cooldowns. He turns
  toward the player at a limited rate, so circling and flanking work as they do in Souls games.
- **Arena:** fog-gate entry trigger → boss bar appears → the arena seals until the fight ends.

## Art direction & UI design system (shared; Card 1 builds the tokens)

Target: **grounded, gritty PBR realism with fairy-tale scale**. The whimsical premise is treated
with total visual seriousness: weathered leather, oxidized iron, real fur, moss and bark.
Lighting does the storytelling; the palette stays earthy and desaturated.

### Palette tokens (`ui/theme/palette.gd` → `class_name Palette`, plus `docs/art-direction.md`)

| Token | Hex | Use |
|---|---|---|
| `forest_shadow` | `#141911` | deep shadow, UI panel base |
| `moss_bright` | `#4A6423` | moss, foreground foliage, positive UI accent |
| `fern_mid` | `#384D26` | mid foliage |
| `bark` | `#3A2E21` | trunks, roots, UI frame |
| `leaf_litter` | `#5C4328` | ground, dirt |
| `canopy_haze` | `#C8CEB8` | fog/sunbeam tint, UI body text |
| `rim_light` | `#E2E6D5` | rim/specular, UI highlight text |
| `cloak_olive` | `#43532A` | ranger cloaks |
| `leather` | `#5A3D28` / `leather_dark` `#332115` | tack, barding, armour, UI borders |
| `cat_fur` | `#181A1B` / `cat_sheen` `#3B4044` | cat mounts |
| `orc_skin` | `#5B6643` | orc |
| `iron` | `#4A4742` / `iron_edge` `#78736A` | chainmail, weapons |
| `blanket_red` | `#8C2F1E` | saddle-blanket accent, **health bar** |
| `blanket_ochre` | `#C08A2E` | saddle-blanket accent, **stamina bar**, boss name |

### Lighting and post (`fx/environment/forest_day.tres`, shared by every level)

- One warm directional sun at a steep angle through the canopy, with shadows on (PCSS soft).
- **Volumetric fog** tinted `canopy_haze`, which produces god rays through gaps in the canopy.
- SDFGI (fallback: VoxelGI baked per level), SSAO and SSIL on; glow subtle; **AgX** tonemap.
- Depth-of-field off in gameplay; subtle DOF only in the title/victory camera.
- **Rim-light readability rule:** dark actors (black cats, orc) use the shared
  `fx/shaders/rim_light.gdshader` next-pass (rim colour `rim_light`, strength 0.35) so they read
  against dark forest. Every actor material must stay readable at 20 m in the target lighting.

### Model specs

- Meshy text/image-to-3D (current default model, `meshy-7.x` or newer; `meshy-5` is retired) with
  realistic PBR textures.
- Triangle budgets: hero characters ≤ 30k tris, boss ≤ 40k, props ≤ 8k, foliage ≤ 3k (with LOD).
- Textures ≤ 2048² for heroes, ≤ 1024² for props. GLB output; glTF +Z faces forward (Meshy rigging
  requires it). Pivot at the feet, centred, real-world scale per the Scale assumption.
- Humanoids (gnome, orc): Meshy Rigging API → Meshy Animation API (`action_ids`, ≤ 10 clips per
  request, merged into one GLB with named clips). They are retargetable through `SkeletonProfileHumanoid`.
- Cat (quadruped; Meshy cannot rig it): Meshy mesh, then Blender headless auto-rig/weight, then CC0
  or authored clips (idle, walk, run, gallop, pounce, hit, flee).

### UI chrome (Souls-style minimal)

- Top-left: health (`blanket_red`), stamina (`blanket_ochre`), mount health (small, `cat_sheen`)
  as thin bars with a `leather` 2 px border on a `forest_shadow` @ 70 % backing.
- Bottom-centre: a wide boss bar (`blanket_red` fill, delayed-damage ghost in `canopy_haze`), with
  the boss name above in a small-caps serif.
- Centre: a small lock-on marker (diamond, `rim_light`) and a bow reticle that tightens with draw.
- Typography (OFL, vendored under `ui/fonts/`): **Cinzel** for titles/boss names and **Alegreya Sans**
  for body/HUD numbers.
- Menus: dark `forest_shadow` panels, `bark` frames, `rim_light` focus highlight; full gamepad
  focus navigation.

## MVP scope

Must-haves:
1. Third-person player controller: movement, sprint, dodge, lock-on, on-foot melee and bow.
2. Cat mount: call, ride, dismount, mounted bow, pounce.
3. One complete boss: Grukk the Orc Brute, two phases.
4. One playable level: Rootfall Hollow (approach + arena + checkpoint) in the target art direction.
5. HUD + game flow: title → play → pause/settings → death/respawn → victory.
6. Asset pipeline producing the gnome ranger, black cat (with barding) and orc brute plus core
   forest props, reproducibly from a manifest.

Non-goals (MVP): open world, inventory/loot/levelling, NPCs/dialogue, saves beyond settings,
multiplayer, multiple bosses, audio beyond placeholder SFX and one ambient track, console
exports, mobile.

## Milestones

- **M0 Foundation:** Card 1 (scaffold, tokens, CI, capture harness).
- **M1 Feel:** Cards 2–5 (assets in parallel with controller and combat core).
- **M2 Content:** Cards 6–9 (mount, boss, level, HUD/flow).
- **M3 Slice:** Card 10 (integration, bot fight, consolidation, README), then the Later backlog.

## Cards

All cards: assignee `coder-claude`; skills `kanban-pr-review-cycle` + `ikitclaw-github-app`; completion
contract `local-only` (new repo, no branch protection; the PR gate is enforced by the review cycle).
"Complex" cards use route `smart-frontier-v2` via `switchyard-anthropic`; routine cards inherit
the profile default `smart-v2`.

| # | Title | Depends on | Route | Acceptance (verifiable) |
|---|---|---|---|---|
| 1 | Scaffold: Godot 4.7.2 project, GUT, gdlint, CI, theme/palette tokens, environment preset, capture harness, README | — | routine | `tools/get_godot.sh` installs the pinned 4.7.2; `godot --headless --import` and `--quit` are clean; GUT sample suite passes headless; `gdlint`/`gdformat --check` pass; CI workflow runs the same; `tools/capture/capture.sh <scene> <out.png>` renders a PNG of `levels/sandbox` under Xvfb |
| 2 | Asset pipeline (Meshy CLI + manifest + ledger) and humanoid heroes: gnome ranger + Grukk orc brute, rigged and animated | 1 | routine | `python tools/meshy/meshy.py plan` dry-run lists tasks and credit estimate; generated GLBs import with no errors; each has the named clips (idle, walk, run, attack×3, hit, death, plus orc slam/sweep/stomp/roar); ledger records spend ≤ 900 credits; captures of both in the sandbox |
| 3 | Black cat mount asset: Meshy mesh + barding, Blender headless quadruped rig and core clips | 2 | complex | `blender -b -P tools/blender/rig_cat.py` reproduces the rig; GLB imports with clips idle/walk/run/gallop/pounce/hit/flee; spend ≤ 300 credits; capture shows the cat with a rider socket bone |
| 4 | Player controller: third-person camera, locomotion, sprint, dodge i-frames, lock-on, state machine, stamina | 1 | complex | GUT unit tests for the state machine, stamina and i-frame window; integration test drives inputs headless (move, dodge through a hitbox, take no damage); lock-on selects nearest in cone |
| 5 | Combat core: components (health/poise/hit/hurtbox), AttackData resources, light/heavy melee, bow aim + sticking arrows, hit-stop, stagger | 4 | complex | Unit tests for damage, poise and weak-point multiplier; integration test: player kills a training dummy with melee and with arrows; arrows persist attached to the target; all tuning lives in `.tres` |
| 6 | Cat mount gameplay: call/mount/dismount, mounted locomotion, mounted bow, pounce, knock-off, mount HP/flee | 3, 5 | complex | Integration tests: call → cat paths to player; mount/dismount state transitions; mounted bow damages dummy; pounce applies poise damage on cooldown; heavy hit dismounts |
| 7 | Boss framework + Grukk the Orc Brute: FSM AI, telegraphed attacks, phases, weak point, fog-gate arena | 2, 5 | complex | Unit tests for move selection by distance band and cooldowns; integration test: boss transitions to phase 2 at 50 %, staggers on poise break, and kills an idle player; boss data lives entirely in `.tres` |
| 8 | Level: Rootfall Hollow (approach + arena + Mushroom Ring checkpoint) in the target art direction, with forest props | 2 | routine | Level loads headless; nav mesh baked; checkpoint rest sets respawn; captures from 3 fixed cameras (approach, arena wide, ground-level hero shot) attached to the PR; prop spend ≤ 600 credits; 60 fps on the dev box at 1080p (log from the perf capture script) |
| 9 | HUD + game flow: health/stamina/mount bars, boss bar, lock-on/reticle, title, pause/settings, death/respawn, victory | 5 | routine | GUT tests: HUD bars track component signals; death → respawn at checkpoint resets the boss; settings persist to `user://settings.cfg`; menus fully gamepad navigable (focus test) |
| 10 | MVP integration check, architecture consolidation & README usage | 6, 7, 8, 9 | complex | Headless bot-fight integration test (scripted player beats Grukk mounted and on foot; scripted idle player dies and respawns) passes in CI; `ARCHITECTURE.md` updated to the real code; no file > 400 LOC; README has controls, build/run/test, asset pipeline, credits; captures + short gameplay notes in the PR |

Wave plan: Card 1 → then 2 and 4 in parallel → 3, 5 → 6, 7, 8, 9 (release in small waves to
avoid stale-base conflicts) → 10.

Visual cards (2, 3, 8, 10) must attach real rendered captures from `tools/capture/` to their PRs.
Green tests do not prove the look.

## Later (not on the board until the MVP consolidation lands)

- Godot 4.8 stable upgrade.
- More "low-level mobs as bosses": Giant Rat Matriarch (sewer), Goblin Shaman + totem adds, Hunting
  Spider (web traps, vertical arena), Dire Wolf (mount-vs-mount chase), Skeleton Knight.
- Ranger squad: AI rider companions as in the concept art, with simple commands (focus target, flank).
- Mount progression: barding sets, cat breeds/traits, saddle-blanket customization.
- RPG layer: levelling, gear, loot, Skyrim-style perks; open forest hub with bosses as world events.
- Audio pass, VFX polish, controller rumble, accessibility options, Steam Deck/export presets, itch.io release CI.
