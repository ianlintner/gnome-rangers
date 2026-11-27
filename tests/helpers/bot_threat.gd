class_name BotThreat
extends RefCounted
## What a [FightBot] reads off the boss: when its telegraphed hit lands, how far it reaches and
## whether the boss is open to a punish. Public state only (the [AttackRunner] phase, the
## current [BossMoveData]); no peeking at the brain's next choice.

## Added to an attack's reach: the player's own radius plus a safety margin.
const MARGIN: float = 0.8


## Game seconds until the boss's current telegraphed hit opens; INF when none is coming.
static func hit_in(boss: BossBase) -> float:
	var runner: AttackRunner = boss.runner
	if runner.phase != AttackRunner.Phase.WINDUP or runner.current == null:
		return INF
	return runner.current.windup - runner.elapsed


## True while the current move ends in a shockwave ring (slams): the ring reaches far.
static func ringing(boss: BossBase) -> bool:
	return boss.current_move != null and boss.current_move.followup_attack != null


## True while the boss cannot answer a hit: staggered, or recovering from a committed attack.
static func boss_open(boss: BossBase) -> bool:
	if boss.state_machine.current_state_name == &"Staggered":
		return true
	if ringing(boss):
		return false  # a slam's shockwave ring is still to come
	return boss.runner.phase == AttackRunner.Phase.RECOVERY and boss.runner.current != null


## Flat distance from the boss inside which its current move (and any follow-up) can land.
static func reach(boss: BossBase) -> float:
	var move: BossMoveData = boss.current_move
	if move == null:
		return INF
	return maxf(reach_of(move.attack), reach_of(move.followup_attack)) + MARGIN


## True when `body` stands where the boss's current move can land.
static func within_reach(boss: BossBase, body: Node3D) -> bool:
	var offset: Vector3 = boss.global_position - body.global_position
	return Vector2(offset.x, offset.z).length() <= reach(boss)


## Flat distance from the boss's centre to the far edge of `attack`'s hit volume.
static func reach_of(attack: AttackData) -> float:
	if attack == null:
		return 0.0
	var offset: float = Vector2(attack.hit_offset.x, attack.hit_offset.z).length()
	if attack.hit_shape == AttackData.HitShape.BOX:
		return offset + Vector2(attack.hit_size.x, attack.hit_size.z).length() * 0.5
	return offset + attack.hit_size.x
