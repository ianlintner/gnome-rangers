class_name FightBot
extends Node
## Scripted player for the headless bot-fight tests (`tests/integration/test_bot_fight.gd`).
##
## The bot only reads public state (positions, the boss's [AttackRunner] phase, stamina, the
## lock-on selector) and acts through [BotInput], i.e. through the named InputMap actions, on
## the real [Player] inside the real Rootfall Hollow level. It runs before the player in every
## physics tick (`process_physics_priority`), so a tap is seen as "just pressed" that tick.
##
## Plans: IDLE rests at the checkpoint, walks into the arena and then stands still; ON_FOOT
## rests, walks the approach and fights with lock-on, dodges, light attacks and arrows
## ([BotFootTactics]); MOUNTED rests, whistles the cat, rides the approach and fights with
## mounted arrows and pounces ([BotSaddleTactics]), remounting after a knock-off, then
## finishes on foot. Neither plan reads `Time`: a fight depends only on the seeds.

enum Plan { IDLE, ON_FOOT, MOUNTED }
enum Stage { REST, CALL_MOUNT, TRAVEL, FIGHT, STAND, DONE }

## The bot switches from travelling to fighting inside this flat distance of the boss.
const ENGAGE_DISTANCE: float = 13.0
const WAYPOINT_REACHED: float = 1.5
const ARRIVE_DISTANCE: float = 45.0
const PATH_REFRESH: float = 1.0
## Retreats start bending towards the arena centre this far inside the arena wall.
const EDGE_MARGIN: float = 6.0
## Length of the test move that checks a heading is free of scenery.
const HEADING_PROBE: float = 1.6
## Turns (degrees, centre side first) tried for a retreat or circle blocked by scenery.
const AROUND_ANGLES: Array[float] = [0.0, 35.0, -35.0, 70.0, -70.0, 110.0, -110.0, 150.0]
## Aim tolerance (radians) at release, and the draw ratio the bot waits for.
const MAX_AIM_ERROR: float = 0.03
const FULL_DRAW: float = 0.95
const SPRINT_HYSTERESIS: Vector2 = Vector2(15.0, 45.0)
## Player states in which the bot keeps its hands off the controls.
const BUSY_STATES: Array[StringName] = [
	&"Dodge", &"Stagger", &"KnockedOff", &"Mounting", &"Dismounting", &"Dead"
]

var plan: Plan = Plan.IDLE
var stage: Stage = Stage.REST
var level: RootfallHollow = null
var player: Player = null
var boss: BossBase = null
var cat: CatMount = null
var input := BotInput.new()
## Game seconds since the bot started.
var game_time: float = 0.0
## Hit tallies on the boss by damage type, and the bot's own action counters.
var hits: Dictionary = {&"melee": 0, &"arrow": 0, &"pounce": 0, &"mounted_arrow": 0}
var dodges: int = 0
var arrows_fired: int = 0
var pounces: int = 0
var mounts: int = 0
## Milestones with their game time, for readable failure messages.
var journal: PackedStringArray = []

var _path: PackedVector3Array = []
var _path_index: int = 0
var _path_age: float = INF
var _sprinting: bool = false
var _foot := BotFootTactics.new(self)
var _saddle := BotSaddleTactics.new(self)


func _init(target_level: RootfallHollow, bot_plan: Plan) -> void:
	name = "FightBot"
	level = target_level
	plan = bot_plan
	process_physics_priority = -100


func _ready() -> void:
	player = level.player
	boss = level.boss
	cat = level.mount
	for hurtbox: Node in boss.find_children("*", "HurtboxComponent", true, false):
		(hurtbox as HurtboxComponent).damaged.connect(_on_boss_damaged)
	note("start plan=%s" % Plan.keys()[plan])
	player.hurtbox.damaged.connect(_on_player_damaged)


func _exit_tree() -> void:
	BotInput.release_all()


func note(text: String) -> void:
	journal.append("[%.1fs] %s" % [game_time, text])


func _physics_process(delta: float) -> void:
	game_time += delta
	input.begin_tick()
	if stage == Stage.DONE or stage == Stage.STAND:
		return
	if boss.health.is_dead() or player.health.is_dead():
		_finish("boss dead" if boss.health.is_dead() else "player dead")
		return
	match stage:
		Stage.REST:
			_rest()
		Stage.CALL_MOUNT:
			_remount()
			if player.mount != null and player.mount.rider_seated:
				note("mounted")
				stage = Stage.TRAVEL
		Stage.TRAVEL:
			_travel()
		Stage.FIGHT:
			if plan == Plan.MOUNTED and player.mount != null:
				_saddle.step()
			elif plan == Plan.MOUNTED and not _saddle.done and _cat_available():
				_remount()
			else:
				_foot.step()


func _finish(reason: String) -> void:
	note(reason)
	stage = Stage.DONE
	BotInput.release_all()


# --- Stages ---------------------------------------------------------------------------------


func _rest() -> void:
	if GameState.checkpoint == null:
		input.tap(&"interact")
		return
	note("rested at %s" % GameState.checkpoint.name)
	stage = Stage.CALL_MOUNT if plan == Plan.MOUNTED else Stage.TRAVEL


## Whistles the cat until it waits beside the player, then climbs on.
func _remount() -> void:
	if busy():
		return
	var distance: float = flat(cat.global_position - player.global_position).length()
	if cat.is_mountable() and distance <= cat.stats.mount_range:
		input.steer(Vector3.ZERO, player.get_view_basis())
		if input.tap(&"interact"):
			mounts += 1
		return
	if cat.state_machine.current_state_name != &"Called":
		input.tap(&"call_mount")
	if stage == Stage.FIGHT and not _foot.dodge_if_threatened():
		input.steer(Vector3.ZERO, player.get_view_basis())


func _travel() -> void:
	var to_boss: Vector3 = flat(boss.global_position - player.global_position)
	if level.fog_gate.is_engaged() and to_boss.length() <= ENGAGE_DISTANCE:
		input.steer(Vector3.ZERO, player.get_view_basis())
		input.hold(&"sprint", false)
		if plan == Plan.IDLE:
			note("standing idle in the arena")
			stage = Stage.STAND
			BotInput.release_all()
		else:
			note("fight")
			stage = Stage.FIGHT
		return
	var mounted: bool = player.mount != null
	var body: Node3D = player.mount if mounted else player
	# Arrive with full stamina: no sprinting on the last stretch before the arena.
	var fresh: bool = to_boss.length() > ARRIVE_DISTANCE
	_update_sprint(fresh and (not mounted or player.mount.rider_seated))
	input.steer(_path_direction(body.global_position, boss.global_position), view())


## Flat heading along the navmesh path from `from` to `goal` (re-planned every second).
func _path_direction(from: Vector3, goal: Vector3) -> Vector3:
	_path_age += get_physics_process_delta_time()
	if _path_age >= PATH_REFRESH or _path_index >= _path.size():
		_path = NavigationServer3D.map_get_path(
			player.get_world_3d().navigation_map, from, goal, true
		)
		_path_index = 1 if _path.size() > 1 else 0
		_path_age = 0.0
	while _path_index < _path.size() - 1:
		if flat(_path[_path_index] - from).length() > WAYPOINT_REACHED:
			break
		_path_index += 1
	if _path.is_empty():
		return flat(goal - from)
	return flat(_path[_path_index] - from)


func _cat_available() -> bool:
	return not cat.health.is_dead() and cat.state_machine.current_state_name != &"Flee"


# --- Shared ---------------------------------------------------------------------------------


## Raises the bow, aims the camera at the boss's head and looses once fully drawn.
func shoot() -> void:
	input.hold(&"aim")
	var view_camera: Camera3D = player.camera.camera
	var head: Vector3 = head_position()
	# The bow shoots along the reticle ray, which starts at the shoulder-offset eye.
	var reticle: Vector2 = view_camera.get_viewport().get_visible_rect().size * 0.5
	var eye: Vector3 = view_camera.project_ray_origin(reticle)
	var error: float = input.look_towards(view_camera.project_ray_normal(reticle), head - eye)
	var aiming: bool = [&"Aim", &"MountedAim"].has(player.state_machine.current_state_name)
	if aiming and player.bow.get_draw_ratio() >= FULL_DRAW and error <= MAX_AIM_ERROR:
		if input.tap(&"fire"):
			arrows_fired += 1


## Keeps the lock on the boss: turns the camera towards it and taps lock-on once in view.
func keep_lock() -> void:
	if locked():
		return
	var to_boss: Vector3 = flat(boss.global_position - player.global_position)
	var error: float = input.look_towards(player.get_view_forward(), to_boss)
	if error < 0.5:
		input.tap(&"lock_on")


func locked() -> bool:
	return player.lock_selector.current_target == boss


func busy() -> bool:
	return BUSY_STATES.has(player.state_machine.current_state_name)


func _update_sprint(allowed: bool) -> void:
	var stamina: float = player.stamina.current
	if _sprinting and stamina < SPRINT_HYSTERESIS.x:
		_sprinting = false
	elif not _sprinting and stamina > SPRINT_HYSTERESIS.y:
		_sprinting = true
	input.hold(&"sprint", allowed and _sprinting and not player.stamina.is_winded())


## True when an arrow loosed now would reach Grukk: the reticle ray (from the shoulder
## camera, which is what the bow aims along) and the flight line from the muzzle both meet
## one of his hurtboxes before any scenery, the cat or anything else.
func clear_shot() -> bool:
	var view_camera: Camera3D = player.camera.camera
	var reticle: Vector2 = view_camera.get_viewport().get_visible_rect().size * 0.5
	var head: Vector3 = head_position()
	var muzzle: Vector3 = player.global_position + Vector3.UP * player.bow.data.muzzle_height
	return (
		_reaches_boss(view_camera.project_ray_origin(reticle), head) and _reaches_boss(muzzle, head)
	)


func _reaches_boss(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		from, to + (to - from).normalized(), Arrow.HIT_MASK
	)
	query.collide_with_areas = true
	query.exclude = [player.hurtbox.get_rid()]
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	var hurtbox := hit.get("collider") as HurtboxComponent
	return hurtbox != null and hurtbox.actor == boss


## A heading for `body` near `wanted`: bent back towards the arena centre near the wall, then
## turned by each of `angles` (degrees, towards the centre first) until a short test move does
## not hit scenery. Cover rocks, the arena wall and the sealed fog gate would otherwise pin
## the bot (or its cat) where it can neither get clear nor open the gap for the bow.
func clear_heading(body: PhysicsBody3D, wanted: Vector3, angles: Array[float]) -> Vector3:
	var heading: Vector3 = flat(wanted).normalized()
	var to_centre: Vector3 = flat(level.arena_center() - body.global_position)
	var edge: float = to_centre.length() - (RootfallLayout.ARENA_RADIUS - EDGE_MARGIN)
	if edge > 0.0:
		heading = (heading + to_centre.normalized() * clampf(edge / 2.0, 0.0, 2.0)).normalized()
	var turn: float = 1.0 if side(heading).dot(to_centre) >= 0.0 else -1.0
	for degrees: float in angles:
		var turned: Vector3 = heading.rotated(Vector3.UP, deg_to_rad(degrees) * turn)
		if not body.test_move(body.global_transform, turned * HEADING_PROBE):
			return turned
	return to_centre.normalized()


## Which way to circle the boss: the side that leads towards the arena centre.
func orbit_sign() -> float:
	var to_boss: Vector3 = flat(boss.global_position - player.global_position)
	var to_centre: Vector3 = flat(level.arena_center() - player.global_position)
	return 1.0 if side(to_boss).dot(to_centre) >= 0.0 else -1.0


func head_position() -> Vector3:
	var head := boss.get_node_or_null(^"HurtboxBody/CollisionShape3D") as Node3D
	return head.global_position if head != null else boss.lock_target.global_position


func view() -> Basis:
	return player.get_view_basis()


func _on_player_damaged(info: DamageInfo) -> void:
	var attack: String = info.attack.resource_name if info.attack != null else "?"
	var distance: float = flat(boss.global_position - player.global_position).length()
	note(
		(
			"hit by %s (%.0f) in %s at %.1f m"
			% [attack, info.amount, player.state_machine.current_state_name, distance]
		)
	)


func _on_boss_damaged(info: DamageInfo) -> void:
	var kind: StringName = info.damage_type
	if kind == &"arrow" and player.mount != null:
		kind = &"mounted_arrow"
	hits[kind] = (hits.get(kind, 0) as int) + 1


static func flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)


static func side(forward: Vector3) -> Vector3:
	return Vector3(-forward.z, 0.0, forward.x).normalized()
