class_name BossStrafeState
extends BossState
## Circles the target with a limited turn rate; flanking and back attacks stay open.

var _direction: float = 1.0
var _swap_left: float = 1.6


func enter(_previous: StringName = &"") -> void:
	_direction = 1.0 if boss.brain.rng.randf() > 0.5 else -1.0
	_swap_left = 1.6


func physics_update(delta: float) -> void:
	if boss == null or boss.target == null:
		return
	boss.face_target(delta)
	_swap_left -= delta
	if _swap_left <= 0.0:
		_direction *= -1.0
		_swap_left = 1.6
	var distance: float = boss.distance_to_target()
	if not boss.brain.available_moves(distance).is_empty() and boss.choose_move() != null:
		state_machine.transition_to(&"Attack")
		return
	if distance > boss.approach_stop_distance + 1.0:
		state_machine.transition_to(&"Approach")
		return
	var forward: Vector3 = boss.target.global_position - boss.global_position
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	var side := Vector3(-forward.z, 0.0, forward.x) * _direction
	boss.velocity.x = side.x * boss.strafe_speed * boss.speed_multiplier
	boss.velocity.z = side.z * boss.strafe_speed * boss.speed_multiplier
