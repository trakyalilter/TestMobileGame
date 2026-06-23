extends SceneTree
## RESEARCH MATERIAL-COST ANALYSIS. For every research, model the wall-clock time
## to acquire its required materials, so amounts can be balanced.
##
## Per-unit acquisition time t(sym):
##   gather  : min over gathers yielding sym of  duration / (chance * maxqty)
##             (deterministic gather rolls chance, then yields the max quantity)
##   craft   : min over recipes outputting sym of duration/out + Σ t(in)*in/out
##   combat  : COMBAT_KILL_S / (chance * maxqty)   [rough — fights are ~constant wall-time]
## All at BASELINE (no skill/yield bonuses): relative ratios are what matter for balance.

var gd
const COMBAT_KILL_S := 8.0      # assumed wall-time per kill (rough; flagged in output)

var _ut := {}                   # sym -> seconds/unit (memoized)
var _src := {}                  # sym -> "gather"/"craft"/"combat"/"none"
var _busy := {}                 # cycle guard

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

# --- source lookups -----------------------------------------------------------
func _gathers_for(sym: String) -> Array:
	var out := []
	for gid in gd.GATHER:
		for row in gd.GATHER[gid].get("loot", []):
			if row[0] == sym:
				out.append([gid, float(row[1]), float(row[3])])   # [id, chance, max]
	return out

func _crafts_for(sym: String) -> Array:
	var out := []
	for cid in gd.CRAFT:
		if (gd.CRAFT[cid].get("outputs", {}) as Dictionary).has(sym):
			out.append(cid)
	return out

func _enemies_for(sym: String) -> Array:
	var out := []
	for eid in gd.ENEMIES:
		for row in gd.ENEMIES[eid].get("loot", []):
			if row[0] == sym:
				out.append([float(row[1]), float(row[3])])   # [chance, max]
	return out

# --- per-unit time, memoized with cycle guard --------------------------------
func _unit_time(sym: String) -> float:
	if sym == "credits":
		return 0.0
	if _ut.has(sym):
		return _ut[sym]
	if _busy.has(sym):
		return 1.0e12   # recursion cycle — make this path lose
	_busy[sym] = true
	var best := 1.0e18
	var src := "none"
	# gather
	for g in _gathers_for(sym):
		var dur: float = float(gd.GATHER[g[0]].get("duration", 4.0))
		var per: float = g[1] * g[2]
		if per > 0.0:
			var t := dur / per
			if t < best:
				best = t; src = "gather"
	# craft (recursive)
	for cid in _crafts_for(sym):
		var r: Dictionary = gd.CRAFT[cid]
		var out_q: float = float(r["outputs"][sym])
		if out_q <= 0.0:
			continue
		var dur: float = float(r.get("duration", 5.0))
		var t := dur / out_q
		var ok := true
		for insym in r.get("inputs", {}):
			var it := _unit_time(insym)
			if it >= 1.0e12:
				ok = false; break
			t += it * float(r["inputs"][insym]) / out_q
		if ok and t < best:
			best = t; src = "craft"
	# combat drop (rough)
	if best >= 1.0e18:
		for e in _enemies_for(sym):
			var per: float = e[0] * e[1]
			if per > 0.0:
				var t := COMBAT_KILL_S / per
				if t < best:
					best = t; src = "combat"
	_busy.erase(sym)
	if best >= 1.0e18:
		best = -1.0   # no known source
		src = "none"
	_ut[sym] = best
	_src[sym] = src
	return best

func _fmt_dur(s: float) -> String:
	if s < 0.0:
		return "n/a"
	if s < 90.0:
		return "%.0fs" % s
	if s < 5400.0:
		return "%.1fm" % (s / 60.0)
	return "%.1fh" % (s / 3600.0)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	gd = root.get_node("GameData")

	# Pre-warm unit times for everything referenced by research.
	var rows := []   # [total_s, id, dict]
	for rid in gd.RESEARCH:
		var t: Dictionary = gd.RESEARCH[rid]
		var total := 0.0
		var combat := false
		var unknown := false
		var parts := []
		for sym in t.get("items", {}):
			var qty := int(t["items"][sym])
			var ut := _unit_time(sym)
			var line_t := -1.0
			if ut >= 0.0:
				line_t = ut * qty
				total += line_t
			else:
				unknown = true
			if _src.get(sym, "") == "combat":
				combat = true
			parts.append([sym, qty, ut, line_t, _src.get(sym, "none")])
		rows.append([total, rid, t, parts, combat, unknown])

	rows.sort_custom(func(a, b): return a[0] > b[0])

	print("\n===== RESEARCH MATERIAL-COST ANALYSIS (baseline, no skill bonuses) =====")
	print("Assumptions: gather yields chance*max per cycle; craft costs roll up input time;")
	print("combat-drop materials use %ds/kill (rough). Times = pure material-gather wall time," % int(COMBAT_KILL_S))
	print("one action at a time. Credits shown raw (separate parallel cost).\n")
	print("%-26s | %-12s | %4s | %12s | %10s | %s" % ["RESEARCH", "CATEGORY", "WARP", "CREDITS", "MAT-TIME", "FLAGS"])
	print("-".repeat(96))
	for r in rows:
		var t: Dictionary = r[2]
		var flags := ""
		if r[4]: flags += "combat "
		if r[5]: flags += "UNKNOWN-SRC "
		print("%-26s | %-12s | %4s | %12s | %10s | %s" % [
			r[1], String(t.get("category", "")).substr(0, 12), "yes" if t.get("requires_warp", false) else "",
			gd.fmt(int(t.get("credits", 0))), _fmt_dur(r[0]), flags])

	# Per-research item breakdown.
	print("\n\n===== PER-RESEARCH ITEM BREAKDOWN =====")
	for r in rows:
		var t: Dictionary = r[2]
		print("\n%s  [%s]  — credits ₡%s — MAT-TIME %s%s" % [
			t.get("name", r[1]), r[1], gd.fmt(int(t.get("credits", 0))), _fmt_dur(r[0]),
			"   (+combat)" if r[4] else ""])
		for p in r[3]:
			print("    %5d x %-16s  @ %9s/ea  = %9s   [%s]" % [
				p[1], p[0], _fmt_dur(p[2]), _fmt_dur(p[3]), p[4]])

	# Resource unit-time reference (sorted).
	print("\n\n===== RESOURCE UNIT-TIME REFERENCE =====")
	var refs := []
	for sym in _ut:
		refs.append([_ut[sym], sym, _src.get(sym, "none")])
	refs.sort_custom(func(a, b): return a[0] > b[0])
	for x in refs:
		print("  %-18s %10s/unit   [%s]" % [x[1], _fmt_dur(x[0]), x[2]])
	quit()
