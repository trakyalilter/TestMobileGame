extends SceneTree
## Verifies the Atlas search box filters materials and enemies by name, and that
## typing refills only the results (the search LineEdit persists, keeping focus).

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _collect_text(node: Node, out: Array) -> void:
	if node is Label or node is Button:
		out.append(node.text)
	for c in node.get_children():
		_collect_text(c, out)

func _count(node: Node, needle: String) -> int:
	var t := []
	_collect_text(node, t)
	var n := 0
	for s in t:
		if needle in s:
			n += 1
	return n

func _count_panels(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		if c is PanelContainer:
			n += 1
	return n

func _find_lineedit(node: Node) -> LineEdit:
	if node is LineEdit:
		return node
	for c in node.get_children():
		var r := _find_lineedit(c)
		if r != null:
			return r
	return null

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	var gd = root.get_node("GameData")
	for n in range(1, gs.SLOT_COUNT + 1):
		gs.delete_slot(n)
	gs.new_character(1, "Tester")
	if is_instance_valid(main._char_select):
		main._char_select.queue_free()
		main._char_select = null
	main._refresh_all()
	await process_frame

	var fail := false

	# Open the Atlas; a search field must be present.
	main.atlas_query = ""
	main.atlas_mode = "materials"
	main._show("atlas")
	await process_frame
	var se := _find_lineedit(main.pages["atlas"])
	if se == null:
		print("FAIL no search field in Atlas")
		print("ATLAS_SEARCH: FAIL")
		quit(1)
		return
	print("PASS Atlas has a search field")

	# Render cap: the materials results must be bounded (no hundreds of panels).
	var panels := _count_panels(main._atlas_results)
	print("materials panels rendered (no search): %d (cap %d)" % [panels, main.ATLAS_MAX_ROWS])
	if panels <= main.ATLAS_MAX_ROWS:
		print("PASS materials list is capped for performance")
	else:
		print("FAIL materials list exceeds the render cap")
		fail = true

	# Materials: search for "Iron" → only matching rows; non-matches gone.
	var iron_name: String = gd.res_name("Fe")
	se.text = iron_name
	se.text_changed.emit(iron_name)
	await process_frame
	var iron_rows := _count(main._atlas_results, iron_name)
	var copper_rows := _count(main._atlas_results, gd.res_name("Cu"))
	print("materials search '%s': iron_rows=%d copper_rows=%d" % [iron_name, iron_rows, copper_rows])
	if iron_rows >= 1 and copper_rows == 0:
		print("PASS materials filter by name")
	else:
		print("FAIL materials filter wrong")
		fail = true

	# The search LineEdit must persist across a refilter (same node, focus kept).
	var se2 := _find_lineedit(main.pages["atlas"])
	if se2 == se:
		print("PASS search field persists across refilter (focus preserved)")
	else:
		print("FAIL search field was recreated on keystroke")
		fail = true

	# Enemies: switch tab, search a known enemy substring.
	main.atlas_query = ""
	main.atlas_mode = "enemies"
	main._show("atlas")
	await process_frame
	se = _find_lineedit(main.pages["atlas"])
	se.text = "Drone"
	se.text_changed.emit("Drone")
	await process_frame
	var drone_rows := _count(main._atlas_results, "Drone")
	print("enemy search 'Drone': matches=%d" % drone_rows)
	if drone_rows >= 1:
		print("PASS enemies filter by name")
	else:
		print("FAIL enemies filter found nothing")
		fail = true

	# A nonsense query yields an empty-state message, no crash.
	se.text = "zzzqqq"
	se.text_changed.emit("zzzqqq")
	await process_frame
	if _count(main._atlas_results, "No enemies found") >= 1:
		print("PASS empty-state shown for no matches")
	else:
		print("FAIL empty-state missing")
		fail = true

	if fail:
		print("ATLAS_SEARCH: FAIL")
		quit(1)
	print("ATLAS_SEARCH: PASS")
	quit()
