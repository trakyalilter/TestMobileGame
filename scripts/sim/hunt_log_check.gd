extends Node
# ============================================================================
# HUNT LOG CHECK (v177)
#
# Per-enemy kill ranks: 25/100/250/500/1000 kills -> 1..5 stars, +10% damage per
# star against THAT enemy. Asserted against real code paths:
#
#   1. star thresholds land exactly on the boundary (24 -> 0, 25 -> 1, ...)
#   2. the damage multiplier is 1.0 + 0.10 * stars, capped at 5 stars
#   3. the bonus is PER-ENEMY — grinding one enemy must not buff another
#   4. it actually reaches damage: a real fight kills measurably faster at 5
#      stars than at 0, with everything else identical
#   5. offline is not left behind: _offline_winnable prices the same bonus
#      (the v177 fleet audit found exactly that omission for the fleet mult)
#   6. it SURVIVES a warp and CLEARS on hard reset
#   7. save round-trip preserves the tally, and a pre-v177 save loads empty
#
#   Godot --headless --path <root> res://scenes/hunt_log_check.tscn
# ============================================================================

const BGC := preload("res://scripts/sim/boss_gearcheck.gd")
const DT := 0.1
const MAXT := 400.0
const TRIALS := 7
const TARGET := "z1_lunar_drone"

var _fails: Array = []
var _bgc

func _fail(msg: String) -> void:
	_fails.append(msg)

# Put lifetime_credits far enough ABOVE the last warp's snapshot that
# calculate_warp_gains() returns > 0. execute_warp() records
# credits_at_warp_start on the way out, so re-setting the same absolute figure
# scores zero progress and the next warp silently no-ops — which is exactly how
# the "second warp" case first came back vacuous.
func _arm_warp(wm) -> void:
	GameState.resources.lifetime_credits = float(wm.credits_at_warp_start) + 50_000_000.0

func _ready() -> void:
	await get_tree().process_frame
	if not GameState.sim_mode:
		print("[HUNT] ABORT: sim_mode false — refusing to run (this probe warps and hard-resets).")
		get_tree().quit(1)
		return
	GameState.set_process(false)
	_bgc = BGC.new()
	print("[HUNT] ============ HUNT LOG CHECK ============")

	_check_thresholds()
	_check_per_enemy()
	_check_damage_effect()
	_check_offline_priced()
	_check_persistence()
	_check_save_roundtrip()

	print("[HUNT] ----------------------------------------")
	for f in _fails:
		print("[HUNT] FAIL: %s" % f)
	print("[HUNT] RESULT: %s (%d failure(s))" % ["PASS" if _fails.is_empty() else "FAIL", _fails.size()])
	get_tree().quit(0 if _fails.is_empty() else 1)

# ---- 1 + 2. thresholds and multiplier ------------------------------------
func _check_thresholds() -> void:
	var cm = GameState.combat_manager
	GameState.hard_reset()
	var want := {0: 0, 24: 0, 25: 1, 99: 1, 100: 2, 249: 2, 250: 3,
		499: 3, 500: 4, 999: 4, 1000: 5, 5000: 5}
	# v177 owner curve: TOTAL bonus per rank, back-loaded — 2.5 / 5 / 10 / 15 / 25.
	# Spelled out here rather than derived from HUNT_STAR_BONUS, so a change to
	# that table has to be made deliberately in two places instead of silently
	# redefining the spec this guard is supposed to hold it to.
	var mult_for := {0: 1.0, 1: 1.025, 2: 1.05, 3: 1.10, 4: 1.15, 5: 1.25}
	var bad := 0
	for k in want:
		cm.enemy_kills[TARGET] = int(k)
		var st := int(cm.get_hunt_stars(TARGET))
		if st != int(want[k]):
			_fail("%d kills -> %d stars, spec says %d" % [int(k), st, int(want[k])])
			bad += 1
		var mult := float(cm.get_hunt_damage_mult(TARGET))
		var expect := float(mult_for[int(want[k])])
		if absf(mult - expect) > 0.0001:
			_fail("%d kills (%d stars) -> mult %.4f, spec says %.4f" % [int(k), st, mult, expect])
			bad += 1
	print("[HUNT] thresholds + back-loaded bonus ladder 2.5/5/10/15/25%%: %s" % (
		"OK" if bad == 0 else "%d wrong" % bad))

# ---- 3. per-enemy isolation ----------------------------------------------
func _check_per_enemy() -> void:
	var cm = GameState.combat_manager
	GameState.hard_reset()
	cm.enemy_kills[TARGET] = 1000
	var other := ""
	for eid in cm.enemy_db:
		if str(eid) != TARGET:
			other = str(eid)
			break
	if int(cm.get_hunt_stars(TARGET)) != 5:
		_fail("1000 kills on %s did not reach 5 stars" % TARGET)
	if int(cm.get_hunt_stars(other)) != 0 or absf(float(cm.get_hunt_damage_mult(other)) - 1.0) > 0.0001:
		_fail("grinding %s leaked a bonus onto %s — the bonus must be PER-ENEMY" % [TARGET, other])
	print("[HUNT] per-enemy isolation: %s at 5 stars, %s still 0" % [TARGET, other])

# ---- 4. the bonus reaches real damage ------------------------------------
func _check_damage_effect() -> void:
	var zero := _ttk_trials(0)
	var five := _ttk_trials(1000)
	# Enough trials to trust the mean — NOT all of them. Demanding 7/7 made this
	# case fail 3 runs in 5 on a single unlucky trial while the RATIO it exists to
	# measure never moved (1.51 / 1.53 / 1.57 / 1.60 across runs). A flapping guard
	# gets ignored, which is worse than no guard.
	var min_wins: int = TRIALS - 2
	if int(zero["wins"]) < min_wins or int(five["wins"]) < min_wins:
		_fail("damage trials unreliable (%d/%d at 0 stars, %d/%d at 5, need %d) — kit setup broken" % [
			int(zero["wins"]), TRIALS, int(five["wins"]), TRIALS, min_wins])
		return
	var t0: float = float(zero["mean"])
	var t5: float = float(five["mean"])
	var ratio: float = t0 / maxf(0.001, t5)
	# +25% damage does not cut TTK by exactly 1/1.25 (overkill, shield phase, the
	# per-swing floor), so accept a band — but a NO-OP would sit at 1.0 and a
	# wrong-sign wiring below it, which is what this really guards. Band recentred
	# from the v177 flat +50% ladder to the owner's back-loaded +25% max.
	if ratio < 1.08 or ratio > 1.55:
		_fail("5 stars changed TTK %.1fs -> %.1fs (x%.2f); expected a clear speedup in [1.08, 1.55]" % [
			t0, t5, ratio])
	print("[HUNT] damage effect: 0 stars %.1fs -> 5 stars %.1fs (x%.2f faster)" % [t0, t5, ratio])

func _setup_fight(kills: int) -> String:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.hard_reset()
	cm.boss_kills.clear()
	_bgc._unlock_research(rm, 1)
	_bgc._set_hull(sm, 1)
	_bgc._fill(sm, "battery", "z1_battery", 3, 1)
	_bgc._fill(sm, "weapon", "z1_kinetic", 0, 1)
	_bgc._ammo_kits(sm, "kinetic", 1)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	# Set the tally AFTER hard_reset (which clears it, correctly).
	cm.enemy_kills[TARGET] = kills
	cm.start_expedition("lunar_orbit")
	cm.set_target_enemy(TARGET)
	return TARGET

func _ttk_trials(kills: int) -> Dictionary:
	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager
	var wins := 0
	var ttks: Array = []
	for _i in range(TRIALS):
		var eid := _setup_fight(kills)
		if cm.current_enemy == null:
			continue
		# Stop on the KILL ITSELF (total_kills ticking), not on an in_combat /
		# current_enemy transition: trash respawns immediately, so those flags do
		# not mark the kill and the first cut of this probe timed something else
		# entirely — it read a 3% difference where offline measured the full 50%.
		var kills_before := int(cm.total_kills)
		var t := 0.0
		var killed := false
		while t < MAXT:
			# Kills accrue during the run and would drift the multiplier mid-measure;
			# re-pin every tick so the cell measures exactly the rank under test.
			cm.enemy_kills[eid] = kills
			cm.process_tick(DT)
			t += DT
			if int(cm.total_kills) > kills_before:
				killed = true
				break
			if sm.current_hp <= 0:
				break
		if killed:
			wins += 1
			ttks.append(t)
	var mean := 0.0
	for v in ttks:
		mean += float(v)
	mean = (mean / float(ttks.size())) if ttks.size() > 0 else 0.0
	return {"wins": wins, "mean": mean}

# ---- 5. offline prices the same bonus -------------------------------------
func _check_offline_priced() -> void:
	var cm = GameState.combat_manager
	_setup_fight(0)
	cm._offline_winnable()
	var bare: float = float(cm._offline_ttk)
	# Same kit, same fight — only the rank changes.
	cm.enemy_kills[TARGET] = 1000
	cm._offline_winnable()
	var starred: float = float(cm._offline_ttk)
	if bare <= 0.0 or starred <= 0.0:
		_fail("offline model returned no TTK (%.1f / %.1f) — case is vacuous" % [bare, starred])
		return
	var ratio: float = bare / maxf(0.001, starred)
	if absf(ratio - 1.25) > 0.05:
		_fail("offline TTK ratio %.3f at 5 stars, expected ~1.25 (+25%% dps). The hunt bonus is not priced offline — the fleet-audit defect, repeated." % ratio)
	print("[HUNT] offline priced: TTK %.1fs -> %.1fs (x%.2f)" % [bare, starred, ratio])

# ---- 6. warp persists, hard reset clears ---------------------------------
func _check_persistence() -> void:
	var cm = GameState.combat_manager
	var wm = GameState.warp_manager
	GameState.hard_reset()
	cm.enemy_kills[TARGET] = 300
	_arm_warp(wm)
	var before := int(wm.total_warps)
	wm.execute_warp()
	if int(wm.total_warps) <= before:
		_fail("execute_warp did not fire — persistence case is vacuous")
		return
	if int(cm.get_enemy_kills(TARGET)) != 300:
		_fail("warp changed the hunt tally: 300 -> %d (design: the record PERSISTS)" % int(cm.get_enemy_kills(TARGET)))
	elif absf(float(cm.get_hunt_damage_mult(TARGET)) - 1.10) > 0.0001:
		_fail("warp kept the kills but not the BONUS: mult %.2f, expected 1.10 at 3 stars" % float(cm.get_hunt_damage_mult(TARGET)))
	else:
		print("[HUNT] warp persistence: 300 kills held (%d stars, x%.2f dmg)" % [
			int(cm.get_hunt_stars(TARGET)), float(cm.get_hunt_damage_mult(TARGET))])

	# A genuine SECOND warp — no hard_reset in between. (The first cut put the
	# save/load test first, and its hard_reset zeroed total_warps, so the
	# "second warp" was really warp #1 again and proved nothing.)
	_arm_warp(wm)
	wm.execute_warp()
	if int(wm.total_warps) < 2:
		_fail("second execute_warp did not fire (total_warps=%d) — the case is vacuous" % int(wm.total_warps))
	elif int(cm.get_enemy_kills(TARGET)) != 300:
		_fail("a SECOND warp changed the tally: 300 -> %d" % int(cm.get_enemy_kills(TARGET)))
	else:
		print("[HUNT] second warp (total_warps=%d): 300 kills still held" % int(wm.total_warps))

	# The REAL player flow is warp -> autosave -> quit -> load, not warp alone.
	# Persistence in memory means nothing if the post-warp save drops it. Clear
	# ONLY the log (not via hard_reset, which would also wipe the warp state this
	# case just established) so the load has something to prove.
	var post: Dictionary = cm.get_save_data_manager()
	cm.enemy_kills = {}
	cm.load_save_data_manager(post)
	if int(cm.get_enemy_kills(TARGET)) != 300:
		_fail("the tally survived the warp but not the save/load AFTER it: 300 -> %d" % int(cm.get_enemy_kills(TARGET)))
	else:
		print("[HUNT] warp -> save -> load: 300 kills still held (x%.2f dmg)" % float(cm.get_hunt_damage_mult(TARGET)))
	GameState.hard_reset()
	if int(cm.get_enemy_kills(TARGET)) != 0:
		_fail("hard_reset left %d kills — a NEW GAME would start with +%d%% damage" % [
			int(cm.get_enemy_kills(TARGET)), int(cm.get_hunt_stars(TARGET)) * 10])
	else:
		print("[HUNT] hard reset clears the log: OK")

# ---- 7. save round-trip + old-save migration ------------------------------
func _check_save_roundtrip() -> void:
	var cm = GameState.combat_manager
	GameState.hard_reset()
	cm.enemy_kills[TARGET] = 137
	var blob: Dictionary = cm.get_save_data_manager()
	GameState.hard_reset()
	cm.load_save_data_manager(blob)
	if int(cm.get_enemy_kills(TARGET)) != 137:
		_fail("save round-trip lost the tally: 137 -> %d" % int(cm.get_enemy_kills(TARGET)))
	# A pre-v177 save has no key at all — must load empty, not crash or invent.
	blob.erase("enemy_kills")
	GameState.hard_reset()
	cm.load_save_data_manager(blob)
	if not cm.enemy_kills.is_empty():
		_fail("a pre-v177 save loaded a non-empty hunt log")
	print("[HUNT] save round-trip + pre-v177 migration: OK")
