# Quest System — Standing Orders
# Distinct from Bounties: passive tracking on all quests at once, no accept/abandon,
# instant claim, auto-replacement on claim. Rewards: credits + material bonus.
# v139: quests own SKILLING, bounties own COMBAT (one system per verb) —
#  - Hunt ("Sweep") quests removed; the per-zone bounty boards absorbed that role
#    (legacy hunt quests on old saves still track + claim via the kept signal hook).
#  - NEW Supply Orders: hand in CRAFTED goods (consumed at claim) for Liras — the
#    manufacturing sink that replaced the old bounty delivery contracts, priced
#    post-#31 (materials are crafting inputs, not vendor trash; no infra-printable
#    Steel-row printers).
#  - Board reroll gains escalating heat (×2 per reroll, cooled by claims) — same
#    anti-scum pattern as the bounty zone refresh.
extends RefCounted

signal quest_updated()

const BOARD_SIZE = 6
const REROLL_BASE_COST = 2500
const MAX_REROLL_HEAT = 12   # price cap ×4096 — deterrent, not a hard wall

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
	10: [["VoidEssence", 20, 50], ["ChronoCore", 10, 25], ["PrimordialShard", 5, 15]],
	# v139: NG+ corrosion-era tiers (Loop 1 reuses the endgame material roster).
	11: [["ExoticMatter", 30, 60], ["VoidEssence", 30, 70], ["OmegaPlating", 10, 25]],
	12: [["PrimordialShard", 15, 35], ["ChronoCore", 20, 45]],
	13: [["ChronoCore", 30, 60], ["VoidEssence", 50, 100]],
	14: [["ExoticMatter", 80, 160], ["OmegaPlating", 30, 60]],
	15: [["PrimordialShard", 60, 120], ["ChronoCore", 60, 120]]
}

# v139: Stockpile targets, quest-owned (was bounty's delivery_materials — moved here
# when deliveries left the bounty board). Rows: [material_id, min_qty, max_qty, credits].
# Credits are the FINAL payout (pre warp/recursion mults) — REPRICED from the v73
# table: stockpiles are non-consuming and auto-complete from inventory, so they pay
# a small passive trickle, never printer sums (old T10 rows paid 10-20M effective;
# a Z8 boss KILL drops 3-6M — that ratio was upside down).
var gather_materials = {
	1: [["Cu", 300, 600, 2000], ["Fe", 200, 450, 2500], ["Si", 150, 300, 2000]],
	2: [["Fe", 500, 1000, 6000], ["Cu", 400, 800, 5000], ["Steel", 60, 150, 8000]],
	3: [["Steel", 150, 300, 18000], ["Ti", 80, 180, 22000], ["Circuit", 60, 120, 20000]],
	4: [["Ti", 200, 400, 45000], ["W", 100, 200, 40000], ["Graphite", 150, 300, 35000]],
	5: [["AdvCircuit", 60, 120, 90000], ["Superalloy", 30, 80, 100000], ["NavData", 60, 150, 70000]],
	6: [["ColonySalvage", 150, 300, 160000], ["AdvCircuit", 100, 200, 150000], ["Steel", 1200, 2500, 130000]],
	7: [["RadIsotope", 120, 300, 260000], ["Pt", 60, 150, 300000], ["Superalloy", 100, 200, 240000]],
	8: [["VoidCrystal", 30, 90, 500000], ["Diamond", 20, 50, 450000], ["ExoticMatter", 12, 30, 550000]],
	9: [["BiohazardSample", 60, 150, 900000], ["Neutronium", 30, 90, 1000000], ["PathogenCore", 12, 30, 1100000]],
	10: [["VoidEssence", 30, 60, 2000000], ["ChronoCore", 12, 30, 2500000], ["PrimordialShard", 8, 20, 3000000]],
	11: [["ExoticMatter", 40, 80, 4500000], ["VoidEssence", 50, 100, 5000000]],
	12: [["PrimordialShard", 30, 60, 8000000], ["OmegaPlating", 20, 50, 9000000]],
	13: [["ChronoCore", 40, 90, 14000000], ["VoidEssence", 80, 160, 15000000]],
	14: [["ExoticMatter", 120, 240, 24000000], ["ChronoCore", 60, 120, 25000000]],
	15: [["PrimordialShard", 120, 240, 40000000], ["OmegaPlating", 60, 120, 42000000]]
}

# v139: Supply Orders — CRAFTED goods only (deep recipe chains: Steel/Circuit/
# AdvCircuit/Superalloy), consumed at claim. The factory sink: pays ~3× the
# same-tier stockpile for real manufacturing effort, stays below hunt-per-minute
# (v107: active combat out-earns idle skilling). Zone-drop exotics deliberately
# excluded — those are combat loot, and combat income is the bounty board's job.
# No tier-1 rows (no crafting unlocked yet) — the roll falls back to Stockpile.
var supply_goods = {
	2: [["Steel", 80, 200, 25000]],
	3: [["Steel", 200, 450, 55000], ["Circuit", 50, 120, 60000]],
	4: [["Circuit", 100, 220, 110000], ["Steel", 400, 900, 100000]],
	5: [["AdvCircuit", 40, 90, 260000], ["Superalloy", 25, 60, 280000]],
	6: [["AdvCircuit", 80, 180, 450000], ["Superalloy", 50, 120, 480000]],
	7: [["Superalloy", 90, 200, 800000], ["AdvCircuit", 150, 300, 750000]],
	8: [["AdvCircuit", 250, 500, 1400000], ["Superalloy", 150, 300, 1500000]],
	9: [["Superalloy", 250, 500, 2600000], ["AdvCircuit", 400, 800, 2400000]],
	10: [["Superalloy", 400, 800, 4500000], ["AdvCircuit", 600, 1200, 4000000]],
	11: [["Superalloy", 600, 1200, 8000000]],
	12: [["AdvCircuit", 900, 1800, 13000000]],
	13: [["Superalloy", 1000, 2000, 22000000]],
	14: [["AdvCircuit", 1500, 3000, 36000000]],
	15: [["Superalloy", 1500, 3000, 60000000]]
}

var board: Array = []
var total_completed: int = 0
var _id_counter: int = 0
# v139: paid-reroll heat — doubles the reroll price per use, cooled 1 step per
# claimed quest (play to earn cheap rerolls; kills supply-order reroll-scumming).
var _reroll_heat: int = 0

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
		# v139: supply orders track exactly like gathers (own N of X) — the
		# difference is at CLAIM, where supply consumes the goods.
		if (q["type"] == "gather" or q["type"] == "supply") and q["target"] == symbol:
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
	# When loading, pull current inventory levels into "gather"/"supply" quests so
	# existing stockpiles count. We cap to target_qty so progress doesn't overshoot.
	if not GameState.resources: return
	var changed = false
	for q in board:
		if q["claimed"]: continue
		if q["type"] == "gather" or q["type"] == "supply":
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
	# Reward tables define tiers 1-15 (v139 added the NG+ rows) — clamp so a
	# future Z16+ unlock can't roll into an empty table and yield a blank quest.
	max_diff = min(max_diff, 15)
	var min_diff = max(1, max_diff - 1)
	# v139: 55% stockpile, 45% supply order (hunts moved to the bounty boards).
	if randf() < 0.55:
		return _generate_gather_quest(min_diff, max_diff)
	else:
		var q = _generate_supply_quest(min_diff, max_diff)
		# Tier bands with no crafted goods yet (T1) fall back to a stockpile.
		if q.is_empty():
			q = _generate_gather_quest(min_diff, max_diff)
		return q

func _generate_gather_quest(min_diff: int, max_diff: int) -> Dictionary:
	var tier = randi_range(min_diff, max_diff)
	var templates = gather_materials.get(tier, [])
	if templates.is_empty(): return {}
	var t = templates[randi() % templates.size()]
	var mat_id = t[0]
	var qty = randi_range(t[1], t[2])
	var credits = t[3]
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

# v139: Supply Orders — the engineer's contract. Requires OWNING the crafted goods
# (tracks like a stockpile) but CLAIM consumes them: a real factory sink, and the
# only intended bulk material→Lira conversion post-#31.
func _generate_supply_quest(min_diff: int, max_diff: int) -> Dictionary:
	var tier = randi_range(min_diff, max_diff)
	var templates = supply_goods.get(tier, [])
	if templates.is_empty(): return {}
	var t = templates[randi() % templates.size()]
	var mat_id = t[0]
	var qty = randi_range(t[1], t[2])
	var credits = t[3]
	var d_name = ElementDB.get_display_name(mat_id)
	return {
		"id": _gen_id(),
		"type": "supply",
		"title": "Supply Order: %s" % d_name,
		"desc": "Deliver %d %s to the station. Goods are consumed when you claim." % [qty, d_name],
		"target": mat_id,
		"target_qty": qty,
		"current_qty": 0,
		"reward_credits": credits,
		"reward_material": _roll_material_bonus(tier),
		"difficulty": tier,
		"completed": false,
		"claimed": false
	}

# v139: hunt ("Sweep") quests REMOVED — kill contracts live on the per-zone bounty
# boards now (the ×10 constant migrated there as HUNT_CREDIT_CONST, honoring the
# v107 active-out-earns-idle principle). The _on_enemy_defeated hook above stays so
# legacy hunt quests already on a pre-v139 board still track and claim; they get
# replaced by gather/supply rolls as they're claimed.

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

	# v139: Supply Orders consume the goods at CLAIM time — re-verify the stock
	# (it may have been spent since the quest auto-completed) and un-complete
	# instead of paying for materials the player no longer holds.
	if q["type"] == "supply":
		var have = GameState.resources.get_element_amount(q["target"])
		if have < q["target_qty"]:
			q["completed"] = false
			q["current_qty"] = have
			quest_updated.emit()
			UITheme.show_notification("Order needs %d %s — stock ran low." % [q["target_qty"], ElementDB.get_display_name(q["target"])], Color.RED)
			return false
		GameState.resources.remove_element(q["target"], q["target_qty"])

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
		# v132: force past the slot cap — this is an EARNED payout; it used to be
		# silently destroyed at 28 slots while the toast still said it was paid.
		GameState.resources.add_element(mat["id"], mat["qty"], true)
		var d_name = ElementDB.get_display_name(mat["id"])
		UITheme.show_notification("+%d %s" % [mat["qty"], d_name], Color(0.5, 1.0, 0.7))

	q["claimed"] = true
	total_completed += 1
	# v139: each claim cools reroll heat one step — playing the board earns
	# cheaper rerolls back.
	_reroll_heat = max(0, _reroll_heat - 1)

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
	var heat = mini(_reroll_heat, MAX_REROLL_HEAT)
	return int(REROLL_BASE_COST * max_diff * pow(2.0, heat))

func reroll_board() -> bool:
	var cost = get_reroll_cost()
	if GameState.resources.get_currency("credits") < cost:
		UITheme.show_notification("Insufficient Liras to reroll!", Color.RED)
		return false
	GameState.resources.remove_currency("credits", cost)
	_reroll_heat += 1
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
		"id_counter": _id_counter,
		"reroll_heat": _reroll_heat
	}

func load_save_data_manager(data: Dictionary):
	board.clear()
	for q in data.get("board", []):
		if q is Dictionary:
			board.append(q)
	total_completed = data.get("total_completed", 0)
	_id_counter = data.get("id_counter", 0)
	_reroll_heat = int(data.get("reroll_heat", 0))
	# Existing save without quest data, or fresh install loading nothing — populate fresh.
	if board.is_empty():
		_fill_board()
	else:
		_sync_gather_progress()

func reset():
	board.clear()
	total_completed = 0
	_id_counter = 0
	_reroll_heat = 0
	# v132: refill immediately — the only other fill paths run at boot, so an
	# in-session hard reset left the Standing Orders board empty until restart.
	_fill_board()
