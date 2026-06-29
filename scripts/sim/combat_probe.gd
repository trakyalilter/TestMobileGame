extends Node

# Boss winnability MATRIX: win-RATE per HULL × drop RARITY × consumables, over N
# seeded trials/cell. Combat power = gear only; uses the weak-type weapon, powers
# the ship, optionally equips repair kits (auto_repair_80 + 35% hull/shield, 10s cd).
#
# Sweeps Z4-Z10 on the ATTAINABLE matched hull per zone (tier N hull for zone N —
# the one zone_N_access unlocks, which is also what the battery-power system is
# balanced for). Z3 was tuned separately. Seed is per (hull,rarity,trial) and
# EXCLUDES the cons flag, so each trial's drop rolls are identical for the cons=N
# vs cons=Y pair → a clean controlled A/B. (Assumes module rolls use the global RNG.)

const AMMO := {"kinetic":"SlugT1", "energy":"CellT1", "explosive":"MissileT1"}
const TYPE_SUFFIX := {"kinetic":"kinetic", "energy":"energy", "explosive":"missile"}
const TRIALS := 20
const MAX_TICKS := 14400          # 3600s hard cap @ DT 0.25 (design TTK target ~13min)
const STALL_TICKS := 1200         # 300s with no enemy-HP drop -> unwinnable, score a loss

# Per zone: the matched/attainable top hull (tier == zone difficulty).
const ZONES := [
	{"zone": "cryofield",      "boss": "z4_boss_overseer",     "t": 4,  "hull": "cruiser_hull"},
	{"zone": "sector_alpha",   "boss": "z5_boss_harbinger",    "t": 5,  "hull": "battlecruiser_hull"},
	{"zone": "sector_beta",    "boss": "z6_boss_colossus",     "t": 6,  "hull": "capital_hull"},
	{"zone": "sector_gamma",   "boss": "z7_boss_sovereign",    "t": 7,  "hull": "carrier_hull"},
	{"zone": "sector_delta",   "boss": "z8_boss_warden",       "t": 8,  "hull": "dreadnought_hull"},
	{"zone": "sector_zeta",    "boss": "z9_boss_patient_zero", "t": 9,  "hull": "titan_hull"},
	{"zone": "sector_epsilon", "boss": "z10_boss_leviathan",   "t": 10, "hull": "leviathan_hull"},
]

const MODE := "matrix"   # "matrix" (full win-rate) | "tune" (2D ATK×HP gate sweep) | "diag" (ship state)
const ATK_MULTS := [1.4, 1.9, 2.5]   # ×current (v1-baked) boss atk — search UP for the cons=Y~80% gate
const HP_MULTS := [0.70, 1.0]        # ×current baked hp (1.0 keeps v1's ×0.50; 0.70 → ~×0.35 of original)
const TUNE_TRIALS := 10

func _ready() -> void:
	match MODE:
		"diag":
			for z in ZONES:
				_diag(String(z["hull"]), String(z["zone"]), String(z["boss"]), int(z["t"]), 4)
		"tune":
			_tune()
		_:
			for z in ZONES:
				_run(String(z["zone"]), String(z["boss"]), int(z["t"]), [String(z["hull"])], [2, 3, 4])
	get_tree().quit()

# Per zone, sweep boss-HP multipliers at LEGENDARY (the target rarity) and report
# cons=N / cons=Y win-rate + median kill time, so the knee that lands the matched
# hull in the "~50% bare / ~70-80% kits" band is visible in one run. HP is the
# primary lever: it cuts the DPS-wall AND shortens the fight (less exposure ->
# better survival). atk stays at 1.0 here; if a zone's cons=N stays far below
# cons=Y even at deep HP trims, that zone also needs an ATK trim.
func _tune() -> void:
	for z in ZONES:
		var zone := String(z["zone"])
		var boss := String(z["boss"])
		var ztier := int(z["t"])
		var hull := String(z["hull"])
		var e: Dictionary = GameState.combat_manager.enemy_db.get(boss, {})
		var base_atk := int(e.get("stats", {}).get("atk", 0))
		var base_hp := int(e.get("stats", {}).get("hp", 0))
		print("[TUNE] === Z%d %s vs %s  (v1 baked hp=%d atk=%d) ===" % [ztier, hull, boss, base_hp, base_atk])
		for hp_raw in HP_MULTS:
			for atk_raw in ATK_MULTS:
				var hm := float(hp_raw)
				var am := float(atk_raw)
				var ly := 0   # LEGENDARY + kits (target ~80%)
				var ln := 0   # LEGENDARY bare   (target ~25%)
				var ry := 0   # RARE + kits      (target ~30% — the gate)
				var lyt := []
				for t in range(TUNE_TRIALS):
					var a: Dictionary = _test(hull, zone, boss, ztier, 3, true, t, hm, am)
					if a["won"]:
						ly += 1
						lyt.append(a["t"])
					var b: Dictionary = _test(hull, zone, boss, ztier, 3, false, t, hm, am)
					if b["won"]:
						ln += 1
					var c: Dictionary = _test(hull, zone, boss, ztier, 2, true, t, hm, am)
					if c["won"]:
						ry += 1
				print("[TUNE] Z%-2d hp=%-9d atk=%-7d | LEG kits %3d%% bare %3d%% med=%ss | RARE kits %3d%%" % [
					ztier, int(base_hp * hm), int(base_atk * am),
					int(round(100.0 * ly / TUNE_TRIALS)), int(round(100.0 * ln / TUNE_TRIALS)), _med(lyt),
					int(round(100.0 * ry / TUNE_TRIALS))])

# Builds the matched hull at the given rarity and reports WHY a cell wins or
# loses: power (eu>ec or weapons stripped), dps (weapons fire but weak), or
# survival (dies fast). Sample = 200s of real combat. UNIQUE (r4) by default.
func _diag(hull: String, zone: String, boss: String, ztier: int, rarity: int) -> void:
	_build_ship(hull, zone, boss, ztier, rarity, false, 0)
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var slots: Array = sm.hulls[hull].get("slots", [])
	var wslots := 0
	var nweap := 0
	for i in range(slots.size()):
		if String(slots[i]) == "weapon":
			wslots += 1
			if sm.loadout.get(i, null) != null:
				nweap += 1
	cm.start_expedition(zone)
	cm.set_target_enemy(boss)
	var pinned: bool = (cm.current_enemy != null and String(cm.current_enemy.get("id","")) == boss)
	var ehp_max: float = float(cm.enemy_max_hp)
	var ehp0: float = float(cm.enemy_hp)
	var alive := true
	var steps := 800   # 200s @ DT 0.25
	for _i in range(steps):
		cm.process_tick(0.25)
		if not cm.in_combat:
			alive = false
			break
		if int(cm.boss_kills.get(boss, 0)) > 0:
			break
	var ehp1: float = float(cm.enemy_hp)
	var dps: float = (ehp0 - ehp1) / (steps * 0.25)
	var kill_need: float = (ehp_max / dps) if dps > 1.0 else -1.0
	print("[DIAG] Z%-2d %-18s r%d pinned=%s | ship eu=%d ec=%d weap=%d/%d atkK=%d atkE=%d atkX=%d hp=%d shld=%d | boss ehp=%d atk=%d def=%d | dps~%.0f killNeed~%.0fs pHPend=%d alive=%s" % [
		ztier, hull, rarity, str(pinned),
		sm.energy_used, sm.energy_capacity, nweap, wslots,
		int(sm.attack_kinetic), int(sm.attack_energy), int(sm.attack_explosive), int(sm.max_hp), int(sm.get("max_shield")),
		int(ehp_max), int(cm.current_enemy.get("stats", {}).get("atk", 0)) if cm.current_enemy else 0,
		int(cm.current_enemy.get("stats", {}).get("def", 0)) if cm.current_enemy else 0,
		dps, kill_need, int(sm.current_hp), str(alive)])
	if cm.in_combat: cm.retreat()

func _run(zone: String, boss: String, ztier: int, hulls: Array, rarities: Array) -> void:
	var e: Dictionary = GameState.combat_manager.enemy_db.get(boss, {})
	var s: Dictionary = e.get("stats", {})
	print("[MTX] Z%d BOSS %s hp=%s shld=%s atk=%s def=%s rk=%s re=%s rx=%s -> weak=%s" % [ztier, boss,
		str(s.get("hp")), str(s.get("max_shield")), str(s.get("atk")), str(s.get("def")),
		str(e.get("resist_k")), str(e.get("resist_e")), str(e.get("resist_x")), _weak(boss)])
	for r in rarities:
		for h in hulls:
			var nw := 0
			var yw := 0
			var nt := []
			var yt := []
			for t in range(TRIALS):
				var rn: Dictionary = _test(h, zone, boss, ztier, int(r), false, t)
				if rn["won"]:
					nw += 1
					nt.append(rn["t"])
				var ry: Dictionary = _test(h, zone, boss, ztier, int(r), true, t)
				if ry["won"]:
					yw += 1
					yt.append(ry["t"])
			print("[MTX] Z%-2d %-18s r%d | cons=N %2d/%d %3d%% medKill=%ss | cons=Y %2d/%d %3d%% medKill=%ss" % [
				ztier, h, r, nw, TRIALS, int(round(100.0 * nw / TRIALS)), _med(nt),
				yw, TRIALS, int(round(100.0 * yw / TRIALS)), _med(yt)])

func _weak(boss: String) -> String:
	var e: Dictionary = GameState.combat_manager.enemy_db.get(boss, {})
	var rk = float(e.get("resist_k", 0)); var re = float(e.get("resist_e", 0)); var rx = float(e.get("resist_x", 0))
	var m = min(rk, min(re, rx))
	if m == rx: return "explosive"
	if m == re: return "energy"
	return "kinetic"

func _med(a: Array) -> String:
	if a.is_empty():
		return "-"
	a.sort()
	return "%d" % int(a[a.size() / 2])

func _fund() -> void:
	var res = GameState.resources
	res.add_currency("credits", 2_000_000_000)
	# Common mats + ammo + repair kits + every exotic HULL-cost material (so
	# construct_hull succeeds for capital/carrier/dreadnought/titan/leviathan).
	for sym in ["Fe","Cu","Si","C","Steel","Circuit","Ti","AdvCircuit","Superalloy","QuantumCore",
			"SlugT1","CellT1","MissileT1","AdvMaintenanceKit","ZeroPoint",
			"VoidArtifact","ExoticMatter","Neutronium","PrimordialShard"]:
		res.add_element(sym, 100_000_000)
	# Hull + zone-module access research (zone_N_access gates the tier-N hull AND
	# the zN modules). _equip also auto-unlocks each module's own research_req.
	for tid in ["shipwright_1","shipwright_2","combustion","kinetic_weapons","energy_weapons",
			"zone_2_access","zone_3_access","zone_4_access","zone_5_access","zone_6_access",
			"zone_7_access","zone_8_access","zone_9_access","zone_10_access"]:
		if not tid in GameState.research_manager.unlocked_techs:
			GameState.research_manager.unlocked_techs.append(tid)
	# auto-consume tier — threshold 0.8 (heal whenever HP/shield < 80%).
	for tid in ["auto_repair_20","auto_repair_40","auto_repair_60","auto_repair_80"]:
		if not tid in GameState.research_manager.unlocked_techs:
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

func _build_ship(hull: String, zone: String, boss: String, ztier: int, rarity: int, use_cons: bool, trial: int) -> void:
	GameState.hard_reset()
	_fund()
	seed(hash("%s_%d_%d" % [hull, rarity, trial]))   # paired across cons; reproducible
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
	for want in ["weapon", "shield", "armor", "engine", "sensor"]:
		for i in range(slots.size()):
			if String(slots[i]) != want or sm.loadout.get(i, null):
				continue
			_equip(i, String(smap[want]), ztier, rarity)
			if sm.energy_used > sm.energy_capacity:
				sm.unequip_slot(i); sm.recalc_stats()
	for i in range(slots.size()):
		if String(slots[i]) == "weapon" and sm.loadout.get(i, null):
			var at := _weak(boss)
			sm.set_slot_ammo(i, AMMO.get(at, "SlugT1"))
	sm.recalc_stats()
	sm.repair_hull()
	if use_cons:
		sm.equip_consumable("hull", "AdvMaintenanceKit")
		sm.equip_consumable("shield", "ZeroPoint")
	else:
		sm.unequip_consumable("hull")
		sm.unequip_consumable("shield")

func _test(hull: String, zone: String, boss: String, ztier: int, rarity: int, use_cons: bool, trial: int, hp_mult: float = 1.0, atk_mult: float = 1.0) -> Dictionary:
	_build_ship(hull, zone, boss, ztier, rarity, use_cons, trial)
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	cm.start_expedition(zone)
	cm.set_target_enemy(boss)
	var ok := (cm.current_enemy != null and String(cm.current_enemy.get("id","")) == boss)
	# Tuning override: simulate a boss HP/ATK trim without editing the data, so the
	# sweep can find the right numbers to bake in. Enemy hp + atk are read live.
	if ok and (hp_mult != 1.0 or atk_mult != 1.0):
		cm.current_enemy["max_hp"] = int(cm.current_enemy["max_hp"] * hp_mult)
		cm.current_enemy["atk"] = int(cm.current_enemy["atk"] * atk_mult)
		cm.enemy_hp = float(cm.current_enemy["max_hp"])
		cm.enemy_max_hp = cm.enemy_hp
	var won := false
	var rounds := 0
	var k0 := int(cm.boss_kills.get(boss, 0))
	var last_ehp: float = float(cm.enemy_hp)
	var stall := 0
	if ok:
		for _i in range(MAX_TICKS):
			cm.process_tick(0.25)
			rounds += 1
			if int(cm.boss_kills.get(boss, 0)) > k0:
				won = true
				break
			if not cm.in_combat:
				break
			if float(cm.enemy_hp) < last_ehp:
				last_ehp = float(cm.enemy_hp)
				stall = 0
			else:
				stall += 1
				if stall >= STALL_TICKS:
					break
	if cm.in_combat: cm.retreat()
	return {"won": won, "t": int(rounds * 0.25)}
