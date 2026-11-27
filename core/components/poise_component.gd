class_name PoiseComponent
extends Node
## Poise: accumulating poise damage that staggers the actor when it fills.
##
## Hits add poise damage. After a delay without hits poise recovers. When the
## accumulated value reaches the maximum, poise breaks: the actor is staggered for
## `stagger_duration` and a riposte window opens (bonus damage, applied by the
## [HurtboxComponent]). Poise resets to empty on the break.

## Emitted when poise breaks; the actor should enter its stagger state.
signal poise_broken
## Emitted when the stagger ends.
signal stagger_ended
## Emitted when the riposte window opens or closes.
signal riposte_changed(is_open: bool)
## Emitted whenever accumulated poise damage changes.
signal changed(current: float, maximum: float)

var max_poise: float = 50.0
## Accumulated poise damage; 0 is a fresh bar, `max_poise` breaks.
var current: float = 0.0
var regen_delay: float = 2.0
var regen_rate: float = 20.0
var stagger_duration: float = 1.0
var riposte_duration: float = 1.5
var riposte_multiplier: float = 1.5
## True while the actor is staggered.
var staggered: bool = false
## True while a hit counts as a riposte.
var riposte_open: bool = false

var _delay_left: float = 0.0
var _stagger_left: float = 0.0
var _riposte_left: float = 0.0


func _physics_process(delta: float) -> void:
	tick(delta)


## Copies the poise fields from `stats` and empties the bar.
func apply_stats(stats: CombatStats) -> void:
	max_poise = stats.poise_max
	regen_delay = stats.poise_regen_delay
	regen_rate = stats.poise_regen_rate
	stagger_duration = stats.stagger_duration
	riposte_duration = stats.riposte_duration
	riposte_multiplier = stats.riposte_damage_multiplier
	current = 0.0
	changed.emit(current, max_poise)


## Clears accumulated poise, stagger and riposte. Used by full actor resets.
func reset() -> void:
	current = 0.0
	_delay_left = 0.0
	_stagger_left = 0.0
	_riposte_left = 0.0
	staggered = false
	_set_riposte(false)
	changed.emit(current, max_poise)


## Adds poise damage. Returns true when this hit broke poise.
## Hits while already staggered do not stack a second break.
func take_poise_damage(amount: float) -> bool:
	if amount <= 0.0 or staggered:
		return false
	_delay_left = regen_delay
	current = minf(current + amount, max_poise)
	changed.emit(current, max_poise)
	if current < max_poise:
		return false
	_break()
	return true


## Advances recovery, the stagger timer and the riposte window by `delta` seconds.
func tick(delta: float) -> void:
	if staggered:
		_stagger_left = maxf(_stagger_left - delta, 0.0)
		if _stagger_left == 0.0:
			staggered = false
			stagger_ended.emit()
	if riposte_open:
		_riposte_left = maxf(_riposte_left - delta, 0.0)
		if _riposte_left == 0.0:
			_set_riposte(false)
	if staggered or current <= 0.0:
		return
	if _delay_left > 0.0:
		_delay_left = maxf(_delay_left - delta, 0.0)
		return
	current = maxf(current - regen_rate * delta, 0.0)
	changed.emit(current, max_poise)


func _break() -> void:
	current = 0.0
	staggered = true
	_stagger_left = stagger_duration
	_riposte_left = riposte_duration
	_set_riposte(true)
	changed.emit(current, max_poise)
	poise_broken.emit()
	EventBus.poise_broken.emit(get_parent())
	EventBus.actor_staggered.emit(get_parent())


func _set_riposte(is_open: bool) -> void:
	if riposte_open == is_open:
		return
	riposte_open = is_open
	riposte_changed.emit(is_open)
