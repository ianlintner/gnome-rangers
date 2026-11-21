class_name AttackHeavyState
extends PlayerState
## Heavy attack: hold `attack_heavy` to charge, release to swing.
##
## Charge time (up to `AttackData.charge_time_max`) scales the swing's damage and
## poise damage. Stamina is paid at release; a refused spend returns to idle. Dodge
## cancels the charge for free, and the swing itself from `dodge_cancel_start`.

var _charge: float = 0.0
var _swinging: bool = false


func enter(_previous_state_name: StringName = &"") -> void:
	_charge = 0.0
	_swinging = false


func exit() -> void:
	player.melee.cancel()


func physics_update(delta: float) -> void:
	player.locomote(Vector3.ZERO, player.stats.deceleration, delta)
	player.update_facing(Vector3.ZERO, delta)
	var heavy: AttackData = player.moveset.heavy
	if _swinging:
		if not player.melee.is_busy():
			state_machine.transition_to(&"Idle")
		elif player.melee.elapsed >= heavy.dodge_cancel_start:
			try_dodge()
		return
	if try_dodge():
		return
	if Input.is_action_pressed(&"attack_heavy"):
		_charge = minf(_charge + delta, heavy.charge_time_max)
		return
	var ratio: float = _charge / heavy.charge_time_max if heavy.charge_time_max > 0.0 else 0.0
	if player.melee.start(heavy, player, player.stamina, ratio):
		_swinging = true
	else:
		state_machine.transition_to(&"Idle")
