extends GutTest
## Every menu has a valid initial focus and a closed loop of focus neighbours,
## so a gamepad can reach and activate every button without a mouse.

const MENUS: Array[PackedScene] = [
	preload("res://ui/menus/title.tscn"),
	preload("res://ui/menus/pause.tscn"),
	preload("res://ui/menus/settings.tscn"),
	preload("res://ui/menus/death.tscn"),
	preload("res://ui/menus/victory.tscn"),
]


func test_each_menu_grabs_focus_on_first_button() -> void:
	for packed: PackedScene in MENUS:
		var menu: Control = packed.instantiate() as Control
		add_child_autofree(menu)
		assert_not_null(get_viewport().gui_get_focus_owner(), menu.scene_file_path)
		assert_eq(get_viewport().gui_get_focus_owner(), menu.first_button(), menu.scene_file_path)
		menu.free()


func test_each_menu_has_closed_focus_neighbour_loop() -> void:
	for packed: PackedScene in MENUS:
		var menu: Control = packed.instantiate() as Control
		add_child_autofree(menu)
		var buttons: Array[Button] = menu.buttons()
		assert_gt(buttons.size(), 1, menu.scene_file_path)
		for i: int in range(buttons.size()):
			var current: Button = buttons[i]
			var down: NodePath = current.focus_neighbor_bottom
			assert_ne(
				down,
				NodePath(""),
				"%s %s has a down neighbour" % [menu.scene_file_path, current.text]
			)
			var next: Node = menu.get_node_or_null(down)
			assert_not_null(next, "%s resolves %s" % [menu.scene_file_path, down])
			assert_true(next is Button, "%s neighbour is a button" % menu.scene_file_path)
		# A full walk visits every button exactly once.
		var visited: Array[Button] = []
		var cursor: Button = buttons[0]
		for _i: int in range(buttons.size()):
			assert_false(visited.has(cursor), "%s focus loop repeats early" % menu.scene_file_path)
			visited.append(cursor)
			cursor = menu.get_node(cursor.focus_neighbor_bottom) as Button
		assert_eq(cursor, buttons[0], "%s focus loop closes" % menu.scene_file_path)
		menu.free()


func test_title_has_continue_new_settings_and_quit() -> void:
	var menu: Control = (MENUS[0] as PackedScene).instantiate() as Control
	add_child_autofree(menu)
	var labels: Array[String] = []
	for button: Button in menu.buttons():
		labels.append(button.text.to_lower())
	assert_true(labels.has("continue"))
	assert_true(labels.has("new game"))
	assert_true(labels.has("settings"))
	assert_true(labels.has("quit"))


func test_pause_has_resume_settings_and_quit_to_title() -> void:
	var menu: Control = (MENUS[1] as PackedScene).instantiate() as Control
	add_child_autofree(menu)
	var labels: Array[String] = []
	for button: Button in menu.buttons():
		labels.append(button.text.to_lower())
	assert_true(labels.has("resume"))
	assert_true(labels.has("settings"))
	assert_true(labels.has("quit to title"))


func test_death_screen_has_respawn_and_quit() -> void:
	var menu: Control = (MENUS[3] as PackedScene).instantiate() as Control
	add_child_autofree(menu)
	assert_eq(menu.title_text().to_lower(), "you were squashed")
	var labels: Array[String] = []
	for button: Button in menu.buttons():
		labels.append(button.text.to_lower())
	assert_true(labels.has("respawn"))
	assert_true(labels.has("quit to title"))


func test_victory_screen_announces_the_win() -> void:
	var menu: Control = (MENUS[4] as PackedScene).instantiate() as Control
	add_child_autofree(menu)
	assert_true(menu.title_text().to_lower().contains("victory"))
	assert_gt(menu.buttons().size(), 0)


func test_settings_menu_exposes_all_five_options() -> void:
	var menu: Control = (MENUS[2] as PackedScene).instantiate() as Control
	add_child_autofree(menu)
	var labels: String = " ".join(menu.option_labels())
	for token: String in ["Mouse", "Stick", "Invert Y", "FOV", "volume", "Quality"]:
		assert_true(labels.contains(token), "option %s" % token)
