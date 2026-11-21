class_name AimState
extends PlayerState
## Bow aim: holding `aim` draws the bow and switches the camera to over-the-shoulder.
##
## The bow starts drawing on entry, so draw time is the time spent aiming; `fire`
## releases the arrow (quick shot when pressed early, full damage when fully drawn) and
## the bow re-nocks by itself after its nock time. Releasing `aim` lets the string
## down. Dodge cancels. Starts and stops are announced on `EventBus.aim_changed` for the
## camera and the HUD reticle.


func enter(_previous_state_name: StringName = &"") -> void:
	player.bow.begin_draw()
	EventBus.aim_changed.emit(true)


func exit() -> void:
	player.bow.cancel_draw()
	EventBus.aim_changed.emit(false)


func physics_update(delta: float) -> void:
	var direction: Vector3 = player.get_move_direction()
	var speed: float = player.stats.move_speed * player.stats.aim_move_speed_multiplier
	player.locomote(direction * speed, player.stats.acceleration, delta)
	player.face_direction(player.get_view_forward(), delta)
	if try_fall() or try_dodge():
		return
	if not Input.is_action_pressed(&"aim"):
		state_machine.transition_to(&"Idle")
		return
	if player.bow.drawing:
		if Input.is_action_just_pressed(&"fire"):
			player.fire_bow()
	else:
		player.bow.begin_draw()  # refused until the nock time has passed
