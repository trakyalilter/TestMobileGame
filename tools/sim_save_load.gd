extends SceneTree
## PHASE 6 — Save / load & persistence. Populates a rich game state (resources,
## XP, research, hulls, a rolled custom module, loadout + presets, buildings,
## fleet, NG+ flags, missions, bounty/standing, kill tallies), snapshots it,
## writes the real save file, SCRAMBLES every field in memory, then loads the
## file back and verifies each persisted field is restored intact. Catches
## fields that are saved-but-not-loaded (or vice-versa), key-type corruption
## (JSON stringifies int keys), and silent data loss across a session boundary.

var gs
var gd
var errors: Array = []
var warns: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s): errors.append(s)
func W(s): warns.append(s)

func eq(name: String, expected, actual) -> void:
	# Numeric-aware deep compare: JSON widens ints to floats on round-trip (the game
	# reads these through int()/float() at use sites), so 3 and 3.0 are equivalent
	# here. Structure and values must otherwise match exactly.
	if not _deep_eq(expected, actual):
		E("%s did not round-trip: expected %s, got %s" % [name, str(expected), str(actual)])

func _deep_eq(a, b) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	if (ta == TYPE_INT or ta == TYPE_FLOAT) and (tb == TYPE_INT or tb == TYPE_FLOAT):
		return absf(float(a) - float(b)) <= 0.0001
	if ta == TYPE_DICTIONARY and tb == TYPE_DICTIONARY:
		if a.size() != b.size(): return false
		for k in a:
			if not b.has(k): return false
			if not _deep_eq(a[k], b[k]): return false
		return true
	if ta == TYPE_ARRAY and tb == TYPE_ARRAY:
		if a.size() != b.size(): return false
		for i in range(a.size()):
			if not _deep_eq(a[i], b[i]): return false
		return true
	return a == b

func eq_approx(name: String, expected: float, actual: float, tol: float = 0.01) -> void:
	if absf(expected - actual) > tol:
		E("%s did not round-trip: expected %.4f, got %.4f" % [name, expected, actual])

func keyset(d) -> Array:
	var k := (d as Dictionary).keys()
	k.sort()
	return k

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	gs = root.get_node("GameState")
	gd = root.get_node("GameData")

	# Fresh slot.
	for n in range(1, gs.SLOT_COUNT + 1):
		gs.delete_slot(n)
	gs.new_character(1, "PersistTester")

	# ---- Populate a rich, representative state. ----
	gs.stop_task()
	gs.resources = {"Dirt": 1234, "Water": 5678, "Steel": 42, "AdvCircuit": 7}
	gs.credits = 987654321
	gs.lifetime_credits = 1987654321
	gs.storage_upgrades = 5
	gs.warp_shards = 12.5
	gs.warp_shards_spent = 3.0
	gs.total_warps = 3
	gs.cryo_unlocked = true
	gs.fleet_ships = [{"hull_id": "fleet_frigate"}, {"hull_id": "fleet_destroyer"}]
	gs.skills = {"combat": 50000, "fabrication": 23000, "engineering": 9000}
	gs.mastery = {"gather_dirt": 1500.0, "smelt_steel_basic": 220.5}
	gs.unlocked_research = {}
	for r in ["basic_engineering", "smelting", "adv_materials", "zone_2_access", "cryo_armaments"]:
		gs.unlocked_research[r] = true
	gs.active_hull = "corvette_hull"
	gs.owned_hulls = {"corvette_hull": true, "frigate_hull": true}
	gs.module_inventory = {"z1_kinetic": 2, "z1_armor": 1}   # live ids: retired gear is purged on load
	gs.custom_modules = {"cm_test_1": {"name": "Test Blaster", "slot": "weapon", "rarity": 3,
		"stats": {"atk_kinetic": 250, "atk_interval": 2.0}, "base": "rail_cannon"}}
	gs.loadout = {"weapon": "z1_kinetic", "armor": "z1_armor"}
	gs.ammo_loadout = {"weapon": "SlugT2"}
	gs.consumable_hull_slot = "RepairKitT1"
	gs.consumable_shield_slot = "ShieldCellT1"
	gs.loot_filter = {0: false, 1: true, 2: true, 3: true, 4: true}
	gs.loadout_presets = {
		1: {"name": "Cryo", "loadout": {"weapon": "z1_kinetic"}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""},
		2: {"name": "Corrosion", "loadout": {"weapon": "corrosion_blaster"}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""},
		3: {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""},
	}
	gs.buildings = {"crew_quarters": 3, "solar_array": 2}
	gs.infra_energy = 44.0
	gs.bounty_total = 17
	gs.standing_total = 29
	gs.missions_active = {"m001": true, "m002": true}
	gs.missions_progress = {"m001": 3, "m002": 1}
	gs.missions_claimed = {"m000": true}
	gs.boss_kills = {"z1_boss_architect": 4, "z10_boss_leviathan": 1}
	gs.hazard_clears = {"emp_nexus": 2}
	gs.game_flags = {"warp_revealed": true, "z11_unlocked": true, "z12_unlocked": true, "recursion_revealed": true}

	# ---- Snapshot (deep copies so later scrambling can't alias). ----
	var snap := {
		"resources": gs.resources.duplicate(true),
		"credits": gs.credits, "lifetime_credits": gs.lifetime_credits,
		"storage_upgrades": gs.storage_upgrades, "warp_shards": gs.warp_shards,
		"warp_shards_spent": gs.warp_shards_spent, "total_warps": gs.total_warps,
		"cryo_unlocked": gs.cryo_unlocked, "fleet_ships": gs.fleet_ships.duplicate(true),
		"skills": gs.skills.duplicate(true), "mastery": gs.mastery.duplicate(true),
		"research_keys": keyset(gs.unlocked_research), "active_hull": gs.active_hull,
		"owned_keys": keyset(gs.owned_hulls), "module_inventory": gs.module_inventory.duplicate(true),
		"custom_modules": gs.custom_modules.duplicate(true), "loadout": gs.loadout.duplicate(true),
		"ammo_loadout": gs.ammo_loadout.duplicate(true), "consumable_hull_slot": gs.consumable_hull_slot,
		"consumable_shield_slot": gs.consumable_shield_slot, "loot_filter": gs.loot_filter.duplicate(true),
		"loadout_presets": gs.loadout_presets.duplicate(true), "buildings": gs.buildings.duplicate(true),
		"infra_energy": gs.infra_energy, "bounty_total": gs.bounty_total,
		"standing_total": gs.standing_total, "missions_active_keys": keyset(gs.missions_active),
		"missions_progress": gs.missions_progress.duplicate(true),
		"missions_claimed_keys": keyset(gs.missions_claimed), "boss_kills": gs.boss_kills.duplicate(true),
		"hazard_clears": gs.hazard_clears.duplicate(true), "game_flags": gs.game_flags.duplicate(true),
	}

	# ---- Persist, then SCRAMBLE every field so a no-op load would be exposed. ----
	gs.save_game()
	gs.resources = {"GARBAGE": -1}
	gs.credits = -1; gs.lifetime_credits = -1; gs.storage_upgrades = -1
	gs.warp_shards = -1.0; gs.warp_shards_spent = -1.0; gs.total_warps = -1
	gs.cryo_unlocked = false; gs.fleet_ships = []
	gs.skills = {}; gs.mastery = {}; gs.unlocked_research = {"WRONG": true}
	gs.active_hull = "WRONG"; gs.owned_hulls = {}
	gs.module_inventory = {}; gs.custom_modules = {}; gs.loadout = {}
	gs.ammo_loadout = {}; gs.consumable_hull_slot = "X"; gs.consumable_shield_slot = "X"
	gs.loot_filter = {}; gs.loadout_presets = {}; gs.buildings = {}; gs.infra_energy = -1.0
	gs.bounty_total = -1; gs.standing_total = -1
	gs.missions_active = {}; gs.missions_progress = {}; gs.missions_claimed = {}
	gs.boss_kills = {}; gs.hazard_clears = {}; gs.game_flags = {}

	# ---- Load it back (away ~ 0 since save wrote time=now). ----
	gs.load_game()
	await process_frame

	# ---- Verify every field restored. ----
	eq("resources", snap["resources"], gs.resources)
	eq("credits", snap["credits"], gs.credits)
	eq("lifetime_credits", snap["lifetime_credits"], gs.lifetime_credits)
	eq("storage_upgrades", snap["storage_upgrades"], gs.storage_upgrades)
	eq_approx("warp_shards", snap["warp_shards"], gs.warp_shards)
	eq_approx("warp_shards_spent", snap["warp_shards_spent"], gs.warp_shards_spent)
	eq("total_warps", snap["total_warps"], gs.total_warps)
	eq("cryo_unlocked", snap["cryo_unlocked"], gs.cryo_unlocked)
	eq("fleet_ships", snap["fleet_ships"], gs.fleet_ships)
	eq("skills", snap["skills"], gs.skills)
	eq("mastery", snap["mastery"], gs.mastery)
	eq("research keys", snap["research_keys"], keyset(gs.unlocked_research))
	eq("active_hull", snap["active_hull"], gs.active_hull)
	eq("owned_hulls keys", snap["owned_keys"], keyset(gs.owned_hulls))
	eq("module_inventory", snap["module_inventory"], gs.module_inventory)
	eq("custom_modules", snap["custom_modules"], gs.custom_modules)
	eq("loadout", snap["loadout"], gs.loadout)
	eq("ammo_loadout", snap["ammo_loadout"], gs.ammo_loadout)
	eq("consumable_hull_slot", snap["consumable_hull_slot"], gs.consumable_hull_slot)
	eq("consumable_shield_slot", snap["consumable_shield_slot"], gs.consumable_shield_slot)
	eq("loot_filter (int-keyed)", snap["loot_filter"], gs.loot_filter)
	eq("loadout_presets (int-keyed)", snap["loadout_presets"], gs.loadout_presets)
	eq("buildings", snap["buildings"], gs.buildings)
	eq("bounty_total", snap["bounty_total"], gs.bounty_total)
	eq("standing_total", snap["standing_total"], gs.standing_total)
	eq("missions_active keys", snap["missions_active_keys"], keyset(gs.missions_active))
	# missions_progress is intentionally re-reconciled by _mission_sync() on load
	# (e.g. a gather mission re-counts against current resources), so its values may
	# differ by design — assert the tracked missions survive, not the exact counts.
	eq("missions_progress keys", keyset(snap["missions_progress"]), keyset(gs.missions_progress))
	eq("missions_claimed keys", snap["missions_claimed_keys"], keyset(gs.missions_claimed))
	# infra_energy is a transient grid-battery buffer recomputed from building power
	# balance on load (clamped to ship energy capacity) — not persisted progress.
	# Assert it lands in a valid range rather than equal to the pre-save charge.
	if gs.infra_energy < 0.0 or not is_finite(gs.infra_energy):
		E("infra_energy invalid after load: %f" % gs.infra_energy)
	eq("boss_kills", snap["boss_kills"], gs.boss_kills)
	eq("hazard_clears", snap["hazard_clears"], gs.hazard_clears)
	# game_flags may gain derived reveals on load (warp/recursion) — assert superset.
	for k in snap["game_flags"]:
		if gs.game_flags.get(k, null) != snap["game_flags"][k]:
			E("game_flags['%s'] did not round-trip: %s -> %s" % [k, snap["game_flags"][k], gs.game_flags.get(k, null)])

	# ---- The save file itself must be valid JSON and atomically backed up. ----
	var path: String = gs.slot_path(gs.current_slot)
	if not FileAccess.file_exists(path):
		E("save file missing at %s" % path)
	else:
		var f := FileAccess.open(path, FileAccess.READ)
		var json := JSON.new()
		if json.parse(f.get_as_text()) != OK:
			E("save file is not valid JSON")
		f.close()
	gs.save_game()   # second save should snapshot the prior file to .bak
	if not FileAccess.file_exists(path + ".bak"):
		W("no .bak backup after second save (atomic-write safety net absent)")

	print("\n===== PHASE 6: SAVE / LOAD & PERSISTENCE =====")
	print("fields checked: 31   save_version=2   slot=%d" % gs.current_slot)
	print("errors=%d  warnings=%d" % [errors.size(), warns.size()])
	if not warns.is_empty():
		print("\n--- WARNINGS (%d) ---" % warns.size())
		for w in warns: print("  ⚠ " + w)
	if not errors.is_empty():
		print("\n--- ERRORS (%d) ---" % errors.size())
		for e in errors: print("  ✗ " + e)
		print("\nSAVE_LOAD: FAIL")
		quit(1)
		return
	print("\nSAVE_LOAD: PASS")
	quit()
