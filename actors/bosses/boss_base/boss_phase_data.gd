class_name BossPhaseData
extends Resource
## Tuning for one boss phase. Phase 1 is the base data on the boss; phase 2 (and
## beyond) lives in `.tres` resources referenced by the boss.

## Fraction of maximum health at which this phase begins (e.g. 0.5).
@export_range(0.0, 1.0, 0.01) var hp_threshold: float = 0.5
## Moves available in this phase. Empty means "keep the base move set".
@export var moveset_override: Array[BossMoveData] = []
## Multiplies locomotion speed in this phase.
@export_range(0.1, 4.0, 0.05) var speed_multiplier: float = 1.0
## Multiplies move cooldowns in this phase (below 1 = faster recoveries).
@export_range(0.1, 4.0, 0.05) var recovery_multiplier: float = 1.0
## Action fired on entry: `roar`, `none`, ... Handled by the boss's phase controller.
@export var on_enter_action: StringName = &"none"
## How long the on-enter action locks the boss's brain, in seconds.
@export_range(0.0, 20.0, 0.1) var on_enter_duration: float = 1.2


func effective_moves(base: Array[BossMoveData]) -> Array[BossMoveData]:
	return moveset_override if not moveset_override.is_empty() else base
