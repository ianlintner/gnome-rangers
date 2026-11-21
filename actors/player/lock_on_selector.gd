class_name LockOnSelector
extends Node
## Player-side lock-on: picks the nearest in-cone target with line of sight, flicks
## between targets, and breaks on distance or lost line of sight.
##
## Reads `lock_on`, `lock_switch_left` and `lock_switch_right` actions. Announces
## changes through `EventBus.lock_on_changed` (the camera and HUD listen there).

## The locked target node (the actor that owns the [LockOnTarget]) or null.
var current_target: Node3D = null

var _current_lock: LockOnTarget = null
var _los_lost_for: float = 0.0
var _player: Player = null


func _ready() -> void:
	_player = get_parent() as Player


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed(&"lock_on"):
		toggle()
	elif Input.is_action_just_pressed(&"lock_switch_left"):
		switch_target(1)
	elif Input.is_action_just_pressed(&"lock_switch_right"):
		switch_target(-1)
	tick(delta)


## Locks the nearest in-cone target, or releases when already locked.
func toggle() -> void:
	if _current_lock != null:
		release()
		return
	var best: LockOnTarget = find_best_target()
	if best != null:
		_set_lock(best)


## Nearest enabled target inside the view cone and range with a clear line of sight.
func find_best_target() -> LockOnTarget:
	var stats: CharacterStats = _player.stats
	var forward: Vector3 = _player.get_view_forward()
	var cos_limit: float = cos(deg_to_rad(stats.lock_cone_half_angle_degrees))
	var best: LockOnTarget = null
	var best_distance: float = INF
	for candidate: LockOnTarget in _candidates():
		var offset: Vector3 = candidate.get_lock_position() - _player.global_position
		var flat := Vector3(offset.x, 0.0, offset.z)
		var distance: float = offset.length()  # 3D: elevation counts towards range
		if distance > stats.lock_on_range or flat.length() < 0.001:
			continue
		if forward.dot(flat.normalized()) < cos_limit:
			continue
		if distance < best_distance and _has_line_of_sight(candidate):
			best = candidate
			best_distance = distance
	return best


## Moves the lock to the neighbour on one side: `direction` +1 is left, -1 is right.
func switch_target(direction: int) -> void:
	if _current_lock == null:
		return
	var forward: Vector3 = _player.get_view_forward()
	var current_angle: float = _view_angle(_current_lock, forward)
	var best: LockOnTarget = null
	var best_delta: float = INF
	for candidate: LockOnTarget in _candidates():
		if candidate == _current_lock or not _in_switch_range(candidate):
			continue
		# Signed offset from the current target, positive to the left (counter-clockwise).
		var delta_angle: float = wrapf(_view_angle(candidate, forward) - current_angle, -PI, PI)
		var side_delta: float = delta_angle * direction
		if side_delta > 0.0 and side_delta < best_delta and _has_line_of_sight(candidate):
			best = candidate
			best_delta = side_delta
	if best != null:
		_set_lock(best)


## Per-tick validity check: breaks on freed/disabled target, distance or lost LOS.
func tick(delta: float) -> void:
	if _current_lock == null:
		return
	if not is_instance_valid(_current_lock) or not _current_lock.enabled:
		release()
		return
	var offset: Vector3 = _current_lock.get_lock_position() - _player.global_position
	if offset.length() > _player.stats.lock_break_range:
		release()
		return
	if _has_line_of_sight(_current_lock):
		_los_lost_for = 0.0
	else:
		_los_lost_for += delta
		if _los_lost_for >= _player.stats.lock_los_grace:
			release()


## Drops the lock and announces it.
func release() -> void:
	if _current_lock == null:
		return
	if is_instance_valid(_current_lock):
		_current_lock.set_locked(false)
	_current_lock = null
	current_target = null
	_los_lost_for = 0.0
	EventBus.lock_on_changed.emit(null)


func _set_lock(target: LockOnTarget) -> void:
	if target == _current_lock:
		return
	if _current_lock != null and is_instance_valid(_current_lock):
		_current_lock.set_locked(false)
	_current_lock = target
	current_target = target.get_parent() as Node3D
	if current_target == null:
		current_target = target
	_los_lost_for = 0.0
	target.set_locked(true)
	EventBus.lock_on_changed.emit(current_target)


func _candidates() -> Array[LockOnTarget]:
	var result: Array[LockOnTarget] = []
	for node: Node in get_tree().get_nodes_in_group(LockOnTarget.GROUP):
		var target := node as LockOnTarget
		if target != null and target.enabled and target.is_inside_tree():
			result.append(target)
	return result


func _in_switch_range(target: LockOnTarget) -> bool:
	var offset: Vector3 = target.get_lock_position() - _player.global_position
	return offset.length() <= _player.stats.lock_on_range


func _view_angle(target: LockOnTarget, forward: Vector3) -> float:
	var offset: Vector3 = target.get_lock_position() - _player.global_position
	return forward.signed_angle_to(Vector3(offset.x, 0.0, offset.z), Vector3.UP)


func _has_line_of_sight(target: LockOnTarget) -> bool:
	var origin: Vector3 = _player.global_position + Vector3.UP * _player.stats.lock_eye_height
	var query := PhysicsRayQueryParameters3D.create(origin, target.get_lock_position())
	query.collision_mask = 1 << 0  # `world` layer only; actors never block sight.
	query.collide_with_areas = false
	return _player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
