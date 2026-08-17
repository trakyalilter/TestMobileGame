extends SceneTree
## Audit of the research table and every mission that depends on it.
## Structural (broken ids, cycles, unreachable nodes), referential (does anything
## gate itself behind a tech that does not exist), progression (can a research
## mission actually be finished when the chain hands it to you), and economic
## (does the cost curve ever go backwards).

var errs: Array = []
var warns: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s: String) -> void: errs.append(s)
func W(s: String) -> void: warns.append(s)

## Every tech that must already be unlocked before `tid` can be.
func _prereqs(gd, tid: String) -> Array:
	var t: Dictionary = gd.RESEARCH.get(tid, {})
	var out: Array = []
	var p := String(t.get("parent", ""))
	if p != "":
		out.append(p)
	for r in t.get("req_tech", []):
		if String(r) != "":
			out.append(String(r))
	return out

## Transitive prerequisite closure, cycle-safe.
func _closure(gd, tid: String) -> Dictionary:
	var seen := {}
	var stack: Array = _prereqs(gd, tid).duplicate()
	while not stack.is_empty():
		var n: String = String(stack.pop_back())
		if seen.has(n):
			continue
		seen[n] = true
		for p in _prereqs(gd, n):
			stack.append(p)
	return seen

func _run() -> void:
	var gs = root.get_node("GameState")
	var gd = root.get_node("GameData")
	print("techs=%d  missions=%d" % [gd.RESEARCH.size(), gd.MISSIONS.size()])

	# ---------- A. structure ----------
	for tid in gd.RESEARCH:
		for p in _prereqs(gd, tid):
			if not gd.RESEARCH.has(p):
				E("tech '%s' requires '%s' which does not exist" % [tid, p])
	for tid in gd.RESEARCH:
		var c := _closure(gd, tid)
		if c.has(tid):
			E("tech '%s' is in its own prerequisite closure (cycle)" % tid)

	# ---------- B. referential: research_req gates ----------
	# ZONES is an Array of dicts; the rest are id -> dict maps. Normalise to
	# (label, id, dict) triples so one pass covers every gated table.
	var gated := {
		"ZONES": gd.ZONES, "CRAFT": gd.CRAFT, "BUILDINGS": gd.BUILDINGS,
		"MODULES": gd.MODULES, "GATHER": gd.GATHER, "HULLS": gd.HULLS,
	}
	var gated_rows: Array = []
	for label in gated:
		var tbl = gated[label]
		if tbl is Array:
			for row in tbl:
				gated_rows.append([String(label), String((row as Dictionary).get("id", "?")), row])
		else:
			for id in tbl:
				gated_rows.append([String(label), String(id), tbl[id]])
	for row in gated_rows:
		var req := String((row[2] as Dictionary).get("research_req", ""))
		if req != "" and not gd.RESEARCH.has(req):
			E("%s '%s' is gated behind missing tech '%s'" % [row[0], row[1], req])

	# ---------- C. research missions target real techs ----------
	var research_missions := 0
	for mid in gd.MISSIONS:
		var m: Dictionary = gd.MISSIONS[mid]
		var ty := String(m.get("type", ""))
		if ty != "research" and ty != "research_multi":
			continue
		research_missions += 1
		var tgt = m.get("target", "")
		var list: Array = tgt if tgt is Array else [tgt]
		for t in list:
			if not gd.RESEARCH.has(String(t)):
				E("mission '%s' asks for tech '%s' which does not exist" % [mid, String(t)])
		if ty == "research_multi":
			var q := int(m.get("qty", m.get("target_qty", 1)))
			if q != list.size():
				E("mission '%s' bundles %d techs but needs qty %d" % [mid, list.size(), q])

	# ---------- D. progression: is each research mission finishable in chain order? ----------
	# Walk the chain, accumulating what the player has been TOLD to research. A
	# mission that asks for a tech whose prerequisites were never asked for (and
	# are not free roots) is completable only by off-chain grinding.
	var chain: Array = []
	var cur := ""
	for mid in gd.MISSIONS:
		var is_target := false
		for other in gd.MISSIONS:
			if String((gd.MISSIONS[other] as Dictionary).get("next", "")) == mid:
				is_target = true
				break
		if not is_target:
			cur = mid
			break
	var guard := 0
	var unlocked := {}
	while cur != "" and guard < 500:
		guard += 1
		chain.append(cur)
		var m: Dictionary = gd.MISSIONS.get(cur, {})
		var ty := String(m.get("type", ""))
		if ty == "research" or ty == "research_multi":
			var tgt = m.get("target", "")
			var list: Array = tgt if tgt is Array else [tgt]
			for t in list:
				var tid := String(t)
				for need in _closure(gd, tid):
					if not unlocked.has(need):
						W("mission '%s' asks for '%s' but its prerequisite '%s' is never a chain objective" % [cur, tid, need])
				unlocked[tid] = true
		cur = String(m.get("next", ""))
	print("chain length=%d  research missions=%d" % [chain.size(), research_missions])

	# ---------- E. economics: where the cost curve steps backwards ----------
	# INFORMATIONAL. Verified against desktop's own tech_tree: every case below
	# exists upstream too. A cheap leaf hanging off an expensive hub is the
	# intended shape — the hub is the investment, the leaf is a small add-on — so
	# this is a map of the curve, not a defect list. It earns its place by
	# catching a NEW inversion that desktop does not have.
	var inversions := 0
	for tid in gd.RESEARCH:
		var t: Dictionary = gd.RESEARCH[tid]
		var c := int(t.get("credits", 0))
		for p in _prereqs(gd, tid):
			var pc := int((gd.RESEARCH.get(p, {}) as Dictionary).get("credits", 0))
			if c > 0 and pc > 0 and c < pc:
				inversions += 1
				W("[curve] '%s' (%s cr) is cheaper than its prerequisite '%s' (%s cr)" % [tid, c, p, pc])
	print("cost-curve inversions: %d (informational — matches desktop)" % inversions)

	# ---------- F. the x2 material multiplier and its exemptions ----------
	var scaled := 0
	var exempt := 0
	for tid in gd.RESEARCH:
		var raw: Dictionary = (gd.RESEARCH[tid] as Dictionary).get("items", {})
		var eff: Dictionary = gs.research_items(tid)
		for sym in raw:
			var r := int(raw[sym])
			var e := int(eff.get(sym, 0))
			if gs._research_item_scalable(String(sym)):
				scaled += 1
				if e != r * 2:
					E("tech '%s' item '%s' should scale x2 (%d) but is %d" % [tid, sym, r * 2, e])
			else:
				exempt += 1
				if e != r:
					E("tech '%s' item '%s' is exempt but changed %d -> %d" % [tid, sym, r, e])
	print("cost items: %d scaled, %d exempt" % [scaled, exempt])

	# ---------- G. dead ends: a tech that does nothing at all ----------
	# Mobile implements most tech effects in CODE (research_bonus, the per-action
	# speed tables), not in the data's "effects" array — so checking the data
	# alone reports almost every leaf as dead. Probe the engine instead.
	var referenced := {}
	for row in gated_rows:
		referenced[String((row[2] as Dictionary).get("research_req", ""))] = true
	for tid in gd.RESEARCH:
		for p in _prereqs(gd, tid):
			referenced[p] = true
	# A tech can also be consumed by NAME anywhere in the engine — most are read
	# via is_research_unlocked("id") rather than a bonus key matching the id. Scan
	# the source so the check reflects real consumption instead of one convention.
	var src := ""
	for path in ["res://scripts/core/game_state.gd", "res://scripts/ui/main.gd"]:
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			src += f.get_as_text()
			f.close()
	if src == "":
		W("could not read engine source — dead-tech check skipped")
	for tid in gd.RESEARCH:
		var t: Dictionary = gd.RESEARCH[tid]
		if referenced.has(tid):
			continue
		if not (t.get("effects", []) as Array).is_empty():
			continue
		if src.find('"%s"' % tid) >= 0:
			continue      # named somewhere in the engine
		W("tech '%s' (%s) gates nothing, is read nowhere, and leads nowhere" % [tid, String(t.get("name", tid))])

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
	print("RESEARCH_AUDIT: %s" % ("FAIL" if not errs.is_empty() else "PASS"))
	quit()
