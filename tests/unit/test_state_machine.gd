extends GutTest
## StateMachine / State unit tests.


class RecordingState:
	extends State
	var log: Array[String] = []

	func enter(previous_state_name: StringName = &"") -> void:
		log.append("enter(%s)" % previous_state_name)

	func exit() -> void:
		log.append("exit")

	func update(_delta: float) -> void:
		log.append("update")

	func physics_update(_delta: float) -> void:
		log.append("physics")

	func handle_input(_event: InputEvent) -> void:
		log.append("input")


var _machine: StateMachine
var _idle: RecordingState
var _run: RecordingState


func before_each() -> void:
	_machine = StateMachine.new()
	_idle = RecordingState.new()
	_idle.name = "Idle"
	_run = RecordingState.new()
	_run.name = "Run"
	_machine.add_child(_idle)
	_machine.add_child(_run)
	_machine.initial_state = &"Idle"
	add_child_autofree(_machine)


func test_initial_state_entered_on_ready() -> void:
	assert_eq(_machine.current_state_name, &"Idle")
	assert_eq(_idle.log, ["enter()"])
	assert_eq(_machine.get_current_state(), _idle)


func test_transition_runs_exit_then_enter_with_previous_name() -> void:
	assert_true(_machine.transition_to(&"Run"))
	assert_eq(_idle.log, ["enter()", "exit"])
	assert_eq(_run.log, ["enter(Idle)"])
	assert_eq(_machine.current_state_name, &"Run")


func test_transition_to_current_state_is_noop() -> void:
	assert_false(_machine.transition_to(&"Idle"))
	assert_eq(_idle.log, ["enter()"])


func test_unknown_state_is_rejected() -> void:
	assert_false(_machine.transition_to(&"Missing"))
	assert_push_error("no such state")
	assert_eq(_machine.current_state_name, &"Idle")


func test_state_changed_signal() -> void:
	watch_signals(_machine)
	_machine.transition_to(&"Run")
	assert_signal_emitted_with_parameters(_machine, "state_changed", [&"Idle", &"Run"])


func test_updates_forwarded_to_active_state_only() -> void:
	_machine._process(0.1)
	_machine._physics_process(0.1)
	_machine._unhandled_input(InputEventKey.new())
	assert_eq(_idle.log, ["enter()", "update", "physics", "input"])
	assert_eq(_run.log, [])


func test_state_names_and_back_reference() -> void:
	assert_true(_machine.has_state(&"Run"))
	assert_false(_machine.has_state(&"Nope"))
	assert_eq(_machine.get_state_names(), [&"Idle", &"Run"])
	assert_eq(_idle.state_machine, _machine)
