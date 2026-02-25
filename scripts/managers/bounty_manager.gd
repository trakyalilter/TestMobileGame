# v72.0: Bounty Board System
extends RefCounted

signal bounty_updated()

const MAX_ACTIVE = 3
const MAX_AVAILABLE = 6
const REFRESH_INTERVAL = 28800.0 # 8 hours in seconds

var available_contracts: Array = []  # Pool of contracts to pick from
var active_contracts: Array = []     # Accepted contracts (max 3)
var completed_contracts: Array = []  # Ready to claim
var refresh_timer: float = 0.0      # Time until next pool refresh
var total_completed: int = 0        # Lifetime stat

# Contract templates scaled by zone difficulty
# Format: {type, zone_id, target, target_qty, reward_credits, reward_module_pool}
var delivery_materials = {
	# zone_difficulty: [[material_id, min_qty, max_qty, credit_reward]]
	1: [["Cu", 500, 1000, 5000], ["Fe", 300, 600, 8000], ["Si", 200, 400, 6000]],
	2: [["Fe", 800, 1500, 20000], ["Cu", 300, 600, 15000], ["Steel", 100, 250, 30000]],
	3: [["Steel", 250, 500, 50000], ["Ti", 100, 250, 80000], ["Circuit", 100, 200, 60000]],
	4: [["Ti", 300, 600, 120000], ["W", 150, 300, 100000], ["Graphite", 200, 400, 80000]],
	5: [["AdvCircuit", 100, 200, 250000], ["Superalloy", 50, 150, 300000], ["NavData", 100, 250, 200000]],
	6: [["ColonySalvage", 250, 500, 400000], ["AdvCircuit", 150, 300, 350000], ["Steel", 2000, 5000, 500000]],
	7: [["RadIsotope", 200, 500, 600000], ["Pt", 100, 250, 750000], ["Superalloy", 150, 300, 550000]],
	8: [["VoidCrystal", 50, 150, 1000000], ["Diamond", 30, 80, 800000], ["ExoticMatter", 20, 50, 1200000]],
	9: [["BiohazardSample", 100, 250, 1500000], ["MutatedTissue", 50, 150, 1800000], ["PathogenCore", 20, 50, 2000000]],
	10: [["VoidEssence", 50, 100, 5000000], ["ChronoCore", 20, 50, 7500000], ["PrimordialShard", 10, 30, 10000000]]
}

func connect_signals():
	var cm = GameState.combat_manager
	if cm:
		if not cm.enemy_defeated.is_connected(_on_enemy_defeated):
			cm.enemy_defeated.connect(_on_enemy_defeated)
		if not cm.combat_started.is_connected(_on_combat_started):
			cm.combat_started.connect(_on_combat_started)

func get_trophy_buff(buff_type: String) -> float:
	if not GameState.resources: return 1.0
	var res = GameState.resources
	var mult = 1.0
	
	# Check for Epsilon Trophy (Global 5% boost)
	if res.get_element_amount("Trophy_Epsilon") > 0:
		mult += 0.05
		
	match buff_type:
		"gathering_xp":
			if res.get_element_amount("Trophy_Lunar") > 0: mult += 0.25
		"mining_yield":
			if res.get_element_amount("Trophy_Belt") > 0: mult += 0.20
		"processing_xp":
			if res.get_element_amount("Trophy_Mars") > 0: mult += 0.25
		"ship_speed":
			if res.get_element_amount("Trophy_Titan") > 0: mult += 0.10
		"research_speed":
			if res.get_element_amount("Trophy_Alpha") > 0: mult += 0.15
		"infrastructure_yield":
			if res.get_element_amount("Trophy_Beta") > 0: mult += 0.20
		"energy_dmg":
			if res.get_element_amount("Trophy_Gamma") > 0: mult += 0.15
		"kinetic_dmg":
			if res.get_element_amount("Trophy_Delta") > 0: mult += 0.15
		"evasion":
			if res.get_element_amount("Trophy_Zeta") > 0: mult += 0.10
			
	return mult

func _on_enemy_defeated(enemy_id: String):
	for contract in active_contracts:
		if contract["type"] == "hunt" and contract["target"] == enemy_id:
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

# ─── Contract Generation ───

func get_player_max_difficulty() -> int:
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	var max_diff = 1  # Lunar Orbit is always available
	for zid in cm.zones:
		var z = cm.zones[zid]
		var req = z.get("research_req", "")
		if req == "" or rm.is_tech_unlocked(req):
			max_diff = max(max_diff, z["difficulty"])
	return max_diff

func generate_contract_pool():
	available_contracts.clear()
	var max_diff = get_player_max_difficulty()
	var min_diff = max(1, max_diff - 1) # Smart Loot: Keep only top 2 tiers
	
	# Generate a mix of hunt and delivery contracts
	var attempts = 0
	while available_contracts.size() < MAX_AVAILABLE and attempts < 100:
		attempts += 1
		var contract = {}
		var roll = randf()
		if roll < 0.4:
			contract = _generate_hunt_contract(min_diff, max_diff)
		elif roll < 0.7:
			contract = _generate_delivery_contract(min_diff, max_diff)
		else:
			contract = _generate_elite_contract(max_diff) # Elites always at max
		
		if contract.size() > 0:
			# Check for duplicates
			var is_dup = false
			for existing in available_contracts:
				if existing["target"] == contract["target"] and existing["type"] == contract["type"]:
					is_dup = true
					break
			if not is_dup:
				available_contracts.append(contract)
	
	refresh_timer = REFRESH_INTERVAL
	bounty_updated.emit()

func get_refresh_cost() -> int:
	var max_diff = get_player_max_difficulty()
	return max_diff * 5000 # Scales from 5k to 50k

func force_refresh() -> bool:
	var cost = get_refresh_cost()
	if GameState.resources.get_currency("credits") < cost:
		UITheme.show_notification("Not enough credits to refresh!", Color.RED)
		return false
	
	GameState.resources.remove_currency("credits", cost)
	generate_contract_pool()
	UITheme.show_notification("Bounty Board Refreshed", Color.CYAN)
	return true

func _generate_hunt_contract(min_diff: int, max_diff: int) -> Dictionary:
	var cm = GameState.combat_manager
	# Pick a random zone within relevance range
	var valid_zones = []
	for zid in cm.zones:
		var z = cm.zones[zid]
		if z["difficulty"] >= min_diff and z["difficulty"] <= max_diff:
			valid_zones.append({"id": zid, "data": z})
	
	if valid_zones.is_empty():
		return {}
	
	var zone = valid_zones[randi() % valid_zones.size()]
	var enemies = zone["data"]["enemies"]
	var enemy_id = enemies[randi() % enemies.size()]
	var enemy_data = cm.enemy_db.get(enemy_id, {})
	
	if enemy_data.is_empty():
		return {}
	
	var is_boss = enemy_data.get("is_boss", false)
	var qty = randi_range(1, 3) if is_boss else randi_range(5, 20)
	var base_xp = enemy_data.get("xp", 10)
	
	# v73.0: Exponential Credit Scaling
	var diff_mult = pow(zone["data"]["difficulty"], 1.5)
	var credit_reward = int(base_xp * qty * 0.5 * diff_mult)
	
	# Module reward: pick from the zone's enemies' module pools
	var module_pool = _get_zone_module_pool(zone["id"])
	
	return {
		"id": _gen_id(),
		"type": "hunt",
		"title": "Hunt: %s" % enemy_data["name"],
		"desc": "Destroy %d %s in %s." % [qty, enemy_data["name"], zone["data"]["name"]],
		"target": enemy_id,
		"target_qty": qty,
		"current_qty": 0,
		"reward_credits": credit_reward,
		"reward_module_pool": module_pool,
		"zone_id": zone["id"],
		"difficulty": zone["data"]["difficulty"],
		"completed": false,
		"claimed": false,
		"is_elite": false
	}

func _generate_elite_contract(max_diff: int) -> Dictionary:
	var cm = GameState.combat_manager
	var valid_zones = []
	for zid in cm.zones:
		var z = cm.zones[zid]
		if z["difficulty"] <= max_diff:
			valid_zones.append({"id": zid, "data": z})
	
	if valid_zones.is_empty(): return {}
	
	var zone = valid_zones[randi() % valid_zones.size()]
	var enemies = zone["data"]["enemies"]
	var enemy_id = enemies[randi() % enemies.size()]
	var enemy_data = cm.enemy_db.get(enemy_id, {})
	
	if enemy_data.is_empty(): return {}
	
	var qty = 1 # Elites are 1v1 duels
	var base_xp = enemy_data.get("xp", 10)
	
	# v73.0: Elite Jackpot Scaling
	var diff_mult = pow(zone["data"]["difficulty"], 1.2)
	var credit_reward = int(base_xp * 75 * diff_mult)
	
	return {
		"id": _gen_id(),
		"type": "hunt",
		"title": "★ ELITE HUNT ★: %s" % enemy_data["name"],
		"desc": "Destroy the ELITE %s in %s. Warning: Extremely Dangerous." % [enemy_data["name"], zone["data"]["name"]],
		"target": enemy_id,
		"target_qty": qty,
		"current_qty": 0,
		"reward_credits": credit_reward,
		"reward_module_pool": _get_zone_module_pool(zone["id"]),
		"zone_id": zone["id"],
		"difficulty": zone["data"]["difficulty"],
		"completed": false,
		"claimed": false,
		"is_elite": true
	}

func _generate_delivery_contract(min_diff: int, max_diff: int) -> Dictionary:
	# Pick a difficulty tier within relevance range
	var tier = randi_range(min_diff, max_diff)
	var templates = delivery_materials.get(tier, [])
	if templates.is_empty():
		return {}
	
	var t = templates[randi() % templates.size()]
	var mat_id = t[0]
	var qty = randi_range(t[1], t[2])
	var credits = t[3]
	
	# Get display name
	var d_name = ElementDB.get_display_name(mat_id)
	
	# Module reward from nearby zone
	var cm = GameState.combat_manager
	var zone_id = ""
	for zid in cm.zones:
		if cm.zones[zid]["difficulty"] == tier:
			zone_id = zid
			break
	var module_pool = _get_zone_module_pool(zone_id) if zone_id != "" else []
	
	return {
		"id": _gen_id(),
		"type": "delivery",
		"title": "Supply: %s" % d_name,
		"desc": "Deliver %d %s to the station." % [qty, d_name],
		"target": mat_id,
		"target_qty": qty,
		"current_qty": 0,  # For delivery, this tracks if accepted (0 = not accepted yet)
		"reward_credits": credits,
		"reward_module_pool": module_pool,
		"zone_id": zone_id,
		"difficulty": tier,
		"completed": false,
		"claimed": false
	}

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
	
	var contract = null
	var idx = -1
	for i in range(available_contracts.size()):
		if available_contracts[i]["id"] == contract_id:
			contract = available_contracts[i]
			idx = i
			break
	
	if contract == null:
		return false
	
	# Delivery contracts: Check and consume materials on acceptance
	if contract["type"] == "delivery":
		var sm = GameState.shipyard_manager
		var logi_edge = sm.affix_bonuses.get("logistician_edge", 0.0)
		var effective_qty = int(contract["target_qty"] * (1.0 - logi_edge))
		
		var has_mats = GameState.resources.has_element(contract["target"], effective_qty)
		if not has_mats:
			var d_name = ElementDB.get_display_name(contract["target"])
			UITheme.show_notification("Not enough %s! (Need %d)" % [d_name, effective_qty], Color.RED)
			return false
		GameState.resources.remove_element(contract["target"], effective_qty)
		contract["current_qty"] = effective_qty # Track what was actually spent
		contract["completed"] = true
	
	available_contracts.remove_at(idx)
	active_contracts.append(contract)
	
	UITheme.show_notification("Contract Accepted: %s" % contract["title"], Color.GOLD)
	bounty_updated.emit()
	return true

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
	var sm = GameState.shipyard_manager
	var bonus_mult = 1.0 + sm.affix_bonuses.get("contract_negotiation", 0.0)
	var final_reward = int(contract["reward_credits"] * bonus_mult)
	
	GameState.resources.add_currency("credits", final_reward)
	UITheme.show_notification("+%s Credits" % UITheme.format_num(final_reward), Color.GOLD)
	
	# Award module (if pool exists)
	var pool = contract["reward_module_pool"]
	if pool.size() > 0:
		var base_id = pool[randi() % pool.size()]
		
		# v74.0: Bounty High-Tier Rarity Floor (Rare+)
		var is_boss = contract["difficulty"] >= 8
		var leg_chance = 0.25 if is_boss else 0.10
		var rarity = sm.Rarity.LEGENDARY if randf() < leg_chance else sm.Rarity.RARE
		
		var custom_id = sm.generate_module_drop(base_id, rarity)
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
	
	# Refund materials for delivery contracts
	if contract["type"] == "delivery" and contract["current_qty"] > 0:
		GameState.resources.add_element(contract["target"], contract["current_qty"])
		UITheme.show_notification("Materials refunded.", Color.YELLOW)
	
	active_contracts.remove_at(idx)
	UITheme.show_notification("Contract Abandoned.", Color(0.6, 0.6, 0.6))
	bounty_updated.emit()
	return true

# ─── Tick (Refresh Timer) ───

func process_tick(delta: float):
	if refresh_timer > 0:
		refresh_timer -= delta
		if refresh_timer <= 0:
			generate_contract_pool()

# ─── Save/Load ───

func get_save_data_manager() -> Dictionary:
	return {
		"available": _serialize_contracts(available_contracts),
		"active": _serialize_contracts(active_contracts),
		"refresh_timer": refresh_timer,
		"total_completed": total_completed,
		"id_counter": _id_counter
	}

func load_save_data_manager(data: Dictionary):
	available_contracts = _deserialize_contracts(data.get("available", []))
	active_contracts = _deserialize_contracts(data.get("active", []))
	refresh_timer = data.get("refresh_timer", 0.0)
	total_completed = data.get("total_completed", 0)
	_id_counter = data.get("id_counter", 0)
	
	# If no available contracts, generate fresh pool
	if available_contracts.is_empty() and active_contracts.is_empty():
		call_deferred("generate_contract_pool")

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
