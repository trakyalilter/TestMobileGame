extends Node

# niv_0 — INDEPENDENT verification probe for the v149 uniform-cadence change.
# Self-contained A/B in ONE process: pushes the CURRENT authored values and the
# PRE-CHANGE authored values (below, extracted from git HEAD d77f1c2) through the
# SAME real spawn_enemy pipeline, so the comparison cannot drift on engine state.
# Read-only: mutates enemy_db in memory only, restores after each measurement.

const OLD_AUTHORED := {
	"z1_dust_mite": [8.0, 3.0],
	"z1_lunar_drone": [13.0, 2.5],
	"z1_survey_probe": [10.0, 1.5],
	"z1_scrap_collector": [15.0, 2.0],
	"z1_boss_architect": [40.0, 3.0],
	"z2_pirate_skiff": [25.0, 1.8],
	"z2_silicate_golem": [33.0, 3.0],
	"z2_claim_jumper": [28.0, 2.2],
	"z2_ore_hauler": [65.0, 5.0],
	"z2_boss_monolith": [220.0, 3.5],
	"z3_scavenger_mech": [40.0, 2.5],
	"z3_martian_sentry": [47.0, 2.0],
	"z3_salvage_swarm": [26.0, 0.6],
	"z3_derelict_frigate": [82.0, 4.0],
	"z3_boss_warmaster": [189.0, 2.5],
	"z4_ice_wraith": [125.0, 1.5],
	"z4_cryo_sentinel": [160.0, 2.5],
	"z4_frost_hulk": [138.0, 4.0],
	"z4_glacial_drone": [140.0, 1.8],
	"z4_boss_overseer": [480.0, 2.5],
	"z5_xenon_scout": [275.0, 1.5],
	"z5_xenon_corvette": [352.0, 2.0],
	"z5_alien_frigate": [388.0, 3.0],
	"z5_alien_probe": [195.0, 1.2],
	"z5_boss_harbinger": [760.0, 2.5],
	"z6_defense_turret": [613.0, 2.5],
	"z6_mining_golem": [773.0, 3.5],
	"z6_rad_beast": [850.0, 2.0],
	"z6_ore_guardian": [688.0, 3.0],
	"z6_boss_colossus": [2100.0, 2.5],
	"z7_shard_swarm": [980.0, 0.8],
	"z7_energy_wraith": [1700.0, 2.0],
	"z7_void_hunter": [1875.0, 1.5],
	"z7_gamma_beast": [1500.0, 3.5],
	"z7_boss_sovereign": [6006.0, 2.5],
	"z8_prism_drone": [3000.0, 1.5],
	"z8_crystal_golem": [3742.0, 3.5],
	"z8_void_stalker": [4125.0, 2.0],
	"z8_nebula_phantom": [3375.0, 2.5],
	"z8_boss_warden": [12200.0, 2.5],
	"z9_plague_drone": [6500.0, 1.2],
	"z9_bio_horror": [8230.0, 2.5],
	"z9_rogue_ai": [9000.0, 1.5],
	"z9_quarantine_mech": [7500.0, 3.5],
	"z9_boss_patient_zero": [26500.0, 2.5],
	"z10_void_stalker": [14375.0, 2.0],
	"z10_temporal_phantom": [18105.0, 1.5],
	"z10_omega_sentinel": [16250.0, 2.5],
	"z10_primordial_titan": [20000.0, 4.0],
	"z10_boss_leviathan": [80000.0, 3.0],
	"z11_warp_revenant": [36000.0, 2.0],
	"z11_phase_horror": [42000.0, 1.5],
	"z11_null_sentinel": [38000.0, 2.5],
	"z11_exotic_leviathan": [50000.0, 4.0],
	"z11_boss_threshold_warden": [350000.0, 2.5],
	"z12_acid_revenant": [90000.0, 2.0],
	"z12_rust_horror": [100000.0, 1.5],
	"z12_corrosion_sentinel": [95000.0, 2.5],
	"z12_caustic_leviathan": [120000.0, 4.0],
	"z12_boss_rift_warden": [320000.0, 2.5],
	"z13_blight_drone": [130000.0, 2.0],
	"z13_corroded_golem": [145000.0, 1.5],
	"z13_acid_serpent": [140000.0, 2.5],
	"z13_patina_phantom": [160000.0, 4.0],
	"z13_boss_verdigris_warden": [300000.0, 2.5],
	"z14_dissolution_wraith": [155000.0, 2.0],
	"z14_caustic_golem": [170000.0, 1.5],
	"z14_rot_leviathan": [165000.0, 2.5],
	"z14_toxin_sentinel": [185000.0, 4.0],
	"z14_boss_dissolution_tyrant": [230000.0, 2.5],
	"z15_caustic_revenant": [180000.0, 2.0],
	"z15_meltdown_colossus": [200000.0, 1.5],
	"z15_corrosion_behemoth": [195000.0, 2.5],
	"z15_blight_titan": [220000.0, 4.0],
	"z15_boss_caustic_sovereign": [190000.0, 2.5],
	"hz_emp_drone_1": [40.0, 2.0],
	"hz_emp_drone_2": [50.0, 3.0],
	"hz_emp_drone_3": [35.0, 1.5],
	"hz_emp_drone_4": [55.0, 3.5],
	"hz_emp_drone_5": [45.0, 2.0],
	"hz_emp_elite": [100.0, 2.5],
	"hz_emp_overlord": [200.0, 2.0],
}

func _pipe(cm, zid, eid) -> Array:
	cm.current_zone = cm.zones[zid]
	cm.current_zone_id = String(zid)
	cm.target_enemy_id = eid
	var guard := 0
	cm.spawn_enemy()
	while bool(cm.current_enemy.get("is_elite", false)) and guard < 500:
		cm.spawn_enemy()
		guard += 1
	if bool(cm.current_enemy.get("is_elite", false)):
		return [-1.0, -1.0]
	return [float(cm.current_enemy.get("atk", 0)), float(cm.current_enemy.get("atk_interval", 0.0))]

func _ready() -> void:
	GameState.hard_reset()
	var cm = GameState.combat_manager
	var smk = load("res://scripts/managers/shipyard_manager.gd")
	var worst_abs := 0.0
	var worst_line := ""
	var over1 := 0
	var n := 0
	var seen := {}
	for zid in cm.zones.keys():
		var z: Dictionary = cm.zones[zid]
		for eid in z.get("enemies", []):
			if not cm.enemy_db.has(eid):
				continue
			var key: String = String(zid) + "|" + String(eid)
			if seen.has(key):
				continue
			seen[key] = true
			if not OLD_AUTHORED.has(eid):
				print("[NIV0] MISSING-OLD %s" % eid)
				continue
			var e: Dictionary = cm.enemy_db[eid]
			var st: Dictionary = e["stats"]
			var cur_atk = st["atk"]
			var cur_iv = st["atk_interval"]
			# NEW side
			var rn: Array = _pipe(cm, zid, eid)
			# OLD side: re-apply the SAME _apply_enemy_tier_rebase rule to the old
			# authored atk (int(round(x * tier_rebase(zone))) for zone >= 2), then
			# push it through the identical pipeline.
			var ez: int = int(e.get("zone", 0))
			var oa: float = float(OLD_AUTHORED[eid][0])
			var oiv: float = float(OLD_AUTHORED[eid][1])
			var ob = oa
			if ez > 1:
				ob = int(round(oa * smk.tier_rebase(ez)))
			st["atk"] = ob
			st["atk_interval"] = oiv
			var ro: Array = _pipe(cm, zid, eid)
			st["atk"] = cur_atk
			st["atk_interval"] = cur_iv
			if rn[0] < 0.0 or ro[0] < 0.0:
				print("[NIV0] ELITE-STUCK %s" % key)
				continue
			var dn: float = rn[0] / maxf(0.0001, rn[1])
			var do_: float = ro[0] / maxf(0.0001, ro[1])
			var err: float = (dn / maxf(0.000001, do_) - 1.0) * 100.0
			n += 1
			if absf(err) > 1.0:
				over1 += 1
				print("[NIV0] OVER1 %-34s old %s@%s -> new %s@%s  dps %.4f -> %.4f  err %+.4f%%" % [key, str(ro[0]), str(ro[1]), str(rn[0]), str(rn[1]), do_, dn, err])
			if absf(err) > worst_abs:
				worst_abs = absf(err)
				worst_line = "%-34s old %s@%s -> new %s@%s  dps %.4f -> %.4f  err %+.4f%%" % [key, str(ro[0]), str(ro[1]), str(rn[0]), str(rn[1]), do_, dn, err]
	print("[NIV0] SAMPLES=%d  OVER_1PCT=%d" % [n, over1])
	print("[NIV0] WORST %s" % worst_line)
	# coverage: any enemy still off the uniform base?
	var bad := 0
	for eid in cm.enemy_db:
		var iv2: float = float(cm.enemy_db[eid]["stats"].get("atk_interval", -1.0))
		if absf(iv2 - cm.DEFAULT_ATTACK_INTERVAL) > 0.0001:
			bad += 1
			print("[NIV0] NONUNIFORM-ENEMY %s iv=%s" % [eid, str(iv2)])
	print("[NIV0] ENEMIES=%d NONUNIFORM=%d" % [cm.enemy_db.size(), bad])
	var sm = GameState.shipyard_manager
	var wbad := 0
	var wn := 0
	for mid in sm.modules:
		var m: Dictionary = sm.modules[mid]
		if String(m.get("slot_type", "")) != "weapon":
			continue
		wn += 1
		var wiv: float = float(m.get("stats", {}).get("atk_interval", -1.0))
		if absf(wiv - cm.DEFAULT_ATTACK_INTERVAL) > 0.0001:
			wbad += 1
			print("[NIV0] NONUNIFORM-WEAPON %s iv=%s" % [mid, str(wiv)])
	print("[NIV0] WEAPONS=%d NONUNIFORM=%d" % [wn, wbad])
	get_tree().quit()
