extends Node
# ZONE 1 BOSS — WHAT THE MISSION CHAIN ACTUALLY BRINGS TO THE FIGHT.
#
# boss_gearcheck answers "does a tier-matched set of rarity R clear boss N", which is
# the right question for the gear ladder and the wrong question for the tutorial. The
# 2026-08-09 reorder (commit 4562435) moved the Rogue Architect ahead of the frigate,
# so Z1 is now the only mandatory fight in the game on the STARTING CORVETTE, and the
# thing the player is holding at that beat is not a tier-matched set. It is:
#
#   m015   2x z1_kinetic  "Mass Driver Mk.I"   COMMON (crafted)
#   m024   1x z1_shield   "Basic Shield"       COMMON (crafted)
#   m024a1 1x z1_armor    "Iron Plate"         COMMON (crafted)
#   m007   1x z1_engine   "Basic Thruster"     COMMON (crafted)
#   m005b  2x z1_battery  "Basic Battery"      COMMON (crafted)
#   m026d  ONE of the two weapons swapped for a RARE drop from m026c
#
# So the real question is a CHAIN cell sitting between boss_gearcheck's Common row
# (must lose) and its Rare row (must win). This probe measures that cell directly,
# on both hulls, alongside the four tier rows, so a tuning change can be judged
# against the fight the player is actually sent into.
#
#   Godot --headless --path <root> res://scenes/z1_boss_tune.tscn [--trials=N]
#
# Nine trials cannot resolve a ~50% win rate. Default is 21; give it more near a
# threshold. Prints a Wilson 95% interval so the noise is visible rather than implied.

const BGC := preload("res://scripts/sim/boss_gearcheck.gd")
const DT := 0.1
const MAXT := 600.0

var TRIALS := 21
var _bgc

func _ready() -> void:
	await get_tree().process_frame
	if not GameState.sim_mode:
		print("[Z1T] ABORT: sim_mode is false — this probe resets state and would touch the real save.")
		get_tree().quit(1)
		return
	for _a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if str(_a).begins_with("--trials="):
			TRIALS = maxi(1, int(str(_a).split("=")[1]))
	GameState.set_process(false)
	_bgc = BGC.new()

	var cm = GameState.combat_manager
	var e: Dictionary = cm.enemy_db.get("z1_boss_architect", {})
	var cn: Dictionary = e.get("charge_nuke", {})
	var atk: float = float((e.get("stats", {}) as Dictionary).get("atk", 0.0))
	print("[Z1T] Rogue Architect: hp=%d shield=%d atk=%.2f def=%d nuke=every_%d x%.3f" % [
		int((e.get("stats", {}) as Dictionary).get("hp", 0)),
		int((e.get("stats", {}) as Dictionary).get("max_shield", 0)),
		atk, int((e.get("stats", {}) as Dictionary).get("def", 0)),
		int(cn.get("every_n", 0)), float(cn.get("mult", 1.0))])
	# The two numbers that decide whether a corvette survives a telegraph.
	print("[Z1T]   normal swing %.1f dmg | NUKE swing %.1f dmg | dmg per nuke period %.1f" % [
		atk, atk * float(cn.get("mult", 1.0)),
		atk * (float(cn.get("every_n", 1)) - 1.0 + float(cn.get("mult", 1.0)))])
	print("[Z1T] %d trials per cell" % TRIALS)
	print("")

	# --sweep: try candidate charge_nuke mults before committing to one. The mult is
	# the smallest-blast-radius lever available — it is read only by _check_charge_nuke
	# for this one enemy, so nothing else in the game moves with it.
	var sweep := false
	for _a2 in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if str(_a2) == "--sweep":
			sweep = true
	if sweep:
		print("[Z1T] %-8s %9s %12s %12s %12s %12s" % [
			"mult", "nuke dmg", "CHAIN", "Common", "Uncommon", "Rare"])
		for cand in [4.2, 3.5, 3.0, 2.5, 2.0]:
			cn["mult"] = float(cand)
			var ch2: Dictionary = _cell(1, "chain")
			var c2: Dictionary = _cell(1, "r0")
			var u2: Dictionary = _cell(1, "r1")
			var ra2: Dictionary = _cell(1, "r2")
			print("[Z1T] %-8.2f %9.1f %12s %12s %12s %12s" % [
				float(cand), atk * float(cand),
				"%d/%d" % [int(ch2["w"]), TRIALS], "%d/%d" % [int(c2["w"]), TRIALS],
				"%d/%d" % [int(u2["w"]), TRIALS], "%d/%d" % [int(ra2["w"]), TRIALS]])
		cn["mult"] = float((e.get("charge_nuke", {}) as Dictionary).get("mult", 4.2))
		get_tree().quit(0)
		return

	# --grid: the mult sweep showed the spike is NOT what kills the chain kit (1/21 even
	# at mult 2.0, a 53-damage nuke). So the binding constraint is the sustained trade,
	# not the telegraph. Sweep the two stats that set it — boss HP (how long the trade
	# lasts) and boss ATK (how hard it hurts) — and find a cell where the Rare weapon
	# the chain hands the player is the thing that decides the fight.
	var grid := false
	for _a3 in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if str(_a3) == "--grid":
			grid = true
	if grid:
		var st: Dictionary = e.get("stats", {})
		var base_hp: float = float(st.get("hp", 960))
		var base_atk: float = float(st.get("atk", 26.667))
		cn["mult"] = 2.5   # the documented derivation, applied for the whole grid
		print("[Z1T] grid at nuke mult 2.5 (the DPS-preserving re-derivation of the")
		print("[Z1T] documented 'every 4th swing, x1.75' intent). Want: Common LOSES, CHAIN >=60%.")
		print("[Z1T] %-7s %-7s %7s %7s %9s %9s %9s %9s" % [
			"hp x", "atk x", "hp", "atk", "Common", "Uncmn", "CHAIN", "Rare"])
		for hm in [1.00, 0.90, 0.80]:
			for am in [0.72, 0.66, 0.60]:
				st["hp"] = base_hp * hm
				st["atk"] = base_atk * am
				var c3: Dictionary = _cell(1, "r0")
				var u3: Dictionary = _cell(1, "r1")
				var ch3: Dictionary = _cell(1, "chain")
				var ra3: Dictionary = _cell(1, "r2")
				var flag := ""
				if int(c3["w"]) == 0 and int(u3["w"]) == 0 and float(ch3["w"]) / float(TRIALS) >= 0.70:
					flag = "  <-- CANDIDATE"
				print("[Z1T] %-7.2f %-7.2f %7.0f %7.1f %9s %9s %9s %9s%s" % [
					hm, am, base_hp * hm, base_atk * am,
					"%d/%d" % [int(c3["w"]), TRIALS], "%d/%d" % [int(u3["w"]), TRIALS],
					"%d/%d" % [int(ch3["w"]), TRIALS], "%d/%d" % [int(ra3["w"]), TRIALS], flag])
		st["hp"] = base_hp
		st["atk"] = base_atk
		get_tree().quit(0)
		return

	print("[Z1T] %-26s %8s %10s %18s %9s" % ["loadout", "wins", "rate", "wilson 95%", "med TTK"])

	var rows := [
		["CHAIN kit  (corvette)", 1, "chain"],
		["CHAIN kit  (frigate)", 2, "chain"],
		["Common     (corvette)", 1, "r0"],
		["Uncommon   (corvette)", 1, "r1"],
		["Rare       (corvette)", 1, "r2"],
		["Legendary  (corvette)", 1, "r3"],
	]
	var out := {}
	for row in rows:
		var res: Dictionary = _cell(int(row[1]), str(row[2]))
		out[str(row[0]).strip_edges()] = res
		var lo: float = float(res["lo"])
		var hi: float = float(res["hi"])
		print("[Z1T] %-26s %4d/%-3d %9.1f%% %18s %9s" % [
			row[0], int(res["w"]), TRIALS, 100.0 * float(res["w"]) / float(TRIALS),
			"[%.0f%%, %.0f%%]" % [100.0 * lo, 100.0 * hi],
			("%.0fs" % float(res["ttk"]) if int(res["w"]) > 0 else "--")])

	print("")
	# The gear rule boss_gearcheck enforces, restated so a tuning pass cannot pass this
	# probe by making the boss trivial.
	var c: int = int((out["Common     (corvette)"] as Dictionary)["w"])
	var u: int = int((out["Uncommon   (corvette)"] as Dictionary)["w"])
	var ch: int = int((out["CHAIN kit  (corvette)"] as Dictionary)["w"])
	var fails := 0
	# COMMON MUST LOSE. This is the whole lesson of the m026c -> m026d -> m026e arc:
	# your crafted starting kit is not enough, go get a drop. If Common ever clears the
	# Rogue Architect, that arc is decoration.
	if c > 0:
		print("[Z1T] FAIL: full COMMON clears the boss %d/%d — the gear rule says Common must lose." % [c, TRIALS])
		fails += 1
	# UNCOMMON IS DELIBERATELY ALLOWED TO WIN HERE (v175 ruling, Z1 only).
	# boss_gearcheck applies a blanket "Common and Uncommon must both lose" to every
	# boss. At Z1 that rule is not satisfiable alongside the mission chain, and the
	# measurement is what settles it: the chain kit is Common armour/shield plus ONE
	# Rare weapon in one of the corvette's two weapon slots, and it measures 35/51
	# (69%, [55,80]) against full Uncommon's 32/51 (63%, [49,75]) — the same power
	# class, intervals overlapping almost entirely. So "the chain kit must clear its
	# own capstone" logically entails "Uncommon clears it too"; no boss stat separates
	# them, and 27 measured grid cells confirmed it (the chain kit never exceeded 38%
	# in any cell where Uncommon still lost).
	# Zone 1's lesson is "crafted gear is not enough, go get a drop" — not "get Rare
	# specifically". Any drop upgrade paying off is the correct tutorial lesson.
	if u > 0:
		print("[Z1T] note: full UNCOMMON clears %d/%d — allowed at Z1 by the v175 ruling," % [u, TRIALS])
		print("[Z1T]       because it is the same power class as the chain kit. Common losing is the gate.")
	var chain_rate: float = float(ch) / float(TRIALS)
	if chain_rate < 0.60:
		print("[Z1T] FAIL: the CHAIN kit clears only %d/%d (%.0f%%). The chain sends the player" % [
			ch, TRIALS, 100.0 * chain_rate])
		print("[Z1T]       into this fight with exactly that loadout, so it must clear comfortably.")
		fails += 1
	print("[Z1T] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _cell(hull_tier: int, mode: String) -> Dictionary:
	var wins := 0
	var ttks: Array = []
	var seen_hp := 0.0
	var deaths := 0
	var timeouts := 0
	for _i in range(TRIALS):
		var r: Dictionary = _fight(hull_tier, mode)
		seen_hp = float(r.get("ehp", 0.0))
		if str(r.get("r", "")) == "WIN":
			wins += 1
			ttks.append(float(r.get("ttk", 0.0)))
		elif str(r.get("r", "")) == "LOSS":
			deaths += 1
		elif str(r.get("r", "")) == "TIME":
			timeouts += 1
	ttks.sort()
	var med: float = (float(ttks[ttks.size() / 2]) if ttks.size() > 0 else 0.0)
	var iv: Array = _wilson(wins, TRIALS)
	# seen_hp is the boss HP the ENGINE actually spawned. If a --grid mutation did not
	# reach enemy_db (hard_reset rebuilding it, spawn_enemy copying from elsewhere),
	# every row would silently measure the same fight and the grid would read as noise.
	return {"w": wins, "ttk": med, "lo": iv[0], "hi": iv[1],
		"ehp": seen_hp, "died": deaths, "timeout": timeouts}


func _fight(hull_tier: int, mode: String) -> Dictionary:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.hard_reset()
	cm.boss_kills.clear()
	cm.total_kills = 0
	_bgc._unlock_research(rm, 1)
	_bgc._set_hull(sm, hull_tier)

	if mode == "chain":
		# Exactly the crafted kit, then ONE weapon slot upgraded to the m026d Rare.
		_bgc._fill(sm, "battery", "z1_battery", 0, 1)
		_bgc._fill(sm, "armor", "z1_armor", 0, 1)
		_bgc._fill(sm, "shield", "z1_shield", 0, 1)
		_bgc._fill(sm, "weapon", "z1_kinetic", 0, 1)
		var wslots: Array = _bgc._slots(sm, "weapon")
		if wslots.size() > 0:
			var rare := str(sm.generate_module_drop("z1_kinetic", 2, 1))
			if rare != "":
				sm.equip_module(wslots[0], rare, true)
	else:
		var rarity: int = int(str(mode).substr(1))
		_bgc._equip_gear(sm, 1, "kinetic", rarity, false, [])

	_bgc._ammo_kits(sm, "kinetic", 1)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	if sm.energy_used > sm.energy_capacity:
		return {"r": "UNPWR"}
	cm.start_expedition("lunar_orbit")
	cm.set_target_enemy("z1_boss_architect")
	if cm.current_enemy == null:
		return {"r": "NOENT"}
	var ehp: float = float(cm.enemy_max_hp)
	var t := 0.0
	while t < MAXT:
		_bgc._kit(sm, cm)
		cm.process_tick(DT)
		t += DT
		if int(cm.boss_kills.get("z1_boss_architect", 0)) > 0:
			return {"r": "WIN", "ttk": t, "ehp": ehp}
		if sm.current_hp <= 0 or not cm.in_combat:
			return {"r": "LOSS", "ehp": ehp}
	return {"r": "TIME", "ehp": ehp}


# Wilson score interval — a 7/21 and a 70/210 are both "33%" and only one of them
# means anything. Printing the interval keeps this probe from being read too hard.
func _wilson(w: int, n: int) -> Array:
	if n <= 0:
		return [0.0, 0.0]
	var z := 1.96
	var p: float = float(w) / float(n)
	var d: float = 1.0 + z * z / float(n)
	var centre: float = p + z * z / (2.0 * float(n))
	var margin: float = z * sqrt(p * (1.0 - p) / float(n) + z * z / (4.0 * float(n) * float(n)))
	return [maxf(0.0, (centre - margin) / d), minf(1.0, (centre + margin) / d)]
