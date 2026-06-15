extends SceneTree
## Verifies system options moved to a dedicated Settings page (Save button gone),
## and the Storage page no longer carries them.

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

	var fail := false

	# Settings page exists and holds the system options.
	if not ("settings" in main.PAGE_IDS) or not main.pages.has("settings"):
		print("FAIL no settings page registered")
		print("SETTINGS: FAIL")
		quit(1)
		return
	main._show("settings")
	await process_frame
	var st := []
	_collect_text(main.pages["settings"], st)
	if _has(st, "Offline Combat") and _has(st, "Reset Game"):
		print("PASS settings page has Offline Combat + Reset")
	else:
		print("FAIL settings page missing system options")
		fail = true
	if _has(st, "Save Now"):
		print("FAIL Save Now button still present")
		fail = true
	else:
		print("PASS Save Now removed (auto-save)")

	# Toggling offline combat works from the settings page.
	var before: bool = gs.offline_combat
	var btn := _find_button(main.pages["settings"], "Offline Combat")
	if btn != null:
		btn.pressed.emit()
		await process_frame
		if gs.offline_combat != before:
			print("PASS offline-combat toggle works")
		else:
			print("FAIL toggle did nothing")
			fail = true

	# Storage page must NOT carry the system options anymore.
	main._show("stats")
	await process_frame
	var stt := []
	_collect_text(main.pages["stats"], stt)
	if _has(stt, "Offline Combat") or _has(stt, "Reset Game") or _has(stt, "Save Now"):
		print("FAIL system options still on the Storage page")
		fail = true
	else:
		print("PASS Storage page no longer has system options")

	if fail:
		print("SETTINGS: FAIL")
		quit(1)
	print("SETTINGS: PASS")
	quit()

func _find_button(node: Node, label_prefix: String) -> Button:
	if node is Button and (node as Button).text.begins_with(label_prefix):
		return node
	for c in node.get_children():
		var r := _find_button(c, label_prefix)
		if r != null:
			return r
	return null
