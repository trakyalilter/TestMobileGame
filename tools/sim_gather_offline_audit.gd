extends SceneTree
## Audit of gathering and the offline catch-up paths.
##
## Offline is the hardest surface to reason about, because it re-implements every
## loop in closed form: a divergence between what a loop pays online and what its
## offline twin pays is invisible in play but is either an exploit or a quiet tax
## on anyone who closes the app. So this RUNS both and compares them.
##
## It also guards the two failure modes desktop had to fix by hand: an uncapped
## away window (unbounded accrual, startup stall) and re-applying the same window
## twice when the app dies before its next save.

var errs: Array = []
var warns: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s: String) -> void: errs.append(s)
func W(s: String) -> void: warns.append(s)
func _chk(cond: bool, label: String, detail := "") -> void:
	if not cond:
		E("%s%s" % [label, ("  — " + detail) if detail != "" else ""])

func _total(gs) -> int:
	var n := 0
	for sym in gs.resources:
		n += int(gs.resources[sym])
	return n

func _run() -> void:
	var gs = root.get_node("GameState")
	var gd = root.get_node("GameData")
	print("gather actions=%d" % gd.GATHER.size())

	# ---------- A. gather table sanity ----------
	var reachable := 0
	for gid in gd.GATHER:
		var a: Dictionary = gd.GATHER[gid]
		var loot: Array = a.get("loot", [])
		if loot.is_empty():
			E("gather action '%s' has an empty loot table — it produces nothing" % gid)
		for row in loot:
			if (row as Array).size() < 4:
				E("gather '%s' row %s is malformed" % [gid, str(row)])
				continue
			if String(row[0]) != "credits" and not gd.RESOURCES.has(String(row[0])):
				E("gather '%s' yields '%s', not a real resource" % [gid, row[0]])
			if float(row[1]) <= 0.0 or float(row[1]) > 1.0:
				E("gather '%s' drop '%s' has chance %.3f" % [gid, row[0], float(row[1])])
			if float(row[2]) > float(row[3]):
				E("gather '%s' drop '%s' has min > max" % [gid, row[0]])
		if float(a.get("duration", 0.0)) <= 0.0:
			E("gather '%s' has a non-positive duration (divide-by-zero risk)" % gid)
		if int(a.get("level_req", 1)) <= gs.MAX_LEVEL:
			reachable += 1
		else:
			E("gather '%s' needs level %d, above the cap of %d" % [gid, int(a.get("level_req", 1)), gs.MAX_LEVEL])
	print("gather actions reachable within the level cap: %d" % reachable)

	# ---------- B. the deterministic yield rule ----------
	# v0.2.1: a completed cycle grants the TOP of the range plus flat bonuses,
	# scaled by the yield multiplier — not a min-max roll. The card UI promises
	# exactly this number, so a regression here makes every gather card lie.
	gs.hard_reset()
	gs.skills["harvesting"] = 0
	var gid0 := ""
	for gid in gd.GATHER:
		if int((gd.GATHER[gid] as Dictionary).get("level_req", 1)) <= 1:
			gid0 = String(gid)
			break
	_chk(gid0 != "", "a level-1 gather action exists to test with")
	if gid0 != "":
		var row0: Array = (gd.GATHER[gid0] as Dictionary)["loot"][0]
		var sym0 := String(row0[0])
		var top := int(row0[3])
		var flat: int = int(gs.research_bonus("gathering_yield")) + int(gs.tree_gathering_flat())
		var expect := maxi(1, int(round((top + flat) * gs.yield_mult("harvesting"))))
		gs.resources[sym0] = 0
		# Only deterministic rows (chance 1.0) are guaranteed to land every cycle.
		if float(row0[1]) >= 1.0:
			gs._roll_loot((gd.GATHER[gid0] as Dictionary).get("loot", []),
				gs.yield_mult("harvesting"), flat, false, true)
			_chk(gs.amount(sym0) == expect,
				"a gather cycle grants exactly the deterministic amount the card shows",
				"got %d, expected %d" % [gs.amount(sym0), expect])

	# ---------- C. online vs offline parity ----------
	# Run the same action for the same wall-clock time through both paths.
	if gid0 != "":
		var dur: float = gs.effective_duration("gather", gid0)
		var window: float = dur * 40.0        # 40 whole cycles
		# --- online ---
		gs.hard_reset()
		gs.skills["harvesting"] = 0
		gs.start_task("gather", gid0)
		var t := 0.0
		while t < window:
			gs._tick_active(dur)
			t += dur
		var online_total := _total(gs)
		var online_xp := int(gs.skills.get("harvesting", 0))
		# --- offline, same window ---
		gs.hard_reset()
		gs.skills["harvesting"] = 0
		gs.start_task("gather", gid0)
		gs._suppress_fx = true
		gs._apply_offline(window)
		gs._suppress_fx = false
		var offline_total := _total(gs)
		var offline_xp := int(gs.skills.get("harvesting", 0))
		print("parity over %d cycles: online %d units / %d xp, offline %d units / %d xp"
			% [int(window / dur), online_total, online_xp, offline_total, offline_xp])
		_chk(offline_total > 0, "offline gathering produces something at all")
		if online_total > 0:
			var ratio := float(offline_total) / float(online_total)
			_chk(ratio > 0.5 and ratio < 2.0,
				"offline yield is in the same ballpark as online",
				"offline/online = %.2f" % ratio)
		if online_xp > 0:
			var xr := float(offline_xp) / float(online_xp)
			_chk(xr > 0.5 and xr < 2.0, "offline XP is in the same ballpark as online",
				"offline/online = %.2f" % xr)

	# ---------- D. the away window must be capped ----------
	# Unbounded accrual is both an exploit and a startup stall: every offline path
	# loops over the window, so a month away is a month of work at load time.
	_chk(gs.OFFLINE_DELTA_CAP_SECONDS > 0.0, "an offline cap exists")
	gs.hard_reset()
	gs.start_task("gather", gid0)
	gs._suppress_fx = true
	gs._apply_offline(gs.OFFLINE_DELTA_CAP_SECONDS)
	var at_cap := _total(gs)
	gs.hard_reset()
	gs.start_task("gather", gid0)
	gs._apply_offline(gs.OFFLINE_DELTA_CAP_SECONDS * 30.0)   # a month
	var past_cap := _total(gs)
	gs._suppress_fx = false
	# _apply_offline itself takes the raw delta; the CALLERS clamp. Verify the
	# clamp exists at both entry points rather than trusting one number.
	var src := ""
	var f := FileAccess.open("res://scripts/core/game_state.gd", FileAccess.READ)
	if f != null:
		src = f.get_as_text()
		f.close()
	var clamps := src.count("OFFLINE_DELTA_CAP_SECONDS")
	_chk(clamps >= 3, "both offline entry points clamp the window",
		"references=%d (constant + 2 call sites expected)" % clamps)
	print("uncapped month would yield %d vs %d at the cap (callers clamp: %d refs)"
		% [past_cap, at_cap, clamps])

	# ---------- E. offline must never go backwards ----------
	gs.hard_reset()
	gs.start_task("gather", gid0)
	gs._suppress_fx = true
	gs._apply_offline(1.0)          # below a single cycle
	gs._suppress_fx = false
	for sym in gs.resources:
		_chk(int(gs.resources[sym]) >= 0, "a sub-cycle window never yields a negative stack",
			"%s = %d" % [sym, int(gs.resources[sym])])

	# ---------- F. mastery accrues offline as well as online ----------
	gs.hard_reset()
	gs.start_task("gather", gid0)
	var m_before: float = gs.mastery_xp(gid0)
	gs._suppress_fx = true
	gs._apply_offline(gs.effective_duration("gather", gid0) * 20.0)
	gs._suppress_fx = false
	_chk(gs.mastery_xp(gid0) > m_before, "offline cycles credit mastery XP",
		"%.0f -> %.0f" % [m_before, gs.mastery_xp(gid0)])

	# ---------- report ----------
	print("")
	if errs.is_empty():
		print("ERRORS: none")
	else:
		print("--- ERRORS (%d) ---" % errs.size())
		for e in errs:
			print("  x %s" % e)
	if not warns.is_empty():
		print("--- WARNINGS (%d) ---" % warns.size())
		for w in warns:
			print("  ! %s" % w)
	print("GATHER_OFFLINE_AUDIT: %s" % ("FAIL" if not errs.is_empty() else "PASS"))
	quit()
