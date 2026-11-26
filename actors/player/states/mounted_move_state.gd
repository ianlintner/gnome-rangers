class_name MountedMoveState
extends MountedState
## Riding at walking pace (also standing still). Sprint, aim, pounce and dismount start here.


func physics_update(_delta: float) -> void:
	if ride_lost():
		return
	drive_cat(false)
	if try_dismount() or try_mounted_aim():
		return
	if wants_sprint():
		state_machine.transition_to(&"MountedSprint")
