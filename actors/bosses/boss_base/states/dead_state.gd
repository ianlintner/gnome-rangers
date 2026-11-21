class_name BossDeadState
extends BossState
## Terminal state: stops movement and lets the arena react to boss_defeated.


func enter(_previous: StringName = &"") -> void:
	if boss != null:
		boss.velocity = Vector3.ZERO
		boss._play_animation(&"death")
		boss.hitbox.set_active(false)
