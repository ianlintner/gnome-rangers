extends GutTest
## GameState checkpoint / respawn behaviour (autoload `GameState`).


func before_each() -> void:
	GameState.clear()


func after_each() -> void:
	GameState.clear()


func test_respawn_falls_back_to_spawn_transform() -> void:
	GameState.spawn_transform = Transform3D(Basis.IDENTITY, Vector3(1, 2, 3))
	assert_eq(GameState.respawn_transform_for_player().origin, Vector3(1, 2, 3))


func test_checkpoint_sets_respawn_point() -> void:
	var marker := Node3D.new()
	add_child_autofree(marker)
	marker.global_position = Vector3(5, 0, 5)
	watch_signals(GameState)
	GameState.set_checkpoint(marker, marker.global_transform)
	assert_signal_emitted(GameState, "checkpoint_set")
	assert_eq(GameState.respawn_transform_for_player().origin, Vector3(5, 0, 5))


func test_reset_run_bumps_token_and_signals() -> void:
	watch_signals(GameState)
	GameState.reset_run()
	assert_eq(GameState.reset_token, 1)
	assert_signal_emitted(GameState, "run_reset")


func test_mark_won_emits_once() -> void:
	watch_signals(EventBus)
	GameState.mark_won()
	GameState.mark_won()
	assert_signal_emit_count(EventBus, "game_won", 1)
	assert_true(GameState.is_won())
