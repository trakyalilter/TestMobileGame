extends SceneTree
## Audit of infrastructure: the building tables, the energy grid, and the
## production graph they form.
##
## The failure this is built around has now bitten three times in this codebase
## (crew_quarters, applied_physics, biosphere_dome): the ENGINE names a content
## id that the DATA no longer has. Nothing errors — the bonus simply never
## applies, and a "+10% XP per Crew Quarters" line sits in the code forever
## describing a building nobody can build. Both directions are checked here:
## engine ids missing from data, and data effects the engine never reads.

var errs: Array = []
var warns: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s: String) -> void: errs.append(s)
func W(s: String) -> void: warns.append(s)

func _run() -> void:
	var gs = root.get_node("GameState")
	var gd = root.get_node("GameData")
	print("buildings=%d" % gd.BUILDINGS.size())

	var src := ""
	for path in ["res://scripts/core/game_state.gd", "res://scripts/ui/main.gd"]:
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			src += f.get_as_text()
			f.close()
	if src == "":
		E("could not read engine source — the cross-reference checks cannot run")

	# ---------- A. engine names a building the data does not have ----------
	# building_count("x") / buildings.get("x") with no matching row means a bonus
	# that can never fire. Regex over the source rather than a hand-kept list,
	# because a hand-kept list is exactly what let the last three through.
	var re := RegEx.new()
	re.compile('(?:building_count|buildings\\.get)\\(\\s*"([a-z0-9_]+)"')
	var named := {}
	for m in re.search_all(src):
		named[m.get_string(1)] = true
	for bid in named:
		if not gd.BUILDINGS.has(String(bid)):
			E("engine reads building '%s' but no such building exists — the bonus can never apply" % bid)
	print("building ids referenced in engine code: %d" % named.size())

	# ---------- B. data declares an effect the engine never reads ----------
	# A `special` is only real if the engine matches the STRING or hardcodes the
	# building's id. Either is fine; neither means a building that lies.
	var specials := {}
	for bid in gd.BUILDINGS:
		var sp := String((gd.BUILDINGS[bid] as Dictionary).get("special", ""))
		if sp == "":
			continue
		specials[sp] = true
		var by_string: bool = src.find('"%s"' % sp) >= 0
		var by_id: bool = named.has(String(bid))
		if not by_string and not by_id:
			E("building '%s' declares special '%s' that the engine never reads — it does nothing" % [bid, sp])
	print("distinct building specials: %s" % str(specials.keys()))

	# ---------- C. the grid must be able to start ----------
	# Every consumer needs power. If nothing generates without first consuming,
	# the grid can never bootstrap.
	var free_gen := 0
	var fuel_gen := 0
	for bid in gd.BUILDINGS:
		var b: Dictionary = gd.BUILDINGS[bid]
		if float(b.get("energy_gen", 0.0)) <= 0.0:
			continue
		if (b.get("input", {}) as Dictionary).is_empty():
			free_gen += 1
		else:
			fuel_gen += 1
	if free_gen == 0:
		E("no building generates energy without fuel — the grid can never bootstrap")
	print("generators: %d input-free, %d fuel-burning" % [free_gen, fuel_gen])

	# ---------- D. everything a building needs must be obtainable ----------
	var obtainable := {}
	for gid in gd.GATHER:
		for row in (gd.GATHER[gid] as Dictionary).get("loot", []):
			obtainable[String(row[0])] = true
	for eid in gd.ENEMIES:
		var en: Dictionary = gd.ENEMIES[eid]
		for key in ["loot", "rare_loot"]:
			for row in en.get(key, []):
				obtainable[String(row[0])] = true
		# Boss cores are granted from the `boss_core` FIELD on a kill, not from a
		# loot row — miss this and every core-gated cost reads as unobtainable.
		var core := String(en.get("boss_core", ""))
		if core != "":
			obtainable[core] = true
	for bid in gd.BUILDINGS:
		for sym in (gd.BUILDINGS[bid] as Dictionary).get("yield", {}):
			obtainable[String(sym)] = true
	var grew := true
	var guard := 0
	while grew and guard < 40:
		grew = false
		guard += 1
		for rid in gd.CRAFT:
			var r: Dictionary = gd.CRAFT[rid]
			var ok := true
			for sym in r.get("inputs", {}):
				if String(sym) != "credits" and not obtainable.has(String(sym)):
					ok = false
					break
			if not ok:
				continue
			for sym in r.get("outputs", {}):
				if not obtainable.has(String(sym)):
					obtainable[String(sym)] = true
					grew = true
			for row in r.get("bonus", []):
				if not obtainable.has(String(row[0])):
					obtainable[String(row[0])] = true
					grew = true
	for bid in gd.BUILDINGS:
		var b: Dictionary = gd.BUILDINGS[bid]
		for key in ["cost", "input"]:
			for sym in b.get(key, {}):
				if String(sym) == "credits":
					continue
				if not obtainable.has(String(sym)):
					E("building '%s' needs '%s' as %s, which nothing can produce" % [bid, sym, key])

	# ---------- E. production loops between buildings ----------
	# Same shape as the crafting loop sweep. Infrastructure yields carry the warp
	# production multiplier, the building-yield research and the Omega capstone,
	# while INPUTS carry none of them — so a lossy-looking pair still flips once
	# the multiplier climbs. Warp scales without a hard ceiling, so any loop here
	# eventually prints; the threshold is what matters.
	var edges := {}
	for bid in gd.BUILDINGS:
		var b: Dictionary = gd.BUILDINGS[bid]
		for a in b.get("input", {}):
			for c in b.get("yield", {}):
				if String(a) == String(c):
					continue
				if not edges.has(String(a)):
					edges[String(a)] = []
				edges[String(a)].append({
					"bid": bid, "to": String(c),
					"in_qty": float(b["input"][a]), "out_qty": float(b["yield"][c]),
				})
	var pairs := {}
	var cycles := 0
	for start in edges:
		for e1 in edges[start]:
			for e2 in edges.get(String(e1["to"]), []):
				if String(e2["to"]) != String(start):
					continue
				var mid := String(e1["to"])
				var key: String = start + "|" + mid if start < mid else mid + "|" + start
				if pairs.has(key):
					continue
				pairs[key] = true
				cycles += 1
				var gain: float = float(e1["out_qty"]) * float(e2["out_qty"])
				var cost: float = float(e1["in_qty"]) * float(e2["in_qty"])
				if gain <= 0.0:
					continue
				var mult_needed: float = sqrt(cost / gain)
				if mult_needed <= 1.0:
					E("building loop prints material with NO multiplier: %s <-> %s (%s, %s)"
						% [start, mid, e1["bid"], e2["bid"]])
				else:
					W("[loop] %s <-> %s (%s, %s) turns net-positive at yield multiplier x%.2f"
						% [start, mid, e1["bid"], e2["bid"], mult_needed])
	print("building 2-cycles examined: %d" % cycles)

	# ---------- F. buildings that do nothing ----------
	for bid in gd.BUILDINGS:
		var b: Dictionary = gd.BUILDINGS[bid]
		var does_something: bool = not (b.get("yield", {}) as Dictionary).is_empty() \
			or float(b.get("energy_gen", 0.0)) > 0.0 \
			or not (b.get("yield_bonus", {}) as Dictionary).is_empty() \
			or String(b.get("special", "")) != ""
		if not does_something:
			W("building '%s' produces nothing, generates nothing and buffs nothing" % bid)

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
	print("INFRA_AUDIT: %s" % ("FAIL" if not errs.is_empty() else "PASS"))
	quit()
