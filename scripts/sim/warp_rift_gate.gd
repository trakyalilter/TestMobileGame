extends Node
# ============================================================================
# WARP RIFT GATE (v141) — the headless bot must warp only when the REAL game
# would let it. v138 made warping diegetic: the Singularity must be OPEN, which
# happens only after a Zone-3+ boss kill THIS run. execute_warp() itself does not
# enforce that (the UI does), so the sim harness has to — otherwise player_bot
# reports warps a player could never have taken (0 boss kills, score-only).
#
# Guards two things:
#   1. the game invariant the bot leans on: rift starts closed, a Z3+ boss opens
#      it, a Z1/Z2 boss does NOT, and warping closes it again.
#   2. the policy + harness both actually check rift_open before warping.
#
#   Godot --headless --path <root> res://scenes/warp_rift_gate.tscn
# ============================================================================

var fails := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond: fails += 1
	print("[RIFT] %-46s %s %s" % [name, "OK" if cond else "*** FAIL", detail])


func _kill_boss(cm, eid: String) -> void:
	var e: Dictionary = cm.enemy_db.get(eid, {})
	cm.current_zone = {"name": "probe", "difficulty": int(e.get("zone", 1)), "enemies": [eid]}
	cm.current_zone_id = "probe"
	cm.target_enemy_id = eid
	cm.spawn_enemy()
	cm.in_combat = true
	cm.enemy_hp = 1
	cm.current_enemy = e.duplicate(true)
	cm.current_enemy["id"] = eid
	# Drive the shared boss-progression path (opens the rift for Z3+).
	cm._apply_boss_progression(eid)


func _ready() -> void:
	GameState.set_process(false)
	var wm = GameState.warp_manager
	var cm = GameState.combat_manager

	print("[RIFT] ============ warp rift gate ============")

	# ── 1. Fresh run: rift closed even with a warp-worthy score ──
	GameState.hard_reset()
	GameState.resources.lifetime_credits = 5.0e8   # way past the 500k gate
	wm.credits_at_warp_start = 0.0
	_ok("score gate open (gains>=1)", wm.calculate_warp_gains() >= 1,
		"gains=%d" % int(wm.calculate_warp_gains()))
	_ok("rift CLOSED at run start", not wm.rift_open)

	# ── 2. A Zone-1 boss does NOT open the rift ──
	GameState.hard_reset()
	GameState.resources.lifetime_credits = 5.0e8
	wm.credits_at_warp_start = 0.0
	_kill_boss(cm, "z1_boss_architect")
	_ok("Z1 boss does NOT open rift", not wm.rift_open)

	# ── 3. A Zone-3 boss DOES open it ──
	var z3 := ""
	for eid in cm.enemy_db:
		var e: Dictionary = cm.enemy_db[eid]
		if bool(e.get("is_boss", false)) and int(e.get("zone", 0)) == 3:
			z3 = String(eid); break
	_ok("found a Z3 boss", z3 != "", z3)
	if z3 != "":
		_kill_boss(cm, z3)
		_ok("Z3 boss OPENS rift", wm.rift_open)

	# ── 4. Warping closes it again (re-earned next run) ──
	if wm.rift_open and wm.calculate_warp_gains() >= 1:
		wm.execute_warp()
		_ok("rift CLOSES after warp", not wm.rift_open)

	# ── 5. Source guard: policy + harness both check rift_open ──
	var pol: String = FileAccess.get_file_as_string("res://scripts/sim/policies/player_like.gd")
	_ok("policy warp verb checks rift_open", pol.contains("not GameState.warp_manager.rift_open"))
	var bot: String = FileAccess.get_file_as_string("res://scripts/sim/player_bot.gd")
	_ok("harness _do_warp checks rift_open", bot.contains("if not wm.rift_open:"))

	print("[RIFT] ============ %s ============" % ("ALL PASS" if fails == 0 else "%d FAIL(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
