class_name BotClock
extends RefCounted
## Fast-forwards the engine for the headless bot-fight tests, and puts it back afterwards.
##
## `Engine.time_scale` alone would make every physics step `factor` times longer (Godot scales
## the step delta, not the step count), which lets hitboxes and arrows skip through targets.
## So the physics tick rate is raised by the same factor: each step still advances 1/60 s of
## game time, there are just `factor` times more of them per real second. Headless, the
## project is mostly idle waiting for real time, so a factor of 16 runs a ~2 minute fight in
## well under 30 s of wall-clock.
##
## Determinism: [HitStop] dips are switched off while fast-forwarding. They only stretch real
## time, but the engine reads `Engine.time_scale` once per main-loop iteration (here up to
## `factor` physics ticks), so a dip would start and end on a wall-clock-dependent tick.
## Every other gameplay timer (stamina, poise, camera, cat pose) runs in the physics tick, so a
## fast-forwarded fight is a pure function of its seeds.

## Default fast-forward factor for the bot fights.
const DEFAULT_FACTOR: float = 16.0

static var _saved_time_scale: float = 1.0
static var _saved_ticks: int = 60
static var _saved_max_steps: int = 8
static var _active: bool = false


## Runs the engine `factor` times faster than real time with unchanged 60 Hz game-time steps.
static func fast_forward(factor: float = DEFAULT_FACTOR) -> void:
	if not _active:
		_saved_time_scale = Engine.time_scale
		_saved_ticks = Engine.physics_ticks_per_second
		_saved_max_steps = Engine.max_physics_steps_per_frame
		_active = true
	Engine.physics_ticks_per_second = roundi(_saved_ticks * factor)
	Engine.max_physics_steps_per_frame = roundi(_saved_max_steps * factor)
	HitStop.base_time_scale = factor
	HitStop.enabled = false
	Engine.time_scale = factor


## Restores the settings saved by [method fast_forward]. Safe to call when not active.
static func restore() -> void:
	HitStop.base_time_scale = 1.0
	HitStop.enabled = true
	HitStop.cancel()
	if not _active:
		return
	Engine.time_scale = _saved_time_scale
	Engine.physics_ticks_per_second = _saved_ticks
	Engine.max_physics_steps_per_frame = _saved_max_steps
	_active = false
