extends Node
# THE HULL-PER-ZONE RULE (owner, 2026-08-09).
#
# "Zone 6 boss can't be beatable with a Tier 5 hull." Generalised: zone N's boss
# requires hull tier N, and beating it is what earns hull N+1. This sweeps every
# zone and reports the boss against the PREVIOUS zone's hull and its own, with
# tier-matched RARE modules in both cases so the hull is the only variable.
#
# PASS means: previous hull loses, own hull wins.
#
# NOTE (2026-08-09 ruling): the game does NOT satisfy this, deliberately. Slot
# growth is ~1.14x per tier and a decisive gate needs ~1.4x, which from 8 slots
# compounds to 166 by T10. Hulls are a strong upgrade, not a gate; MODULE RARITY
# is the gate, and boss_gearcheck holds that at 15/15. This is kept as a
# DIAGNOSTIC — it reports the hull ladder, it does not assert it. Read it before
# proposing hull-per-zone gating again.
#
# The tutorial routes the player through a FRIGATE hull (m026b) and a rare weapon
# (m026d) before the boss beat (m026e), so "rare set on hull tier 1" and "what the
# chain actually hands you" are two different loadouts. Measures both, plus the
# rarity either side, so the answer is a win rate rather than an impression.
#
#   Godot --headless --path <root> res://scenes/z1_boss_kit_check.tscn

const BGC := preload("res://scripts/sim/boss_gearcheck.gd")
const EID := "z1_boss_architect"
const ZONE := "lunar_orbit"
const TRIALS := 21
const DT := 0.1
const MAXT := 900.0
const RNAME := ["Common", "Uncommon", "Rare", "Legendary"]

var _bgc

func _ready() -> void:
	await get_tree().process_frame
	if not GameState.sim_mode:
		print("[HULL] ABORT: sim_mode false")
		get_tree().quit(1)
		return
	GameState.set_process(false)
	_bgc = BGC.new()

	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	print("[HULL] zone N boss, RARE tier-N modules, %d trials. Hull is the only variable." % TRIALS)
	print("[HULL] %-5s %-24s %14s %14s  %s" % ["zone", "boss", "hull N-1", "hull N", "verdict"])
	var fails := 0
	for z in range(1, 11):
		var eid := _boss_of(cm, z)
		if eid == "":
			continue
		var zid := _zone_of(cm, z)
		var prev := _run(sm, cm, rm, z, maxi(1, z - 1), eid, zid)
		var own := _run(sm, cm, rm, z, z, eid, zid)
		var ok: bool = (prev < TRIALS * 0.5) and (own >= TRIALS * 0.6)
		if not ok:
			fails += 1
		print("[HULL] Z%-4d %-24s %10d/%-3d %10d/%-3d  %s" % [
			z, eid.substr(0, 24), prev, TRIALS, own, TRIALS,
			"ok" if ok else ("PREV HULL CLEARS IT" if prev >= TRIALS * 0.5 else "OWN HULL CANNOT")])
	# INFO, not RESULT: this scene reports the hull ladder, it does not assert it.
	# The hull-per-zone rule was measured and DECLINED (see docs/RULINGS) — printing
	# FAIL here would leave a permanently red scene in the suite that people learn to
	# ignore, which is worse than no scene at all.
	print("[HULL] INFO: %d zone(s) where the previous hull still clears the boss." % fails)
	print("[HULL] Expected — hulls are an upgrade, not a gate. Rarity is the gate (boss_gearcheck).")
	get_tree().quit(0)


func _boss_of(cm, z: int) -> String:
	for eid in cm.enemy_db:
		var e: Dictionary = cm.enemy_db[eid]
		if bool(e.get("is_boss", false)) and int(e.get("zone", 0)) == z:
			return String(eid)
	return ""


func _zone_of(cm, z: int) -> String:
	for zid in cm.zones:
		if int(cm.zones[zid].get("difficulty", 0)) == z:
			return String(zid)
	return ""


func _run(sm, cm, rm, zone: int, hull_tier: int, eid: String, zid: String) -> int:
	var wins := 0
	for _i in range(TRIALS):
		if bool(_fight2(sm, cm, rm, zone, hull_tier, eid, zid)):
			wins += 1
	return wins


func _fight2(sm, cm, rm, zone: int, hull_tier: int, eid: String, zid: String) -> bool:
	GameState.hard_reset()
	cm.boss_kills.clear()
	cm.total_kills = 0
	_bgc._unlock_research(rm, zone)
	_bgc._set_hull(sm, hull_tier)
	var weak: String = String(_bgc._weak(cm.enemy_db[eid]))
	_bgc._equip_gear(sm, zone, weak, 2, false, [])   # RARE, tier-matched modules
	_bgc._ammo_kits(sm, weak, zone)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	cm.start_expedition(zid)
	cm.set_target_enemy(eid)
	if cm.current_enemy == null:
		return false
	var t := 0.0
	while t < MAXT:
		_bgc._kit(sm, cm)
		cm.process_tick(DT)
		t += DT
		if int(cm.boss_kills.get(eid, 0)) > 0:
			return true
		if not cm.in_combat:
			return false
	return false


func _fight(sm, cm, rm, hull_tier: int, rarity: int) -> Dictionary:
	GameState.hard_reset()
	cm.boss_kills.clear()
	cm.total_kills = 0
	_bgc._unlock_research(rm, 1)
	_bgc._set_hull(sm, hull_tier)
	# Zone 1 gear regardless of hull — the question is the KIT, not the tier.
	_bgc._equip_gear(sm, 1, "kinetic", rarity, false, [])
	_bgc._ammo_kits(sm, "kinetic", 1)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	cm.start_expedition(ZONE)
	cm.set_target_enemy(EID)
	if cm.current_enemy == null:
		return {"win": false, "t": 0.0, "left": 100.0}
	var t := 0.0
	while t < MAXT:
		_bgc._kit(sm, cm)
		cm.process_tick(DT)
		t += DT
		if int(cm.boss_kills.get(EID, 0)) > 0:
			return {"win": true, "t": t, "left": 0.0}
		if not cm.in_combat:
			break
	var pct: float = 100.0 * float(cm.enemy_hp) / maxf(1.0, float(cm.enemy_max_hp)) if cm.current_enemy != null else 0.0
	return {"win": false, "t": t, "left": pct}
