class_name BotSaddleTactics
extends RefCounted
## Mounted fighting for a [FightBot]: gallop clear of telegraphed hits (the cat cannot roll),
## shoot from the kite band, then pounce. Once the saddle quota (a mounted arrow and a pounce)
## has landed, the bot steps off and the fight is finished on foot, where it can roll.

## Pounce run-up distance, and the band kept while shooting from the saddle. The cat walks
## faster with a drawn bow (5.5 * 0.6 m/s) than Grukk does (2.6 m/s, 3.25 in phase 2), so it
## draws while backing off and only breaks off to gallop below the band.
const POUNCE_RUN_UP: float = 7.0
const KITE_BAND: Vector2 = Vector2(6.0, 14.0)
## Inside this distance the cat backs away while drawing; beyond it, it circles.
const KITE_COMFORT: float = 10.0
## Sideways share of a retreat, so the cat curves round Grukk instead of fleeing straight.
const RETREAT_CURVE: float = 0.6

var bot: FightBot = null
## Set once the saddle quota has landed; the bot then dismounts for good.
var done: bool = false
var _tactics: Array[Callable] = []


func _init(owner: FightBot) -> void:
	bot = owner
	_tactics = [_step_off, _gallop_clear, _pounce, _open_gap, _find_line, _shoot]


## One tick in the saddle.
func step() -> void:
	bot.keep_lock()
	var ride: CatMount = bot.player.mount
	if bot.busy() or ride.state_machine.current_state_name == &"Pounce":
		bot.input.steer(Vector3.ZERO, bot.view())
		return
	if not done and bot.hits[&"pounce"] > 0 and bot.hits[&"mounted_arrow"] > 0:
		done = true
		bot.note("saddle quota met: dismounting to finish on foot")
	for tactic: Callable in _tactics:
		if tactic.call():
			return


## Quota met: get clear of Grukk, then step off.
func _step_off() -> bool:
	if not done:
		return false
	bot.input.hold(&"aim", false)
	if _distance() < KITE_BAND.x:
		_ride(_retreat(0.4))
		return true
	bot.input.hold(&"sprint", false)
	bot.input.steer(Vector3.ZERO, bot.view())
	bot.input.tap(&"interact")
	return true


## The cat cannot roll: gallop clear of any telegraphed hit that would reach the saddle.
func _gallop_clear() -> bool:
	if BotThreat.hit_in(bot.boss) == INF:
		return false
	if _distance() > BotThreat.reach(bot.boss) + POUNCE_RUN_UP * 0.5:
		return false
	bot.input.hold(&"aim", false)
	_ride(_retreat(RETREAT_CURVE))
	return true


## Saddle arrows first, from the safe kite band; only then commit to a pounce.
func _pounce() -> bool:
	var ride: CatMount = bot.player.mount
	if bot.hits[&"mounted_arrow"] == 0 or ride.pounce_cooldown_left > 0.0 or not bot.locked():
		return false
	bot.input.hold(&"aim", false)
	if _distance() < POUNCE_RUN_UP and ride.state_machine.current_state_name != &"Gallop":
		_ride(_retreat(RETREAT_CURVE))  # make room for the run-up
		return true
	_ride(_to_boss())
	if ride.can_pounce(bot.boss) and bot.input.tap(&"attack_heavy"):
		bot.pounces += 1
		bot.note("pounce at %.1f m" % _distance())
	return true


func _open_gap() -> bool:
	if _distance() >= KITE_BAND.x:
		return false
	bot.input.hold(&"aim", false)
	_ride(_retreat(0.4))
	return true


## Cover (or the cat's own head) between the reticle and Grukk: circle until the line clears.
func _find_line() -> bool:
	if bot.clear_shot():
		return false
	bot.input.hold(&"aim", false)
	var circle: Vector3 = FightBot.side(_to_boss()) * bot.orbit_sign() + _band_pull()
	_ride(bot.clear_heading(bot.player.mount, circle, FightBot.AROUND_ANGLES), false)
	return true


## Draws and looses while keeping the band: backing off (curving round) when close,
## circling when comfortable, closing in from beyond it.
func _shoot() -> bool:
	var to_boss: Vector3 = _to_boss()
	var heading: Vector3 = FightBot.side(to_boss) * bot.orbit_sign() + _band_pull()
	if _distance() < KITE_COMFORT:
		heading = _retreat(1.0)
	bot.input.hold(&"sprint", false)
	bot.input.steer(
		bot.clear_heading(bot.player.mount, heading, FightBot.AROUND_ANGLES), bot.view()
	)
	bot.shoot()
	return true


## Walks back into the kite band from beyond its far edge.
func _band_pull() -> Vector3:
	return _to_boss().normalized() if _distance() > KITE_BAND.y else Vector3.ZERO


func _ride(direction: Vector3, gallop: bool = true) -> void:
	bot.input.hold(&"sprint", gallop and not bot.player.stamina.is_winded())
	bot.input.steer(direction, bot.view())


## Away from Grukk, curving `curve` sideways towards the arena centre, clear of scenery.
func _retreat(curve: float) -> Vector3:
	var to_boss: Vector3 = _to_boss().normalized()
	var away: Vector3 = -to_boss + FightBot.side(to_boss) * bot.orbit_sign() * curve
	return bot.clear_heading(bot.player.mount, away, FightBot.AROUND_ANGLES)


func _to_boss() -> Vector3:
	return FightBot.flat(bot.boss.global_position - bot.player.mount.global_position)


func _distance() -> float:
	return _to_boss().length()
