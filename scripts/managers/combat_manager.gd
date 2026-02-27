extends Skill

var in_combat = false

var current_zone = null
var current_zone_id: String = "" # Track explicitly for saving
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
var player_vent_rate = 8.0 # Units per second
var overheat_lock = 0.0 # Timer when overheat occurs
signal heat_changed(current, maximum)


# Battery State
var player_weapon_states: Array = [] # {name, type, timer, interval, dmg_k, dmg_e, slot_idx}
var enemy_attack_timer = 0.0

# Log & Events
var combat_log: Array[String] = []
var combat_events: Array[Dictionary] = [] # [{type, text, color, side}]

# Consumables
var consumable_cooldown = 0.0
var consumable_cooldown_max = 1.5

signal enemy_defeated(enemy_id)
signal combat_started() # v72.8: For Elite bounty detection

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

# Phase 19 Unique States
var enemy_speed_mult = 1.0
var has_reflective = false
var has_reactive = false
var has_exotic_matrix = false
var next_spawn_elite = false # v72.8: Flag for elite hunt contracts

# Step 5: Boss Set Bonus Flags
var has_cryo_set = false
var has_sovereign_set = false
var has_patient_zero_set = false

# Progression compensation so external multipliers (level/research/warp/trophy)
# don't invalidate zone pacing.
const ENEMY_COMP_REGULAR_HP = 0.28
const ENEMY_COMP_REGULAR_SHIELD = 0.24
const ENEMY_COMP_REGULAR_ATK = 0.18
const ENEMY_COMP_BOSS_HP = 0.42
const ENEMY_COMP_BOSS_SHIELD = 0.36
const ENEMY_COMP_BOSS_ATK = 0.28
const ENEMY_COMP_DEF = 0.12

func _module_matches(module_id, base_module_id: String) -> bool:
	if not (module_id is String):
		return false
	if module_id == "" or base_module_id == "":
		return false
	if module_id == base_module_id:
		return true
	var sm = GameState.shipyard_manager
	if not sm:
		return false
	if module_id not in sm.modules:
		return false
	return sm.modules[module_id].get("base_module", "") == base_module_id

func _loadout_has_module(sm: Object, base_module_id: String) -> bool:
	if not sm:
		return false
	for slot in sm.loadout:
		var mid = sm.loadout[slot]
		if _module_matches(mid, base_module_id):
			return true
	return false

# Combat Milestone Bonuses (Phase 21)
func get_milestone_crit_bonus() -> float:
	if get_level() >= 10: return 0.05 # +5% Crit at Lv.10
	return 0.0

func get_milestone_evasion_bonus() -> int:
	if get_level() >= 25: return 15 # +15 Evasion at Lv.25
	return 0

func get_milestone_heat_mult() -> float:
	if get_level() >= 75: return 1.25 # +25% Heat Dissipation at Lv.75
	return 1.0

func is_auto_consume_unlocked() -> bool:
	return get_level() >= 50 # Auto-Consume at Lv.50

func get_external_progression_combat_mult() -> float:
	var rm = GameState.research_manager
	var bm = GameState.bounty_manager
	var combat_mult = 1.0 + (get_level() * 0.005)
	var processing_mult = 1.0
	if GameState.processing_manager:
		processing_mult += GameState.processing_manager.get_level() * 0.01
	
	var research_speed_mult = 1.0
	if rm:
		research_speed_mult += max(0.0, rm.get_efficiency_bonus("attack_speed"))
	
	var warp_mult = 1.0
	if GameState.warp_manager:
		warp_mult = max(1.0, GameState.warp_manager.get_combat_multiplier())
	
	var trophy_mult = 1.0
	if bm:
		var dmg_mult = (max(1.0, bm.get_trophy_buff("kinetic_dmg")) + max(1.0, bm.get_trophy_buff("energy_dmg"))) * 0.5
		var speed_mult = max(1.0, bm.get_trophy_buff("ship_speed"))
		trophy_mult = dmg_mult * speed_mult
	
	return clamp(combat_mult * processing_mult * research_speed_mult * warp_mult * trophy_mult, 1.0, 6.0)

var zones = {
	"lunar_orbit": {
		"name": "Lunar Orbit",
		"desc": "Low threat sector populated by rogue mining drones.",
		"difficulty": 1,
		"enemies": ["lunar_drone", "dust_mite", "scrap_collector", "survey_probe", "rogue_architect"]
	},
	"asteroid_belt": {
		"name": "Asteroid Belt",
		"desc": "Dense field with pirate skiffs and kinetic hazards.",
		"difficulty": 2,
		"enemies": ["pirate_skiff", "rock_golem", "claim_jumper", "ore_hauler", "silicate_monolith"],
		"research_req": "asteroid_clearance"
	},
	"mars_debris": {
		"name": "Mars Debris Field",
		"desc": "Wreckage of the old Martian shipyards. Scavengers abound.",
		"difficulty": 3,
		"enemies": ["scavenger_mech", "martian_sentry", "derelict_frigate", "salvage_swarm", "martian_warmaster"],
		"research_req": "mars_license"
	},
	"titan_halo": {
		"name": "Titan's Halo",
		"desc": "Frozen rings around the gas giant. Extreme cold and pirate lords.",
		"difficulty": 4,
		"enemies": ["cryo_drone", "pirate_gunship", "frozen_hulk", "smuggler_cutter", "titan_overseer", "cryo_lord"],
		"research_req": "outer_system_auth"
	},
	"sector_alpha": {
		"name": "Sector Alpha",
		"desc": "Uncharted region rich in Titanium. High threat.",
		"difficulty": 5,
		"enemies": ["alien_frigate", "xenon_corvette", "xenon_mothership", "xenon_scout", "alien_probe", "xenon_harbinger"], # v57.0: +2
		"research_req": "sector_alpha_decryption"
	},
	"sector_beta": {
		"name": "Sector Beta",
		"desc": "Abandoned mining colony. Automated defense systems hostile. Rich in industrial metals.",
		"difficulty": 6,
		"enemies": ["mining_sentinel", "defense_turret", "colony_overseer", "repair_drone", "ore_guardian", "overseer_prime"], # v57.0: +2
		"research_req": "deep_space_nav"
	},
	"sector_gamma": {
		"name": "Sector Gamma",
		"desc": "Radioactive nebula. Mutated organisms detected. Extreme danger.",
		"difficulty": 7,
		"enemies": ["radiation_beast", "nebula_leviathan", "gamma_colossus", "irradiated_hulk", "plasma_wraith", "rad_beast_alpha"], # v57.0: +2
		"research_req": "radiation_shielding"
	},
	"sector_delta": {
		"name": "Sector Delta",
		"desc": "Crystalline asteroid field. Unknown energy signatures. Ultimate challenge.",
		"difficulty": 8,
		"enemies": ["crystal_golem", "energy_wraith", "sentinel_prime", "shard_swarm", "prism_guardian", "prismatic_sovereign"], # v57.0: +2
		"research_req": "exotic_matter_analysis"
	},
	# ENDGAME ZONE - Added to address retention cliff after Dreadnought
	# v57.0: Added Sector Zeta (Difficulty 9) to bridge Delta → Epsilon gap
	"sector_zeta": {
		"name": "Sector Zeta",
		"desc": "Sealed sector containing ancient alien pathogens and rogue AI. Extreme biohazard.",
		"difficulty": 9,
		"enemies": ["plague_drone", "bio_horror", "rogue_ai_core", "quarantine_warden", "patient_zero"],
		"research_req": "quarantine_protocols"
	},
	"sector_epsilon": {
		"name": "Sector Epsilon",
		"desc": "Beyond known space. Primordial entities and temporal anomalies. Requires Dreadnought-class vessel.",
		"difficulty": 10,
		"enemies": ["void_stalker", "temporal_phantom", "omega_sentinel", "primordial_titan", "void_leviathan", "time_weaver"],
		"research_req": "void_navigation"
	}
}

var enemy_db = {
	"dust_mite": {
		"name": "Space Dust Mite",
		"stats": {"hp": 550, "atk": 45, "def": 10, "atk_interval": 2.5, "accuracy": 20}, # Early game tweak
		"loot": [["Fe", 1, 3], ["MiteChitin", 1, 1]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"],
		"xp": 8
	},
	"lunar_drone": {
		"name": "Lunar Drone",
		"stats": {"hp": 850, "atk": 65, "def": 15, "atk_interval": 2.5, "accuracy": 20},
		"loot": [["Cu", 2, 4], ["Fe", 3, 6], ["DroneCore", 1, 1]],
		"rare_loot": [["Cu", 0.3, 1, 2], ["Chip", 0.08, 1, 1], ["SalvageData", 0.20, 1, 1]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"],
		"xp": 12
	},
	"scrap_collector": {
		"name": "Scrap Collector",
		"stats": {"hp": 1100, "atk": 50, "def": 12, "atk_interval": 2.2, "accuracy": 25},
		"loot": [["Cu", 5, 10], ["Res1", 2, 5], ["DroneCore", 2, 5]],
		"rare_loot": [["NavData", 0.33, 1, 2]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"],
		"xp": 10
	},
	"survey_probe": {
		"name": "Survey Probe",
		"stats": {"hp": 1400, "max_shield": 400, "atk": 30, "def": 18, "atk_interval": 1.0, "accuracy": 30},
		"loot": [["credits", 100, 250], ["Si", 10, 20]],
		"rare_loot": [["Circuit", 0.1, 1, 1], ["NavData", 0.05, 1, 1]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"],
		"xp": 25
	},
	"claim_jumper": {
		"name": "Claim Jumper",
		"stats": {"hp": 4800, "max_shield": 1200, "atk": 155, "def": 38, "atk_interval": 2.2, "accuracy": 45}, # Starts approaching Zone 1 boss (6k/180/45)
		"loot": [["credits", 250, 450], ["Cu", 15, 30], ["StolenCargo", 1, 1]],
		"rare_loot": [["NavData", 0.15, 2, 5]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"],
		"xp": 50
	},
	"ore_hauler": {
		"name": "Ore Hauler Wreck",
		"stats": {"hp": 7500, "atk": 220, "def": 45, "atk_interval": 5.0, "accuracy": 40}, # Exceeds Z1 boss due to low RoF
		"loot": [["Fe", 50, 70], ["W", 15, 20]],
		"rare_loot": [["U", 0.20, 2, 5], ["Ag", 0.15, 1, 3]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"],
		"xp": 80
	},
	"derelict_frigate": {
		"name": "Derelict Frigate",
		"stats": {"hp": 14500, "max_shield": 3500, "atk": 420, "def": 75, "atk_interval": 4.0, "accuracy": 65}, # Approaches Z2 Boss (12k/350/65)
		"loot": [["Steel", 5, 10], ["Fe", 20, 40], ["Res2", 5, 10]],
		"rare_loot": [["Circuit", 0.35, 2, 4], ["Chip", 0.20, 2, 2]],
		"module_drop_chance": 0.15,
		"module_drop_pool": ["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"],
		"is_boss": true,
		"xp": 250
	},
	"salvage_swarm": {
		"name": "Salvage Swarm",
		"stats": {"hp": 9500, "atk": 110, "def": 55, "atk_interval": 0.6, "accuracy": 60}, # Fast attack
		"loot": [["Cu", 10, 20], ["SwarmFragment", 1, 2]],
		"rare_loot": [["Resin", 0.3, 1, 2], ["Cu", 0.2, 1, 2]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"],
		"xp": 35
	},
	"frozen_hulk": {
		"name": "Frozen Hulk",
		"stats": {"hp": 38000, "max_shield": 8000, "atk": 1400, "def": 105, "atk_interval": 6.0, "accuracy": 95}, # Approaches Z3 Boss (45k/1500/110)
		"loot": [["C", 10, 20]],
		"rare_loot": [["Graphite", 0.35, 1, 3], ["W", 0.15, 1, 2]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"],
		"xp": 75
	},
	"smuggler_cutter": {
		"name": "Smuggler Cutter",
		"stats": {"hp": 22000, "max_shield": 16000, "atk": 850, "def": 85, "accuracy": 100}, 
		"loot": [["credits", 100, 200]],
		"rare_loot": [["Li", 0.25, 1, 3], ["Ti", 0.2, 1, 2]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["mining_laser_mk1", "railgun_mk1", "battery_t1", "basic_shield", "basic_thruster", "lidar_array"],
		"xp": 95
	},
	"pirate_skiff": {
		"name": "Pirate Skiff",
		"stats": {"hp": 5200, "max_shield": 1800, "atk": 165, "def": 42, "atk_interval": 1.8, "accuracy": 45}, # Target: Z1 Boss
		"loot": [["credits", 2000, 6000], ["Fe", 10, 20], ["PirateManifest", 1, 1], ["NavData", 1, 2], ["Cu", 100, 200]],
		"rare_loot": [["W", 0.40, 10, 20], ["Ti", 0.30, 40, 50]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["mining_laser_mk2", "micro_missile_launcher", "heatsink_array", "battery_t2", "thermal_tile", "titanium_armor", "aluminum_hull_patch", "plasma_drive", "stasis_web"],
		"xp": 30
	},
	"rock_golem": {
		"name": "Silicate Golem",
		"stats": {"hp": 6500, "atk": 190, "def": 48, "accuracy": 45},
		"loot": [["Si", 100, 200], ["Fe", 10, 20]], # Added Fe for Ammo Sustenance (Audit Round 2)
		"rare_loot": [["Ti", 0.4, 10, 20]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["mining_laser_mk2", "micro_missile_launcher", "heatsink_array", "battery_t2", "thermal_tile", "titanium_armor", "aluminum_hull_patch", "plasma_drive", "stasis_web"],
		"xp": 30
	},
	"scavenger_mech": {
		"name": "Scavenger Mech",
		"stats": {"hp": 11500, "max_shield": 2200, "atk": 310, "def": 60, "accuracy": 65}, # Target: Z2 Boss
		"loot": [["Cu", 10, 20]],
		"rare_loot": [["W", 0.3, 5, 10], ["Res2", 0.20, 1, 1], ["NavData", 0.25, 1, 2]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["mining_laser_mk2", "micro_missile_launcher", "heatsink_array", "battery_t2", "thermal_tile", "titanium_armor", "aluminum_hull_patch", "plasma_drive", "stasis_web"],
		"xp": 55
	},
	"martian_sentry": {
		"name": "Martian Sentry",
		"stats": {"hp": 7500, "max_shield": 6500, "atk": 380, "def": 58, "accuracy": 70}, 
		"loot": [["C", 5, 10]],
		"rare_loot": [["Resin", 0.1, 1, 2], ["Chip", 0.25, 1, 2], ["Rh", 0.10, 1, 2]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["mining_laser_mk2", "micro_missile_launcher", "heatsink_array", "battery_t2", "thermal_tile", "titanium_armor", "aluminum_hull_patch", "plasma_drive", "stasis_web"],
		"xp": 60
	},
	"cryo_drone": {
		"name": "Cryo Drone",
		"stats": {"hp": 35000, "max_shield": 12000, "atk": 1250, "def": 95, "accuracy": 95}, # Target Z3 Boss
		"loot": [["H", 5, 15], ["Water", 5, 10], ["CryoCell", 1, 1]],
		"rare_loot": [["Mesh", 0.05, 1, 1]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["mining_laser_mk2", "micro_missile_launcher", "heatsink_array", "battery_t2", "thermal_tile", "titanium_armor", "aluminum_hull_patch", "plasma_drive", "stasis_web"],
		"xp": 75
	},
	"pirate_gunship": {
		"name": "Pirate Gunship",
		"stats": {"hp": 25000, "max_shield": 12000, "atk": 550, "def": 75, "accuracy": 110}, # Buffed from 20k/8k/350
		"loot": [["credits", 50, 150], ["Ti", 1, 3]],
		"rare_loot": [["Seal", 0.05, 1, 1], ["NavData", 0.2, 1, 3], ["Res2", 0.30, 1, 2]],
		"module_drop_chance": 0.15,
		"module_drop_pool": ["mining_laser_mk2", "micro_missile_launcher", "heatsink_array", "battery_t2", "thermal_tile", "titanium_armor", "aluminum_hull_patch", "plasma_drive", "stasis_web"],
		"is_boss": true,
		"xp": 2500
	},
	"titan_overseer": {
		"name": "TITAN OVERSEER",
		"stats": {"hp": 120000, "max_shield": 40000, "atk": 3500, "def": 180, "accuracy": 160}, # Massive Buff: from 30k/10k/400
		"loot": [["TitanClearance", 1, 1], ["Ti", 50, 100]],
		"rare_loot": [["CryoCell", 0.50, 1, 2], ["Res2", 0.50, 2, 4]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["missile_launcher_mk2", "cryo_vent", "targeting_matrix", "railgun_mk2", "advanced_shield", "composite_armor", "mg_al_frame", "galvanized_plating", "battery_t3"],
		"xp": 15000
	},
	"alien_frigate": {
		"name": "Xenon Patrol Frigate",
		"stats": {"hp": 60000, "max_shield": 22000, "atk": 1150, "def": 145, "accuracy": 120}, # Target Z4 Boss (65k/150)
		"loot": [["credits", 15000, 20000], ["Ti", 30, 60]],
		"rare_loot": [["NavData", 0.35, 2, 5], ["Chip", 0.35, 2, 5], ["VoidArtifact", 0.3, 2, 3], ["Co", 0.35, 2, 4], ["Ni", 0.35, 2, 4], ["Res3", 0.35, 1, 2]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "superalloy_engine", "ai_targeting_system", "broadside_array"],
		"xp": 500
	},
	"xenon_corvette": {
		"name": "Xenon Corvette",
		"stats": {"hp": 68000, "max_shield": 30000, "atk": 1350, "def": 150, "atk_interval": 2.5, "accuracy": 125, "eva": 25}, 
		"loot": [["credits", 40000, 60000], ["Superalloy", 1, 2], ["VoidArtifact", 2, 4], ["NavData", 4, 8], ["Res3", 2, 3], ["Ti", 50, 100], ["U", 5, 15]],
		"rare_loot": [],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "superalloy_engine", "ai_targeting_system", "signal_jammer"],
		"xp": 800
	},
	"xenon_mothership": {
		"name": "XENON MOTHERSHIP",
		"stats": {"hp": 180000, "max_shield": 60000, "atk": 1800, "def": 120, "atk_interval": 6.0, "accuracy": 150, "eva": 30}, # Buffed from 100k/30k/800
		"loot": [["credits", 700000, 1000000], ["Superalloy", 30, 50], ["Chip", 30, 50], ["AdvCircuit", 10, 20], ["QuantumCore", 5, 10], ["VoidArtifact", 10, 25], ["Res3", 50, 100]],
		"rare_loot": [["warmaster_railgun", 0.15, 1, 1], ["warmaster_armor", 0.15, 1, 1], ["warmaster_drive", 0.15, 1, 1]], 
		"module_drop_chance": 0.15,
		"module_drop_pool": ["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "superalloy_engine", "ai_targeting_system", "broadside_array"],
		"is_boss": true,
		"xp": 10000
	},
	"mining_sentinel": {
		"name": "Mining Sentinel MK-VII",
		"stats": {"hp": 170000, "max_shield": 55000, "atk": 1750, "def": 120, "accuracy": 140, "jammer": true}, # Target Z5 Boss (180k/120)
		"loot": [["ColonySalvage", 10, 20], ["Steel", 50, 100]],
		"rare_loot": [["Co", 0.3, 5, 15], ["Ni", 0.3, 5, 15], ["Circuit", 0.3, 10, 25]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "superalloy_engine", "ai_targeting_system", "signal_jammer"],
		"xp": 8000
	},
	"defense_turret": {
		"name": "Automated Defense Turret",
		"stats": {"hp": 210000, "atk": 2100, "def": 135, "atk_interval": 2.5, "accuracy": 150},
		"loot": [["ColonySalvage", 25, 50], ["Circuit", 20, 50], ["TurretCore", 1, 1]],
		"rare_loot": [["Cr", 0.3, 5, 10], ["AdvCircuit", 0.4, 5, 10]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "superalloy_engine", "ai_targeting_system", "broadside_array"],
		"xp": 15000
	},
	"colony_overseer": {
		"name": "Colony Overseer AI",
		"stats": {"hp": 250000, "max_shield": 100000, "atk": 2500, "def": 180, "atk_interval": 3.5, "accuracy": 160, "jammer": true}, # Buffed from 150k/60k/900
		"loot": [["AdvCircuit", 20, 30], ["ColonySalvage", 20, 40], ["ColonyDataCore", 5, 7]],
		"rare_loot": [["overseer_turret", 0.15, 1, 1], ["overseer_bulkhead", 0.15, 1, 1], ["overseer_matrix", 0.15, 1, 1]],
		"module_drop_chance": 0.15,
		"module_drop_pool": ["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "superalloy_engine", "ai_targeting_system", "broadside_array"],
		"is_boss": true,
		"xp": 35000
	},
	"radiation_beast": {
		"name": "Gamma Radiation Beast",
		"stats": {"hp": 260000, "max_shield": 85000, "atk": 2400, "def": 180, "accuracy": 160}, # Target Z6 Boss (250k/180)
		"loot": [["credits", 750000, 1000000], ["RadIsotope", 1, 3], ["U", 100, 150]],
		"rare_loot": [["ReactiveCore", 0.2, 1, 1]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["cryo_laser_mk3", "antimatter_engine", "iridium_armor", "reactive_core_battery", "iridium_penetrator", "platinum_laser", "reactive_armor", "plasma_overcharger", "exotic_shield_matrix"],
		"xp": 500
	},
	"nebula_leviathan": {
		"name": "Nebula Leviathan",
		"stats": {"hp": 500000, "max_shield": 200000, "atk": 4500, "def": 250, "accuracy": 180}, # Buffed from 300k/100k/1200
		"loot": [["credits", 3000000, 5000000], ["Pd", 100, 200], ["RadIsotope", 3, 5], ["U", 700, 1000]],
		"rare_loot": [["ExoticMatter", 0.1, 1, 1], ["rad_beast_spitter", 0.15, 1, 1], ["rad_beast_flesh", 0.15, 1, 1], ["rad_beast_gland", 0.15, 1, 1]],
		"module_drop_chance": 0.15,
		"module_drop_pool": ["cryo_laser_mk3", "plasma_overcharger", "iridium_armor"],
		"is_boss": true,
		"xp": 60000
	},
	"gamma_colossus": {
		"name": "GAMMA COLOSSUS",
		"stats": {"hp": 310000, "max_shield": 110000, "atk": 2850, "def": 190, "atk_interval": 2.5, "accuracy": 165, "jammer": true},
		"loot": [["RadIsotope", 50, 100], ["Pt", 25, 50], ["QuantumCore", 5, 10], ["ExoticIsotope", 1, 3]],
		"rare_loot": [["Ir", 0.5, 5, 15]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["cryo_laser_mk3", "antimatter_engine", "iridium_armor", "reactive_core_battery", "iridium_penetrator", "platinum_laser", "reactive_armor", "plasma_overcharger", "exotic_shield_matrix"],
		"xp": 30000
	},
	"crystal_golem": {
		"name": "Crystalline Golem",
		"stats": {"hp": 550000, "atk": 4800, "def": 255, "accuracy": 185}, # Target Z7 Boss (500k/250)
		"loot": [["VoidCrystal", 1, 3], ["Si", 50, 100], ["Diamond", 1, 3]],
		"rare_loot": [["Ir", 0.2, 1, 2], ["SyntheticCrystal", 0.15, 1, 1]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["quantum_dissipator", "omni_scanner", "torpedo_launcher", "osmium_core_module", "palladium_fuel_cell", "reflective_sheath", "diamond_edge_railgun", "crystal_lens_laser"],
		"xp": 1500
	},
	"energy_wraith": {
		"name": "Energy Wraith",
		"stats": {"hp": 480000, "max_shield": 280000, "atk": 5200, "def": 240, "accuracy": 190},
		"loot": [["ExoticMatter", 2, 5], ["VoidCrystal", 2, 4], ["H", 20, 40]],
		"rare_loot": [["AntimatterParticle", 0.1, 1, 1], ["VoidCrystal", 0.25, 2, 3]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["quantum_dissipator", "omni_scanner", "torpedo_launcher", "osmium_core_module", "palladium_fuel_cell", "reflective_sheath", "diamond_edge_railgun", "crystal_lens_laser"],
		"xp": 1800
	},
	"sentinel_prime": {
		"name": "SENTINEL PRIME",
		"stats": {"hp": 1500000, "max_shield": 500000, "atk": 7500, "def": 500, "accuracy": 200}, # Buffed from 1M/300k/2000
		"loot": [["VoidCrystal", 5, 10], ["Ir", 10, 20], ["QuantumCore", 2, 4]],
		"rare_loot": [["Os", 0.25, 1, 3], ["sovereign_laser", 0.15, 1, 1], ["sovereign_crystal", 0.15, 1, 1], ["sovereign_barrier", 0.15, 1, 1]],
		"module_drop_chance": 0.15,
		"module_drop_pool": ["quantum_dissipator", "omni_scanner", "torpedo_launcher", "osmium_core_module", "palladium_fuel_cell", "reflective_sheath", "diamond_edge_railgun", "crystal_lens_laser"],
		"is_boss": true,
		"xp": 150000
	},
	"void_stalker": {
		"name": "Void Stalker",
		"stats": {"hp": 1800000, "max_shield": 600000, "atk": 8500, "def": 550, "atk_interval": 2.0, "accuracy": 210, "eva": 60}, # Target Z8 Boss (1.5M/500)
		"loot": [["credits", 100000, 200000], ["VoidCrystal", 10, 20], ["ExoticMatter", 5, 10]],
		"rare_loot": [["VoidEssence", 0.50, 1, 2], ["QuantumCore", 0.5, 2, 4]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["omega_armor", "primordial_core", "omega_beam", "void_battery_array", "temporal_drive", "primordial_fortification", "omega_singularity", "void_breaker_laser"],
		"xp": 8000
	},
	"temporal_phantom": {
		"name": "Temporal Phantom",
		"stats": {"hp": 2100000, "max_shield": 1000000, "atk": 9500, "def": 580, "atk_interval": 1.5, "accuracy": 220, "eva": 80},
		"loot": [["credits", 150000, 300000], ["ExoticMatter", 8, 15], ["VoidCrystal", 5, 10], ["AntimatterParticle", 1, 2]],
		"rare_loot": [["ChronoCore", 0.25, 1, 1], ["VoidEssence", 0.2, 1, 2]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["omega_armor", "primordial_core", "omega_beam", "void_battery_array", "temporal_drive", "primordial_fortification", "omega_singularity", "void_breaker_laser"],
		"xp": 10000
	},
	"omega_sentinel": {
		"name": "OMEGA SENTINEL",
		"stats": {"hp": 3500000, "max_shield": 1800000, "atk": 16000, "def": 780, "accuracy": 235, "eva": 40}, # Target Z9 Boss (3M/900)
		"loot": [["credits", 300000, 600000], ["VoidCrystal", 20, 40], ["QuantumCore", 5, 10], ["Ir", 20, 40]],
		"rare_loot": [["OmegaPlating", 0.40, 1, 2], ["ChronoCore", 0.3, 1, 1], ["Os", 0.25, 2, 4], ["Neutronium", 0.15, 1, 2]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["omega_armor", "primordial_core", "omega_beam", "void_battery_array", "temporal_drive", "primordial_fortification", "omega_singularity", "void_breaker_laser"],
		"xp": 25000
	},
	"primordial_titan": {
		"name": "★ PRIMORDIAL TITAN ★",
		"stats": {"hp": 7500000, "max_shield": 3000000, "atk": 24000, "def": 950, "atk_interval": 5.0, "accuracy": 250, "eva": 50},
		"loot": [["credits", 5000000, 15000000], ["VoidCrystal", 100, 200], ["QuantumCore", 20, 40], ["OmegaPlating", 5, 10], ["PrimordialShard", 1, 3], ["ChronoCore", 2, 4], ["VoidEssence", 5, 10]],
		"rare_loot": [],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["omega_armor", "primordial_core", "omega_beam", "void_battery_array", "temporal_drive", "primordial_fortification", "omega_singularity", "void_breaker_laser"],
		"xp": 100000
	},
	"void_leviathan": {
		"name": "VOID LEVIATHAN",
		"stats": {"hp": 15000000, "max_shield": 5000000, "atk": 30000, "def": 1200, "atk_interval": 6.0, "accuracy": 220, "jammer": true, "eva": 60}, # Ultimate Barrier: Buffed from 5M/9k
		"loot": [["credits", 15000000, 30000000], ["VoidEssence", 10, 20], ["PrimordialShard", 5, 10]],
		"rare_loot": [],
		"requires_weapon": "void_breaker_laser",
		"module_drop_chance": 0.15,
		"module_drop_pool": ["omega_armor", "primordial_core", "omega_beam", "void_battery_array", "temporal_drive", "primordial_fortification", "omega_singularity", "void_breaker_laser"],
		"is_boss": true,
		"xp": 1000000
	},
	# v57.0: SECTOR ZETA ENEMIES (Difficulty 9)
	"plague_drone": {
		"name": "Plague Drone",
		"stats": {"hp": 1600000, "max_shield": 600000, "atk": 8500, "def": 530, "atk_interval": 1.8, "accuracy": 205, "eva": 35}, # Target Z8 Boss (1.5M/500)
		"loot": [["credits", 50000, 100000], ["BiohazardSample", 2, 5], ["Ti", 30, 60]],
		"rare_loot": [["PathogenCore", 0.25, 1, 2], ["Res3", 0.3, 5, 10]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["temporal_scrambler", "warp_stabilizer"],
		"xp": 3500
	},
	"bio_horror": {
		"name": "Bio-Horror",
		"stats": {"hp": 1900000, "max_shield": 750000, "atk": 9800, "def": 560, "atk_interval": 2.5, "accuracy": 215, "eva": 25},
		"loot": [["credits", 80000, 150000], ["BiohazardSample", 5, 10], ["MutatedTissue", 2, 4]],
		"rare_loot": [["PathogenCore", 0.4, 1, 3], ["VoidCrystal", 0.2, 2, 4], ["S", 0.30, 2, 5]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["void_engine", "chrono_stabilizer"],
		"xp": 5000
	},
	"rogue_ai_core": {
		"name": "Rogue AI Core",
		"stats": {"hp": 2400000, "max_shield": 1200000, "atk": 10500, "def": 600, "atk_interval": 1.5, "accuracy": 225, "eva": 45},
		"loot": [["credits", 100000, 200000], ["AdvCircuit", 10, 20], ["QuantumCore", 1, 2]],
		"rare_loot": [["AIMatrix", 0.3, 1, 1], ["Chip", 0.5, 5, 10]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["temporal_scrambler", "warp_stabilizer", "void_engine", "chrono_stabilizer"],
		"xp": 6000
	},
	"quarantine_warden": {
		"name": "QUARANTINE WARDEN",
		"stats": {"hp": 3000000, "max_shield": 1500000, "atk": 8500, "def": 900, "accuracy": 220, "eva": 30}, # Buffed from 1.5M/800k/3000
		"loot": [["credits", 200000, 400000], ["BiohazardSample", 10, 20], ["PathogenCore", 2, 4], ["MutatedTissue", 5, 10]],
		"rare_loot": [["QuarantineClearance", 0.5, 1, 1], ["AIMatrix", 0.25, 1, 2]],
		"module_drop_chance": 0.15,
		"module_drop_pool": ["temporal_scrambler", "warp_stabilizer", "void_engine", "chrono_stabilizer"],
		"is_boss": true,
		"xp": 250000
	},
	# v57.0: Late Sector Expansion - Sector Alpha (+2)
	"xenon_scout": {
		"name": "Xenon Scout",
		"stats": {"hp": 55000, "max_shield": 18000, "atk": 1050, "def": 140, "atk_interval": 1.5, "accuracy": 115, "eva": 40}, # Target Z4 Boss
		"loot": [["credits", 5000, 10000], ["Ti", 10, 20], ["Fe", 25, 50]],
		"rare_loot": [["NavData", 0.3, 1, 3], ["Res2", 0.2, 1, 2]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "cobalt_battery_module"],
		"xp": 350
	},
	"alien_probe": {
		"name": "Alien Probe",
		"stats": {"hp": 65000, "max_shield": 25000, "atk": 1250, "def": 150, "atk_interval": 2.0, "accuracy": 125, "eva": 50},
		"loot": [["credits", 2000, 4000], ["SalvageData", 2, 4], ["Circuit", 3, 6]],
		"rare_loot": [["VoidArtifact", 0.1, 1, 1], ["Chip", 0.25, 1, 2]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "mg_battery_module"],
		"xp": 400
	},
	# v57.0: Late Sector Expansion - Sector Beta (+2)
	"repair_drone": {
		"name": "Repair Drone",
		"stats": {"hp": 160000, "max_shield": 60000, "atk": 1650, "def": 125, "atk_interval": 2.5, "accuracy": 135, "eva": 30}, # Target Z5 Boss
		"loot": [["credits", 3000, 6000], ["Cu", 20, 40], ["Circuit", 5, 10]],
		"rare_loot": [["AdvCircuit", 0.2, 1, 2], ["Mesh", 0.15, 1, 2]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "cobalt_battery_module"],
		"xp": 500
	},
	"ore_guardian": {
		"name": "Ore Guardian",
		"stats": {"hp": 190000, "max_shield": 75000, "atk": 1900, "def": 130, "accuracy": 145, "eva": 15}, 
		"loot": [["Fe", 100, 200], ["Ti", 30, 60], ["W", 20, 40]],
		"rare_loot": [["Pt", 0.2, 1, 3], ["Ir", 0.1, 1, 2]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["railgun_mk3", "mining_laser_mk3", "composite_armor_mk2", "stainless_armor", "mg_battery_module"],
		"xp": 700
	},
	# v57.0: Late Sector Expansion - Sector Gamma (+2)
	"irradiated_hulk": {
		"name": "Irradiated Hulk",
		"stats": {"hp": 290000, "max_shield": 95000, "atk": 2700, "def": 185, "atk_interval": 4.0, "accuracy": 170, "eva": 10}, # Target Z6 Boss
		"loot": [["credits", 3000000, 5000000], ["U", 400, 500], ["RadIsotope", 5, 10]],
		"rare_loot": [["Res3", 0.3, 2, 4], ["VoidCrystal", 0.1, 1, 2]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["cryo_laser_mk3", "antimatter_engine", "iridium_armor", "reactive_core_battery"],
		"xp": 1200
	},
	"plasma_wraith": {
		"name": "Plasma Wraith",
		"stats": {"hp": 240000, "max_shield": 150000, "atk": 2900, "def": 175, "atk_interval": 1.8, "accuracy": 165, "eva": 45}, 
		"loot": [["credits", 1500000, 2000000]],
		"rare_loot": [["QuantumCore", 0.15, 1, 1], ["ExoticMatter", 0.1, 1, 2]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["iridium_penetrator", "platinum_laser", "reactive_armor", "plasma_overcharger", "exotic_shield_matrix"],
		"xp": 1500
	},
	# v57.0: Late Sector Expansion - Sector Delta (+2)
	"shard_swarm": {
		"name": "Shard Swarm",
		"stats": {"hp": 600000, "max_shield": 150000, "atk": 5000, "def": 260, "atk_interval": 0.8, "accuracy": 195, "eva": 35}, # Target Z7 Boss
		"loot": [["credits", 20000, 40000], ["VoidCrystal", 3, 6], ["Si", 50, 100]],
		"rare_loot": [["Ir", 0.2, 1, 3], ["QuantumCore", 0.1, 1, 1]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["quantum_dissipator", "omni_scanner", "torpedo_launcher", "osmium_core_module", "palladium_fuel_cell"],
		"xp": 2000
	},
	"prism_guardian": {
		"name": "Prism Guardian",
		"stats": {"hp": 650000, "max_shield": 300000, "atk": 5400, "def": 300, "atk_interval": 2.5, "accuracy": 185, "eva": 25},
		"loot": [["credits", 30000, 60000], ["VoidCrystal", 5, 10], ["ExoticMatter", 2, 4]],
		"rare_loot": [["AncientTech", 0.15, 1, 1], ["Os", 0.1, 1, 2]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["reflective_sheath", "diamond_edge_railgun", "crystal_lens_laser"],
		"xp": 2500
	},
	"rogue_architect": {
		"name": "Rogue Architect",
		"stats": {"hp": 6000, "max_shield": 2000, "atk": 180, "def": 45, "atk_interval": 2.0, "accuracy": 60}, # Buffed from 3k/1k/120
		"loot": [["credits", 10000, 20000], ["W", 5, 10], ["Cu", 20, 50]],
		"rare_loot": [["architect_beam", 0.15, 1, 1], ["architect_plating", 0.15, 1, 1], ["architect_cell", 0.15, 1, 1]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["ai_targeting_system", "superalloy_engine", "composite_armor_mk2"],
		"is_boss": true,
		"xp": 1000
	},
	"silicate_monolith": {
		"name": "Silicate Monolith",
		"stats": {"hp": 12000, "max_shield": 4000, "atk": 350, "def": 65, "atk_interval": 4.0, "accuracy": 85}, # Buffed from 8k/2k/250
		"loot": [["credits", 3000, 5000], ["Si", 50, 100]],
		"rare_loot": [["monolith_blaster", 0.15, 1, 1], ["monolith_shell", 0.15, 1, 1], ["monolith_sensor", 0.15, 1, 1]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["ai_targeting_system", "broadside_array", "stainless_armor"],
		"is_boss": true,
		"xp": 1500
	},
	"martian_warmaster": {
		"name": "Martian Warmaster",
		"stats": {"hp": 45000, "max_shield": 10000, "atk": 1500, "def": 110, "atk_interval": 2.5, "accuracy": 120, "jammer": true}, # Tier Wall: Buffed from 15k/500/30
		"loot": [["credits", 10000, 20000], ["Steel", 20, 40]],
		"rare_loot": [["warmaster_railgun", 0.15, 1, 1], ["warmaster_armor", 0.15, 1, 1], ["warmaster_drive", 0.15, 1, 1]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["railgun_mk3", "superalloy_engine"],
		"is_boss": true,
		"xp": 5000
	},
	"cryo_lord": {
		"name": "Cryo-Lord",
		"stats": {"hp": 65000, "max_shield": 25000, "atk": 1200, "def": 150, "atk_interval": 3.0, "accuracy": 140}, # Buffed from 40k/700/50
		"loot": [["credits", 25000, 45000], ["Ti", 50, 100]],
		"rare_loot": [["cryo_lance", 0.15, 1, 1], ["cryo_plating", 0.15, 1, 1], ["cryo_heat_sink", 0.15, 1, 1]],
		"module_drop_chance": 0.15,
		"module_drop_pool": ["absolute_zero_vent"],
		"is_boss": true,
		"xp": 8000
	},
	"xenon_harbinger": {
		"name": "Xenon Harbinger",
		"stats": {"hp": 80000, "max_shield": 40000, "atk": 1000, "def": 70, "atk_interval": 2.0, "accuracy": 130, "eva": 40},
		"loot": [["credits", 80000, 150000], ["VoidArtifact", 5, 10]],
		"rare_loot": [["harbinger_repeater", 0.15, 1, 1], ["harbinger_carapace", 0.15, 1, 1], ["harbinger_reactor", 0.15, 1, 1]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["antimatter_engine", "reactive_core_battery"],
		"is_boss": true,
		"xp": 6000
	},
	"overseer_prime": {
		"name": "Overseer Prime",
		"stats": {"hp": 350000, "max_shield": 120000, "atk": 3000, "def": 250, "atk_interval": 3.0, "accuracy": 170, "jammer": true}, # Buffed from 200k/1.5k
		"loot": [["credits", 200000, 400000], ["AdvCircuit", 50, 100]],
		"rare_loot": [["overseer_turret", 0.15, 1, 1], ["overseer_bulkhead", 0.15, 1, 1], ["overseer_matrix", 0.15, 1, 1]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["ai_targeting_system", "broadside_array"],
		"is_boss": true,
		"xp": 50000
	},
	"rad_beast_alpha": {
		"name": "Rad-Beast Alpha",
		"stats": {"hp": 650000, "max_shield": 250000, "atk": 5000, "def": 350, "atk_interval": 2.5, "accuracy": 190}, # Buffed from 400k/2.5k
		"loot": [["credits", 500000, 1000000], ["RadIsotope", 20, 40]],
		"rare_loot": [["rad_beast_spitter", 0.15, 1, 1], ["rad_beast_flesh", 0.15, 1, 1], ["rad_beast_gland", 0.15, 1, 1]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["reactive_armor", "exotic_shield_matrix"],
		"is_boss": true,
		"xp": 100000
	},
	"prismatic_sovereign": {
		"name": "Prismatic Sovereign",
		"stats": {"hp": 2500000, "max_shield": 800000, "atk": 9000, "def": 500, "atk_interval": 2.0, "accuracy": 210, "eva": 30}, # Buffed from 1.2M/4.5k
		"loot": [["credits", 1000000, 2000000], ["ExoticMatter", 10, 20]],
		"rare_loot": [["sovereign_laser", 0.15, 1, 1], ["sovereign_crystal", 0.15, 1, 1], ["sovereign_barrier", 0.15, 1, 1]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["reflective_sheath", "diamond_edge_railgun"],
		"is_boss": true,
		"xp": 250000
	},
	"patient_zero": {
		"name": "Patient Zero",
		"stats": {"hp": 5000000, "max_shield": 2000000, "atk": 15000, "def": 750, "atk_interval": 1.5, "accuracy": 230, "eva": 50}, # Pathogen Wall: Buffed from 2.5M/7k
		"loot": [["credits", 3000000, 5000000], ["BiohazardSample", 50, 100]],
		"rare_loot": [["zero_strain_cannon", 0.15, 1, 1], ["zero_strain_carapace", 0.15, 1, 1], ["zero_strain_tendrils", 0.15, 1, 1]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["diamond_edge_railgun", "crystal_lens_laser"],
		"is_boss": true,
		"xp": 1000000
	},
	"time_weaver": {
		"name": "The Time Weaver",
		"stats": {"hp": 30000000, "max_shield": 10000000, "atk": 50000, "def": 2500, "atk_interval": 1.0, "accuracy": 280, "eva": 70}, # Chrono Wall: Buffed from 10M/15k
		"loot": [["credits", 20000000, 50000000], ["VoidEssence", 20, 50]],
		"rare_loot": [["weaver_annihilator", 0.15, 1, 1], ["weaver_shroud", 0.15, 1, 1], ["weaver_core", 0.15, 1, 1]],
		"module_drop_chance": 0.02,
		"module_drop_pool": ["diamond_edge_railgun", "crystal_lens_laser"],
		"is_boss": true,
		"xp": 5000000
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
	
	var sm = GameState.shipyard_manager
	if sm and sm.current_hp <= 0:
		log_msg("SYSTEM CRITICAL: Hull integrity at 0%. Repairs required before engaging.")
		return
	
	# v63.0 Fix: Enforce research requirements
	var data = zones[zone_id]
	if data.get("research_req"):
		if not GameState.research_manager.is_tech_unlocked(data["research_req"]):
			log_msg("ACCESS DENIED: Requires %s" % data["research_req"]) # Should rely on UI, but safe guard here
			return
			
	if current_zone == zones[zone_id] and in_combat: return
	GameState.set_active_manager(self)
	current_zone = zones[zone_id]
	current_zone_id = zone_id # Track ID explicitly
	in_combat = true
	session_loot.clear()
	spawn_enemy()
	player_shield = player_max_shield # FIX: Restore shields on enter
	shield_regen_accumulator = 0.0
	player_heat = 0.0
	overheat_lock = 0.0
	heat_changed.emit(player_heat, player_max_heat)
	log_msg("Warped to %s." % current_zone["name"])

func set_target_enemy(enemy_id):
	# v62.0 Fix: Prevent crash if current_zone is null
	if current_zone == null:
		return

	var sm = GameState.shipyard_manager
	if sm and sm.current_hp <= 0:
		log_msg("SYSTEM CRITICAL: Hull integrity at 0%. Repairs required before engaging.")
		return

	if enemy_id and enemy_id in enemy_db:
		GameState.set_active_manager(self)
		target_enemy_id = enemy_id
		in_combat = true
		spawn_enemy()
		player_shield = player_max_shield # FIX: Restore shields on target
		shield_regen_accumulator = 0.0
		player_heat = 0.0
		overheat_lock = 0.0
		heat_changed.emit(player_heat, player_max_heat)
		log_msg("Targeting: %s" % enemy_db[enemy_id]["name"])
	else:
		target_enemy_id = null

func spawn_enemy():
	var sm = GameState.shipyard_manager
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
		"module_drop_chance": e_data.get("module_drop_chance", 0.0),
		"module_drop_pool": e_data.get("module_drop_pool", []),
		"is_boss": e_data.get("is_boss", false),
		"xp": e_data["xp"],
		"jammer": e_data["stats"].get("jammer", false),
		"eva": e_data["stats"].get("eva", 0),
		# v62.0 Fix: Copy atk_interval so enemy attack speed is used
		"atk_interval": e_data["stats"].get("atk_interval", 3.0),
		"is_elite": false # Default
	}
	
	# Compensate enemy baseline for permanent external progression multipliers.
	# This avoids runaway TTK collapse from combat level / research / warp / trophies.
	var progression_mult = get_external_progression_combat_mult()
	var bonus_over_base = max(0.0, progression_mult - 1.0)
	if bonus_over_base > 0.0:
		var hp_comp = ENEMY_COMP_BOSS_HP if current_enemy["is_boss"] else ENEMY_COMP_REGULAR_HP
		var sh_comp = ENEMY_COMP_BOSS_SHIELD if current_enemy["is_boss"] else ENEMY_COMP_REGULAR_SHIELD
		var atk_comp = ENEMY_COMP_BOSS_ATK if current_enemy["is_boss"] else ENEMY_COMP_REGULAR_ATK
		
		current_enemy["max_hp"] = max(1, int(round(float(current_enemy["max_hp"]) * (1.0 + (bonus_over_base * hp_comp)))))
		current_enemy["max_shield"] = max(0, int(round(float(current_enemy["max_shield"]) * (1.0 + (bonus_over_base * sh_comp)))))
		current_enemy["atk"] = max(1, int(round(float(current_enemy["atk"]) * (1.0 + (bonus_over_base * atk_comp)))))
		current_enemy["def"] = max(0, int(round(float(current_enemy["def"]) * (1.0 + (bonus_over_base * ENEMY_COMP_DEF)))))
	
	# Apply Elite logic if requested by bounty_manager or random chance (5%)
	var elite_chance = 0.05
	# The bounty_manager will signal is_elite through target_enemy_id if it's a specific elite hunt
	# For simplicity, we can check a temporary flag or just let bounty_manager handle it.
	# Let's add a global flag for the next spawn.
	if next_spawn_elite:
		current_enemy["is_elite"] = true
		next_spawn_elite = false
	elif randf() < elite_chance:
		current_enemy["is_elite"] = true
		
	if current_enemy["is_elite"]:
		current_enemy["name"] = "ELITE " + current_enemy["name"]
		current_enemy["max_hp"] *= 2.5
		current_enemy["atk"] *= 1.8
		current_enemy["xp"] *= 3.0
		# Elite loot buff
		current_enemy["loot"] = current_enemy["loot"].duplicate(true)
		for item in current_enemy["loot"]:
			item[1] = int(item[1] * 2.5)
			item[2] = int(item[2] * 2.5)
			
	is_jammed = current_enemy["jammer"]
	combat_started.emit()
	
	# Unique Module Check (Phase 19)
	has_reflective = false
	has_reactive = false
	has_exotic_matrix = false
	enemy_speed_mult = 1.0
	
	has_reflective = _loadout_has_module(sm, "reflective_sheath")
	has_reactive = _loadout_has_module(sm, "reactive_armor")
	has_exotic_matrix = _loadout_has_module(sm, "exotic_shield_matrix")
	
	# Step 5: Boss Set Flags
	has_cryo_set = false
	has_sovereign_set = false
	has_patient_zero_set = false
	
	var set_counts = {}
	for mid in sm.loadout.values():
		if mid and mid in sm.modules:
			var m_data = sm.modules[mid]
			var desc = m_data.get("desc", "")
			if desc.begins_with("(Set)"):
				var set_name = desc.split("[")[0].strip_edges()
				set_counts[set_name] = set_counts.get(set_name, 0) + 1
				
	for s_name in set_counts:
		if set_counts[s_name] >= 3:
			if "Cryo-Lord's Chill" in s_name:
				has_cryo_set = true
			elif "Sovereign's Prism" in s_name:
				has_sovereign_set = true
			elif "Patient Zero's Strain" in s_name:
				has_patient_zero_set = true
	
	if _loadout_has_module(sm, "chrono_stabilizer"):
		enemy_speed_mult *= 0.8
		
	if has_cryo_set:
		enemy_speed_mult *= 0.85 # -15% Enemy Attack Speed
	enemy_hp = current_enemy["max_hp"]
	enemy_max_hp = enemy_hp
	enemy_shield = float(current_enemy["max_shield"])
	enemy_max_shield = enemy_shield
	
	player_max_shield = sm.max_shield
	player_weapon_states.clear()
	var equipped_weapons = []
	
	# v65.4: Engineering skill_mult applied to weapon damage
	var engineering_lvl = 1
	if GameState.processing_manager:
		engineering_lvl = GameState.processing_manager.get_level()
	var weapon_skill_mult = 1.0 + (engineering_lvl * 0.01)
	
	for s_idx in sm.loadout:
		var mid = sm.loadout[s_idx]
		if mid and mid in sm.modules:
			var m_data = sm.modules[mid]
			if m_data.get("slot_type") == "weapon":
				var m_stats = m_data.get("stats", {})
				var w_type = "kinetic"
				if m_stats.get("atk_energy", 0) > 0: w_type = "energy"
				elif m_stats.get("atk_explosive", 0) > 0: w_type = "explosive"
				
				equipped_weapons.append({
					"name": m_data["name"],
					"type": w_type,
					"timer": randf_range(0.0, 0.5),
					"interval": m_stats.get("atk_interval", 2.5),
					"dmg_k": m_stats.get("atk_kinetic", 0) * weapon_skill_mult,
					"dmg_e": m_stats.get("atk_energy", 0) * weapon_skill_mult,
					"dmg_x": m_stats.get("atk_explosive", 0) * weapon_skill_mult,
					"slot_idx": int(s_idx),
					"energy_load": m_stats.get("energy_load", 0)
				})
	if equipped_weapons.is_empty():
		var h_stats = sm.hulls[sm.active_hull]["stats"]
		player_weapon_states.append({"name": "Standard Cannon", "type": "kinetic", "timer": 0.0, "interval": 3.0, "dmg_k": h_stats["atk"], "dmg_e": 0, "dmg_x": 0, "slot_idx": - 1, "energy_load": 0})
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
	var sm = GameState.shipyard_manager
	if sm:
		player_max_shield = sm.max_shield
		
	if not in_combat or not current_enemy or not current_zone:
		_process_regeneration(delta)
		return
		
	var rm = GameState.research_manager
	# v65.4 Fix: Removed sm.attack_speed_bonus here — it's already applied via cooling_mult per-weapon
	var p_speed_mult = (1.0 + rm.get_efficiency_bonus("attack_speed"))
	
	# Safety: Ensure HP never exceeds Max
	if sm.current_hp > sm.max_hp:
		sm.current_hp = sm.max_hp
	
	if overheat_lock > 0:
		# Require 0% purge to resume fire
		if player_heat <= 0.0:
			overheat_lock = 0.0
	if player_heat > 0:
		var current_vent_rate = player_vent_rate * get_milestone_heat_mult()
		
		# Turbo Cooling: 4x vent when overloaded or during overheat lock
		var frame_vent_rate = current_vent_rate
		if player_heat > player_max_heat or overheat_lock > 0:
			frame_vent_rate *= 4.0
			
		player_heat = max(0, player_heat - frame_vent_rate * delta)
		heat_changed.emit(player_heat, player_max_heat)
	# 80% speed penalty removed per user request for full performance until overheat
	
	# v65.0 Fix: Enemy Shield Regen moved to generic accumulator and Capped (Removed old logic)
	
	if _loadout_has_module(sm, "warp_stabilizer"):
		p_speed_mult += 0.15
		
	# v74.0: Heat-Sync Focus (Threshold: 40%)
	if sm.affix_bonuses.get("heat_sync_focus", 0.0) > 0 and player_heat >= (player_max_heat * 0.4):
		p_speed_mult += sm.affix_bonuses["heat_sync_focus"]

	if coolant_flush_timer > 0:
		coolant_flush_timer -= delta
		p_speed_mult *= 2.0
			
	for w_idx in range(player_weapon_states.size()):
		if w_idx >= player_weapon_states.size():
			break # Array was resized (e.g., enemy died and new one spawned)
		var w = player_weapon_states[w_idx]
		# Audit v70.0: Cooling Systems Implementation
		# Base interval is reduced by attack_speed_bonus (e.g., +10% speed = 1.1x faster tick)
		# Or better: timer increments faster. 
		var cooling_mult = 1.0 + sm.attack_speed_bonus
		w["timer"] += delta * p_speed_mult * cooling_mult
		
		if w["timer"] >= w["interval"]:
			_execute_player_attack(w_idx)
			if w_idx >= player_weapon_states.size():
				break # win_fight() may have rebuilt weapon states
			w["timer"] -= w["interval"]
		
	# v65.0 Fix: Use enemy's actual attack interval (was hardcoded 3.0)
	# Audit v70.0: Electronic Warfare Implementation
	# Enemy attack timer increments slower based on jamming_strength
	var jamming_mult = max(0.2, 1.0 - sm.jamming_strength) # Cap slow at 80%
	var e_interval = current_enemy.get("atk_interval", 3.0)
	
	enemy_attack_timer += delta * enemy_speed_mult * jamming_mult
	if enemy_attack_timer >= e_interval:
		_execute_enemy_attack()
		enemy_attack_timer -= e_interval
		
	if consumable_cooldown > 0:
		consumable_cooldown -= delta
	else:
		_check_auto_consume(delta)
	if nanite_hot_timer > 0:
		nanite_hot_timer -= delta
		# Fix: Explicit clamp to prevent overflow
		var heal = sm.max_hp * 0.02 * delta
		if sm.current_hp + heal > sm.max_hp:
			sm.current_hp = sm.max_hp
		else:
			sm.current_hp += heal
		
	if _loadout_has_module(sm, "broadside_array") and in_combat:
		broadside_timer += delta
		if broadside_timer >= 20.0:
			_execute_broadside_burst()
			broadside_timer = 0.0
			
	_process_regeneration(delta)

func _process_regeneration(delta: float):
	var sm = GameState.shipyard_manager
	var rm = GameState.research_manager
	if not sm: return
	
	# Player Shield Regen
	if player_shield < player_max_shield:
		var regen_base = (sm.shield_regen * (1.0 + (rm.get_efficiency_bonus("shield_regen") if rm else 0.0) + sm.shield_regen_bonus))
		player_shield = min(player_max_shield, player_shield + (regen_base * delta))
		
	# Point 5: Patient Zero Hull Regen
	if has_patient_zero_set and sm.current_hp < sm.max_hp:
		sm.current_hp = min(sm.max_hp, sm.current_hp + (50.0 * delta))
	
	# Enemy Shield Regen (1% per second, Combat Only)
	if in_combat and current_enemy and enemy_shield < enemy_max_shield:
		var regen_amt = min(enemy_max_shield * 0.01, 50.0)
		enemy_shield = min(enemy_max_shield, enemy_shield + (regen_amt * delta))

func _execute_player_attack(weapon_idx: int):
	var w = player_weapon_states[weapon_idx]
	var sm = GameState.shipyard_manager
	if overheat_lock > 0: return
	
	# P0 Hotfix: Grid Safety Check (Prevent Overload Exploit)
	var max_energy = 0
	if GameState.resources: max_energy = GameState.resources.max_energy
	
	if sm.energy_used > max_energy:
		# 10% chance to spam log (anti-spam)
		if randf() < 0.1:
			combat_events.append({"type": "miss", "text": "LOW POWER", "color": Color.RED, "side": "player"})
		return # Weapon fails to fire
		
	if is_jammed and randf() < 0.25:
		combat_events.append({"type": "miss", "text": "JAMMED", "color": Color.ORANGE, "side": "enemy"})
		return

	# Manual consume check removed (Auto-only now)

	player_heat += 2.0 + ((w["dmg_k"] + w["dmg_e"] + w["dmg_x"]) / 100.0)
	heat_changed.emit(player_heat, player_max_heat)
	if player_heat >= player_max_heat:
		# Allowed to exceed max_heat numerically for dynamic high-speed cooling phase
		overheat_lock = 1.0 # Logic changed: Locks until heat == 0
		return
	
	# Hit Resolution (Accuracy vs Evasion)
	var p_acc = sm.accuracy
	var e_eva = current_enemy["eva"]
	var hit_chance = clamp(float(p_acc) / (float(p_acc) + float(e_eva)), 0.2, 1.0)
	if randf() > hit_chance:
		combat_events.append({"type": "miss", "text": "MISS", "color": Color.WHITE, "side": "enemy"})
		return

	# v74.0: Static Burst (Reset enemy attack timer)
	var static_burst_chance = sm.affix_bonuses.get("static_burst", 0.0)
	if static_burst_chance > 0 and randf() < static_burst_chance:
		enemy_attack_timer = 0.0
		combat_events.append({"type": "shock", "text": "SHOCKED", "color": Color.YELLOW, "side": "enemy"})

	var p_atk_k = w["dmg_k"]
	var p_atk_e = w["dmg_e"]
	var p_atk_x = w["dmg_x"]
	if w["type"] == "energy" and _loadout_has_module(sm, "plasma_overcharger"):
		p_atk_e *= 2.0
	
	var ammo_id = sm.ammo_loadout.get(w["slot_idx"])
	var requires_ammo = (w["type"] == "kinetic" or w["type"] == "explosive") and w["slot_idx"] != -1
	
	if ammo_id and ammo_id != "":
		if GameState.resources.get_element_amount(ammo_id) > 0:
			GameState.resources.remove_element(ammo_id, 1)
			
			# Audit Phase 19: Use flat bonuses from elements.json where possible, or standardized flat tiers
			# Descriptions say: +5, +15, +30
			if ammo_id.begins_with("Slug"):
				var bonus = 5.0
				if "T1S" in ammo_id: bonus = 10.0 # Heavy Steel Slugs
				elif "T2" in ammo_id: bonus = 15.0
				elif "T3" in ammo_id: bonus = 30.0
				elif "T4" in ammo_id: bonus = 60.0
				p_atk_k += bonus
			elif ammo_id.begins_with("Cell"):
				var bonus = 5.0
				if "T2" in ammo_id: bonus = 15.0
				elif "T3" in ammo_id: bonus = 30.0
				elif "T4" in ammo_id: bonus = 60.0
				p_atk_e += bonus
			elif "Missile" in ammo_id or "Torpedo" in ammo_id:
				var bonus = 10.0
				if "Seeker" in ammo_id: bonus = 25.0
				elif "Torpedo" in ammo_id: bonus = 60.0
				p_atk_x += bonus
		elif requires_ammo:
			return # Ammo equipped but empty
	elif requires_ammo:
		return # No ammo equipped for kinetic weapon
		
	# Feature 66.0: Boss Gating System
	if current_enemy.has("requires_weapon"):
		var req_w = current_enemy["requires_weapon"]
		if not _loadout_has_module(sm, req_w):
			if randf() < 0.2:
				combat_events.append({"type": "miss", "text": "REQUIRES " + req_w.replace("_", " ").to_upper(), "color": Color.RED, "side": "enemy"})
			return # Deals 0 damage and skips calculation
			
	var skill_dmg_mult = (1.0 + (get_level() * 0.005)) * GameState.warp_manager.get_combat_multiplier()
	var total_crit = sm.crit_chance + get_milestone_crit_bonus()
	var res = resolve_damage(p_atk_k * skill_dmg_mult, p_atk_e * skill_dmg_mult, p_atk_x * skill_dmg_mult, enemy_shield, current_enemy["def"], current_zone.get("difficulty", 1), total_crit, true)
	enemy_shield = max(0, enemy_shield - res[0])
	enemy_hp -= res[1]
	if res[0] > 0: combat_events.append({"type": "dmg_shield", "text": "-%d" % res[0], "color": Color.CYAN, "side": "enemy"})
	if res[1] > 0: combat_events.append({"type": "dmg_hull", "text": "-%d" % res[1], "color": Color.RED, "side": "enemy"})
	if enemy_hp <= 0: win_fight()

func _execute_enemy_attack():
	var sm = GameState.shipyard_manager
	var e_acc = current_enemy.get("accuracy", 0)
	var total_eva = sm.evasion + get_milestone_evasion_bonus()
	var dodge_chance = min(float(total_eva) / (float(total_eva) + 150.0 * (1.0 + float(e_acc) / 100.0)), 0.75)
	if randf() < dodge_chance:
		combat_events.append({"type": "miss", "text": "MISS", "color": Color.WHITE, "side": "player"})
	else:
		var difficulty = current_zone.get("difficulty", 1)
		# Enemy uses base crit 5%
		var eres = resolve_damage(current_enemy["atk"], 0, 0, player_shield, sm.defense, difficulty, 0.05, false)
		
		# Reflective Sheath Logic
		if has_reflective and randf() < 0.20:
			var reflected = int(eres[0] * 0.5 + eres[1] * 0.5)
			enemy_hp -= reflected
			combat_events.append({"type": "reflect", "text": "REFL %d" % reflected, "color": Color.WHITE, "side": "enemy"})
			
		# Step 5: Sovereign's Prism Reflect Logic
		if has_sovereign_set and randf() < 0.15:
			var reflected = int(eres[0] + eres[1]) # 100% reflect but lower chance
			enemy_hp -= reflected
			combat_events.append({"type": "reflect", "text": "PRISM REFL %d" % reflected, "color": Color.PURPLE, "side": "enemy"})
		
		# Exotic Shield Matrix Logic (Sector Gamma Protection)
		# v61.0 Fix: Use current_zone_id instead of current_zone.get("id")
		if has_exotic_matrix and current_zone_id == "sector_gamma":
			eres[1] = int(eres[1] * 0.7) # 30% reduction
			
		player_shield = max(0, player_shield - eres[0])
		sm.current_hp -= eres[1]
		if eres[0] > 0: combat_events.append({"type": "dmg_shield", "text": "-%d" % eres[0], "color": Color.CYAN, "side": "player"})
		if eres[1] > 0: combat_events.append({"type": "dmg_hull", "text": "-%d" % eres[1], "color": Color.RED, "side": "player"})
	if sm.current_hp <= 0: lose_fight()

func resolve_damage(atk_k, atk_e, atk_x, c_shield, c_armor, difficulty = 1, crit_chance = 0.05, is_player_attacker = false):
	var shield_dmg_pot = (atk_k * 0.5) + (atk_e * 1.5) + (atk_x * 1.1)
	
	# v74.0: Void Strike (Shield Bypass) - Player Only
	var void_strike_chance = 0.0
	if is_player_attacker:
		void_strike_chance = GameState.shipyard_manager.affix_bonuses.get("void_strike", 0.0)
		
	var is_void_strike = void_strike_chance > 0 and randf() < void_strike_chance
	
	var damage_to_shield = min(c_shield, shield_dmg_pot)
	if is_void_strike and c_shield > 0:
		damage_to_shield = 0 # All damage bleeds to hull
		combat_events.append({"type": "void", "text": "VOID STRIKE", "color": Color.PURPLE, "side": "enemy" if is_player_attacker else "player"})
		
	var bleed_ratio = (shield_dmg_pot - damage_to_shield) / shield_dmg_pot if shield_dmg_pot > 0 else 1.0
	
	var k = max(20.0, float(difficulty) * 50.0)
	
	# Armor Penetration Logic
	var arm_k = c_armor
	var arm_e = c_armor * 0.7
	var arm_x = c_armor * 0.2
	
	# Reactive Armor Logic (Phase 19)
	if has_reactive:
		var hp_ratio = float(GameState.shipyard_manager.current_hp) / float(GameState.shipyard_manager.max_hp)
		# If HP is low, effectively double the K-scale for better mitigation
		k *= (1.0 + (1.0 - hp_ratio))

	var hull_dmg_k = atk_k * 1.2 * (1.0 - arm_k / (arm_k + k))
	var hull_dmg_e = atk_e * 0.9 * (1.0 - arm_e / (arm_e + k))
	var hull_dmg_x = atk_x * 1.0 * (1.0 - arm_x / (arm_x + k))
	
	var total_hull_dmg = (hull_dmg_k + hull_dmg_e + hull_dmg_x) * bleed_ratio
	
	var variance = randf_range(0.9, 1.1)
	var is_crit = randf() < crit_chance
	if is_crit: variance *= 1.5
	return [int(damage_to_shield * variance), int(max(1.0 if (atk_k + atk_e + atk_x) > 0 else 0, total_hull_dmg * variance)), is_crit]

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
			var item_id = entry[0]
			var sm = GameState.shipyard_manager
			if sm and item_id in sm.modules:
				var custom_id = item_id
				var m_data = sm.modules[item_id]
				var rarity = m_data.get("rarity", sm.Rarity.COMMON)
				var zone_difficulty = int(current_zone.get("difficulty", 1))
				
				if rarity == sm.Rarity.UNIQUE:
					# Generate it properly so it rolls affixes and sockets!
					custom_id = sm.generate_module_drop(item_id, sm.Rarity.UNIQUE, zone_difficulty)
					m_data = sm.modules[custom_id]
				else:
					sm.module_inventory[item_id] = sm.module_inventory.get(item_id, 0) + qty
					
				sm.new_drops_alert = true
				sm.inventory_updated.emit()
				
				var rarity_color = sm.RARITY_COLORS.get(rarity, Color.WHITE)
				var rarity_label = sm.RARITY_LABELS.get(rarity, "")
				if rarity_label == "":
					rarity_label = "Common"
				combat_events.append({"type": "loot", "text": "* %s DROP" % rarity_label.to_upper(), "color": rarity_color, "side": "enemy"})
				log_msg("Looted %s Module: %s" % [rarity_label, m_data["name"]])
				
				if custom_id != item_id:
					session_loot[custom_id] = session_loot.get(custom_id, 0) + 1
				else:
					session_loot[item_id] = session_loot.get(item_id, 0) + qty
			else:
				# It's a standard generic element (VoidCrystal, NavData, etc)
				GameState.resources.add_element(item_id, qty)
				
			session_loot[item_id] = session_loot.get(item_id, 0) + qty
	
	var sm = GameState.shipyard_manager
	
	# v74.0: Capacitor Pulse (Shield Restore on Kill)
	var cap_pulse = sm.affix_bonuses.get("capacitor_pulse", 0.0)
	# v76.5: Hard Cap 30%
	cap_pulse = min(cap_pulse, 0.30)
	if cap_pulse > 0:
		var restore_amt = player_max_shield * cap_pulse
		player_shield = min(player_max_shield, player_shield + restore_amt)
		combat_events.append({"type": "heal", "text": "+%d SHIELD" % int(restore_amt), "color": Color.CYAN, "side": "player"})
		
	# v76.5: Nanite Resurgence (Hull Restore on Kill)
	var nanite_surge = sm.affix_bonuses.get("nanite_resurgence", 0.0)
	# v76.5: Hard Cap 30%
	nanite_surge = min(nanite_surge, 0.30)
	if nanite_surge > 0:
		var restore_amt = int(sm.max_hp * nanite_surge)
		sm.current_hp = min(sm.max_hp, sm.current_hp + restore_amt)
		combat_events.append({"type": "heal", "text": "+%d HP" % restore_amt, "color": Color.GREEN, "side": "player"})
		
	# v74.0: Nano-Scavenger (Loot Processed Materials)
	var nano_chance = sm.affix_bonuses.get("nano_scavenger", 0.0)
	if nano_chance > 0 and randf() < nano_chance:
		var extra_materials = ["Circuit", "Chip", "AdvCircuit", "QuantumCore"]
		var drop = extra_materials[randi() % extra_materials.size()]
		# Scale extra loot by difficulty
		var diff = current_zone.get("difficulty", 1)
		var qty = randi_range(1, 1 + int(diff / 3))
		GameState.resources.add_element(drop, qty)
		combat_events.append({"type": "loot", "text": "SCAVENGED %s" % drop, "color": Color.AQUA, "side": "enemy"})
		log_msg("Nano-Scavenger triggered: Found %d %s" % [qty, drop])
	
	# v71.0: Module Rarity Drop System
	var drop_chance = current_enemy.get("module_drop_chance", 0.0)
	var drop_pool = current_enemy.get("module_drop_pool", [])
	
	# Only drop unlocked modules
	var unlocked_pool = []
	for mod_id in drop_pool:
		var req = sm.modules.get(mod_id, {}).get("research_req", "")
		if req == "" or GameState.research_manager.is_tech_unlocked(req):
			unlocked_pool.append(mod_id)
			
	if drop_chance > 0 and unlocked_pool.size() > 0 and randf() < drop_chance:
		var is_boss = current_enemy.get("is_boss", false)
		var rarity = sm.roll_rarity(is_boss)
		var base_id = unlocked_pool[randi() % unlocked_pool.size()]
		var zone_difficulty = int(current_zone.get("difficulty", 1))
		var custom_id = sm.generate_module_drop(base_id, rarity, zone_difficulty)
		if custom_id != "":
			var w_name = sm.modules[custom_id]["name"]
			var rarity_color = sm.RARITY_COLORS[rarity]
			var rarity_label = sm.RARITY_LABELS.get(rarity, "")
			if rarity_label == "":
				rarity_label = "Common"
			combat_events.append({"type": "loot", "text": "%s DROP" % rarity_label.to_upper(), "color": rarity_color, "side": "enemy"})
			log_msg("Looted %s Module: %s" % [rarity_label, w_name])
			session_loot[custom_id] = session_loot.get(custom_id, 0) + 1

	add_xp(int(current_enemy["xp"] * (1.0 + GameState.research_manager.get_efficiency_bonus("combat_xp"))))
	enemy_defeated.emit(current_enemy["id"])
	spawn_enemy()

func lose_fight():
	var sm = GameState.shipyard_manager
	var cost = sm.get_full_repair_cost(sm.active_hull)
	var current_credits = GameState.resources.get_currency("credits")
	if cost > current_credits:
		cost = current_credits
	GameState.resources.add_currency("credits", -cost)
	retreat()

# v66.0: Auto-Consume System
func _check_auto_consume(delta: float):
	if not in_combat: return
	
	# Get Research Threshold
	var threshold = GameState.research_manager.get_auto_consume_threshold()
	if threshold <= 0.0: return # No research unlocked
	
	var sm = GameState.shipyard_manager
	
	# 1. Check Hull
	if sm.consumable_hull_slot != "":
		var hp_pct = float(sm.current_hp) / float(sm.max_hp)
		if hp_pct <= threshold:
			_trigger_consumable(sm.consumable_hull_slot, sm)
			return # One per tick
			
	# 2. Check Shield
	if sm.consumable_shield_slot != "":
		var sh_pct = player_shield / player_max_shield
		if sh_pct <= threshold and player_max_shield > 0:
			_trigger_consumable(sm.consumable_shield_slot, sm)
			return

func use_manual_consumable(type: String):
	if consumable_cooldown > 0: return
	
	var sm = GameState.shipyard_manager
	var item_id = ""
	if type == "hull":
		item_id = sm.consumable_hull_slot
	elif type == "shield":
		item_id = sm.consumable_shield_slot
		
	if item_id != "" and GameState.resources.get_element_amount(item_id) >= 1:
		_trigger_consumable(item_id, sm)

func _trigger_consumable(item_id: String, sm: Object):
	if GameState.resources.get_element_amount(item_id) < 1: return
	
	var data = ElementDB.get_consumable_data(item_id)
	if data.is_empty(): return
	
	GameState.resources.remove_element(item_id, 1)
	consumable_cooldown = consumable_cooldown_max
	
	var heal_pct = data.get("heal_pct", 0.0)
	var type = data.get("type", "hull")
	var dname = data.get("name", "Consumable")
	
	if type == "hull":
		var amt = int(sm.max_hp * heal_pct)
		sm.current_hp = min(sm.max_hp, sm.current_hp + amt)
		combat_events.append({"type": "heal", "text": "+%d HP" % amt, "color": Color.GREEN, "side": "player"})
		log_msg("Used %s: Repaired %d HP" % [dname, amt])
	elif type == "shield":
		var amt = int(player_max_shield * heal_pct)
		player_shield = min(player_max_shield, player_shield + amt)
		combat_events.append({"type": "heal", "text": "+%d SHIELD" % amt, "color": Color.CYAN, "side": "player"})
		log_msg("Used %s: Boosted %d Shield" % [dname, amt])

func _execute_broadside_burst():
	var total_atk_k = 0.0
	for w in player_weapon_states:
		if w["type"] == "kinetic": total_atk_k += w["dmg_k"]
	
	# Broadside delivers a massive kinetic salvo (5x base kinetic attack)
	# subject to standard armor/shield resolution
	var skill_dmg_mult = 1.0 + (get_level() * 0.005)
	var res = resolve_damage(total_atk_k * 5.0 * skill_dmg_mult, 0, 0, enemy_shield, current_enemy["def"], current_zone.get("difficulty", 1), 0.1, true) # 10% base crit for volley
	
	enemy_shield = max(0, enemy_shield - res[0])
	enemy_hp -= res[1]
	
	if res[0] > 0: combat_events.append({"type": "dmg_shield", "text": "BRST %d" % res[0], "color": Color.CYAN, "side": "enemy"})
	if res[1] > 0: combat_events.append({"type": "dmg_hull", "text": "BRST %d" % res[1], "color": Color.GOLD, "side": "enemy"})
	
	if enemy_hp <= 0: win_fight()

func log_msg(msg: String):
	combat_log.append(msg)
	if combat_log.size() > 20: combat_log.pop_front()

func get_save_data_manager() -> Dictionary:
	var data = get_save_data()
	data["in_combat"] = in_combat
	data["current_zone_id"] = current_zone_id
	data["current_enemy_id"] = current_enemy["id"] if current_enemy else null
	data["player_shield"] = player_shield
	data["player_heat"] = player_heat
	data["nanite_hot_timer"] = nanite_hot_timer
	data["coolant_flush_timer"] = coolant_flush_timer
	data["session_loot"] = session_loot
	return data

func load_save_data_manager(data: Dictionary):
	load_save_data(data)
	if data.is_empty(): return
	
	in_combat = data.get("in_combat", false)
	player_shield = data.get("player_shield", 0.0)
	player_heat = data.get("player_heat", 0.0)
	nanite_hot_timer = data.get("nanite_hot_timer", 0.0)
	coolant_flush_timer = data.get("coolant_flush_timer", 0.0)
	session_loot = data.get("session_loot", {})
	
	var zid = data.get("current_zone_id")
	if zid and zid in zones:
		current_zone = zones[zid]
		var eid = data.get("current_enemy_id")
		if eid:
			target_enemy_id = eid
			spawn_enemy() # This will reset weapons/timers but keep flow
	
	# Ensure max shield is set even if not in combat
	if GameState.shipyard_manager:
		player_max_shield = GameState.shipyard_manager.max_shield
func reset(decay_factor: float = 1.0) -> void:
	super.reset(decay_factor)
	retreat()

# v52.1: Offline Combat (opt-in via game_settings)
func calculate_offline(delta: float) -> String:
	if not in_combat or not current_zone or not current_enemy:
		return ""
	
	# Estimate kills based on average combat duration
	var avg_kill_time = 10.0 # Approximate seconds per kill
	var num_kills = int(delta / avg_kill_time)
	if num_kills <= 0: return ""
	
	var loot_summary = {}
	var total_xp = 0
	var credits_earned = 0
	
	for i in range(num_kills):
		# Award loot from current enemy
		var enemy_data = current_enemy
		for entry in enemy_data.get("loot", []):
			var item = entry[0]
			var min_amt = entry[1]
			var max_amt = entry[2]
			var amount = randi_range(min_amt, max_amt)
			# v61.0 Fix: credits in loot should be treated as currency
			if item == "credits":
				GameState.resources.add_currency("credits", amount)
				credits_earned += amount
			else:
				GameState.resources.add_element(item, amount)
				loot_summary[item] = loot_summary.get(item, 0) + amount
		
		# Check rare loot
		for entry in enemy_data.get("rare_loot", []):
			var item = entry[0]
			var chance = entry[1]
			var min_amt = entry[2]
			var max_amt = entry[3]
			if randf() < chance:
				var amount = randi_range(min_amt, max_amt)
				# v61.0 Fix: handle credits in rare_loot too
				if item == "credits":
					GameState.resources.add_currency("credits", amount)
					credits_earned += amount
				else:
					GameState.resources.add_element(item, amount)
					loot_summary[item] = loot_summary.get(item, 0) + amount
		
		# XP (removed defunct enemy_data.get("credits") - credits come from loot)
		var xp = enemy_data.get("xp", 10)
		total_xp += xp
	
	add_xp(total_xp)
	
	# Build report
	var report = "Combat Offline Gains (%d kills):\n" % num_kills
	for item in loot_summary:
		report += " + %d %s\n" % [loot_summary[item], item]
	if credits_earned > 0:
		report += " + %d Credits\n" % credits_earned
	report += " + %d XP" % total_xp
	
	return report
