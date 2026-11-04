extends GutTest
## Palette tokens must match the hex values in PLAN.md / docs/art-direction.md.

const EXPECTED: Dictionary = {
	&"forest_shadow": "141911",
	&"moss_bright": "4A6423",
	&"fern_mid": "384D26",
	&"bark": "3A2E21",
	&"leaf_litter": "5C4328",
	&"canopy_haze": "C8CEB8",
	&"rim_light": "E2E6D5",
	&"cloak_olive": "43532A",
	&"leather": "5A3D28",
	&"leather_dark": "332115",
	&"cat_fur": "181A1B",
	&"cat_sheen": "3B4044",
	&"orc_skin": "5B6643",
	&"iron": "4A4742",
	&"iron_edge": "78736A",
	&"blanket_red": "8C2F1E",
	&"blanket_ochre": "C08A2E",
}


func test_every_plan_token_is_present() -> void:
	for token: StringName in EXPECTED.keys():
		assert_true(Palette.TOKENS.has(token), "missing token %s" % token)
	assert_eq(Palette.TOKENS.size(), EXPECTED.size())


func test_hex_values_match_plan() -> void:
	for token: StringName in EXPECTED.keys():
		var colour: Color = Palette.TOKENS[token]
		var expected := Color(EXPECTED[token] as String)
		assert_eq(
			colour.to_html(false).to_upper(), (EXPECTED[token] as String).to_upper(), str(token)
		)
		assert_eq(colour, expected)


func test_semantic_aliases() -> void:
	assert_eq(Palette.HEALTH, Palette.BLANKET_RED)
	assert_eq(Palette.STAMINA, Palette.BLANKET_OCHRE)
	assert_eq(Palette.MOUNT_HEALTH, Palette.CAT_SHEEN)
	assert_almost_eq(Palette.PANEL_BACKING.a, 0.7, 0.001)
	assert_eq(Palette.PANEL_BACKING.to_html(false), "141911")
