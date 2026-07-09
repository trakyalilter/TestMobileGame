extends Node

# ============================================================================
# Player Bot — headless MISSION-FOLLOWING player sim (v135). Where
# progression_bot answers "is the Z-ladder structurally clearable" (grants
# gear/materials), this bot EARNS everything and answers "what does a player
# following Mission Control actually experience": per-mission funnel times,
# walls, dead time, session/offline cadence. Zero grants (enforced by
# tools/check_player_policy.ps1).
#
# Launch:
#   <godot> --headless --path <proj> res://scenes/player_bot.tscn -- \
#       --archetype=follower --seed=11 --days=14 --until=funnel_end
#   --drywalk            static chain-mappability check only, then quit
#   --archetype          follower|efficient|drifter|overnighter (default follower)
#   --until              funnel_end|first_boss|first_warp (default funnel_end)
#   --maxsteps           hard tick cap (default 2,000,000)
#   --out                telemetry path (default user://sim_out/player_<arch>_<seed>.jsonl)
# ============================================================================

const DT := 0.25
const HARD_CAP := 2_000_000
const NO_PROGRESS_WINDOW := 40_000
const MAX_DEATHS_PER_FIGHT := 2          # player-like: retry twice, then bounce
const HEARTBEAT := 20_000
const POLICY := preload("res://scripts/sim/policies/player_like.gd")
const MILESTONE_IDS := {"m005c": "first_powered", "m017": "first_fight",
	"m024b2": "kits_equipped", "m026b": "frigate", "m026e": "first_boss",
	"m030c": "destroyer", "m033c": "chain_end"}

var tele
var args := {}
var sim_s := 0.0
var step := 0
var day := 0
var max_steps := HARD_CAP
var _save_json := ""
var _save_bak := ""

var policy
var timeline := {}          # mid -> {act, comp, claim, direct, detour, blocked, offline, idx}
var _chain_idx := {}        # mid -> position in the walked chain
var milestones := {}
var violations := 0
var walls: Array = []
var _last_sig := ""
var _last_prog_step := 0
var _dead_streak := 0.0
var _session_dead := 0.0
var _stop_reason := ""
var _pump_accum := 0.0

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	GameState.set_process(false)
	_parse_args()
	max_steps = int(args.get("maxsteps", str(HARD_CAP)))
	if args.has("drywalk"):
		_do_drywalk()
		get_tree().quit(0)
		return
	if args.has("probe"):
		_do_probe(String(args.get("probe", "Res2")))
		get_tree().quit(0)
		return
	_backup_save()
	_open_tele()
	var arch := String(args.get("archetype", "follower"))
	var run_seed := int(args.get("seed", "11"))
	var days := int(args.get("days", "14"))
	var until := String(args.get("until", "funnel_end"))
	_run_one(arch, run_seed, days, until)
	_restore_save()
	if tele:
		tele.close()
	print("[PBOT] done.")
	get_tree().quit(0)

func _do_drywalk() -> void:
	GameState.hard_reset()
	GameState.combat_manager.boss_kills.clear()
	GameState.combat_manager.total_kills = 0
	var ma = load("res://scripts/sim/mission_actions.gd").new()
	var issues: Array = ma.dry_walk_chain()
	if issues.is_empty():
		print("[PBOT][DRYWALK] OK — every chain + goal step is mappable.")
	else:
		for i in issues:
			print("[PBOT][DRYWALK] ISSUE: %s" % i)
		print("[PBOT][DRYWALK] FAILED with %d issue(s)." % issues.size())

# Diagnostic: resolve a symbol's source on a fresh game (no grants) and print
# every intermediate — for debugging misrouted acquire chains.
func _do_probe(sym: String) -> void:
	GameState.hard_reset()
	GameState.combat_manager.boss_kills.clear()
	GameState.combat_manager.total_kills = 0
	var ma = load("res://scripts/sim/mission_actions.gd").new()
	print("[PROBE] sym=%s" % sym)
	print("[PROBE] available zones: %s" % str(GameState.combat_manager.get_available_zones().map(func(z): return z["id"])))
	print("[PROBE] source_for -> %s" % str(ma.source_for(sym)))
	print("[PROBE] _zone_dropping -> %s" % str(ma._zone_dropping(sym)))
	for zid in GameState.combat_manager.zones:
		var hit: Dictionary = ma._roster_drops(String(zid), sym)
		if not hit.is_empty():
			print("[PROBE] roster hit: %s" % str(hit))
	print("[PROBE] recipe_producing -> '%s'" % ma.recipe_producing(sym))

# ---------------------------------------------------------------------------
func _run_one(arch: String, run_seed: int, days: int, until: String) -> void:
	GameState.hard_reset()
	GameState.combat_manager.boss_kills.clear()   # hard_reset does NOT clear these
	GameState.combat_manager.total_kills = 0
	GameState.game_settings["offline_combat"] = false
	_assert_clean(arch)
	seed(run_seed)
	sim_s = 0.0
	step = 0
	day = 0
	timeline.clear()
	milestones.clear()
	walls.clear()
	violations = 0
	_last_sig = ""
	_last_prog_step = 0
	_stop_reason = ""
	_index_chain()

	policy = POLICY.new()
	policy.setup(arch, run_seed)
	tele.write({"t": "meta", "archetype": arch, "seed": run_seed, "days": days,
		"until": until, "dt": DT, "maxsteps": max_steps,
		"params": policy.params, "engine": Engine.get_version_info().get("string", "?")})
	print("[PBOT] ===== %s seed=%d days=%d until=%s =====" % [arch, run_seed, days, until])

	var p: Dictionary = policy.params
	var sessions_per_day := int(p["sessions"])
	var session_len := float(p["session_len"])

	# Day 0: one long continuous first sit (the real day-0 pattern).
	_run_day(0, [float(p["day0_len"])], until)
	# Days 1..N: archetype schedule; offline gaps fill 24h exactly.
	var d_i := 1
	while d_i <= days and _stop_reason == "":
		var plan: Array = []
		for _s in range(sessions_per_day):
			plan.append(session_len)
		_run_day(d_i, plan, until)
		d_i += 1
	if _stop_reason == "":
		_stop_reason = "days_cap"
	_emit_summary(arch, run_seed, until)

func _run_day(day_no: int, session_plan: Array, until: String) -> void:
	day = day_no
	var total_play := 0.0
	for s in session_plan:
		total_play += float(s)
	var gap := (86400.0 - total_play) / float(session_plan.size())
	for s_idx in range(session_plan.size()):
		if _stop_reason != "":
			return
		_run_session(day_no, s_idx, float(session_plan[s_idx]), until)
		if _stop_reason != "":
			return
		_offline_gap(gap)
	_emit_snap("day_end")

# ---------------------------------------------------------------------------
func _run_session(day_no: int, s_idx: int, length: float, until: String) -> void:
	policy.on_session_start()
	_session_dead = 0.0
	_dead_streak = 0.0
	var remaining := length
	var end_cause := "schedule"
	while remaining > 0.0 and _stop_reason == "":
		_pump()
		if _check_until(until) or step > max_steps:
			break
		var d: Dictionary = policy.decide_step()
		_drain_policy_events()
		var slice: float = min(float(d.get("length", 30.0)), remaining)
		var kind := String(d.get("kind", "idle"))
		match kind:
			"gather", "process":
				_run_task_slice(d, slice)
				_dead_streak = 0.0
			"combat", "combat_farm":
				_run_fight_slice(d, slice)
				_dead_streak = 0.0
			"warp":
				_do_warp()
				slice = 1.0
				_dead_streak = 0.0
			_:
				# idle/blocked — dead time with attribution. Background layers
				# still tick (infra/bounty run regardless — faithful).
				_run_dead_slice(d, slice)
		_attribute(d, slice)
		remaining -= slice
		if _dead_streak >= float(policy.params["boredom_s"]):
			end_cause = "boredom"
			break
		_check_overdue()
		if _watchdog():
			end_cause = "stall"
			break
	tele.write({"t": "session", "day": day_no, "idx": s_idx, "planned_s": length,
		"played_s": round(length - remaining), "dead_s": round(_session_dead),
		"end_cause": end_cause, "sim_s": round(sim_s)})

func _run_task_slice(d: Dictionary, slice: float) -> void:
	var mgr = d["mgr"]
	var aid := String(d["id"])
	if GameState.active_manager and GameState.active_manager != mgr:
		GameState.active_manager.stop_action()
	GameState.active_manager = mgr
	# gathering tracks current_action_id; processing tracks current_recipe_id —
	# restarting a running action would reset its progress, so check the right one.
	var cur := ""
	if mgr == GameState.processing_manager:
		cur = str(mgr.current_recipe_id)
	else:
		cur = str(mgr.current_action_id)
	if not mgr.is_active or cur != aid:
		mgr.start_action(aid)
	var ticks := int(slice / DT)
	for _i in range(ticks):
		GameState.infrastructure_manager.process_tick(DT)
		GameState.bounty_manager.process_tick(DT)
		if GameState.active_manager:
			GameState.active_manager.process_tick(DT)
		sim_s += DT
		step += 1
		_pump_maybe()
		# Self-stop re-decide: processing stops itself when inputs run out —
		# ticking a stopped manager is dead time, never productive play.
		if not mgr.is_active:
			return

func _run_dead_slice(d: Dictionary, slice: float) -> void:
	var ticks := int(slice / DT)
	for _i in range(ticks):
		GameState.infrastructure_manager.process_tick(DT)
		GameState.bounty_manager.process_tick(DT)
		sim_s += DT
		step += 1
		_pump_maybe()
	_session_dead += slice
	_dead_streak += slice
	tele.write({"t": "dead", "obj": String(d.get("obj", "")),
		"why": String(d.get("why", "?")), "s": slice, "sim_s": round(sim_s)})

# ---------------------------------------------------------------------------
# Combat with the full realism-assert layer.
# ---------------------------------------------------------------------------
func _run_fight_slice(d: Dictionary, slice: float) -> void:
	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager
	var zid := String(d["zone"])
	var eid := String(d["enemy"])
	var obj := String(d.get("obj", ""))
	var is_boss := bool(cm.enemy_db.get(eid, {}).get("is_boss", false))

	# CANT_FIRE three-way gate — the historical fake-DNF killer. Ammo/power
	# discipline is mission-taught by m016; a failure here is a SIM bug.
	if not policy.combat_ready():
		violations += 1
		_wall(obj, "CANT_FIRE", "bot_policy", "prep passed but combat_ready false (ammo/power)")
		_run_dead_slice({"obj": obj, "why": "CANT_FIRE recovery"}, min(slice, 30.0))
		return
	if is_boss and not policy.kit_invariant_ok():
		violations += 1
		_wall(obj, "kit_wall", "bot_policy", "boss fight without kit invariant (taught)")
		_run_dead_slice({"obj": obj, "why": "kit_wall recovery"}, min(slice, 30.0))
		return

	if GameState.active_manager and GameState.active_manager != cm:
		GameState.active_manager.stop_action()
	if not cm.in_combat or cm.current_zone == null:
		cm.start_expedition(zid)
		cm.set_target_enemy(eid)
		# Boss pin-assert: set_target_enemy bails SILENTLY on power/hp while
		# start_expedition already spawned a random enemy (false-wall trap).
		if cm.current_enemy == null or String(cm.current_enemy.get("id", "")) != eid:
			cm.retreat()
			_wall(obj, "power_wall", "game_gate", "target pin failed (used=%d cap=%d hp=%d)" % [
				sm.energy_used, sm.energy_capacity, sm.current_hp])
			return

	var fight_t0 := sim_s
	var deaths := 0
	var kits_used := 0
	var start_kills := int(cm.total_kills)
	var start_boss := int(cm.boss_kills.get(eid, 0))
	var kit_pct := float(policy.params["kit_pct"])
	var ticks := int(slice / DT)
	var result := "CONTINUE"
	for _i in range(ticks):
		GameState.infrastructure_manager.process_tick(DT)
		GameState.bounty_manager.process_tick(DT)
		if not cm.in_combat:
			# A no-combat tick right after an entry attempt is NOT a death —
			# it means start_expedition refused (locked zone / dead hull). The
			# resolver should never send us here; wall it, don't death-spiral.
			if sm.current_hp > 0 and cm.current_zone == null:
				violations += 1
				_wall(obj, "CANT_ENTER", "bot_policy",
					"expedition to %s refused (zone locked?)" % zid)
				result = "CANT_ENTER"
				break
			deaths += 1
			policy.note_fight_result(eid, false)
			if deaths > MAX_DEATHS_PER_FIGHT:
				result = "LOST"
				break
			var prep: Dictionary = policy._prep_for_fight(obj, eid)
			if not prep.is_empty():
				result = "NOT_READY"
				break
			cm.start_expedition(zid)
			cm.set_target_enemy(eid)
			if cm.current_enemy == null or String(cm.current_enemy.get("id", "")) != eid:
				cm.retreat()
				result = "PIN_FAIL"
				break
		# In-fight kit discipline (mission-taught by m024b2; the manager's 10s
		# in-combat cooldown bounds it — same buttons the player taps).
		if policy.kits_taught and cm.in_combat:
			if sm.current_hp < sm.max_hp * kit_pct \
					and sm.consumable_hull_slot != "" \
					and GameState.resources.get_element_amount(sm.consumable_hull_slot) >= 1 \
					and cm.consumable_cooldown <= 0.0:
				cm.use_manual_consumable("hull")
				kits_used += 1
			elif cm.player_max_shield > 0 and cm.player_shield < cm.player_max_shield * kit_pct \
					and sm.consumable_shield_slot != "" \
					and GameState.resources.get_element_amount(sm.consumable_shield_slot) >= 1 \
					and cm.consumable_cooldown <= 0.0:
				cm.use_manual_consumable("shield")
				kits_used += 1
		cm.process_tick(DT)
		sim_s += DT
		step += 1
		_pump_maybe()
		var won := false
		if is_boss:
			won = int(cm.boss_kills.get(eid, 0)) > start_boss
		else:
			won = int(cm.total_kills) > start_kills
		if won:
			policy.note_fight_result(eid, true)
			start_kills = int(cm.total_kills)
			start_boss = int(cm.boss_kills.get(eid, 0))
			# Mission satisfied? stop fighting (claim + move on).
			var mm = GameState.mission_manager
			if obj in mm.missions and bool(mm.missions[obj]["completed"]):
				result = "WIN"
				break
	if result == "CONTINUE":
		result = "SLICE_END"     # cross-session resume; loss only on real 0-HP defeat
	if result in ["WIN", "LOST"]:
		cm.retreat()
	var wtype := "none"
	for i in policy._slot_indices("weapon"):
		var w = sm.loadout.get(i, null)
		if w:
			wtype = policy._weapon_atype(String(w))
			break
	tele.write({"t": "fight", "enemy": eid, "boss": is_boss, "result": result,
		"dur_s": round(sim_s - fight_t0), "deaths": deaths, "kits": kits_used,
		"wtype": wtype, "hp_pct": round(100.0 * sm.current_hp / max(1.0, float(sm.max_hp))),
		"obj": obj, "sim_s": round(sim_s)})
	if result == "LOST":
		_wall(obj, "boss_losses", "game_gate", "%s lost %d attempts (wtype=%s, kits=%d)" % [
			eid, deaths, wtype, kits_used])

func _do_warp() -> void:
	var wm = GameState.warp_manager
	var gains := int(wm.calculate_warp_gains())
	wm.execute_warp()
	if not milestones.has("first_warp"):
		milestones["first_warp"] = round(sim_s)
	tele.write({"t": "warp", "gains": gains, "total_warps": wm.total_warps,
		"shards": wm.warp_shards, "sim_s": round(sim_s)})
	print("[PBOT][WARP] +%d shards at sim=%.1fh" % [gains, sim_s / 3600.0])

# ---------------------------------------------------------------------------
# Offline gap: ONE closed-form call, resource deltas reported.
# ---------------------------------------------------------------------------
func _offline_gap(gap: float) -> void:
	if _stop_reason != "":
		return
	policy.pre_offline()
	_drain_policy_events()
	var res = GameState.resources
	var cr0 := float(res.get_currency("credits"))
	var val0 := _inventory_value()
	var obj: Dictionary = GameState.mission_manager.get_active_objective()
	GameState.process_offline_progress(min(gap, 86400.0))
	sim_s += gap
	_pump()
	var mid := String(obj.get("id", ""))
	if timeline.has(mid):
		timeline[mid]["offline"] = float(timeline[mid].get("offline", 0.0)) + gap
	tele.write({"t": "offline", "gap_s": round(gap),
		"credits_delta": round(float(res.get_currency("credits")) - cr0),
		"value_delta": round(_inventory_value() - val0), "sim_s": round(sim_s)})

func _inventory_value() -> float:
	var res = GameState.resources
	var total := 0.0
	for sym in res.elements.keys():
		total += float(res.get_element_amount(sym)) * float(ElementDB.get_element_value(sym))
	return total

# ---------------------------------------------------------------------------
# Pump: sync + funnel timestamps + claims. Runs every ~1 sim-second.
# ---------------------------------------------------------------------------
func _pump_maybe() -> void:
	_pump_accum += DT
	if _pump_accum >= 1.0:
		_pump_accum = 0.0
		_pump()

func _pump() -> void:
	var mm = GameState.mission_manager
	mm.sync_progress()
	for mid in mm.active_missions:
		var m: Dictionary = mm.missions[mid]
		if not timeline.has(mid):
			timeline[mid] = {"act": round(sim_s), "comp": -1, "claim": -1,
				"direct": 0.0, "detour": 0.0, "blocked": 0.0, "offline": 0.0,
				"idx": int(_chain_idx.get(mid, -1))}
		if bool(m["completed"]) and int(timeline[mid]["comp"]) < 0:
			timeline[mid]["comp"] = round(sim_s)
	var claimed: Array = policy.pump_claims(sim_s)
	for mid in claimed:
		if timeline.has(mid):
			timeline[mid]["claim"] = round(sim_s)
			_emit_mission(String(mid))
		if MILESTONE_IDS.has(mid) and not milestones.has(MILESTONE_IDS[mid]):
			milestones[MILESTONE_IDS[mid]] = round(sim_s)
	_drain_policy_events()
	if step % HEARTBEAT < 4 and step > 0:
		var obj: Dictionary = GameState.mission_manager.get_active_objective()
		print("[PBOT] d%d sim=%.2fh step=%d | obj=%s | g%d p%d c%d | cr=%.0f | %s" % [
			day, sim_s / 3600.0, step, String(obj.get("id", "-")),
			GameState.gathering_manager.get_level(), GameState.processing_manager.get_level(),
			GameState.combat_manager.get_level(),
			GameState.resources.get_currency("credits"), String(policy.status)])

func _emit_mission(mid: String) -> void:
	var tl: Dictionary = timeline[mid]
	tele.write({"t": "mission", "mid": mid, "idx": int(tl["idx"]),
		"t_act": tl["act"], "t_comp": tl["comp"], "t_claim": tl["claim"],
		"direct_s": round(float(tl["direct"])), "detour_s": round(float(tl["detour"])),
		"blocked_s": round(float(tl["blocked"])), "offline_s": round(float(tl["offline"])),
		"day": day, "credits": int(GameState.resources.get_currency("credits")),
		"g": GameState.gathering_manager.get_level(),
		"p": GameState.processing_manager.get_level(),
		"c": GameState.combat_manager.get_level()})

func _attribute(d: Dictionary, slice: float) -> void:
	var mid := String(d.get("obj", ""))
	if mid == "" or not timeline.has(mid):
		return
	var attr := String(d.get("attr", "detour"))
	if attr in ["direct", "detour", "blocked"]:
		timeline[mid][attr] = float(timeline[mid].get(attr, 0.0)) + slice

func _drain_policy_events() -> void:
	for ev in policy.pending_events:
		var rec: Dictionary = (ev as Dictionary).duplicate()
		rec["sim_s"] = round(sim_s)
		tele.write(rec)
		if String(rec.get("t", "")) == "error":
			_wall(String(rec.get("mid", "")), String(rec.get("why", "error")),
				"game_gate", "policy hard error")
	policy.pending_events.clear()

func _wall(mid: String, code: String, suspect: String, evidence: String) -> void:
	var rec := {"t": "wall", "mid": mid, "code": code, "suspect": suspect,
		"evidence": evidence, "sim_s": round(sim_s), "day": day}
	walls.append(rec)
	tele.write(rec)
	print("[PBOT][WALL] %s %s (%s) — %s" % [mid, code, suspect, evidence])

# ---------------------------------------------------------------------------
func _watchdog() -> bool:
	var mm = GameState.mission_manager
	var claimed_n := 0
	for mid in mm.missions:
		if mm.missions[mid]["claimed"]:
			claimed_n += 1
	var obj: Dictionary = mm.get_active_objective()
	var sig := "%d|%s|%d|%d|%d|%d|%d|%s|%d" % [
		claimed_n, String(obj.get("id", "-")),
		GameState.gathering_manager.get_level(), GameState.processing_manager.get_level(),
		GameState.research_manager.unlocked_techs.size(),
		int(GameState.resources.get_currency("credits") / 100.0),
		int(GameState.combat_manager.total_kills),
		GameState.shipyard_manager.active_hull, GameState.warp_manager.total_warps]
	if sig != _last_sig:
		_last_sig = sig
		_last_prog_step = step
		return false
	if step - _last_prog_step > NO_PROGRESS_WINDOW:
		_stop_reason = "stall"
		_wall(String(obj.get("id", "-")), "stall", "game_gate",
			"no progress %d steps; status=%s" % [NO_PROGRESS_WINDOW, String(policy.status)])
		return true
	if step > max_steps:
		_stop_reason = "maxsteps"
		return true
	return false

# Overdue-objective tripwire: a livelock that keeps MOVING (credits rising,
# levels climbing) evades the fingerprint watchdog — the m019d build-verb bug
# sat invisible for 340 sim-hours with zero walls. One wall per mission whose
# active age exceeds the budget; the run continues (days_cap still ends it).
const OBJ_OVERDUE_S := 172800.0   # 48 sim-hours on one objective = suspicious
var _overdue_walled := {}

func _check_overdue() -> void:
	var obj: Dictionary = GameState.mission_manager.get_active_objective()
	var mid := String(obj.get("id", ""))
	if mid == "" or _overdue_walled.has(mid) or not timeline.has(mid):
		return
	if bool(obj.get("completed", false)):
		return
	var age: float = sim_s - float(timeline[mid].get("act", sim_s))
	if age > OBJ_OVERDUE_S:
		_overdue_walled[mid] = true
		_wall(mid, "mission:overdue", "unknown",
			"active %.0fh without completing; status=%s" % [age / 3600.0, String(policy.status)])

func _check_until(until: String) -> bool:
	var mm = GameState.mission_manager
	match until:
		"first_boss":
			if "m026e" in mm.missions and mm.missions["m026e"]["claimed"]:
				_stop_reason = "until:first_boss"
				return true
		"first_warp":
			if GameState.warp_manager.total_warps >= 1:
				_stop_reason = "until:first_warp"
				return true
		_:
			if "m033c" in mm.missions and mm.missions["m033c"]["claimed"]:
				_stop_reason = "until:funnel_end"
				return true
	return false

# ---------------------------------------------------------------------------
func _index_chain() -> void:
	_chain_idx.clear()
	var mm = GameState.mission_manager
	var mid := "m001"
	var i := 0
	var guard := 0
	while mid != "" and guard < 200:
		guard += 1
		if not mid in mm.missions or _chain_idx.has(mid):
			break
		_chain_idx[mid] = i
		i += 1
		mid = String(mm.missions[mid].get("next_mission", ""))

func _emit_snap(tag: String) -> void:
	var res = GameState.resources
	tele.write({"t": "snap", "tag": tag, "day": day, "sim_s": round(sim_s),
		"credits": int(res.get_currency("credits")),
		"lifetime": int(res.lifetime_credits),
		"g": GameState.gathering_manager.get_level(),
		"p": GameState.processing_manager.get_level(),
		"c": GameState.combat_manager.get_level(),
		"research": GameState.research_manager.unlocked_techs.size(),
		"hull": GameState.shipyard_manager.active_hull,
		"slots": res.get_used_slots(), "slots_max": res.get_max_slots(),
		"kills": int(GameState.combat_manager.total_kills)})

func _emit_summary(arch: String, run_seed: int, until: String) -> void:
	var mm = GameState.mission_manager
	var claimed_n := 0
	var deepest := ""
	var deepest_idx := -1
	for mid in mm.missions:
		if mm.missions[mid]["claimed"]:
			claimed_n += 1
			var idx := int(_chain_idx.get(mid, -1))
			if idx > deepest_idx:
				deepest_idx = idx
				deepest = String(mid)
	tele.write({"t": "summary", "archetype": arch, "seed": run_seed, "until": until,
		"result": _stop_reason, "deepest_mid": deepest, "deepest_idx": deepest_idx,
		"claimed": claimed_n, "sim_s": round(sim_s), "steps": step, "days": day,
		"milestones": milestones, "walls": walls.size(), "violations": violations,
		"g": GameState.gathering_manager.get_level(),
		"p": GameState.processing_manager.get_level(),
		"c": GameState.combat_manager.get_level(),
		"lifetime": int(GameState.resources.lifetime_credits)})
	print("[PBOT][SUMMARY] %s seed=%d: %s | deepest=%s (#%d) claimed=%d | sim=%.1fh days=%d | walls=%d violations=%d" % [
		arch, run_seed, _stop_reason, deepest, deepest_idx, claimed_n,
		sim_s / 3600.0, day, walls.size(), violations])

# ---------------------------------------------------------------------------
func _assert_clean(tag: String) -> void:
	var ok := true
	if GameState.resources.lifetime_credits > 0.0: ok = false
	if GameState.combat_manager.boss_kills.size() > 0: ok = false
	if GameState.warp_manager.total_warps != 0: ok = false
	if not ok:
		print("[PBOT][WARN] %s: state bleed after hard_reset!" % tag)

func _open_tele() -> void:
	tele = load("res://scripts/sim/sim_telemetry.gd").new()
	var out := String(args.get("out", ""))
	if out == "":
		DirAccess.make_dir_recursive_absolute("user://sim_out")
		out = "user://sim_out/player_%s_%s.jsonl" % [
			String(args.get("archetype", "follower")), String(args.get("seed", "11"))]
	tele.open_path(out)
	print("[PBOT] telemetry -> %s (user dir: %s)" % [out, OS.get_user_data_dir()])

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var idx := a.find("=")
			if idx > 2:
				args[a.substr(2, idx - 2)] = a.substr(idx + 1)
			else:
				args[a.substr(2)] = "1"

func _backup_save() -> void:
	if FileAccess.file_exists("user://savegame.json"):
		_save_json = FileAccess.get_file_as_string("user://savegame.json")
	if FileAccess.file_exists("user://savegame.bak"):
		_save_bak = FileAccess.get_file_as_string("user://savegame.bak")

func _restore_save() -> void:
	if _save_json != "":
		var f = FileAccess.open("user://savegame.json", FileAccess.WRITE)
		if f: f.store_string(_save_json); f.close()
	if _save_bak != "":
		var f2 = FileAccess.open("user://savegame.bak", FileAccess.WRITE)
		if f2: f2.store_string(_save_bak); f2.close()
