class_name GallopState
extends MountState
## The rider sprints: the cat gallops with a wider turning circle. Pounces start from here.


func physics_update(delta: float) -> void:
	var stats: MountStats = cat.stats
	cat.steer(cat.drive_direction, stats.gallop_speed, stats.gallop_turn_rate, delta)
	if not cat.drive_gallop or cat.drive_direction.length() <= 0.1:
		state_machine.transition_to(&"Ridden")
