extends Node3D
## Deterministic capture dressing for the boss card. Two modes selected by the
## child name: `Slam` starts the overhead slam windup, `Roar` forces phase 2.

const GRUKK_SCENE: PackedScene = preload("res://actors/bosses/orc_brute/grukk.tscn")

@export var mode: StringName = &"slam"


func _ready() -> void:
	var boss: BossBase = GRUKK_SCENE.instantiate() as BossBase
	add_child(boss)
	boss.position = Vector3.ZERO
	boss.rotation.y = 0.45
	var dummy := Node3D.new()
	dummy.name = "Dummy"
	dummy.position = Vector3(0, 0, -3)
	add_child(dummy)
	var health := HealthComponent.new()
	health.name = "Health"
	health.max_health = 100.0
	dummy.add_child(health)
	health.reset()
	var poise := PoiseComponent.new()
	poise.name = "Poise"
	poise.max_poise = 100.0
	dummy.add_child(poise)
	poise.reset()
	boss.engage(dummy)
	if mode == &"slam":
		var move: BossMoveData = boss.base_moves[0]
		boss.start_move(move)
	elif mode == &"roar":
		var info := DamageInfo.new()
		info.amount = boss.health.max_health * 0.51
		info.poise_damage = 0.0
		var body: BossHurtbox = boss.get_node("HurtboxBody") as BossHurtbox
		body.receive_damage(info)
	var camera := get_node_or_null("Cam") as Camera3D
	if camera != null:
		camera.make_current()
