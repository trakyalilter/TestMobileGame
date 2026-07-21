extends Node
# ============================================================================
# MATRIX-CORE MISSION CHECK (v139f) — the module SOCKET system shipped with
# ZERO mission guidance (matrix_synthesis unlocks at zone_2_access but nothing
# ever taught the player to craft or socket a core). Adds the goal_matrix arc
# (synthesize -> socket), mirroring the Hack/Boost onboarding arcs. Asserts:
#   - the arc reveals ONLY when synthesis is craftable (zone_2_access) AND an
#     equipped module has an open socket -> both steps completable, no soft-wall
#   - craft_matrix completes on owning ANY Matrix Core (random color output)
#   - the arc chains, and socket_check completes when a core is socketed
#   Godot --headless --path <root> res://scenes/matrix_mission_check.tscn
# ============================================================================

var fails := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond: fails += 1
	print("[MATRIX] %-42s %s %s" % [name, "OK" if cond else "*** FAIL", detail])

func _ready() -> void:
	var mm = GameState.mission_manager
	var sm = GameState.shipyard_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	GameState.hard_reset()
	print("[MATRIX] ============ matrix-core mission check ============")

	_ok("goal_matrix_1 defined", mm.missions.has("goal_matrix_1"))
	_ok("goal_matrix_2 defined", mm.missions.has("goal_matrix_2"))
	_ok("arc dormant on fresh game", not mm.missions["goal_matrix_1"]["active"])

	# Gate: zone_2_access ALONE (no open socket) must NOT reveal — the socket step
	# would soft-wall.
	if not "zone_2_access" in rm.unlocked_techs:
		rm.unlocked_techs.append("zone_2_access")
	sm.loadout.clear()
	mm._check_goal_reveals()
	_ok("no reveal without an open socket", not mm.missions["goal_matrix_1"]["active"])

	# Equip a module with an OPEN socket (real module so recalc_stats stays valid).
	sm.modules["z1_kinetic"]["sockets"] = [null]
	sm.loadout[0] = "z1_kinetic"
	_ok("_has_open_socket true", mm._has_open_socket())
	mm._check_goal_reveals()
	_ok("arc reveals w/ zone_2 + socket", mm.missions["goal_matrix_1"]["active"])

	# Step 1: own a Matrix Core (matrix_synthesis outputs a RANDOM color) -> completes.
	GameState.resources.add_element("CrackedCobaltCore", 1)
	mm.sync_progress()
	_ok("goal_matrix_1 completes on craft", mm.missions["goal_matrix_1"]["completed"])

	# Claim step 1 -> step 2 activates.
	mm.claim_reward("goal_matrix_1")
	_ok("goal_matrix_2 active after claim", mm.missions["goal_matrix_2"]["active"])
	_ok("socket step pending pre-socket", not mm.missions["goal_matrix_2"]["completed"],
		"socketed=%d" % mm._count_socketed_matrix_cores())

	# Step 2: socket the core -> socket_check completes.
	var inserted: bool = sm.insert_gem("z1_kinetic", 0, "CrackedCobaltCore")
	_ok("insert_gem succeeded", inserted)
	mm.sync_progress()
	_ok("_count_socketed == 1", mm._count_socketed_matrix_cores() == 1,
		"got %d" % mm._count_socketed_matrix_cores())
	_ok("goal_matrix_2 completes on socket", mm.missions["goal_matrix_2"]["completed"])

	print("[MATRIX] %s" % ("ALL PASS" if fails == 0 else "*** %d FAILURE(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
