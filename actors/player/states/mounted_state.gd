class_name MountedState
extends PlayerState
## Shared helpers for the states a rider can be in. Not a behaviour itself.

## The cat under the rider; null only transiently while the ride ends.
var cat: CatMount:
	get:
		return player.mount


## Hands the camera-relative input to the cat for this tick.
func drive_cat(gallop: bool, aiming: bool = false) -> void:
	cat.drive(player.get_move_direction(), gallop, aiming)


## Leaves the saddle when `interact` is pressed.
func try_dismount() -> bool:
	if not Input.is_action_just_pressed(&"interact"):
		return false
	return state_machine.transition_to(&"Dismounting")


## Raises the bow from the saddle while `aim` is held and the rider is not winded.
func try_mounted_aim() -> bool:
	if not Input.is_action_pressed(&"aim") or player.stamina.is_winded():
		return false
	return state_machine.transition_to(&"MountedAim")


## Asks the cat to pounce at the lock-on target when the heavy-attack button is pressed.
func try_pounce() -> bool:
	if not Input.is_action_just_pressed(&"attack_heavy"):
		return false
	return cat.request_pounce(player.lock_selector.current_target)


## Falls back to idle when the cat vanished from under the rider.
func ride_lost() -> bool:
	if cat != null:
		return false
	state_machine.transition_to(&"Idle")
	return true
