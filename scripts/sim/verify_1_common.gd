extends Node
# ============================================================================
# VERIFY-1: PROBE VALIDITY — does z3_funnel's forced-affix injection inflate the
# WEAKER kit (config 9, Common rarity-0)?
#
# Five kits per zone transition N:
#   A  = cfg1  Rare z(N-1), hull N-1, affixes FORCED (z3_funnel verbatim)
#   R  = cfg1  Rare z(N-1), hull N-1, affixes NATURAL (real game roll)
#   B  = cfg9  Common z(N), hull N,   affixes FORCED (z3_funnel verbatim)
#   Bn = cfg9  Common z(N), hull N,   NO affix write at all (realistic Common)
#   Bx = cfg9  Common z(N), hull N,   affixes FORCED *and registered* into
#        custom_modules so recalc_stats actually consumes them (counterfactual:
#        what cfg9 WOULD look like if the injection were symmetric)
#
# If B == Bn on every stat and kill count, the forced write is a no-op for the
# weak kit and the asymmetry claim stands. If B > Bn, the weak kit IS inflated.
# Bx bounds how large the missing inflation would have been.
#
#   Godot --headless --path <root> res://scenes/verify_1_common.tscn -- --zones=6,10 --window=180
# ============================================================================

const DT := 0.1
var WINDOW := 180.0
const TRIALS := 3

const SUFFIX := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}
const AMMO := {"kinetic": "Slug", "energy": "Cell", "explosive": "Missile"}
const W_AFF := ["dmg_injured", "servo_overclock", "shield_heal_on_hit"]
const A_AFF := ["resist_k", "flat_hp", "hull_heal_on_hit"]
const S_AFF := ["flat_shield", "shield_heal_on_hit", "capacitor_pulse"]
const SLOTS := ["battery", "weapon", "armor", "shield", "engine", "sensor"]

# affix_mode
const AFX_NONE := 0
const AFX_FORCED := 1        # exactly what z3_funnel does
const AFX_FORCED_REG := 2    # forced AND registered so recalc_stats sees it

var _base_backup: Dictionary = {}
var _reg_ids: Array = []

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	var zones: Array = [6, 10]
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--zones="):
			zones = []
			for p in s.split("=")[1].split(","):
				zones.append(int(p))
		elif s.begins_with("--window="):
			WINDOW = float(s.split("=")[1])

	print("[V1] ============ PROBE-VALIDITY VERIFY ============")
	print("[V1] z3_funnel CONFIG rows (label, gear_zone, rarity, wgems, dgems, force_sockets):")
	print("[V1]   cfg1 = [Rare N-1, gems=[], force=false]   cfg9 = [Common N, gems=[], force=false]")
	print("[V1]   -> neither cfg1 nor cfg9 requests gems, so _fill's socket branch never runs for this pair.")
	for z in zones:
		_zone(sm, cm, rm, int(z))
	print("[V1] ============ DONE ============")
	get_tree().quit(0)

func _zone(sm, cm, rm, tz: int) -> void:
	var zid := ""
	for z in cm.zones:
		if int(cm.zones[z].get("difficulty", 0)) == tz:
			zid = String(z)
			break
	if zid == "":
		print("[V1] zone %d NOT FOUND" % tz)
		return
	var roster: Array = []
	for eid in cm.zones[zid].get("enemies", []):
		if roster.size() >= 4:
			break
		if not bool(cm.enemy_db.get(String(eid), {}).get("is_boss", false)):
			roster.append(String(eid))
	print("")
	print("[V1] ######## ZONE %d (%s) ########" % [tz, zid])

	var kits: Array = [
		["A  cfg1 Rare  z%d FORCED" % (tz - 1), tz - 1, 2, tz - 1, AFX_FORCED],
		["R  cfg1 Rare  z%d natural" % (tz - 1), tz - 1, 2, tz - 1, AFX_NONE],
		["B  cfg9 Commn z%d FORCED" % tz, tz, 0, tz, AFX_FORCED],
		["Bn cfg9 Commn z%d no-affix" % tz, tz, 0, tz, AFX_NONE],
		["Bx cfg9 Commn z%d FORCED+REG" % tz, tz, 0, tz, AFX_FORCED_REG],
	]

	for i in range(roster.size()):
		if i != 0 and i != 2:
			continue
		var eid: String = roster[i]
		print("[V1] ---- vs e%d %s ----" % [i + 1, eid])
		print("[V1]   %-28s %-10s %-10s %-10s %-8s %-6s %-6s %s" % [
			"kit", "attack", "EHP", "meas.DPS", "kills", "died", "sockt", "affix_bonuses(nz)"])
		var res: Array = []
		for k in kits:
			var r: Dictionary = _measure(sm, cm, rm, tz, zid, eid, k)
			res.append(r)
			print("[V1]   %-28s %-10.0f %-10.0f %-10.0f %-8d %-6s %-6d %s" % [
				String(k[0]), float(r["attack"]), float(r["ehp"]), float(r["dps"]),
				int(r["kills"]), str(r["died"]), int(r["sockets"]), String(r["afx"])])
		var A: Dictionary = res[0]
		var R: Dictionary = res[1]
		var B: Dictionary = res[2]
		var Bn: Dictionary = res[3]
		var Bx: Dictionary = res[4]
		print("[V1]   >> B vs Bn (is the weak kit inflated by the forced write?):  attack %s  EHP %s  DPS %s  kills %d vs %d" % [
			_rat(float(B["attack"]), float(Bn["attack"])), _rat(float(B["ehp"]), float(Bn["ehp"])),
			_rat(float(B["dps"]), float(Bn["dps"])), int(B["kills"]), int(Bn["kills"])])
		print("[V1]   >> gap with REALISTIC common (Bn) vs forced Rare (A):        DPS %s  kills %d vs %d" % [
			_rat(float(Bn["dps"]), float(A["dps"])), int(Bn["kills"]), int(A["kills"])])
		print("[V1]   >> gap with REALISTIC common (Bn) vs natural Rare (R):       DPS %s  kills %d vs %d" % [
			_rat(float(Bn["dps"]), float(R["dps"])), int(Bn["kills"]), int(R["kills"])])
		print("[V1]   >> counterfactual: if cfg9's forced affixes DID apply (Bx) vs A: DPS %s  kills %d vs %d" % [
			_rat(float(Bx["dps"]), float(A["dps"])), int(Bx["kills"]), int(A["kills"])])

func _rat(bv: float, av: float) -> String:
	if absf(av) < 1e-9:
		return "n/a"
	return "x%.3f" % (bv / av)

func _nz(d: Dictionary) -> String:
	var out: Array = []
	for k in d:
		if absf(float(d[k])) > 1e-9:
			out.append("%s=%.3f" % [String(k), float(d[k])])
	if out.is_empty():
		return "{}"
	return ", ".join(out)

func _measure(sm, cm, rm, tz: int, zid: String, eid: String, cfg: Array) -> Dictionary:
	var out: Dictionary = {}
	_build(sm, cm, rm, tz, zid, eid, cfg)
	out["attack"] = float(sm.attack)
	out["ehp"] = float(sm.max_hp) + float(sm.max_shield)
	out["afx"] = _nz(sm.affix_bonuses)
	out["gems"] = _nz(sm.gem_bonuses)
	var sk := 0
	for i in sm.loadout:
		var mid = sm.loadout[i]
		if mid and mid in sm.modules:
			sk += (sm.modules[mid].get("sockets", []) as Array).size()
	out["sockets"] = sk
	_cleanup(sm)

	var kills: Array = []
	var dps: Array = []
	var died := false
	for _t in range(TRIALS):
		_build(sm, cm, rm, tz, zid, eid, cfg)
		if cm.current_enemy == null:
			_cleanup(sm)
			continue
		var r: Dictionary = _fight(sm, cm)
		kills.append(int(r["kills"]))
		dps.append(float(r["dps"]))
		if bool(r["died"]):
			died = true
		_cleanup(sm)
	kills.sort()
	dps.sort()
	out["kills"] = int(kills[kills.size() / 2]) if not kills.is_empty() else 0
	out["dps"] = float(dps[dps.size() / 2]) if not dps.is_empty() else 0.0
	out["died"] = died
	return out

func _fight(sm, cm) -> Dictionary:
	var t := 0.0
	var k0: int = int(cm.total_kills)
	var dmg := 0.0
	var prev_pool: float = float(cm.enemy_hp) + float(cm.enemy_shield)
	var prev_k: int = int(cm.total_kills)
	while t < WINDOW:
		_kits(sm, cm)
		cm.process_tick(DT)
		t += DT
		var k: int = int(cm.total_kills)
		if k > prev_k:
			dmg += prev_pool
			prev_k = k
			prev_pool = float(cm.enemy_hp) + float(cm.enemy_shield)
		else:
			var pool: float = float(cm.enemy_hp) + float(cm.enemy_shield)
			if pool < prev_pool:
				dmg += prev_pool - pool
			prev_pool = pool
		if sm.current_hp <= 0 or not cm.in_combat:
			return {"kills": int(cm.total_kills) - k0, "died": true, "dps": dmg / maxf(0.1, t)}
	return {"kills": int(cm.total_kills) - k0, "died": false, "dps": dmg / WINDOW}

func _build(sm, cm, rm, tz: int, zid: String, eid: String, cfg: Array) -> void:
	GameState.hard_reset()
	cm.total_kills = 0
	var gz: int = int(cfg[1])
	var rar: int = int(cfg[2])
	var ht: int = int(cfg[3])
	var mode: int = int(cfg[4])
	for tid in rm.tech_tree:
		if int(rm.tech_tree[tid].get("tier", 99)) <= tz and not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)
	_set_hull(sm, ht)
	var e: Dictionary = cm.enemy_db.get(eid, {})
	var weak := _weak(e)
	var side_rar: int = 2 if rar == 4 else rar
	var wa: Array = W_AFF if mode != AFX_NONE else []
	var aa: Array = A_AFF if mode != AFX_NONE else []
	var sa: Array = S_AFF if mode != AFX_NONE else []
	_fill(sm, "battery", "z%d_battery" % gz, gz, min(side_rar, 3), [], mode)
	_fill(sm, "weapon", "z%d_%s" % [gz, SUFFIX[weak]], gz, rar, wa, mode)
	_fill(sm, "armor", "z%d_armor" % gz, gz, rar, aa, mode)
	_fill(sm, "shield", "z%d_shield" % gz, gz, rar, sa, mode)
	_fill(sm, "engine", "z%d_engine" % gz, gz, 0, [], mode)
	_fill(sm, "sensor", "z%d_sensor" % gz, gz, min(side_rar, 3), [], mode)
	_ammo_kits(sm, weak)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	cm.start_expedition(zid)
	cm.set_target_enemy(eid)

func _fill(sm, stype: String, base_id: String, zone: int, rarity: int, affixes: Array, mode: int) -> void:
	if not base_id in sm.modules:
		return
	for i in _slots(sm, stype):
		var cid := String(sm.generate_module_drop(base_id, rarity, zone))
		if cid == "":
			continue
		var m: Dictionary = sm.modules[cid]
		if not affixes.is_empty():
			if cid == base_id and not _base_backup.has(cid):
				_base_backup[cid] = (m.get("affixes", {}) as Dictionary).duplicate()
			var out := {}
			for p in affixes:
				var aid := String(p)
				if not sm.AFFIX_DB.has(aid):
					continue
				var lim: Array = sm.AFFIX_DB[aid].get("limit_to", [])
				if lim.is_empty() or (stype in lim):
					out[aid] = float(sm._roll_affix_value(aid, zone, 1.0)["value"])
			m["affixes"] = out
			if mode == AFX_FORCED_REG and not cid in sm.custom_modules:
				sm.custom_modules[cid] = m
				if not cid in _reg_ids:
					_reg_ids.append(cid)
		sm.equip_module(i, cid, true)

func _cleanup(sm) -> void:
	for mid in _base_backup:
		if mid in sm.modules:
			sm.modules[mid]["affixes"] = (_base_backup[mid] as Dictionary).duplicate()
	_base_backup.clear()
	for mid in _reg_ids:
		sm.custom_modules.erase(mid)
	_reg_ids.clear()

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
