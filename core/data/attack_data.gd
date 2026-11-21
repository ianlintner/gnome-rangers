class_name AttackData
extends Resource
## One attack, described entirely as data: numbers, timings, hitbox volume and animation.
##
## Instances live in `.tres` files (`actors/player/attacks/`, later boss moves) and are
## consumed by [AttackRunner] and [HitboxComponent]. Gameplay scripts read these fields
## and never hard-code combat numbers. Times are seconds, distances metres.

## Volume of the hitbox while the attack is active.
enum HitShape { BOX, SPHERE, CAPSULE }

@export_group("Damage")
## Health removed from an unmitigated target.
@export var damage: float = 10.0
## Poise removed from the target; a full poise bar staggers it.
@export var poise_damage: float = 10.0
## Stamina paid by the attacker to start the attack (0 for free attacks such as AI moves).
@export var stamina_cost: float = 0.0
## Impulse (m/s) pushed along the attack direction; consumers decide how to apply it.
@export var knockback: float = 0.0
## Seconds of global time-scale dip when the attack lands (0 disables hit-stop).
@export var hit_stop_duration: float = 0.0
## Engine time scale held during the hit-stop (0.05 is a near freeze).
@export var hit_stop_time_scale: float = 0.05

@export_group("Timing")
## Seconds from start until the hitbox opens (the telegraph).
@export var windup: float = 0.2
## Seconds the hitbox stays open.
@export var active: float = 0.1
## Seconds after the hitbox closes before the actor is free again.
@export var recovery: float = 0.3
## Seconds from start from which a dodge may cancel the attack.
@export var dodge_cancel_start: float = 0.2
## Seconds from start from which a buffered follow-up input chains into the next attack.
@export var chain_window_start: float = 0.25

@export_group("Hitbox")
@export var hit_shape: HitShape = HitShape.BOX
## Box extents, sphere radius in `x`, or capsule radius in `x` and height in `y`.
@export var hit_size: Vector3 = Vector3(1.0, 1.0, 1.0)
## Hitbox centre in the attacker's local space (-Z is forward).
@export var hit_offset: Vector3 = Vector3(0.0, 0.5, -0.8)

@export_group("Animation")
## Clip the attack plays. Method tracks on it call the runner's open/close hit window.
@export var animation_name: StringName = &""

@export_group("Charge")
## Seconds of holding that reach full charge (0 means the attack cannot be charged).
@export var charge_time_max: float = 0.0
## Damage multiplier at full charge (linear from 1.0 at no charge).
@export var charge_damage_multiplier: float = 1.0
## Poise-damage multiplier at full charge (linear from 1.0 at no charge).
@export var charge_poise_multiplier: float = 1.0


## Seconds from start to the end of recovery.
func total_duration() -> float:
	return windup + active + recovery
