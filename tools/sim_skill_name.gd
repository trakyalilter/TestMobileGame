extends SceneTree
## Verifies the crafting skill is consistently labelled "Engineering" (never
## "Fabrication") in the crew list and recipe lock text.

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

	# Crew skill bars are no longer duplicated on the Stats page.
	main._show("stats")
	await process_frame
	var t := []
	_collect_text(main.pages["stats"], t)
	if _has(t, "CREW"):
		print("FAIL stats page still shows the CREW section")
		fail = true
	else:
		print("PASS stats page no longer duplicates crew stats")

	# The Engineering skill bar still lives on its own page (Craft).
	main._show("craft")
	await process_frame
	var st := []
	_collect_text(main.pages["craft"], st)
	if _has(st, "ENGINEERING"):
		print("PASS Engineering skill bar present on its own page (Craft)")
	else:
		print("FAIL Engineering skill bar missing on Craft")
		fail = true

	# Recipe lock text uses the same skill name.
	var rt: String = main._req_text({"level_req": 8}, "fabrication")
	print("req text: %s" % rt)
	if "Engineering" in rt and not ("Fabrication" in rt):
		print("PASS recipe lock text says Engineering")
	else:
		print("FAIL recipe lock text wrong: %s" % rt)
		fail = true

	# Helper maps the id correctly.
	if main._skill_label("fabrication") == "Engineering":
		print("PASS _skill_label(fabrication) == Engineering")
	else:
		print("FAIL _skill_label wrong: %s" % main._skill_label("fabrication"))
		fail = true

	if fail:
		print("SKILL_NAME: FAIL")
		quit(1)
	print("SKILL_NAME: PASS")
	quit()
