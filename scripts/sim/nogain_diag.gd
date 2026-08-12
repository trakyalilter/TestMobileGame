extends Node
# THE FOUR NOGAIN CELLS, MEASURED PROPERLY (v175)
#
# zone_gate_check reports NOGAIN on Z6->Z7, Z7->Z8, Z8->Z9 and Z9->Z10: a maxed Zone-N
# kit farms Zone N+1 e3 at least as fast as a clean Zone N+1 COMMON set, so the new tier
# is not worth crafting â€” a dominated choice.
#
# It runs TRIALS=5 and reports the MEDIAN, and the cells visibly move between runs
# (Z8->Z9 printed 13 vs 13 on one run and 15 vs 12 on the next). Tuning against a
# 5-sample median is how this project has wasted passes before, so this measures the same
# cells at a higher trial count and reports the RATIO against the rule's own bar
# (maxed must be <= commons / GATE_MIN_SLOWDOWN) with a spread, so a fix can be aimed at
# the size of the real gap rather than at one noisy print.
#
# Also splits the two things that could be driving it â€” is the old kit out-DAMAGING the
# new tier, or just out-SURVIVING it? â€” by reporting deaths alongside kills.
#
#   Godot --headless --path <root> res://scenes/nogain_diag.tscn [--trials=N]

const ZGC := preload("res://scripts/sim/zone_gate_check.gd")

var TRIALS := 13
var _z

func _ready() -> void:
	await get_tree().process_frame
	if not GameState.sim_mode:
		print("[NG] ABORT: sim_mode false")
		get_tree().quit(1)
		return
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if str(a).begins_with("--trials="):
			TRIALS = maxi(1, int(str(a).split("=")[1]))
	GameState.set_process(false)
	_z = ZGC.new()
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	var bar: float = float(_z.GATE_MIN_SLOWDOWN)

	print("[NG] %d trials/cell. Rule: maxedZ(N) kills <= commonZ(N+1) kills / %.2f" % [TRIALS, bar])
	print("[NG] %-9s %-22s | %-22s | %-22s | %8s %8s" % [
		"cell", "maxed Z(N)", "common Z(N+1)", "", "ratio", "bar"])

	for n in range(6, 10):
		var zid: String = _z._zone_with_diff(cm, n + 1)
		if zid == "":
			continue
		var roster: Array = cm.zones[zid].get("enemies", [])
		if roster.size() < 3:
			continue
		var eid := str(roster[2])
		var a: Dictionary = _many(sm, cm, rm, n, zid, eid, true)
		var b: Dictionary = _many(sm, cm, rm, n, zid, eid, false)
		var ak: float = float(a["mean"])
		var bk: float = float(b["mean"])
		# What the maxed kit is ALLOWED to do, and how far over it is.
		var allowed: float = bk / bar
		var over: float = (ak / maxf(0.01, allowed))
		print("[NG] Z%d->Z%d  %5.1f kills %2dd [%d-%d] | %5.1f kills %2dd [%d-%d] | %8.2f %8.2f  %s" % [
			n, n + 1, ak, int(a["deaths"]), int(a["lo"]), int(a["hi"]),
			bk, int(b["deaths"]), int(b["lo"]), int(b["hi"]),
			ak / maxf(0.01, bk), allowed,
			("OVER by x%.2f" % over) if ak > allowed else "ok"])
		print("[NG]           %s needs commons at >= %.1f kills, or maxed at <= %.1f" % [
			eid, ak * bar, allowed])
		# Kills are the outcome; this is the CAUSE. Compare the three kits' raw attack:
		# a clean Common at zone N, the same at N+1 (that difference IS the tier step),
		# and the maxed Zone-N stack. If the stack out-runs the step, no per-enemy tuning
		# fixes it â€” the affix/core budget is the thing that is too big.
		# DECOMPOSITION. sm.attack says the maxed kit has ~0.34x the raw damage of the new
		# tier's commons, which cannot be reconciled with it killing faster -- because
		# affix and Resonant-core multipliers are applied at resolve time and never appear
		# in that stat. So measure the stack the only honest way: strip it.
		#   bare = the SAME Zone-N Legendary, no affixes, no cores.
		# maxed/bare is what the affix+core stack is actually worth, in kills.
		var bare: Dictionary = _many_bare(sm, cm, rm, n, zid, eid)
		var bk2: float = float(bare["mean"])
		print("[NG]           stack: bare LegendaryZ%d %.1f kills -> maxed %.1f = affix+cores worth x%.2f" % [
			n, bk2, ak, ak / maxf(0.1, bk2)])
		print("[NG]           bare vs commonZ%d: %.2f (tier step alone) | needed <= %.2f" % [
			n + 1, bk2 / maxf(0.1, bk), 1.0 / bar])
		# Which half of the stack is doing it? Cut the one that is oversized, not both.
		var aff: float = float(_many_bare(sm, cm, rm, n, zid, eid, true, false)["mean"])
		var gem: float = float(_many_bare(sm, cm, rm, n, zid, eid, false, true)["mean"])
		print("[NG]           split: affixes-only %.1f (x%.2f) | cores-only %.1f (x%.2f) | both %.1f (x%.2f)" % [
			aff, aff / maxf(0.1, bk2), gem, gem / maxf(0.1, bk2), ak, ak / maxf(0.1, bk2)])
		# THE LIKE-FOR-LIKE TEST. The rule pits a fully OPTIMISED Zone-N kit against a
		# FRESH, unoptimised Zone-(N+1) one, which is not the same question as "is the
		# next tier an upgrade". Compare maxed against maxed: if Zone-(N+1) optimised
		# clearly beats Zone-N optimised, the ladder is healthy and the rule is simply
		# comparing the wrong two things.
		var mN1: float = float(_many(sm, cm, rm, n + 1, zid, eid, true)["mean"])
		print("[NG]           LIKE-FOR-LIKE: maxedZ%d %.1f -> maxedZ%d %.1f = tier gain x%.2f" % [
			n, ak, n + 1, mN1, mN1 / maxf(0.1, ak)])
	get_tree().quit(0)


func _weak_of(cm, eid: String) -> String:
	return _z._weak_type(cm.enemy_db.get(eid, {}))


# Build a kit and read the recalculated ship attack. No combat â€” this isolates the raw
# stat so the kill numbers above can be attributed to damage rather than to anything else.
func _atk_of(sm, cm, rm, hull_n: int, gear_n: int, weak: String, maxed: bool) -> float:
	GameState.hard_reset()
	_z._unlock_research(rm, gear_n)
	_z._set_hull(sm, hull_n)
	if maxed:
		_z._equip_maxed(sm, gear_n, weak, {})
	else:
		_z._equip_common(sm, gear_n, weak)
	sm.recalc_stats()
	return float(sm.attack)


# sm.attack is PER-SHOT damage only. The maxed kit's affixes are
# ["dmg_injured", "servo_overclock", "shield_heal_on_hit"] plus three Resonant cores, and
# servo_overclock is attack SPEED â€” none of which shows up in sm.attack. Comparing raw
# attack alone said the maxed kit had 0.35x the damage while killing FASTER, which is not
# a paradox, it is the wrong quantity. Return the whole set.
func _kit_stats(sm, cm, rm, hull_n: int, gear_n: int, weak: String, maxed: bool) -> Dictionary:
	GameState.hard_reset()
	_z._unlock_research(rm, gear_n)
	_z._set_hull(sm, hull_n)
	if maxed:
		_z._equip_maxed(sm, gear_n, weak, {})
	else:
		_z._equip_common(sm, gear_n, weak)
	sm.recalc_stats()
	return {
		"atk": float(sm.attack),
		"spd": float(sm.attack_speed_bonus),
		"crit": float(sm.crit_chance),
		"slots": _z._slots(sm, "weapon").size(),
	}


# Seconds to the FIRST kill in a real fight. NOTE _use_kits, not _kit -- _kit lives on
# boss_gearcheck and calling it from a zone_gate_check-derived probe throws every tick.
func _ttk(sm, cm, rm, hull_n: int, zid: String, eid: String, maxed: bool) -> float:
	GameState.hard_reset()
	cm.total_kills = 0
	var gear_n: int = hull_n if maxed else hull_n
	_z._unlock_research(rm, gear_n)
	_z._set_hull(sm, hull_n)
	var weak: String = _z._weak_type(cm.enemy_db.get(eid, {}))
	if maxed:
		_z._equip_maxed(sm, gear_n, weak, cm.enemy_db.get(eid, {}))
	else:
		_z._equip_common(sm, gear_n, weak)
	_z._ammo_kits(sm, weak, gear_n)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	cm.start_expedition(zid)
	cm.set_target_enemy(eid)
	if cm.current_enemy == null:
		return -1.0
	var t := 0.0
	var k0: int = int(cm.total_kills)
	while t < 180.0:
		_z._use_kits(sm, cm)
		cm.process_tick(0.1)
		t += 0.1
		if int(cm.total_kills) > k0:
			return t
		if sm.current_hp <= 0:
			return -1.0
	return -1.0


# zone_gate_check's maxed path with the affixes and cores taken OUT: same Legendary
# rarity, same hull, same ammo tier, same everything else. Mirrors _run's setup exactly
# (research and ammo at zone_n = hull_n + 1) -- getting that wrong is what made an earlier
# version of this probe report the maxed kit scoring zero kills, because a weapon with no
# valid ammo tier simply never fires.
func _many_bare(sm, cm, rm, hull_n: int, zid: String, eid: String, use_aff: bool = false, use_gem: bool = false) -> Dictionary:
	var ks: Array = []
	var zone_n: int = hull_n + 1
	for _i in range(TRIALS):
		GameState.hard_reset()
		cm.total_kills = 0
		_z._unlock_research(rm, zone_n)
		_z._set_hull(sm, hull_n)
		var e: Dictionary = cm.enemy_db.get(eid, {})
		var weak: String = _z._weak_type(e)
		_z._fill(sm, "battery", "z%d_battery" % hull_n, hull_n, 0, [], [])
		_z._fill(sm, "weapon", "z%d_%s" % [hull_n, _z.SUFFIX[weak]], hull_n, 3, (_z.BEST_WEAPON if use_aff else []), (_z.WEAPON_GEMS if use_gem else []))
		_z._fill(sm, "armor", "z%d_armor" % hull_n, hull_n, 3, [], [])
		_z._fill(sm, "shield", "z%d_shield" % hull_n, hull_n, 3, (_z.BEST_SHIELD if use_aff else []), (_z.DEF_GEMS if use_gem else []))
		_z._fill(sm, "engine", "z%d_engine" % hull_n, hull_n, 0, [], [])
		_z._fill(sm, "sensor", "z%d_sensor" % hull_n, hull_n, 0, [], [])
		_z._ammo_kits(sm, weak, zone_n)
		sm.recalc_stats()
		sm.current_hp = sm.max_hp
		cm.start_expedition(zid)
		cm.set_target_enemy(eid)
		if cm.current_enemy == null:
			ks.append(0)
			continue
		var t := 0.0
		var k0: int = int(cm.total_kills)
		while t < 180.0:
			_z._use_kits(sm, cm)
			cm.process_tick(0.1)
			t += 0.1
			if sm.current_hp <= 0 or not cm.in_combat:
				break
		ks.append(int(cm.total_kills) - k0)
	var tot := 0.0
	for k in ks:
		tot += float(k)
	return {"mean": tot / float(ks.size())}


func _many(sm, cm, rm, hull_n: int, zid: String, eid: String, maxed: bool) -> Dictionary:
	var ks: Array = []
	var deaths := 0
	for _i in range(TRIALS):
		var r: Dictionary = _z._run(sm, cm, rm, hull_n, zid, eid, maxed)
		ks.append(int(r.get("kills", 0)))
		if bool(r.get("died", false)):
			deaths += 1
	ks.sort()
	var tot := 0.0
	for k in ks:
		tot += float(k)
	return {"mean": tot / float(ks.size()), "deaths": deaths,
		"lo": ks[0], "hi": ks[ks.size() - 1]}
