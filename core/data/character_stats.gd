class_name CharacterStats
extends Resource
## Tunable numbers for an on-foot character (the player today, humanoid enemies later).
##
## Instances live in `.tres` files (see `actors/player/player_stats.tres`); gameplay
## scripts read these fields and never hard-code feel values. Distances are metres,
## times seconds, angles radians unless a name says `_degrees`.

@export_group("Locomotion")
## Walk speed (m/s) while moving without sprint.
@export var move_speed: float = 3.0
## Sprint speed (m/s).
@export var sprint_speed: float = 6.0
## Horizontal acceleration (m/s^2) towards the desired velocity.
@export var acceleration: float = 28.0
## Horizontal deceleration (m/s^2) when there is no input.
@export var deceleration: float = 36.0
## How fast the model turns towards its facing direction (rad/s).
@export var turn_rate: float = 12.0
## Stick/WASD magnitude below which input counts as "no input".
@export var input_deadzone: float = 0.15

@export_group("Dodge")
## Roll travel distance (m) over `dodge_duration`.
@export var dodge_distance: float = 3.2
## Seconds the roll moves the player.
@export var dodge_duration: float = 0.45
## Seconds of stationary recovery after the roll movement ends.
@export var dodge_recovery: float = 0.15
## Seconds after dodge start before i-frames begin.
@export var iframe_start: float = 0.05
## Length of the i-frame window in seconds (design range 0.2-0.4).
@export var iframe_duration: float = 0.3
## Backstep (dodge with no input) travel distance (m).
@export var backstep_distance: float = 1.8
## Seconds the backstep moves the player.
@export var backstep_duration: float = 0.3

@export_group("Stamina")
@export var stamina_max: float = 100.0
## Stamina regained per second once the regen delay has elapsed.
@export var stamina_regen_rate: float = 30.0
## Seconds after any spend before regen resumes.
@export var stamina_regen_delay: float = 1.0
## Seconds the character stays winded (actions refused) after hitting zero.
@export var winded_duration: float = 1.5
@export var dodge_stamina_cost: float = 20.0
## Stamina drained per second while sprinting.
@export var sprint_stamina_per_second: float = 12.0

@export_group("Stagger")
## Seconds the stagger stub holds the player before returning to idle.
@export var stagger_duration: float = 0.5

@export_group("Lock-on")
## Maximum distance (m) at which a target can be acquired.
@export var lock_on_range: float = 18.0
## Distance (m) beyond which an existing lock breaks.
@export var lock_break_range: float = 24.0
## Half-angle of the acquisition cone around the view direction, in degrees.
@export var lock_cone_half_angle_degrees: float = 50.0
## Seconds of lost line of sight tolerated before the lock breaks.
@export var lock_los_grace: float = 0.5
## Height above the player's origin that line-of-sight rays start from.
@export var lock_eye_height: float = 0.8
