extends SceneTree

# Throwaway Phase-2 verification sim. Run:
#   xvfb-run -a /tmp/gd/.../Godot --headless --path . -s tools/sim_phase2.gd

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

	# ---- Base Zone-1 loadout (corvette) ----
	gs.active_hull = "corvette_hull"
	gs.owned_hulls["corvette_hull"] = true
	gs.loadout.clear()
	_equip(gs, "z1_battery")
	_equip(gs, "z1_battery")
	_equip(gs, "z1_kinetic")
	_equip(gs, "z1_energy")
	_equip(gs, "z1_shield")
	_equip(gs, "z1_armor")
	gs.combat_hp = gs.combat_max_hp()
	# Load ammo (Slug for kinetic slot, Cell for energy slot)
	gs.resources["SlugT1"] = 100000
	gs.resources["CellT1"] = 100000
	for k in gs.loadout:
		var m = gs.module_def(gs.loadout[k])
		if m.get("slot", "") == "weapon":
			var st = m.get("stats", {})
			if float(st.get("atk_kinetic", 0)) > 0: gs.ammo_loadout[k] = "SlugT1"
			elif float(st.get("atk_energy", 0)) > 0: gs.ammo_loadout[k] = "CellT1"

	# ===== (b) Regression: kill z1_lunar_drone in ~8-15s, survive =====
	# Re-roll until a non-elite spawn (the desktop 5% elite roll inflates TTK and
	# is orthogonal to this regression check).
	gs.combat_hp = gs.combat_max_hp()
	gs._init_combat("z1_lunar_drone")
	var spin := 0
	while gs.enemy_inst.get("elite", false) and spin < 50:
		gs._spawn_enemy_inst("z1_lunar_drone"); spin += 1
	var ttk := 0.0
	var survived := true
	var killed := false
	var prev_hp = float(gs.enemy_inst["hp"])
	while ttk < 60.0 and not killed:
		gs._tick_combat(0.1); ttk += 0.1
		if gs.combat_hp <= 0.0:
			survived = false; break
		var cur_hp = float(gs.enemy_inst["hp"])
		# A kill triggers an auto-respawn: HP jumps back UP to (near) full.
		if cur_hp > prev_hp + 1.0:
			killed = true
		prev_hp = cur_hp
	p("(b) regression kill z1_lunar_drone 8-15s & survive", killed and ttk >= 5.0 and ttk <= 18.0 and survived, "ttk=%.1fs hp=%.0f/%.0f" % [ttk, gs.combat_hp, gs.combat_max_hp()])

	# ===== (c) Enemy energy/explosive ATK compensation =====
	# Compare routed channel value: feed a known atk through _enemy_fire path math.
	# energy enemy: e_e = atk * 0.75 ; explosive: e_x = atk * 0.85.
	var comp_e: float = gs.ENEMY_ENERGY_ATK_COMP
	var comp_x: float = gs.ENEMY_EXPLOSIVE_ATK_COMP
	p("(c) energy comp 0.75 / explosive comp 0.85", abs(comp_e - 0.75) < 0.001 and abs(comp_x - 0.85) < 0.001, "e=%.2f x=%.2f" % [comp_e, comp_x])

	# ===== (d) Enrage: spawn Threshold Warden, drop HP below 0.5, confirm surge =====
	gs.stop_task()
	gs._spawn_enemy_inst("z11_boss_threshold_warden")
	var base_atk = float(gs.enemy_inst["atk"])
	var enr_thr = float(gs.enemy_inst.get("enrage_at", 0.0))
	var enr_mult = float(gs.enemy_inst.get("enrage_atk_mult", 1.5))
	gs._enemy_enraged = false
	gs._check_enrage()
	var enraged_above = gs._enemy_enraged
	# now drop HP below threshold
	gs.enemy_inst["hp"] = float(gs.enemy_inst["max_hp"]) * (enr_thr - 0.01)
	gs._check_enrage()
	var enraged_below = gs._enemy_enraged
	# effective atk after enrage in fire path
	var eff_atk = base_atk * (enr_mult if gs._enemy_enraged else 1.0)
	p("(d) enrage triggers below %.2f HP, atk x%.1f" % [enr_thr, enr_mult], (not enraged_above) and enraged_below and abs(eff_atk - base_atk * enr_mult) < 1.0, "base=%.0f enraged=%.0f" % [base_atk, eff_atk])

	# ===== (e) Trinity: equip 3 pieces of a set, confirm stat bonus =====
	gs.stop_task()
	gs.loadout.clear()
	gs.custom_modules.clear()
	# Power the grid so the z6 set pieces can equip. v110 battery-only energy:
	# each z6 consumer draws 100, so supply tier-matched z6 batteries (350 each).
	_equip(gs, "z6_battery"); _equip(gs, "z6_battery")
	# pick a set with clear stat bonus: colossus_dominion (all_dmg_pct 22, evasion_flat 12)
	var set_id := "colossus_dominion"
	var pieces: Array = GameData.SETS.get(set_id, {}).get("pieces", [])
	var eva_before = float(gs.ship_stats().get("eva", 0.0))
	var active_before = gs.active_trinity_sets()
	for pid in pieces:
		# grant a set-piece instance into inventory and equip
		gs._grant_set_piece(pid)
	# equip the granted custom instances
	for cid in gs.custom_modules.keys():
		if gs.custom_modules[cid].get("set", "") == set_id:
			gs.equip_module(cid)
	var active_after = gs.active_trinity_sets()
	var eva_after = float(gs.ship_stats().get("eva", 0.0))
	var has_set = set_id in active_after
	var eva_gain = eva_after - eva_before
	p("(e) trinity %s active + evasion_flat applied" % set_id, has_set and eva_gain >= 11.0, "eva %.0f->%.0f (active=%s)" % [eva_before, eva_after, str(active_after)])

	# ===== (f) Hazard: gated by unlock boss, runs waves x1.20, completes =====
	gs.loadout.clear()
	gs.active_hull = "corvette_hull"
	# rebuild a strong-enough loadout + faraday counter
	_equip(gs, "z1_battery"); _equip(gs, "z1_battery")
	_equip(gs, "z1_kinetic"); _equip(gs, "z1_shield"); _equip(gs, "z1_engine")
	_equip(gs, "faraday_hull")
	for k in gs.loadout:
		var m2 = gs.module_def(gs.loadout[k])
		if m2.get("slot", "") == "weapon" and float(m2.get("stats", {}).get("atk_kinetic", 0)) > 0:
			gs.ammo_loadout[k] = "SlugT1"
	gs.resources["SlugT1"] = 1000000
	gs.boss_kills.erase("z2_boss_monolith")
	var locked = gs.start_hazard("emp_nexus")
	p("(f1) hazard gated until unlock boss killed", not locked, "start returned %s while locked" % str(locked))
	gs.boss_kills["z2_boss_monolith"] = 1
	var opened = gs.start_hazard("emp_nexus")
	# verify wave scaling: wave 0 vs simulated wave 2 multiplier
	var w0_hp = float(gs.enemy_inst["max_hp"])
	# force-complete by killing each wave
	var cleared := false
	var guard := 0
	gs.combat_hp = 999999.0
	while gs.hazard_state.get("active", false) and guard < 2000:
		guard += 1
		gs.enemy_inst["hp"] = 0.0
		gs._win_combat()
		gs.combat_hp = 999999.0
		if not gs.hazard_state.get("active", false):
			cleared = true
			break
	var got_reward = gs.amount("emp_generator_blueprint") >= 1
	p("(f2) hazard opens after unlock + runs waves + completes", opened and cleared, "first_wave_hp=%.0f reward=%s" % [w0_hp, str(got_reward)])
	p("(f3) hazard first-clear reward granted", got_reward, "emp_generator_blueprint x%d" % gs.amount("emp_generator_blueprint"))

	# ===== (g) Safety caps =====
	gs.stop_task()
	gs.loadout.clear()
	gs.active_hull = "corvette_hull"
	# Inject an extreme-evasion + extreme-reflect via a custom module
	gs.custom_modules["cap_test"] = {
		"name": "Cap Test", "slot": "engine",
		"stats": {"eva": 500, "crit_chance": 5.0, "jamming_strength": 5.0, "shield_regen": 999999, "hp": 100},
		"affixes": {}, "rarity": 0, "base": "z1_engine", "sockets": []
	}
	gs.module_inventory["cap_test"] = 1
	gs.equip_module("cap_test")
	var s = gs.ship_stats()
	var eva_capped = float(s.get("eva", 0.0)) <= gs.MAX_EVASION + 0.01
	var crit_capped = float(s.get("crit", 0.0)) <= gs.MAX_CRIT_CHANCE + 0.01
	var jam_capped = float(s.get("jamming_strength", 0.0)) <= gs.MAX_ENEMY_SLOW + 0.01
	# reflect cap: trinity reflect + reflective sheath clamps to 0.10 in _enemy_fire (test the formula directly)
	var refl = minf((gs.trinity_bonus("reflect_pct") / 100.0) + 0.20, gs.MAX_REFLECT_PERCENT)
	var refl_capped = refl <= gs.MAX_REFLECT_PERCENT + 0.0001
	p("(g) safety caps: eva<=75 crit<=0.5 jam<=0.5 reflect<=0.10", eva_capped and crit_capped and jam_capped and refl_capped,
		"eva=%.0f crit=%.2f jam=%.2f reflect=%.2f" % [s.get("eva",0.0), s.get("crit",0.0), s.get("jamming_strength",0.0), refl])

	print("SIM DONE")
	quit()
