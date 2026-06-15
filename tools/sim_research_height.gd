extends SceneTree
## Verifies the research 2D scroller is clamped to the visible page height (so it
## never overflows below the screen) while its content stays vertically scrollable
## to reach every node.

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
	main._refresh_all()
	await process_frame

	var fail := false
	for tab in ["Operations", "Zones", "Engineering", "Ships"]:
		main.research_tab = tab
		main._show("atlas")   # leave research first so resize fires cleanly
		await process_frame
		main._show("research")
		await process_frame
		await process_frame   # let call_deferred(_size_research_scroller) run
		var hs: ScrollContainer = main._research_hs
		var page: ScrollContainer = main.pages["research"]
		if hs == null:
			print("FAIL %s: no research scroller" % tab)
			fail = true
			continue
		var hs_h := hs.custom_minimum_size.y
		var page_h := page.size.y
		print("%s: scroller_h=%.0f page_h=%.0f content_h=%.0f" % [tab, hs_h, page_h, hs.get_child(0).custom_minimum_size.y])
		# The scroller must fit within the visible page (never taller than it).
		if hs_h <= page_h + 1.0:
			print("PASS %s: scroller fits visible page" % tab)
		else:
			print("FAIL %s: scroller (%.0f) taller than page (%.0f) — nodes fall off-screen" % [tab, hs_h, page_h])
			fail = true
		# Bottom pad: the frame must extend past the scaled tree so the last row can
		# scroll clear of the screen edge / nav bar.
		var frame: Control = hs.get_child(0)
		var canvas: Control = frame.get_child(0)
		var pad: float = frame.custom_minimum_size.y - canvas.custom_minimum_size.y * canvas.scale.y
		print("%s: bottom pad=%.0f" % [tab, pad])
		if pad >= 100.0:
			print("PASS %s: scroll content has bottom clearance" % tab)
		else:
			print("FAIL %s: insufficient bottom clearance (%.0f)" % [tab, pad])
			fail = true
		# If the tree is taller than the scroller, vertical scrolling must be possible.
		var content_h: float = hs.get_child(0).custom_minimum_size.y
		var vbar := hs.get_v_scroll_bar()
		if content_h > hs_h:
			if vbar.max_value - vbar.page > 1.0:
				print("PASS %s: tree taller than view is scrollable" % tab)
			else:
				print("FAIL %s: tree taller than view but not scrollable" % tab)
				fail = true

	if fail:
		print("RESEARCH_HEIGHT: FAIL")
		quit(1)
	print("RESEARCH_HEIGHT: PASS")
	quit()
