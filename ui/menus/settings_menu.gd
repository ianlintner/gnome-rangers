extends MenuScreen
## Settings screen. Buttons cycle values; changes are saved immediately through
## the shared [Settings] helper and applied to the audio bus.

const TIER_LABELS: Array[String] = ["DEV", "HIGH", "ULTRA"]

var settings: Settings = Settings.new()


func _init() -> void:
	menu_title = "SETTINGS"


func menu_actions() -> Array:
	return [
		{&"text": "", &"action": &"mouse_sensitivity"},
		{&"text": "", &"action": &"stick_sensitivity"},
		{&"text": "", &"action": &"invert_y"},
		{&"text": "", &"action": &"fov"},
		{&"text": "", &"action": &"master_volume"},
		{&"text": "", &"action": &"quality_tier"},
		{&"text": "Back", &"action": &"back"},
	]


func _ready() -> void:
	settings.load()
	super._ready()
	_refresh_labels()


func option_labels() -> Array[String]:
	var labels: Array[String] = []
	for button: Button in buttons():
		labels.append(button.text)
	return labels


func _on_action_pressed(action: StringName) -> void:
	if action == &"back":
		menu_action.emit(action)
		return
	match action:
		&"mouse_sensitivity":
			settings.mouse_sensitivity = _step(settings.mouse_sensitivity, 0.25, 2.0, 0.25)
		&"stick_sensitivity":
			settings.stick_sensitivity = _step(settings.stick_sensitivity, 0.25, 2.0, 0.25)
		&"invert_y":
			settings.invert_y = not settings.invert_y
		&"fov":
			settings.fov = _step(settings.fov, 50.0, 100.0, 5.0)
		&"master_volume":
			settings.master_volume = _step(settings.master_volume, 0.0, 1.0, 0.1)
		&"quality_tier":
			settings.quality_tier = (settings.quality_tier + 1) % TIER_LABELS.size()
		_:
			return
	settings.save()
	settings.apply()
	_refresh_labels()
	menu_action.emit(&"settings_changed")


func _step(value: float, minimum: float, maximum: float, step: float) -> float:
	var next_value: float = value + step
	return minimum if next_value > maximum else snappedf(next_value, 0.001)


func _refresh_labels() -> void:
	if buttons().is_empty():
		return
	buttons()[0].text = "Mouse sensitivity: %.2f" % settings.mouse_sensitivity
	buttons()[1].text = "Stick sensitivity: %.2f" % settings.stick_sensitivity
	buttons()[2].text = "Invert Y: %s" % ("ON" if settings.invert_y else "OFF")
	buttons()[3].text = "FOV: %d" % int(settings.fov)
	buttons()[4].text = "Master volume: %d%%" % int(settings.master_volume * 100.0)
	buttons()[5].text = "Quality: %s" % TIER_LABELS[clampi(settings.quality_tier, 0, 2)]
