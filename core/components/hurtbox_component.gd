class_name HurtboxComponent
extends Area3D
## Receives hits for an actor and routes them to its [HealthComponent] and
## [PoiseComponent].
##
## An actor may own several hurtboxes (body, head); a weak point is simply one with a
## `damage_multiplier` above 1. While [member invulnerable] is true (dodge i-frames)
## hits are ignored. Hits from the same [member faction] are ignored too, so no
## friendly fire. The hurtbox never reaches up: actors react to its signals.

## Emitted when a hit lands. `amount` is the damage applied after multipliers.
signal hit_received(amount: float, source: Node)
## Emitted when a hit was ignored (i-frames, dead target or same faction).
signal hit_ignored(amount: float, source: Node)
## Emitted with the full [DamageInfo] of a landed hit (knockback, hit position, flags).
signal damaged(info: DamageInfo)

## Multiplier on incoming damage; above 1 marks a weak point such as the head.
@export var damage_multiplier: float = 1.0
## Side this hurtbox belongs to (`player` or `enemy`); hitboxes skip their own side.
@export var faction: StringName = &"enemy"
## Where arrows stick. Empty means the hurtbox itself, which follows its bone or body.
@export var stick_anchor_path: NodePath
@export var health_path: NodePath = ^"../Health"
@export var poise_path: NodePath = ^"../Poise"

## True during i-frames. Set by the actor's states, not by attackers.
var invulnerable: bool = false
## The actor this hurtbox belongs to (the scene owner, else the parent).
var actor: Node = null
var health: HealthComponent = null
var poise: PoiseComponent = null


func _init() -> void:
	# Layer `hurtbox` (7), scans nothing: hitboxes detect it, not the other way round.
	collision_layer = 1 << 6
	collision_mask = 0
	monitoring = false


func _ready() -> void:
	if actor == null:
		actor = owner if owner != null else get_parent()
	health = get_node_or_null(health_path) as HealthComponent
	poise = get_node_or_null(poise_path) as PoiseComponent


## True for hurtboxes that multiply damage (head and other weak points).
func is_weak_point() -> bool:
	return damage_multiplier > 1.0


## Node an arrow reparents to so it follows this body part.
func get_stick_anchor() -> Node:
	var anchor: Node = get_node_or_null(stick_anchor_path)
	return anchor if anchor != null else self


## Applies a hit. Returns true if it landed, false if it was ignored.
func receive_damage(info: DamageInfo) -> bool:
	if invulnerable or info.faction == faction or (health != null and health.is_dead()):
		hit_ignored.emit(info.amount, info.source)
		return false
	info.is_weak_point = is_weak_point()
	var amount: float = info.amount * damage_multiplier
	if poise != null and poise.riposte_open:
		amount *= poise.riposte_multiplier
	info.final_amount = amount
	if health != null:
		health.take_damage(amount)
	if poise != null:
		poise.take_poise_damage(info.poise_damage)
	hit_received.emit(amount, info.source)
	damaged.emit(info)
	EventBus.damage_dealt.emit(actor, amount, info.is_weak_point)
	EventBus.hit_feedback.emit(info)
	return true


## Convenience for plain damage without an attack: builds a [DamageInfo] with no faction.
func receive_hit(amount: float, source: Node = null) -> bool:
	var info := DamageInfo.new()
	info.amount = amount
	info.source = source
	info.hit_position = global_position
	return receive_damage(info)
