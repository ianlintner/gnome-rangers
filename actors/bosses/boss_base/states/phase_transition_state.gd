class_name BossPhaseTransitionState
extends BossState
## Short on-enter action (e.g. the phase 2 roar) during which the boss is invulnerable
## and does not attack. Duration comes from BossPhaseData.on_enter_duration.

var _left: float = 0.0


## Called by BossBase before entering: locks the duration from `.tres` tuning and
## makes every hurtbox ignore hits (health AND poise) for the whole transition.
func begin(duration: float) -> void:
	_left = maxf(duration, 0.0)


func enter(_previous: StringName = &"") -> void:
	if boss == null:
		return
	boss.health.invulnerable = true
	for hurtbox: Node in boss.find_children("*", "HurtboxComponent", true, false):
		(hurtbox as HurtboxComponent).invulnerable = true
	boss._play_animation(&"roar")
	boss.velocity.x = 0.0
	boss.velocity.z = 0.0


func exit() -> void:
	if boss == null:
		return
	boss.health.invulnerable = false
	for hurtbox: Node in boss.find_children("*", "HurtboxComponent", true, false):
		(hurtbox as HurtboxComponent).invulnerable = false


func physics_update(delta: float) -> void:
	if boss == null:
		return
	_left -= delta
	boss.velocity.x = 0.0
	boss.velocity.z = 0.0
	if _left <= 0.0:
		boss.finish_phase_transition()
