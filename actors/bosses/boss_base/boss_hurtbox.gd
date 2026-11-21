class_name BossHurtbox
extends HurtboxComponent
## Boss weakness rules, kept in a component so any future boss reuses them.
##
## The static [member damage_multiplier] still drives hitbox target selection (the
## head is always the preferred contact point). The effective multiplier depends on
## the hit: the head takes x2 from arrows and a smaller bonus from melee; the back
## takes a bonus only while the boss is staggered.

@export var zone: StringName = &"body"  # body | head | back
## Head multiplier for arrows.
@export_range(1.0, 5.0, 0.05) var arrow_multiplier: float = 2.0
## Head multiplier for everything else.
@export_range(1.0, 5.0, 0.05) var melee_weak_multiplier: float = 1.25
## Back multiplier while staggered.
@export_range(1.0, 5.0, 0.05) var back_stagger_multiplier: float = 1.5


func get_damage_multiplier(info: DamageInfo) -> float:
	if zone == &"head":
		return arrow_multiplier if info.damage_type == &"arrow" else melee_weak_multiplier
	if zone == &"back" and poise != null and poise.staggered:
		return back_stagger_multiplier
	return damage_multiplier
