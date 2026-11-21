class_name BossBase
extends CharacterBody3D
## Reusable boss actor: composes health, poise, hurtboxes, an AttackRunner, a
## StateMachine, a BossBrain and a phase controller. Subclasses (or scenes) only
## supply data. Movement, targets and VFX hooks are the shared implementation.

signal windup_started(move: BossMoveData)
signal roar_started

@export var stats: CombatStats = null
@export var base_moves: Array[BossMoveData] = []
@export var phases: Array[BossPhaseData] = []
@export_range(0.0, 20.0, 0.1) var walk_speed: float = 2.6
@export_range(0.0, 20.0, 0.1) var strafe_speed: float = 1.8
@export_range(0.0, 20.0, 0.1) var approach_stop_distance: float = 2.6
@export_range(0.0, 30.0, 0.1) var gravity: float = 12.0
## Node the boss hunts; assigned by the arena gate on engagement.
var target: Node3D = null
var engaged: bool = false
var current_move: BossMoveData = null
var speed_multiplier: float = 1.0
## Latched on death so a later player death cannot resurrect a defeated boss.
var defeated: bool = false

var _shockwave_timer: SceneTreeTimer = null

@onready var health: HealthComponent = $Health
@onready var poise: PoiseComponent = $Poise
@onready var hitbox: HitboxComponent = $Hitbox
@onready var shockwave: HitboxComponent = get_node_or_null("ShockwaveHitbox") as HitboxComponent
@onready var runner: AttackRunner = $AttackRunner
@onready var brain: BossBrain = $BossBrain
@onready var phase_controller: BossPhaseController = $PhaseController
@onready var state_machine: StateMachine = $StateMachine
@onready var model: Node3D = $Model
@onready var animation_player: AnimationPlayer = $Model/AnimationPlayer


func _ready() -> void:
	if stats != null:
		health.apply_stats(stats)
	brain.moves = base_moves
	brain.active_moves = base_moves.duplicate()
	phase_controller.phases = phases
	phase_controller.phase_entered.connect(_on_phase_entered)
	runner.finished.connect(_on_attack_finished)
	runner.phase_changed.connect(_on_runner_phase_changed)
	hitbox.hit_landed.connect(_on_hit_landed)
	poise.poise_broken.connect(_on_staggered_changed)
	health.died.connect(_on_died)
	EventBus.player_died.connect(reset_boss)
	if not GameState.run_reset.is_connected(reset_boss):
		GameState.run_reset.connect(reset_boss)
	state_machine.transition_to(&"Idle")


func _physics_process(delta: float) -> void:
	brain.tick(delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func engage(new_target: Node3D) -> void:
	if engaged:
		return
	engaged = true
	target = new_target


func distance_to_target() -> float:
	if target == null:
		return 999.0
	var delta: Vector3 = target.global_position - global_position
	delta.y = 0.0
	return delta.length()


func face_target(delta: float) -> void:
	brain.turn_toward(self, target, delta)


func choose_move() -> BossMoveData:
	current_move = brain.pick_move(distance_to_target())
	return current_move


func start_move(move: BossMoveData) -> bool:
	if move == null or move.attack == null:
		return false
	current_move = move
	var ok: bool = runner.start(move.attack, self)
	if ok:
		windup_started.emit(move)
		var animation: StringName = move.windup_animation
		if animation == &"" and move.attack != null:
			animation = move.attack.animation_name
		_play_animation(animation)
		_spawn_windup_vfx(move)
	return ok


func _play_animation(clip: StringName) -> void:
	if animation_player != null and clip != &"" and animation_player.has_animation(clip):
		animation_player.play(clip)


func _spawn_windup_vfx(move: BossMoveData) -> void:
	if move.windup_vfx_path.is_empty():
		return
	var packed := load(move.windup_vfx_path) as PackedScene
	if packed == null:
		return
	var vfx: Node = packed.instantiate()
	add_child(vfx)
	if vfx is Node3D:
		(vfx as Node3D).position = Vector3(0, 0.1, -1.0)


## Fires the move's follow-up (shockwave ring) from the feet when the main window opens.
func _on_runner_phase_changed(phase: AttackRunner.Phase) -> void:
	if phase != AttackRunner.Phase.ACTIVE or current_move == null:
		return
	var followup: AttackData = current_move.followup_attack
	if followup == null or shockwave == null:
		return
	_close_shockwave()  # A previous slam's stray timer must never close this ring early.
	shockwave.configure(followup, self)
	shockwave.set_active(true)
	_shockwave_timer = get_tree().create_timer(followup.active)
	_shockwave_timer.timeout.connect(_on_shockwave_timeout)


## Timer callback: the timer has already fired, so just clear the reference.
func _on_shockwave_timeout() -> void:
	_shockwave_timer = null
	if shockwave != null:
		shockwave.set_active(false)


func _close_shockwave() -> void:
	if _shockwave_timer != null and not _shockwave_timer.is_stopped():
		_shockwave_timer.timeout.disconnect(_on_shockwave_timeout)
		_shockwave_timer = null
	if shockwave != null:
		shockwave.set_active(false)


## Grab-and-throw: a caught target is launched away from the boss.
func _on_hit_landed(hurtbox: HurtboxComponent, _info: DamageInfo) -> void:
	if current_move == null or current_move.throw_speed <= 0.0:
		return
	var victim := hurtbox.actor as CharacterBody3D
	if victim == null:
		return
	var away: Vector3 = victim.global_position - global_position
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.0001 else -global_basis.z
	victim.velocity = away * current_move.throw_speed + Vector3.UP * current_move.throw_lift


func _on_attack_finished(_attack: AttackData) -> void:
	current_move = null
	if state_machine.current_state_name == &"Attack":
		state_machine.transition_to(&"Approach")


func _on_staggered_changed() -> void:
	if not poise.staggered or health.is_dead() or health.invulnerable:
		return
	runner.cancel()
	current_move = null
	_close_shockwave()
	state_machine.transition_to(&"Staggered")


func _on_phase_entered(phase: int, data: BossPhaseData) -> void:
	brain.configure_phase(data, phase)
	speed_multiplier = data.speed_multiplier
	EventBus.boss_phase_changed.emit(self, phase)
	if data.on_enter_action == &"roar":
		# The roar is invulnerable and must not leave an attack hitbox live.
		runner.cancel()
		current_move = null
		_close_shockwave()
		roar_started.emit()
		var transition := (
			state_machine.get_node_or_null("PhaseTransition") as BossPhaseTransitionState
		)
		if transition != null:
			transition.begin(data.on_enter_duration)
		state_machine.transition_to(&"PhaseTransition")
	elif state_machine.current_state_name != &"Attack":
		state_machine.transition_to(&"Approach")


func finish_phase_transition() -> void:
	state_machine.transition_to(&"Approach")


func _on_died() -> void:
	if defeated:
		return
	defeated = true
	runner.cancel()
	_close_shockwave()
	GameState.mark_won()
	EventBus.boss_defeated.emit(self)
	state_machine.transition_to(&"Dead")


func reset_boss() -> void:
	# A beaten boss stays beaten; only a fresh run (GameState.reset_run) revives it.
	if defeated and GameState.is_won():
		return
	defeated = false
	engaged = false
	target = null
	current_move = null
	speed_multiplier = 1.0
	health.invulnerable = false
	health.reset()
	poise.reset()
	brain.reset()
	phase_controller.reset()
	runner.cancel()
	_close_shockwave()
	state_machine.transition_to(&"Idle")
