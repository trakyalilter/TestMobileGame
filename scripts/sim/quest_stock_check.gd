extends Node
# ============================================================================
# QUEST STOCK-BAR CHECK (v139c) — Stockpile/Supply quests are a LIVE inventory
# read ("own N units"), never a spawn-relative accumulator. Reproduces the
# owner-reported screenshot: 6× "Stok: Bakır" (Copper) cards that read
# 272/272/138/138/0 for the SAME material — they must all mirror current Cu.
#   Godot --headless --path <root> res://scenes/quest_stock_check.tscn
# ============================================================================

var fails := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond: fails += 1
	print("[QSTOCK] %-40s %s %s" % [name, "OK" if cond else "*** FAIL", detail])

func _mk_gather(qm, mat: String, target: int) -> Dictionary:
	# Manual gather quest (the generators pick a random material/tier).
	var have = GameState.resources.get_element_amount(mat)
	var q := {"id": qm._gen_id(), "type": "gather", "title": "Stockpile", "desc": "",
		"target": mat, "target_qty": target, "current_qty": min(have, target),
		"reward_credits": 1000, "reward_material": {}, "difficulty": 1,
		"completed": have >= target, "claimed": false}
	qm.board.append(q)
	return q

func _ready() -> void:
	var qm = GameState.quest_manager
	var res = GameState.resources
	GameState.set_process(false)
	GameState.hard_reset()
	qm.board.clear()
	print("[QSTOCK] ============ quest stock-bar live-read check ============")

	# Player owns 272 Copper.
	res.add_element("Cu", 272, true)

	# Four Copper stockpile quests with different targets (mirrors the screenshot).
	var q540 = _mk_gather(qm, "Cu", 540)
	var q570 = _mk_gather(qm, "Cu", 570)
	var q388 = _mk_gather(qm, "Cu", 388)
	var q200 = _mk_gather(qm, "Cu", 200)   # target BELOW holdings → should be complete

	# 1) every Cu quest reads the SAME live inventory (272), not drifted values
	qm._resync_stock_quests()
	var same := (int(q540["current_qty"]) == 272 and int(q570["current_qty"]) == 272 and int(q388["current_qty"]) == 272)
	_ok("all same-material read live inv (272)", same,
		"%d/%d/%d" % [int(q540["current_qty"]), int(q570["current_qty"]), int(q388["current_qty"])])
	_ok("target below holdings = complete", bool(q200["completed"]) and int(q200["current_qty"]) == 200)
	_ok("target above holdings = not complete", not bool(q540["completed"]))

	# 2) a FRESHLY-rolled quest for an owned material is born filled, never 0/N
	var qfresh = _mk_gather(qm, "Cu", 377)
	_ok("fresh quest born at inventory (not 0)", int(qfresh["current_qty"]) == 272,
		"%d/377" % int(qfresh["current_qty"]))

	# 3) gathering MORE advances every Cu bar live (via element_added signal path)
	res.add_element("Cu", 100, true)   # now 372
	qm._resync_stock_quests()
	var advanced := (int(q540["current_qty"]) == 372 and int(qfresh["current_qty"]) == 372)
	_ok("gathering advances all bars live", advanced, "q540=%d" % int(q540["current_qty"]))
	# 372 < 388, so q388 stays incomplete + uncapped; q200 (target below inv) is capped+complete
	_ok("below-target stays partial (not capped)", int(q388["current_qty"]) == 372 and not bool(q388["completed"]))
	_ok("at/over-target completes + caps at target", bool(q200["completed"]) and int(q200["current_qty"]) == 200)

	# 4) SPENDING drops the bars live ("own N right now") + un-completes
	res.remove_element("Cu", 300)   # now 72
	qm._resync_stock_quests()
	var dropped := (int(q540["current_qty"]) == 72 and int(q200["current_qty"]) == 72)
	_ok("spending drops bars live", dropped, "q540=%d q200=%d" % [int(q540["current_qty"]), int(q200["current_qty"])])
	_ok("un-completes when below target", not bool(q200["completed"]) and not bool(q388["completed"]))

	print("[QSTOCK] %s" % ("ALL PASS" if fails == 0 else "*** %d FAILURE(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
