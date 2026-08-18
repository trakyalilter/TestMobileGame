extends SceneTree
## Verifies the enemy SALVAGE list shows module display names + rarity, not raw
## ids like "z2_unique_weapon". The subject enemy is discovered from the data.

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
	# Pick the subject from the data instead of naming one. The Rogue Architect
	# used to drop the z1_unique_* set pieces and this file hard-coded them; the
	# MissionFlow port removed those rows, so the check was asserting names for
	# loot that no longer exists anywhere.
	var eid := ""
	var pieces: Array = []
	for cand in GameData.ENEMIES:
		var rows: Array = (GameData.ENEMIES[cand] as Dictionary).get("loot", [])
		var found: Array = []
		for row in rows:
			var sym := String((row as Array)[0])
			if GameData.SET_MODULES.has(sym) or GameData.MODULES.has(sym):
				found.append(sym)
		if not found.is_empty():
			eid = String(cand)
			pieces = found
			break
	if eid == "":
		print("FAIL no enemy drops a module — the display-name check has no subject")
		fail = true
		print("LOOT_NAMES: FAIL")
		quit(1)
		return
	var names: Array = []
	for sym in pieces:
		var d: Dictionary = GameData.SET_MODULES.get(sym, GameData.MODULES.get(sym, {}))
		names.append(String(d.get("name", "")))
	print("subject: %s drops %s -> %s" % [eid, str(pieces), str(names)])

	var card = main._enemy_card(eid, GameData.ENEMIES[eid])
	root.add_child(card)
	await process_frame
	var ct := []
	_collect_text(card, ct)

	# Raw ids must NOT appear; display names MUST.
	for raw in pieces:
		if _has(ct, String(raw)):
			print("FAIL raw id leaked into SALVAGE: %s" % raw)
			fail = true
	for nm in names:
		if String(nm) != "" and _has(ct, String(nm)):
			print("PASS SALVAGE shows display name: %s" % nm)
		else:
			print("FAIL SALVAGE missing display name: %s" % nm)
			fail = true
	card.queue_free()

	# The enemy Intel modal's RARE DROPS must resolve names too (not raw ids).
	main._show_enemy_intel(eid)
	await process_frame
	var it := []
	_collect_text(main, it)
	for raw in pieces:
		if _has(it, String(raw)):
			print("FAIL raw id leaked into Intel modal: %s" % raw)
			fail = true
	if _has(it, String(names[0])):
		print("PASS Intel modal shows display names")
	else:
		print("FAIL Intel modal missing display name: %s" % names[0])
		fail = true

	if fail:
		print("LOOT_NAMES: FAIL")
		quit(1)
		return
	print("LOOT_NAMES: PASS")
	quit()
