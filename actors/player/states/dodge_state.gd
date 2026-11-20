class_name DodgeState
extends PlayerState
## Roll (directional, camera-relative) or backstep (no input) with an i-frame window.
##
## Stamina is paid by [method PlayerState.try_dodge] before entering. Timings and
## distances come from [CharacterStats].

## Acceleration high enough to reach the target velocity within one physics frame.
const SNAP_ACCELERATION: float = 10000.0

var _direction: Vector3 = Vector3.ZERO
var _speed: float = 0.0
var _move_time: float = 0.0
var _elapsed: float = 0.0


func enter(_previous_state_name: StringName = &"") -> void:
	var stats: CharacterStats = player.stats
	var input_direction: Vector3 = player.get_move_direction()
	if input_direction.length() > 0.0:
		_direction = input_direction.normalized()
		player.snap_facing(_direction)
		_move_time = stats.dodge_duration
		_speed = stats.dodge_distance / maxf(_move_time, 0.01)
	else:
		_direction = -player.get_facing()
		_move_time = stats.backstep_duration
		_speed = stats.backstep_distance / maxf(_move_time, 0.01)
	_elapsed = 0.0
	_update_iframes()


func exit() -> void:
	player.hurtbox.invulnerable = false


func physics_update(delta: float) -> void:
	_elapsed += delta
	_update_iframes()
	if _elapsed < _move_time:
		player.locomote(_direction * _speed, SNAP_ACCELERATION, delta)
	else:
		# Recovery is stationary: stop dead so the roll never exceeds its distance.
		player.locomote(Vector3.ZERO, SNAP_ACCELERATION, delta)
	if _elapsed >= _move_time + player.stats.dodge_recovery:
		state_machine.transition_to(&"Idle")


func _update_iframes() -> void:
	var start: float = player.stats.iframe_start
	player.hurtbox.invulnerable = (
		_elapsed >= start and _elapsed < start + player.stats.iframe_duration
	)
