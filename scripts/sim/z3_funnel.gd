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
# v142b: raised 3 -> 9. Affixes now roll NATURALLY (random pool, 15% GA), so a
# single trial carries real roll variance. 3 trials was already noisy enough to
# flip untouched zones between runs; with honest rolls it would be worse.
const TRIALS := 9
var TZ := 3          # target zone (override: -- --zone=N)
var ZID := "mars_debris"

const SUFFIX := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}
const AMMO := {"kinetic": "Slug", "energy": "Cell", "explosive": "Missile"}
const T1 := ["CrackedCrimsonCore", "CrackedCobaltCore", "CrackedTopazCore"]
const T2 := ["StableCrimsonCore", "StableCobaltCore", "StableTopazCore"]
const T3 := ["PristineCrimsonCore", "PristineCobaltCore", "PristineTopazCore"]
const T1D := ["CrackedAmethystCore", "CrackedCrimsonCore", "CrackedCobaltCore"]
const T2D := ["StableAmethystCore", "StableCrimsonCore", "StableCobaltCore"]
const T3D := ["PristineAmethystCore", "PristineCrimsonCore", "PristineCobaltCore"]

# v142b AFFIX CORRECTION — the hand-picked W_AFF/A_AFF/S_AFF lists were REMOVED.
#
# They fed sm._roll_affix_value(aid, zone, 1.0) — that third arg is ga_chance, so
# 1.0 forced EVERY affix to range-max x GA_MULT. Config 1 (Rare N-1) therefore ran
# 3 guaranteed best-in-slot maximum Greater Affixes per module (~11x a real roll),
# while config 9's identical forced affixes were SILENTLY DISCARDED — a Common drop
# returns the base module id with no custom_modules entry, and recalc_stats only
# aggregates affixes from custom_modules. The probe was measuring a juiced Rare
# against a naked Common, which is what made them look equal at zones 4/6/8/10.
#
# generate_module_drop already rolls affixes correctly (2/3/4 for Rare/Legendary/
# Unique, random draw from the legal pool, 15% GA), so the fix is simply to STOP
# OVERRIDING IT. Do not reintroduce a forced-affix path here.
#
# Sockets are still forced to 3 on the gem configs: "Legendary + T3 cores" means a
# fully socketed kit by definition, so that is the config's intent, not a cheat.

# label, gear_zone, rarity, weapon-gems, defense-gems, forced_sockets
var CONFIGS := [
	["1 Rare  N-1     no cores", 2, 2, [], [], false],
	["5 Legend N-1    T1 cores", 2, 3, T1, T1D, false],
	["6 Legend N-1    T2 cores", 2, 3, T2, T2D, false],
	["7 Legend N-1    T3 cores", 2, 3, T3, T3D, false],
	["8 Unique N-1    no cores", 2, 4, [], [], false],
	["9 Common N      no cores", 3, 0, [], [], false],
	# v146: THE REAL PLAYER'S SITUATION, which every row above missed. Rows 1-8 put
	# old gear on the OLD hull, but the mission chain hands the player a tier-N hull
	# (frigate at m026b) BEFORE they craft tier-N modules — so they arrive in zone N
	# carrying zone N-1 gear on a zone N chassis. The hull adds HP and slots, so this
	# is strictly stronger than row 1 and it is what actually farms the zone.
	# Owner-reported: Legendary+Common Z1 weapons, Legendary+plain Z1 armor, 2 Rare Z1
	# shields cleared z2_ore_hauler (e4). Reproduce it before tuning anything.
	["A Rare  N-1  on hull N", 2, 2, [], [], false, 3],
	["B Legend N-1 on hull N", 2, 3, [], [], false, 3],
	# v149: the owner's four-config spec, ALL on the current-tier hull, because that
	# is the real player shape (the mission chain hands over a tier-N hull before
	# tier-N modules exist). Rows A/B already covered Rare and Legendary bare; these
	# two close the set. Row D (Unique N-1) is the one config that SHOULD farm --
	# it is the earned reward for clearing the previous zone's boss.
	["C Legend N-1 T1 hull N", 2, 3, T1, T1D, false, 3],
	["D Unique N-1     hull N", 2, 4, [], [], false, 3],
]

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--zone="):
			TZ = int(String(a).split("=")[1])
	for zid in cm.zones:
		if int(cm.zones[zid].get("difficulty", 0)) == TZ:
			ZID = String(zid)
			break
	# old-tier configs come from TZ-1; the "common" answer is TZ itself
	for c in CONFIGS:
		c[1] = (TZ if String(c[0]).begins_with("9") else TZ - 1)
		if c.size() > 6:
			c[6] = TZ   # A/B rows: gear from N-1, chassis from N
	print("[Z3F] ========== ZONE-%d GEAR FUNNEL (%s) ==========" % [TZ, ZID])
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
		if int(rm.tech_tree[tid].get("tier", 99)) <= TZ and not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)
	# v146: hull zone may differ from gear zone (cfg[6]); 0/absent = same as gear.
	var hz: int = int(cfg[6]) if cfg.size() > 6 and int(cfg[6]) > 0 else gz
	_set_hull(sm, hz)
	var e: Dictionary = cm.enemy_db.get(eid, {})
	var weak := _weak(e)
	# Unique has no engine/sensor/battery variant in game — those fall back to the
	# best obtainable (Rare now that battery/sensor drop), engine stays Common.
	var side_rar: int = 2 if rar == 4 else rar
	_fill(sm, "battery", "z%d_battery" % gz, gz, min(side_rar, 3), [], force)
	_fill(sm, "weapon", "z%d_%s" % [gz, SUFFIX[weak]], gz, rar, wg, force)
	_fill(sm, "armor", "z%d_armor" % gz, gz, rar, dg, force)
	_fill(sm, "shield", "z%d_shield" % gz, gz, rar, dg, force)
	_fill(sm, "engine", "z%d_engine" % gz, gz, 0, [], false)
	_fill(sm, "sensor", "z%d_sensor" % gz, gz, min(side_rar, 3), [], force)
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

func _fill(sm, stype: String, base_id: String, zone: int, rarity: int, gems: Array, force: bool) -> void:
	# Unique variants live under a different id.
	var bid := base_id
	if rarity == 4:
		# v142: uniques are now split by damage channel, so a Unique set can cover
		# the kin/nrg/exp cycle. Pick the variant matching the weak-type weapon the
		# caller already resolved (base_id is "z<N>_<kinetic|energy|missile>").
		var uid := ""
		if stype == "weapon":
			uid = "z%d_unique_%s" % [zone, base_id.split("_")[-1]]
		else:
			uid = "z%d_unique_%s" % [zone, stype]
		bid = uid if uid in sm.modules else base_id
	if not bid in sm.modules:
		return
	for i in _slots(sm, stype):
		var cid := String(sm.generate_module_drop(bid, rarity, zone))
		if cid == "":
			continue
		var m: Dictionary = sm.modules[cid]
		# NO affix override — generate_module_drop already rolled them naturally.
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
	# v150: was hardcoded "<Base>T2" at EVERY zone (the T1 fallback never fired —
	# SlugT2/CellT2/MissileT2 all exist in ELEMENT_NAMES). That made the funnel a
	# dishonest instrument once ammo bands landed: it over-fed Z1-Z3 (T2 at 1.10x
	# where the band is T1 at 1.00x) and under-fed Z7-Z10 (T2 at 1.10x where the
	# band is T3 at 1.20x). It now loads the band the zone is designed around, via
	# the single band map in ElementDB.
	#   Z1-Z3 -> T1 (1.00x) | Z4-Z6 -> T2 (1.10x) | Z7-Z10 -> T3 (1.20x) | Z11+ -> T4
	var band: String = ElementDB.get_ammo_band_for_zone(TZ)
	var ammo: String = "%s%s" % [AMMO[weak], band]
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
