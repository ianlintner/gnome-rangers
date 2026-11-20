class_name MoveState
extends PlayerState
## Walking, camera-relative; strafes at the lock-on target while locked.


func physics_update(delta: float) -> void:
	var direction: Vector3 = player.get_move_direction()
	player.locomote(direction * player.stats.move_speed, player.stats.acceleration, delta)
	player.update_facing(direction, delta)
	if try_fall() or try_dodge():
		return
	if wants_sprint():
		state_machine.transition_to(&"Sprint")
	elif not player.has_move_input():
		state_machine.transition_to(&"Idle")
