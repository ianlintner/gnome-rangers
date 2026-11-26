class_name MountWorld
extends RefCounted
## Builders for mount tests: a floor with a navigation mesh (optionally with a wall in the
## middle that paths must go around), and the real cat scene.

const CAT_SCENE: PackedScene = preload("res://actors/mount/cat_mount.tscn")
const DUMMY_SCENE: PackedScene = preload("res://actors/enemies/training_dummy/training_dummy.tscn")

const HALF_SIZE: float = 30.0
const WALL_HALF_WIDTH: float = 1.0
const WALL_HALF_LENGTH: float = 6.5


## A navigation region over a flat floor. With `wall`, a wall along Z at x = 0 is both a
## collider and a hole in the navigation mesh, so paths from one side to the other bend.
static func make_nav_floor(wall: bool = false) -> Node3D:
	var root := Node3D.new()
	root.add_child(PlayerWorld.make_floor())
	var xs: Array[float] = [-HALF_SIZE, -WALL_HALF_WIDTH, WALL_HALF_WIDTH, HALF_SIZE]
	var zs: Array[float] = [-HALF_SIZE, -WALL_HALF_LENGTH, WALL_HALF_LENGTH, HALF_SIZE]
	if not wall:
		xs = [-HALF_SIZE, HALF_SIZE]
		zs = [-HALF_SIZE, HALF_SIZE]
	var mesh := NavigationMesh.new()
	var vertices := PackedVector3Array()
	for z: float in zs:
		for x: float in xs:
			vertices.append(Vector3(x, 0.0, z))
	mesh.vertices = vertices
	var columns: int = xs.size()
	for row: int in zs.size() - 1:
		for column: int in columns - 1:
			if wall and row == 1 and column == 1:
				continue  # the hole under the wall
			var a: int = row * columns + column
			# Clockwise seen from above, as the navigation server expects.
			mesh.add_polygon(PackedInt32Array([a, a + 1, a + columns + 1, a + columns]))
	var region := NavigationRegion3D.new()
	region.navigation_mesh = mesh
	root.add_child(region)
	if wall:
		root.add_child(PlayerWorld.make_box(Vector3(2.0, 3.0, 13.0), Vector3(0.0, 1.5, 0.0)))
	return root


## Waits (in physics frames) until the navigation map has synchronised the region.
static func wait_for_navigation(test: GutTest, region_root: Node3D) -> void:
	var regions: Array[Node] = region_root.find_children("*", "NavigationRegion3D", true, false)
	var region: NavigationRegion3D = regions[0] as NavigationRegion3D
	var map: RID = region.get_navigation_map()
	for _frame: int in 30:
		await test.wait_physics_frames(1)
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			return


static func make_cat(position: Vector3 = Vector3.ZERO) -> CatMount:
	var cat := CAT_SCENE.instantiate() as CatMount
	cat.position = position
	return cat
