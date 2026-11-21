class_name Arrow
extends Node3D
## A pooled arrow: kinematic flight with gravity drop, a swept ray per tick (so fast
## arrows never tunnel), damage through its [HitboxComponent], and sticking into
## whatever it hits.
##
## On contact the arrow reparents to the hit hurtbox's stick anchor (a bone or body
## part) at the contact transform, so it rides along with a moving target. Stuck arrows
## despawn after `stuck_lifetime`; the [ArrowPool] caps how many exist.

## Emitted once when the arrow embeds; `target` is the node it is now a child of.
signal stuck(arrow: Arrow, target: Node)
## Emitted when the arrow's flight or stuck lifetime ran out; the pool recycles it.
signal expired(arrow: Arrow)

enum Mode { IDLE, FLYING, STUCK }

## Layers an arrow collides with: `world` (1) and `hurtbox` (7).
const HIT_MASK: int = (1 << 0) | (1 << 6)
## Ray retries after passing through hurtboxes of the shooter's own faction.
const MAX_PASS_THROUGH: int = 4

var mode: Mode = Mode.IDLE
var velocity: Vector3 = Vector3.ZERO

var _data: BowData = null
var _time_left: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

@onready var hitbox: HitboxComponent = $Hitbox


func _physics_process(delta: float) -> void:
	match mode:
		Mode.FLYING:
			_fly(delta)
		Mode.STUCK:
			_time_left -= delta
			if _time_left <= 0.0:
				expired.emit(self)


## Fires the arrow from `origin` along `direction` at `speed`. `attack` is the already
## scaled per-shot damage; `shooter` and `faction` identify who is hurt and who is not.
func launch(
	data: BowData,
	attack: AttackData,
	origin: Vector3,
	direction: Vector3,
	speed: float,
	shooter: Node,
	faction: StringName
) -> void:
	_data = data
	hitbox.faction = faction
	hitbox.configure(attack, shooter, 0.0, false)
	top_level = true
	global_position = origin
	velocity = direction.normalized() * speed
	_time_left = data.flight_lifetime
	_orient()
	visible = true
	mode = Mode.FLYING


## Returns the arrow to its idle pooled state.
func deactivate() -> void:
	mode = Mode.IDLE
	velocity = Vector3.ZERO
	visible = false
	top_level = true


func _fly(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
		expired.emit(self)
		return
	velocity.y -= _gravity * _data.gravity_scale * delta
	var from: Vector3 = global_position
	var to: Vector3 = from + velocity * delta
	var hit: Dictionary = _cast(from, to)
	if hit.is_empty():
		global_position = to
		_orient()
		return
	_on_contact(hit)


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK)
	query.collide_with_areas = true
	var excluded: Array[RID] = []
	for _attempt: int in MAX_PASS_THROUGH:
		query.exclude = excluded
		var hit: Dictionary = space.intersect_ray(query)
		var hurtbox := hit.get("collider") as HurtboxComponent
		if hurtbox == null or hurtbox.faction != hitbox.faction:
			return hit
		excluded.append(hit["rid"] as RID)
	return {}


func _on_contact(hit: Dictionary) -> void:
	var point: Vector3 = hit["position"]
	var anchor: Node = hit["collider"] as Node
	var hurtbox := anchor as HurtboxComponent
	if hurtbox != null:
		hitbox.apply_to(hurtbox, point)
		anchor = hurtbox.get_stick_anchor()
	_stick(point, anchor)


func _stick(point: Vector3, anchor: Node) -> void:
	global_position = point + velocity.normalized() * _data.embed_depth
	var contact: Transform3D = global_transform
	mode = Mode.STUCK
	velocity = Vector3.ZERO
	_time_left = _data.stuck_lifetime
	top_level = false
	reparent(anchor, false)
	global_transform = contact
	stuck.emit(self, anchor)


func _orient() -> void:
	if velocity.length_squared() > 0.0001:
		look_at(global_position + velocity, Vector3.UP)
