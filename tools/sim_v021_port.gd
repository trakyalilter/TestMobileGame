extends SceneTree
## Verifies v0.2.1 ports: (1) deterministic gather yields (online uses fixed max
## quantity), and (2) standing-order tier gated by real zone unlocks (new players
## don't roll T10/T11).

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	var gs = root.get_node("GameState")
	for n in range(1, gs.SLOT_COUNT + 1):
		gs.delete_slot(n)
	gs.new_character(1, "Tester")
	if is_instance_valid(main._char_select):
		main._char_select.queue_free()
		main._char_select = null

	var fail := false

	# (1) Deterministic gather: a guaranteed loot row [sym, 1.0, min, max] grants
	# exactly `max` (x yield mult), every time — no variance.
	var loot := [["Fe", 1.0, 5, 9]]
	var seen := {}
	for i in range(12):
		gs.resources["Fe"] = 0
		gs._roll_loot(loot, 1.0, 0, false, true)   # deterministic = true
		seen[gs.amount("Fe")] = true
	print("deterministic gather amounts seen: %s" % str(seen.keys()))
	if seen.size() == 1 and seen.has(9):
		print("PASS gather yield is deterministic (always max=9)")
	else:
		print("FAIL gather not deterministic: %s" % str(seen.keys()))
		fail = true
	# Combat path (deterministic=false) still varies across the range.
	var cseen := {}
	for i in range(40):
		gs.resources["Cu"] = 0
		gs._roll_loot([["Cu", 1.0, 5, 9]], 1.0, 0, false, false)
		cseen[gs.amount("Cu")] = true
	if cseen.size() > 1:
		print("PASS combat loot still uses range RNG (%d distinct)" % cseen.size())
	else:
		print("FAIL combat loot lost its RNG")
		fail = true

	# (2) Standing-order tier gate. New player: only Z1 reachable → max diff 1.
	var md0: int = gs.standing_max_diff()
	print("new-player standing_max_diff = %d" % md0)
	if md0 <= 2:
		print("PASS new player capped to low-tier orders")
	else:
		print("FAIL new player can roll tier %d orders" % md0)
		fail = true
	# Z11 must NOT count until its unlock_flag is set, even though research_req is "".
	# Unlock everything research-wise; flag still off.
	for tid in GameData.RESEARCH:
		gs.unlocked_research[tid] = true
	var md_no_flag: int = gs.standing_max_diff()
	print("all-research, no z11 flag: standing_max_diff = %d" % md_no_flag)
	if md_no_flag <= 10:
		print("PASS capped at 10 without z11 flag")
	else:
		print("FAIL exceeded 10 (%d) without z11 flag" % md_no_flag)
		fail = true

	if fail:
		print("V021_PORT: FAIL")
		quit(1)
	print("V021_PORT: PASS")
	quit()
