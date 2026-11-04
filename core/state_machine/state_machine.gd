class_name StateMachine
extends Node
## Node-based finite state machine.
##
## Add one child [State] node per behaviour and set `initial_state` to its node
## name. The machine forwards `_process`, `_physics_process` and `_unhandled_input`
## to whichever state is active and owns every transition, so state code stays
## small and testable.
##
## ```gdscript
## @onready var state_machine: StateMachine = %StateMachine
##
## func _ready() -> void:
## 	state_machine.transition_to(&"Idle")
## ```

## Emitted after a transition completed. `from_name` is empty on the first entry.
signal state_changed(from_name: StringName, to_name: StringName)

## Name of the child state to enter automatically in `_ready`, if any.
@export var initial_state: StringName = &""

## Name of the state currently active, or empty before the first transition.
var current_state_name: StringName = &""

var _current_state: State = null
var _states: Dictionary = {}


func _ready() -> void:
	for child in get_children():
		if child is State:
			var state := child as State
			state.state_machine = self
			_states[StringName(state.name)] = state
	if initial_state != &"":
		transition_to(initial_state)


func _process(delta: float) -> void:
	if _current_state != null:
		_current_state.update(delta)


func _physics_process(delta: float) -> void:
	if _current_state != null:
		_current_state.physics_update(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _current_state != null:
		_current_state.handle_input(event)


## Switches to the child state named `state_name`.
## Returns true when the transition happened, false when the name is unknown or
## already active. Unknown names are reported as errors rather than silently
## ignored, because a typo would otherwise look like a frozen actor.
func transition_to(state_name: StringName) -> bool:
	if state_name == current_state_name:
		return false
	if not _states.has(state_name):
		push_error("StateMachine: no such state '%s' on '%s'" % [state_name, name])
		return false

	var previous_name := current_state_name
	if _current_state != null:
		_current_state.exit()

	_current_state = _states[state_name] as State
	current_state_name = state_name
	_current_state.enter(previous_name)
	state_changed.emit(previous_name, state_name)
	return true


## True when a child [State] with this name exists.
func has_state(state_name: StringName) -> bool:
	return _states.has(state_name)


## The active [State] node, or null before the first transition.
func get_current_state() -> State:
	return _current_state


## Names of every child state, sorted, useful in tests and debug overlays.
func get_state_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for state_name in _states.keys():
		names.append(state_name as StringName)
	names.sort()
	return names
