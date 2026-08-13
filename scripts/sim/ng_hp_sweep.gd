extends Node
# SWEEP AN NG+ TRASH ENEMY'S HP AGAINST RULE B (v175)
#
# Rule B needs the clean COMMON set of a zone's own gear to manage >= 5 kills in a 180s
# window with no death. After the defence-ladder repair the NG+ commons survive but do
# not clear the bar: commonZ13 4, commonZ15 2, against 11-16 for the conventional zones.
#
# HP is the lever the owner picked for Z15, and it cannot be derived on paper: authored
# 10M (Z14) -> 17M (Z15) is x1.7, but the SPAWNED values are 7.69B -> 38.5B, a x5.0 step.
# Something past tier_rebase is scaling these (zone steepening), so the only honest way to
# pick a number is to move it and watch the kills.
#
# Reports both sides of every cell it touches, because cutting trash HP moves the maxed
# kits too and the tier-gain assertion has to survive it.
#
#   Godot --headless --path <root> res://scenes/ng_hp_sweep.tscn [--trials=N] [--eid=X]

const ZGC := preload("res://scripts/sim/zone_gate_check.gd")

var TRIALS := 7
var EID := "z15_blight_titan"
# Coarse by default. A cell that is only one kill short needs finer steps than this, so
# the list is settable: --mults=1.0,0.85,0.75,0.65
var MULTS: Array = [1.0, 0.6, 0.45, 0.35, 0.25]
# Supplying --amults= switches to a 2D atk x hp GRID and reports the COMMON kit only.
# Z14 needs that: an HP cut alone cannot stop it dying, and its defence cannot be raised
# because z14_armor is shared with the boss (Uncommon starts beating the Dissolution
# Tyrant), so survivability has to come out of the enemy's attack instead.
var AMULTS: Array = []
var _z

func _ready() -> void:
	await get_tree().process_frame
	if not GameState.sim_mode:
		print("[HPS] ABORT: sim_mode false")
		get_tree().quit(1)
		return
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		var s := str(a)
		if s.begins_with("--trials="):
			TRIALS = maxi(1, int(s.split("=")[1]))
		elif s.begins_with("--eid="):
			EID = s.split("=")[1]
		elif s.begins_with("--mults="):
			MULTS = []
			for part in s.split("=")[1].split(","):
				MULTS.append(float(part))
		elif s.begins_with("--amults="):
			AMULTS = []
			for part2 in s.split("=")[1].split(","):
				AMULTS.append(float(part2))
	GameState.set_process(false)
	_z = ZGC.new()
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager

	var e: Dictionary = cm.enemy_db.get(EID, {})
	if e.is_empty():
		print("[HPS] no such enemy: %s" % EID)
		get_tree().quit(1)
		return
	var zn: int = int(e.get("zone", 0))
	var zid: String = _z._zone_with_diff(cm, zn)
	var st: Dictionary = e.get("stats", {})
	var base_hp: float = float(st.get("hp", 0))
	print("[HPS] %s (zone %d, %s) spawned hp %.0f. Rule B: commons >= 5 kills, no death." % [
		EID, zn, zid, base_hp])
	print("[HPS] %-7s %14s | %-18s | %-14s | %-14s | %s" % [
		"hp x", "hp", "commonZ" + str(zn), "maxedZ" + str(zn - 1), "maxedZ" + str(zn), "verdict"])

	if not AMULTS.is_empty():
		var base_atk: float = float(st.get("atk", 0))
		print("[HPS] 2D GRID: atk x hp, COMMON kit only (kills / died). Need >= 5 and no death.")
		print("[HPS] spawned atk %.0f | %s" % [base_atk,
			"columns are hp x " + str(MULTS)])
		for am in AMULTS:
			var row := "[HPS] atk x%-5.2f (%12.0f) |" % [am, base_atk * am]
			for hm in MULTS:
				st["atk"] = base_atk * am
				st["hp"] = base_hp * hm
				var r: Dictionary = _cellof(sm, cm, rm, zn - 1, zid, EID, false)
				row += " %2d%-5s |" % [int(r["k"]), ("/DIED" if bool(r["d"]) else "")]
			print(row)
		st["atk"] = base_atk
		st["hp"] = base_hp
		get_tree().quit(0)
		return

	for m in MULTS:
		st["hp"] = base_hp * m
		var b: Dictionary = _cellof(sm, cm, rm, zn - 1, zid, EID, false)
		var a2: Dictionary = _cellof(sm, cm, rm, zn - 1, zid, EID, true)
		var c: Dictionary = _cellof(sm, cm, rm, zn, zid, EID, true)
		var b_farm: bool = int(b["k"]) >= 5 and not bool(b["d"])
		var tier: float = float(c["k"]) / maxf(0.1, float(a2["k"]))
		var ok: bool = b_farm and tier >= float(_z.GATE_MIN_SLOWDOWN)
		print("[HPS] %-7.2f %14.0f | %2d kills%-10s | %2d kills%-5s | %2d kills%-5s | %s" % [
			m, base_hp * m,
			int(b["k"]), (" DIED" if bool(b["d"]) else ""),
			int(a2["k"]), (" DIED" if bool(a2["d"]) else ""),
			int(c["k"]), (" DIED" if bool(c["d"]) else ""),
			("OK (tier x%.1f)" % tier) if ok else
				(("RULE B: %s" % ("dies" if bool(b["d"]) else "%d < 5 kills" % int(b["k"])))
					if not b_farm else "tier only x%.1f" % tier)])
	st["hp"] = base_hp
	get_tree().quit(0)


# Median kills over TRIALS, plus whether any window ended in a death.
func _cellof(sm, cm, rm, hull_n: int, zid: String, eid: String, maxed: bool) -> Dictionary:
	var ks: Array = []
	var died := false
	for _i in range(TRIALS):
		var r: Dictionary = _z._run(sm, cm, rm, hull_n, zid, eid, maxed)
		ks.append(int(r.get("kills", 0)))
		if bool(r.get("died", false)):
			died = true
	ks.sort()
	return {"k": ks[ks.size() / 2], "d": died}
