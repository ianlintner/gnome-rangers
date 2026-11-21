extends MenuScreen
## Title screen: Continue (only useful with a checkpoint), New Game, Settings, Quit.


func _init() -> void:
	menu_title = "GNOME RANGERS"
	menu_subtitle = "Rootfall Hollow"


func menu_actions() -> Array:
	return [
		{&"text": "Continue", &"action": &"continue"},
		{&"text": "New Game", &"action": &"new_game"},
		{&"text": "Settings", &"action": &"settings"},
		{&"text": "Quit", &"action": &"quit"},
	]
