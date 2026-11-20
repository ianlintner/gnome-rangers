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


func test_fog_gate_announces_the_boss_once_until_reset() -> void:
	var level: Node3D = await _load_level()
	var gate: FogGateTrigger = level.get_node("FogGate")
	var body := Node3D.new()
	add_child_autofree(body)
	watch_signals(EventBus)
	gate._on_body_entered(body)
	gate._on_body_entered(body)
	assert_signal_emit_count(EventBus, "boss_engaged", 1)
	GameState.reset_run()
	gate._on_body_entered(body)
	assert_signal_emit_count(EventBus, "boss_engaged", 2)
