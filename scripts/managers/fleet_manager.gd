extends Skill

signal activity_occurred

# --- MISSION DATABASE ---
# Each mission provides a different passive stream of resources.
var missions = {
	"scavenge_alpha": {
		"name": "Alpha Sector Scavenging",
		"desc": "Passive yield of Titanium and Iron.",
		"yield": {"Ti": 1.0, "Fe": 5.0, "Scrap": 2.0},
		"interval": 10.0,
		"risk": 0.05,
		"min_tier": 1,
		"research_req": "sector_alpha_decryption"
	},
	"harvest_nebula": {
		"name": "Nebula Harvester",
		"desc": "Passive yield of Hydrogen and Helium.",
		"yield": {"H": 10.0, "He": 2.0, "O": 5.0},
		"interval": 10.0,
		"risk": 0.1,
		"min_tier": 2,
		"research_req": "deep_space_nav"
	},
	"tech_recovery": {
		"name": "Gamma Tech Recovery",
		"desc": "Passive yield of SalvageData and DroneCores.",
		"yield": {"SalvageData": 0.5, "DroneCore": 0.1, "Circuit": 1.0},
		"interval": 15.0,
		"risk": 0.2,
		"min_tier": 3,
		"research_req": "radiation_shielding"
	},
	"void_mining": {
		"name": "Void Crystal Extraction",
		"desc": "Passive yield of Void Crystals and Exotic Matter.",
		"yield": {"VoidCrystal": 0.2, "ExoticMatter": 0.1, "credits": 5000},
		"interval": 20.0,
		"risk": 0.35,
		"min_tier": 4,
		"research_req": "void_navigation"
	}
}

# --- FLEET STATE ---
# active_expeditions: {slot_index: {mission_id, hull_id, stats, progress_timer}}
var active_expeditions: Dictionary = {}
var max_slots: int = 1 # Increasable via research

# Audit v9.0: Damage Buffer System - No auto-deduct, player repairs on return
var pending_repairs: Dictionary = {} # {hull_id: accumulated_damage_cost}

func _init():
	super._init("Administration")
	# Audit v5.0 P2-15: Add early fleet mission
	missions["local_salvage"] = {
		"name": "Local Debris Salvage",
		"desc": "Passive yield of Iron and Scrap from nearby debris.",
		"yield": {"Fe": 2.0, "Cu": 1.0, "Scrap": 3.0},
		"interval": 8.0,
		"risk": 0.02,
		"min_tier": 1,
		"research_req": "fleet_logistics_1"
	}

# Audit v5.0 P2-16: Administration skill bonus - +1% yield per level
func get_yield_multiplier() -> float:
	return 1.0 + (get_level() * 0.01)

# --- CORE LOGIC ---

func get_available_missions() -> Array:
	var available = []
	for mid in missions:
		var m = missions[mid]
		if m.get("research_req") == null or GameState.research_manager.is_tech_unlocked(m["research_req"]):
			available.append(mid)
	return available

func deploy_fleet(slot_idx: int, mission_id: String, hull_id: String) -> bool:
	# Update max_slots from research
	if GameState.research_manager:
		max_slots = int(GameState.research_manager.get_efficiency_bonus("fleet_slots"))

	if slot_idx >= max_slots: return false
	if active_expeditions.has(slot_idx): return false
	if not mission_id in missions: return false
	
	# Verify hull is not active ship
	if hull_id == GameState.shipyard_manager.active_hull:
		return false
		
	# Verify tier requirements
	var hull_data = GameState.shipyard_manager.hulls.get(hull_id)
	if not hull_data: return false
	
	var mission_data = missions[mission_id]
	if hull_data["tier"] < mission_data["min_tier"]:
		return false
		
	active_expeditions[slot_idx] = {
		"mission_id": mission_id,
		"hull_id": hull_id,
		"progress": 0.0,
		"total_earned": {}
	}
	
	print("[Fleet] Deployed %s to %s" % [hull_id, mission_id])
	return true

func recall_fleet(slot_idx: int):
	if active_expeditions.has(slot_idx):
		active_expeditions.erase(slot_idx)

func process_tick(delta: float):
	var speed_bonus = 0.0
	if GameState.research_manager:
		speed_bonus = GameState.research_manager.get_efficiency_bonus("fleet_speed")

	for slot in active_expeditions:
		var exp = active_expeditions[slot]
		var data = missions[exp["mission_id"]]
		
		# Effective Interval: Base / (1.0 + bonus)
		var effective_interval = data["interval"] / (1.0 + speed_bonus)
		
		exp["progress"] += delta
		if exp["progress"] >= effective_interval:
			_resolve_mission_tick(slot)
			exp["progress"] = 0.0

func _resolve_mission_tick(slot: int):
	var exp = active_expeditions[slot]
	var data = missions[exp["mission_id"]]
	
	# Audit v5.0 P1-18: Apply ship efficiency (damaged ships work slower)
	var efficiency = get_ship_efficiency(exp["hull_id"])
	
	# Risk Check (Structural Damage)
	if randf() < data["risk"] * 0.1: # Scaled risk per tick
		var damage = randi_range(50, 200)
		_apply_structural_damage(exp["hull_id"], damage)
		
	# Audit v5.0 P1-16: Apply prestige production multiplier
	var prod_mult = 1.0
	if GameState.warp_manager:
		prod_mult = GameState.warp_manager.get_production_multiplier()
	
	# Audit v5.0 P2-16: Apply Administration skill bonus
	var skill_mult = get_yield_multiplier()
	
	# Payout with all multipliers
	var final_mult = efficiency * prod_mult * skill_mult
	for res in data["yield"]:
		var qty = data["yield"][res] * final_mult
		if res == "credits":
			GameState.resources.add_currency("credits", qty)
		else:
			GameState.resources.add_element(res, qty)
		
		exp["total_earned"][res] = exp["total_earned"].get(res, 0.0) + qty
	
	# Audit v5.0 P0-7: Scale XP by mission tier (20/40/60/80)
	var base_xp = data["min_tier"] * 20
	add_xp(base_xp)
	activity_occurred.emit()

func _apply_structural_damage(hull_id, amount):
	# Audit v9.0: Damage Buffer System
	# Damage accumulates in pending_repairs instead of auto-deducting
	# Player chooses when to repair - ships run at reduced efficiency when damaged
	var reduction = 1.0
	if GameState.infrastructure_manager:
		var docks = GameState.infrastructure_manager.get_building_count("repair_docks")
		reduction = max(0.1, 1.0 - (docks * 0.1)) # 10% per dock, cap at 90% reduction
	
	var base_cost = amount * 10
	var final_cost = int(base_cost * reduction)
	
	# Buffer damage instead of auto-deduct
	pending_repairs[hull_id] = pending_repairs.get(hull_id, 0) + final_cost
	print("[Fleet] Ship %s sustained damage! Pending repair cost: %d Cr" % [hull_id, pending_repairs[hull_id]])

func get_pending_repair_cost(hull_id: String) -> int:
	return pending_repairs.get(hull_id, 0)

func get_total_pending_repairs() -> int:
	var total = 0
	for hull_id in pending_repairs:
		total += pending_repairs[hull_id]
	return total

func repair_ship(hull_id: String) -> bool:
	var cost = pending_repairs.get(hull_id, 0)
	if cost <= 0: return true
	
	var current = GameState.resources.get_currency("credits")
	if current >= cost:
		GameState.resources.add_currency("credits", -cost)
		pending_repairs.erase(hull_id)
		print("[Fleet] Ship %s repaired for %d Cr" % [hull_id, cost])
		return true
	return false

func repair_all_ships() -> int:
	var repaired = 0
	for hull_id in pending_repairs.keys():
		if repair_ship(hull_id):
			repaired += 1
	return repaired

func get_ship_efficiency(hull_id: String) -> float:
	# Ships with pending repairs operate at reduced efficiency
	var damage = pending_repairs.get(hull_id, 0)
	if damage <= 0: return 1.0
	# Efficiency drops by 1% per 1000 credits of damage, min 50%
	return max(0.5, 1.0 - (damage / 100000.0))

# Offline Support
func calculate_offline(delta: float) -> String:
	var speed_bonus = 0.0
	if GameState.research_manager:
		speed_bonus = GameState.research_manager.get_efficiency_bonus("fleet_speed")

	var report = "Fleet Command Offline Gains:\n"
	var total_loot = {}
	var ships_damaged = 0
	
	for slot in active_expeditions:
		var exp = active_expeditions[slot]
		var data = missions[exp["mission_id"]]
		
		var effective_interval = data["interval"] / (1.0 + speed_bonus)
		var cycles = int(delta / effective_interval)
		if cycles <= 0: continue
		
		# Loot
		for res in data["yield"]:
			var total = data["yield"][res] * cycles
			if res == "credits":
				GameState.resources.add_currency("credits", total)
			else:
				GameState.resources.add_element(res, total)
			total_loot[res] = total_loot.get(res, 0.0) + total
			exp["total_earned"][res] = exp["total_earned"].get(res, 0.0) + total
			
		# Damage Probability (Approximation for offline)
		var damage_prob = data["risk"] * 0.1 * cycles
		if randf() < damage_prob:
			ships_damaged += 1
			# Use the protected function to handle docks and protection
			_apply_structural_damage(exp["hull_id"], randi_range(500, 2000))
			
		add_xp(5 * cycles)

	if total_loot.is_empty(): return ""
	
	for res in total_loot:
		report += " + %s: %d\n" % [res, total_loot[res]]
	if ships_damaged > 0:
		report += " ! %d Fleet repairs needed.\n" % ships_damaged
		
	return report

func get_save_data_manager() -> Dictionary:
	var data = get_save_data()
	data["active_expeditions"] = active_expeditions
	data["max_slots"] = max_slots
	data["pending_repairs"] = pending_repairs
	return data

func load_save_data_manager(data: Dictionary):
	load_save_data(data)
	active_expeditions = data.get("active_expeditions", {})
	max_slots = data.get("max_slots", 1)
	pending_repairs = data.get("pending_repairs", {})

func reset(decay_factor: float = 1.0) -> void:
	super.reset(decay_factor)
	active_expeditions.clear()
	pending_repairs.clear()
	max_slots = 1
