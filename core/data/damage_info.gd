class_name DamageInfo
extends RefCounted
## Value object describing one hit as it travels from a [HitboxComponent] to a
## [HurtboxComponent]. The hurtbox fills in the post-mitigation fields.

## Raw damage before weak-point and riposte multipliers.
var amount: float = 0.0
var poise_damage: float = 0.0
## Knockback impulse in m/s along [member direction].
var knockback: float = 0.0
var hit_stop_duration: float = 0.0
var hit_stop_time_scale: float = 1.0
## The attacking actor, or null.
var source: Node = null
## Faction of the attacker (e.g. `player`, `enemy`); hurtboxes of the same faction ignore it.
var faction: StringName = &""
## World-space contact point.
var hit_position: Vector3 = Vector3.ZERO
## World-space unit vector pointing from the attacker towards the target.
var direction: Vector3 = Vector3.ZERO
## The attack this hit came from, if any.
var attack: AttackData = null
## Damage category (`melee`, `arrow`, `aoe`, ...). Set by the hitbox so hurtboxes can
## apply conditional weak-point rules (e.g. head x2 vs arrows).
var damage_type: StringName = &"melee"
## Set by the hurtbox: true when a weak-point hurtbox took the hit.
var is_weak_point: bool = false
## Set by the hurtbox: damage actually applied after multipliers.
var final_amount: float = 0.0


## Builds a hit from `data`, scaling damage and poise by `charge_ratio` (0..1).
static func from_attack(
	data: AttackData, hit_source: Node, hit_faction: StringName, charge_ratio: float = 0.0
) -> DamageInfo:
	var info := DamageInfo.new()
	var charge: float = clampf(charge_ratio, 0.0, 1.0)
	info.amount = data.damage * lerpf(1.0, data.charge_damage_multiplier, charge)
	info.poise_damage = data.poise_damage * lerpf(1.0, data.charge_poise_multiplier, charge)
	info.knockback = data.knockback
	info.hit_stop_duration = data.hit_stop_duration
	info.hit_stop_time_scale = data.hit_stop_time_scale
	info.source = hit_source
	info.faction = hit_faction
	info.attack = data
	return info
