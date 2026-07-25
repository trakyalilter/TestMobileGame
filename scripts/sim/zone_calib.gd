extends Node
# ============================================================================
# ZONE CALIBRATION SOLVER (v142) — 2026-07-25.
#
# ZONE_BASELINE_v142.md showed a clean break at Zone 4: Common-N (the intended
# answer for zone N) lands 2-8 kills where Z2/Z3 land 5-17. That is ONE
# mis-calibration, so rather than hand-guess x0.65 seven times, this probe
# SOLVES for the multipliers.
#
# Method, per (zone, e1..e4):
#   1. kills is ~ 1/enemy_hp, so a secant search on an hp multiplier converges
#      in 3 measurements: measure at m, re-aim m *= kills/target, repeat.
#      max_shield rides the same multiplier (it is part of the same EHP pool).
#   2. with hp fixed, if the tier-matched Common still DIES, step atk down the
#      ATK_STEPS ladder until it survives DEATH_TRIALS runs. Owner idle rule:
#      "common new tier gear set must farm e3/e4 ... if dies no point of idle."
#
# The kit is bit-identical to z3_funnel config 9 (same affixes, ammo, kits,
# 20%/30% consumable thresholds) so the output is directly comparable to the
# Z2/Z3 rows that the owner already accepted.
#
#   Godot --headless --path <root> res://scenes/zone_calib.tscn -- --zones=4,5
# ============================================================================

const DT := 0.1
const WINDOW := 180.0
const TRIALS := 3
const DEATH_TRIALS := 5
# The shape Common-N lands on the two hand-tuned zones (Z2 17/10/7/5,
# Z3 17/11/9/5). Aim e3/e4 a little ABOVE the 5-kill bar so step 2's gate
# traits have room to bite without dropping Common under it.
const TARGETS := [15.0, 10.0, 9.0, 6.0]
const ATK_STEPS := [1.0, 0.85, 0.72, 0.62]
const SECANT_PASSES := 3

const SUFFIX := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}
const AMMO := {"kinetic": "Slug", "energy": "Cell", "explosive": "Missile"}
const W_AFF := ["dmg_injured", "servo_overclock", "shield_heal_on_hit"]
const A_AFF := ["resist_k", "flat_hp", "hull_heal_on_hit"]
const S_AFF := ["flat_shield", "shield_heal_on_hit", "capacitor_pulse"]

var _base: Dictionary = {}   # eid -> {"hp":, "max_shield":, "atk":}

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	var zones: Array = [4, 5, 6, 7, 8, 9, 10]
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--zones="):
			zones = []
			for p in String(a).split("=")[1].split(","):
				zones.append(int(p))
	print("[CAL] ===== ZONE CALIBRATION SOLVER =====")
	print("[CAL] targets e1..e4 = %s kills in %ds, no death" % [str(TARGETS), int(WINDOW)])
	for tz in zones:
		_solve_zone(sm, cm, rm, int(tz))
	print("[CAL] ===== DONE =====")
	get_tree().quit(0)

func _solve_zone(sm, cm, rm, tz: int) -> void:
	var zid := ""
	for z in cm.zones:
		if int(cm.zones[z].get("difficulty", 0)) == tz:
			zid = String(z)
			break
	if zid == "":
		print("[CAL] zone %d: NOT FOUND" % tz)
		return
	var targets: Array = []
	for eid in cm.zones[zid].get("enemies", []):
		if targets.size() >= 4:
			break
		if not bool(cm.enemy_db.get(String(eid), {}).get("is_boss", false)):
			targets.append(String(eid))
	print("[CAL] ---------- ZONE %d (%s) ----------" % [tz, zid])
	for i in range(targets.size()):
		var eid: String = targets[i]
		_remember(cm, eid)
		var target: float = TARGETS[i]

		# --- 1. secant on hp (kills ~ 1/hp) -------------------------------
		var m := 1.0
		var best_m := 1.0
		var best_err := 1e9
		var k := 0
		for _p in range(SECANT_PASSES):
			k = _median_kills(sm, cm, rm, tz, zid, eid, m, 1.0, TRIALS)
			var err: float = absf(float(k) - target)
			if err < best_err:
				best_err = err
				best_m = m
			if k <= 0:
				m *= 0.45
			else:
				m = clampf(m * (float(k) / target), 0.12, 2.0)
		m = best_m

		# --- 2. atk step-down until the tier-matched Common survives -------
		var am := 1.0
		var died := true
		for step in ATK_STEPS:
			am = float(step)
			died = _any_death(sm, cm, rm, tz, zid, eid, m, am, DEATH_TRIALS)
			if not died:
				break
		var final_k := _median_kills(sm, cm, rm, tz, zid, eid, m, am, DEATH_TRIALS)
		var b: Dictionary = _base[eid]
		print("[CAL] e%d %-22s hp x%.2f  atk x%.2f -> kills %-3d %s   | hp %d->%d  shield %d->%d  atk %d->%d" % [
			i + 1, eid, m, am, final_k, ("DIES" if died else "ok"),
			int(b["hp"]), int(round(float(b["hp"]) * m)),
			int(b["max_shield"]), int(round(float(b["max_shield"]) * m)),
			int(b["atk"]), int(round(float(b["atk"]) * am))])
		_restore(cm, eid)

func _remember(cm, eid: String) -> void:
	if _base.has(eid):
		return
	var st: Dictionary = cm.enemy_db[eid].get("stats", {})
	_base[eid] = {
		"hp": float(st.get("hp", 0.0)),
		"max_shield": float(st.get("max_shield", 0.0)),
		"atk": float(st.get("atk", 0.0)),
	}

func _apply(cm, eid: String, m: float, am: float) -> void:
	var b: Dictionary = _base[eid]
	var st: Dictionary = cm.enemy_db[eid]["stats"]
	st["hp"] = int(round(float(b["hp"]) * m))
	if float(b["max_shield"]) > 0.0:
		st["max_shield"] = int(round(float(b["max_shield"]) * m))
	st["atk"] = int(round(float(b["atk"]) * am))

func _restore(cm, eid: String) -> void:
	var b: Dictionary = _base[eid]
	var st: Dictionary = cm.enemy_db[eid]["stats"]
	st["hp"] = int(b["hp"])
	if float(b["max_shield"]) > 0.0:
		st["max_shield"] = int(b["max_shield"])
	st["atk"] = int(b["atk"])

func _median_kills(sm, cm, rm, tz: int, zid: String, eid: String, m: float, am: float, n: int) -> int:
	var ks: Array = []
	for _t in range(n):
		ks.append(int(_run(sm, cm, rm, tz, zid, eid, m, am)["kills"]))
	ks.sort()
	return int(ks[ks.size() / 2])

func _any_death(sm, cm, rm, tz: int, zid: String, eid: String, m: float, am: float, n: int) -> bool:
	for _t in range(n):
		if bool(_run(sm, cm, rm, tz, zid, eid, m, am)["died"]):
			return true
	return false

# ---- kit build + fight (bit-identical to z3_funnel config 9) --------------

func _run(sm, cm, rm, tz: int, zid: String, eid: String, m: float, am: float) -> Dictionary:
	GameState.hard_reset()
	_apply(cm, eid, m, am)
	cm.total_kills = 0
	for tid in rm.tech_tree:
		if int(rm.tech_tree[tid].get("tier", 99)) <= tz and not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)
	_set_hull(sm, tz)
	var e: Dictionary = cm.enemy_db.get(eid, {})
	var weak := _weak(e)
	_fill(sm, "battery", "z%d_battery" % tz, tz, 0, [], [])
	_fill(sm, "weapon", "z%d_%s" % [tz, SUFFIX[weak]], tz, 0, W_AFF, [])
	_fill(sm, "armor", "z%d_armor" % tz, tz, 0, A_AFF, [])
	_fill(sm, "shield", "z%d_shield" % tz, tz, 0, S_AFF, [])
	_fill(sm, "engine", "z%d_engine" % tz, tz, 0, [], [])
	_fill(sm, "sensor", "z%d_sensor" % tz, tz, 0, [], [])
	_ammo_kits(sm, weak)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	if sm.energy_used > sm.energy_capacity:
		return {"kills": 0, "died": false}
	cm.start_expedition(zid)
	cm.set_target_enemy(eid)
	if cm.current_enemy == null:
		return {"kills": 0, "died": false}
	var t := 0.0
	var k0: int = int(cm.total_kills)
	while t < WINDOW:
		_kits(sm, cm)
		cm.process_tick(DT)
		t += DT
		if sm.current_hp <= 0 or not cm.in_combat:
			return {"kills": int(cm.total_kills) - k0, "died": true}
	return {"kills": int(cm.total_kills) - k0, "died": false}

func _fill(sm, stype: String, base_id: String, zone: int, rarity: int, affixes: Array, gems: Array) -> void:
	if not base_id in sm.modules:
		return
	for i in _slots(sm, stype):
		var cid := String(sm.generate_module_drop(base_id, rarity, zone))
		if cid == "":
			continue
		var mod: Dictionary = sm.modules[cid]
		if not affixes.is_empty():
			var out := {}
			for p in affixes:
				var aid := String(p)
				if not sm.AFFIX_DB.has(aid):
					continue
				var lim: Array = sm.AFFIX_DB[aid].get("limit_to", [])
				if lim.is_empty() or (stype in lim):
					out[aid] = float(sm._roll_affix_value(aid, zone, 1.0)["value"])
			mod["affixes"] = out
		if not gems.is_empty():
			if (mod.get("sockets", []) as Array).size() < 3:
				mod["sockets"] = [null, null, null]
			for gi in range(3):
				var gid := String(gems[gi % gems.size()])
				GameState.resources.add_element(gid, 1)
				sm.insert_gem(cid, gi, gid)
		sm.equip_module(i, cid, true)

func _weak(e: Dictionary) -> String:
	var best := "kinetic"
	var bv: float = float(e.get("resist_k", 0.0))
	if float(e.get("resist_e", 0.0)) < bv:
		bv = float(e.get("resist_e", 0.0)); best = "energy"
	if float(e.get("resist_x", 0.0)) < bv:
		best = "explosive"
	return best

func _set_hull(sm, n: int) -> void:
	for h in sm.hulls:
		if int(sm.hulls[h].get("tier", 0)) == clampi(n, 1, 10):
			sm.active_hull = String(h)
			break
	sm.loadout.clear()
	sm.ammo_loadout.clear()
	sm.consumable_hull_slot = ""
	sm.consumable_shield_slot = ""

func _slots(sm, stype: String) -> Array:
	var out: Array = []
	var slots: Array = sm.hulls.get(sm.active_hull, {}).get("slots", [])
	for i in range(slots.size()):
		if String(slots[i]) == stype:
			out.append(i)
	return out

func _ammo_kits(sm, weak: String) -> void:
	var ammo := "%sT2" % AMMO[weak]
	if not ElementDB.ELEMENT_NAMES.has(ammo):
		ammo = "%sT1" % AMMO[weak]
	GameState.resources.add_element(ammo, 1000000)
	for i in _slots(sm, "weapon"):
		sm.ammo_loadout[i] = ammo
	GameState.resources.add_element("EmergencyPatch", 100000)
	GameState.resources.add_element("BasicBooster", 100000)
	sm.equip_consumable("hull", "EmergencyPatch")
	sm.equip_consumable("shield", "BasicBooster")

func _kits(sm, cm) -> void:
	if not cm.in_combat:
		return
	if sm.current_hp < sm.max_hp * 0.20 and sm.consumable_hull_slot != "":
		cm.use_manual_consumable("hull")
	if cm.player_shield < cm.player_max_shield * 0.30 and sm.consumable_shield_slot != "":
		cm.use_manual_consumable("shield")
