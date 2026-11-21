extends GutTest
## Game-flow controller: title → level → pause → death/respawn → victory,
## with a short fade between scenes.

const MAIN: PackedScene = preload("res://main.tscn")
const HEALTH_SCRIPT: Script = preload("res://core/components/health_component.gd")
const STAMINA_SCRIPT: Script = preload("res://core/components/stamina_component.gd")

var _main: Node = null


func before_each() -> void:
	GameState.clear()
	_main = MAIN.instantiate() as Node
	add_child_autofree(_main)


func after_each() -> void:
	_main.free()
	get_tree().paused = false
	GameState.clear()


func _make_level() -> Node3D:
	var level := Node3D.new()
	level.name = "Level"
	var player := Node3D.new()
	player.name = "Player"
	player.add_to_group(&"player")
	var health: Node = HEALTH_SCRIPT.new()
	health.name = "HealthComponent"
	health.max_health = 100.0
	health.current = 20.0
	player.add_child(health)
	var stamina: Node = STAMINA_SCRIPT.new()
	stamina.name = "StaminaComponent"
	stamina.current = 0.0
	player.add_child(stamina)
	level.add_child(player)
	_main.install_level(level)
	return level


func test_starts_on_title_with_fade_hidden() -> void:
	assert_eq(_main.state_name(), &"title")
	assert_not_null(_main.current_menu())
	assert_false(_main.fade_rect().visible, "no fade on the first frame")
	assert_false(get_tree().paused)


func test_new_game_loads_level_and_hides_menu() -> void:
	_main.start_new_game()
	assert_eq(_main.state_name(), &"playing")
	assert_null(_main.current_menu())
	assert_not_null(_main.level())


func test_pause_shows_pause_menu_and_pauses_tree() -> void:
	_main.start_new_game()
	_main.pause()
	assert_eq(_main.state_name(), &"paused")
	assert_true(get_tree().paused)
	assert_eq(_main.current_menu().title_text(), "PAUSED")
	_main.resume()
	assert_eq(_main.state_name(), &"playing")
	assert_false(get_tree().paused)


func test_settings_can_be_opened_from_title_and_pause() -> void:
	_main.open_settings(&"title")
	assert_eq(_main.state_name(), &"settings")
	assert_eq(_main.current_menu().title_text(), "SETTINGS")
	_main.close_settings()
	assert_eq(_main.state_name(), &"title")
	_main.start_new_game()
	_main.pause()
	_main.open_settings(&"pause")
	_main.close_settings()
	assert_eq(_main.state_name(), &"paused")


func test_death_screen_appears_on_player_died() -> void:
	_main.start_new_game()
	_main.on_player_died()
	assert_eq(_main.state_name(), &"dead")
	assert_eq(_main.current_menu().title_text(), "YOU WERE SQUASHED")


func test_respawn_refills_player_and_emits_boss_reset() -> void:
	_main.start_new_game()
	var level: Node3D = _make_level()
	var player: Node = level.get_node("Player")
	_main.on_player_died()
	watch_signals(EventBus)
	watch_signals(GameState)
	var token_before: int = GameState.reset_token
	_main.respawn()
	assert_eq(_main.state_name(), &"playing")
	assert_eq((player.get_node("HealthComponent") as HealthComponent).current, 100.0)
	assert_gt((player.get_node("StaminaComponent") as StaminaComponent).current, 0.0)
	assert_eq(GameState.reset_token, token_before + 1)
	assert_signal_emitted(GameState, "run_reset")
	assert_signal_emitted(EventBus, "player_respawned")


func test_respawn_uses_checkpoint_transform() -> void:
	_main.start_new_game()
	var level: Node3D = _make_level()
	var checkpoint := Node3D.new()
	add_child_autofree(checkpoint)
	checkpoint.global_position = Vector3(4, 0, 9)
	GameState.set_checkpoint(checkpoint, checkpoint.global_transform)
	var player: Node = level.get_node("Player")
	player.global_position = Vector3(99, 0, 99)
	_main.on_player_died()
	_main.respawn()
	assert_eq(player.global_position, Vector3(4, 0, 9))


func test_boss_defeat_shows_victory() -> void:
	_main.start_new_game()
	watch_signals(EventBus)
	EventBus.boss_defeated.emit(null)
	assert_eq(_main.state_name(), &"victory")
	assert_true(GameState.is_won())
	assert_signal_emitted(EventBus, "game_won")


func test_quit_to_title_clears_level_and_unpauses() -> void:
	_main.start_new_game()
	_main.pause()
	_main.quit_to_title()
	assert_eq(_main.state_name(), &"title")
	assert_null(_main.level())
	assert_false(get_tree().paused)


func test_fade_transition_runs_and_settles() -> void:
	_main.start_new_game()
	_main._start_fade()
	assert_true(_main.fade_rect().visible)
	await get_tree().create_timer(0.5).timeout
	assert_almost_eq(_main.fade_rect().color.a, 0.0, 0.01)
	assert_false(_main.fade_rect().visible)
