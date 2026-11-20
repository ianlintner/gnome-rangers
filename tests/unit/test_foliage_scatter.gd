extends GutTest
## FoliageScatter: deterministic, chunked, and keeps the walking corridor clear.

const FERN: PackedScene = preload("res://assets/props/fern_cluster/fern_cluster.glb")


func _make(seed_value: int) -> FoliageScatter:
	var scatter := FoliageScatter.new()
	scatter.source_scene = FERN
	scatter.count = 400
	scatter.seed_value = seed_value
	scatter.area = RootfallLayout.GROUND_RECT
	add_child_autofree(scatter)
	return scatter


func test_scatter_builds_chunks_with_visibility_ranges() -> void:
	var scatter: FoliageScatter = _make(1)
	assert_gt(scatter.chunk_count(), 3, "several chunks")
	assert_gt(scatter.instance_count(), 100)
	var chunk := scatter.get_child(0) as MultiMeshInstance3D
	assert_gt(chunk.visibility_range_end, 0.0)
	assert_eq(chunk.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_same_seed_gives_same_field() -> void:
	assert_eq(_make(5).instance_count(), _make(5).instance_count())
	assert_ne(_make(5).instance_count(), _make(6).instance_count())


func test_nothing_grows_on_the_path_or_in_the_arena() -> void:
	var scatter: FoliageScatter = _make(2)
	assert_eq(scatter.placements().size(), scatter.instance_count())
	for spot: Vector2 in scatter.placements():
		assert_gte(RootfallLayout.distance_to_path(spot), scatter.path_clearance - 0.01)
		assert_false(RootfallLayout.in_arena(spot))
		assert_false(RootfallLayout.in_glade(spot))


func test_wind_shader_replaces_the_material() -> void:
	var scatter: FoliageScatter = _make(3)
	var chunk := scatter.get_child(0) as MultiMeshInstance3D
	var material: Material = chunk.multimesh.mesh.surface_get_material(0)
	assert_true(material is ShaderMaterial)
