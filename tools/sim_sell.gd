extends SceneTree
## Verifies tapping a storage stack opens a sell-quantity picker (not an instant
## sell-all), and selling a chosen quantity removes only that amount.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _find_slider(node: Node) -> HSlider:
	if node is HSlider:
		return node
	for c in node.get_children():
		var r := _find_slider(c)
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
	gs.resources["Fe"] = 100
	var val: int = maxi(1, gd.value_of("Fe"))
	var cr0: int = gs.credits

	# Tapping a stack opens the picker modal (no instant sell).
	main._open_sell_picker("Fe")
	await process_frame
	if main._modal_stack.is_empty():
		print("FAIL sell picker did not open")
		print("SELL: FAIL")
		quit(1)
		return
	if gs.amount("Fe") == 100 and gs.credits == cr0:
		print("PASS tapping opened picker without selling anything")
	else:
		print("FAIL stack changed before confirming")
		fail = true

	# A slider drives the quantity.
	var modal: Node = main._modal_stack[main._modal_stack.size() - 1]
	var sl := _find_slider(modal)
	if sl == null:
		print("FAIL no quantity slider in picker")
		fail = true
	else:
		if sl.max_value == 100 and sl.min_value == 1:
			print("PASS slider range is 1..owned")
		else:
			print("FAIL slider range wrong (min=%d max=%d)" % [sl.min_value, sl.max_value])
			fail = true
		# Choose 30 and confirm via the Sell button.
		sl.value = 30
		await process_frame
		var sell_btn := _find_button(modal, "Sell")
		if sell_btn == null:
			print("FAIL no Sell button")
			fail = true
		else:
			sell_btn.pressed.emit()
			await process_frame
			print("Fe after selling 30: %d  credits gained: %d (expected %d)" % [gs.amount("Fe"), gs.credits - cr0, 30 * val])
			if gs.amount("Fe") == 70 and gs.credits - cr0 == 30 * val:
				print("PASS sold exactly the chosen quantity")
			else:
				print("FAIL sold wrong quantity")
				fail = true

	if fail:
		print("SELL: FAIL")
		quit(1)
	print("SELL: PASS")
	quit()

func _find_button(node: Node, label: String) -> Button:
	if node is Button and (node as Button).text == label:
		return node
	for c in node.get_children():
		var r := _find_button(c, label)
		if r != null:
			return r
	return null
