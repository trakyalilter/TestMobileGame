extends Node

# ============================================================================
# PHASE-GATE SPIKE (NG+ P1) — verifies the multi-phase boss damage gate that
# generalizes the Z11 warp_hardened Cryo wall:
#   * _phase_index splits HP into N even bands (full HP -> 0, dead -> N-1)
#   * _get_breach_factors gives FULL damage only to the current phase's element
#     and cuts every other channel to phase_cut
#   * Z11 warp_hardened stays BYTE-IDENTICAL (k/e/x x0.02, cryo full)
#   * enemy attacks + non-gated enemies are untouched (all 1.0) -> existing
#     conventional combat is mathematically unchanged
#   * an element with no weapon channel yet (corrosion/thermal/…) cuts the whole
#     band -> the intended forward gate (unbeatable until P3 ships the weapon)
#
# Deterministic (no RNG): asserts the gate logic directly, not via sampled DPS.
# Run: tools/run_sim.ps1 -Scene "res://scenes/phase_gate_spike.tscn"
# ============================================================================

var _fails := 0

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	GameState.set_process(false)
	var cm = GameState.combat_manager
	cm.enemy_max_hp = 1000

	print("[PHASE] ---- _phase_index (HP -> band) ----")
	_eq_i("n1 full", _pi(cm, 1000, 1), 0)
	_eq_i("n1 dead", _pi(cm, 0, 1), 0)
	_eq_i("n3 full", _pi(cm, 1000, 3), 0)
	_eq_i("n3 0.70", _pi(cm, 700, 3), 0)
	_eq_i("n3 0.60", _pi(cm, 600, 3), 1)
	_eq_i("n3 0.40", _pi(cm, 400, 3), 1)
	_eq_i("n3 0.30", _pi(cm, 300, 3), 2)
	_eq_i("n3 dead", _pi(cm, 0, 3), 2)
	_eq_i("n5 full", _pi(cm, 1000, 5), 0)
	_eq_i("n5 0.50", _pi(cm, 500, 5), 2)
	_eq_i("n5 dead", _pi(cm, 0, 5), 4)

	print("[PHASE] ---- _get_breach_factors ----")
	cm.enemy_max_hp = 1000
	cm.enemy_hp = 1000

	cm.current_enemy = {"resist_k": 0.0}
	_eq_f("nogate", cm._get_breach_factors(true), {"k": 1.0, "e": 1.0, "x": 1.0, "cryo": 1.0})

	cm.current_enemy = {"warp_hardened": true}
	_eq_f("enemyatk (gated but enemy)", cm._get_breach_factors(false), {"k": 1.0, "e": 1.0, "x": 1.0, "cryo": 1.0})
	_eq_f("z11 warp_hardened", cm._get_breach_factors(true), {"k": 0.02, "e": 0.02, "x": 0.02, "cryo": 1.0})

	var pb = {"phases": ["cryo", "kinetic", "energy"], "phase_cut": 0.15}
	cm.current_enemy = pb
	cm.enemy_max_hp = 1000
	cm.enemy_hp = 1000
	_eq_f("ph0 cryo", cm._get_breach_factors(true), {"k": 0.15, "e": 0.15, "x": 0.15, "cryo": 1.0})
	cm.enemy_hp = 500
	_eq_f("ph1 kinetic", cm._get_breach_factors(true), {"k": 1.0, "e": 0.15, "x": 0.15, "cryo": 0.15})
	cm.enemy_hp = 100
	_eq_f("ph2 energy", cm._get_breach_factors(true), {"k": 0.15, "e": 1.0, "x": 0.15, "cryo": 0.15})

	cm.current_enemy = {"phases": ["corrosion"], "phase_cut": 0.15}
	cm.enemy_hp = 1000
	_eq_f("unmappable corrosion -> all cut", cm._get_breach_factors(true), {"k": 0.15, "e": 0.15, "x": 0.15, "cryo": 0.15})

	cm.current_enemy = {"phases": ["kinetic", "energy"]}
	cm.enemy_max_hp = 1000
	cm.enemy_hp = 1000
	_eq_f("default phase_cut=0.15", cm._get_breach_factors(true), {"k": 1.0, "e": 0.15, "x": 0.15, "cryo": 0.15})

	print("[PHASE] ---- typed exotic (weapon element vs phase) ----")
	var tb = {"phases": ["cryo", "corrosion", "kinetic"], "phase_cut": 0.15}
	cm.current_enemy = tb
	cm.enemy_max_hp = 1000
	cm.enemy_hp = 1000
	_eq_f("cryo wpn / cryo phase", cm._get_breach_factors(true, "cryo"), {"k": 0.15, "e": 0.15, "x": 0.15, "cryo": 1.0})
	cm.enemy_hp = 500
	_eq_f("cryo wpn / corrosion phase", cm._get_breach_factors(true, "cryo"), {"k": 0.15, "e": 0.15, "x": 0.15, "cryo": 0.15})
	cm.enemy_hp = 1000
	_eq_f("corr wpn / cryo phase", cm._get_breach_factors(true, "corrosion"), {"k": 0.15, "e": 0.15, "x": 0.15, "cryo": 0.15})
	cm.enemy_hp = 500
	_eq_f("corr wpn / corrosion phase", cm._get_breach_factors(true, "corrosion"), {"k": 0.15, "e": 0.15, "x": 0.15, "cryo": 1.0})
	cm.enemy_hp = 100
	_eq_f("corr wpn / kinetic phase", cm._get_breach_factors(true, "corrosion"), {"k": 1.0, "e": 0.15, "x": 0.15, "cryo": 0.15})
	cm.current_enemy = {"warp_hardened": true}
	_eq_f("z11 / corrosion wpn (no breach)", cm._get_breach_factors(true, "corrosion"), {"k": 0.02, "e": 0.02, "x": 0.02, "cryo": 0.02})
	_eq_f("z11 / cryo wpn (identical)", cm._get_breach_factors(true, "cryo"), {"k": 0.02, "e": 0.02, "x": 0.02, "cryo": 1.0})

	print("[PHASE] ---- can_swap_loadout_in_combat gate ----")
	cm.in_combat = false
	cm.current_enemy = {"phases": ["cryo", "corrosion"]}
	_eq_b("not in combat", cm.can_swap_loadout_in_combat(), false)
	cm.in_combat = true
	cm.current_enemy = {}
	_eq_b("in combat, no phases", cm.can_swap_loadout_in_combat(), false)
	cm.current_enemy = {"phases": ["cryo"]}
	_eq_b("in combat, single phase", cm.can_swap_loadout_in_combat(), false)
	cm.current_enemy = {"phases": ["cryo", "corrosion"]}
	_eq_b("in combat, multi phase", cm.can_swap_loadout_in_combat(), true)
	cm.in_combat = false

	print("[PHASE] ---- _rebuild_player_weapon_states (runtime, no crash) ----")
	cm._rebuild_player_weapon_states()
	_eq_b("weapon states is Array", cm.player_weapon_states is Array, true)
	print("[PHASE]   (rebuilt %d weapon state(s))" % cm.player_weapon_states.size())

	print("[PHASE] ---- Z12 Rift Warden (end-to-end spawn wiring) ----")
	cm.current_zone = cm.zones["the_rift"]
	cm.target_enemy_id = "z12_boss_rift_warden"
	cm.spawn_enemy()
	_eq_b("warden phases copied", cm.current_enemy.get("phases", []) == ["cryo", "corrosion"], true)
	_eq_b("warden phase_cut copied", abs(float(cm.current_enemy.get("phase_cut", -1.0)) - 0.15) < 0.0001, true)
	# Phase 0 (full HP) = Cryo-hardened
	cm.enemy_hp = cm.enemy_max_hp
	_eq_b("p0 cryo wpn breaches", abs(float(cm._get_breach_factors(true, "cryo")["cryo"]) - 1.0) < 0.0001, true)
	_eq_b("p0 corrosion wpn stalls", abs(float(cm._get_breach_factors(true, "corrosion")["cryo"]) - 0.15) < 0.0001, true)
	# Phase 1 (low HP) = Corrosion-hardened — THE swap-forcing proof
	cm.enemy_hp = int(cm.enemy_max_hp * 0.1)
	_eq_b("p1 cryo wpn STALLS (swap!)", abs(float(cm._get_breach_factors(true, "cryo")["cryo"]) - 0.15) < 0.0001, true)
	_eq_b("p1 corrosion wpn breaches", abs(float(cm._get_breach_factors(true, "corrosion")["cryo"]) - 1.0) < 0.0001, true)
	cm.in_combat = true
	_eq_b("warden allows in-fight swap", cm.can_swap_loadout_in_combat(), true)
	cm.in_combat = false
	# Trash enemy is NOT gated (any weapon clears it)
	cm.target_enemy_id = "z12_acid_revenant"
	cm.spawn_enemy()
	_eq_b("trash not gated (no phases)", (cm.current_enemy.get("phases", []) as Array).is_empty(), true)

	print("[PHASE] ---- Z12 reachability + content wiring ----")
	GameState.game_settings["z12_unlocked"] = false
	_eq_b("the_rift hidden when locked", not _has_zone(cm.get_available_zones(), "the_rift"), true)
	GameState.game_settings["z12_unlocked"] = true
	_eq_b("the_rift shown when unlocked", _has_zone(cm.get_available_zones(), "the_rift"), true)
	GameState.game_settings["z12_unlocked"] = false
# v113: Z11 is warp-gated - z10_cleared alone must NOT show it; only z11_unlocked (set on the warp).
	GameState.game_settings["z11_unlocked"] = false
	GameState.game_settings["z10_cleared"] = true
	_eq_b("Z11 hidden on z10_cleared alone (warp-gated)", not _has_zone(cm.get_available_zones(), "the_threshold"), true)
	GameState.game_settings["z11_unlocked"] = true
	_eq_b("Z11 shown when z11_unlocked", _has_zone(cm.get_available_zones(), "the_threshold"), true)
	GameState.game_settings["z11_unlocked"] = false
	GameState.game_settings["z10_cleared"] = false
	_eq_b("corrosion_armaments tech exists", "corrosion_armaments" in GameState.research_manager.tech_tree, true)
	var sm2 = GameState.shipyard_manager
	_eq_b("corrosion_blaster module exists", "corrosion_blaster" in sm2.modules, true)
	var cb_stats: Dictionary = sm2.modules.get("corrosion_blaster", {}).get("stats", {})
	_eq_b("corrosion_blaster tagged corrosion", str(cb_stats.get("exotic_element", "")) == "corrosion", true)
	_eq_b("corrosion_blaster gated by tech", str(sm2.modules.get("corrosion_blaster", {}).get("research_req", "")) == "corrosion_armaments", true)

	print("[PHASE] ---- Threshold Relic (master key) ----")
	var sm3 = GameState.shipyard_manager
	_eq_b("rift_relic module exists", "rift_relic" in sm3.modules, true)
	_eq_b("rift_relic slot_type=relic", str(sm3.modules.get("rift_relic", {}).get("slot_type", "")) == "relic", true)
	_eq_b("warden drops rift_relic", str(cm.enemy_db.get("z12_boss_rift_warden", {}).get("relic_drop", "")) == "rift_relic", true)
	sm3.module_inventory["rift_relic"] = 1
	sm3.equipped_relic = ""
	_eq_b("equip_relic ok", sm3.equip_relic("rift_relic"), true)
	_eq_b("equipped_relic set", sm3.equipped_relic == "rift_relic", true)
	_eq_b("relic cuts dmg in the_rift (->0.08)", abs(sm3.get_relic_reduction_factor("the_rift") - 0.08) < 0.0001, true)
	_eq_b("relic inert in other zone (->1.0)", abs(sm3.get_relic_reduction_factor("lunar_orbit") - 1.0) < 0.0001, true)
	sm3.unequip_relic()
	_eq_b("unequip clears slot", sm3.equipped_relic == "", true)
	_eq_b("no factor when unequipped", abs(sm3.get_relic_reduction_factor("the_rift") - 1.0) < 0.0001, true)

	print("[PHASE] ---- v113 Cryo/Z4/Z11 cleanup ----")
	_eq_b("Z11 zone = 'The Threshold'", str(cm.zones.get("the_threshold", {}).get("name", "")) == "The Threshold", true)
	_eq_b("Z4 zone = 'Glacier Belt'", str(cm.zones.get("cryofield", {}).get("name", "")) == "Glacier Belt", true)
	_eq_b("CryoCatalyst display exists", ElementDB.get_display_name("CryoCatalyst") == "Cryo Catalyst", true)
	_eq_b("CryoEssence -> 'Glacial Essence'", ElementDB.get_display_name("CryoEssence") == "Glacial Essence", true)
	var rep_cost: Dictionary = sm3.modules.get("cryo_lance", {}).get("cost", {})
	_eq_b("cryo_lance uses CryoCatalyst not CryoEssence", rep_cost.has("CryoCatalyst") and not rep_cost.has("CryoEssence"), true)
	var z10_loot: Array = cm.enemy_db.get("z10_boss_leviathan", {}).get("loot", [])
	var z10_has_cc := false
	for _e in z10_loot:
		if (_e as Array).size() > 0 and str(_e[0]) == "CryoCatalyst":
			z10_has_cc = true
	_eq_b("Z10 boss drops CryoCatalyst", z10_has_cc, true)

	print("[PHASE] ---- Forge Cryogenic Arms mission chain ----")
	var mm = GameState.mission_manager
	_eq_b("goal_cryo_1 exists", "goal_cryo_1" in mm.missions, true)
	_eq_b("goal_cryo_1 = research cryo_armaments", str(mm.missions.get("goal_cryo_1", {}).get("target", "")) == "cryo_armaments", true)
	_eq_b("goal_cryo_1 -> goal_cryo_2", str(mm.missions.get("goal_cryo_1", {}).get("next_mission", "")) == "goal_cryo_2", true)
	_eq_b("goal_cryo_2 = craft cryo_lance", str(mm.missions.get("goal_cryo_2", {}).get("target", "")) == "cryo_lance", true)
	_eq_b("goal_cryo_3 = defeat z11_warp_revenant", str(mm.missions.get("goal_cryo_3", {}).get("target", "")) == "z11_warp_revenant", true)

	print("[PHASE] ---- Corrosion research tier-gated to Z12 ----")
	_eq_b("corrosion_armaments requires_flag=z12_unlocked", str(GameState.research_manager.tech_tree.get("corrosion_armaments", {}).get("requires_flag", "")) == "z12_unlocked", true)
	_eq_b("cryo_armaments requires_flag=cryo_unlocked (hidden pre-warp)", str(GameState.research_manager.tech_tree.get("cryo_armaments", {}).get("requires_flag", "")) == "cryo_unlocked", true)
	_eq_b("free cryo_shard_pistol module removed", not ("cryo_shard_pistol" in GameState.shipyard_manager.modules), true)

	print("[PHASE] ---- v114 Zone Tier-Gate: module tier + pierce rule ----")
	var smT = GameState.shipyard_manager
	_eq_b("get_module_tier z4_kinetic = 4", smT.get_module_tier("z4_kinetic") == 4, true)
	_eq_b("get_module_tier cryo_lance = 8 (power_tier)", smT.get_module_tier("cryo_lance") == 8, true)
	# Inject deterministic test modules. Rarity UNIQUE = enum value 4.
	smT.modules["__t_common_z3"] = {"zone": 3, "slot_type": "weapon", "stats": {}}
	smT.modules["__t_uniq_z3"] = {"zone": 3, "rarity": 4, "slot_type": "weapon", "stats": {}}
	_eq_b("z<=0 always pierces (ungated)", smT.module_pierces_tier("__t_common_z3", 0), true)
	_eq_b("tier3 vs Z3 pierces (craft path)", smT.module_pierces_tier("__t_common_z3", 3), true)
	_eq_b("tier3 common vs Z4 FLOORED", smT.module_pierces_tier("__t_common_z3", 4), false)
	_eq_b("tier3 UNIQUE vs Z4 pierces (skip-key)", smT.module_pierces_tier("__t_uniq_z3", 4), true)
	_eq_b("tier3 UNIQUE vs Z5 FLOORED (Z-2, one zone only)", smT.module_pierces_tier("__t_uniq_z3", 5), false)

	print("[PHASE] ---- v114 defense factors (sub-tier armor/shield floored) ----")
	smT.modules["__t_arm_z2"] = {"zone": 2, "slot_type": "armor", "stats": {"def": 100}}
	smT.modules["__t_arm_z5"] = {"zone": 5, "slot_type": "armor", "stats": {"def": 100}}
	smT.modules["__t_shl_z2"] = {"zone": 2, "slot_type": "shield", "stats": {"max_shield": 100}}
	var _saved_loadout = smT.loadout.duplicate(true)
	smT.loadout = {0: "__t_arm_z2", 1: "__t_arm_z5", 2: "__t_shl_z2"}
	var df5 = smT.get_tier_defense_factors(5, 0.02)
	# armor: z2 floored(×0.02) + z5 full(×1.0) over 200 → (2+100)/200 = 0.51
	_eq_b("def factor mixed armor ~0.51", abs(float(df5["def"]) - 0.51) < 0.001, true)
	# shield: only the sub-tier z2 → ×0.02
	_eq_b("shield factor all sub-tier ~0.02", abs(float(df5["shield"]) - 0.02) < 0.001, true)
	var df0 = smT.get_tier_defense_factors(0, 0.02)
	_eq_b("Z=0 ungated factors 1.0", abs(float(df0["def"]) - 1.0) < 0.001 and abs(float(df0["shield"]) - 1.0) < 0.001, true)

	print("[PHASE] ---- v114 front/back derivation + gate flag ----")
	GameState.game_settings["tier_gate_enabled"] = true
	cm.current_zone = cm.zones["cryofield"]  # Z4 (difficulty 4)
	cm.target_enemy_id = "z4_ice_wraith"     # e1 → front salvage
	cm.spawn_enemy()
	_eq_b("Z4 e1 front: tier_hardened 0", int(cm.current_enemy.get("tier_hardened", -1)) == 0, true)
	_eq_b("Z4 e1 front: drops_modules false", cm.current_enemy.get("drops_modules", true) == false, true)
	cm.target_enemy_id = "z4_frost_hulk"     # e3 → hardened back half
	cm.spawn_enemy()
	_eq_b("Z4 e3 back: tier_hardened 4", int(cm.current_enemy.get("tier_hardened", -1)) == 4, true)
	_eq_b("Z4 e3 back: drops_modules true", cm.current_enemy.get("drops_modules", false) == true, true)
	cm.target_enemy_id = "z4_boss_overseer"  # boss → hardened
	cm.spawn_enemy()
	_eq_b("Z4 boss: tier_hardened 4", int(cm.current_enemy.get("tier_hardened", -1)) == 4, true)
	cm.current_zone = cm.zones["lunar_orbit"]  # Z1 bootstrap (ungated)
	cm.target_enemy_id = "z1_boss_architect"
	cm.spawn_enemy()
	_eq_b("Z1 boss ungated: tier_hardened 0", int(cm.current_enemy.get("tier_hardened", -1)) == 0, true)
	cm.current_zone = cm.zones["the_threshold"]  # Z11 orthogonal (warp gate)
	cm.target_enemy_id = "z11_boss_threshold_warden"
	cm.spawn_enemy()
	_eq_b("Z11 boss: tier_hardened 0 (warp gate, orthogonal)", int(cm.current_enemy.get("tier_hardened", -1)) == 0, true)
	# End-to-end: gate ON + sub-tier armor → defense factor floored on spawn.
	smT.loadout = {0: "__t_arm_z2"}  # zone-2 armor, sub-tier vs Z4
	cm.current_zone = cm.zones["cryofield"]
	cm.target_enemy_id = "z4_frost_hulk"
	cm.spawn_enemy()
	_eq_b("gate ON + sub-tier armor: def factor floored ~0.02", abs(cm._tier_def_factor - 0.02) < 0.001, true)
	# Gate OFF → no flooring even against a hardened-band enemy.
	GameState.game_settings["tier_gate_enabled"] = false
	cm.spawn_enemy()
	_eq_b("gate OFF: def factor 1.0 (no flooring)", abs(cm._tier_def_factor - 1.0) < 0.001, true)
	GameState.game_settings["tier_gate_enabled"] = true
	smT.loadout = _saved_loadout

	if _fails == 0:
		print("[PHASE] ALL PASS")
	else:
		print("[PHASE] *** %d FAILURE(S)" % _fails)
	get_tree().quit(0)

func _pi(cm, hp: int, n: int) -> int:
	cm.enemy_hp = hp
	return cm._phase_index(n)

func _eq_i(label: String, got: int, want: int) -> void:
	var ok: bool = got == want
	if not ok: _fails += 1
	print("[PHASE]   %-28s got=%d want=%d  %s" % [label, got, want, "OK" if ok else "*** FAIL"])

func _eq_f(label: String, got: Dictionary, want: Dictionary) -> void:
	var ok: bool = true
	for key in want:
		if abs(float(got.get(key, -999.0)) - float(want[key])) > 0.0001:
			ok = false
	if not ok: _fails += 1
	print("[PHASE]   %-32s got=%s  %s" % [label, str(got), "OK" if ok else "*** FAIL want=%s" % str(want)])

func _eq_b(label: String, got: bool, want: bool) -> void:
	var ok: bool = got == want
	if not ok: _fails += 1
	print("[PHASE]   %-32s got=%s want=%s  %s" % [label, str(got), str(want), "OK" if ok else "*** FAIL"])

func _has_zone(zlist: Array, zid: String) -> bool:
	for z in zlist:
		if z.get("id", "") == zid:
			return true
	return false
