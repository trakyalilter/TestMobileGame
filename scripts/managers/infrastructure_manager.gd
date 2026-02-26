extends Skill

signal activity_occurred
signal building_constructed(building_id)

var buildings: Dictionary = {}
var building_throttles: Dictionary = {} # {building_id: 0.0 to 1.0}
var generation: float = 0.0
var consumption: float = 0.0
var net_energy: float = 0.0
var energy_efficiency: float = 1.0 # Current grid stability (0.0 to 1.0)
var grid_warning_sent: bool = false
var events: Array = []


var building_db: Dictionary = {
	"solar_panel": {
		"name": "Solar Array",
		"description": "+15.0 kW",
		"cost": {"credits": 125, "Si": 5}, 
		"energy_gen": 15.0, 
		"energy_cons": 0.0,
		"category": "power"
	},
	"coal_burner": {
		"name": "Carbon Generator",
		"description": "+60.0 kW (-1 C)",
		"cost": {"credits": 375, "Fe": 10},
		"energy_gen": 60.0, 
		"energy_cons": 0.0,
		"input": {"C": 1},
		"interval": 10.0,
		"research_req": "combustion",
		"category": "power"
	},
	"geothermal_well": {
		"name": "Geothermal Well",
		"description": "+250.0 kW (Stable)",
		"cost": {"credits": 400000, "Ti": 100, "Hydraulics": 50},
		"energy_gen": 250.0,
		"energy_cons": 0.0,
		"research_req": "fluid_dynamics",
		"category": "power"
	},
	"biomass_plant": {
		"name": "Biomass Plant",
		"description": "+1000.0 kW (-5 Wood)",
		"cost": {"credits": 150000, "Steel": 200, "Circuit": 20},
		"energy_gen": 1000.0,
		"energy_cons": 0.0,
		"input": {"Wood": 5},
		"interval": 10.0,
		"research_req": "combustion",
		"category": "power"
	},
	"palladium_generator": {
		"name": "Palladium Fuel Cell Generator",
		"description": "+15000.0 kW",
		"cost": {"credits": 250000, "PdFuelCell": 20, "Circuit": 40},
		"energy_gen": 15000.0,
		"energy_cons": 0.0,
		"input": {"H": 1},
		"interval": 10.0,
		"research_req": "fuel_cell_tech",
		"category": "power"
	},
	"hydrogen_reactor": {
		"name": "Hydrogen Reactor",
		"description": "+4000.0 kW",
		"cost": {"credits": 50000, "Steel": 200, "Circuit": 50, "NavData": 5},
		"energy_gen": 4000.0,
		"energy_cons": 0.0,
		"input": {"H": 10},
		"interval": 10.0,
		"research_req": "energy_metrics",
		"category": "power"
	},
	"adv_fuel_cell_array": {
		"name": "Advanced Fuel Cell Array",
		"description": "+60000.0 kW (-2 Pd-Cells)",
		"cost": {"credits": 800000, "Ti": 150, "AdvCircuit": 80},
		"energy_gen": 60000.0,
		"energy_cons": 0.0,
		"input": {"PdFuelCell": 2},
		"interval": 10.0,
		"research_req": "fuel_cell_tech",
		"category": "power"
	},
	"fission_reactor": {
		"name": "Fission Reactor",
		"description": "+250000.0 kW (-5 Uranium)",
		"cost": {"credits": 1200000, "Ti": 200, "AdvCircuit": 50},
		"energy_gen": 250000.0,
		"energy_cons": 0.0,
		"input": {"U": 5},
		"interval": 10.0,
		"research_req": "radiation_shielding",
		"category": "power"
	},
	"orbital_solar_relay": {
		"name": "Orbital Solar Relay",
		"description": "+1000000.0 kW (Constant)",
		"cost": {"credits": 5000000, "W": 200, "Chip": 150},
		"energy_gen": 1000000.0,
		"energy_cons": 0.0,
		"research_req": "energy_metrics",
		"category": "power"
	},
	"fusion_reactor": {
		"name": "Fusion Core",
		"description": "+4000000.0 kW",
		"cost": {"credits": 25000000, "Superalloy": 200, "AdvCircuit": 100, "VoidEssence": 20},
		"energy_gen": 4000000.0,
		"energy_cons": 0.0,
		"research_req": "quantum_dynamics",
		"category": "power"
	},
	"antimatter_generator": {
		"name": "Antimatter Generator",
		"description": "+16000000.0 kW (-1 AM-Cell)",
		"cost": {"credits": 25000000, "VoidArtifact": 50, "QuantumCore": 10},
		"energy_gen": 16000000.0,
		"energy_cons": 0.0,
		"input": {"AntimatterFuel": 1},
		"interval": 20.0,
		"research_req": "quantum_dynamics",
		"category": "power"
	},
	# ========== CATEGORY: EXTRACTION ==========
	"auto_excavator": {
		"name": "Auto-Excavator (XL)",
		"description": "+10 Dirt",
		"cost": {"credits": 250000, "Si": 5000, "Fe": 2000},
		"energy_gen": 0.0,
		"energy_cons": 15.0,
		"yield": {"Dirt": 10},
		"interval": 5.0,
		"category": "extraction"
	},
	"industrial_pump": {
		"name": "Industrial Pump",
		"description": "+10 Water",
		"cost": {"credits": 250000, "Si": 5000, "Fe": 2000}, 
		"energy_gen": 0.0,
		"energy_cons": 25.0,
		"yield": {"Water": 10},
		"interval": 5.0,
		"category": "extraction"
	},
	"bio_harvester": {
		"name": "Bio-Harvester",
		"description": "Automated wood collection.",
		"cost": {"credits": 250000, "Steel": 500, "Circuit": 50},
		"energy_gen": 0.0,
		"energy_cons": 40.0,
		"yield": {"Wood": 10},
		"interval": 5.0,
		"research_req": "laser_cutters",
		"category": "extraction"
	},
	"lithium_extractor": {
		"name": "Lithium Extractor",
		"description": "Basic spodumene extraction.",
		"cost": {"credits": 400000, "Steel": 750, "Circuit": 100},
		"energy_gen": 0.0,
		"energy_cons": 80.0,
		"yield": {"Spodumene": 0.5},
		"interval": 5.0,
		"research_req": "basic_electronics",
		"category": "extraction"
	},
	"brine_extractor": {
		"name": "Lithium Brine Well",
		"description": "+1.7 Spodumene (Efficient)",
		"cost": {"credits": 1000000, "Ti": 500,"Superalloy":100},
		"energy_gen": 0.0,
		"energy_cons": 120.0,
		"yield": {"Spodumene": 1.7},
		"interval": 5.0,
		"research_req": "basic_engineering",
		"category": "extraction"
	},
	"copper_mine": {
		"name": "Copper Mine",
		"description": "Basic malachite extraction.",
		"cost": {"credits": 350000, "Steel": 600, "Circuit": 80},
		"energy_gen": 0.0,
		"energy_cons": 80.0,
		"yield": {"Malachite": 0.4},
		"interval": 5.0,
		"research_req": "basic_electronics",
		"category": "extraction"
	},
	"deep_crust_drill": {
		"name": "Deep-Crust Drill",
		"description": "+1.7 Malachite (Heavy)",
		"cost": {"credits": 1000000, "Ti": 500,"Superalloy":100},
		"energy_gen": 0.0,
		"energy_cons": 120.0,
		"yield": {"Malachite": 1.7},
		"interval": 5.0,
		"research_req": "basic_engineering",
		"category": "extraction"
	},
	"tin_mine": {
		"name": "Tin Mine",
		"description": "Cassiterite extraction.",
		"cost": {"credits": 500000, "Steel": 800, "Ti": 50, "Circuit": 100},
		"energy_gen": 0.0,
		"energy_cons": 80.0,
		"yield": {"Cassiterite": 0.4},
		"interval": 5.0,
		"research_req": "basic_electronics",
		"category": "extraction"
	},
	"quartz_mine": {
		"name": "Quartz Mine",
		"description": "Basic silica excavation.",
		"cost": {"credits": 600000, "Steel": 1000, "Ti": 100, "Circuit": 150},
		"energy_gen": 0.0,
		"energy_cons": 80.0,
		"yield": {"Quartz": 0.3},
		"interval": 5.0,
		"research_req": "basic_electronics",
		"category": "extraction"
	},
	"quartz_excavator": {
		"name": "Quartz Resonator",
		"description": "+2.5 Quartz (High Speed)",
		"cost": {"credits": 1000000, "Ti": 500,"Superalloy":100},
		"energy_gen": 0.0,
		"energy_cons": 4500.0,
		"yield": {"Quartz": 2.5},
		"interval": 5.0,
		"research_req": "adv_materials",
		"category": "extraction"
	},
	"uranium_centrifuge": {
		"name": "Uranium Isotope Centrifuge",
		"description": "+1.0 Uranium",
		"cost": {"credits": 50000, "Steel": 500, "Si": 250, "AdvCircuit": 5},
		"energy_gen": 0.0,
		"energy_cons": 750.0,
		"yield": {"U": 1.0},
		"interval": 5.0,
		"research_req": "energy_metrics",
		"category": "extraction"
	},
	"tungsten_drill": {
		"name": "Heavy Tungsten Drill",
		"description": "+2.0 Tungsten",
		"cost": {"credits": 45000, "Ti": 300, "Steel": 500, "Hydraulics": 15},
		"energy_gen": 0.0,
		"energy_cons": 1500.0,
		"yield": {"W": 2.0},
		"interval": 5.0,
		"research_req": "smelting",
		"category": "extraction"
	},
	"zinc_mine": {
		"name": "Zinc Mine",
		"description": "Zinc ore extraction.",
		"cost": {"credits": 750000, "Steel": 1500, "AdvCircuit": 100},
		"energy_gen": 0.0,
		"energy_cons": 160.0,
		"yield": {"ZincOre": 0.4},
		"interval": 5.0,
		"research_req": "metallurgy_advanced",
		"category": "extraction"
	},
	"bauxite_mine": {
		"name": "Bauxite Mine",
		"description": "Basic aluminum ore extraction.",
		"cost": {"credits": 800000, "Steel": 1500, "AdvCircuit": 120},
		"energy_gen": 0.0,
		"energy_cons": 160.0,
		"yield": {"Bauxite": 1.0},
		"interval": 5.0,
		"research_req": "metallurgy_advanced",
		"category": "extraction"
	},
	"bauxite_miner": {
		"name": "Bauxite Strip Miner",
		"description": "+2.5 Bauxite (Industrial)",
		"cost": {"credits": 1000000, "Ti": 500,"Superalloy":100},
		"energy_gen": 0.0,
		"energy_cons": 4500.0,
		"yield": {"Bauxite": 2.5},
		"interval": 5.0,
		"research_req": "adv_materials",
		"category": "extraction"
	},
	"dolomite_quarry": {
		"name": "Dolomite Quarry",
		"description": "Magnesium source extraction.",
		"cost": {"credits": 700000, "Steel": 1200, "AdvCircuit": 80},
		"energy_gen": 0.0,
		"energy_cons": 160.0,
		"yield": {"Dolomite": 0.8},
		"interval": 5.0,
		"research_req": "metallurgy_advanced",
		"category": "extraction"
	},
	"manganese_dredge": {
		"name": "Manganese Dredge",
		"description": "+1.3 Manganese (Seafloor Mining)",
		"cost": {"credits": 850000, "Ti": 400, "AdvCircuit": 100},
		"energy_gen": 0.0,
		"energy_cons": 240.0,
		"yield": {"Mn": 1.3},
		"interval": 5.0,
		"research_req": "metallurgy_advanced",
		"category": "extraction"
	},
	"nickel_mine": {
		"name": "Nickel Mine",
		"description": "Pentlandite extraction.",
		"cost": {"credits": 900000, "Steel": 2000, "Superalloy": 50, "AdvCircuit": 150},
		"energy_gen": 0.0,
		"energy_cons": 1200.0,
		"yield": {"Pentlandite": 0.3},
		"interval": 5.0,
		"research_req": "superalloy_engineering",
		"category": "extraction"
	},
	"chromite_excavator": {
		"name": "Chromite Excavator",
		"description": "Chromium ore extraction.",
		"cost": {"credits": 1000000, "Steel": 2500, "Superalloy": 100, "AdvCircuit": 200},
		"energy_gen": 0.0,
		"energy_cons": 1800.0,
		"yield": {"Chromite": 0.2},
		"interval": 5.0,
		"research_req": "superalloy_engineering",
		"category": "extraction"
	},
	"platinum_drill": {
		"name": "Platinum Drill",
		"description": "Precious metal extraction.",
		"cost": {"credits": 2000000, "Steel": 3000, "Ti": 300, "Chip": 150},
		"energy_gen": 0.0,
		"energy_cons": 12000.0,
		"yield": {"PtOre": 1.0},
		"interval": 10.0,
		"research_req": "precious_metal_refining",
		"category": "extraction"
	},
	"germanite_excavator": {
		"name": "Germanite Excavator",
		"description": "Sulfide ore excavation.",
		"cost": {"credits": 1200000, "Steel": 2000, "Ti": 150, "Chip": 100},
		"energy_gen": 0.0,
		"energy_cons": 120.0,
		"yield": {"Germanit": 0.4},
		"interval": 5.0,
		"research_req": "basic_electronics",
		"category": "extraction"
	},
	"iridium_drill": {
		"name": "Iridium Drill",
		"description": "Deep-void crystal extraction.",
		"cost": {"credits": 3000000, "Steel": 4000, "Ti": 500, "Chip": 200},
		"energy_gen": 0.0,
		"energy_cons": 37500.0,
		"yield": {"Ir": 0.4},
		"interval": 10.0,
		"research_req": "iridium_metallurgy",
		"category": "extraction"
	},
	"osmium_condenser": {
		"name": "Osmium Condenser",
		"description": "Heavy metal recovery.",
		"cost": {"credits": 5000000, "Steel": 5000, "Ti": 800, "W": 100, "Chip": 300},
		"energy_gen": 0.0,
		"energy_cons": 37500.0,
		"yield": {"Os": 0.3},
		"interval": 10.0,
		"research_req": "exotic_metallurgy",
		"category": "extraction"
	},
	"orbital_siphon": {
		"name": "Orbital Gas Siphon",
		"description": "+4 H, +2 He, +2 N",
		"cost": {"credits": 1000000, "Ti": 500,"Superalloy":100},
		"energy_gen": 0.0,
		"energy_cons": 750.0,
		"yield": {"H": 4, "He": 2, "N": 2},
		"interval": 10.0,
		"research_req": "energy_metrics",
		"category": "extraction"
	},
	"precious_dredge": {
		"name": "Precious Metal Dredge",
		"description": "+2 Pt, +1 Ir",
		"cost": {"credits": 1000000, "Ti": 500,"QuantumCore": 10,"Superalloy":100},
		"energy_gen": 0.0,
		"energy_cons": 12000.0,
		"yield": {"PtOre": 2, "Ir": 1},
		"interval": 10.0,
		"research_req": "precious_metal_refining",
		"category": "extraction"
	},
	"void_anchor": {
		"name": "Void Rift Anchor",
		"description": "+1.3 Void Essence",
		"cost": {"credits": 5000000, "Superalloy": 500, "QuantumCore": 10},
		"energy_gen": 0.0,
		"energy_cons": 85000.0,
		"yield": {"VoidEssence": 1.3},
		"interval": 10.0,
		"research_req": "void_navigation",
		"category": "extraction"
	},
	"chrono_siphon": {
		"name": "Chrono-Siphon",
		"description": "+0.3 Chrono Core",
		"cost": {"credits": 25000000, "Superalloy": 1000, "AntimatterFuel": 10},
		"energy_gen": 0.0,
		"energy_cons": 127500.0,
		"yield": {"ChronoCore": 0.3},
		"interval": 10.0,
		"research_req": "void_navigation",
		"category": "extraction"
	},
	"industrial_centrifuge": {
		"name": "Industrial Centrifuge",
		"description": "+5 Fe, +1.7 Si (-8.3 Dirt, -8.3 Water)",
		"cost": {"credits": 500000, "Steel": 1000, "Si": 2000, "DroneCore": 100},
		"energy_gen": 0.0,
		"energy_cons": 180.0,
		"yield": {"Fe": 5, "Si": 1.7},
		"input": {"Dirt": 8.3, "Water": 8.3},
		"interval": 5.0,
		"research_req": "automated_logistics",
		"category": "industry"
	},

	# ========== CATEGORY: INDUSTRY ==========
	"industrial_kiln": {
		"name": "Industrial Kiln",
		"description": "Automated wood carbonization.",
		"cost": {"credits": 150000, "Steel": 300, "Hydraulics": 20},
		"energy_gen": 0.0,
		"energy_cons": 35.0,
		"yield": {"C": 3.8},
		"input": {"Wood": 1.3},
		"interval": 5.0,
		"research_req": "combustion",
		"category": "industry"
	},
	"auto_smelter": {
		"name": "Automated Smelter",
		"description": "+2.5 Steel",
		"cost": {"credits": 6250, "Ti": 20, "Circuit": 5},
		"energy_gen": 0.0,
		"energy_cons": 120.0,
		"yield": {"Steel": 2.5},
		"input": {"Fe": 2.5, "C": 1.3, "O": 2.5},
		"interval": 5.0,
		"research_req": "automated_smelting",
		"category": "industry"
	},
	"copper_smelter": {
		"name": "Copper Smelter",
		"description": "Automated copper smelting.",
		"cost": {"credits": 250000, "Ti": 200, "Circuit": 50},
		"energy_gen": 0.0,
		"energy_cons": 80.0,
		"yield": {"Cu": 1},
		"input": {"Malachite": 2, "C": 1},
		"interval": 5.0,
		"research_req": "basic_electronics",
		"category": "industry"
	},
	"tin_smelter": {
		"name": "Tin Smelter",
		"description": "Automated tin smelting.",
		"cost": {"credits": 400000, "Steel": 400, "Ti": 100, "Hydraulics": 50},
		"energy_gen": 0.0,
		"energy_cons": 80.0,
		"yield": {"Sn": 2},
		"input": {"Cassiterite": 3, "C": 1},
		"interval": 5.0,
		"research_req": "basic_electronics",
		"category": "industry"
	},
	"zinc_smelter": {
		"name": "Zinc Smelter",
		"description": "Automated zinc reduction.",
		"cost": {"credits": 600000, "Steel": 1000, "AdvCircuit": 50},
		"energy_gen": 0.0,
		"energy_cons": 160.0,
		"yield": {"Zn": 2.5},
		"input": {"ZincOre": 3.8, "C": 1.3},
		"interval": 5.0,
		"research_req": "metallurgy_advanced",
		"category": "industry"
	},
	"silicon_furnace": {
		"name": "Silicon Furnace",
		"description": "Automated silicon refining.",
		"cost": {"credits": 500000, "Steel": 500, "Ti": 100, "Hydraulics": 100},
		"energy_gen": 0.0,
		"energy_cons": 80.0,
		"yield": {"Si": 1},
		"input": {"Quartz": 2, "C": 1},
		"interval": 5.0,
		"research_req": "basic_electronics",
		"category": "industry"
	},
	"lithium_refinery": {
		"name": "Lithium Refinery",
		"description": "Automated lithium purification.",
		"cost": {"credits": 450000, "Steel": 500, "Hydraulics": 50},
		"energy_gen": 0.0,
		"energy_cons": 80.0,
		"yield": {"Li": 1},
		"input": {"Spodumene": 2},
		"interval": 5.0,
		"research_req": "basic_electronics",
		"category": "industry"
	},
	"nickel_refinery": {
		"name": "Nickel Refinery",
		"description": "Automated nickel extraction.",
		"cost": {"credits": 800000, "Steel": 1500, "Superalloy": 30, "AdvCircuit": 100},
		"energy_gen": 0.0,
		"energy_cons": 1200.0,
		"yield": {"Ni": 1.7},
		"input": {"Pentlandite": 2.5, "C": 0.8},
		"interval": 5.0,
		"research_req": "superalloy_engineering",
		"category": "industry"
	},
	"chromium_forge": {
		"name": "Chromium Forge",
		"description": "Advanced alloys forge.",
		"cost": {"credits": 900000, "Steel": 2000, "Superalloy": 50, "AdvCircuit": 150},
		"energy_gen": 0.0,
		"energy_cons": 1800.0,
		"yield": {"Cr": 1.3},
		"input": {"Chromite": 1.9, "Al": 0.6},
		"interval": 5.0,
		"research_req": "superalloy_engineering",
		"category": "industry"
	},
	"germanium_smelter": {
		"name": "Germanium Smelter",
		"description": "Automated germanium refining.",
		"cost": {"credits": 1500000, "Steel": 1500, "Ti": 200, "Chip": 100},
		"energy_gen": 0.0,
		"energy_cons": 80.0,
		"yield": {"Germanium": 0.6},
		"input": {"Germanit": 3.1},
		"interval": 5.0,
		"research_req": "basic_electronics",
		"category": "industry"
	},
	"hydro_plant": {
		"name": "Industrial Electrolysis Plant",
		"description": "+5 H, +2.5 O (-2.5 Water)",
		"cost": {"credits": 6250, "Si": 50, "Circuit": 10},
		"energy_gen": 0.0,
		"energy_cons": 100.0,
		"yield": {"H": 5, "O": 2.5},
		"input": {"Water": 2.5},
		"interval": 5.0,
		"research_req": "industrial_electrolysis",
		"category": "industry"
	},
	"auto_press": {
		"name": "Automated Carbon Press",
		"description": "+0.8 Graphite (-4.2 Carbon)",
		"cost": {"credits": 7500, "Fe": 100, "Hydraulics": 5},
		"energy_gen": 0.0,
		"energy_cons": 1500.0, # molecular_compression base
		"yield": {"Graphite": 0.8},
		"input": {"C": 4.2},
		"interval": 5.0,
		"research_req": "molecular_compression",
		"category": "industry"
	},
	"composite_loom": {
		"name": "Composite Loom",
		"description": "+0.6 Composite Weave (-6.3 Fiber, -1.3 Resin)",
		"cost": {"credits": 15000, "Steel": 75, "Fiber": 20},
		"energy_gen": 0.0,
		"energy_cons": 3000.0, # adv_materials
		"yield": {"CompositeWeave": 0.6},
		"input": {"Fiber": 6.3, "Resin": 1.3},
		"interval": 5.0,
		"research_req": "adv_materials",
		"category": "industry"
	},
	"electronics_assembler": {
		"name": "Electronics Assembler",
		"description": "+1.3 Circuit (-2.5 Si, -2.5 Cu, -1.3 Resin)",
		"cost": {"credits": 25000, "Ti": 50, "Circuit": 100, "SalvageData": 20},
		"energy_gen": 0.0,
		"energy_cons": 1500.0, # industrial_automation
		"yield": {"Circuit": 1.3},
		"input": {"Si": 2.5, "Cu": 2.5, "Resin": 1.3},
		"interval": 5.0,
		"research_req": "industrial_automation",
		"category": "industry"
	},
	"matter_deconstructor": {
		"name": "Matter De-constructor",
		"description": "+0.5 Circuit, +0.1 Alloy (Copper processing)",
		"cost": {"credits": 250000, "Ti": 1000, "AdvCircuit": 50},
		"energy_gen": 0.0,
		"energy_cons": 3500.0, # molecular_recycling
		"input": {"Cu": 2500},
		"yield": {"Circuit": 0.5, "Superalloy": 0.1},
		"interval": 5.0,
		"research_req": "molecular_recycling",
		"category": "industry"
	},
	"zero_point_cell_synthesizer": {
		"name": "Zero-Point Cell Synthesizer",
		"description": "+0.7 Cell T3",
		"cost": {"credits": 1000000, "QuantumCore": 10, "ExoticMatter": 20},
		"energy_gen": 0.0,
		"energy_cons": 25000.0, # exotic_metallurgy
		"yield": {"CellT3": 0.7},
		"input": {"ExoticMatter": 0.7, "QuantumCore": 0.7},
		"interval": 5.0,
		"research_req": "exotic_metallurgy",
		"category": "industry"
	},
	"void_crystallizer": {
		"name": "Void Crystallizer",
		"description": "+1.0 Void Crystal (-2.5 Essence)",
		"cost": {"credits": 10000000, "Superalloy": 1000, "QuantumCore": 25},
		"energy_gen": 0.0,
		"energy_cons": 85000.0, # void_navigation
		"input": {"VoidEssence": 2.5},
		"yield": {"VoidCrystal": 1},
		"interval": 10.0,
		"research_req": "void_navigation",
		"category": "industry"
	},
	"basic_kinetic_foundry": {
		"name": "Basic Kinetic Foundry",
		"description": "+10 Slug T1 (-5 Fe)",
		"cost": {"credits": 12500, "Fe": 100, "Si": 50},
		"energy_gen": 0.0,
		"energy_cons": 50.0, # kinetics_101
		"yield": {"SlugT1": 10},
		"input": {"Fe": 5},
		"interval": 5.0,
		"research_req": "kinetics_101",
		"category": "industry"
	},
	"basic_cell_factory": {
		"name": "Basic Cell Factory",
		"description": "+10 Cell T1 (-5 Si)",
		"cost": {"credits": 12500, "Si": 100, "Cu": 20},
		"energy_gen": 0.0,
		"energy_cons": 50.0, # power_systems
		"yield": {"CellT1": 10},
		"input": {"Si": 5},
		"interval": 5.0,
		"research_req": "power_systems",
		"category": "industry"
	},
	"advanced_ballistics_plant": {
		"name": "Advanced Ballistics Plant",
		"description": "+3.1 Slug T2 (-3.1 Steel, -1.3 Al)",
		"cost": {"credits": 125000, "Steel": 100, "Al": 50},
		"energy_gen": 0.0,
		"energy_cons": 2500.0, # processing_tungsten
		"yield": {"SlugT2": 3.1},
		"input": {"Steel": 3.1, "Al": 1.3},
		"interval": 5.0,
		"research_req": "processing_tungsten",
		"category": "industry"
	},
	"high_energy_cell_plant": {
		"name": "High-Energy Cell Plant",
		"description": "+3.1 Cell T2 (-1.9 Si, -1.3 Resin)",
		"cost": {"credits": 125000, "Si": 100, "Resin": 50},
		"energy_gen": 0.0,
		"energy_cons": 2500.0, # advanced_batteries
		"yield": {"CellT2": 3.1},
		"input": {"Si": 1.9, "Resin": 1.3},
		"interval": 5.0,
		"research_req": "advanced_batteries",
		"category": "industry"
	},
	"heavy_ordnance_works": {
		"name": "Heavy Ordnance Works",
		"description": "+0.8 Slug T3 (-0.8 U, -2.1 Superalloy)",
		"cost": {"credits": 2500000, "Superalloy": 50, "U": 20},
		"energy_gen": 0.0,
		"energy_cons": 15000.0, # capital_ship_armament (arbitrary high tier proxy)
		"yield": {"SlugT3": 0.8},
		"input": {"U": 0.8, "Superalloy": 2.1},
		"interval": 5.0,
		"research_req": "capital_ship_armament",
		"category": "industry"
	},

	# ========== CATEGORY: LOGISTICS ==========
	"drone_bay": {
		"name": "Drone Recovery Bay",
		"description": "+Scrap (Zone Scavenging)",
		"cost": {"credits": 5000, "Circuit": 10, "Ti": 20},
		"energy_gen": 0.0,
		"energy_cons": 150.0,
		"max": 1,
		"research_req": "automated_logistics",
		"special": "passive_gather",
		"category": "logistics"
	},
	"fabricator": {
		"name": "Molecular Fabricator",
		"description": "-20% Crafting Time",
		"cost": {"credits": 12500, "Circuit": 50, "Fiber": 20, "Ti": 50},
		"energy_gen": 0.0,
		"energy_cons": 1500.0,
		"max": 1,
		"research_req": "molecular_printing",
		"special": "craft_buff",
		"category": "industry"
	},
	"nitrogen_tank": {
		"name": "Cryo-Storage Array",
		"description": "+10% Nitrogen Yield",
		"cost": {"credits": 12500, "Ti": 100, "Circuit": 25},
		"energy_gen": 0.0,
		"energy_cons": 35.0,
		"yield_bonus": {"N": 0.10},
		"research_req": "cryogenic_storage",
		"category": "logistics"
	},
	"terraforming_processor": {
		"name": "Terraforming Processor",
		"description": "+1 Fertile Soil (+5% Gather Speed)",
		"cost": {"credits": 20000, "Steel": 100, "Circuit": 20},
		"energy_gen": 0.0,
		"energy_cons": 50.0,
		"yield": {"FertileSoil": 1},
		"input": {"Dirt": 25, "Water": 5},
		"interval": 10.0,
		"research_req": "industrial_logistics",
		"category": "logistics"
	},
	"biosphere_dome": {
		"name": "Biosphere Dome",
		"description": "+5% Gather Speed",
		"cost": {"credits": 30000, "Steel": 150, "Si": 50, "FertileSoil": 10},
		"energy_gen": 0.0,
		"energy_cons": 50.0,
		"max": 5,
		"research_req": "industrial_logistics",
		"special": "gather_speed_buff",
		"category": "logistics"
	},
	"crew_quarters": {
		"name": "Crew Quarters",
		"description": "+10% XP Gain",
		"cost": {"credits": 25000, "Steel": 100, "Circuit": 20},
		"energy_gen": 0.0,
		"energy_cons": 50.0,
		"input": {"Food": 1},
		"interval": 30.0,
		"max": 3,
		"research_req": "industrial_logistics",
		"special": "xp_buff",
		"category": "logistics"
	},
	"catalyst_chamber": {
		"name": "Platinum Catalyst Chamber",
		"description": "+25% Processing Speed",
		"cost": {"credits": 500000, "PtCatalyst": 5, "AdvCircuit": 30, "Superalloy": 20},
		"energy_gen": 0.0,
		"energy_cons": 1200.0,
		"max": 1,
		"research_req": "industrial_catalysis",
		"special": "global_catalyst",
		"category": "logistics"
	},
	"silver_catalyst_bay": {
		"name": "Silver Catalyst Bay",
		"description": "+15% Processing Speed",
		"cost": {"credits": 100000, "AgCatalyst": 5, "Circuit": 20},
		"energy_gen": 0.0,
		"energy_cons": 1200.0,
		"max": 1,
		"research_req": "industrial_catalysis",
		"special": "global_catalyst",
		"category": "logistics"
	},
	"repair_docks": {
		"name": "Fleet Repair Docks",
		"description": "-10% Repair Cost",
		"cost": {"credits": 100000, "AdvCircuit": 20, "Steel": 100},
		"energy_gen": 0.0,
		"energy_cons": 500.0,
		"max": 10,
		"research_req": "fleet_logistics_1",
		"category": "logistics"
	},
	"repair_gantry": {
		"name": "Automated Repair Gantry",
		"description": "+Passive Ship Repair",
		"cost": {"credits": 250000, "AdvCircuit": 50, "Superalloy": 50},
		"energy_gen": 0.0,
		"energy_cons": 1500.0,
		"max": 5,
		"research_req": "fleet_logistics_2",
		"category": "logistics"
	}
}

var production_timers: Dictionary = {}

func _init():
	super._init("Infrastructure")

func get_building_count(building_id: String) -> int:
	return buildings.get(building_id, 0)

func set_building_throttle(building_id: String, value: float):
	building_throttles[building_id] = clamp(value, 0.0, 1.0)
	activity_occurred.emit() # Refresh UI rates

func get_building_throttle(building_id: String) -> float:
	return building_throttles.get(building_id, 1.0)

func get_xp_multiplier() -> float:
	# Crew Quarters: +10% per building, max 3 (+30%)
	return 1.0 + (get_building_count("crew_quarters") * 0.10)

func get_effective_yield(building_id: String, resource_symbol: String) -> float:
	var data = building_db.get(building_id)
	if not data or not "yield" in data or not resource_symbol in data["yield"]: return 0.0
	
	var base_qty = float(data["yield"][resource_symbol])
	
	# Engineering Level Scaling
	var scaled_buildings = ["auto_smelter", "hydro_plant", "industrial_centrifuge", "munitions_factory"]
	if building_id in scaled_buildings:
		var eng_lvl = GameState.processing_manager.get_level()
		base_qty *= (1.0 + (log(1.0 + eng_lvl) / log(10.0)) * 5.0)
	
	# Industrial Logistics Hub Bonus (Direct Yield buff instead of speed if specified? 
	# No, let's keep it as speed bonus per plan, but standardize the formula here)
	return base_qty

func get_effective_interval(building_id: String) -> float:
	var data = building_db.get(building_id)
	if not data: return 1.0
	var interval = data.get("interval", 1.0)
	
	# Production Speed Bonuses
	var warp_mult = GameState.warp_manager.get_production_multiplier() if GameState.warp_manager else 1.0
	var skill_speed_mult = 1.0 + (get_level() * 0.01)
	var hub_bonus = 0.0
	if GameState.research_manager:
		hub_bonus = GameState.research_manager.get_efficiency_bonus("industrial_logistics")
	
	# Interval decreases as speed increases
	return interval / (warp_mult * skill_speed_mult * (1.0 + hub_bonus))

func get_total_resource_rates() -> Dictionary:
	var rates = {} # {id: net_per_minute}
	
	# Global Yield Bonuses Pass
	var global_yield_bonuses = {} # {resource: total_mult_bonus}
	for other_bid in buildings:
		var other_data = building_db.get(other_bid)
		if other_data and other_data.has("yield_bonus"):
			for res in other_data["yield_bonus"]:
				global_yield_bonuses[res] = global_yield_bonuses.get(res, 0.0) + (other_data["yield_bonus"][res] * buildings[other_bid])

	for bid in buildings:
		var count = buildings[bid]
		if count <= 0: continue
		var data = building_db.get(bid)
		if not data: continue
		
		var eff_interval = get_effective_interval(bid)
		var efficiency = energy_efficiency
		
		# User Throttle
		var throttle = building_throttles.get(bid, 1.0)
		
		# Yields
		if "yield" in data:
			for res in data["yield"]:
				var base_qty = get_effective_yield(bid, res)
				var total_yield_mult = 1.0 + global_yield_bonuses.get(res, 0.0)
				var qty = base_qty * count * total_yield_mult
				
				# Apply Throttle
				var rate_per_min = (qty / eff_interval) * 60.0 * efficiency * throttle
				rates[res] = rates.get(res, 0.0) + rate_per_min
		
		# Consumptions
		if "input" in data:
			for res in data["input"]:
				var qty = float(data["input"][res]) * count
				# Power generators consume at full speed? Maybe throttle should apply to them too now.
				# If user throttles a generator, they want less consumption.
				var consumption_eff = 1.0 if data.get("category") == "power" else efficiency
				
				# Apply Throttle to consumption too
				var rate_per_min = (qty / eff_interval) * 60.0 * consumption_eff * throttle
				rates[res] = rates.get(res, 0.0) - rate_per_min
				
	return rates

func get_building_adjusted_rate(building_id: String) -> Dictionary:
	"""Calculates real-world production rate for a single building of this type, including all multipliers."""
	if not building_id in building_db: return {}
	var data = building_db[building_id]
	var interval = data.get("interval", 1.0)
	var efficiency = energy_efficiency
	
	var warp_mult = 1.0
	if GameState.warp_manager:
		warp_mult = GameState.warp_manager.get_production_multiplier()
		
	var skill_yield_mult = 1.0 + (get_level() * 0.01)
	
	var global_yield_bonuses = {}
	for other_bid in buildings:
		var other_data = building_db.get(other_bid)
		if other_data and other_data.has("yield_bonus"):
			for res in other_data["yield_bonus"]:
				global_yield_bonuses[res] = global_yield_bonuses.get(res, 0.0) + (other_data["yield_bonus"][res] * buildings[other_bid])

	var results = {"yield": {}, "input": {}}
	
	if "yield" in data:
		for res in data["yield"]:
			var base_qty = float(data["yield"][res])
			if building_id == "auto_smelter" or building_id == "hydro_plant" or building_id == "industrial_centrifuge":
				var eng_lvl = GameState.processing_manager.get_level()
				base_qty = base_qty * (1.0 + (log(1.0 + eng_lvl) / log(10.0)) * 5.0)
			
			var total_yield_mult = 1.0 + global_yield_bonuses.get(res, 0.0)
			
			# v74.0: Extractor Efficiency (Module Affix)
			if GameState.shipyard_manager:
				total_yield_mult *= (1.0 + GameState.shipyard_manager.affix_bonuses.get("extractor_efficiency", 0.0))
				
			var qty = base_qty * total_yield_mult * warp_mult * skill_yield_mult
			results["yield"][res] = (qty / interval) * 60.0 * efficiency
			
	if "input" in data:
		for res in data["input"]:
			var qty = float(data["input"][res])
			results["input"][res] = (qty / interval) * 60.0 * efficiency
			
	return results

func _get_credit_cost_multiplier(count: int) -> float:
	# Keep early pacing intact, then ramp aggressively in late game.
	if count < 10:
		return pow(1.15, float(count))
	if count < 25:
		return pow(1.15, 10.0) * pow(1.24, float(count - 10))
	return pow(1.15, 10.0) * pow(1.24, 15.0) * pow(1.32, float(count - 25))

func _get_passive_item_cost_multiplier(count: int) -> float:
	# Passively generated inputs can scale harder than rare bottlenecks.
	if count < 10:
		return pow(1.15, float(count))
	if count < 25:
		return pow(1.15, 10.0) * pow(1.20, float(count - 10))
	return pow(1.15, 10.0) * pow(1.20, 15.0) * pow(1.26, float(count - 25))

func _get_non_passive_item_cost_multiplier(count: int) -> float:
	# Protect non-passive bottlenecks from exploding requirements.
	var mult: float
	if count < 10:
		mult = pow(1.12, float(count))
	elif count < 25:
		mult = pow(1.12, 10.0) * pow(1.08, float(count - 10))
	else:
		mult = pow(1.12, 10.0) * pow(1.08, 15.0) * pow(1.05, float(count - 25))
	return min(mult, 5.0)

func _is_resource_passively_produced(resource_symbol: String) -> bool:
	for bid in building_db:
		var b = building_db.get(bid)
		if not b: continue
		if not ("yield" in b and resource_symbol in b["yield"]):
			continue
		var req = b.get("research_req")
		if req:
			if not GameState.research_manager:
				continue
			if not GameState.research_manager.is_tech_unlocked(req):
				continue
		return true
	# Drone bay yields Scrap via special runtime logic.
	# Scrap removed in v75.0
	return false

var buy_multiplier: int = 1

func set_buy_multiplier(mult: int):
	buy_multiplier = max(1, mult)

func get_building_cost(building_id: String) -> Dictionary:
	"""Calculates progressive late-game scaling with bottleneck protection for N multi-buys."""
	if not building_id in building_db: return {}
	
	var data = building_db[building_id]
	var current_count = get_building_count(building_id)
	
	var total_scaled_cost = {}
	
	# Iterate for the number of buildings we are buying to sum up the progressive cost
	for i in range(buy_multiplier):
		var theoretical_count = current_count + i
		var credit_multiplier = _get_credit_cost_multiplier(theoretical_count)
		var passive_item_multiplier = _get_passive_item_cost_multiplier(theoretical_count)
		var non_passive_item_multiplier = _get_non_passive_item_cost_multiplier(theoretical_count)
		
		for res in data["cost"]:
			var base_cost = float(data["cost"][res])
			var mult = credit_multiplier
			if res != "credits":
				mult = passive_item_multiplier if _is_resource_passively_produced(res) else non_passive_item_multiplier
			
			var cycle_cost = int(ceil(base_cost * mult))
			total_scaled_cost[res] = total_scaled_cost.get(res, 0) + cycle_cost
			
	return total_scaled_cost

func can_afford(building_id: String) -> bool:
	if not building_id in building_db: return false
	
	var data = building_db[building_id]
	var count = get_building_count(building_id)
	
	# Check research requirement
	if data.get("research_req"):
		if not GameState.research_manager.is_tech_unlocked(data["research_req"]):
			return false
	
	# Hard caps now only apply to unique logic buildings
	if data.has("max") and count >= data["max"]:
		return false
		
	var costs = get_building_cost(building_id)
	for res in costs:
		var qty = costs[res]
		if res == "credits":
			if GameState.resources.get_currency("credits") < qty:
				return false
		else:
			if GameState.resources.get_element_amount(res) < qty:
				return false
	
	return true

func build(building_id: String) -> bool:
	if can_afford(building_id):
		var costs = get_building_cost(building_id)
		
		# Spend
		for res in costs:
			var qty = costs[res]
			if res == "credits":
				GameState.resources.remove_currency("credits", qty)
			else:
				GameState.resources.remove_element(res, qty)
		
		# Add
		var count = get_building_count(building_id)
		buildings[building_id] = count + buy_multiplier
		recalc_energy()
		building_constructed.emit(building_id)
		return true
	return false

func recalc_energy():
	var gen = 0.0
	var cons = 0.0
	
	for bid in buildings:
		var count = buildings[bid]
		var throttle = get_building_throttle(bid)
		if bid in building_db:
			var data = building_db[bid]
			
			# Scaling integrated with efficiency throttle
			gen += data.get("energy_gen", 0.0) * count * throttle
			cons += data.get("energy_cons", 0.0) * count * throttle
	
	
	# Audit v4.0: Milestone Level 10 (+10% Grid Efficiency)
	if is_milestone_unlocked(10):
		gen *= 1.10
		
	generation = gen
	consumption = cons
	net_energy = gen - cons
	
	# Reset warning on recalc
	if gen >= cons: grid_warning_sent = false

func process_tick(delta: float):
	# Energy Management
	# 1. Generate energy from generators
	if net_energy > 0:
		GameState.resources.add_energy(net_energy * delta)
	
	# 2. Check if we have enough energy to power consumers
	var current_energy = GameState.resources.get_energy()
	var can_run_full = (net_energy >= 0 or current_energy > 0)
	
	# 3. Calculate energy efficiency (0.0 to 1.0)
	energy_efficiency = 1.0
	
	if net_energy < 0 and not grid_warning_sent:
		events.append(["log", "CRITICAL: Power Grid unstable! Efficiency drop detected.", "power"])
		grid_warning_sent = true
		
	if net_energy < 0:
		# Negative net energy - running on battery
		var deficit = abs(net_energy) * delta
		if current_energy >= deficit:
			# Consume from battery
			GameState.resources.add_energy(-deficit)
			energy_efficiency = 1.0
		elif current_energy > 0:
			# Partial battery available
			GameState.resources.add_energy(-current_energy)  # Drain remaining
			energy_efficiency = current_energy / deficit
		else:
			# No battery - complete shutdown
			energy_efficiency = 0.0
	
	# 4. Handle Fuel-Based Generation (Jumpstart Fix: Running generators ignore GRID efficiency)
	for bid in buildings:
		var count = buildings[bid]
		if count <= 0: continue
		var throttle = get_building_throttle(bid)
		if throttle <= 0: continue
		
		var data = building_db.get(bid)
		if data.get("energy_gen", 0.0) > 0 and "input" in data:
			# This is a fuel-based generator (Coal Burner, H Reactor)
			var can_fuel = true
			var eff_interval = get_effective_interval(bid)
			for res in data["input"]:
				# Generators run at 100% efficiency regardless of grid status to jumpstart
				var needed = data["input"][res] * count * throttle * (delta / eff_interval)
				if GameState.resources.get_element_amount(res) < needed:
					can_fuel = false
					break
			
			if can_fuel:
				# Consume Fuel
				for res in data["input"]:
					var qty = data["input"][res] * count * throttle * (delta / eff_interval)
					GameState.resources.remove_element(res, qty)
			else:
				# Generator stalls - decrease energy_efficiency for subsequent logic
				var stall_gen = data.get("energy_gen") * count * throttle
				GameState.resources.add_energy(-stall_gen * delta) # Reverse the generation
	
	# Production Logic (scaled by energy efficiency)
	if energy_efficiency > 0:
		for bid in buildings:
			var count = buildings[bid]
			if count <= 0: continue
			
			var data = building_db.get(bid)
			if not data: continue
			
			# Fleet Auto-Repair Logic (special case)
			if bid == "repair_gantry":
				_process_fleet_repairs(delta * energy_efficiency * count)

			if "yield" in data:
				if not bid in production_timers: production_timers[bid] = 0.0
					
				var eff_interval = get_effective_interval(bid)
				production_timers[bid] += delta * energy_efficiency
				
				if production_timers[bid] >= eff_interval:
					# Check if building needs inputs
					var can_produce = true
					var throttle = get_building_throttle(bid)
					if throttle <= 0: can_produce = false
					
					if can_produce and "input" in data:
						for res in data["input"]:
							var qty_needed = data["input"][res] * count * throttle
							if GameState.resources.get_element_amount(res) < qty_needed:
								can_produce = false
								break
					
					if can_produce:
						# Consume inputs if required
						if "input" in data:
							for res in data["input"]:
								var qty = data["input"][res] * count * throttle
								GameState.resources.remove_element(res, qty)
						
						# Production complete
						activity_occurred.emit()
						for res in data["yield"]:
							var qty = get_effective_yield(bid, res)
							
							# Audit v4.0: Global Yield Bonuses (e.g., Nitrogen Pressurization)
							var yield_mult = 1.0
							for other_bid in buildings:
								var other_data = building_db.get(other_bid)
								if other_data and other_data.has("yield_bonus"):
									if res in other_data["yield_bonus"]:
										yield_mult += other_data["yield_bonus"][res] * buildings[other_bid]
							
							# v72.8: Trophy Buffs
							if GameState.bounty_manager:
								yield_mult *= GameState.bounty_manager.get_trophy_buff("infrastructure_yield")
							
							# v74.0: Extractor Efficiency (Module Affix)
							if GameState.shipyard_manager:
								yield_mult *= (1.0 + GameState.shipyard_manager.affix_bonuses.get("extractor_efficiency", 0.0))
							
							GameState.resources.add_element(res, qty * count * throttle * yield_mult)
						
						# Statistical expectation (Audit v5.0 - O(1) Performance Foundation)
						if bid == "hydro_plant":
							if GameState.research_manager and GameState.research_manager.is_tech_unlocked("fluid_dynamics"):
								var expected = count * throttle * 0.2
								var floor_exp = floor(expected)
								var extra = 1 if randf() < (expected - floor_exp) else 0
								GameState.resources.add_element("N", floor_exp + extra)
					
						if bid == "industrial_centrifuge":
							if GameState.research_manager and GameState.research_manager.is_tech_unlocked("advanced_mineralogy"):
								var expected = count * throttle * 0.2
								var floor_exp = floor(expected)
								var extra = 1 if randf() < (expected - floor_exp) else 0
								GameState.resources.add_element("Ti", floor_exp + extra)
					
					production_timers[bid] = 0.0
			
			elif data.get("special", "") == "passive_gather":
				if not bid in production_timers: production_timers[bid] = 0.0
				production_timers[bid] += delta * energy_efficiency
				
				if production_timers[bid] >= 10.0:
					# Passive Gather from unlocked gathering actions
					var gm = GameState.gathering_manager
					if gm and gm.actions:
						var unlocked_actions = []
						for action_id in gm.actions:
							var action = gm.actions[action_id]
							
							# Check if action is unlocked (level + research)
							var lvl_req = action.get("level_req", 1)
							if gm.get_level() >= lvl_req:
								var res_req = action.get("research_req")
								if not res_req or GameState.research_manager.is_tech_unlocked(res_req):
									unlocked_actions.append(action)
						
						if not unlocked_actions.is_empty():
							# Drone Bay Balance: One random roll from unlocked actions per bay per 10s
							for i in range(count):
								if randf() < 0.25: # 25% chance per bay to get something
									var random_action = unlocked_actions.pick_random()
									var loot_table = random_action.get("loot_table", [])
									if not loot_table.is_empty():
										var entry = loot_table.pick_random()
										var element = entry[0]
										var chance = entry[1]
										if randf() < chance:
											var amount = randi_range(entry[2], entry[3])
											GameState.resources.add_element(element, max(1, amount))
					
					# Audit v8.0: Passive Scrap Logic Replaced
					# Always generate 1 Cu per 10s per Drone Bay 
					GameState.resources.add_element("Cu", 1 * count)
					
					production_timers[bid] = 0.0

func calculate_offline(delta: float) -> String:
	# Offline Industry
	# 1. Energy check (static)
	if net_energy < 0:
		return "Infrastructure:\nGrid Offline (Negative Energy)."
	
	var report = ""
	var loot_summary = {}
	
	# Offline Industry: Two-Pass 'Jump-Start' Logic
	# Pass 1: Fuel & Energy Priority (Ensures consumers have inputs ready)
	var fuel_buildings = ["solar_panel", "coal_burner", "hydro_plant", "palladium_generator", "hydrogen_reactor"]
	
	for bid in fuel_buildings:
		if not bid in buildings: continue
		var count = buildings[bid]
		var data = building_db.get(bid)
		var throttle = building_throttles.get(bid, 1.0)
		
		if "yield" in data:
			var eff_interval = get_effective_interval(bid)
			# Effective cycles reduced by throttle
			var base_cycles = int(delta / eff_interval)
			var cycles = int(base_cycles * throttle)
			
			if "input" in data:
				var max_cycles = cycles
				for res in data["input"]:
					var qty_per_cycle = data["input"][res] * count
					var available = GameState.resources.get_element_amount(res)
					var possible = int(available / qty_per_cycle)
					max_cycles = min(max_cycles, possible)
				cycles = max_cycles
			
			if cycles > 0:
				if "input" in data:
					for res in data["input"]:
						GameState.resources.remove_element(res, data["input"][res] * count * cycles)
				for res in data["yield"]:
					var qty = get_effective_yield(bid, res)
					var total = qty * count * cycles
					GameState.resources.add_element(res, total)
					loot_summary[res] = loot_summary.get(res, 0.0) + total

	# Pass 2: General Production
	for bid in buildings:
		if bid in fuel_buildings: continue # Already handled
		var count = buildings[bid]
		if count <= 0: continue
		var data = building_db.get(bid)
		var throttle = building_throttles.get(bid, 1.0)
		
		if "yield" in data:
			var eff_interval = get_effective_interval(bid)
			var base_cycles = int(delta / eff_interval)
			var cycles = int(base_cycles * throttle)
			
			# If building has input requirements, calculate max possible cycles
			if "input" in data:
				var max_cycles = cycles
				for res in data["input"]:
					var qty_per_cycle = data["input"][res] * count
					var available = GameState.resources.get_element_amount(res)
					var possible = int(available / qty_per_cycle)
					max_cycles = min(max_cycles, possible)
				cycles = max_cycles
			
			if cycles > 0:
				# Consume inputs if required
				if "input" in data:
					for res in data["input"]:
						var qty = data["input"][res] * count * cycles
						GameState.resources.remove_element(res, qty)
				
				# Produce outputs
				for res in data["yield"]:
					var qty = get_effective_yield(bid, res)
					var total = qty * count * cycles
					GameState.resources.add_element(res, total)
					loot_summary[res] = loot_summary.get(res, 0.0) + total

	
	if not loot_summary.is_empty():
		report += "Infrastructure Production (Offline):\n"
		for item in loot_summary:
			report += " + %s: %s\n" % [item, FormatUtils.format_number(loot_summary[item])]
			
	# Audit v9.0 P2-23: Special Buff Reporting
	if get_building_count("crew_quarters") > 0:
		report += " + Crew Quarters: +10% XP Active\n"
	if get_building_count("biosphere_dome") > 0:
		var bonus = get_building_count("biosphere_dome") * 5
		report += " + Biosphere Domes: +%d%% Gather Speed Active\n" % bonus
			
	return report

func get_save_data_manager() -> Dictionary:
	var data = get_save_data()
	data["buildings"] = buildings
	data["building_throttles"] = building_throttles
	return data

func load_save_data_manager(data: Dictionary):
	load_save_data(data)
	if data.is_empty(): return
	
	buildings = data.get("buildings", {})
	building_throttles = data.get("building_throttles", {})

	# Fix types if json loaded strings
	for k in buildings: buildings[k] = int(buildings[k])
	for k in building_throttles: building_throttles[k] = float(building_throttles[k])
	
	recalc_energy()

func reset(decay_factor: float = 1.0) -> void:
	super.reset(decay_factor)
	buildings.clear()
	generation = 0.0
	consumption = 0.0
	net_energy = 0.0
	energy_efficiency = 1.0
	production_timers.clear()
	recalc_energy()

func _process_fleet_repairs(repair_power: float):
	# repair_power is delta * efficiency * count
	# Repairs 1% of damage per minute per gantry
	# 1% per 60s = 0.016% per second
	var fm = GameState.fleet_manager
	if not fm or fm.pending_repairs.is_empty(): return
	
	var repair_pct = 0.00016 * repair_power # approx 1% per minute
	for hull_id in fm.pending_repairs.keys():
		var total_damaged = fm.pending_repairs[hull_id]
		if total_damaged <= 0: continue
		
		# For "auto-repair", we treat it as structural mending (doesn't cost credits)
		# but it's slow. This rewards high-end infrastructure.
		var mended = int(total_damaged * repair_pct)
		if mended < 1: mended = 1 # Minimum 1 cr per tick if damaged
		
		fm.pending_repairs[hull_id] = max(0, total_damaged - mended)
		if fm.pending_repairs[hull_id] == 0:
			fm.pending_repairs.erase(hull_id)
