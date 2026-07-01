# v71.0: Module Rarity System
enum Rarity {COMMON, UNCOMMON, RARE, LEGENDARY, UNIQUE}

const RARITY_COLORS = {
	Rarity.COMMON: Color(0.7, 0.7, 0.7), # Light Gray
	Rarity.UNCOMMON: Color(0.2, 1.0, 0.2), # Sharp Green
	Rarity.RARE: Color(0.0, 0.6, 1.0), # Vivid Electric Blue
	Rarity.LEGENDARY: Color(1.0, 0.8, 0.0), # Vivid Gold
	Rarity.UNIQUE: Color(1.0, 0.2, 0.8), # Vivid Magenta
}

const RARITY_LABELS = {
	Rarity.COMMON: "",
	Rarity.UNCOMMON: "Uncommon",
	Rarity.RARE: "Rare",
	Rarity.LEGENDARY: "Legendary",
	Rarity.UNIQUE: "Unique",
}

const RARITY_STAT_RANGE = {
	# v115: rarity COMPRESSED so a full tier step (~2.2x) out-scales every rarity
	# below Unique -> Sector N Common > Sector N-1 Legendary by raw stats (kills the
	# "my old Rare drop dominates the next-zone craft" dead-common problem). Rarity
	# is now a within-tier bump + affixes; only UNIQUE still leapfrogs one tier (the
	# jackpot skip-key). The honest penetration wall enforces it in combat.
	Rarity.COMMON: [0.00, 0.00],    # 1.00x fixed - baseline crafted
	Rarity.UNCOMMON: [0.10, 0.20],  # 1.10x-1.20x - within-zone upgrade
	Rarity.RARE: [0.25, 0.45],      # 1.25x-1.45x - within-zone (< next-Common 2.2x)
	Rarity.LEGENDARY: [0.40, 0.55], # v120: 1.40x-1.55x (was 1.55-1.85). Trimmed so a carried
									# N-1 Legendary's base+rarity sits clearly UNDER a clean
	                                # next-tier Common (2.2x) — its affixes/cores are then a
	                                # comfort margin, not a tier-leapfrog. Keeps Common > Leg
	                                # without nerfing the affix system. Still > Rare (3 affixes).
	Rarity.UNIQUE: [1.40, 2.20],    # 2.40x-3.20x - jackpot: leapfrogs ONE tier, then retires
}

# v114 (Zone Tier-Gate): the per-zone signature alloy each Z2-Z10 common module
# requires (injected at craft time by get_effective_module_cost). See docs/ZONE_TIER_GATE.md.
const TIER_ALLOY_BY_ZONE := {
	2: "ChondriteAlloy", 3: "WreckforgedAlloy", 4: "RimeAlloy", 5: "XenoforgedAlloy",
	6: "ColonyAlloy", 7: "GammaAlloy", 8: "PrismaticAlloy", 9: "BioforgedAlloy", 10: "AeonAlloy",
}

# Drop scaling curve per zone (kept controlled and tapering in late game).
const MODULE_ZONE_SCALE_EARLY = 1.34
const MODULE_ZONE_SCALE_LATE = 1.28
const MODULE_ZONE_LATE_START = 7

# Stats that get rarity bonuses (damage, defense, HP, etc.)
const BOOSTABLE_STATS = [
	"atk_kinetic", "atk_energy", "atk_explosive", "atk_cryo",  # v109: Cryo 4th type
	"hp", "def", "eva", "accuracy", "crit_chance",
	"max_shield", "shield_regen", "energy_capacity",
	"atk_speed_bonus", "shield_regen_mult", "atk_speed_mult",
	"jamming_strength", "atk_interval"
]

# Zone scaling is applied only to flat/core stats.
const ZONE_SCALABLE_STATS = [
	"atk_kinetic", "atk_energy", "atk_explosive", "atk_cryo",  # v109: Cryo 4th type
	"hp", "def", "eva", "accuracy",
	"max_shield", "shield_regen", "energy_capacity",
	"atk_interval"
]

# v110: Battery-only energy model. Hulls provide ZERO energy. Every consumer
# module (weapon/shield/armor/engine/sensor) draws CONSUMER_LOAD_BY_TIER[zone];
# every battery supplies BATTERY_CAP_BY_TIER[zone]. v112: battery supply gives
# each hull tier ~25% power HEADROOM over a full tier-matched consumer set. It
# used to be exactly 1:1 ("exactly powers"), which left ZERO room — slotting any
# higher-tier drop tripped energy_used>energy_capacity and hard-blocked combat
# ("SHIP UNPOWERED"), so a drop's dopamine became "why can't I use it." 25%
# headroom lets the player slot a few next-tier modules before needing battery
# upgrades; a multi-tier leap still requires investment, so the battery economy
# stays a real (non-punishing) constraint. Both DERIVED by tier (not stored
# per-module) so the whole ~50-module roster stays balanced. Index = tier-1.
# Save-safe: energy is derived, so existing loadouts just gain headroom.
const CONSUMER_LOAD_BY_TIER := [10, 15, 25, 40, 60, 100, 150, 220, 350, 500]
const BATTERY_CAP_BY_TIER   := [40, 80, 100, 200, 240, 460, 800, 1000, 1750, 2250]
const CONSUMER_SLOT_TYPES := ["weapon", "shield", "armor", "engine", "sensor"]

# Energy a module-DEFINITION DRAWS (consumers) — works on the def dict so UI
# that only has m_data (no id) can use it too.
func get_def_energy_load(mdef: Dictionary) -> int:
	if not (mdef.get("slot_type", "") in CONSUMER_SLOT_TYPES):
		return 0
	# Explicit override for modules whose zone doesn't match their intended
	# power tier (e.g. Cryo-Lance: zone 11 but starter prestige weapon).
	if mdef.has("power_tier"):
		var pt: int = clampi(int(mdef["power_tier"]), 1, CONSUMER_LOAD_BY_TIER.size())
		return CONSUMER_LOAD_BY_TIER[pt - 1]
	var z: int = int(mdef.get("zone", mdef.get("zone_difficulty", 1)))
	z = clampi(z, 1, CONSUMER_LOAD_BY_TIER.size())
	return CONSUMER_LOAD_BY_TIER[z - 1]

func get_def_energy_capacity(mdef: Dictionary) -> int:
	if mdef.get("slot_type", "") != "battery":
		return 0
	var z: int = int(mdef.get("zone", mdef.get("zone_difficulty", 1)))
	z = clampi(z, 1, BATTERY_CAP_BY_TIER.size())
	return BATTERY_CAP_BY_TIER[z - 1]

# id-based wrappers (used by recalc / equip / per-id UI).
func get_module_energy_load(mid: String) -> int:
	if not mid in modules:
		return 0
	return get_def_energy_load(modules[mid])

func get_module_energy_capacity(mid: String) -> int:
	if not mid in modules:
		return 0
	return get_def_energy_capacity(modules[mid])

# Mid/Late progression tuning for craftable module item requirements.
const MID_MODULE_ITEM_REQ_MULT = 1.35
const LATE_MODULE_ITEM_REQ_MULT = 1.75

const EARLY_MODULE_REQ_TECHS = [
	"kinetics_101", "laser_optics", "power_systems",
	"lightweight_alloys", "basic_electronics",
	# v111.5: eff_scanning_1 removed from early-module gate list (tech was
	# cut — it had no real effect on Data which had no consumer).
	"energy_shields", "combustion"
]

const LATE_MODULE_REQ_TECHS = [
	# v111.7: dropped capital_ship_engineering + void_physics (collapsed bridge
	# techs). Neither was ever a module research_req, so this is inert tidy-up.
	"quantum_dynamics", "xeno_engineering",
	"exotic_matter_analysis", "void_navigation"
]

const MID_MODULE_ITEMS = [
	"Res2", "Res3", "AdvCircuit", "Superalloy", "NavData",
	"ColonyDataCore", "RadIsotope", "ExoticIsotope", "AntimatterParticle"
]

const LATE_MODULE_ITEMS = [
	"VoidArtifact", "VoidCrystal", "VoidEssence", "QuantumCore",
	"ChronoCore", "ExoticMatter", "Neutronium", "AncientTech",
	"AICore", "AIProcessor", "PrimordialShard", "OmegaPlating"
]

# v74.0: Module Affix System (Diablo/PoE Style)
# Categories: tactical, industrial, economy
const AFFIX_DB = {
	# --- TACTICAL (Weapon, Sensor) ---
	"static_burst": {
		"name": "Static Burst", "type": "tactical", "scaling": "percent",
		"range": [3, 8], "limit_to": ["weapon"],
		"desc": "%d%% shock chance on hit to reset enemy attack timer."
	},
	"void_strike": {
		"name": "Void Strike", "type": "tactical", "scaling": "percent",
		"range": [3, 8], "limit_to": ["weapon"],
		"desc": "%d%% chance to bypass Shield and deal Hull damage directly."
	},
	"flat_atk": {
		"name": "Sharpened Edge", "type": "tactical", "scaling": "flat",
		"range": [2, 5], "limit_to": ["weapon"],
		"desc": "+%d Flat Attack damage."
	},
	"flat_accuracy": {
		"name": "Targeting Computer", "type": "tactical", "scaling": "flat",
		"range": [5, 15], "limit_to": ["weapon"],
		"desc": "+%d Flat Accuracy."
	},
	"servo_overclock": {
		"name": "Servo Overclock", "type": "tactical", "scaling": "percent",
		"range": [5, 12], "limit_to": ["weapon"],
		"desc": "+%d%% Attack Speed."
	},

	# --- DEFENSIVE (Armor, Shield) ---
	"flat_hp": {
		"name": "Reinforced Layers", "type": "defensive", "scaling": "flat",
		"range": [5, 15], "limit_to": ["armor"],
		"desc": "+%d Flat Hull Integrity."
	},
	"flat_def": {
		"name": "Damped Plating", "type": "defensive", "scaling": "flat",
		"range": [1, 3], "limit_to": ["armor"],
		"desc": "+%d Flat Defense."
	},
	"flat_shield": {
		"name": "Flux Capacitor", "type": "defensive", "scaling": "flat",
		"range": [10, 30], "limit_to": ["shield"],
		"desc": "+%d Flat Shield Capacity."
	},
	"capacitor_pulse": {
		"name": "Capacitor Pulse", "type": "defensive", "scaling": "percent",
		"range": [2, 5], "limit_to": ["shield", "battery"],
		"desc": "Instantly restore %d%% Max Shield on every enemy kill."
	},
	"nanite_resurgence": {
		"name": "Nanite Resurgence", "type": "defensive", "scaling": "percent",
		"range": [2, 5], "limit_to": ["armor"],
		"desc": "Instantly restore %d%% Max Hull on every enemy kill."
	},

	# --- v127 R3: per-type damage RESISTANCE (Armor, Shield) ---
	# Percent scaling -> stored as a fraction (roll 5-20 -> 0.05-0.20; GA -> 0.40).
	# Aggregated into the ship's resist_k/e/x in recalc_stats, capped 0.75 each.
	"resist_k": {
		"name": "Ablative Plating", "type": "defensive", "scaling": "percent",
		"range": [5, 20], "limit_to": ["armor", "shield"],
		"desc": "+%d%% Kinetic Resistance."
	},
	"resist_e": {
		"name": "Faraday Mesh", "type": "defensive", "scaling": "percent",
		"range": [5, 20], "limit_to": ["armor", "shield"],
		"desc": "+%d%% Energy Resistance."
	},
	"resist_x": {
		"name": "Blast Baffling", "type": "defensive", "scaling": "percent",
		"range": [5, 20], "limit_to": ["armor", "shield"],
		"desc": "+%d%% Explosive Resistance."
	},

	# --- SENSOR (v128): loot-finding identity. Sensor rolls ONLY these three.
	# Wired: enemy_drop_mult -> win_fight loot qty (elements+Liras);
	# module_drop_mult -> get_effective_module_drop_chance;
	# stone_drop_mult -> _roll_hack_stone_drops.
	"enemy_drop_mult": {
		"name": "Prospector Array", "type": "utility", "scaling": "percent",
		"range": [5, 10], "limit_to": ["sensor"],
		"desc": "+%d%% loot quantity from destroyed enemies."
	},
	"module_drop_mult": {
		"name": "Salvage Scanner", "type": "utility", "scaling": "percent",
		"range": [8, 15], "limit_to": ["sensor"],
		"desc": "+%d%% module drop chance."
	},
	"stone_drop_mult": {
		"name": "Cryptographic Decoder", "type": "utility", "scaling": "percent",
		"range": [10, 20], "limit_to": ["sensor"],
		"desc": "+%d%% Hack Card drop chance."
	},
	# v85.1: New Combat Affixes
	"combat_sight": {
		"name": "Combat Sight", "type": "tactical", "scaling": "percent",
		"range": [2, 5], "limit_to": ["weapon"],
		"desc": "+%d%% Critical Strike chance."
	},
	"reflexive_plating": {
		"name": "Reflexive Plating", "type": "defensive", "scaling": "flat",
		"range": [2, 5], "limit_to": ["armor", "engine"],
		"desc": "+%d Flat Evasion."
	},
	"hull_heal_on_hit": {
		"name": "Nanite Syringe", "type": "defensive", "scaling": "linear_tier",
		"range": [1, 3], "limit_to": ["weapon", "armor"],
		"desc": "Restore %d Hull Integrity on every hit."
	},
	"shield_heal_on_hit": {
		"name": "Shield Siphon", "type": "defensive", "scaling": "linear_tier",
		"range": [1, 3], "limit_to": ["weapon", "shield"],
		"desc": "Restore %d Shield Capacity on every hit."
	},
	# v85.3: Refined Sci-Fi Affixes (Inspiration, not Imitation)
	"lucky_hit_chance": {
		"name": "Tactical Breach Chance", "type": "tactical", "scaling": "percent",
		"range": [5, 10], "limit_to": ["weapon"],
		"desc": "+%d%% Tactical Breach Chance."
	},
	"dmg_healthy": {
		"name": "Precision Calibration", "type": "tactical", "scaling": "percent",
		"range": [10, 20], "limit_to": ["weapon"],
		"desc": "+%d%% damage against High Integrity enemies (>80%% Hull)."
	},
	"dmg_injured": {
		"name": "Structural Exploitation", "type": "tactical", "scaling": "percent",
		"range": [15, 30], "limit_to": ["weapon"],
		"desc": "+%d%% damage against Severely Damaged enemies (<35%% Hull)."
	},
	"vuln_on_hit": {
		"name": "Exposing Pulse", "type": "tactical", "scaling": "percent",
		"range": [5, 12], "limit_to": ["weapon"],
		"desc": "%d%% chance to make enemies Exposed (20%% more dmg) for 3s."
	},
	"berserk_on_kill": {
		"name": "Overdrive Catalyst", "type": "tactical", "scaling": "percent",
		"range": [8, 15], "limit_to": ["weapon", "engine"],
		"desc": "%d%% chance on kill to enter Overdrive (+25%% Atk Speed) for 5s."
	}
}

# v85.3: Sci-Fi Thematic Naming System
const AFFIX_NAMING = {
	"static_burst": {"prefix": "Overloaded", "suffix": "of Discharge"},
	"void_strike": {"prefix": "Phased", "suffix": "of the Void"},
	"flat_atk": {"prefix": "Charged", "suffix": "of Lethality"},
	"flat_accuracy": {"prefix": "Calibrated", "suffix": "of Precision"},
	"servo_overclock": {"prefix": "Overclocked", "suffix": "of Haste"},
	"flat_hp": {"prefix": "Reinforced", "suffix": "of Bulwark"},
	"flat_def": {"prefix": "Hardened", "suffix": "of Bastion"},
	"flat_shield": {"prefix": "Flux", "suffix": "of the Aegis"},
	"capacitor_pulse": {"prefix": "Kinetic", "suffix": "of the Dynamo"},
	"nanite_resurgence": {"prefix": "Repairing", "suffix": "of Nanites"},
	"combat_sight": {"prefix": "Surgical", "suffix": "of the Assassin"},
	"reflexive_plating": {"prefix": "Stealth", "suffix": "of Ghosting"},
	"hull_heal_on_hit": {"prefix": "Siphoning", "suffix": "of the Parasite"},
	"shield_heal_on_hit": {"prefix": "Conductive", "suffix": "of the Siphon"},
	"lucky_hit_chance": {"prefix": "Opportunistic", "suffix": "of Synergy"},
	"dmg_healthy": {"prefix": "Executioner's", "suffix": "of the Hunt"},
	"dmg_injured": {"prefix": "Sadistic", "suffix": "of Ending"},
	"vuln_on_hit": {"prefix": "Shattering", "suffix": "of Weakness"},
	"berserk_on_kill": {"prefix": "Neural", "suffix": "of the Reckless"}
}

# Step 6 (v118 redesign): Matrix-core FACETS. PoE-style type-matching — a core's
# effect depends on the HOST module's slot category (weapon=offense / armor+shield=
# defense / engine+sensor+other=utility). Soft per-core, compounds over long runs.
# Two facets SOFTEN (never break) a gate, both offense-only & capped in combat:
# armor_pen (tier wall) and resist_pierce (resist gate). See docs/MATRIX_CORES.md.
const GEM_FACETS = {
	# CRIMSON (Wrath) — crit chance+damage / damage reduction / ammo efficiency
	# (weapon bundles crit_chance so crit_damage isn't dead at the 5% base crit)
	"CrackedCrimsonCore":  {"weapon": {"crit_chance": 0.02, "crit_damage": 0.06}, "defense": {"damage_reduction": 0.015}, "utility": {"ammo_eff": 0.04}},
	"StableCrimsonCore":   {"weapon": {"crit_chance": 0.04, "crit_damage": 0.15}, "defense": {"damage_reduction": 0.03},  "utility": {"ammo_eff": 0.10}},
	"PristineCrimsonCore": {"weapon": {"crit_chance": 0.08, "crit_damage": 0.30}, "defense": {"damage_reduction": 0.06},  "utility": {"ammo_eff": 0.20}},
	# COBALT (Surge) — attack speed / shield regen / energy efficiency
	"CrackedCobaltCore":   {"weapon": {"attack_speed": 0.02}, "defense": {"shield_regen_mult": 0.06}, "utility": {"energy_eff": 0.02}},
	"StableCobaltCore":    {"weapon": {"attack_speed": 0.05}, "defense": {"shield_regen_mult": 0.15}, "utility": {"energy_eff": 0.05}},
	"PristineCobaltCore":  {"weapon": {"attack_speed": 0.10}, "defense": {"shield_regen_mult": 0.30}, "utility": {"energy_eff": 0.10}},
	# TOPAZ (Focus) — armor penetration (tier-wall softener) / evasion / accuracy
	"CrackedTopazCore":    {"weapon": {"armor_pen": 0.03}, "defense": {"evasion_flat": 2.0},  "utility": {"accuracy_flat": 5.0}},
	"StableTopazCore":     {"weapon": {"armor_pen": 0.07}, "defense": {"evasion_flat": 5.0},  "utility": {"accuracy_flat": 12.0}},
	"PristineTopazCore":   {"weapon": {"armor_pen": 0.12}, "defense": {"evasion_flat": 10.0}, "utility": {"accuracy_flat": 25.0}},
	# AMETHYST (Harmonics) — resist pierce (resist-gate softener) / max hull / restore-on-kill
	"CrackedAmethystCore":  {"weapon": {"resist_pierce": 0.03}, "defense": {"max_hull_mult": 0.02}, "utility": {"restore_on_kill": 0.02}},
	"StableAmethystCore":   {"weapon": {"resist_pierce": 0.06}, "defense": {"max_hull_mult": 0.05}, "utility": {"restore_on_kill": 0.04}},
	"PristineAmethystCore": {"weapon": {"resist_pierce": 0.12}, "defense": {"max_hull_mult": 0.10}, "utility": {"restore_on_kill": 0.08}},
}

# v118: aggregate caps per facet — the most any number of sockets can grant. Sized so
# ~4-5 cores reach the cap (past that, more of the same facet is wasted -> pushes a
# diverse matrix), and so a maxed T10 hull (up to 18 weapon / 27 defense / 33 utility
# sockets) can't stack to absurd or BROKEN values (energy_eff/ammo_eff stay < 1.0).
const GEM_FACET_CAPS := {
	"crit_chance": 0.35, "crit_damage": 1.50, "attack_speed": 0.40,
	"shield_regen_mult": 1.20, "max_hull_mult": 0.40,
	"evasion_flat": 50.0, "accuracy_flat": 120.0,
	"ammo_eff": 0.40, "energy_eff": 0.30, "restore_on_kill": 0.25,
	"damage_reduction": 0.30, "armor_pen": 0.20, "resist_pierce": 0.30,
}

var affix_bonuses = {
	"static_burst": 0.0,
	"capacitor_pulse": 0.0,
	"void_strike": 0.0,
	"servo_overclock": 0.0,
	"nanite_resurgence": 0.0,
	"enemy_drop_mult": 0.0,
	"module_drop_mult": 0.0,
	"stone_drop_mult": 0.0,
	# v80.1: Flat Scaling Affixes
	"flat_hp": 0.0,
	"flat_def": 0.0,
	"flat_atk": 0.0,
	"flat_accuracy": 0.0,
	"flat_shield": 0.0,
	# v85.1: New Affixes
	"combat_sight": 0.0,
	"reflexive_plating": 0.0,
	"hull_heal_on_hit": 0.0,
	"shield_heal_on_hit": 0.0,
	# v85.2: New D4 Affixes
	"lucky_hit_chance": 0.0,
	"dmg_healthy": 0.0,
	"dmg_injured": 0.0,
	"vuln_on_hit": 0.0,
	"berserk_on_kill": 0.0,
	# v127 R3: per-type damage resistance affixes (armor/shield)
	"resist_k": 0.0,
	"resist_e": 0.0,
	"resist_x": 0.0
}

# v71.1: Alert System for new drops
signal alert_changed(state: bool)
var new_drops_alert: bool = false:
	set(val):
		if new_drops_alert != val:
			new_drops_alert = val
			alert_changed.emit(val)

var active_hull: String = "corvette_hull"
var module_inventory: Dictionary = {}
var unseen_modules: Dictionary = {}
# v111.18 Phase 2: persistent Armory grid positions for the spatial inventory.
# { item_id: {"x": int, "y": int} }. Items without an entry are auto-packed.
var armory_layout: Dictionary = {}
var loadout: Dictionary = {} # {slot_index: module_id}
# v113 (NG+ P2): the dedicated Relic slot — a single Threshold Relic (master key),
# SEPARATE from the hull's weapon/armor grid (never competes for a hull slot).
# Persists across Warp (re-granted in execute_warp); cleared only on hard reset.
var equipped_relic: String = ""
var ammo_loadout: Dictionary = {} # {slot_index: ammo_id}

# v66.0: Consumable Slots
var consumable_hull_slot: String = "" # e.g. "Mesh"
var consumable_shield_slot: String = "" # e.g. "BasicBooster"

# Loadout Presets — 5 saved builds (Melvor-style equipment sets) for quick swap.
# v113 (NG+ P2): bumped 3→5 so multi-phase NG+ bosses can be answered with one
# preset per element (Cryo / Corrosion / …), tap-swapped mid-fight. Old 3-preset
# saves migrate cleanly — the load handler only restores indices present here, so
# 4 & 5 simply start empty.
var loadout_presets: Dictionary = {
	1: {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""},
	2: {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""},
	3: {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""},
	4: {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""},
	5: {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""}
}

# v72.3: Research Requirements for non-module equipment (Ammo, Consumables)
const ELEMENT_RESEARCH_REQS = {
	# v129: SlugT1/MissileT1 equip gates removed — the T1 starter combat kit
	# (weapon + battery + shield + all three T1 ammo types) is research-free so the
	# tutorial stops bouncing the player to Research. T2+ gates unchanged.
	"SlugT2": "ballistics_optimization",
	# v105b: was "high_energy_munitions" — a tech that doesn't exist in tech_tree.
	# Players could craft SlugT3/T4 via ballistics_optimization but never equip
	# them (can_equip_module check failed against unknown tech). Aligned to the
	# same tech that gates the crafting recipes.
	"SlugT3": "ballistics_optimization",
	"SlugT4": "ballistics_optimization",
	"CellT2": "laser_optics",
	"CellT3": "cryogenic_systems",
	"CellT4": "cryogenic_systems",
	"MissileT2": "advanced_rocketry",
	"MissileT3": "advanced_rocketry",
	"MissileT4": "capital_ship_armament",
	"EmergencyPatch": "basic_engineering", # Early game
	"Mesh": "adv_materials",
	"Seal": "adv_materials",
	"BasicBooster": "basic_engineering", # v129: was energy_shields — starter shield kit matches EmergencyPatch's gate
	"IonField": "field_theory",
	"NitroCoolant": "cryogenic_systems",
	"ZeroPoint": "quantum_dynamics"
}
var custom_modules: Dictionary = {} # Feature v66.0: Random Rare Drops
var _module_item_costs_scaled := false

# Calculated Stats
var max_hp = 100
var current_hp = 100
var active_shield = 0
var max_shield = 0
var shield_regen = 0
var hp_regen = 0 # v80.1: Added for Trinity set bonuses
var attack_kinetic = 0
var attack_energy = 0
var attack_explosive = 0 # Phase 9
# v127: player per-type damage RESISTANCE (0.0-0.75). Summed from equipped
# modules (baseline on armor/shield defs + rollable affix) in recalc_stats,
# capped at 0.75 each, then applied to incoming enemy damage of the matching
# type. Defaults 0 -> combat is mathematically unchanged until modules grant it.
var resist_k = 0.0
var resist_e = 0.0
var resist_x = 0.0
var attack = 0 # Combined
var defense = 0
var evasion = 0
var accuracy = 0
var crit_chance = 0.05 # 5% base
var energy_used = 0
var energy_capacity = 0  # v110: ship's own energy field, decoupled from resources.max_energy (infra grid)
var attack_speed_bonus = 0.0
var shield_regen_bonus = 0.0
var jamming_strength = 0.0 # New: EW Enemy Slow % (0.0 to 1.0)


signal hull_constructed(hull_id)
signal module_crafted(module_id)
signal inventory_updated() # New signal for UI refresh
signal hack_stone_applied(stone_id)  # v128: a Hack Card was successfully applied (mission arc)

var hulls: Dictionary = {
	# v80.1: 10 formula-driven hulls — HP = floor(80 × 2.2^(N-1)), Slots = 6 + 2N
	"corvette_hull": {
		"name": "Corvette",
		"stats": {"hp": 120, "energy_capacity": 25},
		"cost": {"credits": 0},
		"slots": ["weapon", "weapon", "shield", "armor", "engine", "battery", "battery", "sensor"], # 8
		"visual": "res://assets/ships/1.png",
		"tier": 1
	},
	"frigate_hull": {
		"name": "Industrial Frigate",
		"stats": {"hp": 200, "energy_capacity": 75},
		# v126: Reinforced Plating gets its intended "early ship-frame upgrade" sink.
		# SalvagedAlloy/DamagedCircuitry drop only in Z1-2; the frigate (tier 2) is built
		# in that same era, so the reclaimed loop terminates here instead of piling up
		# dead. Anti-deadlock: lvl-8 fallback recipes mint both from Steel/Circuit.
		"cost": {"credits": 30000, "Steel": 50, "ReinforcedPlating": 4},
		"slots": ["weapon", "weapon", "shield", "shield","armor", "armor", "engine", "battery", "battery", "sensor"], # 10
		"research_req": "shipwright_1",
		"visual": "res://assets/ships/2.png",
		"tier": 2
	},
	"destroyer_hull": {
		"name": "Destroyer",
		"stats": {"hp": 387, "energy_capacity": 120},
		# v126: continues the Reinforced Plating sink into the tier-3 hull (still Z1-2 era).
		"cost": {"credits": 90000, "Steel": 100, "Circuit": 20, "ReinforcedPlating": 10},
		"slots": ["weapon", "weapon", "weapon", "shield", "shield", "armor", "armor", "engine", "battery", "battery", "battery", "sensor"], # 12
		"research_req": "shipwright_2",
		"visual": "res://assets/ships/3.png",
		"tier": 3
	},
	"cruiser_hull": {
		"name": "Heavy Cruiser",
		"stats": {"hp": 852, "energy_capacity": 260},
		"cost": {"credits": 270000, "Ti": 200, "AdvCircuit": 50},
		"slots": ["weapon", "weapon", "weapon", "shield", "shield", "shield", "armor", "armor", "engine", "battery", "battery", "battery", "sensor", "sensor"], # 14
		"research_req": "zone_4_access",
		"visual": "res://assets/ships/4.png",
		"tier": 4
	},
	"battlecruiser_hull": {
		"name": "Battlecruiser",
		"stats": {"hp": 1874, "energy_capacity": 570},
		"cost": {"credits": 810000, "Superalloy": 500, "QuantumCore": 25},
		"slots": ["weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "armor", "armor", "engine", "battery", "battery", "battery", "battery", "sensor", "sensor"], # 16
		"research_req": "zone_5_access",
		"visual": "res://assets/ships/5.png",
		"tier": 5
	},
	"capital_hull": {
		"name": "Capital Ship",
		"stats": {"hp": 4124, "energy_capacity": 1255},
		"cost": {"credits": 2430000, "AdvCircuit": 1000, "VoidArtifact": 50},
		"slots": ["weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "armor", "armor", "armor", "engine", "engine", "battery", "battery", "battery", "battery", "sensor", "sensor"], # 18
		"research_req": "zone_6_access",
		"visual": "res://assets/ships/5.png",
		"tier": 6
	},
	"carrier_hull": {
		"name": "Carrier",
		"stats": {"hp": 9073, "energy_capacity": 2760},
		"cost": {"credits": 7290000, "ExoticMatter": 100},
		"slots": ["weapon", "weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "armor", "armor", "armor", "engine", "engine", "battery", "battery", "battery", "battery", "sensor", "sensor"], # 20
		"research_req": "zone_7_access",
		"visual": "res://assets/ships/5.png",
		"tier": 7
	},
	"dreadnought_hull": {
		"name": "Dreadnought",
		"stats": {"hp": 19960, "energy_capacity": 6075},
		"cost": {"credits": 21870000, "ExoticMatter": 200},
		"slots": ["weapon", "weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "armor", "armor", "armor", "engine", "engine", "battery", "battery", "battery", "battery", "battery", "sensor", "sensor", "sensor"], # 22
		"research_req": "zone_8_access",
		"visual": "res://assets/ships/5.png",
		"tier": 8
	},
	"titan_hull": {
		"name": "Titan",
		"stats": {"hp": 43913, "energy_capacity": 13365},
		"cost": {"credits": 65610000, "Neutronium": 500},
		"slots": ["weapon", "weapon", "weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "armor", "armor", "armor", "armor", "engine", "engine", "battery", "battery", "battery", "battery", "battery", "sensor", "sensor", "sensor"], # 24
		"research_req": "zone_9_access",
		"visual": "res://assets/ships/5.png",
		"tier": 9
	},
	"leviathan_hull": {
		"name": "Leviathan",
		"stats": {"hp": 96609, "energy_capacity": 29400},
		"cost": {"credits": 196830000, "PrimordialShard": 1000},
		"slots": ["weapon", "weapon", "weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "shield", "armor", "armor", "armor", "armor", "engine", "engine", "battery", "battery", "battery", "battery", "battery", "battery", "sensor", "sensor", "sensor"], # 26
		"research_req": "zone_10_access",
		"visual": "res://assets/ships/5.png",
		"tier": 10
	}
}

func get_ship_name() -> String:
	if active_hull in hulls:
		return hulls[active_hull].get("name", "Unknown Ship")
	return "No Ship"

var modules: Dictionary = {
	# ═══════════════════════════════════════════════════════════════
	# v80.1: Formula-Driven Modules — 10 Zones × 5 Types = 50 Base
	# Kinetic ATK = floor(8 × 2.2^(N-1))
	# Energy ATK  = floor(10 × 2.2^(N-1))
	# Missile ATK = floor(18 × 2.2^(N-1)), interval 4.0s
	# Shield HP   = floor(40 × 2.2^(N-1)), regen = floor(HP × 0.05)
	# Armor DEF   = floor(5 × 2.2^(N-1)), HP bonus = floor(20 × 2.2^(N-1))
	# ═══════════════════════════════════════════════════════════════

	# ── CRYO WEAPON TIER — the 4th damage type, unlocked by the first Warp. ──
	# Exotic-Matter self-charging (no ammo). The only damage that bites
	# Warp-Hardened (Z11+) hulls. v113: NO free starter weapon — ALL
	# Cryo weapons are CRAFTED via Shipyard craft_module (research: cryo_armaments)
	# during the post-warp re-climb. Z11 drops rarity-rolled cryo_lance upgrades.
	# All Cryo weapons use power_tier to decouple draw from zone 11.
	# v113: the free Cryo Shard Pistol was CUT — Warping no longer hands out a
	# (useless ~Z1-power) weapon. v113: collapsed to ONE craftable Cryo weapon, the
	# Cryo Lance below (RARE entry, Cryo Catalyst + research) — Z11 drops it
	# rarity-rolled and the boss a guaranteed one; a LEGENDARY roll (with affixes)
	# is the real Warden-killer, same craft-then-farm loop as every zone.
	"cryo_lance": {
		"name": "Cryo Lance",
		"slot_type": "weapon",
		"rarity": Rarity.RARE,
		# ~Z10 power level. Endgame Cryo craft — the weapon that makes Z11
		# beatable. 3× equipped → ~19 min Threshold Warden kill (first clear).
		# Z11 drops rarity-rolled copies that can exceed this base via affixes.
		"stats": {"atk_cryo": 4000, "atk_interval": 2.0},
		"cost": {"credits": 2000000, "ExoticMatter": 15, "CryoCatalyst": 12, "Superalloy": 50},
		"desc": "Exotic-Matter cryo lance. Self-charging, no ammo. The only thing that breaches Warp-Hardened hulls - farm The Threshold for legendary-grade rolls.",
		"zone": 11,
		"power_tier": 8,
		"cryo": true,
		"research_req": "cryo_armaments"
	},

	# ── CORROSION WEAPON (NG+ WT2 / Z12) — the 2nd exotic element. ──
	# v113 (NG+ P3): same exotic channel as Cryo (atk_cryo, self-charging/no-ammo),
	# but stats.exotic_element = "corrosion" tags it so the multi-phase gate credits
	# it ONLY against Corrosion phases. A Cryo loadout does ×0.15 on the Rift
	# Warden's Corrosion phase → you swap to a Corrosion preset. Guaranteed drop
	# from the Rift Warden's first clear; craftable thereafter (corrosion_armaments).
	# NOTE: UI still tints it Cryo-ice until per-element weapon coloring ships (P3b).
	"corrosion_blaster": {
		"name": "Corrosion Blaster",
		"slot_type": "weapon",
		"rarity": Rarity.LEGENDARY,
		"stats": {"atk_cryo": 12000, "atk_interval": 2.0, "exotic_element": "corrosion"},
		"cost": {"credits": 8000000, "ExoticMatter": 30, "CryoCatalyst": 20, "Superalloy": 120, "ChronoCore": 8, "VoidCrystal": 15},
		"desc": "Acid-plasma projector. Etches through Corrosion-hardened hulls where cryogenic fire just glazes the surface.",
		"zone": 12,
		"power_tier": 8,
		"research_req": "corrosion_armaments"
	},

	# ── THRESHOLD RELIC (NG+ master key) — the Rift Warden's drop. ──
	# v113 (NG+ P2): dedicated Relic slot (slot_type "relic", NOT a hull slot).
	# While equipped IN its keyed zone, incoming damage is slashed to ~8% so the
	# gate boss becomes survivable → idle-farmable (the "active clear once, then
	# farm" payoff). Empty cost = not craftable; only the boss drops it. Persists
	# across Warp. relic_reduction is P5-tunable.
	"rift_relic": {
		"name": "Threshold Relic — Rift",
		"slot_type": "relic",
		"rarity": Rarity.LEGENDARY,
		"unique": true,
		"stats": {},
		"relic_zone": "the_rift",
		"relic_reduction": 0.92,
		"relic_for": "z12_boss_rift_warden",
		"cost": {},
		"desc": "A master key wrenched from the Rift Warden's core. Equipped, the Rift's corrosive fury barely scratches your hull — clear the gate once, then farm it at will.",
		"zone": 12
	},

	# ── ZONE 1: Lunar Orbit ──
	"z1_kinetic": {
		"name": "Mass Driver Mk.I",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 8, "energy_load": 5, "atk_interval": 2.0},
		"cost": {"credits": 2000, "Fe": 30},
		"desc": "Magnetic projectile cannon. Reliable hull damage.",
		"zone": 1
	},
	"z1_energy": {
		"name": "Pulse Laser Mk.I",
		"slot_type": "weapon",
		"stats": {"atk_energy": 10, "energy_load": 8, "atk_interval": 2.0},
		"cost": {"credits": 2000, "Si": 30},
		"desc": "Fast-firing energy beam. Strong vs shields.",
		"zone": 1
	},
	"z1_missile": {
		"name": "Micro-Missile Launcher",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 18, "energy_load": 10, "atk_interval": 4.0},
		"cost": {"credits": 2500, "Fe": 20, "Cu": 10},
		"desc": "Explosive payload. High armor penetration.",
		"zone": 1
	},
	"z1_shield": {
		"name": "Basic Shield",
		"slot_type": "shield",
		"stats": {"max_shield": 40, "shield_regen": 2},
		"cost": {"credits": 1500, "Si": 20},
		"desc": "Entry-level energy barrier.",
		"zone": 1
	},
	"z1_armor": {
		"name": "Iron Plate",
		"slot_type": "armor",
		"stats": {"def": 5, "hp": 20},
		"cost": {"credits": 1500, "Fe": 25},
		"desc": "Basic hull plating. Reduces incoming damage.",
		"zone": 1
	},

	# ── ZONE 2: Asteroid Belt ──
	"z2_kinetic": {
		"name": "Gauss Rifle",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 18, "energy_load": 10, "atk_interval": 2.0},
		"cost": {"credits": 4400, "Fe": 60, "Cu": 20},
		"desc": "Electromagnetic accelerator. Armor-piercing.",
		"zone": 2, "research_req": "zone_2_access"
	},
	"z2_energy": {
		"name": "Plasma Cutter",
		"slot_type": "weapon",
		"stats": {"atk_energy": 22, "energy_load": 15, "atk_interval": 2.0},
		"cost": {"credits": 4400, "Si": 60, "Cu": 20},
		"desc": "Focused plasma stream. Melts shields.",
		"zone": 2, "research_req": "zone_2_access"
	},
	"z2_missile": {
		"name": "Concussion Missile",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 40, "energy_load": 18, "atk_interval": 4.0},
		"cost": {"credits": 5500, "Fe": 40, "C": 30},
		"desc": "Blast warhead. Devastating hull damage.",
		"zone": 2, "research_req": "zone_2_access"
	},
	"z2_shield": {
		"name": "Deflector Shield",
		"slot_type": "shield",
		"stats": {"max_shield": 88, "shield_regen": 4},
		"cost": {"credits": 3300, "Cu": 40, "Si": 20},
		"desc": "Improved barrier with regen coils.",
		"zone": 2, "research_req": "zone_2_access"
	},
	"z2_armor": {
		"name": "Carbon Fiber Plate",
		"slot_type": "armor",
		"stats": {"def": 11, "hp": 44},
		"cost": {"credits": 3300, "C": 30, "Fe": 20},
		"desc": "Lightweight composite armor.",
		"zone": 2, "research_req": "zone_2_access"
	},

	# ── ZONE 3: Mars Debris ──
	"z3_kinetic": {
		"name": "Autocannon",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 39, "energy_load": 18, "atk_interval": 2.0},
		"cost": {"credits": 9680, "Steel": 40, "Ti": 15},
		"desc": "Rapid-fire ballistic weapon.",
		"zone": 3, "research_req": "zone_3_access"
	},
	"z3_energy": {
		"name": "Cryo Beam",
		"slot_type": "weapon",
		"stats": {"atk_energy": 48, "energy_load": 25, "atk_interval": 2.0},
		"cost": {"credits": 9680, "Si": 100, "Ti": 15},
		"desc": "Helium-cooled beam. Extreme shield damage.",
		"zone": 3, "research_req": "zone_3_access"
	},
	"z3_missile": {
		"name": "Heavy Torpedo",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 87, "energy_load": 30, "atk_interval": 4.0},
		"cost": {"credits": 12100, "Steel": 60, "C": 40},
		"desc": "Armor-busting ordnance.",
		"zone": 3, "research_req": "zone_3_access"
	},
	"z3_shield": {
		"name": "Hardened Shield",
		"slot_type": "shield",
		"stats": {"max_shield": 194, "shield_regen": 9},
		"cost": {"credits": 7260, "Ti": 25, "Circuit": 10},
		"desc": "Military-grade energy barrier.",
		"zone": 3, "research_req": "zone_3_access"
	},
	"z3_armor": {
		"name": "Composite Plate",
		"slot_type": "armor",
		"stats": {"def": 24, "hp": 97},
		"cost": {"credits": 7260, "Steel": 30, "Ti": 10},
		"desc": "Layered ceramic-metal composite.",
		"zone": 3, "research_req": "zone_3_access"
	},

	# ── ZONE 4: Cryofield ──
	"z4_kinetic": {
		"name": "Railgun Mk.II",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 86, "energy_load": 30, "atk_interval": 2.0},
		"cost": {"credits": 21296, "Steel": 80, "AdvCircuit": 9},
		"desc": "High-velocity slug launcher.",
		"zone": 4, "research_req": "zone_4_access"
	},
	"z4_energy": {
		"name": "Ion Lance",
		"slot_type": "weapon",
		"stats": {"atk_energy": 106, "energy_load": 40, "atk_interval": 2.0},
		"cost": {"credits": 21296, "Ti": 60, "AdvCircuit": 9},
		"desc": "Concentrated ion stream.",
		"zone": 4, "research_req": "zone_4_access"
	},
	"z4_missile": {
		"name": "Cluster Warhead",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 192, "energy_load": 45, "atk_interval": 4.0},
		"cost": {"credits": 26620, "Steel": 100, "Chip": 18},
		"desc": "Splits into sub-munitions on impact.",
		"zone": 4, "research_req": "zone_4_access"
	},
	"z4_shield": {
		"name": "Cryo Shield",
		"slot_type": "shield",
		"stats": {"max_shield": 426, "shield_regen": 21},
		"cost": {"credits": 15972, "Ti": 40, "AdvCircuit": 14},
		"desc": "Supercooled barrier matrix.",
		"zone": 4, "research_req": "zone_4_access"
	},
	"z4_armor": {
		"name": "Stainless Armor",
		"slot_type": "armor",
		"stats": {"def": 53, "hp": 213},
		"cost": {"credits": 15972, "Steel": 60, "Ti": 20, "GalvanizedSteel": 10},
		"desc": "Corrosion-resistant alloy plating.",
		"zone": 4, "research_req": "zone_4_access"
	},

	# ── ZONE 5: Xenon Territory ──
	"z5_kinetic": {
		"name": "Gauss Cannon",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 189, "energy_load": 50, "atk_interval": 2.0},
		"cost": {"credits": 46851, "Superalloy": 20, "QuantumCore": 2},
		"desc": "Capital-grade magnetic accelerator.",
		"zone": 5, "research_req": "zone_5_access"
	},
	"z5_energy": {
		"name": "Particle Beam",
		"slot_type": "weapon",
		"stats": {"atk_energy": 234, "energy_load": 60, "atk_interval": 2.0},
		"cost": {"credits": 46851, "Ti": 100, "QuantumCore": 2, "Au": 10},
		"desc": "Accelerated particles strip shields instantly.",
		"zone": 5, "research_req": "zone_5_access"
	},
	"z5_missile": {
		"name": "Seeker Torpedo",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 422, "energy_load": 70, "atk_interval": 4.0},
		"cost": {"credits": 58564, "Superalloy": 30, "Chip": 20},
		"desc": "AI-guided ordnance. Never misses.",
		"zone": 5, "research_req": "zone_5_access"
	},
	"z5_shield": {
		"name": "Xenon Barrier",
		"slot_type": "shield",
		"stats": {"max_shield": 937, "shield_regen": 46},
		"cost": {"credits": 35138, "VoidArtifact": 5, "AdvCircuit": 20, "StainlessSteel": 8},
		"desc": "Reverse-engineered alien shielding.",
		"zone": 5, "research_req": "zone_5_access"
	},
	"z5_armor": {
		"name": "Superalloy Plate",
		"slot_type": "armor",
		"stats": {"def": 117, "hp": 469},
		"cost": {"credits": 35138, "Superalloy": 15, "Steel": 100, "StainlessSteel": 8},
		"desc": "Dense metamaterial hull plating.",
		"zone": 5, "research_req": "zone_5_access"
	},

	# ── ZONE 6: Sector Beta ──
	"z6_kinetic": {
		"name": "Siege Cannon",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 416, "energy_load": 80, "atk_interval": 2.0},
		"cost": {"credits": 103072, "Superalloy": 50, "AdvCircuit": 30},
		"desc": "Colony-siege grade ballistic weapon.",
		"zone": 6, "research_req": "zone_6_access"
	},
	"z6_energy": {
		"name": "Plasma Lancer",
		"slot_type": "weapon",
		"stats": {"atk_energy": 514, "energy_load": 90, "atk_interval": 2.0},
		"cost": {"credits": 103072, "QuantumCore": 5, "AdvCircuit": 30},
		"desc": "Sustained plasma discharge.",
		"zone": 6, "research_req": "zone_6_access"
	},
	"z6_missile": {
		"name": "Antimatter Warhead",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 928, "energy_load": 100, "atk_interval": 4.0},
		"cost": {"credits": 128840, "Superalloy": 60, "QuantumCore": 5},
		"desc": "Annihilation-class ordnance.",
		"zone": 6, "research_req": "zone_6_access"
	},
	"z6_shield": {
		"name": "Reactive Barrier",
		"slot_type": "shield",
		"stats": {"max_shield": 2062, "shield_regen": 103},
		"cost": {"credits": 77304, "VoidArtifact": 15, "QuantumCore": 5},
		"desc": "Adapts to incoming damage patterns.",
		"zone": 6, "research_req": "zone_6_access"
	},
	"z6_armor": {
		"name": "Iridium Armor",
		"slot_type": "armor",
		"stats": {"def": 257, "hp": 1031},
		"cost": {"credits": 77304, "Ir": 10, "Superalloy": 40},
		"desc": "Ultra-dense rare earth plating.",
		"zone": 6, "research_req": "zone_6_access"
	},

	# ── ZONE 7: Sector Gamma ──
	"z7_kinetic": {
		"name": "Neutron Slugger",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 916, "energy_load": 120, "atk_interval": 2.0},
		"cost": {"credits": 226758, "ExoticMatter": 10, "Ir": 10, "IrWAlloy": 5, "AdvCircuit": 40},
		"desc": "Fires neutron-dense projectiles.",
		"zone": 7, "research_req": "zone_7_access"
	},
	"z7_energy": {
		"name": "Void Beam",
		"slot_type": "weapon",
		"stats": {"atk_energy": 1131, "energy_load": 140, "atk_interval": 2.0},
		"cost": {"credits": 226758, "ExoticMatter": 10, "VoidCrystal": 5, "AdvCircuit": 40},
		"desc": "Drains energy from realspace.",
		"zone": 7, "research_req": "zone_7_access"
	},
	"z7_missile": {
		"name": "Singularity Bomb",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 2042, "energy_load": 160, "atk_interval": 4.0},
		"cost": {"credits": 283448, "ExoticMatter": 15, "QuantumCore": 10, "Chip": 55},
		"desc": "Creates micro-singularity on impact.",
		"zone": 7, "research_req": "zone_7_access"
	},
	"z7_shield": {
		"name": "Exotic Shield Matrix",
		"slot_type": "shield",
		"stats": {"max_shield": 4536, "shield_regen": 226},
		"cost": {"credits": 170069, "ExoticMatter": 8, "VoidCrystal": 5, "AdvCircuit": 35},
		"desc": "Exotic matter barrier. Near-impervious.",
		"zone": 7, "research_req": "zone_7_access"
	},
	"z7_armor": {
		"name": "Osmium Core Plate",
		"slot_type": "armor",
		"stats": {"def": 565, "hp": 2268},
		"cost": {"credits": 170069, "Os": 5, "ExoticMatter": 5},
		"desc": "Densest material known to science.",
		"zone": 7, "research_req": "zone_7_access"
	},

	# ── ZONE 8: Sector Delta ──
	"z8_kinetic": {
		"name": "Prismatic Railgun",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 2015, "energy_load": 180, "atk_interval": 2.0},
		"cost": {"credits": 498868, "VoidCrystal": 10, "StructuralLattice": 2, "NeutroniumPlate": 2, "Steel": 4500},
		"desc": "Crystal-focused kinetic lance.",
		"zone": 8, "research_req": "zone_8_access"
	},
	"z8_energy": {
		"name": "Prism Annihilator",
		"slot_type": "weapon",
		"stats": {"atk_energy": 2489, "energy_load": 200, "atk_interval": 2.0},
		"cost": {"credits": 498868, "VoidCrystal": 10, "ExoticMatter": 10, "StructuralLattice": 2, "Ti": 3500},
		"desc": "Refracted energy cascade.",
		"zone": 8, "research_req": "zone_8_access"
	},
	"z8_missile": {
		"name": "Quantum Torpedo",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 4493, "energy_load": 240, "atk_interval": 4.0},
		"cost": {"credits": 623585, "QuantumCore": 20, "StructuralLattice": 3, "NeutroniumPlate": 3, "Steel": 5500},
		"desc": "Exists in superposition until detonation.",
		"zone": 8, "research_req": "zone_8_access"
	},
	"z8_shield": {
		"name": "Prismatic Barrier",
		"slot_type": "shield",
		"stats": {"max_shield": 9980, "shield_regen": 499},
		"cost": {"credits": 374151, "VoidCrystal": 8, "ExoticMatter": 10, "StructuralLattice": 1, "Ti": 3000},
		"desc": "Crystal lattice energy barrier.",
		"zone": 8, "research_req": "zone_8_access"
	},
	"z8_armor": {
		"name": "Diamond Core Plate",
		"slot_type": "armor",
		"stats": {"def": 1244, "hp": 4990},
		"cost": {"credits": 374151, "Diamond": 5, "VoidCrystal": 5, "StructuralLattice": 2, "NeutroniumPlate": 2, "Steel": 4000},
		"desc": "Carbon-lattice super-structure.",
		"zone": 8, "research_req": "zone_8_access"
	},

	# ── ZONE 9: Sector Zeta ──
	"z9_kinetic": {
		"name": "Pathogen Cannon",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 4432, "energy_load": 260, "atk_interval": 2.0},
		"cost": {"credits": 1097510, "BiohazardSample": 20, "BioReactorCore": 3, "Neutronium": 180, "Steel": 9000},
		"desc": "Bio-corrosive projectiles.",
		"zone": 9, "research_req": "zone_9_access"
	},
	"z9_energy": {
		"name": "Zero-Point Beam",
		"slot_type": "weapon",
		"stats": {"atk_energy": 5476, "energy_load": 300, "atk_interval": 2.0},
		"cost": {"credits": 1097510, "ChronoCore": 2, "BioReactorCore": 3, "Neutronium": 180, "Ti": 8000},
		"desc": "Extracts energy from vacuum fluctuations.",
		"zone": 9, "research_req": "zone_9_access"
	},
	"z9_missile": {
		"name": "Biohazard Warhead",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 9885, "energy_load": 350, "atk_interval": 4.0},
		"cost": {"credits": 1371888, "BiohazardSample": 30, "BioReactorCore": 4, "Neutronium": 200, "Steel": 11000},
		"desc": "Viral payload. Corrodes all matter.",
		"zone": 9, "research_req": "zone_9_access"
	},
	"z9_shield": {
		"name": "Quarantine Barrier",
		"slot_type": "shield",
		"stats": {"max_shield": 21956, "shield_regen": 1097},
		"cost": {"credits": 823132, "PathogenCore": 5, "BioReactorCore": 2, "Neutronium": 150, "Ti": 7000},
		"desc": "Containment-grade barrier field.",
		"zone": 9, "research_req": "zone_9_access"
	},
	"z9_armor": {
		"name": "Neutronium Plate",
		"slot_type": "armor",
		"stats": {"def": 2737, "hp": 10978},
		"cost": {"credits": 823132, "Os": 5, "NeutroniumPlate": 4, "Neutronium": 180, "Steel": 9000},
		"desc": "Neutron-star density alloy.",
		"zone": 9, "research_req": "zone_9_access"
	},

	# ── ZONE 10: Sector Epsilon ──
	"z10_kinetic": {
		"name": "Omega Cannon",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 9751, "energy_load": 400, "atk_interval": 2.0},
		"cost": {"credits": 2414522, "PrimordialShard": 5, "PrimordialMatrix": 3, "OmegaComposite": 2, "Neutronium": 200, "Steel": 13000},
		"desc": "Final evolution of kinetic warfare.",
		"zone": 10, "research_req": "zone_10_access"
	},
	"z10_energy": {
		"name": "Chrono Disruptor",
		"slot_type": "weapon",
		"stats": {"atk_energy": 12047, "energy_load": 450, "atk_interval": 2.0},
		"cost": {"credits": 2414522, "ChronoCore": 5, "PrimordialMatrix": 3, "OmegaComposite": 2, "Neutronium": 200, "Ti": 11000},
		"desc": "Tears through spacetime itself.",
		"zone": 10, "research_req": "zone_10_access"
	},
	"z10_missile": {
		"name": "Void Annihilator",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 21747, "energy_load": 500, "atk_interval": 4.0},
		"cost": {"credits": 3018153, "PrimordialShard": 8, "PrimordialMatrix": 4, "OmegaComposite": 3, "Neutronium": 220, "Steel": 15000},
		"desc": "Erases matter from existence.",
		"zone": 10, "research_req": "zone_10_access"
	},
	"z10_shield": {
		"name": "Void Aegis",
		"slot_type": "shield",
		"stats": {"max_shield": 48304, "shield_regen": 2415},
		"cost": {"credits": 1810891, "VoidEssence": 10, "PrimordialMatrix": 2, "OmegaComposite": 2, "Neutronium": 170, "Ti": 9000},
		"desc": "Reality-bending shield barrier.",
		"zone": 10, "research_req": "zone_10_access"
	},
	"z10_armor": {
		"name": "Primordial Bulkhead",
		"slot_type": "armor",
		"stats": {"def": 6022, "hp": 24152},
		"cost": {"credits": 1810891, "PrimordialShard": 3, "PrimordialMatrix": 3, "OmegaComposite": 2, "Neutronium": 200, "Steel": 13000},
		"desc": "Forged from primordial matter.",
		"zone": 10, "research_req": "zone_10_access"
	},

	# ── ENGINE SYSTEMS (10 Zones) ──
	"z1_engine": {
		"name": "Basic Thruster", "slot_type": "engine", "stats": {"eva": 4},
		"cost": {"credits": 1200, "Fe": 15}, "zone": 1
	},
	"z2_engine": {
		"name": "Plasma Drive", "slot_type": "engine", "stats": {"eva": 5},
		"cost": {"credits": 2800, "Cu": 30, "Si": 15}, "zone": 2, "research_req": "zone_2_access"
	},
	"z3_engine": {
		"name": "Ion Engine", "slot_type": "engine", "stats": {"eva": 6},
		"cost": {"credits": 6500, "Steel": 25, "Ti": 10}, "zone": 3, "research_req": "zone_3_access"
	},
	"z4_engine": {
		"name": "Cryo-Pulse Drive", "slot_type": "engine", "stats": {"eva": 7},
		"cost": {"credits": 15000, "Ti": 50, "AdvCircuit": 5}, "zone": 4, "research_req": "zone_4_access"
	},
	"z5_engine": {
		"name": "Superalloy Engine", "slot_type": "engine", "stats": {"eva": 9},
		"cost": {"credits": 35000, "Superalloy": 15, "Chip": 10}, "zone": 5, "research_req": "zone_5_access"
	},
	"z6_engine": {
		"name": "Antimatter Engine", "slot_type": "engine", "stats": {"eva": 10},
		"cost": {"credits": 80000, "Superalloy": 40, "QuantumCore": 2}, "zone": 6, "research_req": "zone_6_access"
	},
	"z7_engine": {
		"name": "Void Engine", "slot_type": "engine", "stats": {"eva": 11},
		"cost": {"credits": 180000, "ExoticMatter": 5, "Ir": 5}, "zone": 7, "research_req": "zone_7_access"
	},
	"z8_engine": {
		"name": "Quantum Drive", "slot_type": "engine", "stats": {"eva": 12},
		"cost": {"credits": 420000, "VoidCrystal": 10, "Os": 5}, "zone": 8, "research_req": "zone_8_access"
	},
	"z9_engine": {
		"name": "Temporal Drive", "slot_type": "engine", "stats": {"eva": 13},
		"cost": {"credits": 950000, "Neutronium": 5, "ChronoCore": 2}, "zone": 9, "research_req": "zone_9_access"
	},
	"z10_engine": {
		"name": "Leviathan Engine", "slot_type": "engine", "stats": {"eva": 15},
		"cost": {"credits": 2200000, "PrimordialShard": 2, "OmegaPlating": 5}, "zone": 10, "research_req": "zone_10_access"
	},

	# ── POWER SYSTEMS (10 Zones) ──
	"z1_battery": {
		"name": "Basic Battery", "slot_type": "battery", "stats": {"energy_capacity": 50},
		"cost": {"credits": 1000,"Fe":10}, "zone": 1
	},
	"z2_battery": {
		"name": "Improved Battery", "slot_type": "battery", "stats": {"energy_capacity": 110},
		"cost": {"credits": 2500, "Cu": 25, "Si": 10}, "zone": 2, "research_req": "zone_2_access"
	},
	"z3_battery": {
		"name": "Co-Li Battery", "slot_type": "battery", "stats": {"energy_capacity": 242},
		"cost": {"credits": 6000, "CoBattery": 3, "Mn": 8}, "zone": 3, "research_req": "zone_3_access"
	},
	"z4_battery": {
		"name": "Mg-Ion Cell", "slot_type": "battery", "stats": {"energy_capacity": 532},
		"cost": {"credits": 14000, "Mg": 30, "AdvCircuit": 5}, "zone": 4, "research_req": "zone_4_access"
	},
	"z5_battery": {
		"name": "Quantum Cell", "slot_type": "battery", "stats": {"energy_capacity": 1171},
		"cost": {"credits": 32000, "QuantumCore": 1, "Si": 100}, "zone": 5, "research_req": "zone_5_access"
	},
	"z6_battery": {
		"name": "Reactive Core", "slot_type": "battery", "stats": {"energy_capacity": 2577},
		"cost": {"credits": 75000, "ReactiveCore": 2, "AdvCircuit": 20}, "zone": 6, "research_req": "zone_6_access"
	},
	"z7_battery": {
		"name": "Exotic Matrix", "slot_type": "battery", "stats": {"energy_capacity": 5669},
		"cost": {"credits": 170000, "ExoticMatter": 5, "VoidCrystal": 5}, "zone": 7, "research_req": "zone_7_access"
	},
	"z8_battery": {
		"name": "Void Battery", "slot_type": "battery", "stats": {"energy_capacity": 12473},
		"cost": {"credits": 400000, "VoidCrystal": 15, "Os": 5}, "zone": 8, "research_req": "zone_8_access"
	},
	"z9_battery": {
		"name": "Neutronium Core", "slot_type": "battery", "stats": {"energy_capacity": 27440},
		"cost": {"credits": 900000, "Neutronium": 10, "Diamond": 2}, "zone": 9, "research_req": "zone_9_access"
	},
	"z10_battery": {
		"name": "Omega Battery", "slot_type": "battery", "stats": {"energy_capacity": 60369},
		"cost": {"credits": 2100000, "PrimordialShard": 5, "OmegaPlating": 5}, "zone": 10, "research_req": "zone_10_access"
	},

	# ── SENSOR SUITES (10 Zones) ──
	"z1_sensor": {
		"name": "Lidar Array", "slot_type": "sensor", "stats": {"accuracy": 30},
		"cost": {"credits": 1500, "Si": 20}, "zone": 1
	},
	"z2_sensor": {
		"name": "Optical Scanner", "slot_type": "sensor", "stats": {"accuracy": 40},
		"cost": {"credits": 3500, "Si": 40, "Cu": 20}, "zone": 2, "research_req": "zone_2_access"
	},
	"z3_sensor": {
		"name": "Deep Space Radar", "slot_type": "sensor", "stats": {"accuracy": 50},
		"cost": {"credits": 8000, "Circuit": 15, "Ti": 10}, "zone": 3, "research_req": "zone_3_access"
	},
	"z4_sensor": {
		"name": "Phased Array", "slot_type": "sensor", "stats": {"accuracy": 60},
		"cost": {"credits": 18000, "AdvCircuit": 10, "Ti": 30, "Au": 5}, "zone": 4, "research_req": "zone_4_access"
	},
	"z5_sensor": {
		"name": "AI Targeting", "slot_type": "sensor", "stats": {"accuracy": 70},
		"cost": {"credits": 42000, "AICore": 1, "Chip": 15}, "zone": 5, "research_req": "zone_5_access"
	},
	"z6_sensor": {
		"name": "Quantum Scanner", "slot_type": "sensor", "stats": {"accuracy": 80},
		"cost": {"credits": 95000, "QuantumCore": 3, "AdvCircuit": 25}, "zone": 6, "research_req": "zone_6_access"
	},
	"z7_sensor": {
		"name": "Exotic Lens", "slot_type": "sensor", "stats": {"accuracy": 90},
		"cost": {"credits": 210000, "ExoticMatter": 5, "VoidCrystal": 5}, "zone": 7, "research_req": "zone_7_access"
	},
	"z8_sensor": {
		"name": "Omni-Scanner", "slot_type": "sensor", "stats": {"accuracy": 100},
		"cost": {"credits": 480000, "VoidArtifact": 10, "Os": 5}, "zone": 8, "research_req": "zone_8_access"
	},
	"z9_sensor": {
		"name": "Temporal Tracker", "slot_type": "sensor", "stats": {"accuracy": 110},
		"cost": {"credits": 1100000, "ChronoCore": 3, "Neutronium": 5}, "zone": 9, "research_req": "zone_9_access"
	},
	"z10_sensor": {
		"name": "Oracle Array", "slot_type": "sensor", "stats": {"accuracy": 120},
		"cost": {"credits": 2500000, "PrimordialShard": 5, "OmegaPlating": 5}, "zone": 10, "research_req": "zone_10_access"
	},

	# ── MATRIX CORES (Sockets) ──
	"matrix_synthesis": {
		"name": "Matrix Synthesis", "slot_type": "gem", "stats": {},
		"cost": {"credits": 20000, "NavData": 10, "Res1": 25},
		"desc": "Synthesize a random Cracked Matrix Core.", "zone": 2, "research_req": "zone_2_access"
	},
	"cracked_crimson_core": {
		"name": "Fuse Stable Crimson", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 50000, "CrackedCrimsonCore": 3},
		"desc": "Fuses 3 Cracked Crimson cores into 1 Stable version.", "zone": 3
	},
	"stable_crimson_core": {
		"name": "Fuse Pristine Crimson", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 250000, "StableCrimsonCore": 3},
		"desc": "Fuses 3 Stable Crimson cores into 1 Pristine version.", "zone": 5
	},
	"cracked_cobalt_core": {
		"name": "Fuse Stable Cobalt", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 50000, "CrackedCobaltCore": 3},
		"desc": "Fuses 3 Cracked Cobalt cores into 1 Stable version.", "zone": 3
	},
	"stable_cobalt_core": {
		"name": "Fuse Pristine Cobalt", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 250000, "StableCobaltCore": 3},
		"desc": "Fuses 3 Stable Cobalt cores into 1 Pristine version.", "zone": 5
	},
	"cracked_topaz_core": {
		"name": "Fuse Stable Topaz", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 50000, "CrackedTopazCore": 3},
		"desc": "Fuses 3 Cracked Topaz cores into 1 Stable version.", "zone": 3
	},
	"stable_topaz_core": {
		"name": "Fuse Pristine Topaz", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 250000, "StableTopazCore": 3},
		"desc": "Fuses 3 Stable Topaz cores into 1 Pristine version.", "zone": 5
	},
	"cracked_amethyst_core": {
		"name": "Fuse Stable Amethyst", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 50000, "CrackedAmethystCore": 3},
		"desc": "Fuses 3 Cracked Amethyst cores into 1 Stable version.", "zone": 3
	},
	"stable_amethyst_core": {
		"name": "Fuse Pristine Amethyst", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 250000, "StableAmethystCore": 3},
		"desc": "Fuses 3 Stable Amethyst cores into 1 Pristine version.", "zone": 5
	},

	# ═══════════════════════════════════════════════════════════════
	# v80.1: Unique Trinity Set Modules — 2.8x base stats per zone
	# 3 per zone boss (Weapon, Armor, Shield) = 30 total
	# All have: rarity=UNIQUE, 4 affixes, 3 matrix sockets
	# ═══════════════════════════════════════════════════════════════

	# ── Z1: Architect's Regalia (+15% ATK Speed, +5 HP Regen/tick) ──
	"z1_unique_weapon": {
		"name": "Architect's Beam", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 16, "energy_load": 12, "atk_interval": 2.0},
		"cost": {}, "desc": "Precision-engineered energy weapon.", "zone": 1,
		"set_id": "architects_regalia", "is_unique": true
	},
	"z1_unique_armor": {
		"name": "Architect's Plating", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 8, "hp": 32},
		"cost": {}, "desc": "Blueprint-perfect hull reinforcement.", "zone": 1,
		"set_id": "architects_regalia", "is_unique": true
	},
	"z1_unique_shield": {
		"name": "Architect's Ward", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 64, "shield_regen": 3},
		"cost": {}, "desc": "Geometrically perfect barrier field.", "zone": 1,
		"set_id": "architects_regalia", "is_unique": true
	},

	# ── Z2: Monolith's Bedrock (+10% DEF, Reflect 5% dmg) ──
	"z2_unique_weapon": {
		"name": "Monolith's Shatter", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 28, "energy_load": 18, "atk_interval": 2.0},
		"cost": {}, "desc": "Crystalline projectile launcher.", "zone": 2,
		"set_id": "monoliths_bedrock", "is_unique": true
	},
	"z2_unique_armor": {
		"name": "Monolith's Shell", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 17, "hp": 70},
		"cost": {}, "desc": "Silicate-hardened hull plating.", "zone": 2,
		"set_id": "monoliths_bedrock", "is_unique": true
	},
	"z2_unique_shield": {
		"name": "Monolith's Barrier", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 140, "shield_regen": 6},
		"cost": {}, "desc": "Stone-resonance energy barrier.", "zone": 2,
		"set_id": "monoliths_bedrock", "is_unique": true
	},

	# v86.0: Hazard Zone Counter Equipment
	"faraday_hull": {
		"name": "Faraday Hull", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 20, "hp": 80},
		"cost": {}, "desc": "EMP-shielded armor plating with integrated electromagnetic dampeners. Grants immunity to weapon jamming in the EMP Nexus.", "zone": 2,
		"is_unique": true, "special": "emp_immunity"
	},

	# ── Z3: Warmaster's Arsenal (+12% Crit Chance, +8% ATK) ──
	"z3_unique_weapon": {
		"name": "Warmaster's Railgun", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 62, "energy_load": 30, "atk_interval": 2.0},
		"cost": {}, "desc": "Mars-forged magnetic accelerator.", "zone": 3,
		"set_id": "warmasters_arsenal", "is_unique": true
	},
	"z3_unique_armor": {
		"name": "Warmaster's Bulkhead", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 38, "hp": 155},
		"cost": {}, "desc": "Battle-scarred Martian alloy.", "zone": 3,
		"set_id": "warmasters_arsenal", "is_unique": true
	},
	"z3_unique_shield": {
		"name": "Warmaster's Aegis", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 310, "shield_regen": 14},
		"cost": {}, "desc": "Command-grade barrier matrix.", "zone": 3,
		"set_id": "warmasters_arsenal", "is_unique": true
	},

	# ── Z4: Overseer's Command (+10% Shield Regen, +50 Accuracy) ──
	"z4_unique_weapon": {
		"name": "Overseer's Lance", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 169, "energy_load": 50, "atk_interval": 2.0},
		"cost": {}, "desc": "Cryo-focused targeting lance.", "zone": 4,
		"set_id": "overseers_command", "is_unique": true
	},
	"z4_unique_armor": {
		"name": "Overseer's Carapace", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 84, "hp": 340},
		"cost": {}, "desc": "Ice-tempered composite armor.", "zone": 4,
		"set_id": "overseers_command", "is_unique": true
	},
	"z4_unique_shield": {
		"name": "Overseer's Dome", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 681, "shield_regen": 33},
		"cost": {}, "desc": "Cryo-stabilized barrier dome.", "zone": 4,
		"set_id": "overseers_command", "is_unique": true
	},

	# ── Z5: Harbinger's Wrath (+15% Missile DMG, -10% Enemy DEF) ──
	"z5_unique_weapon": {
		"name": "Harbinger's Fury", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 675, "energy_load": 90, "atk_interval": 4.0},
		"cost": {}, "desc": "Xenon doomsday missile platform.", "zone": 5,
		"set_id": "harbingers_wrath", "is_unique": true
	},
	"z5_unique_armor": {
		"name": "Harbinger's Bastion", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 187, "hp": 750},
		"cost": {}, "desc": "Alien-alloy hull reinforcement.", "zone": 5,
		"set_id": "harbingers_wrath", "is_unique": true
	},
	"z5_unique_shield": {
		"name": "Harbinger's Veil", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 1499, "shield_regen": 73},
		"cost": {}, "desc": "Xenon phase-shift barrier.", "zone": 5,
		"set_id": "harbingers_wrath", "is_unique": true
	},

	# ── Z6: Colossus Dominion (+12% All DMG, +5% Evasion) ──
	"z6_unique_weapon": {
		"name": "Colossus Cannon", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 665, "energy_load": 120, "atk_interval": 2.0},
		"cost": {}, "desc": "Colony-siege superweapon.", "zone": 6,
		"set_id": "colossus_dominion", "is_unique": true
	},
	"z6_unique_armor": {
		"name": "Colossus Bulwark", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 411, "hp": 1649},
		"cost": {}, "desc": "Gamma-hardened ultra-plating.", "zone": 6,
		"set_id": "colossus_dominion", "is_unique": true
	},
	"z6_unique_shield": {
		"name": "Colossus Aegis", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 3299, "shield_regen": 164},
		"cost": {}, "desc": "Radiation-dampening barrier.", "zone": 6,
		"set_id": "colossus_dominion", "is_unique": true
	},

	# ── Z7: Sovereign's Prism (+300 DEF, +10% Energy DMG) ──
	"z7_unique_weapon": {
		"name": "Sovereign's Ray", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 1809, "energy_load": 180, "atk_interval": 2.0},
		"cost": {}, "desc": "Prismatic energy cascade.", "zone": 7,
		"set_id": "sovereigns_prism", "is_unique": true
	},
	"z7_unique_armor": {
		"name": "Sovereign's Mantle", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 904, "hp": 3628},
		"cost": {}, "desc": "Exotic-matter woven hull.", "zone": 7,
		"set_id": "sovereigns_prism", "is_unique": true
	},
	"z7_unique_shield": {
		"name": "Sovereign's Corona", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 7257, "shield_regen": 361},
		"cost": {}, "desc": "Reality-bending shield aura.", "zone": 7,
		"set_id": "sovereigns_prism", "is_unique": true
	},

	# ── Z8: Warden's Quarantine (+20% Shield HP, +8% Crit) ──
	"z8_unique_weapon": {
		"name": "Warden's Scalpel", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 3982, "energy_load": 280, "atk_interval": 2.0},
		"cost": {}, "desc": "Crystal-focused annihilation beam.", "zone": 8,
		"set_id": "wardens_quarantine", "is_unique": true
	},
	"z8_unique_armor": {
		"name": "Warden's Containment", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 1990, "hp": 7984},
		"cost": {}, "desc": "Diamond-lattice containment hull.", "zone": 8,
		"set_id": "wardens_quarantine", "is_unique": true
	},
	"z8_unique_shield": {
		"name": "Warden's Lockdown", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 15968, "shield_regen": 798},
		"cost": {}, "desc": "Prismatic containment barrier.", "zone": 8,
		"set_id": "wardens_quarantine", "is_unique": true
	},

	# ── Z9: Titan's Legacy (+15% All DMG, +500 DEF) ──
	"z9_unique_weapon": {
		"name": "Titan's Wrath", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 7091, "energy_load": 400, "atk_interval": 2.0},
		"cost": {}, "desc": "Neutronium-core mass driver.", "zone": 9,
		"set_id": "titans_legacy", "is_unique": true
	},
	"z9_unique_armor": {
		"name": "Titan's Aegis", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 4379, "hp": 17564},
		"cost": {}, "desc": "Neutron-star density plating.", "zone": 9,
		"set_id": "titans_legacy", "is_unique": true
	},
	"z9_unique_shield": {
		"name": "Titan's Bulwark", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 35129, "shield_regen": 1755},
		"cost": {}, "desc": "Containment-grade mega-barrier.", "zone": 9,
		"set_id": "titans_legacy", "is_unique": true
	},

	# ── Z10: Leviathan's Crown (+20% All DMG, +1000 HP Regen/tick) ──
	"z10_unique_weapon": {
		"name": "Leviathan's Maw", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 34795, "energy_load": 600, "atk_interval": 4.0},
		"cost": {}, "desc": "Reality-ending void warhead.", "zone": 10,
		"set_id": "leviathans_crown", "is_unique": true
	},
	"z10_unique_armor": {
		"name": "Leviathan's Hide", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 9635, "hp": 38643},
		"cost": {}, "desc": "Primordial matter hull.", "zone": 10,
		"set_id": "leviathans_crown", "is_unique": true
	},
	"z10_unique_shield": {
		"name": "Leviathan's Dominion", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 77286, "shield_regen": 3864},
		"cost": {}, "desc": "Void-sovereign barrier field.", "zone": 10,
		"set_id": "leviathans_crown", "is_unique": true
	}
}


func _init():
	_scale_mid_late_module_item_costs()
	recalc_stats()
	_migrate_module_entries_from_resources()

func _scale_mid_late_module_item_costs() -> void:
	if _module_item_costs_scaled:
		return
	_module_item_costs_scaled = true
	
	for module_id in modules:
		var m_data = modules[module_id]
		if m_data.get("is_custom", false):
			continue
		var slot_type = str(m_data.get("slot_type", ""))
		if slot_type == "gem" or slot_type == "gem_synth":
			continue
		if not m_data.has("cost"):
			continue
		
		var stage = _get_module_cost_stage(m_data)
		if stage <= 0:
			continue
		
		var mult = MID_MODULE_ITEM_REQ_MULT if stage == 1 else LATE_MODULE_ITEM_REQ_MULT
		var cost_dict: Dictionary = m_data["cost"]
		for res in cost_dict:
			if res == "credits":
				continue
			var qty = int(cost_dict[res])
			if qty <= 0:
				continue
			cost_dict[res] = _scale_item_requirement(qty, mult)
		
		m_data["cost"] = cost_dict
		modules[module_id] = m_data

func _get_module_cost_stage(m_data: Dictionary) -> int:
	var req = str(m_data.get("research_req", ""))
	var cost: Dictionary = m_data.get("cost", {})
	
	for res in cost:
		if res in LATE_MODULE_ITEMS:
			return 2
	if req in LATE_MODULE_REQ_TECHS:
		return 2
	
	for res in cost:
		if res in MID_MODULE_ITEMS:
			return 1
	if req == "":
		return 0
	if req in EARLY_MODULE_REQ_TECHS:
		return 0
	return 1

func _scale_item_requirement(base_qty: int, multiplier: float) -> int:
	var scaled = int(ceil(float(base_qty) * multiplier))
	if scaled <= base_qty:
		return base_qty + 1
	return scaled

func _migrate_atk_interval_caps() -> void:
	# Retroactive migration: older saves contain weapon drops where atk_interval
	# was rolled below the new -40% reduction floor (formula coefficient lowered
	# from 0.4 → 0.15). Clamp those values to base × 0.6 so cross-tier outliers
	# get rebalanced. Damage stats are untouched.
	var clamped := 0
	for mid in custom_modules.keys():
		var m: Dictionary = custom_modules[mid]
		var stats: Dictionary = m.get("stats", {})
		if not stats.has("atk_interval"):
			continue
		var base_id: String = m.get("base_module", "")
		if base_id == "" or not base_id in modules:
			continue
		var base_interval: float = float(modules[base_id].get("stats", {}).get("atk_interval", 0.0))
		if base_interval <= 0.0:
			continue
		var floor_val: float = base_interval * 0.6
		var cur: float = float(stats["atk_interval"])
		if cur < floor_val:
			var new_val := snappedf(floor_val, 0.01)
			stats["atk_interval"] = new_val
			# The modules dict is a live mirror that contains custom_modules — keep them in sync.
			if mid in modules:
				modules[mid]["stats"]["atk_interval"] = new_val
			clamped += 1
	if clamped > 0:
		print("[Migration] Clamped atk_interval on %d existing custom module(s) to new -40%% floor." % clamped)

func _migrate_module_entries_from_resources() -> void:
	if not GameState or not GameState.resources:
		return
	
	var moved_any = false
	var symbols_to_remove: Array = []
	for symbol in GameState.resources.elements.keys():
		if symbol in modules:
			var qty = int(GameState.resources.elements.get(symbol, 0))
			if qty > 0:
				module_inventory[symbol] = module_inventory.get(symbol, 0) + qty
				symbols_to_remove.append(symbol)
				moved_any = true
	
	for symbol in symbols_to_remove:
		var qty_left = GameState.resources.get_element_amount(symbol)
		if qty_left > 0:
			GameState.resources.remove_element(symbol, qty_left)
	
	if moved_any:
		new_drops_alert = true
		inventory_updated.emit()

## v109: Grant a fixed module straight into inventory (no cost, no rarity roll).
## Used by the first-Warp Cryo grant and Z11+ Cryo drops.
func grant_module(mid: String, qty: int = 1) -> void:
	if not mid in modules:
		return
	module_inventory[mid] = module_inventory.get(mid, 0) + qty
	unseen_modules[mid] = true
	new_drops_alert = true
	inventory_updated.emit()

func construct_hull(hull_id: String) -> bool:
	if not hull_id in hulls: return false
	
	var hull_data = hulls[hull_id]
	if hull_data.get("research_req"):
		if not GameState.research_manager.is_tech_unlocked(hull_data["research_req"]):
			return false
	
	# Check Costs
	for res in hull_data["cost"]:
		var qty = hull_data["cost"][res]
		if res == "credits":
			if GameState.resources.get_currency("credits") < qty: return false
		else:
			if GameState.resources.get_element_amount(res) < qty: return false
			
	# Consume
	for res in hull_data["cost"]:
		var qty = hull_data["cost"][res]
		if res == "credits":
			GameState.resources.remove_currency("credits", qty)
		else:
			GameState.resources.remove_element(res, qty)
			
	# Snapshot the current loadout (in slot order) so it can be carried over
	# to the new hull. unequip_all() returns these to module_inventory.
	var _carry: Array = []
	var _old_idxs: Array = loadout.keys()
	_old_idxs.sort()
	for _i in _old_idxs:
		if loadout[_i]:
			_carry.append(loadout[_i])

	# Unequip All
	unequip_all()

	active_hull = hull_id
	loadout = {}
	for i in range(hull_data["slots"].size()):
		loadout[i] = null

	# Auto-transfer: re-equip each previous module into the first matching
	# free slot on the new hull. equip_module() enforces type / energy /
	# uniqueness, so anything that no longer fits simply stays in inventory
	# (never lost) instead of forcing a full manual re-equip.
	#
	# Batteries FIRST: capacity is battery-derived (hulls supply 0) and the
	# step-wise equip checks power per module — placing a consumer before any
	# battery tests it against 0 capacity, which rejects it (and used to spam
	# the power warning once per consumer), silently dropping modules that
	# actually fit. Equip silently: internal migration, the ship-status
	# indicator reports the final power state once.
	var _carry_ordered: Array = []
	for _mid in _carry:
		if _mid in modules and modules[_mid].get("slot_type", "") == "battery":
			_carry_ordered.append(_mid)
	for _mid in _carry:
		if not (_mid in modules and modules[_mid].get("slot_type", "") == "battery"):
			_carry_ordered.append(_mid)
	for _mid in _carry_ordered:
		if not _mid in modules:
			continue
		var _mtype = modules[_mid].get("slot_type", "")
		for _s in range(hull_data["slots"].size()):
			if loadout.get(_s) == null and hull_data["slots"][_s] == _mtype:
				if module_inventory.get(_mid, 0) > 0 and equip_module(_s, _mid, true):
					break

	# Recalculate to get new max_hp
	recalc_stats()
	current_hp = max_hp # Explicitly force full health for the new hull
	
	hull_constructed.emit(hull_id) # Audit v11.0: Signal for missions
	return true

func unequip_all():
	for idx in loadout:
		var mid = loadout[idx]
		if mid:
			module_inventory[mid] = module_inventory.get(mid, 0) + 1
	loadout = {}

func craft_module(module_id: String) -> bool:
	if not module_id in modules: return false
	
	var mod_data = modules[module_id]
	if mod_data.get("is_custom", false):
		print("Craft Fail: Dropped modules cannot be crafted.")
		return false
	if mod_data.get("research_req"):
		if not GameState.research_manager.is_tech_unlocked(mod_data["research_req"]):
			return false
	
	# v114: effective cost includes the zone tier-gate alloy when the gate is on.
	var craft_cost = get_effective_module_cost(mod_data)
	# Check Cost
	for res in craft_cost:
		var qty = craft_cost[res]
		if res == "credits":
			if GameState.resources.get_currency("credits") < qty: return false
		else:
			if GameState.resources.get_element_amount(res) < qty: return false

	# Consume
	for res in craft_cost:
		var qty = craft_cost[res]
		if res == "credits":
			GameState.resources.remove_currency("credits", qty)
		else:
			GameState.resources.remove_element(res, qty)
			
	# === Matrix Core Crafting Logic ===
	if module_id == "matrix_synthesis":
		# Roll random core
		var roll = randi() % 4
		var gem_id = ""
		match roll:
			0: gem_id = "CrackedCrimsonCore"
			1: gem_id = "CrackedCobaltCore"
			2: gem_id = "CrackedTopazCore"
			3: gem_id = "CrackedAmethystCore"
			_: gem_id = "CrackedCrimsonCore"
			
		GameState.resources.add_element(gem_id, 1)
		UITheme.show_notification("Synthesized: " + ElementDB.get_display_name(gem_id), Color(0.8, 0.3, 0.8))
		inventory_updated.emit()
		return true
		
	elif mod_data.get("slot_type") == "gem_synth":
		# It's an upgrade recipe, map ID to output gem
		var out_gem = ""
		match module_id:
			"cracked_crimson_core": out_gem = "StableCrimsonCore"
			"stable_crimson_core": out_gem = "PristineCrimsonCore"
			"cracked_cobalt_core": out_gem = "StableCobaltCore"
			"stable_cobalt_core": out_gem = "PristineCobaltCore"
			"cracked_topaz_core": out_gem = "StableTopazCore"
			"stable_topaz_core": out_gem = "PristineTopazCore"
			"cracked_amethyst_core": out_gem = "StableAmethystCore"
			"stable_amethyst_core": out_gem = "PristineAmethystCore"
			
		if out_gem != "":
			GameState.resources.add_element(out_gem, 1)
			UITheme.show_notification("Fused: " + ElementDB.get_display_name(out_gem), Color(0.8, 0.3, 0.8))
			inventory_updated.emit()
			return true
			
	# Normal Module Crafting
	module_inventory[module_id] = module_inventory.get(module_id, 0) + 1
	module_crafted.emit(module_id)
	inventory_updated.emit() # Fix: Signal for UI update
	return true

func equip_module(slot_idx: int, module_id: String, silent: bool = false) -> bool:
	# Used by Designer UI. silent=true for internal bulk re-equip (hull switch,
	# preset load): suppresses per-step power/research toasts — the final
	# recalc + ship-status indicator reports the real power state once.
	if not active_hull in hulls:
		print("Equip Fail: Active hull not found or invalid.")
		return false
	var hull_data = hulls[active_hull]
	
	if slot_idx >= hull_data["slots"].size():
		print("Equip Fail: Slot index out of bounds.")
		return false
	var req_type = hull_data["slots"][slot_idx]
	
	if not module_id in modules:
		print("Equip Fail: Module ID not found.")
		return false
	
	# v71.5: Enforce Research Prerequisites
	var status = can_equip_module(module_id)
	if not status["can_equip"]:
		print("Equip Fail: ", status["reason"])
		if not silent:
			UITheme.show_notification(status["reason"], Color.RED)
		return false
		
	var mod_data = modules[module_id]
	if mod_data["slot_type"] != req_type:
		print("Equip Fail: Slot Type Mismatch. Req: ", req_type, " Got: ", mod_data["slot_type"])
		return false
		
	# v64.0 Fix: Enforce Uniqueness
	if mod_data.get("unique", false):
		for slot in loadout:
			if slot != slot_idx and loadout[slot] == module_id:
				print("Equip Fail: Module is unique and already equipped.")
				return false
	
	if module_inventory.get(module_id, 0) <= 0:
		print("Equip Fail: No inventory.")
		return false
	
	# v110: Battery-only energy guard. Capacity + load are DERIVED by tier
	# (helpers); hulls contribute 0. Compute the loadout's load/capacity both
	# BEFORE and AFTER this hypothetical equip, then block over-capacity — with
	# an anti-softlock exception: always allow an equip that improves the net
	# power margin, so an overloaded ship can always be repaired step by step.
	# v119: Engineering skill no longer scales energy capacity (removed from
	# recalc_stats too — keep this guard consistent). applied_physics research stays.
	var rm = GameState.research_manager
	var phys_mult = 1.0
	if rm:
		phys_mult = 1.0 + rm.get_efficiency_bonus("basic_engineering")
	var cap_mult = phys_mult

	var old_load := 0.0
	var old_cap := 0.0
	var new_load := 0.0
	var new_cap := 0.0
	for s_idx in loadout:
		var mid = loadout[s_idx]
		if mid and mid in modules:
			old_load += get_module_energy_load(mid)
			old_cap += get_module_energy_capacity(mid) * cap_mult
			if s_idx != slot_idx:  # this slot is being replaced by the equip
				new_load += get_module_energy_load(mid)
				new_cap += get_module_energy_capacity(mid) * cap_mult
	# Add the incoming module to the prospective state.
	new_load += get_module_energy_load(module_id)
	new_cap += get_module_energy_capacity(module_id) * cap_mult

	if new_load > new_cap:
		var old_margin = old_cap - old_load
		var new_margin = new_cap - new_load
		# Allow only if this equip improves the margin (anti-softlock).
		if new_margin <= old_margin + 0.1:
			if not silent:
				UITheme.show_notification("Power %d / %d — equip more (or higher-tier) Battery modules first." % [int(round(new_load)), int(round(new_cap))], Color(1.0, 0.45, 0.35))
			return false

	# Unequip existing
	var existing = loadout.get(slot_idx)
	if existing:
		module_inventory[existing] = module_inventory.get(existing, 0) + 1
		
	module_inventory[module_id] = module_inventory.get(module_id, 1) - 1
	if module_inventory[module_id] <= 0:
		module_inventory.erase(module_id)
		
	loadout[slot_idx] = module_id
	
	recalc_stats()
	inventory_updated.emit() # Fix: Signal for UI update
	
	# v80.2 Fix: Clear incompatible ammo when swapping weapons
	if mod_data["slot_type"] == "weapon":
		var ammo_id = ammo_loadout.get(slot_idx, "")
		if ammo_id != "":
			var m_stats = mod_data.get("stats", {})
			var w_type = "kinetic"
			if m_stats.get("atk_energy", 0) > 0: w_type = "energy"
			elif m_stats.get("atk_explosive", 0) > 0: w_type = "explosive"
			
			if not is_ammo_compatible(w_type, ammo_id):
				ammo_loadout.erase(slot_idx) # Clear it so auto-equip can run
	
	# Auto-Equip Ammo if slot is empty (QoL Fix)
	if mod_data["slot_type"] == "weapon" and not ammo_loadout.get(slot_idx):
		var stats = mod_data.get("stats", {})
		if stats.get("atk_kinetic", 0) > 0:
			ammo_loadout[slot_idx] = "SlugT1"
		elif stats.get("atk_energy", 0) > 0:
			ammo_loadout[slot_idx] = "CellT1"
		# v65.0 Fix: Auto-equip for Explosive weapons mismatch
		elif stats.get("atk_explosive", 0) > 0:
			# For explosive, we use "missile" (HE Missiles)
			if GameState.resources.get_element_amount("missile") > 0:
				ammo_loadout[slot_idx] = "missile"
			else:
				print("Equip: No explosive ammo (missile) found in resources for auto-equip.")
	return true

func unequip_slot(slot_idx: int):
	var existing = loadout.get(slot_idx)
	if existing:
		module_inventory[existing] = module_inventory.get(existing, 0) + 1
		loadout.erase(slot_idx)
		# Fix Medium: Clear ammo slot on unequip
		ammo_loadout.erase(slot_idx)
		recalc_stats()
		inventory_updated.emit() # Fix: Signal for UI update

func handle_module_defeat():
	# v125: ONLINE defeat is non-destructive. Every equipped module floors to 50%
	# durability (never lower, never destroyed) — the old 1/6 instant-destroy +
	# 10-50% roll is gone (premium: no sudden loss of earned gear). At <=50% a
	# module is "destroyable", but that loss only ever happens during OFFLINE
	# combat (opt-in + consented — see apply_offline_durability_risk).
	var changed := false
	for slot_idx in loadout:
		var mid = loadout[slot_idx]
		if not mid or mid == "": continue

		# Base modules must become a custom instance so durability can be tracked.
		if not mid.begins_with("custom_"):
			var base_data = modules.get(mid)
			if base_data:
				var custom_id = "custom_%s_%d_%d" % [mid, Time.get_ticks_msec() + slot_idx, _drop_seq]
				_drop_seq += 1
				var custom_module = base_data.duplicate(true)
				custom_module["is_custom"] = true
				custom_module["base_module"] = mid
				custom_module["durability"] = 100

				modules[custom_id] = custom_module
				custom_modules[custom_id] = custom_module
				loadout[slot_idx] = custom_id
				mid = custom_id

		# Guard: a loadout slot can reference a module id that's no longer in
		# `modules` (custom-instance id collision under rapid losses). Skip the
		# stale ref instead of crashing on modules[mid].
		if not (mid in modules):
			continue
		var m = modules[mid]
		var current_dur = int(m.get("durability", 100))
		if current_dur > 50:
			m["durability"] = 50
			changed = true

	if changed:
		log_msg("DEFEAT: equipped modules worn down to 50% durability — repair with Spare Parts.")
		recalc_stats()


func apply_offline_durability_risk(delta: float) -> Array:
	# v125: OFFLINE combat runs unattended, so it carries the real loss risk the
	# player consents to when enabling it. Only modules ALREADY worn to <=50%
	# durability ("destroyable") can be lost — pristine/>50% gear is always safe.
	# Per-module destruction chance scales with hours away, capped. Repairing worn
	# modules before logging off carries ZERO risk. Returns destroyed display names
	# so the offline report can surface exactly what was lost (never silent).
	var destroyed: Array = []
	var hours: float = delta / 3600.0
	var p: float = clampf(0.05 * hours, 0.0, 0.35)   # ~5%/hr, capped 35% per worn module
	if p <= 0.0:
		return destroyed
	var slots_to_clear: Array = []
	for slot_idx in loadout:
		var mid = loadout[slot_idx]
		if not mid or mid == "": continue
		if not (mid in modules): continue
		var dur: int = int(modules[mid].get("durability", 100))
		if dur <= 50 and randf() < p:
			destroyed.append(str(modules[mid].get("name", mid)))
			slots_to_clear.append(slot_idx)
	for slot_idx in slots_to_clear:
		var mid = loadout.get(slot_idx)
		if mid:
			if str(mid).begins_with("custom_"):
				custom_modules.erase(mid)
				modules.erase(mid)
			loadout[slot_idx] = null
	if not slots_to_clear.is_empty():
		recalc_stats()
	return destroyed
	inventory_updated.emit()

func log_msg(msg: String):
	if GameState.combat_manager:
		GameState.combat_manager.log_msg(msg)
	else:
		print(msg)

func set_slot_ammo(slot_idx: int, ammo_id: String) -> bool:
	if ammo_id != "":
		# v80.2 Fix: Enforce ammo-to-weapon compatibility
		var mid = loadout.get(slot_idx)
		if mid and mid in modules:
			var m_stats = modules[mid].get("stats", {})
			var w_type = "kinetic"
			if m_stats.get("atk_energy", 0) > 0: w_type = "energy"
			elif m_stats.get("atk_explosive", 0) > 0: w_type = "explosive"
			
			if not is_ammo_compatible(w_type, ammo_id):
				print("Ammo Fail: Type Mismatch. Weapon: %s, Ammo: %s" % [w_type, ammo_id])
				UITheme.show_notification("Incompatible Ammo Type", Color.RED)
				return false
				
	ammo_loadout[slot_idx] = ammo_id
	return true

# Step 6: Gem Socket Support
func insert_gem(module_id: String, socket_idx: int, gem_id: String) -> bool:
	if GameState.resources.get_element_amount(gem_id) <= 0: return false
	
	var mod = modules.get(module_id)
	if not mod or not mod.has("sockets"): return false
	if socket_idx < 0 or socket_idx >= mod["sockets"].size(): return false
	if mod["sockets"][socket_idx] != null: return false # Already filled
	
	GameState.resources.remove_element(gem_id, 1)
	mod["sockets"][socket_idx] = gem_id
	recalc_stats()
	inventory_updated.emit()
	return true

func remove_gem(module_id: String, socket_idx: int) -> bool:
	# Removed inventory check to allow removal from equipped modules
	var mod = modules.get(module_id)
	if not mod or not mod.has("sockets"): return false
	if socket_idx < 0 or socket_idx >= mod["sockets"].size(): return false
	
	var gem = mod["sockets"][socket_idx]
	if not gem: return false
	
	GameState.resources.add_element(gem, 1)
	mod["sockets"][socket_idx] = null
	recalc_stats()
	inventory_updated.emit()
	return true

# v118: aggregated matrix-core facet bonuses (the 12 new keys), keyed by host slot
# category. Recomputed each recalc_stats; consumed by combat (Phase 2).
var gem_bonuses: Dictionary = {}

# Map a module's slot_type to its gem facet category: weapons -> offense, armor/
# shield -> defense, everything else (engine/sensor/battery/...) -> utility.
func _gem_slot_category(slot_type: String) -> String:
	if slot_type == "weapon":
		return "weapon"
	if slot_type == "armor" or slot_type == "shield":
		return "defense"
	return "utility"

# v118: matrix-core facet text helpers (designer socket UI + gem inspect card).
const GEM_STAT_LABELS := {
	"crit_damage": "Crit Damage", "attack_speed": "Attack Speed",
	"armor_pen": "Armor Penetration", "resist_pierce": "Resist Pierce",
	"damage_reduction": "Damage Reduction", "shield_regen_mult": "Shield Regen",
	"evasion_flat": "Evasion", "max_hull_mult": "Max Hull",
	"ammo_eff": "Ammo Efficiency", "energy_eff": "Energy Efficiency",
	"accuracy_flat": "Accuracy", "restore_on_kill": "Restore on Kill",
}

func format_gem_stat(key: String, val) -> String:
	var label: String = GEM_STAT_LABELS.get(key, key.replace("_", " ").capitalize())
	if key.ends_with("_flat"):
		return "+%d %s" % [int(val), label]
	return "+%d%% %s" % [int(round(float(val) * 100.0)), label]

# The bonus a gem actually provides in a given host slot type (its slot-matched facet).
func get_gem_facet_text(gem_id: String, slot_type: String) -> String:
	if not GEM_FACETS.has(gem_id):
		return ""
	var facet: Dictionary = GEM_FACETS[gem_id].get(_gem_slot_category(slot_type), {})
	var parts: Array = []
	for k in facet:
		parts.append(format_gem_stat(String(k), facet[k]))
	return ", ".join(parts)

func recalc_stats():
	# Capture the pre-recalc damage fraction. Loadout / research / hull /
	# trophy changes all re-run this outside combat; without this the final
	# clamp would fake-damage a full ship when max_hp grows and permanently
	# erode HP on any transient max_hp dip.
	var _prev_max_hp: float = float(max_hp)
	var _hp_ratio: float = 1.0
	if _prev_max_hp > 0.0:
		_hp_ratio = clampf(float(current_hp) / _prev_max_hp, 0.0, 1.0)
	var hp = 0
	var shield = 0.0
	var s_reg = 0.0
	var atk_k = 0
	var atk_e = 0
	var atk_x = 0
	var defe = 0
	var eva = 0.0
	var acc = 100.0
	var crit = 0.05
	var e_cap = 0.0
	var h_reg = 0.0
	var e_load = 0.0
	var atk_speed_bon = 0.0
	var s_reg_bon = 0.0
	var jam_str = 0.0
	var rk = 0.0  # v127: aggregate per-type resistances (baseline + affix)
	var re = 0.0
	var rx = 0.0

	if active_hull in hulls:
		var h = hulls[active_hull]["stats"]
		hp += h.get("hp", 0)
		shield += h.get("max_shield", 0)
		# v119: hull base attack removed — combat damage comes entirely from equipped
		# weapon modules, so the hull `atk` no longer feeds the aggregate (it was never
		# read in combat and only inflated the displayed attack stat).
		defe += h.get("def", 0)
		eva += h.get("eva", 0)
		# v110: hulls provide ZERO energy — all capacity comes from batteries.
		# (hull energy_capacity stat is now vestigial / display-only.)
		# e_cap += h.get("energy_capacity", 0)
		
	# v119: Engineering (Processing) skill no longer buffs ship stats — combat is
	# loadout/hull/warp/research-driven, matching the balance model the sims assume
	# (they run an Engineering-level-1 player). Engineering stays a crafting skill.
	
	for mid in loadout.values():
		if mid:
			if not mid in modules:
				continue
				
			var m = modules[mid]["stats"]
			hp += m.get("hp", 0)
			shield += m.get("max_shield", 0)
			s_reg += m.get("shield_regen", 0)
			hp_regen += m.get("hp_regen", 0) # v80.1: Native HP Regen support
			atk_k += m.get("atk_kinetic", 0)
			atk_e += m.get("atk_energy", 0)
			atk_x += m.get("atk_explosive", 0)
			defe += m.get("def", 0)
			eva += m.get("eva", 0) # v65.3 Fix: Flat stat
			acc += m.get("accuracy", 0)
			crit += m.get("crit_chance", 0.0)
			# v110: derive energy supply (batteries) + draw (consumers) by tier.
			e_cap += get_module_energy_capacity(mid)
			e_load += get_module_energy_load(mid)
			atk_speed_bon += m.get("atk_speed_mult", 0.0)
			atk_speed_bon += m.get("atk_speed_bonus", 0.0)
			s_reg_bon += m.get("shield_regen_mult", 0.0)
			s_reg_bon += m.get("shield_regen_bonus", 0.0)
			jam_str += m.get("jamming_strength", 0.0)
			rk += m.get("resist_k", 0.0)  # v127: baseline resist from module def
			re += m.get("resist_e", 0.0)
			rx += m.get("resist_x", 0.0)
			# v127 R2: per-slot baseline resist (generalist floor from CRAFTED gear).
			# Armor = physical plate (kinetic/explosive lean); Shield = energy barrier.
			var _st := str(modules[mid].get("slot_type", ""))
			if _st == "armor":
				rk += 0.08
				re += 0.02
				rx += 0.06
			elif _st == "shield":
				rk += 0.03
				re += 0.08
				rx += 0.03

	# Reset Affix Bonuses
	for key in affix_bonuses:
		affix_bonuses[key] = 0.0
		
	# Aggregate Affixes from Custom Modules
	for mid in loadout.values():
		if mid and mid in custom_modules:
			var affixes = custom_modules[mid].get("affixes", {})
			for affix_id in affixes:
				if affix_id in affix_bonuses:
					affix_bonuses[affix_id] += affixes[affix_id]

	# v80.1: Apply Flat Affix Bonuses to base values BEFORE multipliers
	hp += affix_bonuses.get("flat_hp", 0.0)
	shield += affix_bonuses.get("flat_shield", 0.0)
	defe += affix_bonuses.get("flat_def", 0.0)
	acc += affix_bonuses.get("flat_accuracy", 0.0)
	atk_k += affix_bonuses.get("flat_atk", 0.0)
	
	# v85.1: Add New Affix types to global stats
	crit += affix_bonuses.get("combat_sight", 0.0)
	eva += affix_bonuses.get("reflexive_plating", 0.0)
	# v127: per-type resist AFFIXES stack on the module-def baseline.
	rk += affix_bonuses.get("resist_k", 0.0)
	re += affix_bonuses.get("resist_e", 0.0)
	rx += affix_bonuses.get("resist_x", 0.0)
	
	# v85.2: Accumulate D4 stats (Combat manager will handle the logic, but we track the totals)
	# Note: These are mostly procs/thresholds, but we track totals for tooltip display logic if needed.
	# Actually, CombatManager will check sm.affix_bonuses directly.

	var rm = GameState.research_manager
	var hp_mult = 1.0
	if rm:
		hp_mult += rm.get_efficiency_bonus("max_hp_mult")
		hp_mult += rm.get_efficiency_bonus("materials_science")
	
	max_hp = int(hp * hp_mult)
	if max_hp <= 0: max_hp = 10
	
	max_shield = shield
	shield_regen = s_reg
	attack_kinetic = atk_k
	attack_energy = atk_e
	attack_explosive = atk_x
	
	# v72.8: Trophy Buffs (Global & Type Specific)
	if GameState.bounty_manager:
		attack_kinetic *= GameState.bounty_manager.get_trophy_buff("kinetic_dmg")
		attack_energy *= GameState.bounty_manager.get_trophy_buff("energy_dmg")
	
	attack = attack_kinetic + attack_energy + attack_explosive
	defense = defe
	evasion = eva
	hp_regen = h_reg
	# v127: commit per-type resistances, each capped at 0.75 (you always eat >=25%).
	resist_k = clampf(rk, 0.0, 0.75)
	resist_e = clampf(re, 0.0, 0.75)
	resist_x = clampf(rx, 0.0, 0.75)
	if GameState.bounty_manager:
		evasion *= GameState.bounty_manager.get_trophy_buff("evasion")
		
	accuracy = acc
	crit_chance = crit
	energy_used = e_load
	attack_speed_bonus = atk_speed_bon
	if GameState.bounty_manager:
		attack_speed_bonus += (GameState.bounty_manager.get_trophy_buff("ship_speed") - 1.0)

	# v112: Primordial Armor capstone — "best-in-slot defense" = +30% hull HP.
	# Self-contained presence check (not via get_trophy_buff, so the global
	# Trophy_Epsilon bonus doesn't silently leak into HP).
	if GameState.resources and GameState.resources.get_element_amount("PrimordialArmor") > 0:
		max_hp = int(max_hp * 1.30)
		if max_hp <= 0: max_hp = 10

	shield_regen_bonus = s_reg_bon
	jamming_strength = jam_str
	
	# Step 6 (v118): Matrix-core facet accumulation. Each socketed gem contributes
	# the facet matching its HOST module's slot category (weapon/defense/utility).
	gem_bonuses = {}
	for mid in loadout.values():
		if mid and mid in modules and modules[mid].has("sockets"):
			var host_cat: String = _gem_slot_category(modules[mid].get("slot_type", ""))
			for gem in modules[mid]["sockets"]:
				if gem and gem in GEM_FACETS:
					var facet: Dictionary = GEM_FACETS[gem].get(host_cat, {})
					for k in facet:
						gem_bonuses[k] = gem_bonuses.get(k, 0.0) + facet[k]
						
	# v118: clamp each facet to its aggregate cap (bounds the max-stack — a maxed T10
	# hull can't push any facet past its GEM_FACET_CAPS ceiling).
	for _gk in gem_bonuses:
		if GEM_FACET_CAPS.has(_gk):
			gem_bonuses[_gk] = minf(float(gem_bonuses[_gk]), float(GEM_FACET_CAPS[_gk]))
	# v118 Phase 2: apply the STAT-aggregate facets here; the rest (crit_chance,
	# crit_damage, armor_pen, resist_pierce, damage_reduction, ammo_eff,
	# restore_on_kill) are consumed live in combat_manager.
	crit_chance += gem_bonuses.get("crit_chance", 0.0)
	evasion += int(round(gem_bonuses.get("evasion_flat", 0.0)))
	accuracy += int(round(gem_bonuses.get("accuracy_flat", 0.0)))
	shield_regen = int(round(float(shield_regen) * (1.0 + gem_bonuses.get("shield_regen_mult", 0.0))))
	max_hp = int(round(float(max_hp) * (1.0 + gem_bonuses.get("max_hull_mult", 0.0))))
	energy_used = int(round(float(energy_used) * (1.0 - gem_bonuses.get("energy_eff", 0.0))))
	attack_speed_bonus += gem_bonuses.get("attack_speed", 0.0)

	# v107: Warp Mastery Tree — C1 Hull Reinforcement (+10% Hull HP, all hulls)
	if GameState.warp_manager:
		max_hp = int(float(max_hp) * GameState.warp_manager.get_tree_hull_bonus())
	# v109: Recursion — Recursive Hardening (infinite +5%/level Hull HP).
	# Multiplicative on top of the warp tree's flat +10%; both compound.
	if GameState.research_manager:
		max_hp = int(float(max_hp) * (1.0 + GameState.research_manager.get_efficiency_bonus("hull_hp_mult")))
	attack = attack_kinetic + attack_energy + attack_explosive

	# v105b: void_shielding_1 +5% Total Ship Shields. Endgame sink that
	# had no consumer despite a 100M-credit unlock cost.
	# Nerfed 20% → 5% (v105c): 20% stacked too hard on shield gem mults.
	if rm and rm.is_tech_unlocked("void_shielding_1"):
		max_shield *= 1.05
	# v118: evasion / energy / etc. gem bonuses now apply in combat (Phase 2).
	
	# Audit v8.0 P1-25: Applied Physics Hub Bonus (+10% Energy Capacity)
	if rm:
		e_cap *= (1.0 + rm.get_efficiency_bonus("basic_engineering"))

	# v110 Phase 1: ship energy capacity now lives on its own field. All ship
	# combat/equip/UI reads use sm.energy_capacity. resources.max_energy is
	# still mirrored (below) for the infrastructure grid, which currently
	# borrows it as a storage ceiling — that coupling is separated in Phase 2
	# when hull energy is removed (so removing it can't shrink the infra grid).
	energy_capacity = e_cap
	# v112: Void Battery capstone — "ultimate power storage" = +40% ship energy
	# capacity (stacks on the v112 battery headroom; lets the player slot more).
	if GameState.resources and GameState.resources.get_element_amount("VoidBattery") > 0:
		energy_capacity = int(energy_capacity * 1.40)
	# v110: ship no longer writes resources.max_energy — that field is now the
	# infrastructure grid's buffer ceiling (set by infrastructure_manager).
	# Ship energy lives entirely on energy_capacity / energy_used.

	# Was the ship full before this recalc? Then keep it full when max_hp
	# grows (fixes "100/132 though I never fought"). Otherwise keep the
	# absolute HP, only clamped to the new max — damage persists until you
	# pay Repair, and recalcs never silently bleed HP out of combat.
	if _hp_ratio >= 0.999:
		current_hp = max_hp
	else:
		current_hp = int(clampf(float(current_hp), 1.0, float(max_hp)))
	
	


# v111.18 Phase 2: persistent Armory grid placement, as (page, x, y). A coord
# of -1 means "no saved position" (auto-pack). Stored as a plain {p,x,y} dict
# for JSON safety. Old saves (pre-pagination) stored just {x,y} → page 0.
func get_armory_pos(item_id: String) -> Vector3i:
	var p = armory_layout.get(item_id)
	if typeof(p) != TYPE_DICTIONARY:
		return Vector3i(-1, -1, -1)
	return Vector3i(int(p.get("p", 0)), int(p.get("x", -1)), int(p.get("y", -1)))

func set_armory_pos(item_id: String, page: int, gx: int, gy: int) -> void:
	armory_layout[item_id] = {"p": page, "x": gx, "y": gy}

func clear_armory_pos(item_id: String) -> void:
	armory_layout.erase(item_id)

func get_save_data_manager() -> Dictionary:
	var data = {}
	data["active_hull"] = active_hull
	data["loadout"] = loadout
	data["inventory"] = module_inventory
	data["unseen_modules"] = unseen_modules
	data["hp"] = current_hp
	data["ammo_loadout"] = ammo_loadout
	data["consumable_hull_slot"] = consumable_hull_slot
	data["consumable_shield_slot"] = consumable_shield_slot
	data["custom_modules"] = custom_modules
	data["loadout_presets"] = loadout_presets
	data["armory_layout"] = armory_layout
	data["equipped_relic"] = equipped_relic  # v113 (NG+ P2)
	return data

func load_save_data_manager(data: Dictionary):
	if data.is_empty(): return
	
	active_hull = data.get("active_hull", "corvette_hull")
	var saved_load = data.get("loadout", {})
	
	if data.has("consumable_hull_slot"): consumable_hull_slot = data["consumable_hull_slot"]
	if data.has("consumable_shield_slot"): consumable_shield_slot = data["consumable_shield_slot"]
	
	custom_modules = data.get("custom_modules", {})
	for cm_id in custom_modules:
		# v118: heat removed — migrate the legacy "heat_sync_focus" affix key
		# (re-skinned to Servo Overclock) on existing rolled gear.
		var _afx = custom_modules[cm_id].get("affixes", null)
		if _afx is Dictionary and _afx.has("heat_sync_focus"):
			_afx["servo_overclock"] = _afx["heat_sync_focus"]
			_afx.erase("heat_sync_focus")
		modules[cm_id] = custom_modules[cm_id]
	
	# Convert JSON string keys back to int if needed or handle direct
	loadout = {}
	if active_hull in hulls:
		var slot_count = hulls[active_hull]["slots"].size()
		for i in range(slot_count):
			var val = saved_load.get(str(i)) # JSON keys are strings
			if not val: val = saved_load.get(i) # Try int key
			loadout[i] = val
			
	module_inventory = data.get("inventory", {})
	unseen_modules = data.get("unseen_modules", {})
	# Migration: old saves have no armory_layout → {} (everything auto-packs).
	armory_layout = data.get("armory_layout", {})
	equipped_relic = data.get("equipped_relic", "")  # v113 (NG+ P2)
	# v113: scrub any equipped/owned module whose def no longer exists (e.g. the
	# removed free Cryo Shard Pistol) so a stale id can't dangle into recalc/UI.
	for _s in loadout.keys():
		var _mid = loadout[_s]
		if _mid != null and _mid != "" and not (_mid in modules):
			loadout[_s] = null
	for _mid in module_inventory.keys():
		if not (_mid in modules):
			module_inventory.erase(_mid)
	_migrate_module_entries_from_resources()
	_migrate_atk_interval_caps()

	# Convert JSON string keys for ammo_loadout back to int
	var saved_ammo = data.get("ammo_loadout", {})
	ammo_loadout = {}
	for key in saved_ammo:
		ammo_loadout[int(key)] = saved_ammo[key]
	recalc_stats()
	_repower_if_unpowered()  # v110: re-power pre-battery loadouts under the battery-only model
	current_hp = data.get("hp", max_hp)

	# Restore loadout presets (JSON string keys → int)
	var saved_presets = data.get("loadout_presets", {})
	for raw_idx in saved_presets:
		var p_idx = int(raw_idx)
		if not p_idx in loadout_presets: continue
		var p = saved_presets[raw_idx]
		var preset = loadout_presets[p_idx]
		preset["name"] = p.get("name", "")
		preset["consumable_hull"] = p.get("consumable_hull", "")
		preset["consumable_shield"] = p.get("consumable_shield", "")
		preset["loadout"] = {}
		for k in p.get("loadout", {}):
			preset["loadout"][int(k)] = p["loadout"][k]
		preset["ammo_loadout"] = {}
		for k in p.get("ammo_loadout", {}):
			preset["ammo_loadout"][int(k)] = p["ammo_loadout"][k]

# Manual Repair System
func get_full_repair_cost(hull_id: String) -> int:
	var costs = {
		"corvette_hull": 1000,
		"frigate_hull": 5000,
		"destroyer_hull": 25000,
		"battlecruiser_hull": 100000,
		"dreadnought_hull": 500000
	}
	return costs.get(hull_id, 1000)

func get_repair_cost() -> int:
	if current_hp >= max_hp:
		return 0
	
	var full_cost = get_full_repair_cost(active_hull)
	var missing_hp = max_hp - current_hp
	var damage_ratio = float(missing_hp) / float(max_hp)
	
	var cost = max(10, int(full_cost * damage_ratio))
	return cost

func can_repair() -> bool:
	# Audit v68.0: Prevent repairs during active combat
	if GameState.combat_manager and GameState.combat_manager.in_combat:
		return false
		
	var has_damage = current_hp < max_hp
	var can_afford = GameState.resources.get_currency("credits") >= get_repair_cost()
	return has_damage and can_afford

func repair_hull() -> bool:
	# v124: hull repair CONSUMES the equipped hull repair kit (no Liras). Out of
	# combat consumables have no cooldown, so this tops up to full by spending
	# kits one at a time. No kit/stock -> can't repair; craft an Emergency Patch
	# (20 Fe, lvl 1, no research — the always-available anti-softlock floor).
	if GameState.combat_manager and GameState.combat_manager.in_combat:
		return false
	if current_hp >= max_hp:
		return false
	var kit = consumable_hull_slot
	if kit == "" or GameState.resources.get_element_amount(kit) < 1:
		print("[Repair] No hull repair kit equipped/stocked.")
		return false
	var cm = GameState.combat_manager
	var guard := 0
	while current_hp < max_hp and GameState.resources.get_element_amount(kit) >= 1 and guard < 200:
		cm.use_manual_consumable("hull")
		guard += 1
	return true
	
func reset(decay_factor: float = 1.0) -> void:
	active_hull = "corvette_hull"
	module_inventory = {}
	unseen_modules = {}
	loadout = {}
	ammo_loadout = {}
	custom_modules = {}
	if active_hull in hulls:
		for i in range(hulls[active_hull]["slots"].size()):
			loadout[i] = null
	# v110: battery-only energy — a fresh corvette needs powered batteries or
	# it can't fit anything (hull provides 0 energy). Grant + auto-equip 2
	# tier-1 batteries into the corvette's battery slots (covers its 6
	# consumers exactly: 2×30 cap = 6×10 load). Runs on new game AND warp
	# (both wipe inventory above).
	_grant_and_equip_starter_batteries()
	recalc_stats()

# v110: seed the active hull's battery slots with tier-1 batteries.
func _grant_and_equip_starter_batteries() -> void:
	if not ("z1_battery" in modules) or not (active_hull in hulls):
		return
	module_inventory["z1_battery"] = 2
	var slots: Array = hulls[active_hull].get("slots", [])
	var placed := 0
	for i in range(slots.size()):
		if placed >= 2:
			break
		if slots[i] == "battery":
			loadout[i] = "z1_battery"
			module_inventory["z1_battery"] -= 1
			placed += 1

# Highest-capacity battery the player currently owns (for the v110 re-power
# migration below); "" if none.
func _best_owned_battery() -> String:
	var best := ""
	var best_cap := 0
	for mid in module_inventory:
		if int(module_inventory.get(mid, 0)) <= 0: continue
		if modules.get(mid, {}).get("slot_type", "") != "battery": continue
		var cap := get_module_energy_capacity(mid)
		if cap > best_cap:
			best_cap = cap
			best = mid
	return best

# v110 migration: pre-battery saves (the hull used to supply energy) load with
# consumers but no batteries → "SHIP UNPOWERED". Fill empty battery slots (best
# owned battery, else a granted z1) until the grid is positive, so a migrated
# ship is never stranded.
func _repower_if_unpowered() -> void:
	if active_hull not in hulls: return
	if energy_used <= energy_capacity: return
	var slots: Array = hulls[active_hull].get("slots", [])
	for i in range(slots.size()):
		if energy_used <= energy_capacity: return
		if slots[i] != "battery" or loadout.get(i) != null: continue
		var bat := _best_owned_battery()
		if bat == "":
			if not ("z1_battery" in modules): return
			module_inventory["z1_battery"] = int(module_inventory.get("z1_battery", 0)) + 1
			bat = "z1_battery"
		loadout[i] = bat
		if int(module_inventory.get(bat, 0)) > 0:
			module_inventory[bat] -= 1
		recalc_stats()

# v66.0: Consumable Management
func equip_consumable(slot_type: String, item_id: String):
	print("Equipping consumable: %s -> %s" % [slot_type, item_id])
	# slot_type: "hull" or "shield"
	var data = ElementDB.get_consumable_data(item_id)
	if data.is_empty():
		print("Invalid consumable data for %s" % item_id)
		return # Invalid item
	
	if data.get("type") != slot_type:
		print("Type mismatch: %s != %s" % [data.get("type"), slot_type])
		return # Mismatch
		
	if slot_type == "hull":
		consumable_hull_slot = item_id
	elif slot_type == "shield":
		consumable_shield_slot = item_id
	# Without this, mission sync (equip_consumables) and the UI never
	# re-evaluate on equip — the Combat Triage step would sit at 0%.
	inventory_updated.emit()

func unequip_consumable(slot_type: String):
	if slot_type == "hull":
		consumable_hull_slot = ""
	elif slot_type == "shield":
		consumable_shield_slot = ""
	inventory_updated.emit()

func get_consumable(slot_type: String) -> String:
	if slot_type == "hull": return consumable_hull_slot
	if slot_type == "shield": return consumable_shield_slot
	return ""

func get_module_zone_multiplier(zone_difficulty: int) -> float:
	var diff = max(1, zone_difficulty)
	var early_steps = min(diff - 1, MODULE_ZONE_LATE_START - 1)
	var late_steps = max(0, diff - MODULE_ZONE_LATE_START)
	return pow(MODULE_ZONE_SCALE_EARLY, early_steps) * pow(MODULE_ZONE_SCALE_LATE, late_steps)

# v80.1: Calculate scaled range for an affix based on zone difficulty
func get_affix_scaled_range(affix_id: String, zone_difficulty: int) -> Array:
	if affix_id not in AFFIX_DB: return [0.0, 0.0]
	var cfg = AFFIX_DB[affix_id]
	var r_min = cfg["range"][0]
	var r_max = cfg["range"][1]
	
	if cfg.get("scaling") == "flat":
		var scaled_min = floor(float(r_min) * pow(1.8, max(0, zone_difficulty - 1)))
		var scaled_max = floor(float(r_max) * pow(1.8, max(0, zone_difficulty - 1)))
		return [scaled_min, scaled_max]
	elif cfg.get("scaling") == "linear_tier":
		# v85.1: Base * Zone
		return [float(r_min) * zone_difficulty, float(r_max) * zone_difficulty]
	else:
		# Percent affixes [3, 10] -> [0.03, 0.10]
		return [float(r_min) / 100.0, float(r_max) / 100.0]

func is_ammo_compatible(weapon_type: String, ammo_id: String) -> bool:
	if ammo_id == "": return true
	if weapon_type == "kinetic":
		return ammo_id.begins_with("Slug") or ammo_id == "kinetic_shell" or "Slug" in ammo_id
	elif weapon_type == "energy":
		return ammo_id.begins_with("Cell") or ammo_id == "energy_cell" or "Cell" in ammo_id
	elif weapon_type == "explosive":
		return "Missile" in ammo_id or "Torpedo" in ammo_id or ammo_id == "missile"
	return false

# v115: monotonic counter so custom-module ids are unique even when many roll in
# the same millisecond. Time.get_ticks_msec() alone collides under batch/offline
# loot -- the second roll overwrote the first in `modules` (silent loss; could even
# swap a Legendary's entry for a Unique, corrupting which module you actually hold).
var _drop_seq: int = 0

# v127 H1: shared affix helpers — the single source of truth that both
# generate_module_drop AND the Hack Stone crafting system call, so affix pooling,
# rolling, Greater-Affix chance and naming can never drift between drops and crafts.

# Legal affix pool for a slot_type, minus any ids to exclude (e.g. already present).
func _legal_affix_pool(slot_type: String, exclude: Array = []) -> Array:
	var pool := []
	for a_id in AFFIX_DB:
		if a_id in exclude:
			continue
		var cfg = AFFIX_DB[a_id]
		if not cfg.has("limit_to") or slot_type in cfg["limit_to"]:
			pool.append(a_id)
	# Fallback: generic industrial/economy fill for slots no affix restricts to.
	if pool.is_empty():
		for a_id in AFFIX_DB:
			if a_id in exclude:
				continue
			if AFFIX_DB[a_id]["type"] in ["industrial", "economy"]:
				pool.append(a_id)
	return pool

# Roll ONE affix's final value at a zone difficulty. 15% Greater-Affix chance
# (2x max roll). Percent -> fraction; flat -> floor(base * 1.8^(zone-1)); linear_tier
# -> base * zone. Returns {"value": float, "is_greater": bool}.
func _roll_affix_value(affix_id: String, zone_difficulty: int, ga_chance: float = 0.15) -> Dictionary:
	var cfg = AFFIX_DB[affix_id]
	var is_greater := randf() < ga_chance
	var raw_val = 0.0
	if is_greater:
		raw_val = cfg["range"][1] * 2.0
	else:
		raw_val = randi_range(cfg["range"][0], cfg["range"][1])
	var final_val := 0.0
	if cfg.get("scaling") == "flat":
		# v128: cap the exponential flat term at AFFIX_ZONE_CAP so stored floats stay exact.
		final_val = floor(float(raw_val) * pow(1.8, int(min(zone_difficulty, AFFIX_ZONE_CAP)) - 1))
	elif cfg.get("scaling") == "linear_tier":
		final_val = float(raw_val) * zone_difficulty
	else:
		final_val = float(raw_val) / 100.0
	return {"value": final_val, "is_greater": is_greater}

# Recompose a module's dynamic display name from its base name + ordered affix ids.
func _compose_module_name(base_name: String, affix_ids: Array) -> String:
	if affix_ids.is_empty():
		return base_name
	var prefix = AFFIX_NAMING.get(affix_ids[0], {}).get("prefix", "")
	var suffix = AFFIX_NAMING.get(affix_ids[-1], {}).get("suffix", "")
	var nm := base_name
	if prefix != "":
		nm = prefix + " " + nm
	if suffix != "" and affix_ids.size() > 1:
		nm = nm + " " + suffix
	return nm

# v71.0: Generate a rarity-boosted module drop from a base module ID
func generate_module_drop(base_module_id: String, rarity: int = Rarity.UNCOMMON, zone_difficulty: int = 1) -> String:
	if base_module_id not in modules:
		print("generate_module_drop: Unknown base module '%s'" % base_module_id)
		return ""
	
	# Common modules are fixed drops; no custom roll is created.
	if rarity == Rarity.COMMON:
		module_inventory[base_module_id] = module_inventory.get(base_module_id, 0) + 1
		new_drops_alert = true
		inventory_updated.emit()
		return base_module_id
	
	var base = modules[base_module_id]
	var custom_id = "custom_%s_%d_%d" % [base_module_id, Time.get_ticks_msec(), _drop_seq]
	_drop_seq += 1
	var zone_mult = get_module_zone_multiplier(zone_difficulty)
	
	# Apply stat bonuses based on rarity tier
	var stat_range = RARITY_STAT_RANGE.get(rarity, [0.0, 0.0])
	var custom_stats = {}
	for stat_key in base.get("stats", {}):
		var base_val = base["stats"][stat_key]
		if stat_key in BOOSTABLE_STATS:
			var scaled_base = base_val
			
			var bonus = randf_range(stat_range[0], stat_range[1])
			var boosted = scaled_base
			
			if stat_key == "atk_interval":
				# Reciprocal scaling: faster fire rate at higher rarity.
				# Coefficient lowered from 0.4 → 0.15 so a max-roll Unique caps near
				# -40% reduction (was -67%). Damage scaling is unchanged; this only
				# affects fire rate, preventing compound DPS outliers that let a
				# T2 Unique trivialize T3+ content.
				var speed_bonus = bonus * 0.15
				boosted = scaled_base / (1.0 + speed_bonus)
				# Hard floor: interval can never drop below 60% of base (-40% cap).
				boosted = max(boosted, scaled_base * 0.6)
				# Absolute floor: never under 0.25s (4Hz fire rate cap) for very fast bases.
				boosted = max(boosted, 0.25)
			else:
				boosted = scaled_base * (1.0 + bonus)
			
			if scaled_base is float or stat_key == "atk_interval":
				custom_stats[stat_key] = snappedf(boosted, 0.01)
			else:
				if float(scaled_base) < 50.0:
					custom_stats[stat_key] = snappedf(boosted, 0.1)
				else:
					custom_stats[stat_key] = int(round(boosted))
		else:
			# Non-boostable stats (energy_load, etc.) stay at base
			custom_stats[stat_key] = base_val
	
	# v74.0: Affix Generation
	var custom_affixes = {}
	var slot_type = base.get("slot_type", "utility")
	
	# v76.5: Filter affix pool by slot_type
	var affix_pool = []
	for a_id in AFFIX_DB:
		var cfg = AFFIX_DB[a_id]
		if not cfg.has("limit_to") or slot_type in cfg["limit_to"]:
			affix_pool.append(a_id)
					
	# Fallback: If no restricted affixes match, allow sensor/industrial as generic fill for empty slots
	if affix_pool.is_empty():
		for a_id in AFFIX_DB:
			if AFFIX_DB[a_id]["type"] in ["industrial", "economy"]:
				affix_pool.append(a_id)
	
	var num_affixes = 0
	if rarity == Rarity.UNCOMMON: num_affixes = 1  # v101: Was 0
	elif rarity == Rarity.RARE: num_affixes = 2    # v101: Was 1
	elif rarity == Rarity.LEGENDARY: num_affixes = 3 # v101: Was 2
	elif rarity == Rarity.UNIQUE: num_affixes = 4  # v101: Was 3
	
	num_affixes = min(num_affixes, affix_pool.size())
	
	# v85.3: Dynamic Naming & GA Initialization
	var final_name = base.get("name", "Unknown")
	var greater_affixes = []
	
	if num_affixes > 0:
		affix_pool.shuffle()
		for i in range(num_affixes):
			var affix_id = affix_pool[i]
			var cfg = AFFIX_DB[affix_id]
			
			# v101: Greater Affix Logic (15% chance, was 10%)
			var is_greater = randf() < 0.15
			var raw_val = 0.0
			
			if is_greater:
				# v101: GA pinned to 2.0x max roll (was 1.5x)
				raw_val = cfg["range"][1] * 2.0
				greater_affixes.append(affix_id)
			else:
				raw_val = randi_range(cfg["range"][0], cfg["range"][1])
				
			var final_val = 0.0
			
			if cfg.get("scaling") == "flat":
				# v80.1: floor(Base * 1.8^(Zone - 1))
				final_val = floor(float(raw_val) * pow(1.8, zone_difficulty - 1))
			elif cfg.get("scaling") == "linear_tier":
				# v85.1: Base * Zone (e.g. 3 * Zone 5 = 15)
				final_val = float(raw_val) * zone_difficulty
			else: # percent
				# v80.1: range [3, 10] becomes [0.03, 0.10]
				final_val = float(raw_val) / 100.0
				
			custom_affixes[affix_id] = final_val
	
		# v85.3: Apply Dynamic Naming if affixes exist
		var affix_ids = custom_affixes.keys()
		var first_affix = affix_ids[0]
		var last_affix = affix_ids[-1]
		
		var prefix = AFFIX_NAMING.get(first_affix, {}).get("prefix", "")
		var suffix = AFFIX_NAMING.get(last_affix, {}).get("suffix", "")
		
		if prefix != "":
			final_name = prefix + " " + final_name
		if suffix != "" and affix_ids.size() > 1:
			final_name = final_name + " " + suffix
			
	var rarity_label = RARITY_LABELS.get(rarity, "")
	var suffix_label = " (%s)" % rarity_label if rarity_label != "" else ""
	
	# Socket Generation (Step 6)
	var sockets = []
	if base.get("rarity") == Rarity.LEGENDARY or rarity == Rarity.LEGENDARY or rarity == Rarity.UNIQUE:
		var socket_count = 3 if rarity == Rarity.UNIQUE else (randi() % 3 + 1) # 1 to 3 sockets for Legendary, 3 for Unique
		for _i in range(socket_count): sockets.append(null)
	elif rarity == Rarity.RARE:
		if randf() < 0.3: # 30% chance for a socket on Rare
			sockets.append(null)
			
	var custom_module = {
		"name": "%s%s" % [final_name, suffix_label],
		"slot_type": base.get("slot_type", "weapon"),
		"stats": custom_stats,
		"cost": {},
		"desc": base.get("desc", ""),
		"is_custom": true,
		"is_unique": base.get("is_unique", false),
		"set_id": base.get("set_id", ""),
		"research_req": base.get("research_req", ""),
		"rarity": rarity,
		"base_module": base_module_id,
		"zone_difficulty": max(1, zone_difficulty),
		# v115 FIX: carry the base module's TIER onto the drop so the tier-gate
		# (get_module_tier / module_tier_penetration) reads it. Without this, rolled
		# drops had no zone/power_tier -> get_module_tier()=0 -> every drop (even a
		# tier-matched Legendary, and the Unique skip-key) was treated as tier 0 and
		# could NEVER pierce a hardened enemy.
		"zone": int(base.get("zone", max(1, zone_difficulty))),
		"power_tier": int(base.get("power_tier", base.get("zone", max(1, zone_difficulty)))),
		"affixes": custom_affixes,
		"greater_affixes": greater_affixes, # v85.2: Track GA affixes
		"sockets": sockets,
		"durability": 100
	}
	
	# Legendary: add extra flavor
	if rarity == Rarity.LEGENDARY:
		custom_module["desc"] = "★ " + custom_module["desc"] + " (Legendary variant)"
	
	modules[custom_id] = custom_module
	custom_modules[custom_id] = custom_module
	
	module_inventory[custom_id] = module_inventory.get(custom_id, 0) + 1
	unseen_modules[custom_id] = true
	new_drops_alert = true
	inventory_updated.emit()
	return custom_id

# Backward compat wrapper
func generate_custom_weapon(base_weapon_id: String) -> String:
	return generate_module_drop(base_weapon_id, Rarity.RARE)

# v71.0: Get rarity of any module (with name-based fallback for legacy items)
func get_module_rarity(module_id: String) -> int:
	var m = modules.get(module_id, {})
	if m.has("rarity"):
		return m["rarity"]
	
	# Fallback: parse from name for modules created before rarity system
	var name_str = m.get("name", "")
	if "(Legendary)" in name_str: return Rarity.LEGENDARY
	if "(Rare)" in name_str: return Rarity.RARE
	if "(Uncommon)" in name_str: return Rarity.UNCOMMON
	return Rarity.COMMON

func get_module_durability(module_id: String) -> int:
	var m = modules.get(module_id, {})
	return int(m.get("durability", 100))

# ══ v127 H2: Hack Stone crafting engine ═══════════════════════════════════
# Rare consumables dragged onto a module in the Ship Designer to modify its affixes
# (currency-as-crafting ported from PoE2 — see docs/design/HACK_STONES.md). All
# rolling routes through the H1 helpers so crafts and drops share ONE affix path.
const HACK_STONE_IDS := ["SpliceChip", "FirmwareInjector", "RootKey", "AnchorBolt", "CorruptionWorm", "RefitBay", "SignalCalibrator"]
# v127: player-facing effect blurb per stone (single source of truth for the
# tooltip / arm-confirm UI). Keep in sync with apply_hack_stone below.
const HACK_STONE_DESC := {
	"SpliceChip": "Awaken a Common module → Uncommon, rolling 1 random affix.",
	"FirmwareInjector": "Forge a Common module straight to Rare with 2 fresh affixes.",
	"RootKey": "Rarity +1 tier — keeps every existing affix, rolls 1 new one.",
	"AnchorBolt": "Lock an affix from rerolls (up to 2 on Legendary; re-apply to release).",
	"CorruptionWorm": "Remove 1 RANDOM unlocked affix, roll a new one (25% Greater-Affix — the gamble).",
	"RefitBay": "Remove 1 CHOSEN unlocked affix, roll a new one in its place (deterministic).",
	"SignalCalibrator": "Re-roll the VALUES of every unanchored affix — identities & count kept.",
}
const HACK_STONE_LIRA_COST := {
	Rarity.UNCOMMON: 500, Rarity.RARE: 3000, Rarity.LEGENDARY: 20000, Rarity.UNIQUE: 100000,
}
# v128: affix magnitude scales 1.8^(zone-1); cap the exponent so deep-zone / NG+ crafts
# keep affix floats exactly integer-representable (< 2^23) instead of silently drifting.
const AFFIX_ZONE_CAP := 15

# v128 P0: craft cost re-couples to the module's ZONE, not rarity alone. A Z12 base rolls
# Z12-magnitude affixes, so it must cost Z12 Liras — closes the cheap-deep-base arbitrage
# (a flat-3000 Rare craft on a Z12 base was ~200x underpriced vs the power it produced).
func _hack_lira_cost(rarity: int, zone_difficulty: int = 3) -> int:
	var base: int = int(HACK_STONE_LIRA_COST.get(rarity, 500))
	var z: int = int(min(max(zone_difficulty, 1), AFFIX_ZONE_CAP))
	return int(base * pow(1.8, max(0, z - 3)))

# v128 Q2: normalized anchor set — legacy single `anchored_affix` (string) + new
# `anchored_affixes` (array). Reading both keeps pre-v128 saves valid with no migration.
func _anchored_array(m: Dictionary) -> Array:
	var out := []
	var legacy: String = str(m.get("anchored_affix", ""))
	if legacy != "":
		out.append(legacy)
	for a in m.get("anchored_affixes", []):
		var s: String = str(a)
		if s != "" and not (s in out):
			out.append(s)
	return out

# Legendary+ modules can hold 2 locks (protect a 2-affix core before Calibrator-fishing
# the third); lower rarities 1.
func _max_anchors(m: Dictionary) -> int:
	return 2 if int(m.get("rarity", Rarity.COMMON)) >= Rarity.LEGENDARY else 1

# Rebuild a custom module's display name from base + affixes + rarity label
# (mirrors generate_module_drop's naming so crafted names read like dropped ones).
func _rebuild_custom_name(m: Dictionary) -> String:
	var base_id: String = str(m.get("base_module", ""))
	var base_name: String = str((modules.get(base_id, {}) as Dictionary).get("name", m.get("name", "Module")))
	var nm: String = _compose_module_name(base_name, m.get("affixes", {}).keys())
	var rl: String = str(RARITY_LABELS.get(int(m.get("rarity", 0)), ""))
	if rl != "":
		nm = "%s (%s)" % [nm, rl]
	return nm

# Public entry: apply a Hack Stone to a module. `module_id` is a base COMMON id
# (Splice/Injector) or a custom_ instance id (all others). `arg` = chosen affix for
# Anchor Bolt. Returns {"ok": bool, "msg": String, "result_id": String}. Stone + Liras
# are consumed ONLY on success (each stone fn does its own consume).
# v127: dry-run acceptance check for the hold-and-click insert flow — mirrors the
# per-stone validation below WITHOUT consuming or applying anything. {ok, msg}.
func can_apply_hack_stone(stone_id: String, module_id: String) -> Dictionary:
	if GameState.resources.get_element_amount(stone_id) < 1:
		return {"ok": false, "msg": "No %s in stock." % ElementDB.get_display_name(stone_id)}
	if module_id == "" or not modules.has(module_id):
		return {"ok": false, "msg": "Invalid module."}
	var m: Dictionary = modules[module_id]
	match stone_id:
		"SpliceChip", "FirmwareInjector":
			if module_id.begins_with("custom_"):
				return {"ok": false, "msg": "Already awakened — use another stone."}
			if int(module_inventory.get(module_id, 0)) < 1:
				return {"ok": false, "msg": "Keep that component in inventory (not equipped) to Splice it."}
			var tr: int = Rarity.UNCOMMON if stone_id == "SpliceChip" else Rarity.RARE
			var tr_z: int = int(m.get("zone", m.get("zone_difficulty", 1)))
			if GameState.resources.get_currency("credits") < _hack_lira_cost(tr, tr_z):
				return {"ok": false, "msg": "Need %d Liras." % _hack_lira_cost(tr, tr_z)}
			return {"ok": true, "msg": ""}
		"RootKey":
			if not module_id.begins_with("custom_"):
				return {"ok": false, "msg": "Awaken it first with a Splice Chip."}
			var rar: int = int(m.get("rarity", Rarity.COMMON))
			if rar >= Rarity.LEGENDARY:
				return {"ok": false, "msg": "Root Key caps at Legendary."}
			var rk_z: int = int(m.get("zone_difficulty", 1))
			if GameState.resources.get_currency("credits") < _hack_lira_cost(rar + 1, rk_z):
				return {"ok": false, "msg": "Need %d Liras." % _hack_lira_cost(rar + 1, rk_z)}
			var rk_af: Dictionary = m.get("affixes", {})
			if _legal_affix_pool(str(m.get("slot_type", "")), rk_af.keys()).is_empty():
				return {"ok": false, "msg": "No new affix type fits this slot."}
			return {"ok": true, "msg": ""}
		"CorruptionWorm", "RefitBay":
			if not module_id.begins_with("custom_"):
				return {"ok": false, "msg": "Awaken it first with a Splice Chip."}
			if int(m.get("rarity", Rarity.COMMON)) < Rarity.RARE:
				return {"ok": false, "msg": "Needs Rare or higher."}
			var cw_anch: Array = _anchored_array(m)
			var cw_removable: bool = false
			for a in m.get("affixes", {}).keys():
				if not (str(a) in cw_anch):
					cw_removable = true
					break
			if not cw_removable:
				return {"ok": false, "msg": "No unlocked affix to reroll."}
			var cw_cost: int = _hack_lira_cost(int(m.get("rarity", Rarity.RARE)), int(m.get("zone_difficulty", 1)))
			if stone_id == "RefitBay":
				cw_cost = int(cw_cost * 1.67)   # control is the premium over the random Worm
			if GameState.resources.get_currency("credits") < cw_cost:
				return {"ok": false, "msg": "Need %d Liras." % cw_cost}
			return {"ok": true, "msg": ""}
		"SignalCalibrator":
			if not module_id.begins_with("custom_"):
				return {"ok": false, "msg": "Awaken it first with a Splice Chip."}
			if int(m.get("rarity", Rarity.COMMON)) < Rarity.RARE:
				return {"ok": false, "msg": "Needs Rare or higher."}
			var sc_anch: Array = _anchored_array(m)
			var sc_rollable: bool = false
			for a in m.get("affixes", {}).keys():
				if not (str(a) in sc_anch):
					sc_rollable = true
					break
			if not sc_rollable:
				return {"ok": false, "msg": "No unanchored affix to re-roll."}
			var sc_cost: int = _hack_lira_cost(int(m.get("rarity", Rarity.RARE)), int(m.get("zone_difficulty", 1)))
			if GameState.resources.get_currency("credits") < sc_cost:
				return {"ok": false, "msg": "Need %d Liras." % sc_cost}
			return {"ok": true, "msg": ""}
		"AnchorBolt":
			if not module_id.begins_with("custom_"):
				return {"ok": false, "msg": "Awaken it first with a Splice Chip."}
			var ab_af: Dictionary = m.get("affixes", {})
			if ab_af.is_empty():
				return {"ok": false, "msg": "No affix to anchor."}
			return {"ok": true, "msg": ""}
	return {"ok": false, "msg": "Unknown stone: %s" % stone_id}

func apply_hack_stone(stone_id: String, module_id: String, arg: String = "") -> Dictionary:
	if GameState.resources.get_element_amount(stone_id) < 1:
		return {"ok": false, "msg": "No %s in stock." % ElementDB.get_display_name(stone_id), "result_id": ""}
	if module_id == "" or not modules.has(module_id):
		return {"ok": false, "msg": "Invalid module.", "result_id": ""}
	var r: Dictionary = {"ok": false, "msg": "Unknown stone: %s" % stone_id, "result_id": ""}
	match stone_id:
		"SpliceChip": r = _stone_materialize(module_id, Rarity.UNCOMMON, stone_id)
		"FirmwareInjector": r = _stone_materialize(module_id, Rarity.RARE, stone_id)
		"RootKey": r = _stone_rootkey(module_id, stone_id)
		"CorruptionWorm": r = _stone_worm(module_id, stone_id, "")     # random target, 25% GA gamble
		"RefitBay": r = _stone_worm(module_id, stone_id, arg)          # chosen target, 15% GA, +67% cost
		"SignalCalibrator": r = _stone_calibrate(module_id, stone_id)
		"AnchorBolt": r = _stone_anchor(module_id, arg, stone_id)
	if bool(r.get("ok", false)):
		hack_stone_applied.emit(stone_id)   # v128: drives the goal_hack_3 mission
	return r

# Splice Chip (UNCOMMON) / Firmware Injector (RARE): awaken a fixed-stat COMMON into
# a rollable custom instance. Reuses generate_module_drop (mints custom + affixes +
# rarity stat boost), then consumes 1 of the base common.
func _stone_materialize(base_id: String, target_rarity: int, stone_id: String) -> Dictionary:
	if base_id.begins_with("custom_"):
		return {"ok": false, "msg": "Already awakened — use another stone.", "result_id": ""}
	if int(module_inventory.get(base_id, 0)) < 1:
		return {"ok": false, "msg": "Keep that component in inventory (not equipped) to Splice it.", "result_id": ""}
	var base: Dictionary = modules[base_id]
	var zone: int = int(base.get("zone", base.get("zone_difficulty", 1)))
	var cost: int = _hack_lira_cost(target_rarity, zone)
	if GameState.resources.get_currency("credits") < cost:
		return {"ok": false, "msg": "Need %d Liras." % cost, "result_id": ""}
	var new_id: String = generate_module_drop(base_id, target_rarity, zone)
	if new_id == "" or new_id == base_id:
		return {"ok": false, "msg": "Splice failed.", "result_id": ""}
	modules[new_id]["stone_crafted"] = true   # v127: mark so demolish can't profit (anti-pump)
	module_inventory[base_id] = int(module_inventory.get(base_id, 0)) - 1
	if int(module_inventory[base_id]) <= 0:
		module_inventory.erase(base_id)
	GameState.resources.remove_currency("credits", cost)
	GameState.resources.remove_element(stone_id, 1)
	inventory_updated.emit()
	return {"ok": true, "msg": "Awakened -> %s" % str((modules[new_id] as Dictionary).get("name", new_id)), "result_id": new_id}

# v127 review #5: top up sockets so a Root-Keyed Legendary/Unique matches a dropped
# one (dropped Legendary rolls 1-3, Unique 3). Never removes existing sockets.
func _topup_sockets(m: Dictionary, rarity: int) -> void:
	if not m.has("sockets"): m["sockets"] = []
	var target: int = 0
	if rarity == Rarity.UNIQUE: target = 3
	elif rarity == Rarity.LEGENDARY: target = 1
	while m["sockets"].size() < target:
		m["sockets"].append(null)

# Root Key: rarity +1 tier, KEEP all existing affixes + values, roll 1 new legal affix.
func _stone_rootkey(module_id: String, stone_id: String) -> Dictionary:
	if not module_id.begins_with("custom_"):
		return {"ok": false, "msg": "Awaken it first with a Splice Chip.", "result_id": ""}
	var m: Dictionary = modules[module_id]
	var rar: int = int(m.get("rarity", Rarity.COMMON))
	if rar >= Rarity.LEGENDARY:
		return {"ok": false, "msg": "Root Key caps at Legendary. Unique modules drop only from Sector bosses.", "result_id": ""}
	var cost: int = _hack_lira_cost(rar + 1, int(m.get("zone_difficulty", 1)))
	if GameState.resources.get_currency("credits") < cost:
		return {"ok": false, "msg": "Need %d Liras." % cost, "result_id": ""}
	if not m.has("affixes"): m["affixes"] = {}
	var pool: Array = _legal_affix_pool(str(m.get("slot_type", "")), m["affixes"].keys())
	if pool.is_empty():
		return {"ok": false, "msg": "No new affix type fits this slot.", "result_id": ""}
	pool.shuffle()
	var new_affix: String = str(pool[0])
	var roll: Dictionary = _roll_affix_value(new_affix, int(m.get("zone_difficulty", 1)))
	m["affixes"][new_affix] = roll["value"]
	if not m.has("greater_affixes"): m["greater_affixes"] = []
	if bool(roll["is_greater"]):
		m["greater_affixes"].append(new_affix)
	m["rarity"] = rar + 1
	m["stone_crafted"] = true   # v127: mark so demolish can't profit (anti-pump)
	_topup_sockets(m, rar + 1)  # v127 review #5: match dropped-item socket count
	m["name"] = _rebuild_custom_name(m)
	GameState.resources.remove_currency("credits", cost)
	GameState.resources.remove_element(stone_id, 1)
	recalc_stats()
	inventory_updated.emit()
	return {"ok": true, "msg": "Root Key -> %s + new affix." % str(RARITY_LABELS.get(rar + 1, "")), "result_id": module_id}

# Corruption Worm (chosen==""): remove 1 RANDOM unanchored affix, roll 1 new at 25% GA — the
# cheap high-variance gamble. Refit Bay (chosen==affix_id): remove that CHOSEN unanchored affix,
# roll 1 new at 15% GA, +67% cost (control is the premium). Count & rarity unchanged; respects anchors.
func _stone_worm(module_id: String, stone_id: String, chosen: String = "") -> Dictionary:
	if not module_id.begins_with("custom_"):
		return {"ok": false, "msg": "Awaken it first with a Splice Chip.", "result_id": ""}
	var m: Dictionary = modules[module_id]
	if int(m.get("rarity", Rarity.COMMON)) < Rarity.RARE:
		return {"ok": false, "msg": "Needs Rare or higher.", "result_id": ""}
	if not m.has("affixes"): m["affixes"] = {}
	var affixes: Dictionary = m["affixes"]
	var anchored: Array = _anchored_array(m)
	var removable: Array = []
	for a in affixes.keys():
		if not (str(a) in anchored):
			removable.append(str(a))
	if removable.is_empty():
		return {"ok": false, "msg": "No unlocked affix to reroll.", "result_id": ""}
	var is_refit: bool = (stone_id == "RefitBay")
	var drop_affix: String = ""
	if is_refit:
		if chosen == "" or not (chosen in removable):
			return {"ok": false, "msg": "Pick an unlocked affix to refit.", "result_id": ""}
		drop_affix = chosen
	else:
		removable.shuffle()
		drop_affix = str(removable[0])
	var cost: int = _hack_lira_cost(int(m.get("rarity", Rarity.RARE)), int(m.get("zone_difficulty", 1)))
	if is_refit:
		cost = int(cost * 1.67)
	if GameState.resources.get_currency("credits") < cost:
		return {"ok": false, "msg": "Need %d Liras." % cost, "result_id": ""}
	if not m.has("greater_affixes"): m["greater_affixes"] = []
	affixes.erase(drop_affix)
	m["greater_affixes"].erase(drop_affix)
	var pool: Array = _legal_affix_pool(str(m.get("slot_type", "")), affixes.keys())
	if not pool.is_empty():
		pool.shuffle()
		var new_affix: String = str(pool[0])
		# Worm gambles harder (25% GA) than deterministic Refit Bay (15%) — its upside.
		var ga: float = 0.15 if is_refit else 0.25
		var roll: Dictionary = _roll_affix_value(new_affix, int(m.get("zone_difficulty", 1)), ga)
		affixes[new_affix] = roll["value"]
		if bool(roll["is_greater"]):
			m["greater_affixes"].append(new_affix)
	m["stone_crafted"] = true   # v128: anti-pump — reshuffle outputs can't be sold for profit
	m["name"] = _rebuild_custom_name(m)
	GameState.resources.remove_currency("credits", cost)
	GameState.resources.remove_element(stone_id, 1)
	recalc_stats()
	inventory_updated.emit()
	var wlabel: String = "Refit Bay: chosen affix rerolled." if is_refit else "Corruption Worm: 1 affix rerolled."
	return {"ok": true, "msg": wlabel, "result_id": module_id}

# Signal Calibrator: re-roll the VALUES of every UNANCHORED affix (same ids, new magnitudes,
# fresh independent 15% GA each). Identities & count untouched — no brick. Respects anchors.
func _stone_calibrate(module_id: String, stone_id: String) -> Dictionary:
	if not module_id.begins_with("custom_"):
		return {"ok": false, "msg": "Awaken it first with a Splice Chip.", "result_id": ""}
	var m: Dictionary = modules[module_id]
	if int(m.get("rarity", Rarity.COMMON)) < Rarity.RARE:
		return {"ok": false, "msg": "Needs Rare or higher.", "result_id": ""}
	if not m.has("affixes"): m["affixes"] = {}
	var affixes: Dictionary = m["affixes"]
	var anchored: Array = _anchored_array(m)
	var targets: Array = []
	for a in affixes.keys():
		if not (str(a) in anchored):
			targets.append(str(a))
	if targets.is_empty():
		return {"ok": false, "msg": "No unanchored affix to re-roll.", "result_id": ""}
	var cost: int = _hack_lira_cost(int(m.get("rarity", Rarity.RARE)), int(m.get("zone_difficulty", 1)))
	if GameState.resources.get_currency("credits") < cost:
		return {"ok": false, "msg": "Need %d Liras." % cost, "result_id": ""}
	if not m.has("greater_affixes"): m["greater_affixes"] = []
	var z: int = int(m.get("zone_difficulty", 1))
	for aid in targets:
		var roll: Dictionary = _roll_affix_value(str(aid), z)   # same id, fresh value + independent 15% GA
		affixes[aid] = roll["value"]
		m["greater_affixes"].erase(aid)
		if bool(roll["is_greater"]):
			m["greater_affixes"].append(aid)
	m["stone_crafted"] = true
	m["name"] = _rebuild_custom_name(m)
	GameState.resources.remove_currency("credits", cost)
	GameState.resources.remove_element(stone_id, 1)
	recalc_stats()
	inventory_updated.emit()
	return {"ok": true, "msg": "Signal Calibrator: %d affix value(s) re-rolled." % targets.size(), "result_id": module_id}

# Anchor Bolt: lock a chosen affix from Worm/Refit/Calibrator. Legendary+ holds 2 locks.
# Re-applying to an anchored affix RELEASES it (free); locking consumes 1 card.
func _stone_anchor(module_id: String, arg: String, stone_id: String) -> Dictionary:
	if not module_id.begins_with("custom_"):
		return {"ok": false, "msg": "Awaken it first with a Splice Chip.", "result_id": ""}
	var m: Dictionary = modules[module_id]
	var affixes: Dictionary = m.get("affixes", {})
	if affixes.is_empty():
		return {"ok": false, "msg": "No affix to anchor.", "result_id": ""}
	var target: String = arg if affixes.has(arg) else str(affixes.keys()[0])
	var arr: Array = _anchored_array(m)
	var tname: String = str((AFFIX_DB.get(target, {}) as Dictionary).get("name", target))
	if target in arr:
		arr.erase(target)
		m["anchored_affixes"] = arr
		m.erase("anchored_affix")           # fold legacy field into the array model
		inventory_updated.emit()
		return {"ok": true, "msg": "Released: %s unlocked." % tname, "result_id": module_id}
	if arr.size() >= _max_anchors(m):
		return {"ok": false, "msg": "Max %d anchor(s) — release one, or Root Key to Legendary." % _max_anchors(m), "result_id": ""}
	arr.append(target)
	m["anchored_affixes"] = arr
	m.erase("anchored_affix")
	GameState.resources.remove_element(stone_id, 1)   # consume only on LOCK, not release
	inventory_updated.emit()
	return {"ok": true, "msg": "Anchored: %s locked." % tname, "result_id": module_id}

# ── v114: Zone Tier-Gate helpers (see docs/ZONE_TIER_GATE.md) ──
# A module's effective tier = power_tier when set (exotic weapons like cryo_lance,
# whose `zone` is the unlock zone, not the power band), else its `zone`.
func get_module_tier(module_id: String) -> int:
	var m = modules.get(module_id, {})
	return int(m.get("power_tier", m.get("zone", 0)))

# v115: HONEST tier wall. A module's penetration vs a tier_hardened: z enemy is a
# GRADUATED curve on the tier deficit -- readable as a penetration-vs-armor mismatch
# (the cards show the numbers), not an arbitrary binary flag, and tunable hard<->soft
# with ONE knob. Replaces the old all-or-nothing x TIER_FLOOR floor.
#   eff_tier = get_module_tier (+1 if Unique -- superior penetration, the skip-key)
#   deficit  = z - eff_tier
#   deficit <= 0 -> 1.0 (tier-matched or better: full effect)
#   deficit >= 1 -> TIER_PEN_PER_TIER ^ deficit, floored at TIER_PEN_FLOOR
# TIER_PEN_PER_TIER IS the hard<->soft dial: 0.15 = HARD (1 under -> 15%, 2 -> 2.25%);
# 0.35 = medium; 0.55 = soft (1 under -> 55%, brute-forceable). Sim-tune, never hand-wave.
const TIER_PEN_PER_TIER := 0.15
const TIER_PEN_FLOOR := 0.02
func module_tier_penetration(module_id: String, z: int) -> float:
	if z <= 0:
		return 1.0
	var mt := get_module_tier(module_id)
	if get_module_rarity(module_id) == Rarity.UNIQUE:
		mt += 1   # Unique = superior penetration -> the one-zone jackpot skip-key
	var deficit := z - mt
	if deficit <= 0:
		return 1.0
	return max(TIER_PEN_FLOOR, pow(TIER_PEN_PER_TIER, deficit))

# Boolean form kept for UI badges / callers that just need "fully pierces?".
func module_pierces_tier(module_id: String, z: int) -> bool:
	return module_tier_penetration(module_id, z) >= 1.0

# Defensive half of the gate: the fraction of armor / shield retained vs a
# tier_hardened: z enemy. Sub-tier ARMOR/SHIELD modules keep only `floor_f` (~0.02)
# of their stat; piercing ones keep all. Returned as multipliers so combat scales
# the FINAL sm.defense / sm.max_shield (preserving set/matrix/research bonuses
# proportionally) rather than re-deriving them. No armor/shield modules → 1.0
# (nothing to floor; bare hull base is not a gated module).
func get_tier_defense_factors(z: int, floor_f: float) -> Dictionary:
	if z <= 0:
		return {"def": 1.0, "shield": 1.0}
	var arm_full := 0.0
	var arm_keep := 0.0
	var sh_full := 0.0
	var sh_keep := 0.0
	for mid in loadout.values():
		if mid and mid in modules:
			var st = modules[mid].get("slot_type", "")
			# v115: graduated penetration, mirrors the offense wall (floor_f kept for
			# signature compat; the curve carries its own TIER_PEN_FLOOR).
			var f: float = module_tier_penetration(mid, z)
			if st == "armor":
				var d: float = modules[mid]["stats"].get("def", 0)
				arm_full += d
				arm_keep += d * f
			elif st == "shield":
				var s: float = modules[mid]["stats"].get("max_shield", 0)
				sh_full += s
				sh_keep += s * f
	return {
		"def": (arm_keep / arm_full) if arm_full > 0.0 else 1.0,
		"shield": (sh_keep / sh_full) if sh_full > 0.0 else 1.0,
	}

# v114: a module's effective craft cost. Injects the zone signature alloy for Z2-Z10
# common (no-rarity) weapon/armor/shield ONLY when the tier gate is on — so ungated /
# pre-feature saves keep their base costs and never need an alloy they can't craft.
# +5 weapon / +6 shield / +8 armor (Z4 reference; tune). Returns a copy (never mutates
# the module's stored cost). Use this everywhere a common module's cost is read.
func get_effective_module_cost(m_data: Dictionary) -> Dictionary:
	var base: Dictionary = (m_data.get("cost", {}) as Dictionary).duplicate()
	if not bool(GameState.game_settings.get("tier_gate_enabled", false)):
		return base
	var z: int = int(m_data.get("zone", 0))
	var st: String = str(m_data.get("slot_type", ""))
	if z >= 2 and z <= 10 and (st == "weapon" or st == "armor" or st == "shield") and not m_data.has("rarity"):
		var alloy: String = str(TIER_ALLOY_BY_ZONE.get(z, ""))
		if alloy != "":
			var qty: int = 8 if st == "armor" else (6 if st == "shield" else 5)
			base[alloy] = int(base.get(alloy, 0)) + qty
	return base

# v71.5: Check if module can be equipped (Prerequisite check)
# Returns: {"can_equip": bool, "reason": String}
func can_equip_module(module_id: String) -> Dictionary:
	var m = modules.get(module_id, {})
	if not m:
		# Check if it's an ammo or consumable
		var is_ammo = module_id in ElementDB.CATEGORIES.get("ammo", [])
		var is_consumable = module_id in ElementDB.CATEGORIES.get("consumables", [])
		
		if is_ammo or is_consumable:
			var req = ELEMENT_RESEARCH_REQS.get(module_id, "")
			if req != "" and GameState.research_manager and not GameState.research_manager.is_tech_unlocked(req):
				var tech_name = GameState.research_manager.tech_tree.get(req, {"name": req}).get("name", req)
				return {"can_equip": false, "reason": "Requires Research: " + tech_name}
			return {"can_equip": true, "reason": ""}
			
		return {"can_equip": false, "reason": "Module not found"}
	
	var req = m.get("research_req", "")
	
	# If it's a dropped module, check the base module's requirement too
	if m.get("is_custom") and m.has("base_module"):
		var base_id = m["base_module"]
		var base_data = modules.get(base_id, {})
		if base_data.has("research_req"):
			req = base_data["research_req"]
	
	if req != "" and not GameState.research_manager.is_tech_unlocked(req):
		# Get human readable tech name
		var tech_name = GameState.research_manager.tech_tree.get(req, {"name": req}).get("name", req)
		return {"can_equip": false, "reason": "Requires Research: " + tech_name}
		
	return {"can_equip": true, "reason": ""}

# v71.0: Roll rarity tier for a combat drop
func roll_rarity(is_boss: bool = false) -> int:
	var roll = randf()
	
	# v82.0: Restricted Rarity — Enemies only drop Uncommon+
	# Common is now strictly for crafting.
	var legendary_chance = 0.15 if is_boss else 0.04
	var rare_chance = 0.35 if is_boss else 0.26
	
	if roll < legendary_chance:
		return Rarity.LEGENDARY
	elif roll < legendary_chance + rare_chance:
		return Rarity.RARE
	else:
		return Rarity.UNCOMMON

# v71.2: Sell module for credits -> v100: Demolish for credits + SpareParts
const RARITY_SELL_PRICES = {
	Rarity.COMMON: 100,
	Rarity.UNCOMMON: 750,
	Rarity.RARE: 5000,
	Rarity.LEGENDARY: 30000,
	Rarity.UNIQUE: 100000,
}

const RARITY_SPARE_PARTS = {
	Rarity.COMMON: 1,
	Rarity.UNCOMMON: 3,
	Rarity.RARE: 8,
	Rarity.LEGENDARY: 25,
	Rarity.UNIQUE: 75,
}

func get_sell_price(module_id: String) -> int:
	var m = modules.get(module_id, {})
	# v127: stone-crafted modules demolish for a token only (see demolish_module) — report 0.
	if m.get("stone_crafted", false):
		return 0
	# Crafted modules: sell for 25% of credit cost
	var cost_credits = m.get("cost", {}).get("credits", 0)
	if cost_credits > 0:
		return max(50, int(cost_credits * 0.25))
	# Dropped modules: sell based on rarity
	var rarity = m.get("rarity", Rarity.COMMON)
	return RARITY_SELL_PRICES.get(rarity, 100)

func get_demolish_parts(module_id: String) -> int:
	var m = modules.get(module_id, {})
	var rarity = m.get("rarity", Rarity.COMMON)
	return RARITY_SPARE_PARTS.get(rarity, 1)

func demolish_module(module_id: String) -> bool:
	if module_id not in module_inventory or module_inventory[module_id] <= 0:
		return false
	# v127 review #1: stone-crafted modules can't be a Lira/SpareParts/salvage faucet.
	# A cheap Common crafted to high rarity would otherwise demolish for MORE than the
	# craft cost AND inflate lifetime_credits -> prestige. Token salvage (1 part) only.
	if modules.get(module_id, {}).get("stone_crafted", false):
		module_inventory[module_id] -= 1
		if module_inventory[module_id] <= 0:
			module_inventory.erase(module_id)
			if module_id in custom_modules:
				custom_modules.erase(module_id)
				modules.erase(module_id)
		GameState.resources.add_element("SparePart", 1)
		inventory_updated.emit()
		return true

	var price = get_sell_price(module_id)
	var parts = get_demolish_parts(module_id)
	
	var m = modules.get(module_id, {})
	var rarity = m.get("rarity", Rarity.COMMON)
	var zone = m.get("zone", 1)
	
	module_inventory[module_id] -= 1
	if module_inventory[module_id] <= 0:
		module_inventory.erase(module_id)
		# Clean up custom modules
		if module_id in custom_modules:
			custom_modules.erase(module_id)
			modules.erase(module_id)
	
	GameState.resources.add_currency("credits", price)
	GameState.resources.add_element("SparePart", parts)
	
	# v101: Zone-specific salvage return based on rarity and zone tier
	if rarity > Rarity.COMMON:
		var salvage_amt = rarity - Rarity.COMMON # 1 to 4 depending on rarity
		var salvage_item = ""
		if zone == 1: salvage_item = "MiteChitin"
		elif zone == 2: salvage_item = "PirateSalvage"
		elif zone == 3: salvage_item = "MartianRelics"
		elif zone == 4: salvage_item = "CryoEssence"
		elif zone == 5: salvage_item = "XenoFragment"
		
		if salvage_item != "":
			GameState.resources.add_element(salvage_item, salvage_amt)

	inventory_updated.emit()
	return true

# ── Bulk Demolish (QoL: Scrap All Commons / Scrap Junk) ──
# Demolishes every NON-EQUIPPED module at or below max_rarity.
# Returns the count of modules scrapped.
func bulk_demolish_by_rarity(max_rarity: int) -> int:
	var equipped_ids = {}
	for slot in loadout:
		var mid = loadout[slot]
		if mid: equipped_ids[mid] = true
	# Collect candidates first (don't mutate while iterating)
	var candidates: Array = []
	for mid in module_inventory.keys():
		if equipped_ids.has(mid): continue
		if get_module_rarity(mid) > max_rarity: continue
		candidates.append(mid)
	var count = 0
	for mid in candidates:
		var qty = module_inventory.get(mid, 0)
		for i in range(qty):
			if demolish_module(mid):
				count += 1
	return count

func count_demolish_candidates_by_rarity(max_rarity: int) -> int:
	var equipped_ids = {}
	for slot in loadout:
		var mid = loadout[slot]
		if mid: equipped_ids[mid] = true
	var n = 0
	for mid in module_inventory.keys():
		if equipped_ids.has(mid): continue
		if get_module_rarity(mid) > max_rarity: continue
		n += module_inventory.get(mid, 0)
	return n

# ── Loadout Presets (QoL: Save/Load build) ──
func save_loadout_preset(idx: int) -> bool:
	if not idx in loadout_presets: return false
	var preset = loadout_presets[idx]
	# Deep copy of current state
	preset["loadout"] = loadout.duplicate(true)
	preset["ammo_loadout"] = ammo_loadout.duplicate(true)
	preset["consumable_hull"] = consumable_hull_slot
	preset["consumable_shield"] = consumable_shield_slot
	if preset["name"] == "":
		preset["name"] = "Build %d" % idx
	inventory_updated.emit()
	return true

func load_loadout_preset(idx: int) -> Dictionary:
	# Returns: {"loaded": int, "skipped": int}
	if not idx in loadout_presets: return {"loaded": 0, "skipped": 0}
	var preset = loadout_presets[idx]
	if _preset_has_no_modules(preset):
		return {"loaded": 0, "skipped": 0}

	# Step 1: Return every currently-equipped module to inventory.
	# This is critical — otherwise equipped modules vanish from accounting.
	var slot_keys = loadout.keys().duplicate()
	for slot in slot_keys:
		if loadout.get(slot):
			unequip_slot(slot)

	# Step 2: Equip preset modules. equip_module handles inventory accounting,
	# slot-type validation, energy capacity, and research gates. Batteries
	# FIRST (establish capacity before consumers, else the per-step power check
	# rejects consumers against 0 capacity) and silently (internal bulk equip —
	# the returned loaded/skipped summary informs the player, not per-step
	# toasts).
	var loaded = 0
	var skipped = 0
	var _slot_order: Array = []
	for raw_slot in preset["loadout"]:
		var _bm = preset["loadout"][raw_slot]
		if _bm != null and _bm != "" and _bm in modules and modules[_bm].get("slot_type", "") == "battery":
			_slot_order.append(raw_slot)
	for raw_slot in preset["loadout"]:
		var _bm = preset["loadout"][raw_slot]
		if not (_bm != null and _bm != "" and _bm in modules and modules[_bm].get("slot_type", "") == "battery"):
			_slot_order.append(raw_slot)
	for raw_slot in _slot_order:
		var slot_idx = int(raw_slot)
		var mid = preset["loadout"][raw_slot]
		if mid == null or mid == "":
			continue
		if equip_module(slot_idx, mid, true):
			loaded += 1
		else:
			skipped += 1

	# Step 3: Restore ammo loadout (only for slots that still have weapons equipped).
	for raw_slot in preset["ammo_loadout"]:
		var slot_idx = int(raw_slot)
		if slot_idx in loadout and loadout[slot_idx] != null and loadout[slot_idx] != "":
			ammo_loadout[slot_idx] = preset["ammo_loadout"][raw_slot]

	# Step 4: Restore consumables (only if the player still owns at least one).
	var hull_c = preset.get("consumable_hull", "")
	if hull_c != "" and GameState.resources and GameState.resources.get_element_amount(hull_c) > 0:
		consumable_hull_slot = hull_c
	else:
		consumable_hull_slot = ""

	var shield_c = preset.get("consumable_shield", "")
	if shield_c != "" and GameState.resources and GameState.resources.get_element_amount(shield_c) > 0:
		consumable_shield_slot = shield_c
	else:
		consumable_shield_slot = ""

	recalc_stats()
	inventory_updated.emit()
	return {"loaded": loaded, "skipped": skipped}

func _preset_has_no_modules(preset: Dictionary) -> bool:
	# A preset is "empty" if every saved slot is null/empty — not just if the dict has no keys.
	# (Loadout dicts have keys for every slot, often with null values.)
	for k in preset.get("loadout", {}):
		var v = preset["loadout"][k]
		if v != null and v != "":
			return false
	return true

func clear_loadout_preset(idx: int) -> bool:
	if not idx in loadout_presets: return false
	loadout_presets[idx] = {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""}
	inventory_updated.emit()
	return true

func is_loadout_preset_empty(idx: int) -> bool:
	if not idx in loadout_presets: return true
	return _preset_has_no_modules(loadout_presets[idx])

# ── Threshold Relic slot (NG+ P2 master key) ──
# v113: relics live in a dedicated single slot, separate from the hull grid.
# equip/unequip validate slot_type + ownership; the combat effect is read via
# get_relic_reduction_factor (applied to incoming damage in the keyed zone only).
func equip_relic(relic_id: String) -> bool:
	if not relic_id in modules: return false
	if modules[relic_id].get("slot_type", "") != "relic": return false
	if module_inventory.get(relic_id, 0) <= 0: return false
	equipped_relic = relic_id
	inventory_updated.emit()
	return true

func unequip_relic() -> void:
	if equipped_relic != "":
		equipped_relic = ""
		inventory_updated.emit()

# Incoming-damage multiplier from the equipped relic IN the given zone (1.0 = no
# effect). A relic only bites in its keyed zone, so it can't become a universal
# god-item — it's the farm-enabler for its tier's gate boss, nothing else.
func get_relic_reduction_factor(zone_id: String) -> float:
	if equipped_relic == "" or not equipped_relic in modules:
		return 1.0
	var r = modules[equipped_relic]
	if str(r.get("relic_zone", "")) != zone_id:
		return 1.0
	var red: float = clampf(float(r.get("relic_reduction", 0.0)), 0.0, 0.99)
	return 1.0 - red

func repair_module(slot_idx: int, cost_parts: int) -> bool:
	# v125: repair is Spare-Parts only (no Liras). Spare Parts come from demolishing
	# surplus modules — that's the maintenance sink that keeps worn gear alive.
	if GameState.resources.get_element_amount("SparePart") < cost_parts: return false

	var mid = loadout.get(slot_idx)
	if not mid or not mid.begins_with("custom_"): return false

	GameState.resources.remove_element("SparePart", cost_parts)

	modules[mid]["durability"] = 100
	if mid in custom_modules:
		custom_modules[mid]["durability"] = 100
	
	recalc_stats()
	inventory_updated.emit()
	return true
