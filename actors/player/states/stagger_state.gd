class_name StaggerState
extends PlayerState
## Hit reaction after a poise break: holds the player for the poise stagger duration
## (`CombatStats.stagger_duration`), then returns to idle. Leaving the previous state
## already cancelled any attack or bow draw.

var _remaining: float = 0.0


func enter(_previous_state_name: StringName = &"") -> void:
	_remaining = player.poise.stagger_duration


func physics_update(delta: float) -> void:
	player.locomote(Vector3.ZERO, player.stats.deceleration, delta)
	_remaining -= delta
	if _remaining <= 0.0:
		state_machine.transition_to(&"Idle")
