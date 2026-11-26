class_name MountStats
extends Resource
## Tunable numbers for the cat mount: speeds, turning, mounting, pounce, knock-off and
## flee/return. Health and poise live in a separate [CombatStats] on the mount scene.
##
## Instances live in `.tres` files (see `actors/mount/mount_stats.tres`); gameplay scripts
## read these fields and never hard-code feel values. Distances are metres, times seconds,
## speeds m/s.

@export_group("Locomotion")
## Ridden speed without sprint. Must exceed the on-foot walk speed.
@export var walk_speed: float = 5.5
## Ridden speed while sprinting (gallop). Must exceed the on-foot sprint speed.
@export var gallop_speed: float = 10.0
## Speed at which the cat runs to the player after `call_mount` or on return from fleeing.
@export var call_speed: float = 8.5
## Horizontal acceleration towards the desired velocity.
@export var acceleration: float = 22.0
## Horizontal deceleration when there is no input.
@export var deceleration: float = 30.0
## Turn rate (rad/s) while walking.
@export var turn_rate: float = 9.0
## Turn rate (rad/s) at a gallop (wider arcs than a walk).
@export var gallop_turn_rate: float = 4.5
## Fraction of walk speed kept while the rider aims the bow.
@export var aim_speed_multiplier: float = 0.6
## Speed above which the cat counts as galloping for pounce eligibility.
@export var gallop_threshold: float = 7.5

@export_group("Mounting")
## Maximum distance (m) from the rider to the cat for `interact` to mount.
@export var mount_range: float = 2.2
## Seconds the rider takes to climb into the saddle.
@export var mount_duration: float = 0.35
## Seconds the dismount takes before the rider is free again.
@export var dismount_duration: float = 0.25
## Where the dismounting rider lands, in the cat's local space (-Z forward, +X right).
@export var dismount_offset: Vector3 = Vector3(-1.1, 0.0, 0.0)
## Rider origin (feet) relative to the saddle bone, in the cat's frame; seats the hips.
@export var rider_offset: Vector3 = Vector3(0.0, -0.46, 0.0)
## Seat height (m) above the cat's origin when its model has no `saddle` bone.
@export var fallback_seat_height: float = 0.9
## Stamina the rider pays per second while sprinting mounted.
@export var sprint_stamina_per_second: float = 8.0
## Seconds between `call_mount` presses that are accepted.
@export var call_cooldown: float = 1.0
## Distance (m) from the rider at which a called cat stops and waits.
@export var call_stop_distance: float = 1.4
## Seconds between path target refreshes while the cat is called.
@export var path_refresh_interval: float = 0.25

@export_group("Pounce")
## Farthest lock-on target distance (m) a pounce can start from.
@export var pounce_max_range: float = 9.0
## Closest target distance (m) for a pounce; closer targets are simply bitten.
@export var pounce_min_range: float = 2.0
## Seconds of crouch before the leap.
@export var pounce_windup: float = 0.25
## Seconds the cat is airborne.
@export var pounce_leap_time: float = 0.55
## Seconds of recovery after landing.
@export var pounce_recovery: float = 0.5
## Apex height (m) of the leap arc.
@export var pounce_height: float = 1.3
## Distance (m) short of the target's centre where the cat lands.
@export var pounce_land_distance: float = 1.0
## Seconds before the next pounce can start, counted from the landing.
@export var pounce_cooldown: float = 4.0
## Damage, poise damage, hitbox shape and timings of the landing strike.
@export var pounce_attack: AttackData

@export_group("Knock-off")
## A single hit on the rider or the cat with at least this much damage throws the rider.
@export var knock_off_damage: float = 26.0
## A single hit with at least this much poise damage throws the rider.
@export var knock_off_poise_damage: float = 30.0
## Seconds the thrown rider is staggered.
@export var knock_off_stagger: float = 1.2
## Horizontal speed (m/s) a thrown rider is flung away from the hit.
@export var knock_off_speed: float = 5.0
## Upward speed (m/s) of the throw.
@export var knock_off_lift: float = 3.5
## Horizontal deceleration (m/s^2) of the tumble.
@export var knock_off_drag: float = 6.0

@export_group("Hurt and flee")
## Seconds the cat flinches after its poise breaks.
@export var hurt_duration: float = 0.5
## Speed (m/s) at which the cat bolts at zero health.
@export var flee_speed: float = 9.0
## Distance (m) the cat runs from where it fell before it stops.
@export var flee_distance: float = 14.0
## Seconds after reaching zero health before the cat comes back.
@export var flee_cooldown: float = 12.0
