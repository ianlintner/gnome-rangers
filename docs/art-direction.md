# Art direction

Target: **grounded, gritty PBR realism with fairy-tale scale**. The whimsical premise is treated
with total visual seriousness: weathered leather, oxidized iron, real fur, moss and bark.
Lighting does the storytelling; the palette stays earthy and desaturated. Mood reference:
[`concept/gnome-rangers-concept.png`](concept/gnome-rangers-concept.png) (a reference for mood
and composition, not something to copy pixel for pixel).

The visual reference scene is `levels/sandbox/sandbox.tscn`; render it with
`tools/capture/capture.sh levels/sandbox/sandbox.tscn out.png`.

## Palette tokens

Source of truth in code: `ui/theme/palette.gd` (`class_name Palette`). `tests/unit/test_palette.gd`
fails if the code and this table drift apart.

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
| `leather` | `#5A3D28` | tack, barding, armour, UI borders |
| `leather_dark` | `#332115` | leather shadow side, pressed UI |
| `cat_fur` | `#181A1B` | cat mounts |
| `cat_sheen` | `#3B4044` | cat fur highlight, mount health bar |
| `orc_skin` | `#5B6643` | orc |
| `iron` | `#4A4742` | chainmail, weapons |
| `iron_edge` | `#78736A` | worn metal edges |
| `blanket_red` | `#8C2F1E` | saddle-blanket accent, **health bar** |
| `blanket_ochre` | `#C08A2E` | saddle-blanket accent, **stamina bar**, boss name |

## Lighting and post

Shared by every level through `fx/environment/forest_day.tres`:

- One warm directional sun at a steep angle through the canopy, shadows on.
- **Volumetric fog** tinted `canopy_haze`; with an occluding canopy it produces visible god rays.
  The sun's `light_volumetric_fog_energy` controls beam strength.
- SDFGI (fallback: VoxelGI baked per level), SSAO and SSIL on, glow subtle, **AgX** tonemap.
- Depth of field off in gameplay; subtle DOF only for the title/victory camera.
- **Rim-light readability rule:** dark actors (black cats, orc) get
  `fx/shaders/rim_light.gdshader` as a `next_pass` material (colour `rim_light`, strength 0.35) so
  they read against dark forest. Every actor material must stay readable at 20 m in the target
  lighting.

## UI chrome (Souls-style minimal)

`ui/theme/game_theme.tres` is the project theme (set in `project.godot`). Style Controls through
it; never hard-code colours in a scene.

- Panels: `forest_shadow` base, `bark` 2 px frame.
- Bars (`ProgressBar` and the `StaminaBar`, `MountBar`, `GhostBar` variations): `forest_shadow`
  at 70 % backing with a `leather` 2 px border. Fills: health `blanket_red`, stamina
  `blanket_ochre`, mount `cat_sheen`, boss delayed-damage ghost `canopy_haze`.
- Buttons: dark panel, `bark` frame, `leather` on hover/pressed, **focus ring `rim_light`**
  (full gamepad focus navigation).
- Text: `canopy_haze` body, `rim_light` highlights. Boss name uses `BossNameLabel` (`blanket_ochre`).
- Centre: lock-on marker (diamond, `rim_light`) and a bow reticle that tightens with draw.
- Typography (OFL, vendored in `ui/fonts/` with licences): **Cinzel** for titles/boss names
  (`HeaderLabel`, `BossNameLabel`), **Alegreya Sans** for body and HUD numbers (theme default).

## Model specs

- Meshy text/image-to-3D with realistic PBR textures. Triangle budgets: hero ≤ 30k, boss ≤ 40k,
  props ≤ 8k, foliage ≤ 3k (with LOD). Textures ≤ 2048² heroes, ≤ 1024² props.
- GLB, +Z forward, pivot at the feet, 1 unit = 1 m at gnome scale (gnome about 1.0 m, cat about
  0.9 m at the shoulder, orc brute about 4.0 m).
