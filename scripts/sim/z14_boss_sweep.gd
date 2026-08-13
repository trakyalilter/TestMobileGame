extends Node
# RESTORE THE Z14 BOSS GEAR RULE AFTER THE DEFENCE REPAIR (v175)
#
# Repairing the Z14 defence ladder (z14_armor/shield x1.36) is what finally lets a clean
# COMMON set farm z14_toxin_sentinel, but the same armour is worn against the zone's boss,
# and boss_gearcheck's rule is Common AND Uncommon must LOSE while Rare+ WINS.
# After the repair: C 0/9, U 9/9 (median 276s), R 9/9 (180s), L 9/9 (148s).
#
# Uncommon needs to die and Rare needs to live, and there is a 1.53x window between their
# clear times to aim at. Boss ATTACK is the lever: raise it until a ~276s fight is fatal
# while a ~180s one is not. Sweeps it and prints the whole rarity row at each step so the
# Rare/Legendary side is visible rather than assumed.
#
#   Godot --headless --path <root> res://scenes/z14_boss_sweep.tscn [--trials=N]

const BGC := preload("res://scripts/sim/boss_gearcheck.gd")

var TRIALS := 9
var _b

func _ready() -> void:
	await get_tree().process_frame
	if not GameState.sim_mode:
		print("[Z14B] ABORT: sim_mode false")
		get_tree().quit(1)
		return
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if str(a).begins_with("--trials="):
			TRIALS = maxi(1, int(str(a).split("=")[1]))
	GameState.set_process(false)
	_b = BGC.new()
	_b.TRIALS = TRIALS
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager

	var eid := "z14_boss_dissolution_tyrant"
	var e: Dictionary = cm.enemy_db.get(eid, {})
	var st: Dictionary = e.get("stats", {})
	var base: float = float(st.get("atk", 0))
	var b := {"zone": "the_dissolution", "eid": eid, "n": 14, "e": e, "weak": _b._weak(e)}

	print("[Z14B] %s spawned atk %.0f, %d trials." % [eid, base, TRIALS])
	print("[Z14B] Rule: Common AND Uncommon must LOSE, Rare or Legendary must WIN >= 60%%.")
	print("[Z14B] %-8s %12s | %-12s %-12s %-12s %-12s | %s" % [
		"atk x", "atk", "Common", "Uncommon", "Rare", "Legend", "verdict"])

	for m in [1.00, 1.25, 1.45, 1.65]:
		st["atk"] = base * m
		var c0: Dictionary = _b._trials(sm, cm, rm, b, 14, b["weak"], 0)
		var c1: Dictionary = _b._trials(sm, cm, rm, b, 14, b["weak"], 1)
		var c2: Dictionary = _b._trials(sm, cm, rm, b, 14, b["weak"], 2)
		var c3: Dictionary = _b._trials(sm, cm, rm, b, 14, b["weak"], 3)
		var c_ok: bool = float(c0["w"]) <= 0.10 * float(TRIALS)
		var u_ok: bool = float(c1["w"]) <= 0.10 * float(TRIALS)
		var win: bool = float(c2["w"]) >= 0.60 * float(TRIALS) or float(c3["w"]) >= 0.60 * float(TRIALS)
		print("[Z14B] %-8.2f %12.0f | %-12s %-12s %-12s %-12s | %s" % [
			m, base * m, _b._cell(c0), _b._cell(c1), _b._cell(c2), _b._cell(c3),
			"OK" if (c_ok and u_ok and win) else
				("Uncommon still wins" if not u_ok else
					("Common wins" if not c_ok else "Rare+ can no longer win"))])
	st["atk"] = base
	get_tree().quit(0)
