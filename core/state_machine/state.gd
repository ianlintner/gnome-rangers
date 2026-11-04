class_name State
extends Node
## Base class for one behaviour state of a [StateMachine].
##
## Subclass this in `actors/<actor>/states/<state_name>_state.gd` and add the
## node as a child of the actor's `StateMachine`. The machine owns the
## lifecycle; states never transition themselves by touching siblings — they
## call `state_machine.transition_to("Other")`.

## The machine that owns this state. Set by [StateMachine] on `_ready`.
var state_machine: StateMachine = null


## Called when the machine enters this state.
## `_previous_state_name` is empty for the machine's initial state.
func enter(_previous_state_name: StringName = &"") -> void:
	pass


## Called when the machine leaves this state for another one.
func exit() -> void:
	pass


## Called every rendered frame while this state is active.
func update(_delta: float) -> void:
	pass


## Called every physics tick while this state is active.
func physics_update(_delta: float) -> void:
	pass


## Called with the current [InputEvent] while this state is active.
func handle_input(_event: InputEvent) -> void:
	pass
