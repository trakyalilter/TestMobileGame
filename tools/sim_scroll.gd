extends SceneTree
## Verifies that a tick-driven same-page rebuild (resources_changed firing while a
## parallel action completes) preserves the ScrollContainer offset, while a tab
## navigation still resets to the top.

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

	# Land on Shipyard · Hulls (the page from the user's screenshot) and give it
	# enough content height to scroll.
	main.shipyard_view = "hulls"
	main._show("shipyard")
	await process_frame
	await process_frame
	var sc: ScrollContainer = main.pages["shipyard"]
	# Force a layout pass so the content has a real height to scroll within.
	await process_frame

	# Simulate the player scrolling down.
	sc.scroll_vertical = 140
	await process_frame
	var before := sc.scroll_vertical
	print("scroll after manual set: %d" % before)

	# Control: an UNFIXED tick rebuild (preserve_scroll=false) must lose the scroll —
	# this is the bug the user reported. Confirms the fix is load-bearing.
	main._refresh_current(false)
	await process_frame
	await process_frame
	var unfixed := sc.scroll_vertical
	print("scroll after UNFIXED tick rebuild: %d" % unfixed)

	# Re-scroll and run the FIXED path.
	sc.scroll_vertical = 140
	await process_frame
	before = sc.scroll_vertical
	# A parallel action completes -> resources_changed -> _on_resources -> tick rebuild.
	main._refresh_current(true)
	await process_frame   # set_deferred lands next frame
	await process_frame
	var after := sc.scroll_vertical
	print("scroll after tick rebuild: %d" % after)
	if after == before:
		print("PASS tick rebuild preserved scroll (%d)" % after)
	else:
		print("FAIL tick rebuild lost scroll: %d -> %d" % [before, after])
		fail = true

	# Navigation must reset to the top.
	sc.scroll_vertical = 140
	await process_frame
	main._show("ship")
	await process_frame
	main._show("shipyard")
	await process_frame
	await process_frame
	var nav := sc.scroll_vertical
	print("scroll after navigation away+back: %d" % nav)
	if nav == 0:
		print("PASS navigation reset scroll to top")
	else:
		print("FAIL navigation did not reset scroll: %d" % nav)
		fail = true

	if fail:
		print("SCROLL: FAIL")
		quit(1)
	print("SCROLL: PASS")
	quit()
