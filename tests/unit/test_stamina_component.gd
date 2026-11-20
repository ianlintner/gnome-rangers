extends GutTest
## StaminaComponent: spend, regen delay, regen, depletion and the winded state.

var _stamina: StaminaComponent
var _stats: CharacterStats


func before_each() -> void:
	_stats = CharacterStats.new()
	_stats.stamina_max = 100.0
	_stats.stamina_regen_rate = 20.0
	_stats.stamina_regen_delay = 1.0
	_stats.winded_duration = 2.0
	_stamina = StaminaComponent.new()
	add_child_autofree(_stamina)
	_stamina.apply_stats(_stats)


func test_starts_full_from_stats() -> void:
	assert_eq(_stamina.current, 100.0)
	assert_eq(_stamina.max_stamina, 100.0)
	assert_false(_stamina.is_winded())


func test_try_spend_deducts_and_reports_success() -> void:
	assert_true(_stamina.try_spend(30.0))
	assert_eq(_stamina.current, 70.0)


func test_try_spend_refused_when_insufficient() -> void:
	_stamina.current = 10.0
	assert_false(_stamina.try_spend(20.0))
	assert_eq(_stamina.current, 10.0)


func test_changed_signal_carries_current_and_max() -> void:
	watch_signals(_stamina)
	_stamina.try_spend(25.0)
	assert_signal_emitted_with_parameters(_stamina, "changed", [75.0, 100.0])


func test_regen_waits_for_delay_then_runs() -> void:
	_stamina.try_spend(50.0)
	_stamina.tick(0.9)
	assert_eq(_stamina.current, 50.0, "still inside the regen delay")
	_stamina.tick(0.2)  # delay ends 0.1 s into this tick; regen applies on later ticks
	_stamina.tick(1.0)
	assert_almost_eq(_stamina.current, 70.0, 0.001)


func test_spend_restarts_the_delay() -> void:
	_stamina.try_spend(10.0)
	_stamina.tick(0.8)
	_stamina.try_spend(10.0)
	_stamina.tick(0.8)
	assert_eq(_stamina.current, 80.0)


func test_regen_caps_at_max() -> void:
	_stamina.try_spend(10.0)
	_stamina.tick(1.0)
	_stamina.tick(10.0)
	assert_eq(_stamina.current, 100.0)


func test_reaching_zero_emits_depleted_and_winds() -> void:
	watch_signals(_stamina)
	assert_true(_stamina.try_spend(100.0))
	assert_signal_emitted(_stamina, "depleted")
	assert_true(_stamina.is_winded())


func test_winded_refuses_spend_and_blocks_regen_until_it_ends() -> void:
	_stamina.try_spend(100.0)
	_stamina.tick(1.5)
	assert_eq(_stamina.current, 0.0, "no regen while winded")
	assert_false(_stamina.try_spend(1.0))
	watch_signals(_stamina)
	_stamina.tick(0.6)
	assert_signal_emitted(_stamina, "recovered")
	assert_false(_stamina.is_winded())
	_stamina.tick(1.0)
	assert_almost_eq(_stamina.current, 20.0, 0.001)


func test_drain_stops_at_zero_and_reports_empty() -> void:
	assert_true(_stamina.drain(60.0))
	assert_false(_stamina.drain(60.0))
	assert_eq(_stamina.current, 0.0)
	assert_true(_stamina.is_winded())
