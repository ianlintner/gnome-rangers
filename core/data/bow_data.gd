class_name BowData
extends Resource
## Tuning for a bow and its arrows. Shared by the player and the mounted bow (card 6).

## Damage, poise, knockback and hit-stop of a fully drawn arrow.
@export var arrow_attack: AttackData

@export_group("Draw")
## Seconds of drawing that reach a full draw.
@export var draw_time_full: float = 1.0
## Damage fraction of a quick shot (draw ratio 0); scales linearly to 1.0 at full draw.
@export var min_damage_ratio: float = 0.3
## Arrow speed (m/s) of a quick shot.
@export var min_speed: float = 18.0
## Arrow speed (m/s) at full draw.
@export var max_speed: float = 42.0
## Seconds after firing before the next draw can begin.
@export var nock_time: float = 0.35

@export_group("Flight")
## Multiplier on the project gravity applied to a flying arrow.
@export var gravity_scale: float = 1.0
## Seconds an arrow may fly before it despawns.
@export var flight_lifetime: float = 4.0
## Distance (m) the aim ray searches for a target point.
@export var aim_range: float = 60.0
## Height (m) above the shooter's origin that arrows leave from.
@export var muzzle_height: float = 0.7

@export_group("Sticking")
## Seconds a stuck arrow stays before it despawns.
@export var stuck_lifetime: float = 12.0
## Stuck arrows allowed at once; the oldest is recycled beyond this.
@export var max_stuck_arrows: int = 24
## Distance (m) the arrow tip sinks into what it hits.
@export var embed_depth: float = 0.08
## Arrows created up front for the pool.
@export var pool_size: int = 8
