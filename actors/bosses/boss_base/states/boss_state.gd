class_name BossState
extends State
## Base for boss FSM states. Resolves the owning BossBase through the StateMachine
## parent, so it works both in scenes and when built ad-hoc in tests.

var boss: BossBase = null


func _ready() -> void:
	var machine := get_parent() as StateMachine
	boss = machine.get_parent() as BossBase if machine != null else null
