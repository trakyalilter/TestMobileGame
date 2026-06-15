extends SceneTree
## Verifies that equipping from the Armory opens a slot picker when the module's
## type has multiple hull slots, and that choosing a slot equips into it.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _collect_buttons(node: Node, out: Array) -> void:
	if node is Button:
		out.append(node)
	for c in node.get_children():
		_collect_buttons(c, out)

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
	# Corvette has two weapon slots. Fit a battery for energy headroom, then own a weapon.
	gs.module_inventory["z1_battery"] = 1
	gs.equip_module("z1_battery")
	gs.module_inventory["z1_kinetic"] = 1
	main.ship_target_slot = -1

	# Equip from browse → multi-slot type → picker opens.
	var before: int = main._modal_stack.size()
	main._do_equip("z1_kinetic", func() -> void: pass, null)
	await process_frame
	if main._modal_stack.size() != before + 1:
		print("FAIL no slot picker opened for a multi-slot module")
		print("EQUIP_SLOT: FAIL")
		quit(1)
		return
	print("PASS slot picker opened for multi-slot module")
	var modal: Node = main._modal_stack[main._modal_stack.size() - 1]
	var btns := []
	_collect_buttons(modal, btns)
	var slot_btns := []
	for b in btns:
		if b.text.begins_with("Slot "):
			slot_btns.append(b)
	print("slot options: %d" % slot_btns.size())
	if slot_btns.size() == 2:
		print("PASS picker lists both weapon slots")
	else:
		print("FAIL expected 2 slot options, got %d" % slot_btns.size())
		fail = true

	# Choose the first slot → module equips into a weapon slot.
	if not slot_btns.is_empty():
		slot_btns[0].pressed.emit()
		await process_frame
		var equipped := false
		for k in gs.loadout:
			if gs.loadout[k] == "z1_kinetic":
				equipped = true
		print("loadout: %s" % str(gs.loadout))
		if equipped:
			print("PASS chosen slot equipped the module")
		else:
			print("FAIL module not equipped after choosing a slot")
			fail = true

	# Single-slot type (armor) equips directly — no picker.
	gs.module_inventory["z1_armor"] = 1
	var before2: int = main._modal_stack.size()
	main._do_equip("z1_armor", func() -> void: pass, null)
	await process_frame
	if main._modal_stack.size() == before2:
		print("PASS single-slot module equipped directly (no picker)")
	else:
		print("FAIL single-slot module opened a picker")
		fail = true

	if fail:
		print("EQUIP_SLOT: FAIL")
		quit(1)
	print("EQUIP_SLOT: PASS")
	quit()
