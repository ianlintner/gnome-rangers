class_name FogGate
extends Area3D
## Boss arena entry kit. The level calls [method spawn_boss] to place an idle instance of
## `boss_scene` at `BossSpawn` (or the gate adopts the node at `boss_path`). When the player
## walks or rides through, it announces `EventBus.boss_engaged`, engages the boss
## and seals the arena. A player death or a new run puts the boss back at its spawn, fully
## reset; a defeat reopens the arena for good.
##
## The trigger box sits on the arena side of the seal line, so the seals always close behind
## the player, never in front of them.

signal sealed_changed(is_sealed: bool)
## Emitted once per engagement with the player that crossed the gate.
signal entered(body: Node3D)

## Scene-tree group the player joins (see [constant Player.GROUP]).
const PLAYER_GROUP: StringName = &"player"

@export var boss_scene: PackedScene = null
@export var boss_path: NodePath = ^""
@export var seal_front_path: NodePath = ^"SealFront"
@export var seal_back_path: NodePath = ^"SealBack"
@export var gate_open_y: float = -4.0
@export var gate_closed_y: float = 0.0

var boss: BossBase = null
var _engaged: bool = false
var _sealed: bool = false

var _boss_spawn_transform: Transform3D = Transform3D.IDENTITY
var _front: Node3D = null
var _back: Node3D = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	EventBus.player_died.connect(reset_arena)
	GameState.run_reset.connect(reset_for_new_run)
	_front = get_node_or_null(seal_front_path) as Node3D
	_back = get_node_or_null(seal_back_path) as Node3D
	_set_sealed(false)
	var spawn: Node3D = get_node_or_null(^"BossSpawn") as Node3D
	_boss_spawn_transform = spawn.global_transform if spawn != null else global_transform
	if boss_path != NodePath("") and has_node(boss_path):
		boss = get_node(boss_path) as BossBase
		_boss_spawn_transform = boss.global_transform


func _exit_tree() -> void:
	if EventBus.player_died.is_connected(reset_arena):
		EventBus.player_died.disconnect(reset_arena)
	if GameState.run_reset.is_connected(reset_for_new_run):
		GameState.run_reset.disconnect(reset_for_new_run)


## Instantiates `boss_scene` beside the gate (a sibling, so it belongs to the level) and
## places it idle at `BossSpawn`. Called by the level once its tree is ready.
func spawn_boss() -> BossBase:
	if boss != null and is_instance_valid(boss):
		return boss
	if boss_scene == null:
		return null
	boss = boss_scene.instantiate() as BossBase
	get_parent().add_child(boss)
	boss.global_transform = _boss_spawn_transform
	return boss


## The player that `body` stands for: the player itself, or the rider of a cat.
func _player_for(body: Node3D) -> Node3D:
	if body == null:
		return null
	if body.is_in_group(PLAYER_GROUP):
		return body
	var cat := body as CatMount
	if cat != null and cat.rider != null:
		return cat.rider
	return null


func _on_body_entered(body: Node3D) -> void:
	var player: Node3D = _player_for(body)
	if _engaged or player == null or boss == null or not is_instance_valid(boss):
		return
	if boss.defeated:
		return
	_engaged = true
	entered.emit(player)
	EventBus.boss_engaged.emit(boss)
	boss.engage(player)
	_set_sealed(true)
	if not EventBus.boss_defeated.is_connected(_on_boss_defeated):
		EventBus.boss_defeated.connect(_on_boss_defeated, CONNECT_ONE_SHOT)


func _on_boss_defeated(_defeated: BossBase) -> void:
	_set_sealed(false)


## True once the player has crossed the gate and the fight is on.
func is_engaged() -> bool:
	return _engaged


## True while the arena doors are closed (read-only for tests and HUD hooks).
func is_sealed() -> bool:
	return _sealed


func _set_sealed(value: bool) -> void:
	_sealed = value
	for wall: Node3D in [_front, _back]:
		if wall == null:
			continue
		var position: Vector3 = wall.position
		position.y = gate_closed_y if value else gate_open_y
		wall.position = position
		if wall is CollisionObject3D:
			(wall as CollisionObject3D).collision_layer = 1 if value else 0
	sealed_changed.emit(value)


func reset_for_new_run() -> void:
	if boss != null and is_instance_valid(boss):
		boss.defeated = false
	reset_arena()


func reset_arena() -> void:
	if EventBus.boss_defeated.is_connected(_on_boss_defeated):
		EventBus.boss_defeated.disconnect(_on_boss_defeated)
	var already_defeated: bool = boss != null and is_instance_valid(boss) and boss.defeated
	if already_defeated:
		# The fight is over; death must not respawn the boss or reopen the gate latch.
		_set_sealed(false)
		return
	_engaged = false
	if boss != null and is_instance_valid(boss) and boss.is_inside_tree():
		boss.global_transform = _boss_spawn_transform
		boss.velocity = Vector3.ZERO
		boss.reset_boss()
	_set_sealed(false)
