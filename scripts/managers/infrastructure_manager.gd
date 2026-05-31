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

# ── P0 Infrastructure rebalance (data-driven; retune via constants, no logic edits) ──
# P0.3: cap the engineering yield bonus so idle industry buildings can't
# obsolete active processing (was 1 + log10(1+eng)*5 → ~11x at eng 99).
const INFRA_ENG_SCALE_COEF := 1.0   # log coefficient (was 5.0)
const INFRA_ENG_SCALE_CAP  := 3.0   # hard ceiling on the engineering multiplier
# P0.2: diminishing returns on stacked buildings — linear to KNEE, then a
# saturating tail (asymptote = KNEE + TAIL). Infra is a parallel baseline,
# not an infinite scaling path.
const INFRA_DR_KNEE := 10
const INFRA_DR_TAIL := 10
# Single source of truth for engineering-scaled buildings (previously
# duplicated & inconsistent: 7 here-equivalent vs only 3 in
# get_building_adjusted_rate, so the UI rate disagreed with production).
const INFRA_ENG_SCALED_BUILDINGS := ["auto_smelter", "hydro_plant", "industrial_centrifuge",
	"munitions_factory", "titanium_refinery", "superalloy_forge", "adv_circuit_foundry"]
# P1.4: gathering owns the ore tier. Raw ORE/metal extractors that duplicate a
# gather action are throttled so active gathering is the primary source and
# infra ore-mining is a convenience trickle (on top of P0.2 DR). Bulk
# (Dirt/Water/Wood), gas, uranium and exotic (Void/Chrono) extractors are NOT
# throttled — those tiers are infra-owned by design. Industry/conversion
# buildings are unaffected (handled by P0.3 eng cap).
const INFRA_ORE_EXTRACTION_MULT := 0.5
const INFRA_ORE_EXTRACTORS := ["lithium_extractor", "brine_extractor", "copper_mine",
	"deep_crust_drill", "tin_mine", "quartz_mine", "quartz_excavator", "zinc_mine",
	"bauxite_mine", "bauxite_miner", "dolomite_quarry", "manganese_dredge", "nickel_mine",
	"chromite_excavator", "tungsten_drill", "germanite_excavator", "platinum_drill",
	"precious_dredge", "iridium_drill", "osmium_condenser"]


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
		"description": "+16000000.0 kW (-1 Quantum Core)",
		"cost": {"credits": 25000000, "VoidArtifact": 50, "QuantumCore": 10},
		"energy_gen": 16000000.0,
		"energy_cons": 0.0,
		# v103d: AntimatterFuel had NO source anywhere -> this generator could
		# never run. Swapped to QuantumCore (obtainable: processing + combat).
		"input": {"QuantumCore": 1},
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
		# v103d: AntimatterFuel had no source -> Chrono-Siphon was unbuildable.
		# Swapped to VoidEssence (obtainable: Void Rift Anchor + gather), same
		# void_navigation tier as this building.
		"cost": {"credits": 25000000, "Superalloy": 1000, "VoidEssence": 50},
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
		# v103e: DroneCore has NO source anywhere (advertised scavenger drop
		# was never implemented) -> Centrifuge was unbuildable. Swapped to
		# Circuit (obtainable: processing + infra + combat), same tier.
		"cost": {"credits": 500000, "Steel": 1000, "Si": 2000, "Circuit": 100},
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
		"yield": {"C": 6.0},
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

	# ===== HEAVY INDUSTRY (v102: auto-producers for zone-gate-tier mats) =====
	# Ti / AdvCircuit / Superalloy previously had no scalable auto-source,
	# making the v102 zone-gate curve unsuppliable by automation. Inputs are
	# deliberately condensed to mats that ALREADY have auto-producers, so the
	# supply gap doesn't cascade. Engineering-scaled (see get_effective_yield).
	"titanium_refinery": {
		"name": "Titanium Refinery",
		"description": "+1.5 Ti (-3 Dolomite)",
		"cost": {"credits": 850000, "Steel": 1500, "Circuit": 100},
		"energy_gen": 0.0,
		"energy_cons": 1200.0,
		"yield": {"Ti": 1.5},
		"input": {"Dolomite": 3},
		"interval": 5.0,
		"research_req": "metallurgy_advanced",
		"category": "industry"
	},
	"superalloy_forge": {
		"name": "Superalloy Forge",
		"description": "+1.0 Superalloy (-4 Steel, -2 Ni, -1 Cr, -1 Ti)",
		"cost": {"credits": 1200000, "Steel": 2500, "Ti": 200, "Circuit": 150},
		"energy_gen": 0.0,
		"energy_cons": 1800.0,
		"yield": {"Superalloy": 1.0},
		"input": {"Steel": 4, "Ni": 2, "Cr": 1, "Ti": 1},
		"interval": 5.0,
		"research_req": "superalloy_engineering",
		"category": "industry"
	},
	"adv_circuit_foundry": {
		"name": "Advanced Circuit Foundry",
		"description": "+1.2 AdvCircuit (-5 Circuit, -4 Si, -2 Germanium)",
		"cost": {"credits": 2000000, "Steel": 3000, "Superalloy": 120, "Circuit": 200},
		"energy_gen": 0.0,
		"energy_cons": 3500.0,
		"yield": {"AdvCircuit": 1.2},
		"input": {"Circuit": 5, "Si": 4, "Germanium": 2},
		"interval": 5.0,
		"research_req": "nano_fabrication",
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
}

var production_timers: Dictionary = {}

# v104: Continuous building-upkeep sink. The economy glut comes from continuous
# raw production vs. one-time gate costs. Research tier-scaling (Lever 1) drains
# stockpiles at gates, but a finite sink still loses to an infinite source over
# a multi-day idle. Upkeep is the forever-drain: every building consumes a small
# amount of the cheapest glut mats per minute, and the per-building cost itself
# grows with total building count so the appetite scales over the long curve.
# Safety: drain-if-available only — if the player can't pay, NOTHING stalls and
# NOTHING goes negative. It only ever removes surplus, never punishes AFK.
const UPKEEP_INTERVAL := 60.0
const UPKEEP_BASE := {"Water": 2.0, "Dirt": 1.0}  # per building, per interval, pre-growth
const UPKEEP_COUNT_GROWTH := 0.05                  # +5% per-building cost per building owned
const UPKEEP_GROWTH_CAP := 8.0                     # growth multiplier ceiling
var _upkeep_timer: float = 0.0
# P2.6: proportional upkeep throttle. When upkeep mats run short, buildings
# produce at the fraction you can afford (bottleneck resource ratio) instead
# of upkeep being a silent free pass. Smooth, self-recovering, never
# destroys buildings. 1.0 = fully supplied. Transient (recomputed; not saved).
var upkeep_efficiency: float = 1.0

func _init():
	super._init("Infrastructure")

# Returns {res: amount_consumed} for reporting. intervals = number of full
# UPKEEP_INTERVAL periods to charge (1 online, many for an offline catch-up).
func _apply_upkeep(intervals: int) -> Dictionary:
	var consumed: Dictionary = {}
	if intervals <= 0:
		return consumed
	var total: int = 0
	for bid in buildings:
		var c: int = buildings[bid]
		if c > 0:
			total += c
	if total <= 0:
		return consumed
	var growth: float = min(UPKEEP_GROWTH_CAP, 1.0 + float(total) * UPKEEP_COUNT_GROWTH)
	for res in UPKEEP_BASE:
		var demand: float = float(UPKEEP_BASE[res]) * float(total) * growth * float(intervals)
		if demand <= 0.0:
			continue
		var avail: float = GameState.resources.get_element_amount(res)
		var take: float = min(demand, avail)  # never negative, never a hard gate
		if take > 0.0:
			GameState.resources.remove_element(res, take)
			consumed[res] = take
	return consumed

# P2.6: affordable fraction of upkeep for `intervals` periods WITHOUT
# consuming — the bottleneck (min) ratio across upkeep resources. Production
# is scaled by this so a shortfall throttles output proportionally.
func _upkeep_efficiency_for(intervals: int) -> float:
	if intervals <= 0:
		return 1.0
	var total: int = 0
	for bid in buildings:
		var c: int = buildings[bid]
		if c > 0:
			total += c
	if total <= 0:
		return 1.0
	var growth: float = min(UPKEEP_GROWTH_CAP, 1.0 + float(total) * UPKEEP_COUNT_GROWTH)
	var eff: float = 1.0
	for res in UPKEEP_BASE:
		var demand: float = float(UPKEEP_BASE[res]) * float(total) * growth * float(intervals)
		if demand <= 0.0:
			continue
		var avail: float = GameState.resources.get_element_amount(res)
		eff = min(eff, clamp(avail / demand, 0.0, 1.0))
	return eff

func get_building_count(building_id: String) -> int:
	return buildings.get(building_id, 0)

func set_building_throttle(building_id: String, value: float):
	building_throttles[building_id] = clamp(value, 0.0, 1.0)
	activity_occurred.emit() # Refresh UI rates

func get_building_throttle(building_id: String) -> float:
	return building_throttles.get(building_id, 1.0)

# P0.3: capped engineering yield multiplier. Single source of truth — used
# by get_effective_yield (online + offline + total rates) AND
# get_building_adjusted_rate, so the UI can no longer disagree with reality.
func _eng_scale(building_id: String) -> float:
	if not building_id in INFRA_ENG_SCALED_BUILDINGS:
		return 1.0
	var eng_lvl = GameState.processing_manager.get_level()
	return clamp(1.0 + (log(1.0 + eng_lvl) / log(10.0)) * INFRA_ENG_SCALE_COEF,
		1.0, INFRA_ENG_SCALE_CAP)

# P0.2: diminishing returns on stacked buildings. Linear up to KNEE, then a
# saturating tail so over-stacking asymptotes (ceiling = KNEE + TAIL).
# Applied to BOTH yield and input so surplus buildings idle rather than
# burn inputs for no extra output.
func _dr_units(count: int) -> float:
	if count <= INFRA_DR_KNEE:
		return float(count)
	var extra := float(count - INFRA_DR_KNEE)
	return float(INFRA_DR_KNEE) + extra / (1.0 + extra / float(INFRA_DR_TAIL))

# P1.4: yield multiplier for raw ore extractors (gathering owns the ore tier).
func _ore_throttle(building_id: String) -> float:
	return INFRA_ORE_EXTRACTION_MULT if building_id in INFRA_ORE_EXTRACTORS else 1.0

func get_effective_yield(building_id: String, resource_symbol: String) -> float:
	var data = building_db.get(building_id)
	if not data or not "yield" in data or not resource_symbol in data["yield"]: return 0.0

	var base_qty = float(data["yield"][resource_symbol])
	base_qty *= _eng_scale(building_id)     # P0.3 capped engineering scaling
	base_qty *= _ore_throttle(building_id)  # P1.4 ore-tier handed to gathering
	# v109: Recursion — Recursive Networking (infinite +5%/level building
	# yield). Applied here (shared by process_tick AND offline catch-up) so
	# online and offline production stay consistent.
	if GameState.research_manager:
		base_qty *= (1.0 + GameState.research_manager.get_efficiency_bonus("building_yield_mult"))
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
				var qty = base_qty * _dr_units(count) * total_yield_mult  # P0.2 DR
				
				# Apply Throttle
				var rate_per_min = (qty / eff_interval) * 60.0 * efficiency * throttle
				rates[res] = rates.get(res, 0.0) + rate_per_min
		
		# Consumptions
		if "input" in data:
			for res in data["input"]:
				var qty = float(data["input"][res]) * _dr_units(count)  # P0.2 DR
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
			# P0.3: same capped scaling as production (was inconsistent here —
			# only 3 buildings vs 7 in get_effective_yield). Per-single-building
			# rate, so no DR (DR is an aggregate cap, see get_total_resource_rates).
			var base_qty = float(data["yield"][res]) * _eng_scale(building_id) * _ore_throttle(building_id)

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
	"""Calculates progressive late-game scaling with O(1) math for N multi-buys."""
	if not building_id in building_db: return {}
	
	var data = building_db[building_id]
	var current_count = get_building_count(building_id)
	var buy_qty = buy_multiplier
	
	var total_scaled_cost = {}
	
	for res in data["cost"]:
		var base_cost = float(data["cost"][res])
		var total_mult = 0.0
		
		if res == "credits":
			total_mult = _get_total_scaling_credits(current_count, buy_qty)
		elif _is_resource_passively_produced(res):
			total_mult = _get_total_scaling_passive(current_count, buy_qty)
		else:
			total_mult = _get_total_scaling_non_passive(current_count, buy_qty)
			
		total_scaled_cost[res] = int(ceil(base_cost * total_mult))
			
	return total_scaled_cost

func _get_total_scaling_credits(start: int, qty: int) -> float:
	var total = 0.0
	var remaining = qty
	var current = start
	
	# Tier 1: 0-10 (rate 1.15)
	if current < 10:
		var batch = min(remaining, 10 - current)
		total += _sum_geometric_series(1.0, 1.15, current, batch)
		remaining -= batch
		current += batch
		
	# Tier 2: 10-25 (rate 1.24)
	if remaining > 0 and current < 25:
		var batch = min(remaining, 25 - current)
		var tier_coeff = pow(1.15, 10.0)
		total += _sum_geometric_series(tier_coeff, 1.24, current - 10, batch)
		remaining -= batch
		current += batch
		
	# Tier 3: 25+ (rate 1.32)
	if remaining > 0:
		var tier_coeff = pow(1.15, 10.0) * pow(1.24, 15.0)
		total += _sum_geometric_series(tier_coeff, 1.32, current - 25, remaining)
		
	return total

func _get_total_scaling_passive(start: int, qty: int) -> float:
	var total = 0.0
	var remaining = qty
	var current = start
	
	# Tier 1: 0-10 (rate 1.15)
	if current < 10:
		var batch = min(remaining, 10 - current)
		total += _sum_geometric_series(1.0, 1.15, current, batch)
		remaining -= batch
		current += batch
		
	# Tier 2: 10-25 (rate 1.20)
	if remaining > 0 and current < 25:
		var batch = min(remaining, 25 - current)
		var tier_coeff = pow(1.15, 10.0)
		total += _sum_geometric_series(tier_coeff, 1.20, current - 10, batch)
		remaining -= batch
		current += batch
		
	# Tier 3: 25+ (rate 1.26)
	if remaining > 0:
		var tier_coeff = pow(1.15, 10.0) * pow(1.20, 15.0)
		total += _sum_geometric_series(tier_coeff, 1.26, current - 25, remaining)
		
	return total

func _get_total_scaling_non_passive(start: int, qty: int) -> float:
	# Non-passive has a min(mult, 5.0) cap which makes it linear once capped
	var total = 0.0
	var remaining = qty
	var current = start
	
	# We can't easily O(1) with the min() in every step if it's not yet hit.
	# But since non-passive caps at 5.0 very quickly, let's just use the loop if small, or math if capped.
	# Actually, the non-passive logic in _get_non_passive_item_cost_multiplier returns the mult for ONE building.
	# mult = pow(1.12, 10) * pow(1.08, 15) * pow(1.05, count-25).
	# Let's find when this hits 5.0.
	# 1.12^10 = 3.10
	# 3.10 * 1.08^15 = 3.10 * 3.17 = 9.8 (already > 5!)
	# Wait, so it caps in Tier 2.
	# 3.10 * 1.08^x = 5 => 1.08^x = 1.61 => x = ln(1.61)/ln(1.08) = 0.47 / 0.076 = 6.2
	# So it caps at 10 + 6.2 = 16.2.
	
	# Since it's piecewise and capped, let's just maintain the iterative approach but ONLY for the uncapped portion.
	# Or better, just fix it properly:
	
	for i in range(qty):
		var mult = _get_non_passive_item_cost_multiplier(current + i)
		if mult >= 5.0:
			# If we hit the cap, the rest is just 5.0 * Remaining
			total += 5.0 * (remaining - i)
			break
		total += mult
		
	return total

func _sum_geometric_series(A: float, r: float, start_pow: int, n: int) -> float:
	if n <= 0: return 0.0
	if abs(r - 1.0) < 0.0001: return A * n
	# Sum = A * r^start * (1 - r^n) / (1 - r)
	return A * pow(r, float(start_pow)) * (1.0 - pow(r, float(n))) / (1.0 - r)

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

const INFRA_ENERGY_BUFFER := 1000000.0  # v110: infra grid's own surplus-buffer ceiling

func process_tick(delta: float):
	# Energy Management
	# v110: the infra grid owns resources.max_energy now (it's the surplus
	# buffer ceiling). The ship used to write this field; it no longer does, so
	# we keep it at a stable buffer size here. Idempotent.
	if GameState.resources and GameState.resources.max_energy < INFRA_ENERGY_BUFFER:
		GameState.resources.set_max_energy(INFRA_ENERGY_BUFFER)
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
			
			if "yield" in data:
				if not bid in production_timers: production_timers[bid] = 0.0
					
				var eff_interval = get_effective_interval(bid)
				production_timers[bid] += delta * energy_efficiency * upkeep_efficiency  # P2.6
				
				if production_timers[bid] >= eff_interval:
					# Check if building needs inputs
					var can_produce = true
					var throttle = get_building_throttle(bid)
					if throttle <= 0: can_produce = false
					
					if can_produce and "input" in data:
						for res in data["input"]:
							var qty_needed = data["input"][res] * _dr_units(count) * throttle  # P0.2 DR
							if GameState.resources.get_element_amount(res) < qty_needed:
								can_produce = false
								break
					
					if can_produce:
						# Consume inputs if required
						if "input" in data:
							for res in data["input"]:
								var qty = data["input"][res] * _dr_units(count) * throttle  # P0.2 DR
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
							
							var _prod: float = qty * _dr_units(count) * throttle * yield_mult  # P0.2 DR
							GameState.resources.add_element(res, _prod)
							GameState.note_production("infra", _prod)  # P3.10
						
						# Statistical expectation (Audit v5.0 - O(1) Performance Foundation)
						if bid == "hydro_plant":
							if GameState.research_manager and GameState.research_manager.is_tech_unlocked("fluid_dynamics"):
								var expected = _dr_units(count) * throttle * 0.2  # P0.2 DR
								var floor_exp = floor(expected)
								var extra = 1 if randf() < (expected - floor_exp) else 0
								GameState.resources.add_element("N", floor_exp + extra)
					
						if bid == "industrial_centrifuge":
							if GameState.research_manager and GameState.research_manager.is_tech_unlocked("advanced_mineralogy"):
								var expected = _dr_units(count) * throttle * 0.2  # P0.2 DR
								var floor_exp = floor(expected)
								var extra = 1 if randf() < (expected - floor_exp) else 0
								GameState.resources.add_element("Ti", floor_exp + extra)
					
					production_timers[bid] = 0.0
			
			elif data.get("special", "") == "passive_gather":
				if not bid in production_timers: production_timers[bid] = 0.0
				production_timers[bid] += delta * energy_efficiency * upkeep_efficiency  # P2.6
				
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
					GameState.resources.add_element("Cu", 1 * count); GameState.note_production("infra", count)  # P3.10

					production_timers[bid] = 0.0

	# v104: Continuous upkeep sink — only charged while the grid is live, so an
	# idle/unpowered base never bleeds mats. Closed-form: accumulate then charge
	# whole intervals at once (no per-frame removal churn).
	if energy_efficiency > 0:
		_upkeep_timer += delta
		if _upkeep_timer >= UPKEEP_INTERVAL:
			var n: int = int(_upkeep_timer / UPKEEP_INTERVAL)
			_upkeep_timer -= float(n) * UPKEEP_INTERVAL
			upkeep_efficiency = _upkeep_efficiency_for(n)  # P2.6 throttle for next cycle
			_apply_upkeep(n)

func calculate_offline(delta: float) -> String:
	# Offline Industry
	# 1. Energy check (static)
	if net_energy < 0:
		return "Infrastructure:\nGrid Offline (Negative Energy)."
	
	var report = ""
	var loot_summary = {}

	# P2.6: throttle offline production by the upkeep fraction the player can
	# afford over the whole window (computed up front, non-consuming; the
	# actual drain still happens once at the end via _apply_upkeep).
	upkeep_efficiency = _upkeep_efficiency_for(int(delta / UPKEEP_INTERVAL))
	
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
			var cycles = int(base_cycles * throttle * upkeep_efficiency)  # P2.6
			
			if "input" in data:
				var max_cycles = cycles
				for res in data["input"]:
					var qty_per_cycle = data["input"][res] * _dr_units(count)  # P0.2 DR
					var available = GameState.resources.get_element_amount(res)
					var possible = int(available / qty_per_cycle)
					max_cycles = min(max_cycles, possible)
				cycles = max_cycles
			
			if cycles > 0:
				if "input" in data:
					for res in data["input"]:
						GameState.resources.remove_element(res, data["input"][res] * _dr_units(count) * cycles)  # P0.2 DR
				for res in data["yield"]:
					var qty = get_effective_yield(bid, res)
					var total = qty * _dr_units(count) * cycles  # P0.2 DR
					GameState.resources.add_element(res, total); GameState.note_production("infra", total)  # P3.10
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
			var cycles = int(base_cycles * throttle * upkeep_efficiency)  # P2.6
			
			# If building has input requirements, calculate max possible cycles
			if "input" in data:
				var max_cycles = cycles
				for res in data["input"]:
					var qty_per_cycle = data["input"][res] * _dr_units(count)  # P0.2 DR
					var available = GameState.resources.get_element_amount(res)
					var possible = int(available / qty_per_cycle)
					max_cycles = min(max_cycles, possible)
				cycles = max_cycles
			
			if cycles > 0:
				# Consume inputs if required
				if "input" in data:
					for res in data["input"]:
						var qty = data["input"][res] * _dr_units(count) * cycles  # P0.2 DR
						GameState.resources.remove_element(res, qty)
				
				# Produce outputs
				for res in data["yield"]:
					var qty = get_effective_yield(bid, res)
					var total = qty * _dr_units(count) * cycles  # P0.2 DR
					GameState.resources.add_element(res, total); GameState.note_production("infra", total)  # P3.10
					loot_summary[res] = loot_summary.get(res, 0.0) + total

	
	if not loot_summary.is_empty():
		report += "Infrastructure Production (Offline):\n"
		for item in loot_summary:
			report += " + %s: %s\n" % [item, FormatUtils.format_number(loot_summary[item])]
			
	# Audit v9.0 P2-23: Special Buff Reporting
	if get_building_count("biosphere_dome") > 0:
		var bonus = get_building_count("biosphere_dome") * 5
		report += " + Biosphere Domes: +%d%% Gather Speed Active\n" % bonus

	# v104: Offline upkeep — closed-form, whole intervals only. Grid is
	# guaranteed live here (negative-energy case returned early above).
	var upkeep := _apply_upkeep(int(delta / UPKEEP_INTERVAL))
	if not upkeep.is_empty():
		report += "Infrastructure Upkeep (Offline):\n"
		for item in upkeep:
			report += " - %s: %s\n" % [item, FormatUtils.format_number(upkeep[item])]

	# Transparency: never silently throttle — tell the player why output was low.
	if upkeep_efficiency < 0.999:
		report += "Infrastructure throttled to %d%% — upkeep ran short.\n" % int(upkeep_efficiency * 100.0)

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
