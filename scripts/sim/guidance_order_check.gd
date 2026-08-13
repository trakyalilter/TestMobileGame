extends Node
# GUIDANCE FOLLOWS THE CHAIN, NOT THE SOURCE FILE (v175).
#
# The Zone 1 boss moved ahead of the industrial arc. A save that had already run
# the arc under the OLD order then had TWO fronts open at once — the boss ramp
# (m026c, downstream of the claimed m017) and Shipwright I (m026, downstream of
# the claimed m025b) — because _rescue_orphan_chains correctly opens the successor
# of every claimed beat.
#
# Both are legitimately open. The bug was which one owned the guidance, and three
# separate places answered it three different ways, none of them the chain:
#   * mission_manager picked the LAST active beat in DEFINITION order;
#   * research_page centred the FIRST active research beat in DEFINITION order;
#   * main.gd's hint ladder was an elif cascade whose priority was SOURCE-FILE
#     order, so m026 (written at line ~1685) beat m026c (line ~1965).
# The player was steered to research Shipwright I and build the frigate before
# killing the boss the frigate is supposed to come after.
#
# What is checked:
#   1. the chain index is a real topological order (every beat after its
#      predecessor), which is the only property the pickers rely on;
#   2. the reported save state — m017 and m025b claimed, m026 + m026c open —
#      resolves to m026c;
#   3. the hint ladder is keyed on the frontier and not on active_missions
#      membership, so the cascade's ORDER can never decide again;
#   4. every beat the chain can reach is either named by the ladder or routable
#      by the generic fallback, so nothing goes dark.
#
#   Godot --headless --path <root> res://scenes/guidance_order_check.tscn

var fails: int = 0

func _ready() -> void:
	await get_tree().process_frame
	GameState.set_process(false)
	var mm = GameState.mission_manager

	# ---- 1. the index must respect every next_mission edge -----------------
	var order: Dictionary = mm.get_chain_index()
	var bad_edges: int = 0
	for mid in mm.missions:
		var nxt := str(mm.missions[mid].get("next_mission", ""))
		if nxt == "" or not mm.missions.has(nxt):
			continue
		if int(order.get(mid, 0)) >= int(order.get(nxt, 0)):
			bad_edges += 1
			if bad_edges <= 3:
				_fail("chain index puts %s (%d) at or after its successor %s (%d)" % [
					mid, int(order.get(mid, 0)), nxt, int(order.get(nxt, 0))])
	print("[GUID] chain index: %d beats, %d edge violation(s)" % [order.size(), bad_edges])

	# The specific ordering the owner asked for, read straight off the index.
	for pair in [["m017", "m026c"], ["m026c", "m026e"], ["m026e", "m009"],
			["m009", "m025b"], ["m025b", "m026"], ["m026", "m026b"]]:
		var a := str(pair[0])
		var b := str(pair[1])
		if int(order.get(a, 0)) >= int(order.get(b, 0)):
			_fail("%s must come before %s in the chain, but the index disagrees" % [a, b])
	print("[GUID] boss (m026e @%d) precedes the industrial arc (m009 @%d) and Shipwright I (m026 @%d)" % [
		int(order.get("m026e", -1)), int(order.get("m009", -1)), int(order.get("m026", -1))])

	# ---- 2. the reported save: two fronts open, boss ramp must win ---------
	# Reproduced from the 175-minute save: the whole industrial arc claimed under
	# the old order, m017 claimed, nothing of the boss ramp done.
	var claimed := ["m001", "m002", "m004", "m005", "m005b", "m005c", "m007", "m007b",
		"m009", "m011", "m012", "m013", "m013b", "m013c", "m015", "m015b", "m016",
		"m016c", "m017", "m018", "m018t1", "m018t2", "m019", "m019b", "m019c",
		"m019d", "m019e", "m024", "m024a1", "m024a2", "m024b", "m024b2", "m024c",
		"m025", "m025a", "m025b"]
	for mid2 in mm.missions:
		mm.missions[mid2]["active"] = false
		mm.missions[mid2]["completed"] = false
		mm.missions[mid2]["claimed"] = false
	mm.active_missions.clear()
	for c in claimed:
		if mm.missions.has(c):
			mm.missions[c]["claimed"] = true
			mm.missions[c]["completed"] = true
	mm._rescue_orphan_chains()

	var open: Array = []
	for mid3 in mm.active_missions:
		open.append(str(mid3))
	open.sort()
	var front := str(mm.get_chain_frontier_id())
	print("[GUID] reported save -> open fronts %s, frontier = %s" % [str(open), front])
	if not ("m026" in open and "m026c" in open):
		_fail("could not reproduce the reported fork (expected m026 and m026c open, got %s)" % str(open))
	if front != "m026c":
		_fail("frontier is %s — the boss ramp (m026c) must own the guidance, not the frigate arc" % front)

	# ---- 3. the ladder may not be keyed on membership ----------------------
	# The defect was structural: `elif "m026" in mm.active_missions` reads the same
	# as the frontier test while one beat is open and diverges when two are. If any
	# of those come back, source order silently owns guidance again.
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	var leaked: int = 0
	for line in src.split("\n"):
		var t := str(line).strip_edges()
		if t.begins_with("elif \"m") and t.ends_with("in mm.active_missions:"):
			leaked += 1
	if leaked > 0:
		_fail("%d hint-ladder branch(es) still test active_missions membership — cascade order decides again" % leaked)
	var keyed: int = src.count("elif front == \"m")
	print("[GUID] hint ladder: %d frontier-keyed branch(es), %d membership branch(es)" % [keyed, leaked])
	if keyed < 50:
		_fail("only %d frontier-keyed branches — the ladder conversion looks incomplete" % keyed)

	# ---- 4. no reachable beat may be unroutable ---------------------------
	# A beat with no bespoke branch falls through to _generic_mission_pulse, which
	# routes by mission TYPE. A type it cannot route AND no branch = a dark arrow.
	var routable := ["gather", "gather_multi", "research", "craft", "construct",
		"defeat", "defeat_retreat", "sell", "visit_page", "loadout_check",
		"loadout_rare_weapon", "drop_rarity", "drop_rarity_weapon", "build", "atlas_lookup",
		"hack_apply"]
	var dark: Array = []
	var cur := "m001"
	var steps := 0
	while cur != "" and steps < 80:
		var m: Dictionary = mm.missions.get(cur, {})
		if m.is_empty():
			break
		var has_branch: bool = src.find("elif front == \"%s\"" % cur) >= 0
		if not has_branch and not (str(m.get("type", "")) in routable):
			dark.append("%s (%s)" % [cur, str(m.get("type", ""))])
		cur = str(m.get("next_mission", ""))
		steps += 1
	if dark.size() > 0:
		_fail("%d beat(s) have no ladder branch and an unroutable type: %s" % [dark.size(), ", ".join(dark)])
	print("[GUID] walked %d chain beats, %d with no guidance at all" % [steps, dark.size()])

	print("[GUID] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _fail(msg: String) -> void:
	print("[GUID] FAIL: %s" % msg)
	fails += 1
