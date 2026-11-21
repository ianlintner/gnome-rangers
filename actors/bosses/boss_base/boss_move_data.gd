class_name BossMoveData
extends Resource
## One boss move: the distance band in which it is eligible, its pick weight, its
## cooldown and the [AttackData] the shared AttackRunner executes. All tuning lives
## in `.tres` files; state code never hard-codes damage or timings.

@export var id: StringName = &"slam"
## Eligible when the horizontal distance to the target is within [min_range, max_range].
@export_range(0.0, 100.0, 0.1) var min_range: float = 0.0
@export_range(0.0, 100.0, 0.1) var max_range: float = 4.0
## Relative chance of being picked inside its band; zero disables the move.
@export_range(0.0, 100.0, 0.1) var weight: float = 1.0
## Seconds before this move can be picked again (scaled by phase recovery multiplier).
@export_range(0.0, 60.0, 0.05) var cooldown: float = 2.0
@export var attack: AttackData = null
## Optional second AttackData fired from the feet when the main attack's hit window
## opens (e.g. the slam's shockwave ring). Timed entirely in data.
@export var followup_attack: AttackData = null
## Grab-and-throw: on catch the target is launched this fast (m/s) away from the boss.
@export_range(0.0, 40.0, 0.5) var throw_speed: float = 0.0
@export_range(0.0, 20.0, 0.5) var throw_lift: float = 0.0
## Optional relative path to a VFX scene spawned for the windup telegraph.
@export_file("*.tscn", "*.gd") var windup_vfx_path: String = ""
## Optional animation clip name played on the model's AnimationPlayer at windup.
@export var windup_animation: StringName = &""
## Name of a special state script to run instead of the generic Attack state.
## Empty means the generic, AttackData-driven boss Attack state.
@export var state_script: StringName = &""
## Only eligible from this phase onward (1-based). Zero means every phase.
@export_range(0, 10) var min_phase: int = 0


func is_eligible(distance: float, phase: int) -> bool:
	return (
		weight > 0.0
		and distance >= min_range
		and distance <= max_range
		and (min_phase == 0 or phase >= min_phase)
	)
