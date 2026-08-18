extends SceneTree
## Phase 7 verification: warp Cryo unlock + infrastructure v109 rebalance +
## shipyard polish. PASS/FAIL printed per gate.

var _pass := 0
var _fail := 0

func _ck(name: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else: _fail += 1
	print("[%s] %s%s" % ["PASS" if ok else "FAIL", name, ("  " + detail) if detail != "" else ""])

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var gs = root.get_node("GameState")
	gs.hard_reset()

	# ===== Gate 3: Warp cryo unlock =====
	_ck("cryo locked at start", not gs.cryo_unlocked)
	# Give the player enough to warp (score gate is earned credits + buildings).
	gs.lifetime_credits = 600000000   # plenty of warp shards
	var g1: int = gs.execute_warp()
	_ck("warp grants shards", g1 > 0, "gains=%d" % g1)
	_ck("warp sets cryo_unlocked", gs.cryo_unlocked)
	# v113 deleted the Cryo Shard Pistol and its first-warp grant. The warp reward
	# is the cryo ARMAMENTS research line (asserted below), not a free weapon —
	# this used to assert the grant, which is why a correct engine read as broken.
	_ck("the retired cryo pistol is gone from the module table",
		not (root.get_node("GameData")).MODULES.has("cryo_shard_pistol"))
	_ck("warping grants no phantom pistol",
		int(gs.module_inventory.get("cryo_shard_pistol", 0)) == 0,
		"have %d" % int(gs.module_inventory.get("cryo_shard_pistol", 0)))
	# requires_warp tech now available (find one).
	var rw_tech := ""
	for tid in (root.get_node("GameData")).RESEARCH:
		if bool((root.get_node("GameData")).RESEARCH[tid].get("requires_warp", false)):
			rw_tech = tid
			break
	if rw_tech != "":
		# Strip any non-warp prereqs so we isolate the warp gate.
		var t: Dictionary = (root.get_node("GameData")).RESEARCH[rw_tech]
		var parent: String = t.get("parent", "")
		if parent != "": gs.unlocked_research[parent] = true
		for rt in t.get("req_tech", []):
			if str(rt) != "": gs.unlocked_research[str(rt)] = true
		gs.credits = 999999999
		for item in t.get("items", {}):
			gs.add_resource(item, int(t["items"][item]) * 2)   # afford the tech's mat cost
		_ck("requires_warp tech available after warp", gs.research_available(rw_tech), rw_tech)
		# Sanity: with cryo locked, the same tech must NOT be available.
		var saved_flag: bool = gs.cryo_unlocked
		gs.cryo_unlocked = false
		_ck("requires_warp tech locked when cryo locked", not gs.research_available(rw_tech))
		gs.cryo_unlocked = saved_flag
	# A second warp must not conjure one either, and must keep the unlock.
	gs.lifetime_credits = 600000000
	gs.execute_warp()
	_ck("re-warping still grants no pistol",
		int(gs.module_inventory.get("cryo_shard_pistol", 0)) == 0)
	_ck("cryo stays unlocked across warps", gs.cryo_unlocked)

	# ===== Gate 4a: Infra eng-scale clamp =====
	gs.hard_reset()
	gs.skills["fabrication"] = gs.xp_for_level(99)
	var es: float = gs._eng_scale("auto_smelter")
	_ck("eng-scale clamped <=3.0 at fab 99", es <= 3.0 + 0.001 and es > 1.0, "got %.3f" % es)
	# Newly-added buildings get the eng bonus.
	_ck("titanium_refinery eng-scaled", gs._eng_scale("titanium_refinery") > 1.0)
	_ck("superalloy_forge eng-scaled", gs._eng_scale("superalloy_forge") > 1.0)
	_ck("adv_circuit_foundry eng-scaled", gs._eng_scale("adv_circuit_foundry") > 1.0)
	_ck("non-listed building not eng-scaled", abs(gs._eng_scale("solar_panel") - 1.0) < 0.001)

	# ===== Gate 4b: Diminishing returns =====
	var dr10: float = gs._dr_units(10)
	var dr100: float = gs._dr_units(100)
	_ck("DR linear up to knee (10->10)", abs(dr10 - 10.0) < 0.001, "%.2f" % dr10)
	_ck("DR saturates (100 effective << 100)", dr100 < 25.0 and dr100 > 10.0, "%.2f" % dr100)
	_ck("DR < linear for large count", dr100 < 100.0)

	# ===== Gate 4c: Ore throttle =====
	_ck("ore extractor throttled 0.5", abs(gs._ore_throttle("copper_mine") - 0.5) < 0.001)
	_ck("non-ore building not throttled", abs(gs._ore_throttle("auto_smelter") - 1.0) < 0.001)

	# ===== Gate 4d: no material upkeep — the grid is the only throttle =====
	# v120 (desktop parity) deleted building upkeep outright. This gate used to
	# call _apply_upkeep and assert Water/Dirt drained; the function no longer
	# exists, so the whole gate errored. The contract now is the inverse: idle
	# stores must NOT be touched, and production must throttle on energy alone.
	gs.hard_reset()
	gs.buildings = {"solar_panel": 5}
	gs.add_resource("Water", 1000)
	gs.add_resource("Dirt", 1000)
	var w0: float = gs.amount("Water")
	var d0: float = gs.amount("Dirt")
	gs._tick_infra(60.0)
	_ck("generators drain no upkeep materials",
		gs.amount("Water") == w0 and gs.amount("Dirt") == d0,
		"Water %.0f->%.0f, Dirt %.0f->%.0f" % [w0, gs.amount("Water"), d0, gs.amount("Dirt")])
	_ck("the upkeep path is gone from the engine", not gs.has_method("_apply_upkeep"))
	# A consumer with no generator behind it runs at reduced efficiency; adding
	# generation restores it. That is the only throttle left.
	gs.hard_reset()
	var consumer := ""
	for bid in (root.get_node("GameData")).BUILDINGS:
		var bd: Dictionary = (root.get_node("GameData")).BUILDINGS[bid]
		if float(bd.get("energy_cons", 0.0)) > 0.0 and not bd.get("yield", {}).is_empty():
			consumer = String(bid)
			break
	if consumer == "":
		_ck("an energy-consuming producer exists to test the grid throttle", false)
	else:
		var cons_each: float = float(((root.get_node("GameData")).BUILDINGS[consumer] as Dictionary).get("energy_cons", 0.0))
		var gen_each: float = float(((root.get_node("GameData")).BUILDINGS["solar_panel"] as Dictionary).get("energy_gen", 1.0))
		gs.buildings = {consumer: 5}
		gs.infra_energy = 0.0
		var starved: float = gs._infra_energy_step(1.0)
		# Size the array to the load rather than guessing a count — the heaviest
		# consumers draw thousands of kW each.
		gs.buildings["solar_panel"] = int(ceil(cons_each * 5.0 / gen_each)) + 10
		gs.infra_energy = 0.0
		var fed: float = gs._infra_energy_step(1.0)
		_ck("a starved grid throttles production", starved < 1.0, "eff=%.2f" % starved)
		_ck("a fed grid runs at full rate", fed >= 0.999, "eff=%.2f with %d panels" % [fed, int(gs.buildings["solar_panel"])])

	# ===== Gate 4e: production halved by DR/ore vs old (eng-scale nerf) =====
	# An ore extractor producing N effective units yields half of raw.
	gs.hard_reset()
	gs.buildings = {"copper_mine": 1}
	var cm: Dictionary = (root.get_node("GameData")).BUILDINGS.get("copper_mine", {})
	if not cm.get("yield", {}).is_empty():
		# Drive one batch and confirm output is ~0.5x raw single yield.
		var sym: String = cm["yield"].keys()[0]
		var raw: float = float(cm["yield"][sym])
		gs._build_frac.clear()
		# accumulate enough batches to bank a whole unit, count them
		var b0: float = gs.amount(sym)
		for _i in range(100):
			gs._produce_batch("copper_mine", 1, cm, {})
		var made: float = gs.amount(sym) - b0
		# 100 batches * raw * 0.5 (ore) * 1 unit; allow eng/warp = 1 at base
		var expected: float = 100.0 * raw * 0.5
		_ck("ore-throttle halves yield", abs(made - expected) <= expected * 0.05 + 1.0,
			"made %.1f vs ~%.1f" % [made, expected])

	# ===== Gate 5: Repair scales with missing HP =====
	gs.hard_reset()
	gs.active_hull = "corvette_hull"
	var maxhp: float = gs.combat_max_hp()
	gs.combat_hp = maxhp
	_ck("repair cost 0 at full HP", gs.repair_cost() == 0, "got %d" % gs.repair_cost())
	gs.combat_hp = maxhp * 0.5
	var half_cost: int = gs.repair_cost()
	var full: int = int(gs.REPAIR_COST["corvette_hull"])
	_ck("repair ~half at 50%% HP", abs(half_cost - full / 2) <= full / 20 + 1,
		"got %d (full %d)" % [half_cost, full])
	gs.combat_hp = 1.0
	_ck("repair near full when nearly dead", gs.repair_cost() > full * 0.9, "got %d" % gs.repair_cost())
	# New hulls have nonzero tier-scaled costs, monotonic.
	var order := ["corvette_hull", "frigate_hull", "destroyer_hull", "cruiser_hull",
		"battlecruiser_hull", "capital_hull", "carrier_hull", "dreadnought_hull",
		"titan_hull", "leviathan_hull"]
	var mono := true
	var prev := 0
	var all_nonzero := true
	for h in order:
		var c: int = int(gs.REPAIR_COST.get(h, 0))
		if c <= 0: all_nonzero = false
		if c < prev: mono = false
		prev = c
	_ck("all 10 hulls have nonzero repair cost", all_nonzero)
	_ck("repair costs monotonic by tier", mono, str(order.map(func(h): return gs.REPAIR_COST.get(h, 0))))

	# ===== Gate 6: Loadout presets save/load =====
	gs.hard_reset()
	for mid in ["z1_battery", "z1_battery", "z1_kinetic", "z1_energy", "z1_shield", "z1_armor"]:
		gs.module_inventory[mid] = int(gs.module_inventory.get(mid, 0)) + 1
		gs.equip_module(mid)
	gs.add_resource("SlugT1", 999)
	for k in gs.loadout:
		var wm: Dictionary = gs.module_def(gs.loadout[k])
		if wm.get("slot", "") == "weapon" and float(wm.get("stats", {}).get("atk_kinetic", 0)) > 0:
			gs.set_ammo(str(k), "SlugT1")
	var saved_loadout: Dictionary = gs.loadout.duplicate(true)
	var saved_ammo: Dictionary = gs.ammo_loadout.duplicate(true)
	# Slot 2, not slot 1: under v134g the ACTIVE slot (1 by default) mirrors every
	# live edit, so stripping the ship legitimately rewrites it. A round-trip has
	# to be tested on a slot that is not the mirror — which is what this gate used
	# to get wrong.
	_ck("save preset slot 2", gs.save_loadout_preset(2))
	# Change loadout: strip everything.
	for slot in gs.loadout.keys().duplicate():
		gs.unequip_slot(slot)
	_ck("loadout cleared", gs.loadout.is_empty())
	_ck("the active slot mirrored the strip (v134g)", gs.is_loadout_preset_empty(1))
	_ck("a non-active preset is untouched by live edits",
		not gs.is_loadout_preset_empty(2))
	var res: Dictionary = gs.load_loadout_preset(2)
	_ck("load preset restores modules", int(res.get("loaded", 0)) == saved_loadout.size(),
		"loaded %d/%d" % [int(res.get("loaded", 0)), saved_loadout.size()])
	_ck("the loaded preset survives its own load", not gs.is_loadout_preset_empty(2))
	# Loading ANOTHER preset must not wipe the one that was active.
	gs.save_loadout_preset(3)
	gs.load_loadout_preset(3)
	_ck("loading a different preset leaves the previous one intact",
		not gs.is_loadout_preset_empty(2))
	# Same module set -> same slot keys; loadout should match.
	var match_ok: bool = gs.loadout.size() == saved_loadout.size()
	for k in saved_loadout:
		if gs.loadout.get(k, "") != saved_loadout[k]:
			match_ok = false
	_ck("restored loadout matches saved", match_ok)
	var ammo_ok := true
	for k in saved_ammo:
		if gs.ammo_loadout.get(k, "") != saved_ammo[k]:
			ammo_ok = false
	_ck("restored ammo matches saved", ammo_ok and not saved_ammo.is_empty())
	_ck("clear preset slot 2", gs.clear_loadout_preset(2) and gs.is_loadout_preset_empty(2))

	print("\n=== Phase 7: %d PASS, %d FAIL ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
