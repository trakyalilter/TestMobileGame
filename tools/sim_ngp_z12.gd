extends SceneTree
## Verifies v0.2.1 NG+ P3 (Z12 The Rift): data present, corrosion weapon exotic
## type, Rift Warden 2-phase gate breached only by the matching armament, and the
## Z11-boss-clear -> warp reveal -> z12_unlocked wiring + zone gate.

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

	# v137 frontier ladder: a boss kill only marks its sector CLEARED. The next
	# sector opens on the following Warp (_reveal_ng_sectors), so the two flags are
	# deliberately separate — this used to assert the kill unlocked Z12 directly.
	gs.game_flags.erase("z11_cleared")
	gs.game_flags.erase("z12_unlocked")
	gs.active_id = "z11_boss_threshold_warden"
	gs._spawn_enemy_inst("z11_boss_threshold_warden")
	gs.enemy_inst["hp"] = 0.0
	gs._win_combat()
	if gs.game_flags.get("z11_cleared", false):
		print("PASS clearing the Z11 boss marks the sector cleared")
	else:
		print("FAIL z11_cleared not set on Z11 boss kill")
		fail = true
	if gs.game_flags.get("z12_unlocked", false):
		print("FAIL Z12 unlocked on the kill — it must wait for the Warp")
		fail = true
	else:
		print("PASS Sector 12 stays shut until the next Warp")
	gs._reveal_ng_sectors()
	if gs.game_flags.get("z12_unlocked", false):
		print("PASS warping opens Sector 12 for a cleared frontier")
	else:
		print("FAIL z12_unlocked not set by the warp-time reveal")
		fail = true
	# Every cleared-flag the kill table can set needs a reveal row, or that sector
	# is cleared and then never opens.
	for kid in gs.NG_CLEAR_TABLE:
		var cf: String = String((gs.NG_CLEAR_TABLE[kid] as Array)[0])
		var revealed := false
		for r in gs.NG_REVEAL:
			if String((r as Array)[0]) == cf:
				revealed = true
		if not revealed:
			print("FAIL '%s' is set by a kill but no warp reveal consumes it" % cf)
			fail = true
	print("frontier ladder: %d clear flags, %d reveal rows" % [gs.NG_CLEAR_TABLE.size(), gs.NG_REVEAL.size()])

	if fail:
		print("NGP_Z12: FAIL")
		quit(1)
		return
	print("NGP_Z12: PASS")
	quit()
