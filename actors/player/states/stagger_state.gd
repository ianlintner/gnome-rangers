class_name StaggerState
extends PlayerState
## Stub: freezes the player for `stagger_duration`, then returns to idle.
## Card 5 will hook hit reactions and poise into this.

var _remaining: float = 0.0


func enter(_previous_state_name: StringName = &"") -> void:
	_remaining = player.stats.stagger_duration


func physics_update(delta: float) -> void:
	player.locomote(Vector3.ZERO, player.stats.deceleration, delta)
	_remaining -= delta
	if _remaining <= 0.0:
		state_machine.transition_to(&"Idle")
