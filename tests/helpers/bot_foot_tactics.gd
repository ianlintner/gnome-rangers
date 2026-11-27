class_name BotFootTactics
extends RefCounted
## On-foot fighting for a [FightBot]: roll through telegraphed hits, punish an open Grukk with
## light attacks, and otherwise keep the bow's range band and shoot. Each tick the first tactic
## (in [method step]'s order) that claims the controls wins.

const MELEE_RANGE: float = 2.9
const ARROW_RANGE: Vector2 = Vector2(5.5, 17.0)
## Dodge when the telegraphed hit opens within this many seconds. The roll's 0.3 s of i-frames
## start a few ticks after the press, so this lead covers the slam and its shockwave ring.
const DODGE_LEAD: float = 0.07
## How far outside melee range the bot still closes in on an open (recovering) boss.
const PUNISH_REACH: float = 1.5
## Stamina always kept back for the next dodge, on top of the dodge's own cost.
const STAMINA_RESERVE: float = 6.0
## Evasion headings tried in order (degrees from straight away, turned towards the centre).
const EVADE_ANGLES: Array[float] = [60.0, -60.0, 100.0, -100.0, 0.0, 140.0, -140.0]
const RING_EVADE_ANGLES: Array[float] = [0.0, 30.0, -30.0, 60.0, -60.0, 100.0, -100.0]

var bot: FightBot = null
var _tactics: Array[Callable] = []


func _init(owner: FightBot) -> void:
	bot = owner
	_tactics = [
		dodge_if_threatened,
		_clear_ring,
		_open_with_melee,
		_find_line_of_sight,
		_recover_stamina,
		_melee,
		_punish,
		_shoot,
		_keep_band,
	]


## One tick of on-foot fighting.
func step() -> void:
	bot.keep_lock()
	if bot.busy():
		return
	for tactic: Callable in _tactics:
		if tactic.call():
			return


## Dodges away from the boss when a telegraphed hit is about to land within reach.
func dodge_if_threatened() -> bool:
	var player: Player = bot.player
	if BotThreat.hit_in(bot.boss) > DODGE_LEAD or not BotThreat.within_reach(bot.boss, player):
		return false
	if player.stamina.current < player.stats.dodge_stamina_cost or player.stamina.is_winded():
		return false
	bot.input.hold(&"aim", false)
	bot.input.steer(evade_direction(), bot.view())
	if bot.input.tap(&"dodge"):
		bot.dodges += 1
	return true


## A clear evasion heading: sideways-and-back from the boss (straight back from a ring, which
## only distance beats), bent towards the arena centre and turned clear of scenery.
func evade_direction() -> Vector3:
	var away: Vector3 = FightBot.flat(bot.player.global_position - bot.boss.global_position)
	var angles: Array[float] = RING_EVADE_ANGLES if BotThreat.ringing(bot.boss) else EVADE_ANGLES
	return bot.clear_heading(bot.player, away, angles)


## A slam rings the floor: get clear while it winds up.
func _clear_ring() -> bool:
	if BotThreat.hit_in(bot.boss) == INF or not BotThreat.ringing(bot.boss):
		return false
	if not BotThreat.within_reach(bot.boss, bot.player):
		return false
	_move(evade_direction())
	return true


## Until the first melee hit lands, walk straight at Grukk and swing once in reach (stamina for
## a dodge kept back). Dodging and ring-clearing outrank this; afterwards the bow rotation resumes.
func _open_with_melee() -> bool:
	if (bot.hits[&"melee"] as int) > 0:
		return false
	var stamina: StaminaComponent = bot.player.stamina
	if stamina.current < _swing_cost() + _reserve() or stamina.is_winded():
		return false
	if _distance() > MELEE_RANGE:
		_move(_to_boss())
		return true
	_move(Vector3.ZERO)
	bot.input.tap(&"attack_light")
	return true


## No lock means no line of sight (cover in the way): circle round it.
func _find_line_of_sight() -> bool:
	if bot.locked() or _distance() <= MELEE_RANGE:
		return false
	_move(_circle())
	return true


## Every action leaves enough stamina for the next dodge: below that, only reposition.
func _recover_stamina() -> bool:
	var stamina: StaminaComponent = bot.player.stamina
	if stamina.current >= _reserve() and not stamina.is_winded():
		return false
	_move(evade_direction() if _distance() < ARROW_RANGE.x else Vector3.ZERO)
	return true


## In melee range: never trade blows; swing only while Grukk is open, else back off.
func _melee() -> bool:
	if _distance() > MELEE_RANGE:
		return false
	if not BotThreat.boss_open(bot.boss):
		_move(evade_direction())
		return true
	_move(Vector3.ZERO)
	if bot.player.stamina.current >= _swing_cost() + _reserve():
		bot.input.tap(&"attack_light")
	return true


## Grukk is recovering just out of reach: close in for the punish.
func _punish() -> bool:
	if not BotThreat.boss_open(bot.boss) or _distance() > MELEE_RANGE + PUNISH_REACH:
		return false
	_move(_to_boss())
	return true


## Inside the bow band: shoot when the reticle ray reaches Grukk, else circle for a line.
func _shoot() -> bool:
	var distance: float = _distance()
	if distance < ARROW_RANGE.x or distance > ARROW_RANGE.y:
		return false
	if not bot.clear_shot():
		_move(_circle())  # cover (or the camera's view of it) is in the way
		return true
	if bot.player.stamina.current < bot.player.bow.data.arrow_attack.stamina_cost + _reserve():
		return false
	bot.input.steer(Vector3.ZERO, bot.view())
	bot.shoot()
	return true


## Outside the band: open the gap again, or walk in.
func _keep_band() -> bool:
	_move(evade_direction() if _distance() < ARROW_RANGE.x else _to_boss())
	return true


## Sideways round Grukk, drifting towards the open arena centre: Grukk walks straight at the
## player and snags on cover rocks, so this unpins both and reopens the line for the bow.
func _circle() -> Vector3:
	var to_centre: Vector3 = FightBot.flat(bot.level.arena_center() - bot.player.global_position)
	var drift: Vector3 = to_centre.normalized() * clampf(to_centre.length() / 8.0, 0.0, 1.0)
	var circle: Vector3 = FightBot.side(_to_boss()).normalized() * bot.orbit_sign() + drift
	return bot.clear_heading(bot.player, circle, FightBot.AROUND_ANGLES)


func _move(direction: Vector3) -> void:
	bot.input.hold(&"aim", false)
	bot.input.steer(direction, bot.view())


func _to_boss() -> Vector3:
	return FightBot.flat(bot.boss.global_position - bot.player.global_position)


func _distance() -> float:
	return _to_boss().length()


func _reserve() -> float:
	return bot.player.stats.dodge_stamina_cost + STAMINA_RESERVE


## A tap may chain into any light hit, so budget for the dearest one.
func _swing_cost() -> float:
	var cost: float = 0.0
	for swing: AttackData in bot.player.moveset.light_chain:
		cost = maxf(cost, swing.stamina_cost)
	return cost
