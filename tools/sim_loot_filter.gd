extends SceneTree
## Verifies the loot filter skips filtered module drops (rarity / slot / weapon
## type) and that the salvage panel caps its height + scrolls when long.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _find_scroll_with_loot(node: Node, main):
	# The salvage scroller is main._loot_scroll.
	return main._loot_scroll

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	for n in range(1, gs.SLOT_COUNT + 1):
		gs.delete_slot(n)
	gs.new_character(1, "Tester")
	if is_instance_valid(main._char_select):
		main._char_select.queue_free()
		main._char_select = null
	main._refresh_all()
	await process_frame

	var fail := false

	# --- Filter logic. Find a base weapon and a base armor module.
	var weapon_base := ""
	var armor_base := ""
	for mid in GameData.MODULES:
		var slot = GameData.MODULES[mid].get("slot", "")
		if slot == "weapon" and weapon_base == "":
			weapon_base = mid
		elif slot == "armor" and armor_base == "":
			armor_base = mid
	# All on by default → kept.
	if gs.loot_drop_kept(weapon_base, 2) and gs.loot_drop_kept(armor_base, 3):
		print("PASS default filter keeps everything")
	else:
		print("FAIL default filter dropped something")
		fail = true
	# Turn off rarity 2 → that weapon at rarity 2 filtered, rarity 3 still kept.
	gs.loot_filter[2] = false
	if not gs.loot_drop_kept(weapon_base, 2) and gs.loot_drop_kept(weapon_base, 3):
		print("PASS rarity filter skips rarity 2")
	else:
		print("FAIL rarity filter wrong")
		fail = true
	gs.loot_filter[2] = true
	# Turn off armor slot → armor drops filtered, weapon kept.
	gs.loot_type_filter["armor"] = false
	if not gs.loot_drop_kept(armor_base, 3) and gs.loot_drop_kept(weapon_base, 3):
		print("PASS slot filter skips armor")
	else:
		print("FAIL slot filter wrong")
		fail = true
	gs.loot_type_filter["armor"] = true
	# Weapon damage-type filter: determine the weapon's type, disable it.
	var st = GameData.MODULES[weapon_base].get("stats", {})
	var wtype = "kinetic"
	if float(st.get("atk_cryo", 0)) > 0: wtype = "cryo"
	elif float(st.get("atk_energy", 0)) > 0: wtype = "energy"
	elif float(st.get("atk_explosive", 0)) > 0: wtype = "explosive"
	gs.loot_weapon_type_filter[wtype] = false
	if not gs.loot_drop_kept(weapon_base, 3):
		print("PASS weapon-type filter skips %s weapons" % wtype)
	else:
		print("FAIL weapon-type filter wrong")
		fail = true
	gs.loot_weapon_type_filter[wtype] = true

	# --- Persistence: filter survives save/load round-trip.
	gs.loot_filter[0] = false
	gs.save_game()
	gs.loot_filter[0] = true
	gs.load_game()
	if gs.loot_filter[0] == false:
		print("PASS loot filter persists through save/load")
	else:
		print("FAIL loot filter not saved")
		fail = true
	gs.loot_filter[0] = true

	# --- Salvage panel: caps height + scrolls when long.
	gs.start_task("combat", "z1_lunar_drone")
	for i in range(40):
		gs._log_session_loot("loot_%d" % i, 1)
	# Pretend resources for display (unknown ids resolve to themselves).
	main._show("combat")
	await process_frame
	main._refresh_current()
	await process_frame
	var sc: ScrollContainer = main._loot_scroll
	if sc == null:
		print("FAIL no salvage scroll container")
		fail = true
	else:
		print("salvage rows=%d scroll_h=%.0f content_h=%.0f" % [gs.session_loot.size(), sc.custom_minimum_size.y, sc.get_child(0).get_combined_minimum_size().y])
		var vbar := sc.get_v_scroll_bar()
		if sc.custom_minimum_size.y > 0 and (vbar.max_value - vbar.page) > 1.0:
			print("PASS long salvage list is capped + scrollable")
		else:
			print("FAIL salvage list not scrollable (h=%.0f)" % sc.custom_minimum_size.y)
			fail = true

	# --- Filter modal opens.
	var before = main._modal_stack.size()
	main._open_loot_filter()
	await process_frame
	if main._modal_stack.size() == before + 1:
		print("PASS loot filter modal opens")
	else:
		print("FAIL loot filter modal did not open")
		fail = true

	if fail:
		print("LOOT_FILTER: FAIL")
		quit(1)
	print("LOOT_FILTER: PASS")
	quit()
