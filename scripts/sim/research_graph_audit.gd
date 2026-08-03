extends Node
# ============================================================================
# RESEARCH GRAPH AUDIT — is the tech tree STRUCTURALLY sound?
#
# The existing research probes ask other questions:
#   research_deadnode_audit  — does a tech DO anything?
#   research_costcheck       — what does a tech really cost?
#   research_dump            — how long does the tree take?
# None of them ask whether the GRAPH itself is valid. This does.
#
# can_unlock() treats BOTH `parent` and `req_tech` as hard prerequisites (AND),
# plus optional requires_warp / requires_flag world gates. So the tree is a DAG
# whose edges are parent+req_tech. Checks:
#   1. DANGLING   — a prereq naming a tech that does not exist (permanent lock)
#   2. CYCLE      — a prereq loop (nothing in it can EVER unlock)
#   3. UNREACHABLE— nodes no prereq-satisfying order can reach
#   4. ORPHAN GATE— content whose research_req names a non-existent tech
#                   (that content is unreachable forever)
#   5. TIER FLOW  — a prereq sitting in a LATER tier than its child
#   6. COST FLOW  — a prereq costing more than the child it gates
#   7. COST ITEMS — cost_items naming an element that does not exist
#   8. SELF-REF   — a node listing itself as its own prereq
#
#   Godot --headless --path <root> res://scenes/research_graph_audit.tscn
# ============================================================================

var fails := 0
var warns := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond: fails += 1
	print("[RGA] %-50s %s %s" % [name, "OK" if cond else "*** FAIL", detail])

func _warn(msg: String) -> void:
	warns += 1
	print("[RGA]   !! %s" % msg)


# Both prereq edges, skipping empties.
func _prereqs(node: Dictionary) -> Array:
	var out := []
	var p = node.get("parent")
	if p != null and String(p) != "":
		out.append(String(p))
	var r = node.get("req_tech")
	if r != null and String(r) != "":
		out.append(String(r))
	return out


func _ready() -> void:
	GameState.set_process(false)
	GameState.hard_reset()
	var rm = GameState.research_manager
	var tt: Dictionary = rm.tech_tree

	print("[RGA] ============ research graph audit ============")
	print("[RGA] tech nodes: %d" % tt.size())

	# ── 1. DANGLING + 8. SELF-REF ──
	var dangling := []
	var selfref := []
	for tid in tt:
		for p in _prereqs(tt[tid]):
			if p == String(tid):
				selfref.append(String(tid))
			elif not tt.has(p):
				dangling.append("%s -> %s" % [tid, p])
	_ok("no prereq names a missing tech", dangling.is_empty(), str(dangling))
	_ok("no tech is its own prereq", selfref.is_empty(), str(selfref))

	# ── 2. CYCLE + 3. UNREACHABLE ──
	# Kahn-style: repeatedly unlock everything whose prereqs are all satisfied.
	# Whatever never unlocks is either in a cycle or downstream of a broken edge.
	var unlocked := {}
	var progress := true
	while progress:
		progress = false
		for tid in tt:
			if unlocked.has(tid):
				continue
			var ready := true
			for p in _prereqs(tt[tid]):
				if not unlocked.has(p):
					ready = false
					break
			if ready:
				unlocked[tid] = true
				progress = true
	var stuck := []
	for tid in tt:
		if not unlocked.has(tid):
			stuck.append(String(tid))
	_ok("every tech is reachable (no cycle / broken chain)", stuck.is_empty(),
		("%d stuck: %s" % [stuck.size(), str(stuck)]) if not stuck.is_empty() else "")

	# Roots — sanity that the tree has an entry point at all.
	var roots := []
	for tid in tt:
		if _prereqs(tt[tid]).is_empty():
			roots.append(String(tid))
	_ok("tree has at least one root", not roots.is_empty(), "roots=%s" % str(roots))

	# ── 4. ORPHAN GATES — content pointing at a tech that does not exist ──
	# Every `research_req` in the game must name a real tech, or that content can
	# never be built/crafted/entered.
	var orphans := []
	var _check_reqs := func(src: String, db: Dictionary) -> void:
		for k in db:
			var d = db[k]
			if typeof(d) != TYPE_DICTIONARY:
				continue
			var rq := String((d as Dictionary).get("research_req", ""))
			if rq != "" and not tt.has(rq):
				orphans.append("%s:%s -> %s" % [src, k, rq])
	_check_reqs.call("bld", GameState.infrastructure_manager.building_db)
	_check_reqs.call("rcp", GameState.processing_manager.recipes)
	_check_reqs.call("gath", GameState.gathering_manager.actions)
	_check_reqs.call("mod", GameState.shipyard_manager.modules)
	_check_reqs.call("hull", GameState.shipyard_manager.hulls)
	_check_reqs.call("zone", GameState.combat_manager.zones)
	_ok("no content gated behind a missing tech", orphans.is_empty(), str(orphans))

	# ── 5. TIER FLOW ──
	# A prereq in a LATER tier than its child means the tree renders out of order.
	var tier_bad := []
	for tid in tt:
		var my_t := int((tt[tid] as Dictionary).get("tier", 0))
		for p in _prereqs(tt[tid]):
			if not tt.has(p):
				continue
			var pt := int((tt[p] as Dictionary).get("tier", 0))
			if pt > my_t:
				tier_bad.append("%s(T%d) requires %s(T%d)" % [tid, my_t, p, pt])
	_ok("no prereq sits in a later tier than its child", tier_bad.is_empty(), "")
	for t in tier_bad:
		_warn("TIER INVERSION: %s" % t)

	# ── 6. COST FLOW (advisory) ──
	var cost_bad := []
	for tid in tt:
		var my_c := float((tt[tid] as Dictionary).get("cost", 0))
		for p in _prereqs(tt[tid]):
			if not tt.has(p):
				continue
			var pc := float((tt[p] as Dictionary).get("cost", 0))
			if pc > my_c and my_c > 0.0:
				cost_bad.append("%s(%d) gated by pricier %s(%d)" % [tid, int(my_c), p, int(pc)])
	print("[RGA]   cost inversions (advisory): %d" % cost_bad.size())
	for c in cost_bad:
		_warn("COST INVERSION: %s" % c)

	# ── 7. COST ITEMS must be real elements ──
	# NOTE: an element is real if EITHER registry knows it — get_display_name falls
	# back from ELEMENT_NAMES to ELEMENT_DATA. Checking only ELEMENT_NAMES flagged
	# NanoSubstrate (a live, building-produced material) as a hard lock. It isn't.
	var bad_items := []
	for tid in tt:
		var ci: Dictionary = (tt[tid] as Dictionary).get("cost_items", {})
		for sym in ci:
			var s := String(sym)
			if not (ElementDB.ELEMENT_NAMES.has(s) or ElementDB.ELEMENT_DATA.has(s)):
				bad_items.append("%s -> %s" % [tid, s])
	_ok("all cost_items name a real element", bad_items.is_empty(), str(bad_items))

	# ── 9. TAB COVERAGE — every tech must be reachable in the UI ──
	# research_page.graphs is a HARDCODED per-tab node list, not derived from the
	# node's `category`. A tech added to tech_tree but missed there renders nowhere:
	# unresearchable in normal play even though every graph check above passes.
	var rp = load("res://scripts/ui/research_page.gd").new()
	var in_tab := {}
	var dupes := []
	for tab in rp.graphs:
		for nid in (rp.graphs[tab] as Dictionary).get("nodes", []):
			var n := String(nid)
			if in_tab.has(n):
				dupes.append("%s in both %s and %s" % [n, in_tab[n], tab])
			in_tab[n] = String(tab)
	var invisible := []
	for tid in tt:
		if not in_tab.has(String(tid)):
			invisible.append(String(tid))
	var ghost := []          # listed in a tab but no such tech
	for n in in_tab:
		if not tt.has(n):
			ghost.append("%s (tab %s)" % [n, in_tab[n]])
	rp.free()
	_ok("every tech appears in a research tab", invisible.is_empty(),
		("%d invisible: %s" % [invisible.size(), str(invisible)]) if not invisible.is_empty() else "")
	_ok("no tech listed in two tabs", dupes.is_empty(), str(dupes))
	_ok("no tab lists a non-existent tech", ghost.is_empty(), str(ghost))

	# 9b. ADVISORY, not a defect. A node whose parent sits in another tab is laid out
	# as a root there (calculate_layout: "if parent not in this tab, treat as root"),
	# so it renders with no prereq line. That is DELIBERATE for cross-discipline
	# branches — energy_shields is a Combat tech growing off the Industry root — and
	# 10 such edges predate this audit. Listed so a placement choice is visible, and
	# so an accidental orphan (a node put in the wrong tab) can be spotted.
	var cross_tab := []
	for tid in tt:
		var par = (tt[tid] as Dictionary).get("parent")
		if par == null or String(par) == "":
			continue
		var mine := String(in_tab.get(String(tid), ""))
		var theirs := String(in_tab.get(String(par), ""))
		if mine != "" and theirs != "" and mine != theirs:
			cross_tab.append("%s(%s) <- %s(%s)" % [tid, mine, par, theirs])
	print("[RGA]   cross-tab prereq edges (no line drawn): %d" % cross_tab.size())
	for c in cross_tab:
		print("[RGA]     %s" % c)

	# ── World-gated techs: report, so a flag typo is visible ──
	var gated := []
	for tid in tt:
		var n: Dictionary = tt[tid]
		if bool(n.get("requires_warp", false)):
			gated.append("%s (warp)" % tid)
		var rf := String(n.get("requires_flag", ""))
		if rf != "":
			gated.append("%s (flag:%s)" % [tid, rf])
	print("[RGA]   world-gated techs: %s" % str(gated))

	print("[RGA] ---- %d warning(s) ----" % warns)
	print("[RGA] ============ %s ============" % ("ALL PASS" if fails == 0 else "%d FAIL(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
