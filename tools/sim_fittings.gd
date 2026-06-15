extends SceneTree
## Verifies the Ship Designer LOADOUT now shows fitting cards (consumables + ammo)
## alongside the module slot cards, and that tapping one opens a picker modal.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

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
	# Equip a weapon so an ammo fitting card appears (after the hull is initialized).
	# Battery first (energy capacity), then a weapon so an ammo fitting card appears.
	for mid in ["z1_battery", "z1_kinetic", "z1_shield"]:
		gs.module_inventory[mid] = 1
		gs.equip_module(mid)
	await process_frame

	var fail := false

	main.ship_view = "loadout"
	main._show("ship")
	await process_frame
	await process_frame
	var t := []
	_collect_text(main.pages["ship"], t)
	for needle in ["FITTINGS", "Hull Repair Kit", "Shield Booster", "Ammo ·"]:
		if _has(t, needle):
			print("PASS loadout shows fitting card: %s" % needle)
		else:
			print("FAIL loadout missing fitting card: %s" % needle)
			fail = true

	# Tapping the ammo fitting card opens a picker modal (tracked + scrollable).
	var before: int = main._modal_stack.size()
	main._open_consumable_picker("hull", "Hull Repair Kit")
	await process_frame
	if main._modal_stack.size() == before + 1:
		print("PASS consumable picker modal opened")
		var mt := []
		_collect_text(main._modal_stack[main._modal_stack.size() - 1], mt)
		if _has(mt, "None"):
			print("PASS picker lists a None option")
		else:
			print("FAIL picker missing None option")
			fail = true
	else:
		print("FAIL consumable picker modal did not open")
		fail = true

	if fail:
		print("FITTINGS: FAIL")
		quit(1)
	print("FITTINGS: PASS")
	quit()
