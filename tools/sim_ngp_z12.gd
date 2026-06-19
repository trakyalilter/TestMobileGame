extends SceneTree
## Verifies v0.2.1 NG+ P3 (Z12 The Rift): data present, corrosion weapon exotic
## type, Rift Warden 2-phase gate breached only by the matching armament, and the
## Z11-boss-clear -> z12_unlocked wiring + zone gate.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	var gs = root.get_node("GameState")
	for n in range(1, gs.SLOT_COUNT + 1):
		gs.delete_slot(n)
	gs.new_character(1, "Tester")
	if is_instance_valid(main._char_select):
		main._char_select.queue_free()
		main._char_select = null

	var fail := false

	# Data present.
	var ok_data := GameData.MODULES.has("corrosion_blaster") and GameData.ZONES.any(func(z): return z.get("name","") == "Sector 12 — The Rift") and GameData.ENEMIES.has("z12_boss_rift_warden") and GameData.RESEARCH.has("corrosion_armaments")
	if ok_data:
		print("PASS Z12 data present (weapon/zone/boss/research)")
	else:
		print("FAIL Z12 data missing")
		fail = true
	# Boss phases.
	var ph: Array = GameData.ENEMIES["z12_boss_rift_warden"].get("phases", [])
	if ph == ["cryo", "corrosion"]:
		print("PASS Rift Warden is a 2-phase boss (cryo->corrosion)")
	else:
		print("FAIL boss phases wrong: %s" % str(ph))
		fail = true
	# Corrosion weapon gated by research.
	if GameData.MODULES["corrosion_blaster"].get("research_req","") == "corrosion_armaments":
		print("PASS corrosion blaster gated by corrosion_armaments")
	else:
		print("FAIL corrosion weapon research gate wrong")
		fail = true

	# Equip corrosion blaster -> weapon carries exotic_type "corrosion".
	gs.module_inventory["corrosion_blaster"] = 1
	gs.loadout["0"] = "corrosion_blaster"   # slot 0 is a weapon slot on the corvette
	var wx := ""
	for w in gs.ship_weapons():
		if w.get("name","") == "Corrosion Blaster":
			wx = String(w.get("exotic_type",""))
	print("corrosion weapon exotic_type = %s" % wx)
	if wx == "corrosion":
		print("PASS corrosion weapon tagged exotic_type=corrosion")
	else:
		print("FAIL corrosion weapon exotic_type wrong (%s)" % wx)
		fail = true

	# Spawn the Rift Warden; in phase 2 (corrosion) only a corrosion weapon breaches.
	gs._spawn_enemy_inst("z12_boss_rift_warden")
	gs.enemy_inst["hp"] = gs.enemy_inst["max_hp"] * 0.2   # deep in band 2
	var bf_corr: Dictionary = gs._breach_factors("corrosion")
	var bf_cryo: Dictionary = gs._breach_factors("cryo")
	print("phase2 breach: corrosion.cryo=%.2f cryo.cryo=%.2f" % [bf_corr["cryo"], bf_cryo["cryo"]])
	if bf_corr["cryo"] == 1.0 and bf_cryo["cryo"] == 0.15:
		print("PASS phase 2 breached by corrosion, not cryo")
	else:
		print("FAIL phase-2 exotic gate wrong")
		fail = true
	# Phase 1 (cryo): cryo breaches, corrosion does not.
	gs.enemy_inst["hp"] = gs.enemy_inst["max_hp"] * 0.95
	if gs._breach_factors("cryo")["cryo"] == 1.0 and gs._breach_factors("corrosion")["cryo"] == 0.15:
		print("PASS phase 1 breached by cryo, not corrosion")
	else:
		print("FAIL phase-1 exotic gate wrong")
		fail = true

	# Z11-boss clear unlocks Z12 (the_rift gated by z12_unlocked flag).
	gs.game_flags.erase("z12_unlocked")
	gs.active_id = "z11_boss_threshold_warden"
	gs._spawn_enemy_inst("z11_boss_threshold_warden")
	gs.enemy_inst["hp"] = 0.0
	gs._win_combat()
	if gs.game_flags.get("z12_unlocked", false):
		print("PASS clearing Z11 boss unlocks Sector 12")
	else:
		print("FAIL z12_unlocked not set on Z11 boss kill")
		fail = true

	if fail:
		print("NGP_Z12: FAIL")
		quit(1)
	print("NGP_Z12: PASS")
	quit()
