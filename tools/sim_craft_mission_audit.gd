extends SceneTree
## Audit of the crafting economy and the mission chain's objectives.
##
## sim_data_integrity already proves every id RESOLVES and sim_mission_audit
## proves the chain is structurally sound. This covers what neither does:
##   * closed conversion loops that print materials for free
##   * recipe inputs nothing in the game can actually produce
##   * mission objectives that resolve but can never be SATISFIED
##
## The loop sweep matters more on mobile than upstream. Desktop's exploit risk
## comes from an ADDITIVE per-cycle yield flat; mobile multiplies craft outputs
## by research_efficiency_mult (up to x32), so a two-step loop compounds it to
## x1024 and a ratio that looks safely lossy at x1 can still print.

var errs: Array = []
var warns: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s: String) -> void: errs.append(s)
func W(s: String) -> void: warns.append(s)

## Everything the game can hand the player without crafting it.
func _base_sources(gd) -> Dictionary:
	var out := {}
	for gid in gd.GATHER:
		for row in (gd.GATHER[gid] as Dictionary).get("loot", []):
			out[String(row[0])] = true
	for eid in gd.ENEMIES:
		var e: Dictionary = gd.ENEMIES[eid]
		for key in ["loot", "rare_loot"]:
			for row in e.get(key, []):
				out[String(row[0])] = true
	for bid in gd.BUILDINGS:
		for sym in (gd.BUILDINGS[bid] as Dictionary).get("yield", {}):
			out[String(sym)] = true
	return out

## The later objective that introduces `sym`, or "" if the chain never does.
## Only objectives AFTER `after_id` count — the caller already knows it is not
## taught before that point.
func _taught_at(gd, sym: String, after_id: String) -> String:
	var seen_self := false
	for mid in gd.MISSION_ORDER:
		if String(mid) == after_id:
			seen_self = true
			continue
		if not seen_self:
			continue
		var m: Dictionary = gd.MISSIONS[mid]
		var t = m.get("target", "")
		if t is Dictionary:
			if (t as Dictionary).has(sym):
				return String(mid)
		elif t is Array:
			continue                    # research_multi lists techs, not materials
		elif t is String and String(t) == sym:
			return String(mid)
	return ""

func _run() -> void:
	var gs = root.get_node("GameState")
	var gd = root.get_node("GameData")
	print("recipes=%d  missions=%d" % [gd.CRAFT.size(), gd.MISSIONS.size()])

	# ================= CRAFTING =================

	# ---- A. closed conversion loops (free-material printers) ----
	# Edge a -> b whenever one recipe consumes a and produces b.
	var edges := {}
	for rid in gd.CRAFT:
		var r: Dictionary = gd.CRAFT[rid]
		var ins: Dictionary = r.get("inputs", {})
		var outs: Dictionary = r.get("outputs", {})
		for a in ins:
			for b in outs:
				if String(a) == String(b):
					continue
				if not edges.has(String(a)):
					edges[String(a)] = []
				edges[String(a)].append({
					"rid": rid, "to": String(b),
					"in_qty": float(ins[a]), "out_qty": float(outs[b]),
					"inputs": ins,
				})
	var max_eff: float = 32.0     # Efficiency V
	var loops := 0
	var seen_pairs := {}
	for start in edges:
		for e1 in edges[start]:
			for e2 in edges.get(String(e1["to"]), []):
				if String(e2["to"]) != String(start):
					continue
				var mid := String(e1["to"])
				var key: String = start + "|" + mid if start < mid else mid + "|" + start
				if seen_pairs.has(key):
					continue
				seen_pairs[key] = true
				loops += 1
				# Run e2 once: it yields out2*E of `mid`... in cycle terms, one pass
				# returns out1*out2*E^2 of `start` for in1*in2 spent. Solve for the
				# efficiency at which the cycle stops losing.
				var gain: float = float(e1["out_qty"]) * float(e2["out_qty"])
				var cost: float = float(e1["in_qty"]) * float(e2["in_qty"])
				if gain <= 0.0:
					continue
				var eff_needed: float = sqrt(cost / gain)
				# CLOSED (nothing outside the cycle is consumed) = a pure printer.
				var cycle := {String(start): true, mid: true}
				var closed := true
				for src in [e1, e2]:
					for need in (src["inputs"] as Dictionary):
						if String(need) != "credits" and not cycle.has(String(need)):
							closed = false
				if eff_needed <= 1.0:
					E("%s loop is net-positive with NO research: %s <-> %s"
						% ["closed" if closed else "open", start, mid])
				elif eff_needed <= max_eff:
					var kind: String = "CLOSED — free material printer" if closed \
						else "open (pays outside inputs, but still amplifies)"
					W("[loop] %s <-> %s turns net-positive at efficiency x%.1f (cap x%.0f) — %s"
						% [start, mid, eff_needed, max_eff, kind])
	print("2-cycles examined: %d (open loops included — mobile scales craft outputs\n  by the efficiency multiplier, exactly as desktop does, so an open loop\n  still amplifies its cycle materials)" % loops)

	# ---- B. recipe inputs nothing can produce ----
	var producible := _base_sources(gd)
	var grew := true
	var guard := 0
	while grew and guard < 40:
		grew = false
		guard += 1
		for rid in gd.CRAFT:
			var r: Dictionary = gd.CRAFT[rid]
			var have_all := true
			for sym in r.get("inputs", {}):
				if String(sym) != "credits" and not producible.has(String(sym)):
					have_all = false
					break
			if not have_all:
				continue
			for sym in r.get("outputs", {}):
				if not producible.has(String(sym)):
					producible[String(sym)] = true
					grew = true
			for row in r.get("bonus", []):
				if not producible.has(String(row[0])):
					producible[String(row[0])] = true
					grew = true
	for rid in gd.CRAFT:
		for sym in (gd.CRAFT[rid] as Dictionary).get("inputs", {}):
			if String(sym) == "credits":
				continue
			if not producible.has(String(sym)):
				E("recipe '%s' needs '%s', which nothing gathers, drops, builds or crafts" % [rid, sym])

	# ---- C. recipes that produce nothing ----
	for rid in gd.CRAFT:
		var r: Dictionary = gd.CRAFT[rid]
		if (r.get("outputs", {}) as Dictionary).is_empty() and (r.get("bonus", []) as Array).is_empty():
			E("recipe '%s' has no outputs and no bonus rolls" % rid)

	# ================= MISSION OBJECTIVES =================
	# Every target must resolve for its TYPE — sim_mission_audit only checks
	# defeat and research, so a bad gather/craft/build target slips through and
	# stalls the chain silently (exactly how the m002 tutorial block survived).
	var checked := 0
	for mid in gd.MISSIONS:
		var m: Dictionary = gd.MISSIONS[mid]
		var ty := String(m.get("type", ""))
		var tgt = m.get("target", "")
		checked += 1
		match ty:
			"gather":
				if not gd.RESOURCES.has(String(tgt)):
					E("mission '%s' gathers '%s', not a real resource" % [mid, tgt])
			"gather_multi":
				if not (tgt is Dictionary):
					E("mission '%s' is gather_multi but its target is not a map" % mid)
				else:
					for sym in tgt:
						if not gd.RESOURCES.has(String(sym)):
							E("mission '%s' gathers '%s', not a real resource" % [mid, sym])
			"craft":
				var t := String(tgt)
				var known: bool = gd.CRAFT.has(t) or gd.MODULES.has(t) or gd.RESOURCES.has(t)
				if not known:
					E("mission '%s' crafts '%s', which is not a recipe, module or resource" % [mid, t])
				# A craft objective on a material nothing produces can never finish.
				if gd.RESOURCES.has(t) and not producible.has(t) and not gd.MODULES.has(t):
					E("mission '%s' crafts '%s', which nothing can produce" % [mid, t])
			"build":
				if not gd.BUILDINGS.has(String(tgt)):
					E("mission '%s' builds '%s', not a real building" % [mid, tgt])
			"construct":
				if not gd.HULLS.has(String(tgt)):
					E("mission '%s' constructs '%s', not a real hull" % [mid, tgt])
			"defeat", "defeat_retreat":
				if not gd.ENEMIES.has(String(tgt)):
					E("mission '%s' defeats '%s', not a real enemy" % [mid, tgt])
			"research", "research_multi":
				var list: Array = tgt if tgt is Array else [tgt]
				for t2 in list:
					if not gd.RESEARCH.has(String(t2)):
						E("mission '%s' researches '%s', which does not exist" % [mid, t2])
			_:
				checked -= 1   # event-driven types carry no resolvable target
	print("missions with a resolvable target: %d" % checked)

	# ---- chain-order feasibility for craft objectives ----
	# Walk the chain and check that a craft objective's recipe is unlocked by a
	# tech the chain has already asked for (or needs none). Otherwise the player
	# is told to make something they cannot yet research.
	var cur := "m001"
	var unlocked := {}
	var steps := 0
	while cur != "" and gd.MISSIONS.has(cur) and steps < 500:
		steps += 1
		var m: Dictionary = gd.MISSIONS[cur]
		var ty := String(m.get("type", ""))
		if ty == "research" or ty == "research_multi":
			var tgt2 = m.get("target", "")
			for t3 in (tgt2 if tgt2 is Array else [tgt2]):
				unlocked[String(t3)] = true
		elif ty == "craft":
			var rid := String(m.get("target", ""))
			if gd.CRAFT.has(rid):
				var req := String((gd.CRAFT[rid] as Dictionary).get("research_req", ""))
				if req != "" and not unlocked.has(req):
					W("mission '%s' asks to craft '%s' but its tech '%s' is not a chain objective yet" % [cur, rid, req])
		cur = String(m.get("next", ""))

	# ---- the chain must TEACH a material before it demands one made of it ----
	# Reachability is NOT the test here. Lithium was always reachable — mine
	# Spodumene, refine it — but no mission mentioned either, so "craft 5 Battery
	# Cells" (5 Li each) landed on a player who had never seen the ore. Raw drops
	# are found on the Gather page unaided; anything that has to be REFINED must be
	# introduced by an earlier objective first.
	# NOT _base_sources here: that counts building yields, and a Lithium Refinery
	# costs 500 Steel and 450k credits — nothing a tutorial player can reach. It is
	# why the first version of this check passed on the broken chain. Only what a
	# player can pick up unaided counts: gather actions and combat drops.
	var raw := {}
	for gid in gd.GATHER:
		for row in (gd.GATHER[gid] as Dictionary).get("loot", []):
			raw[String(row[0])] = true
	for eid in gd.ENEMIES:
		for key in ["loot", "rare_loot"]:
			for row in (gd.ENEMIES[eid] as Dictionary).get(key, []):
				raw[String(row[0])] = true
	var taught := {}
	for mid in gd.MISSION_ORDER:
		var m3: Dictionary = gd.MISSIONS[mid]
		var ty3 := String(m3.get("type", ""))
		var tgt3 = m3.get("target", "")
		# What this objective forces the player to produce.
		var wanted: Array = []
		if ty3 == "gather":
			wanted.append(String(tgt3))
		elif ty3 == "gather_multi" and tgt3 is Dictionary:
			for sym in tgt3:
				wanted.append(String(sym))
		elif ty3 == "craft":
			wanted.append(String(tgt3))
		for w2 in wanted:
			# The inputs the player must already command to make this.
			var inputs := {}
			if gd.MODULES.has(w2):
				for c in (gd.MODULES[w2] as Dictionary).get("cost", {}):
					if String(c) != "credits":
						inputs[String(c)] = true
			else:
				for rid in gd.CRAFT:
					if not (gd.CRAFT[rid] as Dictionary).get("outputs", {}).has(w2):
						continue
					for i in (gd.CRAFT[rid] as Dictionary).get("inputs", {}):
						inputs[String(i)] = true
					break
			for i in inputs:
				var sym2 := String(i)
				if raw.has(sym2) or taught.has(sym2) or sym2 == "credits":
					continue
				# Taught LATER is an ordering bug — the chain knows the material
				# matters and introduces it in the wrong place. Taught nowhere is
				# an inherited gap: desktop's own chain never covers these either,
				# so it is flagged for a content call rather than failed on.
				var later := _taught_at(gd, sym2, mid)
				if later != "":
					E("mission '%s' (%s) needs %s to make %s, but the chain does not introduce %s until '%s'"
						% [mid, String(m3.get("name", "")), gd.res_name(sym2), gd.res_name(w2),
							gd.res_name(sym2), later])
				else:
					W("mission '%s' needs %s to make %s and nothing in the chain introduces it (inherited from desktop)"
						% [mid, gd.res_name(sym2), gd.res_name(w2)])
			taught[w2] = true
		# A research objective teaches whatever its recipes unlock by name only —
		# not a material — so nothing is marked here.
	print("chain material flow: %d objectives walked, %d materials introduced"
		% [gd.MISSION_ORDER.size(), taught.size()])

	# ---- report ----
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
	print("CRAFT_MISSION_AUDIT: %s" % ("FAIL" if not errs.is_empty() else "PASS"))
	quit()
