

var active_hull: String = "corvette_hull"
var module_inventory: Dictionary = {}
var loadout: Dictionary = {} # {slot_index: module_id}
var ammo_loadout: Dictionary = {} # {slot_index: ammo_id}

# v66.0: Consumable Slots
var consumable_hull_slot: String = ""    # e.g. "Mesh"
var consumable_shield_slot: String = ""  # e.g. "BasicBooster"

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

var hulls: Dictionary = {
	"corvette_hull": {
		"name": "Corvette Hull",
		"stats": {"hp": 100, "atk": 10, "energy_capacity": 100},
		"cost": {"credits": 0},
		"slots": ["weapon", "weapon", "shield", "shield", "engine", "battery", "battery"], # 7 Slots
		"visual": "res://assets/ships/1.png",
		"tier": 0  # v61.0: Added for mission gating
	},
	"frigate_hull": {
		"name": "Industrial Frigate",
		"stats": {"hp": 800, "atk": 25, "energy_capacity": 250},
		"cost": {"credits": 5000, "Res1": 20},
		"slots": ["weapon", "weapon", "weapon", "shield", "shield", "shield", "engine", "battery", "battery", "battery", "sensor"], # 11 Slots (Added Sensor)
		"research_req": "shipwright_1",
		"visual": "res://assets/ships/2.png",
		"tier": 1  # v61.0
	},
	"destroyer_hull": {
		"name": "Destroyer Class",
		"stats": {"hp": 2500, "atk": 60, "energy_capacity": 600},
		"cost": {"credits": 37500, "Ti": 50, "Circuit": 25, "Res2": 10},
		"slots": ["weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "engine", "battery", "battery", "battery", "battery", "sensor", "cooling"], # 15 Slots (+Sensor, +Cooling)
		"research_req": "shipwright_2",
		"visual": "res://assets/ships/3.png",
		"tier": 2  # v61.0
	},
	"battlecruiser_hull": {
		"name": "Battlecruiser Class",
		"stats": {"hp": 8000, "atk": 120, "energy_capacity": 1500},
		"cost": {"credits": 375000, "Steel": 500, "AdvCircuit": 50, "VoidArtifact": 5, "Res3": 15},
		"slots": ["weapon", "weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "shield", "engine", "battery", "battery", "battery", "battery", "battery", "sensor", "sensor", "cooling", "cooling"], # 20 Slots (+2 Sensor, +2 Cooling)
		"research_req": "capital_ship_engineering",
		"visual": "res://assets/ships/4.png",
		"tier": 3  # v61.0
	},
	"dreadnought_hull": {
		"name": "Dreadnought Class",
		"stats": {"hp": 20000, "atk": 250, "energy_capacity": 4000},
		"cost": {"credits": 25000000, "Steel": 100000, "Ti": 2500, "Neutronium": 50, "Circuit": 1000, "Chip": 250, "Superalloy": 100, "AdvCircuit": 100, "QuantumCore": 10, "VoidArtifact": 25},
		"slots": ["weapon", "weapon", "weapon", "weapon", "weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "shield", "shield", "shield", "engine", "battery", "battery", "battery", "battery", "battery", "battery", "sensor", "sensor", "sensor", "cooling", "cooling", "cooling"], # +3 Sensor, +3 Cooling
		"research_req": "quantum_dynamics",
		"visual": "res://assets/ships/5.png",
		"tier": 4  # v61.0
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
		"stats": {"atk_energy": 40, "energy_load": 15}, 
		"cost": {"credits": 12500, "Si": 20, "Ti": 10, "Circuit": 10, "Chip": 10},
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
	"targeting_computer": {
		"name": "Targeting Computer",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 15, "atk_energy": 15, "accuracy": 25, "energy_load": 5},  # Audit v40.0: Buffed ATK 5→15
		"cost": {"credits": 750, "Chip": 10, "Si": 20},
		"desc": "Advanced analytics. +25 Accuracy for all weapons.",
		"research_req": "automated_logistics"
	},
	"cryo_laser_mk3": {
		"name": "Cryo-Cooled Laser Mk.III",
		"slot_type": "weapon",
		"stats": {"atk_energy": 80, "energy_load": 20},
		"cost": {"credits": 1125000, "Ti": 30, "CoolantCell": 5, "AdvCircuit": 3},
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
		"stats": {"atk_explosive": 450, "energy_load": 60, "atk_interval": 12.0},
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
		"stats": {"jamming_strength": 0.10, "energy_load": 15},
		"cost": {"credits": 8000, "Circuit": 15, "Magnet": 5},
		"desc": "Disrupts comms. Slows enemies by 10%.",
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
		"stats": {"energy_capacity": 150, "atk_speed_mult": 0.10},  # ITER4: +10% attack speed
		"cost": {"BatteryT2": 10},
		"desc": "High-density Storage. +10% Attack Speed.",
		"research_req": "adv_materials"
	},
	"battery_t3": {
		"name": "Zero-Point Module",
		"slot_type": "battery",
		"stats": {"energy_capacity": 500, "shield_regen_mult": 0.20},  # ITER4: +20% shield regen
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
		"slot_type": "shield", 
		"stats": {"def": 35, "hp": 250}, 
		"cost": {"credits": 5000, "Graphite": 20},
		"desc": "Ablative carbon armor. Increases Hull & Armor.",
		"research_req": "adv_materials"
	},
	"titanium_armor": {
		"name": "Titanium Plating",
		"slot_type": "shield", 
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
		"stats": {"eva": 70, "energy_load": 30},
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
		"cost": {"credits": 25000, "Steel": 50, "W": 10, "AlWire": 20},  # v62.0 Fix: Added AlWire sink
		"desc": "Magnetic accelerator. Armor penetration.",
		"research_req": "ballistics_optimization"
	},
	"railgun_mk3": {
		"name": "Coil Cannon",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 100, "energy_load": 25, "atk_interval": 4.0},
		"cost": {"credits": 1000000, "Steel":300, "AdvCircuit": 100, "Superalloy": 75},
		"desc": "Devastating kinetic damage. Hull shredder.",
		"research_req": "capital_ship_engineering"
	},
	# Shields T2
	"advanced_shield": {
		"name": "Hardened Deflectors",
		"slot_type": "shield",
		"stats": {"max_shield": 150, "shield_regen": 5, "energy_load": 25},
		"cost": {"credits": 3000, "Si": 200, "Circuit": 10},
		"desc": "Enhanced shield projectors with rapid regeneration.",
		"research_req": "shipwright_1"
	},
	"composite_armor": {
		"name": "Composite Plating",
		"slot_type": "shield",
		"stats": {"def": 45, "hp": 350},
		"cost": {"credits": 2000, "Ti": 50, "Graphite": 20},
		"desc": "Layered titanium-carbon armor.",
		"research_req": "shipwright_2"
	},
	# Early Game Budget Modules
	"aluminum_hull_patch": {
		"name": "Aluminum Hull Patch",
		"slot_type": "shield",
		"stats": {"hp": 50, "eva": 5},
		"cost": {"credits": 150, "Al": 15},
		"desc": "Lightweight plating. Less protection but improved maneuverability.",
		"research_req": "lightweight_alloys"
	},
	"mg_al_frame": {
		"name": "Magnesium-Aluminum Frame",
		"slot_type": "shield",
		"stats": {"hp": 80, "eva": 10},
		"cost": {"credits": 400, "AlMgAlloy": 10},
		"desc": "Aerospace alloy. High strength-to-weight ratio increases evasion.",
		"research_req": "adv_materials"
	},
	"galvanized_plating": {
		"name": "Galvanized Plating",
		"slot_type": "shield",
		"stats": {"def": 18, "hp": 100},
		"cost": {"credits": 600, "GalvanizedSteel": 15},
		"desc": "Corrosion-proof steel. Reliable mid-tier armor.",
		"research_req": "smelting"
	},
	# Mid-Game Advanced Modules
	"stainless_armor": {
		"name": "Stainless Steel Armor",
		"slot_type": "shield",
		"stats": {"def": 30, "hp": 180},
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
		"slot_type": "shield",
		"stats": {"hp": 300, "def": 40, "eva": 15},
		"cost": {"credits": 8000, "CompositeWeave": 15, "Ti": 20},
		"desc": "Advanced woven armor. Balanced HP, DEF, and evasion.",
		"research_req": "adv_materials"
	},
	# Late-Game Rare Metal Modules
	"iridium_armor": {
		"name": "Iridium Armor Plating",
		"slot_type": "shield",
		"stats": {"def": 100, "hp": 500},
		"cost": {"credits": 8500000, "IrPlate": 15},
		"desc": "Nearly indestructible. Ultimate defensive module. (Hardened)",
		"research_req": "iridium_metallurgy",
		"hardened": true
	},
	"osmium_core_module": {
		"name": "Osmium Reactor Core",
		"slot_type": "shield",
		"stats": {"hp": 5000, "def": 50},
		"cost": {"credits": 12500000, "OsCore": 3},
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
		"stats": {"atk_kinetic": 350, "energy_load": 30},
		"cost": {"credits": 12000, "IrWAlloy": 30, "Circuit": 20},
		"desc": "Armor-piercing penetrator. Ignores 50% of enemy armor.",
		"research_req": "iridium_metallurgy"
	},
	"platinum_laser": {
		"name": "Platinum-Enhanced Laser",
		"slot_type": "weapon",
		"stats": {"atk_energy": 300, "energy_load": 35},
		"cost": {"credits": 5000000, "Pt": 20, "Si": 100, "AdvCircuit": 15},
		"desc": "Pt-coated optics. Superior energy damage.",
		"research_req": "industrial_catalysis"
	},
	# UNIQUE MODULES (Mid-Late Game)
	"reactive_armor": {
		"name": "Reactive Plate Alpha",
		"slot_type": "shield",
		"stats": {"hp": 1000, "def": 20},
		"cost": {"credits": 1500000, "Superalloy": 50, "AdvCircuit": 10, "AncientComponent": 5},
		"desc": "(Unique) Adaptive plating. Reduces incoming damage as Hull decreases.",
		"research_req": "superalloy_engineering",
		"unique_id": "reactive_armor_effect"
	},
	"plasma_overcharger": {
		"name": "Plasma Overcharger",
		"slot_type": "weapon",
		"stats": {"atk_energy": 100, "energy_load": 50},  # Audit v40.0: Buffed ATK 20→100
		"cost": {"credits": 1000000, "AdvCircuit": 50, "Superalloy":75},
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
		"cost": {"credits": 8000000, "ChronoCore": 5, "QuantumCore": 15, "AdvCircuit": 30},
		"desc": "(Endgame) Temporal field. Slows enemy attack speed by 20%.",
		"research_req": "void_navigation",
		"unique_id": "chrono_slow_effect"
	},
	"omega_armor": {
		"name": "Omega Plating Array",
		"slot_type": "shield",
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
		"slot_type": "shield",
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
		"stats": {"atk_kinetic": 10, "atk_energy": 10, "crit_chance": 0.20, "accuracy": 25},
		"cost": {"credits": 50000, "AICore": 3, "AdvCircuit": 10},
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
		"stats": {"atk_kinetic": 600, "energy_load": 40},
		"cost": {"credits": 200000, "Diamond": 10, "W": 50, "Steel": 200},
		"desc": "Hyper-velocity penetrator. Best-in-class kinetic damage.",
		"research_req": "exotic_matter_analysis"
	},
	# T7 Fix: SyntheticCrystal
	"crystal_lens_laser": {
		"name": "Crystal Lens Laser",
		"slot_type": "weapon",
		"stats": {"atk_energy": 700, "energy_load": 50},
		"cost": {"credits": 250000, "SyntheticCrystal": 10, "Si": 500, "AdvCircuit": 30},
		"desc": "Focused coherent light. Best-in-class energy damage.",
		"research_req": "exotic_matter_analysis"
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
	# Since capacity can change based on module being equipped/unequipped, 
	# we do a simple check: is the new module adding more load than the ship currently has room for?
	# However, it's safer to allow the equip and let recalc_stats() handle the "Grid Overloaded" state 
	# or just block after calculation. Let's stick to blocking if total load > current capacity.
	var current_cap = hulls[active_hull]["stats"].get("energy_capacity", 100.0)
	for s_idx in loadout:
		if s_idx == slot_idx: continue
		var mid = loadout[s_idx]
		if mid and modules.has(mid):
			current_cap += modules[mid]["stats"].get("energy_capacity", 0)
	if mod_data["slot_type"] == "battery":
		current_cap += mod_data["stats"].get("energy_capacity", 0)
	
	if potential_load > current_cap:
		print("Equip Fail: Grid Overloaded. Needs more battery modules.")
		return false

	# Unequip existing
	if existing:
		module_inventory[existing] += 1
		
	module_inventory[module_id] -= 1
	loadout[slot_idx] = module_id
	
	recalc_stats()
	
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
			# Note: Ammo is a RESOURCE, not a MODULE. Check GameState.resources.
			if GameState.resources.get_element_amount("missile") > 0:
				ammo_loadout[slot_idx] = "missile"
			# Fallback if no specific explosive ammo is found
			else:
				print("Equip: No explosive ammo (missile) found in resources for auto-equip.")
			
	return true

func unequip_slot(slot_idx: int):
	var existing = loadout.get(slot_idx)
	if existing:
		module_inventory[existing] = module_inventory.get(existing, 0) + 1
		loadout[slot_idx] = null
		recalc_stats()

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
	attack = atk_k + atk_e + atk_x
	defense = defe
	evasion = eva
	accuracy = acc
	crit_chance = crit
	energy_used = e_load
	attack_speed_bonus = atk_speed_bon
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
	return data

func load_save_data_manager(data: Dictionary):
	if data.is_empty(): return
	
	active_hull = data.get("active_hull", "corvette_hull")
	var saved_load = data.get("loadout", {})
	
	if data.has("consumable_hull_slot"): consumable_hull_slot = data["consumable_hull_slot"]
	if data.has("consumable_shield_slot"): consumable_shield_slot = data["consumable_shield_slot"]
	
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
