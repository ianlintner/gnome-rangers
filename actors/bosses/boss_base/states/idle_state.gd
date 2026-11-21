class_name BossIdleState
extends BossState
## Boss waits until engaged, then decides whether to approach, strafe or attack.

var _think_left: float = 0.0


func enter(_previous: StringName = &"") -> void:
	_think_left = 0.15


func physics_update(delta: float) -> void:
	if boss == null or not boss.engaged or boss.target == null:
		return
	_think_left -= delta
	boss.face_target(delta)
	if _think_left > 0.0:
		return
	_think_left = 0.2
	var distance: float = boss.distance_to_target()
	if boss.brain.available_moves(distance).is_empty():
		state_machine.transition_to(
			&"Approach" if distance > boss.approach_stop_distance else &"Strafe"
		)
		return
	if boss.choose_move() != null:
		state_machine.transition_to(&"Attack")
