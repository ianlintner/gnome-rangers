extends Node
## Global run state, autoloaded as `GameState`.
##
## Deliberately small: it holds the last rested checkpoint, the transform the
## player respawns at, and the current boss reset tokens. It is not a general
## gameplay singleton — everything else belongs in a component or a state.

## Emitted when a checkpoint becomes the active respawn point.
signal checkpoint_set(checkpoint: Node)

## Emitted after `reset_run`, so listeners can put the world back to its start.
signal run_reset

## The checkpoint node the player last rested at, or null before the first rest.
var checkpoint: Node = null

## Where the player is placed on respawn. Falls back to `spawn_transform`.
var respawn_transform: Transform3D = Transform3D.IDENTITY

## Where the level starts the player when no checkpoint has been set.
var spawn_transform: Transform3D = Transform3D.IDENTITY

## Monotonic counter bumped whenever the world should reset (death, new run).
## Bosses and other world state watch this instead of being reset directly.
var reset_token: int = 0

var _boss_defeated: bool = false


## Records `checkpoint` as the active respawn point and copies its transform.
func set_checkpoint(checkpoint_node: Node, transform: Transform3D) -> void:
	checkpoint = checkpoint_node
	respawn_transform = transform
	checkpoint_set.emit(checkpoint_node)


## Called on death: returns the player to the last rested checkpoint.
func respawn_transform_for_player() -> Transform3D:
	if checkpoint != null and checkpoint is Node3D:
		return (checkpoint as Node3D).global_transform
	return respawn_transform if respawn_transform != Transform3D.IDENTITY else spawn_transform


## Tells every listener to put the world back to its starting state.
func reset_run() -> void:
	_boss_defeated = false
	reset_token += 1
	run_reset.emit()


## Marks the run as won. The victory screen listens for `EventBus.game_won`.
func mark_won() -> void:
	if _boss_defeated:
		return
	_boss_defeated = true
	EventBus.game_won.emit()


func is_won() -> bool:
	return _boss_defeated


## Test helper: clears all run state without emitting signals.
func clear() -> void:
	checkpoint = null
	respawn_transform = Transform3D.IDENTITY
	spawn_transform = Transform3D.IDENTITY
	reset_token = 0
	_boss_defeated = false
