extends "res://scripts/sim/policy_base.gd"

# COMBAT RUSHER — funds a ship via early gathering, then farms combat for the
# big credit drops that feed the warp loop. Realistic supply chain:
#   gather/sell -> research kinetics_101 -> build Slug Factory (passive ammo)
#   -> craft + equip a Z1 loadout -> farm Z1 trash for credits.
#
# Honest scope (Phase 2): this gets the bot ARMED and FARMING, and measures
# combat's credit rate + time-to-armed vs the gather-sell path. Beating zone
# bosses (for cores -> zone_N_access -> deeper zones) needs loadout tuning the
# spike showed a basic corvette can't do yet — that's the next iteration.

const KEEP := ["Fe", "Si", "Cu", "C", "Steel", "SlugT1"]   # don't sell the war chest
const Z1_CONSUMERS := {0: "z1_kinetic", 1: "z1_kinetic", 2: "z1_shield", 3: "z1_armor", 4: "z1_engine", 7: "z1_sensor"}

func manage_meta() -> void:
	# 1. Drive research toward the arming path: adv_materials gates Fe gathering
	#    (weapon mats); kinetics_101 gates the Slug Factory (ammo). Then a little
	#    greedy expansion for the rest.
	unlock_toward("adv_materials")
	unlock_toward("kinetics_101")
	try_unlock_research(3)
	# 2. Bank credits, keeping the war chest (Fe for weapons + ammo).
	sell_surplus(_protected())
	# 3. Arm the corvette as funds allow (weapons first -> is_armed ASAP).
	_arm_ship()

func _protected() -> Dictionary:
	var keep := {}
	for sym in KEEP:
		keep[sym] = 200.0
	return keep

func _arm_ship() -> void:
	var sm = GameState.shipyard_manager
	# Fill each Z1 consumer slot: craft the module if needed, then equip.
	for slot in Z1_CONSUMERS:
		var mid: String = Z1_CONSUMERS[slot]
		if sm.loadout.get(slot, "") == mid:
			continue
		if int(sm.module_inventory.get(mid, 0)) <= 0:
			if not sm.craft_module(mid):   # pays credits + mats; fails if unaffordable
				continue
		sm.equip_module(slot, mid)
	sm.recalc_stats()

func decide_session() -> Dictionary:
	var res = GameState.resources
	var P = GameState.processing_manager
	var G = GameState.gathering_manager

	# Phase 1 — bootstrap the economy. Sifting Fe needs basic_engineering (125cr),
	# so first fund research the optimizer way: gather valuables to sell.
	if not GameState.research_manager.is_tech_unlocked("basic_engineering"):
		return {"kind": "gather", "mgr": G, "id": String(best_gather()[0])}

	# Phase 2 — not armed yet: build up Fe (Dry Sifting Dirt->Fe) for the weapon.
	if not is_armed():
		if res.get_element_amount("Fe") < 60.0:
			if res.get_element_amount("Dirt") >= 10.0:
				return {"kind": "process", "mgr": P, "id": "sift_dirt_dry"}
			return {"kind": "gather", "mgr": G, "id": "gather_dirt"}
		# Have Fe; manage_meta crafts+equips. Fund credits meanwhile.
		return {"kind": "gather", "mgr": G, "id": String(best_gather()[0])}

	# Phase 3 — armed. Keep a deep ammo buffer (craft_slug_t1: 1 Fe -> 20 SlugT1)
	# so offline combat farming has fuel. Weapons with no ammo deal 0 damage.
	if res.get_element_amount("SlugT1") < 1000.0:
		if res.get_element_amount("Fe") >= 1.0:
			return {"kind": "process", "mgr": P, "id": "craft_slug_t1"}
		if res.get_element_amount("Dirt") >= 10.0:
			return {"kind": "process", "mgr": P, "id": "sift_dirt_dry"}
		return {"kind": "gather", "mgr": G, "id": "gather_dirt"}

	# Armed + stocked -> farm Zone-1 trash.
	var zones := unlocked_zone_ids()
	if not zones.is_empty():
		var zid: String = zones[0]
		var enemies: Array = GameState.combat_manager.zones[zid].get("enemies", [])
		var enemy: String = enemies[0] if not enemies.is_empty() else ""
		return {"kind": "combat", "zone": zid, "enemy": enemy}
	return {"kind": "gather", "mgr": G, "id": String(best_gather()[0])}

func pre_offline() -> void:
	# Armed + stocked: keep COMBAT active so offline_combat farms credits while
	# away — the dominant lever for combat's progression weakness.
	var cm = GameState.combat_manager
	if is_armed() and GameState.resources.get_element_amount("SlugT1") > 50.0:
		var zones := unlocked_zone_ids()
		if not zones.is_empty():
			cm.start_expedition(String(zones[0]))
			var enemies: Array = cm.zones[String(zones[0])].get("enemies", [])
			if not enemies.is_empty():
				cm.set_target_enemy(String(enemies[0]))
			GameState.active_manager = cm
			return
	# Still arming: gather Dirt while away (feedstock for Dry Sifting -> Fe).
	var gm = GameState.gathering_manager
	gm.start_action("gather_dirt")
	GameState.active_manager = gm
	if GameState.active_manager and GameState.active_manager != gm:
		GameState.active_manager.stop_action()
	GameState.active_manager = gm

func want_warp() -> bool:
	# Warping calls resources.reset() AND shipyard.reset() — wiping the Fe/credit
	# stockpile AND the equipped loadout. Two findings forced these guards:
	#  1) Don't warp before armed, or warp-ASAP traps the bot in a prestige loop
	#     that never accumulates weapon mats.
	#  2) Don't warp the instant we arm, or the reset wipes the just-crafted
	#     weapon before a single fight — gate on combat level (proxy for "has
	#     actually fought") so the ship earns its keep first.
	if not is_armed():
		return false
	if GameState.combat_manager.get_level() < 5:
		return false
	return GameState.warp_manager.calculate_warp_gains() >= 1
