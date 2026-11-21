class_name BossAttackState
extends BossState
## Generic attack state: runs whatever BossMoveData the brain selected through the
## shared AttackRunner. Special moves (combo, leaping slam, grab) can be routed by
## subclassing this state via BossMoveData.state_script.


func enter(_previous: StringName = &"") -> void:
	if boss == null or boss.current_move == null:
		state_machine.transition_to(&"Idle")
		return
	if not boss.start_move(boss.current_move):
		state_machine.transition_to(&"Idle")


func physics_update(_delta: float) -> void:
	if boss == null:
		return
	boss.velocity.x = 0.0
	boss.velocity.z = 0.0
