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

# v141d: material reward pool removed — quests pay Liras only (owner).

# v139: Stockpile targets, quest-owned. Rows: [material_id, min_qty, max_qty, credits].
# Credits are the FINAL payout (pre warp/recursion mults).
# v139c: Stockpile orders now CONSUME the delivered goods (like Supply), so this is
# the raw-material -> Lira SINK, not a passive reward-for-holding. Rewards bumped
# x1.75 over the original repriced table to make surplus-dumping clearly worth the
# consumed goods + the lost double-dip, while staying UNDER combat income per minute
# (v107 active-out-earns-idle) and bounded by material throughput (no printer:
# each claim costs the full delivered stack). Supply (crafted) still leads per tier.
var gather_materials = {
	1: [["Cu", 300, 600, 3500], ["Fe", 200, 450, 4400], ["Si", 150, 300, 3500]],
	2: [["Fe", 500, 1000, 10000], ["Cu", 400, 800, 8800], ["Steel", 60, 150, 14000]],
	3: [["Steel", 150, 300, 32000], ["Ti", 80, 180, 38000], ["Circuit", 60, 120, 35000]],
	4: [["Ti", 200, 400, 79000], ["W", 100, 200, 70000], ["Graphite", 150, 300, 61000]],
	5: [["AdvCircuit", 60, 120, 160000], ["Superalloy", 30, 80, 180000], ["NavData", 60, 150, 120000]],
	6: [["ColonySalvage", 150, 300, 280000], ["AdvCircuit", 100, 200, 260000], ["Steel", 1200, 2500, 230000]],
	7: [["RadIsotope", 120, 300, 460000], ["Pt", 60, 150, 520000], ["Superalloy", 100, 200, 420000]],
	8: [["VoidCrystal", 30, 90, 880000], ["Diamond", 20, 50, 790000], ["ExoticMatter", 12, 30, 960000]],
	9: [["BiohazardSample", 60, 150, 1600000], ["Neutronium", 30, 90, 1800000], ["PathogenCore", 12, 30, 1900000]],
	10: [["VoidEssence", 30, 60, 3500000], ["ChronoCore", 12, 30, 4400000], ["PrimordialShard", 8, 20, 5200000]],
	11: [["ExoticMatter", 40, 80, 7900000], ["VoidEssence", 50, 100, 8800000]],
	12: [["PrimordialShard", 30, 60, 14000000], ["OmegaPlating", 20, 50, 16000000]],
	13: [["ChronoCore", 40, 90, 24000000], ["VoidEssence", 80, 160, 26000000]],
	14: [["ExoticMatter", 120, 240, 42000000], ["ChronoCore", 60, 120, 44000000]],
	15: [["PrimordialShard", 120, 240, 70000000], ["OmegaPlating", 60, 120, 74000000]]
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
		# v139c: also watch REMOVALS — a Stockpile/Supply bar must drop live when
		# the player spends the material (it reflects what you OWN right now).
		if not GameState.resources.element_removed.is_connected(_on_element_removed):
			GameState.resources.element_removed.connect(_on_element_removed)
	if GameState.combat_manager:
		if not GameState.combat_manager.enemy_defeated.is_connected(_on_enemy_defeated):
			GameState.combat_manager.enemy_defeated.connect(_on_enemy_defeated)
	# First-time board population
	if board.is_empty():
		_fill_board()
	else:
		# Sync gather progress from inventory in case we missed elements
		_resync_stock_quests()

func _on_element_added(_symbol, _amount):
	# v139c: gather/supply progress is a LIVE inventory read (see
	# _resync_stock_quests), not an accumulator — any add re-derives from what
	# the player now owns.
	_resync_stock_quests()

func _on_element_removed(_symbol, _amount):
	# v139c: spending a material lowers its Stockpile/Supply bars live.
	_resync_stock_quests()

func _on_enemy_defeated(enemy_id):
	for q in board:
		if q["completed"] or q["claimed"]: continue
		if q["type"] == "hunt" and q["target"] == enemy_id:
			q["current_qty"] = min(q["current_qty"] + 1, q["target_qty"])
			if q["current_qty"] >= q["target_qty"]:
				q["completed"] = true
			quest_updated.emit()

# v139c: a Stockpile/Supply quest means "own N units of X" — its progress is a
# LIVE read of current inventory, min(owned, target), re-derived on every
# inventory change (up AND down). The old model INCREMENTED from when each quest
# spawned, so two quests for the same material drifted apart and a freshly-rolled
# one showed 0/N even while the player already owned hundreds (owner-reported
# 6× "Stok: Bakır" cards reading 272/272/138/138/0). Both-way so the bar mirrors
# holdings and never latches on stale accumulated counts.
func _resync_stock_quests():
	if not GameState.resources: return
	var changed = false
	for q in board:
		if q["claimed"]: continue
		if q["type"] == "gather" or q["type"] == "supply":
			var have = GameState.resources.get_element_amount(q["target"])
			var new_cur = min(have, q["target_qty"])
			var new_done: bool = have >= q["target_qty"]
			if new_cur != q["current_qty"] or new_done != q["completed"]:
				q["current_qty"] = new_cur
				q["completed"] = new_done
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
	var qty = _round_qty(randi_range(t[1], t[2]))
	var credits = t[3]
	var d_name = ElementDB.get_display_name(mat_id)
	# v139c: born reflecting current inventory ("own N"), never 0/N when held.
	var have = GameState.resources.get_element_amount(mat_id) if GameState.resources else 0
	return {
		"id": _gen_id(),
		"type": "gather",
		"title": tr("Stockpile: %s") % d_name,
		"desc": tr("Acquire %d units of %s.") % [qty, d_name],
		"target": mat_id,
		"target_qty": qty,
		"current_qty": min(have, qty),
		"reward_credits": credits,
		"difficulty": tier,
		"completed": have >= qty,
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
	var qty = _round_qty(randi_range(t[1], t[2]))
	var credits = t[3]
	var d_name = ElementDB.get_display_name(mat_id)
	# v139c: born reflecting current inventory (live "own N" read).
	var have = GameState.resources.get_element_amount(mat_id) if GameState.resources else 0
	return {
		"id": _gen_id(),
		"type": "supply",
		"title": tr("Supply Order: %s") % d_name,
		"desc": tr("Deliver %d %s to the station. Goods are consumed when you claim.") % [qty, d_name],
		"target": mat_id,
		"target_qty": qty,
		"current_qty": min(have, qty),
		"reward_credits": credits,
		"difficulty": tier,
		"completed": have >= qty,
		"claimed": false
	}

# v139: hunt ("Sweep") quests REMOVED — kill contracts live on the per-zone bounty
# boards now (the ×10 constant migrated there as HUNT_CREDIT_CONST, honoring the
# v107 active-out-earns-idle principle). The _on_enemy_defeated hook above stays so
# legacy hunt quests already on a pre-v139 board still track and claim; they get
# replaced by gather/supply rolls as they're claimed.

func _gen_id() -> String:
	_id_counter += 1
	return "quest_%d_%d" % [Time.get_ticks_msec(), _id_counter]

# v139c: quest targets snap to clean, divisible-by-10 numbers (owner: no
# confusing 282/387 asks). Step scales with magnitude so big supply orders stay
# tidy too — every result is a multiple of 10.
func _round_qty(n: int) -> int:
	if n < 100: return maxi(10, int(round(n / 10.0)) * 10)
	if n < 1000: return int(round(n / 10.0)) * 10
	if n < 10000: return int(round(n / 100.0)) * 100
	return int(round(n / 1000.0)) * 1000

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

	# v139c: BOTH order types CONSUME the goods at CLAIM time. Supply always did;
	# gather ("Stockpile") now does too — without it, the live-inventory bar made
	# every held-material order auto-complete, and claim→reroll→claim printed
	# infinite Liras for materials you never spent (owner-reported). Consuming
	# turns raw stock into a Lira sink and re-verifies the stock (it may have been
	# spent since the bar auto-completed) — un-complete instead of paying for
	# materials no longer held.
	if q["type"] == "supply" or q["type"] == "gather":
		var have = GameState.resources.get_element_amount(q["target"])
		if have < q["target_qty"]:
			q["completed"] = false
			q["current_qty"] = have
			quest_updated.emit()
			UITheme.show_notification(tr("Order needs %d %s — stock ran low.") % [q["target_qty"], ElementDB.get_display_name(q["target"])], Color.RED)
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
	UITheme.show_notification(tr("+%s Liras") % UITheme.format_num(cred), Color(1.0, 0.85, 0.3))

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
		UITheme.show_notification(tr("Insufficient Liras to reroll!"), Color.RED)
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
	UITheme.show_notification(tr("Standing Orders Rerolled"), Color.CYAN)
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
		_resync_stock_quests()

func reset():
	board.clear()
	total_completed = 0
	_id_counter = 0
	_reroll_heat = 0
	# v132: refill immediately — the only other fill paths run at boot, so an
	# in-session hard reset left the Standing Orders board empty until restart.
	_fill_board()
