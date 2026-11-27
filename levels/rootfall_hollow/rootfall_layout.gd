class_name RootfallLayout
extends RefCounted
## Shared layout constants for Rootfall Hollow (metres, gnome scale, -Z is "forward").
##
## The level builder (`tools/level/build_rootfall.gd`), the level script, the tests and the
## capture/perf presets all read these numbers, so the map has exactly one definition.

## Where the Mushroom Ring checkpoint sits. The player starts beside it.
const CHECKPOINT_POS := Vector3(0.0, 0.0, 0.0)
const PLAYER_START_POS := Vector3(0.0, 0.0, 3.0)
## Where the cat waits at the start: on the path centreline a short whistle away.
const MOUNT_START_POS := Vector3(3.0, 0.0, -14.0)

## Centreline of the approach path, checkpoint to fog gate (x, z). About 330 m: roughly
## 60 s at a 5.5 m/s run and 95 s at a 3.5 m/s walk. The three wide waypoints (index 2, 5, 7)
## sit in open glades that are wide enough for the cat to gallop through.
const PATH_XZ: Array[Vector2] = [
	Vector2(0.0, 0.0),
	Vector2(6.0, -28.0),
	Vector2(24.0, -58.0),
	Vector2(28.0, -92.0),
	Vector2(10.0, -128.0),
	Vector2(-14.0, -158.0),
	Vector2(-26.0, -194.0),
	Vector2(-12.0, -230.0),
	Vector2(4.0, -258.0),
	Vector2(0.0, -280.0),
]
## Half-width of the walkable path corridor kept free of foliage and props.
const PATH_HALF_WIDTH: float = 4.5
## Waypoint indices of the open glades (mount-friendly) and their clear radius.
const GLADE_INDICES: Array[int] = [2, 5, 7]
const GLADE_RADIUS: float = 13.0

## Fog gate in the south wall of the arena.
const GATE_POS := Vector3(0.0, 0.0, -283.0)
const GATE_HALF_WIDTH: float = 6.5

## Boss arena: a ~40 m circle framed by trunks (ring radius) and root walls.
const ARENA_CENTER := Vector3(0.0, 0.0, -305.0)
const ARENA_RADIUS: float = 20.0
const TRUNK_RING_RADIUS: float = 24.5
const TRUNK_RING_COUNT: int = 14

## Walkable ground rectangle (x min, z min, width, depth).
const GROUND_RECT := Rect2(-90.0, -350.0, 180.0, 400.0)

## Height at which the shadow-only canopy slabs hover and their cell size.
const CANOPY_HEIGHT: float = 34.0
const CANOPY_CELL: float = 22.0


## Returns the 3D point of path waypoint `index` on the ground.
static func path_point(index: int) -> Vector3:
	return Vector3(PATH_XZ[index].x, 0.0, PATH_XZ[index].y)


## Shortest distance in the XZ plane from `point` to the path polyline.
static func distance_to_path(point: Vector2) -> float:
	var best: float = INF
	for i: int in range(PATH_XZ.size() - 1):
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
			point, PATH_XZ[i], PATH_XZ[i + 1]
		)
		best = minf(best, point.distance_to(closest))
	return best


## True when `point` lies inside the boss arena disc (plus `margin`).
static func in_arena(point: Vector2, margin: float = 0.0) -> bool:
	var centre := Vector2(ARENA_CENTER.x, ARENA_CENTER.z)
	return point.distance_to(centre) <= ARENA_RADIUS + margin


## True when `point` is inside a glade disc.
static func in_glade(point: Vector2) -> bool:
	for index: int in GLADE_INDICES:
		if point.distance_to(PATH_XZ[index]) <= GLADE_RADIUS:
			return true
	return false


## Total length of the approach path in metres.
static func path_length() -> float:
	var total: float = 0.0
	for i: int in range(PATH_XZ.size() - 1):
		total += PATH_XZ[i].distance_to(PATH_XZ[i + 1])
	return total
