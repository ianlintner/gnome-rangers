class_name FallState
extends PlayerState
## Airborne: gravity only, horizontal velocity is kept (no air steering in the MVP).


func physics_update(delta: float) -> void:
	player.locomote(Vector3.ZERO, 0.0, delta)
	if player.is_on_floor():
		state_machine.transition_to(&"Idle")
