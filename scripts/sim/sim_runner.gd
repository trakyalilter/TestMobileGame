extends Node

# ============================================================================
# Headless Virtual-Player Balance Harness — Phase 1 MVP
# ----------------------------------------------------------------------------
# Drives the REAL managers (no UI) as a behavior-archetype bot through days of
# compressed game time, emitting JSONL telemetry for progression-pacing
# analysis: time-to-skill-milestone and time-to-first-warp.
#
# Launch (via tools/run_sim.ps1, which swaps run/main_scene):
#   ... -- --archetype=optimizer --seed=12345 --days=30 --out=<path>
#
# Time model: active SESSIONS (real process_tick loop) + offline GAPS (one
# closed-form process_offline_progress call) — mirrors the game's own two code
# paths and a realistic play schedule. Sessions+gaps sum to 24h per day.
# ============================================================================

const DT := 0.25                       # sim-seconds per manual step in a session
const MILESTONES := [10, 25, 50, 75, 100]

var tele                                # SimTelemetry
var policy                             # PolicyBase subclass
var args := {}                          # parsed --key=value CLI args

var sim_s := 0.0                        # elapsed sim-seconds
var ttm := {"gathering": {}, "processing": {}}   # first sim_s each milestone hit
var time_to_first_warp = null
var combat_kills := 0                   # enemies defeated (combat archetype)
var highest_zone_diff := 0              # deepest zone difficulty entered

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	GameState.set_process(false)        # harness owns the clock (no double-tick / autosave)
	_parse_args()

	var archetype: String = str(args.get("archetype", "optimizer"))
	var seed_v: int = int(args.get("seed", "1"))
	var days: int = int(args.get("days", "7"))

	_new_game(seed_v)

	if GameState.combat_manager.has_signal("enemy_defeated"):
		GameState.combat_manager.enemy_defeated.connect(_on_enemy_defeated)

	# A combat-focused player turns on Offline Combat (the game supports it,
	# opt-in). Modeling that here isolates "is combat weak, or just starved of
	# offline time?" without changing any game balance number.
	if archetype == "combat":
		GameState.game_settings["offline_combat"] = true

	policy = _make_policy(archetype)
	if policy == null:
		push_error("[SIM] unknown archetype: %s" % archetype)
		get_tree().quit(1)
		return

	var sched := _schedule_for(archetype)
	if not _open_tele(archetype, seed_v):
		get_tree().quit(1)
		return

	tele.write({
		"t": "meta", "archetype": archetype, "seed": seed_v, "days": days,
		"sessions_per_day": sched["sessions"], "session_len_s": sched["len"],
		"offline_gap_s": sched["gap"], "dt": DT,
		"engine": Engine.get_version_info().get("string", ""),
	})

	print("[SIM] %s seed=%d days=%d  (%d sessions/day, %.0fs each, %.0fs gaps)" % [
		archetype, seed_v, days, sched["sessions"], sched["len"], sched["gap"]])

	for day in range(days):
		for sess in range(int(sched["sessions"])):
			policy.manage_meta()
			_maybe_warp()
			var decision: Dictionary = policy.decide_session()
			_run_session(decision, float(sched["len"]))
			sim_s += float(sched["len"])
			_snapshot(day, "session")

			policy.pre_offline()
			# Reflect offline-combat's zone in the depth telemetry (pre_offline may
			# have set combat as the away-task).
			if GameState.combat_manager.in_combat and GameState.combat_manager.current_zone:
				var zd: int = int(GameState.combat_manager.current_zone.get("difficulty", 0))
				if zd > highest_zone_diff:
					highest_zone_diff = zd
			# Offline kills fire no per-kill signal, so capture them as the delta
			# of the manager's total_kills across the closed-form offline step.
			var k_before: int = GameState.combat_manager.total_kills
			GameState.process_offline_progress(float(sched["gap"]))
			combat_kills += GameState.combat_manager.total_kills - k_before
			sim_s += float(sched["gap"])
			_snapshot(day, "offline")

			_heartbeat(day, days, sess)

	_write_summary(archetype, seed_v, days)
	tele.close()
	print("[SIM] done: sim_s=%.0f (%.1f days)  first_warp=%s  total_warps=%d" % [
		sim_s, sim_s / 86400.0, str(time_to_first_warp), GameState.warp_manager.total_warps])
	get_tree().quit(0)

# ---------------------------------------------------------------------------
func _run_session(decision: Dictionary, length: float) -> void:
	if decision.is_empty():
		return
	# Drain the managers' UI event buffers. In-game the UI drains these every
	# frame; headless there's no consumer, so they'd grow unbounded over a
	# multi-day run. Clearing each session keeps memory flat.
	GameState.gathering_manager.events.clear()
	GameState.processing_manager.events.clear()

	if str(decision.get("kind", "gather")) == "combat":
		_run_combat_session(decision, length)
		return

	var mgr = decision["mgr"]
	var id: String = str(decision["id"])
	_set_active(mgr)
	mgr.start_action(id)
	var steps := int(length / DT)
	for _i in range(steps):
		GameState.infrastructure_manager.process_tick(DT)
		if GameState.active_manager:
			GameState.active_manager.process_tick(DT)

func _run_combat_session(decision: Dictionary, length: float) -> void:
	var cm = GameState.combat_manager
	var zid: String = str(decision.get("zone", ""))
	var enemy: String = str(decision.get("enemy", ""))
	if zid == "":
		return
	var diff := int(cm.zones[zid].get("difficulty", 0))
	if diff > highest_zone_diff:
		highest_zone_diff = diff
	_set_active(cm)
	cm.start_expedition(zid)
	if enemy != "":
		cm.set_target_enemy(enemy)
	var steps := int(length / DT)
	for _i in range(steps):
		GameState.infrastructure_manager.process_tick(DT)   # Slug Factory makes ammo
		if not cm.in_combat:
			# Retreated or died — re-enter to keep farming the session out.
			cm.start_expedition(zid)
			if enemy != "":
				cm.set_target_enemy(enemy)
		cm.process_tick(DT)

func _on_enemy_defeated(_a = null, _b = null, _c = null) -> void:
	combat_kills += 1

func _heartbeat(day: int, days: int, sess: int) -> void:
	# Compact live-progress line (grep the log for "[SIM] day" to watch a run).
	var gm = GameState.gathering_manager
	var pm = GameState.processing_manager
	var wm = GameState.warp_manager
	var res = GameState.resources
	print("[SIM] day %d/%d sess %d | sim=%.2fd | g_lvl=%d p_lvl=%d | lifeCr=%.0f | warps=%d shards=%.0f" % [
		day + 1, days, sess + 1, sim_s / 86400.0,
		gm.get_level(), pm.get_level(), res.lifetime_credits,
		wm.total_warps, wm.warp_shards])

func _maybe_warp() -> void:
	if not policy.want_warp():
		return
	var wm = GameState.warp_manager
	var shards_before: float = wm.warp_shards
	wm.execute_warp()
	var gained: float = wm.warp_shards - shards_before
	if gained <= 0:
		return
	if time_to_first_warp == null:
		time_to_first_warp = sim_s
	tele.write({
		"t": "event", "kind": "WARP", "sim_s": sim_s,
		"shards_gained": gained, "total_warps": wm.total_warps,
	})

func _snapshot(day: int, phase: String) -> void:
	var gm = GameState.gathering_manager
	var pm = GameState.processing_manager
	var rm = GameState.research_manager
	var wm = GameState.warp_manager
	var im = GameState.infrastructure_manager
	var res = GameState.resources

	var btot := 0
	for bid in im.buildings:
		btot += int(im.buildings[bid])
	var score: float = (res.lifetime_credits - wm.credits_at_warp_start) + float(btot) * 1000.0

	tele.write({
		"t": "snap", "sim_s": sim_s, "day": day, "phase": phase,
		"g_lvl": gm.get_level(), "p_lvl": pm.get_level(),
		"g_xp": gm.xp, "p_xp": pm.xp,
		"research_n": rm.unlocked_techs.size(),
		"credits": res.get_currency("credits"),
		"lifetime_credits": res.lifetime_credits,
		"warp_shards": wm.warp_shards, "total_warps": wm.total_warps,
		"progress_score": score, "buildings": btot,
		"slots_used": res.get_used_slots(), "slots_cap": res.get_max_slots(),
		"c_lvl": GameState.combat_manager.get_level(),
		"hp": GameState.shipyard_manager.current_hp,
		"max_hp": GameState.shipyard_manager.max_hp,
		"kills": combat_kills, "zone_diff": highest_zone_diff,
	})

	_check_milestones("gathering", gm.get_level())
	_check_milestones("processing", pm.get_level())

func _check_milestones(skill: String, lvl: int) -> void:
	for m in MILESTONES:
		var key := str(m)
		if lvl >= m and not ttm[skill].has(key):
			ttm[skill][key] = sim_s
			tele.write({"t": "event", "kind": "MILESTONE", "skill": skill, "level": m, "sim_s": sim_s})

func _write_summary(archetype: String, seed_v: int, days: int) -> void:
	var gm = GameState.gathering_manager
	var pm = GameState.processing_manager
	var rm = GameState.research_manager
	var wm = GameState.warp_manager
	var im = GameState.infrastructure_manager
	var res = GameState.resources
	var btot := 0
	for bid in im.buildings:
		btot += int(im.buildings[bid])

	tele.write({
		"t": "summary", "archetype": archetype, "seed": seed_v, "days": days,
		"sim_s_total": sim_s,
		"ttm": ttm,
		"time_to_first_warp": time_to_first_warp,
		"total_warps": wm.total_warps,
		"final_lifetime_credits": res.lifetime_credits,
		"research_count": rm.unlocked_techs.size(),
		"buildings": btot,
		"final_g_lvl": gm.get_level(), "final_p_lvl": pm.get_level(),
		"final_c_lvl": GameState.combat_manager.get_level(),
		"combat_kills": combat_kills, "highest_zone_diff": highest_zone_diff,
	})

# ---------------------------------------------------------------------------
func _make_policy(name: String):
	match name:
		"optimizer": return load("res://scripts/sim/policies/optimizer.gd").new()
		"casual": return load("res://scripts/sim/policies/casual.gd").new()
		"combat": return load("res://scripts/sim/policies/combat_rusher.gd").new()
	return null

func _schedule_for(name: String) -> Dictionary:
	var sessions := 3
	var length := 600.0
	match name:
		"optimizer": sessions = 5; length = 900.0   # engaged: 5×15min/day
		"casual":    sessions = 2; length = 300.0   # casual:  2×5min/day
		"combat":    sessions = 5; length = 900.0   # engaged combat schedule
	var gap := (86400.0 - float(sessions) * length) / float(sessions)
	return {"sessions": sessions, "len": length, "gap": gap}

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var idx := a.find("=")
			if idx > 2:
				args[a.substr(2, idx - 2)] = a.substr(idx + 1)

func _open_tele(archetype: String, seed_v: int) -> bool:
	tele = load("res://scripts/sim/sim_telemetry.gd").new()
	var out: String = str(args.get("out", ""))
	if out == "":
		DirAccess.make_dir_recursive_absolute("user://sim_out")
		out = "user://sim_out/%s_%d.jsonl" % [archetype, seed_v]
	else:
		# Ensure the parent dir of a custom --out path exists (per-batch folders).
		var d := out.get_base_dir()
		if d != "":
			DirAccess.make_dir_recursive_absolute(d)
	var ok: bool = tele.open_path(out)
	print("[SIM] telemetry -> %s  (user dir: %s)" % [out, OS.get_user_data_dir()])
	return ok

func _new_game(run_seed: int) -> void:
	GameState.hard_reset()
	GameState.resources.add_currency("credits", 100)
	GameState.resources.add_element("Dirt", 50)
	GameState.resources.add_element("Water", 50)
	seed(run_seed)

func _set_active(mgr) -> void:
	if GameState.active_manager and GameState.active_manager != mgr:
		GameState.active_manager.stop_action()
	GameState.active_manager = mgr
