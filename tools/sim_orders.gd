extends SceneTree
## Guard for the v179 order-board changes (desktop orders_check).
##
## Two rules keep the board from freezing into a price list you stop reading:
## a new sector rerolls the cards you have not earned or seriously stocked, and
## repeat deliveries of a material climb a supplier ladder. Both are easy to
## break quietly — the first by vaporising an almost-finished card, the second by
## letting the ladder compound across a prestige into the warp gate.

var errs: Array = []
var warns: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s: String) -> void: errs.append(s)
func _chk(cond: bool, label: String, detail := "") -> void:
	if not cond:
		E("%s%s" % [label, ("  — " + detail) if detail != "" else ""])

func _run() -> void:
	var gs = root.get_node("GameState")
	var gd = root.get_node("GameData")
	gs._suppress_fx = true

	# ---------- A. the supplier ladder ----------
	gs.hard_reset()
	var sym := "Fe"
	_chk(is_equal_approx(gs.supplier_mult(sym), 1.0), "an untouched material pays face value")
	_chk(gs.supplier_pct(sym) == 0, "and shows no badge")
	for i in range(1, gs.SUPPLIER_MAX_STEPS + 3):
		gs.supplier_deliveries[sym] = i
		var want: float = 1.0 + gs.SUPPLIER_STEP * float(mini(i, gs.SUPPLIER_MAX_STEPS))
		_chk(is_equal_approx(gs.supplier_mult(sym), want),
			"%d deliveries pay x%.2f" % [i, want], "got x%.3f" % gs.supplier_mult(sym))
	_chk(is_equal_approx(gs.supplier_mult(sym), 1.0 + gs.SUPPLIER_STEP * gs.SUPPLIER_MAX_STEPS),
		"the ladder CAPS rather than climbing forever",
		"x%.3f after %d deliveries" % [gs.supplier_mult(sym), gs.SUPPLIER_MAX_STEPS + 2])
	print("supplier ladder: %d steps of %.0f%%, cap +%d%%"
		% [gs.SUPPLIER_MAX_STEPS, gs.SUPPLIER_STEP * 100.0, gs.supplier_pct(sym)])
	# It is per-material, not a global bonus.
	_chk(is_equal_approx(gs.supplier_mult("Cu"), 1.0), "another material is unaffected")

	# ---------- B. claiming advances the ladder and pays it ----------
	gs.hard_reset()
	gs.ensure_standing_board()
	var board: Array = gs.standing_board
	_chk(not board.is_empty(), "the board has orders to claim")
	if not board.is_empty():
		var q: Dictionary = board[0]
		var tgt := String(q.get("target", ""))
		gs.resources[tgt] = int(q.get("target_qty", 1)) * 3
		gs.sync_standing_gather()
		var before_credits: int = gs.credits
		var claimed: bool = gs.claim_standing_order(0)
		_chk(claimed, "a stocked order claims")
		_chk(int(gs.supplier_deliveries.get(tgt, 0)) == 1,
			"the claim advances that material's ladder",
			"%d deliveries" % int(gs.supplier_deliveries.get(tgt, 0)))
		_chk(gs.credits > before_credits, "and pays out")
		# The second delivery of the same material must pay more than face value.
		_chk(gs.supplier_mult(tgt) > 1.0, "the next order for it carries a premium",
			"x%.2f" % gs.supplier_mult(tgt))

	# ---------- C. run-scoped: a warp resets the ladder ----------
	# Left to compound, repeat trade would inflate lifetime_credits — the number
	# the warp gate reads — so the ladder must not survive a prestige.
	gs.hard_reset()
	gs.supplier_deliveries["Fe"] = 5
	gs.lifetime_credits = 600_000_000
	gs.credits_at_warp_start = 0
	gs.execute_warp()
	_chk(gs.supplier_deliveries.is_empty(), "warping clears the ladder",
		"%s" % str(gs.supplier_deliveries))
	gs.hard_reset()
	gs.supplier_deliveries["Fe"] = 5
	gs.hard_reset()
	_chk(gs.supplier_deliveries.is_empty(), "a new game clears it too")

	# ---------- D. a sector unlock refreshes the stale cards only ----------
	gs.hard_reset()
	gs.ensure_standing_board()
	gs.last_max_diff = gs.standing_max_diff()
	# One card earned, one nearly stocked, the rest untouched.
	var earned_id := ""
	var stocked_id := ""
	if gs.standing_board.size() >= 3:
		var q0: Dictionary = gs.standing_board[0]
		q0["completed"] = true
		q0["claimed"] = false
		earned_id = String(q0.get("id", ""))
		var q1: Dictionary = gs.standing_board[1]
		q1["current_qty"] = int(q1.get("target_qty", 10))     # fully stocked
		stocked_id = String(q1.get("id", ""))
	# Open a sector: raise the reachable band the way a zone research does.
	for z in gd.ZONES:
		var req := String(z.get("research_req", ""))
		var flag := String(z.get("unlock_flag", ""))
		if int(z.get("difficulty", 1)) <= gs.standing_max_diff() + 1:
			if req != "":
				gs.unlocked_research[req] = true
			if flag != "":
				gs.game_flags[flag] = true
	var refreshed: bool = gs.refresh_standing_for_unlock()
	_chk(refreshed, "the unlock refreshes the board",
		"band %d -> %d" % [gs.last_max_diff, gs.standing_max_diff()])
	if refreshed:
		var kept_earned := false
		var kept_stocked := false
		for q2 in gs.standing_board:
			var qid := String((q2 as Dictionary).get("id", ""))
			if qid == earned_id:
				kept_earned = true
			if qid == stocked_id:
				kept_stocked = true
		_chk(earned_id == "" or kept_earned,
			"a completed-unclaimed card SURVIVES — never vaporise an earned claim")
		_chk(stocked_id == "" or kept_stocked,
			"a card already half-stocked survives too")
		_chk(gs.standing_board.size() == gs.STANDING_BOARD_SIZE,
			"the board is refilled to full", "%d cards" % gs.standing_board.size())
		_chk(gs.standing_notice != "", "the player is told the board changed")
	# Running it again with no further unlock must do nothing.
	gs.standing_notice = ""
	_chk(not gs.refresh_standing_for_unlock(),
		"a second check with no new sector is a no-op")

	gs._suppress_fx = false
	print("")
	if errs.is_empty():
		print("ERRORS: none")
	else:
		print("--- ERRORS (%d) ---" % errs.size())
		for e in errs:
			print("  x %s" % e)
	print("ORDERS: %s" % ("FAIL" if not errs.is_empty() else "PASS"))
	quit()
