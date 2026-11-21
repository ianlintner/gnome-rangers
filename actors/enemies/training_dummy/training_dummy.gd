class_name TrainingDummy
extends CharacterBody3D
## A stationary target with health, poise and a head weak point, for the sandbox and
## for combat tests. It reacts visibly to a poise break (tilts back) and to death
## (falls over, stops being lockable). [method reset] stands it back up.

## Health and poise tuning; see `training_dummy_stats.tres`.
@export var stats: CombatStats
## Degrees the model tilts back while staggered or dead.
@export var stagger_tilt_degrees: float = 20.0
@export var death_tilt_degrees: float = 80.0

@onready var health: HealthComponent = $Health
@onready var poise: PoiseComponent = $Poise
@onready var hurtbox: HurtboxComponent = $Hurtbox
@onready var head_hurtbox: HurtboxComponent = $HeadHurtbox
@onready var lock_on_target: LockOnTarget = $LockOnTarget
@onready var model: Node3D = $Model


func _ready() -> void:
	if stats == null:
		stats = CombatStats.new()
	health.apply_stats(stats)
	poise.apply_stats(stats)
	health.died.connect(_on_died)
	poise.poise_broken.connect(_on_poise_broken)
	poise.stagger_ended.connect(_on_stagger_ended)


## Heals fully, clears poise and stands the dummy back up.
func reset() -> void:
	health.reset()
	poise.apply_stats(stats)
	lock_on_target.enabled = true
	_tilt(0.0)


func _on_died() -> void:
	lock_on_target.enabled = false
	_tilt(death_tilt_degrees)


func _on_poise_broken() -> void:
	if not health.is_dead():
		_tilt(stagger_tilt_degrees)


func _on_stagger_ended() -> void:
	if not health.is_dead():
		_tilt(0.0)


func _tilt(degrees: float) -> void:
	model.rotation.x = deg_to_rad(degrees)
