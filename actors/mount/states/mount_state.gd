class_name MountState
extends State
## Shared helper for the cat's states: reaches the [CatMount] and its stats. Not a behaviour
## itself; each concrete state lives in its own file and extends this.

@onready var cat: CatMount = owner as CatMount


## The state a cat returns to when an action ends: ridden when it has a rider, else idle.
func resting_state() -> StringName:
	return &"Ridden" if cat.rider != null else &"Idle"
