class_name BowComponent
extends Node
## A bow: draw timing, damage and speed scaling, aiming and firing pooled arrows.
##
## Reusable by the on-foot player and the mounted rider. The owner drives it:
## [method begin_draw] when aim starts, [method fire] on the fire input,
## [method cancel_draw] when aim ends. Draw time scales damage and arrow speed
## linearly between a quick shot and a full draw (see [BowData]).

## Emitted every physics tick while drawing, with the draw ratio 0..1.
signal draw_changed(ratio: float)
## Emitted when an arrow was released.
signal fired(arrow: Arrow, draw_ratio: float)
signal draw_cancelled

@export var data: BowData
## Side of the shooter, so arrows pass through friends.
@export var faction: StringName = &"player"

var drawing: bool = false
var draw_time: float = 0.0
var pool: ArrowPool = null

var _nock_left: float = 0.0


func _ready() -> void:
	if data != null:
		setup(data)


func _physics_process(delta: float) -> void:
	tick(delta)


## Applies `bow_data` and (re)builds the arrow pool.
func setup(bow_data: BowData) -> void:
	data = bow_data
	if pool != null:
		pool.queue_free()
	pool = ArrowPool.new()
	pool.name = &"ArrowPool"
	add_child(pool)
	pool.setup(data)


## Advances the nock cooldown and the draw timer by `delta` seconds.
func tick(delta: float) -> void:
	_nock_left = maxf(_nock_left - delta, 0.0)
	if drawing:
		draw_time += delta
		draw_changed.emit(get_draw_ratio())


## Starts drawing. Refused while the previous arrow is still being nocked.
func begin_draw() -> bool:
	if drawing or _nock_left > 0.0:
		return false
	drawing = true
	draw_time = 0.0
	draw_changed.emit(0.0)
	return true


## Lets the string down without firing.
func cancel_draw() -> void:
	if not drawing:
		return
	drawing = false
	draw_time = 0.0
	draw_cancelled.emit()


## Draw progress from 0 (quick shot) to 1 (full draw).
func get_draw_ratio() -> float:
	return clampf(draw_time / maxf(data.draw_time_full, 0.01), 0.0, 1.0)


## Direction to fire from `origin`: towards what the camera centre points at, or the
## shooter's facing when there is no camera. `exclude` lists RIDs the aim ray ignores
## (the shooter's own hurtboxes).
func aim_direction(
	shooter: Node3D, origin: Vector3, camera: Camera3D, exclude: Array[RID]
) -> Vector3:
	if camera == null:
		return -shooter.global_basis.z
	var ray_from: Vector3 = camera.global_position
	var ray_dir: Vector3 = -camera.global_basis.z
	var ray_to: Vector3 = ray_from + ray_dir * data.aim_range
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, Arrow.HIT_MASK)
	query.collide_with_areas = true
	query.exclude = exclude
	var hit: Dictionary = shooter.get_world_3d().direct_space_state.intersect_ray(query)
	var point: Vector3 = hit.get("position", ray_to)
	return (point - origin).normalized()


## Releases an arrow from `origin` along `direction`, paying the arrow's stamina cost.
## Returns the arrow, or null when not drawing or stamina refused.
func fire(
	shooter: Node3D, origin: Vector3, direction: Vector3, stamina: StaminaComponent = null
) -> Arrow:
	if not drawing:
		return null
	var cost: float = data.arrow_attack.stamina_cost
	if stamina != null and not stamina.try_spend(cost):
		return null
	var ratio: float = get_draw_ratio()
	var attack: AttackData = data.arrow_attack.duplicate() as AttackData
	attack.stamina_cost = 0.0
	attack.damage *= lerpf(data.min_damage_ratio, 1.0, ratio)
	var arrow: Arrow = pool.acquire()
	arrow.launch(
		data,
		attack,
		origin,
		direction,
		lerpf(data.min_speed, data.max_speed, ratio),
		shooter,
		faction
	)
	drawing = false
	draw_time = 0.0
	_nock_left = data.nock_time
	fired.emit(arrow, ratio)
	return arrow
