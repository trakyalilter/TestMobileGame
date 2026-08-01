extends Node
func _ready() -> void: call_deferred("_t")
func _t() -> void:
	var cm = GameState.combat_manager
	var fail := 0
	for zid in cm.zones:
		var z: Dictionary = cm.zones[zid]
		var ids: Array = z.get("enemies", [])
		var trash: Array = []
		for e in ids:
			if not cm.enemy_db.get(e, {}).get("is_boss", false): trash.append(e)
		var diff: int = int(z.get("difficulty", 0))
		var line := "Z%-2d %-18s trash=%d " % [diff, zid, trash.size()]
		# triangle balance
		var weak := {}
		var gearers := []
		for e in trash:
			var d: Dictionary = cm.enemy_db[e]
			for ch in [["resist_k","K"],["resist_e","E"],["resist_x","X"]]:
				if float(d.get(ch[0], 0.0)) < 0.0: weak[ch[1]] = e
			if not cm.enemy_is_front_salvage(e, zid): gearers.append(e)
		line += "weak=%s gear=%d" % [str(weak.keys()), gearers.size()]
		if diff >= 2 and diff <= 10 and diff != 11:
			if trash.size() != 3 and diff != 11: line += "  <-- COUNT"; fail += 1
			if gearers.size() != 1: line += "  <-- GEAR!=1"; fail += 1
		if diff not in [1, 11] and weak.size() != 3:
			line += "  <-- TRIANGLE INCOMPLETE"; fail += 1
		print("[ZC] " + line)
	print("[ZC] RESULT: %s" % ("PASS" if fail == 0 else "FAIL(%d)" % fail))
	get_tree().quit(0)
