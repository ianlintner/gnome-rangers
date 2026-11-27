class_name MountIdleState
extends MountState
## Waiting for the rider: the cat stands still and can be mounted or called.


func physics_update(delta: float) -> void:
	cat.steer(Vector3.ZERO, 0.0, cat.stats.turn_rate, delta)
