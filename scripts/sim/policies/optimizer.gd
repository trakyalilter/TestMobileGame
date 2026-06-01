extends "res://scripts/sim/policy_base.gd"

# OPTIMIZER — min-maxer. Greedy best credits/sec each session; aggressively
# expands research + buildings (buildings are both passive income AND a warp
# lever: each counts 1000 toward progress_score); warps the instant the gate
# trips, to measure the fastest realistic time-to-first-warp.

func manage_meta() -> void:
	# Natural order: unlock research, bank credits (keeping building/recipe
	# feedstock), then buy buildings IF affordable. NOTE: a pure gather-and-sell
	# optimizer rarely accumulates the intermediate mats (Si/Cu/Fe...) buildings
	# need — so buildings often stay at 0. That is a FINDING (the fastest warp
	# path bypasses infra+processing), not something to force.
	try_unlock_research(8)
	sell_surplus(_protected())
	buy_buildings(15)
	maybe_upgrade_storage()

# Common early building cost-materials + best-recipe feedstock are retained so
# selling doesn't strip the inputs the next build/process cycle needs.
const BUILD_FEEDSTOCK := ["Si", "Fe", "Cu", "C", "Steel", "Al", "Mg", "Co", "Ni"]

func _protected() -> Dictionary:
	var keep := {}
	for sym in BUILD_FEEDSTOCK:
		keep[sym] = 100.0
	var rid := best_recipe_id()
	if rid != "":
		var r = GameState.processing_manager.recipes[rid]
		for sym in r.get("input", {}):
			keep[sym] = max(float(keep.get(sym, 0.0)), RESERVE_KEEP)
	return keep

func decide_session() -> Dictionary:
	var g := best_gather()                  # [id, cps, xps]
	var g_score := float(g[1]) + 0.01 * float(g[2])
	var rid := best_recipe_id()
	if rid != "" and recipe_runnable(rid):
		var r_score := recipe_profit_per_sec(rid) + 0.01 * recipe_xp_per_sec(rid)
		if r_score > g_score:
			return {"mgr": GameState.processing_manager, "id": rid}
	return {"mgr": GameState.gathering_manager, "id": String(g[0])}

func want_warp() -> bool:
	return GameState.warp_manager.calculate_warp_gains() >= 1
