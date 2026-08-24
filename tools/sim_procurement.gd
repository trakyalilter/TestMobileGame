extends SceneTree
## Station Procurement (desktop v162 Demand Engine) — engine contract.
## The pool is the part that can silently break: it must gate claims WITHOUT
## destroying the order or the goods, refill from a timestamp (so offline works
## with no tick), and never let a generated order exceed what the pool can pay.

var _fail := false

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		print("PASS %s" % label)
	else:
		print("FAIL %s%s" % [label, ("  — " + detail) if detail != "" else ""])
		_fail = true

## Give the player a producer whose yield lands in `fam`, so the family is online.
func _bring_family_online(gs, gd, fam: String) -> String:
	for bid in gd.BUILDINGS:
		for res in gd.BUILDINGS[bid].get("yield", {}):
			if gs.proc_family_of(String(res)) == fam:
				gs.buildings[bid] = 20
				return String(bid)
	return ""

func _run() -> void:
	var gs = root.get_node("GameState")
	var gd = root.get_node("GameData")

	# ---- family/price tables ----
	_ok(gs.proc_family_of("Fe") == "refining", "Fe maps to refining")
	_ok(gs.proc_family_of("AdvCircuit") == "electronics", "AdvCircuit maps to electronics")
	_ok(gs.proc_family_of("NotAThing") == "", "unknown good has no family")
	_ok(gs.proc_unit_price("DreadnoughtFrame") > gs.proc_unit_price("Fe"),
		"price ladder encodes production depth")

	# ---- offline / no lines ----
	gs.buildings = {}
	gs.proc_boards = {}
	_ok(gs.proc_online_families().is_empty(), "no families online without buildings")
	_ok(not gs.procurement_unlocked(), "procurement locked before any factory")

	# ---- bring a family online ----
	var bid := _bring_family_online(gs, gd, "refining")
	_ok(bid != "", "found a refining producer", "bid=%s" % bid)
	_ok(gs.proc_online_families().has("refining"), "refining online after building it")
	_ok(gs.procurement_unlocked(), "procurement unlocks with a line online")

	# ---- rates are NET ----
	var rates: Dictionary = gs.infra_net_rates()
	_ok(not rates.is_empty(), "infra_net_rates reports something")

	# ---- board fills ----
	gs.ensure_procurement()
	var board: Array = gs.procurement_board("refining")
	_ok(board.size() > 0 and board.size() <= gs.PROC_CARDS_PER_FAMILY,
		"board fills within the card cap", "size=%d" % board.size())
	# Uniqueness is a PREFERENCE, not a rule: the picker falls back to repeats
	# when a family has fewer producing goods than card slots (a single-good line
	# should still get a full board rather than one lonely card).
	var uniq := {}
	for q in board:
		uniq[String(q["target"])] = true
	var producing: int = (gs._proc_family_rates("refining", rates) as Dictionary).size()
	if producing >= gs.PROC_CARDS_PER_FAMILY:
		_ok(uniq.size() == board.size(), "distinct goods used while enough are producing",
			"producing=%d unique=%d cards=%d" % [producing, uniq.size(), board.size()])
	else:
		_ok(uniq.size() == mini(producing, board.size()),
			"every producing good is represented before any repeat",
			"producing=%d unique=%d cards=%d" % [producing, uniq.size(), board.size()])

	# ---- v177: no order may exceed the pool's claimable share ----
	var cap: float = gs.proc_pool_cap("refining")
	var worst := 0.0
	for q in board:
		worst = maxf(worst, float(q["reward_credits"]))
	_ok(cap > 0.0, "pool cap is positive for an online family", "cap=%.0f" % cap)
	_ok(worst <= cap * gs.PROC_ORDER_MAX_POOL_FRAC + 1.0,
		"no generated order exceeds the claimable share (no dead cards)",
		"worst=%.0f cap=%.0f" % [worst, cap])

	# ---- claim requires stock ----
	var order: Dictionary = board[0]
	var sym := String(order["target"])
	var need := int(order["target_qty"])
	gs.resources[sym] = 0
	gs.sync_procurement()
	_ok(not gs.claim_procurement(String(order["id"])), "cannot claim without the goods")

	# ---- claim consumes goods and pays ----
	gs.resources[sym] = need
	gs.sync_procurement()
	_ok(bool(order.get("completed", false)), "order completes once stock is held")
	var cred_before: int = gs.credits
	var pool_before: float = gs.proc_pool_value("refining")
	var claimed: bool = gs.claim_procurement(String(order["id"]))
	_ok(claimed, "claim succeeds with stock and demand")
	_ok(gs.amount(sym) == 0, "goods are CONSUMED on claim", "left=%d" % gs.amount(sym))
	_ok(gs.credits > cred_before, "claim pays credits")
	_ok(gs.proc_pool_value("refining") < pool_before, "claim draws down the demand pool")
	_ok(gs.procurement_board("refining").size() == board.size(),
		"claimed slot is replaced at current rates")

	# ---- the pool gate keeps order AND goods ----
	gs.proc_pools["refining"] = 0.0
	var b2: Array = gs.procurement_board("refining")
	var o2: Dictionary = b2[0]
	var sym2 := String(o2["target"])
	gs.resources[sym2] = int(o2["target_qty"])
	gs.sync_procurement()
	var held_before: int = gs.amount(sym2)
	var blocked: bool = gs.claim_procurement(String(o2["id"]))
	_ok(not blocked, "empty pool BLOCKS the claim")
	_ok(gs.amount(sym2) == held_before, "blocked claim does not consume goods")
	var still_there := false
	for q in gs.procurement_board("refining"):
		if String(q["id"]) == String(o2["id"]):
			still_there = true
	_ok(still_there, "blocked claim keeps the order on the board")
	_ok(gs.proc_notice != "", "player is told why, not left guessing")

	# ---- pool refills from the timestamp (this IS the offline path) ----
	gs.proc_pools["refining"] = 0.0
	gs._proc_pool_ts = Time.get_unix_time_from_system() - 3600.0   # an hour ago
	var refilled: float = gs.proc_pool_value("refining")
	var expected: float = cap / gs.PROC_POOL_HOURS
	_ok(abs(refilled - expected) < expected * 0.05,
		"one hour offline refills ~1/24th of the cap",
		"got=%.0f expected=%.0f" % [refilled, expected])
	gs.proc_pools["refining"] = cap * 10.0
	_ok(gs.proc_pool_value("refining") <= cap, "pool value is clamped DOWN to the cap")

	# ---- no generated order can be a dead card ----
	# A claim is blocked outright when the pool holds less than the order's value
	# and the card never resizes, so an order worth more than the CAP is
	# permanently unclaimable. Order value follows the player's line rate while
	# the cap follows their combat frontier, so an engineer who over-invests in
	# factories for their zone was the one locked out.
	var dead := 0
	var checked := 0
	for fam2 in gs.PROC_FAMILIES:
		var fam2_s := String(fam2)
		var cap2: float = gs.proc_pool_cap(fam2_s)
		if cap2 <= 0.0:
			continue
		for good in gs.PROC_FAMILIES[fam2_s]:
			# Generate at a deliberately over-scaled line rate — the exact case
			# that produced dead cards before the clamp.
			var o3: Dictionary = gs._gen_proc_order(fam2_s, String(good), 1_000_000.0)
			checked += 1
			if float(o3.get("reward_credits", 0.0)) > cap2:
				dead += 1
	_ok(dead == 0, "no over-scaled line can generate an unclaimable order",
		"%d of %d goods produced a card worth more than its pool cap" % [dead, checked])
	print("order sizing: %d goods generated at an absurd line rate, %d dead cards" % [checked, dead])

	# ---- stale cards self-heal ----
	# An order bakes in the unit price it was generated at. After a retune, a card
	# priced at the old rate must be dropped and refilled rather than sitting on
	# the board advertising a number the table no longer honours.
	gs.current_slot = 1
	gs.load_failed = false
	var fam3 := _bring_family_online(gs, gd, "refining")
	gs.ensure_procurement()
	var board3: Array = gs.proc_boards.get("refining", [])
	if board3.is_empty():
		_ok(false, "the refining board has a card to stale out")
	else:
		var victim: Dictionary = board3[0]
		var real_price: float = float(victim["unit_price"])
		victim["unit_price"] = real_price / 10.0        # a pre-retune card
		var stale_id := String(victim["id"])
		gs.save_game()
		gs.hard_reset()
		gs.current_slot = 1
		gs.load_game()
		var survived := false
		for q3 in gs.proc_boards.get("refining", []):
			if String((q3 as Dictionary)["id"]) == stale_id:
				survived = true
		_ok(not survived, "a card priced at a stale rate is dropped on load")
		# And the board refills, so the player never loses a slot to the heal.
		var after: Array = gs.procurement_board("refining")
		_ok(after.size() == gs.PROC_CARDS_PER_FAMILY,
			"the board refills to full on the same tick",
			"%d of %d cards" % [after.size(), gs.PROC_CARDS_PER_FAMILY])
		for q4 in after:
			var want4: float = gs.proc_unit_price(String((q4 as Dictionary)["target"]))
			_ok(is_equal_approx(float((q4 as Dictionary)["unit_price"]), want4),
				"every card on the healed board is priced at the current table")
	gs.delete_slot(1)

	print("PROCUREMENT: %s" % ("FAIL" if _fail else "PASS"))
	quit()
