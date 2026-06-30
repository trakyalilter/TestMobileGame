# Quest System — Standing Orders
# Distinct from Bounties: passive tracking on all quests at once, no accept/abandon,
# instant claim, auto-replacement on claim. Rewards: credits + material bonus.
extends RefCounted

signal quest_updated()

const BOARD_SIZE = 6
const REROLL_BASE_COST = 2500

# Per-tier material reward pool: [material_id, min_qty, max_qty]
# Pulled from rare/intermediate materials so the bonus feels meaningful.
var material_rewards = {
	1: [["Cu", 100, 250], ["Fe", 80, 180], ["Si", 50, 150]],
	2: [["Steel", 40, 100], ["Cu", 200, 500], ["Circuit", 25, 60]],
	3: [["Ti", 60, 150], ["Steel", 150, 350], ["AdvCircuit", 30, 80]],
	4: [["W", 80, 200], ["Ti", 200, 450], ["Graphite", 100, 250]],
	5: [["Superalloy", 30, 80], ["AdvCircuit", 80, 200], ["NavData", 50, 120]],
	6: [["AdvCircuit", 150, 350], ["ColonySalvage", 100, 250], ["Superalloy", 60, 150]],
	7: [["RadIsotope", 80, 200], ["Pt", 50, 120], ["Superalloy", 100, 250]],
	8: [["VoidCrystal", 20, 60], ["Diamond", 15, 40], ["ExoticMatter", 10, 30]],
	9: [["BiohazardSample", 40, 100], ["Neutronium", 25, 70], ["PathogenCore", 10, 25]],
	10: [["VoidEssence", 20, 50], ["ChronoCore", 10, 25], ["PrimordialShard", 5, 15]]
}

var board: Array = []
var total_completed: int = 0
var _id_counter: int = 0

func connect_signals():
	if GameState.resources:
		if not GameState.resources.element_added.is_connected(_on_element_added):
			GameState.resources.element_added.connect(_on_element_added)
	if GameState.combat_manager:
		if not GameState.combat_manager.enemy_defeated.is_connected(_on_enemy_defeated):
			GameState.combat_manager.enemy_defeated.connect(_on_enemy_defeated)
	# First-time board population
	if board.is_empty():
		_fill_board()
	else:
		# Sync gather progress from inventory in case we missed elements
		_sync_gather_progress()

func _on_element_added(symbol, amount):
	for q in board:
		if q["completed"] or q["claimed"]: continue
		if q["type"] == "gather" and q["target"] == symbol:
			q["current_qty"] = min(q["current_qty"] + amount, q["target_qty"])
			if q["current_qty"] >= q["target_qty"]:
				q["completed"] = true
			quest_updated.emit()

func _on_enemy_defeated(enemy_id):
	for q in board:
		if q["completed"] or q["claimed"]: continue
		if q["type"] == "hunt" and q["target"] == enemy_id:
			q["current_qty"] = min(q["current_qty"] + 1, q["target_qty"])
			if q["current_qty"] >= q["target_qty"]:
				q["completed"] = true
			quest_updated.emit()

func _sync_gather_progress():
	# When loading, pull current inventory levels into "gather" quests so existing
	# stockpiles count. We cap to target_qty so progress doesn't overshoot.
	if not GameState.resources: return
	var changed = false
	for q in board:
		if q["claimed"]: continue
		if q["type"] == "gather":
			var have = GameState.resources.get_element_amount(q["target"])
			if have > q["current_qty"]:
				q["current_qty"] = min(have, q["target_qty"])
				if q["current_qty"] >= q["target_qty"]:
					q["completed"] = true
				changed = true
	if changed: quest_updated.emit()

# ── Board Generation ──

func _get_max_difficulty() -> int:
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	if not cm or not rm: return 1
	var max_diff = 1
	for zid in cm.zones:
		var z = cm.zones[zid]
		var req = z.get("research_req", "")
		var flag = z.get("unlock_flag", "")
		# A zone counts as reachable only if BOTH its research gate AND its
		# unlock-flag gate are satisfied. Bug: the_threshold (Z11, difficulty 11)
		# has an empty research_req — it gates via unlock_flag "z11_unlocked" —
		# so the old req=="" check counted it as unlocked for everyone, and a
		# brand-new player got T10-T11 quest rolls.
		var research_ok: bool = (req == "" or rm.is_tech_unlocked(req))
		var flag_ok: bool = (flag == "" or GameState.game_settings.get(flag, false))
		if research_ok and flag_ok:
			max_diff = max(max_diff, int(z["difficulty"]))
	return max_diff

func _fill_board():
	while board.size() < BOARD_SIZE:
		var q = _generate_quest()
		if q.size() > 0:
			board.append(q)
		else:
			break
	quest_updated.emit()

func _generate_quest() -> Dictionary:
	var max_diff = _get_max_difficulty()
	# delivery_materials / material_rewards only define tiers 1-10, so never
	# roll above 10 even once Z11 is unlocked — a tier-11 roll hits an empty
	# table and yields a blank quest. (Tier-11 reward tables are a future add.)
	max_diff = min(max_diff, 10)
	var min_diff = max(1, max_diff - 1)
	# 55% gather, 45% hunt
	if randf() < 0.55:
		return _generate_gather_quest(min_diff, max_diff)
	else:
		return _generate_hunt_quest(min_diff, max_diff)

func _generate_gather_quest(min_diff: int, max_diff: int) -> Dictionary:
	# Pull from BountyManager's material table for tier-curated material picks
	var bm = GameState.bounty_manager
	if not bm: return {}
	var tier = randi_range(min_diff, max_diff)
	var templates = bm.delivery_materials.get(tier, [])
	if templates.is_empty(): return {}
	var t = templates[randi() % templates.size()]
	var mat_id = t[0]
	# Quests demand smaller quantities than bounties (quests aren't consumed)
	var qty = int(randf_range(t[1], t[2]) * 0.6)
	var credits = int(t[3] * 0.4)
	var d_name = ElementDB.get_display_name(mat_id)
	return {
		"id": _gen_id(),
		"type": "gather",
		"title": "Stockpile: %s" % d_name,
		"desc": "Acquire %d units of %s." % [qty, d_name],
		"target": mat_id,
		"target_qty": qty,
		"current_qty": 0,
		"reward_credits": credits,
		"reward_material": _roll_material_bonus(tier),
		"difficulty": tier,
		"completed": false,
		"claimed": false
	}

func _generate_hunt_quest(min_diff: int, max_diff: int) -> Dictionary:
	var cm = GameState.combat_manager
	if not cm: return {}
	var valid_zones = []
	for zid in cm.zones:
		var z = cm.zones[zid]
		if z["difficulty"] >= min_diff and z["difficulty"] <= max_diff:
			valid_zones.append({"id": zid, "data": z})
	if valid_zones.is_empty(): return {}
	var zone = valid_zones[randi() % valid_zones.size()]
	var enemies = zone["data"]["enemies"]
	# Prefer non-boss for quests; bosses are bounty territory
	var non_boss = []
	for eid in enemies:
		var ed = cm.enemy_db.get(eid, {})
		if not ed.get("is_boss", false):
			non_boss.append(eid)
	if non_boss.is_empty(): non_boss = enemies
	var enemy_id = non_boss[randi() % non_boss.size()]
	var enemy_data = cm.enemy_db.get(enemy_id, {})
	if enemy_data.is_empty(): return {}
	var qty = randi_range(8, 20)
	var base_xp = enemy_data.get("xp", 10)
	var diff_mult = pow(zone["data"]["difficulty"], 1.4)
	# v107: Combat tasks pay ~1.2x per-minute over gather tasks at the same
	# tier. Active attention + hull/consumable risk + gear investment are
	# paid for in the formula constant, not just at high tiers where the
	# diff_mult dominates. Was 3.0 — that made Z1 sweep pay 0.33x stockpile
	# per minute and silently taught new players to ignore combat. The 10.0
	# constant restores the design principle that risky/active tasks
	# out-earn idle gather tasks per minute.
	var credit_reward = int(base_xp * qty * 10.0 * diff_mult)
	return {
		"id": _gen_id(),
		"type": "hunt",
		"title": "Sweep: %s" % enemy_data["name"],
		"desc": "Destroy %d %s in %s." % [qty, enemy_data["name"], zone["data"]["name"]],
		"target": enemy_id,
		"target_qty": qty,
		"current_qty": 0,
		"reward_credits": credit_reward,
		"reward_material": _roll_material_bonus(zone["data"]["difficulty"]),
		"difficulty": zone["data"]["difficulty"],
		"completed": false,
		"claimed": false
	}

func _roll_material_bonus(tier: int) -> Dictionary:
	# 60% chance to roll a material reward in addition to credits
	if randf() > 0.6: return {}
	var pool = material_rewards.get(tier, [])
	if pool.is_empty(): return {}
	var pick = pool[randi() % pool.size()]
	return {"id": pick[0], "qty": randi_range(pick[1], pick[2])}

func _gen_id() -> String:
	_id_counter += 1
	return "quest_%d_%d" % [Time.get_ticks_msec(), _id_counter]

# ── Player Actions ──

func claim_quest(quest_id: String) -> bool:
	var idx = -1
	for i in range(board.size()):
		if board[i]["id"] == quest_id:
			idx = i
			break
	if idx == -1: return false
	var q = board[idx]
	if not q["completed"] or q["claimed"]: return false

	# Award credits
	var cred = q["reward_credits"]
	if GameState.warp_manager:
		cred = int(cred * GameState.warp_manager.get_production_multiplier())
	# v109: Recursion — Recursive Acquisition (+5%/level Lira rewards)
	if GameState.research_manager:
		cred = int(cred * (1.0 + GameState.research_manager.get_efficiency_bonus("credit_reward_mult")))
	GameState.resources.add_currency("credits", cred)
	UITheme.show_notification("+%s Liras" % UITheme.format_num(cred), Color(1.0, 0.85, 0.3))

	# Award material bonus
	var mat = q.get("reward_material", {})
	if mat and mat.size() > 0:
		GameState.resources.add_element(mat["id"], mat["qty"])
		var d_name = ElementDB.get_display_name(mat["id"])
		UITheme.show_notification("+%d %s" % [mat["qty"], d_name], Color(0.5, 1.0, 0.7))

	q["claimed"] = true
	total_completed += 1

	# Replace with a fresh quest
	board.remove_at(idx)
	var fresh = _generate_quest()
	if fresh.size() > 0:
		board.append(fresh)
	quest_updated.emit()
	return true

func claim_all_completed() -> int:
	# Snapshot completed quest IDs first — claim_quest mutates the board
	var to_claim: Array = []
	for q in board:
		if q["completed"] and not q["claimed"]:
			to_claim.append(q["id"])
	var n = 0
	for qid in to_claim:
		if claim_quest(qid):
			n += 1
	return n

func count_claimable() -> int:
	var n = 0
	for q in board:
		if q["completed"] and not q["claimed"]:
			n += 1
	return n

func get_reroll_cost() -> int:
	var max_diff = _get_max_difficulty()
	return REROLL_BASE_COST * max_diff

func reroll_board() -> bool:
	var cost = get_reroll_cost()
	if GameState.resources.get_currency("credits") < cost:
		UITheme.show_notification("Insufficient Liras to reroll!", Color.RED)
		return false
	GameState.resources.remove_currency("credits", cost)
	# Keep completed-but-unclaimed quests; reroll the rest
	var kept = []
	for q in board:
		if q["completed"] and not q["claimed"]:
			kept.append(q)
	board = kept
	_fill_board()
	UITheme.show_notification("Standing Orders Rerolled", Color.CYAN)
	return true

# ── Save / Load ──

func get_save_data_manager() -> Dictionary:
	var arr = []
	for q in board:
		arr.append(q.duplicate())
	return {
		"board": arr,
		"total_completed": total_completed,
		"id_counter": _id_counter
	}

func load_save_data_manager(data: Dictionary):
	board.clear()
	for q in data.get("board", []):
		if q is Dictionary:
			board.append(q)
	total_completed = data.get("total_completed", 0)
	_id_counter = data.get("id_counter", 0)
	# Existing save without quest data, or fresh install loading nothing — populate fresh.
	if board.is_empty():
		_fill_board()
	else:
		_sync_gather_progress()

func reset():
	board.clear()
	total_completed = 0
	_id_counter = 0
