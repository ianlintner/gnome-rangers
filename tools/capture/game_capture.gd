class_name GameCapture
extends Node
## Real-game capture driver: boots `res://main.tscn` in a fixed 1280x720 SubViewport (so output
## is independent of the window manager) and saves one PNG per requested shot.
## Run as a scene (not `-s`) so autoloads exist; needs a real display, never `--headless`.
## Use `tools/capture/game.sh [--shots a,b,...] [--out DIR]`.
##
## Shot registry contract (stable; later tickets only change what is on screen):
##  - [constant SHOTS] maps a shot name to the name of a method on this class.
##  - Every shot method is a coroutine `func _shot_x() -> void` that starts from a freshly booted
##    game (title screen up), drives it until the state it names is on screen, and returns. The
##    driver then waits for the frame to draw and writes `<out>/<shot name>.png`.
##  - To add a shot: add a SHOTS entry and its method. Names are the PNG file names.
## Reaching states uses the headless bot-fight helpers ([FightBot], [BotInput], [BotClock]).

const SIZE: Vector2i = Vector2i(1280, 720)
const MAIN: PackedScene = preload("res://main.tscn")
const DEFAULT_OUT: String = "~/lab/artifacts/playable-sweep/gnome-rangers/next/"
## Wall-clock safety net (ms) for any one "drive until" loop.
const WALL_BUDGET_MS: int = 120000
const SHOTS: Dictionary = {
	&"title_backdrop": &"_shot_title_backdrop",
	&"first_run_controls": &"_shot_first_run_controls",
	&"on_foot_explore": &"_shot_on_foot_explore",
	&"mounted_gallop_gnome": &"_shot_mounted_gallop_gnome",
	&"fog_gate_prompt": &"_shot_fog_gate_prompt",
	&"boss_phase2_hit_sparks": &"_shot_boss_phase2_hit_sparks",
	&"death_world_behind": &"_shot_death_world_behind",
	&"victory": &"_shot_victory",
}

var _out_dir: String = DEFAULT_OUT
var _requested: Array[StringName] = []
var _viewport: SubViewport = null
var _game: GameFlow = null
var _failed: bool = false
var _hit_phase2: bool = false


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i < args.size():
		if args[i] == "--out" and i + 1 < args.size():
			i += 1
			_out_dir = args[i]
		elif args[i] == "--shots" and i + 1 < args.size():
			i += 1
			for shot_name: String in args[i].split(",", false):
				_requested.append(StringName(shot_name))
		i += 1
	if _requested.is_empty():
		for key: StringName in SHOTS.keys():
			_requested.append(key)
	_out_dir = _out_dir.replace("~", OS.get_environment("HOME"))
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run()


## Returns the names of requested shots that are not in [constant SHOTS].
static func unknown_shots(names: Array[StringName]) -> Array[StringName]:
	var unknown: Array[StringName] = []
	for shot_name: StringName in names:
		if not SHOTS.has(shot_name):
			unknown.append(shot_name)
	return unknown


func _run() -> void:
	var unknown: Array[StringName] = unknown_shots(_requested)
	if not unknown.is_empty():
		push_error("game_capture.gd: unknown shots %s (known: %s)" % [unknown, SHOTS.keys()])
		get_tree().quit(2)
		return
	for shot_name: StringName in _requested:
		await _boot()
		await call(SHOTS[shot_name] as StringName)
		BotClock.restore()
		await _write(shot_name)
		_game.free()
		_game = null
		_viewport.free()
		_viewport = null
		BotInput.release_all()
		if _failed:
			break
	get_tree().quit(1 if _failed else 0)


func _boot() -> void:
	GameState.clear()
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_game = MAIN.instantiate() as GameFlow
	_viewport.add_child(_game)
	await _frames(5)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await get_tree().physics_frame


func _write(shot_name: StringName) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("game_capture.gd: no image for %s" % shot_name)
		_failed = true
		return
	var path: String = "%s/%s.png" % [_out_dir, shot_name]
	var err: Error = image.save_png(path)
	if err != OK:
		push_error("game_capture.gd: failed to save %s (error %d)" % [path, err])
		_failed = true
		return
	print("game_capture.gd: wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])


## Starts a new game and lets the level settle (navmesh ready) so a bot can plan paths.
func _start_game() -> RootfallHollow:
	_game.start_new_game()
	var level := _game.level() as RootfallHollow
	var goal: Vector3 = level.boss.global_position
	var map: RID = level.get_world_3d().navigation_map
	NavigationServer3D.map_set_use_async_iterations(map, false)
	for _i: int in range(240):
		await get_tree().physics_frame
		var path: PackedVector3Array = NavigationServer3D.map_get_path(
			map, level.player.global_position, goal, true
		)
		if not path.is_empty():
			break
	return level


func _start_bot(plan: FightBot.Plan) -> FightBot:
	var level: RootfallHollow = await _start_game()
	seed(20261126)
	level.boss.brain.set_seed(20261126)
	var bot := FightBot.new(level, plan)
	level.add_child(bot)
	BotClock.fast_forward()
	return bot


## Steps physics until `done` returns true; flags a failure when the safety budget is hit.
func _until(done: Callable, what: String) -> bool:
	var started: int = Time.get_ticks_msec()
	while not done.call():
		await get_tree().physics_frame
		if Time.get_ticks_msec() - started > WALL_BUDGET_MS:
			push_error("game_capture.gd: gave up waiting for %s" % what)
			_failed = true
			return false
	return true


# --- Shots ------------------------------------------------------------------------------------


func _shot_title_backdrop() -> void:
	await _frames(30)


func _shot_first_run_controls() -> void:
	# Until the controls card exists this is the first frame after New Game.
	await _start_game()


func _shot_on_foot_explore() -> void:
	var bot: FightBot = await _start_bot(FightBot.Plan.ON_FOOT)
	await _until(func() -> bool: return bot.stage == FightBot.Stage.TRAVEL, "bot to leave camp")
	await _frames(240)
	BotClock.restore()
	await _frames(2)


func _shot_mounted_gallop_gnome() -> void:
	var bot: FightBot = await _start_bot(FightBot.Plan.MOUNTED)
	await _until(
		func() -> bool: return bot.stage == FightBot.Stage.TRAVEL and bot.player.mount != null,
		"rider to be mounted"
	)
	await _frames(180)
	BotClock.restore()
	await _frames(2)


func _shot_fog_gate_prompt() -> void:
	var bot: FightBot = await _start_bot(FightBot.Plan.MOUNTED)
	await _until(func() -> bool: return bot.level.fog_gate.is_sealed(), "the fog gate to seal")
	BotClock.restore()
	await _frames(2)


func _shot_boss_phase2_hit_sparks() -> void:
	var bot: FightBot = await _start_bot(FightBot.Plan.ON_FOOT)
	_hit_phase2 = false
	var on_hit := func(info: DamageInfo) -> void:
		if info.source == bot.player and bot.boss.phase_controller.phase >= 2:
			_hit_phase2 = true
	EventBus.hit_feedback.connect(on_hit)
	await _until(func() -> bool: return _hit_phase2, "a landed hit in phase 2")
	EventBus.hit_feedback.disconnect(on_hit)
	BotClock.restore()
	# One frame on: the spark burst spawned by the hit is on screen.
	await _frames(1)


func _shot_death_world_behind() -> void:
	var level: RootfallHollow = await _start_game()
	await _frames(60)
	level.player.health.take_damage(level.player.health.max_health * 10.0)
	await _until(func() -> bool: return _game.state_name() == &"dead", "the death screen")
	await _frames(30)


func _shot_victory() -> void:
	var level: RootfallHollow = await _start_game()
	await _frames(30)
	level.boss.engage(level.player)
	level.boss.health.take_damage(level.boss.health.max_health * 10.0)
	await _until(func() -> bool: return _game.state_name() == &"victory", "the victory screen")
	await _frames(30)
