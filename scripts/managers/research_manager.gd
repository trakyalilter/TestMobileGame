extends Skill

signal activity_occurred

var action_duration = 5.0
var current_action = ""
var is_active = false
var action_progress = 0.0

# v56.0: Progression Pacing Extension - 2.5x credit costs for 30-40h playtime
const COST_MULTIPLIER = 2.5
# v56.1: 2x material requirements for progression extension
const MATERIAL_MULTIPLIER = 2.0

var unlocked_techs = []
var repeatable_techs = {} # {id: level}

signal tech_unlocked(tech_id)

func _on_research_completed(active_tech_id):
	activity_occurred.emit()

var tech_tree = {
	"basic_engineering": {
		"name": "Basic Engineering",
		"description": "Unlocks:\n• Mineral Washing\n• Scrap Recycling\n• Lithium Refining",
		"cost": 50,
		"type": "technology",
		"parent": null
	},
	"applied_physics": {
		"name": "Applied Physics",
		"description": "Fundamental theory of energy and mass.\nFirst tier accessible with Credits.",
		"cost": 250,
		"type": "technology",
		"parent": "basic_engineering"
	},
	"materials_science": {
		"name": "Materials Science",
		"description": "Elementary studies of matter and chemical bonding.\nFirst tier accessible with Credits.",
		"cost": 250,
		"type": "technology",
		"parent": "basic_engineering"
	},
	"industrial_logistics": {
		"name": "Industrial Logistics",
		"description": "Efficiency frameworks and sorting algorithms.\nFirst tier accessible with Credits.",
		"cost": 250,
		"type": "technology",
		"parent": "basic_engineering"
	},
	"fluid_dynamics": {
		"name": "Fluid Dynamics",
		"description": "Unlocks:\n• Water Pumping\n• Electrolysis",
		"cost": 50,
		"type": "technology",
		"parent": "applied_physics"
	},
	"combustion": {
		"name": "Organic Combustion",
		"description": "Unlocks:\n• Charcoal Kiln\n• Fly Ash Separation\n• HE Missile (Ammo)\n• Micro-Missile Launcher",
		"cost": 50,
		"type": "technology",
		"parent": "materials_science"
	},
	"smelting": {
		"name": "Efficient Smelting",
		# v61.0 Fix: Bronze Alloy doesn't exist, corrected to Galvanized Steel
		"description": "Unlocks:\n• Steel Foundry\n• Galvanized Steel",
		"cost": 1500,  # Audit v41.0: Reduced from 3000 to smooth progression
		"cost_items": {"Res1": 7, "Circuit": 15},
		"type": "technology",
		"parent": "combustion"
	},
	"shipwright_1": {
		"name": "Shipwright I",
		"description": "Unlocks:\n• Industrial Frigate (T2)\n• Titanium Plating",
		"cost": 2000,
		"cost_items": {"Res1": 20},
		"type": "technology",
		"parent": "smelting"
	},

	"shipwright_2": {
		"name": "Shipwright II",
		"description": "Unlocks:\n• Escort Destroyer (T3)",
		"cost": 2000,
		"cost_items": {"Res2": 10},
		"type": "technology",
		"parent": "shipwright_1"
	},
	"adv_materials": {
		"name": "Advanced Materials",
		"description": "Unlocks:\n• Graphite Press\n• Semiconductor Wafer\n• Graphene Battery\n• Quartz Resonator (Auto)\n• Heavy Tungsten Drill (Auto)",
		"cost": 2000,
		"cost_items": {"Res2": 10},
		"type": "technology",
		"parent": "smelting"
	},
	"energy_shields": {
		"name": "Energy Fields",
		"description": "Unlocks:\n• Deflector Shield",
		"cost": 500,
		"type": "technology",
		"parent": "applied_physics"
	},
	"eff_scanning_1": {
		"name": "Sensor Calibration",
		"description": "Optimizes sensor arrays for better data retrieval.\nBonus: +50% Scanning Yield",
		"cost": 150,
		"type": "technology",
		"parent": "applied_physics"
	},

	"automation": {
		"name": "Factory Automation",
		"description": "Unlocks:\n• Advanced Circuitry\n• Automated Assembly Line",
		"cost": 5000,
		"cost_items": {"Res2": 25, "Circuit": 20},
		"type": "technology",
		"parent": "adv_materials"
	},
	"advanced_rocketry": {
		"name": "Advanced Rocketry",
		"description": "Unlocks:\n• Seeker Missile Mk.II\n• Seeker Missile (Ammo)",
		"cost": 15000,
		"cost_items": {"Steel": 100, "Circuit": 50},
		"type": "technology",
		"parent": "automation"
	},
	"sector_alpha_decryption": {
		"name": "Sector Scanning (Alpha)",
		"description": "Unlocks:\n• Sector Alpha (Titanium)\n\nRequires Titan Clearance from Titan Overseer.",
		"cost_items": {"NavData": 10, "PirateManifest": 10, "TitanClearance": 1},
		"type": "technology",
		"parent": "shipwright_1"
	},
	"xeno_archaeology": {
		"name": "Xeno-Archaeology",
		"description": "Unlocks:\n• Analyze Void Artifact",
		"cost": 2000,
		"cost_items": {"VoidArtifact": 1, "NavData": 5},
		"type": "technology",
		"parent": "sector_alpha_decryption"
	},
	"warp_drive": {
		"name": "Warp Drive Theory",
		"description": "Unlocks:\n• Galaxy Map",
		"cost": 5000,
		"cost_items": {"NavData": 50, "Ti": 200, "Res3": 10},
		"type": "technology",
		"parent": "shipwright_2"
	},
	# --- v56.1: CONTENT GATES (Intermediate milestones) ---
	"asteroid_clearance": {
		"name": "Asteroid Belt Clearance",
		"description": "Official mining license for Asteroid Belt operations.\nUnlocks:\n• Asteroid Belt zone\n• Claim Jumper enemy",
		"cost": 2500,
		"cost_items": {"PirateManifest": 3, "NavData": 5, "Fe": 100},
		"type": "technology",
		"parent": "shipwright_1"
	},
	"mars_license": {
		"name": "Mars Sector License",
		"description": "Authorization for Mars Debris Field salvage operations.\nUnlocks:\n• Mars Debris Field zone\n• Derelict Frigate enemy",
		"cost": 10000,
		"cost_items": {"StolenCargo": 5, "NavData": 15, "Steel": 50},
		"type": "technology",
		"parent": "asteroid_clearance"
	},
	"outer_system_auth": {
		"name": "Outer System Authorization",
		"description": "Permits exploration beyond the inner planets.\nUnlocks:\n• Titan's Halo zone\n• Pirate Gunship enemy",
		"cost": 25000,
		"cost_items": {"ColonySalvage": 3, "Ti": 100, "Res2": 20},
		"type": "technology",
		"parent": "mars_license"
	},
	"deep_space_expedition": {
		"name": "Deep Space Expedition",
		"description": "Full authorization for deep space operations.\nUnlocks:\n• Sector Beta, Gamma, Delta zones\n• Endgame enemies",
		"cost": 100000,
		"cost_items": {"VoidArtifact": 3, "Res3": 25, "AdvCircuit": 25},
		"type": "technology",
		"parent": "outer_system_auth"
	},
	# v57.1: Sector Zeta research requirement
	"quarantine_protocols": {
		"name": "Quarantine Protocols",
		"description": "Biohazard containment and pathogen research.\nUnlocks:\n• Sector Zeta zone\n• Bio-Agent Synthesis\n• AI Processor Array\n• Regenerative Plating",
		"cost": 150000,
		"cost_items": {"Res3": 40, "VoidCrystal": 10, "AdvCircuit": 30},
		"type": "technology",
		"parent": "deep_space_expedition"
	},
	# --- NEW EARLY GAME GATES ---
	"kinetics_101": {
		"name": "Kinetic Weapons Theory",
		"description": "Unlocks:\n• Mass Driver",
		"cost": 50,
		"type": "technology",
		"parent": "applied_physics"
	},
	"laser_optics": {
		"name": "Laser Optics",
		# v61.0 Fix: Module is named Pulse Laser, not Focused Laser
		"description": "Unlocks:\n• Pulse Laser Mk.II",
		"cost": 300,
		"cost_items": {"Res1": 5},
		"type": "technology",
		"parent": "fluid_dynamics"
	},

	"power_systems": {
		"name": "Power Systems",
		"description": "Unlocks:\n• Basic Battery Module",
		"cost": 300,
		"type": "technology",
		"parent": "applied_physics"
	},
	"lightweight_alloys": {
		"name": "Lightweight Alloys",
		"description": "Unlocks:\n• Aluminum Smelting\n• Aluminum-Magnesium Alloy",
		"cost": 200,
		"cost_items": {"Res1": 3},
		"type": "technology",
		"parent": "materials_science"
	},
	"basic_electronics": {
		"name": "Basic Electronics",
		"description": "Unlocks:\n• Standard Circuit Assembly (Industrial)",
		"cost": 800,
		"cost_items": {"Cu": 20, "Si": 20},
		"type": "technology",
		"parent": "industrial_logistics"
	},
	# --- GATHERING UPGRADES ---
	"diamond_drills": {
		"name": "Diamond Tipped Drills",
		"description": "Bonus:\n• +25% Excavate Soil speed",
		"cost": 200,
		"cost_items": {"Res1": 2},
		"type": "technology",
		"parent": "industrial_logistics"
	},
	"high_flow_pumps": {
		"name": "High-Flow Pumps",
		"description": "Bonus:\n• +50% Pump Water speed",
		"cost": 250,
		"cost_items": {"Res1": 2},
		"type": "technology",
		"parent": "fluid_dynamics"
	},
	"laser_cutters": {
		"name": "Laser Cutters",
		"description": "Bonus:\n• +50% Deforest Zone speed",
		"cost": 300,
		"cost_items": {"Res1": 2},
		"type": "technology",
		"parent": "combustion"
	},
	"magnetic_funnels": {
		"name": "Magnetic Funnels",
		"description": "Bonus:\n• +25% Harvest Nebula speed",
		"cost": 2000,
		"cost_items": {"Res1": 10},
		"type": "technology",
		"parent": "energy_shields"
	},
	# Gathering Tier 2 (+50%) & Tier 3 (+75%)
	"ultrasonic_drills": {
		"name": "Ultrasonic Drills",
		"description": "Bonus:\n• +50% Excavate Soil speed",
		"cost": 1000,
		"cost_items": {"Res1": 10},
		"type": "technology",
		"parent": "diamond_drills"
	},
	"plasma_bore": {
		"name": "Plasma Bore",
		"description": "Bonus:\n• +75% Excavate Soil speed",
		"cost": 5000,
		"type": "technology",
		"parent": "ultrasonic_drills"
	},
	"superfluid_intake": {
		"name": "Superfluid Intake",
		"description": "Bonus:\n• +50% Pump Water speed",
		"cost": 1500,
		"type": "technology",
		"parent": "high_flow_pumps"
	},
	"hydro_vortex": {
		"name": "Hydro-Vortex Arrays",
		"description": "Bonus:\n• +75% Pump Water speed",
		"cost": 7500,
		"type": "technology",
		"parent": "superfluid_intake"
	},
	"mono_filament": {
		"name": "Mono-Filament Wire",
		"description": "Bonus:\n• +50% Deforest Zone speed",
		"cost": 2000,
		"type": "technology",
		"parent": "laser_cutters"
	},
	"molecular_disassembler": {
		"name": "Molecular Disassembler",
		"description": "Bonus:\n• +75% Deforest Zone speed",
		"cost": 10000,
		"type": "technology",
		"parent": "mono_filament"
	},
	# --- PROCESSING UPGRADES ---
	"fast_centrifuges": {
		"name": "High-RPM Centrifuges",
		"description": "Bonus:\n• +25% Mineral Washing speed",
		"cost": 200,
		"type": "technology",
		"parent": "industrial_logistics"
	},
	"catalytic_electrodes": {
		"name": "Catalytic Electrodes",
		"description": "Bonus:\n• +25% Electrolysis speed",
		"cost": 300,
		"type": "technology",
		"parent": "fluid_dynamics"
	},
	"pyrolysis_control": {
		"name": "Pyrolysis Control",
		"description": "Bonus:\n• +25% Charcoal Kiln speed",
		"cost": 400,
		"cost_items": {"Res1": 5},
		"type": "technology",
		"parent": "combustion"
	},
	"blast_furnace": {
		"name": "Blast Furnace",
		"description": "Bonus:\n• +25% Steel Foundry speed",
		"cost": 800,
		"cost_items": {"Res1": 10},
		"type": "technology",
		"parent": "smelting"
	},
	"hydraulic_press": {
		"name": "Hydraulic Press",
		"description": "Bonus:\n• +25% Graphite Press speed",
		"cost": 1500,
		"type": "technology",
		"parent": "adv_materials"
	},
	# Processing Tier 2 (+50%) & Tier 3 (+75%)
	"maglev_bearings": {
		"name": "Mag-Lev Bearings",
		"description": "Bonus:\n• +50% Mineral Washing speed",
		"cost": 1000,
		"type": "technology",
		"parent": "fast_centrifuges"
	},
	"quantum_separators": {
		"name": "Quantum Separators",
		"description": "Bonus:\n• +75% Mineral Washing speed",
		"cost": 5000,
		"type": "technology",
		"parent": "maglev_bearings"
	},
	"advanced_mineralogy": {
		"name": "Advanced Mineralogy",
		"description": "Industrial Centrifuges now have a chance to extract Titanium (Ti) from Dirt processing.",
		"cost": 5000,
		"cost_items": {"Si": 100, "Fe": 100},
		"type": "technology",
		"parent": "fast_centrifuges"
	},
	"ion_exchange": {
		"name": "Ion-Exchange Membranes",
		"description": "Bonus:\n• +50% Electrolysis speed",
		"cost": 1500,
		"type": "technology",
		"parent": "catalytic_electrodes"
	},
	"resonance_splitters": {
		"name": "Resonance Splitters",
		"description": "Bonus:\n• +75% Electrolysis speed",
		"cost": 7500,
		"type": "technology",
		"parent": "ion_exchange"
	},
	# --- MILITARY UPGRADES ---
	"processing_tungsten": {
		"name": "Processing Tungsten",
		"description": "Unlocks:\n• Tungsten Sabot Rounds (T2)",
		"cost": 1000,
		"cost_items": {"Res1": 10},
		"type": "technology",
		"parent": "smelting"
	},
	"ballistics_optimization": {
		"name": "Ballistics Optimization", 
		"description": "Unlocks:\n• Depleted Uranium Rounds (T3)\n• Heavy Railgun",
		"cost": 1500,
		"type": "technology",
		"parent": "processing_tungsten"
	},
	"energy_metrics": {
		"name": "Energy Metrics",
		"description": "High-capacity storage and generation theory.\nUnlocks:\n• Hydrogen Reactor\n• Vaporizer Cells (T3)\n• Plasma Lance Mk.III\n• Orbital Gas Siphon (Auto)\n• Uranium Centrifuge (Auto)",
		"cost": 5000,
		"cost_items": {"Res2": 20, "AdvCircuit": 10},
		"type": "technology",
		"parent": "fluid_dynamics"
	},
	"cryogenic_systems": {
		"name": "Cryogenic Systems",
		"description": "Unlocks:\n• Helium Coolant Cell\n• Cryo-Cooled Laser Mk.III",
		"cost": 25000,
		"cost_items": {"He": 50, "Ti": 30},
		"type": "technology",
		"parent": "energy_metrics"
	},
	# --- LOGISTICS UPGRADES ---
	"automated_logistics": {
		"name": "Automated Logistics",
		"description": "Unlocks:\n• Drone Bay",
		"cost": 3000,
		"type": "technology",
		"parent": "industrial_logistics"
	},
	"molecular_printing": {
		"name": "Molecular Printing",
		"description": "Unlocks:\n• Fabricator (+20% crafting)",
		"cost": 5000,
		"cost_items": {"Circuit": 50, "Fiber": 20},
		"type": "technology",
		"parent": "shipwright_2"
	},
	# --- END-GAME AUTOMATION (NEW) ---
	"automated_smelting": {
		"name": "Automated Smelting",
		"description": "Unlocks:\n• Auto-Smelter",
		"cost": 2500,
		"cost_items": {"Ti": 20},
		"type": "technology",
		"parent": "blast_furnace"
	},
	"oxygen_blast_furnace": {
		"name": "Oxygen-Blast Furnaces",
		"description": "Industrial optimization for Steel production. Increases Steel yield from 1 to 5 per cycle.",
		"cost": 5000,
		"cost_items": {"Steel": 100, "O": 200},
		"type": "technology",
		"parent": "blast_furnace"
	},
	"industrial_electrolysis": {
		"name": "Industrial Electrolysis",
		"description": "Unlocks:\n• Hydro-Plant",
		"cost": 2500,
		"cost_items": {"Si": 50},
		"type": "technology",
		"parent": "catalytic_electrodes"
	},
	"molecular_compression": {
		"name": "Molecular Compression",
		"description": "Unlocks:\n• Auto-Press",
		"cost": 3000,
		"cost_items": {"Fe": 100},
		"type": "technology",
		"parent": "hydraulic_press"
	},
	"mass_production_tactics": {
		"name": "Mass Production Tactics",
		"description": "Unlocks:\n• Munitions Factory",
		"cost": 5000,
		"cost_items": {"Circuit": 20, "Steel": 20},
		"type": "technology",
		"parent": "automated_logistics"
	},
	"xeno_engineering": {
		"name": "Xeno-Engineering",
		"description": "Unlocks:\n• Alien Flora Cultivation\n• Analyzing Xeno-Materials",
		"cost": 10000,
		"cost_items": {"SalvageData": 10, "Circuit": 50},
		"type": "technology",
		"parent": "automated_logistics"
	},
	# --- FLEET COMMAND TECHS (New) ---
	"fleet_logistics_1": {
		"name": "Fleet Logistics I",
		"description": "Unlocks:\n• Secondary Fleet Slot\n• Basic Expeditionary Command",
		"cost": 25000,
		"cost_items": {"Circuit": 100, "Ti": 100},
		"type": "technology",
		"parent": "automated_logistics"
	},
	"fleet_logistics_2": {
		"name": "Fleet Logistics II",
		"description": "Unlocks:\n• Tertiary Fleet Slot\n• Advanced Fleet Coordination",
		"cost": 250000,
		"cost_items": {"AdvCircuit": 50, "Gold": 20},
		"type": "technology",
		"parent": "fleet_logistics_1"
	},
	"automated_expeditions": {
		"name": "Predictive Route Planning",
		"description": "Bonus:\n• -25% Fleet Mission Interval",
		"cost": 50000,
		"cost_items": {"NavData": 50, "Circuit": 200},
		"type": "technology",
		"parent": "fleet_logistics_1"
	},
	# --- END-GAME SHIPS (NEW) ---
	"capital_ship_engineering": {
		"name": "Capital Ship Doctrine",
		"description": "Unlocks:\n• Battlecruiser (T4)\n• Coil Cannon\n• Antimatter Engine",
		"cost": 500000,
		"cost_items": {"VoidArtifact": 5, "Ti": 200, "Res3": 100, "ColonyDataCore": 5}, # Audit v20.0: Added ColonyDataCore (Overseer Drop)
		"type": "technology",
		"parent": "shipwright_2"
	},
	"capital_ship_armament": {
		"name": "Capital Ship Armament",
		"description": "Unlocks:\n• Heavy Torpedo Launcher\n• Photon Torpedo (Ammo)",
		"cost": 1000000,
		"cost_items": {"VoidArtifact": 10, "Superalloy": 50, "AdvCircuit": 50},
		"type": "technology",
		"parent": "capital_ship_engineering"
	},
	"quantum_dynamics": {
		"name": "Quantum Dynamics",
		"description": "Unlocks:\n• Dreadnought (T5)",
		"cost": 5000000,
		"cost_items": {"QuantumCore": 20, "VoidArtifact": 50, "Res3": 500},
		"type": "technology",
		"parent": "capital_ship_engineering"
	},
	"broadside_tactics": {
		"name": "Broadside Tactics",
		"description": "Unlocks:\n• Broadside Integrated Array (Burst Module)",
		"cost": 250000,
		"cost_items": {"Res3": 25, "AdvCircuit": 50},
		"type": "technology",
		"parent": "capital_ship_engineering"
	},
	# New Zone Unlocks
	"deep_space_nav": {
		"name": "Deep Space Navigation",
		"description": "Unlocks:\n• Sector Beta (Mining Colony)",
		"cost": 100000,
		"cost_items": {"NavData": 25, "Ti": 150, "Res3": 10},
		"type": "technology",
		"parent": "warp_drive"
	},
	"radiation_shielding": {
		"name": "Radiation Shielding Theory",
		"description": "Unlocks:\n• Sector Gamma (Radioactive)",
		"cost": 250000,
		"cost_items": {"Co": 50, "Al": 100, "Circuit": 30},
		"type": "technology",
		"parent": "deep_space_nav"
	},
	"exotic_matter_analysis": {
		"name": "Exotic Matter Analysis",
		"description": "Unlocks:\n• Sector Delta (Crystalline)",
		"cost": 1000000,
		"cost_items": {"Pt": 20, "ExoticMatter": 10, "QuantumCore": 3},
		"type": "technology",
		"parent": "radiation_shielding"
	},
	# Mid-Game Technology
	"metallurgy_advanced": {
		"name": "Advanced Metallurgy",
		"description": "Unlocks:\n• Stainless Steel Alloy",
		"cost": 5000,
		"cost_items": {"Cr": 20, "Ni": 20},
		"type": "technology",
		"parent": "smelting"
	},
	"advanced_batteries": {
		"name": "Advanced Battery Technology",
		"description": "Unlocks:\n• Li-Co Battery\n• Mg-Ion Battery",
		"cost": 8000,
		"cost_items": {"Co": 30, "Li": 50, "Circuit": 15},
		"type": "technology",
		"parent": "adv_materials"
	},
	"superalloy_engineering": {
		"name": "Superalloy Engineering",
		"description": "Unlocks:\n• Cobalt Superalloy",
		"cost": 100000,
		"cost_items": {"Co": 100, "Ni": 100, "Cr": 50, "Ti": 100},
		"type": "technology",
		"parent": "metallurgy_advanced"
	},
	# Late-Game Rare Metal Technologies
	"precious_metal_refining": {
		"name": "Precious Metal Refining",
		"description": "Unlocks:\n• Platinum Extraction\n• Palladium Refining\n• Precious Metal Dredge (Auto)",
		"cost": 1500,
		"cost_items": {"Ti": 200, "Res2": 25},
		"type": "technology",
		"parent": "deep_space_nav"
	},
	"industrial_catalysis": {
		"name": "Industrial Catalysis",
		"description": "Bonus:\n• +25% All Production Speed",
		"cost": 1000000,
		"cost_items": {"Pt": 200, "Si": 200, "AdvCircuit": 20},
		"type": "technology",
		"parent": "precious_metal_refining"
	},
	"fuel_cell_tech": {
		"name": "Fuel Cell Technology",
		"description": "Unlocks:\n• Hydrogen Fuel Cell",
		"cost": 250000,
		"cost_items": {"Pd": 30, "H": 500, "Circuit": 30},
		"type": "technology",
		"parent": "precious_metal_refining"
	},
	"iridium_metallurgy": {
		"name": "Iridium Metallurgy",
		"description": "Unlocks:\n• Iridium Mining\n• Iridium Armor",
		"cost": 40000,
		"cost_items": {"Pt": 50, "Res3": 10},
		"type": "technology",
		"parent": "superalloy_engineering"
	},
	"exotic_metallurgy": {
		"name": "Exotic Metallurgy",
		"description": "Unlocks:\n• Osmium Harvesting\n• Osmium Armor",
		"cost": 2000000,
		"cost_items": {"Ir": 100, "Res3": 50},
		"type": "technology",
		"parent": "iridium_metallurgy"
	},
	# --- NEW LATE-GAME TECH (Expansion) ---
	"colony_automation": {
		"name": "Colony AI Integration",
		"description": "Unlocks:\n• Colonial Auto-Extractor (Grants +5 Base Gathering Yield)",
		"cost": 50000,
		"cost_items": {"ColonyDataCore": 1, "ColonySalvage": 100, "AdvCircuit": 50},
		"type": "technology",
		"parent": "deep_space_nav"
	},
	"gamma_optics": {
		"name": "High-Energy Gamma Optics",
		"description": "Unlocks:\n• Gamma Pulse Battery (Ship Module)\n• Advanced Laser Tech",
		"cost": 75000,
		"cost_items": {"RadIsotope": 50, "Pt": 100},
		"type": "technology",
		"parent": "radiation_shielding"
	},
	"void_physics": {
		"name": "Extreme Void Physics",
		"description": "Unlocks:\n• Void Phase Engine (Ship Module)\n• Void Shielding",
		"cost": 5000000,
		"cost_items": {"VoidCrystal": 20, "QuantumCore": 10, "AntimatterParticle": 5},
		"type": "technology",
		"parent": "exotic_matter_analysis"
	},
	# ENDGAME - Sector Epsilon unlock
	"void_navigation": {
		"name": "Void Navigation",
		"description": "Unlocks:\n• Sector Epsilon - The Void\n• Void Rift Anchor (Auto)\n• Chrono-Siphon (Auto)\n\nRequires Quarantine Clearance from Quarantine Warden.",
		"cost": 50000000,
		"cost_items": {"QuantumCore": 30, "VoidCrystal": 50, "ExoticMatter": 20, "AncientTech": 5, "QuarantineClearance": 1},  # v58.0: Added clearance req
		"type": "technology",
		"parent": "void_physics"
	},
	# ENDGAME SINKS - Iteration 7
	"void_weaponry_1": {
		"name": "Void Weaponry Optimization",
		"description": "Bonus:\n• +20% Total Ship Damage",
		"cost": 100000000,
		"cost_items": {"VoidEssence": 50, "ChronoCore": 20, "PrimordialShard": 5},
		"type": "technology",
		"parent": "void_navigation"
	},
	"void_shielding_1": {
		"name": "Void Shielding Optimization",
		"description": "Bonus:\n• +20% Total Ship Shields",
		"cost": 100000000,
		"cost_items": {"OmegaPlating": 50, "VoidEssence": 20, "PrimordialShard": 5},
		"type": "technology",
		"parent": "void_navigation"
	},
	"perfect_automation": {
		"name": "Omni-Fabrication",
		"description": "Bonus:\n• +30% Processing & Research Speed (Global)",
		"cost": 10000000,
		"cost_items": {"AICore": 5, "AncientTech": 5, "AdvCircuit": 200},
		"type": "technology",
		"parent": "colony_automation"
	},
	# --- EFFICIENCY & STAT EXPANSION (Phase 7) ---
	"salvage_heuristics": {
		"name": "Salvage Heuristics",
		"description": "Bonus:\n• +2 rolls in Scrap Recycling",
		"cost": 1000,
		"cost_items": {"Res1": 10},
		"type": "technology",
		"parent": "smelting"
	},
	"scavenger_protocol": {
		"name": "Scavenger Protocol",
		"description": "Bonus:\n• +15% DroneCore drop chance",
		"cost": 2500,
		"cost_items": {"Res2": 5},
		"type": "technology",
		"parent": "salvage_heuristics"
	},
	"combat_heuristics": {
		"name": "Combat Heuristics",
		"description": "Bonus:\n• +20% Combat XP gain",
		"cost": 1500,
		"cost_items": {"Res1": 10},
		"type": "technology",
		"parent": "industrial_logistics"
	},
	"shield_harmonics": {
		"name": "Shield Harmonics",
		"description": "Bonus:\n• +20% Shield Regeneration speed",
		"cost": 2000,
		"cost_items": {"Res1": 10},
		"type": "technology",
		"parent": "energy_shields"
	},
	"hull_hardening": {
		"name": "Carbon Hull Lattice",
		"description": "Bonus:\n• +15% Ship Max HP",
		"cost": 1200,
		"cost_items": {"Res1": 5},
		"type": "technology",
		"parent": "combustion"
	},
	"core_overclocking": {
		"name": "Reactor Overclocking",
		"description": "Bonus:\n• +10% Combat Attack Speed",
		"cost": 4000,
		"cost_items": {"Res2": 10},
		"type": "technology",
		"parent": "power_systems"
	},
	"deep_core_optics": {
		"name": "Deep Core Optics",
		"description": "Bonus:\n• +1 Base Yield for all Gathering",
		"cost": 800,
		"cost_items": {"Res1": 5},
		"type": "technology",
		"parent": "laser_cutters"
	},
	"nano_fabrication": {
		"name": "Nano-Fabrication",
		"description": "Bonus:\n• -15% Processing duration",
		"cost": 5000,
		"cost_items": {"Res2": 10},
		"type": "technology",
		"parent": "automation"
	},
	"data_clustering": {
		"name": "Data Clustering",
		"description": "Bonus:\n• -20% Research action duration",
		"cost": 2000,
		"cost_items": {"Res1": 15},
		"type": "technology",
		"parent": "industrial_logistics"
	},
	"industrial_automation": {
		"name": "Industrial Automation",
		"description": "Advanced robotics for mass production.\nUnlocks:\n• Electronics Assembler",
		"cost": 15000,
		"cost_items": {"Circuit": 50, "Steel": 200},
		"type": "technology",
		"parent": "automated_smelting"
	},
	"molecular_recycling": {
		"name": "Molecular Recycling",
		"description": "Unlocks:\n• Matter De-constructor",
		"cost": 50000,
		"cost_items": {"Res2": 50, "AdvCircuit": 25},
		"type": "technology",
		"parent": "industrial_automation"
	},
	"cryogenic_storage": {
		"name": "Cryogenic Storage",
		"description": "Unlocks:\n• Cryo-Storage Array",
		"cost": 30000,
		"cost_items": {"Ti": 100, "Si": 200},
		"type": "technology",
		"parent": "cryogenic_systems"
	}
}

var repeatable_tech_db = {
	"production_focus": {
		"name": "Recursive Optimization (Industry)",
		"description": "Infinite scaling: +5% Global Processing Speed per level.",
		"base_cost": 100000,
		"base_items": {"VoidArtifact": 5, "AdvCircuit": 50},
		"bonus_type": "processing_speed",
		"bonus_value": 0.05
	},
	"combat_focus": {
		"name": "Recursive Calibration (Combat)",
		"description": "Infinite scaling: +5% Total Ship Damage per level.",
		"base_cost": 100000,
		"base_items": {"VoidArtifact": 5, "QuantumCore": 5},
		"bonus_type": "combat_damage",
		"bonus_value": 0.05
	},
	"gathering_focus": {
		"name": "Recursive Logistics (Gathering)",
		"description": "Infinite scaling: +5% Global Gathering Yield per level.",
		"base_cost": 100000,
		"base_items": {"VoidArtifact": 5, "DroneCore": 50},
		"bonus_type": "gathering_yield_mult",
		"bonus_value": 0.05
	}
}


func _init():
	super._init("Astrophysics")

func can_unlock(tech_id: String) -> bool:
	if not tech_id in tech_tree: return false
	if tech_id in unlocked_techs: return false
	
	var node = tech_tree[tech_id]
	var cost = int(node.get("cost", 0) * COST_MULTIPLIER)  # v56.0
	var parent = node.get("parent")
	
	if GameState.resources.get_currency("credits") < cost: return false
	
	if "cost_items" in node:
		for item in node["cost_items"]:
			var qty = int(node["cost_items"][item] * MATERIAL_MULTIPLIER)  # v56.1
			if GameState.resources.get_element_amount(item) < qty: return false
	
	if parent and not parent in unlocked_techs: return false
	
	return true

func unlock_tech(tech_id: String) -> bool:
	if can_unlock(tech_id):
		var node = tech_tree[tech_id]
		
		# Pay
		if node.get("cost", 0) > 0:
			var scaled_cost = int(node["cost"] * COST_MULTIPLIER)  # v56.0
			GameState.resources.remove_currency("credits", scaled_cost)
		
		if "cost_items" in node:
			for item in node["cost_items"]:
				var scaled_qty = int(node["cost_items"][item] * MATERIAL_MULTIPLIER)  # v56.1
				GameState.resources.remove_element(item, scaled_qty)
				
		unlocked_techs.append(tech_id)
		tech_unlocked.emit(tech_id)
		print("Unlocked tech: " + node["name"])
		return true
	return false

func is_tech_unlocked(tech_id):
	if tech_id == null: return true
	return tech_id in unlocked_techs

func get_repeatable_level(tech_id: String) -> int:
	return repeatable_techs.get(tech_id, 0)

func get_repeatable_cost(tech_id: String) -> Dictionary:
	if not tech_id in repeatable_tech_db: return {}
	var data = repeatable_tech_db[tech_id]
	var lvl = get_repeatable_level(tech_id)
	
	var cost_cr = data["base_cost"] * pow(1.5, lvl) * COST_MULTIPLIER  # v56.0
	var costs = {"credits": int(cost_cr)}
	for res in data["base_items"]:
		costs[res] = int(data["base_items"][res] * pow(1.2, lvl))
	return costs

func can_unlock_repeatable(tech_id: String) -> bool:
	if not tech_id in repeatable_tech_db: return false
	var costs = get_repeatable_cost(tech_id)
	
	if GameState.resources.get_currency("credits") < costs["credits"]: return false
	for res in costs:
		if res == "credits": continue
		if GameState.resources.get_element_amount(res) < costs[res]: return false
	return true

func unlock_repeatable_tech(tech_id: String) -> bool:
	if can_unlock_repeatable(tech_id):
		var costs = get_repeatable_cost(tech_id)
		for res in costs:
			if res == "credits":
				GameState.resources.remove_currency("credits", costs[res])
			else:
				GameState.resources.remove_element(res, costs[res])
		
		repeatable_techs[tech_id] = get_repeatable_level(tech_id) + 1
		activity_occurred.emit()
		return true
	return false

func get_efficiency_bonus(bonus_type: String) -> float:
	match bonus_type:
		"scrap_rolls":
			return 2.0 if "salvage_heuristics" in unlocked_techs else 0.0
		"drone_core_chance":
			return 0.15 if "scavenger_protocol" in unlocked_techs else 0.0
		"combat_xp":
			return 0.20 if "combat_heuristics" in unlocked_techs else 0.0
		"shield_regen":
			return 0.20 if "shield_harmonics" in unlocked_techs else 0.0
		"max_hp_mult":
			return 0.15 if "hull_hardening" in unlocked_techs else 0.0
		"attack_speed":
			return 0.10 if "core_overclocking" in unlocked_techs else 0.0
		"gathering_yield":
			var yield_bonus = 0.0
			if "deep_core_optics" in unlocked_techs: yield_bonus += 1.0
			if "colony_automation" in unlocked_techs: yield_bonus += 5.0 # Buffed from 2.0
			return yield_bonus
		"processing_speed":
			var p_speed = 0.0
			if "nano_fabrication" in unlocked_techs: p_speed += 0.15
			if "perfect_automation" in unlocked_techs: p_speed += 0.30
			return p_speed
		"research_speed":
			var r_speed = 0.0
			if "data_clustering" in unlocked_techs: r_speed += 0.20
			if "perfect_automation" in unlocked_techs: r_speed += 0.30
			return r_speed
		"fleet_slots":
			var slots = 1
			if "fleet_logistics_1" in unlocked_techs: slots += 1
			if "fleet_logistics_2" in unlocked_techs: slots += 1
			return float(slots)
		"fleet_speed":
			return 0.25 if "automated_expeditions" in unlocked_techs else 0.0
	# Audit v8.0 P1-25: Hub Node Passive Bonuses
	if bonus_type == "applied_physics" and is_tech_unlocked("applied_physics"):
		return 0.10 # +10% Energy Capacity
	if bonus_type == "materials_science" and is_tech_unlocked("materials_science"):
		return 0.10 # +10% Max Hull HP
	if bonus_type == "industrial_logistics" and is_tech_unlocked("industrial_logistics"):
		return 0.10 # +10% Global Production Speed
		
	# Audit v64.0 Fix: Dead Techs Wired Up
	if bonus_type == "industrial_catalysis" and is_tech_unlocked("industrial_catalysis"):
		return 0.15 # +15% Global Production Speed
	if bonus_type == "xeno_engineering" and is_tech_unlocked("xeno_engineering"):
		return 0.25 # +25% Rare Loot Chance (Used by Combat/Gathering)
		
	# Audit v10.0: Infinite Sinks
	var repeatable_bonus = 0.0
	for rid in repeatable_techs:
		var lvl = int(repeatable_techs[rid])
		var r_data = repeatable_tech_db.get(rid)
		if r_data and r_data["bonus_type"] == bonus_type:
			repeatable_bonus += lvl * r_data["bonus_value"]
			
	return repeatable_bonus

func get_research_speed_multiplier() -> float:
	# Audit v8.0 P2-20: +1% Research Speed per Level
	return 1.0 + (get_level() * 0.01)

func get_affordable_researches_count() -> int:
	"""Phase 2.1: Checks if tech is available AND player has specific items/credits"""
	var count = 0
	for tid in tech_tree:
		if not is_tech_unlocked(tid) and can_unlock(tid):
			# can_unlock already checks credits and items
			count += 1
	return count

func reset(decay_factor: float = 1.0) -> void:
	super.reset(decay_factor)
	unlocked_techs = []
	stop_action()

# Audit v2.0 P1-6: Soft reset preserves unlocked techs, only clears in-progress
func soft_reset():
	# Keep unlocked_techs intact!
	stop_action()
	# XP is also preserved through soft reset

func get_save_data_manager() -> Dictionary:
	var data = get_save_data()
	data["unlocked_techs"] = unlocked_techs
	data["repeatable_techs"] = repeatable_techs
	return data

func load_save_data_manager(data: Dictionary):
	load_save_data(data)
	unlocked_techs = data.get("unlocked_techs", [])
	repeatable_techs = data.get("repeatable_techs", {})

# Action Logic (Scanning)

func start_scan():
	start_action("scan_sector")

func start_action(action_id: String):
	is_active = true
	current_action = action_id
	action_progress = 0.0

func stop_action():
	is_active = false
	current_action = ""
	action_progress = 0.0

func get_data_yield_multiplier() -> float:
	# astrophysics level bonus: +10% per level
	return 1.0 + (get_level() * 0.1)

func complete_action():
	var base_yield = 15
	if "eff_scanning_1" in unlocked_techs:
		base_yield = int(base_yield * 1.5)
	
	var scaled_yield = int(base_yield * get_data_yield_multiplier())
	GameState.resources.add_currency("data", scaled_yield)
	add_xp(25)

func process_tick(delta: float):
	if not is_active or current_action == "": return
	
	# Audit v8.0: Combine hub bonuses, research unlocks, and Skill Level
	var speed_mult = (1.0 + get_efficiency_bonus("research_speed")) * get_research_speed_multiplier()
	action_progress += delta * speed_mult
	
	if action_progress >= action_duration:
		complete_action()
		action_progress = 0.0 # Loop

func calculate_offline(delta: float):
	if not is_active or current_action == "": return null
	
	var speed_mult = (1.0 + get_efficiency_bonus("research_speed")) * get_research_speed_multiplier()
	var effective_duration = action_duration / speed_mult
	
	var actions = int(delta / effective_duration)
	if actions <= 0: return null
	
	var base_yield = 15
	if "eff_scanning_1" in unlocked_techs: 
		base_yield = int(base_yield * 1.5)
	
	# v61.0 Fix: Remove duplicate speed_mult - actions count already factors in speed via effective_duration
	var total_data = int(base_yield * actions * get_data_yield_multiplier())
	var total_xp = int(25 * actions)
	
	GameState.resources.add_currency("data", total_data)
	add_xp(total_xp)
	
	return "Research (Scanning):\nActions: %d\nData Gained: %d\nXP Gained: %d" % [actions, total_data, total_xp]
