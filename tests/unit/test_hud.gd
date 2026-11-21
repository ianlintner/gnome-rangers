extends GutTest
## HUD reacts to component/EventBus signals only; it never polls gameplay nodes.

const HUD: PackedScene = preload("res://ui/hud/hud.tscn")

var _hud: CanvasLayer = null


func before_each() -> void:
	GameState.clear()
	_hud = HUD.instantiate() as CanvasLayer
	add_child_autofree(_hud)


func after_each() -> void:
	GameState.clear()
	_hud.free()
	_hud = null


func test_health_bar_reacts_to_player_health_changed() -> void:
	EventBus.player_health_changed.emit(30.0, 100.0)
	assert_almost_eq(_hud.health_ratio(), 0.3, 0.001)
	assert_almost_eq(_hud.ghost_ratio(), 1.0, 0.001, "ghost holds the pre-damage value")
	EventBus.player_health_changed.emit(10.0, 100.0)
	assert_almost_eq(_hud.health_ratio(), 0.1, 0.001)
	assert_almost_eq(_hud.ghost_ratio(), 1.0, 0.001, "ghost still lingers after further damage")
	EventBus.player_health_changed.emit(60.0, 100.0)
	assert_almost_eq(
		_hud.ghost_ratio(), 1.0, 0.001, "ghost still drains from the old high-water mark"
	)


func test_ghost_bar_catches_up_after_delay() -> void:
	_hud.ghost_delay = 0.0
	_hud.ghost_speed = 100.0
	EventBus.player_health_changed.emit(100.0, 100.0)
	EventBus.player_health_changed.emit(20.0, 100.0)
	_hud._process(0.016)
	assert_almost_eq(_hud.ghost_ratio(), 0.2, 0.001)


func test_stamina_and_mount_bars_react_to_signals() -> void:
	EventBus.player_stamina_changed.emit(5.0, 20.0)
	assert_almost_eq(_hud.stamina_ratio(), 0.25, 0.001)
	EventBus.mount_health_changed.emit(50.0, 200.0)
	assert_almost_eq(_hud.mount_ratio(), 0.25, 0.001)


func test_mount_bar_visibility_follows_mount_signals() -> void:
	assert_false(_hud.mount_root().visible, "hidden before mounting")
	EventBus.mount_mounted.emit()
	assert_true(_hud.mount_root().visible)
	EventBus.mount_dismounted.emit()
	assert_false(_hud.mount_root().visible)


func test_boss_bar_appears_on_engaged_and_hides_on_defeat() -> void:
	assert_false(_hud.boss_root().visible)
	EventBus.boss_engaged.emit(null)
	assert_true(_hud.boss_root().visible)
	assert_eq(_hud.boss_name_text(), "", "no name until boss publishes one")
	EventBus.boss_defeated.emit(null)
	assert_false(_hud.boss_root().visible)


func test_boss_bar_hides_on_reset_and_game_won() -> void:
	EventBus.boss_engaged.emit(null)
	GameState.reset_run()
	assert_false(_hud.boss_root().visible)
	EventBus.boss_engaged.emit(null)
	EventBus.game_won.emit()
	assert_false(_hud.boss_root().visible)


func test_boss_bar_uses_boss_name_when_available() -> void:
	var boss := Node3D.new()
	boss.name = "Grukk"
	add_child_autofree(boss)
	EventBus.boss_engaged.emit(boss)
	assert_eq(_hud.boss_name_text(), "GRUKK")


func test_lock_on_diamond_follows_target_signal() -> void:
	assert_false(_hud.lock_on_root().visible)
	var target := Node3D.new()
	add_child_autofree(target)
	target.global_position = Vector3(2, 1, 3)
	EventBus.lock_on_changed.emit(target)
	assert_true(_hud.lock_on_root().visible)
	_hud.screen_center = Vector2(640, 360)
	_hud.project_lock_on(get_viewport().get_camera_3d())
	# Without a camera the diamond still centres rather than dividing by zero.
	EventBus.lock_on_changed.emit(null)
	assert_false(_hud.lock_on_root().visible)


func test_bow_reticle_tightens_with_draw_ratio() -> void:
	assert_false(_hud.reticle_root().visible)
	EventBus.aim_changed.emit(true)
	assert_true(_hud.reticle_root().visible)
	EventBus.bow_draw_changed.emit(0.0)
	var wide: float = _hud.reticle_spread()
	EventBus.bow_draw_changed.emit(1.0)
	assert_lt(_hud.reticle_spread(), wide, "reticle closes as the bow draws")
	EventBus.aim_changed.emit(false)
	assert_false(_hud.reticle_root().visible)


func test_hud_uses_only_palette_colours() -> void:
	assert_eq(_hud.health_color(), Palette.BLANKET_RED)
	assert_eq(_hud.stamina_color(), Palette.BLANKET_OCHRE)
	assert_eq(_hud.mount_color(), Palette.CAT_SHEEN)
	assert_eq(_hud.backing_color().a, Palette.PANEL_BACKING.a)
