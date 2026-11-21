extends GutTest
## Grukk fights a real (idle) player body headlessly: kills it, throws it on a grab,
## and rings the floor with a shockwave after the overhead slam.

const GRUKK: PackedScene = preload("res://actors/bosses/orc_brute/grukk.tscn")
const GRAB: BossMoveData = preload("res://actors/bosses/orc_brute/moves/grab.tres")
const SLAM: BossMoveData = preload("res://actors/bosses/orc_brute/moves/slam.tres")

var _boss: Grukk = null
var _player: CharacterBody3D = null
var _floor: StaticBody3D = null


func before_each() -> void:
	GameState.clear()
	_floor = StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	floor_shape.shape = box
	_floor.add_child(floor_shape)
	_floor.position = Vector3(0, -0.5, 0)
	add_child_autofree(_floor)
	_boss = GRUKK.instantiate() as Grukk
	add_child_autofree(_boss)
	_boss.position = Vector3(0, 0, 0)
	_player = _make_player()
	add_child_autofree(_player)
	_player.position = Vector3(0, 0, -2.0)


func after_each() -> void:
	GameState.clear()


func _make_player() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = "Player"
	body.collision_layer = 2
	var health := HealthComponent.new()
	health.name = "Health"
	health.max_health = 40.0
	body.add_child(health)
	health.reset()
	var poise := PoiseComponent.new()
	poise.name = "Poise"
	poise.max_poise = 1000.0
	body.add_child(poise)
	poise.reset()
	var hurtbox := HurtboxComponent.new()
	hurtbox.name = "Hurtbox"
	hurtbox.faction = &"player"
	body.add_child(hurtbox)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.0
	shape.shape = capsule
	shape.position = Vector3(0, 0.5, 0)
	hurtbox.add_child(shape)
	return body


func _health_of(body: Node) -> HealthComponent:
	return body.get_node("Health") as HealthComponent


func test_grukk_kills_an_idle_player() -> void:
	_boss.engage(_player)
	for _i: int in range(60 * 30):
		await get_tree().physics_frame
		if _health_of(_player).is_dead():
			break
	assert_true(_health_of(_player).is_dead(), "idle player did not survive Grukk")


func test_grab_deals_damage_and_throws_the_player() -> void:
	_boss.target = _player
	_boss.start_move(GRAB)
	var before: float = _health_of(_player).current
	for _i: int in range(90):
		await get_tree().physics_frame
	assert_lt(_health_of(_player).current, before, "grab damaged the player")
	assert_gt(_player.velocity.length(), 0.0, "player was launched")


func test_slam_move_carries_a_shockwave_followup_hitbox() -> void:
	assert_not_null(SLAM.followup_attack)
	assert_not_null(_boss.shockwave)
	_boss.target = _player
	_boss.start_move(SLAM)
	var saw_ring: bool = false
	for _i: int in range(60):
		await get_tree().physics_frame
		if _boss.shockwave.active:
			saw_ring = true
	assert_true(saw_ring, "shockwave ring opened after the slam window")
