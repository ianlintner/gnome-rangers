extends GutTest
## A pooled projectile's hitbox must forget earlier targets when it is reused.

const ARROW_ATTACK: AttackData = preload("res://actors/player/attacks/arrow.tres")

var _hitbox: HitboxComponent = null
var _hurtbox: HurtboxComponent = null
var _health: HealthComponent = null


func before_each() -> void:
	var target := Node3D.new()
	add_child_autofree(target)
	_health = HealthComponent.new()
	_health.name = "Health"
	target.add_child(_health)
	_hurtbox = HurtboxComponent.new()
	_hurtbox.faction = &"enemy"
	_hurtbox.health_path = ^"../Health"
	target.add_child(_hurtbox)
	_hitbox = HitboxComponent.new()
	_hitbox.faction = &"player"
	add_child_autofree(_hitbox)
	_hitbox.configure(ARROW_ATTACK, self, 0.0, false)


func test_the_same_target_is_hit_once_per_launch() -> void:
	assert_true(_hitbox.apply_to(_hurtbox, Vector3.ZERO))
	assert_false(_hitbox.apply_to(_hurtbox, Vector3.ZERO), "one hit per launch")


func test_clear_hits_lets_a_recycled_projectile_hit_again() -> void:
	assert_true(_hitbox.apply_to(_hurtbox, Vector3.ZERO))
	_hitbox.clear_hits()
	assert_true(_hitbox.apply_to(_hurtbox, Vector3.ZERO), "a relaunched arrow hits again")
	assert_lt(_health.current, _health.max_health - ARROW_ATTACK.damage, "both hits dealt damage")
