extends SceneTree
## Audit of the shipyard: hulls, modules, sets and the ids the engine names.
##
## The engine-names-missing-content class needs a distinction here that it did
## not need for buildings. Reading a missing module is HARMLESS —
## loadout_has_module("x") simply returns false and a dormant hook does nothing,
## which is how six unique modules sit dead in desktop's own combat manager.
## GRANTING a missing module is not: it writes an inventory entry with no
## definition, so the item has no name, no slot, and can never be equipped.
## Those two cases are graded differently.

var errs: Array = []
var warns: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s: String) -> void: errs.append(s)
func W(s: String) -> void: warns.append(s)

func _run() -> void:
	var gs = root.get_node("GameState")
	var gd = root.get_node("GameData")
	print("hulls=%d  modules=%d  set_modules=%d  sets=%d"
		% [gd.HULLS.size(), gd.MODULES.size(), gd.SET_MODULES.size(), gd.SETS.size()])

	var src := ""
	for path in ["res://scripts/core/game_state.gd", "res://scripts/ui/main.gd"]:
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			src += f.get_as_text()
			f.close()
	if src == "":
		E("could not read engine source — cross-reference checks cannot run")

	# ---------- A. modules the engine GRANTS must exist ----------
	# A write into module_inventory creates a real item; if the id has no
	# definition the player gets a nameless, slotless, unequippable entry.
	var re_grant := RegEx.new()
	re_grant.compile('module_inventory\\[\\s*"([a-z0-9_]+)"\\s*\\]')
	var granted := {}
	for m in re_grant.search_all(src):
		granted[m.get_string(1)] = true
	for mid in granted:
		if not gd.MODULES.has(String(mid)) and not gd.SET_MODULES.has(String(mid)):
			E("engine GRANTS module '%s' which has no definition — the player receives a broken item" % mid)
	print("module ids granted by engine code: %d" % granted.size())

	# ---------- B. modules the engine only READS ----------
	var re_read := RegEx.new()
	re_read.compile('loadout_has_module\\(\\s*"([a-z0-9_]+)"')
	var read_ids := {}
	for m in re_read.search_all(src):
		read_ids[m.get_string(1)] = true
	var dormant := 0
	for mid in read_ids:
		if not gd.MODULES.has(String(mid)) and not gd.SET_MODULES.has(String(mid)):
			dormant += 1
			W("[dormant] engine hook reads module '%s' which has no definition — inert, matching desktop" % mid)
	print("module ids read by engine code: %d (%d dormant)" % [read_ids.size(), dormant])

	# ---------- C. slots must be real ----------
	var hull_slots := {}
	for hid in gd.HULLS:
		for s in (gd.HULLS[hid] as Dictionary).get("slots", []):
			hull_slots[String(s)] = true
	hull_slots["aux"] = true          # granted by the CMB_3 warp node
	hull_slots["gem"] = true          # cores route through sockets, not slots
	hull_slots["gem_synth"] = true
	for mid in gd.MODULES:
		var slot := String((gd.MODULES[mid] as Dictionary).get("slot", ""))
		if slot == "":
			E("module '%s' has no slot — it can never be equipped" % mid)
		elif slot == "relic":
			# v113 NG+ P2: desktop gives relics a DEDICATED slot, handled beside
			# gem/gem_synth rather than on the hull. Mobile has no relic slot and
			# never reads the enemy `relic_drop` field, so the item is inert
			# rather than broken — unported content, not malformed data.
			W("[unported] module '%s' needs the NG+ relic slot, which mobile does not implement" % mid)
		elif not hull_slots.has(slot):
			E("module '%s' wants slot '%s' which no hull provides" % [mid, slot])

	# ---------- D. set pieces and their sets ----------
	var pieces_by_set := {}
	for sid in gd.SET_MODULES:
		var sm: Dictionary = gd.SET_MODULES[sid]
		var setn := String(sm.get("set", ""))
		if setn == "":
			W("set module '%s' declares no set" % sid)
			continue
		if not gd.SETS.has(setn):
			E("set module '%s' belongs to set '%s' which does not exist" % [sid, setn])
			continue
		pieces_by_set[setn] = int(pieces_by_set.get(setn, 0)) + 1
	for setn in gd.SETS:
		var declared: int = (gd.SETS[setn] as Dictionary).get("pieces", []).size()
		var actual := int(pieces_by_set.get(setn, 0))
		if declared > 0 and actual != declared:
			W("set '%s' declares %d pieces but %d modules claim it" % [setn, declared, actual])
		for p in (gd.SETS[setn] as Dictionary).get("pieces", []):
			if not gd.SET_MODULES.has(String(p)) and not gd.MODULES.has(String(p)):
				E("set '%s' lists piece '%s' which does not exist" % [setn, p])

	# ---------- E. costs must be obtainable ----------
	var obtainable := {}
	for gid in gd.GATHER:
		for row in (gd.GATHER[gid] as Dictionary).get("loot", []):
			obtainable[String(row[0])] = true
	for eid in gd.ENEMIES:
		var en: Dictionary = gd.ENEMIES[eid]
		for key in ["loot", "rare_loot"]:
			for row in en.get(key, []):
				obtainable[String(row[0])] = true
		var core := String(en.get("boss_core", ""))
		if core != "":
			obtainable[core] = true
	for bid in gd.BUILDINGS:
		for sym in (gd.BUILDINGS[bid] as Dictionary).get("yield", {}):
			obtainable[String(sym)] = true
	# Matrix cores come from buy_module's gem paths (Matrix Synthesis rolls a
	# Cracked core; fusion promotes three into one), never from a CRAFT recipe —
	# so a purely recipe-driven closure would call every core unobtainable.
	for mid in gd.MODULES:
		var slot0 := String((gd.MODULES[mid] as Dictionary).get("slot", ""))
		if slot0 == "gem":
			for c in ["CrackedAmethystCore", "CrackedCobaltCore", "CrackedCrimsonCore", "CrackedTopazCore"]:
				obtainable[c] = true
		elif slot0 == "gem_synth":
			var out: String = gs._gem_synth_output(String(mid))
			if out != "":
				obtainable[out] = true
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
	var cost_rows := 0
	for tbl_name in ["MODULES", "HULLS"]:
		var tbl: Dictionary = gd.MODULES if tbl_name == "MODULES" else gd.HULLS
		for id in tbl:
			for sym in (tbl[id] as Dictionary).get("cost", {}):
				if String(sym) == "credits":
					continue
				cost_rows += 1
				if not obtainable.has(String(sym)):
					E("%s '%s' costs '%s', which nothing can produce" % [tbl_name, id, sym])
	print("cost entries checked: %d" % cost_rows)

	# ---------- F. a buyable module must actually do something ----------
	for mid in gd.MODULES:
		var m: Dictionary = gd.MODULES[mid]
		var slot := String(m.get("slot", ""))
		if slot == "gem" or slot == "gem_synth" or slot == "relic":
			continue      # recipes and relics carry no stat block by design
		if (m.get("stats", {}) as Dictionary).is_empty():
			W("module '%s' has no stats — equipping it changes nothing" % mid)

	# ---------- G. hull ladder ----------
	var by_tier := {}
	for hid in gd.HULLS:
		var h: Dictionary = gd.HULLS[hid]
		var t := int(h.get("tier", 0))
		var slots: int = (h.get("slots", []) as Array).size()
		if slots <= 0:
			E("hull '%s' has no slots" % hid)
		if by_tier.has(t):
			W("hulls '%s' and '%s' share tier %d" % [by_tier[t], hid, t])
		else:
			by_tier[t] = String(hid)
	var tiers: Array = by_tier.keys()
	tiers.sort()
	var prev_slots := 0
	for t in tiers:
		var slots2: int = ((gd.HULLS[by_tier[t]] as Dictionary).get("slots", []) as Array).size()
		if prev_slots > 0 and slots2 < prev_slots:
			W("[curve] tier %d hull '%s' has fewer slots (%d) than the tier below (%d)"
				% [t, by_tier[t], slots2, prev_slots])
		prev_slots = slots2
	print("hull tiers: %s" % str(tiers))

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
	print("SHIPYARD_AUDIT: %s" % ("FAIL" if not errs.is_empty() else "PASS"))
	quit()
