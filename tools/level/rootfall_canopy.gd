class_name RootfallCanopy
extends RefCounted
## Shadow-only canopy slabs for Rootfall Hollow, with holes where the sun beams should land.

## Direction the sun's light travels (shared with the builder's DirectionalLight3D).
const SUN_DIRECTION := Vector3(-0.12, -0.95, 0.25)


## Adds the `CanopyOccluders` MultiMesh under `level` (direction maths: SUN_DIRECTION).
static func add_to(level: Node3D) -> void:
	var direction: Vector3 = SUN_DIRECTION.normalized()
	var travel: float = RootfallLayout.CANOPY_HEIGHT / -direction.y
	var shift := Vector2(direction.x, direction.z) * travel
	var targets: Array[Vector2] = [
		Vector2(0.0, -2.0),
		Vector2(0.0, -305.0),
		Vector2(-9.0, -297.0),
		Vector2(9.0, -312.0),
	]
	for index: int in RootfallLayout.GLADE_INDICES:
		targets.append(RootfallLayout.PATH_XZ[index])
	targets.append(RootfallLayout.PATH_XZ[4] + Vector2(8.0, 0.0))
	targets.append(RootfallLayout.PATH_XZ[8] + Vector2(-6.0, 4.0))
	var holes: Array[Vector2] = []
	for target: Vector2 in targets:
		holes.append(target - shift)
	var cell: float = RootfallLayout.CANOPY_CELL
	var rect: Rect2 = RootfallLayout.GROUND_RECT.grow(60.0)
	var transforms: Array[Transform3D] = []
	var x: float = rect.position.x
	while x < rect.end.x:
		var z: float = rect.position.y
		while z < rect.end.y:
			var centre := Vector2(x + cell * 0.5, z + cell * 0.5)
			if not _in_hole(centre, holes, cell * 0.62):
				transforms.append(
					Transform3D(
						Basis.IDENTITY, Vector3(centre.x, RootfallLayout.CANOPY_HEIGHT, centre.y)
					)
				)
			z += cell
		x += cell
	var slab := BoxMesh.new()
	slab.size = Vector3(cell, 2.5, cell)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = slab
	multimesh.instance_count = transforms.size()
	for index: int in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var canopy := MultiMeshInstance3D.new()
	canopy.name = "CanopyOccluders"
	canopy.multimesh = multimesh
	canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	level.add_child(canopy)
	canopy.owner = level


static func _in_hole(centre: Vector2, holes: Array[Vector2], radius: float) -> bool:
	for hole: Vector2 in holes:
		if centre.distance_to(hole) < radius * 1.5:
			return true
	return false
