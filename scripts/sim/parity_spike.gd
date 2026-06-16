extends Node

# ============================================================================
# INFRA <-> ACTIVE PARITY SPIKE — does always-on infrastructure stay a healthy
# FRACTION of active crafting, or does the uncapped Recursion lever
# (infrastructure_focus, +5%/lvl building yield) let idle infra out-produce
# active and kill the core loop?
#
# Measures ACTUAL Steel produced over a fixed sim window on each side
# (bypasses the 3 disagreeing display-rate paths), at a sweep of Recursion
# infrastructure_focus levels. Target (sanity checklist): infra = 30-70% of
# active. >=100% means active crafting is obsolete.
#
#   ACTIVE = one smelt_steel_oxygen action (the foreground choice)
#   INFRA  = N auto_smelters running in the background
#
# Run: tools/run_sim.ps1 -Scene "res://scenes/parity_spike.tscn"
# ============================================================================

const DT := 0.25
const WINDOW_S := 600.0                 # measure produced Steel over 10 sim-min
const SMELTERS := 10                    # the checklist's scenario
const RECURSION_LEVELS := [0, 10, 30, 60, 100]
const PROC_LEVEL := 90                  # high enough that eng_scale maxes (~x3) + recipe unlocked

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	GameState.set_process(false)
	GameState.hard_reset()
	seed(777)
	_unlock()

	var im = GameState.infrastructure_manager
	var pm = GameState.processing_manager
	im.energy_efficiency = 1.0            # full grid (isolate yield math from power)

	# Active baseline is constant across Recursion (building_yield_mult is infra-
	# only), so measure it once.
	var active_per_min: float = _measure_active()

	print("[PARITY] active smelt_steel_oxygen = %.0f Steel/min (proc_lvl %d)" % [active_per_min, PROC_LEVEL])
	print("[PARITY] infra = %d auto_smelters. Target: infra 30-70%% of active; >=100%% = active dead." % SMELTERS)
	print("[PARITY] -------------------------------------------------------------")
	print("[PARITY] recursionLvl | bldgYieldMult | infra Steel/min | infra/active")
	for lvl in RECURSION_LEVELS:
		GameState.research_manager.repeatable_techs["infrastructure_focus"] = int(lvl)
		var bym: float = GameState.research_manager.get_efficiency_bonus("building_yield_mult")
		var infra_per_min: float = _measure_infra()
		var ratio: float = (infra_per_min / active_per_min * 100.0) if active_per_min > 0.0 else 0.0
		var flag: String = ""
		if ratio >= 100.0: flag = "  <-- ACTIVE OBSOLETE"
		elif ratio > 70.0: flag = "  <-- above target band"
		print("[PARITY] %d | x%.2f | %.0f | %.0f%%%s" % [int(lvl), 1.0 + bym, infra_per_min, ratio, flag])
	print("[PARITY] done")
	get_tree().quit(0)

func _unlock() -> void:
	var rm = GameState.research_manager
	# Unlock the techs that gate the recipe + the infra yield levers.
	for t in ["basic_engineering", "materials_science", "smelting", "blast_furnace",
			"automated_smelting", "oxygen_blast_furnace", "metallurgy_advanced", "combustion"]:
		if t in rm.tech_tree and not (t in rm.unlocked_techs):
			rm.unlocked_techs.append(t)
	# Tier-appropriate engineering level so eng_scale (log, cap x3) is near max.
	GameState.processing_manager.level = PROC_LEVEL
	# Bottomless INPUTS so neither side ever starves (Steel is the measured
	# output — left out so deltas read off a clean base, not off 1e9).
	for sym in ["Fe", "C", "O", "Mn"]:
		GameState.resources.add_element(sym, 1000000000.0)
	# Bottomless ENERGY buffer so the power grid never throttles infra — we are
	# measuring YIELD parity, not the power balance (auto_smelters draw 120 each
	# with no generator; without this the grid collapses efficiency to 0).
	GameState.resources.set_max_energy(1.0e15)

func _steel() -> float:
	return GameState.resources.get_element_amount("Steel")

func _measure_active() -> float:
	var pm = GameState.processing_manager
	# Ensure no buildings interfere; run only the active recipe.
	GameState.active_manager = pm
	pm.start_action("smelt_steel_oxygen")
	var before: float = _steel()
	var steps: int = int(WINDOW_S / DT)
	for _i in range(steps):
		pm.process_tick(DT)
	var gained: float = _steel() - before
	pm.stop_action()
	return gained / (WINDOW_S / 60.0)

func _measure_infra() -> float:
	var im = GameState.infrastructure_manager
	im.buildings = {"auto_smelter": SMELTERS}
	GameState.resources.add_energy(1.0e15)
	im.process_tick(DT)   # one tick so energy_efficiency settles to 1.0 (full grid)
	# Canonical net-per-min rate (the path offline + UI use); includes eng-scale,
	# ore-throttle, the Recursion building_yield_mult, Mastery, DR, warp.
	var rate: float = im.get_total_resource_rates().get("Steel", 0.0)
	print("[PARITY-dbg]   eff=%.2f  effYield/bldg=%.3f  rate=%.1f" % [
		im.energy_efficiency, im.get_effective_yield("auto_smelter", "Steel"), rate])
	im.buildings = {}
	return rate
