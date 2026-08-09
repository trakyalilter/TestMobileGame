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

	print("[ONB] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


# ---- 5. NOT CHECKED: "no beat may need a material no earlier beat introduced"
#
# Attempted and removed. It could not be made to fail, through four revisions,
# and a check that cannot fail is worse than no check — it reads as coverage.
# The premise is broken by the game itself: the starter kit already grants C, Cu,
# Li, Malachite, Spodumene AND Wood — every material the industrial block later
# teaches the player to mine — so "has the chain taught you to get this yet" has
# no clean answer. Seed the reachable set from the kit and everything is
# reachable from beat zero; seed it empty and you are asserting a fiction, since
# the player really does hold those materials.
#
# Worth revisiting only if the starter kit is trimmed to the raws the opening
# actually uses (Dirt/Water/Fe/Si). Then the ordering rule becomes testable and
# this is the check to write.

func _fail(msg: String) -> void:
	print("[ONB] FAIL: %s" % msg)
	fails += 1
