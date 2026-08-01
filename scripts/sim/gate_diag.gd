extends Node
# v142 focused diagnostic: dump the ACTUAL in-sim state of both kits for one
# transition, plus the enemy they fight. Two tuning passes barely moved the farm
# sim, so the model is wrong somewhere — this prints ground truth instead.

const SUFFIX := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}
const BEST_WEAPON := ["dmg_injured", "servo_overclock", "shield_heal_on_hit"]
const RES_W := ["ResonantCrimsonCore", "ResonantCobaltCore", "ResonantTopazCore"]

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	var hull_n := 2
	var zid := "mars_debris"
	var eid := "z3_derelict_frigate"
	print("[DIAG] ===== Z2 maxed vs Z3 common, target %s =====" % eid)
	_dump(sm, cm, rm, hull_n, zid, eid, true)
	_dump(sm, cm, rm, hull_n, zid, eid, false)
	get_tree().quit(0)

func _dump(sm, cm, rm, hull_n: int, zid: String, eid: String, maxed: bool) -> void:
	GameState.hard_reset()
	var zone_n: int = hull_n + 1
	for tid in rm.tech_tree:
		if int(rm.tech_tree[tid].get("tier", 99)) <= zone_n and not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)
	var e_def: Dictionary = cm.enemy_db.get(eid, {})
	var weak := "kinetic"
	var bv: float = float(e_def.get("resist_k", 0.0))
	if float(e_def.get("resist_e", 0.0)) < bv:
		bv = float(e_def.get("resist_e", 0.0)); weak = "energy"
	if float(e_def.get("resist_x", 0.0)) < bv:
		weak = "explosive"
	var wsuf := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}[weak]
	var want := clampi(hull_n if maxed else zone_n, 1, 10)
	for h in sm.hulls:
		if int(sm.hulls[h].get("tier", 0)) == want:
			sm.active_hull = String(h)
			break
	sm.loadout.clear()
	sm.ammo_loadout.clear()
	var gear_n: int = hull_n if maxed else zone_n
	var rarity: int = 3 if maxed else 0
	print("[DIAG]   weak=%s weapon=z%d_%s hull_tier=%d" % [weak, gear_n, wsuf, want])
	var eq := 0
	var tried := 0
	for stype in ["battery", "weapon", "armor", "shield"]:
		var base_id := "z%d_%s" % [gear_n, (wsuf if stype == "weapon" else stype)]
		if not base_id in sm.modules:
			print("[DIAG]   MISSING base module %s" % base_id)
			continue
		for i in _slots(sm, stype):
			tried += 1
			var cid := String(sm.generate_module_drop(base_id, rarity, gear_n))
			if cid == "":
				print("[DIAG]   generate_module_drop RETURNED EMPTY for %s" % base_id)
				continue
			if maxed and stype == "weapon":
				var m: Dictionary = sm.modules[cid]
				var out := {}
				for aid in BEST_WEAPON:
					var cfg: Dictionary = sm.AFFIX_DB[aid]
					var lim: Array = cfg.get("limit_to", [])
					if lim.is_empty() or (stype in lim):
						out[aid] = float(sm._roll_affix_value(aid, gear_n, 1.0)["value"])
				m["affixes"] = out
				m["sockets"] = [null, null, null]
				for gi in range(3):
					GameState.resources.add_element(RES_W[gi], 1)
					sm.insert_gem(cid, gi, RES_W[gi])
			if sm.equip_module(i, cid, true):
				eq += 1
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	var label := ("MAXED z%d LEG" % gear_n) if maxed else ("COMMON z%d" % gear_n)
	print("[DIAG] %-14s hull=%s equipped=%d/%d atk=%.0f def=%.0f hp=%.0f shield=%.0f pwr=%d/%d" % [
		label, sm.active_hull, eq, tried, sm.attack, sm.defense, sm.max_hp, sm.max_shield,
		int(sm.energy_used), int(sm.energy_capacity)])
	# Now spawn the enemy and read ITS effective stats after steepening.
	cm.start_expedition(zid)
	cm.set_target_enemy(eid)
	if cm.current_enemy != null:
		print("[DIAG]                enemy hp=%.0f atk=%.0f def=%.0f shield=%.0f th=%d p_shield=%.0f" % [
			float(cm.enemy_max_hp), float(cm.current_enemy.get("atk", 0)),
			float(cm.current_enemy.get("def", 0)), float(cm.enemy_max_shield),
			int(cm.current_enemy.get("tier_hardened", -1)), float(cm.player_max_shield)])

func _slots(sm, stype: String) -> Array:
	var out: Array = []
	var slots: Array = sm.hulls.get(sm.active_hull, {}).get("slots", [])
	for i in range(slots.size()):
		if String(slots[i]) == stype:
			out.append(i)
	return out
