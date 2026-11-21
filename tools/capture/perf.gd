extends SceneTree
## Fly-through performance capture: logs average fps along the approach path to the arena.
##
## Needs a real rendering device (not `--headless`); run it through perf.sh.
## Usage: godot --path . -s tools/capture/perf.gd -- [--scene res://...tscn] [--seconds N]
##   [--size WxH] [--tier high|dev] [--speed M_PER_S] [--hide Node,Node] [--out log.txt]
##
## The camera flies the Rootfall approach polyline at gnome eye height, then pans across the
## arena. Frames are timed with vsync off so the figure is raw throughput, not the refresh rate.
## The first `WARMUP` seconds are excluded from the averages (shader compilation, fog warm-up).

const WARMUP: float = 3.0
const EYE_HEIGHT: float = 1.6

var _scene_path: String = "res://levels/rootfall_hollow/rootfall_hollow.tscn"
var _seconds: float = 30.0
var _size := Vector2i(1920, 1080)
var _tier: String = "dev"
var _speed: float = 11.0
var _out: String = ""
var _hide: PackedStringArray = []

var _camera: Camera3D = null
var _elapsed: float = 0.0
var _distance: float = 0.0
var _frame_times: Array[float] = []
var _second_bucket: Array[float] = []
var _bucket_start: float = 0.0
var _per_second: Array[String] = []
var _route: Array[Vector3] = []
var _viewport: SubViewport = null


func _initialize() -> void:
	_parse_args()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var packed := load(_scene_path) as PackedScene
	if packed == null:
		push_error("perf.gd: cannot load %s" % _scene_path)
		quit(1)
		return
	_viewport = SubViewport.new()
	_viewport.size = _size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var level: Node = packed.instantiate()
	# Set the tier before entering the tree: the level applies it in its own `_ready`.
	if "quality_tier" in level:
		level.set(&"quality_tier", 1 if _tier == "dev" else 0)
	_viewport.add_child(level)
	for hidden: String in _hide:
		var node := level.get_node_or_null(hidden) as Node3D
		if node != null:
			node.visible = false
	_camera = Camera3D.new()
	_camera.fov = 62.0
	_camera.current = true
	_viewport.add_child(_camera)
	for point: Vector2 in RootfallLayout.PATH_XZ:
		_route.append(Vector3(point.x, EYE_HEIGHT, point.y))
	_route.append(RootfallLayout.ARENA_CENTER + Vector3(0.0, EYE_HEIGHT, 6.0))
	_place_camera()


func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i < args.size():
		match args[i]:
			"--scene":
				i += 1
				_scene_path = args[i]
			"--seconds":
				i += 1
				_seconds = float(args[i])
			"--size":
				i += 1
				var parts: PackedStringArray = args[i].split("x")
				_size = Vector2i(int(parts[0]), int(parts[1]))
			"--tier":
				i += 1
				_tier = args[i]
			"--speed":
				i += 1
				_speed = float(args[i])
			"--hide":
				i += 1
				_hide = args[i].split(",")
			"--out":
				i += 1
				_out = args[i]
		i += 1


func _process(delta: float) -> bool:
	_elapsed += delta
	_distance += _speed * delta
	_place_camera()
	if _elapsed >= WARMUP:
		_frame_times.append(delta)
		_second_bucket.append(delta)
		if _elapsed - _bucket_start >= 1.0 + WARMUP and _second_bucket.size() > 0:
			_flush_bucket()
	if _elapsed >= _seconds + WARMUP:
		_finish()
	return false


func _flush_bucket() -> void:
	var total: float = 0.0
	for frame: float in _second_bucket:
		total += frame
	_per_second.append(
		"t=%5.1fs  fps=%6.1f" % [_elapsed - WARMUP, float(_second_bucket.size()) / total]
	)
	_second_bucket.clear()
	_bucket_start = _elapsed - WARMUP


func _place_camera() -> void:
	var travelled: float = 0.0
	for index: int in range(_route.size() - 1):
		var leg: float = _route[index].distance_to(_route[index + 1])
		if _distance <= travelled + leg or index == _route.size() - 2:
			var t: float = clampf((_distance - travelled) / leg, 0.0, 1.0)
			var at: Vector3 = _route[index].lerp(_route[index + 1], t)
			var ahead: Vector3 = _route[index + 1] + Vector3(0.0, 0.6, 0.0)
			if at.distance_to(ahead) > 0.1:
				_camera.look_at_from_position(at, ahead, Vector3.UP)
			else:
				_camera.position = at
			return
		travelled += leg


func _finish() -> void:
	var sorted: Array[float] = _frame_times.duplicate()
	sorted.sort()
	var total: float = 0.0
	for frame: float in _frame_times:
		total += frame
	var average: float = float(_frame_times.size()) / total
	var p99_ms: float = sorted[int(float(sorted.size()) * 0.99)] * 1000.0
	var info: String = RenderingServer.get_video_adapter_name()
	var lines: Array[String] = [
		"adapter: %s" % info,
		"scene: %s  tier: %s  size: %dx%d" % [_scene_path, _tier, _size.x, _size.y],
		(
			"frames: %d over %.1fs (warmup %.0fs excluded), flight %.0f m"
			% [_frame_times.size(), total, WARMUP, minf(_distance, 400.0)]
		),
		"average_fps: %.1f" % average,
		"min_fps: %.1f  p99_frame_ms: %.1f" % [1.0 / sorted[sorted.size() - 1], p99_ms],
	]
	lines.append_array(_per_second)
	for line: String in lines:
		print(line)
	if _out != "":
		var file := FileAccess.open(_out, FileAccess.WRITE)
		if file != null:
			file.store_string("\n".join(lines) + "\n")
	quit(0)
