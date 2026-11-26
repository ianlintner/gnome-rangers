class_name HurtState
extends MountState
## Flinch after a poise break: the cat stops and ignores the rider's input briefly.

var _remaining: float = 0.0


func enter(_previous_state_name: StringName = &"") -> void:
	_remaining = cat.stats.hurt_duration


func physics_update(delta: float) -> void:
	cat.steer(Vector3.ZERO, 0.0, cat.stats.turn_rate, delta)
	_remaining -= delta
	if _remaining <= 0.0:
		state_machine.transition_to(resting_state())
