extends Node
# ============================================================================
# IDLE-RULE REFUTATION PROBE — "one gear SET per zone", not "one per cell".
#
# z3_funnel.gd::_run calls _weak(e) PER CELL and re-equips the whole weapon
# suite + the matching ammo for every enemy. Before the v153 reassignment that
# was a no-op inside a zone (all 5 cells shared one weak channel), so row 9
# genuinely measured "a tier-matched Common SET farms the zone". After the
# reassignment e3/e4 have different weak channels from e1/e2, so the funnel is
# now silently swapping loadouts mid-zone.
#
# This probe re-runs the SAME row-9 config two ways:
#   WEAK  = per-cell optimal channel        (what z3_funnel measures)
#   PRIM  = pinned to the ZONE PRIMARY      (the channel e1/e2/boss want, i.e.
#           the one an arriving player actually crafted first)
# Everything else is byte-identical to z3_funnel: same hull, same rarity, same
# natural affix rolls, same ammo band, same consumable policy, same 9 trials.
#
#   Godot --headless --path <root> res://scenes/idle_single_set.tscn -- --zones=2,3
# ============================================================================

const DT := 0.1
const WINDOW := 180.0
const FARM_KILLS := 5
const TRIALS := 9
var ZONES: Array = [2, 3, 4, 5, 6, 7, 8, 9, 10]
var TZ := 2
var ZID := ""

const SUFFIX := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}
const AMMO := {"kinetic": "Slug", "energy": "Cell", "explosive": "Missile"}

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--zones="):
			ZONES = []
			for p in String(a).split("=")[1].split(","):
				ZONES.append(int(p))
	print("[ISS] ===== ONE-SET-PER-ZONE IDLE RULE CHECK (row 9 Common N, no cores) =====")
	print("[ISS] farm = >=%d kills in %ds, no death across %d trials. D = died." % [FARM_KILLS, int(WINDOW), TRIALS])
	for z in ZONES:
		TZ = int(z)
		ZID = ""
		for zid in cm.zones:
			if int(cm.zones[zid].get("difficulty", 0)) == TZ:
				ZID = String(zid)
				break
		if ZID == "":
			continue
		var roster: Array = cm.zones[ZID].get("enemies", [])
		var targets: Array = []
		for i in range(min(4, roster.size())):
			if not bool(cm.enemy_db.get(String(roster[i]), {}).get("is_boss", false)):
				targets.append(String(roster[i]))
		if targets.is_empty():
			continue
		var primary := _weak(cm.enemy_db.get(targets[0], {}))
		print("[ISS] --- Z%-2d %-18s primary(e1 weak) = %s" % [TZ, ZID, primary])
		for mode in ["WEAK", "PRIM", "MIX"]:
			var line := "[ISS] Z%-2d %-5s" % [TZ, mode]
			for eid in targets:
				var chan := primary if mode == "PRIM" else _weak(cm.enemy_db.get(eid, {}))
				if mode == "MIX":
					chan = "MIX"
				var r: Dictionary = _cell(sm, cm, rm, eid, chan)
				var mark := "D" if bool(r["died"]) else ("*" if int(r["kills"]) >= FARM_KILLS else " ")
				line += " %-16s" % ("%s:%d%s" % [chan.substr(0, 3).to_upper(), int(r["kills"]), mark])
			print(line)
	get_tree().quit(0)

func _cell(sm, cm, rm, eid: String, chan: String) -> Dictionary:
	var ks: Array = []
	var died := false
	for _t in range(TRIALS):
		var r: Dictionary = _run(sm, cm, rm, eid, chan)
		ks.append(int(r["kills"]))
		if bool(r["died"]):
			died = true
	ks.sort()
	return {"kills": ks[ks.size() / 2], "died": died}

func _run(sm, cm, rm, eid: String, chan: String) -> Dictionary:
	GameState.hard_reset()
	cm.total_kills = 0
	var gz: int = TZ
	var rar: int = 0
	for tid in rm.tech_tree:
		if int(rm.tech_tree[tid].get("tier", 99)) <= TZ and not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)
	_set_hull(sm, TZ)
	_fill(sm, "battery", "z%d_battery" % gz, gz, rar)
	if chan == "MIX":
		var cyc := ["kinetic", "energy", "explosive"]
		var ws := _slots(sm, "weapon")
		for j in range(ws.size()):
			var c2: String = String(cyc[j % 3])
			var cid := String(sm.generate_module_drop("z%d_%s" % [gz, SUFFIX[c2]], rar, gz))
			if cid != "":
				sm.equip_module(ws[j], cid, true)
	else:
		_fill(sm, "weapon", "z%d_%s" % [gz, SUFFIX[chan]], gz, rar)
	_fill(sm, "armor", "z%d_armor" % gz, gz, rar)
	_fill(sm, "shield", "z%d_shield" % gz, gz, rar)
	_fill(sm, "engine", "z%d_engine" % gz, gz, 0)
	_fill(sm, "sensor", "z%d_sensor" % gz, gz, rar)
	_ammo_kits(sm, chan)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	if sm.energy_used > sm.energy_capacity:
		return {"kills": 0, "died": false}
	cm.start_expedition(ZID)
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

func _fill(sm, stype: String, base_id: String, zone: int, rarity: int) -> void:
	if not base_id in sm.modules:
		return
	for i in _slots(sm, stype):
		var cid := String(sm.generate_module_drop(base_id, rarity, zone))
		if cid == "":
			continue
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

func _ammo_kits(sm, chan: String) -> void:
	var band: String = ElementDB.get_ammo_band_for_zone(TZ)
	var cyc := ["kinetic", "energy", "explosive"]
	var ws := _slots(sm, "weapon")
	for j in range(ws.size()):
		var c2: String = String(cyc[j % 3]) if chan == "MIX" else chan
		var ammo: String = "%s%s" % [AMMO[c2], band]
		if not ElementDB.ELEMENT_NAMES.has(ammo):
			ammo = "%sT1" % AMMO[c2]
		GameState.resources.add_element(ammo, 1000000)
		sm.ammo_loadout[ws[j]] = ammo
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
