class_name Checkpoint
extends Node3D
## Mushroom Ring checkpoint: interact to rest.
##
## Resting makes this ring the active respawn point (`GameState.set_checkpoint`),
## refills the resting actor's health and stamina when it exposes those
## components, and resets the world (the boss) through `GameState.reset_run`.
## Everything else learns about it from `EventBus.checkpoint_rested`.

## Component node names looked up on the resting actor. A component that is not
## present (e.g. before the combat core lands) is simply skipped.
const HEALTH_NODE: StringName = &"HealthComponent"
const STAMINA_NODE: StringName = &"StaminaComponent"
## Method each component exposes to refill itself.
const REFILL_METHOD: StringName = &"restore_full"

@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	_interactable.interacted.connect(_on_interacted)


## Rests the `actor` here. Public so tests and scripted bots can call it directly.
func rest(actor: Node) -> void:
	GameState.set_checkpoint(self, global_transform)
	_refill(actor, HEALTH_NODE)
	_refill(actor, STAMINA_NODE)
	GameState.reset_run()
	EventBus.checkpoint_rested.emit(self)


func _refill(actor: Node, component_name: StringName) -> void:
	if actor == null:
		return
	var component: Node = actor.get_node_or_null(NodePath(component_name))
	if component != null and component.has_method(REFILL_METHOD):
		component.call(REFILL_METHOD)


func _on_interacted(actor: Node) -> void:
	rest(actor)
