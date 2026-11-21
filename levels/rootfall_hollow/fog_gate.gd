class_name FogGate
extends Area3D
## Boss arena entry kit: on player entry it spawns/finds the boss, announces
## `EventBus.boss_engaged`, seals the arena, and restores everything after a defeat
## or a player death. Keeps the old FogGateTrigger API (`entered`, `_on_body_entered`)
## so existing level subscribers and tests keep working.

signal sealed_changed(is_sealed: bool)
signal entered(body: Node3D)

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
	GameState.run_reset.connect(reset_arena)
	if boss_path != NodePath("") and has_node(boss_path):
		boss = get_node(boss_path) as BossBase
	if boss != null:
		_boss_spawn_transform = boss.global_transform
	_front = get_node_or_null(seal_front_path) as Node3D
	_back = get_node_or_null(seal_back_path) as Node3D
	_set_sealed(false)


func _on_body_entered(body: Node3D) -> void:
	if _engaged:
		return
	_engaged = true
	entered.emit(body)
	EventBus.boss_engaged.emit(boss)
	# Only a player-like body seals the arena and spawns the boss.
	if body.get_node_or_null("Health") == null or body.get_node_or_null("Poise") == null:
		return
	if boss == null and boss_scene != null:
		boss = boss_scene.instantiate() as BossBase
		get_tree().current_scene.add_child(boss)
		_boss_spawn_transform = boss.global_transform
	if boss == null:
		return
	var spawn: Node3D = get_node_or_null(^"BossSpawn")
	if spawn != null:
		boss.global_transform = spawn.global_transform
		_boss_spawn_transform = spawn.global_transform
	boss.engage(body)
	_set_sealed(true)
	EventBus.boss_defeated.connect(_on_boss_defeated, CONNECT_ONE_SHOT)


func _on_boss_defeated(_defeated: BossBase) -> void:
	_set_sealed(false)


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


func reset_arena() -> void:
	if EventBus.boss_defeated.is_connected(_on_boss_defeated):
		EventBus.boss_defeated.disconnect(_on_boss_defeated)
	_engaged = false
	if boss != null and is_instance_valid(boss):
		boss.global_transform = _boss_spawn_transform
		boss.reset_boss()
	_set_sealed(false)
