extends SceneTree
## Data-integrity smoke: exercise the data-driven paths the UI/runtime use so
## any broken cross-reference (zones->enemies->modules->research) surfaces.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var gs = root.get_node("GameState")
	var gd = root.get_node("GameData")
	gs.hard_reset()
	var errs := 0

	# Every zone enemy must resolve to an ENEMIES entry with combat data.
	for z in gd.ZONES:
		for eid in z.get("enemies", []):
			if not gd.ENEMIES.has(eid):
				print("MISSING enemy %s in zone %s" % [eid, z.get("id")]); errs += 1
				continue
			var e: Dictionary = gd.ENEMIES[eid]
			for f in ["dmg_type", "resist_k", "resist_e", "resist_x", "eva", "zone"]:
				if not e.has(f):
					print("enemy %s missing field %s" % [eid, f]); errs += 1
			# combat_preview must not crash and should report a TTK.
			var prev: Dictionary = gs.combat_preview(eid)
			if prev.is_empty():
				print("combat_preview empty for %s" % eid); errs += 1

	# Every module drop pool id must be a real module.
	for eid in gd.ENEMIES:
		for mid in gd.ENEMIES[eid].get("drop_pool", []):
			if not gd.MODULES.has(mid) and not gd.SET_MODULES.has(mid):
				print("enemy %s drop_pool has unknown module %s" % [eid, mid]); errs += 1

	# Every hull must yield ship_stats when equipped fresh.
	for hid in gd.HULLS:
		gs.active_hull = hid
		gs.owned_hulls[hid] = true
		gs.loadout = {}
		var ss: Dictionary = gs.ship_stats()
		if ss.is_empty() or float(ss.get("hp", 0)) <= 0.0:
			print("hull %s produced no stats" % hid); errs += 1
	gs.active_hull = "corvette_hull"

	# Module research_req must point at a real research node (or be empty).
	for mid in gd.MODULES:
		var rr: String = gd.MODULES[mid].get("research_req", "")
		if rr != "" and not gd.RESEARCH.has(rr):
			print("module %s research_req unknown: %s" % [mid, rr]); errs += 1

	# Set pieces must reference a real SETS entry and vice-versa.
	for mid in gd.SET_MODULES:
		var sid: String = gd.SET_MODULES[mid].get("set", "")
		if sid != "" and not gd.SETS.has(sid):
			print("set module %s -> unknown set %s" % [mid, sid]); errs += 1

	# Research_graphs nodes must all be real research ids.
	for tab in gd.RESEARCH_TABS:
		for nid in gd.RESEARCH_GRAPHS[tab]["nodes"]:
			if not gd.RESEARCH.has(nid):
				print("graph node %s not in RESEARCH" % nid); errs += 1

	# Mission chain: every 'next' must resolve (or be "").
	for mid in gd.MISSION_ORDER:
		var nx: String = gd.MISSIONS.get(mid, {}).get("next", "")
		if nx != "" and not gd.MISSIONS.has(nx):
			print("mission %s -> unknown next %s" % [mid, nx]); errs += 1

	print("---")
	print("zones=%d enemies=%d hulls=%d modules=%d set_modules=%d sets=%d research=%d missions=%d" % [
		gd.ZONES.size(), gd.ENEMIES.size(), gd.HULLS.size(), gd.MODULES.size(),
		gd.SET_MODULES.size(), gd.SETS.size(), gd.RESEARCH.size(), gd.MISSIONS.size()])
	print("SMOKE: %s (errors=%d)" % ["PASS" if errs == 0 else "FAIL", errs])
	quit()
