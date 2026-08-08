extends Node
# Z10 CAPSTONE GATE DIAGNOSTIC (one-shot, not a guard).
#
# boss_gearcheck says Uncommon beats z10_boss_leviathan 9/9 at ~262s when the
# rule is that Uncommon must LOSE. Before ruling on a fix I need to know WHICH
# axis the gate turns on, because the answer changes the lever:
#   - if Uncommon wins a DPS race the boss survives, raise boss HP;
#   - if Uncommon wins by surviving long enough, raise boss ATK.
# Reports, per rarity: win rate, TTK, and for losses whether the player DIED or
# ran out the clock, plus how long the player stayed alive.
#
#   Godot --headless --path <root> res://scenes/z10_gate_diag.tscn

const BGC := preload("res://scripts/sim/boss_gearcheck.gd")
const TRIALS := 9
const DT := 0.1
const MAXT := 1500.0
const RNAME := ["Common", "Uncommon", "Rare", "Legendary"]

var _bgc

func _ready() -> void:
	await get_tree().process_frame
	if not GameState.sim_mode:
		print("[Z10] ABORT: sim_mode false — refusing to run against a real save.")
		get_tree().quit(1)
		return
	GameState.set_process(false)
	_bgc = BGC.new()          # reuse its gear/ammo/kit helpers verbatim
	add_child(_bgc)
	_bgc.set_process(false)

	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager
	var rm = GameState.research_manager
	var e: Dictionary = cm.enemy_db["z10_boss_leviathan"]
	print("[Z10] boss hp=%d atk=%d (post-rebase, as shipped)" % [
		int(e["stats"]["hp"]), int(e["stats"].get("atk", 0))])
	print("[Z10] %-11s %-6s %-9s %-9s %-9s" % ["rarity", "wins", "meanTTK", "deaths", "aliveAtLoss"])

	for rarity in range(4):
		var wins := 0
		var ttk_sum := 0.0
		var deaths := 0
		var timeouts := 0
		var alive_sum := 0.0
		var left_sum := 0.0
		for _i in range(TRIALS):
			var r := _fight(sm, cm, rm, e, rarity)
			match String(r["r"]):
				"WIN":
					wins += 1
					ttk_sum += float(r["t"])
				"DEAD":
					deaths += 1
					alive_sum += float(r["t"])
					left_sum += float(r["left"])
				_:
					timeouts += 1
					left_sum += float(r["left"])
		var losses: int = deaths + timeouts
		print("[Z10] %-11s %d/%-4d %-9s %-9s %s" % [
			RNAME[rarity], wins, TRIALS,
			("%.0fs" % (ttk_sum / maxf(1.0, float(wins)))) if wins > 0 else "-",
			"%d died %d timeout" % [deaths, timeouts],
			("%.0fs (boss %.0f%% left)" % [alive_sum / maxf(1.0, float(deaths)), left_sum / maxf(1.0, float(losses))]) if losses > 0 else "-"])

	print("[Z10] done")
	get_tree().quit(0)


func _fight(sm, cm, rm, e: Dictionary, rarity: int) -> Dictionary:
	# Same per-fight teardown boss_gearcheck uses. Without clearing boss_kills the
	# first win leaks into every later trial as an instant free win — that is how
	# the first draft of this probe reported Rare and Legendary at 0s TTK.
	GameState.hard_reset()
	cm.boss_kills.clear()
	cm.total_kills = 0
	_bgc._unlock_research(rm, 10)
	_bgc._set_hull(sm, 10)
	_bgc._equip_gear(sm, 10, "explosive", rarity, false, [])
	_bgc._ammo_kits(sm, "explosive", 10)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	cm.start_expedition("sector_epsilon")
	cm.set_target_enemy("z10_boss_leviathan")
	if cm.current_enemy == null:
		return {"r": "NOENT", "t": 0.0, "left": 100.0}
	var t := 0.0
	while t < MAXT:
		_bgc._kit(sm, cm)
		cm.process_tick(DT)
		t += DT
		if int(cm.boss_kills.get("z10_boss_leviathan", 0)) > 0:
			return {"r": "WIN", "t": t, "left": 0.0}
		if sm.current_hp <= 0 or not cm.in_combat:
			return {"r": "DEAD", "t": t, "left": 100.0 * float(cm.enemy_hp) / maxf(1.0, float(cm.enemy_max_hp))}
	return {"r": "TIME", "t": t, "left": 100.0 * float(cm.enemy_hp) / maxf(1.0, float(cm.enemy_max_hp))}
