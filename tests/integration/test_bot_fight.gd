extends GutTest
## MVP gate: headless bot fights through the real game. `main.tscn` starts a new game, which
## loads Rootfall Hollow with the real player, camera, cat and Grukk; a [FightBot] plays it
## through the named InputMap actions only.
##
## Determinism and speed: every RNG the fight uses (the global one and Grukk's brain) is
## seeded with [constant SEED], every gameplay timer runs in the physics tick, and the bot loop
## steps a fixed number of physics frames, so a run is a pure function of the seed. [BotClock]
## fast-forwards the engine 16x (time scale plus a 16x physics tick rate, so every step is still
## 1/60 s of game time). [constant GAME_FRAMES] is the normal terminator; the wall-clock budget
## is only a safety net and fails the test loudly when hit. The clock is restored in
## `after_each`.

const MAIN: PackedScene = preload("res://main.tscn")
const SEED: int = 20261126
## Physics frames (1/60 s of game time each) a whole run (rest, approach, fight) may take.
const GAME_FRAMES: int = 420 * 60
## Wall-clock milliseconds a single run may take before it is failed as too slow.
const WALL_BUDGET_MS: int = 60000

var _main: GameFlow = null
var _level: RootfallHollow = null
var _bot: FightBot = null


func before_each() -> void:
	GameState.clear()
	BotClock.fast_forward()
	_main = MAIN.instantiate() as GameFlow
	add_child(_main)
	_main.start_new_game()
	_level = _main.level() as RootfallHollow
	await _wait_for_navigation()


func after_each() -> void:
	BotInput.release_all()
	BotClock.restore()
	if is_instance_valid(_main):
		_main.free()
	_main = null
	_level = null
	_bot = null
	get_tree().paused = false
	GameState.clear()


## Waits until the baked navmesh is really in the map: a path from the player reaches Grukk.
## Map syncs are made synchronous first, so the bot's first path query never races a worker
## thread, and the game is paused meanwhile, so however many frames the sync takes, the fight
## starts from the same state (the cat's idle cycle, for one). Fails if the navmesh never
## arrives.
func _wait_for_navigation() -> void:
	var map: RID = _level.get_world_3d().navigation_map
	get_tree().paused = true
	NavigationServer3D.map_set_use_async_iterations(map, false)
	var goal: Vector3 = _level.boss.global_position
	for _frame: int in range(240):
		await get_tree().physics_frame
		var path: PackedVector3Array = NavigationServer3D.map_get_path(
			map, _level.player.global_position, goal, true
		)
		if not path.is_empty() and Vector2(path[-1].x - goal.x, path[-1].z - goal.z).length() < 2.0:
			get_tree().paused = false
			return
	get_tree().paused = false
	fail_test("the Rootfall Hollow navmesh never reached the map")


## Seeds every RNG the fight uses, then hands the controls to a [FightBot].
func _start_bot(plan: FightBot.Plan) -> void:
	seed(SEED)
	_level.boss.brain.set_seed(SEED)
	_bot = FightBot.new(_level, plan)
	_level.add_child(_bot)


## Steps physics until `done` returns true or [constant GAME_FRAMES] run out. Returns whether
## it finished. Exceeding the wall-clock budget is a test failure, never a silent stop.
func _run_until(done: Callable) -> bool:
	var started: int = Time.get_ticks_msec()
	for _frame: int in range(GAME_FRAMES):
		await get_tree().physics_frame
		if done.call():
			return true
		if Time.get_ticks_msec() - started > WALL_BUDGET_MS:
			fail_test("wall-clock safety budget of %d ms exceeded%s" % [WALL_BUDGET_MS, _story()])
			return false
	return false


func _story() -> String:
	var boss: BossBase = _level.boss
	return (
		(
			"\n%s\n%.0f game s: boss hp %.0f/%.0f phase %d, player hp %.0f, hits %s, dodges %d,"
			+ " arrows %d, pounces %d"
		)
		% [
			"\n".join(_bot.journal),
			_bot.game_time,
			boss.health.current,
			boss.health.max_health,
			boss.phase_controller.phase,
			_level.player.health.current,
			_bot.hits,
			_bot.dodges,
			_bot.arrows_fired,
			_bot.pounces,
		]
	)


func _assert_victory() -> void:
	var boss: BossBase = _level.boss
	assert_true(boss.health.is_dead(), "Grukk is defeated" + _story())
	assert_true(boss.defeated, "the real death path latched the defeat")
	assert_eq(boss.phase_controller.phase, 2, "the fight went through phase 2")
	assert_eq(_main.state_name(), &"victory", "the flow reached the victory screen")
	assert_true(GameState.is_won())
	assert_false(_level.player.health.is_dead(), "the bot survived")
	assert_false(_level.fog_gate.is_sealed(), "the arena reopens after the defeat")


func test_on_foot_bot_defeats_grukk() -> void:
	_start_bot(FightBot.Plan.ON_FOOT)
	watch_signals(EventBus)
	var finished: bool = await _run_until(func() -> bool: return _bot.stage == FightBot.Stage.DONE)
	assert_true(finished, "the fight ended within budget" + _story())
	_assert_victory()
	assert_signal_emitted(EventBus, "boss_engaged")
	assert_signal_emitted(EventBus, "boss_defeated")
	assert_gt(_bot.hits[&"melee"], 0, "melee landed")
	assert_gt(_bot.hits[&"arrow"], 0, "arrows landed")
	assert_gt(_bot.dodges, 0, "telegraphed moves were dodged")


func test_mounted_bot_defeats_grukk() -> void:
	_start_bot(FightBot.Plan.MOUNTED)
	var finished: bool = await _run_until(func() -> bool: return _bot.stage == FightBot.Stage.DONE)
	assert_true(finished, "the fight ended within budget" + _story())
	_assert_victory()
	assert_gt(_bot.mounts, 0, "the bot called and mounted the cat")
	assert_gt(_bot.hits[&"pounce"], 0, "pounces landed")
	assert_gt(_bot.hits[&"mounted_arrow"], 0, "arrows from the saddle landed")


func test_idle_bot_dies_and_respawns_at_the_checkpoint_with_grukk_reset() -> void:
	_start_bot(FightBot.Plan.IDLE)
	var player: Player = _level.player
	var boss: BossBase = _level.boss
	var died: bool = await _run_until(func() -> bool: return _main.state_name() == &"dead")
	assert_true(died, "Grukk killed the idle player" + _story())
	assert_true(player.health.is_dead())
	assert_eq(_main.current_menu().title_text(), "YOU WERE SQUASHED")
	var checkpoint: Checkpoint = _level.get_node("Checkpoint") as Checkpoint
	assert_eq(GameState.checkpoint, checkpoint, "the bot rested at the Mushroom Ring")

	# Respawn through the death screen's real button.
	(_main.current_menu() as MenuScreen).first_button().pressed.emit()
	await get_tree().physics_frame
	assert_eq(_main.state_name(), &"playing")
	assert_eq(player.health.current, player.health.max_health, "full HP")
	assert_eq(player.state_machine.current_state_name, &"Idle", "alive again")
	var offset: Vector3 = player.global_position - checkpoint.global_position
	assert_lt(Vector2(offset.x, offset.z).length(), 0.5, "back at the checkpoint")
	assert_eq(boss.health.current, boss.health.max_health, "Grukk at full health")
	assert_eq(boss.phase_controller.phase, 1, "Grukk back in phase 1")
	assert_false(boss.engaged, "Grukk no longer engaged")
	assert_false(boss.defeated)
	assert_false(_level.fog_gate.is_engaged(), "the gate can be engaged again")
	assert_false(_level.fog_gate.is_sealed(), "the arena is open")
	var spawn: Node3D = _level.fog_gate.get_node("BossSpawn") as Node3D
	assert_lt(boss.global_position.distance_to(spawn.global_position), 0.5, "Grukk at his spawn")
