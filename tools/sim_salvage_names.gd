extends SceneTree
## Verifies the salvage panel resolves a sold/scrapped module's name from its cid
## instead of showing the raw "cm_..."/"set_..." id.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	var gd = root.get_node("GameData")
	for n in range(1, gs.SLOT_COUNT + 1):
		gs.delete_slot(n)
	gs.new_character(1, "Tester")
	if is_instance_valid(main._char_select):
		main._char_select.queue_free()
		main._char_select = null

	var fail := false

	# Roll a real module, then scrap it (removes the custom_modules entry) while it
	# stays in session_loot — the leak the user saw.
	var cid: String = gs.generate_module("z2_kinetic", 2, 2)
	gs._log_session_loot(cid, 1)
	print("cid = %s" % cid)
	# Resolves to its proper name while owned.
	var owned_name = main._loot_display(cid)[0]
	if "_" not in owned_name:
		print("PASS owned module resolves to a name (%s)" % owned_name)
	else:
		print("FAIL owned module shows raw id (%s)" % owned_name)
		fail = true
	# Scrap it (sell removes from custom_modules); session_loot still references it.
	gs.sell_module(cid)
	var after = main._loot_display(cid)[0]
	print("after scrap: %s" % after)
	var base_name: String = gd.item_name("z2_kinetic")
	if after == base_name and not after.begins_with("cm_"):
		print("PASS scrapped module resolves to base name '%s' (no raw cid)" % base_name)
	else:
		print("FAIL scrapped module shows '%s' (expected '%s')" % [after, base_name])
		fail = true

	# Set-piece cid fallback.
	var scid: String = gs._grant_set_piece("z2_unique_weapon")
	gs._log_session_loot(scid, 1)
	gs.custom_modules.erase(scid)   # simulate it being gone
	var set_after = main._loot_display(scid)[0]
	print("set fallback: %s" % set_after)
	if set_after == gd.item_name("z2_unique_weapon"):
		print("PASS set-piece cid resolves to set name")
	else:
		print("FAIL set-piece cid wrong (%s)" % set_after)
		fail = true

	# Plain resources unaffected.
	if main._loot_display("Fe")[0] == gd.res_name("Fe") and main._cid_base("Fe") == "":
		print("PASS plain resource id unaffected")
	else:
		print("FAIL resource id mis-parsed")
		fail = true

	if fail:
		print("SALVAGE_NAMES: FAIL")
		quit(1)
	print("SALVAGE_NAMES: PASS")
	quit()
