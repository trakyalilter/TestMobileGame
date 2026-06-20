extends SceneTree
## PHASE 1 — Data integrity. Every id referenced anywhere in GameData must resolve:
## recipe/building/hull/module/research/gather inputs-outputs-costs -> real
## resources; research_req/parent/req_tech -> real tech; enemy loot/drop_pool ->
## real resource/module; zone enemies -> real enemies; sets <-> set-modules <->
## trinity; research-graph nodes -> real techs; mission targets; and no raw-id
## name leaks. Fails on any dangling reference.

var gd
var errors: Array = []
var warns: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s): errors.append(s)
func W(s): warns.append(s)
func is_res(s) -> bool: return s == "credits" or gd.RESOURCES.has(s)
func is_mod(s) -> bool: return gd.MODULES.has(s) or gd.SET_MODULES.has(s)
func is_tech(s) -> bool: return gd.RESEARCH.has(s)

func _chk_research_req(owner: String, d: Dictionary) -> void:
	var rr = d.get("research_req", "")
	if rr != null and rr != "" and not is_tech(rr):
		E("%s research_req '%s' is not a real tech" % [owner, rr])

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	gd = root.get_node("GameData")

	# --- CRAFT recipes ---
	for cid in gd.CRAFT:
		var r: Dictionary = gd.CRAFT[cid]
		for sym in r.get("inputs", {}):
			if not is_res(sym): E("CRAFT %s input '%s' not a resource" % [cid, sym])
		for sym in r.get("outputs", {}):
			if not gd.RESOURCES.has(sym): E("CRAFT %s output '%s' not a resource" % [cid, sym])
		for row in r.get("bonus", []):
			if not gd.RESOURCES.has(row[0]): E("CRAFT %s bonus '%s' not a resource" % [cid, row[0]])
		_chk_research_req("CRAFT %s" % cid, r)

	# --- GATHER ---
	for gid in gd.GATHER:
		var a: Dictionary = gd.GATHER[gid]
		for row in a.get("loot", []):
			if not gd.RESOURCES.has(row[0]): E("GATHER %s loot '%s' not a resource" % [gid, row[0]])
		_chk_research_req("GATHER %s" % gid, a)

	# --- BUILDINGS ---
	for bid in gd.BUILDINGS:
		var b: Dictionary = gd.BUILDINGS[bid]
		for sym in b.get("cost", {}):
			if not is_res(sym): E("BUILDING %s cost '%s' not a resource" % [bid, sym])
		for sym in b.get("yield", {}):
			if not gd.RESOURCES.has(sym): E("BUILDING %s yield '%s' not a resource" % [bid, sym])
		for sym in b.get("input", {}):
			if not gd.RESOURCES.has(sym): E("BUILDING %s input '%s' not a resource" % [bid, sym])
		_chk_research_req("BUILDING %s" % bid, b)

	# --- HULLS ---
	for hid in gd.HULLS:
		var h: Dictionary = gd.HULLS[hid]
		for sym in h.get("cost", {}):
			if not is_res(sym): E("HULL %s cost '%s' not a resource" % [hid, sym])
		if (h.get("slots", []) as Array).is_empty(): W("HULL %s has no slots" % hid)
		_chk_research_req("HULL %s" % hid, h)

	# --- MODULES + SET_MODULES ---
	for mid in gd.MODULES:
		var m: Dictionary = gd.MODULES[mid]
		for sym in m.get("cost", {}):
			if not is_res(sym): E("MODULE %s cost '%s' not a resource" % [mid, sym])
		if String(m.get("slot", "")) == "": W("MODULE %s has no slot" % mid)
		_chk_research_req("MODULE %s" % mid, m)
	for sid in gd.SET_MODULES:
		var sm: Dictionary = gd.SET_MODULES[sid]
		var setn = sm.get("set", "")
		if setn != "" and not gd.SETS.has(setn): E("SET_MODULE %s set '%s' not a real set" % [sid, setn])
		if String(sm.get("slot", "")) == "": W("SET_MODULE %s has no slot" % sid)

	# --- RESEARCH internal ---
	for tid in gd.RESEARCH:
		var t: Dictionary = gd.RESEARCH[tid]
		var par = t.get("parent", "")
		if par != null and par != "" and not is_tech(par):
			E("RESEARCH %s parent '%s' not a real tech" % [tid, par])
		for sym in t.get("items", {}):
			if not gd.RESOURCES.has(sym): E("RESEARCH %s item '%s' not a resource" % [tid, sym])
		var rq = t.get("req_tech", [])
		if rq is Array:
			for x in rq:
				if not is_tech(x): E("RESEARCH %s req_tech '%s' not a real tech" % [tid, x])
		elif rq is String and rq != "" and not is_tech(rq):
			E("RESEARCH %s req_tech '%s' not a real tech" % [tid, rq])

	# --- ENEMIES ---
	for eid in gd.ENEMIES:
		var e: Dictionary = gd.ENEMIES[eid]
		for row in e.get("loot", []):
			if not (is_res(row[0]) or is_mod(row[0])):
				E("ENEMY %s loot '%s' not a resource or module" % [eid, row[0]])
		for dm in e.get("drop_pool", []):
			if not gd.MODULES.has(dm): E("ENEMY %s drop_pool '%s' not a real module" % [eid, dm])
		var bc = e.get("boss_core", "")
		if bc != "" and not gd.RESOURCES.has(bc): E("ENEMY %s boss_core '%s' not a resource" % [eid, bc])

	# --- ZONES ---
	for z in gd.ZONES:
		for eid in z.get("enemies", []):
			if not gd.ENEMIES.has(eid): E("ZONE %s enemy '%s' not a real enemy" % [z.get("name",""), eid])
		var rr = z.get("research_req", "")
		if rr != "" and not is_tech(rr): E("ZONE %s research_req '%s' not a tech" % [z.get("name",""), rr])

	# --- SETS / TRINITY ---
	for setn in gd.SETS:
		var sd: Dictionary = gd.SETS[setn]
		for p in sd.get("pieces", []):
			if not gd.SET_MODULES.has(p): E("SET %s piece '%s' not a set-module" % [setn, p])
		var boss = sd.get("boss", "")
		if boss != "" and not gd.ENEMIES.has(boss): E("SET %s boss '%s' not a real enemy" % [setn, boss])
	for setn in gd.TRINITY_SET_BONUSES:
		if not gd.SETS.has(setn): E("TRINITY_SET_BONUSES key '%s' not a real set" % setn)

	# --- RESEARCH_GRAPHS ---
	for tab in gd.RESEARCH_GRAPHS:
		var g: Dictionary = gd.RESEARCH_GRAPHS[tab]
		for nid in g.get("nodes", []):
			if not gd.RESEARCH.has(nid): E("RESEARCH_GRAPHS[%s] node '%s' not a real tech" % [tab, nid])
			elif not g.get("pos", {}).has(nid): E("RESEARCH_GRAPHS[%s] node '%s' has no position" % [tab, nid])

	# --- MISSIONS (target sanity) ---
	for mid in gd.MISSIONS:
		var m: Dictionary = gd.MISSIONS[mid]
		var ty: String = m.get("type", "")
		var tg = m.get("target", "")
		match ty:
			"defeat":
				if not gd.ENEMIES.has(tg): E("MISSION %s defeat enemy '%s' missing" % [mid, tg])
			"research":
				if not is_tech(tg): E("MISSION %s research tech '%s' missing" % [mid, tg])
			"research_multi":
				if tg is Array:
					for x in tg:
						if not is_tech(x): E("MISSION %s research_multi tech '%s' missing" % [mid, x])
			"construct":
				if not gd.HULLS.has(tg): E("MISSION %s construct hull '%s' missing" % [mid, tg])
			"craft":
				if not is_mod(tg): E("MISSION %s craft module '%s' missing" % [mid, tg])

	# --- Name-leak guard: every module/set id referenced in enemy loot/drop must
	# resolve to a real name (item_name != the raw id). ---
	for eid in gd.ENEMIES:
		for row in gd.ENEMIES[eid].get("loot", []):
			var s = row[0]
			if is_mod(s) and gd.item_name(s) == s:
				E("ENEMY %s loot module '%s' has no display name (raw-id leak)" % [eid, s])
		for dm in gd.ENEMIES[eid].get("drop_pool", []):
			if gd.item_name(dm) == dm:
				E("ENEMY %s drop_pool '%s' has no display name" % [eid, dm])

	# --- Report ---
	print("\n===== PHASE 1: DATA INTEGRITY =====")
	print("resources=%d gather=%d craft=%d research=%d enemies=%d zones=%d modules=%d set_modules=%d sets=%d buildings=%d hulls=%d" % [
		gd.RESOURCES.size(), gd.GATHER.size(), gd.CRAFT.size(), gd.RESEARCH.size(), gd.ENEMIES.size(),
		gd.ZONES.size(), gd.MODULES.size(), gd.SET_MODULES.size(), gd.SETS.size(), gd.BUILDINGS.size(), gd.HULLS.size()])
	print("errors=%d  warnings=%d" % [errors.size(), warns.size()])
	if not warns.is_empty():
		print("\n--- WARNINGS ---")
		for w in warns: print("  ⚠ " + w)
	if not errors.is_empty():
		print("\n--- ERRORS ---")
		for e in errors: print("  ✗ " + e)
		print("\nDATA_INTEGRITY: FAIL")
		quit(1)
	print("\nDATA_INTEGRITY: PASS")
	quit()
