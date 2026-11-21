class_name AttackRunner
extends Node
## Plays one [AttackData] at a time and opens its hit window.
##
## Hit windows are animation-driven: the attack's clip carries call-method tracks that
## invoke [method open_hit_window] and [method close_hit_window] on this node, so the
## window follows the animation. When the clip has no such tracks (placeholder clips)
## the runner falls back to the AttackData `windup` / `active` / `recovery` timings.
## Either way the attack ends after `total_duration()`, so state code has one clock.
##
## Stamina is paid in [method start]; a refused spend means the attack never begins.
## The runner never plays AnimationTree states itself: it emits
## [signal animation_requested] and the actor routes it ("signal up").

## Emitted when the attack starts; the actor should play `animation_name`.
signal animation_requested(animation_name: StringName)
signal phase_changed(phase: Phase)
## Emitted when the attack ran to the end of its recovery.
signal finished(attack: AttackData)
## Emitted when [method cancel] interrupted a running attack.
signal cancelled(attack: AttackData)

enum Phase { IDLE, WINDUP, ACTIVE, RECOVERY }

@export var hitbox_path: NodePath = ^"../Hitbox"
## AnimationPlayer holding the attack clips, used to detect hit-window method tracks.
@export var animation_player_path: NodePath
## When true the runner calls `play` on the AnimationPlayer itself (no AnimationTree).
@export var play_animation_directly: bool = false

var current: AttackData = null
var phase: Phase = Phase.IDLE
## Seconds since the current attack started.
var elapsed: float = 0.0
var charge_ratio: float = 0.0

var _hitbox: HitboxComponent = null
var _animation_player: AnimationPlayer = null
var _clip_drives_window: bool = false


func _ready() -> void:
	_hitbox = get_node_or_null(hitbox_path) as HitboxComponent
	_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer


func _physics_process(delta: float) -> void:
	tick(delta)


## True when `stamina` (optional) could pay for `attack` right now.
func can_start(attack: AttackData, stamina: StaminaComponent = null) -> bool:
	if attack == null:
		return false
	return stamina == null or (not stamina.is_winded() and stamina.current >= attack.stamina_cost)


## Starts `attack` for `attacker`, paying its stamina cost. Returns false (and does
## nothing) when the cost cannot be paid. A running attack is replaced.
func start(
	attack: AttackData, attacker: Node, stamina: StaminaComponent = null, charge: float = 0.0
) -> bool:
	if not can_start(attack, stamina):
		return false
	if stamina != null and not stamina.try_spend(attack.stamina_cost):
		return false
	if phase != Phase.IDLE:
		cancel()
	current = attack
	elapsed = 0.0
	charge_ratio = clampf(charge, 0.0, 1.0)
	if _hitbox != null:
		_hitbox.configure(attack, attacker, charge_ratio)
	_clip_drives_window = _clip_has_window(attack.animation_name)
	_set_phase(Phase.WINDUP)
	animation_requested.emit(attack.animation_name)
	if play_animation_directly and _has_clip(attack.animation_name):
		_animation_player.play(attack.animation_name)
	return true


## Advances the attack by `delta` seconds. Called from `_physics_process`.
func tick(delta: float) -> void:
	if phase == Phase.IDLE:
		return
	elapsed += delta
	if not _clip_drives_window:
		if phase == Phase.WINDUP and elapsed >= current.windup:
			open_hit_window()
		if phase == Phase.ACTIVE and elapsed >= current.windup + current.active:
			close_hit_window()
	if elapsed >= current.total_duration():
		_finish()


## Opens the hitbox. Called by the animation's method track (or by [method tick]).
func open_hit_window() -> void:
	if phase != Phase.WINDUP:
		return
	if _hitbox != null:
		_hitbox.set_active(true)
	_set_phase(Phase.ACTIVE)


## Closes the hitbox and enters recovery.
func close_hit_window() -> void:
	if phase != Phase.ACTIVE:
		return
	if _hitbox != null:
		_hitbox.set_active(false)
	_set_phase(Phase.RECOVERY)


## Aborts the running attack (dodge cancel, stagger) and closes the hitbox.
func cancel() -> void:
	if phase == Phase.IDLE:
		return
	var attack: AttackData = current
	_end()
	cancelled.emit(attack)


func is_busy() -> bool:
	return phase != Phase.IDLE


func _finish() -> void:
	var attack: AttackData = current
	_end()
	finished.emit(attack)


func _end() -> void:
	if _hitbox != null:
		_hitbox.set_active(false)
	current = null
	_set_phase(Phase.IDLE)


func _set_phase(value: Phase) -> void:
	phase = value
	phase_changed.emit(value)


func _has_clip(clip_name: StringName) -> bool:
	return _animation_player != null and _animation_player.has_animation(clip_name)


func _clip_has_window(clip_name: StringName) -> bool:
	if not _has_clip(clip_name):
		return false
	var clip: Animation = _animation_player.get_animation(clip_name)
	var root: Node = _animation_player.get_node_or_null(_animation_player.root_node)
	var found: Dictionary = {}
	for track: int in clip.get_track_count():
		if clip.track_get_type(track) != Animation.TYPE_METHOD or not clip.track_is_enabled(track):
			continue
		if root == null or root.get_node_or_null(clip.track_get_path(track)) != self:
			continue
		for key: int in clip.track_get_key_count(track):
			found[clip.method_track_get_name(track, key)] = true
	return found.has(&"open_hit_window") and found.has(&"close_hit_window")
