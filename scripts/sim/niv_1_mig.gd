extends Node
# INDEPENDENT VERIFICATION PROBE (niv_1) — v149 save migration.
# Goes beyond ivmig_probe: real load_save_data_manager round-trip, idempotency
# (load -> save -> load), the "_unique_weapon" missiles, and a multi-channel roll.

func _ready() -> void:
	var sm = GameState.shipyard_manager
	GameState.hard_reset()

	# Synthetic PRE-v149 save payload. All intervals are legal rolls off the OLD
	# bases (missile 4.0 -> [2.40, 4.00]; kinetic/energy 2.0 -> [1.20, 2.00]).
	var cm_payload := {
		"m_missile_mid": {"base_module": "z3_missile", "rarity": 2, "sockets": [],
			"stats": {"atk_explosive": 113.0, "energy_load": 30, "atk_interval": 3.60}},
		"m_missile_floor": {"base_module": "z3_missile", "rarity": 4, "sockets": [],
			"stats": {"atk_explosive": 150.0, "energy_load": 30, "atk_interval": 2.40}},
		"m_missile_max": {"base_module": "z10_missile", "rarity": 1, "sockets": [],
			"stats": {"atk_explosive": 23000.0, "energy_load": 500, "atk_interval": 4.00}},
		"m_uniq_weapon_z5": {"base_module": "z5_unique_weapon", "rarity": 4, "sockets": [],
			"stats": {"atk_explosive": 1000.0, "energy_load": 90, "atk_interval": 2.90}},
		"m_uniq_weapon_z10": {"base_module": "z10_unique_weapon", "rarity": 4, "sockets": [],
			"stats": {"atk_explosive": 50000.0, "energy_load": 600, "atk_interval": 3.10}},
		"m_kin": {"base_module": "z3_kinetic", "rarity": 3, "sockets": [],
			"stats": {"atk_kinetic": 60.0, "energy_load": 18, "atk_interval": 1.55}},
		"m_nrg_maxroll": {"base_module": "z3_energy", "rarity": 4, "sockets": [],
			"stats": {"atk_energy": 90.0, "energy_load": 25, "atk_interval": 2.00}},
		"m_cryo": {"base_module": "cryo_lance", "rarity": 0, "sockets": [],
			"stats": {"atk_cryo": 40000.0, "atk_interval": 2.00}},
	}
	var before := {}
	for k in cm_payload:
		var st: Dictionary = cm_payload[k]["stats"]
		before[k] = [_dmg(st), float(st["atk_interval"]), _dmg(st) / float(st["atk_interval"])]

	var save := {"custom_modules": cm_payload.duplicate(true), "inventory": {}, "loadout": {},
		"active_hull": sm.active_hull, "unseen_modules": {}, "armory_layout": {}}
	sm.load_save_data_manager(save)

	print("[NIV1] --- PASS 1 (load of a pre-v149 save) ---")
	var pass1 := {}
	for k in cm_payload:
		var st2: Dictionary = sm.custom_modules[k]["stats"]
		var d := _dmg(st2)
		var iv := float(st2["atk_interval"])
		pass1[k] = [d, iv, d / iv]
		var err: float = (d / iv - float(before[k][2])) / float(before[k][2]) * 100.0
		var alias: bool = sm.modules.get(k, {}) == sm.custom_modules[k]
		print("[NIV1] %-18s dmg %9.3f@%.2f (dps %10.4f)  ->  %9.3f@%.2f (dps %10.4f)  DPS ERR %+.9f%%  aliased=%s" % [
			k, before[k][0], before[k][1], before[k][2], d, iv, d / iv, err, str(alias)])

	# IDEMPOTENCY: save what we now have and load it again (a normal relog).
	var save2 := {"custom_modules": sm.custom_modules.duplicate(true), "inventory": {}, "loadout": {},
		"active_hull": sm.active_hull, "unseen_modules": {}, "armory_layout": {}}
	sm.load_save_data_manager(save2)
	print("[NIV1] --- PASS 2 (relog: must be a NO-OP) ---")
	var bad := 0
	for k in cm_payload:
		var st3: Dictionary = sm.custom_modules[k]["stats"]
		var d3 := _dmg(st3)
		var iv3 := float(st3["atk_interval"])
		var drift: float = (d3 / iv3 - float(pass1[k][2])) / float(pass1[k][2]) * 100.0
		if absf(drift) > 1e-9 or absf(d3 - float(pass1[k][0])) > 1e-6:
			bad += 1
			print("[NIV1] NOT IDEMPOTENT %s  %.4f@%.2f -> %.4f@%.2f  (dps drift %+.6f%%)" % [
				k, pass1[k][0], pass1[k][1], d3, iv3, drift])
	print("[NIV1] IDEMPOTENCY: %s (%d drifting entries)" % ["OK" if bad == 0 else "BROKEN", bad])

	# Every authored weapon base must sit at the constant.
	var off := 0
	for mid in sm.modules:
		if mid in cm_payload:
			continue
		var st4: Dictionary = sm.modules[mid].get("stats", {})
		if st4.has("atk_interval") and absf(float(st4["atk_interval"]) - GameState.combat_manager.DEFAULT_ATTACK_INTERVAL) > 1e-9:
			off += 1
			print("[NIV1] AUTHORED BASE OFF-CONSTANT: %s iv=%s" % [mid, str(st4["atk_interval"])])
	print("[NIV1] AUTHORED WEAPON BASES OFF-CONSTANT: %d" % off)
	get_tree().quit()

func _dmg(st: Dictionary) -> float:
	return float(st.get("atk_kinetic", 0)) + float(st.get("atk_energy", 0)) \
		+ float(st.get("atk_explosive", 0)) + float(st.get("atk_cryo", 0))
