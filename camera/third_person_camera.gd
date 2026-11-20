class_name ThirdPersonCamera
extends Node3D
## Orbit camera on a SpringArm3D. Follows `target`, reads mouse and stick look,
## collides with the `world` layer and eases into a lock-on framing.
##
## Look sensitivity and invert-Y are read from `user://settings.cfg` (section
## `controls`, keys `look_sensitivity` and `invert_y`) with defaults 1.0 / false;
## card 9 owns the settings screen that writes them.

const SETTINGS_PATH: String = "user://settings.cfg"
const SETTINGS_SECTION: String = "controls"

## Feel numbers; see `default_camera_tuning.tres`.
@export var tuning: CameraTuning
## The node to follow (normally the player).
@export var target_path: NodePath

## Heading in radians; the flat basis of this angle defines camera-relative movement.
var yaw: float = 0.0
## Pitch in radians; negative looks down at the player.
var pitch: float = 0.0
var look_sensitivity: float = 1.0
var invert_y: bool = false
## Node being framed while locked on, or null.
var lock_target: Node3D = null

var _target: Node3D = null
var _base_arm: float = 0.0

@onready var camera: Camera3D = $SpringArm3D/Camera3D
@onready var _arm: SpringArm3D = $SpringArm3D


func _ready() -> void:
	if tuning == null:
		tuning = CameraTuning.new()
	top_level = true
	_load_settings()
	_base_arm = tuning.arm_length
	_arm.spring_length = _base_arm
	_arm.margin = tuning.collision_margin
	pitch = deg_to_rad(tuning.default_pitch_degrees)
	if not target_path.is_empty():
		set_target(get_node_or_null(target_path) as Node3D)
	EventBus.lock_on_changed.connect(_on_lock_on_changed)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_rotation()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var scale_factor: float = tuning.mouse_radians_per_pixel * look_sensitivity
		look(-motion.relative.x * scale_factor, -motion.relative.y * scale_factor)


func _process(delta: float) -> void:
	if _target != null:
		var goal: Vector3 = _target.global_position + Vector3.UP * tuning.pivot_height
		global_position = global_position.lerp(goal, 1.0 - exp(-tuning.follow_smoothing * delta))
	if is_instance_valid(lock_target) and _target != null:
		_frame_lock_target(delta)
	else:
		var stick: Vector2 = Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
		var speed: float = tuning.stick_radians_per_second * look_sensitivity * delta
		look(-stick.x * speed, -stick.y * speed)
	_arm.spring_length = lerpf(_arm.spring_length, _desired_arm(), 1.0 - exp(-5.0 * delta))
	_apply_rotation()


## Sets the node to follow and snaps the rig onto it.
func set_target(target: Node3D) -> void:
	_target = target
	if _target != null:
		global_position = _target.global_position + Vector3.UP * tuning.pivot_height


## Adds a yaw/pitch delta in radians, applying the invert-Y setting and pitch limits.
func look(yaw_delta: float, pitch_delta: float) -> void:
	yaw = wrapf(yaw + yaw_delta, -PI, PI)
	var sign_y: float = -1.0 if invert_y else 1.0
	pitch = clampf(
		pitch + pitch_delta * sign_y,
		deg_to_rad(tuning.pitch_min_degrees),
		deg_to_rad(tuning.pitch_max_degrees)
	)
	_apply_rotation()


## Yaw-only basis: camera-relative movement is built from this, ignoring pitch.
func get_flat_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func _frame_lock_target(delta: float) -> void:
	var to_target: Vector3 = lock_target.global_position - _target.global_position
	to_target.y = 0.0
	if to_target.length_squared() > 0.0001:
		var goal_yaw: float = atan2(-to_target.x, -to_target.z)
		var blend: float = 1.0 - exp(-tuning.lock_on_smoothing * delta)
		yaw = lerp_angle(yaw, goal_yaw, blend)
		var goal_pitch: float = deg_to_rad(tuning.lock_on_pitch_degrees)
		pitch = lerpf(pitch, goal_pitch, blend)


func _desired_arm() -> float:
	var extra: float = tuning.lock_on_extra_arm if is_instance_valid(lock_target) else 0.0
	return _base_arm + extra


func _apply_rotation() -> void:
	rotation.y = yaw
	_arm.rotation.x = pitch


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	look_sensitivity = float(config.get_value(SETTINGS_SECTION, "look_sensitivity", 1.0))
	invert_y = bool(config.get_value(SETTINGS_SECTION, "invert_y", false))


func _on_lock_on_changed(target: Node) -> void:
	lock_target = target as Node3D
