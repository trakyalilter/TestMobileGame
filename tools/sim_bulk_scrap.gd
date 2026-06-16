extends SceneTree
## Verifies bulk "scrap junk" sells unequipped low-rarity modules (keeping equipped
## and higher-rarity gear) — the crowded-Armory fix.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

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

	var fail := false

	# Hand-build an inventory: commons + uncommons (unequipped), one rare, one
	# equipped uncommon.
	gs.custom_modules["c_common"] = {"name": "Junk A", "slot": "weapon", "rarity": 0, "stats": {}, "affixes": {}}
	gs.module_inventory["c_common"] = 1
	gs.custom_modules["c_unc"] = {"name": "Junk B", "slot": "weapon", "rarity": 1, "stats": {}, "affixes": {}}
	gs.module_inventory["c_unc"] = 2
	gs.custom_modules["c_rare"] = {"name": "Keep Rare", "slot": "weapon", "rarity": 2, "stats": {}, "affixes": {}}
	gs.module_inventory["c_rare"] = 1
	gs.custom_modules["c_eq"] = {"name": "Equipped Unc", "slot": "weapon", "rarity": 1, "stats": {}, "affixes": {}}
	gs.module_inventory["c_eq"] = 1
	gs.loadout["0"] = "c_eq"   # equipped → must never be scrapped

	# count_bulk_sell(1): unequipped rarity<=1 → c_common(1) + c_unc(2) = 3.
	var cnt: int = gs.count_bulk_sell(1)
	print("count_bulk_sell(<=Uncommon) = %d (expect 3)" % cnt)
	if cnt == 3:
		print("PASS scrap count excludes equipped + higher rarity")
	else:
		print("FAIL scrap count wrong")
		fail = true

	var cr0: int = gs.credits
	var sold: int = gs.bulk_sell_by_rarity(1)
	print("sold = %d, credits +%d" % [sold, gs.credits - cr0])
	if sold == 3:
		print("PASS bulk scrap sold all 3 junk modules")
	else:
		print("FAIL bulk scrap sold %d" % sold)
		fail = true
	if not gs.module_inventory.has("c_common") and not gs.module_inventory.has("c_unc"):
		print("PASS junk removed from inventory")
	else:
		print("FAIL junk still present")
		fail = true
	if int(gs.module_inventory.get("c_rare", 0)) == 1 and int(gs.module_inventory.get("c_eq", 0)) == 1:
		print("PASS rare + equipped modules preserved")
	else:
		print("FAIL preserved-gear check failed")
		fail = true
	if gs.credits > cr0:
		print("PASS scrapping granted credits")
	else:
		print("FAIL no credits from scrap")
		fail = true

	# Armory renders the scrap controls when junk exists.
	gs.custom_modules["c_common2"] = {"name": "Junk C", "slot": "weapon", "rarity": 0, "stats": {}, "affixes": {}}
	gs.module_inventory["c_common2"] = 1
	main.ship_mod_slot = "weapon"
	main.ship_view = "armory"
	main._show("ship")
	await process_frame
	var txts := []
	_collect_text(main.pages["ship"], txts)
	var has_scrap := false
	for t in txts:
		if t.begins_with("Scrap "):
			has_scrap = true
	if has_scrap:
		print("PASS Armory shows scrap controls")
	else:
		print("FAIL Armory missing scrap controls")
		fail = true

	if fail:
		print("BULK_SCRAP: FAIL")
		quit(1)
	print("BULK_SCRAP: PASS")
	quit()

func _collect_text(node: Node, out: Array) -> void:
	if node is Label or node is Button:
		out.append(node.text)
	for c in node.get_children():
		_collect_text(c, out)
