class_name HudBuilder
extends RefCounted
## Shared construction helpers for [Hud]. Keeps the HUD script focused on signal
## reactions; every colour still comes from [Palette].

const BORDER: int = 2
const BAR_WIDTH: float = 240.0
const BAR_HEIGHT: float = 10.0


static func backing_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.PANEL_BACKING
	style.border_color = Palette.LEATHER
	set_border_all(style, BORDER)
	return style


static func empty_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.FOREST_SHADOW
	style.border_width_left = 0
	return style


static func fill_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style


static func set_border_all(style: StyleBoxFlat, width: int) -> void:
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width


## Creates a thin bar inside its own bordered backing panel.
static func bar(
	parent: Node, name: String, color: Color, width: float, height: float
) -> ProgressBar:
	var track: PanelContainer = PanelContainer.new()
	track.name = name + "Track"
	track.custom_minimum_size = Vector2(width, height + 2 * BORDER)
	track.add_theme_stylebox_override(&"panel", backing_style())
	parent.add_child(track)
	var bar_node := ProgressBar.new()
	bar_node.name = name
	bar_node.min_value = 0.0
	bar_node.max_value = 100.0
	bar_node.value = 100.0
	bar_node.show_percentage = false
	bar_node.custom_minimum_size = Vector2(width - 2 * BORDER, height)
	bar_node.add_theme_stylebox_override(&"background", empty_style())
	bar_node.add_theme_stylebox_override(&"fill", fill_style(color))
	track.add_child(bar_node)
	return bar_node


## Creates a bar inside an existing parent without an extra backing panel, so two
## bars can occupy the same health track (delayed ghost behind the live fill).
static func overlaid_bar(bar_name: String, color: Color, parent: Node) -> ProgressBar:
	var bar_node := ProgressBar.new()
	bar_node.name = bar_name
	bar_node.min_value = 0.0
	bar_node.max_value = 100.0
	bar_node.value = 100.0
	bar_node.show_percentage = false
	bar_node.custom_minimum_size = Vector2(BAR_WIDTH - 2 * BORDER, BAR_HEIGHT)
	bar_node.add_theme_stylebox_override(&"background", empty_style())
	bar_node.add_theme_stylebox_override(&"fill", fill_style(color))
	parent.add_child(bar_node)
	return bar_node
