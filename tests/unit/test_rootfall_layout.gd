extends GutTest
## RootfallLayout geometry helpers (the single definition of the level map).


func test_path_is_about_a_minute_on_foot() -> void:
	var length: float = RootfallLayout.path_length()
	# 60-90 s of travel between a 3.5 m/s walk and a 5.5 m/s run.
	assert_between(length / 5.5, 45.0, 75.0, "run time (s)")
	assert_between(length / 3.5, 70.0, 110.0, "walk time (s)")


func test_distance_to_path_is_zero_on_a_waypoint() -> void:
	assert_almost_eq(RootfallLayout.distance_to_path(RootfallLayout.PATH_XZ[3]), 0.0, 0.001)


func test_distance_to_path_measures_to_the_nearest_segment() -> void:
	var first: Vector2 = RootfallLayout.PATH_XZ[0]
	var off: Vector2 = first + Vector2(-7.0, 0.0)
	assert_almost_eq(RootfallLayout.distance_to_path(off), 7.0, 0.5)


func test_arena_and_glade_membership() -> void:
	var centre := Vector2(RootfallLayout.ARENA_CENTER.x, RootfallLayout.ARENA_CENTER.z)
	assert_true(RootfallLayout.in_arena(centre))
	assert_false(RootfallLayout.in_arena(centre + Vector2(RootfallLayout.ARENA_RADIUS + 5.0, 0.0)))
	assert_true(RootfallLayout.in_glade(RootfallLayout.PATH_XZ[RootfallLayout.GLADE_INDICES[0]]))
	assert_false(RootfallLayout.in_glade(RootfallLayout.PATH_XZ[0]))


func test_gate_sits_on_the_arena_rim() -> void:
	var gate := Vector2(RootfallLayout.GATE_POS.x, RootfallLayout.GATE_POS.z)
	var centre := Vector2(RootfallLayout.ARENA_CENTER.x, RootfallLayout.ARENA_CENTER.z)
	assert_between(gate.distance_to(centre), RootfallLayout.ARENA_RADIUS, 28.0)
