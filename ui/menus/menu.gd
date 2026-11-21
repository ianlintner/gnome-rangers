class_name MenuScreen
extends Control
## Shared menu shell: a title, a vertical column of buttons, and a closed
## gamepad focus loop. Subclasses supply `menu_title` and `menu_actions`.
##
## Building buttons from data keeps every screen's focus navigation identical:
## down moves to the next button and wraps, up moves to the previous one and wraps,
## and the first button owns focus as soon as the screen enters the tree.

signal menu_action(action: StringName)

@export var menu_title: String = ""
@export var menu_subtitle: String = ""

var _title_label: Label
var _subtitle_label: Label
var _list: VBoxContainer
var _buttons: Array[Button] = []


## Array of Dictionaries: {text: String, action: StringName}.
func menu_actions() -> Array:
	return []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backing := ColorRect.new()
	backing.color = Palette.PANEL_BACKING
	backing.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backing)

	var centre := VBoxContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_CENTER)
	centre.custom_minimum_size = Vector2(420.0, 0.0)
	centre.add_theme_constant_override(&"separation", 12)
	add_child(centre)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.text = menu_title
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override(&"font_size", 40)
	_title_label.add_theme_color_override(&"font_color", Palette.RIM_LIGHT)
	centre.add_child(_title_label)

	if not menu_subtitle.is_empty():
		_subtitle_label = Label.new()
		_subtitle_label.name = "Subtitle"
		_subtitle_label.text = menu_subtitle
		_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_subtitle_label.add_theme_color_override(&"font_color", Palette.CANOPY_HAZE)
		centre.add_child(_subtitle_label)

	_list = VBoxContainer.new()
	_list.name = "Buttons"
	_list.add_theme_constant_override(&"separation", 8)
	centre.add_child(_list)

	var actions: Array = menu_actions()
	for i: int in range(actions.size()):
		var data: Dictionary = actions[i]
		var button := Button.new()
		button.name = "Action%d" % i
		button.text = String(data.get(&"text", ""))
		button.custom_minimum_size = Vector2(320.0, 44.0)
		button.focus_mode = Control.FOCUS_ALL
		var action: StringName = StringName(data.get(&"action", &""))
		button.pressed.connect(_on_action_pressed.bind(action))
		_list.add_child(button)
		_buttons.append(button)
	_wire_focus_neighbours()
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _wire_focus_neighbours() -> void:
	var count: int = _buttons.size()
	if count == 0:
		return
	for i: int in range(count):
		var button: Button = _buttons[i]
		var previous: Button = _buttons[(i - 1 + count) % count]
		var following: Button = _buttons[(i + 1) % count]
		button.focus_neighbor_left = get_path_to(previous)
		button.focus_neighbor_right = get_path_to(following)
		button.focus_neighbor_top = button.focus_neighbor_left
		button.focus_neighbor_bottom = button.focus_neighbor_right


func _on_action_pressed(action: StringName) -> void:
	menu_action.emit(action)


# --- Test-facing accessors --------------------------------------------------


func buttons() -> Array[Button]:
	return _buttons


func first_button() -> Button:
	return _buttons[0] if not _buttons.is_empty() else null


func title_text() -> String:
	return menu_title


func option_labels() -> Array[String]:
	return []
