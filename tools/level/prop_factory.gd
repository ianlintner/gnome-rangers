class_name PropFactory
extends RefCounted
## Builds scaled, grounded, collidable prop nodes from imported Meshy GLBs.
##
## Meshy meshes arrive normalised (largest extent about 1.9) with an arbitrary pivot, so each
## prop is sized here at gnome scale (1 unit = 1 m, gnome about 1 m): scaled to a real size,
## centred on x/z, with its underside at y = 0. Collision is generated at the final size, so
## bodies are never scaled (Jolt prefers that).

enum Collision { NONE, CYLINDER, CONVEX, TRIMESH }

## Per-prop sizing. `size` is metres of the measured `axis` ("y" = height, "max" = the largest
## extent); `squash` narrows x/z relative to y (a Meshy trunk comes out far too fat for its
## height, and bark reads naturally when stretched vertically).
const SPECS: Dictionary = {
	"trunk_giant_a": {"axis": "y", "size": 36.0, "squash": 0.4},
	"trunk_giant_b": {"axis": "y", "size": 36.0, "squash": 0.5},
	"root_arch": {"axis": "max", "size": 9.0, "squash": 1.0},
	"fallen_log": {"axis": "max", "size": 8.0, "squash": 1.0},
	"mushroom_ring": {"axis": "max", "size": 3.4, "squash": 1.0},
	"rock_mossy": {"axis": "max", "size": 2.2, "squash": 1.0},
	"fern_cluster": {"axis": "max", "size": 2.2, "squash": 1.0},
}

var _meshes: Dictionary = {}
var _scenes: Dictionary = {}
## Collision shapes shared between bodies with the same prop, size and sink (keeps the saved
## scene small: a trimesh is saved once instead of once per instance).
var _shapes: Dictionary = {}


## Creates a StaticBody3D named `node_name` holding the prop `prop` at `position`.
## `scale_multiplier` scales the nominal size; `sink` buries the base by that many metres.
func make_body(
	prop: String,
	node_name: String,
	position: Vector3,
	yaw: float,
	collision: Collision,
	scale_multiplier: float = 1.0,
	sink: float = 0.0,
) -> StaticBody3D:
	var mesh: Mesh = _mesh_of(prop)
	var raw: AABB = mesh.get_aabb()
	var scale_vector: Vector3 = _scale_of(prop, scale_multiplier, raw)
	var centre := Vector3(
		raw.position.x + raw.size.x * 0.5, raw.position.y, raw.position.z + raw.size.z * 0.5
	)
	var model_transform := Transform3D(
		Basis.from_scale(scale_vector), Vector3(0.0, -sink, 0.0) - centre * scale_vector
	)
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.rotation.y = yaw
	var model := _scene_of(prop).instantiate() as Node3D
	model.name = "Model"
	model.transform = model_transform
	body.add_child(model)
	var shape_key: String = "%s|%d|%.2f|%.2f" % [prop, collision, scale_multiplier, sink]
	if not _shapes.has(shape_key):
		_shapes[shape_key] = _shape_for(mesh, collision, model_transform)
	var shape: Shape3D = _shapes[shape_key]
	if shape != null:
		var holder := CollisionShape3D.new()
		holder.name = "Collision"
		holder.shape = shape
		if collision == Collision.CYLINDER:
			var box: AABB = model_transform * mesh.get_aabb()
			holder.position = Vector3(0.0, box.position.y + box.size.y * 0.5, 0.0)
		body.add_child(holder)
	body.set_meta(&"size", raw.size * scale_vector)
	return body


## Footprint radius (metres) a placed prop occupies, used to keep clear of the path.
func footprint_radius(prop: String, scale_multiplier: float = 1.0) -> float:
	var raw: AABB = _mesh_of(prop).get_aabb()
	var scale_vector: Vector3 = _scale_of(prop, scale_multiplier, raw)
	return maxf(raw.size.x * scale_vector.x, raw.size.z * scale_vector.z) * 0.5


func _scale_of(prop: String, scale_multiplier: float, raw: AABB) -> Vector3:
	var spec: Dictionary = SPECS[prop]
	var measured: float = raw.size.y
	if spec["axis"] == "max":
		measured = maxf(raw.size.x, maxf(raw.size.y, raw.size.z))
	var factor: float = float(spec["size"]) * scale_multiplier / maxf(measured, 0.001)
	var squash: float = float(spec["squash"])
	return Vector3(factor * squash, factor, factor * squash)


func _scene_of(prop: String) -> PackedScene:
	if not _scenes.has(prop):
		_scenes[prop] = load("res://assets/props/%s/%s.glb" % [prop, prop])
	return _scenes[prop] as PackedScene


func _mesh_of(prop: String) -> Mesh:
	if not _meshes.has(prop):
		var instance: Node = _scene_of(prop).instantiate()
		_meshes[prop] = _first_mesh(instance).mesh
		instance.free()
	return _meshes[prop] as Mesh


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _first_mesh(child)
		if found != null:
			return found
	return null


func _shape_for(mesh: Mesh, collision: Collision, model_transform: Transform3D) -> Shape3D:
	match collision:
		Collision.CYLINDER:
			var box: AABB = model_transform * mesh.get_aabb()
			var cylinder := CylinderShape3D.new()
			cylinder.radius = 0.42 * minf(box.size.x, box.size.z)
			cylinder.height = box.size.y
			return cylinder
		Collision.CONVEX:
			var convex := mesh.create_convex_shape(true, true) as ConvexPolygonShape3D
			var points := PackedVector3Array()
			for point: Vector3 in convex.points:
				points.append(model_transform * point)
			convex.points = points
			return convex
		Collision.TRIMESH:
			var trimesh := mesh.create_trimesh_shape() as ConcavePolygonShape3D
			var faces := PackedVector3Array()
			for vertex: Vector3 in trimesh.get_faces():
				faces.append(model_transform * vertex)
			trimesh.set_faces(faces)
			return trimesh
	return null
