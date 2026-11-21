class_name Settings
extends RefCounted
## Player-facing preferences, persisted to `user://settings.cfg`.
##
## Deliberately a plain RefCounted value object rather than an autoload: menus create one,
## edit it, call [method save], and the main scene calls [method apply]. Tests can redirect
## the file with [method configure_for_tests]. Only the small ConfigFile helper owns I/O.

const SECTION_INPUT := &"input"
const SECTION_VIDEO := &"video"
const SECTION_AUDIO := &"audio"

const DEFAULT_PATH := "user://settings.cfg"

## Quality tier indices match RootfallHollow.QualityTier where they overlap (0 = DEV,
## 1 = HIGH). Index 2 is reserved for an ULTRA preset and clamps to HIGH for now.
const TIER_DEV: int = 0
const TIER_HIGH: int = 1
const TIER_ULTRA: int = 2

static var _path: String = DEFAULT_PATH

@export_range(0.25, 2.0, 0.05) var mouse_sensitivity: float = 1.0
@export_range(0.25, 2.0, 0.05) var stick_sensitivity: float = 1.0
@export var invert_y: bool = false
@export_range(50.0, 100.0, 1.0) var fov: float = 70.0
@export_range(0.0, 1.0, 0.01) var master_volume: float = 1.0
@export_range(0, 2, 1) var quality_tier: int = TIER_HIGH


## Redirects the config path; used by tests and nothing else.
static func configure_for_tests(path: String) -> void:
	_path = path


static func config_path() -> String:
	return _path


func save() -> bool:
	var config := ConfigFile.new()
	config.set_value(SECTION_INPUT, &"mouse_sensitivity", mouse_sensitivity)
	config.set_value(SECTION_INPUT, &"stick_sensitivity", stick_sensitivity)
	config.set_value(SECTION_INPUT, &"invert_y", invert_y)
	config.set_value(SECTION_VIDEO, &"fov", fov)
	config.set_value(SECTION_VIDEO, &"quality_tier", quality_tier)
	config.set_value(SECTION_AUDIO, &"master_volume", master_volume)
	return config.save(_path) == OK


func load() -> bool:
	var config := ConfigFile.new()
	var result: Error = config.load(_path)
	if result != OK:
		return false
	mouse_sensitivity = clampf(
		float(config.get_value(SECTION_INPUT, &"mouse_sensitivity", mouse_sensitivity)), 0.25, 2.0
	)
	stick_sensitivity = clampf(
		float(config.get_value(SECTION_INPUT, &"stick_sensitivity", stick_sensitivity)), 0.25, 2.0
	)
	invert_y = bool(config.get_value(SECTION_INPUT, &"invert_y", invert_y))
	fov = clampf(float(config.get_value(SECTION_VIDEO, &"fov", fov)), 50.0, 100.0)
	master_volume = clampf(
		float(config.get_value(SECTION_AUDIO, &"master_volume", master_volume)), 0.0, 1.0
	)
	quality_tier = clampi(int(config.get_value(SECTION_VIDEO, &"quality_tier", quality_tier)), 0, 2)
	return true


## Applies audio/video settings immediately. Input and FOV values are read by their owners.
func apply() -> void:
	var bus_index: int = AudioServer.get_bus_index("Master")
	if bus_index >= 0:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(master_volume, 0.0001)))
		AudioServer.set_bus_mute(bus_index, master_volume <= 0.0)
