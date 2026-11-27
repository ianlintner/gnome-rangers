class_name HitboxComponent
extends Area3D
## Deals damage. Enabled only during an attack's active frames, carries the
## [AttackData] and the attacking actor, and hits each target actor at most once per
## swing (one open window).
##
## The [AttackRunner] opens and closes it. While active it polls the overlapping
## hurtboxes every physics tick, which stays deterministic when the window opens on a
## target that is already inside. Projectiles call [method apply_to] directly with the
## contact point from their swept ray, so every hit in the game goes through here.

## Emitted when a hit landed (not when it was ignored by i-frames).
signal hit_landed(hurtbox: HurtboxComponent, info: DamageInfo)

## Side of the attacker; hurtboxes of the same faction are skipped.
@export var faction: StringName = &"player"
## Category stamped on every hit from this hitbox (`melee`, `arrow`, `heavy`, ...).
@export var damage_type: StringName = &"melee"

var attack: AttackData = null
var attacker: Node = null
var charge_ratio: float = 0.0
var active: bool = false

var _hit_actors: Array[Node] = []
var _shape_node: CollisionShape3D = null


func _init() -> void:
	collision_layer = 0
	collision_mask = 1 << 6  # `hurtbox`
	monitoring = false
	monitorable = false


func _ready() -> void:
	# Layers `player_hitbox` (5) and `enemy_hitbox` (6).
	collision_layer = (1 << 4) if faction == &"player" else (1 << 5)


func _physics_process(_delta: float) -> void:
	if not active:
		return
	var best: Dictionary = {}
	# The physics server reports overlaps in no fixed order; apply hits in scene-path order so a
	# swing that catches several actors at once (a cat and its rider) resolves the same each run.
	var areas: Array[Area3D] = get_overlapping_areas()
	areas.sort_custom(_by_path)
	for area: Area3D in areas:
		var hurtbox := area as HurtboxComponent
		if hurtbox == null or hurtbox.faction == faction or hurtbox.actor == attacker:
			continue
		if _hit_actors.has(hurtbox.actor):
			continue
		var current: HurtboxComponent = best.get(hurtbox.actor) as HurtboxComponent
		if current == null or hurtbox.damage_multiplier > current.damage_multiplier:
			best[hurtbox.actor] = hurtbox
	for hurtbox: HurtboxComponent in best.values():
		apply_to(hurtbox, hurtbox.global_position)


static func _by_path(a: Node, b: Node) -> bool:
	return String(a.get_path()) < String(b.get_path())


## Binds the attack and attacker. With `build_shape` the Area3D volume is rebuilt from
## the attack's hitbox data; projectiles pass false and use [method apply_to] only.
func configure(
	data: AttackData, hit_source: Node, charge: float = 0.0, build_shape: bool = true
) -> void:
	attack = data
	attacker = hit_source
	charge_ratio = charge
	if build_shape:
		_build_shape(data)


## Opens or closes the hit window. Opening starts a new swing: every target may be hit again.
func set_active(value: bool) -> void:
	active = value
	monitoring = value
	if value:
		clear_hits()


## Forgets who was hit, so every target may be hit again. Pooled projectiles call this on
## every launch; opening a hit window does it implicitly.
func clear_hits() -> void:
	_hit_actors.clear()


## Applies the bound attack to `hurtbox` unless its actor was already hit this swing.
## Returns true when the hit landed.
func apply_to(hurtbox: HurtboxComponent, hit_position: Vector3) -> bool:
	if attack == null or _hit_actors.has(hurtbox.actor):
		return false
	var info: DamageInfo = DamageInfo.from_attack(attack, attacker, faction, charge_ratio)
	info.damage_type = damage_type
	info.hit_position = hit_position
	info.direction = _direction_to(hit_position)
	if not hurtbox.receive_damage(info):
		return false
	_hit_actors.append(hurtbox.actor)
	hit_landed.emit(hurtbox, info)
	HitStop.request(get_tree(), info.hit_stop_duration, info.hit_stop_time_scale)
	return true


func _direction_to(point: Vector3) -> Vector3:
	var origin: Vector3 = global_position
	if attacker is Node3D:
		origin = (attacker as Node3D).global_position
	var direction: Vector3 = point - origin
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.0001 else -global_basis.z


func _build_shape(data: AttackData) -> void:
	if _shape_node == null:
		_shape_node = CollisionShape3D.new()
		add_child(_shape_node)
	match data.hit_shape:
		AttackData.HitShape.SPHERE:
			var sphere := SphereShape3D.new()
			sphere.radius = data.hit_size.x
			_shape_node.shape = sphere
		AttackData.HitShape.CAPSULE:
			var capsule := CapsuleShape3D.new()
			capsule.radius = data.hit_size.x
			capsule.height = maxf(data.hit_size.y, data.hit_size.x * 2.0)
			_shape_node.shape = capsule
		_:
			var box := BoxShape3D.new()
			box.size = data.hit_size
			_shape_node.shape = box
	_shape_node.position = data.hit_offset
