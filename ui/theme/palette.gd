class_name Palette
extends RefCounted
## Art-direction colour tokens. Single source of truth for every colour in code.
##
## Values mirror the table in `docs/art-direction.md`. Style UI through
## `game_theme.tres` and these constants; never hard-code a hex in a scene or script.

const FOREST_SHADOW := Color("141911")
const MOSS_BRIGHT := Color("4A6423")
const FERN_MID := Color("384D26")
const BARK := Color("3A2E21")
const LEAF_LITTER := Color("5C4328")
const CANOPY_HAZE := Color("C8CEB8")
const RIM_LIGHT := Color("E2E6D5")
const CLOAK_OLIVE := Color("43532A")
const LEATHER := Color("5A3D28")
const LEATHER_DARK := Color("332115")
const CAT_FUR := Color("181A1B")
const CAT_SHEEN := Color("3B4044")
const ORC_SKIN := Color("5B6643")
const IRON := Color("4A4742")
const IRON_EDGE := Color("78736A")
const BLANKET_RED := Color("8C2F1E")
const BLANKET_OCHRE := Color("C08A2E")

## Token name -> colour, for tools and tests that iterate the whole palette.
const TOKENS: Dictionary = {
	&"forest_shadow": FOREST_SHADOW,
	&"moss_bright": MOSS_BRIGHT,
	&"fern_mid": FERN_MID,
	&"bark": BARK,
	&"leaf_litter": LEAF_LITTER,
	&"canopy_haze": CANOPY_HAZE,
	&"rim_light": RIM_LIGHT,
	&"cloak_olive": CLOAK_OLIVE,
	&"leather": LEATHER,
	&"leather_dark": LEATHER_DARK,
	&"cat_fur": CAT_FUR,
	&"cat_sheen": CAT_SHEEN,
	&"orc_skin": ORC_SKIN,
	&"iron": IRON,
	&"iron_edge": IRON_EDGE,
	&"blanket_red": BLANKET_RED,
	&"blanket_ochre": BLANKET_OCHRE,
}

## Health bar fill.
const HEALTH := BLANKET_RED
## Stamina bar fill and boss name.
const STAMINA := BLANKET_OCHRE
## Mount health bar fill.
const MOUNT_HEALTH := CAT_SHEEN
## UI panel body colour (forest_shadow at 70 % alpha, the HUD backing).
const PANEL_BACKING := Color(0.0784, 0.0980, 0.0667, 0.7)
