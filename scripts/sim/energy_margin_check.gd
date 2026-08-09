extends Node
# SHIP ENERGY MARGIN — how much headroom does a FULL loadout actually have?
#
# v110 made batteries the only energy source and sized them so, per hull tier,
# "full battery slots exactly power full consumer slots". If that is literally
# exact, any capacity cut makes a full ship UNPOWERED — set_target_enemy blocks
# combat entry outright when energy_used > energy_capacity.
#
# The +10% basic_engineering hub bonus was removed in v174 after this measured
# the margin at ~2x draw on every tier. This now ASSERTS that margin: a full
# tier-matched loadout on plain COMMON batteries must fit inside capacity with
# room to spare, so a future capacity or draw change cannot quietly push a
# legitimate ship under the line and block it from combat.
#
#   Godot --headless --path <root> res://scenes/energy_margin_check.tscn

const BGC := preload("res://scripts/sim/boss_gearcheck.gd")

var _bgc

func _ready() -> void:
	await get_tree().process_frame
	if not GameState.sim_mode:
		print("[NRG] ABORT: sim_mode false")
		get_tree().quit(1)
		return
	GameState.set_process(false)
	_bgc = BGC.new()

	var sm = GameState.shipyard_manager
	var rm = GameState.research_manager

	# A full ship must not merely fit — it must fit with this much headroom, so a
	# player who swaps one module for a heavier one is not instantly locked out.
	var MIN_RATIO := 1.25
	var fails := 0
	print("[NRG] full tier-matched loadout, COMMON batteries. Require cap >= draw x %.2f" % MIN_RATIO)
	print("[NRG] %-4s %-12s %10s %10s %8s %7s" % ["zone", "hull", "draw", "cap", "margin", "ratio"])

	for z in range(1, 11):
		GameState.hard_reset()
		_bgc._unlock_research(rm, z)
		_bgc._set_hull(sm, z)
		# boss_gearcheck fills battery slots at LEGENDARY, which over-states capacity
		# by the rarity roll. The honest floor is a player running plain COMMON
		# batteries with everything else tier-matched, so measure that.
		_bgc._equip_gear(sm, z, "kinetic", 3, false, [])
		for slot in _bgc._slots(sm, "battery"):
			var cid := String(sm.generate_module_drop("z%d_battery" % clampi(z, 1, 10), 0, z))
			if cid != "":
				sm.equip_module(slot, cid, true)
		sm.recalc_stats()
		var draw: int = int(sm.energy_used)
		var cap: int = int(sm.energy_capacity)
		var ratio: float = float(cap) / maxf(1.0, float(draw))
		var bad: bool = ratio < MIN_RATIO
		if bad:
			fails += 1
		print("[NRG] Z%-3d %-12s %10d %10d %+8d %6.2fx%s" % [
			z, String(sm.active_hull).substr(0, 12), draw, cap, cap - draw, ratio,
			"  <-- TOO TIGHT" if bad else ""])

	print("[NRG] RESULT: %s (%d tier(s) under %.2fx)" % [
		"PASS" if fails == 0 else "FAIL", fails, MIN_RATIO])
	get_tree().quit(0 if fails == 0 else 1)
