class_name Checkpoint
extends Node3D
## Mushroom Ring checkpoint: interact to rest.
##
## Resting makes this ring the active respawn point (`GameState.set_checkpoint`), refills the
## resting player ([method Player.restore_vitals]) and resets the world (the boss) through
## `GameState.reset_run`. Everything else learns about it from `EventBus.checkpoint_rested`.

@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	_interactable.interacted.connect(_on_interacted)


## Rests the `actor` here. Public so tests and scripted bots can call it directly.
func rest(actor: Node) -> void:
	GameState.set_checkpoint(self, global_transform)
	var player := actor as Player
	if player != null:
		player.restore_vitals()
	GameState.reset_run()
	EventBus.checkpoint_rested.emit(self)


func _on_interacted(actor: Node) -> void:
	rest(actor)
