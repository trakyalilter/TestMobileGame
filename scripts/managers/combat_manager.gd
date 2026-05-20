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

# Throttle for the "no ammo" combat warning so it doesn't spam every tick.
var _last_ammo_warn_ms: int = 0

signal enemy_defeated(enemy_id)
signal combat_started() # v72.8: For Elite bounty detection

# Buffs
var active_buffs = {} # {buff_name: duration}

# Session Tracking
var session_loot = {} # {item_id: total_amount}

# Combat timers shown on the combat page HUD.
# combat_session_time runs from engage until retreat (overall combat duration).
# time_since_last_kill resets to 0 on every enemy_defeated and tracks the
# current kill streak's elapsed time. Both only accumulate while in_combat.
var combat_session_time: float = 0.0
var time_since_last_kill: float = 0.0

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

# v85.2: D4 Combat States
var enemy_vulnerable_timer = 0.0
var player_berserk_timer = 0.0

# v85.0: Loot Filter Settings
var loot_filter: Dictionary = {
	0: true, # COMMON
	1: true, # UNCOMMON
	2: true, # RARE
	3: true, # LEGENDARY
	4: true  # UNIQUE
}
var loot_type_filter: Dictionary = {
	"weapon": true,
	"armor": true,
	"shield": true,
	"engine": true,
	"battery": true,
	"sensor": true
}
# Sub-filter for WEAPON drops by damage type (only consulted when a dropped
# module is a weapon). Lets players farm e.g. only explosive weapons.
var loot_weapon_type_filter: Dictionary = {
	"kinetic": true,
	"energy": true,
	"explosive": true
}

# Relative drop weight per slot type. Core combat gear stays dominant;
# sensor/engine are rarer "spice" drops so widening the pools doesn't tax
# weapon/shield/armor frequency. Battery is weight 0 by design: it has a
# single stat with deterministic Shipyard scaling (zone_N_access gated) and
# only one weak affix, so loot treatment would add dilution, not depth —
# it is acquired exclusively from the Shipyard.
const MODULE_DROP_WEIGHTS := {
	"weapon": 10, "shield": 10, "armor": 10,
	"sensor": 4, "engine": 4,
	"battery": 0,
}

# v86.0: Hazard Zone (Dungeon) State
var hazard_state = {
	"active": false,
	"zone_id": "",
	"wave": 0,
	"max_waves": 7,
	"completed": false
}
var boss_kills: Dictionary = {} # {enemy_id: kill_count}
var hazard_clears: Dictionary = {} # {hazard_zone_id: true}

# Progression compensation so external multipliers (level/research/warp/trophy)
# don't invalidate zone pacing.
const ENEMY_COMP_REGULAR_HP = 0.28
const ENEMY_COMP_REGULAR_SHIELD = 0.24
const ENEMY_COMP_REGULAR_ATK = 0.18
const ENEMY_COMP_BOSS_HP = 0.42
const ENEMY_COMP_BOSS_SHIELD = 0.36
const ENEMY_COMP_BOSS_ATK = 0.28
const ENEMY_COMP_DEF = 0.12

# v87.0: Enemy Typed Damage Balance Compensation
# Energy enemies deal 1.5x to shields (up from 0.5x kinetic), so reduce raw ATK
# Explosive enemies bypass 80% armor, so reduce raw ATK
const ENEMY_ENERGY_ATK_COMP = 0.75
const ENEMY_EXPLOSIVE_ATK_COMP = 0.85

# v80.1: Combat Safety Caps — Anti-Exploit Hard Ceilings
const MIN_ATTACK_INTERVAL = 0.3           # Prevents infinite DPS
const MAX_ATK_SPEED_MULT = 3.0            # Max 3x base fire rate
const MAX_EVASION = 75                    # Enemies always ≥25% hit chance
const MAX_CRIT_CHANCE = 0.50              # No guaranteed crit loops
const MAX_CRIT_DAMAGE = 3.0               # Caps burst spikes
const MAX_DAMAGE_REDUCTION = 0.80         # Explicit DEF ceiling
const MAX_SHIELD_REGEN_PERCENT = 5        # % of max shield per second
const MAX_HP_REGEN_PERCENT = 2            # % of max HP per second
const MAX_ENEMY_SLOW = 0.50               # Jamming can't freeze enemies
const MAX_REFLECT_PERCENT = 0.10          # Reflect capped
const DEF_K_CONSTANT = 40.0               # v103: lowered so enemy/player DEF actually mitigates
const DEF_K_ZONE_SCALE = 30.0             # was 100/100 → DEF was ~14% at Z3 boss (worthless); now ~35%
const DEF_K_ZONE_EXP = 1.3                # k(zone) = BASE + SCALE * zone^EXP. MAX_DAMAGE_REDUCTION clamp below prevents unkillable late enemies

# v80.1: Trinity Set Bonus Definitions — 3/3 pieces needed
# Bonuses are substantial rewards for hunting all 3 pieces from zone bosses (3% drop each)
var active_trinity_sets: Array = []  # Populated on stat recalc

const TRINITY_SET_BONUSES = {
	"architects_regalia":  {"name": "Architect's Regalia",  "pieces": 3, "bonus": {"atk_speed_pct": 25, "hp_regen_flat": 20}},
	"monoliths_bedrock":   {"name": "Monolith's Bedrock",   "pieces": 3, "bonus": {"def_pct": 20, "reflect_pct": 10}},
	"warmasters_arsenal":  {"name": "Warmaster's Arsenal",  "pieces": 3, "bonus": {"crit_chance": 20, "atk_pct": 18}},
	"overseers_command":   {"name": "Overseer's Command",   "pieces": 3, "bonus": {"shield_regen_pct": 22, "accuracy_flat": 120}},
	"harbingers_wrath":    {"name": "Harbinger's Wrath",    "pieces": 3, "bonus": {"missile_dmg_pct": 30, "enemy_def_reduce_pct": 20}},
	"colossus_dominion":   {"name": "Colossus Dominion",    "pieces": 3, "bonus": {"all_dmg_pct": 22, "evasion_flat": 12}},
	"sovereigns_prism":    {"name": "Sovereign's Prism",    "pieces": 3, "bonus": {"def_flat": 800, "energy_dmg_pct": 22}},
	"wardens_quarantine":  {"name": "Warden's Quarantine",  "pieces": 3, "bonus": {"shield_hp_pct": 35, "crit_chance": 16}},
	"titans_legacy":       {"name": "Titan's Legacy",       "pieces": 3, "bonus": {"all_dmg_pct": 28, "def_flat": 1500}},
	"leviathans_crown":    {"name": "Leviathan's Crown",    "pieces": 3, "bonus": {"all_dmg_pct": 35, "hp_regen_flat": 3000}}
}

func _get_active_trinity_sets() -> Array:
	var sm = GameState.shipyard_manager
	if not sm:
		return []
	var set_counts = {}
	for slot in sm.loadout:
		var mod_id = sm.loadout[slot]
		if mod_id == null or mod_id == "":
			continue
		# Look up module data
		var mod_data = sm.modules.get(mod_id, {})
		var sid = mod_data.get("set_id", "")
		
		# Fallback: if sid is missing on custom item, check base module
		if sid == "" and mod_data.get("is_custom") and mod_data.has("base_module"):
			var base_id = mod_data["base_module"]
			sid = sm.modules.get(base_id, {}).get("set_id", "")
			
		if sid != "":
			set_counts[sid] = set_counts.get(sid, 0) + 1
	var result = []
	for sid in set_counts:
		if sid in TRINITY_SET_BONUSES:
			if set_counts[sid] >= TRINITY_SET_BONUSES[sid]["pieces"]:
				result.append(sid)
	return result

func get_set_piece_count(set_id: String) -> int:
	var sm = GameState.shipyard_manager
	if not sm: return 0
	var count = 0
	for slot in sm.loadout:
		var mod_id = sm.loadout[slot]
		if mod_id == null or mod_id == "": continue
		var mod_data = sm.modules.get(mod_id, {})
		var sid = mod_data.get("set_id", "")
		
		# Fallback: if sid is missing on custom item, check base module
		if sid == "" and mod_data.get("is_custom") and mod_data.has("base_module"):
			var base_id = mod_data["base_module"]
			sid = sm.modules.get(base_id, {}).get("set_id", "")
			
		if sid == set_id:
			count += 1
	return count

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

# v80.1: Formula-driven zones — 10 zones with proper research gates
var zones = {
	"lunar_orbit": {
		"name": "Lunar Orbit",
		"desc": "Low threat sector populated by rogue mining drones.",
		"difficulty": 1,
		"enemies": ["z1_dust_mite", "z1_lunar_drone", "z1_scrap_collector", "z1_survey_probe", "z1_boss_architect"]
	},
	"asteroid_belt": {
		"name": "Asteroid Belt",
		"desc": "Dense asteroid field. Pirates and territorial fauna.",
		"difficulty": 2,
		"enemies": ["z2_pirate_skiff", "z2_silicate_golem", "z2_claim_jumper", "z2_ore_hauler", "z2_boss_monolith"],
		"research_req": "zone_2_access"
	},
	"mars_debris": {
		"name": "Mars Debris Field",
		"desc": "War-torn debris. Salvage mechs and derelict defenses.",
		"difficulty": 3,
		"enemies": ["z3_scavenger_mech", "z3_martian_sentry", "z3_salvage_swarm", "z3_derelict_frigate", "z3_boss_warmaster"],
		"research_req": "zone_3_access"
	},
	"cryofield": {
		"name": "Cryofield",
		"desc": "Frozen deep-space anomaly. Cryo-adapted hostiles.",
		"difficulty": 4,
		"enemies": ["z4_ice_wraith", "z4_cryo_sentinel", "z4_frost_hulk", "z4_glacial_drone", "z4_boss_overseer"],
		"research_req": "zone_4_access"
	},
	"sector_alpha": {
		"name": "Sector Alpha",
		"desc": "Xenon-controlled territory. Advanced alien technology.",
		"difficulty": 5,
		"enemies": ["z5_xenon_scout", "z5_xenon_corvette", "z5_alien_frigate", "z5_alien_probe", "z5_boss_harbinger"],
		"research_req": "zone_5_access"
	},
	"sector_beta": {
		"name": "Sector Beta",
		"desc": "Abandoned mining colony. Automated defense systems.",
		"difficulty": 6,
		"enemies": ["z6_defense_turret", "z6_mining_golem", "z6_rad_beast", "z6_ore_guardian", "z6_boss_colossus"],
		"research_req": "zone_6_access"
	},
	"sector_gamma": {
		"name": "Sector Gamma",
		"desc": "Deep space void. Energy wraiths and exotic matter.",
		"difficulty": 7,
		"enemies": ["z7_shard_swarm", "z7_energy_wraith", "z7_void_hunter", "z7_gamma_beast", "z7_boss_sovereign"],
		"research_req": "zone_7_access"
	},
	"sector_delta": {
		"name": "Sector Delta",
		"desc": "Crystal nebula. Prismatic entities and void anomalies.",
		"difficulty": 8,
		"enemies": ["z8_prism_drone", "z8_crystal_golem", "z8_void_stalker", "z8_nebula_phantom", "z8_boss_warden"],
		"research_req": "zone_8_access"
	},
	"sector_zeta": {
		"name": "Sector Zeta",
		"desc": "Quarantine zone. Biological horrors and rogue AI.",
		"difficulty": 9,
		"enemies": ["z9_plague_drone", "z9_bio_horror", "z9_rogue_ai", "z9_quarantine_mech", "z9_boss_patient_zero"],
		"research_req": "zone_9_access"
	},
	"sector_epsilon": {
		"name": "Sector Epsilon",
		"desc": "Beyond known space. Primordial entities and temporal anomalies.",
		"difficulty": 10,
		"enemies": ["z10_void_stalker", "z10_temporal_phantom", "z10_omega_sentinel", "z10_primordial_titan", "z10_boss_leviathan"],
		"research_req": "zone_10_access"
	}
}

# v86.0: Hazard Zone Definitions
var hazard_zones = {
	"emp_nexus": {
		"name": "EMP Nexus",
		"desc": "Electromagnetic death-field. Weapons jam constantly without shielding.",
		"unlock_boss": "z2_boss_monolith",
		"counter_module": "faraday_hull",
		"hazard_type": "emp_storm",
		"max_waves": 7,
		"enemy_pool": ["hz_emp_drone_1", "hz_emp_drone_2", "hz_emp_drone_3", "hz_emp_drone_4", "hz_emp_drone_5"],
		"elite_enemy": "hz_emp_elite",
		"boss_enemy": "hz_emp_overlord",
		"first_clear_reward": "emp_generator_blueprint",
		"zone_difficulty": 3
	}
}

# v80.1: Formula-Driven Enemy DB
# Regular: HP=floor(200*2.2^(N-1)), ATK=floor(12*2.2^(N-1)), DEF=floor(3*2.2^(N-1))
# Boss: HP×6, ATK×2.5, DEF×3, Shield×3
# Enemy variants within zone: ±20% stat variation for diversity
var enemy_db = {
	# ═══ ZONE 1: Lunar Orbit — Reg HP~200, ATK~15, DEF~3 ═══
	"z1_dust_mite": {
		"name": "Space Dust Mite",
		"stats": {"hp": 80, "atk": 8, "def": 0, "atk_interval": 3.0, "accuracy": 10},
		"loot": [["Fe", 2, 4], ["credits", 50, 100], ["Res1", 1, 2], ["MiteChitin", 1, 3]],
		"rare_loot": [],
		"module_drop_chance": 0.15,
		"module_drop_pool": ["z1_kinetic", "z1_energy", "z1_shield", "z1_armor"],
		"xp": 5, "eva": 5, "zone": 1, "resist_k": -0.20, "resist_e": 0.0, "resist_x": 0.10, "dmg_type": "kinetic"
	},
	"z1_lunar_drone": {
		"name": "Lunar Drone",
		"stats": {"hp": 120, "atk": 13, "def": 3, "atk_interval": 2.5, "accuracy": 18},
		"loot": [["Fe", 2, 5], ["Cu", 1, 3], ["Res1", 1, 2], ["MiteChitin", 1, 3]],
		"rare_loot": [["NavData", 0.10, 1, 1]],
		"module_drop_chance": 0.20,
		"module_drop_pool": ["z1_kinetic", "z1_energy", "z1_missile", "z1_shield", "z1_armor", "z1_battery"],
		"xp": 8, "eva": 8, "zone": 1, "resist_k": -0.30, "resist_e": 0.30, "resist_x": 0.0, "dmg_type": "kinetic"
	},
	"z1_survey_probe": {
		"name": "Survey Probe",
		"stats": {"hp": 150, "max_shield": 40, "atk": 13, "def": 3, "atk_interval": 1.0, "accuracy": 22},
		"loot": [["credits", 80, 150], ["Si", 2, 4], ["Res1", 1, 3], ["MiteChitin", 1, 2]],
		"rare_loot": [["NavData", 0.15, 1, 2], ["DamagedCircuitry", 0.35, 1, 2]],
		"module_drop_chance": 0.25,
		"module_drop_pool": ["z1_kinetic", "z1_energy", "z1_shield", "z1_armor", "z1_sensor"],
		"xp": 12, "eva": 15, "zone": 1, "resist_k": 0.30, "resist_e": -0.30, "resist_x": 0.0, "dmg_type": "energy"
	},
	"z1_scrap_collector": {
		"name": "Scrap Collector",
		"stats": {"hp": 200, "atk": 15, "def": 3, "atk_interval": 2.2, "accuracy": 20},
		"loot": [["Fe", 3, 6], ["Si", 1, 3], ["Res1", 1, 3], ["MiteChitin", 2, 4]],
		"rare_loot": [["Cu", 0.15, 2, 4], ["SalvagedAlloy", 0.35, 1, 2]],
		"module_drop_chance": 0.25,
		"module_drop_pool": ["z1_kinetic", "z1_energy", "z1_missile", "z1_shield", "z1_armor", "z1_engine"],
		"xp": 10, "eva": 6, "zone": 1, "resist_k": 0.10, "resist_e": -0.20, "resist_x": 0.30, "dmg_type": "kinetic"
	},

	"z1_boss_architect": {
		"name": "Rogue Architect",
		"stats": {"hp": 1200, "max_shield": 120, "atk": 54, "def": 18, "atk_interval": 2.5, "accuracy": 35},
		"loot": [["credits", 500, 1000], ["Cu", 10, 25], ["Fe", 15, 30], ["Res1", 5, 10], ["MiteChitin", 5, 12]],
		"rare_loot": [["z1_unique_weapon", 0.03, 1, 1], ["z1_unique_armor", 0.03, 1, 1], ["z1_unique_shield", 0.03, 1, 1], ["SalvagedAlloy", 0.90, 2, 4], ["DamagedCircuitry", 0.90, 2, 4]],
		"boss_core": "Z1_Core",
		"module_drop_chance": 0.25,
		"module_drop_pool": ["z1_kinetic", "z1_energy", "z1_missile", "z1_shield", "z1_armor", "z1_engine", "z1_battery", "z1_sensor"],
		"is_boss": true, "xp": 100, "eva": 10, "zone": 1, "resist_k": 0.25, "resist_e": 0.25, "resist_x": -0.30, "dmg_type": "kinetic"
	},

	# ═══ ZONE 2: Asteroid Belt — Reg HP~480, ATK~33, DEF~7 ═══
	"z2_pirate_skiff": {
		"name": "Pirate Skiff",
		"stats": {"hp": 380, "atk": 25, "def": 5, "atk_interval": 1.8, "accuracy": 25},
		"loot": [["credits", 150, 300], ["Fe", 3, 8], ["Res1", 2, 4], ["PirateSalvage", 1, 3]],
		"rare_loot": [["Cu", 0.15, 3, 6]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z2_kinetic", "z2_energy", "z2_missile", "z2_shield", "z2_armor"],
		"xp": 20, "eva": 12, "zone": 2, "resist_k": -0.20, "resist_e": 0.30, "resist_x": -0.20, "dmg_type": "kinetic"
	},
	"z2_silicate_golem": {
		"name": "Silicate Golem",
		"stats": {"hp": 480, "atk": 33, "def": 7, "atk_interval": 3.0, "accuracy": 22},
		"loot": [["Si", 5, 15], ["Fe", 3, 8], ["Res1", 2, 4], ["PirateSalvage", 1, 3]],
		"rare_loot": [["Ti", 0.10, 1, 3], ["DamagedCircuitry", 0.40, 1, 3]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z2_kinetic", "z2_energy", "z2_missile", "z2_shield", "z2_armor"],
		"xp": 25, "eva": 5, "zone": 2, "resist_k": 0.40, "resist_e": 0.0, "resist_x": -0.35, "dmg_type": "kinetic"
	},
	"z2_claim_jumper": {
		"name": "Claim Jumper",
		"stats": {"hp": 520, "atk": 38, "def": 8, "atk_interval": 2.2, "accuracy": 28},
		"loot": [["credits", 200, 400], ["Sn", 2, 5], ["Res1", 2, 5], ["PirateSalvage", 2, 4]],
		"rare_loot": [["Ti", 0.12, 2, 4]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z2_kinetic", "z2_energy", "z2_missile", "z2_shield", "z2_armor"],
		"xp": 28, "eva": 15, "zone": 2, "resist_k": 0.15, "resist_e": -0.15, "resist_x": 0.0, "dmg_type": "explosive"
	},
	"z2_ore_hauler": {
		"name": "Ore Hauler",
		"stats": {"hp": 950, "atk": 28, "def": 10, "atk_interval": 5.0, "accuracy": 20},
		"loot": [["Fe", 10, 25], ["Si", 5, 12], ["Res1", 2, 5], ["PirateSalvage", 2, 5], ["SalvageData", 1, 3]],
		"rare_loot": [["Steel", 0.10, 1, 3], ["SalvagedAlloy", 0.40, 1, 3]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z2_kinetic", "z2_energy", "z2_shield", "z2_armor", "z2_sensor", "z2_engine"],
		"xp": 22, "eva": 3, "zone": 2, "resist_k": 0.45, "resist_e": 0.15, "resist_x": -0.30, "dmg_type": "kinetic"
	},
	"z2_boss_monolith": {
		"name": "Silicate Monolith",
		"stats": {"hp": 5280, "max_shield": 264, "atk": 132, "def": 39, "atk_interval": 3.5, "accuracy": 45},
		"loot": [["credits", 2000, 5000], ["Ti", 5, 12], ["Fe", 20, 40], ["Res1", 10, 20], ["PirateSalvage", 5, 12]],
		"rare_loot": [["z2_unique_weapon", 0.03, 1, 1], ["z2_unique_armor", 0.03, 1, 1], ["z2_unique_shield", 0.03, 1, 1], ["faraday_hull", 0.03, 1, 1], ["SalvagedAlloy", 0.90, 3, 6], ["DamagedCircuitry", 0.90, 3, 6]],
		"boss_core": "Z2_Core",
		"module_drop_chance": 0.25,
		"module_drop_pool": ["z2_kinetic", "z2_energy", "z2_missile", "z2_shield", "z2_armor"],
		"is_boss": true, "xp": 300, "eva": 8, "zone": 2, "resist_k": 0.45, "resist_e": 0.15, "resist_x": -0.40, "dmg_type": "kinetic"
	},

	# ═══ ZONE 3: Mars Debris — Reg HP~1152, ATK~73, DEF~15 ═══
	"z3_scavenger_mech": {
		"name": "Scavenger Mech",
		"stats": {"hp": 900, "atk": 57, "def": 12, "atk_interval": 2.5, "accuracy": 35},
		"loot": [["Steel", 3, 8], ["Fe", 8, 20], ["Res2", 1, 2], ["MartianRelics", 1, 3]],
		"rare_loot": [["Circuit", 0.10, 1, 2], ["Ni", 0.10, 1, 3]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z3_kinetic", "z3_energy", "z3_missile", "z3_shield", "z3_armor"],
		"xp": 50, "eva": 10, "zone": 3, "resist_k": 0.0, "resist_e": -0.25, "resist_x": 0.25, "dmg_type": "explosive"
	},
	"z3_martian_sentry": {
		"name": "Martian Sentry",
		"stats": {"hp": 1152, "max_shield": 300, "atk": 73, "def": 15, "atk_interval": 2.0, "accuracy": 40},
		"loot": [["C", 3, 8], ["credits", 400, 800], ["Res2", 1, 2], ["MartianRelics", 1, 3]],
		"rare_loot": [["Chip", 0.08, 1, 2]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z3_kinetic", "z3_energy", "z3_missile", "z3_shield", "z3_armor"],
		"xp": 60, "eva": 12, "zone": 3, "resist_k": 0.0, "resist_e": -0.30, "resist_x": 0.30, "dmg_type": "explosive"
	},
	"z3_salvage_swarm": {
		"name": "Salvage Swarm",
		"stats": {"hp": 800, "atk": 38, "def": 10, "atk_interval": 0.6, "accuracy": 38},
		"loot": [["Fe", 5, 15], ["Cu", 3, 8], ["Res2", 1, 2], ["MartianRelics", 1, 2], ["SalvageData", 2, 4]],
		"rare_loot": [["Steel", 0.15, 2, 5], ["Sn", 0.12, 2, 4]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z3_kinetic", "z3_energy", "z3_shield", "z3_armor", "z3_sensor", "z3_engine"],
		"xp": 45, "eva": 20, "zone": 3, "resist_k": -0.15, "resist_e": -0.15, "resist_x": 0.15, "dmg_type": "kinetic"
	},
	"z3_derelict_frigate": {
		"name": "Derelict Frigate",
		"stats": {"hp": 2000, "max_shield": 400, "atk": 82, "def": 18, "atk_interval": 4.0, "accuracy": 42},
		"loot": [["Steel", 5, 12], ["Fe", 10, 25], ["Res2", 1, 3], ["MartianRelics", 2, 4]],
		"rare_loot": [["Ti", 0.10, 2, 5], ["Cr", 0.08, 1, 3]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z3_kinetic", "z3_energy", "z3_missile", "z3_shield", "z3_armor"],
		"xp": 70, "eva": 5, "zone": 3, "resist_k": 0.15, "resist_e": -0.30, "resist_x": 0.40, "dmg_type": "explosive"
	},
	"z3_boss_warmaster": {
		"name": "Martian Warmaster",
		"stats": {"hp": 17424, "max_shield": 580, "atk": 319, "def": 87, "atk_interval": 2.5, "accuracy": 65},
		"loot": [["credits", 5000, 10000], ["Steel", 20, 40], ["Ti", 10, 25], ["Res2", 5, 10], ["MartianRelics", 5, 12]],
		"rare_loot": [["z3_unique_weapon", 0.03, 1, 1], ["z3_unique_armor", 0.03, 1, 1], ["z3_unique_shield", 0.03, 1, 1]],
		"boss_core": "Z3_Core",
		"module_drop_chance": 0.25,
		"module_drop_pool": ["z3_kinetic", "z3_energy", "z3_missile", "z3_shield", "z3_armor"],
		"is_boss": true, "xp": 800, "eva": 15, "zone": 3, "resist_k": 0.15, "resist_e": -0.40, "resist_x": 0.45, "dmg_type": "explosive"
	},

	# ═══ ZONE 4: Cryofield — Reg HP~2765, ATK~160, DEF~32 ═══
	"z4_ice_wraith": {
		"name": "Ice Wraith",
		"stats": {"hp": 2200, "max_shield": 600, "atk": 125, "def": 25, "atk_interval": 1.5, "accuracy": 50},
		"loot": [["CoolantCell", 1, 3], ["credits", 800, 1500], ["Res2", 1, 3], ["CryoEssence", 1, 3]],
		"rare_loot": [["AdvCircuit", 0.08, 1, 2]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z4_kinetic", "z4_energy", "z4_missile", "z4_shield", "z4_armor"],
		"xp": 120, "eva": 25, "zone": 4, "resist_k": -0.25, "resist_e": 0.30, "resist_x": 0.0, "dmg_type": "energy"
	},
	"z4_cryo_sentinel": {
		"name": "Cryo Sentinel",
		"stats": {"hp": 2765, "max_shield": 800, "atk": 160, "def": 32, "atk_interval": 2.5, "accuracy": 55},
		"loot": [["Ti", 5, 12], ["credits", 1000, 2000], ["Res2", 1, 3], ["CryoEssence", 1, 3]],
		"rare_loot": [["Chip", 0.10, 1, 3]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z4_kinetic", "z4_energy", "z4_missile", "z4_shield", "z4_armor"],
		"xp": 140, "eva": 12, "zone": 4, "resist_k": -0.25, "resist_e": 0.40, "resist_x": 0.0, "dmg_type": "energy"
	},
	"z4_frost_hulk": {
		"name": "Frost Hulk",
		"stats": {"hp": 5000, "atk": 138, "def": 40, "atk_interval": 4.0, "accuracy": 48},
		"loot": [["Steel", 8, 18], ["Fe", 15, 35], ["Res2", 1, 3], ["CryoEssence", 1, 2]],
		"rare_loot": [["Ti", 0.15, 3, 8]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z4_kinetic", "z4_energy", "z4_shield", "z4_armor", "z4_sensor", "z4_engine"],
		"xp": 130, "eva": 5, "zone": 4, "resist_k": -0.30, "resist_e": 0.25, "resist_x": 0.15, "dmg_type": "kinetic"
	},
	"z4_glacial_drone": {
		"name": "Glacial Drone",
		"stats": {"hp": 2400, "max_shield": 500, "atk": 175, "def": 28, "atk_interval": 1.8, "accuracy": 58},
		"loot": [["credits", 1200, 2500], ["Cu", 5, 12], ["Res2", 2, 4], ["CryoEssence", 2, 4]],
		"rare_loot": [["AdvCircuit", 0.10, 1, 2]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z4_kinetic", "z4_energy", "z4_missile", "z4_shield", "z4_armor"],
		"xp": 135, "eva": 18, "zone": 4, "resist_k": -0.15, "resist_e": 0.30, "resist_x": 0.0, "dmg_type": "energy"
	},
	"z4_boss_overseer": {
		"name": "Cryo Overseer",
		"stats": {"hp": 51110, "max_shield": 1277, "atk": 766, "def": 191, "atk_interval": 2.5, "accuracy": 85},
		"loot": [["credits", 15000, 30000], ["Ti", 30, 60], ["AdvCircuit", 5, 12], ["Res2", 10, 20], ["CryoEssence", 5, 12]],
		"rare_loot": [["z4_unique_weapon", 0.03, 1, 1], ["z4_unique_armor", 0.03, 1, 1], ["z4_unique_shield", 0.03, 1, 1]],
		"boss_core": "Z4_Core",
		"module_drop_chance": 0.25,
		"module_drop_pool": ["z4_kinetic", "z4_energy", "z4_missile", "z4_shield", "z4_armor"],
		"is_boss": true, "xp": 2000, "eva": 15, "zone": 4, "resist_k": -0.40, "resist_e": 0.45, "resist_x": 0.0, "dmg_type": "energy"
	},

	# ═══ ZONE 5: Sector Alpha — Reg HP~6636, ATK~352, DEF~70 ═══
	"z5_xenon_scout": {
		"name": "Xenon Scout",
		"stats": {"hp": 5300, "max_shield": 1500, "atk": 275, "def": 55, "atk_interval": 1.5, "accuracy": 65},
		"loot": [["credits", 3000, 6000], ["VoidArtifact", 1, 2], ["Res2", 2, 5], ["XenoFragment", 1, 3]],
		"rare_loot": [["QuantumCore", 0.05, 1, 1]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z5_kinetic", "z5_energy", "z5_missile", "z5_shield", "z5_armor"],
		"xp": 300, "eva": 30, "zone": 5, "resist_k": 0.30, "resist_e": 0.0, "resist_x": -0.25, "dmg_type": "energy"
	},
	"z5_xenon_corvette": {
		"name": "Xenon Corvette",
		"stats": {"hp": 6636, "max_shield": 2000, "atk": 352, "def": 70, "atk_interval": 2.0, "accuracy": 70},
		"loot": [["credits", 4000, 8000], ["Ti", 10, 25], ["Res2", 2, 5], ["XenoFragment", 1, 3]],
		"rare_loot": [["Superalloy", 0.08, 1, 3]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z5_kinetic", "z5_energy", "z5_missile", "z5_shield", "z5_armor"],
		"xp": 350, "eva": 15, "zone": 5, "resist_k": 0.30, "resist_e": 0.0, "resist_x": -0.30, "dmg_type": "energy"
	},
	"z5_alien_frigate": {
		"name": "Alien Frigate",
		"stats": {"hp": 12000, "max_shield": 2500, "atk": 388, "def": 80, "atk_interval": 3.0, "accuracy": 72},
		"loot": [["VoidArtifact", 2, 5], ["credits", 5000, 10000], ["Res2", 3, 6], ["XenoFragment", 2, 4]],
		"rare_loot": [["QuantumCore", 0.08, 1, 1]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z5_kinetic", "z5_energy", "z5_missile", "z5_shield", "z5_armor"],
		"xp": 380, "eva": 10, "zone": 5, "resist_k": 0.35, "resist_e": 0.15, "resist_x": -0.30, "dmg_type": "kinetic"
	},
	"z5_alien_probe": {
		"name": "Alien Probe",
		"stats": {"hp": 5000, "max_shield": 3000, "atk": 313, "def": 60, "atk_interval": 1.2, "accuracy": 78},
		"loot": [["credits", 4000, 7000], ["Circuit", 5, 10], ["Res2", 2, 5], ["XenoFragment", 1, 3]],
		"rare_loot": [["AdvCircuit", 0.10, 2, 4]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z5_kinetic", "z5_energy", "z5_shield", "z5_armor", "z5_sensor", "z5_engine"],
		"xp": 320, "eva": 35, "zone": 5, "resist_k": 0.25, "resist_e": -0.15, "resist_x": -0.25, "dmg_type": "energy"
	},
	"z5_boss_harbinger": {
		"name": "Xenon Harbinger",
		"stats": {"hp": 140553, "max_shield": 2811, "atk": 1827, "def": 421, "atk_interval": 2.5, "accuracy": 110},
		"loot": [["credits", 50000, 100000], ["VoidArtifact", 10, 25], ["QuantumCore", 2, 5], ["Res2", 15, 30], ["XenoFragment", 5, 12]],
		"rare_loot": [["z5_unique_weapon", 0.03, 1, 1], ["z5_unique_armor", 0.03, 1, 1], ["z5_unique_shield", 0.03, 1, 1]],
		"boss_core": "Z5_Core",
		"module_drop_chance": 0.25,
		"module_drop_pool": ["z5_kinetic", "z5_energy", "z5_missile", "z5_shield", "z5_armor"],
		"is_boss": true, "xp": 5000, "eva": 20, "zone": 5, "resist_k": 0.35, "resist_e": 0.15, "resist_x": -0.40, "dmg_type": "energy"
	},

	# ═══ ZONE 6: Sector Beta — Reg HP~15926, ATK~773, DEF~155 ═══
	"z6_defense_turret": {
		"name": "Defense Turret",
		"stats": {"hp": 12700, "atk": 613, "def": 125, "atk_interval": 2.5, "accuracy": 90},
		"loot": [["ColonySalvage", 5, 12], ["Circuit", 5, 12], ["Res3", 1, 2]],
		"rare_loot": [["AdvCircuit", 0.10, 2, 5]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z6_kinetic", "z6_energy", "z6_missile", "z6_shield", "z6_armor"],
		"xp": 700, "eva": 5, "zone": 6, "resist_k": 0.0, "resist_e": -0.30, "resist_x": 0.30, "dmg_type": "kinetic"
	},
	"z6_mining_golem": {
		"name": "Mining Golem",
		"stats": {"hp": 15926, "atk": 773, "def": 155, "atk_interval": 3.5, "accuracy": 85},
		"loot": [["Fe", 50, 100], ["Ti", 10, 25], ["Res3", 1, 2]],
		"rare_loot": [["Superalloy", 0.10, 2, 5]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z6_kinetic", "z6_energy", "z6_missile", "z6_shield", "z6_armor"],
		"xp": 750, "eva": 5, "zone": 6, "resist_k": 0.15, "resist_e": -0.40, "resist_x": 0.40, "dmg_type": "explosive"
	},
	"z6_rad_beast": {
		"name": "Radiation Beast",
		"stats": {"hp": 30000, "max_shield": 4000, "atk": 850, "def": 140, "atk_interval": 2.0, "accuracy": 92},
		"loot": [["RadIsotope", 1, 3], ["U", 5, 12], ["Res3", 1, 3]],
		"rare_loot": [["Ir", 0.08, 1, 2]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z6_kinetic", "z6_energy", "z6_missile", "z6_shield", "z6_armor"],
		"xp": 780, "eva": 12, "zone": 6, "resist_k": -0.15, "resist_e": -0.25, "resist_x": 0.25, "dmg_type": "kinetic"
	},
	"z6_ore_guardian": {
		"name": "Ore Guardian",
		"stats": {"hp": 14000, "max_shield": 5000, "atk": 688, "def": 170, "atk_interval": 3.0, "accuracy": 88},
		"loot": [["Fe", 30, 70], ["Steel", 10, 25], ["Res3", 1, 3]],
		"rare_loot": [["VoidArtifact", 0.10, 1, 3]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z6_kinetic", "z6_energy", "z6_shield", "z6_armor", "z6_sensor", "z6_engine"],
		"xp": 720, "eva": 8, "zone": 6, "resist_k": 0.25, "resist_e": -0.30, "resist_x": 0.45, "dmg_type": "explosive"
	},
	"z6_boss_colossus": {
		"name": "Gamma Colossus",
		"stats": {"hp": 371061, "max_shield": 6184, "atk": 4329, "def": 927, "atk_interval": 2.5, "accuracy": 140},
		"loot": [["credits", 200000, 500000], ["Ir", 5, 12], ["Superalloy", 10, 25], ["Res3", 10, 20], ["ColonyDataCore", 2, 5]],
		"rare_loot": [["z6_unique_weapon", 0.03, 1, 1], ["z6_unique_armor", 0.03, 1, 1], ["z6_unique_shield", 0.03, 1, 1]],
		"boss_core": "Z6_Core",
		"module_drop_chance": 0.25,
		"module_drop_pool": ["z6_kinetic", "z6_energy", "z6_missile", "z6_shield", "z6_armor"],
		"is_boss": true, "xp": 15000, "eva": 15, "zone": 6, "resist_k": 0.15, "resist_e": -0.40, "resist_x": 0.45, "dmg_type": "explosive"
	},

	# ═══ ZONE 7: Sector Gamma — Reg HP~38222, ATK~1700, DEF~341 ═══
	"z7_shard_swarm": {
		"name": "Shard Swarm",
		"stats": {"hp": 30000, "atk": 1350, "def": 270, "atk_interval": 0.8, "accuracy": 100},
		"loot": [["ExoticMatter", 1, 3], ["VoidCrystal", 1, 2], ["Res3", 2, 4], ["ExoticIsotope", 1, 2]],
		"rare_loot": [["Os", 0.08, 1, 2]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z7_kinetic", "z7_energy", "z7_missile", "z7_shield", "z7_armor"],
		"xp": 1500, "eva": 30, "zone": 7, "resist_k": -0.25, "resist_e": 0.30, "resist_x": 0.0, "dmg_type": "energy"
	},
	"z7_energy_wraith": {
		"name": "Energy Wraith",
		"stats": {"hp": 38222, "max_shield": 15000, "atk": 1700, "def": 341, "atk_interval": 2.0, "accuracy": 105},
		"loot": [["ExoticMatter", 2, 5], ["VoidCrystal", 1, 3], ["Res3", 2, 5]],
		"rare_loot": [["Ir", 0.10, 1, 3]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z7_kinetic", "z7_energy", "z7_missile", "z7_shield", "z7_armor"],
		"xp": 1800, "eva": 18, "zone": 7, "resist_k": -0.30, "resist_e": 0.45, "resist_x": 0.0, "dmg_type": "energy"
	},
	"z7_void_hunter": {
		"name": "Void Hunter",
		"stats": {"hp": 32000, "max_shield": 12000, "atk": 1875, "def": 300, "atk_interval": 1.5, "accuracy": 110},
		"loot": [["VoidCrystal", 2, 4], ["credits", 50000, 100000], ["Res3", 2, 5]],
		"rare_loot": [["ExoticMatter", 0.12, 2, 4]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z7_kinetic", "z7_energy", "z7_missile", "z7_shield", "z7_armor"],
		"xp": 1700, "eva": 25, "zone": 7, "resist_k": -0.30, "resist_e": 0.40, "resist_x": 0.15, "dmg_type": "energy"
	},
	"z7_gamma_beast": {
		"name": "Gamma Beast",
		"stats": {"hp": 75000, "atk": 1500, "def": 380, "atk_interval": 3.5, "accuracy": 95},
		"loot": [["RadIsotope", 3, 8], ["ExoticMatter", 1, 3], ["Res3", 2, 5]],
		"rare_loot": [["Os", 0.10, 1, 2]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z7_kinetic", "z7_energy", "z7_shield", "z7_armor", "z7_sensor", "z7_engine"],
		"xp": 1600, "eva": 8, "zone": 7, "resist_k": -0.15, "resist_e": 0.30, "resist_x": 0.0, "dmg_type": "kinetic"
	},
	"z7_boss_sovereign": {
		"name": "Sovereign Prism",
		"stats": {"hp": 952391, "max_shield": 13605, "atk": 10204, "def": 2040, "atk_interval": 2.5, "accuracy": 170},
		"loot": [["credits", 1000000, 2000000], ["ExoticMatter", 15, 30], ["Os", 3, 8], ["Res3", 15, 30]],
		"rare_loot": [["z7_unique_weapon", 0.03, 1, 1], ["z7_unique_armor", 0.03, 1, 1], ["z7_unique_shield", 0.03, 1, 1]],
		"boss_core": "Z7_Core",
		"module_drop_chance": 0.25,
		"module_drop_pool": ["z7_kinetic", "z7_energy", "z7_missile", "z7_shield", "z7_armor"],
		"is_boss": true, "xp": 35000, "eva": 20, "zone": 7, "resist_k": -0.40, "resist_e": 0.45, "resist_x": 0.0, "dmg_type": "energy"
	},

	# ═══ ZONE 8: Sector Delta — Reg HP~91733, ATK~3742, DEF~749 ═══
	"z8_prism_drone": {
		"name": "Prism Drone",
		"stats": {"hp": 73000, "max_shield": 25000, "atk": 3000, "def": 600, "atk_interval": 1.5, "accuracy": 120},
		"loot": [["VoidCrystal", 3, 8], ["credits", 100000, 200000], ["Res3", 3, 6], ["ExoticIsotope", 1, 3]],
		"rare_loot": [["Diamond", 0.05, 1, 1]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z8_kinetic", "z8_energy", "z8_missile", "z8_shield", "z8_armor"],
		"xp": 4000, "eva": 22, "zone": 8, "resist_k": 0.40, "resist_e": 0.0, "resist_x": -0.30, "dmg_type": "energy"
	},
	"z8_crystal_golem": {
		"name": "Crystal Golem",
		"stats": {"hp": 91733, "atk": 3742, "def": 749, "atk_interval": 3.5, "accuracy": 115},
		"loot": [["VoidCrystal", 5, 12], ["Os", 1, 3], ["Res3", 3, 6], ["AntimatterParticle", 1, 2]],
		"rare_loot": [["Diamond", 0.08, 1, 1]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z8_kinetic", "z8_energy", "z8_missile", "z8_shield", "z8_armor"],
		"xp": 4500, "eva": 5, "zone": 8, "resist_k": 0.45, "resist_e": 0.15, "resist_x": -0.40, "dmg_type": "kinetic"
	},
	"z8_void_stalker": {
		"name": "Void Stalker",
		"stats": {"hp": 80000, "max_shield": 35000, "atk": 4125, "def": 680, "atk_interval": 2.0, "accuracy": 125},
		"loot": [["ExoticMatter", 3, 8], ["VoidCrystal", 2, 5], ["Res3", 3, 8]],
		"rare_loot": [["Os", 0.10, 1, 3]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z8_kinetic", "z8_energy", "z8_missile", "z8_shield", "z8_armor"],
		"xp": 4200, "eva": 28, "zone": 8, "resist_k": 0.30, "resist_e": -0.15, "resist_x": -0.25, "dmg_type": "energy"
	},
	"z8_nebula_phantom": {
		"name": "Nebula Phantom",
		"stats": {"hp": 182000, "max_shield": 40000, "atk": 3375, "def": 800, "atk_interval": 2.5, "accuracy": 118},
		"loot": [["credits", 150000, 300000], ["VoidCrystal", 3, 7], ["Res3", 3, 8]],
		"rare_loot": [["ExoticMatter", 0.12, 2, 5]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z8_kinetic", "z8_energy", "z8_shield", "z8_armor", "z8_sensor", "z8_engine"],
		"xp": 4300, "eva": 15, "zone": 8, "resist_k": 0.40, "resist_e": 0.15, "resist_x": -0.30, "dmg_type": "kinetic"
	},
	"z8_boss_warden": {
		"name": "Prismatic Warden",
		"stats": {"hp": 2394583, "max_shield": 29932, "atk": 23945, "def": 4489, "atk_interval": 2.5, "accuracy": 200},
		"loot": [["credits", 3000000, 6000000], ["VoidCrystal", 20, 50], ["Diamond", 2, 5], ["Res3", 20, 40]],
		"rare_loot": [["z8_unique_weapon", 0.03, 1, 1], ["z8_unique_armor", 0.03, 1, 1], ["z8_unique_shield", 0.03, 1, 1]],
		"boss_core": "Z8_Core",
		"module_drop_chance": 0.25,
		"module_drop_pool": ["z8_kinetic", "z8_energy", "z8_missile", "z8_shield", "z8_armor"],
		"is_boss": true, "xp": 80000, "eva": 18, "zone": 8, "resist_k": 0.45, "resist_e": 0.15, "resist_x": -0.40, "dmg_type": "kinetic"
	},

	# ═══ ZONE 9: Sector Zeta — Reg HP~220160, ATK~8230, DEF~1648 ═══
	"z9_plague_drone": {
		"name": "Plague Drone",
		"stats": {"hp": 175000, "max_shield": 50000, "atk": 6500, "def": 1300, "atk_interval": 1.2, "accuracy": 140},
		"loot": [["BiohazardSample", 2, 5], ["credits", 300000, 600000], ["Res3", 5, 10], ["AntimatterParticle", 1, 3]],
		"rare_loot": [["PathogenCore", 0.05, 1, 1]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z9_kinetic", "z9_energy", "z9_missile", "z9_shield", "z9_armor"],
		"xp": 10000, "eva": 20, "zone": 9, "resist_k": 0.0, "resist_e": -0.25, "resist_x": 0.30, "dmg_type": "explosive"
	},
	"z9_bio_horror": {
		"name": "Bio-Horror",
		"stats": {"hp": 220160, "max_shield": 70000, "atk": 8230, "def": 1648, "atk_interval": 2.5, "accuracy": 145},
		"loot": [["BiohazardSample", 3, 8], ["Neutronium", 1, 2], ["Res3", 5, 10]],
		"rare_loot": [["PathogenCore", 0.08, 1, 1]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z9_kinetic", "z9_energy", "z9_missile", "z9_shield", "z9_armor"],
		"xp": 12000, "eva": 12, "zone": 9, "resist_k": 0.0, "resist_e": -0.30, "resist_x": 0.40, "dmg_type": "explosive"
	},
	"z9_rogue_ai": {
		"name": "Rogue AI Core",
		"stats": {"hp": 190000, "max_shield": 90000, "atk": 9000, "def": 1400, "atk_interval": 1.5, "accuracy": 155},
		"loot": [["Chip", 10, 25], ["AdvCircuit", 5, 12], ["Res3", 5, 10]],
		"rare_loot": [["ChronoCore", 0.05, 1, 1]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z9_kinetic", "z9_energy", "z9_missile", "z9_shield", "z9_armor"],
		"xp": 11000, "eva": 25, "zone": 9, "resist_k": -0.15, "resist_e": -0.25, "resist_x": 0.25, "dmg_type": "energy"
	},
	"z9_quarantine_mech": {
		"name": "Quarantine Mech",
		"stats": {"hp": 437500, "atk": 7500, "def": 1800, "atk_interval": 3.5, "accuracy": 138},
		"loot": [["Neutronium", 1, 3], ["credits", 500000, 1000000], ["Res3", 5, 10]],
		"rare_loot": [["PathogenCore", 0.10, 1, 2]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z9_kinetic", "z9_energy", "z9_shield", "z9_armor", "z9_sensor", "z9_engine"],
		"xp": 11500, "eva": 5, "zone": 9, "resist_k": 0.15, "resist_e": -0.30, "resist_x": 0.45, "dmg_type": "explosive"
	},
	"z9_boss_patient_zero": {
		"name": "Patient Zero",
		"stats": {"hp": 5926594, "max_shield": 65851, "atk": 55973, "def": 9877, "atk_interval": 1.5, "accuracy": 230},
		"loot": [["credits", 10000000, 20000000], ["Neutronium", 10, 25], ["PathogenCore", 3, 8], ["Res3", 30, 50], ["QuarantineClearance", 1, 1]],
		"rare_loot": [["z9_unique_weapon", 0.03, 1, 1], ["z9_unique_armor", 0.03, 1, 1], ["z9_unique_shield", 0.03, 1, 1]],
		"boss_core": "Z9_Core",
		"module_drop_chance": 0.25,
		"module_drop_pool": ["z9_kinetic", "z9_energy", "z9_missile", "z9_shield", "z9_armor"],
		"is_boss": true, "xp": 200000, "eva": 20, "zone": 9, "resist_k": 0.15, "resist_e": -0.40, "resist_x": 0.45, "dmg_type": "explosive"
	},

	# ═══ ZONE 10: Sector Epsilon — Reg HP~528384, ATK~18105, DEF~3627 ═══
	"z10_void_stalker": {
		"name": "Void Reaver",
		"stats": {"hp": 420000, "max_shield": 150000, "atk": 14375, "def": 2900, "atk_interval": 2.0, "accuracy": 160},
		"loot": [["PrimordialShard", 1, 3], ["VoidEssence", 1, 2]],
		"rare_loot": [["ChronoCore", 0.05, 1, 1]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z10_kinetic", "z10_energy", "z10_missile", "z10_shield", "z10_armor"],
		"xp": 25000, "eva": 25, "zone": 10, "resist_k": -0.30, "resist_e": 0.40, "resist_x": 0.0, "dmg_type": "kinetic"
	},
	"z10_temporal_phantom": {
		"name": "Temporal Phantom",
		"stats": {"hp": 528384, "max_shield": 200000, "atk": 18105, "def": 3627, "atk_interval": 1.5, "accuracy": 170},
		"loot": [["ChronoCore", 1, 2], ["VoidEssence", 2, 4]],
		"rare_loot": [["PrimordialShard", 0.08, 1, 2]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z10_kinetic", "z10_energy", "z10_missile", "z10_shield", "z10_armor"],
		"xp": 30000, "eva": 35, "zone": 10, "resist_k": -0.30, "resist_e": 0.45, "resist_x": 0.0, "dmg_type": "energy"
	},
	"z10_omega_sentinel": {
		"name": "Omega Sentinel",
		"stats": {"hp": 600000, "max_shield": 180000, "atk": 16250, "def": 4000, "atk_interval": 2.5, "accuracy": 165},
		"loot": [["OmegaPlating", 1, 3], ["PrimordialShard", 1, 2]],
		"rare_loot": [["VoidEssence", 0.10, 1, 3]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z10_kinetic", "z10_energy", "z10_missile", "z10_shield", "z10_armor"],
		"xp": 28000, "eva": 10, "zone": 10, "resist_k": -0.25, "resist_e": 0.30, "resist_x": 0.10, "dmg_type": "explosive"
	},
	"z10_primordial_titan": {
		"name": "Primordial Titan",
		"stats": {"hp": 1050000, "atk": 20000, "def": 3400, "atk_interval": 4.0, "accuracy": 158},
		"loot": [["PrimordialShard", 2, 5], ["credits", 5000000, 10000000]],
		"rare_loot": [["OmegaPlating", 0.08, 1, 2]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z10_kinetic", "z10_energy", "z10_shield", "z10_armor", "z10_sensor", "z10_engine"],
		"xp": 32000, "eva": 5, "zone": 10, "resist_k": -0.15, "resist_e": 0.30, "resist_x": 0.15, "dmg_type": "kinetic"
	},
	"z10_boss_leviathan": {
		"name": "Void Leviathan",
		"stats": {"hp": 14487230, "max_shield": 144872, "atk": 130385, "def": 21730, "atk_interval": 3.0, "accuracy": 250},
		"loot": [["credits", 50000000, 100000000], ["PrimordialShard", 20, 50], ["ChronoCore", 5, 12]],
		"rare_loot": [["z10_unique_weapon", 0.03, 1, 1], ["z10_unique_armor", 0.03, 1, 1], ["z10_unique_shield", 0.03, 1, 1]],
		"boss_core": "Z10_Core",
		"module_drop_chance": 0.25,
		"module_drop_pool": ["z10_kinetic", "z10_energy", "z10_missile", "z10_shield", "z10_armor"],
		"is_boss": true, "xp": 500000, "eva": 25, "zone": 10, "resist_k": -0.40, "resist_e": 0.45, "resist_x": 0.0, "dmg_type": "energy"
	},

	# ═══ HAZARD ZONE: EMP Nexus — Boosted Z2 enemies ═══
	"hz_emp_drone_1": {
		"name": "EMP Assault Drone",
		"stats": {"hp": 600, "max_shield": 150, "atk": 40, "def": 15, "atk_interval": 2.0, "accuracy": 35},
		"loot": [["credits", 500, 1000], ["Fe", 5, 10], ["Cu", 3, 6]],
		"rare_loot": [], "xp": 40, "eva": 15, "zone": 2,
		"resist_k": 0.20, "resist_e": -0.20, "resist_x": 0.0, "dmg_type": "energy"
	},
	"hz_emp_drone_2": {
		"name": "Charged Golem",
		"stats": {"hp": 800, "atk": 50, "def": 20, "atk_interval": 3.0, "accuracy": 30},
		"loot": [["credits", 600, 1200], ["Si", 5, 10], ["Cu", 2, 5]],
		"rare_loot": [], "xp": 45, "eva": 5, "zone": 2,
		"resist_k": 0.30, "resist_e": -0.15, "resist_x": -0.10, "dmg_type": "energy"
	},
	"hz_emp_drone_3": {
		"name": "Pulse Skimmer",
		"stats": {"hp": 500, "max_shield": 300, "atk": 35, "def": 10, "atk_interval": 1.5, "accuracy": 40},
		"loot": [["credits", 400, 800], ["Fe", 3, 8], ["Res1", 2, 4]],
		"rare_loot": [], "xp": 35, "eva": 20, "zone": 2,
		"resist_k": 0.10, "resist_e": -0.25, "resist_x": 0.10, "dmg_type": "energy"
	},
	"hz_emp_drone_4": {
		"name": "Static Hauler",
		"stats": {"hp": 1000, "atk": 55, "def": 25, "atk_interval": 3.5, "accuracy": 28},
		"loot": [["credits", 700, 1400], ["Fe", 8, 15], ["Ti", 1, 3]],
		"rare_loot": [], "xp": 50, "eva": 3, "zone": 2,
		"resist_k": 0.25, "resist_e": 0.0, "resist_x": -0.20, "dmg_type": "energy"
	},
	"hz_emp_drone_5": {
		"name": "Ion Disruptor",
		"stats": {"hp": 700, "max_shield": 200, "atk": 45, "def": 12, "atk_interval": 2.0, "accuracy": 38},
		"loot": [["credits", 500, 1000], ["Cu", 5, 10], ["Si", 3, 6]],
		"rare_loot": [], "xp": 42, "eva": 18, "zone": 2,
		"resist_k": 0.15, "resist_e": -0.20, "resist_x": 0.0, "dmg_type": "energy"
	},
	"hz_emp_elite": {
		"name": "EMP Commander",
		"stats": {"hp": 2500, "max_shield": 600, "atk": 100, "def": 40, "atk_interval": 2.5, "accuracy": 50},
		"loot": [["credits", 3000, 6000], ["Cu", 10, 20], ["Ti", 3, 8], ["Res1", 5, 10]],
		"rare_loot": [["Circuit", 0.30, 3, 6]],
		"xp": 150, "eva": 12, "zone": 2,
		"resist_k": 0.30, "resist_e": -0.25, "resist_x": -0.15, "dmg_type": "energy"
	},
	"hz_emp_overlord": {
		"name": "EMP Overlord",
		"stats": {"hp": 8000, "max_shield": 1500, "atk": 200, "def": 60, "atk_interval": 2.0, "accuracy": 65},
		"loot": [["credits", 10000, 20000], ["Cu", 20, 40], ["Ti", 8, 15], ["Res1", 10, 20]],
		"rare_loot": [["AdvCircuit", 0.25, 2, 4], ["NavData", 0.40, 1, 3]],
		"is_boss": true, "xp": 500, "eva": 10, "zone": 2,
		"resist_k": 0.35, "resist_e": -0.30, "resist_x": -0.20, "dmg_type": "energy"
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
	
	# v86.0: Append unlocked hazard zones
	for hz_id in hazard_zones:
		if is_hazard_unlocked(hz_id):
			var hz = hazard_zones[hz_id]
			var display_data = {
				"name": "⚠ %s" % hz["name"],
				"desc": hz["desc"],
				"difficulty": hz.get("zone_difficulty", 3),
				"is_hazard": true
			}
			available.append({"id": hz_id, "data": display_data, "is_hazard": true})
	
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
	combat_session_time = 0.0
	time_since_last_kill = 0.0
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
		combat_session_time = 0.0
		time_since_last_kill = 0.0
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
		"boss_core": e_data.get("boss_core", ""),
		"xp": e_data["xp"],
		"jammer": e_data["stats"].get("jammer", false),
		"eva": e_data["stats"].get("eva", 0),
		# v62.0 Fix: Copy atk_interval so enemy attack speed is used
		"atk_interval": e_data["stats"].get("atk_interval", 3.0),
		"is_elite": false, # Default
		"resist_k": e_data.get("resist_k", 0.0),
		"resist_e": e_data.get("resist_e", 0.0),
		"resist_x": e_data.get("resist_x", 0.0),
		"dmg_type": e_data.get("dmg_type", "kinetic") # v87.0: Typed enemy damage
	}
	
	# v103b: Static zone-gap steepening (zone 3+). A complete sub-zone gear/set
	# out-DPSes later content otherwise; both regular enemies AND bosses scale.
	# Zones 1-2 untouched (early game stays gentle). First-pass curve — tune the
	# two _zhp / _zdef knobs from playtest.
	var _ezone := int(e_data.get("zone", current_zone.get("difficulty", 1)))
	if _ezone >= 3:
		# v103c: gate via OFFENSE, not HP. HP-sponging just made fights long
		# but still winnable (sustain race). Eased HP, kept DEF, added ATK so
		# sub-zone defensive stats can't survive the kill time; zone-N gear can.
		var _zhp: float = 1.7 + 0.25 * float(_ezone - 3)   # z3 ≈1.7× … z10 ≈3.45×
		var _zdef: float = 1.7                             # 0.80 mitig clamp keeps it killable
		var _zatk: float = 1.7 + 0.20 * float(_ezone - 3)  # z3 ≈1.7× … z10 ≈3.1× — the real gate
		current_enemy["max_hp"] = int(current_enemy["max_hp"] * _zhp)
		current_enemy["def"] = int(current_enemy["def"] * _zdef)
		current_enemy["atk"] = int(current_enemy["atk"] * _zatk)

	# v103: Measured progression compensation. Enemies scale ONLY against the
	# player's *external grind* multiplier (combat level + warp), NOT gear —
	# so leveling/warping can't trivialize a zone with old modules, but better
	# gear is still the real lever to out-power content. Partial catch-up via
	# the ENEMY_COMP_* fractions (<0.5), so zone pacing stays readable.
	var _is_boss := bool(current_enemy.get("is_boss", false))
	var _ext_mult: float = (1.0 + get_level() * 0.005)
	if GameState.warp_manager:
		_ext_mult *= max(1.0, GameState.warp_manager.get_combat_multiplier())
	if _ext_mult > 1.0:
		var _g := _ext_mult - 1.0
		var _hpf := ENEMY_COMP_BOSS_HP if _is_boss else ENEMY_COMP_REGULAR_HP
		var _atkf := ENEMY_COMP_BOSS_ATK if _is_boss else ENEMY_COMP_REGULAR_ATK
		var _shf := ENEMY_COMP_BOSS_SHIELD if _is_boss else ENEMY_COMP_REGULAR_SHIELD
		current_enemy["max_hp"] = int(current_enemy["max_hp"] * (1.0 + _g * _hpf))
		current_enemy["atk"] = int(current_enemy["atk"] * (1.0 + _g * _atkf))
		current_enemy["def"] = int(current_enemy["def"] * (1.0 + _g * ENEMY_COMP_DEF))
		current_enemy["max_shield"] = int(current_enemy["max_shield"] * (1.0 + _g * _shf))

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
	active_trinity_sets = _get_active_trinity_sets()
	
	# Trinity Bonus: Enemy DEF Reduction (Harbinger's Wrath)
	if "harbingers_wrath" in active_trinity_sets:
		var red = TRINITY_SET_BONUSES["harbingers_wrath"]["bonus"]["enemy_def_reduce_pct"]
		current_enemy["def"] = int(current_enemy["def"] * (1.0 - red / 100.0))
	
	# Legacy check for backward compatibility (if any)
	if _loadout_has_module(sm, "chrono_stabilizer"):
		enemy_speed_mult *= 0.8
	if "architects_regalia" in active_trinity_sets:
		# Add any specific logic if needed, but mostly handled in stat tallies
		pass

	enemy_hp = current_enemy["max_hp"]
	enemy_max_hp = enemy_hp
	enemy_shield = float(current_enemy["max_shield"])
	enemy_max_shield = enemy_shield
	
	# v80.1: Recalculate player stats including set bonuses before safety caps
	_apply_trinity_stat_bonuses(sm)
	
	# v80.1: Apply safety caps after all bonuses are computed
	apply_safety_caps()
	
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
	player_weapon_states.append_array(equipped_weapons)
	log_msg("Readying Weapon Battery: %d systems online." % player_weapon_states.size())

func retreat():
	in_combat = false
	current_enemy = null
	log_msg("Emergency Warp engaged!")

func stop_action():
	retreat()

# v80.1: Centralized safety cap enforcement — called ONCE after all bonuses
func apply_safety_caps():
	var sm = GameState.shipyard_manager
	if not sm: return
	
	# ATK Speed: clamp multiplier (Max 3.0x -> +200%)
	sm.attack_speed_bonus = min(sm.attack_speed_bonus, MAX_ATK_SPEED_MULT - 1.0)
	
	# Evasion: max 75
	sm.evasion = min(sm.evasion, MAX_EVASION)
	
	# Crit Chance: max 50%
	sm.crit_chance = min(sm.crit_chance, MAX_CRIT_CHANCE)
	
	# Crit Damage: max 3.0 (if we add it later)
	
	# Shield Regen: cap to MAX_SHIELD_REGEN_PERCENT% of max shield per second
	if sm.max_shield > 0:
		var max_s_regen = int(sm.max_shield * MAX_SHIELD_REGEN_PERCENT / 100.0)
		sm.shield_regen = min(sm.shield_regen, max_s_regen)
	
	# HP Regen: cap to MAX_HP_REGEN_PERCENT% per second
	if sm.max_hp > 0:
		var max_h_regen = int(sm.max_hp * MAX_HP_REGEN_PERCENT / 100.0)
		sm.hp_regen = min(sm.hp_regen, max_h_regen)
	
	# Enemy Slow / Jamming
	sm.jamming_strength = min(sm.jamming_strength, MAX_ENEMY_SLOW)

func _get_set_bonus_value(bonus_key: String) -> float:
	var total = 0.0
	for set_id in active_trinity_sets:
		var b = TRINITY_SET_BONUSES[set_id]["bonus"]
		if bonus_key in b:
			total += b[bonus_key]
	return total

func _apply_trinity_stat_bonuses(sm):
	# Apply standard bonuses that fit into shipyard_manager stat fields
	sm.attack_speed_bonus += _get_set_bonus_value("atk_speed_pct") / 100.0
	sm.defense += _get_set_bonus_value("def_flat")
	if _get_set_bonus_value("def_pct") > 0:
		sm.defense = int(sm.defense * (1.0 + _get_set_bonus_value("def_pct") / 100.0))
	
	sm.crit_chance += _get_set_bonus_value("crit_chance") / 100.0
	sm.evasion += _get_set_bonus_value("evasion_flat")
	
	# Accuracy
	sm.accuracy = (sm.affix_bonuses.get("accuracy", 0.0) if "affix_bonuses" in sm else 100.0) + _get_set_bonus_value("accuracy_flat")
	
	# HP Regen
	sm.hp_regen = sm.hp_regen + _get_set_bonus_value("hp_regen_flat")
	
	# Shield HP %
	if _get_set_bonus_value("shield_hp_pct") > 0:
		sm.max_shield = int(sm.max_shield * (1.0 + _get_set_bonus_value("shield_hp_pct") / 100.0))
	
	# Shield Regen %	
	if _get_set_bonus_value("shield_regen_pct") > 0:
		sm.shield_regen = int(sm.shield_regen * (1.0 + _get_set_bonus_value("shield_regen_pct") / 100.0))
	
	# Enemy slow (jamming + chrono + cryo set)
	enemy_speed_mult = max(enemy_speed_mult, 1.0 - MAX_ENEMY_SLOW)

func process_tick(delta: float):
	var sm = GameState.shipyard_manager
	if sm:
		player_max_shield = sm.max_shield
		
	if not in_combat or not current_enemy or not current_zone:
		_process_regeneration(delta)
		return

	# Accumulate combat HUD timers while a fight is active.
	combat_session_time += delta
	time_since_last_kill += delta

	var rm = GameState.research_manager
	# v65.4: Removed sm.attack_speed_bonus here — it's already applied via cooling_mult per-weapon
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
		
	# v85.2: Berserking Logic (+25% Attack Speed)
	if player_berserk_timer > 0:
		player_berserk_timer -= delta
		p_speed_mult *= 1.25
		
	if enemy_vulnerable_timer > 0:
		enemy_vulnerable_timer -= delta
			
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
			# v80.1: Clamp effective interval to MIN_ATTACK_INTERVAL
			var effective_interval = max(MIN_ATTACK_INTERVAL, w["interval"] / (p_speed_mult * cooling_mult))
			if w["timer"] * (p_speed_mult * cooling_mult) / max(0.01, w["interval"]) >= 1.0:
				_execute_player_attack(w_idx)
			if w_idx >= player_weapon_states.size():
				break # win_fight() may have rebuilt weapon states
			w["timer"] -= w["interval"]
		
	# v65.0 Fix: Use enemy's actual attack interval (was hardcoded 3.0)
	# Audit v70.0: Electronic Warfare Implementation
	# Enemy attack timer increments slower based on jamming_strength
	# v80.1: Clamp jamming to safety cap
	var jamming_mult = max(1.0 - MAX_ENEMY_SLOW, 1.0 - sm.jamming_strength)
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
		
	# v80.1: Unified HP Regen (Trinity sets + Potential Modules)
	if sm.hp_regen > 0 and sm.current_hp < sm.max_hp:
		# Safety cap already applied in apply_safety_caps()
		sm.current_hp = min(sm.max_hp, sm.current_hp + (sm.hp_regen * delta))
	
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
	
	# v86.0: EMP Storm hazard — 40% weapon jam if in EMP Nexus without counter
	if hazard_state["active"] and _get_active_hazard_type() == "emp_storm":
		var has_counter = _loadout_has_module(sm, "faraday_hull")
		var jam_chance = 0.10 if has_counter else 0.40 # 10% even with counter for flavor
		if randf() < jam_chance:
			combat_events.append({"type": "miss", "text": "EMP JAM", "color": Color.YELLOW, "side": "enemy"})
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

	# v85.1: Heal on Hit Affixes
	var hull_heal = sm.affix_bonuses.get("hull_heal_on_hit", 0.0)
	if hull_heal > 0:
		sm.current_hp = min(sm.max_hp, sm.current_hp + hull_heal)
		
	var shield_heal = sm.affix_bonuses.get("shield_heal_on_hit", 0.0)
	if shield_heal > 0:
		player_shield = min(player_max_shield, player_shield + shield_heal)

	# v85.2: Lucky Hit Logic
	# Base 10% Lucky Hit chance + prefix bonuses
	var base_lucky_hit = 0.10 + sm.affix_bonuses.get("lucky_hit_chance", 0.0)
	var is_lucky_hit = randf() < base_lucky_hit
	
	if is_lucky_hit:
		# Trigger Vulnerable
		var vuln_chance = sm.affix_bonuses.get("vuln_on_hit", 0.0)
		if vuln_chance > 0 and randf() < vuln_chance:
			enemy_vulnerable_timer = 3.0
			combat_events.append({"type": "status", "text": "EXPOSED!", "color": Color.MEDIUM_PURPLE, "side": "enemy"})

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
	var requires_ammo = w["slot_idx"] != -1 # All equipped weapons require ammo
	
	# v80.2 Fix: Enforce Ammo Type Compatibility
	if ammo_id and ammo_id != "" and not sm.is_ammo_compatible(w["type"], ammo_id):
		ammo_id = "" # Ignore incompatible ammo
		
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
			_warn_no_ammo()
			return # Ammo equipped but empty
	elif requires_ammo:
		_warn_no_ammo()
		return # No ammo equipped — weapon can't fire at all
		
	# Feature 66.0: Boss Gating System
	if current_enemy.has("requires_weapon"):
		var req_w = current_enemy["requires_weapon"]
		if not _loadout_has_module(sm, req_w):
			if randf() < 0.2:
				combat_events.append({"type": "miss", "text": "REQUIRES " + req_w.replace("_", " ").to_upper(), "color": Color.RED, "side": "enemy"})
			return # Deals 0 damage and skips calculation
			
	# v105: combat_focus (Recursive Calibration) +5%/level Total Ship Damage.
	# Previously combat_focus's bonus_type "combat_damage" had no consumer;
	# wiring it into skill_dmg_mult means every ship damage path picks it up.
	# v105b: void_weaponry_1 (+5% Total Ship Damage) — endgame sink that was
	# defined but had no consumer. Wired alongside combat_focus.
	# Nerfed 20% → 5% (v105c): 20% stacked too hard on efficiency × warp × combat_focus.
	var combat_dmg_bonus := 0.0
	var void_weap_bonus := 0.0
	if GameState.research_manager:
		combat_dmg_bonus = GameState.research_manager.get_efficiency_bonus("combat_damage")
		if GameState.research_manager.is_tech_unlocked("void_weaponry_1"):
			void_weap_bonus = 0.05
	var skill_dmg_mult = (1.0 + (get_level() * 0.005)) * GameState.warp_manager.get_combat_multiplier() * (1.0 + combat_dmg_bonus) * (1.0 + void_weap_bonus)
	
	# v80.1: Trinity Damage Multipliers
	var trinity_atk_mult = 1.0 + (_get_set_bonus_value("atk_pct") + _get_set_bonus_value("all_dmg_pct")) / 100.0
	var trinity_energy_mult = 1.0 + _get_set_bonus_value("energy_dmg_pct") / 100.0
	var trinity_missile_mult = 1.0 + _get_set_bonus_value("missile_dmg_pct") / 100.0
	
	p_atk_k *= skill_dmg_mult * trinity_atk_mult
	p_atk_e *= skill_dmg_mult * trinity_atk_mult * trinity_energy_mult
	p_atk_x *= skill_dmg_mult * trinity_atk_mult * trinity_missile_mult
	
	var total_crit = sm.crit_chance + get_milestone_crit_bonus()
	var res = resolve_damage(p_atk_k, p_atk_e, p_atk_x, enemy_shield, current_enemy["def"], current_zone.get("difficulty", 1), total_crit, true)
	enemy_shield = max(0, enemy_shield - res[0])
	enemy_hp -= res[1]
	
	# v86.0: Typed damage labels
	var type_tag = "KIN"
	if p_atk_e > p_atk_k and p_atk_e > p_atk_x: type_tag = "NRG"
	elif p_atk_x > p_atk_k and p_atk_x > p_atk_e: type_tag = "EXP"
	
	if res[0] > 0: combat_events.append({"type": "dmg_shield", "text": "-%d %s" % [res[0], type_tag], "color": Color.CYAN, "side": "enemy"})
	if res[1] > 0: combat_events.append({"type": "dmg_hull", "text": "-%d %s" % [res[1], type_tag], "color": Color.RED, "side": "enemy"})
	
	# v86.0: Resistance feedback
	var dominant_resist = current_enemy.get("resist_k", 0.0)
	if type_tag == "NRG": dominant_resist = current_enemy.get("resist_e", 0.0)
	elif type_tag == "EXP": dominant_resist = current_enemy.get("resist_x", 0.0)
	
	if dominant_resist >= 0.20 and randf() < 0.15: # 15% chance to show feedback (anti-spam)
		combat_events.append({"type": "resist", "text": "RESISTED", "color": Color.GRAY, "side": "enemy"})
	elif dominant_resist <= -0.20 and randf() < 0.15:
		combat_events.append({"type": "weakness", "text": "WEAK SPOT", "color": Color.GREEN, "side": "enemy"})
	
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
		# v87.0: Enemy uses typed damage channels
		var e_atk = current_enemy["atk"]
		var e_type = current_enemy.get("dmg_type", "kinetic")
		var e_atk_k = 0
		var e_atk_e = 0
		var e_atk_x = 0
		match e_type:
			"energy":
				e_atk_e = e_atk * ENEMY_ENERGY_ATK_COMP
			"explosive":
				e_atk_x = e_atk * ENEMY_EXPLOSIVE_ATK_COMP
			_:
				e_atk_k = e_atk
		# Enemy uses base crit 5%
		var eres = resolve_damage(e_atk_k, e_atk_e, e_atk_x, player_shield, sm.defense, difficulty, 0.05, false)
		
		# v80.1: Unified Reflect Logic (Reflective Sheath + Monolith's Bedrock)
		var reflect_pct = _get_set_bonus_value("reflect_pct") / 100.0
		if has_reflective: reflect_pct += 0.20
		
		# Enforce reflect safety cap
		reflect_pct = min(reflect_pct, MAX_REFLECT_PERCENT)
		
		if reflect_pct > 0:
			var ref_dmg = int((eres[0] + eres[1]) * reflect_pct)
			if ref_dmg > 0:
				enemy_hp -= ref_dmg
				combat_events.append({"type": "reflect", "text": "REFLECT %d" % ref_dmg, "color": Color.WHITE, "side": "enemy"})
				if enemy_hp <= 0:
					win_fight()
					return # Stop further attack resolution if enemy is dead
		
		# Exotic Shield Matrix Logic (Sector Gamma Protection)
		# v61.0 Fix: Use current_zone_id instead of current_zone.get("id")
		if has_exotic_matrix and current_zone_id == "sector_gamma":
			eres[1] = int(eres[1] * 0.7) # 30% reduction
			
		player_shield = max(0, player_shield - eres[0])
		sm.current_hp -= eres[1]
		# v87.0: Typed damage labels for enemy attacks
		var e_type_tag = "KIN"
		match current_enemy.get("dmg_type", "kinetic"):
			"energy": e_type_tag = "NRG"
			"explosive": e_type_tag = "EXP"
		if eres[0] > 0: combat_events.append({"type": "dmg_shield", "text": "-%d %s" % [eres[0], e_type_tag], "color": Color.CYAN, "side": "player"})
		if eres[1] > 0: combat_events.append({"type": "dmg_hull", "text": "-%d %s" % [eres[1], e_type_tag], "color": Color.RED, "side": "player"})
	if sm.current_hp <= 0: lose_fight()

func resolve_damage(atk_k, atk_e, atk_x, c_shield, c_armor, difficulty = 1, crit_chance = 0.05, is_player_attacker = false):
	var shield_dmg_pot = (atk_k * 0.5) + (atk_e * 1.5) + (atk_x * 1.1)
	var sm = GameState.shipyard_manager
	
	# v85.2: Vulnerable Status (+20% damage taken)
	if not is_player_attacker and enemy_vulnerable_timer > 0:
		shield_dmg_pot *= 1.2
	
	# v85.2: Healthy/Injured Damage Bonuses
	if is_player_attacker:
		var enemy_hp_pct = float(enemy_hp) / float(enemy_max_hp) if enemy_max_hp > 0 else 1.0
		if enemy_hp_pct >= 0.8:
			var bonus = sm.affix_bonuses.get("dmg_healthy", 0.0)
			if bonus > 0: shield_dmg_pot *= (1.0 + bonus)
		elif enemy_hp_pct <= 0.35:
			var bonus = sm.affix_bonuses.get("dmg_injured", 0.0)
			if bonus > 0: shield_dmg_pot *= (1.0 + bonus)

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
	
	# Zone-scaled k: prevents 99%+ damage mitigation in late zones (Z7+).
	# Z1: k=200; Z5: k=908; Z10: k=2095 — final boss TTK ~30 min instead of ~11 hours.
	var zone_diff = 1
	if current_zone_id != "" and current_zone_id in zones:
		zone_diff = zones[current_zone_id].get("difficulty", 1)
	var k = DEF_K_CONSTANT + DEF_K_ZONE_SCALE * pow(float(zone_diff), DEF_K_ZONE_EXP)
	
	# Armor Penetration Logic
	var arm_k = c_armor
	var arm_e = c_armor * 0.7
	var arm_x = c_armor * 0.2
	
	# Reactive Armor Logic (Phase 19)
	if has_reactive:
		var hp_ratio = float(GameState.shipyard_manager.current_hp) / float(GameState.shipyard_manager.max_hp)
		# If HP is low, effectively double the K-scale for better mitigation
		k *= (1.0 + (1.0 - hp_ratio))

	# Clamp mitigation to MAX_DAMAGE_REDUCTION so lower k can't create
	# unkillable high-DEF enemies (≥20% of each damage type always lands).
	var _min_factor = 1.0 - MAX_DAMAGE_REDUCTION
	var hull_dmg_k = atk_k * 1.2 * max(_min_factor, 1.0 - arm_k / (arm_k + k))
	var hull_dmg_e = atk_e * 0.9 * max(_min_factor, 1.0 - arm_e / (arm_e + k))
	var hull_dmg_x = atk_x * 1.0 * max(_min_factor, 1.0 - arm_x / (arm_x + k))
	
	# v86.0: Enemy Damage Type Resistances
	if is_player_attacker and current_enemy:
		var rk = clamp(current_enemy.get("resist_k", 0.0), -0.40, 0.50)
		var re = clamp(current_enemy.get("resist_e", 0.0), -0.40, 0.50)
		var rx = clamp(current_enemy.get("resist_x", 0.0), -0.40, 0.50)
		# Phase A: capture per-type pre/post-resist so we can see whether
		# players actually adapt their damage type to the enemy.
		GameState.note_damage(hull_dmg_k, hull_dmg_e, hull_dmg_x,
			hull_dmg_k * (1.0 - rk), hull_dmg_e * (1.0 - re), hull_dmg_x * (1.0 - rx))
		hull_dmg_k *= (1.0 - rk)
		hull_dmg_e *= (1.0 - re)
		hull_dmg_x *= (1.0 - rx)
	
	var total_hull_dmg = (hull_dmg_k + hull_dmg_e + hull_dmg_x) * bleed_ratio
	
	# v85.2: Vulnerable/Thresholds applied to Hull too
	if not is_player_attacker and enemy_vulnerable_timer > 0:
		total_hull_dmg *= 1.2
		
	if is_player_attacker:
		var enemy_hp_pct = float(enemy_hp) / float(enemy_max_hp) if enemy_max_hp > 0 else 1.0
		if enemy_hp_pct >= 0.8:
			var bonus = sm.affix_bonuses.get("dmg_healthy", 0.0)
			if bonus > 0: total_hull_dmg *= (1.0 + bonus)
		elif enemy_hp_pct <= 0.35:
			var bonus = sm.affix_bonuses.get("dmg_injured", 0.0)
			if bonus > 0: total_hull_dmg *= (1.0 + bonus)
	
	var variance = randf_range(0.9, 1.1)
	var is_crit = randf() < crit_chance
	if is_crit: variance *= 1.5
	return [int(damage_to_shield * variance), int(max(1.0 if (atk_k + atk_e + atk_x) > 0 else 0, total_hull_dmg * variance)), is_crit]

# v101: Combat Loot Scaling System
# Ensures combat resource drops keep pace with gathering/processing progression
func get_combat_loot_multiplier() -> float:
	var mult = 1.0
	
	# 1. Combat Skill Level bonus (+1% per level, e.g. Lvl 50 = +50%)
	mult += get_level() * 0.01
	
	# 2. Zone Difficulty bonus (+15% per zone tier above 1)
	var zone_diff = current_zone.get("difficulty", 1) if current_zone else 1
	mult += max(0, (zone_diff - 1)) * 0.15
	
	# 3. Efficiency Research tiers (same x2-x32 curve as gathering)
	var rm = GameState.research_manager
	if rm:
		if rm.is_tech_unlocked("efficiency_5"): mult *= 4.0  # x32 total with base
		elif rm.is_tech_unlocked("efficiency_4"): mult *= 3.0
		elif rm.is_tech_unlocked("efficiency_3"): mult *= 2.5
		elif rm.is_tech_unlocked("efficiency_2"): mult *= 2.0
		elif rm.is_tech_unlocked("efficiency_1"): mult *= 1.5
	
	# 4. Warp Manager bonus
	if GameState.warp_manager:
		mult *= max(1.0, GameState.warp_manager.get_combat_multiplier())
	
	return mult

func get_effective_module_drop_chance(enemy_data: Dictionary) -> float:
	var base = enemy_data.get("module_drop_chance", 0.0)
	if base <= 0: return 0.0
	
	var sm = GameState.shipyard_manager
	var rm = GameState.research_manager
	
	# 1. Accuracy Bonus: +1% per 4 points above 100 (e.g. 500 Accuracy = +100%)
	var acc_bonus = max(0, (sm.accuracy - 100) / 400.0)
	
	# 2. Xeno-Engineering Bonus (Rare Loot Chance)
	var xeno_bonus = rm.get_efficiency_bonus("xeno_engineering") if rm else 0.0
	
	var total_mult = 1.0 + acc_bonus + xeno_bonus
	return base * total_mult

# Weighted pick over a drop pool using MODULE_DROP_WEIGHTS by slot type.
# Entries whose slot type has weight <= 0 (e.g. battery) can never drop,
# even if present in an enemy's pool. Returns "" if nothing is eligible.
func _pick_weighted_base(pool: Array, sm: Object) -> String:
	var total := 0.0
	var weighted := []
	for mid in pool:
		var st = sm.modules.get(mid, {}).get("slot_type", "weapon")
		var w = float(MODULE_DROP_WEIGHTS.get(st, 10))
		if w <= 0.0:
			continue
		weighted.append([mid, w])
		total += w
	if weighted.is_empty():
		return ""
	var r := randf() * total
	for pair in weighted:
		r -= pair[1]
		if r <= 0.0:
			return pair[0]
	return weighted[-1][0]

func win_fight():
	log_msg("Destroyed %s!" % current_enemy["name"])
	
	# v101: Combat Loot Scaling — loot now grows with progression
	var loot_mult = get_combat_loot_multiplier()
	
	for entry in current_enemy["loot"]:
		var base_qty = randi_range(entry[1], entry[2])
		var qty = int(ceil(float(base_qty) * loot_mult))
		if entry[0] == "credits": GameState.resources.add_currency("credits", qty)
		else: GameState.resources.add_element(entry[0], qty)
		if entry[0] != "credits": GameState.note_production("combat", qty)  # P3.10
		session_loot[entry[0]] = session_loot.get(entry[0], 0) + qty
		
	# v80.1: Boss Core drops
	if current_enemy.get("is_boss", false) and current_enemy.has("boss_core") and current_enemy["boss_core"] != "":
		var core_id = current_enemy["boss_core"]
		GameState.resources.add_element(core_id, 1); GameState.note_production("combat", 1)  # P3.10
		
		# v80.4: Display friendly name from DB
		var core_name = "Boss Core"
		if ElementDB:
			core_name = ElementDB.get_display_name(core_id)
			
		combat_events.append({"type": "loot", "text": "BOSS CORE: %s" % core_name, "color": Color.ORANGE, "side": "enemy"})
		log_msg("Looted Boss Core: %s" % core_name)
		session_loot[core_id] = session_loot.get(core_id, 0) + 1
	# v85.2: Berserking Proc on Kill
	var berserk_chance = GameState.shipyard_manager.affix_bonuses.get("berserk_on_kill", 0.0)
	if berserk_chance > 0 and randf() < berserk_chance:
		player_berserk_timer = 5.0
		combat_events.append({"type": "status", "text": "OVERDRIVEN!", "color": Color.ORANGE_RED, "side": "player"})

	for entry in current_enemy.get("rare_loot", []):
		if randf() < entry[1]:
			var qty = randi_range(entry[2], entry[3])
			var item_id = entry[0]
			var sm = GameState.shipyard_manager
			
			if sm and item_id in sm.modules:
				var m_data = sm.modules[item_id]
				var rarity = m_data.get("rarity", sm.Rarity.COMMON)
				var zone_difficulty = int(current_zone.get("difficulty", 1))
				
				# Generate it properly so it rolls affixes and sockets!
				# Rare loot modules should always be generated if not COMMON
				var final_id = item_id
				if rarity != sm.Rarity.COMMON:
					final_id = sm.generate_module_drop(item_id, rarity, zone_difficulty)
					m_data = sm.modules[final_id]
					session_loot[final_id] = session_loot.get(final_id, 0) + 1
				else:
					sm.module_inventory[item_id] = sm.module_inventory.get(item_id, 0) + qty
					sm.unseen_modules[item_id] = true
					session_loot[item_id] = session_loot.get(item_id, 0) + qty
					
				sm.new_drops_alert = true
				sm.inventory_updated.emit()
				
				var rarity_color = sm.RARITY_COLORS.get(rarity, Color.WHITE)
				var rarity_label = sm.RARITY_LABELS.get(rarity, "")
				if rarity_label == "":
					rarity_label = "Common"
				combat_events.append({"type": "loot", "text": "* %s DROP" % rarity_label.to_upper(), "color": rarity_color, "side": "enemy"})
				log_msg("Looted %s Module: %s" % [rarity_label, m_data["name"]])
			else:
				# It's a standard generic element (VoidCrystal, NavData, etc)
				GameState.resources.add_element(item_id, qty); GameState.note_production("combat", qty)  # P3.10
				if item_id in ElementDB.get_elements_in_category("reclaimed_components"):
					GameState.note_material(item_id, "combat", qty)  # Phase 0
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
		GameState.resources.add_element(drop, qty); GameState.note_production("combat", qty)  # P3.10
		combat_events.append({"type": "loot", "text": "SCAVENGED %s" % drop, "color": Color.AQUA, "side": "enemy"})
		log_msg("Nano-Scavenger triggered: Found %d %s" % [qty, drop])
	
	# v71.0: Module Rarity Drop System
	var drop_chance = get_effective_module_drop_chance(current_enemy)

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

		# v85.0: Apply Loot Filter
		var base_id = _pick_weighted_base(unlocked_pool, sm)
		if base_id != "":
			var m_data = sm.modules.get(base_id, {})
			var slot_type = m_data.get("slot_type", "weapon")

			var is_rarity_ok = loot_filter.get(rarity, true)
			var is_type_ok = loot_type_filter.get(slot_type, true)

			# Weapon sub-filter by damage type (energy > explosive > kinetic,
			# matching the weapon-type rule used everywhere else).
			if is_type_ok and slot_type == "weapon":
				var wstats = m_data.get("stats", {})
				var wtype = "kinetic"
				if float(wstats.get("atk_energy", 0)) > 0.0:
					wtype = "energy"
				elif float(wstats.get("atk_explosive", 0)) > 0.0:
					wtype = "explosive"
				is_type_ok = loot_weapon_type_filter.get(wtype, true)

			if is_rarity_ok and is_type_ok:
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
			else:
				var reason = "Rarity" if not is_rarity_ok else "Type"
				if not is_rarity_ok and not is_type_ok: reason = "Rarity & Type"
				log_msg("Filtered out %s (%s) module drop." % [sm.RARITY_LABELS.get(rarity, "Common"), slot_type.capitalize()])

	add_xp(int(current_enemy["xp"] * (1.0 + GameState.research_manager.get_efficiency_bonus("combat_xp"))))
	# Per-kill HUD timer resets at the moment of the kill; session timer keeps running.
	time_since_last_kill = 0.0
	enemy_defeated.emit(current_enemy["id"])
	
	# v86.0: Track boss kills for hazard zone unlocks
	if current_enemy.get("is_boss", false):
		var eid = current_enemy["id"]
		boss_kills[eid] = boss_kills.get(eid, 0) + 1
	
	# v86.0: Hazard Zone Gauntlet Progression
	if hazard_state["active"]:
		hazard_state["wave"] += 1
		if hazard_state["wave"] >= hazard_state["max_waves"]:
			# Gauntlet Complete!
			_complete_hazard_zone()
		else:
			# Spawn next wave enemy (NO HP/shield reset)
			_spawn_hazard_wave_enemy()
			combat_events.append({"type": "status", "text": "WAVE %d/%d" % [hazard_state["wave"] + 1, hazard_state["max_waves"]], "color": Color.YELLOW, "side": "player"})
		return
	
	spawn_enemy()

func lose_fight():
	var sm = GameState.shipyard_manager
	var cost = sm.get_full_repair_cost(sm.active_hull)
	var current_credits = GameState.resources.get_currency("credits")
	if cost > current_credits:
		cost = current_credits
	GameState.resources.add_currency("credits", -cost)
	
	# v100.0: Module Durability System
	sm.handle_module_defeat()
	
	# v86.0: Hazard Zone — eject on death
	if hazard_state["active"]:
		var hz_name = hazard_zones.get(hazard_state["zone_id"], {}).get("name", "Hazard Zone")
		log_msg("EJECTED from %s at Wave %d/%d!" % [hz_name, hazard_state["wave"] + 1, hazard_state["max_waves"]])
		combat_events.append({"type": "status", "text": "HAZARD FAILED", "color": Color.RED, "side": "player"})
		_reset_hazard_state()
	
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

func _warn_no_ammo():
	# A weapon tried to fire with no ammo (it deals ZERO damage). Surface it
	# clearly but throttled, so the player understands why nothing's happening.
	var now := Time.get_ticks_msec()
	if now - _last_ammo_warn_ms < 2500:
		return
	_last_ammo_warn_ms = now
	combat_events.append({
		"type": "miss",
		"text": "NO AMMO — load ammo in the Designer",
		"color": Color(1.0, 0.55, 0.2),
		"side": "player"
	})

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
	# subject to standard armor/shield resolution.
	# v105: also picks up combat_focus (Recursive Calibration) bonus.
	# v105b: void_weaponry_1 +5% Total Ship Damage (endgame sink).
	# Nerfed 20% → 5% (v105c) to match main hit path.
	var combat_dmg_bonus_b := 0.0
	var void_weap_bonus_b := 0.0
	if GameState.research_manager:
		combat_dmg_bonus_b = GameState.research_manager.get_efficiency_bonus("combat_damage")
		if GameState.research_manager.is_tech_unlocked("void_weaponry_1"):
			void_weap_bonus_b = 0.05
	var skill_dmg_mult = (1.0 + (get_level() * 0.005)) * (1.0 + combat_dmg_bonus_b) * (1.0 + void_weap_bonus_b)
	var res = resolve_damage(total_atk_k * 5.0 * skill_dmg_mult, 0, 0, enemy_shield, current_enemy["def"], current_zone.get("difficulty", 1), 0.1, true) # 10% base crit for volley
	
	enemy_shield = max(0, enemy_shield - res[0])
	enemy_hp -= res[1]
	
	if res[0] > 0: combat_events.append({"type": "dmg_shield", "text": "BRST %d" % res[0], "color": Color.CYAN, "side": "enemy"})
	if res[1] > 0: combat_events.append({"type": "dmg_hull", "text": "BRST %d" % res[1], "color": Color.GOLD, "side": "enemy"})
	
	if enemy_hp <= 0: win_fight()

func log_msg(msg: String):
	combat_log.append(msg)
	if combat_log.size() > 20: combat_log.pop_front()

# v86.0: Hazard Zone API
func start_hazard(zone_id: String) -> bool:
	if zone_id not in hazard_zones:
		log_msg("Unknown hazard zone: %s" % zone_id)
		return false
	
	var hz = hazard_zones[zone_id]
	
	# Check unlock: boss must have been killed at least once
	var unlock_boss = hz.get("unlock_boss", "")
	if unlock_boss != "" and boss_kills.get(unlock_boss, 0) <= 0:
		log_msg("LOCKED: Defeat %s first." % enemy_db.get(unlock_boss, {}).get("name", unlock_boss))
		return false
	
	# Hard gate: counter module must be equipped
	var counter = hz.get("counter_module", "")
	if counter != "":
		var sm = GameState.shipyard_manager
		if not _loadout_has_module(sm, counter):
			var mod_name = sm.modules.get(counter, {}).get("name", counter)
			log_msg("BLOCKED: %s required to enter %s." % [mod_name, hz["name"]])
			combat_events.append({"type": "status", "text": "REQUIRES: %s" % mod_name.to_upper(), "color": Color.RED, "side": "player"})
			return false
	
	# Set up gauntlet
	hazard_state = {
		"active": true,
		"zone_id": zone_id,
		"wave": 0,
		"max_waves": hz.get("max_waves", 7),
		"completed": false
	}
	
	# Create a dummy zone entry for combat compatibility
	current_zone = {
		"name": hz["name"],
		"desc": hz["desc"],
		"difficulty": hz.get("zone_difficulty", 3),
		"enemies": hz["enemy_pool"]
	}
	current_zone_id = zone_id
	
	GameState.set_active_manager(self)
	in_combat = true
	
	var sm = GameState.shipyard_manager
	player_shield = sm.max_shield
	shield_regen_accumulator = 0.0
	player_heat = 0.0
	overheat_lock = 0.0
	heat_changed.emit(player_heat, player_max_heat)
	
	_spawn_hazard_wave_enemy()
	log_msg("ENTERING: %s — WAVE 1/%d" % [hz["name"], hazard_state["max_waves"]])
	combat_events.append({"type": "status", "text": "HAZARD: %s" % hz["name"].to_upper(), "color": Color.YELLOW, "side": "player"})
	combat_events.append({"type": "status", "text": "WAVE 1/%d" % hazard_state["max_waves"], "color": Color.YELLOW, "side": "player"})
	return true

func _spawn_hazard_wave_enemy():
	var hz = hazard_zones.get(hazard_state["zone_id"], {})
	var wave = hazard_state["wave"]
	var max_waves = hazard_state["max_waves"]
	
	var eid = ""
	if wave == max_waves - 1:
		# Final wave: Boss
		eid = hz.get("boss_enemy", hz["enemy_pool"][0])
	elif wave == max_waves - 2:
		# Second to last: Elite mini-boss
		eid = hz.get("elite_enemy", hz["enemy_pool"][0])
	else:
		# Regular waves: pick from pool
		eid = hz["enemy_pool"][wave % hz["enemy_pool"].size()]
	
	# Scale stats by wave progression (+20% per wave)
	var wave_mult = 1.0 + (wave * 0.20)
	
	target_enemy_id = eid
	spawn_enemy()
	
	# Apply wave scaling
	current_enemy["max_hp"] = int(current_enemy["max_hp"] * wave_mult)
	current_enemy["atk"] = int(current_enemy["atk"] * wave_mult)
	current_enemy["max_shield"] = int(current_enemy.get("max_shield", 0) * wave_mult)
	
	enemy_hp = current_enemy["max_hp"]
	enemy_max_hp = enemy_hp
	enemy_shield = float(current_enemy["max_shield"])
	enemy_max_shield = enemy_shield

func _complete_hazard_zone():
	var hz_id = hazard_state["zone_id"]
	var hz = hazard_zones.get(hz_id, {})
	var hz_name = hz.get("name", "Hazard Zone")
	
	log_msg("HAZARD CLEARED: %s!" % hz_name)
	combat_events.append({"type": "status", "text": "HAZARD CLEARED!", "color": Color.GOLD, "side": "player"})
	
	# First-clear reward
	if hz_id not in hazard_clears:
		hazard_clears[hz_id] = true
		var reward = hz.get("first_clear_reward", "")
		if reward != "":
			GameState.resources.add_element(reward, 1)
			log_msg("FIRST CLEAR REWARD: %s" % reward.replace("_", " ").capitalize())
			combat_events.append({"type": "loot", "text": "★ FIRST CLEAR REWARD", "color": Color.GOLD, "side": "player"})
	
	_reset_hazard_state()
	in_combat = false

func _reset_hazard_state():
	hazard_state = {
		"active": false,
		"zone_id": "",
		"wave": 0,
		"max_waves": 7,
		"completed": false
	}

func _get_active_hazard_type() -> String:
	if not hazard_state["active"]:
		return ""
	var hz = hazard_zones.get(hazard_state["zone_id"], {})
	return hz.get("hazard_type", "")

func is_hazard_unlocked(zone_id: String) -> bool:
	if zone_id not in hazard_zones:
		return false
	var hz = hazard_zones[zone_id]
	var unlock_boss = hz.get("unlock_boss", "")
	return unlock_boss == "" or boss_kills.get(unlock_boss, 0) > 0

func has_counter_module(zone_id: String) -> bool:
	if zone_id not in hazard_zones:
		return false
	var counter = hazard_zones[zone_id].get("counter_module", "")
	if counter == "":
		return true # No counter needed
	var sm = GameState.shipyard_manager
	return _loadout_has_module(sm, counter)

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
	data["loot_filter"] = loot_filter
	data["loot_type_filter"] = loot_type_filter
	data["loot_weapon_type_filter"] = loot_weapon_type_filter
	data["boss_kills"] = boss_kills
	data["hazard_clears"] = hazard_clears
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
	
	# v85.0: Loot Filter Loading
	if data.has("loot_filter"):
		var saved_filter = data["loot_filter"]
		# Merge to handle new rarities if added
		for r in saved_filter:
			loot_filter[int(r)] = saved_filter[r]
			
	if data.has("loot_type_filter"):
		var saved_type_filter = data["loot_type_filter"]
		for t in saved_type_filter:
			loot_type_filter[t] = saved_type_filter[t]

	if data.has("loot_weapon_type_filter"):
		var saved_wt_filter = data["loot_weapon_type_filter"]
		for t in saved_wt_filter:
			loot_weapon_type_filter[t] = saved_wt_filter[t]
	
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
	
	# v86.0: Load boss kills and hazard clears
	boss_kills = data.get("boss_kills", {})
	hazard_clears = data.get("hazard_clears", {})
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
		var d_name = "Liras" if item == "credits" else (ElementDB.get_display_name(item) if ElementDB else item)
		report += " + %s: %d\n" % [d_name, loot_summary[item]]
	if credits_earned > 0:
		report += " + Liras: %d\n" % credits_earned
	report += " + XP: %d" % total_xp
	
	return report
