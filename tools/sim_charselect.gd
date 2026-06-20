extends SceneTree
## Character-select UI sim: boots the real main scene (no slot active), asserts the
## select screen lists slots, and that New + Play transition into the game with the
## overlay removed and a page shown — no SCRIPT ERROR.

var _fail := false

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("PASS " + msg)
	else:
		print("FAIL " + msg)
		_fail = true

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

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var gs = root.get_node("GameState")
	# Clean slate, then seed slot 1 so the select screen has one filled + empties.
	for n in range(1, gs.SLOT_COUNT + 1):
		gs.delete_slot(n)
	if FileAccess.file_exists(gs.SAVE_PATH):
		DirAccess.remove_absolute(gs.SAVE_PATH)
	gs.new_character(1, "Nova")
	gs.gain_credits(5400)
	gs.save_game()
	gs.current_slot = 0           # back to "boot" state for the UI

	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	# Character-select overlay should be present and listing slots.
	_ck(is_instance_valid(main._char_select), "char-select overlay built on boot")
	var ct := []
	_collect_text(main._char_select, ct)
	_ck(_has(ct, "STELLAR FORGE") and _has(ct, "COMMANDER ROSTER"), "title header present")
	_ck(_has(ct, "Nova") and _has(ct, "DEPLOY"), "filled slot shows name + Deploy")
	_ck(_has(ct, "New Commander") and _has(ct, "CREATE COMMANDER"), "empty slot shows recruit + Create")

	# --- Play the filled slot → enters the game.
	main._play_slot(1)
	await process_frame
	await process_frame
	_ck(not is_instance_valid(main._char_select), "Play removes the select overlay")
	_ck(gs.current_slot == 1 and gs.credits == 5400 and gs.character_name == "Nova", "Play loaded Nova's save")
	var any_page := false
	for pid in main.PAGE_IDS:
		if main.pages.has(pid) and main.pages[pid].visible:
			any_page = true
	_ck(any_page, "a game page is visible after Play")

	# --- Back to select, then New Character into an empty slot.
	main._show_char_select()
	await process_frame
	main._char_select.queue_free()
	main._char_select = null
	gs.current_slot = 0
	gs.new_character(2, "Rook")
	main._enter_game()
	await process_frame
	await process_frame
	_ck(not is_instance_valid(main._char_select), "New Character enters game (overlay gone)")
	_ck(gs.current_slot == 2 and gs.character_name == "Rook", "New Character created Rook in slot 2")

	# cleanup
	for n in range(1, gs.SLOT_COUNT + 1):
		gs.delete_slot(n)

	if _fail:
		print("CHARSELECT: FAIL")
		quit(1)
	print("CHARSELECT: PASS")
	quit()
