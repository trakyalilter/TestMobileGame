extends Node
# ============================================================================
# Warp Cadence Scenario — does prestige keep feeling faster EACH time?
# ----------------------------------------------------------------------------
# warp_accel proves warp #1 accelerates the re-run. This proves the COMPOUNDING
# promise (CLAUDE.md: "prestige must feel faster each time"): run N sequential
# warps via the same deterministic economic drive and record the real playtime
# to reach each successive warp gate. A healthy prestige loop makes each gap
# non-increasing (retained XP + persistent research + growing shard/tree mults
# should out-run the flat 500k gate), and shard yield should grow per warp.
#
# Run: godot --headless --path <repo> res://scenes/warp_cadence.tscn -- --warps=5
# ============================================================================

const DT := 0.25
const POLICY := preload("res://scripts/sim/policy_base.gd")
const WARP_STEP_CAP := 900_000
const NO_PROGRESS_WINDOW := 80_000
const SESSION_LEN := 60.0

var sim_s := 0.0
var step := 0
var n_warps := 5
var findings: Array = []

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	GameState.set_process(false)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--warps="):
			n_warps = int(a.substr(8))
	seed(20260703)
	print("[WARP-CADENCE] measuring time-to-warp across %d sequential warps" % n_warps)

	GameState.hard_reset()
	GameState.resources.add_currency("credits", 100)
	var wm = GameState.warp_manager
	var pb = POLICY.new()

	var gaps: Array = []          # real playtime (h) to reach each warp
	var yields: Array = []        # shards gained each warp
	var mults: Array = []         # cumulative production mult after each warp

	for w in range(n_warps):
		sim_s = 0.0; step = 0
		var r := _drive_to_warp(pb)
		if r["result"] != "WARP_READY":
			findings.append("✖ warp #%d never reached the gate (%s) after %d prior warps — cadence broke" % [w + 1, r["result"], w])
			break
		var gap_h: float = r["sim_s"] / 3600.0
		var gains: int = wm.calculate_warp_gains()
		var g_pre: int = GameState.gathering_manager.get_level()
		var res_pre: int = GameState.research_manager.unlocked_techs.size()
		wm.execute_warp()
		# spend shards on the cheapest economic tree nodes each warp
		for nid in ["ENG_1", "ENG_4", "ENG_S1", "ENG_S2", "REC_S1"]:
			var guard := 0
			while wm.can_purchase_node(nid) and guard < 50:
				if not wm.purchase_node(nid): break
				guard += 1
		gaps.append(gap_h); yields.append(gains); mults.append(wm.get_production_multiplier())
		print("[WARP-CADENCE] warp #%d: %.2fh to gate | +%d shards (total %.0f) | g_lvl=%d res=%d | prod×%.2f cmb×%.2f" % [
			w + 1, gap_h, gains, wm.warp_shards, g_pre, res_pre,
			wm.get_production_multiplier(), wm.get_combat_multiplier()])

	_analyze(gaps, yields, mults)

func _analyze(gaps: Array, yields: Array, mults: Array) -> void:
	print("")
	if gaps.size() >= 2:
		print("[WARP-CADENCE] time-to-warp (h): %s" % str(gaps.map(func(x): return snappedf(x, 0.01))))
		print("[WARP-CADENCE] shards/warp:      %s" % str(yields))
		print("[WARP-CADENCE] cumulative prod×: %s" % str(mults.map(func(x): return snappedf(x, 0.01))))
		# INVARIANT 1: cadence non-increasing (allow 10% noise per step)
		for i in range(1, gaps.size()):
			if gaps[i] > gaps[i - 1] * 1.10:
				findings.append("✖ warp #%d took LONGER than #%d (%.2fh → %.2fh) — prestige stopped accelerating" % [
					i + 1, i, gaps[i - 1], gaps[i]])
		# INVARIANT 2: shard yield should grow (compounding power)
		if int(yields[-1]) < int(yields[0]):
			findings.append("⚠ shard yield shrank across warps (%d → %d) — later warps reward less" % [int(yields[0]), int(yields[-1])])
		# headline speedup first→last
		if gaps[-1] > 0:
			print("[WARP-CADENCE] first→last speedup: %.2f× (%.2fh → %.2fh)" % [gaps[0] / gaps[-1], gaps[0], gaps[-1]])
	else:
		findings.append("✖ fewer than 2 warps completed — cadence not measurable")

	print("")
	if findings.is_empty():
		print("[WARP-CADENCE] HEALTHY — cadence holds or accelerates and shard yield grows.")
	else:
		print("[WARP-CADENCE] %d FINDING(S):" % findings.size())
		for f in findings:
			print("   " + f)
	get_tree().quit()

func _progress_score() -> float:
	var wm = GameState.warp_manager
	var btot := 0
	for bid in GameState.infrastructure_manager.buildings:
		btot += int(GameState.infrastructure_manager.buildings[bid])
	return (GameState.resources.lifetime_credits - wm.credits_at_warp_start) + float(btot) * 1000.0

func _drive_to_warp(pb) -> Dictionary:
	var wm = GameState.warp_manager
	var gm = GameState.gathering_manager
	var start_step := step
	var start_sim := sim_s
	var last_score := -1.0
	var last_prog := step
	while true:
		if wm.calculate_warp_gains() >= 1:
			return {"result": "WARP_READY", "sim_s": sim_s - start_sim, "steps": step - start_step}
		pb.try_unlock_research(2)
		pb.buy_buildings(3)
		pb.maybe_upgrade_storage()
		var bg: Array = pb.best_gather()
		if bg.is_empty():
			return {"result": "STALL:no_gather", "sim_s": sim_s - start_sim, "steps": step - start_step}
		_set_active(gm)
		gm.start_action(str(bg[0]))
		var steps := int(SESSION_LEN / DT)
		for _i in range(steps):
			GameState.infrastructure_manager.process_tick(DT)
			GameState.bounty_manager.process_tick(DT)
			GameState.warp_manager.process_charge(DT)
			if GameState.active_manager: GameState.active_manager.process_tick(DT)
			sim_s += DT; step += 1
		pb.sell_surplus({})
		var score := _progress_score()
		if score > last_score + 1.0:
			last_score = score; last_prog = step
		if step - last_prog > NO_PROGRESS_WINDOW or (step - start_step) > WARP_STEP_CAP:
			return {"result": "STALL:no_progress", "sim_s": sim_s - start_sim, "steps": step - start_step}
	return {"result": "STALL:unreachable", "sim_s": sim_s - start_sim, "steps": step - start_step}

func _set_active(mgr) -> void:
	if GameState.active_manager and GameState.active_manager != mgr:
		GameState.active_manager.stop_action()
	GameState.active_manager = mgr
