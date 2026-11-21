extends GutTest
## Settings helper: values persist to a ConfigFile and round-trip with validation.

const SETTINGS_SCRIPT: Script = preload("res://ui/menus/settings.gd")

var _path: String = ""


func before_each() -> void:
	_path = "user://test_settings_%d.cfg" % randi()
	Settings.configure_for_tests(_path)


func after_each() -> void:
	Settings.configure_for_tests("user://settings.cfg")
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


func test_defaults_are_sane() -> void:
	var settings: Settings = Settings.new()
	assert_almost_eq(settings.mouse_sensitivity, 1.0, 0.001)
	assert_almost_eq(settings.stick_sensitivity, 1.0, 0.001)
	assert_false(settings.invert_y)
	assert_almost_eq(settings.fov, 70.0, 0.001)
	assert_almost_eq(settings.master_volume, 1.0, 0.001)
	assert_eq(settings.quality_tier, 1)


func test_settings_round_trip_to_user_settings_cfg() -> void:
	var settings: Settings = Settings.new()
	settings.mouse_sensitivity = 0.45
	settings.stick_sensitivity = 1.75
	settings.invert_y = true
	settings.fov = 82.0
	settings.master_volume = 0.3
	settings.quality_tier = 0
	assert_true(settings.save(), "save succeeded")
	assert_true(FileAccess.file_exists(_path), "settings file exists")

	var loaded: Settings = Settings.new()
	loaded.load()
	assert_almost_eq(loaded.mouse_sensitivity, 0.45, 0.001)
	assert_almost_eq(loaded.stick_sensitivity, 1.75, 0.001)
	assert_true(loaded.invert_y)
	assert_almost_eq(loaded.fov, 82.0, 0.001)
	assert_almost_eq(loaded.master_volume, 0.3, 0.001)
	assert_eq(loaded.quality_tier, 0)


func test_load_clamps_out_of_range_values() -> void:
	var config := ConfigFile.new()
	config.set_value("input", "mouse_sensitivity", 999.0)
	config.set_value("input", "stick_sensitivity", -5.0)
	config.set_value("video", "fov", 300.0)
	config.set_value("audio", "master_volume", -1.0)
	config.set_value("video", "quality_tier", 99)
	config.save(_path)
	var loaded: Settings = Settings.new()
	loaded.load()
	assert_lte(loaded.mouse_sensitivity, 2.0)
	assert_gte(loaded.stick_sensitivity, 0.25)
	assert_lte(loaded.fov, 100.0)
	assert_gte(loaded.master_volume, 0.0)
	assert_gte(loaded.quality_tier, 0)
	assert_lte(loaded.quality_tier, 2)


func test_apply_sets_master_volume_bus() -> void:
	var settings: Settings = Settings.new()
	settings.master_volume = 0.25
	settings.apply()
	var bus_index: int = AudioServer.get_bus_index("Master")
	assert_almost_eq(AudioServer.get_bus_volume_db(bus_index), linear_to_db(0.25), 0.01)
	settings.master_volume = 1.0
	settings.apply()
