extends Node

# Generic boss winnability: which HULL + drop RARITY clears a given zone boss?
# Combat power = gear only. Powers the ship properly, uses the weak-type weapon.

const AMMO := {"kinetic":"SlugT1", "energy":"CellT1", "explosive":"MissileT1"}
const TYPE_SUFFIX := {"kinetic":"kinetic", "energy":"energy", "explosive":"missile"}

func _ready() -> void:
	_run("mars_debris", "z3_boss_warmaster", 3, ["destroyer_hull", "cruiser_hull", "battlecruiser_hull"], [2, 3, 4])
	get_tree().quit()

func _run(zone: String, boss: String, ztier: int, hulls: Array, rarities: Array) -> void:
	var e: Dictionary = GameState.combat_manager.enemy_db.get(boss, {})
	var s: Dictionary = e.get("stats", {})
	print("BOSS %s hp=%s shld=%s atk=%s def=%s rk=%s re=%s rx=%s -> weak=%s" % [boss,
		str(s.get("hp")), str(s.get("max_shield")), str(s.get("atk")), str(s.get("def")),
		str(e.get("resist_k")), str(e.get("resist_e")), str(e.get("resist_x")), _weak(boss)])
	for r in rarities:
		for h in hulls:
			_test(h, zone, boss, ztier, int(r))

func _weak(boss: String) -> String:
	var e: Dictionary = GameState.combat_manager.enemy_db.get(boss, {})
	var rk = float(e.get("resist_k", 0)); var re = float(e.get("resist_e", 0)); var rx = float(e.get("resist_x", 0))
	var m = min(rk, min(re, rx))
	if m == rx: return "explosive"
	if m == re: return "energy"
	return "kinetic"

func _fund() -> void:
	var res = GameState.resources
	res.add_currency("credits", 200_000_000)
	for sym in ["Fe","Cu","Si","C","Steel","Circuit","Ti","AdvCircuit","Superalloy","QuantumCore",
			"SlugT1","CellT1","MissileT1"]:
		res.add_element(sym, 10_000_000)
	for tid in ["shipwright_1","shipwright_2","zone_2_access","zone_3_access","zone_4_access",
			"zone_5_access","combustion","kinetic_weapons","energy_weapons"]:
		if tid in GameState.research_manager.tech_tree and not tid in GameState.research_manager.unlocked_techs:
			GameState.research_manager.unlocked_techs.append(tid)

func _equip(idx: int, suffix: String, ztier: int, rarity: int) -> bool:
	var sm = GameState.shipyard_manager
	var base := ""
	for k in range(ztier, 0, -1):
		var cand := "z%d_%s" % [k, suffix]
		if cand in sm.modules:
			var rr = sm.modules[cand].get("research_req")
			if rr and not rr in GameState.research_manager.unlocked_techs:
				GameState.research_manager.unlocked_techs.append(rr)
			base = cand
			break
	if base == "":
		return false
	var mid: String = sm.generate_module_drop(base, rarity, ztier)
	if mid == "":
		mid = base
		if int(sm.module_inventory.get(mid, 0)) <= 0:
			sm.craft_module(mid)
	else:
		sm.module_inventory[mid] = int(sm.module_inventory.get(mid, 0)) + 1
	var ok: bool = sm.equip_module(idx, mid, true)
	sm.recalc_stats()
	return ok

func _test(hull: String, zone: String, boss: String, ztier: int, rarity: int) -> void:
	GameState.hard_reset()
	_fund()
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	if cm.in_combat: cm.retreat()
	sm.construct_hull(hull)
	sm.active_hull = hull
	var slots: Array = sm.hulls[hull].get("slots", [])
	for i in range(slots.size()):
		sm.loadout[i] = null
	sm.recalc_stats()
	var wsuffix: String = TYPE_SUFFIX[_weak(boss)]
	for i in range(slots.size()):
		if String(slots[i]) == "battery":
			_equip(i, "battery", ztier, rarity)
	var smap := {"weapon":wsuffix, "shield":"shield", "armor":"armor", "engine":"engine", "sensor":"sensor"}
	var nweap := 0
	for want in ["weapon", "shield", "armor", "engine", "sensor"]:
		for i in range(slots.size()):
			if String(slots[i]) != want or sm.loadout.get(i, null):
				continue
			_equip(i, String(smap[want]), ztier, rarity)
			if sm.energy_used > sm.energy_capacity:
				sm.unequip_slot(i); sm.recalc_stats()
			elif want == "weapon":
				nweap += 1
	for i in range(slots.size()):
		if String(slots[i]) == "weapon" and sm.loadout.get(i, null):
			var at := _weak(boss)
			sm.set_slot_ammo(i, AMMO.get(at, "SlugT1"))
	sm.recalc_stats()
	sm.repair_hull()
	cm.start_expedition(zone)
	cm.set_target_enemy(boss)
	var ok := (cm.current_enemy != null and String(cm.current_enemy.get("id","")) == boss)
	var won := false
	var rounds := 0
	var k0 := int(cm.boss_kills.get(boss, 0))
	if ok:
		for _i in range(14400):   # 3600s @ DT 0.25
			cm.process_tick(0.25)
			rounds += 1
			if int(cm.boss_kills.get(boss, 0)) > k0:
				won = true; break
			if not cm.in_combat:
				break
	var atk: int = int(sm.attack_kinetic) + int(sm.attack_energy) + int(sm.attack_explosive)
	print("  %-16s r%d | weap=%d eu=%d ec=%d hp=%d shld=%s atkSum=%d acc=%s | WON=%s t=%.0fs endHP=%d" % [
		hull, rarity, nweap, sm.energy_used, sm.energy_capacity, sm.max_hp, str(sm.get("max_shield")),
		atk, str(sm.get("accuracy")), str(won), rounds * 0.25, sm.current_hp])
	if cm.in_combat: cm.retreat()
