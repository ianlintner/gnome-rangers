class_name FleeState
extends MountState
## Zero health: the rider is thrown, the cat bolts away from the player, waits out
## `flee_cooldown` and then recovers and runs back (see [method CatMount.recover]).

var _direction: Vector3 = Vector3.ZERO
var _start: Vector3 = Vector3.ZERO
var _elapsed: float = 0.0


func enter(_previous_state_name: StringName = &"") -> void:
	cat.hurtbox.invulnerable = true
	cat.eject_rider(cat.global_basis.z)
	_start = cat.global_position
	_elapsed = 0.0
	_direction = _away_from_player()
	cat.fled.emit()


func physics_update(delta: float) -> void:
	_elapsed += delta
	var stats: MountStats = cat.stats
	var ran: float = (
		Vector2(cat.global_position.x - _start.x, cat.global_position.z - _start.z).length()
	)
	if ran < stats.flee_distance:
		cat.steer(_direction, stats.flee_speed, stats.turn_rate * 2.0, delta)
	else:
		cat.steer(Vector3.ZERO, 0.0, stats.turn_rate, delta)
	if _elapsed >= stats.flee_cooldown:
		cat.recover()


func _away_from_player() -> Vector3:
	var player := cat.get_tree().get_first_node_in_group(CatMount.PLAYER_GROUP) as Node3D
	var away: Vector3 = cat.get_facing()
	if player != null:
		var offset: Vector3 = cat.global_position - player.global_position
		offset.y = 0.0
		if offset.length() > 0.1:
			away = offset.normalized()
	return away
