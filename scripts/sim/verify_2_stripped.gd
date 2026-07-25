extends Node
# ============================================================================
# VERIFY-2: is the config1-vs-config9 collapse a PROBE ARTIFACT (forced max-GA
# affixes on the old kit only), or does something in resolve_damage /
# recalc_stats / spawn_enemy compress the tier gap on its own?
#
# Four kits per zone N, all fighting the SAME zone-N enemies:
#   AF = z3_funnel config 1 verbatim  (Rare N-1, FORCED max-GA W/A/S affixes)
#   AN = Rare N-1, NATURAL affix roll (what the real game gives)
#   A0 = Rare N-1, affixes STRIPPED to {} (pure base stats + rarity roll)
#   B  = config 9 (Common N, no affixes possible)
#
# If A0 vs B reproduces the ~2.78x per-module tier gap in kills/DPS, the
# collapse is entirely the forced affixes. If A0 still measures ~equal to B,
# something ELSE compresses it and the prior report is wrong.
#
#   Godot --headless --path <root> res://scenes/verify_2_stripped.tscn -- --zones=6,10 --window=180
# ============================================================================

const DT := 0.1
var WINDOW := 180.0
var ZONES: Array = [4, 6, 8, 10]
var TRIALS := 3

const SUFFIX := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}
const AMMO := {"kinetic": "Slug", "energy": "Cell", "explosive": "Missile"}
const W_AFF := ["dmg_injured", "servo_overclock", "shield_heal_on_hit"]
const A_AFF := ["resist_k", "flat_hp", "hull_heal_on_hit"]
const S_AFF := ["flat_shield", "shield_heal_on_hit", "capacitor_pulse"]

# mode: "forced" | "natural" | "strip" | "common"
var KITS := ["AF", "AN", "A0", "B"]

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--zones="):
			ZONES = []
			for p in s.split("=")[1].split(","):
				ZONES.append(int(p))
		elif s.begins_with("--window="):
			WINDOW = float(s.split("=")[1])
		elif s.begins_with("--trials="):
			TRIALS = int(s.split("=")[1])
	print("[V2] ===== STRIPPED-AFFIX TIER-GAP VERIFY  window=%ds trials=%d =====" % [int(WINDOW), TRIALS])
	print("[V2] AF=Rare N-1 forced max-GA | AN=Rare N-1 natural roll | A0=Rare N-1 NO affixes | B=Common N")
	for tz in ZONES:
		_run_zone(sm, cm, rm, int(tz))
	get_tree().quit(0)

func _run_zone(sm, cm, rm, tz: int) -> void:
	var zid := ""
	for z in cm.zones:
		if int(cm.zones[z].get("difficulty", 0)) == tz:
			zid = String(z)
			break
	if zid == "":
		return
	var roster: Array = cm.zones[zid].get("enemies", [])
	var targets: Array = []
	for i in range(min(4, roster.size())):
		if not bool(cm.enemy_db.get(String(roster[i]), {}).get("is_boss", false)):
			targets.append(String(roster[i]))
	print("\n[V2] ---------- ZONE %d (%s) ----------" % [tz, zid])
	# stat snapshot per kit (built once, vs e1 just for the stat print)
	for kit in KITS:
		var st: Dictionary = _build(sm, cm, rm, tz, kit, String(targets[0]))
		print("[V2] %-3s  atk=%-14s hp=%-12s shield=%-11s weapons=%d ivl=%.2f speed_mult=%.3f affix=%s" % [
			kit, _fmt(st["atk"]), _fmt(st["hp"]), _fmt(st["shield"]),
			int(st["nw"]), float(st["ivl"]), float(st["speed"]), str(st["affix"])])
	for ei in range(targets.size()):
		var eid := String(targets[ei])
		var line := "[V2] e%d %-24s" % [ei + 1, eid]
		var res := {}
		for kit in KITS:
			res[kit] = _cell(sm, cm, rm, tz, kit, eid)
		for kit in KITS:
			var r: Dictionary = res[kit]
			line += " %s=%d%s(dps %s)" % [kit, int(r["kills"]), ("D" if bool(r["died"]) else ""), _fmt(r["dps"])]
		# the two ratios that matter
		var b: Dictionary = res["B"]
		var a0: Dictionary = res["A0"]
		var af: Dictionary = res["AF"]
		var r_a0: float = (float(b["dps"]) / float(a0["dps"])) if float(a0["dps"]) > 0.0 else -1.0
		var r_af: float = (float(b["dps"]) / float(af["dps"])) if float(af["dps"]) > 0.0 else -1.0
		line += "  || B/A0 dps x%.2f  B/AF dps x%.2f" % [r_a0, r_af]
		print(line)

func _fmt(v) -> String:
	var f := float(v)
	if f >= 1e9: return "%.2fB" % (f / 1e9)
	if f >= 1e6: return "%.2fM" % (f / 1e6)
	if f >= 1e3: return "%.2fK" % (f / 1e3)
	return "%.1f" % f

func _cell(sm, cm, rm, tz: int, kit: String, eid: String) -> Dictionary:
	var ks: Array = []
	var ds: Array = []
	var died := false
	for _t in range(TRIALS):
		var r: Dictionary = _fight(sm, cm, rm, tz, kit, eid)
		ks.append(int(r["kills"]))
		ds.append(float(r["dps"]))
		if bool(r["died"]):
			died = true
	ks.sort()
	ds.sort()
	return {"kills": ks[ks.size() / 2], "dps": ds[ds.size() / 2], "died": died}

# Builds the kit and returns a stat snapshot. Leaves the ship equipped.
func _build(sm, cm, rm, tz: int, kit: String, eid: String) -> Dictionary:
	GameState.hard_reset()
	cm.total_kills = 0
	for tid in rm.tech_tree:
		if int(rm.tech_tree[tid].get("tier", 99)) <= tz and not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)
	var gz: int = tz if kit == "B" else tz - 1
	var rar: int = 0 if kit == "B" else 2
	var mode := "common" if kit == "B" else ("forced" if kit == "AF" else ("natural" if kit == "AN" else "strip"))
	_set_hull(sm, gz)
	var e: Dictionary = cm.enemy_db.get(eid, {})
	var weak := _weak(e)
	_fill(sm, "battery", "z%d_battery" % gz, gz, min(rar, 3), [], mode)
	_fill(sm, "weapon", "z%d_%s" % [gz, SUFFIX[weak]], gz, rar, W_AFF, mode)
	_fill(sm, "armor", "z%d_armor" % gz, gz, rar, A_AFF, mode)
	_fill(sm, "shield", "z%d_shield" % gz, gz, rar, S_AFF, mode)
	_fill(sm, "engine", "z%d_engine" % gz, gz, 0, [], "common")
	_fill(sm, "sensor", "z%d_sensor" % gz, gz, min(rar, 3), [], mode)
	_ammo_kits(sm, weak)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	# derived fire-rate view (mirrors combat_manager.process_tick)
	var speed: float = 1.0 + rm.get_efficiency_bonus("attack_speed")
	speed += float(sm.affix_bonuses.get("servo_overclock", 0.0))
	speed *= (1.0 + sm.attack_speed_bonus)
	var nz := {}
	for k in sm.affix_bonuses:
		if abs(float(sm.affix_bonuses[k])) > 0.0001:
			nz[k] = snappedf(float(sm.affix_bonuses[k]), 0.001)
	var nw := 0
	var ivl := 0.0
	for i in sm.loadout:
		var mid = sm.loadout[i]
		if mid and mid in sm.modules and sm.modules[mid].get("slot_type", "") == "weapon":
			nw += 1
			ivl += float(sm.modules[mid]["stats"].get("atk_interval", 2.5))
	return {"atk": sm.attack, "hp": sm.max_hp, "shield": sm.max_shield, "nw": nw,
		"ivl": (ivl / float(max(1, nw))), "speed": speed, "affix": nz}

func _fight(sm, cm, rm, tz: int, kit: String, eid: String) -> Dictionary:
	var zid := ""
	for z in cm.zones:
		if int(cm.zones[z].get("difficulty", 0)) == tz:
			zid = String(z)
			break
	_build(sm, cm, rm, tz, kit, eid)
	if sm.energy_used > sm.energy_capacity:
		return {"kills": 0, "dps": 0.0, "died": false}
	cm.start_expedition(zid)
	cm.set_target_enemy(eid)
	if cm.current_enemy == null:
		return {"kills": 0, "dps": 0.0, "died": false}
	var t := 0.0
	var k0: int = int(cm.total_kills)
	# Same target every respawn, so the pool is constant: total damage =
	# kills * pool + progress into the live one. No per-tick delta bookkeeping.
	var pool: float = float(cm.enemy_max_hp) + float(cm.enemy_max_shield)
	var died := false
	while t < WINDOW:
		_kits(sm, cm)
		cm.process_tick(DT)
		t += DT
		if sm.current_hp <= 0 or not cm.in_combat:
			died = true
			break
	var kills: int = int(cm.total_kills) - k0
	var partial: float = 0.0
	if cm.current_enemy and not died:
		partial = max(0.0, pool - (float(cm.enemy_hp) + float(cm.enemy_shield)))
	var dmg: float = float(kills) * pool + partial
	return {"kills": kills, "dps": dmg / max(0.1, t), "died": died}

func _fill(sm, stype: String, base_id: String, zone: int, rarity: int, affixes: Array, mode: String) -> void:
	if not base_id in sm.modules:
		return
	# guard: _fill on a COMMON writes into the SHARED base dict, so snapshot it
	var base_backup = (sm.modules[base_id].get("affixes", null))
	for i in _slots(sm, stype):
		var cid := String(sm.generate_module_drop(base_id, rarity, zone))
		if cid == "":
			continue
		var m: Dictionary = sm.modules[cid]
		if mode == "forced" and not affixes.is_empty():
			var out := {}
			for p in affixes:
				var aid := String(p)
				if not sm.AFFIX_DB.has(aid):
					continue
				var lim: Array = sm.AFFIX_DB[aid].get("limit_to", [])
				if lim.is_empty() or (stype in lim):
					out[aid] = float(sm._roll_affix_value(aid, zone, 1.0)["value"])
			m["affixes"] = out
			if cid in sm.custom_modules:
				sm.custom_modules[cid]["affixes"] = out
		elif mode == "strip":
			m["affixes"] = {}
			if cid in sm.custom_modules:
				sm.custom_modules[cid]["affixes"] = {}
		sm.equip_module(i, cid, true)
	# restore the shared base dict so a COMMON build can never leak affixes forward
	if base_backup == null:
		sm.modules[base_id].erase("affixes")
	else:
		sm.modules[base_id]["affixes"] = base_backup

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
