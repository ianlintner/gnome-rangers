class_name IdleState
extends PlayerState
## Standing still: decelerates and watches for input, dodge and loss of ground.


func physics_update(delta: float) -> void:
	player.locomote(Vector3.ZERO, player.stats.deceleration, delta)
	player.update_facing(Vector3.ZERO, delta)
	if try_fall() or try_dodge():
		return
	if wants_sprint():
		state_machine.transition_to(&"Sprint")
	elif player.has_move_input():
		state_machine.transition_to(&"Move")
