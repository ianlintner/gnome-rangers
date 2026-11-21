class_name FoliageScatter
extends Node3D
## Scatters one prop as chunked MultiMesh instances over a ground rectangle.
##
## Instances are bucketed into square chunks, each its own [MultiMeshInstance3D], so the
## renderer can frustum-cull a chunk and apply `visibility_range_end` per chunk (with a fade).
## Mesh LODs come from the glTF import (Godot generates them), which also apply inside a
## MultiMesh. Placement is deterministic for a given `seed_value`, so captures are repeatable.
## With `wind` on, the prop's material is swapped for the shared `fx/shaders/foliage_wind`.

const WIND_SHADER: Shader = preload("res://fx/shaders/foliage_wind.gdshader")

## The prop scene; its first [MeshInstance3D] supplies the mesh.
@export var source_scene: PackedScene
## Number of instances attempted across the whole rectangle (rejected spots are dropped).
@export var count: int = 300
## Ground rectangle (x, z, width, depth) the instances are spread over.
@export var area: Rect2 = Rect2(-90.0, -350.0, 180.0, 400.0)
## Chunk edge length in metres.
@export var chunk_size: float = 40.0
## Largest extent in metres after scaling; random +-`scale_jitter` is applied on top.
@export var target_size: float = 1.2
@export_range(0.0, 0.5) var scale_jitter: float = 0.25
@export var seed_value: int = 1
## Distance at which a chunk stops rendering (with a fade margin).
@export var visibility_end: float = 70.0
@export var cast_shadows: bool = false
## Swap the material for the shared wind shader.
@export var wind: bool = true
## Keep this far from the approach path centreline when `keep_off_path` is set.
@export var keep_off_path: bool = true
@export var path_clearance: float = RootfallLayout.PATH_HALF_WIDTH
## Keep out of the open glades and the arena floor (cover is placed by hand there).
@export var keep_out_of_arena: bool = true

var _mesh: Mesh = null
var _base_scale: float = 1.0
var _foot_offset: float = 0.0
var _sway_height: float = 1.0
var _spots: Array[Vector2] = []


## World XZ position of every placed instance (the headless renderer cannot read MultiMesh back).
func placements() -> Array[Vector2]:
	return _spots


func _ready() -> void:
	if source_scene == null or not _extract_mesh():
		return
	_build_chunks()


## Number of chunk instances created (for tests and the perf log).
func chunk_count() -> int:
	return get_child_count()


## Total number of scattered instances across all chunks.
func instance_count() -> int:
	var total: int = 0
	for child: Node in get_children():
		var chunk := child as MultiMeshInstance3D
		if chunk != null:
			total += chunk.multimesh.instance_count
	return total


func _extract_mesh() -> bool:
	var instance: Node = source_scene.instantiate()
	var mesh_node: MeshInstance3D = _first_mesh(instance)
	if mesh_node == null:
		instance.free()
		push_error("FoliageScatter: %s has no MeshInstance3D" % source_scene.resource_path)
		return false
	var source: Mesh = mesh_node.mesh
	# The instance is not in the tree yet, so use local transforms (glTF roots are identity).
	var box: AABB = mesh_node.transform * source.get_aabb()
	var largest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	_base_scale = target_size / maxf(largest, 0.001)
	_foot_offset = -box.position.y * _base_scale
	_sway_height = box.size.y * _base_scale
	_mesh = source.duplicate() as Mesh
	for surface: int in range(_mesh.get_surface_count()):
		var material: Material = mesh_node.get_active_material(surface)
		_mesh.surface_set_material(surface, _wind_material(material) if wind else material)
	instance.free()
	return true


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _first_mesh(child)
		if found != null:
			return found
	return null


func _wind_material(source: Material) -> Material:
	var standard := source as BaseMaterial3D
	if standard == null:
		return source
	var material := ShaderMaterial.new()
	material.shader = WIND_SHADER
	material.set_shader_parameter(&"albedo_texture", standard.albedo_texture)
	material.set_shader_parameter(&"albedo_tint", standard.albedo_color)
	if standard.normal_texture != null:
		material.set_shader_parameter(&"normal_texture", standard.normal_texture)
	if standard.roughness_texture != null:
		material.set_shader_parameter(&"orm_texture", standard.roughness_texture)
	material.set_shader_parameter(&"sway_height", maxf(_sway_height, 0.1))
	return material


func _build_chunks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var buckets: Dictionary = {}
	for _i: int in range(count):
		var spot := Vector2(
			rng.randf_range(area.position.x, area.end.x),
			rng.randf_range(area.position.y, area.end.y)
		)
		var jitter: float = rng.randf_range(1.0 - scale_jitter, 1.0 + scale_jitter)
		var yaw: float = rng.randf_range(0.0, TAU)
		if _rejected(spot):
			continue
		_spots.append(spot)
		var key := Vector2i(floori(spot.x / chunk_size), floori(spot.y / chunk_size))
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append([spot, jitter, yaw])
	for key: Vector2i in buckets:
		_add_chunk(key, buckets[key] as Array)


func _rejected(spot: Vector2) -> bool:
	if keep_off_path and RootfallLayout.distance_to_path(spot) < path_clearance:
		return true
	if keep_out_of_arena and (RootfallLayout.in_arena(spot, 2.0) or RootfallLayout.in_glade(spot)):
		return true
	return false


func _add_chunk(key: Vector2i, entries: Array) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _mesh
	multimesh.instance_count = entries.size()
	var centre := Vector3((key.x + 0.5) * chunk_size, 0.0, (key.y + 0.5) * chunk_size)
	for index: int in range(entries.size()):
		var entry: Array = entries[index]
		var spot: Vector2 = entry[0]
		var scale_factor: float = _base_scale * float(entry[1])
		var orientation := Basis(Vector3.UP, float(entry[2])).scaled(Vector3.ONE * scale_factor)
		var origin := Vector3(spot.x, _foot_offset * float(entry[1]), spot.y) - centre
		multimesh.set_instance_transform(index, Transform3D(orientation, origin))
	var node := MultiMeshInstance3D.new()
	node.name = "Chunk_%d_%d" % [key.x, key.y]
	node.multimesh = multimesh
	node.position = centre
	node.visibility_range_end = visibility_end
	node.visibility_range_end_margin = 6.0
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	node.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if cast_shadows
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	add_child(node)
