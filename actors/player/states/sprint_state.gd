class_name SprintState
extends PlayerState
## Sprinting drains stamina per second and always faces the movement direction.


func physics_update(delta: float) -> void:
	var direction: Vector3 = player.get_move_direction()
	player.locomote(direction * player.stats.sprint_speed, player.stats.acceleration, delta)
	player.update_facing(direction, delta, false)
	if try_fall() or try_dodge() or try_mount_actions() or try_combat():
		return
	var drained: bool = player.stamina.drain(player.stats.sprint_stamina_per_second * delta)
	if not drained or not Input.is_action_pressed(&"sprint") or not player.has_move_input():
		state_machine.transition_to(&"Move" if player.has_move_input() else &"Idle")
