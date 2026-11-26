class_name MountingState
extends MountedState
## Climbing into the saddle: the body glides onto the cat's saddle bone over
## `MountStats.mount_duration`, then the ride begins.

var _elapsed: float = 0.0


func enter(_previous_state_name: StringName = &"") -> void:
	_elapsed = 0.0


func physics_update(delta: float) -> void:
	if ride_lost():
		return
	_elapsed += delta
	var duration: float = maxf(cat.stats.mount_duration, 0.01)
	cat.place_rider(clampf(_elapsed / duration, 0.0, 1.0))
	if _elapsed >= duration:
		cat.finish_mounting()
		state_machine.transition_to(&"Mounted")
