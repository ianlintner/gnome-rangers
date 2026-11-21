extends GutTest
## Rootfall Hollow: loads, has a baked navmesh, and the Mushroom Ring checkpoint works.

const LEVEL: PackedScene = preload("res://levels/rootfall_hollow/rootfall_hollow.tscn")
const CHECKPOINT: PackedScene = preload("res://levels/checkpoint/checkpoint.tscn")
const PROBE: Script = preload("res://tests/support/refill_probe.gd")

var _level: Node3D = null


func before_each() -> void:
	GameState.clear()


func after_each() -> void:
	GameState.clear()


func _load_level() -> Node3D:
	_level = LEVEL.instantiate() as Node3D
	add_child_autofree(_level)
	# The navigation server syncs the region into its map asynchronously; wait until the baked
	# ground answers (bounded, so a missing navmesh fails instead of hanging).
	var region: NavigationRegion3D = _level.get_node("NavigationRegion3D")
	var map: RID = region.get_navigation_map()
	for _frame: int in range(120):
		await get_tree().physics_frame
		# Queries before the first sync log an error, so gate on the iteration id first.
		if NavigationServer3D.map_get_iteration_id(map) == 0:
			continue
		var probe: Vector3 = NavigationServer3D.map_get_closest_point(map, Vector3(6.0, 0.0, -28.0))
		if probe != Vector3.ZERO:
			break
	return _level


func test_level_loads_with_expected_landmarks() -> void:
	var level: Node3D = await _load_level()
	assert_not_null(level)
	for landmark: String in ["PlayerStart", "ArenaCenter", "BossSpawn", "Checkpoint", "FogGate"]:
		assert_not_null(level.get_node_or_null(landmark), landmark)
	assert_not_null(level.get_node_or_null("AmbientLoop"))
	assert_true(level.get_node("WorldEnvironment").environment.volumetric_fog_enabled)


func test_level_publishes_spawn_transform() -> void:
	var level: Node3D = await _load_level()
	var start: Node3D = level.get_node("PlayerStart")
	assert_eq(GameState.spawn_transform.origin, start.global_transform.origin)


func test_navmesh_is_baked_and_connects_checkpoint_to_arena_centre() -> void:
	var level: Node3D = await _load_level()
	var region: NavigationRegion3D = level.get_node("NavigationRegion3D")
	assert_gt(region.navigation_mesh.get_polygon_count(), 100, "baked polygons")
	var map: RID = region.get_navigation_map()
	NavigationServer3D.map_force_update(map)
	var from: Vector3 = (level.get_node("Checkpoint") as Node3D).global_position
	var to: Vector3 = (level.get_node("ArenaCenter") as Node3D).global_position
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, from, to, true)
	assert_gt(path.size(), 1, "a path exists")
	assert_lt(path[path.size() - 1].distance_to(to), 1.5, "path ends at the arena centre")
	var length: float = 0.0
	for i: int in range(path.size() - 1):
		length += path[i].distance_to(path[i + 1])
	assert_gt(length, RootfallLayout.path_length() * 0.9, "the path follows the approach")


func test_arena_is_walled_except_for_the_gate() -> void:
	var level: Node3D = await _load_level()
	var map: RID = (level.get_node("NavigationRegion3D") as NavigationRegion3D).get_navigation_map()
	# Open ground exists just outside the far side of the ring, but the only way out is the
	# fog gate on the opposite side, so the route must detour around the whole ring.
	var outside: Vector3 = RootfallLayout.ARENA_CENTER + Vector3(0.0, 0.0, -36.0)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		map, RootfallLayout.ARENA_CENTER, outside, true
	)
	var length: float = 0.0
	for i: int in range(path.size() - 1):
		length += path[i].distance_to(path[i + 1])
	assert_gt(length, 80.0, "no shortcut through the arena wall (direct distance is 36 m)")


func test_arena_wall_colliders_block_passage_at_player_height() -> void:
	var level: Node3D = await _load_level()
	var wall: StaticBody3D = level.get_node("ArenaWall")
	var radius: float = RootfallLayout.ARENA_RADIUS + 1.6
	assert_gt(wall.get_child_count(), 20, "wall segments exist")
	for shape_node: CollisionShape3D in wall.get_children():
		var box: BoxShape3D = shape_node.shape
		var local_origin: Vector3 = shape_node.global_position - RootfallLayout.ARENA_CENTER
		var radial := Vector3(local_origin.x, 0.0, local_origin.z).normalized()
		assert_almost_eq(
			Vector2(local_origin.x, local_origin.z).length(), radius, 0.01, "on the perimeter"
		)
		# Long axis runs along the perimeter, not radially.
		var long_axis: Vector3 = shape_node.global_transform.basis.x.normalized()
		assert_almost_eq(absf(long_axis.dot(radial)), 0.0, 0.01, "tangential long axis")
		# A ground-level actor at the same bearing is inside the collider's vertical extent.
		var probe: Vector3 = RootfallLayout.ARENA_CENTER + radial * radius + Vector3(0.0, 1.0, 0.0)
		var local: Vector3 = shape_node.global_transform.affine_inverse() * probe
		assert_lt(absf(local.x), box.size.x * 0.5, "covers the bearing")
		assert_lt(absf(local.y), box.size.y * 0.5, "reaches player height")
		assert_lt(absf(local.z), box.size.z * 0.5, "spans the wall thickness")


func test_ambient_loop_autoplays_and_loops() -> void:
	var level: Node3D = await _load_level()
	var ambient: AudioStreamPlayer = level.get_node("AmbientLoop")
	assert_true(ambient.autoplay)
	assert_true(ambient.playing, "autoplay survived _ready")
	var stream := ambient.stream as AudioStreamWAV
	assert_not_null(stream)
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "loop configured at import")


func test_quality_tier_round_trips_high_dev_high() -> void:
	var viewport: Viewport = get_viewport()
	viewport.msaa_3d = Viewport.MSAA_2X
	var level: RootfallHollow = await _load_level() as RootfallHollow
	var sun: DirectionalLight3D = level.get_node("Sun")
	var high_environment: Environment = level.get_node("WorldEnvironment").environment
	var high_distance: float = sun.directional_shadow_max_distance
	assert_true(high_environment.sdfgi_enabled)
	assert_eq(high_environment.volumetric_fog_length, 80.0, "initial HIGH fog length")

	level.apply_quality_tier(RootfallHollow.QualityTier.DEV)
	var dev_environment: Environment = level.get_node("WorldEnvironment").environment
	assert_false(dev_environment.sdfgi_enabled)
	assert_false(dev_environment.ssil_enabled)
	assert_lt(sun.directional_shadow_max_distance, high_distance)
	assert_eq(viewport.msaa_3d, Viewport.MSAA_DISABLED)

	level.apply_quality_tier(RootfallHollow.QualityTier.HIGH)
	var restored: Environment = level.get_node("WorldEnvironment").environment
	assert_eq(restored.sdfgi_enabled, high_environment.sdfgi_enabled)
	assert_eq(restored.ssil_enabled, high_environment.ssil_enabled)
	assert_eq(restored.ssao_enabled, high_environment.ssao_enabled)
	assert_eq(restored.volumetric_fog_length, 80.0, "restored HIGH fog length")
	assert_eq(restored.volumetric_fog_detail_spread, high_environment.volumetric_fog_detail_spread)
	assert_eq(sun.directional_shadow_max_distance, high_distance)
	assert_eq(viewport.msaa_3d, Viewport.MSAA_2X, "HIGH restores MSAA")

	# DEV overrides must not outlive the level.
	level.apply_quality_tier(RootfallHollow.QualityTier.DEV)
	level.get_parent().remove_child(level)
	assert_eq(viewport.msaa_3d, Viewport.MSAA_2X, "level unload restores MSAA")
	level.free()
	_level = null
	viewport.msaa_3d = Viewport.MSAA_DISABLED


func test_checkpoint_rest_sets_respawn_refills_and_resets_world() -> void:
	var checkpoint := CHECKPOINT.instantiate() as Checkpoint
	add_child_autofree(checkpoint)
	checkpoint.global_position = Vector3(12.0, 0.0, -40.0)
	var actor := Node3D.new()
	for component: String in ["HealthComponent", "StaminaComponent"]:
		var probe := Node.new()
		probe.name = component
		probe.set_script(PROBE)
		actor.add_child(probe)
	add_child_autofree(actor)
	watch_signals(EventBus)
	watch_signals(GameState)
	var token_before: int = GameState.reset_token

	var interactable: Interactable = checkpoint.get_node("Interactable")
	assert_true(interactable.interact(actor), "interaction accepted")

	assert_eq(GameState.checkpoint, checkpoint)
	assert_eq(GameState.respawn_transform_for_player().origin, Vector3(12.0, 0.0, -40.0))
	assert_eq(GameState.reset_token, token_before + 1, "world reset requested")
	assert_signal_emitted(EventBus, "checkpoint_rested")
	assert_signal_emitted(GameState, "run_reset")
	for component: String in ["HealthComponent", "StaminaComponent"]:
		assert_eq(actor.get_node(component).refilled, 1, "%s refilled" % component)


func test_resting_in_the_level_checkpoint_becomes_the_respawn_point() -> void:
	var level: Node3D = await _load_level()
	var checkpoint: Checkpoint = level.get_node("Checkpoint")
	checkpoint.rest(null)
	assert_eq(GameState.checkpoint, checkpoint)
	assert_eq(GameState.respawn_transform_for_player().origin, checkpoint.global_position)


func _player_like_body() -> Node3D:
	var body := Node3D.new()
	var health := HealthComponent.new()
	health.name = "Health"
	body.add_child(health)
	health.reset()
	var poise := PoiseComponent.new()
	poise.name = "Poise"
	body.add_child(poise)
	poise.reset()
	add_child_autofree(body)
	return body


func test_fog_gate_announces_the_boss_once_until_reset() -> void:
	var level: Node3D = await _load_level()
	var gate: FogGate = level.get_node("FogGate") as FogGate
	var body := _player_like_body()
	watch_signals(EventBus)
	gate._on_body_entered(body)
	gate._on_body_entered(body)
	assert_signal_emit_count(EventBus, "boss_engaged", 1)
	var payload: Object = get_signal_parameters(EventBus, "boss_engaged", 0)[0] as Object
	assert_not_null(payload, "the engaged boss is never null")
	GameState.reset_run()
	gate._on_body_entered(body)
	assert_signal_emit_count(EventBus, "boss_engaged", 2)


func test_fog_gate_ignores_non_player_bodies() -> void:
	var level: Node3D = await _load_level()
	var gate: FogGate = level.get_node("FogGate") as FogGate
	var scenery := Node3D.new()
	add_child_autofree(scenery)
	watch_signals(EventBus)
	gate._on_body_entered(scenery)
	assert_signal_emit_count(EventBus, "boss_engaged", 0)
	assert_false(gate.is_sealed(), "a stray body does not latch the gate")
