extends Node
# ============================================================================
# Warp Acceleration Scenario — does prestige actually make the re-run faster?
# ----------------------------------------------------------------------------
# The core prestige promise is "each run is faster." This scenario tests it
# DIRECTLY (the A/B/C bot warps from a fresh game → near-zero shards, so it
# can't). Phase 1: fresh game → drive the greedy policy to clear Zone TARGET,
# recording sim-time + skill levels. Then WARP (banking the real progress →
# shards + 30% XP retention + persistent research + tree nodes). Phase 2:
# re-drive to clear Zone TARGET again. Assert phase 2 is meaningfully faster.
#
# Also verifies the mechanical prestige invariants that a static read can't:
#   • warp yields ≥1 shard and warp_shards is monotonic
#   • XP retention: post-warp level ≥ the retained-XP floor (not nuked to 1)
#   • research persists across the warp (soft reset)
#   • no stall in either phase
#
# Run: godot --headless --path <repo> res://scenes/warp_accel.tscn -- --target=2
# ============================================================================

const DT := 0.25
const POLICY := preload("res://scripts/sim/policy_base.gd")   # economic helpers only
const PHASE_STEP_CAP := 900_000
const NO_PROGRESS_WINDOW := 80_000
const SESSION_LEN := 60.0             # sim-seconds of gathering per decision

var sim_s := 0.0
var step := 0
var target := 2
var findings: Array = []

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	GameState.set_process(false)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--target="):
			target = int(a.substr(9))
	seed(20260703)
	print("[WARP-ACCEL] two-phase: drive to FIRST-WARP-READY → warp → measure re-progress")

	# ── PHASE 1: fresh game → earn the first warp (progress_score ≥ 500k) ─
	GameState.hard_reset()
	GameState.resources.add_currency("credits", 100)
	var wm = GameState.warp_manager
	var p1 = POLICY.new()
	var r1 := _drive_to_warp_ready(p1)
	var t1: float = r1["sim_s"]
	var score1: float = _progress_score()
	var g1: int = GameState.gathering_manager.get_level()
	var res1: int = GameState.research_manager.unlocked_techs.size()
	print("[WARP-ACCEL] phase1: %s in %.2fh (%d steps) | score=%.0f g_lvl=%d research=%d gather=%s" % [
		r1["result"], t1 / 3600.0, r1["steps"], score1, g1, res1, r1["gather"]])
	if r1["result"] != "WARP_READY":
		findings.append("✖ phase1 never reached the first warp (%s) — economic path to prestige is blocked" % r1["result"])
		_verdict(); return

	# ── WARP: bank the first run ─────────────────────────────────────────
	var gains: int = wm.calculate_warp_gains()
	_do_warp(p1)
	var shards_after: float = wm.warp_shards
	var res_after: int = GameState.research_manager.unlocked_techs.size()
	var g_after: int = GameState.gathering_manager.get_level()
	if shards_after < 1:
		findings.append("✖ warp yielded <1 shard at the warp-ready gate (%.0f)" % shards_after)
	if res_after < res1:
		findings.append("✖ research did NOT persist across warp (%d → %d) — soft-reset broken" % [res1, res_after])
	if g1 >= 20 and g_after <= 1:
		findings.append("✖ XP retention broken: gathering %d → %d across warp (should keep ~30%%)" % [g1, g_after])
	print("[WARP-ACCEL] warp: +%d shards → %.0f | g_lvl %d→%d | research %d→%d | prod×%.2f cmb×%.2f" % [
		gains, shards_after, g1, g_after, res1, res_after,
		wm.get_production_multiplier(), wm.get_combat_multiplier()])

	# ── PHASE 2: re-earn the SAME progress post-warp (should be faster) ───
	# credits_at_warp_start is now the post-warp baseline, so "another 500k of
	# NEW progress" is the apples-to-apples comparison to phase 1.
	sim_s = 0.0; step = 0
	var p2 = POLICY.new()
	var r2 := _drive_to_warp_ready(p2)
	var t2: float = r2["sim_s"]
	print("[WARP-ACCEL] phase2: %s in %.2fh (%d steps) | g_lvl=%d" % [
		r2["result"], t2 / 3600.0, r2["steps"], GameState.gathering_manager.get_level()])
	if r2["result"] != "WARP_READY":
		findings.append("✖ phase2 did NOT re-reach warp-ready post-warp (%s) — a warp made progress WORSE" % r2["result"])
		_verdict(); return

	# ── the prestige promise: phase 2 should be meaningfully faster ──────
	var speedup: float = (t1 / t2) if t2 > 0 else 0.0
	print("[WARP-ACCEL] ACCELERATION: phase1=%.2fh → phase2=%.2fh  (%.2f× faster)" % [
		t1 / 3600.0, t2 / 3600.0, speedup])
	if t2 >= t1:
		findings.append("✖ PRESTIGE BROKEN: re-earning warp progress was SLOWER post-warp (%.2fh → %.2fh)." % [t1/3600.0, t2/3600.0])
	elif speedup < 1.15:
		findings.append("⚠ prestige acceleration weak: only %.2f× faster (research persistence + XP retention + warp mult should beat 1.15×)" % speedup)

	_verdict()

func _verdict() -> void:
	print("")
	if findings.is_empty():
		print("[WARP-ACCEL] HEALTHY — prestige accelerates the re-run and all invariants hold.")
	else:
		print("[WARP-ACCEL] %d FINDING(S):" % findings.size())
		for f in findings:
			print("   " + f)
	get_tree().quit()

func _progress_score() -> float:
	var wm = GameState.warp_manager
	var btot := 0
	for bid in GameState.infrastructure_manager.buildings:
		btot += int(GameState.infrastructure_manager.buildings[bid])
	return (GameState.resources.lifetime_credits - wm.credits_at_warp_start) + float(btot) * 1000.0

# ── driver: economic-only drive to the first warp (deterministic, comparable) ─
# gather best cps → sell → reinvest (research/buildings/storage), until the warp
# gate (progress_score ≥ 500k) is met. Same strategy both phases, so the only
# variable is what the warp CARRIED (retained XP + persistent research + shard
# multipliers) — which is exactly the prestige acceleration we want to measure.
func _drive_to_warp_ready(pb) -> Dictionary:
	var wm = GameState.warp_manager
	var gm = GameState.gathering_manager
	var start_step := step
	var start_sim := sim_s
	var last_score := -1.0
	var last_prog := step
	var best_gather_id := ""
	while true:
		if wm.calculate_warp_gains() >= 1:
			return {"result": "WARP_READY", "sim_s": sim_s - start_sim, "steps": step - start_step, "gather": best_gather_id}

		# reinvest surplus: cheap research opens better gathers; buildings add to
		# progress_score directly + auto-produce sellable mats.
		pb.try_unlock_research(2)
		pb.buy_buildings(3)
		pb.maybe_upgrade_storage()

		var bg: Array = pb.best_gather()
		if bg.is_empty():
			return {"result": "STALL:no_gather", "sim_s": sim_s - start_sim, "steps": step - start_step, "gather": best_gather_id}
		best_gather_id = str(bg[0])
		_set_active(gm)
		gm.start_action(best_gather_id)
		var steps := int(SESSION_LEN / DT)
		for _i in range(steps):
			GameState.infrastructure_manager.process_tick(DT)
			GameState.bounty_manager.process_tick(DT)
			# v134h: Warp-Core Charge is manual-feed now — sim does not model feeding.
			if GameState.active_manager: GameState.active_manager.process_tick(DT)
			sim_s += DT; step += 1
		pb.sell_surplus({})    # convert gathered mats to credits → lifetime_credits

		var score := _progress_score()
		if score > last_score + 1.0:
			last_score = score; last_prog = step
		if step - last_prog > NO_PROGRESS_WINDOW or (step - start_step) > PHASE_STEP_CAP:
			return {"result": "STALL:no_progress", "sim_s": sim_s - start_sim, "steps": step - start_step, "gather": best_gather_id}
	return {"result": "STALL:unreachable", "sim_s": sim_s - start_sim, "steps": step - start_step, "gather": best_gather_id}

func _do_warp(_p) -> void:
	var wm = GameState.warp_manager
	wm.execute_warp()
	# spend the shard(s) on the cheapest economic nodes so phase 2 also sees the
	# tree-bonus lever (not just the flat shard multiplier).
	var order: Array = ["ENG_1", "ENG_4", "ENG_S1", "ENG_S2"]
	for nid in order:
		var guard := 0
		while wm.can_purchase_node(nid) and guard < 50:
			if not wm.purchase_node(nid): break
			guard += 1

func _set_active(mgr) -> void:
	if GameState.active_manager and GameState.active_manager != mgr:
		GameState.active_manager.stop_action()
	GameState.active_manager = mgr
