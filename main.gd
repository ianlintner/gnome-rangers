class_name GameFlow
extends Node
## Root scene-flow controller: title, gameplay, pause, settings, death, victory.
##
## Each screen is a menu scene hosted one at a time under `MenuHost`. The level is
## a separate scene under `LevelHost` so it can be freed between runs. A single
## full-screen ColorRect performs every transition fade; no AnimationPlayer or
## Tween ownership is spread across screens.

signal state_changed(state: StringName)

enum State { TITLE, PLAYING, PAUSED, SETTINGS, DEAD, VICTORY }

const TITLE_MENU: PackedScene = preload("res://ui/menus/title.tscn")
const PAUSE_MENU: PackedScene = preload("res://ui/menus/pause.tscn")
const SETTINGS_MENU: PackedScene = preload("res://ui/menus/settings.tscn")
const DEATH_MENU: PackedScene = preload("res://ui/menus/death.tscn")
const VICTORY_MENU: PackedScene = preload("res://ui/menus/victory.tscn")
const DEFAULT_LEVEL: PackedScene = preload("res://levels/rootfall_hollow/rootfall_hollow.tscn")

const STATE_NAMES: Dictionary = {
	State.TITLE: &"title",
	State.PLAYING: &"playing",
	State.PAUSED: &"paused",
	State.SETTINGS: &"settings",
	State.DEAD: &"dead",
	State.VICTORY: &"victory",
}

const NAME_STATES: Dictionary = {
	&"title": State.TITLE,
	&"paused": State.PAUSED,
	&"pause": State.PAUSED,
	&"settings": State.SETTINGS,
	&"dead": State.DEAD,
	&"victory": State.VICTORY,
}

## Overridable so captures can load the sandbox instead of the full level.
@export var level_scene: PackedScene = DEFAULT_LEVEL
## Seconds for each half of the fade.
@export_range(0.05, 1.0, 0.05) var fade_duration: float = 0.25

var _state: int = State.TITLE
var _settings_return: int = State.TITLE
var _menu: Control = null
var _level: Node = null

@onready var _menu_host: CanvasLayer = $MenuHost
@onready var _level_host: Node3D = $LevelHost
@onready var _fade: ColorRect = $FadeLayer/Fade
@onready var _hud: CanvasLayer = $HUD


func _ready() -> void:
	# Only the flow controller keeps processing while paused; the level host
	# must stay PAUSABLE so the player/boss/AI actually freeze behind overlays.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade.visible = false
	_hud.visible = false
	_fade.color = Color(
		Palette.FOREST_SHADOW.r, Palette.FOREST_SHADOW.g, Palette.FOREST_SHADOW.b, 0.0
	)
	EventBus.player_died.connect(_on_player_died)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.boss_engaged.connect(_on_boss_engaged)
	var settings: Settings = Settings.new()
	settings.load()
	settings.apply()
	_show_menu(TITLE_MENU, &"title")


func _exit_tree() -> void:
	get_tree().paused = false
	if EventBus.player_died.is_connected(_on_player_died):
		EventBus.player_died.disconnect(_on_player_died)
	if EventBus.boss_defeated.is_connected(_on_boss_defeated):
		EventBus.boss_defeated.disconnect(_on_boss_defeated)
	if EventBus.boss_engaged.is_connected(_on_boss_engaged):
		EventBus.boss_engaged.disconnect(_on_boss_engaged)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if _state == State.PLAYING:
			pause()
			get_viewport().set_input_as_handled()
		elif _state == State.PAUSED:
			resume()
			get_viewport().set_input_as_handled()


# --- State machine ----------------------------------------------------------


func state_name() -> StringName:
	return STATE_NAMES.get(_state, &"unknown")


func _set_state(next_state: int) -> void:
	_state = next_state
	state_changed.emit(state_name())


func _show_menu(packed: PackedScene, state_name_value: StringName) -> void:
	_clear_menu()
	_menu = packed.instantiate() as Control
	_menu_host.add_child(_menu)
	_menu.menu_action.connect(_on_menu_action)
	_set_state(_state_for_name(state_name_value))


func _state_for_name(name_value: StringName) -> int:
	return NAME_STATES.get(name_value, State.TITLE)


func _clear_menu() -> void:
	if _menu != null:
		if _menu.menu_action.is_connected(_on_menu_action):
			_menu.menu_action.disconnect(_on_menu_action)
		# The menu may be mid-emit (its own button chose this action), so it cannot be freed
		# now; take it out of the tree at once and free it at the end of the frame.
		_menu_host.remove_child(_menu)
		_menu.queue_free()
		_menu = null


func current_menu() -> Control:
	return _menu


func level() -> Node:
	return _level


func fade_rect() -> ColorRect:
	return _fade


func _on_menu_action(action: StringName) -> void:
	match action:
		&"new_game":
			start_new_game()
		&"continue":
			continue_game()
		&"settings":
			open_settings(state_name())
		&"back":
			close_settings()
		&"resume":
			resume()
		&"quit_to_title":
			quit_to_title()
		&"quit":
			quit_game()
		&"respawn":
			respawn()
		&"settings_changed":
			_apply_settings()


func _apply_settings() -> void:
	var settings: Settings = Settings.new()
	settings.load()
	settings.apply()
	var active_level: Node = _level
	if active_level != null and active_level.has_method(&"apply_quality_tier"):
		# RootfallHollow owns the renderer overrides; 0 = DEV, 1+ = HIGH.
		var tier: int = settings.quality_tier
		active_level.call(&"apply_quality_tier", 0 if tier == 0 else 1)


# --- Transitions ------------------------------------------------------------


func _start_fade() -> void:
	_fade.visible = true
	_fade.color.a = 1.0
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "color:a", 0.0, fade_duration)
	tween.finished.connect(_on_fade_finished)


func _on_fade_finished() -> void:
	_fade.visible = false


func start_new_game() -> void:
	GameState.clear()
	GameState.reset_run()
	_load_level()
	_begin_play()


func continue_game() -> void:
	if _level == null:
		_load_level()
	_begin_play()


func _load_level() -> void:
	_clear_level()
	if level_scene != null:
		_level = level_scene.instantiate()
		_level_host.add_child(_level)


## Installs a level directly (used by tests and capture harnesses).
func install_level(node: Node) -> void:
	_clear_level()
	_level = node
	_level_host.add_child(_level)


func _clear_level() -> void:
	if _level != null:
		_level.free()
		_level = null


func _begin_play() -> void:
	_clear_menu()
	get_tree().paused = false
	_set_state(State.PLAYING)
	_hud.visible = true
	_start_fade()
	_apply_settings()


func pause() -> void:
	if _state != State.PLAYING:
		return
	get_tree().paused = true
	_show_menu(PAUSE_MENU, &"paused")


func resume() -> void:
	if _state != State.PAUSED:
		return
	_clear_menu()
	get_tree().paused = false
	_set_state(State.PLAYING)


func open_settings(return_state: StringName) -> void:
	_settings_return = _state_for_name(return_state)
	_show_menu(SETTINGS_MENU, &"settings")


func close_settings() -> void:
	if _state != State.SETTINGS:
		return
	# Restore the screen we came from: clearing the menu without putting a new
	# one up left the player stranded on a blank viewport.
	match _settings_return:
		State.PAUSED:
			_show_menu(PAUSE_MENU, &"paused")
		State.TITLE, _:
			_show_menu(TITLE_MENU, &"title")


## Public entry point for tests and level scripts that drive death directly.
func on_player_died() -> void:
	_on_player_died()


func _on_player_died() -> void:
	if _state != State.PLAYING:
		return
	_show_menu(DEATH_MENU, &"dead")


func _on_boss_engaged(_boss: Node) -> void:
	pass  # The HUD handles the visual; the flow controller stays level-agnostic.


func _on_boss_defeated(_boss: Node) -> void:
	if _state == State.VICTORY or _state == State.TITLE:
		return
	GameState.mark_won()
	get_tree().paused = false
	_show_menu(VICTORY_MENU, &"victory")


func respawn() -> void:
	GameState.reset_run()
	var player: Player = _find_player()
	if player != null:
		player.global_transform = GameState.respawn_transform_for_player()
		player.velocity = Vector3.ZERO
		player.restore_vitals()
	EventBus.player_respawned.emit()
	_begin_play()


## The level's player: its `Player` child, else the first node in the player group.
func _find_player() -> Player:
	if _level == null:
		return null
	var direct := _level.get_node_or_null(^"Player") as Player
	if direct != null:
		return direct
	return get_tree().get_first_node_in_group(Player.GROUP) as Player


func quit_to_title() -> void:
	get_tree().paused = false
	_clear_level()
	_clear_menu()
	_hud.visible = false
	_set_state(State.TITLE)
	_show_menu(TITLE_MENU, &"title")


func quit_game() -> void:
	get_tree().quit()
