class_name ArrowPool
extends Node
## Owns a bow's arrows: hands out idle ones, takes them back when they expire and
## caps how many may be stuck in targets at once (the oldest is recycled first).
##
## Idle arrows are hidden children of the pool. Flying and stuck arrows live in the
## world (stuck ones as children of what they hit); freed targets take their arrows
## with them, so the pool prunes dead references before counting.

const ARROW_SCENE: PackedScene = preload("res://actors/projectiles/arrow.tscn")

var _data: BowData = null
var _idle: Array = []
var _stuck: Array = []


## Prepares the pool from `data` and creates `pool_size` idle arrows.
func setup(data: BowData) -> void:
	_data = data
	for _i: int in data.pool_size:
		_idle.append(_create())


## Returns an idle arrow, creating one when the pool ran dry.
func acquire() -> Arrow:
	_prune(_idle)
	if _idle.is_empty():
		return _create()
	return _idle.pop_back() as Arrow


## Takes `arrow` back: it becomes a hidden idle child of the pool again.
func release(arrow: Arrow) -> void:
	_stuck.erase(arrow)
	arrow.deactivate()
	if arrow.get_parent() != self:
		arrow.reparent(self, false)
	if not _idle.has(arrow):
		_idle.append(arrow)


## Number of arrows currently embedded in targets or the world.
func stuck_count() -> int:
	_prune(_stuck)
	return _stuck.size()


## Number of arrows waiting in the pool.
func idle_count() -> int:
	_prune(_idle)
	return _idle.size()


func _create() -> Arrow:
	var arrow := ARROW_SCENE.instantiate() as Arrow
	add_child(arrow)
	arrow.deactivate()
	arrow.stuck.connect(_on_arrow_stuck)
	arrow.expired.connect(release)
	return arrow


func _on_arrow_stuck(arrow: Arrow, _target: Node) -> void:
	_stuck.append(arrow)
	_prune(_stuck)
	while _stuck.size() > _data.max_stuck_arrows:
		release(_stuck[0] as Arrow)


func _prune(list: Array) -> void:
	for index: int in range(list.size() - 1, -1, -1):
		if not is_instance_valid(list[index]):
			list.remove_at(index)
