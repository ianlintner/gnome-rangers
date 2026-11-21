class_name DeadState
extends PlayerState
## The player ran out of health: no input, just friction. The death flow (card 9)
## listens to `EventBus.player_died` and respawns the player.


func physics_update(delta: float) -> void:
	player.locomote(Vector3.ZERO, player.stats.deceleration, delta)
