class_name HitStop
extends RefCounted
## Hit-stop: the project's single standard approach is a brief global time-scale dip.
##
## When a hit lands, [method request] sets `Engine.time_scale` to a low value and restores
## [member base_time_scale] (normally 1.0) after `duration` real seconds. The restore timer
## ignores the time scale, so the dip lasts the stated real time. Overlapping requests extend
## the dip; the last request wins the scale. Per-actor freezes are deliberately not used: one
## mechanism keeps every system (animation, physics, timers) in sync.

## The time scale outside a dip. Always 1.0 in the game; the headless bot-fight tests raise it
## to fast-forward a fight (`tests/helpers/bot_clock.gd`), and the dip then scales with it.
static var base_time_scale: float = 1.0
## When false, [method request] does nothing. The dip slows every system uniformly, so it only
## changes real time, never the outcome in game time; the fast-forwarded bot fights switch it
## off because a scale change lands on a wall-clock-dependent physics tick (the engine reads
## `Engine.time_scale` once per main-loop iteration, and an iteration runs many ticks).
static var enabled: bool = true
## Incremented on every request so only the newest timer restores the scale.
static var _generation: int = 0


## Dips the time scale to `time_scale` for `duration` real seconds. Ignored for a
## non-positive duration, a missing tree or while [member enabled] is false.
static func request(tree: SceneTree, duration: float, time_scale: float) -> void:
	if tree == null or duration <= 0.0 or not enabled:
		return
	_generation += 1
	var mine: int = _generation
	Engine.time_scale = base_time_scale * clampf(time_scale, 0.01, 1.0)
	# process_always = true, process_in_physics = false, ignore_time_scale = true. A raised base
	# shortens the real-time wait so the dip covers the same span of game time.
	var real_duration: float = duration / maxf(base_time_scale, 0.01)
	tree.create_timer(real_duration, true, false, true).timeout.connect(
		func() -> void:
			if _generation == mine:
				Engine.time_scale = base_time_scale
	)


## Restores the base time scale immediately and invalidates pending restores.
static func cancel() -> void:
	_generation += 1
	Engine.time_scale = base_time_scale
