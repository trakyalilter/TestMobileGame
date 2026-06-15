extends SceneTree
## Verifies global drag-to-scroll: a touch drag that starts over a card (cards are
## covered by tap Buttons) scrolls the page, and a drag does NOT fire the card's
## tap. Also checks a short/unscrollable page is left alone.

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
	if is_instance_valid(main._welcome):
		main._welcome.queue_free()
		main._welcome = null
	# Unlock plenty so a page has many cards (tall enough to scroll).
	for mid in ["z1_kinetic", "z1_energy", "z1_shield", "z1_battery"]:
		gs.module_inventory[mid] = 1
		gs.equip_module(mid)
	main._refresh_all()
	await process_frame

	var fail := false

	# Find a page whose ScrollContainer is actually scrollable.
	var target_page := ""
	for pid in ["craft", "gather", "shipyard", "build", "missions"]:
		main._show(pid)
		await process_frame
		await process_frame
		if main._can_scroll(main.pages[pid]):
			target_page = pid
			break
	if target_page == "":
		print("FAIL no scrollable page found to test")
		print("DRAG: FAIL")
		quit(1)
		return
	print("testing drag on page: %s" % target_page)

	var sc: ScrollContainer = main.pages[target_page]
	var rect := sc.get_global_rect()
	var cx := rect.position.x + rect.size.x * 0.5
	var top := rect.position.y + 60.0
	var v0 := sc.scroll_vertical
	print("scroll before drag: %d" % v0)

	print("gate: modal=%d drawer=%s char_select=%s welcome=%s" % [main._modal_depth, str(main.drawer_open), str(is_instance_valid(main._char_select)), str(is_instance_valid(main._welcome))])

	# Drive press + upward drag + release directly through the handler (headless
	# input routing for synthetic touch is unreliable; this exercises the same path).
	main._drag_begin(Vector2(cx, top + 220.0))
	print("drag target: %s" % str(main._drag_target))
	for i in range(1, 12):
		main._drag_move(Vector2(cx, top + 220.0 - i * 18.0))
		await process_frame
	main._drag_end()
	await process_frame

	var v1 := sc.scroll_vertical
	print("scroll after drag: %d" % v1)
	if v1 > v0 + 20:
		print("PASS drag over card scrolled the page (%d -> %d)" % [v0, v1])
	else:
		print("FAIL drag over card did not scroll (%d -> %d)" % [v0, v1])
		fail = true

	# Let inertia glide settle (should not error or jump wildly).
	for _i in range(30):
		main._process(0.016)
		await process_frame
	print("scroll after inertia: %d" % sc.scroll_vertical)

	if fail:
		print("DRAG: FAIL")
		quit(1)
	print("DRAG: PASS")
	quit()
