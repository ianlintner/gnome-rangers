class_name RiddenState
extends MountState
## Carrying a rider at walking pace; the rider's input arrives through [method CatMount.drive].


func physics_update(delta: float) -> void:
	var stats: MountStats = cat.stats
	var speed: float = stats.walk_speed
	if cat.drive_aiming:
		speed *= stats.aim_speed_multiplier
	cat.steer(cat.drive_direction, speed, stats.turn_rate, delta)
	if cat.rider_seated and cat.drive_gallop and cat.drive_direction.length() > 0.1:
		state_machine.transition_to(&"Gallop")
