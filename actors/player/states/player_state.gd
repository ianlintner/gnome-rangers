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


## Starts the first light attack when pressed and stamina pays for it.
func try_attack_light() -> bool:
	if not Input.is_action_just_pressed(&"attack_light") or player.moveset.light_chain.is_empty():
		return false
	var first: AttackData = player.moveset.light_chain[0]
	if not player.melee.start(first, player, player.stamina):
		return false
	return state_machine.transition_to(&"AttackLight")


## Enters the heavy attack's charge when pressed and stamina could pay for it.
func try_attack_heavy() -> bool:
	if not Input.is_action_just_pressed(&"attack_heavy"):
		return false
	if not player.melee.can_start(player.moveset.heavy, player.stamina):
		return false
	return state_machine.transition_to(&"AttackHeavy")


## Raises the bow while `aim` is held and the player is not winded.
func try_aim() -> bool:
	if not Input.is_action_pressed(&"aim") or player.stamina.is_winded():
		return false
	return state_machine.transition_to(&"Aim")


## Every combat entry point, in priority order: aim, heavy, light.
func try_combat() -> bool:
	return try_aim() or try_attack_heavy() or try_attack_light()


## Mounts the nearest cat in range when `interact` is pressed (through its Interactable).
func try_mount() -> bool:
	if not Input.is_action_just_pressed(&"interact"):
		return false
	var cat: CatMount = player.find_mount()
	if cat == null or not cat.can_be_mounted_by(player):
		return false
	return cat.interactable.interact(player)


## Whistles the cat over when `call_mount` is pressed.
func try_call_mount() -> bool:
	if not Input.is_action_just_pressed(&"call_mount"):
		return false
	var cat: CatMount = player.find_mount()
	return cat != null and cat.call_to(player)


## Uses the interactable the player stands in (rests at a checkpoint) on `interact`.
func try_interact() -> bool:
	if not Input.is_action_just_pressed(&"interact"):
		return false
	var target: Interactable = player.find_interactable()
	return target != null and target.interact(player)


## Interact-style inputs available on foot: mount first, then call, then other interactables.
func try_mount_actions() -> bool:
	return try_mount() or try_call_mount() or try_interact()


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
