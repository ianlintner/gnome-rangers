class_name PounceState
extends MountState
## Crouch, leap at the lock-on target on a ballistic arc, land with the pounce strike,
## recover. Timings, range, height and the strike's damage come from [MountStats]; the
## cooldown starts on landing.

enum Phase { WINDUP, LEAP, RECOVER }

var _phase: Phase = Phase.WINDUP
var _elapsed: float = 0.0
var _start: Vector3 = Vector3.ZERO
var _flat_velocity: Vector3 = Vector3.ZERO


func enter(_previous_state_name: StringName = &"") -> void:
	_phase = Phase.WINDUP
	_elapsed = 0.0
	var target: Node3D = cat.pounce_target
	var to_target: Vector3 = Vector3.ZERO
	if is_instance_valid(target):
		to_target = target.global_position - cat.global_position
		to_target.y = 0.0
	if to_target.length() > 0.01:
		cat.rotation.y = atan2(-to_target.x, -to_target.z)
	var distance: float = maxf(to_target.length() - cat.stats.pounce_land_distance, 0.0)
	_flat_velocity = to_target.normalized() * distance / maxf(cat.stats.pounce_leap_time, 0.01)


func physics_update(delta: float) -> void:
	_elapsed += delta
	var stats: MountStats = cat.stats
	match _phase:
		Phase.WINDUP:
			cat.steer(Vector3.ZERO, 0.0, stats.turn_rate, delta)
			if _elapsed >= stats.pounce_windup:
				_begin_leap()
		Phase.LEAP:
			_leap()
		Phase.RECOVER:
			cat.steer(Vector3.ZERO, 0.0, stats.turn_rate, delta)
			if _elapsed >= stats.pounce_recovery:
				state_machine.transition_to(resting_state())


func _begin_leap() -> void:
	_phase = Phase.LEAP
	_elapsed = 0.0
	_start = cat.global_position


func _leap() -> void:
	var stats: MountStats = cat.stats
	var progress: float = clampf(_elapsed / maxf(stats.pounce_leap_time, 0.01), 0.0, 1.0)
	# Parabola with apex `pounce_height` at the midpoint; vertical speed is its derivative.
	cat.velocity = _flat_velocity
	cat.velocity.y = 4.0 * stats.pounce_height / stats.pounce_leap_time * (1.0 - 2.0 * progress)
	cat.move_and_slide()
	if progress >= 1.0:
		_land()


func _land() -> void:
	_phase = Phase.RECOVER
	_elapsed = 0.0
	cat.velocity = Vector3.ZERO
	cat.start_pounce_cooldown()
	cat.strike()
