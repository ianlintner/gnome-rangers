extends Node
## Test double for a health/stamina component: records that `restore_full` was called.

var refilled: int = 0


func restore_full() -> void:
	refilled += 1
