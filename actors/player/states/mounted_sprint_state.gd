class_name MountedSprintState
extends MountedState
## Galloping: the rider pays stamina per second and may pounce at the lock-on target.


func physics_update(delta: float) -> void:
	if ride_lost():
		return
	drive_cat(true)
	if try_pounce() or try_dismount() or try_mounted_aim():
		return
	var cost: float = cat.stats.sprint_stamina_per_second * delta
	var drained: bool = player.stamina.drain(cost)
	if not drained or not Input.is_action_pressed(&"sprint") or not player.has_move_input():
		state_machine.transition_to(&"Mounted")
