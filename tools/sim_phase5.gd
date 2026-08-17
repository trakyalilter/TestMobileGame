extends SceneTree
## Phase 5 data-pipeline verification: boss cores, energy budget, research gating,
## non-set rarity, and combat regression with the basic Z1 loadout.
## Prints PASS/FAIL for each of the 5 verifications + an overall summary.

var _pass := 0
var _fail := 0

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _chk(label: String, ok: bool, extra := "") -> void:
	if ok:
		_pass += 1
		print("PASS: %s %s" % [label, extra])
	else:
		_fail += 1
		print("FAIL: %s %s" % [label, extra])

func _run() -> void:
	var gs = root.get_node("GameState")

	_verify_combat_and_grid(gs)
	_verify_boss_core(gs)
	_verify_research_gating(gs)
	_verify_power_budget(gs)

	print("=====================================")
	print("PHASE5 SUMMARY: %d PASS / %d FAIL -> %s" % [_pass, _fail, "ALL PASS" if _fail == 0 else "FAILURES"])
	quit()

# V2 + V5(load): basic z1 loadout fits the grid and kills z1_lunar_drone in 8-15s.
func _verify_combat_and_grid(gs) -> void:
	print("--- V2: combat regression + grid fit ---")
	gs.hard_reset()
	# v110 battery-only energy: hulls supply ZERO energy. The basic z1 starter
	# (4 consumers @ 10 = 40 load) needs the corvette's TWO battery slots
	# (2 x 30 = 60 cap) to fit. Batteries first so capacity exists before consumers.
	var loadout := ["z1_battery", "z1_battery", "z1_kinetic", "z1_energy", "z1_shield", "z1_armor"]
	var all_equipped := true
	for mid in loadout:
		gs.module_inventory[mid] = int(gs.module_inventory.get(mid, 0)) + 1
		if not gs.equip_module(mid):
			all_equipped = false
			print("  equip FAILED: %s" % mid)
	var ss: Dictionary = gs.ship_stats()
	var load := float(ss.get("energy_load", 0))
	var cap := float(ss.get("energy_cap", 0))
	_chk("basic z1 loadout equips", all_equipped)
	_chk("loadout fits grid", load <= cap, "(load=%.0f cap=%.0f)" % [load, cap])
	_chk("consumers draw power", load > 0.0, "(load=%.0f)" % load)

	# Load ammo for the two weapons (kinetic->Slug, energy->Cell).
	gs.add_resource("SlugT1", 9999)
	gs.add_resource("CellT1", 9999)
	for k in gs.loadout:
		var m: Dictionary = gs.module_def(gs.loadout[k])
		if m.get("slot", "") == "weapon":
			var st: Dictionary = m.get("stats", {})
			if float(st.get("atk_kinetic", 0)) > 0:
				gs.set_ammo(str(k), "SlugT1")
			elif float(st.get("atk_energy", 0)) > 0:
				gs.set_ammo(str(k), "CellT1")

	gs.start_task("combat", "z1_lunar_drone")
	var t := 0.0
	var dt := 0.1
	var killed := false
	var prev_hp := float(gs.enemy_inst.get("hp", 0))
	while t < 60.0:
		gs._tick_combat(dt)
		t += dt
		if gs.active_type != "combat":
			break
		var ehp := float(gs.enemy_inst.get("hp", 0))
		if ehp > prev_hp + 1.0:
			killed = true
			break
		prev_hp = ehp
	gs.stop_task()
	_chk("z1_lunar_drone killed in 8-15s", killed and t >= 8.0 and t <= 15.0,
		"(t=%.1fs killed=%s player_hp=%.0f)" % [t, str(killed), gs.combat_hp])

# V3: boss kill grants ZN_Core, and gates zone_2_access research.
func _verify_boss_core(gs) -> void:
	print("--- V3: boss core drop + zone research gate ---")
	gs.hard_reset()
	# zone_2_access requires Z1_Core + Cu/Fe + credits + req_tech shipwright_1.
	var before: int = gs.amount("Z1_Core")
	gs.start_task("combat", "z1_boss_architect")
	# Deterministically resolve the win (weapon-fire RNG would make timing flaky).
	gs._win_combat()
	gs.stop_task()
	var after: int = gs.amount("Z1_Core")
	_chk("Z1_Core +1 on boss kill", after == before + 1, "(%d -> %d)" % [before, after])

	# Now check zone_2_access gating. Unlock prereqs + supply costs.
	gs.hard_reset()
	var t2: Dictionary = GameData.RESEARCH["zone_2_access"]
	# Satisfy every prerequisite tech so only the Z1_Core item is the variable.
	for rt in t2.get("req_tech", []):
		gs.unlocked_research[String(rt)] = true
	gs.credits = int(t2.get("credits", 0)) + 10
	# Ask the ENGINE for the effective costs — never re-derive them here. Raw data
	# quantities are pre-MATERIAL_MULTIPLIER, and a local copy of that formula is
	# exactly the drift desktop's v141 fix warns about (its research modal showed
	# double the real requirement for every zone gate).
	var eff2: Dictionary = gs.research_items("zone_2_access")
	for item in eff2:
		if item != "Z1_Core":
			gs.add_resource(item, int(eff2[item]))
	var avail_without: bool = gs.research_available("zone_2_access")
	_chk("zone_2_access NOT researchable without Z1_Core", not avail_without)
	gs.add_resource("Z1_Core", int(eff2.get("Z1_Core", 1)))
	var avail_with: bool = gs.research_available("zone_2_access")
	_chk("zone_2_access researchable once Z1_Core met", avail_with)

	# V3b: Z11 unlock on Z10 boss still fires.
	gs.hard_reset()
	gs.start_task("combat", "z10_boss_leviathan")
	gs._win_combat()
	gs.stop_task()
	_chk("Z11 unlocks on Z10 boss kill", bool(gs.game_flags.get("z11_unlocked", false)))
	_chk("Z10_Core granted", gs.amount("Z10_Core") >= 1)

# V4: a tech with a req_tech is gated until the req_tech (and parent) unlock.
func _verify_research_gating(gs) -> void:
	print("--- V4: req_tech gating ---")
	gs.hard_reset()
	# laser_optics: parent=power_systems, req_tech=[fluid_dynamics].
	var tid := "laser_optics"
	var t: Dictionary = GameData.RESEARCH[tid]
	gs.credits = int(t.get("credits", 0)) + 100
	for item in t.get("items", {}):
		gs.add_resource(item, int(t["items"][item]) * 4)
	# Unlock the parent only — req_tech still missing.
	if t.get("parent", "") != "":
		gs.unlocked_research[String(t["parent"])] = true
	var before: bool = gs.research_available(tid)
	_chk("laser_optics NOT available without req_tech", not before)
	# Unlock req_tech -> now available.
	for rt in t.get("req_tech", []):
		gs.unlocked_research[String(rt)] = true
	var after: bool = gs.research_available(tid)
	_chk("laser_optics available after req_tech unlocked", after)

	# V4b: requires_warp gate on cryo_armaments.
	gs.hard_reset()
	var ct: Dictionary = GameData.RESEARCH["cryo_armaments"]
	gs.credits = int(ct.get("credits", 0)) + 100
	for item in ct.get("items", {}):
		gs.add_resource(item, int(ct["items"][item]) * 4)
	for rt in ct.get("req_tech", []):
		gs.unlocked_research[String(rt)] = true
	if ct.get("parent", "") != "":
		gs.unlocked_research[String(ct["parent"])] = true
	# v111: the warp gate is now the persistent cryo_unlocked flag (set on the
	# first Warp), not total_warps directly.
	gs.cryo_unlocked = false
	var pre_warp: bool = gs.research_available("cryo_armaments")
	_chk("cryo_armaments NOT available before warp", not pre_warp)
	gs.cryo_unlocked = true
	var post_warp: bool = gs.research_available("cryo_armaments")
	_chk("cryo_armaments available after warp", post_warp)

# V5: a previously-loadless consumer now draws power; a battery supplies capacity.
func _verify_power_budget(gs) -> void:
	print("--- V5: power budget derivation ---")
	# z1_armor previously had no energy_load in modules.json -> now derived to 10.
	var armor: Dictionary = GameData.MODULES.get("z1_armor", {})
	var armor_load := int(armor.get("stats", {}).get("energy_load", 0))
	_chk("z1_armor draws power (was 0)", armor_load > 0, "(load=%d)" % armor_load)
	# z2_shield is a representative consumer with no explicit load in source data.
	var z2sh: Dictionary = GameData.MODULES.get("z2_shield", {})
	var z2sh_load := int(z2sh.get("stats", {}).get("energy_load", 0))
	_chk("z2_shield draws power", z2sh_load > 0, "(load=%d)" % z2sh_load)
	# Battery supplies capacity.
	var bat: Dictionary = GameData.MODULES.get("z1_battery", {})
	var bat_cap := int(bat.get("stats", {}).get("energy_capacity", 0))
	_chk("z1_battery supplies capacity", bat_cap > 0, "(cap=%d)" % bat_cap)
	# Non-set droppable module carries rarity (cryo_lance).
	var lance: Dictionary = GameData.MODULES.get("cryo_lance", {})
	_chk("cryo_lance carries rarity", lance.has("rarity"), "(rarity=%s)" % str(lance.get("rarity", "MISSING")))
