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

	# 5) EXPLOIT CLOSED: gather orders CONSUME on claim, so held stock can't
	#    print infinite rewards (owner-reported claim→reroll→claim farm).
	qm.board.clear()
	res.remove_element("Cu", res.get_element_amount("Cu"))   # zero Cu
	res.add_element("Cu", 500, true)
	var g1 = _mk_gather(qm, "Cu", 200); qm._resync_stock_quests()
	var cr0 = res.get_currency("credits")
	var claim1 = qm.claim_quest(g1["id"])
	_ok("gather claim CONSUMES stock", claim1 and int(res.get_element_amount("Cu")) == 300,
		"cu=%d" % int(res.get_element_amount("Cu")))
	_ok("gather claim pays Liras", res.get_currency("credits") > cr0)
	var g2 = _mk_gather(qm, "Cu", 200); qm._resync_stock_quests()   # 300 Cu → completes
	qm.claim_quest(g2["id"])                                        # drains to 100
	var g3 = _mk_gather(qm, "Cu", 200); qm._resync_stock_quests()   # 100 Cu
	var claim3 = qm.claim_quest(g3["id"])
	_ok("farm broken once stock runs out", (not claim3) and int(res.get_element_amount("Cu")) == 100,
		"claim3=%s cu=%d" % [str(claim3), int(res.get_element_amount("Cu"))])

	# 6) clean divisible-by-10 targets (no 199/282/387)
	_ok("_round_qty divisible-by-10",
		qm._round_qty(199) == 200 and qm._round_qty(387) == 390 and qm._round_qty(282) == 280 and qm._round_qty(1523) == 1500,
		"199→%d 387→%d 282→%d 1523→%d" % [qm._round_qty(199), qm._round_qty(387), qm._round_qty(282), qm._round_qty(1523)])

	print("[QSTOCK] %s" % ("ALL PASS" if fails == 0 else "*** %d FAILURE(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
