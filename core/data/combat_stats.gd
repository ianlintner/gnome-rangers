class_name CombatStats
extends Resource
## Health and poise tuning for any actor that can be hurt (player, mount, bosses, dummies).
##
## Instances live in `.tres` files next to the actor; [HealthComponent] and
## [PoiseComponent] copy these on `apply_stats`.

@export_group("Health")
@export var max_health: float = 100.0

@export_group("Poise")
## Accumulated poise damage that breaks poise and staggers the actor.
@export var poise_max: float = 50.0
## Seconds without poise damage before poise starts recovering.
@export var poise_regen_delay: float = 2.0
## Poise damage recovered per second once recovery starts.
@export var poise_regen_rate: float = 20.0
## Seconds the actor stays staggered after a poise break.
@export var stagger_duration: float = 1.0
## Seconds the riposte window stays open after a poise break.
@export var riposte_duration: float = 1.5
## Damage multiplier applied to hits that land inside the riposte window.
@export var riposte_damage_multiplier: float = 1.5
