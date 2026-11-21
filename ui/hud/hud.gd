class_name Hud
extends CanvasLayer
## Souls-style minimal HUD. Every value comes from an EventBus signal; gameplay
## nodes are never queried. The only per-frame work is the delayed ghost bar and
## screen projection of an externally supplied lock-on target.
##
## Visuals are built here from [Palette] tokens so there is no inline hex anywhere
## in the UI (the shared theme supplies fonts and focus visuals).

const BAR_WIDTH: float = 240.0
const BAR_HEIGHT: float = 10.0
const BORDER: int = 2
const BOSS_WIDTH: float = 560.0

## Seconds before the damage ghost starts closing the gap.
@export var ghost_delay: float = 0.45
## Speed of the ghost catch-up, in ratio units per second.
@export var ghost_speed: float = 0.6
## Centre of the screen in viewport coordinates; updated on resize.
var screen_center: Vector2 = Vector2.ZERO

var _health_fill: ProgressBar
var _health_ghost: ProgressBar
var _stamina_fill: ProgressBar
var _mount_fill: ProgressBar
var _mount_root: PanelContainer
var _boss_root: PanelContainer
var _boss_name: Label
var _boss_fill: ProgressBar
var _lock_on: Polygon2D
var _reticle_root: Node2D
var _reticle_lines: Array[Line2D] = []

var _health_ratio: float = 1.0
var _ghost_ratio: float = 1.0
var _ghost_target: float = 1.0
var _ghost_timer: float = 0.0
var _stamina_ratio: float = 1.0
var _mount_ratio: float = 1.0
var _boss_ratio: float = 1.0
var _lock_target: Node = null
var _aiming: bool = false
var _draw_ratio: float = 0.0


func _ready() -> void:
	screen_center = get_viewport().get_visible_rect().size * 0.5
	_build_bars()
	_build_boss_bar()
	_build_markers()
	_connect_signals()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_on_resized)


func _exit_tree() -> void:
	for signal_info: Array in _events():
		var source: Object = signal_info[0]
		var signal_name: StringName = signal_info[1]
		var callable_target: Callable = Callable(self, signal_info[2])
		if is_instance_valid(source) and source.is_connected(signal_name, callable_target):
			source.disconnect(signal_name, callable_target)
	for pair: Array in [
		[EventBus, &"player_died", Callable(self, "_on_boss_reset")],
		[EventBus, &"player_respawned", Callable(self, "_on_boss_reset")],
		[GameState, &"run_reset", Callable(self, "_on_boss_reset")],
	]:
		if pair[0].is_connected(pair[1], pair[2]):
			pair[0].disconnect(pair[1], pair[2])


func _events() -> Array:
	return [
		[EventBus, &"player_health_changed", &"_on_player_health_changed"],
		[EventBus, &"player_stamina_changed", &"_on_player_stamina_changed"],
		[EventBus, &"mount_health_changed", &"_on_mount_health_changed"],
		[EventBus, &"mount_mounted", &"_on_mount_mounted"],
		[EventBus, &"mount_dismounted", &"_on_mount_dismounted"],
		[EventBus, &"boss_engaged", &"_on_boss_engaged"],
		[EventBus, &"boss_defeated", &"_on_boss_defeated"],
		[EventBus, &"game_won", &"_on_boss_defeated"],
		[EventBus, &"lock_on_changed", &"_on_lock_on_changed"],
		[EventBus, &"aim_changed", &"_on_aim_changed"],
		[EventBus, &"bow_draw_changed", &"_on_bow_draw_changed"],
	]


func _connect_signals() -> void:
	for signal_info: Array in _events():
		var source: Object = signal_info[0]
		source.connect(signal_info[1], Callable(self, signal_info[2]))
	EventBus.player_died.connect(_on_boss_reset)
	EventBus.player_respawned.connect(_on_boss_reset)
	GameState.run_reset.connect(_on_boss_reset)


func _process(delta: float) -> void:
	if _ghost_ratio > _ghost_target:
		if _ghost_timer > 0.0:
			_ghost_timer -= delta
			return
		_ghost_ratio = maxf(_ghost_target, _ghost_ratio - ghost_speed * delta)
		_health_ghost.value = _ghost_ratio * 100.0
	elif _ghost_ratio < _ghost_target:
		_ghost_ratio = _ghost_target
		_health_ghost.value = _ghost_ratio * 100.0
	if _lock_target != null:
		project_lock_on(get_viewport().get_camera_3d())


# --- Construction -----------------------------------------------------------


func _build_bars() -> void:
	var root := VBoxContainer.new()
	root.name = "Bars"
	root.position = Vector2(24.0, 24.0)
	root.add_theme_constant_override(&"separation", 6)
	add_child(root)

	# The ghost sits behind the health fill in the same track.
	var track: PanelContainer = PanelContainer.new()
	track.name = "HealthTrack"
	track.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT + 2 * BORDER)
	track.add_theme_stylebox_override(&"panel", HudBuilder.backing_style())
	root.add_child(track)
	_health_ghost = HudBuilder.overlaid_bar("HealthGhost", Palette.CANOPY_HAZE.darkened(0.3), track)
	_health_fill = HudBuilder.overlaid_bar("Health", Palette.HEALTH, track)
	# Stack both progress bars in the same rectangle.
	_health_ghost.set_anchors_preset(Control.PRESET_FULL_RECT)
	_health_fill.set_anchors_preset(Control.PRESET_FULL_RECT)

	_stamina_fill = HudBuilder.bar(root, "Stamina", Palette.STAMINA, BAR_WIDTH * 0.8, BAR_HEIGHT)
	_mount_root = PanelContainer.new()
	_mount_root.name = "Mount"
	_mount_root.add_theme_stylebox_override(&"panel", HudBuilder.backing_style())
	root.add_child(_mount_root)
	var inner := VBoxContainer.new()
	_mount_root.add_child(inner)
	_mount_fill = HudBuilder.bar(
		inner, "MountHealth", Palette.MOUNT_HEALTH, BAR_WIDTH * 0.6, BAR_HEIGHT
	)
	_mount_root.visible = false


func _build_boss_bar() -> void:
	_boss_root = PanelContainer.new()
	_boss_root.name = "Boss"
	_boss_root.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_boss_root.position = Vector2(-BOSS_WIDTH * 0.5, -96.0)
	_boss_root.custom_minimum_size = Vector2(BOSS_WIDTH, 52.0)
	_boss_root.add_theme_stylebox_override(&"panel", HudBuilder.backing_style())
	add_child(_boss_root)
	_boss_root.visible = false

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override(&"separation", 4)
	_boss_root.add_child(inner)
	_boss_name = Label.new()
	_boss_name.name = "BossName"
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.add_theme_font_size_override(&"font_size", 18)
	_boss_name.add_theme_color_override(&"font_color", Palette.STAMINA)
	inner.add_child(_boss_name)
	_boss_fill = HudBuilder.bar(
		inner, "BossHealth", Palette.HEALTH, BOSS_WIDTH - 2 * BORDER, BAR_HEIGHT
	)


func _build_markers() -> void:
	_lock_on = Polygon2D.new()
	_lock_on.name = "LockOn"
	_lock_on.polygon = PackedVector2Array(
		[Vector2(0, -12), Vector2(12, 0), Vector2(0, 12), Vector2(-12, 0)]
	)
	_lock_on.color = Palette.CANOPY_HAZE
	_lock_on.visible = false
	add_child(_lock_on)

	_reticle_root = Node2D.new()
	_reticle_root.name = "Reticle"
	_reticle_root.visible = false
	add_child(_reticle_root)
	for _i: int in range(4):
		var line := Line2D.new()
		line.width = 2.0
		line.default_color = Palette.CANOPY_HAZE
		line.add_point(Vector2.ZERO)
		line.add_point(Vector2.ZERO)
		_reticle_root.add_child(line)
		_reticle_lines.append(line)
	_update_reticle()


# --- Signal handlers --------------------------------------------------------


func _on_player_health_changed(current: float, maximum: float) -> void:
	var ratio: float = clampf(current / maxf(maximum, 0.0001), 0.0, 1.0)
	_health_ratio = ratio
	_health_fill.value = ratio * 100.0
	if ratio < _ghost_target:
		_ghost_timer = ghost_delay
	_ghost_target = ratio
	if ratio >= _ghost_ratio:
		_ghost_ratio = ratio
		_health_ghost.value = ratio * 100.0


func _on_player_stamina_changed(current: float, maximum: float) -> void:
	_stamina_ratio = clampf(current / maxf(maximum, 0.0001), 0.0, 1.0)
	_stamina_fill.value = _stamina_ratio * 100.0


func _on_mount_health_changed(current: float, maximum: float) -> void:
	_mount_ratio = clampf(current / maxf(maximum, 0.0001), 0.0, 1.0)
	_mount_fill.value = _mount_ratio * 100.0


func _on_mount_mounted() -> void:
	_mount_root.visible = true


func _on_mount_dismounted() -> void:
	_mount_root.visible = false


func _on_boss_engaged(boss: Node) -> void:
	_boss_root.visible = true
	_boss_name.text = boss.name.to_upper() if boss != null else ""
	_boss_fill.value = 100.0
	_boss_ratio = 1.0


func _on_boss_defeated(_boss: Node = null) -> void:
	_boss_root.visible = false


func _on_boss_reset() -> void:
	_boss_root.visible = false


func _on_lock_on_changed(target: Node) -> void:
	_lock_target = target if is_instance_valid(target) else null
	_lock_on.visible = _lock_target != null
	if _lock_target == null:
		return
	project_lock_on(get_viewport().get_camera_3d())


func _on_aim_changed(active: bool) -> void:
	_aiming = active
	_reticle_root.visible = active
	_update_reticle()


func _on_bow_draw_changed(ratio: float) -> void:
	_draw_ratio = clampf(ratio, 0.0, 1.0)
	_update_reticle()


func _on_resized() -> void:
	screen_center = get_viewport().get_visible_rect().size * 0.5
	_update_reticle()


# --- Projection and visuals -------------------------------------------------


## Projects the current lock-on target to screen space. `camera` may be null (tests
## and menus); in that case the diamond simply sits at screen centre.
func project_lock_on(camera: Camera3D) -> void:
	if _lock_target == null:
		_lock_on.visible = false
		return
	_lock_on.visible = true
	if camera == null or not (_lock_target is Node3D):
		_lock_on.position = screen_center
		return
	var world_point: Vector3 = (_lock_target as Node3D).global_position
	var projected: Vector2 = camera.unproject_position(world_point)
	var rect: Rect2 = get_viewport().get_visible_rect()
	_lock_on.position = Vector2(
		clampf(projected.x, BORDER, rect.size.x - BORDER),
		clampf(projected.y, BORDER, rect.size.y - BORDER)
	)


func _update_reticle() -> void:
	var spread: float = reticle_spread()
	var directions: Array[Vector2] = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
	for i: int in range(_reticle_lines.size()):
		var direction: Vector2 = directions[i]
		_reticle_lines[i].set_point_position(0, direction * spread)
		_reticle_lines[i].set_point_position(1, direction * (spread + 14.0))
	_reticle_root.position = screen_center


func reticle_spread() -> float:
	return lerpf(34.0, 8.0, _draw_ratio)


# --- Test-facing accessors --------------------------------------------------


func health_ratio() -> float:
	return _health_ratio


func ghost_ratio() -> float:
	return _ghost_ratio


func stamina_ratio() -> float:
	return _stamina_ratio


func mount_ratio() -> float:
	return _mount_ratio


func mount_root() -> Control:
	return _mount_root


func boss_root() -> Control:
	return _boss_root


func boss_name_text() -> String:
	return _boss_name.text


func lock_on_root() -> Node2D:
	return _lock_on


func reticle_root() -> Node2D:
	return _reticle_root


func health_color() -> Color:
	return Palette.HEALTH


func stamina_color() -> Color:
	return Palette.STAMINA


func mount_color() -> Color:
	return Palette.MOUNT_HEALTH


func backing_color() -> Color:
	return Palette.PANEL_BACKING
