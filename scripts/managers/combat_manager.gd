extends Skill

var in_combat = false

var current_zone = null
var current_zone_id: String = "" # Track explicitly for saving
var current_enemy = null
var target_enemy_id = null
var _enemy_enraged: bool = false  # v109: per-fight enrage state (P3 boss mechanic)
var _current_phase_idx: int = -1  # v113 (NG+ P1): per-fight multi-phase band index (telegraph dedupe)

# Battle State (Enemies only, player uses shipyard_manager.current_hp)
var player_shield = 0.0
var player_max_shield = 0.0

var enemy_hp = 0
var enemy_max_hp = 100
var enemy_shield = 0.0
var enemy_max_shield = 0.0



# Battery State
var player_weapon_states: Array = [] # {name, type, timer, interval, dmg_k, dmg_e, slot_idx}
var enemy_attack_timer = 0.0

# Log & Events
var combat_log: Array[String] = []
var combat_events: Array[Dictionary] = [] # [{type, text, color, side}]

# Consumables
var consumable_cooldown = 0.0
# v106: 1.5 → 12.0 overshot; recalibrated to 10.0. Short enough that careful
# timing matters, long enough that spam can no longer carry you through any
# fight regardless of damage type or gear. Pair with the heal_pct values in
# element_db: top-tier consumables now restore ~35% per cycle, not 50%.
var consumable_cooldown_max = 10.0
var kit_potency_dbg: float = 1.0  # sim-only knob: scales consumable heal_pct for the death-tension sweep; 1.0 = normal play

# Throttle for the "no ammo" combat warning so it doesn't spam every tick.
var _last_ammo_warn_ms: int = 0

signal enemy_defeated(enemy_id)
signal combat_started() # v72.8: For Elite bounty detection
signal zones_changed() # v113 (NG+): a flag-gated zone (Z11/Z12) unlocked → refresh the sector list
signal zone_entered(zone_id) # v128: player deployed into a sector — drives "discover" missions
signal combat_lost() # v128: player lost a fight (modules took durability damage) — first-loss coach hook

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
	"explosive": true,
	"cryo": true  # v109: 4th type
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
var total_kills: int = 0 # all enemies defeated (active + offline) — telemetry + the offline-combat nudge
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
# v120: combat leveling removed. The crit/evasion milestones were combat-XP power
# perks — neutralized to 0 so a high-level LEGACY save can't keep them (the soft-gate
# balance assumes no combat-level bonus). Auto-Consume is gated on the auto_repair_*
# RESEARCH nodes (the live _check_auto_consume gate already uses get_auto_consume_threshold);
# this helper now mirrors that research gate instead of a combat level.
func get_milestone_crit_bonus() -> float:
	return 0.0

func get_milestone_evasion_bonus() -> int:
	return 0

func is_auto_consume_unlocked() -> bool:
	return GameState.research_manager.get_auto_consume_threshold() > 0.0

# v112: Removed dead get_external_progression_combat_mult() — a 6×-clamped
# "enemy progression compensation" that had ZERO callers (verified repo-wide).
# It was meant to scale enemies up to match player level/research/warp/trophy so
# zones stayed hard, but it never ran. A TTK spike (scripts/sim/combat_spike.gd)
# confirmed on-tier boss fights are already in the v106 ballpark WITHOUT it
# (T7 ~15min, T10 ~24min on an unoptimized tier-matched Legendary loadout), and
# scaling old zones back up would fight the genre's "re-clear fast once you out-
# level it" power fantasy. If NG+/siege ever needs per-loop enemy scaling it
# should be its own deliberate system, not this dead clamp. (Resolves the sanity
# checklist "Multiplier clamps actually bind" item — answer: it didn't bind.)

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
		"name": "Glacier Belt",
		"desc": "Frozen deep-space anomaly. Ice-adapted hostiles.",
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
	},
	# v109: Zone 11 — the Warp Gate. Auto-unlocks on Z10 boss kill (flag, not
	# research). Enemies are warp_hardened (Cryo-only). See enemy_db Z11 block.
	"the_threshold": {
		"name": "The Threshold",
		"desc": "Warp-Hardened space. Hostiles are immune to conventional armaments — only Cryogenic weapons (unlocked by Warping) breach them.",
		"difficulty": 11,
		"enemies": ["z11_warp_revenant", "z11_phase_horror", "z11_null_sentinel", "z11_exotic_leviathan", "z11_boss_threshold_warden"],
		"unlock_flag": "z11_unlocked"
	},
	# v113 (NG+ P3, WT2): Zone 12 — The Rift. CORROSION element. Clear-gated:
	# unlocks on (Z11 boss cleared + Warp), NOT research (wiring in P3 step 4).
	# Trash are conventional (any weapon clears them); the Rift Warden is the
	# 2-phase gate (Cryo → Corrosion) — swap to a Corrosion preset for phase 2.
	"the_rift": {
		"name": "Sector 12 — The Rift",
		"desc": "A corrosive tear in space. The Rift Warden hardens against Cryo, then Corrosion — breach each phase with the matching armament.",
		"difficulty": 12,
		"enemies": ["z12_acid_revenant", "z12_rust_horror", "z12_corrosion_sentinel", "z12_caustic_leviathan", "z12_boss_rift_warden"],
		"unlock_flag": "z12_unlocked"
	}
}

# Look up a zone's display NAME by its difficulty tier (1-12). Modules carry their
# source `zone` (= tier); this maps it to the sector name ("Lunar Orbit", "Sector
# Alpha", …) for provenance UI. Falls back to "Sector N" if no zone matches.
func get_zone_name(tier: int) -> String:
	for k in zones:
		if int(zones[k].get("difficulty", 0)) == tier:
			return str(zones[k].get("name", ""))
	return "Sector %d" % tier

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
		"xp": 10, "eva": 6, "zone": 1, "resist_k": 0.25, "resist_e": 0.20, "resist_x": -0.30, "dmg_type": "kinetic"
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
		"module_drop_pool": ["z2_kinetic", "z2_energy", "z2_missile"],
		"xp": 28, "eva": 15, "zone": 2, "resist_k": 0.15, "resist_e": -0.15, "resist_x": 0.0, "dmg_type": "explosive"
	},
	"z2_ore_hauler": {
		"name": "Ore Hauler",
		"stats": {"hp": 950, "atk": 28, "def": 10, "atk_interval": 5.0, "accuracy": 20},
		"loot": [["Fe", 10, 25], ["Si", 5, 12], ["Res1", 2, 5], ["PirateSalvage", 2, 5], ["SalvageData", 1, 3]],
		"rare_loot": [["Steel", 0.10, 1, 3], ["SalvagedAlloy", 0.40, 1, 3]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z2_shield", "z2_armor"],
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
		"module_drop_pool": ["z3_kinetic", "z3_energy", "z3_missile"],
		"xp": 45, "eva": 20, "zone": 3, "resist_k": -0.15, "resist_e": -0.15, "resist_x": 0.15, "dmg_type": "kinetic"
	},
	"z3_derelict_frigate": {
		"name": "Derelict Frigate",
		"stats": {"hp": 2000, "max_shield": 400, "atk": 82, "def": 18, "atk_interval": 4.0, "accuracy": 42},
		"loot": [["Steel", 5, 12], ["Fe", 10, 25], ["Res2", 1, 3], ["MartianRelics", 2, 4]],
		"rare_loot": [["Ti", 0.10, 2, 5], ["Cr", 0.08, 1, 3]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z3_shield", "z3_armor"],
		"xp": 70, "eva": 5, "zone": 3, "resist_k": 0.15, "resist_e": -0.30, "resist_x": 0.40, "dmg_type": "explosive"
	},
	"z3_boss_warmaster": {
		"name": "Martian Warmaster",
		"stats": {"hp": 17424, "max_shield": 580, "atk": 210, "def": 87, "atk_interval": 2.5, "accuracy": 65},
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
		"loot": [["CoolantCell", 1, 3], ["credits", 800, 1500], ["Res2", 1, 3], ["CryoEssence", 1, 3], ["RimeplateScrap", 3, 6]],  # v114: Z4 front signature raw
		"rare_loot": [["AdvCircuit", 0.08, 1, 2]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z4_kinetic", "z4_energy", "z4_missile", "z4_shield", "z4_armor"],
		"xp": 120, "eva": 25, "zone": 4, "resist_k": -0.25, "resist_e": 0.30, "resist_x": 0.0, "dmg_type": "energy"
	},
	"z4_cryo_sentinel": {
		"name": "Frost Sentinel",
		"stats": {"hp": 2765, "max_shield": 800, "atk": 160, "def": 32, "atk_interval": 2.5, "accuracy": 55},
		"loot": [["Ti", 5, 12], ["credits", 1000, 2000], ["Res2", 1, 3], ["CryoEssence", 1, 3], ["RimeplateScrap", 3, 6]],  # v114: Z4 front signature raw
		"rare_loot": [["Chip", 0.10, 1, 3]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z4_kinetic", "z4_energy", "z4_missile", "z4_shield", "z4_armor"],
		"xp": 140, "eva": 12, "zone": 4, "resist_k": -0.25, "resist_e": 0.40, "resist_x": 0.0, "dmg_type": "energy"
	},
	"z4_frost_hulk": {
		"name": "Frost Hulk",
		"stats": {"hp": 5000, "atk": 138, "def": 40, "atk_interval": 4.0, "accuracy": 48},
		"loot": [["Steel", 8, 18], ["Fe", 15, 35], ["Res2", 1, 3], ["CryoEssence", 1, 2]],
		"rare_loot": [["Ti", 0.15, 3, 8], ["Au", 0.20, 1, 3]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z4_kinetic", "z4_energy", "z4_missile"],
		"xp": 130, "eva": 5, "zone": 4, "resist_k": -0.30, "resist_e": 0.25, "resist_x": 0.15, "dmg_type": "kinetic"
	},
	"z4_glacial_drone": {
		"name": "Glacial Drone",
		"stats": {"hp": 2400, "max_shield": 500, "atk": 175, "def": 28, "atk_interval": 1.8, "accuracy": 58},
		"loot": [["credits", 1200, 2500], ["Cu", 5, 12], ["Res2", 2, 4], ["CryoEssence", 2, 4]],
		"rare_loot": [["AdvCircuit", 0.10, 1, 2]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z4_shield", "z4_armor"],
		"xp": 135, "eva": 18, "zone": 4, "resist_k": -0.15, "resist_e": 0.30, "resist_x": 0.0, "dmg_type": "energy"
	},
	"z4_boss_overseer": {
		"name": "Glacial Overseer",
		"stats": {"hp": 25555, "max_shield": 1277, "atk": 444, "def": 191, "atk_interval": 2.5, "accuracy": 85},
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
		"rare_loot": [["Superalloy", 0.08, 1, 3], ["Au", 0.25, 2, 5]],
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
		"module_drop_pool": ["z5_kinetic", "z5_energy", "z5_missile"],
		"xp": 380, "eva": 10, "zone": 5, "resist_k": 0.35, "resist_e": 0.15, "resist_x": -0.30, "dmg_type": "kinetic"
	},
	"z5_alien_probe": {
		"name": "Alien Probe",
		"stats": {"hp": 5000, "max_shield": 3000, "atk": 313, "def": 60, "atk_interval": 1.2, "accuracy": 78},
		"loot": [["credits", 4000, 7000], ["Circuit", 5, 10], ["Res2", 2, 5], ["XenoFragment", 1, 3]],
		"rare_loot": [["AdvCircuit", 0.10, 2, 4]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z5_shield", "z5_armor"],
		"xp": 320, "eva": 35, "zone": 5, "resist_k": 0.25, "resist_e": -0.15, "resist_x": -0.25, "dmg_type": "energy"
	},
	"z5_boss_harbinger": {
		"name": "Xenon Harbinger",
		"stats": {"hp": 70277, "max_shield": 2811, "atk": 749, "def": 421, "atk_interval": 2.5, "accuracy": 110},
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
		"module_drop_pool": ["z6_kinetic", "z6_energy", "z6_missile"],
		"xp": 780, "eva": 12, "zone": 6, "resist_k": -0.15, "resist_e": -0.25, "resist_x": 0.25, "dmg_type": "kinetic"
	},
	"z6_ore_guardian": {
		"name": "Ore Guardian",
		"stats": {"hp": 14000, "max_shield": 5000, "atk": 688, "def": 170, "atk_interval": 3.0, "accuracy": 88},
		"loot": [["Fe", 30, 70], ["Steel", 10, 25], ["Res3", 1, 3]],
		"rare_loot": [["VoidArtifact", 0.10, 1, 3]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z6_shield", "z6_armor"],
		"xp": 720, "eva": 8, "zone": 6, "resist_k": 0.25, "resist_e": -0.30, "resist_x": 0.45, "dmg_type": "explosive"
	},
	"z6_boss_colossus": {
		"name": "Gamma Colossus",
		"stats": {"hp": 185531, "max_shield": 6184, "atk": 1775, "def": 927, "atk_interval": 2.5, "accuracy": 140},
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
		"module_drop_pool": ["z7_kinetic", "z7_energy", "z7_missile"],
		"xp": 1700, "eva": 25, "zone": 7, "resist_k": -0.30, "resist_e": 0.40, "resist_x": 0.15, "dmg_type": "energy"
	},
	"z7_gamma_beast": {
		"name": "Gamma Beast",
		"stats": {"hp": 75000, "atk": 1500, "def": 380, "atk_interval": 3.5, "accuracy": 95},
		"loot": [["RadIsotope", 3, 8], ["ExoticMatter", 1, 3], ["Res3", 2, 5]],
		"rare_loot": [["Os", 0.10, 1, 2]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z7_shield", "z7_armor"],
		"xp": 1600, "eva": 8, "zone": 7, "resist_k": -0.15, "resist_e": 0.30, "resist_x": 0.0, "dmg_type": "kinetic"
	},
	"z7_boss_sovereign": {
		"name": "Sovereign Prism",
		# v106: Late-game escalation pass — HP 952K→1.4M, ATK 10.2K→14K. Target ~8 min for tier-matched legendary clears (was ~6 min).
		"stats": {"hp": 490000, "max_shield": 13605, "atk": 6006, "def": 2040, "atk_interval": 2.5, "accuracy": 170},
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
		"module_drop_pool": ["z8_kinetic", "z8_energy", "z8_missile"],
		"xp": 4200, "eva": 28, "zone": 8, "resist_k": 0.30, "resist_e": -0.15, "resist_x": -0.25, "dmg_type": "energy"
	},
	"z8_nebula_phantom": {
		"name": "Nebula Phantom",
		"stats": {"hp": 182000, "max_shield": 40000, "atk": 3375, "def": 800, "atk_interval": 2.5, "accuracy": 118},
		"loot": [["credits", 150000, 300000], ["VoidCrystal", 3, 7], ["Res3", 3, 8]],
		"rare_loot": [["ExoticMatter", 0.12, 2, 5]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z8_shield", "z8_armor"],
		"xp": 4300, "eva": 15, "zone": 8, "resist_k": 0.40, "resist_e": 0.15, "resist_x": -0.30, "dmg_type": "kinetic"
	},
	"z8_boss_warden": {
		"name": "Prismatic Warden",
		# v106: Late-game escalation pass — HP 2.39M→4M, ATK 23.9K→38K. Target ~10 min for tier-matched legendary.
		"stats": {"hp": 1400000, "max_shield": 29932, "atk": 12200, "def": 4489, "atk_interval": 2.5, "accuracy": 200},
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
		"module_drop_pool": ["z9_kinetic", "z9_energy", "z9_missile"],
		"xp": 11000, "eva": 25, "zone": 9, "resist_k": -0.15, "resist_e": -0.25, "resist_x": 0.25, "dmg_type": "energy"
	},
	"z9_quarantine_mech": {
		"name": "Quarantine Mech",
		"stats": {"hp": 437500, "atk": 7500, "def": 1800, "atk_interval": 3.5, "accuracy": 138},
		"loot": [["Neutronium", 1, 3], ["credits", 500000, 1000000], ["Res3", 5, 10]],
		"rare_loot": [["PathogenCore", 0.10, 1, 2]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z9_shield", "z9_armor"],
		"xp": 11500, "eva": 5, "zone": 9, "resist_k": 0.15, "resist_e": -0.30, "resist_x": 0.45, "dmg_type": "explosive"
	},
	"z9_boss_patient_zero": {
		"name": "Patient Zero",
		# v106: Late-game escalation pass — HP 5.93M→10M, ATK 56K→90K. Target ~12 min for tier-matched legendary, smoothing the ramp into Z10's 13 min finale.
		"stats": {"hp": 3500000, "max_shield": 65851, "atk": 23400, "def": 9877, "atk_interval": 2.5, "accuracy": 230},
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
		"loot": [["PrimordialShard", 1, 3], ["VoidEssence", 1, 2], ["CryoCatalyst", 1, 3], ["AeonResiduum", 3, 6]],  # v114: Z10 front signature raw
		"rare_loot": [["ChronoCore", 0.05, 1, 1]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z10_kinetic", "z10_energy", "z10_missile", "z10_shield", "z10_armor"],
		"xp": 25000, "eva": 25, "zone": 10, "resist_k": -0.30, "resist_e": 0.40, "resist_x": 0.0, "dmg_type": "kinetic"
	},
	"z10_temporal_phantom": {
		"name": "Temporal Phantom",
		"stats": {"hp": 528384, "max_shield": 200000, "atk": 18105, "def": 3627, "atk_interval": 1.5, "accuracy": 170},
		"loot": [["ChronoCore", 1, 2], ["VoidEssence", 2, 4], ["CryoCatalyst", 1, 3], ["AeonResiduum", 3, 6]],  # v114: Z10 front signature raw
		"rare_loot": [["PrimordialShard", 0.08, 1, 2]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z10_kinetic", "z10_energy", "z10_missile", "z10_shield", "z10_armor"],
		"xp": 30000, "eva": 35, "zone": 10, "resist_k": -0.30, "resist_e": 0.45, "resist_x": 0.0, "dmg_type": "energy"
	},
	"z10_omega_sentinel": {
		"name": "Omega Sentinel",
		"stats": {"hp": 600000, "max_shield": 180000, "atk": 16250, "def": 4000, "atk_interval": 2.5, "accuracy": 165},
		"loot": [["OmegaPlating", 1, 3], ["PrimordialShard", 1, 2], ["CryoCatalyst", 1, 3]],
		"rare_loot": [["VoidEssence", 0.10, 1, 3]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z10_kinetic", "z10_energy", "z10_missile"],
		"xp": 28000, "eva": 10, "zone": 10, "resist_k": -0.25, "resist_e": 0.30, "resist_x": 0.10, "dmg_type": "explosive"
	},
	"z10_primordial_titan": {
		"name": "Primordial Titan",
		"stats": {"hp": 1050000, "atk": 20000, "def": 3400, "atk_interval": 4.0, "accuracy": 158},
		"loot": [["PrimordialShard", 2, 5], ["credits", 5000000, 10000000], ["CryoCatalyst", 2, 4]],
		"rare_loot": [["OmegaPlating", 0.08, 1, 2]],
		"module_drop_chance": 0.10,
		"module_drop_pool": ["z10_shield", "z10_armor"],
		"xp": 32000, "eva": 5, "zone": 10, "resist_k": -0.15, "resist_e": 0.30, "resist_x": 0.15, "dmg_type": "kinetic"
	},
	"z10_boss_leviathan": {
		"name": "Void Leviathan",
		# v106: Final-boss credibility pass.
		#   ATK    130K→300K→200K   (first buff over-tuned; recalibrated to
		#                            ~54% over the trivial original — credible
		#                            threat, not instant death)
		#   HP     14.4M→30M→20M    (30M pushed optimal clear to ~19.5 min;
		#                            20M lands at ~13 min — climactic, not
		#                            endurance; off-meta still ~16 min penalty)
		#   res_e  0.45→0.65→0.55   (still punishes NRG-on-NRG-resist; survivable)
		# Boss stays WEAK KIN at −0.40 — swapping loadout is the real reward.
		"stats": {"hp": 7000000, "max_shield": 144872, "atk": 70200, "def": 21730, "atk_interval": 3.0, "accuracy": 250},
		"loot": [["credits", 50000000, 100000000], ["PrimordialShard", 20, 50], ["ChronoCore", 5, 12], ["CryoCatalyst", 10, 25]],
		"rare_loot": [["z10_unique_weapon", 0.03, 1, 1], ["z10_unique_armor", 0.03, 1, 1], ["z10_unique_shield", 0.03, 1, 1]],
		"boss_core": "Z10_Core",
		"module_drop_chance": 0.25,
		"module_drop_pool": ["z10_kinetic", "z10_energy", "z10_missile", "z10_shield", "z10_armor"],
		"is_boss": true, "xp": 500000, "eva": 25, "zone": 10, "resist_k": -0.40, "resist_e": 0.55, "resist_x": 0.0, "dmg_type": "energy"
	},

	# ═══ ZONE 11: The Threshold — WARP-HARDENED (Cryo-only). The Warp Gate. ═══
	# warp_hardened=true → conventional K/E/X damage is ~nullified in
	# resolve_damage; only Cryo (the first-Warp unlock) bites. resist_cryo
	# -0.25 = take 125% Cryo. Raw HP steps up from Z10, but the real wall is
	# the player's firepower collapsing to a single Cryo weapon until Z11
	# drops more (module_drop_pool = cryo_lance, rarity-rolled).
	"z11_warp_revenant": {
		"name": "Warp Revenant",
		"stats": {"hp": 1500000, "max_shield": 250000, "atk": 36000, "def": 7000, "atk_interval": 2.0, "accuracy": 180},
		"loot": [["ExoticMatter", 2, 5], ["PrimordialShard", 1, 3]],
		"rare_loot": [["ChronoCore", 0.08, 1, 2]],
		"module_drop_chance": 0.15,
		"module_drop_pool": ["cryo_lance"],
		"xp": 60000, "eva": 25, "zone": 11, "warp_hardened": true, "resist_k": 0.0, "resist_e": 0.0, "resist_x": 0.0, "resist_cryo": -0.25, "dmg_type": "energy"
	},
	"z11_phase_horror": {
		"name": "Phase Horror",
		"stats": {"hp": 2000000, "max_shield": 300000, "atk": 42000, "def": 8500, "atk_interval": 1.5, "accuracy": 190},
		"loot": [["ChronoCore", 2, 4], ["VoidEssence", 3, 6]],
		"rare_loot": [["OmegaPlating", 0.08, 1, 2]],
		"module_drop_chance": 0.15,
		"module_drop_pool": ["cryo_lance"],
		"xp": 70000, "eva": 35, "zone": 11, "warp_hardened": true, "resist_k": 0.0, "resist_e": 0.0, "resist_x": 0.0, "resist_cryo": -0.25, "dmg_type": "explosive"
	},
	"z11_null_sentinel": {
		"name": "Null Sentinel",
		"stats": {"hp": 2600000, "max_shield": 280000, "atk": 38000, "def": 10000, "atk_interval": 2.5, "accuracy": 185},
		"loot": [["OmegaPlating", 2, 4], ["PrimordialShard", 2, 4]],
		"rare_loot": [["VoidEssence", 0.10, 2, 4]],
		"module_drop_chance": 0.15,
		"module_drop_pool": ["cryo_lance"],
		"xp": 75000, "eva": 10, "zone": 11, "warp_hardened": true, "resist_k": 0.0, "resist_e": 0.0, "resist_x": 0.0, "resist_cryo": -0.25, "dmg_type": "kinetic"
	},
	"z11_exotic_leviathan": {
		"name": "Exotic Leviathan",
		"stats": {"hp": 3200000, "atk": 50000, "def": 8000, "atk_interval": 4.0, "accuracy": 175},
		"loot": [["PrimordialShard", 3, 6], ["credits", 20000000, 40000000]],
		"rare_loot": [["OmegaPlating", 0.10, 2, 3]],
		"module_drop_chance": 0.15,
		"module_drop_pool": ["cryo_lance"],
		"xp": 80000, "eva": 5, "zone": 11, "warp_hardened": true, "resist_k": 0.0, "resist_e": 0.0, "resist_x": 0.0, "resist_cryo": -0.25, "dmg_type": "kinetic"
	},
	"z11_boss_threshold_warden": {
		"name": "Threshold Warden",
		# v111: The Warp Gate boss. Cryo-only. With 3× crafted Cryo-Lance
		# (10K atk_cryo each, resist -0.25 → ×1.25) the first clear takes
		# ~19 min — tight, rewarding, and accelerated by Z11 regular drops.
		# Guaranteed Cryo-Lance drop on kill so the first clear upgrades a slot.
		"stats": {"hp": 22000000, "max_shield": 500000, "atk": 350000, "def": 52000, "atk_interval": 2.5, "accuracy": 260},
		"enrage_at": 0.5, "enrage_atk_mult": 1.5,  # v109: last-stand ATK surge below 50% HP — burst it down or out-sustain it
		"loot": [["credits", 100000000, 200000000], ["ExoticMatter", 30, 60], ["ChronoCore", 10, 20], ["PrimordialShard", 20, 40]],
		"rare_loot": [["cryo_lance", 1.0, 1, 1]],
		"module_drop_chance": 0.30,
		"module_drop_pool": ["cryo_lance"],
		"is_boss": true, "xp": 1000000, "eva": 20, "zone": 11, "warp_hardened": true, "resist_k": 0.0, "resist_e": 0.0, "resist_x": 0.0, "resist_cryo": -0.25, "dmg_type": "energy"
	},

	# ═══ ZONE 12: The Rift — CORROSION (NG+ WT2). Multi-phase boss gate. ═══
	# v113 (NG+ P3): trash are conventional (any weapon clears them) — their acid
	# DoT enemy-attack is a follow-up (needs the player-debuff hook), so for now
	# they use energy/kinetic/explosive dmg_type. The Rift Warden is the 2-phase
	# gate. resist_cryo stays 0.0: the exotic channel is shared by Cryo+Corrosion
	# weapons, so a per-element resist isn't possible yet — the PHASE gate is the
	# element puzzle. Numbers are first-pass; sim-tuned in P5.
	"z12_acid_revenant": {
		"name": "Acid Revenant",
		"stats": {"hp": 1800000, "max_shield": 300000, "atk": 90000, "def": 12000, "atk_interval": 2.0, "accuracy": 280},
		"loot": [["ExoticMatter", 3, 7], ["PrimordialShard", 2, 5]],
		"rare_loot": [["ChronoCore", 0.10, 1, 3]],
		"module_drop_chance": 0.12,
		"module_drop_pool": ["corrosion_blaster"],
		"xp": 120000, "eva": 30, "zone": 12, "resist_k": 0.0, "resist_e": 0.0, "resist_x": 0.0, "resist_cryo": 0.0, "dmg_type": "energy"
	},
	"z12_rust_horror": {
		"name": "Rust Horror",
		"stats": {"hp": 2400000, "max_shield": 350000, "atk": 100000, "def": 15000, "atk_interval": 1.5, "accuracy": 290},
		"loot": [["ChronoCore", 3, 6], ["VoidEssence", 4, 8]],
		"rare_loot": [["OmegaPlating", 0.10, 1, 3]],
		"module_drop_chance": 0.12,
		"module_drop_pool": ["corrosion_blaster"],
		"xp": 135000, "eva": 38, "zone": 12, "resist_k": 0.0, "resist_e": 0.0, "resist_x": 0.0, "resist_cryo": 0.0, "dmg_type": "explosive"
	},
	"z12_corrosion_sentinel": {
		"name": "Corrosion Sentinel",
		"stats": {"hp": 3000000, "max_shield": 320000, "atk": 95000, "def": 18000, "atk_interval": 2.5, "accuracy": 285},
		"loot": [["OmegaPlating", 3, 6], ["PrimordialShard", 3, 6]],
		"rare_loot": [["VoidEssence", 0.12, 2, 5]],
		"module_drop_chance": 0.12,
		"module_drop_pool": ["corrosion_blaster"],
		"xp": 145000, "eva": 12, "zone": 12, "resist_k": 0.0, "resist_e": 0.0, "resist_x": 0.0, "resist_cryo": 0.0, "dmg_type": "kinetic"
	},
	"z12_caustic_leviathan": {
		"name": "Caustic Leviathan",
		"stats": {"hp": 3600000, "atk": 120000, "def": 13000, "atk_interval": 4.0, "accuracy": 270},
		"loot": [["PrimordialShard", 4, 8], ["credits", 40000000, 80000000]],
		"rare_loot": [["OmegaPlating", 0.12, 2, 4]],
		"module_drop_chance": 0.12,
		"module_drop_pool": ["corrosion_blaster"],
		"xp": 155000, "eva": 5, "zone": 12, "resist_k": 0.0, "resist_e": 0.0, "resist_x": 0.0, "resist_cryo": 0.0, "dmg_type": "kinetic"
	},
	"z12_boss_rift_warden": {
		"name": "Rift Warden",
		# v113 (NG+ P3, WT2): the first MULTI-PHASE gate. Phase 1 hardens against
		# all-but-Cryo, phase 2 against all-but-Corrosion (each off-element ×0.15).
		# Phased bosses skip zone-steepening (base = effective). First clear is
		# ACTIVE: swap Cryo→Corrosion preset at the PHASE 2 telegraph. Guaranteed
		# Corrosion Blaster drop so the first clear arms you for the idle farm.
		"stats": {"hp": 50000000, "max_shield": 800000, "atk": 600000, "def": 70000, "atk_interval": 2.5, "accuracy": 300},
		"phases": ["cryo", "corrosion"], "phase_cut": 0.15,
		"relic_drop": "rift_relic",  # v113 (NG+ P2): guaranteed master key on first clear
		"enrage_at": 0.4, "enrage_atk_mult": 1.5,
		"loot": [["credits", 200000000, 400000000], ["ExoticMatter", 50, 100], ["ChronoCore", 20, 40], ["PrimordialShard", 40, 80]],
		"rare_loot": [["corrosion_blaster", 1.0, 1, 1]],
		"module_drop_chance": 0.30,
		"module_drop_pool": ["corrosion_blaster"],
		"is_boss": true, "xp": 2500000, "eva": 22, "zone": 12, "resist_k": 0.0, "resist_e": 0.0, "resist_x": 0.0, "resist_cryo": 0.0, "dmg_type": "energy"
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
		# v109: flag-gated zones (Z11 auto-unlocks on Z10 boss kill — no
		# research node). Hidden until the game_settings flag is set.
		var flag = data.get("unlock_flag", "")
		if flag != "" and not GameState.game_settings.get(flag, false):
			continue
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
	zone_entered.emit(zone_id)  # v128: fires "discover" mission progress (e.g. goal_001)
	in_combat = true
	session_loot.clear()
	combat_session_time = 0.0
	time_since_last_kill = 0.0
	spawn_enemy()
	player_shield = player_max_shield # FIX: Restore shields on enter
	shield_regen_accumulator = 0.0
	log_msg("Warped to %s." % current_zone["name"])

# ── v114: Zone Tier-Gate (front/back sector-hardening) — docs/ZONE_TIER_GATE.md ──
# A tier_hardened: Z enemy (the back-half e3/e4 + boss of Z2-Z10) floors SUB-TIER
# gear to TIER_FLOOR: offense (this weapon ~2% damage) AND defense (sub-tier
# armor/shield ~2% effective). Tier-Z gear pierces; a Unique exactly one zone below
# pierces too (jackpot skip-key). Forces a re-gear into the zone's common set.
# New-game-only via game_settings.tier_gate_enabled (old saves stay ungated).
const TIER_FLOOR := 0.02
var _tier_def_factor: float = 1.0     # armor multiplier vs the current hardened enemy (1.0 = ungated)
var _tier_shield_factor: float = 1.0  # shield-pool multiplier vs the current hardened enemy

func _tier_gate_on() -> bool:
	return bool(GameState.game_settings.get("tier_gate_enabled", false))

# Derived tier_hardened for an enemy by its position in the CURRENT zone roster:
# e3/e4 + boss of Z2-Z10 = the hardened back half (returns the zone difficulty);
# e1/e2 (front salvage), Z1 (bootstrap) and Z11+ (warp/exotic gate) return 0.
# Single source of truth for spawn_enemy AND the combat-page pre-fight badge.
# An explicit def `tier_hardened` still overrides at spawn time.
func get_enemy_tier_hardened(eid: String, zone_id_override: String = "") -> int:
	# zone_id_override lets the combat-page pre-fight list query a BROWSED zone
	# (current_zone is only set once a fight starts). Defaults to current_zone.
	var zone = current_zone
	if zone_id_override != "" and zone_id_override in zones:
		zone = zones[zone_id_override]
	if zone == null:
		return 0
	var zdiff: int = int(zone.get("difficulty", 1))
	if zdiff < 2 or zdiff > 10:
		return 0
	var roster: Array = zone.get("enemies", [])
	var is_back: bool = (roster.find(eid) >= 2) or bool(enemy_db.get(eid, {}).get("is_boss", false))
	return zdiff if is_back else 0

# Is this enemy the front-half salvage yard (e1/e2 of Z2-Z10)? Those drop materials
# only — no module rolls.
func enemy_is_front_salvage(eid: String, zone_id_override: String = "") -> bool:
	# zone_id_override mirrors get_enemy_tier_hardened — lets the pre-fight card query
	# a BROWSED zone (current_zone is only set once a fight starts).
	var zone = current_zone
	if zone_id_override != "" and zone_id_override in zones:
		zone = zones[zone_id_override]
	if zone == null:
		return false
	var zdiff: int = int(zone.get("difficulty", 1))
	if zdiff < 2 or zdiff > 10:
		return false
	var idx: int = (zone.get("enemies", []) as Array).find(eid)
	return idx >= 0 and idx < 2 and not bool(enemy_db.get(eid, {}).get("is_boss", false))

func set_target_enemy(enemy_id):
	# v62.0 Fix: Prevent crash if current_zone is null
	if current_zone == null:
		return

	var sm = GameState.shipyard_manager
	if sm and sm.current_hp <= 0:
		log_msg("SYSTEM CRITICAL: Hull integrity at 0%. Repairs required before engaging.")
		return

	# v110: whole-ship power gate. If the battery banks can't cover the total
	# module draw, the ship can't operate in combat at all (not just per-weapon
	# fail). Block entry with a clear pointer to the fix.
	if sm and sm.energy_used > sm.energy_capacity:
		log_msg("SHIP UNPOWERED: battery capacity %d < power draw %d. Equip more (or higher-tier) Battery modules." % [int(sm.energy_capacity), int(sm.energy_used)])
		UITheme.show_notification("⚡ SHIP UNPOWERED — equip Battery modules to cover your power draw (%d / %d)." % [int(sm.energy_used), int(sm.energy_capacity)], Color(1.0, 0.45, 0.35))
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
		"resist_cryo": e_data.get("resist_cryo", 0.0),       # v109: 4th type
		"warp_hardened": e_data.get("warp_hardened", false), # v109: Z11 Cryo gate
		"phases": e_data.get("phases", []),                  # v113 (NG+ P1): multi-phase element gate
		"phase_cut": e_data.get("phase_cut", 0.15),          # v113: off-element damage factor
		"tier_hardened": e_data.get("tier_hardened", get_enemy_tier_hardened(eid)),     # v114: derived from zone position (def overrides)
		"drops_modules": e_data.get("drops_modules", not enemy_is_front_salvage(eid)),  # v114: front half (e1/e2) → materials only
		"enrage_at": e_data.get("enrage_at", 0.0),           # v109: P3 boss mechanic (HP fraction)
		"enrage_atk_mult": e_data.get("enrage_atk_mult", 1.5),
		"dmg_type": e_data.get("dmg_type", "kinetic") # v87.0: Typed enemy damage
	}
	_enemy_enraged = false  # v109: reset per-fight enrage state on spawn
	_current_phase_idx = -1  # v113 (NG+ P1): reset phase band so the opening phase telegraphs
	
	# v103b: Static zone-gap steepening (zone 3+). A complete sub-zone gear/set
	# out-DPSes later content otherwise; both regular enemies AND bosses scale.
	# Zones 1-2 untouched (early game stays gentle). First-pass curve — tune the
	# two _zhp / _zdef knobs from playtest.
	var _ezone := int(e_data.get("zone", current_zone.get("difficulty", 1)))
	# v109: warp_hardened (Z11+) enemies skip zone-steepening — their gate is
	# the Cryo requirement, not inflated stats. Base stats ARE the intended
	# effective values (only the bounded ENEMY_COMP catch-up below applies),
	# which keeps Z11 tuning predictable instead of ×3.7-ballooned.
	if _ezone >= 3 and not e_data.get("warp_hardened", false) and (e_data.get("phases", []) as Array).is_empty():
		# v120: SOFT-GATE recalibration. The old v103c curve (atk 1.7→3.1×) was
		# tuned assuming the player carries core/affix EHP — a freshly-crafted
		# CLEAN current-tier Common (the intended back-half solution) couldn't
		# survive it from z6 on (sim-confirmed). Eased so a clean Common clears
		# the back half at every zone; the gate now lives in the Common's raw
		# tier-step lead over a (lower-base) carried N-1 Legendary, not in
		# enemy ATK that only core-EHP gear can outlast. Tune vs gating_spike.
		# Rises through z8, then PLATEAUS: past z8 the ATK ramp outpaced what a
		# sustain-less clean Common can tank (it died at z9/z10 e3 while a carried
		# Legendary's heal-on-hit affixes outlasted it — inverting the cycle). The
		# cap holds z9-z10 at z8's Common-survivable level; the late-game gate is
		# the boss + the warp wall (Z11), not ever-climbing regular ATK.
		var _zhp: float = min(2.10, 1.45 + 0.13 * float(_ezone - 3))  # z3 ≈1.45× … z8+ ≈2.10×
		var _zdef: float = 1.5                                        # 0.80 mitig clamp keeps it killable
		var _zatk: float = min(1.95, 1.45 + 0.10 * float(_ezone - 3)) # z3 ≈1.45× … z8+ ≈1.95×
		current_enemy["max_hp"] = int(current_enemy["max_hp"] * _zhp)
		current_enemy["def"] = int(current_enemy["def"] * _zdef)
		current_enemy["atk"] = int(current_enemy["atk"] * _zatk)

	# v103: Measured progression compensation. Enemies scale ONLY against the
	# player's *external grind* multiplier (combat level + warp), NOT gear —
	# so leveling/warping can't trivialize a zone with old modules, but better
	# gear is still the real lever to out-power content. Partial catch-up via
	# the ENEMY_COMP_* fractions (<0.5), so zone pacing stays readable.
	var _is_boss := bool(current_enemy.get("is_boss", false))
	# v120: combat leveling removed — enemies scale ONLY against the warp grind
	# multiplier now (better gear, not combat XP, is the lever that out-powers a zone).
	var _ext_mult: float = 1.0
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
	
	_rebuild_player_weapon_states()

	# v120: tier-hardening defense floor removed — no sub-tier armor/shield collapse.
	# Kept as 1.0 no-op multipliers so the resolve_damage call sites and shield-pool
	# math below are untouched.
	_tier_def_factor = 1.0
	_tier_shield_factor = 1.0

# v113 (NG+ P2): rebuild the per-fight weapon snapshot from the CURRENT loadout.
# Called on enemy spawn AND on an in-fight loadout swap (multi-phase boss gate),
# so both paths share one code path. Resets weapon timers (fresh fire schedule).
func _rebuild_player_weapon_states() -> void:
	var sm = GameState.shipyard_manager
	player_max_shield = sm.max_shield
	player_weapon_states.clear()
	var equipped_weapons = []

	# v119: Engineering skill no longer buffs weapon damage — combat damage is
	# loadout/warp/research-driven (matches the balance model the sims use).

	for s_idx in sm.loadout:
		var mid = sm.loadout[s_idx]
		if mid and mid in sm.modules:
			var m_data = sm.modules[mid]
			if m_data.get("slot_type") == "weapon":
				var m_stats = m_data.get("stats", {})
				var w_type = "kinetic"
				if m_stats.get("atk_energy", 0) > 0: w_type = "energy"
				elif m_stats.get("atk_explosive", 0) > 0: w_type = "explosive"
				elif m_stats.get("atk_cryo", 0) > 0: w_type = "cryo"  # v109: 4th type

				equipped_weapons.append({
					"name": m_data["name"],
					"type": w_type,
					# v114: tier-gate identity for the offense floor (see _execute_player_attack).
					"mid": mid,
					"tier": sm.get_module_tier(mid),
					"rarity": sm.get_module_rarity(mid),
					# v113 (NG+ P2): exotic subtype for the multi-phase gate. Cryo
					# weapons default "cryo"; future elements (corrosion/thermal/…)
					# set stats.exotic_element. Only consulted for the exotic channel.
					"exotic_type": str(m_stats.get("exotic_element", "cryo")),
					"timer": randf_range(0.0, 0.5),
					"interval": m_stats.get("atk_interval", 2.5),
					# v107: Warp Mastery Tree — C2 Weapon Tuning (+10% module damage)
					"dmg_k": m_stats.get("atk_kinetic", 0) * GameState.warp_manager.get_tree_damage_bonus(),
					"dmg_e": m_stats.get("atk_energy", 0) * GameState.warp_manager.get_tree_damage_bonus(),
					"dmg_x": m_stats.get("atk_explosive", 0) * GameState.warp_manager.get_tree_damage_bonus(),
					"dmg_cryo": m_stats.get("atk_cryo", 0) * GameState.warp_manager.get_tree_damage_bonus(),  # cryo uses the general damage bonus (Cryo Overcharge node removed)
					"slot_idx": int(s_idx),
					"energy_load": m_stats.get("energy_load", 0)
				})
	player_weapon_states.append_array(equipped_weapons)
	log_msg("Readying Weapon Battery: %d systems online." % player_weapon_states.size())

# v113 (NG+ P2): the in-fight loadout swap — the active gate for multi-phase
# bosses. The auto-battler contract forbids in-FIGHT inputs EXCEPT this, and only
# against a multi-phase boss (each phase demands a different element; you swap to
# the matching preset). Re-equips the preset, resyncs combat-relevant ship stats,
# then rebuilds the weapon snapshot. Cost: weapon cooldowns reset (a fair tempo
# hit) — NO free heal (current HP/shield untouched). Returns true if it applied.
func swap_loadout_in_combat(preset_idx: int) -> bool:
	if not can_swap_loadout_in_combat():
		return false
	var sm = GameState.shipyard_manager
	if sm.is_loadout_preset_empty(preset_idx):
		return false
	var res = sm.load_loadout_preset(preset_idx)
	if int(res.get("loaded", 0)) <= 0:
		return false
	# Resync the combat-relevant ship state from the new loadout (set bonuses,
	# unique-module flags, safety caps), then the weapon snapshot.
	_apply_trinity_stat_bonuses(sm)
	apply_safety_caps()
	active_trinity_sets = _get_active_trinity_sets()
	has_reflective = _loadout_has_module(sm, "reflective_sheath")
	has_reactive = _loadout_has_module(sm, "reactive_armor")
	has_exotic_matrix = _loadout_has_module(sm, "exotic_shield_matrix")
	_rebuild_player_weapon_states()
	combat_events.append({"type": "status", "text": "⟳ LOADOUT SWAPPED", "color": Color(0.70, 0.95, 1.0), "side": "player"})
	log_msg("Reconfigured loadout mid-engagement — weapon battery recalibrating.")
	return true

# v113 (NG+ P2): the swap is only legal against a multi-phase boss (the locked
# exception to "no in-fight inputs"). Single-phase / warp_hardened / normal
# enemies never expose it — the auto-battler contract stays intact everywhere else.
func can_swap_loadout_in_combat() -> bool:
	if not in_combat or current_enemy == null:
		return false
	return (current_enemy.get("phases", []) as Array).size() > 1

func retreat():
	in_combat = false
	current_enemy = null
	consumable_cooldown = 0.0   # v124: clear so out-of-combat repair-kit buttons aren't stuck disabled by a stale cooldown
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
	# v120 FIX: this was '=' reading a bogus affix_bonuses["accuracy"] key (no such key →
	# always 0.0), which WIPED the recalc'd accuracy (base 100 + sensors + gem accuracy_flat)
	# on every combat entry — flooring hit chance at ~20% game-wide and making late zones
	# unkillable. Now additive, matching the def/crit/evasion set-bonus lines above.
	sm.accuracy += _get_set_bonus_value("accuracy_flat")
	
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
	
	# v65.0 Fix: Enemy Shield Regen moved to generic accumulator and Capped (Removed old logic)

	if _loadout_has_module(sm, "warp_stabilizer"):
		p_speed_mult += 0.15

	# Servo Overclock: flat attack-speed affix.
	if sm.affix_bonuses.get("servo_overclock", 0.0) > 0:
		p_speed_mult += sm.affix_bonuses["servo_overclock"]

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

	# P0 Hotfix: Grid Safety Check (Prevent Overload Exploit)
	# v110: read the ship's own energy_capacity (decoupled from the infra grid).
	if sm.energy_used > sm.energy_capacity:
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
	var p_atk_cryo = w.get("dmg_cryo", 0.0)  # v109
	if w["type"] == "energy" and _loadout_has_module(sm, "plasma_overcharger"):
		p_atk_e *= 2.0

	var ammo_id = sm.ammo_loadout.get(w["slot_idx"])
	# v109: Cryo weapons are Exotic-Matter self-charging — no ammo required.
	var requires_ammo = w["slot_idx"] != -1 and w["type"] != "cryo"
	
	# v80.2 Fix: Enforce Ammo Type Compatibility
	if ammo_id and ammo_id != "" and not sm.is_ammo_compatible(w["type"], ammo_id):
		ammo_id = "" # Ignore incompatible ammo
		
	if ammo_id and ammo_id != "":
		if GameState.resources.get_element_amount(ammo_id) > 0:
			# v118: Crimson ammo_eff (utility facet) — chance to not consume ammo.
			if randf() >= sm.gem_bonuses.get("ammo_eff", 0.0):
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
	# v112 Fleet P2 (soft role): the warp-built fleet adds 0.25x/ship of the main
	# ship's damage, capped at +100% — the surplus-on-top accelerator from the
	# design doc. 1.0 (no-op) when locked/empty, so pre-warp combat is unchanged.
	var fleet_dmg_mult := 1.0
	if GameState.fleet_manager:
		fleet_dmg_mult = GameState.fleet_manager.get_combat_dps_mult()
	# v120: combat leveling removed — the (1.0 + level*0.005) term is gone. Player
	# combat power now comes from gear + warp + research, never from a combat XP bar.
	var skill_dmg_mult = GameState.warp_manager.get_combat_multiplier() * (1.0 + combat_dmg_bonus) * (1.0 + void_weap_bonus) * fleet_dmg_mult
	
	# v80.1: Trinity Damage Multipliers
	var trinity_atk_mult = 1.0 + (_get_set_bonus_value("atk_pct") + _get_set_bonus_value("all_dmg_pct")) / 100.0
	var trinity_energy_mult = 1.0 + _get_set_bonus_value("energy_dmg_pct") / 100.0
	var trinity_missile_mult = 1.0 + _get_set_bonus_value("missile_dmg_pct") / 100.0
	
	p_atk_k *= skill_dmg_mult * trinity_atk_mult
	p_atk_e *= skill_dmg_mult * trinity_atk_mult * trinity_energy_mult
	p_atk_x *= skill_dmg_mult * trinity_atk_mult * trinity_missile_mult
	p_atk_cryo *= skill_dmg_mult * trinity_atk_mult  # v109

	# v120: tier-hardening offense floor removed — the soft numeric gate (rarity
	# curve + per-zone enemy tuning) drives progression now; no per-tier damage
	# penalty. (Warp-Hardened Z11 Cryo wall is separate, in resolve_damage.)

	var total_crit = sm.crit_chance + get_milestone_crit_bonus()
	var res = resolve_damage(p_atk_k, p_atk_e, p_atk_x, enemy_shield, current_enemy["def"], current_zone.get("difficulty", 1), total_crit, true, p_atk_cryo, w.get("exotic_type", "cryo"))
	enemy_shield = max(0, enemy_shield - res[0])
	enemy_hp -= res[1]
	_check_phase_transition()  # v113 (NG+ P1): telegraph if this hit crossed an HP band

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

# v113 (NG+ P1): which HP band (phase) is the boss in right now? Full HP → phase
# 0, near-death → phase n-1. Even split: with n phases each band is 1/n of HP.
func _phase_index(n: int) -> int:
	if n <= 1 or enemy_max_hp <= 0:
		return 0
	var frac: float = clampf(float(enemy_hp) / float(enemy_max_hp), 0.0, 1.0)
	return clampi(int((1.0 - frac) * float(n)), 0, n - 1)

# v113 (NG+ P1): per-channel damage multipliers for the boss phase-gate. This is
# the generalization of the Z11 warp_hardened Cryo wall. A boss with a `phases`
# list (e.g. ["cryo","corrosion","thermal"]) splits its HP into N bands; in the
# current band only that phase's element deals full damage, every other channel
# is cut to `phase_cut` (default 0.15). warp_hardened stays its own binary branch
# (Cryo-only, ×0.02) so Z11 behaviour is byte-identical. Player attacks only;
# enemy attacks + non-gated enemies always return all-1.0 (combat unchanged).
# An element with no weapon channel yet (corrosion/thermal/radiation/graviton)
# matches nothing → that whole band is cut, i.e. unbeatable until P3 ships the
# weapon — the intended forward gate.
func _get_breach_factors(is_player_attacker: bool, weapon_exotic: String = "cryo") -> Dictionary:
	if not is_player_attacker or current_enemy == null:
		return {"k": 1.0, "e": 1.0, "x": 1.0, "cryo": 1.0}
	# Z11 binary gate: conventional ×0.02; the exotic channel breaches only if the
	# weapon's exotic type is Cryo (the first-warp unlock). At first warp Cryo is
	# the only exotic that exists, so this stays byte-identical to shipped Z11.
	if current_enemy.get("warp_hardened", false):
		return {"k": 0.02, "e": 0.02, "x": 0.02, "cryo": 1.0 if weapon_exotic == "cryo" else 0.02}
	# NG+ multi-phase gate. The exotic channel is full only when the attacking
	# weapon's exotic type matches the current phase element (cryo vs corrosion vs
	# thermal …) — so a Cryo loadout does NOT breach a Corrosion phase. This is the
	# forcing function behind the loadout-preset swap: bring the right element.
	var phases: Array = current_enemy.get("phases", [])
	if phases.is_empty():
		return {"k": 1.0, "e": 1.0, "x": 1.0, "cryo": 1.0}
	var breach: String = str(phases[_phase_index(phases.size())]).to_lower()
	var cut: float = float(current_enemy.get("phase_cut", 0.15))
	return {
		"k": 1.0 if breach == "kinetic" else cut,
		"e": 1.0 if breach == "energy" else cut,
		"x": 1.0 if breach == "explosive" else cut,
		"cryo": 1.0 if breach == weapon_exotic else cut,
	}

# v113 (NG+ P1): multi-phase boss telegraph. Mirrors _check_enrage — fires once
# each time the boss crosses into a new HP band, announcing which element now
# breaches. Pure feedback; the gate itself is recomputed live in resolve_damage.
# Solvable by pre-fight loadout only (bring every phase's element), honouring the
# auto-battler contract. Single-phase / warp_hardened enemies never transition.
func _check_phase_transition() -> void:
	if current_enemy == null:
		return
	var phases: Array = current_enemy.get("phases", [])
	if phases.size() <= 1 or enemy_max_hp <= 0:
		return
	var idx := _phase_index(phases.size())
	if idx == _current_phase_idx:
		return
	_current_phase_idx = idx
	var elem: String = str(phases[idx]).to_upper()
	combat_events.append({"type": "status", "text": "⚠ PHASE %d — %s-HARDENED" % [idx + 1, elem], "color": Color(0.70, 0.95, 1.0), "side": "enemy"})
	log_msg("%s — PHASE %d: only %s armaments breach it now." % [current_enemy.get("name", "Target"), idx + 1, elem.capitalize()])

# v109: P3 boss mechanic — Enrage. When the enemy's HP first crosses below its
# enrage_at fraction, it permanently surges ATK by enrage_atk_mult for the rest
# of the fight. Telegraphed once. Solvable purely by pre-fight loadout: bring
# enough Cryo burst to skip the window, or enough hull/consumables to outlast it
# (no in-fight input — honours the auto-battler contract). Data-driven via the
# enrage_at / enrage_atk_mult fields on any enemy (currently Threshold Warden).
func _check_enrage() -> void:
	if _enemy_enraged or current_enemy == null:
		return
	var thr := float(current_enemy.get("enrage_at", 0.0))
	if thr <= 0.0 or enemy_max_hp <= 0:
		return
	if float(enemy_hp) / float(enemy_max_hp) <= thr:
		_enemy_enraged = true
		var mult := float(current_enemy.get("enrage_atk_mult", 1.5))
		combat_events.append({"type": "status", "text": "⚠ ENRAGED — ATK ×%.1f" % mult, "color": Color(1.0, 0.35, 0.20), "side": "enemy"})
		log_msg("%s has ENRAGED — incoming damage surging." % current_enemy.get("name", "Target"))

func _execute_enemy_attack():
	var sm = GameState.shipyard_manager
	_check_enrage()  # v109: re-evaluate enrage before this swing (telegraph + buff)
	var e_acc = current_enemy.get("accuracy", 0)
	var total_eva = sm.evasion + get_milestone_evasion_bonus()
	var dodge_chance = min(float(total_eva) / (float(total_eva) + 150.0 * (1.0 + float(e_acc) / 100.0)), 0.75)
	if randf() < dodge_chance:
		combat_events.append({"type": "miss", "text": "MISS", "color": Color.WHITE, "side": "player"})
	else:
		var difficulty = current_zone.get("difficulty", 1)
		# v87.0: Enemy uses typed damage channels
		var e_atk = current_enemy["atk"]
		if _enemy_enraged:
			e_atk = int(e_atk * float(current_enemy.get("enrage_atk_mult", 1.5)))  # v109
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
		# v127: player per-type damage RESISTANCE. Only the enemy's active type
		# is non-zero, so this scales the incoming hit by the matching resist
		# (0 by default -> neutral). Summed from modules & capped 0.75 in recalc_stats.
		e_atk_k = e_atk_k * (1.0 - sm.resist_k)
		e_atk_e = e_atk_e * (1.0 - sm.resist_e)
		e_atk_x = e_atk_x * (1.0 - sm.resist_x)
		# Enemy uses base crit 5%
		var eres = resolve_damage(e_atk_k, e_atk_e, e_atk_x, player_shield, sm.defense * _tier_def_factor, difficulty, 0.05, false)
		
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

		# v113 (NG+ P2): Threshold Relic — the master key. Equipped IN its keyed
		# zone, it slashes incoming damage so the gate boss is survivable enough
		# to idle-farm (the "active first clear, then farm" payoff). Inert in any
		# other zone, so it never becomes a universal god-item.
		var _relic_f: float = sm.get_relic_reduction_factor(current_zone_id)
		if _relic_f < 1.0:
			eres[0] = int(eres[0] * _relic_f)
			eres[1] = int(eres[1] * _relic_f)

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

# v116: amplify authored damage-type RESISTANCES toward an 80% wall so the wrong
# damage type is a ~5x TTK penalty (forces type-switching), while WEAKNESSES keep
# their authored value. The authored data maxes at 0.45, so a flat clamp bump did
# nothing -- this scales the positive side up (0.45 -> 0.80) and preserves the
# triangle's spread. Soft axis (x0.20 is still grindable in idle); the HARD gate
# stays the tier-penetration wall (don't double-hard-gate tier AND type).
const RESIST_AMP := 1.78    # 0.45 (authored max) * 1.78 ~= 0.80
const RESIST_MAX := 0.80
func _amp_resist(r: float) -> float:
	if r > 0.0:
		return clamp(r * RESIST_AMP, 0.0, RESIST_MAX)
	return clamp(r, -0.40, 0.0)

func resolve_damage(atk_k, atk_e, atk_x, c_shield, c_armor, difficulty = 1, crit_chance = 0.05, is_player_attacker = false, atk_cryo = 0.0, p_weapon_exotic = "cryo"):
	# v109 Phase 1: Cryo is the 4th damage type. Inert until Cryo weapons ship
	# (Phase 2) — atk_cryo / resist_cryo / warp_hardened all default to
	# 0/0/false, so existing K/E/X combat is mathematically unchanged.
	# Warp-Hardened (Z11+) enemies near-nullify conventional damage (×0.02);
	# only Cryo bites — this is the mechanical prestige gate.
	# v113 (NG+ P1): boss phase-gate per-channel factors. Generalizes the Z11
	# warp_hardened binary Cryo wall into a data-driven per-phase element gate
	# (see _get_breach_factors). All 1.0 for non-gated enemies AND every enemy
	# attack, so conventional K/E/X combat is mathematically unchanged.
	var _bf := _get_breach_factors(is_player_attacker, str(p_weapon_exotic))
	var _f_k: float = _bf["k"]
	var _f_e: float = _bf["e"]
	var _f_x: float = _bf["x"]
	var _f_cryo: float = _bf["cryo"]
	var shield_dmg_pot = (atk_k * 0.5 * _f_k) + (atk_e * 1.5 * _f_e) + (atk_x * 1.1 * _f_x) + (atk_cryo * 1.0 * _f_cryo)
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
	var arm_cryo = c_armor * 0.5  # v109: Cryo penetration sits between Energy and Explosive
	
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
	var hull_dmg_cryo = atk_cryo * 1.0 * max(_min_factor, 1.0 - arm_cryo / (arm_cryo + k))  # v109
	
	# v86.0: Enemy Damage Type Resistances
	if is_player_attacker and current_enemy:
		var rk = _amp_resist(current_enemy.get("resist_k", 0.0))
		var re = _amp_resist(current_enemy.get("resist_e", 0.0))
		var rx = _amp_resist(current_enemy.get("resist_x", 0.0))
		# v118: Amethyst resist_pierce softens the resist gate — shave positive
		# resistances toward 0 (capped 0.30), never flips a weakness. 0.80 -> min 0.50,
		# so the wrong type stays a penalty and switching is still worthwhile.
		var _rp: float = clampf(sm.gem_bonuses.get("resist_pierce", 0.0), 0.0, 0.30)
		if _rp > 0.0:
			if rk > 0.0: rk = maxf(rk - _rp, 0.0)
			if re > 0.0: re = maxf(re - _rp, 0.0)
			if rx > 0.0: rx = maxf(rx - _rp, 0.0)
		# Phase A: capture per-type pre/post-resist so we can see whether
		# players actually adapt their damage type to the enemy.
		GameState.note_damage(hull_dmg_k, hull_dmg_e, hull_dmg_x,
			hull_dmg_k * (1.0 - rk), hull_dmg_e * (1.0 - re), hull_dmg_x * (1.0 - rx))
		hull_dmg_k *= (1.0 - rk)
		hull_dmg_e *= (1.0 - re)
		hull_dmg_x *= (1.0 - rx)
		# v109: Cryo resist (defaults 0). Z11 warp_hardened enemies set
		# resist_cryo ~ -0.25 (weak), so Cryo over-performs against them.
		var rc = clamp(current_enemy.get("resist_cryo", 0.0), -0.40, 0.50)
		hull_dmg_cryo *= (1.0 - rc)
		# v113 (NG+ P1): apply the phase-gate per-channel factors AFTER the resist
		# clamp so the gate bypasses the 50% resist ceiling — a hard mechanical
		# wall, not armor. warp_hardened → k/e/x ×0.02, cryo full (Z11, unchanged);
		# NG+ phases → off-element channels ×phase_cut. Non-gated enemies: all 1.0.
		hull_dmg_k *= _f_k
		hull_dmg_e *= _f_e
		hull_dmg_x *= _f_x
		hull_dmg_cryo *= _f_cryo

	var total_hull_dmg = (hull_dmg_k + hull_dmg_e + hull_dmg_x + hull_dmg_cryo) * bleed_ratio
	
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
	
	# v118: Crimson damage_reduction (defense facet) — flat % off incoming damage
	# when the ENEMY attacks. Capped 0.50 so a full set can't trivialize defense.
	if not is_player_attacker:
		var _dr: float = clampf(sm.gem_bonuses.get("damage_reduction", 0.0), 0.0, 0.50)
		if _dr > 0.0:
			total_hull_dmg *= (1.0 - _dr)
			damage_to_shield *= (1.0 - _dr)
	var variance = randf_range(0.9, 1.1)
	var is_crit = randf() < crit_chance
	# v118: Crimson crit_damage (weapon facet) boosts the player's crit multiplier
	# (base 1.5x). Player attacks only.
	if is_crit:
		variance *= (1.5 + (sm.gem_bonuses.get("crit_damage", 0.0) if is_player_attacker else 0.0))
	return [int(damage_to_shield * variance), int(max(1.0 if (atk_k + atk_e + atk_x) > 0 else 0, total_hull_dmg * variance)), is_crit]

# v101: Combat Loot Scaling System
# Ensures combat resource drops keep pace with gathering/processing progression
func get_combat_loot_multiplier() -> float:
	var mult = 1.0
	
	# Zone Difficulty bonus (+15% per zone tier above 1). The old +1%/combat-level
	# loot bonus was dropped with combat leveling — gear + zone tier drive loot now.
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

# v109: Recursion — Recursive Acquisition (+5%/level Lira rewards). Applied
# to combat credit drops (online + offline); quest_manager / bounty_manager
# apply the same bonus to their own reward paths.
func _credit_reward_mult() -> float:
	if GameState.research_manager:
		return 1.0 + GameState.research_manager.get_efficiency_bonus("credit_reward_mult")
	return 1.0

func get_effective_module_drop_chance(enemy_data: Dictionary) -> float:
	var base = enemy_data.get("module_drop_chance", 0.0)
	if base <= 0: return 0.0

	# v109: Accuracy NO LONGER affects drop rate. The old (accuracy-100)/400
	# bonus was uncapped and turned drops into a firehose at high accuracy
	# (×3 at 900 acc, guaranteed past ~2100). Drop chance is now the enemy's
	# flat base, modified ONLY by the bounded Xeno-Engineering research node
	# (a deliberate +rare-loot investment).
	var rm = GameState.research_manager
	var xeno_bonus = rm.get_efficiency_bonus("xeno_engineering") if rm else 0.0
	# v128: Sensor "Salvage Scanner" affix (module_drop_mult) — the only per-slot
	# multiplier on module drop chance. Bounded (max GA ~0.30 per affix).
	var sm = GameState.shipyard_manager
	var salvage = sm.affix_bonuses.get("module_drop_mult", 0.0) if sm else 0.0
	return base * (1.0 + xeno_bonus) * (1.0 + salvage)

# Weighted pick over a drop pool using MODULE_DROP_WEIGHTS by slot type.
# Entries whose slot type has weight <= 0 (e.g. battery) can never drop,
# even if present in an enemy's pool. Returns "" if nothing is eligible.
# v109: Roll a single MODULE drop — rarity roll → weighted base pick → loot
# filter → generate. Extracted so bosses can call it 4-10× for a loot burst.
# Touches modules only (never currency/materials/boss cores). Honours the loot
# filter: a roll whose rarity/type is filtered out is skipped ("only loot you
# keep is rolled").
func _roll_one_module_drop(unlocked_pool: Array, sm) -> void:
	var is_boss = current_enemy.get("is_boss", false)
	var rarity = sm.roll_rarity(is_boss)
	var base_id = _pick_weighted_base(unlocked_pool, sm)
	if base_id == "":
		return
	var m_data = sm.modules.get(base_id, {})
	var slot_type = m_data.get("slot_type", "weapon")
	var is_rarity_ok = loot_filter.get(rarity, true)
	var is_type_ok = loot_type_filter.get(slot_type, true)
	# Weapon sub-filter by damage type (cryo > energy > explosive > kinetic).
	if is_type_ok and slot_type == "weapon":
		var wstats = m_data.get("stats", {})
		var wtype = "kinetic"
		if float(wstats.get("atk_cryo", 0)) > 0.0:
			wtype = "cryo"
		elif float(wstats.get("atk_energy", 0)) > 0.0:
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
		log_msg("Filtered out %s (%s) module drop." % [sm.RARITY_LABELS.get(rarity, "Common"), slot_type.capitalize()])

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

# v127 H4: centralized Hack Stone drop roll — research-gated (firmware_hacking) +
# zone-tiered, so ONE place governs it instead of editing every enemy's rare_loot.
# Rates per docs/design/HACK_STONES.md. Bosses guarantee an Injector; boss/elite
# feed Root Key. Only fires once firmware_hacking is researched (~Z3-era gate).
func _roll_hack_stone_drops(zone: int, is_boss: bool, is_elite: bool) -> void:
	var rm = GameState.research_manager
	if not rm or not rm.is_tech_unlocked("firmware_hacking"):
		return
	var res = GameState.resources
	# v128: Sensor "Cryptographic Decoder" affix (stone_drop_mult) scales the RANDOM
	# roll only — boss-guaranteed drops (Injector) stay guaranteed. Bounded (GA ~0.40).
	var sm_s = GameState.shipyard_manager
	var smult = 1.0 + (sm_s.affix_bonuses.get("stone_drop_mult", 0.0) if sm_s else 0.0)
	# Q1: Recursion "Cryptographic Cache" warp node scales the RANDOM roll only —
	# boss-guaranteed drops (Injector, Calibrator@Z6+) stay guaranteed.
	var wm_s = GameState.warp_manager
	if wm_s:
		smult *= (1.0 + wm_s.get_tree_card_drop_bonus())
	var got: Array = []
	if zone >= 1 and randf() < 0.25 * smult:
		res.add_element("SpliceChip", 1)
		got.append("Splice Chip")
	if zone >= 2 and (is_boss or randf() < 0.12 * smult):
		res.add_element("FirmwareInjector", 1)
		got.append("Firmware Injector")
	if zone >= 3 and ((is_boss and randf() < 0.08 * smult) or (is_elite and randf() < 0.06 * smult)):
		res.add_element("RootKey", 1)
		got.append("Root Key")
	if zone >= 4 and randf() < 0.015 * smult:
		res.add_element("AnchorBolt", 1)
		got.append("Anchor Bolt")
	if zone >= 5 and randf() < 0.05 * smult:
		res.add_element("CorruptionWorm", 1)
		got.append("Corruption Worm")
	if zone >= 4 and randf() < 0.05 * smult:
		res.add_element("RefitBay", 1)
		got.append("Refit Bay")
	# v128: Signal Calibrator — the D30 value-reroll faucet. Boss-guaranteed Z6+ (bypasses
	# smult) so the refine supply lands exactly when players have an affix set to GA-fish.
	if zone >= 6 and (is_boss or randf() < 0.03 * smult):
		res.add_element("SignalCalibrator", 1)
		got.append("Signal Calibrator")
	if not got.is_empty():
		combat_events.append({"type": "loot", "text": "HACK CARD: %s" % ", ".join(PackedStringArray(got)), "color": Color(0.60, 0.85, 1.0), "side": "enemy"})

func win_fight():
	log_msg("Destroyed %s!" % current_enemy["name"])
	
	# v101: Combat Loot Scaling — loot now grows with progression
	var loot_mult = get_combat_loot_multiplier()
	# v128: Sensor "Prospector Array" affix (enemy_drop_mult) — scales ALL enemy
	# loot quantity (elements + Liras). Bounded (max GA ~0.20 per affix).
	var sm_loot = GameState.shipyard_manager
	if sm_loot:
		loot_mult *= (1.0 + sm_loot.affix_bonuses.get("enemy_drop_mult", 0.0))

	for entry in current_enemy["loot"]:
		var base_qty = randi_range(entry[1], entry[2])
		var qty = int(ceil(float(base_qty) * loot_mult))
		if entry[0] == "credits":
			qty = int(qty * _credit_reward_mult())  # v109 Recursive Acquisition
			GameState.resources.add_currency("credits", qty)
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
		# v109: Z10 boss kill auto-unlocks Zone 11 "The Threshold" (the Warp
		# Gate). Signposts that Warping is now the path — and what it grants.
		if core_id == "Z10_Core" and not GameState.game_settings.get("z10_cleared", false) and not GameState.game_settings.get("z11_unlocked", false):
			GameState.game_settings["z10_cleared"] = true  # v113: Z11 now unlocks on the NEXT Warp (directs the player to prestige), not here
			UITheme.show_notification("⟨ SECTOR 11 DETECTED — THE THRESHOLD ⟩  Hostiles are Warp-Hardened, immune to conventional armaments. Execute a Warp Core reset to unlock Cryogenic tech, then research Cryogenic Armaments and craft Cryo weapons in the Shipyard.", Color(0.55, 0.85, 1.0))
	# v113 (NG+ P3): clearing the Z11 Threshold Warden flags the Rift frontier.
	# Z12 "The Rift" (Corrosion tier) then reveals on the NEXT Warp — the locked
	# clear-gated pacing (clear boss → Warp → next zone). The Warden has no
	# boss_core, so detect by id. Flag persists across Warp; cleared on hard reset.
	if current_enemy.get("id", "") == "z11_boss_threshold_warden" and not GameState.game_settings.get("z11_cleared", false):
		GameState.game_settings["z11_cleared"] = true
		UITheme.show_notification("⟨ FRONTIER BREACHED — THE RIFT BECKONS ⟩  The Threshold Warden falls. Execute a Warp Core reset to push into Sector 12 — The Rift, where the Warden hardens against Cryo, then Corrosion. Bring both, and swap loadout presets mid-fight.", Color(0.6, 0.9, 0.7))
	# v113 (NG+ P2): boss master-key drop. A boss with a relic_drop grants its
	# Threshold Relic exactly once (guaranteed, no affixes), flags it earned (so it
	# persists across Warp + re-grants), and auto-equips it if the Relic slot is
	# empty — so the active first-clear immediately flips the boss to farmable.
	var _rdrop: String = current_enemy.get("relic_drop", "")
	if _rdrop != "":
		var _smr = GameState.shipyard_manager
		if _smr and not GameState.game_settings.get(_rdrop + "_earned", false) and _smr.module_inventory.get(_rdrop, 0) <= 0:
			_smr.module_inventory[_rdrop] = 1
			GameState.game_settings[_rdrop + "_earned"] = true
			if _smr.equipped_relic == "":
				_smr.equipped_relic = _rdrop
			var _rname = _smr.modules.get(_rdrop, {}).get("name", "Threshold Relic")
			UITheme.show_notification("⟨ MASTER KEY — %s ⟩  Auto-equipped to your Relic slot. The Warden's onslaught is now survivable — farm it at will." % _rname, Color(0.9, 0.82, 0.4))
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
	# v120: front-half (e1/e2) enemies are the salvage yard — materials only, no
	# module rolls (always-on demand-spine routing). Module gear drops only from the
	# back half (e3/e4) + boss. drops_modules is set per-enemy at spawn_enemy.
	var drop_chance = get_effective_module_drop_chance(current_enemy)
	if not current_enemy.get("drops_modules", true):
		drop_chance = 0.0

	var drop_pool = current_enemy.get("module_drop_pool", [])
	
	# Only drop unlocked modules
	var unlocked_pool = []
	for mod_id in drop_pool:
		var req = sm.modules.get(mod_id, {}).get("research_req", "")
		if req == "" or GameState.research_manager.is_tech_unlocked(req):
			unlocked_pool.append(mod_id)
			
	# v109: MODULE drops only. Bosses burst — roll 4-10 modules (each
	# independently rarity-rolled), drop_chance gate bypassed so a boss kill
	# reliably showers gear. Regulars keep the single drop_chance-gated roll.
	# Scoped to MODULES — Liras, materials, and boss cores (Lunar Cores etc.)
	# are handled in their own blocks above and remain single-drop.
	if unlocked_pool.size() > 0:
		if current_enemy.get("is_boss", false):
			var roll_count = randi_range(4, 10)
			for _i in range(roll_count):
				_roll_one_module_drop(unlocked_pool, sm)
		elif drop_chance > 0 and randf() < drop_chance:
			_roll_one_module_drop(unlocked_pool, sm)

	add_xp(int(current_enemy["xp"] * (1.0 + GameState.research_manager.get_efficiency_bonus("combat_xp"))))
	# v118: Amethyst restore_on_kill (utility facet) — heal % max HP + shield per kill.
	var _rok: float = sm.gem_bonuses.get("restore_on_kill", 0.0)
	if _rok > 0.0:
		sm.current_hp = min(sm.max_hp, sm.current_hp + int(sm.max_hp * _rok))
		player_shield = minf(player_max_shield, player_shield + player_max_shield * _rok)
	# Per-kill HUD timer resets at the moment of the kill; session timer keeps running.
	time_since_last_kill = 0.0
	# v127 H4: research-gated, zone-tiered Hack Stone drop.
	_roll_hack_stone_drops(int(current_zone.get("difficulty", 1)), current_enemy.get("is_boss", false), current_enemy.get("is_elite", false))
	enemy_defeated.emit(current_enemy["id"])
	total_kills += 1
	_maybe_offline_combat_nudge()

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

# One-time tip: once the player has fought meaningfully, surface that Offline
# Combat exists (it's opt-in / off by default). Sim data showed a combat-main
# is non-viable WITHOUT it (never prestiges) but casual-competitive WITH it —
# so discoverability is the fix, not an enemy-reward rebalance. Flag persists
# in game_settings (saved); hard_reset clears it so a fresh game re-nudges.
const OFFLINE_COMBAT_NUDGE_AT := 15

func _maybe_offline_combat_nudge() -> void:
	if total_kills < OFFLINE_COMBAT_NUDGE_AT:
		return
	if GameState.game_settings.get("offline_combat", false):
		return
	if GameState.game_settings.get("offline_combat_nudge_seen", false):
		return
	GameState.game_settings["offline_combat_nudge_seen"] = true
	UITheme.show_notification("TIP: Enable Offline Combat in Options to keep fighting and earning while you're away.", Color(0.55, 0.85, 1.0))

func lose_fight():
	var sm = GameState.shipyard_manager
	# v124: no Lira death penalty — losing costs the consumed kits (to re-heal)
	# + module durability damage below, not credits.

	# v100.0: Module Durability System
	sm.handle_module_defeat()
	
	# v86.0: Hazard Zone — eject on death
	if hazard_state["active"]:
		var hz_name = hazard_zones.get(hazard_state["zone_id"], {}).get("name", "Hazard Zone")
		log_msg("EJECTED from %s at Wave %d/%d!" % [hz_name, hazard_state["wave"] + 1, hazard_state["max_waves"]])
		combat_events.append({"type": "status", "text": "HAZARD FAILED", "color": Color.RED, "side": "player"})
		_reset_hazard_state()

	retreat()
	combat_lost.emit()  # v128: fires the first-loss durability coach

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
	if in_combat and consumable_cooldown > 0: return   # v124: no cooldown out of combat
	
	var sm = GameState.shipyard_manager
	var item_id = ""
	if type == "hull":
		item_id = sm.consumable_hull_slot
	elif type == "shield":
		item_id = sm.consumable_shield_slot
		
	if item_id != "" and GameState.resources.get_element_amount(item_id) >= 1:
		_trigger_consumable(item_id, sm)

# v3 death-tension: repair kits heal a % of hull HP + shield, which balloons into
# near-infinite sustain on the huge late-game hulls (leviathan ~96k HP + ~140k
# shield). Scale kit potency down by hull tier so late fights stay LOSABLE even
# with kits. Tiers 1-3 (corvette/frigate/destroyer) keep full kits — early game
# and the Z1-Z3 balance are untouched; mid hulls 0.55x; big hulls (7-10) 0.30x.
func _kit_tier_factor(sm: Object) -> float:
	# Per-tier, sim-tuned so Legendary+kits lands ~80% (death tension) on each
	# zone's matched hull. Non-uniform because kits scale with each hull's HP+shield
	# differently (the titan's kits are most over-effective → harshest cut at t9).
	var t: int = int(sm.hulls.get(sm.active_hull, {}).get("tier", 1))
	match t:
		1, 2, 3: return 1.0    # corvette/frigate/destroyer — early game + Z1-Z3 untouched
		4: return 0.35
		5: return 0.20
		6: return 0.45
		7: return 0.35
		8: return 0.30
		9: return 0.20
		_: return 0.30         # tier 10 (leviathan) and beyond

func _trigger_consumable(item_id: String, sm: Object):
	if GameState.resources.get_element_amount(item_id) < 1: return
	
	var data = ElementDB.get_consumable_data(item_id)
	if data.is_empty(): return
	
	GameState.resources.remove_element(item_id, 1)
	# v124: cooldown only applies IN combat — out of combat (repairing between
	# fights) consumables fire freely so the player can top up to full.
	if in_combat:
		consumable_cooldown = consumable_cooldown_max

	var heal_pct = data.get("heal_pct", 0.0)
	heal_pct *= kit_potency_dbg
	if in_combat:
		heal_pct *= _kit_tier_factor(sm)   # v3: kits weaken on big hulls IN COMBAT (death tension); full strength for out-of-combat repair
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
	var skill_dmg_mult = (1.0 + combat_dmg_bonus_b) * (1.0 + void_weap_bonus_b)  # v120: combat-level term removed
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
	data["nanite_hot_timer"] = nanite_hot_timer
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
	nanite_hot_timer = data.get("nanite_hot_timer", 0.0)
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
# Can the player actually beat the current enemy? Offline combat is a
# continuation of a winnable fight, not free progress on a wall. Generous by
# design (ignores armor/resist mitigation) so it only ever blocks a fight that
# is unwinnable by a wide margin.
func _offline_winnable() -> bool:
	if not current_enemy: return false
	var conv_dps := 0.0
	var cryo_dps := 0.0
	for w in player_weapon_states:
		var iv: float = max(MIN_ATTACK_INTERVAL, float(w.get("interval", 2.5)))
		conv_dps += (float(w.get("dmg_k", 0.0)) + float(w.get("dmg_e", 0.0)) + float(w.get("dmg_x", 0.0))) / iv
		cryo_dps += float(w.get("dmg_cryo", 0.0)) / iv
	# v113 (NG+ P1): multi-phase boss — must breach EVERY phase band; the worst
	# band governs whether an offline farm is viable. Elements with no weapon
	# channel yet (corrosion/thermal/…) make the band unbeatable → not a farm.
	var _phases: Array = current_enemy.get("phases", [])
	if not _phases.is_empty():
		var _cut: float = float(current_enemy.get("phase_cut", 0.15))
		var _worst := -1.0
		for _ph in _phases:
			var _pe: String = str(_ph).to_lower()
			var _bd := 0.0
			match _pe:
				"cryo": _bd = cryo_dps + conv_dps * _cut
				"kinetic", "energy", "explosive": _bd = conv_dps + cryo_dps * _cut
				_: _bd = (conv_dps + cryo_dps) * _cut
			if _worst < 0.0 or _bd < _worst:
				_worst = _bd
		if _worst <= 0.0:
			return false
		var _ehp: float = float(max(enemy_max_hp, enemy_hp)) + float(enemy_max_shield)
		return _ehp <= 0.0 or (_ehp / _worst) <= 1800.0
	var hardened: bool = current_enemy.get("warp_hardened", false)
	# Warp-hardened (Z11+) enemies need Cryo; conventional weapons do x0.02 and
	# can NEVER kill them — no Cryo output is unwinnable regardless of duration.
	if hardened and cryo_dps <= 0.0:
		return false
	var dps: float = cryo_dps + (conv_dps * (0.02 if hardened else 1.0))
	if dps <= 0.0:
		return false
	# Under-power guard: can't kill within ~30 min of continuous fire → not a farm.
	var enemy_ehp: float = float(max(enemy_max_hp, enemy_hp)) + float(enemy_max_shield)
	return enemy_ehp <= 0.0 or (enemy_ehp / dps) <= 1800.0

func calculate_offline(delta: float):
	if not in_combat or not current_zone or not current_enemy:
		return ""
	# Don't award offline kills against an enemy the ship can't actually beat
	# (warp-hardened with no Cryo, or grossly under-tier).
	if not _offline_winnable():
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
				amount = int(amount * _credit_reward_mult())  # v109 Recursive Acquisition
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
					amount = int(amount * _credit_reward_mult())  # v109 Recursive Acquisition
					GameState.resources.add_currency("credits", amount)
					credits_earned += amount
				else:
					GameState.resources.add_element(item, amount)
					loot_summary[item] = loot_summary.get(item, 0) + amount
		
		# XP (removed defunct enemy_data.get("credits") - credits come from loot)
		var xp = enemy_data.get("xp", 10)
		total_xp += xp

	add_xp(total_xp)
	total_kills += num_kills   # count offline kills (no per-kill signal offline)

	# v125: offline combat is unattended → modules already worn to <=50% durability
	# can be lost (the risk the player consented to when enabling it). Surface
	# exactly what was destroyed in the report — never a silent deletion.
	var notes: Array = []
	var lost_modules: Array = GameState.shipyard_manager.apply_offline_durability_risk(delta)
	if not lost_modules.is_empty():
		notes.append("⚠ Lost to offline wear (durability ≤50%%): %s" % [", ".join(PackedStringArray(lost_modules))])

	# v112: structured offline block (was a formatted string). Liras fold into
	# `gains` under "credits" so the ledger renders them as one row.
	var gains = loot_summary.duplicate()
	if credits_earned > 0:
		gains["credits"] = credits_earned
	return {
		"category": "combat",
		"title": "Combat Sweep",
		"action": "",
		"time_sec": int(delta),
		"actions": num_kills,
		"xp": total_xp,
		"gains": gains,
		"drains": {},
		"notes": notes,
		"status": "active",
	}
