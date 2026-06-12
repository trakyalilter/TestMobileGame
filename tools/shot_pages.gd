extends SceneTree
## Optional screenshot harness (run under xvfb). Renders the combat battle view
## and the enemy Intel modal to PNGs under /tmp for visual inspection. Not part
## of CI; PNGs are not committed.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _shot(path: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved %s" % path)

func _run() -> void:
	root.get_window().size = Vector2i(720, 1280)
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	# Dismiss the boot welcome overlay so pages are visible in the capture.
	main._welcome_done = true
	if main._welcome != null:
		main._welcome.queue_free()
		main._welcome = null
	await process_frame
	var gs = root.get_node("GameState")
	for mid in ["z1_kinetic", "z1_energy", "z1_shield", "z1_battery"]:
		gs.module_inventory[mid] = 1
		gs.equip_module(mid)

	# Combat targeting page (enemy cards with affinity chips).
	main._show("combat")
	await _shot("/tmp/mobile_combat_targets.png")

	# Live battle view.
	gs.start_task("combat", "z1_lunar_drone")
	main._show("combat")
	main._refresh_current()
	await _shot("/tmp/mobile_battle.png")
	gs.stop_task()

	# Enemy Intel modal.
	main._show("combat")
	await process_frame
	main._show_enemy_intel("z1_lunar_drone")
	await _shot("/tmp/mobile_intel.png")

	# Dismiss the Intel modal overlay (a ColorRect child of main) before moving on.
	for c in main.get_children():
		if c is ColorRect and c.color.a > 0.5:
			c.queue_free()
	await process_frame

	# Hazard zones page.
	main._show("hazard")
	await _shot("/tmp/mobile_hazard.png")

	# Trinity / ship loadout.
	main.ship_view = "loadout"
	main._show("ship")
	await _shot("/tmp/mobile_trinity.png")

	print("SHOTS: DONE")
	quit()
