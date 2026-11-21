class_name BossStaggeredState
extends BossState
## Poise break: the boss is open to back/riposte damage until stagger ends.


func physics_update(_delta: float) -> void:
	if boss == null:
		return
	boss.velocity.x = 0.0
	boss.velocity.z = 0.0
	if not boss.poise.staggered and not boss.runner.is_busy():
		state_machine.transition_to(&"Approach")
