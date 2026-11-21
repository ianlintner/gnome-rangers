class_name BossPhaseController
extends Node
## Watches a HealthComponent and enters each configured phase exactly once when
## the health fraction drops to that phase's threshold. Phase data is data-only,
## so new bosses need no new controller code.

signal phase_entered(phase: int, data: BossPhaseData)

@export var health_path: NodePath = ^"../Health"
## Phase 2+ data, in ascending threshold order. Phase 1 is implicitly full health.
@export var phases: Array[BossPhaseData] = []

var phase: int = 1
var health: HealthComponent = null
var _entered: Dictionary = {}


func _ready() -> void:
	health = get_node_or_null(health_path) as HealthComponent
	if health != null:
		health.changed.connect(_on_health_changed)
	reset()


func reset() -> void:
	phase = 1
	_entered.clear()
	if health != null and not health.changed.is_connected(_on_health_changed):
		health.changed.connect(_on_health_changed)


func _on_health_changed(current: float, maximum: float) -> void:
	if health == null or health.is_dead() or maximum <= 0.0:
		return
	var fraction: float = current / maximum
	for index: int in range(phases.size()):
		var next_phase: int = index + 2
		if _entered.has(next_phase):
			continue
		var data: BossPhaseData = phases[index]
		if data == null or fraction > data.hp_threshold:
			continue
		_entered[next_phase] = true
		phase = next_phase
		phase_entered.emit(phase, data)
