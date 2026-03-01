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
	Rarity.COMMON: [0.00, 0.00],    # Fixed roll (no RNG spread)
	Rarity.UNCOMMON: [0.05, 0.08],  # 1.05x - 1.08x
	Rarity.RARE: [0.11, 0.15],      # 1.11x - 1.15x
	Rarity.LEGENDARY: [0.18, 0.22], # 1.18x - 1.22x
	Rarity.UNIQUE: [0.23, 0.27],    # 1.23x - 1.27x
}

# Drop scaling curve per zone (kept controlled and tapering in late game).
const MODULE_ZONE_SCALE_EARLY = 1.34
const MODULE_ZONE_SCALE_LATE = 1.28
const MODULE_ZONE_LATE_START = 7

# Stats that get rarity bonuses (damage, defense, HP, etc.)
const BOOSTABLE_STATS = [
	"atk_kinetic", "atk_energy", "atk_explosive",
	"hp", "def", "eva", "accuracy", "crit_chance",
	"max_shield", "shield_regen", "energy_capacity",
	"atk_speed_bonus", "shield_regen_mult", "atk_speed_mult",
	"jamming_strength", "atk_interval"
]

# Zone scaling is applied only to flat/core stats.
const ZONE_SCALABLE_STATS = [
	"atk_kinetic", "atk_energy", "atk_explosive",
	"hp", "def", "eva", "accuracy",
	"max_shield", "shield_regen", "energy_capacity",
	"atk_interval"
]

# Mid/Late progression tuning for craftable module item requirements.
const MID_MODULE_ITEM_REQ_MULT = 1.35
const LATE_MODULE_ITEM_REQ_MULT = 1.75

const EARLY_MODULE_REQ_TECHS = [
	"kinetics_101", "laser_optics", "power_systems",
	"lightweight_alloys", "basic_electronics", "eff_scanning_1",
	"energy_shields", "fluid_dynamics", "combustion"
]

const LATE_MODULE_REQ_TECHS = [
	"capital_ship_engineering", "quantum_dynamics", "xeno_engineering",
	"exotic_matter_analysis", "void_navigation", "void_physics"
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
		"range": [5, 15], "limit_to": ["weapon", "sensor"],
		"desc": "+%d Flat Accuracy."
	},
	"heat_sync_focus": {
		"name": "Heat-Sync Focus", "type": "tactical", "scaling": "percent",
		"range": [5, 12], "limit_to": ["weapon", "cooling"],
		"desc": "+%d%% Attack Speed while Heat is above 40%%."
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

	# --- INDUSTRIAL (Sensor, Battery) ---
	"refinery_link": {
		"name": "Refinery Link", "type": "industrial", "scaling": "percent",
		"range": [3, 10], "limit_to": ["sensor"],
		"desc": "+%d%% Global Processing Speed."
	},
	"extractor_efficiency": {
		"name": "Extractor Efficiency", "type": "industrial", "scaling": "percent",
		"range": [3, 10], "limit_to": ["sensor"],
		"desc": "+%d%% Auto-Miner Yield."
	},
	"nano_scavenger": {
		"name": "Nano-Scavenger", "type": "industrial", "scaling": "percent",
		"range": [3, 10], "limit_to": ["sensor"],
		"desc": "%d%% chance to loot processed materials from kills."
	},

	# --- ECONOMY (Sensor) ---
	"contract_negotiation": {
		"name": "Contract Negotiation", "type": "economy", "scaling": "percent",
		"range": [3, 10], "limit_to": ["sensor"],
		"desc": "+%d%% Bounty Credit rewards."
	},
	"logistician_edge": {
		"name": "Logistician's Edge", "type": "economy", "scaling": "percent",
		"range": [3, 10], "limit_to": ["sensor"],
		"desc": "-%d%% material requirements for Delivery Contracts."
	}
}

# Step 6: Gem/Matrix Core Effects
const GEM_GLOBAL_EFFECTS = {
	"CrackedCrimsonCore": {"atk_kinetic_mult": 0.02, "atk_energy_mult": 0.02, "crit_chance": 0.02},
	"StableCrimsonCore": {"atk_kinetic_mult": 0.05, "atk_energy_mult": 0.05, "crit_chance": 0.05},
	"PristineCrimsonCore": {"atk_kinetic_mult": 0.10, "atk_energy_mult": 0.10, "crit_chance": 0.10},
	
	"CrackedCobaltCore": {"max_shield_mult": 0.02, "shield_regen_mult": 0.02, "eva_mult": 0.02},
	"StableCobaltCore": {"max_shield_mult": 0.05, "shield_regen_mult": 0.05, "eva_mult": 0.05},
	"PristineCobaltCore": {"max_shield_mult": 0.10, "shield_regen_mult": 0.10, "eva_mult": 0.10},
	
	"CrackedTopazCore": {"energy_capacity_mult": 0.02},
	"StableTopazCore": {"energy_capacity_mult": 0.05},
	"PristineTopazCore": {"energy_capacity_mult": 0.10},
	
	"CrackedAmethystCore": {"def_mult": 0.02, "hp_mult": 0.02},
	"StableAmethystCore": {"def_mult": 0.05, "hp_mult": 0.05},
	"PristineAmethystCore": {"def_mult": 0.10, "hp_mult": 0.10}
}

var affix_bonuses = {
	"static_burst": 0.0,
	"capacitor_pulse": 0.0,
	"void_strike": 0.0,
	"heat_sync_focus": 0.0,
	"nanite_resurgence": 0.0,
	"refinery_link": 0.0,
	"extractor_efficiency": 0.0,
	"nano_scavenger": 0.0,
	"contract_negotiation": 0.0,
	"logistician_edge": 0.0,
	# v80.1: Flat Scaling Affixes
	"flat_hp": 0.0,
	"flat_def": 0.0,
	"flat_atk": 0.0,
	"flat_accuracy": 0.0,
	"flat_shield": 0.0
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
var loadout: Dictionary = {} # {slot_index: module_id}
var ammo_loadout: Dictionary = {} # {slot_index: ammo_id}

# v66.0: Consumable Slots
var consumable_hull_slot: String = "" # e.g. "Mesh"
var consumable_shield_slot: String = "" # e.g. "BasicBooster"

# v72.3: Research Requirements for non-module equipment (Ammo, Consumables)
const ELEMENT_RESEARCH_REQS = {
	"SlugT1": "kinetics_101",
	"SlugT2": "ballistics_optimization",
	"SlugT3": "high_energy_munitions",
	"SlugT4": "high_energy_munitions",
	"CellT2": "laser_optics",
	"CellT3": "cryogenic_systems",
	"CellT4": "cryogenic_systems",
	"HE_Missile": "combustion",
	"Seeker_Missile": "advanced_rocketry",
	"Photon_Torpedo": "capital_ship_armament",
	"EmergencyPatch": "basic_engineering", # Early game
	"Mesh": "adv_materials",
	"Seal": "adv_materials",
	"BasicBooster": "energy_shields",
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
var attack = 0 # Combined
var defense = 0
var evasion = 0
var accuracy = 0
var crit_chance = 0.05 # 5% base
var energy_used = 0
var attack_speed_bonus = 0.0
var shield_regen_bonus = 0.0
var jamming_strength = 0.0 # New: EW Enemy Slow % (0.0 to 1.0)


signal hull_constructed(hull_id)
signal module_crafted(module_id)
signal inventory_updated() # New signal for UI refresh

var hulls: Dictionary = {
	# v80.1: 10 formula-driven hulls — HP = floor(80 × 2.2^(N-1)), Slots = 6 + 2N
	"corvette_hull": {
		"name": "Corvette",
		"stats": {"hp": 120, "atk": 12, "energy_capacity": 25},
		"cost": {"credits": 0},
		"slots": ["weapon", "weapon", "shield", "armor", "engine", "battery", "battery", "sensor"], # 8
		"visual": "res://assets/ships/1.png",
		"tier": 1
	},
	"frigate_hull": {
		"name": "Industrial Frigate",
		"stats": {"hp": 185, "atk": 20, "energy_capacity": 55},
		"cost": {"credits": 30000, "Fe": 200, "Cu": 100},
		"slots": ["weapon", "weapon", "shield", "shield", "armor", "engine", "battery", "battery", "battery", "sensor"], # 10
		"research_req": "shipwright_1",
		"visual": "res://assets/ships/2.png",
		"tier": 2
	},
	"destroyer_hull": {
		"name": "Destroyer",
		"stats": {"hp": 387, "atk": 40, "energy_capacity": 120},
		"cost": {"credits": 90000, "Steel": 100, "Circuit": 20},
		"slots": ["weapon", "weapon", "weapon", "shield", "shield", "armor", "armor", "engine", "battery", "battery", "battery", "sensor"], # 12
		"research_req": "shipwright_2",
		"visual": "res://assets/ships/3.png",
		"tier": 3
	},
	"cruiser_hull": {
		"name": "Heavy Cruiser",
		"stats": {"hp": 852, "atk": 88, "energy_capacity": 260},
		"cost": {"credits": 270000, "Ti": 200, "AdvCircuit": 50},
		"slots": ["weapon", "weapon", "weapon", "shield", "shield", "shield", "armor", "armor", "engine", "battery", "battery", "battery", "sensor", "sensor"], # 14
		"research_req": "zone_4_access",
		"visual": "res://assets/ships/4.png",
		"tier": 4
	},
	"battlecruiser_hull": {
		"name": "Battlecruiser",
		"stats": {"hp": 1874, "atk": 194, "energy_capacity": 570},
		"cost": {"credits": 810000, "Superalloy": 500, "QuantumCore": 25},
		"slots": ["weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "armor", "armor", "engine", "battery", "battery", "battery", "battery", "sensor", "sensor"], # 16
		"research_req": "zone_5_access",
		"visual": "res://assets/ships/5.png",
		"tier": 5
	},
	"capital_hull": {
		"name": "Capital Ship",
		"stats": {"hp": 4124, "atk": 426, "energy_capacity": 1255},
		"cost": {"credits": 2430000, "AdvCircuit": 1000, "VoidArtifact": 50},
		"slots": ["weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "armor", "armor", "armor", "engine", "engine", "battery", "battery", "battery", "battery", "sensor", "sensor"], # 18
		"research_req": "zone_6_access",
		"visual": "res://assets/ships/5.png",
		"tier": 6
	},
	"carrier_hull": {
		"name": "Carrier",
		"stats": {"hp": 9073, "atk": 937, "energy_capacity": 2760},
		"cost": {"credits": 7290000, "ExoticMatter": 100},
		"slots": ["weapon", "weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "armor", "armor", "armor", "engine", "engine", "battery", "battery", "battery", "battery", "sensor", "sensor"], # 20
		"research_req": "zone_7_access",
		"visual": "res://assets/ships/5.png",
		"tier": 7
	},
	"dreadnought_hull": {
		"name": "Dreadnought",
		"stats": {"hp": 19960, "atk": 2062, "energy_capacity": 6075},
		"cost": {"credits": 21870000, "ExoticMatter": 200},
		"slots": ["weapon", "weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "armor", "armor", "armor", "engine", "engine", "battery", "battery", "battery", "battery", "battery", "sensor", "sensor", "sensor"], # 22
		"research_req": "zone_8_access",
		"visual": "res://assets/ships/5.png",
		"tier": 8
	},
	"titan_hull": {
		"name": "Titan",
		"stats": {"hp": 43913, "atk": 4537, "energy_capacity": 13365},
		"cost": {"credits": 65610000, "Neutronium": 500},
		"slots": ["weapon", "weapon", "weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "armor", "armor", "armor", "armor", "engine", "engine", "battery", "battery", "battery", "battery", "battery", "sensor", "sensor", "sensor"], # 24
		"research_req": "zone_9_access",
		"visual": "res://assets/ships/5.png",
		"tier": 9
	},
	"leviathan_hull": {
		"name": "Leviathan",
		"stats": {"hp": 96609, "atk": 9981, "energy_capacity": 29400},
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
		"cost": {"credits": 21296, "Steel": 80, "AdvCircuit": 5},
		"desc": "High-velocity slug launcher.",
		"zone": 4, "research_req": "zone_4_access"
	},
	"z4_energy": {
		"name": "Ion Lance",
		"slot_type": "weapon",
		"stats": {"atk_energy": 106, "energy_load": 40, "atk_interval": 2.0},
		"cost": {"credits": 21296, "Ti": 60, "AdvCircuit": 5},
		"desc": "Concentrated ion stream.",
		"zone": 4, "research_req": "zone_4_access"
	},
	"z4_missile": {
		"name": "Cluster Warhead",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 192, "energy_load": 45, "atk_interval": 4.0},
		"cost": {"credits": 26620, "Steel": 100, "Chip": 10},
		"desc": "Splits into sub-munitions on impact.",
		"zone": 4, "research_req": "zone_4_access"
	},
	"z4_shield": {
		"name": "Cryo Shield",
		"slot_type": "shield",
		"stats": {"max_shield": 426, "shield_regen": 21},
		"cost": {"credits": 15972, "Ti": 40, "AdvCircuit": 8},
		"desc": "Supercooled barrier matrix.",
		"zone": 4, "research_req": "zone_4_access"
	},
	"z4_armor": {
		"name": "Stainless Armor",
		"slot_type": "armor",
		"stats": {"def": 53, "hp": 213},
		"cost": {"credits": 15972, "Steel": 60, "Ti": 20},
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
		"cost": {"credits": 46851, "Ti": 100, "QuantumCore": 2},
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
		"cost": {"credits": 35138, "VoidArtifact": 5, "AdvCircuit": 20},
		"desc": "Reverse-engineered alien shielding.",
		"zone": 5, "research_req": "zone_5_access"
	},
	"z5_armor": {
		"name": "Superalloy Plate",
		"slot_type": "armor",
		"stats": {"def": 117, "hp": 469},
		"cost": {"credits": 35138, "Superalloy": 15, "Steel": 100},
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
		"cost": {"credits": 226758, "ExoticMatter": 10, "Ir": 10},
		"desc": "Fires neutron-dense projectiles.",
		"zone": 7, "research_req": "zone_7_access"
	},
	"z7_energy": {
		"name": "Void Beam",
		"slot_type": "weapon",
		"stats": {"atk_energy": 1131, "energy_load": 140, "atk_interval": 2.0},
		"cost": {"credits": 226758, "ExoticMatter": 10, "VoidCrystal": 5},
		"desc": "Drains energy from realspace.",
		"zone": 7, "research_req": "zone_7_access"
	},
	"z7_missile": {
		"name": "Singularity Bomb",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 2042, "energy_load": 160, "atk_interval": 4.0},
		"cost": {"credits": 283448, "ExoticMatter": 15, "QuantumCore": 10},
		"desc": "Creates micro-singularity on impact.",
		"zone": 7, "research_req": "zone_7_access"
	},
	"z7_shield": {
		"name": "Exotic Shield Matrix",
		"slot_type": "shield",
		"stats": {"max_shield": 4536, "shield_regen": 226},
		"cost": {"credits": 170069, "ExoticMatter": 8, "VoidCrystal": 5},
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
		"cost": {"credits": 498868, "VoidCrystal": 10, "Os": 5},
		"desc": "Crystal-focused kinetic lance.",
		"zone": 8, "research_req": "zone_8_access"
	},
	"z8_energy": {
		"name": "Prism Annihilator",
		"slot_type": "weapon",
		"stats": {"atk_energy": 2489, "energy_load": 200, "atk_interval": 2.0},
		"cost": {"credits": 498868, "VoidCrystal": 10, "ExoticMatter": 10},
		"desc": "Refracted energy cascade.",
		"zone": 8, "research_req": "zone_8_access"
	},
	"z8_missile": {
		"name": "Quantum Torpedo",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 4493, "energy_load": 240, "atk_interval": 4.0},
		"cost": {"credits": 623585, "QuantumCore": 20, "VoidCrystal": 10},
		"desc": "Exists in superposition until detonation.",
		"zone": 8, "research_req": "zone_8_access"
	},
	"z8_shield": {
		"name": "Prismatic Barrier",
		"slot_type": "shield",
		"stats": {"max_shield": 9980, "shield_regen": 499},
		"cost": {"credits": 374151, "VoidCrystal": 8, "ExoticMatter": 10},
		"desc": "Crystal lattice energy barrier.",
		"zone": 8, "research_req": "zone_8_access"
	},
	"z8_armor": {
		"name": "Diamond Core Plate",
		"slot_type": "armor",
		"stats": {"def": 1244, "hp": 4990},
		"cost": {"credits": 374151, "Diamond": 5, "VoidCrystal": 5},
		"desc": "Carbon-lattice super-structure.",
		"zone": 8, "research_req": "zone_8_access"
	},

	# ── ZONE 9: Sector Zeta ──
	"z9_kinetic": {
		"name": "Pathogen Cannon",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 4432, "energy_load": 260, "atk_interval": 2.0},
		"cost": {"credits": 1097510, "Neutronium": 10, "BiohazardSample": 20},
		"desc": "Bio-corrosive projectiles.",
		"zone": 9, "research_req": "zone_9_access"
	},
	"z9_energy": {
		"name": "Zero-Point Beam",
		"slot_type": "weapon",
		"stats": {"atk_energy": 5476, "energy_load": 300, "atk_interval": 2.0},
		"cost": {"credits": 1097510, "Neutronium": 10, "ChronoCore": 2},
		"desc": "Extracts energy from vacuum fluctuations.",
		"zone": 9, "research_req": "zone_9_access"
	},
	"z9_missile": {
		"name": "Biohazard Warhead",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 9885, "energy_load": 350, "atk_interval": 4.0},
		"cost": {"credits": 1371888, "BiohazardSample": 30, "Neutronium": 10},
		"desc": "Viral payload. Corrodes all matter.",
		"zone": 9, "research_req": "zone_9_access"
	},
	"z9_shield": {
		"name": "Quarantine Barrier",
		"slot_type": "shield",
		"stats": {"max_shield": 21956, "shield_regen": 1097},
		"cost": {"credits": 823132, "Neutronium": 8, "PathogenCore": 5},
		"desc": "Containment-grade barrier field.",
		"zone": 9, "research_req": "zone_9_access"
	},
	"z9_armor": {
		"name": "Neutronium Plate",
		"slot_type": "armor",
		"stats": {"def": 2737, "hp": 10978},
		"cost": {"credits": 823132, "Neutronium": 5, "Os": 5},
		"desc": "Neutron-star density alloy.",
		"zone": 9, "research_req": "zone_9_access"
	},

	# ── ZONE 10: Sector Epsilon ──
	"z10_kinetic": {
		"name": "Omega Cannon",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 9751, "energy_load": 400, "atk_interval": 2.0},
		"cost": {"credits": 2414522, "PrimordialShard": 5, "OmegaPlating": 10},
		"desc": "Final evolution of kinetic warfare.",
		"zone": 10, "research_req": "zone_10_access"
	},
	"z10_energy": {
		"name": "Chrono Disruptor",
		"slot_type": "weapon",
		"stats": {"atk_energy": 12047, "energy_load": 450, "atk_interval": 2.0},
		"cost": {"credits": 2414522, "ChronoCore": 5, "VoidEssence": 5},
		"desc": "Tears through spacetime itself.",
		"zone": 10, "research_req": "zone_10_access"
	},
	"z10_missile": {
		"name": "Void Annihilator",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 21747, "energy_load": 500, "atk_interval": 4.0},
		"cost": {"credits": 3018153, "PrimordialShard": 8, "ChronoCore": 5},
		"desc": "Erases matter from existence.",
		"zone": 10, "research_req": "zone_10_access"
	},
	"z10_shield": {
		"name": "Void Aegis",
		"slot_type": "shield",
		"stats": {"max_shield": 48304, "shield_regen": 2415},
		"cost": {"credits": 1810891, "VoidEssence": 10, "PrimordialShard": 5},
		"desc": "Reality-bending shield barrier.",
		"zone": 10, "research_req": "zone_10_access"
	},
	"z10_armor": {
		"name": "Primordial Bulkhead",
		"slot_type": "armor",
		"stats": {"def": 6022, "hp": 24152},
		"cost": {"credits": 1810891, "PrimordialShard": 3, "OmegaPlating": 5},
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
		"cost": {"credits": 6000, "Co": 15, "Li": 15}, "zone": 3, "research_req": "zone_3_access"
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
		"cost": {"credits": 18000, "AdvCircuit": 10, "Ti": 30}, "zone": 4, "research_req": "zone_4_access"
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

	# ── Z1: Architect's Regalia (+15% ATK Speed, +20 HP Regen/tick) ──
	"z1_unique_weapon": {
		"name": "Architect's Beam", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 28, "energy_load": 12, "atk_interval": 2.0},
		"cost": {}, "desc": "Precision-engineered energy weapon.", "zone": 1,
		"set_id": "architects_regalia", "is_unique": true
	},
	"z1_unique_armor": {
		"name": "Architect's Plating", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 14, "hp": 56},
		"cost": {}, "desc": "Blueprint-perfect hull reinforcement.", "zone": 1,
		"set_id": "architects_regalia", "is_unique": true
	},
	"z1_unique_shield": {
		"name": "Architect's Ward", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 112, "shield_regen": 5},
		"cost": {}, "desc": "Geometrically perfect barrier field.", "zone": 1,
		"set_id": "architects_regalia", "is_unique": true
	},

	# ── Z2: Monolith's Bedrock (+10% DEF, Reflect 5% dmg) ──
	"z2_unique_weapon": {
		"name": "Monolith's Shatter", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 50, "energy_load": 18, "atk_interval": 2.0},
		"cost": {}, "desc": "Crystalline projectile launcher.", "zone": 2,
		"set_id": "monoliths_bedrock", "is_unique": true
	},
	"z2_unique_armor": {
		"name": "Monolith's Shell", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 31, "hp": 123},
		"cost": {}, "desc": "Silicate-hardened hull plating.", "zone": 2,
		"set_id": "monoliths_bedrock", "is_unique": true
	},
	"z2_unique_shield": {
		"name": "Monolith's Barrier", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 246, "shield_regen": 12},
		"cost": {}, "desc": "Stone-resonance energy barrier.", "zone": 2,
		"set_id": "monoliths_bedrock", "is_unique": true
	},

	# ── Z3: Warmaster's Arsenal (+12% Crit Chance, +8% ATK) ──
	"z3_unique_weapon": {
		"name": "Warmaster's Railgun", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 109, "energy_load": 30, "atk_interval": 2.0},
		"cost": {}, "desc": "Mars-forged magnetic accelerator.", "zone": 3,
		"set_id": "warmasters_arsenal", "is_unique": true
	},
	"z3_unique_armor": {
		"name": "Warmaster's Bulkhead", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 67, "hp": 271},
		"cost": {}, "desc": "Battle-scarred Martian alloy.", "zone": 3,
		"set_id": "warmasters_arsenal", "is_unique": true
	},
	"z3_unique_shield": {
		"name": "Warmaster's Aegis", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 543, "shield_regen": 27},
		"cost": {}, "desc": "Command-grade barrier matrix.", "zone": 3,
		"set_id": "warmasters_arsenal", "is_unique": true
	},

	# ── Z4: Overseer's Command (+10% Shield Regen, +50 Accuracy) ──
	"z4_unique_weapon": {
		"name": "Overseer's Lance", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 297, "energy_load": 50, "atk_interval": 2.0},
		"cost": {}, "desc": "Cryo-focused targeting lance.", "zone": 4,
		"set_id": "overseers_command", "is_unique": true
	},
	"z4_unique_armor": {
		"name": "Overseer's Carapace", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 148, "hp": 596},
		"cost": {}, "desc": "Ice-tempered composite armor.", "zone": 4,
		"set_id": "overseers_command", "is_unique": true
	},
	"z4_unique_shield": {
		"name": "Overseer's Dome", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 1192, "shield_regen": 59},
		"cost": {}, "desc": "Cryo-stabilized barrier dome.", "zone": 4,
		"set_id": "overseers_command", "is_unique": true
	},

	# ── Z5: Harbinger's Wrath (+15% Missile DMG, -10% Enemy DEF) ──
	"z5_unique_weapon": {
		"name": "Harbinger's Fury", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 1181, "energy_load": 90, "atk_interval": 4.0},
		"cost": {}, "desc": "Xenon doomsday missile platform.", "zone": 5,
		"set_id": "harbingers_wrath", "is_unique": true
	},
	"z5_unique_armor": {
		"name": "Harbinger's Bastion", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 327, "hp": 1313},
		"cost": {}, "desc": "Alien-alloy hull reinforcement.", "zone": 5,
		"set_id": "harbingers_wrath", "is_unique": true
	},
	"z5_unique_shield": {
		"name": "Harbinger's Veil", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 2623, "shield_regen": 131},
		"cost": {}, "desc": "Xenon phase-shift barrier.", "zone": 5,
		"set_id": "harbingers_wrath", "is_unique": true
	},

	# ── Z6: Colossus Dominion (+12% All DMG, +5% Evasion) ──
	"z6_unique_weapon": {
		"name": "Colossus Cannon", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 1164, "energy_load": 120, "atk_interval": 2.0},
		"cost": {}, "desc": "Colony-siege superweapon.", "zone": 6,
		"set_id": "colossus_dominion", "is_unique": true
	},
	"z6_unique_armor": {
		"name": "Colossus Bulwark", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 719, "hp": 2886},
		"cost": {}, "desc": "Gamma-hardened ultra-plating.", "zone": 6,
		"set_id": "colossus_dominion", "is_unique": true
	},
	"z6_unique_shield": {
		"name": "Colossus Aegis", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 5773, "shield_regen": 288},
		"cost": {}, "desc": "Radiation-dampening barrier.", "zone": 6,
		"set_id": "colossus_dominion", "is_unique": true
	},

	# ── Z7: Sovereign's Prism (+300 DEF, +10% Energy DMG) ──
	"z7_unique_weapon": {
		"name": "Sovereign's Ray", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 3166, "energy_load": 180, "atk_interval": 2.0},
		"cost": {}, "desc": "Prismatic energy cascade.", "zone": 7,
		"set_id": "sovereigns_prism", "is_unique": true
	},
	"z7_unique_armor": {
		"name": "Sovereign's Mantle", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 1582, "hp": 6350},
		"cost": {}, "desc": "Exotic-matter woven hull.", "zone": 7,
		"set_id": "sovereigns_prism", "is_unique": true
	},
	"z7_unique_shield": {
		"name": "Sovereign's Corona", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 12700, "shield_regen": 635},
		"cost": {}, "desc": "Reality-bending shield aura.", "zone": 7,
		"set_id": "sovereigns_prism", "is_unique": true
	},

	# ── Z8: Warden's Quarantine (+20% Shield HP, +8% Crit) ──
	"z8_unique_weapon": {
		"name": "Warden's Scalpel", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 6969, "energy_load": 280, "atk_interval": 2.0},
		"cost": {}, "desc": "Crystal-focused annihilation beam.", "zone": 8,
		"set_id": "wardens_quarantine", "is_unique": true
	},
	"z8_unique_armor": {
		"name": "Warden's Containment", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 3483, "hp": 13972},
		"cost": {}, "desc": "Diamond-lattice containment hull.", "zone": 8,
		"set_id": "wardens_quarantine", "is_unique": true
	},
	"z8_unique_shield": {
		"name": "Warden's Lockdown", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 27944, "shield_regen": 1397},
		"cost": {}, "desc": "Prismatic containment barrier.", "zone": 8,
		"set_id": "wardens_quarantine", "is_unique": true
	},

	# ── Z9: Titan's Legacy (+15% All DMG, +500 DEF) ──
	"z9_unique_weapon": {
		"name": "Titan's Wrath", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 12409, "energy_load": 400, "atk_interval": 2.0},
		"cost": {}, "desc": "Neutronium-core mass driver.", "zone": 9,
		"set_id": "titans_legacy", "is_unique": true
	},
	"z9_unique_armor": {
		"name": "Titan's Aegis", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 7663, "hp": 30738},
		"cost": {}, "desc": "Neutron-star density plating.", "zone": 9,
		"set_id": "titans_legacy", "is_unique": true
	},
	"z9_unique_shield": {
		"name": "Titan's Bulwark", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 61476, "shield_regen": 3073},
		"cost": {}, "desc": "Containment-grade mega-barrier.", "zone": 9,
		"set_id": "titans_legacy", "is_unique": true
	},

	# ── Z10: Leviathan's Crown (+20% All DMG, +1000 HP Regen/tick) ──
	"z10_unique_weapon": {
		"name": "Leviathan's Maw", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 60891, "energy_load": 600, "atk_interval": 4.0},
		"cost": {}, "desc": "Reality-ending void warhead.", "zone": 10,
		"set_id": "leviathans_crown", "is_unique": true
	},
	"z10_unique_armor": {
		"name": "Leviathan's Hide", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 16861, "hp": 67625},
		"cost": {}, "desc": "Primordial matter hull.", "zone": 10,
		"set_id": "leviathans_crown", "is_unique": true
	},
	"z10_unique_shield": {
		"name": "Leviathan's Dominion", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 135251, "shield_regen": 6762},
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
			
	# Unequip All
	unequip_all()
	
	active_hull = hull_id
	loadout = {}
	for i in range(hull_data["slots"].size()):
		loadout[i] = null
		
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
	
	# Check Cost
	for res in mod_data["cost"]:
		var qty = mod_data["cost"][res]
		if res == "credits":
			if GameState.resources.get_currency("credits") < qty: return false
		else:
			if GameState.resources.get_element_amount(res) < qty: return false
			
	# Consume
	for res in mod_data["cost"]:
		var qty = mod_data["cost"][res]
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

func equip_module(slot_idx: int, module_id: String) -> bool:
	# Used by Designer UI
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
	
	# Design Constraint: Enforce Energy Load (Audit Phase 18)
	var potential_load = energy_used
	var existing = loadout.get(slot_idx)
	if existing:
		potential_load -= modules[existing]["stats"].get("energy_load", 0)
	potential_load += mod_data["stats"].get("energy_load", 0)
	
	# Note: Energy Capacity is hull + modules. We need to check against TOTAL capacity.
	var engineering_lvl = 1
	if GameState.processing_manager:
		engineering_lvl = GameState.processing_manager.get_level()
	var skill_mult = 1.0 + (engineering_lvl * 0.01)
	
	var rm = GameState.research_manager
	var phys_mult = 1.0
	if rm:
		phys_mult = 1.0 + rm.get_efficiency_bonus("applied_physics")
		
	var current_cap = hulls[active_hull]["stats"].get("energy_capacity", 100.0)
	for s_idx in loadout:
		if s_idx == slot_idx: continue
		var mid = loadout[s_idx]
		if mid and modules.has(mid):
			current_cap += modules[mid]["stats"].get("energy_capacity", 0) * skill_mult
	if mod_data["slot_type"] == "battery":
		current_cap += mod_data["stats"].get("energy_capacity", 0) * skill_mult
	current_cap *= phys_mult
	
	# ------------------------------------------------------------------
	# Grid Safety Logic (Redesigned v2.0)
	# ------------------------------------------------------------------
	
	# 1. Calc Old Capacity (Local Source of Truth)
	var old_cap = hulls[active_hull]["stats"].get("energy_capacity", 100.0)
	for s_idx in loadout:
		var mid = loadout[s_idx]
		if mid and mid in modules:
			old_cap += modules[mid]["stats"].get("energy_capacity", 0) * skill_mult
	old_cap *= phys_mult
			
	# 2. Check Overload
	if potential_load > current_cap:
		# We are entering (or staying in) an Overloaded state.
		# Strict Rule: Generally Forbidden.
		# Exception A: Battery Upgrade (Anti-Softlock)
		# If we are adding more capacity (upgrading battery), ALWAYS allow it.
		# Using slightly relaxed comparison for float precision
		if current_cap > (old_cap + 0.1):
			print("Equip Warning: Grid Overloaded, but Capacity Improved (%f > %f). Allowed." % [current_cap, old_cap])
			# Allow fallthrough
		
		# Exception B: Margin Improvement
		# If we aren't adding capacity, but we are reducing load MORE than we are losing capacity?
		# new_margin > old_margin
		else:
			var old_margin = old_cap - energy_used
			var new_margin = current_cap - potential_load
			
			if new_margin > (old_margin + 0.1):
				print("Equip Warning: Grid Overloaded, but Margin Improved (%f > %f). Allowed." % [new_margin, old_margin])
				# Allow fallthrough
			else:
				print("Equip Fail: Grid Overloaded. Needs more battery modules. Potential: %f, Cap: %f (Old Cap: %f, Old Margin: %f, New Margin: %f)" % [potential_load, current_cap, old_cap, old_margin, new_margin])
				UITheme.show_notification("Grid Overload: Insufficient Power", Color.RED)
				return false

	# Unequip existing
	if existing:
		module_inventory[existing] += 1
		
	module_inventory[module_id] -= 1
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
	if not module_id in module_inventory: return false
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
	if not module_id in module_inventory: return false
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

func recalc_stats():
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
	
	if active_hull in hulls:
		var h = hulls[active_hull]["stats"]
		hp += h.get("hp", 0)
		shield += h.get("max_shield", 0)
		atk_k += h.get("atk", 0)
		defe += h.get("def", 0)
		eva += h.get("eva", 0)
		e_cap += h.get("energy_capacity", 0)
		
	# Audit v7.0: Merged Shipyard bonus into Engineering (Processing) skill
	var engineering_lvl = 1
	if GameState.processing_manager:
		engineering_lvl = GameState.processing_manager.get_level()
	var skill_mult = 1.0 + (engineering_lvl * 0.01)
	
	for mid in loadout.values():
		if mid:
			if not mid in modules:
				continue
				
			var m = modules[mid]["stats"]
			hp += m.get("hp", 0) * skill_mult
			shield += m.get("max_shield", 0) * skill_mult
			s_reg += m.get("shield_regen", 0) * skill_mult
			hp_regen += m.get("hp_regen", 0) * skill_mult # v80.1: Native HP Regen support
			atk_k += m.get("atk_kinetic", 0) * skill_mult
			atk_e += m.get("atk_energy", 0) * skill_mult
			atk_x += m.get("atk_explosive", 0) * skill_mult
			defe += m.get("def", 0) * skill_mult
			eva += m.get("eva", 0) # v65.3 Fix: Flat stat, no skill_mult
			acc += m.get("accuracy", 0)
			crit += m.get("crit_chance", 0.0)
			e_cap += m.get("energy_capacity", 0) * skill_mult
			e_load += m.get("energy_load", 0)
			atk_speed_bon += m.get("atk_speed_mult", 0.0)
			atk_speed_bon += m.get("atk_speed_bonus", 0.0)
			s_reg_bon += m.get("shield_regen_mult", 0.0)
			s_reg_bon += m.get("shield_regen_bonus", 0.0)
			jam_str += m.get("jamming_strength", 0.0)

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
	if GameState.bounty_manager:
		evasion *= GameState.bounty_manager.get_trophy_buff("evasion")
		
	accuracy = acc
	crit_chance = crit
	energy_used = e_load
	attack_speed_bonus = atk_speed_bon
	if GameState.bounty_manager:
		attack_speed_bonus += (GameState.bounty_manager.get_trophy_buff("ship_speed") - 1.0)
		
	shield_regen_bonus = s_reg_bon
	jamming_strength = jam_str
	
	# Step 6: Gem (Matrix Core) Bonuses Accumulation
	var gem_totals = {}
	for mid in loadout.values():
		if mid and mid in modules and modules[mid].has("sockets"):
			for gem in modules[mid]["sockets"]:
				if gem and gem in GEM_GLOBAL_EFFECTS:
					var eff = GEM_GLOBAL_EFFECTS[gem]
					for k in eff:
						gem_totals[k] = gem_totals.get(k, 0.0) + eff[k]
						
	# Apply Gem Multipliers
	max_hp *= (1.0 + gem_totals.get("hp_mult", 0.0))
	defense *= (1.0 + gem_totals.get("def_mult", 0.0))
	attack_kinetic *= (1.0 + gem_totals.get("atk_kinetic_mult", 0.0))
	attack_energy *= (1.0 + gem_totals.get("atk_energy_mult", 0.0))
	attack_explosive *= (1.0 + gem_totals.get("atk_explosive_mult", 0.0))
	attack = attack_kinetic + attack_energy + attack_explosive
	crit_chance += gem_totals.get("crit_chance", 0.0)
	max_shield *= (1.0 + gem_totals.get("max_shield_mult", 0.0))
	shield_regen *= (1.0 + gem_totals.get("shield_regen_mult", 0.0))
	evasion *= (1.0 + gem_totals.get("eva_mult", 0.0))
	e_cap *= (1.0 + gem_totals.get("energy_capacity_mult", 0.0))
	jamming_strength += gem_totals.get("jamming_strength", 0.0)
	
	# Audit v8.0 P1-25: Applied Physics Hub Bonus (+10% Energy Capacity)
	if rm:
		e_cap *= (1.0 + rm.get_efficiency_bonus("applied_physics"))
	
	if GameState.resources:
		GameState.resources.set_max_energy(e_cap)
	
	current_hp = min(current_hp, max_hp)
	
	
	# Update Global Resources
	if GameState.resources:
		GameState.resources.set_max_energy(e_cap)


func get_save_data_manager() -> Dictionary:
	var data = {}
	data["active_hull"] = active_hull
	data["loadout"] = loadout
	data["inventory"] = module_inventory
	data["hp"] = current_hp
	data["ammo_loadout"] = ammo_loadout
	data["consumable_hull_slot"] = consumable_hull_slot
	data["consumable_shield_slot"] = consumable_shield_slot
	data["custom_modules"] = custom_modules
	return data

func load_save_data_manager(data: Dictionary):
	if data.is_empty(): return
	
	active_hull = data.get("active_hull", "corvette_hull")
	var saved_load = data.get("loadout", {})
	
	if data.has("consumable_hull_slot"): consumable_hull_slot = data["consumable_hull_slot"]
	if data.has("consumable_shield_slot"): consumable_shield_slot = data["consumable_shield_slot"]
	
	custom_modules = data.get("custom_modules", {})
	for cm_id in custom_modules:
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
	_migrate_module_entries_from_resources()
	
	# Convert JSON string keys for ammo_loadout back to int
	var saved_ammo = data.get("ammo_loadout", {})
	ammo_loadout = {}
	for key in saved_ammo:
		ammo_loadout[int(key)] = saved_ammo[key]
	recalc_stats()
	current_hp = data.get("hp", max_hp)

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
	print("[Repair] Attempting repair...")
	
	# Audit v68.0: Prevent repairs during active combat
	if GameState.combat_manager and GameState.combat_manager.in_combat:
		print("[Repair] Failed: Combat in progress.")
		return false
		
	if current_hp >= max_hp:
		print("[Repair] Failed: Already at max HP (%f/%d)" % [current_hp, max_hp])
		return false
	
	var cost = get_repair_cost()
	var credits_val = GameState.resources.get_currency("credits")
	
	if credits_val < cost:
		print("[Repair] Failed: Insufficient credits (%f < %d)" % [credits_val, cost])
		return false
	
	GameState.resources.remove_currency("credits", cost)
	current_hp = max_hp
	print("[Repair] Success! New HP: %d" % current_hp)
	return true
	
func reset(decay_factor: float = 1.0) -> void:
	active_hull = "corvette_hull"
	module_inventory = {}
	loadout = {}
	ammo_loadout = {}
	custom_modules = {}
	if active_hull in hulls:
		for i in range(hulls[active_hull]["slots"].size()):
			loadout[i] = null
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

func unequip_consumable(slot_type: String):
	if slot_type == "hull":
		consumable_hull_slot = ""
	elif slot_type == "shield":
		consumable_shield_slot = ""

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
	var custom_id = "custom_%s_%d" % [base_module_id, Time.get_ticks_msec()]
	var zone_mult = get_module_zone_multiplier(zone_difficulty)
	
	# Apply stat bonuses based on rarity tier
	var stat_range = RARITY_STAT_RANGE.get(rarity, [0.0, 0.0])
	var custom_stats = {}
	for stat_key in base.get("stats", {}):
		var base_val = base["stats"][stat_key]
		if stat_key in BOOSTABLE_STATS:
			var scaled_base = base_val
			if stat_key in ZONE_SCALABLE_STATS:
				if stat_key == "atk_interval":
					# Higher-zone drops should not become slower.
					scaled_base = max(0.25, float(base_val) / zone_mult)
				else:
					scaled_base = base_val * zone_mult
			
			var bonus = randf_range(stat_range[0], stat_range[1])
			var boosted = scaled_base
			
			if stat_key == "atk_interval":
				# Reciprocal scaling: +100% speed = 0.5x interval
				var speed_bonus = bonus * 0.4
				boosted = scaled_base / (1.0 + speed_bonus)
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
	if rarity == Rarity.RARE: num_affixes = 1
	elif rarity == Rarity.LEGENDARY: num_affixes = 2
	elif rarity == Rarity.UNIQUE: num_affixes = 3
	
	# v76.6: Prevents index crash if pool is smaller than required num (e.g. Armor unique only has 1 affix)
	num_affixes = min(num_affixes, affix_pool.size())
	
	if num_affixes > 0:
		affix_pool.shuffle()
		for i in range(num_affixes):
			var affix_id = affix_pool[i]
			var cfg = AFFIX_DB[affix_id]
			var raw_val = randi_range(cfg["range"][0], cfg["range"][1])
			var final_val = 0.0
			
			if cfg.get("scaling") == "flat":
				# v80.1: floor(Base * 1.8^(Zone - 1))
				final_val = floor(float(raw_val) * pow(1.8, zone_difficulty - 1))
			else: # percent
				# v80.1: range [3, 10] becomes [0.03, 0.10]
				final_val = float(raw_val) / 100.0
				
			custom_affixes[affix_id] = final_val
	
	var rarity_label = RARITY_LABELS.get(rarity, "")
	var suffix = " (%s)" % rarity_label if rarity_label != "" else ""
	
	# Socket Generation (Step 6)
	var sockets = []
	if base.get("rarity") == Rarity.LEGENDARY or rarity == Rarity.LEGENDARY or rarity == Rarity.UNIQUE:
		var socket_count = 3 if rarity == Rarity.UNIQUE else (randi() % 3 + 1) # 1 to 3 sockets for Legendary, 3 for Unique
		for _i in range(socket_count): sockets.append(null)
	elif rarity == Rarity.RARE:
		if randf() < 0.3: # 30% chance for a socket on Rare
			sockets.append(null)
			
	var custom_module = {
		"name": "%s%s" % [base.get("name", "Unknown"), suffix],
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
		"affixes": custom_affixes, # Add affixes here
		"sockets": sockets # Array of gem IDs or null
	}
	
	# Legendary: add extra flavor
	if rarity == Rarity.LEGENDARY:
		custom_module["desc"] = "★ " + custom_module["desc"] + " (Legendary variant)"
	
	modules[custom_id] = custom_module
	custom_modules[custom_id] = custom_module
	
	module_inventory[custom_id] = module_inventory.get(custom_id, 0) + 1
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

# v71.2: Sell module for credits
const RARITY_SELL_PRICES = {
	Rarity.COMMON: 100,
	Rarity.UNCOMMON: 500,
	Rarity.RARE: 2500,
	Rarity.LEGENDARY: 15000,
}

func get_sell_price(module_id: String) -> int:
	var m = modules.get(module_id, {})
	# Crafted modules: sell for 25% of credit cost
	var cost_credits = m.get("cost", {}).get("credits", 0)
	if cost_credits > 0:
		return max(50, int(cost_credits * 0.25))
	# Dropped modules: sell based on rarity
	var rarity = m.get("rarity", Rarity.COMMON)
	return RARITY_SELL_PRICES.get(rarity, 100)

func sell_module(module_id: String) -> bool:
	if module_id not in module_inventory or module_inventory[module_id] <= 0:
		return false
	
	var price = get_sell_price(module_id)
	module_inventory[module_id] -= 1
	if module_inventory[module_id] <= 0:
		module_inventory.erase(module_id)
		# Clean up custom modules
		if module_id in custom_modules:
			custom_modules.erase(module_id)
			modules.erase(module_id)
	
	GameState.resources.add_currency("credits", price)
	inventory_updated.emit()
	return true
