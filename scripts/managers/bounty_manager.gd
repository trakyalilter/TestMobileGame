# v72.0: Bounty Board System
# v139: PER-ZONE boards — Bounties are now the COMBAT contract system.
#  - Every unlocked zone carries its own 4-card board: 2 hunts + 1 boss bounty + 1 elite duel.
#  - DELIVERY contracts moved to the Quest system as Supply Orders (quests own skilling,
#    bounties own combat — one system per verb). Legacy delivery contracts already in the
#    ACTIVE list keep working (claim/abandon), they just never generate again.
#  - Natural refresh (8h, ticked offline via game_state.process_offline_progress)
#    regenerates ALL zone boards and clears paid-reroll heat; the paid REFRESH targets
#    ONE zone and doubles in price per use within the window (anti reroll-scumming).
extends RefCounted

signal bounty_updated()

const MAX_ACTIVE = 3
const CARDS_PER_ZONE = 4
const REFRESH_INTERVAL = 28800.0 # 8 hours in seconds
const REFRESH_BASE_COST = 5000   # × zone difficulty × 2^rerolls-this-window
const MAX_REROLL_HEAT = 12       # price cap ×4096 — a deterrent, not a hard wall

# v139: hunt payouts absorb the removed quest-hunt ("Sweep") income role — the ×10
# constant matches the old quest sweep at Z1 while the 1.6 exponent keeps the old
# bounty top-end. Elite keeps its v73 jackpot curve. Boss bounties use the hunt
# formula on boss-sized xp (≈2.4× a same-tier trash hunt — the boss premium).
const HUNT_CREDIT_CONST = 10.0
const HUNT_DIFF_EXP = 1.6
const ELITE_CREDIT_CONST = 300.0
const ELITE_DIFF_EXP = 1.5

var available_by_zone: Dictionary = {}  # zone_id -> Array[contract]
var zone_rerolls: Dictionary = {}       # zone_id -> paid refreshes since last natural refresh
var active_contracts: Array = []        # Accepted contracts (max 3, global across zones)
var refresh_timer: float = 0.0          # Time until the next natural all-board refresh
var total_completed: int = 0            # Lifetime stat

func connect_signals():
	var cm = GameState.combat_manager
	if cm:
		if not cm.enemy_defeated.is_connected(_on_enemy_defeated):
			cm.enemy_defeated.connect(_on_enemy_defeated)
		if not cm.combat_started.is_connected(_on_combat_started):
			cm.combat_started.connect(_on_combat_started)

# v131: Zone Trophies REMOVED from the game. This now returns only the v112
# CAPSTONE held-item buffs (Omega Accelerator / Temporal Module) — callers are
# unchanged; buff types with no capstone simply return 1.0.
func get_trophy_buff(buff_type: String) -> float:
	if not GameState.resources: return 1.0
	var res = GameState.resources
	var mult = 1.0
	match buff_type:
		"mining_yield":
			# v112: Omega Accelerator capstone — "massively increases all production".
			if res.get_element_amount("OmegaAccelerator") > 0: mult += 0.50
		"infrastructure_yield":
			# v112: Omega Accelerator capstone also boosts always-on infra yield.
			if res.get_element_amount("OmegaAccelerator") > 0: mult += 0.50
		"ship_speed":
			# v112: Temporal Stabilizer capstone — "massive combat speed boost".
			if res.get_element_amount("TemporalModule") > 0: mult += 0.30
	return mult

func _on_enemy_defeated(enemy_id: String):
	# v132: elite hunts must be completed on the ELITE variant. The signal carries
	# no elite flag, but it fires from win_fight while current_enemy is still the
	# killed enemy — read its is_elite there. (Without this, killing the normal
	# variant of the target cashed the elite contract's outsized payout.)
	var was_elite: bool = false
	var cm = GameState.combat_manager
	if cm and cm.current_enemy:
		was_elite = bool(cm.current_enemy.get("is_elite", false))
	for contract in active_contracts:
		if contract["type"] == "hunt" and contract["target"] == enemy_id:
			if contract.get("is_elite", false) and not was_elite:
				continue
			contract["current_qty"] = min(contract["current_qty"] + 1, contract["target_qty"])
			if contract["current_qty"] >= contract["target_qty"]:
				contract["completed"] = true
				if contract.get("is_elite", false):
					UITheme.show_notification("ELITE BREACHED: Contract Complete", Color.GOLD)
			bounty_updated.emit()

func _on_combat_started():
	# If we have an active elite hunt for this zone/enemy, flag the combat_manager
	var cm = GameState.combat_manager
	if not cm: return

	for contract in active_contracts:
		if contract.get("is_elite", false) and not contract["completed"]:
			if contract["zone_id"] == cm.current_zone_id and contract["target"] == cm.current_enemy["id"]:
				cm.next_spawn_elite = true
				log_msg("ELITE SIGNATURE DETECTED!")
				break

func log_msg(msg: String):
	if GameState.combat_manager:
		GameState.combat_manager.log_msg(msg)

# ─── Zone Boards ───

# Zones that count as reachable: BOTH the research gate AND the unlock-flag gate
# must pass (the_threshold/Z11+ gate purely via unlock_flag — see the v132 fix).
# Returned sorted by difficulty so the UI tab strip reads Z1 → frontier.
func get_unlocked_zones() -> Array:
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	if not cm or not rm: return []
	var out: Array = []
	for zid in cm.zones:
		var z = cm.zones[zid]
		var req = z.get("research_req", "")
		var flag = z.get("unlock_flag", "")
		var research_ok: bool = (req == "" or rm.is_tech_unlocked(req))
		var flag_ok: bool = (flag == "" or GameState.game_settings.get(flag, false))
		if research_ok and flag_ok:
			out.append({"id": zid, "name": String(z.get("name", zid)), "difficulty": int(z["difficulty"])})
	out.sort_custom(func(a, b): return a["difficulty"] < b["difficulty"])
	return out

# UI accessor. Lazy-seeds a board for a zone that unlocked mid-window (research or
# flag flipped since the last natural refresh) without touching the global timer.
func get_zone_contracts(zone_id: String) -> Array:
	if not available_by_zone.has(zone_id):
		available_by_zone[zone_id] = _generate_zone_pool(zone_id)
	return available_by_zone[zone_id]

# Natural refresh: every unlocked zone gets a fresh board, paid-reroll heat clears,
# and the 8h window re-arms.
func generate_all_pools():
	available_by_zone.clear()
	zone_rerolls.clear()
	for z in get_unlocked_zones():
		available_by_zone[z["id"]] = _generate_zone_pool(z["id"])
	refresh_timer = REFRESH_INTERVAL
	bounty_updated.emit()

func _generate_zone_pool(zone_id: String) -> Array:
	var cm = GameState.combat_manager
	if not cm: return []
	var zone = cm.zones.get(zone_id, {})
	if zone.is_empty(): return []
	var trash: Array = []
	var boss_id := ""
	for eid in zone.get("enemies", []):
		if cm.enemy_db.get(eid, {}).get("is_boss", false):
			boss_id = eid
		else:
			trash.append(eid)
	# v139b: bounties target only the MODULE-HUNTER enemies — the back-half trash
	# (e3 = weapons pool, e4 = shield/armor pool) + the boss. The front-half (e1/e2)
	# is the material-farm lane and never gets a contract. Every zone ships 4 trash
	# + boss, so "last two" = e3/e4 universally (defensive slice for odd rosters).
	var hunters: Array = trash.slice(maxi(0, trash.size() - 2)) if trash.size() > 0 else []
	var pool: Array = []
	# One hunt per module-hunter, deterministic — the board always offers both the
	# weapon-farm target AND the defense-farm target.
	for eid in hunters:
		var c = _make_hunt(zone_id, zone, eid, false, false)
		if c.size() > 0: pool.append(c)
	if boss_id != "":
		var cb = _make_hunt(zone_id, zone, boss_id, true, false)
		if cb.size() > 0: pool.append(cb)
	if hunters.size() > 0:
		# Elite duels roll module-hunter variants only — boss content is the boss
		# bounty's job, and an elite-multiplied PHASED warden (Z11+) is untuned.
		var ce = _make_hunt(zone_id, zone, hunters[randi() % hunters.size()], false, true)
		if ce.size() > 0: pool.append(ce)
	return pool

func _make_hunt(zone_id: String, zone: Dictionary, enemy_id: String, boss_hunt: bool, elite: bool) -> Dictionary:
	var cm = GameState.combat_manager
	var enemy_data = cm.enemy_db.get(enemy_id, {})
	if enemy_data.is_empty(): return {}
	var diff = int(zone["difficulty"])
	var base_xp = enemy_data.get("xp", 10)
	var qty: int
	var credit_reward: int
	var title: String
	var desc: String
	if elite:
		qty = 1 # Elites are 1v1 duels
		credit_reward = int(base_xp * ELITE_CREDIT_CONST * pow(diff, ELITE_DIFF_EXP))
		title = "ELITE HUNT: %s" % enemy_data["name"]
		desc = "Destroy the ELITE %s in %s. Warning: Extremely Dangerous." % [enemy_data["name"], zone["name"]]
	elif boss_hunt:
		# Offline-completable by design (v138b: offline boss kills emit enemy_defeated).
		qty = randi_range(1, 2)
		credit_reward = int(base_xp * qty * HUNT_CREDIT_CONST * pow(diff, HUNT_DIFF_EXP))
		title = "BOSS BOUNTY: %s" % enemy_data["name"]
		desc = "Destroy %d× %s in %s." % [qty, enemy_data["name"], zone["name"]]
	else:
		qty = randi_range(5, 20)
		credit_reward = int(base_xp * qty * HUNT_CREDIT_CONST * pow(diff, HUNT_DIFF_EXP))
		title = "Hunt: %s" % enemy_data["name"]
		desc = "Destroy %d %s in %s." % [qty, enemy_data["name"], zone["name"]]
	return {
		"id": _gen_id(),
		"type": "hunt",
		"title": title,
		"desc": desc,
		"target": enemy_id,
		"target_qty": qty,
		"current_qty": 0,
		"reward_credits": credit_reward,
		"reward_module_pool": _get_zone_module_pool(zone_id),
		"zone_id": zone_id,
		"difficulty": diff,
		"completed": false,
		"claimed": false,
		"is_elite": elite,
		"is_boss_hunt": boss_hunt
	}

# ─── Paid Refresh (per zone, escalating) ───

func get_refresh_cost(zone_id: String) -> int:
	var cm = GameState.combat_manager
	var diff: int = 1
	if cm:
		diff = int(cm.zones.get(zone_id, {}).get("difficulty", 1))
	var heat = mini(int(zone_rerolls.get(zone_id, 0)), MAX_REROLL_HEAT)
	return int(REFRESH_BASE_COST * diff * pow(2.0, heat))

func force_refresh(zone_id: String) -> bool:
	var cost = get_refresh_cost(zone_id)
	if GameState.resources.get_currency("credits") < cost:
		UITheme.show_notification("Not enough Liras to refresh!", Color.RED)
		return false
	GameState.resources.remove_currency("credits", cost)
	zone_rerolls[zone_id] = int(zone_rerolls.get(zone_id, 0)) + 1
	available_by_zone[zone_id] = _generate_zone_pool(zone_id)
	UITheme.show_notification("Zone Board Refreshed", Color.CYAN)
	bounty_updated.emit()
	return true

func _get_zone_module_pool(zone_id: String) -> Array:
	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager
	var zone = cm.zones.get(zone_id, {})
	var pool = []
	for eid in zone.get("enemies", []):
		var e = cm.enemy_db.get(eid, {})
		for mid in e.get("module_drop_pool", []):
			if mid not in pool:
				var req = sm.modules.get(mid, {}).get("research_req", "")
				if req == "" or (GameState.research_manager and GameState.research_manager.is_tech_unlocked(req)):
					pool.append(mid)
	return pool

var _id_counter = 0
func _gen_id() -> String:
	_id_counter += 1
	return "bounty_%d_%d" % [Time.get_ticks_msec(), _id_counter]

# ─── Player Actions ───

func accept_contract(contract_id: String) -> bool:
	if active_contracts.size() >= MAX_ACTIVE:
		UITheme.show_notification("Contract slots full! (Max %d)" % MAX_ACTIVE, Color.RED)
		return false
	for zid in available_by_zone:
		var pool: Array = available_by_zone[zid]
		for i in range(pool.size()):
			if pool[i]["id"] == contract_id:
				var contract = pool[i]
				pool.remove_at(i)
				active_contracts.append(contract)
				UITheme.show_notification("Contract Accepted: %s" % contract["title"], Color.GOLD)
				bounty_updated.emit()
				return true
	return false

func claim_contract(contract_id: String) -> bool:
	var contract = null
	var idx = -1
	for i in range(active_contracts.size()):
		if active_contracts[i]["id"] == contract_id:
			contract = active_contracts[i]
			idx = i
			break

	if contract == null or not contract["completed"]:
		return false

	# Award credits
	var bonus_mult = 1.0
	# v109: Recursion — Recursive Acquisition (+5%/level Lira rewards)
	if GameState.research_manager:
		bonus_mult *= (1.0 + GameState.research_manager.get_efficiency_bonus("credit_reward_mult"))
	# v132: apply the warp production multiplier — quests AND missions both scale
	# with it; bounties didn't, so they fell a full multiplier tier behind the
	# parallel income systems on every warp ("background always pays" decayed).
	if GameState.warp_manager:
		bonus_mult *= GameState.warp_manager.get_production_multiplier()
	var final_reward = int(contract["reward_credits"] * bonus_mult)

	GameState.resources.add_currency("credits", final_reward)
	UITheme.show_notification("+%s Liras" % UITheme.format_num(final_reward), Color.GOLD)

	# Award module (if pool exists)
	var sm = GameState.shipyard_manager
	var pool = contract["reward_module_pool"]
	if pool.size() > 0:
		var base_id = pool[randi() % pool.size()]

		# v74.0: Bounty High-Tier Rarity Floor (Rare+)
		var is_boss = contract["difficulty"] >= 8
		var leg_chance = 0.25 if is_boss else 0.10
		var rarity = sm.Rarity.LEGENDARY if randf() < leg_chance else sm.Rarity.RARE

		var custom_id = sm.generate_module_drop(base_id, rarity, int(contract.get("difficulty", 1)))
		if custom_id != "":
			var m_name = sm.modules[custom_id]["name"]
			var r_color = sm.RARITY_COLORS.get(rarity, Color.WHITE)
			UITheme.show_notification("Module Received: %s" % m_name, r_color)

		sm.inventory_updated.emit()

	contract["claimed"] = true

	active_contracts.remove_at(idx)
	total_completed += 1

	bounty_updated.emit()
	return true

func abandon_contract(contract_id: String) -> bool:
	var contract = null
	var idx = -1
	for i in range(active_contracts.size()):
		if active_contracts[i]["id"] == contract_id:
			contract = active_contracts[i]
			idx = i
			break

	if contract == null:
		return false

	# Refund materials for LEGACY delivery contracts (pre-v139 saves — deliveries
	# no longer generate, but accepted ones must still refund on abandon).
	if contract["type"] == "delivery" and contract["current_qty"] > 0:
		GameState.resources.add_element(contract["target"], contract["current_qty"])
		UITheme.show_notification("Materials refunded.", Color.YELLOW)

	active_contracts.remove_at(idx)
	UITheme.show_notification("Contract Abandoned.", Color(0.6, 0.6, 0.6))
	bounty_updated.emit()
	return true

# ─── Tick (Refresh Timer) ───

func process_tick(delta: float):
	if refresh_timer <= 0.0:
		# Window unarmed — fresh install, in-session state clear, or the UI
		# lazy-seeded a board before the first tick. Seed every zone board and
		# arm the 8h window (generate_all_pools re-arms, so this fires once).
		generate_all_pools()
		return
	refresh_timer -= delta
	if refresh_timer <= 0:
		# One regeneration regardless of how large the (offline) delta was —
		# boards would only overwrite themselves on multi-window absences.
		generate_all_pools()

# v132: bounty was the ONLY manager without reset() — hard_reset left the old
# playthrough's contracts claimable on a brand-new save. Clears everything and
# reseeds boards at the CURRENT (post-reset) progression tier.
func reset(_decay_factor: float = 1.0) -> void:
	available_by_zone.clear()
	zone_rerolls.clear()
	active_contracts.clear()
	refresh_timer = 0.0
	total_completed = 0
	_id_counter = 0
	generate_all_pools()

# ─── Save/Load ───

func get_save_data_manager() -> Dictionary:
	var by_zone := {}
	for zid in available_by_zone:
		by_zone[zid] = _serialize_contracts(available_by_zone[zid])
	return {
		"available_by_zone": by_zone,
		"zone_rerolls": zone_rerolls.duplicate(),
		"active": _serialize_contracts(active_contracts),
		"refresh_timer": refresh_timer,
		"total_completed": total_completed,
		"id_counter": _id_counter
	}

func load_save_data_manager(data: Dictionary):
	available_by_zone.clear()
	var bz = data.get("available_by_zone", {})
	for zid in bz:
		if bz[zid] is Array:
			available_by_zone[zid] = _deserialize_contracts(bz[zid])
	zone_rerolls.clear()
	var zr = data.get("zone_rerolls", {})
	for zid in zr:
		zone_rerolls[zid] = int(zr[zid])
	active_contracts = _deserialize_contracts(data.get("active", []))
	refresh_timer = data.get("refresh_timer", 0.0)
	total_completed = data.get("total_completed", 0)
	_id_counter = data.get("id_counter", 0)
	# v139 migration: pre-zone-board saves carried one flat "available" pool —
	# discard it (available cards are ephemeral RNG; ACTIVE contracts, including
	# legacy deliveries, were preserved above) and seed the per-zone boards fresh.
	if available_by_zone.is_empty():
		call_deferred("generate_all_pools")

func _serialize_contracts(contracts: Array) -> Array:
	var arr = []
	for c in contracts:
		arr.append(c.duplicate())
	return arr

func _deserialize_contracts(data: Array) -> Array:
	var arr = []
	for c in data:
		if c is Dictionary:
			arr.append(c)
	return arr
