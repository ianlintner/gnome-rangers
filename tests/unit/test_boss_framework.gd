extends GutTest
## Boss framework unit tests: deterministic move selection, distance bands,
## cooldowns, limited turning and context-sensitive weak points.

const BRAIN_SCRIPT: Script = preload("res://actors/bosses/boss_base/boss_brain.gd")
const MOVE_SCRIPT: Script = preload("res://actors/bosses/boss_base/boss_move_data.gd")
const PHASE_SCRIPT: Script = preload("res://actors/bosses/boss_base/boss_phase_data.gd")
const HURTBOX_SCRIPT: Script = preload("res://actors/bosses/boss_base/boss_hurtbox.gd")
const DAMAGE_SCRIPT: Script = preload("res://core/data/damage_info.gd")
const POISE_SCRIPT: Script = preload("res://core/components/poise_component.gd")


func _move(
	id: String, lo: float, hi: float, weight: float, cooldown: float, phase: int = 0
) -> BossMoveData:
	var move: BossMoveData = MOVE_SCRIPT.new()
	move.id = StringName(id)
	move.min_range = lo
	move.max_range = hi
	move.weight = weight
	move.cooldown = cooldown
	move.min_phase = phase
	return move


func _brain(moves: Array[BossMoveData]) -> BossBrain:
	var brain: BossBrain = BRAIN_SCRIPT.new()
	add_child_autofree(brain)
	brain.moves = moves
	brain.reset()
	brain.set_seed(1234)
	return brain


func test_move_selection_never_picks_out_of_band_moves() -> void:
	var close_move := _move("close", 0.0, 3.0, 1.0, 0.0)
	var far_move := _move("far", 7.0, 20.0, 1.0, 0.0)
	var brain := _brain([close_move, far_move])
	for _i: int in range(30):
		assert_eq(brain.pick_move(1.0).id, &"close")
		assert_eq(brain.pick_move(12.0).id, &"far")


func test_move_selection_is_deterministic_for_a_seed() -> void:
	var moves: Array[BossMoveData] = [
		_move("a", 0.0, 10.0, 2.0, 0.0),
		_move("b", 0.0, 10.0, 3.0, 0.0),
		_move("c", 0.0, 10.0, 5.0, 0.0),
	]
	var first := _brain(moves)
	var second := _brain(moves)
	var a: Array[String] = []
	var b: Array[String] = []
	for _i: int in range(25):
		a.append(String(first.pick_move(1.0).id))
		b.append(String(second.pick_move(1.0).id))
	assert_eq(a, b, "same seed produces the same move sequence")


func test_picked_move_starts_its_cooldown_and_is_skipped_until_it_expires() -> void:
	var a := _move("a", 0.0, 10.0, 1.0, 1.5)
	var b := _move("b", 0.0, 10.0, 1.0, 0.0)
	var brain := _brain([a, b])
	brain.set_seed(7)
	var picked: BossMoveData = brain.pick_move(1.0)
	assert_gt(brain.cooldown_left(picked.id), 0.0, "cooldown started on pick")
	for _i: int in range(10):
		assert_ne(brain.pick_move(1.0).id, picked.id, "cooling move is skipped")
	brain.tick(2.0)
	assert_eq(brain.cooldown_left(picked.id), 0.0, "cooldown expired")


func test_phase_two_unlocks_phase_two_moves_only() -> void:
	var base_move := _move("base", 0.0, 10.0, 1.0, 0.0)
	var combo := _move("combo", 0.0, 10.0, 1.0, 0.0, 2)
	var brain := _brain([base_move, combo])
	assert_eq(brain.pick_move(1.0).id, &"base")
	var phase: BossPhaseData = PHASE_SCRIPT.new()
	phase.moveset_override = [combo]
	brain.configure_phase(phase, 2)
	assert_eq(brain.pick_move(1.0).id, &"combo")


func test_turn_rate_limits_rotation_per_frame() -> void:
	var brain := _brain([])
	brain.turn_rate_degrees = 90.0
	var body := Node3D.new()
	add_child_autofree(body)
	var target := Node3D.new()
	add_child_autofree(target)
	target.global_position = Vector3(0, 0, -10)
	var before: float = body.rotation.y
	brain.turn_toward(body, target, 0.1)
	assert_lt(absf(body.rotation.y - before), deg_to_rad(90.0) + 0.001)


func _hurtbox(zone: StringName) -> BossHurtbox:
	var node := Node3D.new()
	add_child_autofree(node)
	var poise: PoiseComponent = POISE_SCRIPT.new()
	poise.name = "Poise"
	poise.max_poise = 50.0
	node.add_child(poise)
	var hurtbox: BossHurtbox = HURTBOX_SCRIPT.new()
	node.add_child(hurtbox)
	hurtbox.zone = zone
	return hurtbox


func test_head_takes_double_arrow_damage_but_less_melee() -> void:
	var head := _hurtbox(&"head")
	var arrow: DamageInfo = DAMAGE_SCRIPT.new()
	arrow.damage_type = &"arrow"
	arrow.amount = 10.0
	var melee: DamageInfo = DAMAGE_SCRIPT.new()
	melee.damage_type = &"melee"
	melee.amount = 10.0
	assert_almost_eq(head.get_damage_multiplier(arrow), 2.0, 0.001)
	assert_almost_eq(head.get_damage_multiplier(melee), 1.25, 0.001)


func test_back_bonus_applies_only_while_staggered() -> void:
	var back := _hurtbox(&"back")
	var hit: DamageInfo = DAMAGE_SCRIPT.new()
	hit.amount = 10.0
	assert_almost_eq(back.get_damage_multiplier(hit), 1.0, 0.001)
	(back.get_parent().get_node("Poise") as PoiseComponent).staggered = true
	assert_almost_eq(back.get_damage_multiplier(hit), 1.5, 0.001)


func _phase_controller() -> BossPhaseController:
	var actor := Node3D.new()
	add_child_autofree(actor)
	var health: HealthComponent = HealthComponent.new()
	health.name = "Health"
	actor.add_child(health)
	health.max_health = 100.0
	health.reset()
	var controller: BossPhaseController = BossPhaseController.new()
	actor.add_child(controller)
	var data: BossPhaseData = PHASE_SCRIPT.new()
	data.hp_threshold = 0.5
	controller.phases = [data]
	return controller


func test_phase_two_triggers_exactly_once_at_the_threshold() -> void:
	var controller := _phase_controller()
	watch_signals(controller)
	var health: HealthComponent = controller.health
	health.take_damage(49.0)
	assert_signal_not_emitted(controller, "phase_entered")
	health.take_damage(1.0)
	assert_signal_emit_count(controller, "phase_entered", 1)
	assert_eq(controller.phase, 2)
	health.take_damage(10.0)
	assert_signal_emit_count(controller, "phase_entered", 1, "no repeat on further damage")


func test_phase_controller_reset_restores_phase_one_and_allows_retrigger() -> void:
	var controller := _phase_controller()
	watch_signals(controller)
	controller.health.take_damage(50.0)
	assert_signal_emit_count(controller, "phase_entered", 1)
	controller.reset()
	assert_eq(controller.phase, 1)
	controller.health.reset()
	controller.health.take_damage(50.0)
	assert_signal_emit_count(controller, "phase_entered", 2)
