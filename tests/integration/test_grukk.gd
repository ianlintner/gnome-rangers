extends GutTest
## Headless Grukk integration: scene composition, engagement, phase transition,
## poise break/back bonus, defeat and full reset after player death.

const GRUKK: PackedScene = preload("res://actors/bosses/orc_brute/grukk.tscn")
const PLAYER: PackedScene = preload("res://actors/player/player.tscn")

var _boss: Grukk = null
var _player: Node3D = null


func before_each() -> void:
	GameState.clear()
	_boss = GRUKK.instantiate() as Grukk
	add_child_autofree(_boss)
	_player = Node3D.new()
	_player.name = "Player"
	add_child_autofree(_player)
	var health := HealthComponent.new()
	health.name = "Health"
	health.max_health = 30.0
	_player.add_child(health)
	health.reset()
	var poise := PoiseComponent.new()
	poise.name = "Poise"
	poise.max_poise = 30.0
	_player.add_child(poise)
	poise.reset()


func after_each() -> void:
	GameState.clear()


func _hit(zone: String, amount: float, damage_type: StringName = &"melee") -> void:
	var info := DamageInfo.new()
	info.amount = amount
	info.poise_damage = 0.0
	info.damage_type = damage_type
	var box: BossHurtbox = _boss.get_node("Hurtbox" + zone) as BossHurtbox
	assert_true(box.receive_damage(info), "hit landed on %s" % zone)


func test_grukk_scene_loads_all_components_and_states() -> void:
	assert_not_null(_boss)
	assert_not_null(_boss.health)
	assert_not_null(_boss.poise)
	assert_not_null(_boss.runner)
	assert_not_null(_boss.brain)
	assert_eq(_boss.state_machine.get_child_count(), 7)
	assert_eq(_boss.base_moves.size(), 5)
	assert_eq(_boss.phases.size(), 1)


func test_engage_sets_target_and_announces_through_the_gate() -> void:
	watch_signals(EventBus)
	_boss.engage(_player)
	assert_true(_boss.engaged)
	assert_eq(_boss.target, _player)


func test_phase_two_roar_fires_once_at_half_health() -> void:
	watch_signals(EventBus)
	watch_signals(_boss)
	_boss.engage(_player)
	_hit("Body", 310.0)
	assert_eq(_boss.phase_controller.phase, 2)
	assert_signal_emit_count(EventBus, "boss_phase_changed", 1)
	assert_signal_emit_count(_boss, "roar_started", 1)
	assert_eq(_boss.state_machine.current_state_name, &"PhaseTransition")


func test_poise_break_staggers_grukk_and_back_hit_gets_bonus() -> void:
	var info := DamageInfo.new()
	info.amount = 5.0
	info.poise_damage = 100.0
	(_boss.get_node("HurtboxBody") as BossHurtbox).receive_damage(info)
	assert_true(_boss.poise.staggered)
	assert_eq(_boss.state_machine.current_state_name, &"Staggered")
	var before: float = _boss.health.current
	_hit("Back", 10.0)
	var expected: float = 15.0 * _boss.poise.riposte_multiplier
	assert_almost_eq(
		before - _boss.health.current,
		expected,
		0.01,
		"back bonus x1.5 with riposte bonus from the poise break"
	)


func test_head_hurtbox_takes_double_arrow_damage() -> void:
	var before: float = _boss.health.current
	_hit("Head", 10.0, &"arrow")
	assert_almost_eq(before - _boss.health.current, 20.0, 0.01)


func test_player_death_resets_health_phase_and_arena() -> void:
	_boss.engage(_player)
	_hit("Body", 320.0)
	assert_eq(_boss.phase_controller.phase, 2)
	EventBus.player_died.emit()
	assert_almost_eq(_boss.health.current, _boss.health.max_health, 0.01)
	assert_eq(_boss.phase_controller.phase, 1)
	assert_false(_boss.engaged)
	assert_eq(_boss.state_machine.current_state_name, &"Idle")


func test_lethal_damage_defeats_boss_and_emits_once() -> void:
	watch_signals(EventBus)
	_boss.engage(_player)
	_hit("Body", 1000.0)
	assert_true(_boss.health.is_dead())
	assert_signal_emit_count(EventBus, "boss_defeated", 1)
	assert_eq(_boss.state_machine.current_state_name, &"Dead")


func test_phase_two_moveset_adds_combo_and_leaping_slam() -> void:
	_boss.engage(_player)
	_hit("Body", 310.0)
	var ids: Array[StringName] = []
	for move: BossMoveData in _boss.brain.active_moves:
		ids.append(move.id)
	assert_has(ids, &"combo")
	assert_has(ids, &"leaping_slam")
	assert_lt(_boss.brain.recovery_multiplier, 1.0, "faster recoveries in phase 2")


func test_defeated_boss_stays_dead_after_player_death() -> void:
	_boss.engage(_player)
	_hit("Body", 1000.0)
	assert_true(_boss.defeated)
	assert_true(GameState.is_won())
	EventBus.player_died.emit()
	assert_true(_boss.health.is_dead(), "death is not undone by a later player death")
	assert_true(_boss.defeated)
	assert_eq(_boss.state_machine.current_state_name, &"Dead")


func test_new_run_revives_a_defeated_boss() -> void:
	_boss.engage(_player)
	_hit("Body", 1000.0)
	GameState.reset_run()
	assert_false(_boss.defeated)
	assert_almost_eq(_boss.health.current, _boss.health.max_health, 0.01)
	assert_eq(_boss.state_machine.current_state_name, &"Idle")


func test_phase_transition_cancels_an_in_flight_attack() -> void:
	var move: BossMoveData = load("res://actors/bosses/orc_brute/moves/slam.tres")
	_boss.engage(_player)
	assert_true(_boss.start_move(move))
	assert_true(_boss.runner.is_busy())
	_hit("Body", 310.0)
	assert_false(_boss.runner.is_busy(), "the roar never leaves a live attack")
	assert_false((_boss.get_node("Hitbox") as HitboxComponent).active)
	assert_false((_boss.get_node("ShockwaveHitbox") as HitboxComponent).active)


func test_roar_ignores_health_and_poise_damage() -> void:
	_boss.engage(_player)
	_hit("Body", 310.0)
	var before: float = _boss.health.current
	var info := DamageInfo.new()
	info.amount = 10.0
	info.poise_damage = 100.0
	assert_false((_boss.get_node("HurtboxBody") as BossHurtbox).receive_damage(info))
	assert_almost_eq(_boss.health.current, before, 0.01)
	assert_false(_boss.poise.staggered, "the roar cannot be interrupted by poise damage")
	assert_eq(_boss.state_machine.current_state_name, &"PhaseTransition")
