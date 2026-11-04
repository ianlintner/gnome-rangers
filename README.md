# Gnome Rangers

A third-person fantasy action RPG built in [Godot](https://godotengine.org/). You are a tiny gnome
ranger riding an armoured black cat. At your scale, the low-level mobs of an ordinary fantasy RPG
(orcs, goblins, giant rats, wolves, spiders) are the bosses.

![Concept art: gnome rangers on black cats harrying an orc brute](docs/concept/gnome-rangers-concept.png)

Combat follows familiar third-person action-RPG mechanics (Elden Ring, Dark Souls, Skyrim):
lock-on, stamina, dodge rolls with i-frames, light and heavy attacks, bow aiming, telegraphed
boss attacks and checkpoint respawns. The twist is that you can whistle up your cat, fight
mounted with a bow, and pounce.

## Status

**Pre-alpha: project scaffold only.** There is no playable game yet. What exists: the Godot
project, CI, test and lint tooling, the shared event bus / state machine plumbing, the art
palette and UI theme, and a look-dev sandbox scene (`levels/sandbox`). The MVP vertical slice is one boss
fight (Grukk the Ironjaw, an orc brute about four times your height) in a single forest arena.
[`PLAN.md`](PLAN.md) has the full plan, art direction and work breakdown, and
[`ARCHITECTURE.md`](ARCHITECTURE.md) has the code conventions.

## Stack

- Godot **4.7.2-stable** (standard build), typed GDScript, Forward+ renderer, Jolt physics
- GUT for unit and integration tests; gdtoolkit (`gdlint`, `gdformat`) for lint and formatting
- 3D assets generated with [Meshy](https://www.meshy.ai/), with Blender (headless) for cleanup and
  quadruped rigging, plus CC0 assets from Quaternius, Kenney, Poly Haven and ambientCG

## Develop

```sh
tools/get_godot.sh                                   # install pinned Godot to ~/.local/bin/godot
pip install -r requirements-dev.txt                  # gdlint + gdformat (gdtoolkit 4.x)

godot --headless --import --path .                   # import assets (first run / after asset changes)
godot --path .                                       # run the project (opens the sandbox)
godot --headless --quit --path .                     # parse check

godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit   # tests (GUT)
gdlint . && gdformat --check .                       # lint and format check (addons/ excluded)
gdformat .                                           # apply formatting

tools/capture/capture.sh levels/sandbox/sandbox.tscn /tmp/sandbox.png [--camera <NodePath>] [--frames N]
```

**Captures** need a real Vulkan device, so they cannot use `--headless`. `capture.sh` uses
`xvfb-run` when installed (this is what CI does, with Mesa lavapipe: `apt install xvfb
mesa-vulkan-drivers`). Without Xvfb it falls back to the live Wayland/X session
(`WAYLAND_DISPLAY`/`DISPLAY`), which is the path on a desktop dev box. `CAPTURE_SIZE=WxH`
changes the resolution (default 1280x720).

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`ARCHITECTURE.md`](ARCHITECTURE.md) before
changing code.

## License

- Code: [MIT](LICENSE)
- Generated art, audio and concept art: [CC-BY-4.0](assets/LICENSE-ASSETS.md)
- Third-party CC0 assets are listed in `assets/CREDITS.md` as they are added.
