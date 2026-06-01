extends "res://scripts/sim/policy_base.gd"

# CASUAL — short sessions, long offline, "good enough" choices. Picks the
# highest-tier unlocked gather action (a "this looks strong" heuristic) and
# never micro-optimizes processing. Sells everything on login, researches /
# builds only occasionally, and is slow to pull the warp trigger. Brackets the
# Optimizer: if BOTH curves feel fine, the real population in between is safe.

var _meta_counter := 0

func manage_meta() -> void:
	sell_surplus({})            # dumps the whole bag — no feedstock planning
	_meta_counter += 1
	if _meta_counter % 3 == 0:  # only tinkers with meta every 3rd login
		try_unlock_research(2)
		buy_buildings(3)
	maybe_upgrade_storage()

func decide_session() -> Dictionary:
	var gm = GameState.gathering_manager
	var best := "gather_dirt"
	var best_req := -1
	for aid in unlocked_gather_actions():
		var req := int(gm.actions[aid].get("level_req", 1))
		if req > best_req:
			best_req = req; best = aid
	return {"mgr": gm, "id": best}

func want_warp() -> bool:
	return GameState.warp_manager.calculate_warp_gains() >= 2
