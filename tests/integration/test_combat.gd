extends GutTest
## Combat integration: the real player scene fights the real training dummy through
## scripted input actions. Hit-stop is cancelled each frame so it cannot skew timings.

const DUMMY_SCENE: PackedScene = preload("res://actors/enemies/training_dummy/training_dummy.tscn")

var _player: Player
var _dummy: TrainingDummy
var _damage_events: Array[float] = []


func before_each() -> void:
	add_child_autofree(PlayerWorld.make_floor())
	_player = PlayerWorld.make_player()
	add_child_autofree(_player)
	_damage_events.clear()
	EventBus.damage_dealt.connect(_on_damage_dealt)


func after_each() -> void:
	PlayerWorld.release_all_actions()
	for action: StringName in [&"attack_light", &"attack_heavy", &"aim", &"fire"]:
		Input.action_release(action)
	if EventBus.damage_dealt.is_connected(_on_damage_dealt):
		EventBus.damage_dealt.disconnect(_on_damage_dealt)
	HitStop.cancel()


func _on_damage_dealt(_target: Node, amount: float, _weak: bool) -> void:
	_damage_events.append(amount)


func _spawn_dummy(position: Vector3) -> void:
	_dummy = DUMMY_SCENE.instantiate() as TrainingDummy
	_dummy.position = position
	add_child_autofree(_dummy)
	await wait_physics_frames(3)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)


func _light_chain() -> void:
	for _link: int in 3:
		await _tap(&"attack_light")
		await wait_seconds(0.3)
	await wait_seconds(0.5)


func test_light_chain_kills_the_training_dummy() -> void:
	await _spawn_dummy(Vector3(0, 0, -1.3))
	for _round: int in 4:
		if _dummy.health.is_dead():
			break
		await _light_chain()
		await wait_seconds(1.0)  # stamina regen
	assert_true(_dummy.health.is_dead(), "light chain should kill 100 HP within four rounds")
	assert_eq(_player.state_machine.current_state_name, &"Idle")


func test_light_chain_advances_through_three_links() -> void:
	await _spawn_dummy(Vector3(0, 0, -1.3))
	var seen: Array[StringName] = []
	_player.melee.animation_requested.connect(func(clip: StringName) -> void: seen.append(clip))
	await _light_chain()
	assert_eq(seen, [&"attack_light_1", &"attack_light_2", &"attack_light_3"])


func test_dodge_cancels_an_attack() -> void:
	await _spawn_dummy(Vector3(0, 0, -6))
	await _tap(&"attack_light")
	await wait_seconds(0.2)  # past the dodge-cancel window
	await _tap(&"dodge")
	await wait_physics_frames(2)
	assert_eq(_player.state_machine.current_state_name, &"Dodge")
	assert_false(_player.melee.is_busy())


func test_attack_with_no_stamina_is_refused() -> void:
	await _spawn_dummy(Vector3(0, 0, -1.3))
	_player.stamina.current = 1.0
	await _tap(&"attack_light")
	await wait_physics_frames(2)
	assert_ne(_player.state_machine.current_state_name, &"AttackLight")
	assert_eq(_dummy.health.current, 100.0)


func test_heavy_attack_breaks_poise() -> void:
	await _spawn_dummy(Vector3(0, 0, -1.3))
	Input.action_press(&"attack_heavy")
	await wait_seconds(1.1)  # full charge
	Input.action_release(&"attack_heavy")
	await wait_seconds(0.8)
	assert_true(_dummy.poise.staggered or _dummy.poise.riposte_open, "heavy hit broke poise")
	assert_lt(_dummy.health.current, 100.0)


func test_staggered_player_cannot_act_until_recovered() -> void:
	await _spawn_dummy(Vector3(0, 0, -8))
	_player.poise.take_poise_damage(_player.poise.max_poise)
	await wait_physics_frames(3)
	assert_eq(_player.state_machine.current_state_name, &"Stagger")
	await wait_seconds(_player.poise.stagger_duration + 0.3)
	assert_eq(_player.state_machine.current_state_name, &"Idle")


func _hold_aim() -> void:
	Input.action_press(&"aim")
	await wait_physics_frames(3)


func test_aim_toggles_camera_signal_and_draws_the_bow() -> void:
	watch_signals(EventBus)
	await _hold_aim()
	assert_eq(_player.state_machine.current_state_name, &"Aim")
	assert_true(_player.bow.drawing)
	assert_signal_emitted_with_parameters(EventBus, "aim_changed", [true])
	Input.action_release(&"aim")
	await wait_physics_frames(3)
	assert_signal_emitted_with_parameters(EventBus, "aim_changed", [false])
	assert_false(_player.bow.drawing)


func _shoot_after(draw_seconds: float) -> void:
	if draw_seconds > 0.0:
		await wait_seconds(draw_seconds)
	else:
		await wait_physics_frames(1)
	await _tap(&"fire")
	await wait_seconds(0.8)


func test_full_draw_does_more_damage_than_a_quick_shot() -> void:
	await _spawn_dummy(Vector3(0, 0, -5))
	await _hold_aim()
	await _shoot_after(0.0)
	var quick: float = _damage_events.back()
	await wait_seconds(0.5)  # nock
	await _shoot_after(1.2)
	var full: float = _damage_events.back()
	assert_eq(_damage_events.size(), 2, "both arrows hit")
	assert_gt(full, quick * 1.5, "full %s vs quick %s" % [full, quick])


func test_arrows_kill_the_dummy() -> void:
	await _spawn_dummy(Vector3(0, 0, -5))
	await _hold_aim()
	for _shot: int in 6:
		if _dummy.health.is_dead():
			break
		_player.stamina.current = _player.stamina.max_stamina
		await _shoot_after(1.1)
	assert_true(_dummy.health.is_dead())


func test_head_shot_hits_harder_than_body() -> void:
	await _spawn_dummy(Vector3(0, 0, -5))
	_player.bow.setup(_player.bow.data)
	var arrow: Arrow = null
	for height: float in [0.7, 1.65]:  # body centre, head centre
		_player.bow.begin_draw()
		_player.bow.draw_time = 1.0
		var origin: Vector3 = Vector3(0, height, -2)
		arrow = _player.bow.fire(_player, origin, Vector3(0, 0, -1), null)
		await wait_seconds(0.4)
	assert_eq(_damage_events.size(), 2)
	assert_almost_eq(_damage_events[1], _damage_events[0] * 2.0, 0.01)
	assert_not_null(arrow)


func test_arrows_stay_attached_to_a_moving_dummy() -> void:
	await _spawn_dummy(Vector3(0, 0, -5))
	await _hold_aim()
	await _shoot_after(1.1)
	var pool: ArrowPool = _player.bow.pool
	assert_eq(pool.stuck_count(), 1)
	var stuck: Arrow = null
	for node: Node in _dummy.find_children("*", "Node3D", true, false):
		if node is Arrow:
			stuck = node
	assert_not_null(stuck, "the arrow reparented into the dummy")
	var before: Vector3 = stuck.global_position
	_dummy.global_position += Vector3(2, 0, 0)
	await wait_physics_frames(2)
	assert_almost_eq(stuck.global_position.x - before.x, 2.0, 0.01)


func test_stuck_arrows_are_capped_and_recycled() -> void:
	await _spawn_dummy(Vector3(0, 0, -5))
	var data: BowData = _player.bow.data.duplicate() as BowData
	data.max_stuck_arrows = 2
	_player.bow.setup(data)
	for _shot: int in 4:
		_player.bow.begin_draw()
		_player.bow.draw_time = 1.0
		_player.bow.fire(_player, Vector3(0, 0.7, -2), Vector3(0, 0, -1), null)
		await wait_seconds(0.3)
		_player.bow._nock_left = 0.0
	assert_eq(_player.bow.pool.stuck_count(), 2)
