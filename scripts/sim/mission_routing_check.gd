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

# Types main.gd::_generic_mission_pulse knows how to place. Adding a mission type
# without teaching the router about it is the failure this catches.
const ROUTABLE_TYPES := ["research", "defeat", "drop_rarity", "build", "construct",
	"craft", "craft_matrix", "loadout_check", "equip_consumables",
	"loadout_rare_weapon", "loadout_rare_weapon_type", "hack_apply", "socket_check",
	"warp_perform", "overclock_install", "visit_page", "gather", "gather_multi"]

# "discover" completes on a world event, not by visiting anywhere — there is no
# correct arrow target, so it is exempt rather than a routing hole.
const UNROUTABLE_BY_DESIGN := ["discover"]

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
	var mm = GameState.mission_manager
	print("[MROUTE] ============ mission routing ============")
	print("[MROUTE] missions defined: %d" % mm.missions.size())

	var bad_type := []
	var unsourced := []
	var ambiguous := []

	for mid in mm.missions:
		var m: Dictionary = mm.missions[mid]
		var mtype := String(m.get("type", ""))
		if not (mtype in ROUTABLE_TYPES) and not (mtype in UNROUTABLE_BY_DESIGN):
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

	_ok("every mission type is routable", bad_type.is_empty(), str(bad_type).substr(0, 200))
	_ok("every gather target has a producer", unsourced.is_empty(), str(unsourced).substr(0, 200))
	_ok("no '<sidebar page> tab' phrasing in mission text", ambiguous.is_empty(), str(ambiguous).substr(0, 200))

	# The arcs that actually regressed — assert they exist and carry a routable
	# type, so a future refactor that drops them fails here instead of in-game.
	for mid in ["goal_hack_1", "m029a7"]:
		var m: Dictionary = mm.missions.get(mid, {})
		_ok("%s defined + routable" % mid,
			not m.is_empty() and String(m.get("type", "")) in ROUTABLE_TYPES,
			String(m.get("type", "MISSING")))

	print("[MROUTE] ============ %s ============" % ("ALL PASS" if fails == 0 else "%d FAIL(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
