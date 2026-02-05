extends Skill

var in_combat = false

var current_zone = null
var current_enemy = null
var target_enemy_id = null

# Battle State (Enemies only, player uses shipyard_manager.current_hp)
var player_shield = 0.0
var player_max_shield = 0.0

var enemy_hp = 0
var enemy_max_hp = 100
var enemy_shield = 0.0
var enemy_max_shield = 0.0

# Thermal State (Audit v12.0)
var player_heat = 0.0
var player_max_heat = 100.0
var player_vent_rate = 5.0 # Units per second
var overheat_lock = 0.0 # Timer when overheat occurs
signal heat_changed(current, maximum)


# Battery State
var player_weapon_states: Array = [] # {name, type, timer, interval, dmg_k, dmg_e, slot_idx}
var enemy_attack_timer = 0.0

# Log & Events
var combat_log: Array[String] = []
var combat_events: Array[Dictionary] = [] # [{type, text, color, side}]

# Consumables
var equipped_consumable_id = null
var auto_consume_enabled = false
var auto_consume_threshold = 0.3
var consumable_cooldown = 0.0
var consumable_cooldown_max = 10.0

signal enemy_defeated(enemy_id)

# Buffs
var active_buffs = {} # {buff_name: duration}

# Session Tracking
var session_loot = {} # {item_id: total_amount}

# Balanced Phase 2 Buffs
var broadside_timer = 0.0
var coolant_flush_timer = 0.0

# Forensic 3: Logic Fixes
var shield_regen_accumulator = 0.0

# Audit v9.0: HoT & Jamming
var nanite_hot_timer = 0.0
var nanite_hot_duration = 15.0
var is_jammed = false

var zones = {
	"lunar_orbit": {
		"name": "Lunar Orbit",
		"desc": "Low threat sector populated by rogue mining drones.",
		"difficulty": 1,
		"enemies": ["lunar_drone", "dust_mite", "scrap_collector", "survey_probe"]
	},
	"asteroid_belt": {
		"name": "Asteroid Belt",
		"desc": "Dense field with pirate skiffs and kinetic hazards.",
		"difficulty": 2,
		"enemies": ["pirate_skiff", "rock_golem", "claim_jumper", "ore_hauler"]
	},
	"mars_debris": {
		"name": "Mars Debris Field",
		"desc": "Wreckage of the old Martian shipyards. Scavengers abound.",
		"difficulty": 3,
		"enemies": ["scavenger_mech", "martian_sentry", "derelict_frigate", "salvage_swarm"]
	},
	"titan_halo": {
		"name": "Titan's Halo",
		"desc": "Frozen rings around the gas giant. Extreme cold and pirate lords.",
		"difficulty": 4,
		"enemies": ["cryo_drone", "pirate_gunship", "frozen_hulk", "smuggler_cutter"]
	},
	"sector_alpha": {
		"name": "Sector Alpha",
		"desc": "Uncharted region rich in Titanium. High threat.",
		"difficulty": 5,
		"enemies": ["alien_frigate", "xenon_corvette", "xenon_mothership"],
		"research_req": "sector_alpha_decryption"
	},
	"sector_beta": {
		"name": "Sector Beta - Mining Colony Ruins",
		"desc": "Abandoned mining colony. Automated defense systems hostile. Rich in industrial metals.",
		"difficulty": 6,
		"enemies": ["mining_sentinel", "defense_turret", "colony_overseer"],
		"research_req": "deep_space_nav"
	},
	"sector_gamma": {
		"name": "Sector Gamma - Radioactive Nebula",
		"desc": "Radioactive nebula. Mutated organisms detected. Extreme danger.",
		"difficulty": 7,
		"enemies": ["radiation_beast", "nebula_leviathan", "gamma_colossus"],
		"research_req": "radiation_shielding"
	},
	"sector_delta": {
		"name": "Sector Delta - Crystalline Fields",
		"desc": "Crystalline asteroid field. Unknown energy signatures. Ultimate challenge.",
		"difficulty": 8,
		"enemies": ["crystal_golem", "energy_wraith", "sentinel_prime"],
		"research_req": "exotic_matter_analysis"
	},
	# ENDGAME ZONE - Added to address retention cliff after Dreadnought
	"sector_epsilon": {
		"name": "Sector Epsilon - The Void",
		"desc": "Beyond known space. Primordial entities and temporal anomalies. Requires Dreadnought-class vessel.",
		"difficulty": 10,
		"enemies": ["void_stalker", "temporal_phantom", "omega_sentinel", "primordial_titan"],
		"research_req": "void_navigation"
	}
}

var enemy_db = {
	"dust_mite": {
		"name": "Space Dust Mite",
		"stats": {"hp": 50, "max_shield": 0, "atk": 3, "def": 0, "atk_interval": 2.5, "accuracy": 0},
		"loot": [["Scrap", 1, 2], ["MiteChitin", 1, 1]],
		"xp": 8
	},
	"lunar_drone": {
		"name": "Lunar Drone",
		"stats": {"hp": 60, "max_shield": 0, "atk": 5, "def": 1, "atk_interval": 2.5, "accuracy": 5},
		"loot": [["Scrap", 3, 5], ["Fe", 4, 10], ["DroneCore", 1, 1]],
		"rare_loot": [["Cu", 0.3, 1, 2], ["Chip", 0.08, 1, 1], ["SalvageData", 0.20, 1, 1]], 
		"xp": 12
	},
	"scrap_collector": {
		"name": "Scrap Collector",
		"stats": {"hp": 350, "max_shield": 0, "atk": 20, "def": 5, "atk_interval": 2.2, "accuracy": 10},
		"loot": [["Scrap", 7, 12], ["Res1", 2, 5]],
		"rare_loot": [["DroneCore", 0.30, 1, 2]],
		"xp": 10
	},
	"survey_probe": {
		"name": "Derelict Survey Probe",
		"stats": {"hp": 600, "max_shield": 50, "atk": 35, "def": 18, "atk_interval": 2.5, "accuracy": 15},
		"loot": [["Si", 5, 8], ["Cu", 1, 2], ["SalvageData", 1, 1], ["NavData", 2, 2]],
		"rare_loot": [["Chip", 0.15, 2, 3]],
		"xp": 25
	},
	"claim_jumper": {
		"name": "Claim Jumper",
		"stats": {"hp": 2000, "max_shield": 100, "atk": 4, "def": 20, "atk_interval": 2.2, "accuracy": 20},
		"loot": [["credits", 250, 450], ["Cu", 15, 30], ["StolenCargo", 1, 1]],
		"rare_loot": [["NavData", 0.15, 2, 5]],
		"xp": 50
	},
	"ore_hauler": {
		"name": "Ore Hauler Wreck",
		"stats": {"hp": 4500, "max_shield": 0, "atk": 80, "def": 40, "atk_interval": 5.0, "accuracy": 25},
		"loot": [["Fe", 150, 300], ["W", 100, 200], ["Scrap", 10, 20]],
		"rare_loot": [["U", 0.20, 2, 5]], 
		"xp": 80
	},
	"derelict_frigate": {
		"name": "Derelict Frigate",
		"stats": {"hp": 12000, "max_shield": 500, "atk": 150, "def": 65, "atk_interval": 4.0, "accuracy": 30},
		"loot": [["Steel", 5, 12], ["Scrap", 20, 40], ["Res2", 5, 10]],
		"rare_loot": [["Circuit", 0.35, 2, 4], ["Chip", 0.20, 2, 2]],
		"xp": 250
	},
	"salvage_swarm": {
		"name": "Salvage Swarm",
		"stats": {"hp": 2500, "max_shield": 0, "atk": 60, "def": 10, "atk_interval": 0.6, "accuracy": 35},
		"loot": [["Scrap", 10, 20], ["SwarmFragment", 1, 2]],
		"rare_loot": [["Resin", 0.3, 1, 2], ["Cu", 0.2, 1, 2]],
		"xp": 35
	},
	"frozen_hulk": {
		"name": "Frozen Hulk",
		"stats": {"hp": 6500, "max_shield": 250, "atk": 18, "def": 70, "atk_interval": 6.0, "accuracy": 40},
		"loot": [["C", 10, 20]],
		"rare_loot": [["Graphite", 0.35, 1, 3], ["W", 0.15, 1, 2]],
		"xp": 75
	},
	"smuggler_cutter": {
		"name": "Smuggler Cutter",
		"stats": {"hp": 450, "max_shield": 180, "atk": 32, "def": 25, "accuracy": 45},
		"loot": [["credits", 100, 200]],
		"rare_loot": [["Li", 0.25, 1, 3], ["Ti", 0.2, 1, 2]],
		"xp": 95
	},
	"pirate_skiff": {
		"name": "Pirate Skiff",
		"stats": {"hp": 2250, "max_shield": 150, "atk": 35, "def": 22, "atk_interval": 1.75, "accuracy": 50},
		"loot": [["credits", 2000, 6000], ["Scrap", 3, 6], ["PirateManifest", 1, 1], ["NavData", 1, 2], ["Cu", 100, 200]],
		"rare_loot": [["W", 0.40, 10, 20], ["Ti", 0.30, 40, 50]],
		"xp": 30
	},
	"rock_golem": {
		"name": "Silicate Golem",
		"stats": {"hp": 3600, "max_shield": 0, "atk": 60, "def": 12, "accuracy": 20},
		"loot": [["Si", 100, 200]],
		"rare_loot": [["Ti", 0.4, 10, 20]],
		"xp": 30
	},
	"scavenger_mech": {
		"name": "Scavenger Mech",
		"stats": {"hp": 4000, "max_shield": 100, "atk": 25, "def": 60, "accuracy": 40},
		"loot": [["Cu", 5, 10], ["Scrap", 5, 10]],
		"rare_loot": [["W", 0.3, 5, 10], ["Res2", 0.20, 1, 1], ["NavData", 0.25, 1, 2]],
		"xp": 55
	},
	"martian_sentry": {
		"name": "Martian Sentry",
		"stats": {"hp": 250, "max_shield": 250, "atk": 30, "def": 10, "accuracy": 50},
		"loot": [["C", 5, 10]],
		"rare_loot": [["Resin", 0.1, 1, 2], ["Chip", 0.25, 1, 2]],
		"xp": 60
	},
	"cryo_drone": {
		"name": "Cryo Drone",
		"stats": {"hp": 300, "max_shield": 400, "atk": 20, "def": 20, "accuracy": 60},
		"loot": [["H", 5, 15], ["Water", 5, 10], ["CryoCell", 1, 1]],
		"rare_loot": [["Mesh", 0.05, 1, 1]],
		"xp": 75
	},
	"pirate_gunship": {
		"name": "Pirate Gunship",
		"stats": {"hp": 800, "max_shield": 300, "atk": 45, "def": 40, "accuracy": 65},
		"loot": [["credits", 50, 150], ["Ti", 1, 3]],
		"rare_loot": [["Seal", 0.05, 1, 1], ["NavData", 0.2, 1, 3], ["Res2", 0.30, 1, 2]],
		"xp": 120
	},
	"alien_frigate": {
		"name": "Xenon Patrol Frigate",
		"stats": {"hp": 12000, "max_shield": 8000, "atk": 120, "def": 50, "atk_interval": 3.0, "accuracy": 45},
		"loot": [["Ti", 15, 30], ["Scrap", 30, 60]],
		"rare_loot": [["NavData", 0.3, 2, 5], ["Chip", 0.3, 2, 5], ["VoidArtifact", 0.15, 1, 2], ["Co", 0.15, 2, 4], ["Ni", 0.15, 2, 4], ["Res3", 0.30, 5, 10]], 
		"xp": 500
	},
	"xenon_corvette": {
		"name": "Xenon Corvette",
		"stats": {"hp": 25000, "max_shield": 15000, "atk": 400, "def": 80, "atk_interval": 2.5, "accuracy": 80},
		"loot": [["Ti", 20, 50], ["U", 5, 15]],
		"rare_loot": [["NavData", 0.4, 3, 7], ["VoidArtifact", 0.3, 2, 4], ["Cr", 0.10, 1, 3], ["Res3", 0.25, 5, 8]],
		"xp": 800
	},
	"xenon_mothership": {
		"name": "XENON MOTHERSHIP",
		"stats": {"hp": 150000, "max_shield": 80000, "atk": 1200, "def": 250, "atk_interval": 6.0, "accuracy": 100},
		"loot": [["Ti", 200, 500], ["Chip", 25, 50], ["AdvCircuit", 10, 20], ["QuantumCore", 5, 10], ["VoidArtifact", 10, 25], ["Res3", 50, 100]],
		"rare_loot": [],
		"xp": 5000
	},
	"mining_sentinel": {
		"name": "Mining Sentinel MK-VII",
		"stats": {"hp": 60000, "max_shield": 25000, "atk": 800, "def": 120, "atk_interval": 3.0, "accuracy": 90, "jammer": true},
		"loot": [["ColonySalvage", 10, 20], ["Steel", 50, 100]],
		"rare_loot": [["Co", 0.3, 5, 15], ["Ni", 0.3, 5, 15], ["Circuit", 0.3, 10, 25]],
		"xp": 8000
	},
	"defense_turret": {
		"name": "Automated Defense Turret",
		"stats": {"hp": 100000, "max_shield": 0, "atk": 1500, "def": 250, "atk_interval": 2.5, "accuracy": 100},
		"loot": [["ColonySalvage", 25, 50], ["Circuit", 20, 50], ["TurretCore", 1, 1]],
		"rare_loot": [["Cr", 0.3, 5, 10], ["AdvCircuit", 0.4, 5, 10]],
		"xp": 15000
	},
	"colony_overseer": {
		"name": "Colony Overseer AI",
		"stats": {"hp": 80000, "max_shield": 40000, "atk": 1000, "def": 150, "atk_interval": 3.5, "accuracy": 120, "jammer": true},
		"loot": [["AdvCircuit", 10, 20], ["ColonySalvage", 20, 40], ["ColonyDataCore", 1, 1]],
		"rare_loot": [["Pd", 0.3, 2, 5], ["AICore", 0.25, 1, 1], ["Chip", 0.25, 5, 10]],
		"xp": 20000
	},
	"radiation_beast": {
		"name": "Gamma Radiation Beast",
		"stats": {"hp": 20000, "max_shield": 12000, "atk": 150, "def": 70, "accuracy": 90},
		"loot": [["RadIsotope", 1, 3], ["U", 5, 10], ["Zn", 3, 6]],
		"rare_loot": [["Pt", 0.15, 1, 2], ["ReactiveCore", 0.2, 1, 1]],
		"xp": 500
	},
	"nebula_leviathan": {
		"name": "Nebula Leviathan",
		"stats": {"hp": 35000, "max_shield": 20000, "atk": 200, "def": 90, "accuracy": 100},
		"loot": [["RadIsotope", 3, 5], ["U", 10, 20], ["Graphite", 15, 25]],
		"rare_loot": [["Pt", 0.25, 1, 3], ["Pd", 0.2, 1, 2], ["ExoticMatter", 0.1, 1, 1]],
		"xp": 800
	},
	"gamma_colossus": {
		"name": "GAMMA COLOSSUS",
		"stats": {"hp": 500000, "max_shield": 200000, "atk": 3000, "def": 400, "atk_interval": 5.0, "accuracy": 130, "jammer": true},
		"loot": [["RadIsotope", 50, 100], ["Pt", 25, 50], ["QuantumCore", 5, 10], ["ExoticIsotope", 1, 3]],
		"rare_loot": [["Ir", 0.5, 5, 15]],
		"xp": 30000
	},
	"crystal_golem": {
		"name": "Crystalline Golem",
		"stats": {"hp": 50000, "max_shield": 0, "atk": 180, "def": 200, "accuracy": 120},
		"loot": [["VoidCrystal", 1, 3], ["Si", 50, 100], ["Diamond", 1, 3]],
		"rare_loot": [["Ir", 0.2, 1, 2], ["SyntheticCrystal", 0.15, 1, 1]],
		"xp": 1500
	},
	"energy_wraith": {
		"name": "Energy Wraith",
		"stats": {"hp": 30000, "max_shield": 50000, "atk": 250, "def": 50, "accuracy": 130},
		"loot": [["ExoticMatter", 2, 5], ["VoidCrystal", 2, 4], ["H", 20, 40]],
		"rare_loot": [["AntimatterParticle", 0.1, 1, 1], ["VoidCrystal", 0.25, 2, 3]],
		"xp": 1800
	},
	"crystal_sentinel": {
		"name": "SENTINEL PRIME",
		"stats": {"hp": 150000, "max_shield": 80000, "atk": 400, "def": 180, "accuracy": 150},
		"loot": [["VoidCrystal", 5, 10], ["Ir", 10, 20], ["QuantumCore", 2, 4]],
		"rare_loot": [["Os", 0.25, 1, 3], ["AncientTech", 0.2, 1, 1]],
		"xp": 5000
	},
	"void_stalker": {
		"name": "Void Stalker",
		"stats": {"hp": 200000, "max_shield": 150000, "atk": 600, "def": 300, "atk_interval": 2.0, "accuracy": 150},
		"loot": [["credits", 100000, 200000], ["VoidCrystal", 10, 20], ["ExoticMatter", 5, 10]],
		"rare_loot": [["VoidEssence", 0.30, 1, 2], ["QuantumCore", 0.5, 2, 4]],
		"xp": 8000
	},
	"temporal_phantom": {
		"name": "Temporal Phantom",
		"stats": {"hp": 150000, "max_shield": 250000, "atk": 500, "def": 200, "atk_interval": 1.5, "accuracy": 160},
		"loot": [["credits", 150000, 300000], ["ExoticMatter", 8, 15], ["VoidCrystal", 5, 10], ["AntimatterParticle", 1, 2]],
		"rare_loot": [["ChronoCore", 0.25, 1, 1], ["VoidEssence", 0.2, 1, 2]],
		"xp": 10000
	},
	"omega_sentinel": {
		"name": "OMEGA SENTINEL",
		"stats": {"hp": 500000, "max_shield": 300000, "atk": 1000, "def": 500, "atk_interval": 3.0, "accuracy": 180},
		"loot": [["credits", 300000, 600000], ["VoidCrystal", 20, 40], ["QuantumCore", 5, 10], ["Ir", 20, 40]],
		"rare_loot": [["OmegaPlating", 0.40, 1, 2], ["ChronoCore", 0.3, 1, 1], ["Os", 0.25, 2, 4]],
		"xp": 25000
	},
	"primordial_titan": {
		"name": "★ PRIMORDIAL TITAN ★",
		"stats": {"hp": 2000000, "max_shield": 1000000, "atk": 2500, "def": 800, "atk_interval": 5.0, "accuracy": 200},
		"loot": [["credits", 5000000, 15000000], ["VoidCrystal", 100, 200], ["QuantumCore", 20, 40], ["OmegaPlating", 5, 10], ["PrimordialShard", 1, 3], ["ChronoCore", 2, 4], ["VoidEssence", 5, 10]],
		"rare_loot": [],
		"xp": 100000
	}
}

func _init():
	super._init("Combat")

func get_available_zones() -> Array:
	var available = []
	for zid in zones:
		var data = zones[zid]
		var req = data.get("research_req")
		if req:
			if GameState.research_manager.is_tech_unlocked(req):
				available.append({"id": zid, "data": data})
		else:
			available.append({"id": zid, "data": data})
	return available

func start_expedition(zone_id: String):
	if not zone_id in zones: return
	if current_zone == zones[zone_id] and in_combat: return
	GameState.set_active_manager(self)
	current_zone = zones[zone_id]
	in_combat = true
	session_loot.clear()
	spawn_enemy()
	log_msg("Warped to %s." % current_zone["name"])

func set_target_enemy(enemy_id):
	if enemy_id and enemy_id in enemy_db:
		GameState.set_active_manager(self)
		target_enemy_id = enemy_id
		in_combat = true
		spawn_enemy()
		log_msg("Targeting: %s" % enemy_db[enemy_id]["name"])
	else:
		target_enemy_id = null

func spawn_enemy():
	var eid = target_enemy_id if target_enemy_id else current_zone["enemies"][randi() % current_zone["enemies"].size()]
	var e_data = enemy_db[eid]
	current_enemy = {
		"id": eid,
		"name": e_data["name"],
		"max_hp": e_data["stats"]["hp"],
		"atk": e_data["stats"]["atk"],
		"def": e_data["stats"]["def"],
		"accuracy": e_data["stats"].get("accuracy", 0),
		"max_shield": e_data["stats"].get("max_shield", 0),
		"loot": e_data["loot"],
		"rare_loot": e_data.get("rare_loot", []),
		"xp": e_data["xp"],
		"jammer": e_data["stats"].get("jammer", false)
	}
	is_jammed = current_enemy["jammer"]
	enemy_hp = current_enemy["max_hp"]
	enemy_max_hp = enemy_hp
	enemy_shield = float(current_enemy["max_shield"])
	enemy_max_shield = enemy_shield
	
	var sm = GameState.shipyard_manager
	player_max_shield = sm.max_shield
	player_weapon_states.clear()
	var equipped_weapons = []
	for s_idx in sm.loadout:
		var mid = sm.loadout[s_idx]
		if mid and mid in sm.modules:
			var m_data = sm.modules[mid]
			if m_data.get("slot_type") == "weapon":
				var m_stats = m_data.get("stats", {})
				equipped_weapons.append({
					"name": m_data["name"],
					"type": "kinetic" if m_stats.get("atk_kinetic", 0) > 0 else "energy",
					"timer": randf_range(0.0, 0.5),
					"interval": m_stats.get("atk_interval", 2.5),
					"dmg_k": m_stats.get("atk_kinetic", 0),
					"dmg_e": m_stats.get("atk_energy", 0),
					"slot_idx": int(s_idx),
					"energy_load": m_data.get("energy_load", 0)
				})
	if equipped_weapons.is_empty():
		var h_stats = sm.hulls[sm.active_hull]["stats"]
		player_weapon_states.append({"name": "Standard Cannon", "type": "kinetic", "timer": 0.0, "interval": 3.0, "dmg_k": h_stats["atk"], "dmg_e": 0, "slot_idx": -1, "energy_load": 0})
	else:
		player_weapon_states.append_array(equipped_weapons)
	log_msg("Readying Weapon Battery: %d systems online." % player_weapon_states.size())

func retreat():
	in_combat = false
	current_enemy = null
	log_msg("Emergency Warp engaged!")

func stop_action():
	retreat()

func process_tick(delta: float):
	if not in_combat or not current_enemy: return
	var sm = GameState.shipyard_manager
	var rm = GameState.research_manager
	var p_speed_mult = (1.0 + rm.get_efficiency_bonus("attack_speed") + sm.attack_speed_bonus) * GameState.warp_manager.get_combat_multiplier()
	
	if overheat_lock > 0:
		overheat_lock -= delta
		sm.current_hp -= sm.max_hp * 0.025 * delta
	if player_heat > 0:
		player_heat = max(0, player_heat - player_vent_rate * delta)
		heat_changed.emit(player_heat, player_max_heat)
	if player_heat > 80.0: p_speed_mult *= 0.5
	
	if enemy_shield < enemy_max_shield:
		enemy_shield = min(enemy_max_shield, enemy_shield + (enemy_max_shield * 0.02 * delta))
	
	for slot in sm.loadout:
		if sm.loadout[slot] == "warp_stabilizer":
			p_speed_mult += 0.15
			break
			
	for w_idx in range(player_weapon_states.size()):
		var w = player_weapon_states[w_idx]
		w["timer"] += delta * p_speed_mult
		if w["timer"] >= w["interval"]:
			_execute_player_attack(w_idx)
			w["timer"] = 0.0
		
	enemy_attack_timer += delta 
	if enemy_attack_timer >= current_enemy.get("atk_interval", 3.0):
		_execute_enemy_attack()
		enemy_attack_timer = 0.0
	if consumable_cooldown > 0: consumable_cooldown -= delta
	if nanite_hot_timer > 0:
		nanite_hot_timer -= delta
		sm.current_hp = min(sm.max_hp, sm.current_hp + (sm.max_hp * 0.02) * delta)
	if coolant_flush_timer > 0:
		coolant_flush_timer -= delta
		p_speed_mult *= 2.0
		
	var has_broadside = false
	for slot in sm.loadout:
		if sm.loadout[slot] == "broadside_array":
			has_broadside = true
			break
	if has_broadside and in_combat:
		broadside_timer += delta
		if broadside_timer >= 20.0:
			_execute_broadside_burst()
			broadside_timer = 0.0
			
	shield_regen_accumulator += delta
	if shield_regen_accumulator >= 1.0:
		if player_shield < player_max_shield:
			player_shield = min(player_max_shield, player_shield + (sm.shield_regen * (1.0 + rm.get_efficiency_bonus("shield_regen") + sm.shield_regen_bonus)))
		shield_regen_accumulator = 0.0

func _execute_player_attack(weapon_idx: int):
	var w = player_weapon_states[weapon_idx]
	var sm = GameState.shipyard_manager
	if overheat_lock > 0: return
	var e_cost = w.get("energy_load", 0) * 0.1
	if GameState.resources.get_energy() < e_cost:
		log_msg("LACK OF ENERGY: Weapon Offline!")
		return
	GameState.resources.add_energy(-e_cost)
	if is_jammed and randf() < 0.25:
		combat_events.append({"type": "miss", "text": "JAMMED", "color": Color.ORANGE, "side": "enemy"})
		return

	if auto_consume_enabled and equipped_consumable_id:
		if sm.current_hp < auto_consume_threshold * sm.max_hp: use_consumable()
		elif equipped_consumable_id == "Mesh" and player_shield < auto_consume_threshold * player_max_shield: use_consumable()

	player_heat += 2.0 + ((w["dmg_k"] + w["dmg_e"]) / 100.0)
	heat_changed.emit(player_heat, player_max_heat)
	if player_heat >= player_max_heat:
		player_heat = player_max_heat
		overheat_lock = 5.0
		return

	var p_atk_k = w["dmg_k"]
	var p_atk_e = w["dmg_e"]
	if w["type"] == "energy":
		for slot in sm.loadout:
			if sm.loadout[slot] == "plasma_overcharger":
				p_atk_e *= 2.0
				break
	
	var ammo_id = sm.ammo_loadout.get(w["slot_idx"])
	if ammo_id and ammo_id != "":
		if GameState.resources.get_element_amount(ammo_id) > 0:
			GameState.resources.remove_element(ammo_id, 1)
			if ammo_id.begins_with("Slug"): p_atk_k *= 1.25 if "T2" in ammo_id else (1.5 if "T3" in ammo_id else 1.1)
			else: p_atk_e *= 1.25 if "T2" in ammo_id else (1.5 if "T3" in ammo_id else 1.1)
		else: return
	else: return
		
	var skill_dmg_mult = 1.0 + (get_level() * 0.005)
	var res = resolve_damage(p_atk_k * skill_dmg_mult, p_atk_e * skill_dmg_mult, enemy_shield, current_enemy["def"], current_zone.get("difficulty", 1))
	enemy_shield = max(0, enemy_shield - res[0])
	enemy_hp -= res[1]
	if res[0] > 0: combat_events.append({"type": "dmg_shield", "text": "-%d" % res[0], "color": Color.CYAN, "side": "enemy"})
	if res[1] > 0: combat_events.append({"type": "dmg_hull", "text": "-%d" % res[1], "color": Color.RED, "side": "enemy"})
	if enemy_hp <= 0: win_fight()

func _execute_enemy_attack():
	var sm = GameState.shipyard_manager
	var e_acc = current_enemy.get("accuracy", 0)
	var dodge_chance = min(float(sm.evasion) / (float(sm.evasion) + 150.0 * (1.0 + float(e_acc) / 100.0)), 0.75)
	if randf() < dodge_chance:
		combat_events.append({"type": "miss", "text": "MISS", "color": Color.WHITE, "side": "player"})
	else:
		var difficulty = current_zone.get("difficulty", 1)
		var eres = resolve_damage(current_enemy["atk"], 0, player_shield, sm.defense, difficulty)
		player_shield = max(0, player_shield - eres[0])
		sm.current_hp -= eres[1]
		if eres[0] > 0: combat_events.append({"type": "dmg_shield", "text": "-%d" % eres[0], "color": Color.CYAN, "side": "player"})
		if eres[1] > 0: combat_events.append({"type": "dmg_hull", "text": "-%d" % eres[1], "color": Color.RED, "side": "player"})
	if sm.current_hp <= 0: lose_fight()

func resolve_damage(atk_k, atk_e, c_shield, c_armor, difficulty = 1):
	var shield_dmg_pot = (atk_k * 0.5) + (atk_e * 1.5)
	var damage_to_shield = min(c_shield, shield_dmg_pot)
	var bleed_ratio = (shield_dmg_pot - damage_to_shield) / shield_dmg_pot if shield_dmg_pot > 0 else 1.0
	var k = max(20.0, float(difficulty) * 50.0)
	var hull_dmg = ((atk_k * 1.2 * (1.0 - c_armor/(c_armor+k))) + (atk_e * 0.9 * (1.0 - (c_armor*0.7)/(c_armor*0.7+k)))) * bleed_ratio
	var variance = randf_range(0.9, 1.1)
	var is_crit = randf() < 0.05
	if is_crit: variance *= 1.5
	return [int(damage_to_shield * variance), int(max(1.0 if (atk_k+atk_e)>0 else 0, hull_dmg * variance)), is_crit]

func win_fight():
	log_msg("Destroyed %s!" % current_enemy["name"])
	for entry in current_enemy["loot"]:
		var qty = randi_range(entry[1], entry[2])
		if entry[0] == "credits": GameState.resources.add_currency("credits", qty)
		else: GameState.resources.add_element(entry[0], qty)
		session_loot[entry[0]] = session_loot.get(entry[0], 0) + qty
	for entry in current_enemy.get("rare_loot", []):
		if randf() < entry[1]:
			var qty = randi_range(entry[2], entry[3])
			GameState.resources.add_element(entry[0], qty)
			session_loot[entry[0]] = session_loot.get(entry[0], 0) + qty
	add_xp(int(current_enemy["xp"] * (1.0 + GameState.research_manager.get_efficiency_bonus("combat_xp"))))
	enemy_defeated.emit(current_enemy["id"])
	spawn_enemy()

func lose_fight():
	var sm = GameState.shipyard_manager
	var cost = sm.get_full_repair_cost(sm.active_hull)
	GameState.resources.add_currency("credits", -cost)
	retreat()

func equip_consumable(item_id):
	equipped_consumable_id = item_id

func toggle_auto_consume(enabled):
	auto_consume_enabled = enabled

func use_consumable():
	if not in_combat or not equipped_consumable_id or consumable_cooldown > 0: return
	if GameState.resources.get_element_amount(equipped_consumable_id) < 1: return
	GameState.resources.remove_element(equipped_consumable_id, 1)
	consumable_cooldown = consumable_cooldown_max
	var edata = GameState.get_element_data(equipped_consumable_id)
	var effect = edata.get("effect", "")
	var value = edata.get("value", 0)
	if effect == "heal_hull" and value > 0:
		var sm = GameState.shipyard_manager
		sm.current_hp = min(sm.max_hp, sm.current_hp + value)
		combat_events.append({"type": "heal", "text": "+%d HP" % value, "color": Color.GREEN, "side": "player"})
	elif effect == "heal_shield" and value > 0:
		player_shield = min(player_max_shield, player_shield + value)
		combat_events.append({"type": "heal", "text": "+%d Shield" % value, "color": Color.CYAN, "side": "player"})
	if equipped_consumable_id == "NitroCoolant": coolant_flush_timer = 10.0
	elif equipped_consumable_id == "nanite_swarm": nanite_hot_timer = 15.0

func _execute_broadside_burst():
	var e_cost = 100.0
	if GameState.resources.get_energy() < e_cost: return
	GameState.resources.add_energy(-e_cost)
	var total_kinetic_dps = 0.0
	for w in player_weapon_states:
		if w["type"] == "kinetic": total_kinetic_dps += (w["dmg_k"] / w["interval"])
	if total_kinetic_dps <= 0: total_kinetic_dps = GameState.shipyard_manager.attack * 0.2
	var final_dmg = int(total_kinetic_dps * 60.0 * (1.0 - float(current_enemy["def"])/(current_enemy["def"]+20.0)))
	enemy_hp -= max(1, final_dmg)
	combat_events.append({"type": "dmg_hull", "text": "BURST %d" % final_dmg, "color": Color.GOLD, "side": "enemy"})
	if enemy_hp <= 0: win_fight()

func log_msg(msg: String):
	combat_log.append(msg)
	if combat_log.size() > 20: combat_log.pop_front()

func get_save_data_manager() -> Dictionary: return get_save_data()
func load_save_data_manager(data: Dictionary): load_save_data(data)
func reset(decay_factor: float = 1.0) -> void:
	super.reset(decay_factor)
	retreat()
