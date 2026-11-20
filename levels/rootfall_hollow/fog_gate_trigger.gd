class_name FogGateTrigger
extends Area3D
## Placeholder fog-gate entry trigger for the boss arena.
##
## Card 7 owns the real fog-gate kit (seal, boss bar). Until it lands, this
## trigger announces the encounter on the shared bus so card 7's kit and the HUD
## can subscribe to the same event: `EventBus.boss_engaged(boss)`. When the real
## kit replaces this node, it must emit the same signal.

## Emitted once, the first time the player body enters the gate.
signal entered(body: Node3D)

## The boss node announced on `EventBus.boss_engaged`. Optional until card 7 lands.
@export var boss: Node3D = null

var _engaged: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	GameState.run_reset.connect(_on_run_reset)


func _on_body_entered(body: Node3D) -> void:
	if _engaged:
		return
	_engaged = true
	entered.emit(body)
	EventBus.boss_engaged.emit(boss)


func _on_run_reset() -> void:
	_engaged = false
