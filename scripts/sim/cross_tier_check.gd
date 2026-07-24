extends Node
# ============================================================================
# PER-ZONE e3/e4 TUNER — correct framing: the two sides use DIFFERENT hulls.
#   WIN  = Tier-Z hull + Zone-Z Common          (legit Zone-Z player) -> must WIN
#   LOSE = Tier-(Z-1) hull + Zone-(Z-1) Leg+matrix (under-tier farmer)  -> must LOSE
# Sweeps an ATK-lethality factor (and optional HP factor) on the zone's e3/e4 to
# find where the gate lands. Real combat engine. Set TUNE_ZONE per pass.
#   run via backup-save -> real user-dir -> restore; hard_resets each fight.
# ============================================================================

const DT := 0.1
const TRIALS := 3
const SUFFIX := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}
const AMMO := {"kinetic": "Slug", "energy": "Cell", "explosive": "Missile"}
const CORES := ["PristineCrimsonCore", "PristineCobaltCore", "PristineTopazCore", "PristineAmethystCore"]

const TUNE_ZONE := 2
const GEAR_BUFFS := [1.0, 1.5, 2.0, 2.5]   # buff Z-N COMMON gear (dps + survivability)
const ENEMY_BUFFS := [1.5, 2.5, 3.5]       # buff Z-N e3/e4 (hp + atk)

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	var z := TUNE_ZONE
	var zid := _zone_of(cm, z)
	var ens: Array = cm.zones[zid].get("enemies", [])
	var e3 := String(ens[2]); var e4 := String(ens[3])
	print("[TUNE] ===== Zone %d: buff Z%d gear (G) x buff Z%d enemy (E), normal kits, %d trials =====" % [z, z, z, TRIALS])
	print("[TUNE] e3=%s e4=%s" % [e3, e4])
	print("[TUNE] WIN = Z%d Common xG (must WIN) | LOSE = Z%d Leg+matrix (unbuffed, must LOSE)" % [z, z-1])
	var lose := {"gz": z-1, "r": 3, "matrix": true, "ht": z, "res": z, "gearG": 1.0}
	for g in GEAR_BUFFS:
		for e in ENEMY_BUFFS:
			var win := {"gz": z, "r": 0, "matrix": false, "ht": z, "res": z, "gearG": g}
			var wc := _pair(sm, cm, rm, win, z, e3, e4, e)
			var lc := _pair(sm, cm, rm, lose, z, e3, e4, e)
			print("[TUNE] gearG%.1f enemyE%.1f | WIN e3 %s e4 %s || LOSE e3 %s e4 %s" % [g, e, wc[0], wc[1], lc[0], lc[1]])
	print("[TUNE] pick G/E where WIN 3/3 and LOSE 0/3 (both e3+e4).")
	get_tree().quit()

func _pair(sm, cm, rm, cfg, z, e3, e4, enemyE) -> Array:
	return [_cell(_trials(sm, cm, rm, cfg, e3, z, enemyE)), _cell(_trials(sm, cm, rm, cfg, e4, z, enemyE))]

func _weak(e) -> String:
	var rk := float(e.get("resist_k", 0.0)); var re := float(e.get("resist_e", 0.0)); var rx := float(e.get("resist_x", 0.0))
	var m := minf(rk, minf(re, rx))
	if m == rx: return "explosive"
	if m == re: return "energy"
	return "kinetic"

func _trials(sm, cm, rm, cfg, eid, zone, enemyE) -> Dictionary:
	var weak := _weak(cm.enemy_db.get(eid, {}))
	var wins := 0
	for _i in range(TRIALS):
		if String(_fight(sm, cm, rm, cfg, eid, zone, weak, enemyE).get("r","")) == "WIN":
			wins += 1
	return {"w": wins}

func _cell(r) -> String:
	return "%d/%d" % [int(r.get("w", 0)), TRIALS]

func _fight(sm, cm, rm, cfg, eid, zone, weak, enemyE) -> Dictionary:
	GameState.hard_reset()
	cm.boss_kills.clear(); cm.total_kills = 0
	for tid in rm.tech_tree:
		if int(rm.tech_tree[tid].get("tier", 99)) <= int(cfg["res"]) and not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)
	_set_hull(sm, int(cfg["ht"]))
	_equip(sm, int(cfg["gz"]), weak, int(cfg["r"]))
	if bool(cfg.get("matrix", false)):
		_socket_cores(sm)
	_ammo_kits(sm, weak, int(cfg["gz"]))
	sm.recalc_stats()
	# Buff the WIN gear: scale derived combat stats (dps + survivability) by gearG.
	var g: float = float(cfg.get("gearG", 1.0))
	if g != 1.0:
		sm.attack_kinetic *= g; sm.attack_energy *= g; sm.attack_explosive *= g
		sm.defense *= g; sm.max_shield *= g; sm.max_hp *= g
	sm.current_hp = sm.max_hp
	if sm.energy_used > sm.energy_capacity:
		return {"r": "UNPWR"}
	var st = cm.enemy_db[eid]["stats"]
	var oh = st.get("hp", 0); var oa = st.get("atk", 0)
	st["hp"] = oh * enemyE; st["atk"] = oa * enemyE
	cm.start_expedition(_zone_of(cm, zone))
	cm.set_target_enemy(eid)
	var res := {"r": "NOENT"}
	if cm.current_enemy != null and String(cm.current_enemy.get("id","")) == eid:
		var t := 0.0
		res = {"r": "TIME"}
		while t < 150.0:
			_kit(sm, cm)
			cm.process_tick(DT)
			t += DT
			if cm.total_kills > 0:
				res = {"r": "WIN"}; break
			if sm.current_hp <= 0 or not cm.in_combat:
				res = {"r": "LOSS"}; break
	st["hp"] = oh; st["atk"] = oa
	return res

func _zone_of(cm, n) -> String:
	for zid in cm.zones:
		if int(cm.zones[zid].get("difficulty", 0)) == n:
			return String(zid)
	return ""

func _set_hull(sm, tier) -> void:
	var hid := ""
	for h in sm.hulls:
		if int(sm.hulls[h].get("tier", 0)) == tier: hid = String(h); break
	if hid == "": hid = "corvette_hull"
	sm.active_hull = hid
	sm.loadout.clear(); sm.ammo_loadout.clear()
	sm.consumable_hull_slot = ""; sm.consumable_shield_slot = ""

func _slots(sm, stype) -> Array:
	var out := []; var slots: Array = sm.hulls.get(sm.active_hull, {}).get("slots", [])
	for i in range(slots.size()):
		if String(slots[i]) == stype: out.append(i)
	return out

func _equip(sm, gz, weak, rarity) -> void:
	_fill(sm, "battery", "z%d_battery" % clampi(gz,1,10), 3, gz)
	_fill(sm, "weapon", "z%d_%s" % [gz, SUFFIX[weak]], rarity, gz)
	_fill(sm, "armor", "z%d_armor" % gz, rarity, gz)
	_fill(sm, "shield", "z%d_shield" % gz, rarity, gz)

func _fill(sm, stype, base_id, rarity, zone) -> void:
	if not base_id in sm.modules: return
	for i in _slots(sm, stype):
		var cid := String(sm.generate_module_drop(base_id, rarity, zone))
		if cid != "": sm.equip_module(i, cid, true)

func _socket_cores(sm) -> void:
	for c in CORES:
		GameState.resources.add_element(c, 100)
	var ci := 0
	for slot in sm.loadout:
		var mid = sm.loadout[slot]
		if mid == null or String(mid) == "" or not (mid in sm.modules): continue
		var m = sm.modules[mid]
		if not m.has("sockets"): continue
		for i in range(m["sockets"].size()):
			if m["sockets"][i] == null:
				sm.insert_gem(String(mid), i, CORES[ci % CORES.size()])
				ci += 1

func _ammo_kits(sm, weak, gz) -> void:
	var atier := clampi((gz + 1) / 2, 1, 4)
	var ammo := "%sT%d" % [AMMO[weak], atier]
	if not ElementDB.ELEMENT_NAMES.has(ammo): ammo = "%sT1" % AMMO[weak]
	GameState.resources.add_element(ammo, 1000000)
	for i in _slots(sm, "weapon"): sm.ammo_loadout[i] = ammo
	GameState.resources.add_element("EmergencyPatch", 100000)
	GameState.resources.add_element("BasicBooster", 100000)
	sm.equip_consumable("hull", "EmergencyPatch")
	sm.equip_consumable("shield", "BasicBooster")

func _kit(sm, cm) -> void:
	if cm.consumable_cooldown > 0.0: return
	if sm.current_hp < sm.max_hp * 0.5 and sm.consumable_hull_slot != "":
		cm.use_manual_consumable("hull")
	elif cm.player_max_shield > 0 and cm.player_shield < cm.player_max_shield * 0.5 and sm.consumable_shield_slot != "":
		cm.use_manual_consumable("shield")
