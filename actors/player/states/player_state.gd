class_name PlayerState
extends State
## Shared helpers for the player's states. Not a behaviour itself: each concrete
## state lives in its own file and extends this to reach the [Player] and stats.

@onready var player: Player = owner as Player


## Starts a dodge when the action was pressed and stamina pays for it.
func try_dodge() -> bool:
	if not Input.is_action_just_pressed(&"dodge"):
		return false
	if not player.stamina.try_spend(player.stats.dodge_stamina_cost):
		return false
	return state_machine.transition_to(&"Dodge")


## Moves to Fall when the body has left the ground.
func try_fall() -> bool:
	if player.is_on_floor():
		return false
	return state_machine.transition_to(&"Fall")


## True when sprint is held, there is input and stamina is available.
func wants_sprint() -> bool:
	return (
		Input.is_action_pressed(&"sprint")
		and player.has_move_input()
		and not player.stamina.is_winded()
		and player.stamina.current > 0.0
	)
