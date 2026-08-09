extends Node
# OPENING CHAIN WALKABILITY.
#
# The first four beats are the most fragile in the game: a new player has no
# research, no levels and no stock, so any one of them can be gated behind
# something the previous beat does not provide. v174 reordered them to
# gather-then-research (Dirt -> Water -> Basic Engineering -> Mineral Washing),
# which only works because collect_water's research gate was removed with it.
#
# Walks the chain in its declared order and asserts each beat is reachable with
# only what the beats before it grant.
#
#   Godot --headless --path <root> res://scenes/onboarding_order_check.tscn

const EXPECTED := ["m001", "m004", "m002", "m005"]

var fails: int = 0

func _ready() -> void:
	await get_tree().process_frame
	GameState.set_process(false)
	var mm = GameState.mission_manager
	var gm = GameState.gathering_manager
	var rm = GameState.research_manager

	# ---- 1. the chain runs in the intended order --------------------------
	var walk: Array = []
	var cur := "m001"
	for _i in range(EXPECTED.size()):
		walk.append(cur)
		var m: Dictionary = mm.missions.get(cur, {})
		if m.is_empty():
			_fail("chain breaks: %s is not a mission" % cur)
			break
		cur = String(m.get("next_mission", ""))
		if cur == "":
			break
	print("[ONB] chain: %s" % " -> ".join(walk))
	if walk != EXPECTED:
		_fail("expected %s" % " -> ".join(EXPECTED))

	# ---- 2. the water beat must not need research the player cannot have --
	var water: Dictionary = gm.actions.get("collect_water", {})
	var wreq := String(water.get("research_req", ""))
	if wreq != "":
		_fail("collect_water still gates on '%s', but its mission now runs BEFORE research" % wreq)

	# ---- 3. 350 Dirt must actually reach collect_water's level_req --------
	# Simulate the first beat honestly: gather Dirt until the mission's quota is
	# met, then read the level. Hand-arithmetic on the RS curve is exactly the
	# kind of thing that is wrong when it matters.
	var dirt: Dictionary = gm.actions.get("gather_dirt", {})
	var per: float = 0.0
	for row in dirt.get("loot_table", []):
		per = (float((row as Array)[2]) + float((row as Array)[3])) / 2.0
	var need: float = float(mm.missions.get("m001", {}).get("target_qty", 350))
	var runs: int = int(ceil(need / maxf(1.0, per)))
	var xp_each: float = float(dirt.get("xp", 0))
	gm.xp = 0.0
	gm.rebuild_level_silently()
	for _r in range(runs):
		gm.add_xp(xp_each)
	var lvl: int = gm.level
	var want_lvl: int = int(water.get("level_req", 1))
	print("[ONB] m001 = %.0f Dirt ~= %d actions x %.0f xp -> gathering level %d (collect_water needs %d)" % [
		need, runs, xp_each, lvl, want_lvl])
	if lvl < want_lvl:
		_fail("350 Dirt leaves the player at level %d but Pump Water needs %d" % [lvl, want_lvl])

	# ---- 4. the research beat must still gate what PROCESSES the raws -----
	# Removing the gathering gate must not have opened the refinery early.
	var pm = GameState.processing_manager
	var cent := String((pm.recipes.get("centrifuge_dirt", {}) as Dictionary).get("research_req", ""))
	if cent != "basic_engineering":
		_fail("centrifuge_dirt gates on '%s' — processing should still need the research" % cent)
	print("[ONB] centrifuge_dirt still gates on '%s'" % cent)

	_check_material_order(mm, GameState.shipyard_manager, pm)

	print("[ONB] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


# ---- 5. no beat may need a material no earlier beat introduced ----------
# The ordering rule: a beat must never demand something the chain has not yet
# taught you to obtain. Carries a REACHABLE set seeded from the actual starter
# kit, grown by each gather beat, and expanded to a fixed point through any
# recipe whose inputs are already reachable.
#
# I removed this once, believing the starter kit granted the six industrial
# materials and made everything reachable from beat zero. It does not — that was
# the live dev save read by mistake. A fresh game starts with Dirt/Water/Fe/Si,
# so the rule is testable after all.
func _check_material_order(mm, sm, pm) -> void:
	var res_script = load("res://scripts/core/resources.gd")
	var fresh = res_script.new()
	fresh.seed_starter_kit()
	var have: Dictionary = {}
	for sym in fresh.elements:
		have[str(sym)] = true
	var seed_list: Array = have.keys()
	_expand(have, pm)

	var cur := "m001"
	var n := 0
	while cur != "" and n < 45:
		var m: Dictionary = mm.missions.get(cur, {})
		if m.is_empty():
			break
		var t := str(m.get("type", ""))
		var wants: Array = []
		if t == "gather":
			wants.append(str(m.get("target", "")))
		elif t == "gather_multi":
			for k in (m.get("target", {}) as Dictionary):
				wants.append(str(k))
		elif t == "craft" or t == "construct":
			var mid := str(m.get("target", ""))
			var cost: Dictionary = {}
			if mid in sm.modules:
				cost = sm.modules[mid].get("cost", {})
			elif mid in sm.hulls:
				cost = sm.hulls[mid].get("cost", {})
			for k2 in cost:
				wants.append(str(k2))

		# check BEFORE teaching, or a beat validates itself
		for w in wants:
			if str(w) == "credits" or have.has(w):
				continue
			if _gatherable(w):
				continue      # this beat legitimately teaches you to mine it
			_fail("%s (%s) needs %s — no earlier beat provides it" % [
				cur, str(m.get("target", "")).substr(0, 20), w])
		for w2 in wants:
			have[w2] = true
		_expand(have, pm)
		cur = str(m.get("next_mission", ""))
		n += 1
	print("[ONB] material order: seed %s -> %d reachable across %d beats" % [
		str(seed_list), have.size(), n])


func _gatherable(sym: String) -> bool:
	for aid in GameState.gathering_manager.actions:
		for row in GameState.gathering_manager.actions[aid].get("loot_table", []):
			if String((row as Array)[0]) == sym:
				return true
	return false


# Grow the reachable set to a fixed point.
func _expand(have: Dictionary, pm) -> void:
	var changed := true
	while changed:
		changed = false
		for rid in pm.recipes:
			var r: Dictionary = pm.recipes[rid]
			var ok := true
			for k in r.get("input", {}):
				if not have.has(String(k)):
					ok = false
					break
			if not ok:
				continue
			for o in r.get("output", {}):
				if not have.has(String(o)):
					have[String(o)] = true
					changed = true

func _fail(msg: String) -> void:
	print("[ONB] FAIL: %s" % msg)
	fails += 1
