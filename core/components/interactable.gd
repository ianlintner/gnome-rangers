class_name Interactable
extends Area3D
## Marks a world object the player can use with the `interact` action.
##
## Attach as a child of the object's scene. The player's interaction probe finds
## it through the `interact` physics layer, announces it through
## `EventBus.interaction_target_changed`, and calls [method interact] when the
## `interact` action is pressed. The owning scene reacts to [signal interacted]
## ("call down, signal up").

## Emitted when an actor uses this object. `actor` is the node that interacted.
signal interacted(actor: Node)

## Short verb shown by the HUD prompt, e.g. "Rest".
@export var prompt_text: String = "Interact"

## When false the object ignores [method interact] (e.g. a spent lever).
@export var enabled: bool = true


func _ready() -> void:
	# Named layer `interact` (bit 9); the interactable is only ever a target, never a scanner.
	collision_layer = 1 << 8
	collision_mask = 0
	monitoring = false


## Called by the actor's interaction probe. Returns true when the use was accepted.
func interact(actor: Node) -> bool:
	if not enabled:
		return false
	interacted.emit(actor)
	return true
