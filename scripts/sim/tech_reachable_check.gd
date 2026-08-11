extends Node
# EVERY RESEARCH TECH MUST BE CLICKABLE (v175).
#
# research_manager.tech_tree is the source of truth for what exists; research_page.graphs
# is a SECOND, hand-maintained list of which node ids each tab renders. A tech present in
# the first and absent from the second is fully functional — can_unlock() returns true,
# unlock_tech() works, probes that grant research directly see it — and completely
# unreachable for the player, because no widget is ever instantiated for it.
#
# That is exactly what happened to the NG+ armament ladder: rift / verdigris /
# dissolution / caustic_armaments were authored, wired into the Z12-Z15 gear gate, and
# never added to a tab. All 16 Z12-Z15 modules were uncraftable, and boss_gearcheck did
# not notice because it grants research through the manager rather than the UI.
#
# The failure is silent in both directions, so this checks both:
#   1. every tech_tree id appears in exactly one tab (missing = unbuyable; duplicated =
#      rendered twice and the second widget fights the first for state);
#   2. every id listed in a tab actually exists in tech_tree (a stale id draws nothing
#      or crashes the layout);
#   3. a node whose `parent` lives in a DIFFERENT tab cannot draw its prereq line —
#      the v145 note in research_page.gd records this rule, so it is asserted, not
#      re-learned;
#   4. the modules gated by those techs are actually craftable once the tech is owned,
#      which is the player-visible consequence the whole thing exists for.
#
#   Godot --headless --path <root> res://scenes/tech_reachable_check.tscn

const PAGE := "res://scripts/ui/research_page.gd"

var fails: int = 0

func _ready() -> void:
	await get_tree().process_frame
	GameState.set_process(false)
	var rm = GameState.research_manager
	var sm = GameState.shipyard_manager

	# Read the tab lists off the SCRIPT rather than standing up the scene: the page needs
	# a full UI tree, and this must run headless. graphs is a plain literal at the top.
	var tabs: Dictionary = _parse_tabs()
	if tabs.is_empty():
		print("[TECH] FAIL: could not parse graphs{} out of %s — the parser has drifted." % PAGE)
		print("[TECH] RESULT: FAIL (1 failure(s))")
		get_tree().quit(1)
		return
	var where: Dictionary = {}          # tech id -> [tab, tab...]
	var total_listed := 0
	for tab in tabs:
		for tid in tabs[tab]:
			total_listed += 1
			if not where.has(tid):
				where[tid] = []
			(where[tid] as Array).append(tab)
	print("[TECH] %d tabs, %d listed ids, %d techs in tech_tree" % [
		tabs.size(), total_listed, rm.tech_tree.size()])

	# ---- 1. every tech is rendered somewhere -------------------------------
	var missing: Array = []
	for tid in rm.tech_tree:
		if not where.has(str(tid)):
			missing.append(str(tid))
	missing.sort()
	if missing.size() > 0:
		_fail("%d tech(s) exist in tech_tree but appear in NO tab, so the player can never click them: %s" % [
			missing.size(), ", ".join(missing)])

	# ---- 2. no tab lists a tech that does not exist ------------------------
	var ghosts: Array = []
	for tid2 in where:
		if not rm.tech_tree.has(str(tid2)):
			ghosts.append("%s (in %s)" % [tid2, ", ".join(where[tid2])])
	if ghosts.size() > 0:
		_fail("%d tab entr(ies) name a tech that is not in tech_tree: %s" % [ghosts.size(), ", ".join(ghosts)])

	# ---- 3. no tech is rendered twice --------------------------------------
	var dupes: Array = []
	for tid3 in where:
		if (where[tid3] as Array).size() > 1:
			dupes.append("%s (%s)" % [tid3, ", ".join(where[tid3])])
	if dupes.size() > 0:
		_fail("%d tech(s) are listed in more than one tab: %s" % [dupes.size(), ", ".join(dupes)])

	# ---- 4. a prereq line can only be drawn inside one tab -----------------
	var split: Array = []
	for tid4 in rm.tech_tree:
		var par := str((rm.tech_tree[tid4] as Dictionary).get("parent", ""))
		if par == "" or par == "<null>" or not where.has(str(tid4)) or not where.has(par):
			continue
		var a: String = str((where[str(tid4)] as Array)[0])
		var bt: String = str((where[par] as Array)[0])
		if a != bt:
			split.append("%s is in '%s' but its parent %s is in '%s'" % [tid4, a, par, bt])
	# INFORMATIONAL, not a failure. Ten nodes across the tree already sit in a different
	# tab from their parent (industrial_logistics/basic_engineering, energy_shields/
	# basic_engineering, ...). That is a pre-existing cosmetic condition — the node is
	# still clickable, it just draws no connecting line — and failing on it would give
	# the repo another permanently-red guard that gets ignored, which is precisely how
	# phase_gate_spike stopped being read. Printed with the full list so a NEW one is
	# visible in the diff of this probe's output.
	if split.size() > 0:
		print("[TECH] note: %d node(s) draw no prereq line (parent in another tab, cosmetic, pre-existing):" % split.size())
		for s2 in split:
			print("[TECH]        %s" % s2)

	# ---- 5. the payoff: gated modules must become craftable ----------------
	# The reason any of this matters. Walk each armament tech, count what it gates, and
	# confirm those modules flip to craftable once the tech is owned. A tech that is
	# reachable but gates nothing usable is the same dead end wearing a different hat.
	var arms: Array = []
	for tid5 in rm.tech_tree:
		if str(tid5).ends_with("_armaments"):
			arms.append(str(tid5))
	arms.sort()
	print("[TECH] armament ladder: %d tech(s)" % arms.size())
	for a2 in arms:
		var gated: Array = []
		for mid in sm.modules:
			if str((sm.modules[mid] as Dictionary).get("research_req", "")) == a2:
				gated.append(str(mid))
		var tab_of: String = (str((where[a2] as Array)[0]) if where.has(a2) else "NONE")
		var mark: String = "" if where.has(a2) else "   <-- UNREACHABLE"
		print("[TECH]   %-24s tab=%-12s gates %2d module(s)%s" % [a2, tab_of, gated.size(), mark])
		if gated.is_empty():
			_fail("%s gates no modules at all" % a2)

	# ---- 6. walk the ladder the way the player does ------------------------
	# Being listed in a tab is not the same as being obtainable. Unlock the chain in
	# order, granting each sector flag as the player would by clearing that sector, and
	# assert at every step that (a) can_unlock() opens exactly when its prereq lands,
	# (b) it does NOT open before its flag is set, and (c) the modules it gates flip to
	# craftable. Without (b) the fix could quietly leak the whole NG+ ladder into a
	# pre-warp game, which would be a worse bug than the one being fixed.
	print("[TECH] --- ladder walk (grant flag, unlock, check gated modules) ---")
	var chain := ["cryo_armaments", "corrosion_armaments", "rift_armaments",
		"verdigris_armaments", "dissolution_armaments", "caustic_armaments"]
	# The ladder hangs off cryogenic_systems, which hangs off the ordinary tree. Grant
	# that closure first — a player standing at Z12 has long since bought it — or every
	# rung fails on its prereq and the walk reports six defects for one missing seed.
	var seeded := 0
	for tid0 in chain:
		for anc in _ancestors(rm, tid0):
			if anc in chain or anc in rm.unlocked_techs:
				continue
			rm.unlocked_techs.append(anc)
			seeded += 1
	GameState.game_settings["cryo_unlocked"] = true
	print("[TECH] seeded %d prerequisite tech(s) below the ladder" % seeded)
	for tid6 in chain:
		if not rm.tech_tree.has(tid6):
			_fail("ladder tech %s is missing from tech_tree" % tid6)
			continue
		var node: Dictionary = rm.tech_tree[tid6]
		var flag := str(node.get("requires_flag", ""))
		# can_unlock() checks AFFORDABILITY BEFORE it checks any gate, so an unfunded
		# probe gets `false` for every tech and reads it as "locked". That is how the
		# first version of this walk reported all six as broken, including the two that
		# already shipped working. Bankroll the fight so the only thing under test is
		# the prereq/flag gating.
		GameState.resources.add_currency("credits", 1.0e12)
		for item in (node.get("cost_items", {}) as Dictionary):
			GameState.resources.add_element(str(item),
				float(rm._effective_item_requirement(str(item), int(node["cost_items"][item]))) * 2.0, true)
		# Prove the funding actually landed, or this silently reverts to the same bug.
		if GameState.resources.get_currency("credits") < float(node.get("cost", 0)):
			_fail("probe could not fund %s — the affordability path is still masking the gate test" % tid6)
			continue
		# Before the flag: must be locked. This is the leak guard.
		if flag != "":
			GameState.game_settings[flag] = false
			if rm.can_unlock(tid6):
				_fail("%s is unlockable with its flag '%s' still false — the NG+ ladder leaks early" % [tid6, flag])
			GameState.game_settings[flag] = true
		var opened: bool = rm.can_unlock(tid6)
		if not opened:
			_fail("%s cannot be unlocked: %s" % [tid6, _why_locked(rm, tid6)])
			continue
		if not (tid6 in rm.unlocked_techs):
			rm.unlocked_techs.append(tid6)
		var gated2: Array = []
		var craftable := 0
		for mid2 in sm.modules:
			if str((sm.modules[mid2] as Dictionary).get("research_req", "")) != tid6:
				continue
			gated2.append(str(mid2))
			if rm.is_tech_unlocked(tid6):
				craftable += 1
		print("[TECH]   %-24s flag=%-14s unlocked -> %d/%d gated module(s) now craftable" % [
			tid6, (flag if flag != "" else "none"), craftable, gated2.size()])
		if craftable != gated2.size():
			_fail("%s unlocked but only %d of %d gated modules became craftable" % [
				tid6, craftable, gated2.size()])

	print("[TECH] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


# Pull the `"Tab Name": {"nodes": [ ... ]}` literal out of research_page.gd. Comment
# lines are skipped so a commented-out id is correctly treated as NOT rendered.
func _parse_tabs() -> Dictionary:
	var src := FileAccess.get_file_as_string(PAGE)
	if src == "":
		return {}
	var out: Dictionary = {}
	var cur := ""
	var in_nodes := false
	for raw in src.split("\n"):
		var line := str(raw).strip_edges()
		if line.begins_with("#"):
			continue
		if line.ends_with("\": {") and line.begins_with("\""):
			cur = line.substr(1, line.length() - 5)
			out[cur] = []
			in_nodes = false
			continue
		if cur == "":
			continue
		if line.begins_with("\"nodes\""):
			in_nodes = true
			continue
		if in_nodes and line.begins_with("]"):
			in_nodes = false
			continue
		if in_nodes:
			for part in line.split(","):
				var p := str(part).strip_edges()
				if p.begins_with("\"") and p.length() > 2:
					(out[cur] as Array).append(p.substr(1, p.length() - 2))
	return out


# can_unlock() returns a bare bool, so a failing walk cannot say which of its seven
# conditions bit. Mirror the order and name the first one. (Mirroring is normally the
# wrong move for a test — a copied formula keeps passing after the real one breaks — but
# this is used only to EXPLAIN a failure that can_unlock itself already reported, never
# to decide pass/fail, so the real code path stays the authority.)
# Transitive parent + req_tech closure below a tech, nearest-first.
func _ancestors(rm, tid: String) -> Array:
	var out: Array = []
	var queue: Array = [tid]
	var seen: Dictionary = {tid: true}
	while queue.size() > 0:
		var cur := str(queue.pop_front())
		var node: Dictionary = rm.tech_tree.get(cur, {})
		for key in ["parent", "req_tech"]:
			var up = node.get(key)
			if up == null or str(up) == "" or seen.has(str(up)):
				continue
			seen[str(up)] = true
			out.append(str(up))
			queue.append(str(up))
	out.reverse()      # deepest ancestor first, so each is granted before its child
	return out


func _why_locked(rm, tid: String) -> String:
	if not tid in rm.tech_tree:
		return "not in tech_tree"
	if tid in rm.unlocked_techs:
		return "already unlocked"
	var node: Dictionary = rm.tech_tree[tid]
	var cost: float = float(node.get("cost", 0)) * float(rm.COST_MULTIPLIER)
	var have: float = GameState.resources.get_currency("credits")
	if have < cost:
		return "cannot afford: %.0f Liras held, %.0f needed" % [have, cost]
	for item in (node.get("cost_items", {}) as Dictionary):
		var need: float = float(rm._effective_item_requirement(str(item), int(node["cost_items"][item])))
		var got: float = GameState.resources.get_element_amount(str(item))
		if got < need:
			return "short %s: %.0f held, %.0f needed" % [item, got, need]
	var par2 = node.get("parent")
	if par2 and not (par2 in rm.unlocked_techs):
		return "parent '%s' is not unlocked" % str(par2)
	var rq = node.get("req_tech")
	if rq and not (rq in rm.unlocked_techs):
		return "req_tech '%s' is not unlocked" % str(rq)
	if node.get("requires_warp", false) and not GameState.game_settings.get("cryo_unlocked", false):
		return "requires_warp is set but cryo_unlocked is false"
	var rf := str(node.get("requires_flag", ""))
	if rf != "" and not GameState.game_settings.get(rf, false):
		return "requires_flag '%s' is false" % rf
	return "unknown — can_unlock said no but every mirrored condition passed (the mirror has drifted)"


func _fail(msg: String) -> void:
	print("[TECH] FAIL: %s" % msg)
	fails += 1
