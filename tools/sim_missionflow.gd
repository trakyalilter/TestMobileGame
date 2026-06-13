extends SceneTree
## Verifier for the curated mobile mission chain (flow pass) + research_multi type.
## Run: xvfb-run -a Godot --headless --path . -s tools/sim_missionflow.gd

var fail := false

func _init() -> void:
	call_deferred("_run")

func p(label: String, ok: bool, extra: String = "") -> void:
	if not ok:
		fail = true
	print(("PASS" if ok else "FAIL"), " | ", label, ("  " + extra) if extra != "" else "")

# Tech prereqs (parent + req_tech) for a research/research_multi target.
func _prereqs(tid: String) -> Array:
	var t: Dictionary = GameData.RESEARCH.get(tid, {})
	var out := []
	var parent: String = t.get("parent", "")
	if parent != "":
		out.append(parent)
	for rt in t.get("req_tech", []):
		if String(rt) != "":
			out.append(String(rt))
	return out

func _run() -> void:
	await create_timer(0.4).timeout
	var gs = get_root().get_node("GameState")
	print("===== MISSIONFLOW VERIFICATION =====")

	# ---- 2. CHAIN INTEGRITY ----
	var order: Array = GameData.MISSION_ORDER
	p("(2a) MISSION_ORDER non-empty", not order.is_empty(), "len=%d" % order.size())
	# Walk next from order[0]; no cycles, every next resolves, ends cleanly.
	var cur: String = order[0]
	var seen := {}
	var walk := []
	var cycle := false
	var bad_next := ""
	while cur != "":
		if seen.has(cur):
			cycle = true; break
		if not GameData.MISSIONS.has(cur):
			bad_next = cur; break
		seen[cur] = true
		walk.append(cur)
		cur = GameData.MISSIONS[cur].get("next", "")
	p("(2b) chain walk: no cycle, all next resolve, ends cleanly",
		not cycle and bad_next == "" and cur == "", "walked=%d" % walk.size())
	p("(2c) walk == MISSION_ORDER", walk == order)

	# Every mission target exists in the right table.
	var bad_targets := []
	for mid in order:
		var m: Dictionary = GameData.MISSIONS[mid]
		var t: String = m.get("type", "")
		var tgt = m.get("target", "")
		match t:
			"research":
				if not GameData.RESEARCH.has(str(tgt)): bad_targets.append("%s:%s" % [mid, tgt])
			"research_multi":
				for tid in tgt:
					if not GameData.RESEARCH.has(String(tid)): bad_targets.append("%s:%s" % [mid, tid])
			"gather":
				if not GameData.RESOURCES.has(str(tgt)): bad_targets.append("%s:%s" % [mid, tgt])
			"gather_multi":
				for sym in tgt:
					if not GameData.RESOURCES.has(String(sym)): bad_targets.append("%s:%s" % [mid, sym])
			"craft":
				if not (GameData.MODULES.has(str(tgt)) or GameData.CRAFT.has(str(tgt))):
					bad_targets.append("%s:%s" % [mid, tgt])
			"construct":
				if not GameData.HULLS.has(str(tgt)): bad_targets.append("%s:%s" % [mid, tgt])
			"defeat":
				if not GameData.ENEMIES.has(str(tgt)): bad_targets.append("%s:%s" % [mid, tgt])
	p("(2d) every mission target resolves to real data", bad_targets.is_empty(), str(bad_targets))

	# ---- 3. DEPENDENCY ORDER ----
	# Simulate completing the chain top-to-bottom. Maintain unlocked-research set.
	# A research/research_multi's tech prereqs must already be unlocked; a
	# gather/craft/construct whose target needs research must come after it.
	var unlocked := {}
	var violations := []
	# Map gather action / craft recipe / module / hull research_req for the target.
	for mid in order:
		var m: Dictionary = GameData.MISSIONS[mid]
		var t: String = m.get("type", "")
		var tgt = m.get("target", "")
		if t == "research":
			for pr in _prereqs(str(tgt)):
				if not unlocked.has(pr):
					violations.append("%s needs %s (prereq of %s)" % [mid, pr, tgt])
			unlocked[str(tgt)] = true
		elif t == "research_multi":
			# Each tech's prereqs must be met by EARLIER missions OR an earlier tech
			# in this same list (the list is unlocked left-to-right).
			for tid in tgt:
				for pr in _prereqs(String(tid)):
					if not unlocked.has(pr):
						violations.append("%s needs %s (prereq of %s)" % [mid, pr, tid])
				unlocked[String(tid)] = true
		elif t == "gather":
			# crafted/refined materials carry a recipe research_req.
			var rr := _craft_req_for_set(str(tgt), unlocked)
			if rr != "":
				violations.append("%s gather %s needs research %s" % [mid, tgt, rr])
		elif t == "gather_multi":
			for sym in tgt:
				var rr2 := _craft_req_for_set(String(sym), unlocked)
				if rr2 != "":
					violations.append("%s gather %s needs research %s" % [mid, sym, rr2])
		elif t == "craft":
			var mr: String = GameData.MODULES.get(str(tgt), {}).get("research_req", "")
			if mr != "" and not unlocked.has(mr):
				violations.append("%s craft %s needs research %s" % [mid, tgt, mr])
		elif t == "construct":
			var hr: String = GameData.HULLS.get(str(tgt), {}).get("research_req", "")
			if hr != "" and not unlocked.has(hr):
				violations.append("%s construct %s needs research %s" % [mid, tgt, hr])
	# PRE-EXISTING desktop gaps the curation deliberately did NOT touch (Chapter-2
	# tail kept verbatim in desktop order): these zone/warp gate techs are never
	# made explicit mission targets in EITHER the desktop or the curated chain — a
	# player crosses them via off-mission research / boss-core drops. The curation's
	# contract is "don't introduce NEW dependency breaks", so we assert the violation
	# set equals exactly this known baseline.
	var KNOWN := [
		"m031 needs zone_5_access (prereq of sector_alpha_decryption)",
		"m032b needs warp_drive (prereq of deep_space_nav)",
		"m032c construct battlecruiser_hull needs research zone_5_access",
		"m033c construct dreadnought_hull needs research zone_8_access",
	]
	var new_violations := []
	for v in violations:
		if not KNOWN.has(v):
			new_violations.append(v)
	p("(3) dependency order: no NEW dependency break introduced by curation",
		new_violations.is_empty(), "new=%s  (pre-existing kept: %d)" % [str(new_violations), violations.size() - new_violations.size()])

	# ---- 4. research_multi behavior + coach ----
	# m002 is the merged Foundational Research (3 techs).
	gs.missions_active.clear(); gs.missions_progress.clear(); gs.missions_claimed.clear()
	gs._mission_completed_seen.clear(); gs.unlocked_research.clear()
	gs.credits = 999999999
	gs.missions_active["m002"] = true
	var m002: Dictionary = GameData.MISSIONS["m002"]
	gs.unlocked_research["basic_engineering"] = true; gs._mission_sync()
	var inc1: bool = not gs.mission_completed("m002")
	gs.unlocked_research["applied_physics"] = true; gs._mission_sync()
	var inc2: bool = not gs.mission_completed("m002")
	gs.unlocked_research["fluid_dynamics"] = true; gs._mission_sync()
	var done3: bool = gs.mission_completed("m002")
	p("(4a) research_multi incomplete until ALL techs unlocked, then completes",
		inc1 and inc2 and done3, "have=%d/%d" % [gs.research_multi_have(m002), int(m002.get("qty",0))])

	# Coach resolution: research page + a REAL node (first not-yet-unlocked).
	gs.unlocked_research.clear()
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main._welcome_done = true
	if main._welcome != null: main._welcome.queue_free(); main._welcome = null
	for n in range(1, gs.SLOT_COUNT + 1): gs.delete_slot(n)
	gs.new_character(1, "Tester")
	if is_instance_valid(main._char_select): main._char_select.queue_free(); main._char_select = null
	for sk in gs.skills: gs.skills[sk] = 99999999
	gs.unlocked_research.clear()
	var rc: Dictionary = main._coach_resolve(m002)
	var first_locked: String = gs.research_multi_first_locked(m002)
	p("(4b) coach research_multi -> Research page + first locked node",
		rc["page"] == "research" and rc["card"] == "basic_engineering" and first_locked == "basic_engineering",
		"page=%s card=%s" % [rc["page"], rc["card"]])
	# Navigate and find the real node card.
	gs.missions_active = {"m002": true}
	main._show("research")
	await process_frame
	await process_frame
	var node = main._coach_find_card(rc["card"])
	p("(4c) coach research_multi node card present on Research page", node != null)
	# After unlocking the first, coach advances to the next locked tech.
	gs.unlocked_research["basic_engineering"] = true
	var rc2: Dictionary = main._coach_resolve(m002)
	p("(4d) coach advances to next locked tech after first unlock",
		rc2["card"] == "applied_physics", "card=%s" % rc2["card"])

	# ---- 5. TUTORIAL GATE ----
	gs.missions_active.clear(); gs.missions_progress.clear(); gs.missions_claimed.clear()
	gs._mission_completed_seen.clear()
	gs._mission_init()
	var fresh_gate: bool = not gs._tutorial_done()
	var goals_hidden: bool = not gs.missions_active.has("goal_001")
	# Find the LAST [TUTORIAL] mission actually on the chain.
	var last_tut := ""
	for mid in order:
		if String(GameData.MISSIONS[mid].get("name", "")).begins_with("[TUTORIAL]"):
			last_tut = mid
	p("(5a) fresh: tutorial NOT done + goals hidden", fresh_gate and goals_hidden, "last_tut=%s" % last_tut)
	# Claim everything up to and including last_tut.
	gs.missions_claimed.clear()
	for mid in order:
		gs.missions_claimed[mid] = true
		if mid == last_tut: break
	var done_after: bool = gs._tutorial_done()
	gs._surface_core_goals()
	var goals_shown: bool = gs.missions_active.has("goal_001")
	p("(5b) after claiming last [TUTORIAL]: tutorial done + goals surface",
		done_after and goals_shown)

	print("===== END MISSIONFLOW =====")
	if fail:
		print("MISSIONFLOW: FAIL"); quit(1)
	print("MISSIONFLOW: PASS"); quit()

# Research req to obtain `sym` GIVEN the already-unlocked set: a material is
# satisfiable if ANY recipe that outputs it is craftable now (ungated, or its
# gate already unlocked). Returns "" if satisfiable, else the cheapest missing
# gate (so the check only flags materials with NO currently-craftable recipe).
func _craft_req_for_set(sym: String, unlocked: Dictionary) -> String:
	var missing := ""
	var any_recipe := false
	for cid in GameData.CRAFT:
		var r: Dictionary = GameData.CRAFT[cid]
		if r.get("outputs", {}).has(sym):
			any_recipe = true
			var rr: String = r.get("research_req", "")
			if rr == "" or unlocked.has(rr):
				return ""   # a craftable-now recipe exists → satisfiable
			missing = rr
	return missing if any_recipe else ""
