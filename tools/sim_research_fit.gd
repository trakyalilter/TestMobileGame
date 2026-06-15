extends SceneTree
## Verifies the research graph is scaled to fit the page width so nodes don't
## hang off the right edge, while staying legible (scale floor) and panning the
## remainder. Checks every discipline tab.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _find_canvas(node: Node) -> Control:
	# The graph canvas: a big Control (holds all node buttons) wrapped in a frame
	# inside the both-axis graph scroller. Identify it by its large min-size and
	# many children (distinguishes it from subtab strips and node cards).
	if node is Control:
		var cs: Control = node
		if cs.custom_minimum_size.x >= 300.0 and cs.get_child_count() > 3:
			return cs
	for c in node.get_children():
		var r := _find_canvas(c)
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
	main._refresh_all()
	await process_frame

	var fail := false
	var max_cw := 0.0
	for tab in ["Operations", "Zones", "Engineering", "Ships"]:
		main.research_tab = tab
		main._show("research")
		await process_frame
		await process_frame
		var canvas := _find_canvas(main.pages["research"])
		if canvas == null:
			print("FAIL %s: no graph canvas found" % tab)
			fail = true
			continue
		var frame: Control = canvas.get_parent()
		var s := canvas.scale.x
		var cw := canvas.custom_minimum_size.x
		max_cw = maxf(max_cw, cw)
		var fw := frame.custom_minimum_size.x
		print("%s: scale=%.3f canvas_w=%.0f frame_w=%.0f" % [tab, s, cw, fw])
		# Scale must never enlarge, and must respect the legibility floor.
		if s > 1.0001 or s < 0.62 - 0.001:
			print("FAIL %s: scale out of range (%.3f)" % [tab, s])
			fail = true
		# The frame must carry the SCALED footprint so the scroller measures the
		# fitted size (this is what keeps the tree inside the visible width).
		if absf(fw - cw * s) > 1.0:
			print("FAIL %s: frame footprint %.0f != canvas_w*scale %.0f" % [tab, fw, cw * s])
			fail = true
		else:
			print("PASS %s: frame carries scaled footprint" % tab)

	# On a real portrait device the page is ~696 logical px wide. Prove the fit
	# math actually shrinks the widest tree there (otherwise the fix is a no-op).
	var dev_w := 720.0 - 12.0 * 2.0
	var dev_fit := clampf(dev_w / max_cw, 0.62, 1.0)
	print("widest tree=%.0f  device fit @696=%.3f" % [max_cw, dev_fit])
	if dev_fit < 1.0:
		print("PASS device-width fit shrinks the widest tree into view")
	else:
		print("FAIL widest tree already fits 696 — scaling would never trigger")
		fail = true

	if fail:
		print("RESEARCH_FIT: FAIL")
		quit(1)
	print("RESEARCH_FIT: PASS")
	quit()
