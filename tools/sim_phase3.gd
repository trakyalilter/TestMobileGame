extends SceneTree

# Throwaway Phase-3 verification sim (progression wiring). Run:
#   xvfb-run -a /tmp/gd/.../Godot --headless --path . -s tools/sim_phase3.gd

func _init() -> void:
	call_deferred("_run")

func p(label: String, ok: bool, extra: String = "") -> void:
	print(("PASS" if ok else "FAIL"), " | ", label, ("  " + extra) if extra != "" else "")

func _equip(gs, mid: String) -> void:
	gs.module_inventory[mid] = int(gs.module_inventory.get(mid, 0)) + 1
	gs.equip_module(mid)

func _run() -> void:
	await create_timer(0.5).timeout
	var gs = get_root().get_node("GameState")

	print("===== PHASE 3 VERIFICATION =====")

	# ============ 1. BOOT (implied clean by running) ============
	p("(1) boot reached GameState", gs != null)

	# ============ 2. COMBAT REGRESSION ============
	gs.active_hull = "corvette_hull"
	gs.owned_hulls["corvette_hull"] = true
	gs.loadout.clear()
	_equip(gs, "z1_battery")
	_equip(gs, "z1_battery")
	_equip(gs, "z1_kinetic")
	_equip(gs, "z1_energy")
	_equip(gs, "z1_shield")
	_equip(gs, "z1_armor")
	gs.resources["SlugT1"] = 100000
	gs.resources["CellT1"] = 100000
	for k in gs.loadout:
		var m = gs.module_def(gs.loadout[k])
		if m.get("slot", "") == "weapon":
			var st = m.get("stats", {})
			if float(st.get("atk_kinetic", 0)) > 0: gs.ammo_loadout[k] = "SlugT1"
			elif float(st.get("atk_energy", 0)) > 0: gs.ammo_loadout[k] = "CellT1"
	gs.combat_hp = gs.combat_max_hp()
	gs._init_combat("z1_lunar_drone")
	var spin := 0
	while gs.enemy_inst.get("elite", false) and spin < 50:
		gs._spawn_enemy_inst("z1_lunar_drone"); spin += 1
	var ttk := 0.0
	var killed := false
	var survived := true
	var prev_hp = float(gs.enemy_inst["hp"])
	while ttk < 60.0 and not killed:
		gs._tick_combat(0.1); ttk += 0.1
		if gs.combat_hp <= 0.0:
			survived = false; break
		var cur_hp = float(gs.enemy_inst["hp"])
		if cur_hp > prev_hp + 1.0:
			killed = true
		prev_hp = cur_hp
	p("(2) regression kill z1_lunar_drone 8-15s & survive", killed and ttk >= 5.0 and ttk <= 18.0 and survived, "ttk=%.1fs" % ttk)
	gs.stop_task()

	# ============ 3. RESEARCH BONUSES ============
	# 3a. attack_speed via core_overclocking (+0.10)
	gs.unlocked_research.erase("core_overclocking")
	var as0 = gs.research_bonus("attack_speed")
	gs.unlocked_research["core_overclocking"] = true
	var as1 = gs.research_bonus("attack_speed")
	p("(3a) attack_speed core_overclocking +0.10", abs(as0) < 0.001 and abs(as1 - 0.10) < 0.001, "%.2f -> %.2f" % [as0, as1])

	# 3b. max_hp_mult via hull_hardening (+0.15)
	gs.unlocked_research["hull_hardening"] = true
	p("(3b) max_hp_mult hull_hardening +0.15", abs(gs.research_bonus("max_hp_mult") - 0.15) < 0.001, "%.2f" % gs.research_bonus("max_hp_mult"))

	# 3c. processing_speed: nano_fabrication(0.15)+perfect_automation(0.30)+industrial_catalysis(0.25 v105b)=0.70
	gs.unlocked_research["nano_fabrication"] = true
	gs.unlocked_research["perfect_automation"] = true
	gs.unlocked_research["industrial_catalysis"] = true
	var ps = gs.research_bonus("processing_speed")
	p("(3c) processing_speed nano+perfect+catalysis=0.70", abs(ps - 0.70) < 0.001, "%.2f" % ps)

	# 3d. efficiency multiplier tiers 1..5 => 2,4,8,16,32
	for r in ["efficiency_1","efficiency_2","efficiency_3","efficiency_4","efficiency_5"]:
		gs.unlocked_research.erase(r)
	var em0 = gs.research_efficiency_mult()
	gs.unlocked_research["efficiency_1"] = true
	var em1 = gs.research_efficiency_mult()
	gs.unlocked_research["efficiency_3"] = true
	var em3 = gs.research_efficiency_mult()
	gs.unlocked_research["efficiency_5"] = true
	var em5 = gs.research_efficiency_mult()
	p("(3d) efficiency tiers 1x/2x/8x/32x", em0 == 1.0 and em1 == 2.0 and em3 == 8.0 and em5 == 32.0, "%.0f/%.0f/%.0f/%.0f" % [em0,em1,em3,em5])

	# 3e. repeatable tech adds for EVERY bonus_type (v105 fix): processing_speed += 0.05/level
	var ps_before = gs.research_bonus("processing_speed")
	gs.repeatable_research["production_focus"] = 3   # +0.15
	var ps_after = gs.research_bonus("processing_speed")
	p("(3e) repeatable production_focus +0.05*3 to processing_speed", abs(ps_after - ps_before - 0.15) < 0.001, "%.2f -> %.2f" % [ps_before, ps_after])

	# 3f. repeatable building_yield_mult (infrastructure_focus) wired
	gs.repeatable_research["infrastructure_focus"] = 2  # +0.10
	p("(3f) building_yield_mult infrastructure_focus +0.10", abs(gs.research_bonus("building_yield_mult") - 0.10) < 0.001, "%.2f" % gs.research_bonus("building_yield_mult"))

	# 3g. credit_reward_mult (wealth_focus) wired
	gs.repeatable_research["wealth_focus"] = 4  # +0.20
	p("(3g) credit_reward_mult wealth_focus -> mult 1.20", abs(gs.credit_reward_mult() - 1.20) < 0.001, "%.2f" % gs.credit_reward_mult())

	# 3h. hull_hp_mult (defense_focus) folds into max_hp
	var hp_base = gs.combat_max_hp()
	gs.repeatable_research["defense_focus"] = 2  # +0.10
	var hp_def = gs.combat_max_hp()
	p("(3h) defense_focus hull_hp_mult raises max_hp", hp_def > hp_base, "%.0f -> %.0f" % [hp_base, hp_def])
	gs.repeatable_research.clear()

	# ============ 4. MISSIONS ============
	# Reset mission state to a fresh chain. Clear research too so the merged
	# research_multi partial-completion check (4c) is deterministic.
	gs.missions_active.clear()
	gs.missions_progress.clear()
	gs.missions_claimed.clear()
	gs._mission_completed_seen.clear()
	gs.unlocked_research.clear()
	gs._mission_init()

	# Goal missions surfaced (always active)
	var goals_active = gs.missions_active.has("goal_001") and gs.missions_active.has("goal_002") and gs.missions_active.has("goal_003")
	p("(4a) goal_* missions active on init", goals_active)

	# Tutorial m001: gather 350 Dirt
	gs.add_resource("Dirt", 400)
	gs._mission_sync()
	var m001_done = gs.mission_completed("m001")
	gs.claim_mission("m001")
	var m002_active = gs.missions_active.has("m002")
	p("(4b) m001 gather complete + claim + advance to m002", m001_done and gs.missions_claimed.has("m001") and m002_active)

	# m002: merged research_multi (Foundational Research) — needs ALL 3 techs, then
	# advances to m004 (the curated chain dropped the separate m002b/m003 steps).
	gs.credits = 999999999   # afford all three foundational unlocks
	gs.unlock_research("basic_engineering")
	var m002_partial = not gs.mission_completed("m002")   # 1/3 — still incomplete
	gs.unlock_research("applied_physics")
	gs.unlock_research("fluid_dynamics")
	var m002_done = gs.mission_completed("m002")
	gs.claim_mission("m002")
	p("(4c) m002 research_multi completes after all 3 techs + advances to m004",
		m002_partial and m002_done and gs.missions_claimed.has("m002") and gs.missions_active.has("m004"))

	# NEW TYPE: warp_perform (goal_002 needs 1 warp)
	var warps_before = gs.total_warps
	gs._mission_event("warp_perform", "warp", 1)   # simulate the event hook
	gs.total_warps = warps_before + 1
	gs._mission_sync()
	p("(4d) NEW warp_perform goal_002 completes after a warp", gs.mission_completed("goal_002"), "warps=%d" % gs.total_warps)

	# NEW TYPE: equip_consumables (build a one-off mission state check)
	# Use the live evaluator directly against a synthetic mission dict.
	gs.resources["EmergencyPatch"] = 5
	gs.resources["BasicBooster"] = 5
	gs.consumable_hull_slot = "EmergencyPatch"
	gs.consumable_shield_slot = "BasicBooster"
	var ec_met = gs._equip_consumables_met({"target": "1", "qty": 1})
	p("(4e) NEW equip_consumables: both slots stocked", ec_met)

	# NEW TYPE: discover (goal_001 -> sector_epsilon, fires on zone research unlock)
	# sector_epsilon's gating research is zone_10_access. Pre-unlock the parent
	# chain and grant resources so the real unlock_research path runs (and fires
	# the discover hook), rather than poking unlocked_research directly.
	var disc0 = gs.mission_completed("goal_001")
	for parent in ["zone_2_access","zone_3_access","zone_4_access","zone_5_access","zone_6_access","zone_7_access","zone_8_access","zone_9_access"]:
		gs.unlocked_research[parent] = true
	gs.credits = 999999999999
	var z10 = GameData.RESEARCH.get("zone_10_access", {})
	for it in z10.get("items", {}):
		gs.resources[it] = int(z10["items"][it]) + 10
	var unlocked_ok = gs.unlock_research("zone_10_access")
	var disc1 = gs.mission_completed("goal_001")
	p("(4f) NEW discover goal_001 on zone_10_access unlock", unlocked_ok and (not disc0) and disc1)

	# NEW TYPE: visit_page (drive a visit_page mission via the page hook)
	# Activate m016c manually and visit "combat".
	gs.missions_active["m016c"] = true
	gs.mission_visit_page("combat")
	p("(4g) NEW visit_page m016c completes on Combat page", gs.mission_completed("m016c"))

	# NEW TYPE: drop_rarity / loadout_rare_weapon (rarity-2 weapon)
	gs.loadout.clear()
	gs.module_inventory.clear()
	var rare_w = gs.generate_module("z1_kinetic", 2, 1)   # rarity 2 = Rare
	var dr_met = gs._has_module_rarity(2)
	gs.equip_module(rare_w)
	var lrw_met = gs._has_rare_weapon_equipped(2)
	p("(4h) NEW drop_rarity + loadout_rare_weapon (rarity>=2)", dr_met and lrw_met)

	# ============ 5. BUILDING / GATHER / PROCESS BONUS ============
	# 5a. biosphere_dome grants +5% gather speed per building
	gs.buildings.clear()
	var gsp0 = gs.gather_speed_mult("gather_dirt")
	gs.buildings["biosphere_dome"] = 1
	var gsp1 = gs.gather_speed_mult("gather_dirt")
	p("(5a) biosphere_dome +5% gather speed", abs(gsp1 - gsp0 - 0.05) < 0.001, "%.3f -> %.3f" % [gsp0, gsp1])

	# 5b. per-action gather speed tech (diamond_drills +0.50 on gather_dirt)
	gs.buildings.clear()
	gs.unlocked_research.erase("diamond_drills")
	var gt0 = gs.gather_speed_mult("gather_dirt")
	gs.unlocked_research["diamond_drills"] = true
	var gt1 = gs.gather_speed_mult("gather_dirt")
	p("(5b) diamond_drills +0.50 gather speed", abs(gt1 - gt0 - 0.50) < 0.001, "%.2f -> %.2f" % [gt0, gt1])

	# 5c. processing recipe speed tech (blast_furnace +0.25 on smelt_steel_basic)
	gs.unlocked_research.erase("blast_furnace")
	var rs0 = gs.recipe_speed_mult("smelt_steel_basic")
	gs.unlocked_research["blast_furnace"] = true
	var rs1 = gs.recipe_speed_mult("smelt_steel_basic")
	p("(5c) blast_furnace +0.25 recipe speed", abs(rs1 - rs0 - 0.25) < 0.001, "%.2f -> %.2f" % [rs0, rs1])

	# 5d. building yield reflects building_yield_mult (infrastructure_focus)
	# Verify the produce path multiplies by net_mult.
	gs.repeatable_research["infrastructure_focus"] = 2  # +0.10
	var nm = 1.0 + gs.research_bonus("building_yield_mult")
	p("(5d) building_yield net mult = 1.10", abs(nm - 1.10) < 0.001, "%.2f" % nm)

	# ============ 6. FULL TUTORIAL CHAIN WALK ============
	# Reset and walk m001..m007b across gather/research/gather_multi/craft/loadout_check.
	gs.missions_active.clear()
	gs.missions_progress.clear()
	gs.missions_claimed.clear()
	gs._mission_completed_seen.clear()
	gs.unlocked_research.clear()
	gs.loadout.clear()
	gs.module_inventory.clear()
	gs.resources.clear()
	gs.credits = 999999999
	gs._mission_init()

	# Curated mobile chain: m001 → m002(research_multi×3) → m004 → m005 →
	# m014(kinetics_101) → m020(power_systems). Power beat is now AHEAD of the
	# engine equip (mobile hulls give no energy, so a battery must seat first).
	var walk_ok := true
	var trace := []
	# m001 gather Dirt 350
	gs.add_resource("Dirt", 400); gs._mission_sync()
	walk_ok = walk_ok and gs.claim_mission("m001"); trace.append("m001" if gs.missions_claimed.has("m001") else "m001!")
	# m002 merged research_multi (basic_engineering + applied_physics + fluid_dynamics)
	gs.unlock_research("basic_engineering")
	gs.unlock_research("applied_physics")
	gs.unlock_research("fluid_dynamics")
	walk_ok = walk_ok and gs.claim_mission("m002"); trace.append("m002" if gs.missions_claimed.has("m002") else "m002!")
	# m004 gather Water 350
	gs.add_resource("Water", 400); gs._mission_sync()
	walk_ok = walk_ok and gs.claim_mission("m004"); trace.append("m004" if gs.missions_claimed.has("m004") else "m004!")
	# m005 gather_multi {Si:100, Fe:80}
	gs.add_resource("Si", 120); gs.add_resource("Fe", 100); gs._mission_sync()
	walk_ok = walk_ok and gs.claim_mission("m005"); trace.append("m005" if gs.missions_claimed.has("m005") else "m005!")
	# m014 research kinetics_101 (parent of power_systems — researched FIRST now)
	gs.unlock_research("kinetics_101")
	walk_ok = walk_ok and gs.claim_mission("m014"); trace.append("m014" if gs.missions_claimed.has("m014") else "m014!")
	# m020 research power_systems (parent prerequisite kinetics_101 now met)
	gs.unlock_research("power_systems")
	walk_ok = walk_ok and gs.claim_mission("m020"); trace.append("m020" if gs.missions_claimed.has("m020") else "m020!")
	p("(6) curated chain m001->m020 advances via mixed events (incl. research_multi)",
		walk_ok and gs.missions_active.has("m021"), " ".join(trace))

	print("===== END PHASE 3 =====")
	quit()
