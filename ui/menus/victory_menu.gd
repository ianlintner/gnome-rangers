extends MenuScreen
## Victory screen, shown when the boss is defeated.


func _init() -> void:
	menu_title = "VICTORY"
	menu_subtitle = "Rootfall Hollow is quiet again."


func menu_actions() -> Array:
	return [
		{&"text": "New Game", &"action": &"new_game"},
		{&"text": "Quit to title", &"action": &"quit_to_title"},
	]
