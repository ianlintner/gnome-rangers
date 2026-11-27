class_name BotInput
extends RefCounted
## Virtual gamepad for the bot-fight tests. Everything goes through `Input.action_press` /
## `action_release` on the project's named InputMap actions, so the player's states read the
## bot exactly as they read a human: no raw keycodes and no direct state-machine calls.
##
## Call [method begin_tick] first thing every physics tick (the bot runs before the player), then
## hold, tap or steer. A tap is pressed for one tick and released on the next, which is what
## `Input.is_action_just_pressed` needs to fire exactly once.

const MOVE_ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right"]
const LOOK_ACTIONS: Array[StringName] = [&"look_up", &"look_down", &"look_left", &"look_right"]
const BUTTON_ACTIONS: Array[StringName] = [
	&"attack_light",
	&"attack_heavy",
	&"dodge",
	&"sprint",
	&"lock_on",
	&"lock_switch_left",
	&"lock_switch_right",
	&"aim",
	&"fire",
	&"call_mount",
	&"interact",
]

## Look proportional gain: stick deflection per radian of aim error.
const LOOK_GAIN: float = 2.0

var _tapped: Array[StringName] = []
var _cooldown: Dictionary = {}


## Releases last tick's taps. Returns nothing; call once per physics tick before anything else.
func begin_tick() -> void:
	for action: StringName in _tapped:
		Input.action_release(action)
	_tapped.clear()
	for action: StringName in _cooldown.keys():
		var left: int = (_cooldown[action] as int) - 1
		if left <= 0:
			_cooldown.erase(action)
		else:
			_cooldown[action] = left


## Presses `action` for exactly one tick. Ignored while the action is still down or was tapped
## on the previous tick (a release tick is needed between two presses).
func tap(action: StringName) -> bool:
	if Input.is_action_pressed(action) or _cooldown.has(action):
		return false
	Input.action_press(action)
	_tapped.append(action)
	_cooldown[action] = 2
	return true


func hold(action: StringName, held: bool = true) -> void:
	if held:
		Input.action_press(action)
	elif Input.is_action_pressed(action):
		Input.action_release(action)


## Holds the move stick towards the world direction `direction` (horizontal), relative to the
## camera's flat basis as the player reads it. A zero direction centres the stick.
func steer(direction: Vector3, view: Basis) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		for action: StringName in MOVE_ACTIONS:
			Input.action_release(action)
		return
	flat = flat.normalized()
	# Player.get_move_direction() is basis.x * input.x + basis.z * input.y.
	var right: float = flat.dot(view.x)
	var back: float = flat.dot(view.z)
	_axis(&"move_left", &"move_right", right)
	_axis(&"move_forward", &"move_back", back)


## Deflects the look stick so the view direction `forward` turns towards `wanted`.
## Returns the remaining aim error in radians.
func look_towards(forward: Vector3, wanted: Vector3) -> float:
	var flat_forward := Vector3(forward.x, 0.0, forward.z)
	var flat_wanted := Vector3(wanted.x, 0.0, wanted.z)
	var yaw_error: float = 0.0
	if flat_forward.length_squared() > 0.0001 and flat_wanted.length_squared() > 0.0001:
		yaw_error = flat_forward.signed_angle_to(flat_wanted, Vector3.UP)
	var pitch_error: float = (
		asin(clampf(wanted.normalized().y, -1.0, 1.0))
		- asin(clampf(forward.normalized().y, -1.0, 1.0))
	)
	# Positive yaw error is counter-clockwise from above (turn left); positive pitch looks up.
	_look_axis(&"look_right", &"look_left", yaw_error)
	_look_axis(&"look_down", &"look_up", pitch_error)
	return Vector2(yaw_error, pitch_error).length()


func centre_look() -> void:
	for action: StringName in LOOK_ACTIONS:
		Input.action_release(action)


## Releases every action the bot can touch. Call from test teardown.
static func release_all() -> void:
	for group: Array[StringName] in [MOVE_ACTIONS, LOOK_ACTIONS, BUTTON_ACTIONS]:
		for action: StringName in group:
			Input.action_release(action)


func _axis(negative: StringName, positive: StringName, value: float) -> void:
	if absf(value) < 0.05:
		Input.action_release(negative)
		Input.action_release(positive)
		return
	var press: StringName = positive if value > 0.0 else negative
	var other: StringName = negative if value > 0.0 else positive
	Input.action_release(other)
	Input.action_press(press, absf(value))


func _look_axis(negative: StringName, positive: StringName, error: float) -> void:
	var output: float = clampf(absf(error) * LOOK_GAIN, 0.0, 1.0)
	if output < 0.02:
		Input.action_release(negative)
		Input.action_release(positive)
		return
	var press: StringName = positive if error > 0.0 else negative
	var other: StringName = negative if error > 0.0 else positive
	Input.action_release(other)
	# Map past the action deadzone so small corrections still move the stick.
	var deadzone: float = InputMap.action_get_deadzone(press)
	Input.action_press(press, lerpf(deadzone + 0.01, 1.0, output))
