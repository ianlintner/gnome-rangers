extends GutTest
## Player FSM transitions, driven with scripted input actions on a real floor.

var _player: Player


func before_each() -> void:
	add_child_autofree(PlayerWorld.make_floor())
	_player = PlayerWorld.make_player()
	add_child_autofree(_player)
	await wait_physics_frames(3)


func after_each() -> void:
	PlayerWorld.release_all_actions()


func _state() -> StringName:
	return _player.state_machine.current_state_name


func test_idle_on_the_floor_at_start() -> void:
	assert_eq(_state(), &"Idle")


func test_idle_to_move_to_sprint_to_dodge_to_idle() -> void:
	Input.action_press(&"move_forward")
	await wait_physics_frames(3)
	assert_eq(_state(), &"Move")

	Input.action_press(&"sprint")
	await wait_physics_frames(3)
	assert_eq(_state(), &"Sprint")

	Input.action_press(&"dodge")
	await wait_physics_frames(2)
	Input.action_release(&"dodge")
	assert_eq(_state(), &"Dodge")

	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	await wait_seconds(0.9)
	assert_eq(_state(), &"Idle")


func test_dodge_with_no_input_is_a_backstep_away_from_facing() -> void:
	var start: Vector3 = _player.global_position
	Input.action_press(&"dodge")
	await wait_physics_frames(2)
	Input.action_release(&"dodge")
	assert_eq(_state(), &"Dodge")
	await wait_seconds(0.8)
	assert_gt(_player.global_position.z - start.z, 1.0, "backstep moves towards +Z (backwards)")


func test_dodge_spends_stamina() -> void:
	Input.action_press(&"dodge")
	await wait_physics_frames(2)
	Input.action_release(&"dodge")
	assert_almost_eq(_player.stamina.current, 80.0, 1.0)


func test_dodge_refused_without_stamina() -> void:
	_player.stamina.current = 5.0
	Input.action_press(&"dodge")
	await wait_physics_frames(3)
	Input.action_release(&"dodge")
	assert_eq(_state(), &"Idle")


func test_sprint_ends_when_stamina_runs_out() -> void:
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await wait_physics_frames(3)
	_player.stamina.current = 0.1
	await wait_physics_frames(4)
	assert_ne(_state(), &"Sprint")
	assert_true(_player.stamina.is_winded())


func test_stagger_stub_returns_to_idle() -> void:
	_player.stagger()
	assert_eq(_state(), &"Stagger")
	await wait_seconds(0.7)
	assert_eq(_state(), &"Idle")


func test_falls_when_there_is_no_ground() -> void:
	_player.global_position = Vector3(100, 5, 100)
	await wait_physics_frames(4)
	assert_eq(_state(), &"Fall")
