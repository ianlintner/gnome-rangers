extends Node
## Renders four screenshots of the real MVP slice through `main.tscn`:
## checkpoint, mounted approach, Grukk in phase 2, and the victory menu.
## Run as a scene (not with -s) so project autoloads are registered.
## Needs a real rendering device (not --headless); see tools/capture/final_slice.sh.

const FRAMES: Array[int] = [40, 100, 170, 240]
const NAMES: PackedStringArray = [
	"final_checkpoint.png",
	"final_mounted_approach.png",
	"final_boss_phase2.png",
	"final_victory.png",
]

var _out_dir: String = "res://docs/captures"
var _viewport: SubViewport = null
var _game: Node = null
var _level: RootfallHollow = null
var _frame: int = 0
var _shot: int = 0


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i < args.size():
		if args[i] == "--out":
			i += 1
			if i < args.size():
				_out_dir = args[i]
		i += 1
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		push_error("final_slice.gd: cannot load res://main.tscn")
		get_tree().quit(1)
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_game = packed.instantiate()
	_viewport.add_child(_game)
	_game.call("start_new_game")
	_level = _game.get("_level") as RootfallHollow
	if _level == null or _level.player == null or _level.boss == null:
		push_error("final_slice.gd: level or actors missing")
		get_tree().quit(1)


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame == 41:
		var player: Player = _level.player
		var cat: CatMount = _level.mount
		if cat.attach_rider(player):
			player.state_machine.transition_to(&"Mounting")
		# Frame the arena approach, not the campfire.
		var gate: Node3D = _level.get_node_or_null("FogGate") as Node3D
		if gate != null:
			var approach: Vector3 = gate.global_position + Vector3(0.0, 0.0, 6.0)
			cat.global_position = approach
			player.global_position = approach
	elif _frame == 101:
		var player: Player = _level.player
		var boss: BossBase = _level.boss
		player.global_position = _level.arena_center() + Vector3(0.0, 0.0, 5.0)
		boss.global_position = _level.arena_center()
		boss.engage(player)
		EventBus.boss_engaged.emit(boss)
		boss.health.take_damage(340.0)
	elif _frame == 171:
		_level.boss.health.take_damage(1000.0)
	if _shot < FRAMES.size() and _frame >= FRAMES[_shot]:
		_save()
		_shot += 1
		if _shot >= FRAMES.size():
			get_tree().quit(0)


func _save() -> void:
	var index: int = _shot
	RenderingServer.frame_post_draw.connect(_write_image.bind(index), CONNECT_ONE_SHOT)


func _write_image(index: int) -> void:
	var image: Image = _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("final_slice.gd: viewport returned no image")
		get_tree().quit(1)
		return
	var path: String = _out_dir + "/" + NAMES[index]
	var err: Error = image.save_png(path)
	if err != OK:
		push_error("final_slice.gd: failed to save %s (error %d)" % [path, err])
		get_tree().quit(1)
		return
	print("final_slice.gd: wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])
