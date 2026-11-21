class_name CameraTuning
extends Resource
## Feel numbers for the third-person camera rig (`camera/third_person_camera.tscn`).
## User-facing sensitivity and invert come from settings, not from here.

@export_group("Orbit")
## SpringArm3D length (m) from the pivot to the camera.
@export var arm_length: float = 3.6
## Height (m) above the followed node's origin that the camera pivots around.
@export var pivot_height: float = 1.1
@export var pitch_min_degrees: float = -60.0
@export var pitch_max_degrees: float = 70.0
## Pitch (degrees) the camera settles at when it has no look input.
@export var default_pitch_degrees: float = -18.0
## Mouse sensitivity in radians per pixel at settings multiplier 1.0.
@export var mouse_radians_per_pixel: float = 0.0025
## Stick look speed in radians per second at settings multiplier 1.0.
@export var stick_radians_per_second: float = 3.2

@export_group("Aim")
## SpringArm3D length (m) while aiming the bow (over-the-shoulder).
@export var aim_arm_length: float = 1.8
## Sideways camera offset (m) while aiming; positive puts the player on the left.
@export var aim_shoulder_offset: float = 0.6
## Field of view (degrees) while aiming.
@export var aim_fov: float = 50.0
## Exponential rate at which arm length, offset and fov ease into and out of aim mode.
@export var aim_smoothing: float = 10.0

@export_group("Smoothing")
## Exponential follow rate for the pivot position (1/s); higher is snappier.
@export var follow_smoothing: float = 14.0
## Exponential rate at which yaw/pitch ease towards the lock-on framing.
@export var lock_on_smoothing: float = 6.0
## Pitch (degrees) the camera prefers while locked on.
@export var lock_on_pitch_degrees: float = -14.0
## Extra pull-back (m) while locked on so both the player and target stay framed.
@export var lock_on_extra_arm: float = 1.2
## Margin (m) the arm keeps from geometry.
@export var collision_margin: float = 0.2
