extends GutTest
## AttackRunner timing fallback, stamina refusal and one-hit-per-swing hitboxes.

var _actor: Node3D
var _hitbox: HitboxComponent
var _runner: AttackRunner
var _stamina: StaminaComponent
var _attack: AttackData
var _target: Node3D
var _target_health: HealthComponent
var _target_hurtbox: HurtboxComponent


func before_each() -> void:
	_attack = AttackData.new()
	_attack.damage = 10.0
	_attack.poise_damage = 5.0
	_attack.stamina_cost = 20.0
	_attack.windup = 0.1
	_attack.active = 0.2
	_attack.recovery = 0.1
	_actor = Node3D.new()
	_hitbox = HitboxComponent.new()
	_hitbox.name = &"Hitbox"
	_runner = AttackRunner.new()
	_stamina = StaminaComponent.new()
	_actor.add_child(_hitbox)
	_actor.add_child(_runner)
	_actor.add_child(_stamina)
	add_child_autofree(_actor)
	var stats := CharacterStats.new()
	stats.stamina_max = 100.0
	_stamina.apply_stats(stats)
	_runner.set_physics_process(false)  # tests drive tick() by hand
	_target = Node3D.new()
	_target_health = HealthComponent.new()
	_target_health.name = &"Health"
	_target_hurtbox = HurtboxComponent.new()
	_target_hurtbox.name = &"Hurtbox"
	_target.add_child(_target_health)
	_target.add_child(_target_hurtbox)
	add_child_autofree(_target)
	_target_hurtbox.actor = _target
	_target_health.max_health = 100.0
	_target_health.reset()


func test_start_pays_stamina() -> void:
	assert_true(_runner.start(_attack, _actor, _stamina))
	assert_eq(_stamina.current, 80.0)


func test_start_refused_when_stamina_is_short() -> void:
	_stamina.current = 5.0
	assert_false(_runner.start(_attack, _actor, _stamina))
	assert_false(_runner.is_busy())
	assert_eq(_stamina.current, 5.0, "a refused attack costs nothing")


func test_placeholder_clip_falls_back_to_attack_data_timings() -> void:
	_runner.start(_attack, _actor, _stamina)
	assert_eq(_runner.phase, AttackRunner.Phase.WINDUP)
	assert_false(_hitbox.active)
	_runner.tick(0.11)
	assert_eq(_runner.phase, AttackRunner.Phase.ACTIVE)
	assert_true(_hitbox.active)
	_runner.tick(0.2)
	assert_eq(_runner.phase, AttackRunner.Phase.RECOVERY)
	assert_false(_hitbox.active)
	watch_signals(_runner)
	_runner.tick(0.1)
	assert_false(_runner.is_busy())
	assert_signal_emitted(_runner, "finished")


func test_cancel_closes_the_hit_window() -> void:
	_runner.start(_attack, _actor, _stamina)
	_runner.tick(0.15)
	watch_signals(_runner)
	_runner.cancel()
	assert_false(_hitbox.active)
	assert_false(_runner.is_busy())
	assert_signal_emitted(_runner, "cancelled")


func test_method_track_clip_drives_the_window_instead_of_timings() -> void:
	var player := AnimationPlayer.new()
	_actor.add_child(player)
	var clip := Animation.new()
	clip.length = 0.3
	var track: int = clip.add_track(Animation.TYPE_METHOD)
	clip.track_set_path(track, ^"AttackRunner")
	clip.track_insert_key(track, 0.05, {"method": &"open_hit_window", "args": []})
	var library := AnimationLibrary.new()
	library.add_animation(&"swing", clip)
	player.add_animation_library(&"", library)
	_runner._animation_player = player
	_attack.animation_name = &"swing"
	_runner.start(_attack, _actor, _stamina)
	_runner.tick(0.2)
	assert_eq(_runner.phase, AttackRunner.Phase.WINDUP, "timings ignored: the track has not fired")
	_runner.open_hit_window()
	assert_true(_hitbox.active)


func test_one_hit_per_target_per_swing() -> void:
	_hitbox.configure(_attack, _actor, 0.0, false)
	_hitbox.set_active(true)
	assert_true(_hitbox.apply_to(_target_hurtbox, Vector3.ZERO))
	assert_false(_hitbox.apply_to(_target_hurtbox, Vector3.ZERO))
	assert_eq(_target_health.current, 90.0)


func test_a_new_swing_may_hit_the_same_target_again() -> void:
	_hitbox.configure(_attack, _actor, 0.0, false)
	_hitbox.set_active(true)
	_hitbox.apply_to(_target_hurtbox, Vector3.ZERO)
	_hitbox.set_active(false)
	_hitbox.set_active(true)
	assert_true(_hitbox.apply_to(_target_hurtbox, Vector3.ZERO))
	assert_eq(_target_health.current, 80.0)


func test_ignored_hit_does_not_use_up_the_swing() -> void:
	_hitbox.configure(_attack, _actor, 0.0, false)
	_hitbox.set_active(true)
	_target_hurtbox.invulnerable = true
	assert_false(_hitbox.apply_to(_target_hurtbox, Vector3.ZERO))
	_target_hurtbox.invulnerable = false
	assert_true(_hitbox.apply_to(_target_hurtbox, Vector3.ZERO))


func test_hit_stop_dips_and_restores_time_scale() -> void:
	HitStop.request(get_tree(), 0.05, 0.1)
	assert_eq(Engine.time_scale, 0.1)
	await wait_seconds(0.2)
	assert_eq(Engine.time_scale, 1.0)


func after_each() -> void:
	HitStop.cancel()
