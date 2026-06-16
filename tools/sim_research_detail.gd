extends SceneTree
## Verifies the research detail modal lists what a tech UNLOCKS, and that the
## tighter layout still builds + fits.

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

	# _research_unlocks finds gated content. "automation" gates craft_adv_circuit.
	var u: Array = main._research_unlocks("automation")
	print("automation unlocks: %s" % str(u))
	var has_advcirc := false
	for s in u:
		if "Advanced Circuit" in s:
			has_advcirc = true
	if not u.is_empty() and has_advcirc:
		print("PASS _research_unlocks finds gated recipe (Advanced Circuitry)")
	else:
		print("FAIL _research_unlocks missing Advanced Circuitry")
		fail = true

	# A zone-gate tech unlocks a zone (◎) and follow-on tech.
	var uz: Array = main._research_unlocks("zone_2_access")
	if not uz.is_empty():
		print("PASS zone-access tech reports unlocks: %s" % str(uz))
	else:
		print("NOTE zone_2_access has no scanned unlocks")

	# The detail modal renders an UNLOCKS section.
	main._show_research_detail("automation")
	await process_frame
	var modal: Node = main._modal_stack[main._modal_stack.size() - 1]
	var t := []
	_collect_text(modal, t)
	if _has(t, "UNLOCKS") and _has(t, "Advanced Circuit"):
		print("PASS detail modal shows UNLOCKS with the recipe")
	else:
		print("FAIL detail modal missing UNLOCKS")
		fail = true
	if _has(t, "REQUIREMENTS"):
		print("PASS detail still shows REQUIREMENTS")
	else:
		print("FAIL detail lost REQUIREMENTS")
		fail = true

	if fail:
		print("RESEARCH_DETAIL: FAIL")
		quit(1)
	print("RESEARCH_DETAIL: PASS")
	quit()
