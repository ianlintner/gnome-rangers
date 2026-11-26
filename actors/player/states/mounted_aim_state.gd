class_name MountedAimState
extends MountedState
## Bow aim from the saddle, reusing the on-foot bow. The cat walks at a reduced speed
## while the rider aims; releasing `aim` or dismounting ends it.


func enter(_previous_state_name: StringName = &"") -> void:
	player.bow.begin_draw()
	EventBus.aim_changed.emit(true)


func exit() -> void:
	player.bow.cancel_draw()
	EventBus.aim_changed.emit(false)


func physics_update(_delta: float) -> void:
	if ride_lost():
		return
	drive_cat(false, true)
	if try_dismount():
		return
	if not Input.is_action_pressed(&"aim"):
		state_machine.transition_to(&"Mounted")
		return
	if player.bow.drawing:
		if Input.is_action_just_pressed(&"fire"):
			player.fire_bow()
	else:
		player.bow.begin_draw()  # refused until the nock time has passed
