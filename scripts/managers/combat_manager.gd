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
	# === ZONE 1: LUNAR ORBIT ===
	"dust_mite": {
		"name": "Space Dust Mite",
		"stats": {"hp": 50, "max_shield": 0, "atk": 3, "def": 0, "atk_interval": 2.5, "accuracy": 0},
		"loot": [["Scrap", 1, 2], ["MiteChitin", 1, 1]],  # Audit v20.0: Added MiteChitin unique
		"xp": 8
	},
	"lunar_drone": {
		"name": "Lunar Drone",
		"stats": {"hp": 60, "max_shield": 0, "atk": 5, "def": 1, "atk_interval": 2.5, "accuracy": 5},
		"loot": [["Scrap", 3, 5], ["Fe", 4, 10], ["DroneCore", 1, 1]],  # EXCLUSIVE: DroneCore
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
		"loot": [["Si", 5, 8], ["Cu", 1, 2], ["SalvageData", 1, 1], ["NavData", 2, 2]],  # P0 FIX: Guaranteed NavData (Audit 3.0: 2x)
		"rare_loot": [["Chip", 0.15, 2, 3]],
		"xp": 25
	},

	# New Asteroid Belt Enemies
	"claim_jumper": {
		"name": "Claim Jumper",
		"stats": {"hp": 2500, "max_shield": 100, "atk": 45, "def": 25, "atk_interval": 2.2, "accuracy": 20},
		"loot": [["credits", 250, 450], ["Cu", 15, 30], ["StolenCargo", 1, 1]],  # Audit v20.0: Added StolenCargo unique
		"rare_loot": [["NavData", 0.15, 2, 5]],
		"xp": 50
	},
	"ore_hauler": {
		"name": "Ore Hauler Wreck",
		"stats": {"hp": 4500, "max_shield": 0, "atk": 80, "def": 40, "atk_interval": 5.0, "accuracy": 25},
		"loot": [["Fe", 150, 300], ["C", 200, 500], ["Scrap", 10, 20]],
		"rare_loot": [["W", 0.35, 15, 30], ["U", 0.10, 2, 5]], 
		"xp": 80
	},
	# New Mars Debris Enemies
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
		"loot": [["Scrap", 10, 20], ["SwarmFragment", 1, 2]],  # Audit v20.0: Added SwarmFragment unique
		"rare_loot": [["Resin", 0.3, 1, 2], ["Cu", 0.2, 1, 2]],
		"xp": 35
	},
	# New Titan's Halo Enemies
	"frozen_hulk": {
		"name": "Frozen Hulk",
		"stats": {"hp": 6500, "max_shield": 250, "atk": 18, "def": 70, "atk_interval": 6.0, "accuracy": 40},
		"loot": [["C", 10, 20]],  # Best Carbon farm
		"rare_loot": [["Graphite", 0.35, 1, 3], ["W", 0.15, 1, 2]],
		"xp": 75
	},
	"smuggler_cutter": {
		"name": "Smuggler Cutter",
		"stats": {"hp": 450, "max_shield": 180, "atk": 32, "def": 25, "accuracy": 45},
		"loot": [["credits", 100, 200]],  # Best credits in D4
		"rare_loot": [["Li", 0.25, 1, 3], ["Ti", 0.2, 1, 2]],  # Rare Li/Ti
		"xp": 95
	},
	"pirate_skiff": {
		"name": "Pirate Skiff",
		"stats": {"hp": 3000, "max_shield": 200, "atk": 35, "def": 30, "atk_interval": 1.75, "accuracy": 50},
		"loot": [["credits", 2000, 6000], ["Scrap", 3, 6], ["PirateManifest", 1, 1], ["NavData", 1, 2], ["Cu", 100, 200]],
		"rare_loot": [["W", 0.40, 10, 20], ["Ti", 0.30, 40, 50]],
		"xp": 30
	},

	"rock_golem": {
		"name": "Silicate Golem",
		"stats": {"hp": 4500, "max_shield": 0, "atk": 60, "def": 12, "accuracy": 20},
		"loot": [["Si", 100, 200]],
		"rare_loot": [["Ti", 0.4, 10, 20]], # Audit v17.0: The Titanium Bridge

		"xp": 30
	},
	"scavenger_mech": {
		"name": "Scavenger Mech",
		"stats": {"hp": 4000, "max_shield": 100, "atk": 25, "def": 60, "accuracy": 40},
		"loot": [["Cu", 5, 10], ["Scrap", 5, 10]],
		"rare_loot": [["W", 0.3, 5, 10], ["Res2", 0.20, 1, 1], ["NavData", 0.25, 1, 2]],  # Audit v1.0: Added NavData
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
		"loot": [["H", 5, 15], ["Water", 5, 10], ["CryoCell", 1, 1]],  # Audit v20.0: Added CryoCell unique
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
		"rare_loot": [["NavData", 0.4, 3, 7], ["VoidArtifact", 0.3, 2, 4], ["Cr", 0.10, 1, 3], ["Res3", 0.25, 5, 8]],  # TIER FIX: Cr for Superalloy
		"xp": 800
	},
	"xenon_mothership": {
		"name": "XENON MOTHERSHIP",
		"stats": {"hp": 150000, "max_shield": 80000, "atk": 1200, "def": 250, "atk_interval": 6.0, "accuracy": 100},
		"loot": [["Ti", 200, 500], ["Chip", 25, 50], ["AdvCircuit", 10, 20], ["QuantumCore", 5, 10], ["VoidArtifact", 10, 25], ["Res3", 50, 100]],
		"rare_loot": [],
		"xp": 5000
	},
	# Sector Beta Enemies (Difficulty 6) - HP ~8k-15k
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
		"loot": [["ColonySalvage", 25, 50], ["Circuit", 20, 50], ["TurretCore", 1, 1]],  # Audit v20.0: Added TurretCore unique
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

	# Sector Gamma Enemies (Difficulty 7) - HP ~20k-80k
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
		"xp": 30000  # ITER3 FIX: Reduced from 150k (was 5x higher than intended)
	},

	# Sector Delta Enemies (Difficulty 8) - HP ~50k-150k
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
	"sentinel_prime": {
		"name": "SENTINEL PRIME",
		"stats": {"hp": 150000, "max_shield": 80000, "atk": 400, "def": 180, "accuracy": 150},
		"loot": [["VoidCrystal", 5, 10], ["Ir", 10, 20], ["QuantumCore", 2, 4]],
		"rare_loot": [["Os", 0.25, 1, 3], ["AncientTech", 0.2, 1, 1]],
		"xp": 5000
	},
	
	# === SECTOR EPSILON: THE VOID (Endgame) === HP 200k-2M, 60% AP attacks
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
	
	# Only clear session loot if we are actually changing zones or starting fresh
	if current_zone == zones[zone_id] and in_combat:
		return
		
	GameState.set_active_manager(self)
	current_zone = zones[zone_id]
	in_combat = true
	session_loot.clear()
	spawn_enemy()
	log_msg("Warped to %s." % current_zone["name"])
	target_enemy_id = null

func set_target_enemy(enemy_id):
	if enemy_id and enemy_id in enemy_db:
		GameState.set_active_manager(self)
		target_enemy_id = enemy_id
		if in_combat:
			spawn_enemy() # Respawn immediately
		else:
			in_combat = true
			spawn_enemy()
		log_msg("Targeting: %s" % enemy_db[enemy_id]["name"])
	else:
		target_enemy_id = null
		log_msg("Targeting cleared.")

func spawn_enemy():
	var eid = ""
	if target_enemy_id:
		eid = target_enemy_id
	else:
		if not current_zone: return
		var list_enemies = current_zone["enemies"]
		eid = list_enemies[randi() % list_enemies.size()]
		
	var e_data = enemy_db[eid]
	
	current_enemy = {
		"id": eid,
		"name": e_data["name"],
		"max_hp": e_data["stats"]["hp"],
		"atk": e_data["stats"]["atk"],
		"def": e_data["stats"]["def"],
		"accuracy": e_data["stats"].get("accuracy", 0), # Load accuracy
		"max_shield": e_data["stats"].get("max_shield", 0),
		"loot": e_data["loot"],
		"rare_loot": e_data.get("rare_loot", []),
		"xp": e_data["xp"],
		"jammer": e_data["stats"].get("jammer", false)
	}
	
	is_jammed = current_enemy.get("jammer", false)
	nanite_hot_timer = 0.0
	
	enemy_hp = current_enemy["max_hp"]
	enemy_max_hp = current_enemy["max_hp"]
	enemy_shield = float(current_enemy["max_shield"])
	enemy_max_shield = float(current_enemy["max_shield"])
	
	var sm = GameState.shipyard_manager
	var rm = GameState.research_manager
	player_max_shield = sm.max_shield
	
	if sm.current_hp <= 0:
		# If they start combat at 0 (after death), we give them internal battle HP
		# but they should have paid the repair bill already.
		sm.current_hp = sm.max_hp
		player_shield = player_max_shield
	
	# Initialize Player Weapon Battery
	player_weapon_states.clear()
	
	# 1. Collect Modules from loadout first
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
					"timer": randf_range(0.0, 0.5), # Slight stagger
					"interval": 2.5,
					"dmg_k": m_stats.get("atk_kinetic", 0),
					"dmg_e": m_stats.get("atk_energy", 0),
					"slot_idx": int(s_idx)
				})
				
	# 2. Add Hull's built-in weapon ONLY if no modules are equipped
	if equipped_weapons.is_empty():
		var h_stats = sm.hulls[sm.active_hull]["stats"]
		if h_stats.get("atk", 0) > 0:
			player_weapon_states.append({
				"name": "Standard Cannon",
				"type": "kinetic",
				"timer": 0.0,
				"interval": 3.0, # Slower base
				"dmg_k": h_stats["atk"],
				"dmg_e": 0,
				"slot_idx": -1 # No module
			})
	else:
		player_weapon_states.append_array(equipped_weapons)

	log_msg("Encountered: " + current_enemy["name"])
	log_msg("Readying Weapon Battery: %d systems online." % player_weapon_states.size())

func retreat():
	in_combat = false
	current_enemy = null
	for w in player_weapon_states:
		w["timer"] = 0.0
	enemy_attack_timer = 0.0
	session_loot.clear()
	
	log_msg("Emergency Warp engaged! Expedition aborted.")

func stop_action():
	retreat()

func process_tick(delta: float):
	if not in_combat or not current_enemy: return
	
	var sm = GameState.shipyard_manager
	var rm = GameState.research_manager
	var p_speed_mult = 1.0 + rm.get_efficiency_bonus("attack_speed")
	p_speed_mult *= GameState.warp_manager.get_combat_multiplier()
	
	# Audit v12.0: Thermal Stress Logic
	if overheat_lock > 0:
		overheat_lock -= delta
		# Overheat Penalty: Minor Hull Damage (2.5% per sec)
		sm.current_hp -= sm.max_hp * 0.025 * delta
		if overheat_lock <= 0:
			log_msg("SYSTEMS RECOVERED: Weapons online.")
	
	# Vent Heat
	if player_heat > 0:
		player_heat = max(0, player_heat - player_vent_rate * delta)
		heat_changed.emit(player_heat, player_max_heat)
	
	# High Heat Penalty: 80% Heat = 50% Speed
	if player_heat > 80.0:
		p_speed_mult *= 0.5
		
	# Global Regen (Enemy)
	if enemy_shield < enemy_max_shield:
		enemy_shield = min(enemy_max_shield, enemy_shield + (enemy_max_shield * 0.02 * delta))
	
	# Warp Stabilizer check
	for slot in sm.loadout:
		if sm.loadout[slot] == "warp_stabilizer":
			p_speed_mult += 0.15 # 15% Faster combat
			break
			
	# Update Player Weapon Timers
	for w_idx in range(player_weapon_states.size()):
		var w = player_weapon_states[w_idx]
		w["timer"] += delta * p_speed_mult
		if w["timer"] >= w["interval"]:
			_execute_player_attack(w_idx)
			w["timer"] = 0.0
		
	# Update Enemy Timer
	# Assume enemy is constant speed unless we add status effects later
	enemy_attack_timer += delta 
	var e_interval = current_enemy.get("atk_interval", 3.0)
	if enemy_attack_timer >= e_interval:
		_execute_enemy_attack()
		enemy_attack_timer = 0.0
		
	# Cooldowns tick per second conceptually
	if consumable_cooldown > 0:
		consumable_cooldown -= delta
		
	# Audit v9.0: Nanite HoT Logic
	if nanite_hot_timer > 0:
		nanite_hot_timer -= delta
		var heal_tick = (sm.max_hp * 0.02) * delta
		sm.current_hp = min(sm.max_hp, sm.current_hp + heal_tick)
		
	# Balanced Phase 2: Coolant Flush
	if coolant_flush_timer > 0:
		coolant_flush_timer -= delta
		p_speed_mult *= 2.0 # Doubled speed
		
	# Balanced Phase 2: Broadside Burst
	var has_broadside = false
	for slot in sm.loadout:
		if sm.loadout[slot] == "broadside_array":
			has_broadside = true
			break
			
	if has_broadside and in_combat and current_enemy:
		broadside_timer += delta
		if broadside_timer >= 20.0:
			_execute_broadside_burst()
			broadside_timer = 0.0
			
	# Forensic 3: Constant Shield Regen (Standalone timer)
	var regen_mult = 1.0 + rm.get_efficiency_bonus("shield_regen")
	shield_regen_accumulator += delta
	if shield_regen_accumulator >= 1.0:
		if player_shield < player_max_shield:
			player_shield = min(player_max_shield, player_shield + (sm.shield_regen * regen_mult))
		shield_regen_accumulator = 0.0

func _execute_player_attack(weapon_idx: int = 0):
	if weapon_idx >= player_weapon_states.size(): return
	var w = player_weapon_states[weapon_idx]
	var sm = GameState.shipyard_manager
	
	# Audit v12.0: Overheat check
	if overheat_lock > 0:
		return
		
	# Forensic 3: Energy Enforcement
	var e_cost = w.get("energy_load", 0) * 0.1 # Concept: 10% of load per shot
	if GameState.resources.get_energy() < e_cost:
		log_msg("LACK OF ENERGY: Weapon Offline!")
		return
	GameState.resources.add_energy(-e_cost)
	
	# Audit v9.0 P1-29: Targeting Jammer (25% Miss Chance)
	if is_jammed and randf() < 0.25:
		log_msg("JAMMED: Targeting computer failed!")
		combat_events.append({"type": "miss", "text": "JAMMED", "color": Color.ORANGE, "side": "enemy"})
		return

	# --- Periodic Maintenance (Only on first weapon or special tick?) ---
	# We perform shield regen and buff decay once per "firing cycle" of the hull if possible
	# but for simplicity, let's keep it here or handle independently.
	# Decision: Regen on every firing increases regen speed, so we scale it.
	# Auto-Consume
	if auto_consume_enabled and equipped_consumable_id:
		var hp_thresh = auto_consume_threshold * sm.max_hp
		if sm.current_hp < hp_thresh:
			use_consumable()
		elif equipped_consumable_id == "Mesh": # Shield Item
			var s_thresh = auto_consume_threshold * player_max_shield
			if player_shield < s_thresh:
				use_consumable()

	# Audit v12.0: Heat Generation
	# Formula: Base 2.0 + small fraction of total damage
	var heat_gen = 2.0 + ((w["dmg_k"] + w["dmg_e"]) / 100.0)
	player_heat += heat_gen
	heat_changed.emit(player_heat, player_max_heat)
	
	if player_heat >= player_max_heat:
		player_heat = player_max_heat
		overheat_lock = 5.0 # 5 Second lockout
		log_msg("CRITICAL OVERHEAT! Systems rebooting...")
		combat_events.append({"type": "miss", "text": "OVERHEAT", "color": Color.RED, "side": "enemy"})
		return # This shot fails due to emergency shutdown

	# Buff Duration Logic
	if "dmg_bonus_duration" in active_buffs:
		active_buffs["dmg_bonus_duration"] -= 1
		if active_buffs["dmg_bonus_duration"] <= 0:
			if "dmg_bonus_k" in active_buffs: active_buffs.erase("dmg_bonus_k")
			if "dmg_bonus_e" in active_buffs: active_buffs.erase("dmg_bonus_e")
			active_buffs.erase("dmg_bonus_duration")
			log_msg("Ammo depleted.")

	# --- Attack Calculation for this specific weapon ---
	var p_atk_k = w["dmg_k"]
	var p_atk_e = w["dmg_e"]
	
	# Plasma Overcharger implementation (Apply to all energy weapons)
	if w["type"] == "energy":
		for slot in sm.loadout:
			if sm.loadout[slot] == "plasma_overcharger":
				p_atk_e *= 2.0 # 100% Boost
				break
	
	# Ammo Logic Check for this slot
	var can_fire = true
	var ammo_id = sm.ammo_loadout.get(w["slot_idx"])
	var ammo_armor_bypass = 0.0
	
	if ammo_id and ammo_id != "":
		var qty = GameState.resources.get_element_amount(ammo_id)
		if qty > 0:
			GameState.resources.remove_element(ammo_id, 1)
			# ITER3 FIX: Tiered ammo bonuses now use % scaling instead of flat
			# T2 also grants 15% armor bypass as special effect
			if ammo_id == "SlugT1": p_atk_k = int(p_atk_k * 1.10)  # +10%
			elif ammo_id == "SlugT2": 
				p_atk_k = int(p_atk_k * 1.25)  # +25%
				ammo_armor_bypass = 0.15  # ITER3: T2 special - 15% armor bypass
			elif ammo_id == "SlugT3": p_atk_k = int(p_atk_k * 1.50)  # +50%
			elif ammo_id == "CellT1": p_atk_e = int(p_atk_e * 1.10)  # +10%
			elif ammo_id == "CellT2": 
				p_atk_e = int(p_atk_e * 1.25)  # +25%
				ammo_armor_bypass = 0.15  # ITER3: T2 special - 15% armor bypass
			elif ammo_id == "CellT3": p_atk_e = int(p_atk_e * 1.50)  # +50%
		else:
			log_msg("SLOT %d OFFLINE: Ammunition Depleted!" % w["slot_idx"])
			can_fire = false
	else:
		log_msg("SLOT %d OFFLINE: No Ammunition Equipped!" % w["slot_idx"])
		can_fire = false

	if not can_fire:
		combat_events.append({"type": "miss", "text": "OFFLINE", "color": Color.GRAY, "side": "enemy"})
		return
		
	var e_def = current_enemy["def"]
	var difficulty = current_zone.get("difficulty", 1)
	
	# Audit v7.0 P1-22: Combat Skill Damage Bonus (+0.5% per Level)
	var skill_dmg_mult = 1.0 + (get_level() * 0.005)
	p_atk_k *= skill_dmg_mult
	p_atk_e *= skill_dmg_mult
	
	var res = resolve_damage(p_atk_k, p_atk_e, enemy_shield, e_def, difficulty)
	# res = [shield_dmg, hull_dmg, is_crit]
	
	# Targeting Computer Logic
	# Force crit check if not already crit
	if not res[2]: 
		var crit_chance_bonus = 0.0
		# Check Ship Loadout for 'targeting_computer'
		# ShipyardManager exposes loadout?
		if "loadout" in sm: # Dictionary
			for slot in sm.loadout:
				if sm.loadout[slot] == "targeting_computer":
					crit_chance_bonus += 0.15 # 15% Crit
					
		if crit_chance_bonus > 0 and randf() < crit_chance_bonus:
			res[2] = true # Force Crit
			res[0] = int(res[0] * 1.5)
			res[1] = int(res[1] * 1.5)
	
	enemy_shield = max(0, enemy_shield - res[0])
	enemy_hp -= res[1]
	
	if res[0] > 0:
		combat_events.append({"type": "dmg_shield", "text": "-%d" % res[0], "color": Color.CYAN, "side": "enemy"})
	if res[1] > 0:
		combat_events.append({"type": "dmg_hull", "text": "-%d" % res[1], "color": Color.RED, "side": "enemy"})
		
	var msg = "PLAYER: -%d Shield, -%d Hull" % [res[0], res[1]]
	if res[2]: msg += " (CRIT!)"
	if ammo_id and ammo_id != "": msg += " [AMMO]"
	log_msg(msg)
	
	if enemy_hp <= 0:
		win_fight()
		return

func _execute_enemy_attack():
	var sm = GameState.shipyard_manager
	# --- Enemy Turn ---
	var e_atk = current_enemy["atk"]
	var e_atk_k = e_atk
	var e_atk_e = 0
	if "alien" in current_enemy["id"]: # Simple check
		e_atk_k = 0
		e_atk_e = e_atk
		
	# Dodge - ITER7: Diminishing Returns Formula with Enemy Accuracy Layer
	var e_acc = current_enemy.get("accuracy", 0)
	var dodge_chance = float(sm.evasion) / (float(sm.evasion) + 150.0 * (1.0 + float(e_acc) / 100.0))
	# Deferred P2-9: Hard cap evasion at 75% to prevent god-mode builds
	dodge_chance = min(dodge_chance, 0.75)
	
	var roll = randf()
	if roll < dodge_chance:
		# PARRY MECHANIC: If roll is in the bottom 20% of the success range
		if roll < dodge_chance * 0.2:
			var p_atk = current_enemy["atk"]
			var max_reflect = int(current_enemy["max_hp"] * 0.05) # Cap at 5% of max HP
			var reflected = min(int(p_atk), max_reflect) # Reflect 100% up to the cap
			
			enemy_hp -= reflected
			log_msg("PERFECT DODGE: Parried and reflected %d damage!" % reflected)
			combat_events.append({"type": "parry", "text": "PARRY %d" % reflected, "color": Color.DEEP_SKY_BLUE, "side": "enemy"})
			
			# SHIELD BUFFER (Audit v6.0): Successful Parry restores 5% of MISSING shield
			var missing_shield = player_max_shield - player_shield
			var restore_amt = int(missing_shield * 0.05)
			if restore_amt > 0:
				player_shield = min(player_max_shield, player_shield + restore_amt)
				combat_events.append({"type": "heal", "text": "+%d SHIELD" % restore_amt, "color": Color.CYAN, "side": "player"})
			# Flash the screen/HUD?
		else:
			log_msg("Player Dodged!")
			combat_events.append({"type": "miss", "text": "MISS", "color": Color.WHITE, "side": "player"})
	else:
		var p_def = sm.defense
		
		# ITER2 FIX: Armor Piercing - Late-game enemies bypass armor to counter Osmium stacking
		var armor_piercing = 0.0
		if current_enemy and current_enemy.get("id"):
			var eid = current_enemy["id"]
			# Sector Gamma enemies have 30% AP
			if eid in ["radiation_beast", "nebula_leviathan", "gamma_colossus"]:
				armor_piercing = 0.30
			# Sector Delta enemies have 50% AP
			elif eid in ["crystal_golem", "energy_wraith", "sentinel_prime"]:
				armor_piercing = 0.50
			# Sector Epsilon enemies have 60% AP (endgame)
			elif eid in ["void_stalker", "temporal_phantom", "omega_sentinel", "primordial_titan"]:
				armor_piercing = 0.60
		
		# Apply AP reduction to player defense
		var effective_def = p_def * (1.0 - armor_piercing)
		
		# Reactive Armor Implementation
		var hp_percent = float(sm.current_hp) / float(sm.max_hp)
		var reactive_reduction = 1.0
		if hp_percent < 0.9: # Bonus starts below 90%
			for slot in sm.loadout:
				if sm.loadout[slot] == "reactive_armor":
					# 5% reduction for every 10% missing
					var missing_chunks = floor((1.0 - hp_percent) * 10.0)
					reactive_reduction = 1.0 - (missing_chunks * 0.05)
					reactive_reduction = max(0.4, reactive_reduction) # Cap at 60% reduction
					break

		# ITER7: Pass difficulty to resolve_damage for scaling mitigation
		var difficulty = current_zone.get("difficulty", 1)
		var eres = resolve_damage(e_atk_k * reactive_reduction, e_atk_e * reactive_reduction, player_shield, effective_def, difficulty)
		
		player_shield = max(0, player_shield - eres[0])
		sm.current_hp -= eres[1]
		
		if eres[0] > 0:
			combat_events.append({"type": "dmg_shield", "text": "-%d" % eres[0], "color": Color.CYAN, "side": "player"})
		if eres[1] > 0:
			combat_events.append({"type": "dmg_hull", "text": "-%d" % eres[1], "color": Color.RED, "side": "player"})

		# Reflective Sheath Implementation
		for slot in sm.loadout:
			if sm.loadout[slot] == "reflective_sheath":
				if randf() < 0.2: # 20% Chance
					var reflected = int((eres[0] + eres[1]) * 0.5)
					if reflected > 0:
						enemy_hp -= reflected
						log_msg("REFLECTED: %d damage back to enemy!" % reflected)
						combat_events.append({"type": "dmg_hull", "text": "REFLECT %d" % reflected, "color": Color.ORANGE, "side": "enemy"})
					break

		log_msg("ENEMY: -%d Shield, -%d Hull" % [eres[0], eres[1]])

	if sm.current_hp <= 0:
		lose_fight()

func resolve_damage(atk_k, atk_e, c_shield, c_armor, difficulty = 1):
	var shield_dmg_pot = (atk_k * 0.5) + (atk_e * 1.5)
	
	var damage_to_shield = 0.0
	var bleed_ratio = 1.0
	
	if c_shield > 0:
		if shield_dmg_pot >= c_shield:
			damage_to_shield = c_shield
			var remaining = shield_dmg_pot - c_shield
			bleed_ratio = remaining / shield_dmg_pot if shield_dmg_pot > 0 else 0.0
		else:
			damage_to_shield = shield_dmg_pot
			bleed_ratio = 0.0
	
	# Minimum impact rule: Any hit that connects should do something
	if damage_to_shield == 0 and shield_dmg_pot > 0:
		damage_to_shield = 1.0
			
	var damage_to_hull = 0.0
	if bleed_ratio > 0:
		# P1 FIX: Energy Penetration - Energy ignores 30% of armor
		var energy_armor_pen = 0.30
		var armor_for_kinetic = c_armor
		var armor_for_energy = c_armor * (1.0 - energy_armor_pen)
		
		# ITER7: Armor Divisor scales with difficulty to prevent high-tier paralysis
		# k = 50 * Difficulty (min 20)
		var k = max(20.0, float(difficulty) * 50.0)
		
		# Calculate kinetic portion
		var k_hull_pot = atk_k * 1.2
		var k_mitigation = float(armor_for_kinetic) / (float(armor_for_kinetic) + k)
		var k_damage = k_hull_pot * (1.0 - k_mitigation)
		
		# Calculate energy portion (buffed from 0.7 to 0.9)
		var e_hull_pot = atk_e * 0.9
		var e_mitigation = float(armor_for_energy) / (float(armor_for_energy) + k)
		var e_damage = e_hull_pot * (1.0 - e_mitigation)
		
		damage_to_hull = (k_damage + e_damage) * bleed_ratio
		
		# Minimum 1 damage if anything bled through
		if damage_to_hull < 1.0 and (atk_k + atk_e) > 0:
			damage_to_hull = 1.0
			
	var variance = randf_range(0.9, 1.1)
	var is_crit = false
	if randf() < 0.05:
		variance *= 1.5
		is_crit = true
		
	return [int(damage_to_shield * variance), int(damage_to_hull * variance), is_crit]

func win_fight():
	log_msg("Destroyed %s!" % current_enemy["name"])
	
	var rm = GameState.research_manager
	
	# Loot
	var loot = current_enemy["loot"]
	for entry in loot:
		# entry = [item, min, max]
		var item = entry[0]
		var qty = randi_range(entry[1], entry[2])
		if item == "credits":
			GameState.resources.add_currency("credits", qty)
		else:
			GameState.resources.add_element(item, qty)
		
		# Track Session Loot
		session_loot[item] = session_loot.get(item, 0) + qty
		log_msg("Looted: %d %s" % [qty, item])
		
	# Rare Loot
	var rare = current_enemy["rare_loot"]
	for entry in rare:
		# entry = [item, chance, min, max]
		if randf() < entry[1]:
			var qty = randi_range(entry[2], entry[3])
			GameState.resources.add_element(entry[0], qty)
			
			# Track Session Loot
			var item = entry[0]
			session_loot[item] = session_loot.get(item, 0) + qty
			log_msg("RARE DROP: %d %s!" % [qty, entry[0]])
			
	# Bonus DroneCore (Scavenger Protocol)
	if current_enemy["id"] == "lunar_drone":
		var drone_bonus = rm.get_efficiency_bonus("drone_core_chance")
		if drone_bonus > 0 and randf() < drone_bonus:
			GameState.resources.add_element("DroneCore", 1)
			session_loot["DroneCore"] = session_loot.get("DroneCore", 0) + 1
			log_msg("BONUS L-DRONE RECOVERY: 1 DroneCore")

	var xp_to_add = current_enemy["xp"] * (1.0 + rm.get_efficiency_bonus("combat_xp"))
	add_xp(int(xp_to_add))
	enemy_defeated.emit(current_enemy["id"])
	spawn_enemy()

func lose_fight():
	log_msg("CRITICAL FAILURE. Ship destroyed.")
	
	# Calculate Repair Cost based on ship tier from shipyard_manager
	var sm = GameState.shipyard_manager
	var repair_cost = sm.get_full_repair_cost(sm.active_hull)
	
	# Deduct credits (can go negative = debt)
	GameState.resources.add_currency("credits", -repair_cost)
	
	log_msg("REPAIR BILL: %d Credits" % repair_cost)
	combat_events.append({
		"type": "repair", 
		"text": "REPAIR: -%d Cr" % repair_cost, 
		"color": Color.ORANGE, 
		"side": "player"
	})
	
	retreat()

# Deleted local _get_repair_cost as it's now centralized in shipyard_manager

func equip_consumable(item_id):
	equipped_consumable_id = item_id

func toggle_auto_consume(enabled):
	auto_consume_enabled = enabled

func use_consumable():
	if not in_combat or not equipped_consumable_id: return
	if consumable_cooldown > 0: return
	
	if GameState.resources.get_element_amount(equipped_consumable_id) < 1:
		log_msg("Out of %s!" % equipped_consumable_id)
		return
		
	GameState.resources.remove_element(equipped_consumable_id, 1)
	consumable_cooldown = consumable_cooldown_max
	
	# CONSUMABLES (Healing Items Only)
	# Note: Ammo items (SlugT1, CellT1, etc.) are handled in shipyard active_ammo slot
	
	if equipped_consumable_id == "Mesh":
		# Shield Repair
		var heal_amount = 50
		player_shield = min(player_max_shield, player_shield + heal_amount)
		combat_events.append({"type": "heal", "text": "+%d Shield" % heal_amount, "color": Color.GREEN, "side": "player"})
		log_msg("Used Nanoweave Mesh (+%d Shield)" % heal_amount)
		
	elif equipped_consumable_id == "Seal":
		# Hull Repair
		var sm = GameState.shipyard_manager
		var heal_amount = 50
		sm.current_hp = min(sm.max_hp, sm.current_hp + heal_amount)
		combat_events.append({"type": "heal", "text": "+%d HP" % heal_amount, "color": Color.GREEN, "side": "player"})
		log_msg("Used Hull Sealant (+%d HP)" % heal_amount)
		
	elif equipped_consumable_id == "NitroCoolant":
		# Coolant Flush
		coolant_flush_timer = 10.0
		log_msg("NITROGEN FLUSH: Attack speed doubled for 10s!")
		combat_events.append({"type": "buff", "text": "SPEED BOOST", "color": Color.AQUA, "side": "player"})

	elif equipped_consumable_id == "nanite_swarm":
		# Nanite Repair Swarm - HoT
		nanite_hot_timer = nanite_hot_duration
		log_msg("NANITE SWARM: Rapid hull repair active (15s)!")
		combat_events.append({"type": "heal", "text": "NANITES ON", "color": Color.SPRING_GREEN, "side": "player"})

	# Audit v2.0: Early consumables
	elif equipped_consumable_id == "EmergencyPatch":
		# Emergency Hull Patch - Basic healing
		var sm = GameState.shipyard_manager
		var heal_amount = 50
		sm.current_hp = min(sm.max_hp, sm.current_hp + heal_amount)
		combat_events.append({"type": "heal", "text": "+%d HP" % heal_amount, "color": Color.GREEN, "side": "player"})
		log_msg("EMERGENCY PATCH: +%d Hull" % heal_amount)
		
	elif equipped_consumable_id == "BasicBooster":
		# Basic Shield Booster - Early shield restore
		var restored = 30
		player_shield = min(player_max_shield, player_shield + restored)
		combat_events.append({"type": "heal", "text": "+%d Shield" % restored, "color": Color.CYAN, "side": "player"})
		log_msg("SHIELD BOOST: +%d Shield" % restored)

	else:
		# Unknown consumable - just consume it silently
		log_msg("Used %s (no effect)" % equipped_consumable_id)

func _execute_broadside_burst():
	var total_kinetic_dps = 0.0
	for w in player_weapon_states:
		if w["type"] == "kinetic":
			total_kinetic_dps += (w["dmg_k"] / w["interval"])
			
	if total_kinetic_dps <= 0:
		# Fallback if no specific kinetic weapons, use 20% of base atk as proxy
		total_kinetic_dps = GameState.shipyard_manager.attack * 0.2
		
	var burst_dmg = int(total_kinetic_dps * 3.0 * 20.0) # 300% of DPS over the 20s interval
	# Apply Mitigation
	var mitigation = float(current_enemy.get("def", 0)) / (float(current_enemy.get("def", 0)) + 20.0)
	var final_dmg = int(burst_dmg * (1.0 - mitigation))
	
	if final_dmg < 1: final_dmg = 1
	
	enemy_hp -= final_dmg
	log_msg("BROADSIDE BURST: %d Kinetic damage!" % final_dmg)
	combat_events.append({"type": "dmg_hull", "text": "BURST %d" % final_dmg, "color": Color.GOLD, "side": "enemy"})
	
	if enemy_hp <= 0:
		win_fight()


func log_msg(msg: String):
	combat_log.append(msg)
	if combat_log.size() > 20:
		combat_log.pop_front()
	# Signal?
	
func get_save_data_manager() -> Dictionary:
	var data = get_save_data()
	# Save XP is handled by base Skill.
	# We generally don't save mid-combat state for idle games usually, just reset to home.
	return data

func load_save_data_manager(data: Dictionary):
	load_save_data(data)

func reset(decay_factor: float = 1.0) -> void:
	super.reset(decay_factor)
	retreat()
	log_msg("Combat Reset.")
