extends MenuScreen
## Pause overlay: Resume, Settings, Quit to title.


func _init() -> void:
	menu_title = "PAUSED"


func menu_actions() -> Array:
	return [
		{&"text": "Resume", &"action": &"resume"},
		{&"text": "Settings", &"action": &"settings"},
		{&"text": "Quit to title", &"action": &"quit_to_title"},
	]
