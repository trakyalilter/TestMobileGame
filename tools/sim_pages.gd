extends SceneTree
## Page-render smoke: load the real main scene and build every page so any
## UI build error against the new data surfaces as a SCRIPT ERROR in stderr.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	# Give the player gear + research so combat/ship/research pages have content.
	var gs = root.get_node("GameState")
	for mid in ["z1_kinetic", "z1_energy", "z1_shield", "z1_battery"]:
		gs.module_inventory[mid] = 1
		gs.equip_module(mid)
	for pid in main.PAGE_IDS:
		main._show(pid)
		await process_frame
		print("built page: %s" % pid)
	# Also enter a combat to exercise the battle view.
	gs.start_task("combat", "z1_lunar_drone")
	main._show("combat")
	await process_frame
	main._refresh_current()
	await process_frame
	print("PAGES: PASS")
	quit()
