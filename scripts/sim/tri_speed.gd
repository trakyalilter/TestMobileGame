extends Node
# ============================================================================
# TRIANGLE SPEED DUEL (owner rule, 2026-07-26)
#
# The funnel (z3_funnel.gd) always equips the enemy's LOWEST-resist weapon, so
# it only ever measures the FAST path. It CANNOT tell you whether the resisted
# type is unfarmable or whether natural is meaningfully slower than weak.
#
# This probe fixes the gear (row 9 of the funnel: clean Common tier-N set on a
# tier-N hull, real consumables) and varies ONLY the weapon damage channel:
#
#   RESISTED = the channel with the enemy's highest resist  -> must NOT farm
#   NATURAL  = the channel at 0.0                           -> farms, slowly
#   WEAK     = the channel with the enemy's lowest resist    -> farms fast
#
# Reports kills in a 180s window and seconds-per-kill for each.
#
#   Godot --headless --path <root> res://scenes/tri_speed.tscn -- --zone=N
# ============================================================================

const DT := 0.1
const WINDOW := 180.0
const FARM_KILLS := 5
const TRIALS := 5

const SUFFIX := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}
const AMMO := {"kinetic": "Slug", "energy": "Cell", "explosive": "Missile"}

var ZONES := [2, 3, 4, 5, 6, 7, 8, 9, 10]

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--zone="):
			ZONES = [int(String(a).split("=")[1])]
	print("[TRI] ===== TRIANGLE SPEED DUEL — gear FIXED (Common tier-N, hull N), weapon channel VARIED =====")
	print("[TRI] farm bar = >=%d kills in %ds with no death. s/kill = %d/kills." % [FARM_KILLS, int(WINDOW), int(WINDOW)])
	print("[TRI] %-24s %-22s %-22s %-22s" % ["zone / enemy", "RESISTED", "NATURAL", "WEAK"])
	print("[TRI] " + "-".repeat(94))
	for tz in ZONES:
		var zid := ""
		for z in cm.zones:
			if int(cm.zones[z].get("difficulty", 0)) == tz:
				zid = String(z)
				break
		if zid == "":
			continue
		for eid in cm.zones[zid].get("enemies", []):
			var e: Dictionary = cm.enemy_db.get(String(eid), {})
			# Bosses are excluded: a clean Common set loses to every boss by design
			# (boss_gearcheck owns that invariant), so all three channels read "D"
			# and tell you nothing about relative speed.
			if e.is_empty() or bool(e.get("is_boss", false)):
				continue
			var roles := _roles(e)
			var line := "[TRI] %-24s" % ("Z%d %s" % [tz, String(e.get("name", eid)).substr(0, 18)])
			for role in ["resisted", "natural", "weak"]:
				var ch: String = String(roles[role])
				var r: Dictionary = _cell(sm, cm, rm, String(eid), zid, tz, ch)
				var k: int = int(r["kills"])
				var spk := ("%.0f" % (WINDOW / float(k))) if k > 0 else "inf"
				var mark := "D" if bool(r["died"]) else ("*" if k >= FARM_KILLS else " ")
				line += " %-22s" % ("%s %d%s (%ss/kill)" % [ch.substr(0, 3).to_upper(), k, mark, spk])
			print(line)
		print("[TRI] " + "-".repeat(94))
	print("[TRI] * = farms | D = DIED | RESISTED must be blank/D, NATURAL should farm slowly, WEAK fast.")
	get_tree().quit(0)

# Highest resist = resisted, lowest = weak, remainder = natural.
func _roles(e: Dictionary) -> Dictionary:
	var v := {"kinetic": float(e.get("resist_k", 0.0)), "energy": float(e.get("resist_e", 0.0)), "explosive": float(e.get("resist_x", 0.0))}
	var hi := "kinetic"
	var lo := "kinetic"
	for c in v:
		if float(v[c]) > float(v[hi]):
			hi = String(c)
		if float(v[c]) < float(v[lo]):
			lo = String(c)
	var mid := "kinetic"
	for c in v:
		if String(c) != hi and String(c) != lo:
			mid = String(c)
	return {"resisted": hi, "natural": mid, "weak": lo}

func _cell(sm, cm, rm, eid: String, zid: String, tz: int, chan: String) -> Dictionary:
	var ks: Array = []
	var died := false
	for _t in range(TRIALS):
		var r: Dictionary = _run(sm, cm, rm, eid, zid, tz, chan)
		ks.append(int(r["kills"]))
		if bool(r["died"]):
			died = true
	ks.sort()
	return {"kills": ks[ks.size() / 2], "died": died}

func _run(sm, cm, rm, eid: String, zid: String, tz: int, chan: String) -> Dictionary:
	GameState.hard_reset()
	cm.total_kills = 0
	for tid in rm.tech_tree:
		if int(rm.tech_tree[tid].get("tier", 99)) <= tz and not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)
	_set_hull(sm, tz)
	_fill(sm, "battery", "z%d_battery" % tz, tz)
	_fill(sm, "weapon", "z%d_%s" % [tz, SUFFIX[chan]], tz)
	_fill(sm, "armor", "z%d_armor" % tz, tz)
	_fill(sm, "shield", "z%d_shield" % tz, tz)
	_fill(sm, "engine", "z%d_engine" % tz, tz)
	_fill(sm, "sensor", "z%d_sensor" % tz, tz)
	_ammo_kits(sm, chan)
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

func _fill(sm, stype: String, base_id: String, zone: int) -> void:
	if not base_id in sm.modules:
		return
	for i in _slots(sm, stype):
		var cid := String(sm.generate_module_drop(base_id, 0, zone))
		if cid == "":
			continue
		sm.equip_module(i, cid, true)

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
	var ammo := "%sT2" % AMMO[chan]
	if not ElementDB.ELEMENT_NAMES.has(ammo):
		ammo = "%sT1" % AMMO[chan]
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
