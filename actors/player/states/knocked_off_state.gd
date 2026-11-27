class_name KnockedOffState
extends PlayerState
## Thrown from the saddle by a hard hit (or a fleeing cat): the rider tumbles away
## from the hit, then lies staggered for `MountStats.knock_off_stagger`.

var _remaining: float = 0.0
var _drag: float = 0.0


func enter(_previous_state_name: StringName = &"") -> void:
	var cat: CatMount = player.mount
	if cat == null:
		_remaining = 0.0
		return
	_remaining = cat.stats.knock_off_stagger
	_drag = cat.stats.knock_off_drag
	cat.detach_rider(true, player.knock_off_direction)


func physics_update(delta: float) -> void:
	player.locomote(Vector3.ZERO, _drag, delta)
	_remaining -= delta
	if _remaining <= 0.0:
		state_machine.transition_to(&"Idle")
