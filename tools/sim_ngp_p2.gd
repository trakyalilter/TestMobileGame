extends SceneTree
## Verifies v0.2.1 NG+ P2 in-fight loadout swap: only legal vs a multi-phase boss,
## loads a preset mid-fight, rebuilds the weapon snapshot, no free heal.

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

	# Gating: not in combat -> no swap.
	if not gs.can_swap_loadout_in_combat():
		print("PASS swap disabled out of combat")
	else:
		print("FAIL swap allowed out of combat")
		fail = true

	# v134h parity: the swap is no longer gated to phase bosses. Desktop's
	# load_loadout_preset has no combat gate at all, so any live fight can swap;
	# only the PHASE-GATE PANEL stays boss-only. This used to assert the old
	# multi-phase-only rule.
	gs.active_type = "combat"
	gs.active_id = "z1_lunar_drone"
	gs._spawn_enemy_inst("z1_lunar_drone")
	if gs.can_swap_loadout_in_combat():
		print("PASS swap available in an ordinary fight (v134h)")
	else:
		print("FAIL swap refused in an ordinary fight")
		fail = true

	# Multi-phase boss -> swap available.
	gs.active_id = "z12_boss_rift_warden"
	gs._spawn_enemy_inst("z12_boss_rift_warden")
	if gs.can_swap_loadout_in_combat():
		print("PASS swap available vs multi-phase boss")
	else:
		print("FAIL swap unavailable vs phase boss")
		fail = true

	# Build a Corrosion preset (battery first so the weapon has power on load).
	gs.module_inventory["z10_battery"] = 1
	gs.module_inventory["corrosion_blaster"] = 1
	gs.loadout_presets[2] = {"name": "Corrosion", "loadout": {"5": "z10_battery", "0": "corrosion_blaster"}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""}

	# Mid-fight: record player HP, swap, verify corrosion equipped + no heal.
	var hp_before: float = gs.combat_hp
	gs.combat_hp = gs.combat_max_hp() * 0.5   # damaged
	var dmg_hp: float = gs.combat_hp
	var ok: bool = gs.swap_loadout_in_combat(2)
	print("swap result=%s loadout=%s" % [str(ok), str(gs.loadout)])
	var has_corr := false
	for k in gs.loadout:
		if gs.loadout[k] == "corrosion_blaster":
			has_corr = true
	var w_has_corr := false
	for w in gs._weapons:
		if w.get("name", "") == "Corrosion Blaster" and w.get("exotic_type", "") == "corrosion":
			w_has_corr = true
	if ok and has_corr and w_has_corr:
		print("PASS swap equipped corrosion + rebuilt weapon snapshot")
	else:
		print("FAIL swap did not apply (ok=%s loadout_corr=%s weap_corr=%s)" % [str(ok), str(has_corr), str(w_has_corr)])
		fail = true
	if abs(gs.combat_hp - dmg_hp) < 0.001:
		print("PASS no free heal on swap (HP unchanged)")
	else:
		print("FAIL swap healed (%.0f -> %.0f)" % [dmg_hp, gs.combat_hp])
		fail = true

	# An empty preset can't be swapped to.
	if not gs.swap_loadout_in_combat(3):
		print("PASS empty preset swap rejected")
	else:
		print("FAIL empty preset swap accepted")
		fail = true

	# Combat page shows the swap UI vs a phase boss.
	main._refresh_all()
	main._show("combat")
	await process_frame
	main._refresh_current()
	await process_frame
	var t := []
	_collect_text(main.pages["combat"], t)
	if _has(t, "SWAP LOADOUT"):
		print("PASS combat page shows the phase-gate swap UI")
	else:
		print("FAIL swap UI missing on combat page")
		fail = true

	if fail:
		print("NGP_P2: FAIL")
		quit(1)
		return
	print("NGP_P2: PASS")
	quit()

func _collect_text(node: Node, out: Array) -> void:
	if node is Label or node is Button:
		out.append(node.text)
	for c in node.get_children():
		_collect_text(c, out)

func _has(texts: Array, needle: String) -> bool:
	for t in texts:
		if needle in t:
			return true
	return false
