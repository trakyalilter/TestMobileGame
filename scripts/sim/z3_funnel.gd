extends Node
# ============================================================================
# ZONE-3 GEAR FUNNEL (v142) — owner spec, 2026-07-25.
#
# Fights Zone 3 e1/e2/e3/e4 with 9 gear configurations. Always consumables
# (real cooldown honoured — use_manual_consumable enforces it).
#
#   1 Rare Z2,      no cores          6 Legendary Z2 + T2
#   2 Rare Z2     + T1 cores          7 Legendary Z2 + T3
#   3 Rare Z2     + T2 cores          8 Unique Z2,   no cores  <- must farm ALL
#   4 Rare Z2     + T3 cores          9 Common Z3,   no cores  <- must farm ALL
#   5 Legendary Z2 + T1 cores
#
# Design frame (owner): T3 cores are 9 Cracked + Lira per Pristine, so a full
# T3 matrix is a REAL grind — a player who paid it has EARNED a tier skip and
# should not be forced to craft the next zone's commons. So high-core configs
# farming Z3 is a PASS, not a leak. The gate must bite on the cheap configs.
#
# NOTE (surfaced by this probe): sockets are only granted at Legendary+ in
# generate_module_drop, so configs 2-4 (Rare + cores) cannot exist in game.
# They are measured with FORCED sockets and tagged [!] so the comparison is
# still informative — decide whether Rare should get sockets.
#
#   Godot --headless --path <root> res://scenes/z3_funnel.tscn
# ============================================================================

const DT := 0.1
const WINDOW := 180.0
const FARM_KILLS := 5
const TRIALS := 3
const ZID := "mars_debris"

const SUFFIX := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}
const AMMO := {"kinetic": "Slug", "energy": "Cell", "explosive": "Missile"}
const T1 := ["CrackedCrimsonCore", "CrackedCobaltCore", "CrackedTopazCore"]
const T2 := ["StableCrimsonCore", "StableCobaltCore", "StableTopazCore"]
const T3 := ["PristineCrimsonCore", "PristineCobaltCore", "PristineTopazCore"]
const T1D := ["CrackedAmethystCore", "CrackedCrimsonCore", "CrackedCobaltCore"]
const T2D := ["StableAmethystCore", "StableCrimsonCore", "StableCobaltCore"]
const T3D := ["PristineAmethystCore", "PristineCrimsonCore", "PristineCobaltCore"]
const W_AFF := ["dmg_injured", "servo_overclock", "shield_heal_on_hit"]
const A_AFF := ["resist_k", "flat_hp", "hull_heal_on_hit"]
const S_AFF := ["flat_shield", "shield_heal_on_hit", "capacitor_pulse"]

# label, gear_zone, rarity, weapon-gems, defense-gems, forced_sockets
var CONFIGS := [
	["1 Rare Z2       no cores", 2, 2, [], [], false],
	["2 Rare Z2       T1 cores", 2, 2, T1, T1D, true],
	["3 Rare Z2       T2 cores", 2, 2, T2, T2D, true],
	["4 Rare Z2       T3 cores", 2, 2, T3, T3D, true],
	["5 Legendary Z2  T1 cores", 2, 3, T1, T1D, false],
	["6 Legendary Z2  T2 cores", 2, 3, T2, T2D, false],
	["7 Legendary Z2  T3 cores", 2, 3, T3, T3D, false],
	["8 Unique Z2     no cores", 2, 4, [], [], false],
	["9 Common Z3     no cores", 3, 0, [], [], false],
]

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	print("[Z3F] ================ ZONE-3 GEAR FUNNEL ================")
	_consumable_check(sm)
	print("[Z3F] farm = >=%d kills in %ds, no death. cell = kills (D=died)." % [FARM_KILLS, int(WINDOW)])
	var roster: Array = cm.zones[ZID].get("enemies", [])
	var targets: Array = []
	for i in range(min(4, roster.size())):
		if not bool(cm.enemy_db.get(String(roster[i]), {}).get("is_boss", false)):
			targets.append(String(roster[i]))
	var hdr := "[Z3F] %-26s" % "config"
	for i in range(targets.size()):
		hdr += " %-14s" % ("e%d" % (i + 1))
	print(hdr)
	print("[Z3F] " + "-".repeat(84))
	for cfg in CONFIGS:
		var line := "[Z3F] %-26s" % String(cfg[0])
		for eid in targets:
			var r: Dictionary = _cell(sm, cm, rm, eid, cfg)
			var mark := "D" if bool(r["died"]) else ("*" if int(r["kills"]) >= FARM_KILLS else " ")
			line += " %-14s" % ("%d%s%s" % [int(r["kills"]), mark, ("[!]" if bool(cfg[5]) else "")])
		print(line)
	print("[Z3F] " + "-".repeat(84))
	print("[Z3F] * = farms (>=%d kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)" % FARM_KILLS)
	get_tree().quit(0)

# Deadlock guard: the kits the funnel leans on must be craftable in this era.
func _consumable_check(sm) -> void:
	var pm = GameState.processing_manager
	for kit in ["EmergencyPatch", "BasicBooster"]:
		var found := ""
		for rid in pm.recipes:
			var r: Dictionary = pm.recipes[rid]
			if (r.get("output", {}) as Dictionary).has(kit):
				found = String(rid)
				break
		if found == "":
			print("[Z3F] CONSUMABLE %s: NO RECIPE — deadlock risk" % kit)
			continue
		var rec: Dictionary = pm.recipes[found]
		print("[Z3F] CONSUMABLE %-14s recipe=%-24s lvl_req=%-3d research=%s" % [
			kit, found, int(rec.get("level_req", 1)), String(rec.get("research_req", "-"))])

func _cell(sm, cm, rm, eid: String, cfg: Array) -> Dictionary:
	var ks: Array = []
	var died := false
	for _t in range(TRIALS):
		var r: Dictionary = _run(sm, cm, rm, eid, cfg)
		ks.append(int(r["kills"]))
		if bool(r["died"]):
			died = true
	ks.sort()
	return {"kills": ks[ks.size() / 2], "died": died}

func _run(sm, cm, rm, eid: String, cfg: Array) -> Dictionary:
	GameState.hard_reset()
	cm.total_kills = 0
	var gz: int = int(cfg[1])
	var rar: int = int(cfg[2])
	var wg: Array = cfg[3]
	var dg: Array = cfg[4]
	var force: bool = bool(cfg[5])
	for tid in rm.tech_tree:
		if int(rm.tech_tree[tid].get("tier", 99)) <= 3 and not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)
	_set_hull(sm, gz)
	var e: Dictionary = cm.enemy_db.get(eid, {})
	var weak := _weak(e)
	# Unique has no engine/sensor/battery variant in game — those fall back to the
	# best obtainable (Rare now that battery/sensor drop), engine stays Common.
	var side_rar: int = 2 if rar == 4 else rar
	_fill(sm, "battery", "z%d_battery" % gz, gz, min(side_rar, 3), [], [], force)
	_fill(sm, "weapon", "z%d_%s" % [gz, SUFFIX[weak]], gz, rar, W_AFF, wg, force)
	_fill(sm, "armor", "z%d_armor" % gz, gz, rar, A_AFF, dg, force)
	_fill(sm, "shield", "z%d_shield" % gz, gz, rar, S_AFF, dg, force)
	_fill(sm, "engine", "z%d_engine" % gz, gz, 0, [], [], false)
	_fill(sm, "sensor", "z%d_sensor" % gz, gz, min(side_rar, 3), [], [], force)
	_ammo_kits(sm, weak)
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

func _fill(sm, stype: String, base_id: String, zone: int, rarity: int, affixes: Array, gems: Array, force: bool) -> void:
	# Unique variants live under a different id.
	var bid := base_id
	if rarity == 4:
		var uid := "z%d_unique_%s" % [zone, ("weapon" if stype == "weapon" else stype)]
		bid = uid if uid in sm.modules else base_id
	if not bid in sm.modules:
		return
	for i in _slots(sm, stype):
		var cid := String(sm.generate_module_drop(bid, rarity, zone))
		if cid == "":
			continue
		var m: Dictionary = sm.modules[cid]
		if not affixes.is_empty():
			var out := {}
			for p in affixes:
				var aid := String(p)
				if not sm.AFFIX_DB.has(aid):
					continue
				var lim: Array = sm.AFFIX_DB[aid].get("limit_to", [])
				if lim.is_empty() or (stype in lim):
					out[aid] = float(sm._roll_affix_value(aid, zone, 1.0)["value"])
			m["affixes"] = out
		if not gems.is_empty():
			if force or (m.get("sockets", []) as Array).size() < 3:
				m["sockets"] = [null, null, null]
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
	# v142: auto_repair_20 (tier 2, reachable at the Z2->Z3 transition) fires at
	# 20% HP. Modelling 80% flattered the kits and hid real idle deaths.
	if sm.current_hp < sm.max_hp * 0.20 and sm.consumable_hull_slot != "":
		cm.use_manual_consumable("hull")
	if cm.player_shield < cm.player_max_shield * 0.30 and sm.consumable_shield_slot != "":
		cm.use_manual_consumable("shield")
