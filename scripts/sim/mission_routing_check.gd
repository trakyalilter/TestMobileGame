extends Node
# ============================================================================
# MISSION ROUTING CHECK (v141c) — every mission must be able to point somewhere.
#
# The gold directive arrow is driven by a hand-written elif chain in main.gd
# keyed on explicit mission ids. Missions added after that chain was written
# (the whole goal_* arc, the m029a* chapter beats) fell through it and produced
# NO arrow — and the repair fallback underneath then pulsed COMBAT, which reads
# as "this mission wants Combat". v141c added a type-driven generic fallback.
#
# This guards the DATA that fallback depends on, which is where the real rot is:
#   1. every mission's type is one the router knows how to place
#   2. every gather-type mission names a material something actually produces
#      (an unsourced target resolves to no page -> no arrow -> silent dead end)
#   3. no mission text says "<X> tab" for a word that is also a sidebar page,
#      which is how goal_hack_1's "(Combat tab)" fought its own arrow
#
#   Godot --headless --path <root> res://scenes/mission_routing_check.tscn
# ============================================================================

# v174: routability used to be a hand-copied list of _page_for_mission's match
# arms, and it had drifted — "atlas_lookup" IS routed (main.gd returns "atlas")
# but was missing here, and the list knew nothing about the explicit per-mission
# elif ladder in _generic_mission_pulse, which is what actually routes m017.
# Both were reported as routing holes that did not exist.
#
# Derived from main.gd's source now, so the guard cannot drift from the router
# again: a new match arm or a new ladder entry is picked up on the next run.
const MAIN_SRC := "res://scripts/main.gd"

# "discover" completes on a world event, not by visiting anywhere — there is no
# correct arrow target, so it is exempt rather than a routing hole.
const UNROUTABLE_BY_DESIGN := ["discover"]

var ROUTABLE_TYPES: Array = []      # match arms of _page_for_mission
var EXPLICIT_ROUTED_IDS: Array = [] # ids hand-placed by the _generic_mission_pulse ladder

func _scan_router() -> void:
	var f := FileAccess.open(MAIN_SRC, FileAccess.READ)
	if f == null:
		push_error("[MROUTE] cannot read %s" % MAIN_SRC)
		return
	var lines: PackedStringArray = f.get_as_text().split("
")
	f.close()
	var in_pfm := false
	for raw in lines:
		var t := String(raw).strip_edges()
		# --- explicit ladder: elif "mNNN" in mm.active_missions ---
		if "in mm.active_missions" in t:
			for tok in _quoted(t):
				if tok.begins_with("m"):
					EXPLICIT_ROUTED_IDS.append(tok)
		# --- _page_for_mission match arms ---
		if t.begins_with("func _page_for_mission"):
			in_pfm = true
			continue
		if in_pfm:
			if t.begins_with("func "):
				in_pfm = false
				continue
			# A match ARM ends in ":" (or "\\" when it wraps); a return does not.
			if (t.ends_with(":") or t.ends_with("\\")) and not t.begins_with("match ") and not t.begins_with("#"):
				ROUTABLE_TYPES.append_array(_quoted(t))

func _quoted(line: String) -> Array:
	var out: Array = []
	var parts: PackedStringArray = line.split("\"")
	var i := 1
	while i < parts.size():
		var v := String(parts[i]).strip_edges()
		if v != "":
			out.append(v)
		i += 2
	return out

# Sidebar page words. Saying "<page> tab" is only a problem on a RESEARCH mission,
# where "tab" means a category INSIDE the Research Lab — "Combat tab" then fights
# the sidebar's own Combat button. On a gather/craft mission "Engineering tab"
# correctly means the Engineering page, so those must not be flagged.
const SIDEBAR_WORDS := ["Combat", "Shipyard", "Infrastructure", "Engineering",
	"Mine", "Inventory", "Bounties", "Quests"]

var fails := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		fails += 1
	print("[MROUTE] %-52s %s %s" % [name, "OK" if cond else "*** FAIL", detail])


# Code-granted items: no loot table or recipe lists them, they are handed out by
# a manager directly (SpliceChip in combat_manager::2853 on a Hack Card roll).
# Verified by grep, not guessed — an entry here must be a real add_element site.
const CODE_GRANTED := ["SpliceChip"]


func _sourced(sym: String) -> bool:
	if sym in CODE_GRANTED:
		return true
	var gm = GameState.gathering_manager
	var pm = GameState.processing_manager
	var cm = GameState.combat_manager
	if gm:
		for aid in gm.actions:
			for e in gm.actions[aid].get("loot_table", []):
				if String(e[0]) == sym:
					return true
	if pm:
		for rid in pm.recipes:
			if (pm.recipes[rid].get("output", {}) as Dictionary).has(sym):
				return true
	# Combat loot counts as a producer — m032d asks for VoidArtifact, which no
	# gather action or recipe makes; it drops off Z6+ enemies.
	if cm:
		for eid in cm.enemy_db:
			var e = cm.enemy_db[eid]
			for entry in e.get("loot", []):
				if String(entry[0]) == sym:
					return true
			for entry in e.get("rare_loot", []):
				if String(entry[0]) == sym:
					return true
			if String(e.get("boss_core", "")) == sym:
				return true
	return false


func _ready() -> void:
	GameState.hard_reset()
	_scan_router()
	var mm = GameState.mission_manager
	print("[MROUTE] ============ mission routing ============")
	print("[MROUTE] router scan: %d routable types, %d explicitly-routed ids" % [
		ROUTABLE_TYPES.size(), EXPLICIT_ROUTED_IDS.size()])
	print("[MROUTE] missions defined: %d" % mm.missions.size())

	var bad_type := []
	var unsourced := []
	var ambiguous := []

	var tutorial_count := 0
	for mid in mm.missions:
		var m: Dictionary = mm.missions[mid]
		var mtype := String(m.get("type", ""))
		# v141c: only [TUTORIAL] missions get a directive arrow now, so only they
		# MUST be routable. Goal / chapter / endgame arcs are self-directed — an
		# unroutable type there is fine, it simply produces no arrow.
		var is_tutorial: bool = (String(m.get("tag", "")) == "[TUTORIAL]")
		if is_tutorial:
			tutorial_count += 1
			# Routed either generically (by type) or by an explicit ladder entry
			# for this exact mission id — m017's defeat_retreat has no type arm but
			# is hand-placed onto the Lunar Drone card.
			if not (mtype in ROUTABLE_TYPES) 					and not (mtype in UNROUTABLE_BY_DESIGN) 					and not (String(mid) in EXPLICIT_ROUTED_IDS):
				bad_type.append("%s:%s" % [String(mid), mtype])

		if mtype == "gather":
			var sym := String(m.get("target", ""))
			if sym != "" and not _sourced(sym):
				unsourced.append("%s:%s" % [String(mid), sym])
		elif mtype == "gather_multi":
			for s in (m.get("target", {}) as Dictionary):
				if not _sourced(String(s)):
					unsourced.append("%s:%s" % [String(mid), String(s)])

		# Research missions only — see SIDEBAR_WORDS note.
		if mtype == "research":
			var desc := String(m.get("description", ""))
			for w in SIDEBAR_WORDS:
				if desc.contains("%s tab" % w):
					ambiguous.append("%s:'%s tab'" % [String(mid), w])

	print("[MROUTE] tutorial missions: %d" % tutorial_count)
	_ok("every TUTORIAL mission type is routable", bad_type.is_empty(), str(bad_type).substr(0, 200))
	_ok("every gather target has a producer", unsourced.is_empty(), str(unsourced).substr(0, 200))
	_ok("no '<sidebar page> tab' phrasing in mission text", ambiguous.is_empty(), str(ambiguous).substr(0, 200))

	# The directive is tutorial-gated: a [TUTORIAL] mission must be able to point
	# somewhere, and a non-tutorial one must NOT be treated as a directive source.
	var t_ok: bool = String(mm.missions.get("m019", {}).get("tag", "")) == "[TUTORIAL]" \
		and String(mm.missions.get("m019", {}).get("type", "")) in ROUTABLE_TYPES
	_ok("sample tutorial (m019) is tagged + routable", t_ok, mm.missions.get("m019", {}).get("tag", "MISSING"))
	_ok("m029a7 is NOT tutorial (no directive)",
		String(mm.missions.get("m029a7", {}).get("tag", "")) != "[TUTORIAL]",
		mm.missions.get("m029a7", {}).get("tag", "MISSING"))
	_ok("goal_hack_1 is NOT tutorial (no directive)",
		String(mm.missions.get("goal_hack_1", {}).get("tag", "")) != "[TUTORIAL]",
		mm.missions.get("goal_hack_1", {}).get("tag", "MISSING"))

	print("[MROUTE] ============ %s ============" % ("ALL PASS" if fails == 0 else "%d FAIL(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
