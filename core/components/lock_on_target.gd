class_name LockOnTarget
extends Node3D
## Marks an actor as lockable. Add as a child of the enemy; position it at the
## point the camera and marker should frame (chest height). The player's
## `LockOnSelector` finds every enabled target through the [constant GROUP] group.

## Emitted when the player locks onto or releases this target (HUD marker hook).
signal locked_changed(is_locked: bool)

## Scene-tree group all lockable targets join.
const GROUP: StringName = &"lock_on_targets"

## Disabled targets (dead enemies) are skipped by the selector.
@export var enabled: bool = true

var is_locked: bool = false


func _ready() -> void:
	add_to_group(GROUP)


## World position that framing, range and line-of-sight checks use.
func get_lock_position() -> Vector3:
	return global_position


## Called by the selector. Emits [signal locked_changed] only on a real change.
func set_locked(value: bool) -> void:
	if is_locked == value:
		return
	is_locked = value
	locked_changed.emit(value)
