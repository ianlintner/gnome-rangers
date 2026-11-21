class_name HitStop
extends RefCounted
## Hit-stop: the project's single standard approach is a brief global time-scale dip.
##
## When a hit lands, [method request] sets `Engine.time_scale` to a low value and
## restores 1.0 after `duration` real seconds. The restore timer ignores the time
## scale, so the dip lasts the stated real time. Overlapping requests extend the dip;
## the last request wins the scale. Per-actor freezes are deliberately not used: one
## mechanism keeps every system (animation, physics, timers) in sync.

## Incremented on every request so only the newest timer restores the scale.
static var _generation: int = 0


## Dips the time scale to `time_scale` for `duration` real seconds. Ignored for a
## non-positive duration or a missing tree.
static func request(tree: SceneTree, duration: float, time_scale: float) -> void:
	if tree == null or duration <= 0.0:
		return
	_generation += 1
	var mine: int = _generation
	Engine.time_scale = clampf(time_scale, 0.01, 1.0)
	# process_always = true, process_in_physics = false, ignore_time_scale = true.
	tree.create_timer(duration, true, false, true).timeout.connect(
		func() -> void:
			if _generation == mine:
				Engine.time_scale = 1.0
	)


## Restores normal time immediately and invalidates pending restores.
static func cancel() -> void:
	_generation += 1
	Engine.time_scale = 1.0
