extends SceneTree
## Verifies offline combat feeds the SALVAGE THIS RUN tally (session_loot), so a
## returning player sees what they farmed while away.

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

	var loot := [["credits", 1.0, 100, 200], ["Fe", 1.0, 10, 20], ["Cu", 1.0, 5, 10]]

	# (A) The exact changed path: offline loot WITH session logging populates the
	# SALVAGE THIS RUN tally (so returning players see what they farmed away).
	gs.session_loot = {}
	gs._offline_loot(loot, 1.0, 4, true)
	print("session_loot after logged offline loot: %s" % str(gs.session_loot))
	if gs.session_loot.has("credits") and gs.session_loot.has("Fe") and gs.session_loot.has("Cu"):
		print("PASS offline loot fed the SALVAGE THIS RUN tally")
	else:
		print("FAIL offline loot did not feed the tally")
		fail = true

	# (B) Default (gather/craft) must NOT pollute the combat-only tally.
	gs.session_loot = {}
	gs._offline_loot(loot, 1.0, 4)
	if gs.session_loot.is_empty():
		print("PASS non-combat offline loot leaves the tally untouched")
	else:
		print("FAIL non-combat offline loot polluted the tally: %s" % str(gs.session_loot))
		fail = true

	# (C) Integrated: if the drone is farmable, offline combat logs salvage too.
	for mid in ["z1_kinetic", "z1_energy", "z1_shield"]:
		gs.module_inventory[mid] = 1
		gs.equip_module(mid)
	gs.start_task("combat", "z1_lunar_drone")
	var preview: Dictionary = gs.combat_preview("z1_lunar_drone")
	gs._offline_combat(3600.0)
	if preview.get("farmable", false) or preview.get("win", false):
		if not gs.session_loot.is_empty():
			print("PASS integrated offline combat logged salvage")
		else:
			print("FAIL integrated offline combat logged nothing despite farmable")
			fail = true
	else:
		print("NOTE drone not farmable with starter gear in headless — integrated path skipped")

	# The combat page must render those salvage rows when the player returns.
	main._refresh_all()
	main._show("combat")
	await process_frame
	main._refresh_current()
	await process_frame
	var texts := []
	_collect_text(main.pages["combat"], texts)
	if _has(texts, "SALVAGE THIS RUN"):
		print("PASS battle view shows the SALVAGE THIS RUN panel")
	else:
		print("FAIL SALVAGE THIS RUN panel missing on return")
		fail = true

	if fail:
		print("OFFLINE_SALVAGE: FAIL")
		quit(1)
	print("OFFLINE_SALVAGE: PASS")
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
