class_name PlayerWorld
extends RefCounted
## Builders for controller tests: a floor, a player on it, lockable dummies and walls.

const PLAYER_SCENE: PackedScene = preload("res://actors/player/player.tscn")
const CAMERA_SCENE: PackedScene = preload("res://camera/third_person_camera.tscn")

const ACTIONS: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
	&"sprint",
	&"dodge",
	&"lock_on",
	&"lock_switch_left",
	&"lock_switch_right",
]


static func make_floor() -> StaticBody3D:
	return make_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0))


static func make_box(size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = position
	return body


## Instantiates the player (optionally with its own `stats`) at the origin.
static func make_player(stats: CharacterStats = null) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	if stats != null:
		player.stats = stats
	player.position = Vector3.ZERO
	return player


## A lockable dummy: a Node3D carrying a [LockOnTarget] at its origin.
static func make_dummy(position: Vector3) -> Node3D:
	var dummy := Node3D.new()
	dummy.add_child(LockOnTarget.new())
	dummy.position = position + Vector3.UP  # lock point at chest height, above the floor
	return dummy


static func release_all_actions() -> void:
	for action: StringName in ACTIONS:
		Input.action_release(action)
