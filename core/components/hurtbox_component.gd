class_name HurtboxComponent
extends Area3D
## Receives hits for an actor. Minimal version: card 5 adds damage mitigation,
## poise and the weak-point multiplier on top of this API.
##
## While [member invulnerable] is true (dodge i-frames) hits are ignored. The
## owning actor wires `hit_received` to its health; the hurtbox never reaches up.

## Emitted when a hit lands. `amount` is raw damage; `source` may be null.
signal hit_received(amount: float, source: Node)
## Emitted when a hit was ignored because of invulnerability.
signal hit_ignored(amount: float, source: Node)

## True during i-frames. Set by the actor's states, not by attackers.
var invulnerable: bool = false


func _init() -> void:
	# Layer `hurtbox` (7), scans nothing: hitboxes detect it, not the other way round.
	collision_layer = 1 << 6
	collision_mask = 0
	monitoring = false


## Applies a hit. Returns true if it landed, false if i-frames ignored it.
func receive_hit(amount: float, source: Node = null) -> bool:
	if invulnerable:
		hit_ignored.emit(amount, source)
		return false
	hit_received.emit(amount, source)
	return true
