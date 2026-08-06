extends Node
# Board must be duplicate-free AND must grow back to BOARD_SIZE once enough
# materials are unlocked -- a permanently short board would be a new bug.
func _ready() -> void:
	var qm = GameState.quest_manager
	GameState.set_process(false)
	for forced in [1, 2, 3, 5, 10, 14]:
		var sizes := {}
		var dups := 0
		for trial in range(60):
			qm.board.clear()
			# emulate progression by generating against a forced difficulty window
			while qm.board.size() < qm.BOARD_SIZE:
				var q = qm._generate_gather_quest(max(1, forced - 1), forced)
				if q.size() == 0: break
				qm.board.append(q)
			sizes[qm.board.size()] = true
			var seen := {}
			for x in qm.board:
				var sym := String(x.get("target",""))
				if seen.has(sym): dups += 1
				seen[sym] = true
		var ks := sizes.keys(); ks.sort()
		print("[UQ] maxdiff=%-3d board sizes=%s  duplicates=%d" % [forced, str(ks), dups])
	print("[UQ] DONE")
	get_tree().quit(0)
