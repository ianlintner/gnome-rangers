class_name AttackLightState
extends PlayerState
## Light attack chain: each press inside the chain window advances to the next link.
##
## The first link is started by [method PlayerState.try_attack_light]. Presses are
## buffered (`MeleeMoveset.input_buffer_time`) so a slightly early press still chains
## once the window opens. A dodge press cancels the attack once `dodge_cancel_start`
## has passed. Leaving the state, for any reason, cancels the running attack.

var _index: int = 0
var _buffer_left: float = 0.0


func enter(_previous_state_name: StringName = &"") -> void:
	_index = 0
	_buffer_left = 0.0


func exit() -> void:
	player.melee.cancel()


func physics_update(delta: float) -> void:
	player.locomote(Vector3.ZERO, player.stats.deceleration, delta)
	player.update_facing(Vector3.ZERO, delta)
	var runner: AttackRunner = player.melee
	if runner.current == null:
		state_machine.transition_to(&"Idle")
		return
	if Input.is_action_just_pressed(&"attack_light"):
		_buffer_left = player.moveset.input_buffer_time
	else:
		_buffer_left = maxf(_buffer_left - delta, 0.0)
	if runner.elapsed >= runner.current.dodge_cancel_start and try_dodge():
		return
	_try_chain(runner)


func _try_chain(runner: AttackRunner) -> void:
	var chain: Array[AttackData] = player.moveset.light_chain
	if _buffer_left <= 0.0 or _index + 1 >= chain.size():
		return
	if runner.elapsed < runner.current.chain_window_start:
		return
	if runner.start(chain[_index + 1], player, player.stamina):
		_index += 1
		_buffer_left = 0.0
