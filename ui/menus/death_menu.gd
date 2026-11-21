extends MenuScreen
## Death screen: the Souls-style failure message and a respawn at the checkpoint.


func _init() -> void:
	menu_title = "YOU WERE SQUASHED"
	menu_subtitle = "The forest remembers."


func menu_actions() -> Array:
	return [
		{&"text": "Respawn", &"action": &"respawn"},
		{&"text": "Quit to title", &"action": &"quit_to_title"},
	]
