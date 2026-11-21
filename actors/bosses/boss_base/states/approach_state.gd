class_name BossApproachState
extends BossState
## Closes distance until a move becomes eligible; turns with a limited turn rate.


func physics_update(delta: float) -> void:
	if boss == null or boss.target == null:
		return
	boss.face_target(delta)
	var distance: float = boss.distance_to_target()
	if not boss.brain.available_moves(distance).is_empty():
		if boss.choose_move() != null:
			state_machine.transition_to(&"Attack")
			return
	var direction: Vector3 = boss.target.global_position - boss.global_position
	direction.y = 0.0
	if direction.length() > boss.approach_stop_distance:
		boss.velocity.x = direction.normalized().x * boss.walk_speed * boss.speed_multiplier
		boss.velocity.z = direction.normalized().z * boss.walk_speed * boss.speed_multiplier
	else:
		boss.velocity.x = 0.0
		boss.velocity.z = 0.0
		if distance > 0.0:
			state_machine.transition_to(&"Strafe")
