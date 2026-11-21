class_name MeleeMoveset
extends Resource
## The on-foot melee moves of an actor: a light chain, a chargeable heavy and the
## input-feel numbers that tie them together. Lives in a `.tres` (see
## `actors/player/player_moveset.tres`).

## Light attacks in chain order; pressing again inside the chain window advances.
@export var light_chain: Array[AttackData] = []
@export var heavy: AttackData
## Seconds an attack press is remembered so it fires as soon as the chain allows.
@export var input_buffer_time: float = 0.25
