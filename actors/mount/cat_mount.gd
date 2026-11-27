class_name CatMount
extends CharacterBody3D
## The black cat mount: a CharacterBody3D that assembles components and a node state machine.
##
## States (see `states/`): Idle, Called (paths to the rider with a NavigationAgent3D),
## Ridden, Gallop, Pounce, Hurt, Flee. The rider is the [Player]; while mounted the player's
## body is placed on the cat's `saddle` bone every tick and the player's own states drive
## the cat through [method drive]. The cat owns its health and poise, so a hit on the mount
## or on the rider that is above the knock-off thresholds in [MountStats] throws the rider.
##
## Facing convention: the body's forward is -Z. The glTF model faces +Z, so it sits under
## `Model` rotated by PI.

## Emitted after the rider is seated (the end of the mounting animation).
signal rider_mounted(rider: Player)
## Emitted when the rider leaves the saddle; `thrown` is true for a knock-off or flee.
signal rider_dismounted(rider: Player, thrown: bool)
## Emitted when the pounce lands and its strike opens.
signal pounce_landed
## Emitted when the cat runs off at zero health.
signal fled
## Emitted when the cat has recovered and comes back.
signal returned

## Scene-tree group every mount joins (the player finds its cat through it).
const GROUP: StringName = &"mount"
const SADDLE_BONE: StringName = &"saddle"
const PLAYER_GROUP: StringName = &"player"

## Speeds, turning, pounce, knock-off and flee numbers; see `mount_stats.tres`.
@export var stats: MountStats
## Health and poise numbers; see `mount_combat_stats.tres`.
@export var combat_stats: CombatStats
## The node the cat runs to when called. Falls back to the first node in the `player` group.
@export var call_target_path: NodePath

## The seated rider, or null.
var rider: Player = null
## True once the rider has finished climbing on and follows the saddle.
var rider_seated: bool = false
## Camera-relative world direction the rider asks for, length <= 1 (set by the rider's states).
var drive_direction: Vector3 = Vector3.ZERO
## True while the rider sprints.
var drive_gallop: bool = false
## True while the rider aims the bow (slows the cat).
var drive_aiming: bool = false
## Seconds until the next pounce may start.
var pounce_cooldown_left: float = 0.0
## The target of the pounce in progress or just requested.
var pounce_target: Node3D = null
## The node the cat is running to while in the Called state.
var call_target: Node3D = null

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _call_cooldown_left: float = 0.0
var _skeleton: Skeleton3D = null
## Index of [constant SADDLE_BONE] in [member _skeleton]; -1 without a saddle bone.
var _saddle_bone: int = -1

@onready var health: HealthComponent = $Health
@onready var poise: PoiseComponent = $Poise
@onready var hurtbox: HurtboxComponent = $Hurtbox
@onready var hitbox: HitboxComponent = $Hitbox
@onready var melee: AttackRunner = $AttackRunner
@onready var state_machine: StateMachine = $StateMachine
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var interactable: Interactable = $Interactable
@onready var model: Node3D = $Model
@onready var animator: MountAnimator = $MountAnimator


func _ready() -> void:
	if stats == null:
		stats = MountStats.new()
	if combat_stats == null:
		combat_stats = CombatStats.new()
	add_to_group(GROUP)
	# Tick after the children (state machine, AnimationTree) so the rider is seated on this
	# tick's body position and saddle pose, not last tick's.
	process_physics_priority = 10
	health.apply_stats(combat_stats)
	poise.apply_stats(combat_stats)
	health.changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	poise.poise_broken.connect(_on_poise_broken)
	hurtbox.damaged.connect(_check_knock_off)
	interactable.interacted.connect(_on_interacted)
	_setup_saddle()
	animator.setup(model, stats)
	state_machine.state_changed.connect(_on_state_changed)
	state_machine.transition_to(&"Idle")


func _physics_process(delta: float) -> void:
	pounce_cooldown_left = maxf(pounce_cooldown_left - delta, 0.0)
	_call_cooldown_left = maxf(_call_cooldown_left - delta, 0.0)
	interactable.enabled = is_mountable()
	animator.set_speed(get_horizontal_speed())
	_sync_rider()


# --- Calling ------------------------------------------------------------------------------


## Whistle: the cat runs to `target` (default: the player). Returns false while ridden,
## fleeing, busy or on the call cooldown.
func call_to(target: Node3D = null) -> bool:
	if rider != null or _call_cooldown_left > 0.0 or health.is_dead():
		return false
	if not [&"Idle", &"Called"].has(state_machine.current_state_name):
		return false
	call_target = target if target != null else _find_player()
	if call_target == null:
		return false
	_call_cooldown_left = stats.call_cooldown
	return state_machine.transition_to(&"Called") or state_machine.current_state_name == &"Called"


# --- Mounting -----------------------------------------------------------------------------


## True when `actor` could climb on right now (no rider, alive, standing or arrived).
func is_mountable() -> bool:
	return rider == null and not health.is_dead() and state_machine.current_state_name == &"Idle"


## True when `actor` is a player standing within mount range of a mountable cat.
func can_be_mounted_by(actor: Node3D) -> bool:
	if not is_mountable() or actor == null:
		return false
	return actor.global_position.distance_to(global_position) <= stats.mount_range


## Seats `actor` (the player) and puts the cat under its control. The player's Mounting
## state blends it onto the saddle; [method finish_mounting] completes the hand-over.
func attach_rider(actor: Player) -> bool:
	if rider != null or actor == null:
		return false
	rider = actor
	rider_seated = false
	rider.hurtbox.damaged.connect(_check_knock_off)
	rider.health.died.connect(_on_rider_died)
	rider.begin_ride(self)
	state_machine.transition_to(&"Ridden")
	return true


## Called by the player's Mounting state when the climb is done.
func finish_mounting() -> void:
	if rider == null:
		return
	rider_seated = true
	rider_mounted.emit(rider)
	EventBus.mount_mounted.emit()
	EventBus.mount_health_changed.emit(health.current, health.max_health)


## Frees the saddle. `thrown` flings the rider away from `from_direction` (the way the hit
## travelled); otherwise the rider steps down beside the cat.
func detach_rider(thrown: bool, from_direction: Vector3 = Vector3.ZERO) -> void:
	if rider == null:
		return
	var actor: Player = rider
	rider = null
	var was_seated: bool = rider_seated
	rider_seated = false
	_disconnect_rider(actor)
	var seat: Vector3 = seat_transform().origin
	if thrown:
		var away: Vector3 = Vector3(from_direction.x, 0.0, from_direction.z)
		away = away.normalized() if away.length() > 0.001 else global_basis.z
		actor.global_position = seat
		actor.velocity = away * stats.knock_off_speed + Vector3.UP * stats.knock_off_lift
	else:
		actor.global_position = global_position + global_basis * stats.dismount_offset
		actor.velocity = Vector3.ZERO
	actor.end_ride()
	drive_direction = Vector3.ZERO
	drive_gallop = false
	drive_aiming = false
	if [&"Ridden", &"Gallop"].has(state_machine.current_state_name):
		state_machine.transition_to(&"Idle")
	if was_seated:
		EventBus.mount_dismounted.emit()
	rider_dismounted.emit(actor, thrown)


## Where the rider's feet sit: the saddle bone (or a fixed height when the model has none).
func seat_transform() -> Transform3D:
	var basis_yaw := Basis(Vector3.UP, rotation.y)
	var anchor: Vector3 = (
		global_position + basis_yaw * Vector3(0.0, stats.fallback_seat_height, 0.0)
	)
	if _saddle_bone != -1:
		# Read the bone pose directly: it is recomputed on demand, so the seat is exact for this
		# tick whatever the order of deferred skeleton updates and rendered frames.
		anchor = _skeleton.global_transform * _skeleton.get_bone_global_pose(_saddle_bone).origin
	return Transform3D(basis_yaw, anchor + basis_yaw * stats.rider_offset)


## Moves the rider towards the seat; `weight` 1 snaps it there.
func place_rider(weight: float = 1.0) -> void:
	if rider == null:
		return
	var seat: Transform3D = seat_transform()
	rider.global_transform = rider.global_transform.interpolate_with(seat, clampf(weight, 0.0, 1.0))


# --- Driving ------------------------------------------------------------------------------


## The rider's request for this tick: a world direction (length <= 1) and sprint/aim flags.
func drive(direction: Vector3, gallop: bool = false, aiming: bool = false) -> void:
	drive_direction = direction
	drive_gallop = gallop
	drive_aiming = aiming


## Accelerates towards `direction * speed`, turns to face it, applies gravity and slides.
func steer(direction: Vector3, speed: float, turn_rate: float, delta: float) -> void:
	var wanted: Vector3 = direction * speed
	var accel: float = stats.acceleration if wanted.length() > 0.01 else stats.deceleration
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(wanted, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if direction.length_squared() > 0.0001:
		face(direction, turn_rate, delta)
	apply_gravity(delta)
	move_and_slide()


## Applies gravity to the vertical velocity (zero while on the floor).
func apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta


## Turns the body towards `direction` at `rate` rad/s.
func face(direction: Vector3, rate: float, delta: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	rotation.y = rotate_toward(rotation.y, atan2(-direction.x, -direction.z), rate * delta)


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Horizontal direction the cat faces.
func get_facing() -> Vector3:
	return Vector3(-global_basis.z.x, 0.0, -global_basis.z.z).normalized()


# --- Pounce -------------------------------------------------------------------------------


## True when the cat is galloping, off cooldown and `target` is inside the pounce range.
func can_pounce(target: Node3D) -> bool:
	if rider == null or not rider_seated or not is_instance_valid(target):
		return false
	if state_machine.current_state_name != &"Gallop" or pounce_cooldown_left > 0.0:
		return false
	if get_horizontal_speed() < stats.gallop_threshold:
		return false
	var distance: float = _flat_distance_to(target)
	return distance >= stats.pounce_min_range and distance <= stats.pounce_max_range


## Starts a pounce at `target` when allowed. Returns true when the pounce began.
func request_pounce(target: Node3D) -> bool:
	if not can_pounce(target):
		return false
	pounce_target = target
	return state_machine.transition_to(&"Pounce")


## Starts the post-pounce cooldown (called by the Pounce state on landing).
func start_pounce_cooldown() -> void:
	pounce_cooldown_left = stats.pounce_cooldown


## Opens the landing strike: the pounce [AttackData] on the mount's hitbox.
func strike() -> void:
	melee.start(stats.pounce_attack, self)
	pounce_landed.emit()


# --- Hurt, flee, return -------------------------------------------------------------------


## Throws the rider off when they are seated.
func eject_rider(from_direction: Vector3) -> void:
	if rider != null:
		rider.knock_off(from_direction)


## Restores the cat after the flee cooldown and calls it back to the player.
func recover() -> void:
	health.reset()
	poise.reset()
	hurtbox.invulnerable = false
	returned.emit()
	call_target = _find_player()
	_call_cooldown_left = 0.0
	if call_target != null:
		state_machine.transition_to(&"Called")
	else:
		state_machine.transition_to(&"Idle")


func _check_knock_off(info: DamageInfo) -> void:
	if rider == null:
		return
	if info.amount >= stats.knock_off_damage or info.poise_damage >= stats.knock_off_poise_damage:
		rider.knock_off(info.direction)


func _on_interacted(actor: Node) -> void:
	var player := actor as Player
	if player != null and can_be_mounted_by(player):
		attach_rider(player)


func _on_rider_died() -> void:
	detach_rider(true, -global_basis.z)


func _on_health_changed(current: float, maximum: float) -> void:
	EventBus.mount_health_changed.emit(current, maximum)


func _on_died() -> void:
	state_machine.transition_to(&"Flee")


func _on_poise_broken() -> void:
	if not health.is_dead() and not [&"Flee", &"Pounce"].has(state_machine.current_state_name):
		state_machine.transition_to(&"Hurt")


func _on_state_changed(_from_name: StringName, to_name: StringName) -> void:
	animator.play_for_state(to_name)


func _disconnect_rider(actor: Player) -> void:
	if actor.hurtbox.damaged.is_connected(_check_knock_off):
		actor.hurtbox.damaged.disconnect(_check_knock_off)
	if actor.health.died.is_connected(_on_rider_died):
		actor.health.died.disconnect(_on_rider_died)


func _sync_rider() -> void:
	if rider != null and rider_seated:
		place_rider(1.0)


func _setup_saddle() -> void:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or skeleton.find_bone(SADDLE_BONE) == -1:
		push_warning("CatMount: no saddle bone; seating the rider at the fallback height")
		return
	_skeleton = skeleton
	_saddle_bone = skeleton.find_bone(SADDLE_BONE)


func _find_player() -> Node3D:
	var node := get_node_or_null(call_target_path) as Node3D
	if node != null:
		return node
	return get_tree().get_first_node_in_group(PLAYER_GROUP) as Node3D


func _flat_distance_to(target: Node3D) -> float:
	var offset: Vector3 = target.global_position - global_position
	return Vector2(offset.x, offset.z).length()
