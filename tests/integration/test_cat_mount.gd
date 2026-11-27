extends GutTest
## Cat mount integration: the real player, cat and training dummy driven by scripted input
## actions on a navigation-meshed floor.

const MOUNT_ACTIONS: Array[StringName] = [
	&"call_mount", &"interact", &"aim", &"fire", &"attack_heavy", &"attack_light"
]

var _world: Node3D
var _player: Player
var _cat: CatMount
var _dummy: TrainingDummy


func after_each() -> void:
	PlayerWorld.release_all_actions()
	for action: StringName in MOUNT_ACTIONS:
		Input.action_release(action)
	EventBus.lock_on_changed.emit(null)
	EventBus.aim_changed.emit(false)
	HitStop.cancel()


## Builds the floor, a player at the origin and a cat at `cat_position`.
func _setup(cat_position: Vector3, wall: bool = false) -> void:
	_world = MountWorld.make_nav_floor(wall)
	add_child_autofree(_world)
	_player = PlayerWorld.make_player()
	_world.add_child(_player)
	_cat = MountWorld.make_cat(cat_position)
	_world.add_child(_cat)
	await MountWorld.wait_for_navigation(self, _world)
	await wait_physics_frames(3)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)


## Puts the player on the cat through the real interact path and waits for the ride to start.
func _mount_up() -> void:
	await _tap(&"interact")
	await wait_seconds(0.6)


func _spawn_dummy(position: Vector3) -> void:
	_dummy = MountWorld.DUMMY_SCENE.instantiate() as TrainingDummy
	_dummy.position = position
	_world.add_child(_dummy)
	await wait_physics_frames(3)


func _heavy_hit(target: HurtboxComponent) -> bool:
	var attack: AttackData = load("res://actors/bosses/orc_brute/attacks/leaping_slam.tres")
	var info: DamageInfo = DamageInfo.from_attack(attack, null, &"enemy")
	info.direction = Vector3.BACK
	return target.receive_damage(info)


func test_call_mount_runs_the_cat_to_the_player_on_the_navmesh() -> void:
	await _setup(Vector3(-14, 0, 0))
	await _tap(&"call_mount")
	await wait_physics_frames(2)
	assert_eq(_cat.state_machine.current_state_name, &"Called")
	await wait_seconds(3.0)
	var distance: float = _cat.global_position.distance_to(_player.global_position)
	assert_lt(distance, _cat.stats.call_stop_distance + 0.4, "cat arrived next to the player")
	assert_eq(_cat.state_machine.current_state_name, &"Idle", "and waits there")


func test_called_cat_paths_around_a_wall() -> void:
	await _setup(Vector3(-10, 0, 0), true)
	_player.global_position = Vector3(10, 0, 0)
	await wait_physics_frames(2)
	await _tap(&"call_mount")
	var widest_z: float = 0.0
	for _step: int in 90:
		await wait_physics_frames(6)
		widest_z = maxf(widest_z, absf(_cat.global_position.z))
		if _cat.state_machine.current_state_name == &"Idle":
			break
	assert_gt(widest_z, MountWorld.WALL_HALF_LENGTH, "the cat went round the end of the wall")
	assert_lt(_cat.global_position.distance_to(_player.global_position), 2.0, "and arrived")


func test_mount_and_dismount_transitions() -> void:
	await _setup(Vector3(1.2, 0, 0))
	var mounted: Array[bool] = []
	EventBus.mount_mounted.connect(func() -> void: mounted.append(true))
	EventBus.mount_dismounted.connect(func() -> void: mounted.append(false))
	await _tap(&"interact")
	await wait_physics_frames(2)
	assert_eq(_player.state_machine.current_state_name, &"Mounting")
	assert_eq(_cat.state_machine.current_state_name, &"Ridden")
	assert_eq(_player.collision_layer, 0, "the rider body stops colliding")
	await wait_seconds(0.6)
	assert_eq(_player.state_machine.current_state_name, &"Mounted")
	assert_eq(_cat.rider, _player)
	assert_true(_cat.rider_seated)
	var seat: Vector3 = _cat.seat_transform().origin
	assert_lt(_player.global_position.distance_to(seat), 0.05, "rider sits on the saddle")
	await _tap(&"interact")
	await wait_physics_frames(2)
	assert_eq(_player.state_machine.current_state_name, &"Dismounting")
	await wait_seconds(0.5)
	assert_eq(_player.state_machine.current_state_name, &"Idle")
	assert_null(_cat.rider)
	assert_eq(_cat.state_machine.current_state_name, &"Idle")
	assert_eq(_player.collision_layer, 2, "collision layer restored")
	assert_eq(mounted, [true, false])


func test_cannot_mount_out_of_range() -> void:
	await _setup(Vector3(6, 0, 0))
	await _tap(&"interact")
	await wait_physics_frames(3)
	assert_null(_cat.rider)
	assert_eq(_player.state_machine.current_state_name, &"Idle")


func test_rider_follows_the_saddle_while_the_cat_moves() -> void:
	await _setup(Vector3(1.2, 0, 0))
	await _mount_up()
	Input.action_press(&"move_forward")
	await wait_seconds(1.0)
	Input.action_release(&"move_forward")
	var seat: Vector3 = _cat.seat_transform().origin
	assert_lt(_player.global_position.distance_to(seat), 0.05)
	assert_almost_eq(
		_player.rotation.y, _cat.rotation.y, 0.01, "the rider faces the way the cat does"
	)


func test_mounted_walk_and_gallop_are_faster_than_on_foot() -> void:
	await _setup(Vector3(1.2, 0, 0))
	await _mount_up()
	Input.action_press(&"move_forward")
	await wait_seconds(1.0)
	var walk: float = _cat.get_horizontal_speed()
	assert_gt(walk, _player.stats.move_speed + 1.0, "mounted walk beats walking")
	Input.action_press(&"sprint")
	await wait_seconds(1.2)
	var gallop: float = _cat.get_horizontal_speed()
	assert_gt(gallop, _player.stats.sprint_speed + 1.0, "gallop beats the on-foot sprint")
	assert_eq(_cat.state_machine.current_state_name, &"Gallop")
	assert_eq(_player.state_machine.current_state_name, &"MountedSprint")
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")


func test_mounted_sprint_spends_stamina() -> void:
	await _setup(Vector3(1.2, 0, 0))
	await _mount_up()
	var before: float = _player.stamina.current
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await wait_seconds(1.0)
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")
	assert_lt(_player.stamina.current, before - 4.0, "galloping costs stamina")


func test_mounted_arrow_damages_the_dummy() -> void:
	await _setup(Vector3(1.2, 0, 0))
	await _mount_up()
	await _spawn_dummy(_player.global_position + Vector3(0, 0, -7))
	var before: float = _dummy.health.current
	Input.action_press(&"aim")
	await wait_seconds(1.1)  # a full draw
	assert_eq(_player.state_machine.current_state_name, &"MountedAim")
	await _tap(&"fire")
	await wait_seconds(0.8)
	assert_lt(_dummy.health.current, before, "the arrow hit the dummy")
	Input.action_release(&"aim")
	await wait_physics_frames(3)
	assert_eq(_player.state_machine.current_state_name, &"Mounted")


func test_pounce_applies_poise_damage_and_respects_its_cooldown() -> void:
	await _setup(Vector3(1.2, 0, 0))
	await _mount_up()
	_cat.stats = _cat.stats.duplicate() as MountStats
	_cat.stats.pounce_cooldown = 2.0
	await _spawn_dummy(_player.global_position + Vector3(0, 0, -16))
	var landed: Array[bool] = []
	_cat.pounce_landed.connect(func() -> void: landed.append(true))
	EventBus.lock_on_changed.emit(null)
	await _tap(&"lock_on")
	assert_eq(_player.lock_selector.current_target, _dummy, "locked onto the dummy")
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await wait_seconds(1.2)
	assert_eq(_cat.state_machine.current_state_name, &"Gallop")
	await _tap(&"attack_heavy")
	await wait_physics_frames(2)
	assert_eq(_cat.state_machine.current_state_name, &"Pounce")
	await wait_seconds(1.0)
	assert_eq(landed.size(), 1, "the pounce landed")
	assert_gt(_dummy.health.max_health - _dummy.health.current, 0.0, "pounce damage")
	assert_true(_dummy.poise.staggered, "pounce poise damage broke the dummy's poise")
	# Immediately again: refused by the cooldown even though the cat gallops again.
	assert_gt(_cat.pounce_cooldown_left, 0.0)
	assert_false(_cat.can_pounce(_dummy), "cooldown refuses a second pounce")
	await wait_seconds(2.1)
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")
	assert_eq(_cat.pounce_cooldown_left, 0.0, "cooldown elapsed")


func test_pounce_needs_a_gallop_and_a_target_in_range() -> void:
	await _setup(Vector3(1.2, 0, 0))
	await _mount_up()
	await _spawn_dummy(_player.global_position + Vector3(0, 0, -5))
	assert_false(_cat.request_pounce(_dummy), "standing cat cannot pounce")
	assert_false(_cat.request_pounce(null), "no target, no pounce")


func test_heavy_hit_knocks_the_rider_off() -> void:
	await _setup(Vector3(1.2, 0, 0))
	await _mount_up()
	var light := DamageInfo.new()
	light.amount = 5.0
	light.poise_damage = 5.0
	light.faction = &"enemy"
	assert_true(_player.hurtbox.receive_damage(light))
	await wait_physics_frames(3)
	assert_eq(
		_player.state_machine.current_state_name, &"Mounted", "a light hit keeps the rider on"
	)
	assert_true(_heavy_hit(_player.hurtbox))
	await wait_physics_frames(3)
	assert_eq(_player.state_machine.current_state_name, &"KnockedOff")
	assert_null(_cat.rider, "the saddle is empty")
	assert_eq(_cat.state_machine.current_state_name, &"Idle")
	assert_gt(_player.velocity.length(), 1.0, "the rider is flung")
	await wait_seconds(_cat.stats.knock_off_stagger + 0.4)
	assert_eq(_player.state_machine.current_state_name, &"Idle", "and recovers")
	assert_eq(_player.collision_layer, 2)


func test_heavy_hit_on_the_cat_also_knocks_the_rider_off() -> void:
	await _setup(Vector3(1.2, 0, 0))
	await _mount_up()
	assert_true(_heavy_hit(_cat.hurtbox))
	await wait_physics_frames(3)
	assert_eq(_player.state_machine.current_state_name, &"KnockedOff")
	assert_null(_cat.rider)


func test_mount_flees_at_zero_health_and_returns_after_the_cooldown() -> void:
	await _setup(Vector3(1.2, 0, 0))
	await _mount_up()
	_cat.stats = _cat.stats.duplicate() as MountStats
	_cat.stats.flee_cooldown = 1.5
	_cat.stats.flee_distance = 5.0
	var health_events: Array[float] = []
	EventBus.mount_health_changed.connect(
		func(current: float, _max: float) -> void: health_events.append(current)
	)
	var returned: Array[bool] = []
	_cat.returned.connect(func() -> void: returned.append(true))
	var start: Vector3 = _cat.global_position
	assert_true(_cat.hurtbox.receive_hit(_cat.health.max_health + 1.0))
	await wait_physics_frames(3)
	assert_eq(_cat.state_machine.current_state_name, &"Flee")
	assert_eq(_player.state_machine.current_state_name, &"KnockedOff", "the rider is thrown")
	assert_null(_cat.rider)
	assert_true(health_events.has(0.0), "the HUD bar saw the cat reach zero")
	await wait_seconds(1.0)
	assert_gt(_cat.global_position.distance_to(start), 3.0, "the cat ran off")
	assert_false(_cat.hurtbox.receive_hit(10.0), "a fleeing cat cannot be hurt")
	await wait_seconds(1.2)
	assert_eq(returned.size(), 1, "the cat came back")
	assert_eq(_cat.health.current, _cat.health.max_health, "with full health")
	assert_eq(_cat.state_machine.current_state_name, &"Called")
	await wait_seconds(3.0)
	assert_lt(
		_cat.global_position.distance_to(_player.global_position), 2.5, "and ran to the rider"
	)


func test_mount_health_changes_reach_the_event_bus() -> void:
	await _setup(Vector3(1.2, 0, 0))
	var seen: Array[Vector2] = []
	EventBus.mount_health_changed.connect(
		func(current: float, maximum: float) -> void: seen.append(Vector2(current, maximum))
	)
	_cat.hurtbox.receive_hit(20.0)
	assert_eq(seen.back(), Vector2(_cat.health.max_health - 20.0, _cat.health.max_health))


func test_cat_ignores_call_while_ridden() -> void:
	await _setup(Vector3(1.2, 0, 0))
	await _mount_up()
	assert_false(_cat.call_to(_player))
