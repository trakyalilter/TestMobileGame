extends SceneTree
## Verifies the enemy SALVAGE list shows module display names + rarity, not raw
## ids like "z1_unique_weapon".

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
	# The Rogue Architect drops the unique set pieces directly in its loot table.
	var eid := "z1_boss_architect"
	var card = main._enemy_card(eid, GameData.ENEMIES[eid])
	root.add_child(card)
	await process_frame
	var ct := []
	_collect_text(card, ct)

	# Raw ids must NOT appear; display names MUST.
	for raw in ["z1_unique_weapon", "z1_unique_armor", "z1_unique_shield"]:
		if _has(ct, raw):
			print("FAIL raw id leaked into SALVAGE: %s" % raw)
			fail = true
	for nm in ["Architect's Beam", "Architect's Plating", "Architect's Ward"]:
		if _has(ct, nm):
			print("PASS SALVAGE shows display name: %s" % nm)
		else:
			print("FAIL SALVAGE missing display name: %s" % nm)
			fail = true
	card.queue_free()

	if fail:
		print("LOOT_NAMES: FAIL")
		quit(1)
	print("LOOT_NAMES: PASS")
	quit()
