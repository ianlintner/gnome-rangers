class_name Player
extends CharacterBody3D
## The playable gnome ranger: a CharacterBody3D that assembles components and a
## node state machine. States call the movement helpers here; this script owns no
## behaviour of its own beyond wiring and animation parameters.
##
## Facing convention: the body's forward is -Z (Godot default). Put the visual under
## `PlayerModel`; a GLB that faces +Z is rotated by PI on that node, never here.

## Stats used by every state; tuned in `player_stats.tres`.
@export var stats: CharacterStats
## Optional camera rig that defines "camera-relative". Falls back to the body's facing.
@export var camera_path: NodePath

## The camera rig movement is relative to, or null.
var camera: ThirdPersonCamera = null

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _anim_playback: AnimationNodeStateMachinePlayback = null

@onready var stamina: StaminaComponent = $Stamina
@onready var hurtbox: HurtboxComponent = $Hurtbox
@onready var state_machine: StateMachine = $StateMachine
@onready var lock_selector: LockOnSelector = $LockOnSelector
@onready var model: Node3D = $PlayerModel
@onready var anim_tree: AnimationTree = $PlayerModel/AnimationTree


func _ready() -> void:
	if stats == null:
		stats = CharacterStats.new()
	if not camera_path.is_empty():
		camera = get_node_or_null(camera_path) as ThirdPersonCamera
	stamina.apply_stats(stats)
	stamina.changed.connect(_on_stamina_changed)
	anim_tree.active = true
	_anim_playback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	state_machine.state_changed.connect(_on_state_changed)
	state_machine.transition_to(&"Idle")


func _physics_process(_delta: float) -> void:
	_update_locomotion_blend()


## Raw movement input; x is right, y is back (Godot's get_vector convention).
func get_move_input() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")


## True when the raw input is past the deadzone.
func has_move_input() -> bool:
	return get_move_input().length() > stats.input_deadzone


## Horizontal world direction of the movement input, camera-relative, length <= 1.
func get_move_direction() -> Vector3:
	var input: Vector2 = get_move_input()
	if input.length() <= stats.input_deadzone:
		return Vector3.ZERO
	var basis: Basis = get_view_basis()
	return (basis.x * input.x + basis.z * input.y).limit_length(1.0)


## Flat yaw basis of the camera (or of the body when no camera is assigned).
func get_view_basis() -> Basis:
	if camera != null:
		return camera.get_flat_basis()
	return Basis(Vector3.UP, rotation.y)


## Horizontal forward of the view, used by the lock-on cone.
func get_view_forward() -> Vector3:
	return -get_view_basis().z


## Horizontal direction the body currently faces.
func get_facing() -> Vector3:
	return Vector3(-global_basis.z.x, 0.0, -global_basis.z.z).normalized()


## Moves horizontally towards `desired` (world velocity) with `accel`, applies gravity
## and calls move_and_slide. Every state ends its physics_update through this.
func locomote(desired: Vector3, accel: float, delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(Vector3(desired.x, 0.0, desired.z), accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
	move_and_slide()


## Turns the body to face `direction` at the stats turn rate. Zero is ignored.
func face_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	var target_yaw: float = atan2(-direction.x, -direction.z)
	rotation.y = rotate_toward(rotation.y, target_yaw, stats.turn_rate * delta)


## Snaps the body to face `direction` immediately (dodge start).
func snap_facing(direction: Vector3) -> void:
	if direction.length_squared() > 0.0001:
		rotation.y = atan2(-direction.x, -direction.z)


## Facing step shared by walking states: strafe at the lock-on target while locked,
## otherwise turn towards `move_direction`.
func update_facing(move_direction: Vector3, delta: float, allow_strafe: bool = true) -> void:
	var target: Node3D = lock_selector.current_target
	if allow_strafe and target != null:
		var to_target: Vector3 = target.global_position - global_position
		to_target.y = 0.0
		face_direction(to_target, delta)
	else:
		face_direction(move_direction, delta)


## Puts the player in the stagger stub state (card 5 will call this on poise break).
func stagger() -> void:
	state_machine.transition_to(&"Stagger")


func _update_locomotion_blend() -> void:
	var local: Vector3 = global_basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
	var scale_speed: float = maxf(stats.sprint_speed, 0.01)
	# BlendSpace2D axes: x = strafe right, y = forward (-Z) speed, both in [-1, 1].
	anim_tree.set("parameters/Locomotion/blend_position", Vector2(local.x, -local.z) / scale_speed)


func _on_state_changed(_from_name: StringName, to_name: StringName) -> void:
	if _anim_playback == null:
		return
	_anim_playback.travel(&"Dodge" if to_name == &"Dodge" else &"Locomotion")


func _on_stamina_changed(current: float, maximum: float) -> void:
	EventBus.player_stamina_changed.emit(current, maximum)
