extends GutTest
## Health, poise, hurtbox routing, i-frames, weak points and AttackData-driven damage.

var _actor: Node3D
var _health: HealthComponent
var _poise: PoiseComponent
var _hurtbox: HurtboxComponent
var _head: HurtboxComponent
var _stats: CombatStats


func before_each() -> void:
	_stats = CombatStats.new()
	_stats.max_health = 100.0
	_stats.poise_max = 50.0
	_stats.poise_regen_delay = 1.0
	_stats.poise_regen_rate = 10.0
	_stats.stagger_duration = 1.0
	_stats.riposte_duration = 1.5
	_stats.riposte_damage_multiplier = 2.0
	_actor = Node3D.new()
	_health = HealthComponent.new()
	_health.name = &"Health"
	_poise = PoiseComponent.new()
	_poise.name = &"Poise"
	_hurtbox = HurtboxComponent.new()
	_hurtbox.name = &"Hurtbox"
	_head = HurtboxComponent.new()
	_head.name = &"Head"
	_head.damage_multiplier = 2.0
	for child: Node in [_health, _poise, _hurtbox, _head]:
		_actor.add_child(child)
	add_child_autofree(_actor)
	_health.apply_stats(_stats)
	_poise.apply_stats(_stats)
	# Hurtboxes are children of the actor, so `../Health` resolves; actor is the parent.
	_hurtbox.actor = _actor
	_head.actor = _actor
	_head.health_path = ^"../Health"


func _info(damage: float, poise_damage: float = 0.0) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = damage
	info.poise_damage = poise_damage
	info.faction = &"player"
	return info


func test_damage_reduces_health_and_reports_removed_amount() -> void:
	assert_eq(_health.take_damage(30.0), 30.0)
	assert_eq(_health.current, 70.0)


func test_damage_cannot_overkill_and_died_fires_once() -> void:
	watch_signals(_health)
	_health.take_damage(250.0)
	_health.take_damage(10.0)
	assert_eq(_health.current, 0.0)
	assert_true(_health.is_dead())
	assert_signal_emit_count(_health, "died", 1)


func test_died_is_published_on_the_event_bus() -> void:
	watch_signals(EventBus)
	_health.take_damage(100.0)
	assert_signal_emitted_with_parameters(EventBus, "actor_died", [_actor])


func test_invulnerable_health_ignores_damage() -> void:
	_health.invulnerable = true
	assert_eq(_health.take_damage(50.0), 0.0)
	assert_eq(_health.current, 100.0)


func test_heal_is_capped_and_dead_actors_stay_dead() -> void:
	_health.take_damage(40.0)
	assert_eq(_health.heal(100.0), 40.0)
	_health.take_damage(500.0)
	assert_eq(_health.heal(10.0), 0.0)


func test_hurtbox_routes_damage_to_health() -> void:
	assert_true(_hurtbox.receive_damage(_info(25.0)))
	assert_eq(_health.current, 75.0)


func test_weak_point_multiplies_damage_and_flags_the_hit() -> void:
	var info: DamageInfo = _info(10.0)
	assert_true(_head.receive_damage(info))
	assert_eq(_health.current, 80.0)
	assert_true(info.is_weak_point)
	assert_eq(info.final_amount, 20.0)


func test_iframes_make_the_hurtbox_immune() -> void:
	_hurtbox.invulnerable = true
	watch_signals(_hurtbox)
	assert_false(_hurtbox.receive_damage(_info(40.0, 40.0)))
	assert_eq(_health.current, 100.0)
	assert_eq(_poise.current, 0.0)
	assert_signal_emitted(_hurtbox, "hit_ignored")


func test_same_faction_hits_are_ignored() -> void:
	_hurtbox.faction = &"player"
	assert_false(_hurtbox.receive_damage(_info(40.0)))
	assert_eq(_health.current, 100.0)


func test_poise_damage_accumulates_without_breaking() -> void:
	assert_false(_poise.take_poise_damage(20.0))
	assert_eq(_poise.current, 20.0)
	assert_false(_poise.staggered)


func test_poise_break_staggers_opens_riposte_and_recovers() -> void:
	watch_signals(_poise)
	watch_signals(EventBus)
	assert_true(_poise.take_poise_damage(50.0))
	assert_true(_poise.staggered)
	assert_true(_poise.riposte_open)
	assert_signal_emitted(_poise, "poise_broken")
	assert_signal_emitted_with_parameters(EventBus, "actor_staggered", [_actor])
	_poise.tick(1.0)
	assert_false(_poise.staggered, "stagger ends after its duration")
	assert_signal_emitted(_poise, "stagger_ended")
	assert_true(_poise.riposte_open, "riposte outlasts the stagger")
	_poise.tick(0.6)
	assert_false(_poise.riposte_open)


func test_poise_regenerates_after_its_delay() -> void:
	_poise.take_poise_damage(30.0)
	_poise.tick(0.9)
	assert_eq(_poise.current, 30.0, "no regen inside the delay")
	_poise.tick(0.2)
	_poise.tick(1.0)
	assert_lt(_poise.current, 30.0)


func test_hits_during_stagger_do_not_break_again() -> void:
	_poise.take_poise_damage(50.0)
	assert_false(_poise.take_poise_damage(50.0))


func test_riposte_window_boosts_damage() -> void:
	_poise.take_poise_damage(50.0)
	_hurtbox.receive_damage(_info(10.0))
	assert_eq(_health.current, 80.0, "riposte multiplier 2.0 applied")


func test_hurtbox_poise_break_flows_through_the_hit() -> void:
	_hurtbox.receive_damage(_info(1.0, 60.0))
	assert_true(_poise.staggered)


func test_damage_info_scales_with_charge() -> void:
	var data := AttackData.new()
	data.damage = 10.0
	data.poise_damage = 20.0
	data.charge_damage_multiplier = 2.0
	data.charge_poise_multiplier = 3.0
	var full: DamageInfo = DamageInfo.from_attack(data, null, &"player", 1.0)
	assert_eq(full.amount, 20.0)
	assert_eq(full.poise_damage, 60.0)
	var none: DamageInfo = DamageInfo.from_attack(data, null, &"player", 0.0)
	assert_eq(none.amount, 10.0)
