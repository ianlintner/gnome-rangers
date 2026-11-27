class_name StaminaComponent
extends Node
## Stamina pool with spend, regen delay and a winded state at zero.
##
## Attach as a child of an actor and call [method apply_stats] with its
## [CharacterStats]. Spending actions go through [method try_spend]; continuous
## costs (sprinting) use [method drain]. Regen runs from `_process` via [method tick].

## Emitted whenever the current value changes (spend, drain or regen).
signal changed(current: float, maximum: float)
## Emitted once when the pool reaches zero; the component is then winded.
signal depleted
## Emitted when the winded state ends.
signal recovered

var max_stamina: float = 100.0
var current: float = 100.0
var regen_rate: float = 30.0
var regen_delay: float = 1.0
var winded_duration: float = 1.5

var _delay_left: float = 0.0
var _winded_left: float = 0.0


func _physics_process(delta: float) -> void:
	tick(delta)


## Copies the stamina fields from `stats` and refills the pool.
func apply_stats(stats: CharacterStats) -> void:
	max_stamina = stats.stamina_max
	regen_rate = stats.stamina_regen_rate
	regen_delay = stats.stamina_regen_delay
	winded_duration = stats.winded_duration
	current = max_stamina
	_delay_left = 0.0
	_winded_left = 0.0
	changed.emit(current, max_stamina)


## True while the character is winded (actions are refused).
## Refills to maximum and clears the regen delay and winded state (rest, respawn).
func reset() -> void:
	current = max_stamina
	_delay_left = 0.0
	_winded_left = 0.0
	changed.emit(current, max_stamina)


func is_winded() -> bool:
	return _winded_left > 0.0


## Spends `cost` if the character is not winded and has enough. Returns success.
func try_spend(cost: float) -> bool:
	if is_winded() or current < cost:
		return false
	_remove(cost)
	return true


## Removes up to `amount` for continuous costs. Returns false once the pool is empty.
func drain(amount: float) -> bool:
	if is_winded() or current <= 0.0:
		return false
	_remove(amount)
	return current > 0.0


## Advances the regen delay, winded timer and regeneration by `delta` seconds.
func tick(delta: float) -> void:
	if _winded_left > 0.0:
		_winded_left = maxf(_winded_left - delta, 0.0)
		if _winded_left == 0.0:
			recovered.emit()
			return  # regen resumes on the next tick; the rest of this one is not credited
	if _delay_left > 0.0:
		_delay_left = maxf(_delay_left - delta, 0.0)
		return
	if _winded_left > 0.0 or current >= max_stamina:
		return
	current = minf(current + regen_rate * delta, max_stamina)
	changed.emit(current, max_stamina)


func _remove(amount: float) -> void:
	current = maxf(current - amount, 0.0)
	_delay_left = regen_delay
	changed.emit(current, max_stamina)
	if current <= 0.0:
		_winded_left = winded_duration
		depleted.emit()
