class_name BossBrain
extends Node
## Reusable boss decision layer. Picks a move by weighted random choice among the
## moves eligible for the current distance band, respecting per-move cooldowns.
## Also owns the limited turn rate so flanking and circling work: a boss rotates
## towards its target instead of snapping to face it.

signal move_selected(move: BossMoveData)

@export var moves: Array[BossMoveData] = []
## Degrees per second the boss can turn toward its target.
@export_range(0.0, 1080.0, 1.0) var turn_rate_degrees: float = 180.0
## Radius inside which the target counts as "close" for band bookkeeping.
@export_range(0.0, 100.0, 0.1) var close_band: float = 3.0
@export_range(0.0, 100.0, 0.1) var mid_band: float = 9.0

var rng := RandomNumberGenerator.new()
var phase: int = 1
var recovery_multiplier: float = 1.0
var active_moves: Array[BossMoveData] = []
var _cooldowns: Dictionary = {}


func _ready() -> void:
	active_moves = moves.duplicate()
	reset()


func set_seed(seed_value: int) -> void:
	rng.seed = seed_value


func reset() -> void:
	_cooldowns.clear()
	phase = 1
	recovery_multiplier = 1.0
	active_moves = moves.duplicate()


func configure_phase(data: BossPhaseData, next_phase: int) -> void:
	phase = next_phase
	recovery_multiplier = data.recovery_multiplier
	active_moves = data.effective_moves(moves)


func band_for_distance(distance: float) -> StringName:
	if distance <= close_band:
		return &"close"
	if distance <= mid_band:
		return &"mid"
	return &"far"


## Eligible moves in the current band whose cooldown has expired.
func available_moves(distance: float) -> Array[BossMoveData]:
	var result: Array[BossMoveData] = []
	for move: BossMoveData in active_moves:
		if move == null or not move.is_eligible(distance, phase):
			continue
		if (_cooldowns.get(move.id, 0.0) as float) > 0.0:
			continue
		result.append(move)
	return result


## Picks one move, or null when nothing is ready. Deterministic for a given RNG seed.
func pick_move(distance: float) -> BossMoveData:
	var candidates := available_moves(distance)
	if candidates.is_empty():
		return null
	var total: float = 0.0
	for move: BossMoveData in candidates:
		total += move.weight
	if total <= 0.0:
		return null
	var roll: float = rng.randf_range(0.0, total)
	for move: BossMoveData in candidates:
		roll -= move.weight
		if roll <= 0.0:
			start_cooldown(move)
			move_selected.emit(move)
			return move
	var last: BossMoveData = candidates[candidates.size() - 1]
	start_cooldown(last)
	move_selected.emit(last)
	return last


func start_cooldown(move: BossMoveData) -> void:
	_cooldowns[move.id] = move.cooldown * recovery_multiplier


func cooldown_left(move_id: StringName) -> float:
	return _cooldowns.get(move_id, 0.0) as float


func tick(delta: float) -> void:
	for id: StringName in _cooldowns.keys():
		var left: float = (_cooldowns[id] as float) - delta
		if left <= 0.0:
			_cooldowns.erase(id)
		else:
			_cooldowns[id] = left


## Rotates `body` towards `target` by at most the configured turn rate. Returns the
## signed angle still remaining, in radians.
func turn_toward(body: Node3D, target: Node3D, delta: float) -> float:
	if body == null or target == null:
		return 0.0
	var flat_from: Vector3 = -body.global_transform.basis.z
	var to_target: Vector3 = target.global_position - body.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return 0.0
	to_target = to_target.normalized()
	var remaining: float = flat_from.signed_angle_to(to_target, Vector3.UP)
	var max_step: float = deg_to_rad(turn_rate_degrees) * delta
	var step: float = clampf(remaining, -max_step, max_step)
	if absf(step) > 0.00001:
		body.rotate_y(step)
	return remaining - step
