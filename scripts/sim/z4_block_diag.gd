extends Node
# IS THE Z3->Z4 "BLOCK" A REAL WALL, OR A 5-TRIAL SAMPLING ARTIFACT? (v175)
#
# zone_gate_check reports BLOCK on Z3->Z4: `commonZ4 15k/DIED`. Rule B says a clean
# Zone N+1 COMMON set must farm Zone N+1 e3/e4, and `died_any` goes true if ANY of its
# TRIALS=5 windows ends in a death. So a death RATE of a few percent is enough to flip
# the whole cell to BLOCK a noticeable fraction of runs.
#
# That matters here more than usual, because z4_glacial_drone's stat line is not a
# guess. Its comment block carries a 108-trials-per-cell sweep (v147) reporting the
# clean Common death rate at 1-3 per 108 windows and concluding the discrimination
# ratio is MAXIMAL at the shipped value, decaying on every axis; it says in as many
# words "Fix the affix axis, not this stat line". v151 then raised its EHP x1.75 and
# measured 0 deaths over 21 trials. Nerfing atk against that on the strength of one
# 5-trial DIED would be the exact mistake this repo keeps writing guards to avoid.
#
# So measure the death rate directly, with enough windows to tell 3% from 40%.
#   * a few percent   -> the BLOCK is sampling noise; fix the GUARD, not the enemy
#   * tens of percent -> the wall is real and the stat line is in play
#
# Calls zone_gate_check's OWN _run() rather than a copy. The first version of this
# probe hand-rolled the window loop and called `_kit()`, which lives on boss_gearcheck,
# not here — so it threw "Nonexistent function '_kit'" on every one of 1800 ticks per
# window and took over an hour to not finish. Reusing _run() also inherits its
# early-exit on death, which is most of the speed.
#
#   Godot --headless --path <root> res://scenes/z4_block_diag.tscn [--trials=N]

const ZGC := preload("res://scripts/sim/zone_gate_check.gd")

var TRIALS := 21
var _z

func _ready() -> void:
	await get_tree().process_frame
	if not GameState.sim_mode:
		print("[Z4D] ABORT: sim_mode false")
		get_tree().quit(1)
		return
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if str(a).begins_with("--trials="):
			TRIALS = maxi(1, int(str(a).split("=")[1]))
	GameState.set_process(false)
	_z = ZGC.new()
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager

	var zid: String = _z._zone_with_diff(cm, 4)
	var eid := str((cm.zones[zid].get("enemies", []) as Array)[2])
	# enemy_db is ALREADY rebased at runtime, so this is the SPAWNED number, not the
	# source literal. tier_rebase(4) = (3.75/2.2)^3 = 4.952, so the authored value is
	# whatever this divided by that comes to — derived rather than hardcoded, because a
	# hardcoded literal in a probe label goes stale the first time the stat is retuned
	# (this one already did).
	var st: Dictionary = cm.enemy_db[eid].get("stats", {})
	var spawned: float = float(st.get("atk", 0))
	print("[Z4D] %s spawned atk %.0f (source literal ~%.3f x tier_rebase 4.952)" % [
		eid, spawned, spawned / 4.952])
	print("[Z4D] clean COMMON Z4, %d windows. Counting DEATHS (zone_gate_check's own _run)." % TRIALS)

	var deaths := 0
	var kills: Array = []
	for i in range(TRIALS):
		var r: Dictionary = _z._run(sm, cm, rm, 3, zid, eid, false)
		kills.append(int(r.get("kills", 0)))
		if bool(r.get("died", false)):
			deaths += 1
		if (i + 1) % 7 == 0:
			print("[Z4D]   ... %d/%d windows, %d death(s)" % [i + 1, TRIALS, deaths])
	kills.sort()
	var rate: float = float(deaths) / float(TRIALS)
	var iv: Array = _wilson(deaths, TRIALS)
	print("[Z4D] DEATHS %d/%d = %.1f%%   Wilson95 [%.0f%%, %.0f%%]   median kills %d" % [
		deaths, TRIALS, 100.0 * rate, 100.0 * float(iv[0]), 100.0 * float(iv[1]),
		int(kills[kills.size() / 2])])
	var p_block: float = 1.0 - pow(1.0 - rate, 5.0)
	print("[Z4D] at that rate a TRIALS=5 boolean cell reports BLOCK %.0f%% of runs." % [100.0 * p_block])
	print("[Z4D] v147 measured 1-3/108 (0.9-2.8%%) and v151 measured 0/21 at this stat line.")
	get_tree().quit(0)


func _wilson(w: int, n: int) -> Array:
	if n <= 0:
		return [0.0, 0.0]
	var z := 1.96
	var p: float = float(w) / float(n)
	var d: float = 1.0 + z * z / float(n)
	var centre: float = p + z * z / (2.0 * float(n))
	var margin: float = z * sqrt(p * (1.0 - p) / float(n) + z * z / (4.0 * float(n) * float(n)))
	return [maxf(0.0, (centre - margin) / d), minf(1.0, (centre + margin) / d)]
