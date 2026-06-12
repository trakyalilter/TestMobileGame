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
	var before_cryo: int = int(gs.module_inventory.get("cryo_shard_pistol", 0))
	var g1: int = gs.execute_warp()
	_ck("warp grants shards", g1 > 0, "gains=%d" % g1)
	_ck("warp sets cryo_unlocked", gs.cryo_unlocked)
	var after1: int = int(gs.module_inventory.get("cryo_shard_pistol", 0))
	_ck("first warp grants 1 cryo pistol", after1 == before_cryo + 1, "have %d" % after1)
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
	# Second warp must NOT duplicate the pistol.
	gs.lifetime_credits = 600000000
	gs.execute_warp()
	var after2: int = int(gs.module_inventory.get("cryo_shard_pistol", 0))
	_ck("re-warp does not duplicate pistol", after2 == 1, "have %d" % after2)

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

	# ===== Gate 4d: Upkeep drains Water/Dirt =====
	gs.hard_reset()
	gs.buildings = {"solar_panel": 5}
	gs.add_resource("Water", 1000)
	gs.add_resource("Dirt", 1000)
	var w0: float = gs.amount("Water")
	var d0: float = gs.amount("Dirt")
	var consumed: Dictionary = gs._apply_upkeep(1)
	_ck("upkeep drains Water", gs.amount("Water") < w0 and consumed.has("Water"),
		"-%.1f" % (w0 - gs.amount("Water")))
	_ck("upkeep drains Dirt", gs.amount("Dirt") < d0 and consumed.has("Dirt"),
		"-%.1f" % (d0 - gs.amount("Dirt")))
	# Upkeep never goes negative when short.
	gs.resources["Water"] = 1.0
	gs._apply_upkeep(100)
	_ck("upkeep never negative", gs.amount("Water") >= 0.0, "Water=%.2f" % gs.amount("Water"))

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
	_ck("save preset slot 1", gs.save_loadout_preset(1))
	# Change loadout: strip everything.
	for slot in gs.loadout.keys().duplicate():
		gs.unequip_slot(slot)
	_ck("loadout cleared", gs.loadout.is_empty())
	var res: Dictionary = gs.load_loadout_preset(1)
	_ck("load preset restores modules", int(res.get("loaded", 0)) == saved_loadout.size(),
		"loaded %d/%d" % [int(res.get("loaded", 0)), saved_loadout.size()])
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
	_ck("clear preset slot 1", gs.clear_loadout_preset(1) and gs.is_loadout_preset_empty(1))

	print("\n=== Phase 7: %d PASS, %d FAIL ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
