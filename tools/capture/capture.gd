extends SceneTree
## Renders a scene for N frames, then saves the viewport to a PNG.
##
## Needs a real rendering device (not `--headless`); run it through capture.sh.
## Usage: godot --path . -s tools/capture/capture.gd -- <scene> <out.png>
## [--camera <NodePath>] [--size WxH] [--frames N]

var _out_path: String = ""
var _frames: int = 30
var _frame: int = 0
var _viewport: SubViewport = null


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var camera_path: String = ""
	var size := Vector2i(1280, 720)
	var positional: Array[String] = []
	var i: int = 0
	while i < args.size():
		match args[i]:
			"--camera":
				i += 1
				camera_path = args[i]
			"--size":
				i += 1
				var parts: PackedStringArray = args[i].split("x")
				size = Vector2i(int(parts[0]), int(parts[1]))
			"--frames":
				i += 1
				_frames = int(args[i])
			_:
				positional.append(args[i])
		i += 1
	if positional.size() < 2:
		push_error("capture.gd: usage: <scene> <out.png> [--camera <NodePath>] [--frames N]")
		quit(2)
		return
	_out_path = positional[1]

	var packed := load(positional[0]) as PackedScene
	if packed == null:
		push_error("capture.gd: cannot load scene %s" % positional[0])
		quit(1)
		return
	var instance: Node = packed.instantiate()
	# Render into a fixed-size SubViewport so output is independent of the window manager.
	_viewport = SubViewport.new()
	_viewport.size = size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_viewport.add_child(instance)
	if camera_path != "":
		var camera := instance.get_node_or_null(camera_path) as Camera3D
		if camera == null:
			push_error("capture.gd: no Camera3D at %s" % camera_path)
			quit(1)
			return
		camera.make_current()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < _frames:
		return false
	if _frame == _frames:
		_finish()
	return false


func _finish() -> void:
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("capture.gd: viewport returned no image (is a display attached?)")
		quit(1)
		return
	var err: Error = image.save_png(_out_path)
	if err != OK:
		push_error("capture.gd: failed to save %s (error %d)" % [_out_path, err])
		quit(1)
		return
	print(
		(
			"capture.gd: wrote %s (%dx%d, %d frames)"
			% [_out_path, image.get_width(), image.get_height(), _frames]
		)
	)
	quit(0)
