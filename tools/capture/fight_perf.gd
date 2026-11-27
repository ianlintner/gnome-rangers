extends Node
## Logs per-second FPS across a full real on-foot Grukk fight (scripted by FightBot).
## Run as a scene so project autoloads exist. Needs a real rendering device; see fight_perf.sh.
## BotClock must stay fast-forwarded: the bot's fixed game-time step makes the run repeatable,
## while each logged sample covers one real second of rendering on the dev box.

const SEED: int = 20261126
const FACTOR: float = 8.0
const MAX_SECONDS: float = 180.0

var _level: RootfallHollow = null
var _bot: FightBot = null
var _out: String = "res://docs/perf/final_fight_fps.txt"
var _lines: PackedStringArray = PackedStringArray()
var _sample_start_usec: int = 0
var _started_usec: int = 0
var _frames: int = 0


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i < args.size():
		if args[i] == "--out":
			i += 1
			if i < args.size():
				_out = args[i]
		i += 1
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	GameState.clear()
	BotClock.fast_forward(FACTOR)
	var packed: PackedScene = load("res://main.tscn") as PackedScene
	var game: GameFlow = packed.instantiate() as GameFlow
	viewport.add_child(game)
	game.start_new_game()
	_level = game.level() as RootfallHollow
	await _wait_for_navigation()
	seed(SEED)
	_level.boss.brain.set_seed(SEED)
	_bot = FightBot.new(_level, FightBot.Plan.ON_FOOT)
	_level.add_child(_bot)
	var now: int = Time.get_ticks_usec()
	_started_usec = now
	_sample_start_usec = now
	_lines.append(
		(
			"seed=%d factor=%.0f physics_tps=%d viewport=1280x720"
			% [SEED, FACTOR, Engine.physics_ticks_per_second]
		)
	)
	_lines.append("t_real_s,fps,boss_hp,boss_phase,bot_stage,hits_melee,hits_arrow")


func _wait_for_navigation() -> void:
	var map: RID = _level.get_world_3d().navigation_map
	get_tree().paused = true
	NavigationServer3D.map_set_use_async_iterations(map, false)
	for _frame: int in range(240):
		await get_tree().physics_frame
		var path: PackedVector3Array = NavigationServer3D.map_get_path(
			map, _level.player.global_position, _level.boss.global_position, true
		)
		if not path.is_empty():
			break
	get_tree().paused = false


func _process(_delta: float) -> void:
	if _started_usec == 0:
		return
	var now: int = Time.get_ticks_usec()
	var elapsed: float = float(now - _started_usec) / 1000000.0
	var sample: float = float(now - _sample_start_usec) / 1000000.0
	_frames += 1
	if sample >= 1.0:
		_lines.append(
			(
				"%.1f,%.1f,%.0f,%d,%d,%d,%d"
				% [
					elapsed,
					_frames / sample,
					_level.boss.health.current,
					_level.boss.phase_controller.phase,
					_bot.stage,
					_bot.hits[&"melee"],
					_bot.hits[&"arrow"]
				]
			)
		)
		_sample_start_usec = now
		_frames = 0
	var done: bool = _bot.stage == FightBot.Stage.DONE or _level.boss.health.is_dead()
	if done or elapsed > MAX_SECONDS:
		_lines.append(
			(
				"%.1f,%.1f,%.0f,%d,%d,%d,%d"
				% [
					elapsed,
					_frames / maxf(sample, 0.001),
					_level.boss.health.current,
					_level.boss.phase_controller.phase,
					_bot.stage,
					_bot.hits[&"melee"],
					_bot.hits[&"arrow"]
				]
			)
		)
		_write()
		get_tree().quit(0)


func _write() -> void:
	BotClock.restore()
	var dir: String = _out.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(_out, FileAccess.WRITE)
	if file == null:
		push_error("fight_perf.gd: cannot write %s" % _out)
		return
	for line: String in _lines:
		file.store_line(line)
	file.close()
	print("fight_perf.gd: wrote %s (%d samples)" % [_out, _lines.size() - 2])
