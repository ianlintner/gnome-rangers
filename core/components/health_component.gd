class_name HealthComponent
extends Node
## Hit points for an actor: damage, healing, an invulnerable flag and death.
##
## Attach as a child of the actor and call [method apply_stats] with its
## [CombatStats]. A [HurtboxComponent] routes hits here; nothing else should
## remove health. Death is announced once through [signal died] and
## `EventBus.actor_died`.

## Emitted on every change (damage, heal, reset) with the new and maximum value.
signal changed(current: float, maximum: float)
## Emitted when damage was applied. `amount` is what actually left the pool.
signal damaged(amount: float)
## Emitted when health was restored. `amount` is what actually returned.
signal healed(amount: float)
## Emitted once when health reaches zero.
signal died

## While true all damage is ignored (cutscenes, spawn protection, boss transitions).
var invulnerable: bool = false
var max_health: float = 100.0
var current: float = 100.0


## Copies the health fields from `stats` and refills the pool.
func apply_stats(stats: CombatStats) -> void:
	max_health = stats.max_health
	reset()


## Refills to maximum. Does not re-announce an earlier death.
func reset() -> void:
	current = max_health
	changed.emit(current, max_health)


func is_dead() -> bool:
	return current <= 0.0


## Removes up to `amount`. Returns the health actually removed (0 when ignored).
func take_damage(amount: float) -> float:
	if invulnerable or is_dead() or amount <= 0.0:
		return 0.0
	var removed: float = minf(amount, current)
	current -= removed
	damaged.emit(removed)
	changed.emit(current, max_health)
	if current <= 0.0:
		died.emit()
		EventBus.actor_died.emit(get_parent())
	return removed


## Restores up to `amount` without exceeding maximum. Dead actors cannot be healed.
func heal(amount: float) -> float:
	if is_dead() or amount <= 0.0:
		return 0.0
	var restored: float = minf(amount, max_health - current)
	if restored <= 0.0:
		return 0.0
	current += restored
	healed.emit(restored)
	changed.emit(current, max_health)
	return restored
