class_name CalledState
extends MountState
## Running to the player after `call_mount`: paths over the navigation mesh with the
## NavigationAgent3D and falls back to a straight run when the level has no navmesh.

var _refresh_left: float = 0.0


func enter(_previous_state_name: StringName = &"") -> void:
	_refresh_left = 0.0


func physics_update(delta: float) -> void:
	var target: Node3D = cat.call_target
	if not is_instance_valid(target) or cat.rider != null:
		state_machine.transition_to(&"Idle")
		return
	var stats: MountStats = cat.stats
	var to_target: Vector3 = target.global_position - cat.global_position
	to_target.y = 0.0
	if to_target.length() <= stats.call_stop_distance:
		state_machine.transition_to(&"Idle")
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		cat.nav_agent.target_position = target.global_position
		_refresh_left = stats.path_refresh_interval
	cat.steer(_path_direction(to_target), stats.call_speed, stats.turn_rate, delta)


## Direction along the navigation path, or straight at the target when there is no path.
func _path_direction(to_target: Vector3) -> Vector3:
	var agent: NavigationAgent3D = cat.nav_agent
	var next_position: Vector3 = agent.get_next_path_position()  # also refreshes the path
	if agent.get_current_navigation_path().size() >= 2:
		var step: Vector3 = next_position - cat.global_position
		step.y = 0.0
		if step.length() > 0.05:
			return step.normalized()
	return to_target.normalized()
