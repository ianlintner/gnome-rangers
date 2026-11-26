extends Node
## Plays the sandbox with scripted input and saves two PNGs of the main viewport: the rider
## mid-gallop and the cat mid-pounce. Needs a real rendering device (not `--headless`); run it
## through `tools/capture/mount.sh`, which passes the output directory after `--`.

const SANDBOX: PackedScene = preload("res://levels/sandbox/sandbox.tscn")
const DUMMY_AT: Vector3 = Vector3(1.2, 0.0, -16.0)

var _out_dir: String = "docs/captures"
var _sandbox: Node3D = null


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_sandbox = SANDBOX.instantiate() as Node3D
	add_child(_sandbox)
	_run.call_deferred()


func _run() -> void:
	var cat := _sandbox.get_node("CatMount") as CatMount
	(_sandbox.get_node("Dummies/DummyNear") as Node3D).global_position = Vector3(-12.0, 0.0, 6.0)
	(_sandbox.get_node("Dummies/DummyFar") as Node3D).global_position = DUMMY_AT
	await _wait(0.5)
	await _press(&"interact")
	await _wait(0.8)
	await _press(&"lock_on")
	await _wait(0.2)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait(1.1)
	await _save("mount_gallop.png")
	await _press(&"attack_heavy")
	await _wait(cat.stats.pounce_windup + cat.stats.pounce_leap_time * 0.5)
	await _save("mount_pounce.png")
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	get_tree().quit(0)


func _press(action: StringName) -> void:
	Input.action_press(action)
	await _wait(0.1)
	Input.action_release(action)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = _out_dir.path_join(file_name)
	if image == null or image.is_empty() or image.save_png(path) != OK:
		push_error("mount_capture_rig.gd: could not save %s" % path)
		get_tree().quit(1)
		return
	print("mount_capture_rig.gd: wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])
