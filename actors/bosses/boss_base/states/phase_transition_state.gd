class_name BossPhaseTransitionState
extends BossState
## Short on-enter action (e.g. the phase 2 roar) during which the boss is invulnerable
## and does not attack. The scene's animation or timer calls finish_phase_transition.

@export var duration: float = 1.2

var _left: float = 0.0


func enter(_previous: StringName = &"") -> void:
	_left = duration
	if boss != null:
		boss.health.invulnerable = true
		boss._play_animation(&"roar")
		boss.velocity.x = 0.0
		boss.velocity.z = 0.0


func exit() -> void:
	if boss != null:
		boss.health.invulnerable = false


func physics_update(delta: float) -> void:
	if boss == null:
		return
	_left -= delta
	boss.velocity.x = 0.0
	boss.velocity.z = 0.0
	if _left <= 0.0:
		boss.finish_phase_transition()
