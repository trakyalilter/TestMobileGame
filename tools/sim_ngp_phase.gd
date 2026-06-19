extends SceneTree
## Verifies v0.2.1 NG+ P1 multi-phase boss gate: phase index by HP band, per-channel
## breach factors, off-element damage cut, warp_hardened parity, phase telegraph.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	var gs = root.get_node("GameState")

	var fail := false

	# Synthetic 2-phase boss: phase 0 = energy, phase 1 = cryo.
	gs.enemy_inst = {
		"hp": 100.0, "max_hp": 100.0, "shield": 0.0, "def": 0.0,
		"resist_k": 0.0, "resist_e": 0.0, "resist_x": 0.0, "resist_cryo": 0.0,
		"phases": ["energy", "cryo"], "phase_cut": 0.15,
	}

	# Full HP -> phase 0 (energy). Energy full, others cut.
	var bf0: Dictionary = gs._breach_factors("cryo")
	print("phase0 breach: %s" % str(bf0))
	if gs._phase_index(2) == 0 and bf0["e"] == 1.0 and bf0["k"] == 0.15 and bf0["cryo"] == 0.15:
		print("PASS phase 0: only energy breaches")
	else:
		print("FAIL phase 0 breach wrong")
		fail = true

	# Damage cut: kinetic does ~cut vs energy in phase 0.
	var dmg_e: float = gs.resolve_damage(0, 100, 0, 0, 0, 1, 0.0, true, 0, "cryo")[1]
	var dmg_k: float = gs.resolve_damage(100, 0, 0, 0, 0, 1, 0.0, true, 0, "cryo")[1]
	print("phase0 hull dmg: energy=%.1f kinetic=%.1f" % [dmg_e, dmg_k])
	if dmg_e > dmg_k * 3.0:
		print("PASS off-element damage is cut in phase 0")
	else:
		print("FAIL off-element not cut (e=%.1f k=%.1f)" % [dmg_e, dmg_k])
		fail = true

	# Drop to phase 1 (cryo). Now a cryo weapon breaches; energy is cut.
	gs.enemy_inst["hp"] = 40.0
	var bf1: Dictionary = gs._breach_factors("cryo")
	print("phase1 breach: %s" % str(bf1))
	if gs._phase_index(2) == 1 and bf1["cryo"] == 1.0 and bf1["e"] == 0.15:
		print("PASS phase 1: only cryo breaches")
	else:
		print("FAIL phase 1 breach wrong")
		fail = true
	# A corrosion-exotic weapon does NOT breach the cryo phase.
	var bf1_corr: Dictionary = gs._breach_factors("corrosion")
	if bf1_corr["cryo"] == 0.15:
		print("PASS wrong-exotic weapon cut in cryo phase")
	else:
		print("FAIL wrong-exotic not cut")
		fail = true

	# warp_hardened parity: k/e/x -> 0.02, cryo full only for cryo weapon.
	gs.enemy_inst = {"hp": 100.0, "max_hp": 100.0, "warp_hardened": true}
	var bh: Dictionary = gs._breach_factors("cryo")
	var bh_kin: Dictionary = gs._breach_factors("kinetic")
	if bh["k"] == 0.02 and bh["cryo"] == 1.0 and bh_kin["cryo"] == 0.02:
		print("PASS warp_hardened gate unchanged (cryo breaches, conventional x0.02)")
	else:
		print("FAIL warp_hardened parity broken: %s" % str(bh))
		fail = true

	# Non-gated enemy: all channels full.
	gs.enemy_inst = {"hp": 100.0, "max_hp": 100.0}
	var bn: Dictionary = gs._breach_factors("cryo")
	if bn["k"] == 1.0 and bn["e"] == 1.0 and bn["x"] == 1.0 and bn["cryo"] == 1.0:
		print("PASS non-gated enemy takes full damage (combat unchanged)")
	else:
		print("FAIL non-gated enemy altered")
		fail = true

	# Telegraph fires on band entry.
	gs.enemy_inst = {"hp": 100.0, "max_hp": 100.0, "phases": ["energy", "cryo"], "phase_cut": 0.15}
	gs._phase_idx = -1
	gs.combat_events = []
	gs._check_phase_transition()           # enters phase 0
	gs.enemy_inst["hp"] = 30.0
	gs._check_phase_transition()           # enters phase 1
	var phase_events := 0
	for ev in gs.combat_events:
		if "PHASE" in str(ev.get("text", "")):
			phase_events += 1
	print("phase telegraph events: %d" % phase_events)
	if phase_events >= 2:
		print("PASS phase transitions telegraph")
	else:
		print("FAIL telegraph missing (%d)" % phase_events)
		fail = true

	if fail:
		print("NGP_PHASE: FAIL")
		quit(1)
	print("NGP_PHASE: PASS")
	quit()
