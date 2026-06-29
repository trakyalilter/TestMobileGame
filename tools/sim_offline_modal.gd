extends SceneTree
## Verifies (1) the offline report renders as two-column rows (name + qty),
## and (2) drag-scroll works inside an open module-detail modal.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _find_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for c in node.get_children():
		var r := _find_scroll(c)
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
	for n in range(1, gs.SLOT_COUNT + 1):
		gs.delete_slot(n)
	gs.new_character(1, "Tester")
	if is_instance_valid(main._char_select):
		main._char_select.queue_free()
		main._char_select = null
	if is_instance_valid(main._welcome):
		main._welcome.queue_free()
		main._welcome = null
	main._refresh_all()
	await process_frame

	var fail := false

	# --- (1) Offline report two-column rows.
	main._show_offline("Away for 23m 3s\n\nDestroyed 195 Lunar Drone\nIron\t+710\nCopper\t+406\nModules\t+37\nCombat XP\t+1560")
	await process_frame
	# The frontmost modal is the offline overlay; find HBox rows with two labels.
	var modal: Node = main._modal_stack[main._modal_stack.size() - 1]
	var rows := 0
	var stack := [modal]
	while not stack.is_empty():
		var nd = stack.pop_back()
		# Each report row is an HBox of [icon-or-spacer, name Label, amount Label];
		# detect by a name+amount label pair whose last label begins with "+".
		if nd is HBoxContainer:
			var labels := []
			for c in nd.get_children():
				if c is Label:
					labels.append(c)
			if labels.size() >= 2 and (labels[labels.size() - 1] as Label).text.begins_with("+"):
				rows += 1
		for c in nd.get_children():
			stack.append(c)
	print("offline two-column rows: %d" % rows)
	if rows >= 4:
		print("PASS offline report renders separate name/qty rows")
	else:
		print("FAIL offline report not in two-column rows (got %d)" % rows)
		fail = true
	# No raw tab should leak into any single label.
	var leaked := false
	stack = [modal]
	while not stack.is_empty():
		var nd = stack.pop_back()
		if nd is Label and "\t" in (nd as Label).text:
			leaked = true
		for c in nd.get_children():
			stack.append(c)
	if leaked:
		print("FAIL a label still contains a raw tab")
		fail = true
	else:
		print("PASS no raw tabs in labels")
	modal.queue_free()
	await process_frame

	# --- (2) Drag inside a module-detail modal.
	# Give an owned module with sockets/affixes so the detail modal is tall.
	var mid: String = gs.generate_module("z1_shield", 2, 1)
	main.ship_target_slot = -1
	main._open_module_detail(mid)
	await process_frame
	await process_frame
	if main._modal_stack.is_empty():
		print("FAIL module detail modal did not open")
		print("OFFLINE_MODAL: FAIL")
		quit(1)
		return
	var dm: Node = main._modal_stack[main._modal_stack.size() - 1]
	var msc := _find_scroll(dm)
	if msc == null:
		print("FAIL no scroll container in module modal")
		fail = true
	else:
		# Target the modal scroll via the same resolver the input handler uses.
		var rect := msc.get_global_rect()
		var pos := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + 40.0)
		var resolved: ScrollContainer = main._scrollable_at(pos)
		print("resolved modal scroll: %s (can_scroll=%s)" % [str(resolved == msc), str(main._can_scroll(msc))])
		if resolved != msc:
			print("FAIL drag resolver did not target the modal's scroll container")
			fail = true
		elif not main._can_scroll(msc):
			print("NOTE modal content fits — not scrollable in this layout; resolver still correct")
			print("PASS modal drag resolves to modal scroll container")
		else:
			var v0 := msc.scroll_vertical
			main._drag_begin(pos)
			for i in range(1, 12):
				main._drag_move(pos - Vector2(0, i * 16.0))
				await process_frame
			main._drag_end()
			var v1 := msc.scroll_vertical
			print("modal scroll: %d -> %d" % [v0, v1])
			if v1 > v0:
				print("PASS drag scrolled inside the modal")
			else:
				print("FAIL drag did not scroll inside the modal")
				fail = true

	if fail:
		print("OFFLINE_MODAL: FAIL")
		quit(1)
	print("OFFLINE_MODAL: PASS")
	quit()
