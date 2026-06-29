extends Node

# ============================================================================
# Progression Bot — headless AI player that drives the REAL managers from a
# fresh game to Z10-cleared, across 3 scenarios: A=0 warps, B=1, C=2.
# Reports per-zone clear time/steps + classifies any stall. Reuses the
# progression policy + the established DT=0.25 tick model. See _botspec.md.
#
# Launch (PowerShell), e.g.:
#   <godot> --headless --path <proj> res://scenes/progression_bot.tscn -- --scenario=A --maxsteps=400000
#   (omit --scenario to run A,B,C; omit --maxsteps for the full 4M cap)
# ============================================================================

const DT := 0.25
const HARD_GLOBAL_CAP := 4_000_000
const NO_PROGRESS_WINDOW := 40_000
const MAX_DEATHS_PER_FIGHT := 4
const HEARTBEAT := 20_000
const POLICY := preload("res://scripts/sim/policies/progression.gd")

var tele
var args := {}
var sim_s := 0.0
var step := 0
var max_steps := HARD_GLOBAL_CAP
var _save_json := ""
var _save_bak := ""

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	GameState.set_process(false)
	_parse_args()
	max_steps = int(args.get("maxsteps", str(HARD_GLOBAL_CAP)))
	_backup_save()
	_open_tele()
	var scen: String = str(args.get("scenario", ""))
	var scens: Array = [scen] if scen != "" else ["A", "B", "C"]
	for sc in scens:
		_run_scenario(sc, _warps_for(sc))
	_restore_save()
	if tele: tele.close()
	print("[BOT] all scenarios done.")
	get_tree().quit(0)

func _warps_for(sc: String) -> int:
	return {"A": 0, "B": 1, "C": 2}.get(sc, 0)

# ---------------------------------------------------------------------------
func _run_scenario(sc: String, target_warps: int) -> void:
	GameState.hard_reset()
	seed(1)
	GameState.combat_manager.boss_kills.clear()      # hard_reset does NOT clear these
	GameState.combat_manager.total_kills = 0
	GameState.game_settings["offline_combat"] = false
	var clean := _assert_clean(sc)

	var p = POLICY.new()
	p.target_warps = target_warps
	sim_s = 0.0
	step = 0
	var clears := {}
	var warps := []
	var last_sig := ""
	var last_prog := 0
	var stall = null
	print("[BOT] ===== scenario %s (target_warps=%d, clean=%s) =====" % [sc, target_warps, str(clean)])

	while true:
		p.manage_meta()
		if p._should_warp():
			warps.append(_do_warp(p, sc))
		var N: int = p._next_uncleared_zone()
		if N > 10:
			_emit_summary(sc, "Z10_CLEARED", clears, warps, null)
			return
		var d: Dictionary = p.decide_session()
		var res = _run_session(d, p, N)
		if String(d.get("kind", "")) == "combat" and p._tier_of(String(d.get("zone", ""))) == N:
			p.note_fight(N, res == "CLEARED")    # only count attempts on THIS zone's boss
		if res == "CLEARED" and not clears.has(N):
			clears[N] = {"sim_s": sim_s, "steps": step}
			_emit_clear(sc, N, p, d)

		var sig := _progress_sig(p)
		if sig != last_sig:
			last_sig = sig
			last_prog = step
		if step - last_prog > NO_PROGRESS_WINDOW or step > max_steps:
			var reason: String = p.classify_stall(N)
			stall = {"zone": N, "reason": reason, "sim_s": round(sim_s), "step": step,
				"capped": step > max_steps}
			tele.write({"evt": "STALL", "scenario": sc, "zone": N, "reason": reason,
				"sim_s": round(sim_s), "step": step, "g_lvl": GameState.gathering_manager.get_level(),
				"p_lvl": GameState.processing_manager.get_level(),
				"research": GameState.research_manager.unlocked_techs.size(),
				"credits": int(GameState.resources.get_currency("credits")),
				"last_gate": p.last_gate_reason})
			print("[BOT][STALL] %s Z%d : %s  (sim=%.2fh step=%d, last_gate=%s)" % [
				sc, N, reason, sim_s / 3600.0, step, p.last_gate_reason])
			_emit_summary(sc, "STALLED", clears, warps, stall)
			return

		if step % HEARTBEAT < 60:
			print("[BOT] scen=%s N=%d | sim=%.2fh step=%d | g%d p%d res%d | cr=%.0f cores=%d | ready=%s | gate=%s" % [
				sc, N, sim_s / 3600.0, step,
				GameState.gathering_manager.get_level(), GameState.processing_manager.get_level(),
				GameState.research_manager.unlocked_techs.size(),
				GameState.resources.get_currency("credits"), _core_count(),
				str(p._combat_ready(N)), p.last_gate_reason])

func _progress_sig(p) -> String:
	var farm_sum := 0
	for z in p.farm_kills.values():
		farm_sum += int(z)
	return "%d|%d|%d|%d|%d|%d|%d|%d|%s|%s" % [
		p.cleared.size(), GameState.gathering_manager.get_level(),
		GameState.processing_manager.get_level(), GameState.research_manager.unlocked_techs.size(),
		int(GameState.resources.get_currency("credits") / 100.0), _core_count(),
		farm_sum, p.drops_granted.size(), GameState.shipyard_manager.active_hull,
		str(GameState.warp_manager.total_warps)]

func _core_count() -> int:
	var n := 0
	for z in range(1, 11):
		n += int(GameState.resources.get_element_amount("Z%d_Core" % z))
	return n

# ---------------------------------------------------------------------------
func _run_session(d: Dictionary, p, N: int):
	var kind: String = String(d.get("kind", "noop"))
	if kind == "combat":
		return _run_boss_fight(String(d["zone"]), String(d["enemy"]), float(d.get("length", 60.0)),
			p, N, int(d.get("farm_to", 1)))
	if kind == "trash":
		return _run_trash(String(d["zone"]), String(d["enemy"]), float(d.get("length", 120.0)), p, N)
	if kind == "noop":
		if GameState.combat_manager.in_combat:
			GameState.combat_manager.retreat()
		_jump_offline(float(d.get("gap", 600.0)))
		return null
	# gather | process
	var mgr = d["mgr"]
	_set_active(mgr)
	mgr.start_action(String(d["id"]))
	var steps := int(float(d.get("length", 30.0)) / DT)
	for _i in range(steps):
		GameState.infrastructure_manager.process_tick(DT)
		GameState.bounty_manager.process_tick(DT)
		GameState.warp_manager.process_charge(DT)
		if GameState.active_manager:
			GameState.active_manager.process_tick(DT)
		sim_s += DT
		step += 1
	return null

func _run_trash(zid: String, trash_id: String, length: float, p, N: int) -> String:
	# Farm a specific trash mob (set_target_enemy makes spawn_enemy re-roll it, never
	# the boss) to accrue p.farm_kills[N] + real credits/loot/time. Drops are granted.
	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager
	if sm.current_hp <= 0 and not cm.in_combat:
		sm.repair_hull()
	if sm.energy_used > sm.energy_capacity:
		return "POWER_WALL"
	if not p._combat_ready(N):
		return "NOT_READY"
	_set_active(cm)
	cm.start_expedition(zid)
	cm.set_target_enemy(trash_id)
	var start_total := int(cm.total_kills)
	var steps := int(length / DT)
	var deaths := 0
	for _i in range(steps):
		GameState.infrastructure_manager.process_tick(DT)
		GameState.bounty_manager.process_tick(DT)
		GameState.warp_manager.process_charge(DT)
		if not cm.in_combat:
			deaths += 1
			if deaths > MAX_DEATHS_PER_FIGHT:
				break
			if sm.current_hp <= 0:
				sm.repair_hull()
			p._arm_for_zone(N)
			p._ensure_powered(N)
			cm.start_expedition(zid)
			cm.set_target_enemy(trash_id)
		cm.process_tick(DT)
		sim_s += DT
		step += 1
	var kills := int(cm.total_kills) - start_total
	p.farm_kills[N] = int(p.farm_kills.get(N, 0)) + kills
	cm.retreat()
	return "FARMED"

func _run_boss_fight(zid: String, boss_id: String, length: float, p, N: int, farm_to: int) -> String:
	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager
	if sm.current_hp <= 0 and not cm.in_combat:
		sm.repair_hull()
	if sm.energy_used > sm.energy_capacity:
		return "POWER_WALL"
	if not p._combat_ready(N):
		return "NOT_READY"
	_set_active(cm)
	cm.start_expedition(zid)
	cm.set_target_enemy(boss_id)
	if cm.current_enemy == null or String(cm.current_enemy.get("id", "")) != boss_id:
		cm.retreat()
		return "POWER_WALL"
	var start_kills := int(cm.boss_kills.get(boss_id, 0))
	var steps := int(length / DT)
	var deaths := 0
	for _i in range(steps):
		GameState.infrastructure_manager.process_tick(DT)
		GameState.bounty_manager.process_tick(DT)
		GameState.warp_manager.process_charge(DT)
		if not cm.in_combat:
			deaths += 1
			if deaths > MAX_DEATHS_PER_FIGHT or not p._combat_ready(N):
				cm.retreat()
				return "TIMEOUT"
			if sm.current_hp <= 0:
				sm.repair_hull()
			p._arm_for_zone(N); p._ensure_powered(N); p._ensure_ammo(N)
			cm.start_expedition(zid)
			cm.set_target_enemy(boss_id)
			if cm.current_enemy == null or String(cm.current_enemy.get("id", "")) != boss_id:
				cm.retreat()
				return "POWER_WALL"
		cm.process_tick(DT)
		sim_s += DT
		step += 1
		var k := int(cm.boss_kills.get(boss_id, 0))
		if k > start_kills:
			var tier: int = p._tier_of(zid)
			p.cleared[tier] = true
			if int(GameState.resources.get_element_amount("Z%d_Core" % tier)) >= farm_to:
				cm.retreat()
				return "CLEARED"
			start_kills = k
	cm.retreat()
	return "TIMEOUT"

func _do_warp(p, sc: String) -> Dictionary:
	var wm = GameState.warp_manager
	var pre_score: float = (GameState.resources.lifetime_credits - wm.credits_at_warp_start)
	var gains: int = wm.calculate_warp_gains()
	wm.execute_warp()
	var bought := []
	var order: Array = ["ENG_1", "ENG_4", "ENG_S1", "ENG_S2"]
	if wm.total_warps >= 2:
		order = ["REC_1", "CMB_1", "CMB_2", "ENG_1", "ENG_4", "CMB_S1", "ENG_S1", "ENG_S2"]
	for nid in order:
		var guard := 0
		while wm.can_purchase_node(nid) and guard < 50:
			if wm.purchase_node(nid):
				bought.append(nid)
			guard += 1
	p.cleared.clear()
	p._force_fresh_rearm = true
	var rec := {"evt": "warp", "scenario": sc,
		"total_warps": wm.total_warps, "shards": wm.warp_shards, "tier": wm.get_warp_tier(),
		"prod_mult": wm.get_production_multiplier(), "cmb_mult": wm.get_combat_multiplier(),
		"nodes": bought, "gains": gains, "score": pre_score, "sim_s": round(sim_s)}
	tele.write(rec)
	print("[BOT][WARP] %s -> warp #%d, +%d shards, tier %d, prod×%.2f cmb×%.2f, bought %s" % [
		sc, wm.total_warps, gains, wm.get_warp_tier(), wm.get_production_multiplier(),
		wm.get_combat_multiplier(), str(bought)])
	return rec

func _jump_offline(gap: float) -> void:
	GameState.process_offline_progress(min(gap, 86400.0))
	sim_s += gap

func _set_active(mgr) -> void:
	if GameState.active_manager and GameState.active_manager != mgr:
		GameState.active_manager.stop_action()
	GameState.active_manager = mgr

# ---------------------------------------------------------------------------
func _emit_clear(sc: String, N: int, p, d: Dictionary) -> void:
	var sm = GameState.shipyard_manager
	var wm = GameState.warp_manager
	var res = GameState.resources
	var rec := {"evt": "zone_clear", "scenario": sc, "zone": N, "boss": p._boss_id(N),
		"sim_s": round(sim_s), "steps": step,
		"credits": int(res.get_currency("credits")), "lifetime_credits": int(res.lifetime_credits),
		"g_lvl": GameState.gathering_manager.get_level(), "p_lvl": GameState.processing_manager.get_level(),
		"research": GameState.research_manager.unlocked_techs.size(),
		"hull": sm.active_hull, "atk_k": sm.attack_kinetic, "atk_e": sm.attack_energy,
		"atk_x": sm.attack_explosive, "max_hp": sm.max_hp,
		"energy_used": sm.energy_used, "energy_cap": sm.energy_capacity,
		"warps": wm.total_warps, "shards": wm.warp_shards, "tier": wm.get_warp_tier()}
	tele.write(rec)
	print("[CLEAR] %s Z%d %s @ sim=%.2fh step=%d | cr=%.0f lifeCr=%.0f | g%d p%d | hull=%s atkK=%d atkE=%d atkX=%d hp=%d | warps=%d shards=%.0f" % [
		sc, N, p._boss_id(N), sim_s / 3600.0, step, res.get_currency("credits"), res.lifetime_credits,
		GameState.gathering_manager.get_level(), GameState.processing_manager.get_level(),
		sm.active_hull, sm.attack_kinetic, sm.attack_energy, sm.attack_explosive, sm.max_hp,
		wm.total_warps, wm.warp_shards])

func _emit_summary(sc: String, result: String, clears: Dictionary, warps: Array, stall) -> void:
	var times := []
	var steps_arr := []
	for n in range(1, 11):
		if clears.has(n):
			times.append(round(float(clears[n]["sim_s"])))
			steps_arr.append(int(clears[n]["steps"]))
		else:
			times.append(-1); steps_arr.append(-1)
	tele.write({"evt": "summary", "scenario": sc, "result": result, "total_sim_s": round(sim_s),
		"total_steps": step, "zones_cleared": clears.size(), "zone_clear_times_s": times,
		"zone_clear_steps": steps_arr, "warps": warps.size(),
		"final_g_lvl": GameState.gathering_manager.get_level(),
		"final_p_lvl": GameState.processing_manager.get_level(),
		"final_research": GameState.research_manager.unlocked_techs.size(),
		"final_lifetime_credits": int(GameState.resources.lifetime_credits), "stall": stall})
	print("[BOT][SUMMARY] %s : %s | zones=%d/10 | sim=%.2fh steps=%d | g%d p%d | warps=%d | times(h)=%s" % [
		sc, result, clears.size(), sim_s / 3600.0, step,
		GameState.gathering_manager.get_level(), GameState.processing_manager.get_level(),
		warps.size(), str(times.map(func(t): return -1 if t < 0 else round(float(t) / 360.0) / 10.0))])

# ---------------------------------------------------------------------------
func _assert_clean(sc: String) -> bool:
	var ok := true
	if GameState.resources.lifetime_credits > 0.0: ok = false
	if GameState.combat_manager.boss_kills.size() > 0: ok = false
	if GameState.warp_manager.total_warps != 0: ok = false
	if _core_count() > 0: ok = false
	if not ok:
		print("[BOT][WARN] scenario %s not clean at start (state bleed!)" % sc)
	return ok

func _open_tele() -> void:
	tele = load("res://scripts/sim/sim_telemetry.gd").new()
	var out: String = str(args.get("out", ""))
	if out == "":
		DirAccess.make_dir_recursive_absolute("user://sim_out")
		out = "user://sim_out/progression.jsonl"
	tele.open_path(out)
	print("[BOT] telemetry -> %s (user dir: %s)" % [out, OS.get_user_data_dir()])

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var idx := a.find("=")
			if idx > 2:
				args[a.substr(2, idx - 2)] = a.substr(idx + 1)

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
