extends GutTest
## The real-game capture registry lists the documented shots and every entry is runnable.
## The driver is bound by path, not by a global class_name: it is a tool, not test plumbing.

const GameCapture: Script = preload("res://tools/capture/game_capture.gd")

const REQUIRED: Array[StringName] = [
	&"title_backdrop",
	&"first_run_controls",
	&"on_foot_explore",
	&"mounted_gallop_gnome",
	&"fog_gate_prompt",
	&"boss_phase2_hit_sparks",
	&"death_world_behind",
	&"victory",
]


func test_registry_has_required_shots() -> void:
	for shot_name: StringName in REQUIRED:
		assert_true(GameCapture.SHOTS.has(shot_name), "registry has %s" % shot_name)


func test_every_entry_resolves_to_a_method() -> void:
	var driver: Node = GameCapture.new()
	for shot_name: StringName in GameCapture.SHOTS.keys():
		var method: StringName = GameCapture.SHOTS[shot_name] as StringName
		assert_true(driver.has_method(method), "%s -> %s exists" % [shot_name, method])
		assert_true(Callable(driver, method).is_valid(), "%s is callable" % shot_name)
	driver.free()


func test_unknown_shots_are_reported() -> void:
	var names: Array[StringName] = [&"victory", &"nope"]
	var unknown: Array[StringName] = GameCapture.unknown_shots(names)
	assert_eq(unknown, [&"nope"] as Array[StringName])
