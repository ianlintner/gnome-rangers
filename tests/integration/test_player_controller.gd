extends GutTest
## Headless controller integration: scripted input actions drive the real player scene.

const PHYSICS_DT: float = 1.0 / 60.0

var _player: Player
var _hitbox: AttackerProbe
var _landed: Array[int] = []
var _ignored: Array[int] = []
var _dodge_start_frame: int = -1


func before_each() -> void:
	add_child_autofree(PlayerWorld.make_floor())
	_player = PlayerWorld.make_player()
	add_child_autofree(_player)
	await wait_physics_frames(3)


func after_each() -> void:
	PlayerWorld.release_all_actions()
	EventBus.lock_on_changed.emit(null)


func test_player_moves_forward_camera_relative() -> void:
	var start: Vector3 = _player.global_position
	Input.action_press(&"move_forward")
	await wait_seconds(1.0)
	Input.action_release(&"move_forward")
	var travelled: float = start.z - _player.global_position.z
	assert_between(travelled, 2.5, 3.2, "about 3 m/s for 1 s, minus the acceleration ramp")
	assert_almost_eq(_player.global_position.x, start.x, 0.1)


func test_movement_follows_camera_yaw() -> void:
	var camera := PlayerWorld.CAMERA_SCENE.instantiate() as ThirdPersonCamera
	add_child_autofree(camera)
	camera.yaw = -PI / 2.0  # camera looks along +X
	_player.camera = camera
	var start: Vector3 = _player.global_position
	Input.action_press(&"move_forward")
	await wait_seconds(0.8)
	Input.action_release(&"move_forward")
	assert_gt(_player.global_position.x - start.x, 1.5)
	assert_almost_eq(_player.global_position.z, start.z, 0.2)


func _arm_hit_recording() -> void:
	_hitbox = AttackerProbe.new()
	_hitbox.damage = 0.5  # the player now has real health; keep the probe from killing it
	add_child_autofree(_hitbox)
	_player.hurtbox.hit_received.connect(
		func(_amount: float, _source: Node) -> void: _landed.append(Engine.get_physics_frames())
	)
	_player.hurtbox.hit_ignored.connect(
		func(_amount: float, _source: Node) -> void: _ignored.append(Engine.get_physics_frames())
	)
	_player.state_machine.state_changed.connect(
		func(_from: StringName, to: StringName) -> void:
			if to == &"Dodge":
				_dodge_start_frame = Engine.get_physics_frames()
	)
	await wait_physics_frames(2)  # let the area overlap register


func test_standing_in_an_active_hitbox_takes_damage() -> void:
	await _arm_hit_recording()
	_hitbox.active = true
	await wait_physics_frames(10)
	assert_gt(_landed.size(), 0)
	assert_eq(_ignored.size(), 0)


func test_dodge_through_hitbox_is_safe_inside_iframes_and_hurt_outside() -> void:
	await _arm_hit_recording()
	_hitbox.active = true
	Input.action_press(&"move_left")
	Input.action_press(&"dodge")
	await wait_physics_frames(2)
	Input.action_release(&"dodge")
	await wait_seconds(0.8)
	Input.action_release(&"move_left")
	_hitbox.active = false

	assert_gt(_dodge_start_frame, 0, "the dodge started")
	assert_gt(_ignored.size(), 5, "hits during i-frames were ignored")
	var window_start: int = int(ceil(_player.stats.iframe_start / PHYSICS_DT)) + 1
	var window_end: int = (
		int(floor((_player.stats.iframe_start + _player.stats.iframe_duration) / PHYSICS_DT)) - 1
	)
	for frame: int in _landed:
		var offset: int = frame - _dodge_start_frame
		assert_false(
			offset >= window_start and offset <= window_end,
			"damage landed inside the i-frame window at offset %d" % offset
		)
	var late_hits: Array[int] = _landed.filter(
		func(frame: int) -> bool: return frame - _dodge_start_frame > window_end + 2
	)
	assert_gt(late_hits.size(), 0, "damage lands again after the window closes")


func test_lock_on_picks_nearest_in_cone_and_ignores_closer_target_behind() -> void:
	var behind := PlayerWorld.make_dummy(Vector3(0, 0, 2))
	var near := PlayerWorld.make_dummy(Vector3(1, 0, -6))
	var far := PlayerWorld.make_dummy(Vector3(-1, 0, -12))
	var beyond_range := PlayerWorld.make_dummy(Vector3(0, 0, -40))
	for dummy: Node3D in [behind, near, far, beyond_range]:
		add_child_autofree(dummy)
	await wait_physics_frames(2)
	watch_signals(EventBus)

	_player.lock_selector.toggle()

	assert_eq(_player.lock_selector.current_target, near)
	assert_signal_emitted_with_parameters(EventBus, "lock_on_changed", [near])


func test_lock_on_via_input_action_then_flick_and_release() -> void:
	var near := PlayerWorld.make_dummy(Vector3(1, 0, -6))
	var far := PlayerWorld.make_dummy(Vector3(-2, 0, -10))
	add_child_autofree(near)
	add_child_autofree(far)
	await wait_physics_frames(2)

	Input.action_press(&"lock_on")
	await wait_physics_frames(2)
	Input.action_release(&"lock_on")
	assert_eq(_player.lock_selector.current_target, near)

	Input.action_press(&"lock_switch_left")
	await wait_physics_frames(2)
	Input.action_release(&"lock_switch_left")
	assert_eq(_player.lock_selector.current_target, far, "far target is to the left of near")

	Input.action_press(&"lock_switch_right")
	await wait_physics_frames(2)
	Input.action_release(&"lock_switch_right")
	assert_eq(_player.lock_selector.current_target, near)

	Input.action_press(&"lock_on")
	await wait_physics_frames(2)
	Input.action_release(&"lock_on")
	assert_null(_player.lock_selector.current_target)


func test_lock_breaks_on_distance() -> void:
	var target := PlayerWorld.make_dummy(Vector3(0, 0, -6))
	add_child_autofree(target)
	await wait_physics_frames(2)
	_player.lock_selector.toggle()
	assert_eq(_player.lock_selector.current_target, target)
	watch_signals(EventBus)
	target.global_position = Vector3(0, 0, -_player.stats.lock_break_range - 5.0)
	_player.lock_selector.tick(PHYSICS_DT)
	assert_null(_player.lock_selector.current_target)
	assert_signal_emitted_with_parameters(EventBus, "lock_on_changed", [null])


func test_lock_breaks_after_line_of_sight_is_lost_for_the_grace_period() -> void:
	var target := PlayerWorld.make_dummy(Vector3(0, 0, -8))
	add_child_autofree(target)
	await wait_physics_frames(2)
	_player.lock_selector.toggle()
	assert_eq(_player.lock_selector.current_target, target)
	add_child_autofree(PlayerWorld.make_box(Vector3(6, 4, 0.5), Vector3(0, 2, -4)))
	await wait_physics_frames(2)
	_player.lock_selector.tick(_player.stats.lock_los_grace * 0.4)
	assert_eq(_player.lock_selector.current_target, target, "still inside the grace period")
	_player.lock_selector.tick(_player.stats.lock_los_grace)
	assert_null(_player.lock_selector.current_target)


func test_lock_ignores_target_without_line_of_sight() -> void:
	add_child_autofree(PlayerWorld.make_box(Vector3(6, 4, 0.5), Vector3(0, 2, -4)))
	add_child_autofree(PlayerWorld.make_dummy(Vector3(0, 0, -8)))
	await wait_physics_frames(2)
	_player.lock_selector.toggle()
	assert_null(_player.lock_selector.current_target)


func test_locked_player_faces_the_target_while_strafing() -> void:
	var target := PlayerWorld.make_dummy(Vector3(0, 0, -8))
	add_child_autofree(target)
	await wait_physics_frames(2)
	_player.lock_selector.toggle()
	Input.action_press(&"move_right")
	await wait_seconds(0.8)
	Input.action_release(&"move_right")
	var to_target: Vector3 = (target.global_position - _player.global_position).normalized()
	assert_gt(_player.get_facing().dot(to_target), 0.97, "faces the target, not the move direction")
	assert_gt(_player.global_position.x, 1.0, "still strafed to the right")


func test_roll_covers_its_distance_then_holds_still_during_recovery() -> void:
	var start: Vector3 = _player.global_position
	Input.action_press(&"move_left")
	Input.action_press(&"dodge")
	await wait_physics_frames(2)
	Input.action_release(&"dodge")
	await wait_seconds(_player.stats.dodge_duration + PHYSICS_DT * 2.0)
	var after_move: Vector3 = _player.global_position
	assert_eq(_player.state_machine.current_state_name, &"Dodge", "still recovering")
	assert_almost_eq(start.distance_to(after_move), _player.stats.dodge_distance, 0.3)
	await wait_physics_frames(3)
	assert_almost_eq(_player.global_position, after_move, Vector3.ONE * 0.001)
	assert_almost_eq(_player.velocity.length(), 0.0, 0.001)
	Input.action_release(&"move_left")


func test_lock_on_uses_3d_range_for_elevated_targets() -> void:
	var tower := PlayerWorld.make_dummy(Vector3(0, 50, -5))
	add_child_autofree(tower)
	await wait_physics_frames(2)
	_player.lock_selector.toggle()
	assert_null(_player.lock_selector.current_target, "50 m up is out of range")


func test_lock_breaks_when_target_climbs_out_of_range() -> void:
	var target := PlayerWorld.make_dummy(Vector3(0, 0, -5))
	add_child_autofree(target)
	await wait_physics_frames(2)
	_player.lock_selector.toggle()
	assert_eq(_player.lock_selector.current_target, target)
	target.global_position.y += 50.0
	_player.lock_selector.tick(PHYSICS_DT)
	assert_null(_player.lock_selector.current_target)
