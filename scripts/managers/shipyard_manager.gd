# v71.0: Module Rarity System
enum Rarity {COMMON, UNCOMMON, RARE, LEGENDARY}

const RARITY_COLORS = {
	Rarity.COMMON: Color(0.7, 0.7, 0.7), # Light Gray
	Rarity.UNCOMMON: Color(0.2, 1.0, 0.2), # Sharp Green
	Rarity.RARE: Color(0.0, 0.6, 1.0), # Vivid Electric Blue
	Rarity.LEGENDARY: Color(1.0, 0.8, 0.0), # Vivid Gold
}

const RARITY_LABELS = {
	Rarity.COMMON: "",
	Rarity.UNCOMMON: "Uncommon",
	Rarity.RARE: "Rare",
	Rarity.LEGENDARY: "Legendary",
}

const RARITY_STAT_RANGE = {
	Rarity.UNCOMMON: [0.05, 0.15],
	Rarity.RARE: [0.15, 0.30],
	Rarity.LEGENDARY: [0.30, 0.50],
}

# Stats that get rarity bonuses (damage, defense, HP, etc.)
const BOOSTABLE_STATS = [
	"atk_kinetic", "atk_energy", "atk_explosive",
	"hp", "def", "eva", "accuracy", "crit_chance",
	"max_shield", "shield_regen", "energy_capacity",
	"atk_speed_bonus", "shield_regen_mult", "atk_speed_mult",
	"jamming_strength"
]

# v74.0: Module Affix System (Diablo/PoE Style)
# Categories: tactical, industrial, economy
const AFFIX_DB = {
	"static_burst": {
		"name": "Static Burst",
		"type": "tactical",
		"range": [0.10, 0.30],
		"desc": "%d%% shock chance on hit to reset enemy attack timer."
	},
	"capacitor_pulse": {
		"name": "Capacitor Pulse",
		"type": "tactical",
		"range": [0.05, 0.15],
		"desc": "Instantly restore %d%% Max Shield on every enemy kill."
	},
	"void_strike": {
		"name": "Void Strike",
		"type": "tactical",
		"range": [0.05, 0.20],
		"desc": "%d%% chance to bypass Shield and deal Hull damage directly."
	},
	"heat_sync_focus": {
		"name": "Heat-Sync Focus",
		"type": "tactical",
		"range": [0.10, 0.40],
		"desc": "+%d%% Attack Speed while Heat is above 40%%."
	},
	"refinery_link": {
		"name": "Refinery Link",
		"type": "industrial",
		"range": [0.05, 0.20],
		"desc": "+%d%% Global Processing Speed."
	},
	"extractor_efficiency": {
		"name": "Extractor Efficiency",
		"type": "industrial",
		"range": [0.10, 0.30],
		"desc": "+%d%% Auto-Miner Yield."
	},
	"nano_scavenger": {
		"name": "Nano-Scavenger",
		"type": "industrial",
		"range": [0.10, 0.25],
		"desc": "%d%% chance to loot processed materials from kills."
	},
	"contract_negotiation": {
		"name": "Contract Negotiation",
		"type": "economy",
		"range": [0.10, 0.30],
		"desc": "+%d%% Bounty Credit rewards."
	},
	"logistician_edge": {
		"name": "Logistician's Edge",
		"type": "economy",
		"range": [0.10, 0.40],
		"desc": "-%d%% material requirements for Delivery Contracts."
	}
}

var affix_bonuses = {
	"static_burst": 0.0,
	"capacitor_pulse": 0.0,
	"void_strike": 0.0,
	"heat_sync_focus": 0.0,
	"refinery_link": 0.0,
	"extractor_efficiency": 0.0,
	"nano_scavenger": 0.0,
	"contract_negotiation": 0.0,
	"logistician_edge": 0.0
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

# Calculated Stats
var max_hp = 100
var current_hp = 100
var active_shield = 0
var max_shield = 0
var shield_regen = 0
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
var ship_energy_gen = 0.0 # Phase 6: Reactor integration

signal hull_constructed(hull_id)
signal module_crafted(module_id)
signal inventory_updated() # New signal for UI refresh

var hulls: Dictionary = {
	"corvette_hull": {
		"name": "Corvette Hull",
		"stats": {"hp": 100, "atk": 10, "energy_capacity": 25},
		"cost": {"credits": 0},
		"slots": ["weapon", "weapon", "shield", "shield", "engine", "battery", "battery", "armor"], # 8 Slots (+1 Armor)
		"visual": "res://assets/ships/1.png",
		"tier": 0 # v61.0: Added for mission gating
	},
	"frigate_hull": {
		"name": "Industrial Frigate",
		"stats": {"hp": 800, "atk": 25, "energy_capacity": 60},
		"cost": {"credits": 5000, "Res1": 20},
		"slots": ["weapon", "weapon", "weapon", "shield", "shield", "shield", "engine", "battery", "battery", "battery", "sensor", "armor", "armor"], # 13 Slots (+2 Armor)
		"research_req": "shipwright_1",
		"visual": "res://assets/ships/2.png",
		"tier": 1 # v61.0
	},
	"destroyer_hull": {
		"name": "Destroyer Class",
		"stats": {"hp": 2500, "atk": 60, "energy_capacity": 150},
		"cost": {"credits": 37500, "Ti": 50, "Circuit": 25, "Res2": 10},
		"slots": ["weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "engine", "battery", "battery", "battery", "battery", "sensor", "cooling", "armor", "armor", "armor"], # 18 Slots (+3 Armor)
		"research_req": "shipwright_2",
		"visual": "res://assets/ships/3.png",
		"tier": 2 # v61.0
	},
	"battlecruiser_hull": {
		"name": "Battlecruiser Class",
		"stats": {"hp": 8000, "atk": 120, "energy_capacity": 350},
		"cost": {"credits": 375000, "Steel": 500, "AdvCircuit": 50, "VoidArtifact": 5, "Res3": 15},
		"slots": ["weapon", "weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "shield", "engine", "battery", "battery", "battery", "battery", "battery", "sensor", "sensor", "cooling", "cooling", "armor", "armor", "armor", "armor"], # 24 Slots (+4 Armor)
		"research_req": "capital_ship_engineering",
		"visual": "res://assets/ships/4.png",
		"tier": 3 # v61.0
	},
	"dreadnought_hull": {
		"name": "Dreadnought Class",
		"stats": {"hp": 20000, "atk": 250, "energy_capacity": 1000},
		"cost": {"credits": 25000000, "Steel": 100000, "Ti": 2500, "Neutronium": 50, "Circuit": 1000, "Chip": 250, "Superalloy": 100, "AdvCircuit": 100, "QuantumCore": 10, "VoidArtifact": 25},
		"slots": ["weapon", "weapon", "weapon", "weapon", "weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "shield", "shield", "shield", "engine", "battery", "battery", "battery", "battery", "battery", "battery", "sensor", "sensor", "sensor", "cooling", "cooling", "cooling", "armor", "armor", "armor", "armor", "armor"], # +5 Armor
		"research_req": "quantum_dynamics",
		"visual": "res://assets/ships/5.png",
		"tier": 4 # v61.0
	}
}

func get_ship_name() -> String:
	if active_hull in hulls:
		return hulls[active_hull].get("name", "Unknown Ship")
	return "No Ship"

var modules: Dictionary = {
	# Weapons
	"mining_laser_mk1": {
		"name": "Pulse Laser Mk.I",
		"slot_type": "weapon",
		"stats": {"atk_energy": 12, "energy_load": 5, "atk_interval": 1.5},
		"cost": {"credits": 125, "Si": 5},
		"desc": "Fast-firing Energy Beam. Effective vs Shields."
	},
	"mining_laser_mk2": {
		"name": "Pulse Laser Mk.II",
		"slot_type": "weapon",
		"stats": {"atk_energy": 40, "energy_load": 15, "atk_interval": 1.5},
		"cost": {"credits": 25000, "Si": 40, "Ti": 15, "Circuit": 15, "Chip": 10},
		"desc": "High intensity beam. Melts shields.",
		"research_req": "laser_optics"
	},
	"railgun_mk1": {
		"name": "Mass Driver",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 25, "energy_load": 5, "atk_interval": 3.0},
		"cost": {"credits": 2500, "Fe": 50},
		"desc": "Heavy magnetic projectile. Slow but powerful.",
		"research_req": "kinetics_101"
	},
	"cryo_laser_mk3": {
		"name": "Cryo-Cooled Laser Mk.III",
		"slot_type": "weapon",
		"stats": {"atk_energy": 80, "energy_load": 20, "atk_interval": 1.0},
		"cost": {"credits": 2500000, "Ti": 50, "CoolantCell": 10, "AdvCircuit": 5},
		"desc": "Helium-cooled beam. Extreme shield damage.",
		"research_req": "cryogenic_systems"
	},
	"micro_missile_launcher": {
		"name": "Micro-Missile Launcher",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 40, "energy_load": 10, "atk_interval": 4.0},
		"cost": {"credits": 12500, "Ti": 20, "C": 50},
		"desc": "Explosive payload. High Armor Penetration.",
		"research_req": "combustion"
	},
	"missile_launcher_mk2": {
		"name": "Seeker Missile Mk.II",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 120, "energy_load": 20, "atk_interval": 5.5},
		"cost": {"credits": 300000, "Steel": 200, "AdvCircuit": 20, "Res2": 10},
		"desc": "Advanced tracking missiles. Devastates armored hulls.",
		"research_req": "advanced_rocketry"
	},
	"torpedo_launcher": {
		"name": "Heavy Torpedo",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 1500, "energy_load": 60, "atk_interval": 12.0},
		"cost": {"credits": 12500000, "Superalloy": 50, "Chip": 50, "VoidArtifact": 5},
		"desc": "Capital-class warhead. Massive armor penetration.",
		"research_req": "capital_ship_armament"
	},
	# Cooling Systems
	"heatsink_array": {
		"name": "Heatsink Array",
		"slot_type": "cooling",
		"stats": {"atk_speed_bonus": 0.10, "energy_load": 5},
		"cost": {"credits": 12500, "Al": 20, "Graphite": 10},
		"desc": "Dissipates heat. +10% Attack Speed.",
		"research_req": "adv_materials"
	},
	"cryo_vent": {
		"name": "Cryo-Vent System",
		"slot_type": "cooling",
		"stats": {"atk_speed_bonus": 0.15, "energy_load": 15},
		"cost": {"credits": 62500, "CryoCell": 10, "Ti": 20},
		"desc": "Active cooling. +15% Attack Speed.",
		"research_req": "cryogenic_systems"
	},
	"quantum_dissipator": {
		"name": "Quantum Dissipator",
		"slot_type": "cooling",
		"stats": {"atk_speed_bonus": 0.25, "energy_load": 50},
		"cost": {"credits": 12500000, "QuantumCore": 5, "Superalloy": 50},
		"desc": "Vents heat into subspace. +25% Attack Speed.",
		"research_req": "quantum_dynamics"
	},
	# Sensor Suites
	"lidar_array": {
		"name": "LIDAR Array",
		"slot_type": "sensor",
		"stats": {"accuracy": 15, "energy_load": 10},
		"cost": {"credits": 12500, "Si": 20, "Circuit": 10},
		"desc": "Laser imaging. +15 Accuracy.",
		"research_req": "basic_electronics"
	},
	"targeting_matrix": {
		"name": "Targeting Matrix",
		"slot_type": "sensor",
		"stats": {"accuracy": 20, "crit_chance": 0.05, "energy_load": 25},
		"cost": {"credits": 75000, "AdvCircuit": 10, "NavData": 5},
		"desc": "Advanced tracking. +20 Accuracy, +5% Crit.",
		"research_req": "automated_logistics"
	},
	"omni_scanner": {
		"name": "Omni-Scanner",
		"slot_type": "sensor",
		"stats": {"accuracy": 40, "crit_chance": 0.10, "energy_load": 60},
		"cost": {"credits": 5000000, "AICore": 5, "VoidCrystal": 20},
		"desc": "All-seeing eye. +40 Accuracy, +10% Crit.",
		"research_req": "xeno_engineering"
	},
	# Electronic Warfare
	"signal_jammer": {
		"name": "Signal Jammer",
		"slot_type": "sensor",
		"stats": {"jamming_strength": 0.15, "energy_load": 25},
		"cost": {"credits": 50000, "SuperconductingMagnet": 5, "Circuit": 25},
		"desc": "Disrupts enemy targeting. Reduces enemy attack speed by 15%.",
		"research_req": "basic_electronics"
	},
	"stasis_web": {
		"name": "Stasis Web",
		"slot_type": "sensor",
		"stats": {"jamming_strength": 0.20, "energy_load": 40},
		"cost": {"credits": 50000, "AdvCircuit": 20, "Res3": 10},
		"desc": "Local time dilation. Slows enemies by 20%.",
		"research_req": "field_theory"
	},
	"temporal_scrambler": {
		"name": "Temporal Scrambler",
		"slot_type": "sensor",
		"stats": {"jamming_strength": 0.40, "energy_load": 100},
		"cost": {"credits": 10000000, "ChronoCore": 5, "VoidEssence": 50},
		"desc": "Rewrites causality. Slows enemies by 40%.",
		"research_req": "void_physics"
	},
	# Batteries
	"battery_t1": {
		"name": "Basic Battery Module",
		"slot_type": "battery",
		"stats": {"energy_capacity": 50},
		"cost": {"BatteryT1": 5},
		"desc": "Standard Energy Storage.",
		"research_req": "power_systems"
	},
	"battery_t2": {
		"name": "Graphene Matrix",
		"slot_type": "battery",
		"stats": {"energy_capacity": 150, "atk_speed_mult": 0.10}, # ITER4: +10% attack speed
		"cost": {"BatteryT2": 10},
		"desc": "High-density Storage. +10% Attack Speed.",
		"research_req": "adv_materials"
	},
	"battery_t3": {
		"name": "Zero-Point Module",
		"slot_type": "battery",
		"stats": {"energy_capacity": 500, "shield_regen_mult": 0.20}, # ITER4: +20% shield regen
		"cost": {"BatteryT3": 10},
		"desc": "Infinite Void Energy. +20% Shield Regen.",
		"research_req": "warp_drive"
	},
	# Shields
	"basic_shield": {
		"name": "Deflector Shield",
		"slot_type": "shield",
		"stats": {"max_shield": 50, "shield_regen": 2, "energy_load": 10},
		"cost": {"credits": 1500, "Si": 50},
		"desc": "Generates a regenerative energy field.",
		"research_req": "energy_shields"
	},
	"thermal_tile": {
		"name": "Graphite Armor",
		"slot_type": "armor",
		"stats": {"def": 35, "hp": 250},
		"cost": {"credits": 8000, "Graphite": 50, "Ti": 10},
		"desc": "Ablative carbon armor. Increases Hull & Armor.",
		"research_req": "adv_materials"
	},
	"titanium_armor": {
		"name": "Titanium Plating",
		"slot_type": "armor",
		"stats": {"def": 50, "hp": 400},
		"cost": {"credits": 75000, "Ti": 20},
		"desc": "Heavy-duty alloy armor.",
		"research_req": "shipwright_1"
	},
	# Engines
	"basic_thruster": {
		"name": "Ion Thrusters",
		"slot_type": "engine",
		"stats": {"eva": 10, "energy_load": 5},
		"cost": {"credits": 50, "Fe": 5},
		"desc": "Slow but reliable."
	},
	"plasma_drive": {
		"name": "Plasma Drive",
		"slot_type": "engine",
		"stats": {"eva": 25, "energy_load": 15},
		"cost": {"credits": 1000, "Ti": 10, "Circuit": 5},
		"desc": "High-efficiency plasma propulsion.",
		"research_req": "shipwright_1"
	},
	"antimatter_engine": {
		"name": "Antimatter Engine",
		"slot_type": "engine",
		"stats": {"eva": 70, "energy_load": 200},
		"cost": {"credits": 5000, "VoidArtifact": 1, "AdvCircuit": 5},
		"desc": "Experimental FTL-capable drive.",
		"research_req": "capital_ship_engineering"
	},
	# Weapons T2/T3
	"mining_laser_mk3": {
		"name": "Plasma Lance Mk.III",
		"slot_type": "weapon",
		"stats": {"atk_energy": 75, "energy_load": 25, "atk_interval": 1.2},
		"cost": {"credits": 25000, "Si": 50, "Ti": 20, "AdvCircuit": 10},
		"desc": "Cutting-edge beam weapon. Devastates shields.",
		"research_req": "shipwright_2"
	},
	"railgun_mk2": {
		"name": "Heavy Railgun",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 75, "energy_load": 20, "atk_interval": 3.5},
		"cost": {"credits": 25000, "Steel": 50, "W": 10, "AlWire": 20}, # v62.0 Fix: Added AlWire sink
		"desc": "Magnetic accelerator. Armor penetration.",
		"research_req": "ballistics_optimization"
	},
	"railgun_mk3": {
		"name": "Coil Cannon",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 280, "energy_load": 25, "atk_interval": 4.0},
		"cost": {"credits": 2000000, "Steel": 500, "AdvCircuit": 150, "Superalloy": 100, "Diamond": 5},
		"desc": "Devastating kinetic damage. Hull shredder.",
		"research_req": "capital_ship_engineering"
	},
	# Shields T2
	"advanced_shield": {
		"name": "Hardened Deflectors",
		"slot_type": "shield",
		"stats": {"max_shield": 150, "shield_regen": 5, "energy_load": 200},
		"cost": {"credits": 3000, "Si": 200, "Circuit": 10},
		"desc": "Enhanced shield projectors with rapid regeneration.",
		"research_req": "shipwright_1"
	},
	"composite_armor": {
		"name": "Composite Plating",
		"slot_type": "armor",
		"stats": {"def": 45, "hp": 350},
		"cost": {"credits": 2000, "Ti": 50, "Graphite": 20},
		"desc": "Layered titanium-carbon armor.",
		"research_req": "shipwright_2"
	},
	# Early Game Budget Modules
	"aluminum_hull_patch": {
		"name": "Aluminum Hull Patch",
		"slot_type": "armor",
		"stats": {"hp": 50, "eva": 5},
		"cost": {"credits": 150, "Al": 15},
		"desc": "Lightweight plating. Less protection but improved maneuverability.",
		"research_req": "lightweight_alloys"
	},
	"mg_al_frame": {
		"name": "Magnesium-Aluminum Frame",
		"slot_type": "armor",
		"stats": {"hp": 80, "eva": 10},
		"cost": {"credits": 400, "AlMgAlloy": 10},
		"desc": "Aerospace alloy. High strength-to-weight ratio increases evasion.",
		"research_req": "adv_materials"
	},
	"galvanized_plating": {
		"name": "Galvanized Plating",
		"slot_type": "armor",
		"stats": {"def": 18, "hp": 100},
		"cost": {"credits": 600, "GalvanizedSteel": 15},
		"desc": "Corrosion-proof steel. Reliable mid-tier armor.",
		"research_req": "smelting"
	},
	# Mid-Game Advanced Modules
	"stainless_armor": {
		"name": "Stainless Steel Armor",
		"slot_type": "armor",
		"stats": {"def": 50, "hp": 350},
		"cost": {"credits": 12000, "StainlessSteel": 25},
		"desc": "Superior corrosion resistance. Excellent mid-tier protection.",
		"research_req": "metallurgy_advanced"
	},
	"cobalt_battery_module": {
		"name": "Cobalt-Lithium Battery Pack",
		"slot_type": "battery",
		"stats": {"energy_capacity": 300},
		"cost": {"credits": 2000, "CoBattery": 5, "Circuit": 10},
		"desc": "High energy density. 3x capacity of basic batteries.",
		"research_req": "advanced_batteries"
	},
	"mg_battery_module": {
		"name": "Magnesium-Ion Cell Array",
		"slot_type": "battery",
		"stats": {"energy_capacity": 250, "eva": 5},
		"cost": {"credits": 1800, "MgBattery": 5, "AlWire": 15},
		"desc": "Lightweight batteries. Fast charge + improved evasion.",
		"research_req": "advanced_batteries"
	},
	"superalloy_engine": {
		"name": "Superalloy Engine Core",
		"slot_type": "engine",
		"stats": {"eva": 45, "energy_load": 20},
		"cost": {"credits": 350000, "Superalloy": 20, "Circuit": 15},
		"desc": "Heat-resistant alloy engine. High performance between Plasma and Antimatter.",
		"research_req": "superalloy_engineering"
	},
	# ITER5 FIX: CompositeWeave use
	"composite_armor_mk2": {
		"name": "Composite Armor Mk.II",
		"slot_type": "armor",
		"stats": {"hp": 300, "def": 40, "eva": 15},
		"cost": {"credits": 8000, "CompositeWeave": 15, "Ti": 20},
		"desc": "Advanced woven armor. Balanced HP, DEF, and evasion.",
		"research_req": "adv_materials"
	},
	# Late-Game Rare Metal Modules
	"iridium_armor": {
		"name": "Iridium Armor Plating",
		"slot_type": "armor",
		"stats": {"def": 100, "hp": 500},
		"cost": {"credits": 8500000, "IrPlate": 15},
		"desc": "Nearly indestructible. Ultimate defensive module. (Hardened)",
		"research_req": "iridium_metallurgy",
		"hardened": true
	},
	"osmium_core_module": {
		"name": "Osmium Armor Plating",
		"slot_type": "armor",
		"stats": {"hp": 5000, "def": 50},
		"cost": {"credits": 12500000, "OsCore": 3, "Os": 25},
		"desc": "Densest material. Massive HP boost. Immunity to armor piercing. (Hardened)",
		"research_req": "exotic_metallurgy",
		"hardened": true
	},
	"palladium_fuel_cell": {
		"name": "Palladium Fuel Cell Array",
		"slot_type": "battery",
		"stats": {"energy_capacity": 400, "energy_gen": 10},
		"cost": {"credits": 8000, "PdFuelCell": 10, "AdvCircuit": 5},
		"desc": "Pd-H2 fuel cell. Generates energy passively.",
		"research_req": "fuel_cell_tech"
	},
	# Audit v45.0: ReactiveCore sink
	"reactive_core_battery": {
		"name": "Reactive Core Battery",
		"slot_type": "battery",
		"stats": {"energy_capacity": 150, "shield_regen": 5},
		"cost": {"credits": 75000, "ReactiveCore": 5, "RadIsotope": 20, "Circuit": 30},
		"desc": "Radioactive core. Boosts shield regeneration. (Sector Gamma drop)",
		"research_req": "radiation_shielding"
	},
	"iridium_penetrator": {
		"name": "Iridium-Tungsten Penetrator",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 500, "energy_load": 30, "atk_interval": 3.0},
		"cost": {"credits": 12000000, "IrWAlloy": 30, "AdvCircuit": 30,"SyntheticCrystal":5},
		"desc": "Armor-piercing penetrator. Ignores 50% of enemy armor.",
		"research_req": "iridium_metallurgy"
	},
	"platinum_laser": {
		"name": "Platinum-Enhanced Laser",
		"slot_type": "weapon",
		"stats": {"atk_energy": 350, "energy_load": 35, "atk_interval": 2.0},
		"cost": {"credits": 5000000, "PtCatalyst": 20, "AdvCircuit": 30, "SyntheticCrystal": 5},
		"desc": "Pt-coated optics. Superior energy damage.",
		"research_req": "industrial_catalysis"
	},
	# UNIQUE MODULES (Mid-Late Game)
	"reactive_armor": {
		"name": "Reactive Plate Alpha",
		"slot_type": "armor",
		"stats": {"hp": 1000, "def": 20},
		"cost": {"credits": 1500000, "Superalloy": 50, "AdvCircuit": 10, "AncientComponent": 5, "ReactiveCore": 2},
		"desc": "(Unique) Adaptive plating. Reduces incoming damage as Hull decreases.",
		"research_req": "superalloy_engineering",
		"unique_id": "reactive_armor_effect"
	},
	"plasma_overcharger": {
		"name": "Plasma Overcharger",
		"slot_type": "weapon",
		"stats": {"atk_energy": 100, "energy_load": 300, "atk_interval": 0.8}, # Audit v40.0: Buffed ATK 202100
		"cost": {"credits": 1000000, "AdvCircuit": 50, "Superalloy": 75},
		"desc": "(Unique) Heavily boosts Energy Damage but consumes massive Reactor power.",
		"research_req": "energy_metrics",
		"unique_id": "plasma_overload_effect"
	},
	"reflective_sheath": {
		"name": "Reflective Phase Sheath",
		"slot_type": "shield",
		"stats": {"max_shield": 500, "shield_regen": 10},
		"cost": {"credits": 500000, "VoidCrystal": 5, "AdvCircuit": 15},
		"desc": "(Unique) 20% chance to reflect 50% of incoming damage back to the attacker.",
		"research_req": "exotic_metallurgy",
		"unique_id": "reflect_damage_effect"
	},
	"warp_stabilizer": {
		"name": "Warp-Field Stabilizer",
		"slot_type": "engine",
		"stats": {"eva": 40},
		"cost": {"credits": 150000, "NavData": 10, "Circuit": 20, "AncientComponent": 2},
		"desc": "(Unique) Stabilizes internal fields. Increases Combat Attack Speed by 15%.",
		"research_req": "warp_drive",
		"unique_id": "warp_combat_speed_effect"
	},
	"broadside_array": {
		"name": "Broadside Integrated Array",
		"slot_type": "weapon",
		"stats": {"energy_load": 100},
		"cost": {"credits": 500000, "Steel": 5000, "AdvCircuit": 20, "Hydraulics": 10},
		"desc": "(Unique) Automated burst fire system. Deals 300% Total Kinetic DPS every 20s.",
		"research_req": "broadside_tactics",
		"unique_id": "broadside_burst_effect"
	},
	# === SECTOR EPSILON ENDGAME MODULES ===
	"void_engine": {
		"name": "Void Phase Engine",
		"slot_type": "engine",
		"stats": {"eva": 180, "energy_load": 50}, # ITER7: 180 = ~55% dodge on new formula
		"cost": {"credits": 5000000, "VoidEssence": 10, "VoidCrystal": 30, "AdvCircuit": 50},
		"desc": "(Endgame) Phase through reality. High Evasion potential.",
		"research_req": "void_navigation"
	},
	"chrono_stabilizer": {
		"name": "Chrono Stabilizer",
		"slot_type": "shield",
		"stats": {"max_shield": 800, "shield_regen": 20},
		"cost": {"credits": 8000000, "ChronoCore": 5, "QuantumCore": 15, "AdvCircuit": 30, "ExoticIsotope": 10},
		"desc": "(Endgame) Temporal field. Slows enemy attack speed by 20%.",
		"research_req": "void_navigation",
		"unique_id": "chrono_slow_effect"
	},
	"omega_armor": {
		"name": "Omega Plating Array",
		"slot_type": "armor",
		"stats": {"def": 450, "hp": 3000}, # ITER7: 450 = ~47% mitigation in Sector Epsilon
		"cost": {"credits": 10000000, "OmegaPlating": 10, "Ir": 50, "Superalloy": 100},
		"desc": "(Endgame) Ultimate defensive module. +450 DEF, +3000 HP. (Hardened)",
		"research_req": "void_navigation",
		"hardened": true
	},
	"primordial_core": {
		"name": "★ Primordial Core ★",
		"slot_type": "battery",
		"stats": {"energy_capacity": 2000, "atk_speed_mult": 0.25, "shield_regen_mult": 0.25},
		"cost": {"credits": 25000000, "PrimordialShard": 5, "ChronoCore": 3, "VoidEssence": 10},
		"desc": "(Legendary) Heart of the Titan. +2000 Energy, +25% ATK Speed, +25% Shield Regen.",
		"research_req": "void_navigation",
		"unique_id": "primordial_power"
	},
	"omega_beam": {
		"name": "★ Omega Beam ★",
		"slot_type": "weapon",
		"stats": {"atk_energy": 1200, "energy_load": 100, "atk_interval": 0.5},
		"cost": {"credits": 25000000, "OmegaPlating": 5, "VoidEssence": 5},
		"desc": "(Endgame) Concentrated void energy stream. Deletes matter.",
		"research_req": "void_navigation"
	},
	# ========== ULTIMATE MODULES (P0-6: Endgame Crafted Item Sinks) ==========
	"void_battery_array": {
		"name": "★ Void Battery Array ★",
		"slot_type": "battery",
		"stats": {"energy_capacity": 3000, "energy_gen": 30, "shield_regen_mult": 0.75},
		"cost": {"credits": 50000000, "VoidBattery": 5},
		"desc": "(Legendary) Pinnacle of void engineering. +3000 Energy, +30 Passive Regen, +75% Shield Regen.",
		"research_req": "void_navigation"
	},
	"temporal_drive": {
		"name": "★ Temporal Drive ★",
		"slot_type": "engine",
		"stats": {"eva": 120, "atk_speed_mult": 0.75, "energy_load": 75},
		"cost": {"credits": 75000000, "TemporalModule": 3},
		"desc": "(Legendary) Bends time itself. +120 EVA, +75% Attack Speed.",
		"research_req": "void_navigation"
	},
	"primordial_fortification": {
		"name": "★ Primordial Fortification ★",
		"slot_type": "armor",
		"stats": {"hp": 15000, "def": 300, "max_shield": 1000, "shield_regen": 30},
		"cost": {"credits": 100000000, "PrimordialArmor": 3},
		"desc": "(Legendary) Invincible titan shell. +15000 HP, +300 DEF, +1000 Shield. (Super-Hardened)",
		"research_req": "void_navigation",
		"hardened": true # Logic in Combat Manager will check for this ID specifically for 100% resist
	},
	"omega_singularity": {
		"name": "★★ Omega Singularity ★★",
		"slot_type": "battery",
		"stats": {"energy_capacity": 5000, "energy_gen": 100, "atk_speed_mult": 0.50, "shield_regen_mult": 1.0},
		"cost": {"credits": 250000000, "OmegaAccelerator": 2},
		"desc": "(Mythic) Reality-bending power source. THE ultimate module.",
		"research_req": "void_navigation"
	},
	# ========== AUDIT v20.0: DEAD RESOURCE ACTIVATION ==========
	# T5 Fix: AICore
	"ai_targeting_system": {
		"name": "AI Targeting System",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 10, "atk_energy": 10, "crit_chance": 0.20, "accuracy": 25, "atk_interval": 2.5},
		"cost": {"credits": 50000, "AICore": 3, "AdvCircuit": 10, "TurretCore": 1},
		"desc": "(Unique) Neural network targeting. +20% Crit Chance, +25 Accuracy.",
		"research_req": "industrial_automation",
		"unique_id": "ai_targeting_effect"
	},
	# T6 Fix: ExoticIsotope
	"exotic_shield_matrix": {
		"name": "Exotic Shield Matrix",
		"slot_type": "shield",
		"stats": {"max_shield": 300, "shield_regen": 15, "def": 30},
		"cost": {"credits": 100000, "ExoticIsotope": 5, "Superalloy": 20},
		"desc": "(Unique) Radiation-hardened shields. Reduces Gamma zone damage by 30%.",
		"research_req": "radiation_shielding",
		"unique_id": "exotic_shield_effect"
	},
	# T7 Fix: Diamond
	"diamond_edge_railgun": {
		"name": "Diamond-Edge Railgun",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 2400, "energy_load": 40, "atk_interval": 4.0},
		"cost": {"credits": 200000, "Diamond": 10, "W": 50, "Steel": 200},
		"desc": "Hyper-velocity penetrator. Best-in-class kinetic damage.",
		"research_req": "exotic_matter_analysis"
	},
	# T7 Fix: SyntheticCrystal
	"crystal_lens_laser": {
		"name": "Crystal Lens Laser",
		"slot_type": "weapon",
		"stats": {"atk_energy": 800, "energy_load": 50, "atk_interval": 1.0},
		"cost": {"credits": 15000000, "SyntheticCrystal": 25, "VoidCrystal": 10, "AdvCircuit": 50},
		"desc": "Focused coherent light. Best-in-class energy damage.",
		"research_req": "exotic_matter_analysis"
	},
	# v66.0: Unique Boss Gating Weapon
	"void_breaker_laser": {
		"name": "Void Breaker Laser",
		"slot_type": "weapon",
		"stats": {"atk_energy": 1200, "energy_load": 80, "atk_interval": 2.5},
		"cost": {"credits": 50000000, "VoidArtifact": 5, "VoidCrystal": 50, "QuantumCore": 10},
		"desc": "[UNIQUE] Emits a frequency capable of shattering temporal shielding.",
		"research_req": "void_navigation"
	}
}


func _init():
	recalc_stats()

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

func set_slot_ammo(slot_idx: int, ammo_id: String):
	ammo_loadout[slot_idx] = ammo_id
	# No recalc needed as ammo doesn't affect base stats usually

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
	
	# Audit v8.0 P1-25: Applied Physics Hub Bonus (+10% Energy Capacity)
	if rm:
		e_cap *= (1.0 + rm.get_efficiency_bonus("applied_physics"))
	
	if GameState.resources:
		GameState.resources.set_max_energy(e_cap)
	
	current_hp = min(current_hp, max_hp)
	
	# Phase 6: Expose Ship Generation for Grid Integration
	ship_energy_gen = 0.0
	for mid in loadout.values():
		if mid and mid in modules:
			ship_energy_gen += modules[mid]["stats"].get("energy_gen", 0.0)
	
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

# v71.0: Generate a rarity-boosted module drop from a base module ID
func generate_module_drop(base_module_id: String, rarity: int = Rarity.UNCOMMON) -> String:
	if base_module_id not in modules:
		print("generate_module_drop: Unknown base module '%s'" % base_module_id)
		return ""
	
	# Common modules are just base — no custom needed
	if rarity == Rarity.COMMON:
		GameState.resources.add_element(base_module_id, 1)
		inventory_updated.emit()
		return base_module_id
	
	var base = modules[base_module_id]
	var custom_id = "custom_%s_%d" % [base_module_id, Time.get_ticks_msec()]
	
	# Apply stat bonuses based on rarity tier
	var stat_range = RARITY_STAT_RANGE.get(rarity, [0.05, 0.15])
	var custom_stats = {}
	for stat_key in base.get("stats", {}):
		var base_val = base["stats"][stat_key]
		if stat_key in BOOSTABLE_STATS:
			# Boost "good" stats by the rarity range
			var bonus = randf_range(stat_range[0], stat_range[1])
			var boosted = base_val * (1.0 + bonus)
			
			if base_val is float:
				custom_stats[stat_key] = boosted
			else:
				# Audit v76.0: Prevent integer truncation from deleting rarity bonuses on low-stat modules
				if base_val < 50:
					custom_stats[stat_key] = snappedf(boosted, 0.1)
				else:
					custom_stats[stat_key] = int(round(boosted))
		else:
			# Non-boostable stats (energy_load, atk_interval) stay at base
			custom_stats[stat_key] = base_val
	
	# v74.0: Affix Generation
	var custom_affixes = {}
	var affix_pool = AFFIX_DB.keys()
	
	var num_affixes = 0
	if rarity == Rarity.RARE: num_affixes = 1
	elif rarity == Rarity.LEGENDARY: num_affixes = 2
	
	if num_affixes > 0:
		affix_pool.shuffle()
		for i in range(num_affixes):
			var affix_id = affix_pool[i]
			var cfg = AFFIX_DB[affix_id]
			var val = randf_range(cfg["range"][0], cfg["range"][1])
			custom_affixes[affix_id] = val
	
	var rarity_label = RARITY_LABELS.get(rarity, "")
	var suffix = " (%s)" % rarity_label if rarity_label != "" else ""
	
	var custom_module = {
		"name": "%s%s" % [base.get("name", "Unknown"), suffix],
		"slot_type": base.get("slot_type", "weapon"),
		"stats": custom_stats,
		"cost": {},
		"desc": base.get("desc", ""),
		"is_custom": true,
		"rarity": rarity,
		"base_module": base_module_id,
		"affixes": custom_affixes # Add affixes here
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
	var legendary_chance = 0.05 if is_boss else 0.02
	if roll < legendary_chance:
		return Rarity.LEGENDARY
	elif roll < legendary_chance + 0.10:
		return Rarity.RARE
	elif roll < legendary_chance + 0.10 + 0.30:
		return Rarity.UNCOMMON
	else:
		return Rarity.COMMON

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
