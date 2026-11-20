class_name RootfallProps
extends RefCounted
## Deterministic hand-authored-by-seed prop placement for Rootfall Hollow.
##
## Called by `build_rootfall.gd` while generating the scene. Everything is derived from
## [RootfallLayout] plus a fixed seed, so rebuilding the level reproduces the same forest.

const SEED: int = 8081
## Extra metres kept between a prop footprint and the walking corridor.
const PATH_MARGIN: float = 2.0

var _factory: PropFactory
var _rng := RandomNumberGenerator.new()
var _placed: Array[Vector3] = []  # x, z, footprint radius of everything placed so far
var _owner_root: Node = null


func _init(factory: PropFactory) -> void:
	_factory = factory
	_rng.seed = SEED


## Builds all prop groups under `parent`; `owner_root` becomes the owner of every created node.
func populate(parent: Node3D, owner_root: Node) -> void:
	_owner_root = owner_root
	_place_arena_frame(_group(parent, "ArenaFrame"))
	_place_arena_cover(_group(parent, "ArenaCover"))
	_place_path_trunks(_group(parent, "PathTrunks"))
	_place_scatter(_group(parent, "PathProps"))


func _group(parent: Node3D, group_name: String) -> Node3D:
	var group := Node3D.new()
	group.name = group_name
	parent.add_child(group)
	group.owner = _owner_root
	return group


func _add(
	group: Node3D,
	prop: String,
	position: Vector3,
	yaw: float,
	collision: PropFactory.Collision,
	scale_multiplier: float = 1.0,
	sink: float = 0.0,
) -> void:
	var node_name: String = "%s_%d" % [prop, group.get_child_count()]
	var body: StaticBody3D = _factory.make_body(
		prop, node_name, position, yaw, collision, scale_multiplier, sink
	)
	group.add_child(body)
	body.owner = _owner_root
	for child: Node in body.get_children():
		child.owner = _owner_root
	_placed.append(
		Vector3(position.x, position.z, _factory.footprint_radius(prop, scale_multiplier))
	)


## Ring of colossal trunks with root arches between them, open at the fog gate.
func _place_arena_frame(group: Node3D) -> void:
	var centre: Vector3 = RootfallLayout.ARENA_CENTER
	var count: int = RootfallLayout.TRUNK_RING_COUNT
	# Trunks are ~11 m wide: keep them clear of the gate opening plus their own half-width.
	var trunk_clear: float = (
		(RootfallLayout.GATE_HALF_WIDTH + 7.0) / RootfallLayout.TRUNK_RING_RADIUS
	)
	var arch_clear: float = (RootfallLayout.GATE_HALF_WIDTH + 2.0) / 21.2
	for i: int in range(count):
		var theta: float = (float(i) + 0.5) / float(count) * TAU
		var wrapped: float = absf(wrapf(theta, -PI, PI))
		var variant: String = "trunk_giant_a" if i % 2 == 0 else "trunk_giant_b"
		var trunk_radius: float = RootfallLayout.TRUNK_RING_RADIUS
		var at: Vector3 = centre + Vector3(sin(theta), 0.0, cos(theta)) * trunk_radius
		if wrapped > trunk_clear:
			_add(group, variant, at, theta + PI, PropFactory.Collision.CYLINDER, 1.0, 0.4)
		# Root wall between this trunk and the next: an arch hugging the inside of the ring.
		var mid: float = theta + PI / float(count)
		if absf(wrapf(mid, -PI, PI)) > arch_clear:
			var wall: Vector3 = centre + Vector3(sin(mid), 0.0, cos(mid)) * 21.2
			_add(group, "root_arch", wall, mid + PI / 2.0, PropFactory.Collision.TRIMESH, 1.5, 0.2)
	# The two flanking trunks that frame the fog gate.
	for side: float in [-1.0, 1.0]:
		var flank: Vector3 = RootfallLayout.GATE_POS + Vector3(side * 12.0, 0.0, -2.0)
		_add(
			group,
			"trunk_giant_a" if side < 0.0 else "trunk_giant_b",
			flank,
			0.0,
			PropFactory.Collision.CYLINDER,
			1.15,
			0.4
		)


## Roots and logs inside the arena that give the bow player partial cover.
func _place_arena_cover(group: Node3D) -> void:
	var centre: Vector3 = RootfallLayout.ARENA_CENTER
	for i: int in range(4):
		var theta: float = (float(i) + 0.5) / 4.0 * TAU + 0.35
		var at: Vector3 = centre + Vector3(sin(theta), 0.0, cos(theta)) * 11.0
		_add(group, "root_arch", at, theta, PropFactory.Collision.TRIMESH, 0.55, 0.15)
	for i: int in range(3):
		var theta: float = float(i) / 3.0 * TAU + 1.1
		var at: Vector3 = centre + Vector3(sin(theta), 0.0, cos(theta)) * 6.5
		_add(group, "fallen_log", at, theta + 0.6, PropFactory.Collision.CONVEX, 0.7, 0.1)
	for i: int in range(5):
		var theta: float = float(i) / 5.0 * TAU + 0.2
		var at: Vector3 = centre + Vector3(sin(theta), 0.0, cos(theta)) * 17.0
		_add(group, "rock_mossy", at, theta, PropFactory.Collision.CONVEX, 1.4)


## Extra colossal trunks flanking the approach, kept off the walking corridor and the glades.
func _place_path_trunks(group: Node3D) -> void:
	var attempts: int = 0
	var placed: int = 0
	var box: Rect2 = RootfallLayout.GROUND_RECT
	while placed < 26 and attempts < 4000:
		attempts += 1
		var spot := Vector2(
			_rng.randf_range(box.position.x + 6.0, box.end.x - 6.0),
			_rng.randf_range(RootfallLayout.GATE_POS.z + 14.0, box.end.y - 8.0)
		)
		var variant: String = "trunk_giant_a" if _rng.randf() < 0.5 else "trunk_giant_b"
		var radius: float = _factory.footprint_radius(variant, 1.0)
		if _blocked(spot, radius, 9.0):
			continue
		_add(
			group,
			variant,
			Vector3(spot.x, 0.0, spot.y),
			_rng.randf_range(0.0, TAU),
			PropFactory.Collision.CYLINDER,
			_rng.randf_range(0.8, 1.2),
			0.4
		)
		placed += 1


## Logs, rocks and low root arches dressing the path edges and glades.
func _place_scatter(group: Node3D) -> void:
	var plans: Array[Dictionary] = [
		{
			"prop": "fallen_log",
			"count": 7,
			"scale": [0.8, 1.3],
			"col": PropFactory.Collision.CONVEX
		},
		{
			"prop": "rock_mossy",
			"count": 34,
			"scale": [0.6, 1.8],
			"col": PropFactory.Collision.CONVEX
		},
		{
			"prop": "root_arch",
			"count": 6,
			"scale": [0.5, 0.8],
			"col": PropFactory.Collision.TRIMESH
		},
	]
	var box: Rect2 = RootfallLayout.GROUND_RECT
	for plan: Dictionary in plans:
		var prop: String = plan["prop"]
		var placed: int = 0
		var attempts: int = 0
		var scale_range: Array = plan["scale"]
		while placed < int(plan["count"]) and attempts < 3000:
			attempts += 1
			var spot := Vector2(
				_rng.randf_range(box.position.x + 4.0, box.end.x - 4.0),
				_rng.randf_range(RootfallLayout.GATE_POS.z + 10.0, box.end.y - 6.0)
			)
			var factor: float = snappedf(
				_rng.randf_range(float(scale_range[0]), float(scale_range[1])), 0.1
			)
			if _blocked(spot, _factory.footprint_radius(prop, factor), PATH_MARGIN):
				continue
			_add(
				group,
				prop,
				Vector3(spot.x, 0.0, spot.y),
				_rng.randf_range(0.0, TAU),
				plan["col"] as PropFactory.Collision,
				factor,
				0.1
			)
			placed += 1


## True when a footprint at `spot` would block the path, a glade, the arena or another prop.
func _blocked(spot: Vector2, radius: float, margin: float) -> bool:
	if RootfallLayout.distance_to_path(spot) < RootfallLayout.PATH_HALF_WIDTH + radius + margin:
		return true
	if RootfallLayout.in_glade(spot) or RootfallLayout.in_arena(spot, 28.0):
		return true
	if (
		spot.distance_to(Vector2(RootfallLayout.CHECKPOINT_POS.x, RootfallLayout.CHECKPOINT_POS.z))
		< 14.0 + radius
	):
		return true
	for other: Vector3 in _placed:
		if spot.distance_to(Vector2(other.x, other.y)) < radius + other.z + 0.5:
			return true
	return false
