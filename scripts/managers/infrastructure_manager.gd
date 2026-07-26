extends Skill

signal activity_occurred
signal building_constructed(building_id)
signal boost_card_installed(building_id)  # v130: drives the Boost-Card onboarding mission

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
const INFRA_ENG_SCALE_CAP  := 2.0   # hard ceiling on the engineering multiplier (v112: 3.0->2.0, trims the infra baseline into the 30-70%-of-active parity band)
# P0.2: diminishing returns on stacked buildings — linear to KNEE, then a
# saturating tail (asymptote = KNEE + TAIL). Infra is a parallel baseline,
# not an infinite scaling path.
const INFRA_DR_KNEE := 10
const INFRA_DR_TAIL := 10
# v121 / v134h: PRIMITIVE extractors (the base-material pyramid — 3 bulk + 21
# raw-ore extractors, whose surplus the player now MANUALLY feeds into the Warp
# Core) get a far higher DR ceiling so stacking ~10-30 of each pays. Knee 30 +
# Tail 30 => ~45 useful asymptote (vs 20). (Output grows freely — the Core is a
# manual "Feed the Core" sink now, not an auto-drain — so this just lets the
# stockpiles the player feeds build up.)
# Industry/converters/power EXCLUDED — they keep 10/10 so infra can't obsolete
# active processing (and converter outputs Cu/Steel/Ti stay scarce).
const INFRA_PRIMITIVE_DR_KNEE := 30
const INFRA_PRIMITIVE_DR_TAIL := 30
const PRIMITIVE_EXTRACTORS := ["auto_excavator", "industrial_pump", "bio_harvester",
	"lithium_extractor", "brine_extractor", "copper_mine", "deep_crust_drill",
	"tin_mine", "quartz_mine", "quartz_excavator", "zinc_mine", "bauxite_mine",
	"bauxite_miner", "dolomite_quarry", "manganese_dredge", "nickel_mine",
	"chromite_excavator", "tungsten_drill", "germanite_excavator", "platinum_drill",
	"precious_dredge", "iridium_drill", "osmium_condenser", "uranium_centrifuge"]
# Single source of truth for engineering-scaled buildings (previously
# duplicated & inconsistent: 7 here-equivalent vs only 3 in
# get_building_adjusted_rate, so the UI rate disagreed with production).
# v144: "munitions_factory" REMOVED from this list. It was a dangling id (no
# building_db entry) until the explosive ammo ladder was authored; now that the
# building exists, leaving it here would make it the ONLY ammo building with
# engineering scaling. The cap is reached at Engineering ~10 (1 + log10(11) =
# 2.04 -> clamped to 2.0), so effectively every player would get 10 MissileT1/5s
# — kinetic's own rate, for a weapon that fires at HALF the cadence. That is a
# 2x oversupply, not the demand parity the ladder is tuned for. All six ammo
# buildings now scale identically (eng multiplier 1.0).
const INFRA_ENG_SCALED_BUILDINGS := ["auto_smelter", "hydro_plant", "industrial_centrifuge",
	"titanium_refinery", "superalloy_forge", "adv_circuit_foundry",
	"au_refinery", "semiconductor_furnace", "structural_press", "chip_fab"]
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
		"cost": {"credits": 15000, "Steel": 100, "Hydraulics": 10},
		"energy_gen": 250.0,
		"energy_cons": 0.0,
		"research_req": "basic_engineering",
		"category": "power"
	},
	"biomass_plant": {
		"name": "Biomass Plant",
		"description": "+1000.0 kW (-5 Wood)",
		"cost": {"credits": 35000, "Steel": 200, "Circuit": 20},
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
		"research_req": "quantum_dynamics",
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
		"cost": {"credits": 80000000, "VoidArtifact": 100, "QuantumCore": 25},
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
		"cost": {"credits": 12000, "Fe": 2000, "Si": 1200, "Z1_Core": 2},
		"energy_gen": 0.0,
		"energy_cons": 15.0,
		"yield": {"Dirt": 10},
		"interval": 5.0,
		"category": "extraction"
	},
	"industrial_pump": {
		"name": "Industrial Pump",
		"description": "+10 Water",
		"cost": {"credits": 12000, "Fe": 2000, "Si": 1200, "Z1_Core": 2}, 
		"energy_gen": 0.0,
		"energy_cons": 25.0,
		"yield": {"Water": 10},
		"interval": 5.0,
		"category": "extraction"
	},
	"bio_harvester": {
		"name": "Bio-Harvester",
		"description": "Automated wood collection.",
		"cost": {"credits": 45000, "Steel": 900, "Circuit": 60, "Z2_Core": 2},
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
		"description": "+1.7 Lithium Ore (Efficient)",
		"cost": {"credits": 1500000, "Steel": 1800, "AdvCircuit": 120},
		"energy_gen": 0.0,
		"energy_cons": 300.0,
		"yield": {"Spodumene": 1.7},
		"interval": 5.0,
		"research_req": "metallurgy_advanced",
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
		"cost": {"credits": 1400000, "Steel": 1600, "AdvCircuit": 100},
		"energy_gen": 0.0,
		"energy_cons": 300.0,
		"yield": {"Malachite": 1.7},
		"interval": 5.0,
		"research_req": "metallurgy_advanced",
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
		"cost": {"credits": 2200000, "Ti": 500, "AdvCircuit": 150},
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
		"cost": {"credits": 2200000, "Ti": 450, "AdvCircuit": 130},
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
		"research_req": "adv_materials",
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
		"cost": {"credits": 1600000, "Ti": 350, "AdvCircuit": 90},
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
		"cost": {"credits": 3500000, "Ti": 600, "QuantumCore": 10, "AdvCircuit": 180},
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
	# ========== Phase B: LATE-TIER BULK CONVERTER BAND (Z8-10 spine) ==========
	# First infra source of Neutronium (previously NONE). void_navigation tier.
	"neutronium_condenser": {
		"name": "Neutronium Condenser",
		"description": "+0.4 Neutronium",
		"cost": {"credits": 30000000, "Superalloy": 1500, "VoidCrystal": 40, "QuantumCore": 20},
		"energy_gen": 0.0,
		"energy_cons": 150000.0,
		"yield": {"Neutronium": 0.4},
		"interval": 10.0,
		"research_req": "neutronium_synthesis",
		"category": "extraction"
	},
	"bioreactor_vat": {
		"name": "Bio-Reactor Vat",
		"description": "+0.2 Bio-Reactor Core (-6 Biohazard Sample, -0.5 Pathogen Core, -1 Quantum Core)",
		"cost": {"credits": 35000000, "Superalloy": 1200, "QuantumCore": 25, "Neutronium": 30},
		"energy_gen": 0.0,
		"energy_cons": 160000.0,
		"yield": {"BioReactorCore": 0.2},
		"input": {"BiohazardSample": 6, "QuantumCore": 1, "PathogenCore": 0.5},
		"interval": 10.0,
		"research_req": "neutronium_synthesis",
		"category": "industry"
	},
	"omega_foundry": {
		"name": "Omega Foundry",
		"description": "+0.15 Omega Composite (-3 Omega Plating, -1 Neutronium Plate, -15 Adv Circuit)",
		"cost": {"credits": 45000000, "Neutronium": 60, "OmegaPlating": 30, "AdvCircuit": 200},
		"energy_gen": 0.0,
		"energy_cons": 180000.0,
		"yield": {"OmegaComposite": 0.15},
		"input": {"OmegaPlating": 3, "NeutroniumPlate": 1, "AdvCircuit": 15},
		"interval": 10.0,
		"research_req": "primordial_engineering",
		"category": "industry"
	},
	"primordial_extractor": {
		"name": "Primordial Extractor",
		"description": "+0.1 Primordial Matrix (-2.5 Primordial Shard, -1.5 Diamond, -1 Void Lattice)",
		"cost": {"credits": 60000000, "Neutronium": 100, "PrimordialShard": 25, "OmegaComposite": 5},
		"energy_gen": 0.0,
		"energy_cons": 200000.0,
		"yield": {"PrimordialMatrix": 0.1},
		"input": {"PrimordialShard": 2.5, "Diamond": 1.5, "VoidLattice": 1},
		"interval": 10.0,
		"research_req": "primordial_engineering",
		"category": "industry"
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
		"research_req": "industrial_logistics",
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
	# v136: Co had NO scalable source — only refine_pentlandite's 0.4-chance
	# byproduct (an ACTIVE processing recipe). The parallel infra factory could
	# auto-produce Ni/Cr/Ti/Steel but never Co, so Superalloy (Co 2/craft,
	# demanded in the thousands for zone_6-10 gates) was hard-bottlenecked. This
	# gives the factory a real Co source. Co-produced with Ni from Pentlandite
	# (realistic). Build cost is deliberately Co-free (Steel + AdvCircuit) so
	# there's no Superalloy->Co->Superalloy circular deadlock on the first build.
	"cobalt_refinery": {
		"name": "Cobalt Refinery",
		"description": "Extracts cobalt from pentlandite sulfide — the co-metal to nickel, essential for superalloys.",
		"cost": {"credits": 850000, "Steel": 2000, "AdvCircuit": 150},
		"energy_gen": 0.0,
		"energy_cons": 1500.0,
		"yield": {"Co": 1.5},
		"input": {"Pentlandite": 2.5, "C": 0.8},
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
		"research_req": "adv_materials",
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
		# v139g Beat-2 funnel tune: Circuit 100 -> 40, SalvageData 20 -> 12. A
		# 100-Circuit toll on the machine that MAKES Circuits was chicken-and-egg
		# grind (part of the measured m029a7-band 55h wall); 40 keeps the
		# bootstrap idea without out-grinding the hand-craft era it replaces.
		"cost": {"credits": 25000, "Ti": 50, "Circuit": 40, "SalvageData": 12},
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
	# v150 BAND ALIGNMENT (see ElementDB.AMMO_BAND_MIN_ZONE). This was the ONLY
	# band-honest ammo building in the game, and only by accident (its
	# ExoticMatter input is a Z7 drop). It is now honest ON PURPOSE, and unified
	# with its kinetic/explosive siblings: all three T3 plants share the shape
	# {Superalloy bulk, channel payload, VoidCrystal yield/20} on zone_7_access.
	# It previously sat on a different tech (exotic_metallurgy) with a different
	# input shape (ExoticMatter + QuantumCore) — the same asymmetry class the
	# owner has now hit twice. Magnitudes are scaled off heavy_ordnance_works'
	# rung by yield ratio (0.7/0.8), so this is a shape change, not a buff pass.
	"zero_point_cell_synthesizer": {
		"name": "Zero-Point Cell Synthesizer",
		"description": "+0.7 Cell T3 (-1.84 Superalloy, -0.7 Adv Circuit, -0.035 Void Crystal)",
		"cost": {"credits": 1000000, "QuantumCore": 10, "ExoticMatter": 20},
		"energy_gen": 0.0,
		"energy_cons": 25000.0, # zone_7_access
		"yield": {"CellT3": 0.7},
		"input": {"Superalloy": 1.84, "AdvCircuit": 0.7, "VoidCrystal": 0.035},
		"interval": 5.0,
		"research_req": "zone_7_access",
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
	# ═══ v150 AMMO BAND ALIGNMENT — the automation layer ═══════════════════════
	# This is where the band leaked WORST before v150, and it was measured:
	#   advanced_ballistics_plant sat on processing_tungsten (tier 2, cost Res1 10
	#   — Res1 drops from every ZONE 1 enemy), so a Zone 1 player could fully
	#   automate T2 kinetic ammo. high_energy_cell_plant (advanced_batteries) and
	#   guided_munitions_plant (advanced_rocketry) were the same story at Z2/Z3.
	#   heavy_ordnance_works and thermobaric_warhead_works sat on
	#   capital_ship_armament, whose cost_items include VoidArtifact — a ZONE 5
	#   drop — landing T3 ammo automation two full bands early.
	# Every T2/T3 plant's input list was also generic (Steel/Al/Si/Resin/U/
	# Superalloy); not one touched a zone material. Band-gating only the RECIPES
	# would have left automation untouched and the whole exercise decorative.
	#
	# TWO fixes, both required:
	#  1. Band catalyst in the input list at the SAME 1-per-20-rounds ratio the
	#     recipes use (input = yield / 20). This makes automation physically
	#     incapable of running ahead of the band. Starvation is safe: _apply_
	#     production sets can_produce = false when an input is short, so the
	#     building produces nothing AND consumes nothing that cycle — no stall,
	#     no crash. Sub-1.0 inputs accrue correctly through _in_carry, so a single
	#     VoidCrystal funds ~25 cycles of heavy_ordnance_works.
	#  2. req_tech retiered to the band's zone-access tech, so a player never sees
	#     a plant they can build but cannot feed. The thematic techs keep their
	#     place in the tree via `parent`; only the gate moved.
	# Missile plants draw HALF the catalyst per second, correctly — that is the
	# same demand-parity rule the v144 explosive ladder was tuned to.
	# T4 has NO ammo building on ANY channel, and that is INTENTIONAL: T4 is the
	# NG+/Z11+ hand-crafted tier. Do not "fix" the omission on one channel.
	"advanced_ballistics_plant": {
		"name": "Advanced Ballistics Plant",
		"description": "+3.1 Slug T2 (-3.1 Steel, -1.3 Al, -0.155 Rimeplate Scrap)",
		"cost": {"credits": 125000, "Steel": 100, "Al": 50},
		"energy_gen": 0.0,
		"energy_cons": 2500.0, # zone_4_access
		"yield": {"SlugT2": 3.1},
		"input": {"Steel": 3.1, "Al": 1.3, "RimeplateScrap": 0.155},
		"interval": 5.0,
		"research_req": "zone_4_access",
		"category": "industry"
	},
	"high_energy_cell_plant": {
		"name": "High-Energy Cell Plant",
		"description": "+3.1 Cell T2 (-1.9 Si, -1.3 Resin, -0.155 Rimeplate Scrap)",
		"cost": {"credits": 125000, "Si": 100, "Resin": 50},
		"energy_gen": 0.0,
		"energy_cons": 2500.0, # zone_4_access
		"yield": {"CellT2": 3.1},
		"input": {"Si": 1.9, "Resin": 1.3, "RimeplateScrap": 0.155},
		"interval": 5.0,
		"research_req": "zone_4_access",
		"category": "industry"
	},
	"heavy_ordnance_works": {
		"name": "Heavy Ordnance Works",
		"description": "+0.8 Slug T3 (-0.8 U, -2.1 Superalloy, -0.04 Void Crystal)",
		"cost": {"credits": 2500000, "Superalloy": 50, "U": 20},
		"energy_gen": 0.0,
		"energy_cons": 15000.0, # zone_7_access
		"yield": {"SlugT3": 0.8},
		"input": {"U": 0.8, "Superalloy": 2.1, "VoidCrystal": 0.04},
		"interval": 5.0,
		"research_req": "zone_7_access",
		"category": "industry"
	},

	# ===== EXPLOSIVE AMMO LADDER (v144) =====
	# Explosive had NO ammo building at ANY tier — a dropped feature, not a design
	# choice ("munitions_factory" was already referenced in
	# INFRA_ENG_SCALED_BUILDINGS with no entry behind it). That mattered because
	# explosive is the MANDATORY damage type at Z2/Z5/Z8 (v150 resist triangle:
	# the Z8 boss is explosive-weak -0.40 / energy-resisted 0.37, i.e. explosive
	# over resisted = x1.40 / x0.3414 = 4.1x), so a player routed onto the weak type
	# hand-crafted missiles forever while kinetic/energy players never paid that
	# tax — and an empty missile stack means the weapon does not fire at all.
	#
	# Rates are EXACTLY HALF the kinetic rung at every tier because explosive
	# fires at half the cadence (atk_interval 4.0s vs 2.0s). That is demand
	# PARITY, not a buff. Cost / energy / research shape mirror the kinetic
	# ladder rung-for-rung: T1 at a tier-1 combat tech, T2 at the tech that gates
	# the T2 recipe, T3 at capital_ship_armament.
	"munitions_factory": {
		"name": "Munitions Factory",
		"description": "+5 Missile T1 (-2.5 Fe, -1 C)",
		"cost": {"credits": 12500, "Fe": 100, "C": 50},
		"energy_gen": 0.0,
		"energy_cons": 50.0, # ordnance_101
		"yield": {"MissileT1": 5},
		"input": {"Fe": 2.5, "C": 1.0},
		"interval": 5.0,
		"research_req": "ordnance_101",
		"category": "industry"
	},
	"guided_munitions_plant": {
		"name": "Guided Munitions Plant",
		"description": "+1.55 Missile T2 (-1.55 Steel, -0.65 Al, -0.078 Rimeplate Scrap)",
		"cost": {"credits": 125000, "Steel": 100, "Al": 50},
		"energy_gen": 0.0,
		"energy_cons": 2500.0, # zone_4_access
		"yield": {"MissileT2": 1.55},
		"input": {"Steel": 1.55, "Al": 0.65, "RimeplateScrap": 0.078},
		"interval": 5.0,
		"research_req": "zone_4_access",
		"category": "industry"
	},
	"thermobaric_warhead_works": {
		"name": "Thermobaric Warhead Works",
		"description": "+0.4 Missile T3 (-0.4 Structural Component, -1.05 Superalloy, -0.02 Void Crystal)",
		"cost": {"credits": 2500000, "Superalloy": 50, "U": 20},
		"energy_gen": 0.0,
		"energy_cons": 15000.0, # zone_7_access
		"yield": {"MissileT3": 0.4},
		# v150: U -> StructuralComponent so the plant mirrors craft_missile_t3's
		# channel payload, matching the kinetic/energy rungs' recipe-mirroring.
		"input": {"StructuralComponent": 0.4, "Superalloy": 1.05, "VoidCrystal": 0.02},
		"interval": 5.0,
		"research_req": "zone_7_access",
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
	# ========== Phase C: MID-SPINE CONVERTERS (fill the hollow mid) ==========
	# Input->output converters mirroring the real processing recipes so infra
	# now DEEPENS the electronics/structural spine instead of skipping it.
	# Feeders for adv_circuit_foundry (below) + chip_fab; au_refinery is Au's
	# first infra source (deferred here from Phase A). NOT ore-throttled.
	"au_refinery": {
		"name": "Gold Refinery",
		"description": "+1.5 Au (-40 Dirt, -40 Water)",
		"cost": {"credits": 700000, "Steel": 1200, "Circuit": 80},
		"energy_gen": 0.0,
		"energy_cons": 1000.0,
		"yield": {"Au": 1.5},
		"input": {"Dirt": 40, "Water": 40},
		"interval": 5.0,
		"research_req": "industrial_electrolysis",
		"category": "industry"
	},
	"semiconductor_furnace": {
		"name": "Semiconductor Furnace",
		"description": "+1.5 Semiconductor (-3 Si, -1.5 Germanium)",
		"cost": {"credits": 950000, "Steel": 1500, "Circuit": 120},
		"energy_gen": 0.0,
		"energy_cons": 1400.0,
		"yield": {"Semiconductor": 1.5},
		"input": {"Si": 3, "Germanium": 1.5},
		"interval": 5.0,
		"research_req": "automation",
		"category": "industry"
	},
	"structural_press": {
		"name": "Structural Press",
		"description": "+1.0 StructuralComponent (-10 Fe, -5 Cu, -5 Si, -3 C, -2 Li)",
		"cost": {"credits": 1100000, "Steel": 2200, "Ti": 150, "Circuit": 120},
		"energy_gen": 0.0,
		"energy_cons": 1600.0,
		"yield": {"StructuralComponent": 1.0},
		"input": {"Fe": 10, "Cu": 5, "Si": 5, "C": 3, "Li": 2},
		"interval": 5.0,
		"research_req": "metallurgy_advanced",
		"category": "industry"
	},
	"chip_fab": {
		"name": "Chip Fabrication Line",
		"description": "+0.8 Chip (-1.6 Semiconductor, -0.8 Au, -4 N)",
		"cost": {"credits": 1500000, "Steel": 2500, "Superalloy": 100, "Circuit": 150},
		"energy_gen": 0.0,
		"energy_cons": 2400.0,
		"yield": {"Chip": 0.8},
		"input": {"Semiconductor": 1.6, "Au": 0.8, "N": 4},
		"interval": 5.0,
		"research_req": "automation",
		"category": "industry"
	},
	"adv_circuit_foundry": {
		"name": "Advanced Circuit Foundry",
		"description": "+1.2 AdvCircuit (-2.4 Semiconductor, -1.2 Au, -2.4 StructuralComponent)",
		"cost": {"credits": 2000000, "Steel": 3000, "Superalloy": 120, "Circuit": 200},
		"energy_gen": 0.0,
		"energy_cons": 3500.0,
		"yield": {"AdvCircuit": 1.2},
		"input": {"Semiconductor": 2.4, "Au": 1.2, "StructuralComponent": 2.4},
		"interval": 5.0,
		"research_req": "automation",
		"category": "industry"
	},

	# ========== CATEGORY: LOGISTICS ==========
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
# v131: integer economy — per-"bid|res" fractional remainder so infrastructure
# grants/consumes WHOLE units while preserving exact expected output (sub-1 yields
# ACCRUE instead of flooring to zero, so nothing is lost). Transient — rebuilt from
# play, not saved; losing <1 unit of carry across a reload is negligible.
var _out_carry: Dictionary = {}
var _in_carry: Dictionary = {}

# v120: building upkeep REMOVED. Grid energy availability (energy_efficiency)
# and per-recipe input materials are the only infrastructure sinks now.

# ── Infra ↔ Mastery feedback (player request) ───────────────────────────────
# A building that produces a material feeds that material's crafting/gathering
# Mastery, and that Mastery raises the building's output. The loop is BOUNDED
# and non-compounding by construction: infra XP is per production *cycle* (not
# per unit produced), and Mastery scales only YIELD (never the cycle interval),
# so higher output can't accelerate its own XP. Mastery itself lives in the
# processing/gathering managers (per recipe/action) and already persists across
# warp — nothing new to save here.
const INFRA_MASTERY_XP_FACTOR := 0.15       # one infra cycle = 15% of an active completion
const INFRA_MASTERY_EFF_PER_LEVEL := 0.002  # +0.2% building output per linked Mastery level
const INFRA_MASTERY_EFF_MAX := 0.20         # ceiling: +20% output at Mastery 100
var _mastery_link_cache: Dictionary = {}    # building_id -> {"mgr","id","symbol"} or {} (no link)

func _init():
	super._init("Infrastructure")

# v120: _apply_upkeep + _upkeep_efficiency_for removed with building upkeep.

func get_building_count(building_id: String) -> int:
	return buildings.get(building_id, 0)

func set_building_throttle(building_id: String, value: float):
	# v131: Overclock — a Boost-Card-unlocked building type can throttle up to 200%.
	var cap: float = 2.0 if get_overclock(building_id) >= 1 else 1.0
	building_throttles[building_id] = clamp(value, 0.0, cap)
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
func _dr_units(building_id: String, count: int) -> float:
	var knee := INFRA_PRIMITIVE_DR_KNEE if building_id in PRIMITIVE_EXTRACTORS else INFRA_DR_KNEE
	var tail := INFRA_PRIMITIVE_DR_TAIL if building_id in PRIMITIVE_EXTRACTORS else INFRA_DR_TAIL
	var dr: float
	if count <= knee:
		dr = float(count)
	else:
		var extra := float(count - knee)
		dr = float(knee) + extra / (1.0 + extra / float(tail))
	# v131: Overclock moved OFF the unit count and ONTO the throttle slider (a
	# Boost Card unlocks 0-200% per type). _dr_units is pure diminishing-returns
	# again; throttle applies the 200% boost, type-wide, over production AND energy.
	return dr

# ── v131: Infrastructure Overclock (Boost Cards) ────────────────────────────
# {building_id: 1} once unlocked. A Boost Card is a ONE-TIME unlock per building
# TYPE (consumed on install — a permanent sink) that raises that type's Efficiency
# throttle cap from 100% to 200%. The boost IS the throttle slider, so it applies
# TYPE-WIDE over both production and energy. Any value >= 1 means unlocked.
var overclocks: Dictionary = {}

func get_overclock(building_id: String) -> int:
	# v135a: ENG_5 (Building Overclock warp node) globally unlocks overclock on ALL
	# building types — the meta-prestige counterpart to the per-type Boost Card. The
	# 200% cap + quadratic input penalty + UI slider all route through here, so this
	# one gate propagates the whole feature.
	if GameState.warp_manager and GameState.warp_manager.is_node_purchased("ENG_5"):
		return 1
	return int(overclocks.get(building_id, 0))

# v131: Overclock input cost. OUTPUT scales linearly with throttle; INPUT scales
# QUADRATICALLY above 100% (Satisfactory-style) — a type at 200% doubles output but
# quadruples input. At/below 100% it stays linear (plain throttle).
func _overclock_input_mult(throttle: float) -> float:
	if throttle <= 1.0:
		return throttle
	return throttle * throttle

# Install one Boost Card from cargo — a ONE-TIME unlock that raises this building
# type's Efficiency cap to 200% (the slider then drives the boost). Returns {ok, msg}.
func install_boost_card(building_id: String) -> Dictionary:
	if not building_id in building_db:
		return {"ok": false, "msg": "Unknown building."}
	var count: int = int(buildings.get(building_id, 0))
	if count <= 0:
		return {"ok": false, "msg": "Build one first — a card unlocks overclock on an owned building type."}
	if int(overclocks.get(building_id, 0)) >= 1:
		return {"ok": false, "msg": "Overclock already unlocked for this building type."}
	if GameState.resources.get_element_amount("BoostCard") < 1:
		return {"ok": false, "msg": "No Boost Card in cargo — fabricate one in Engineering."}
	GameState.resources.remove_element("BoostCard", 1)
	overclocks[building_id] = 1
	activity_occurred.emit()
	boost_card_installed.emit(building_id)
	return {"ok": true, "msg": "Overclock unlocked — Efficiency can now go up to 200%."}

# P1.4: yield multiplier for raw ore extractors (gathering owns the ore tier).
func _ore_throttle(building_id: String) -> float:
	return INFRA_ORE_EXTRACTION_MULT if building_id in INFRA_ORE_EXTRACTORS else 1.0

# Resolve (and cache) which Mastery a building feeds: its highest-yield material
# routed to the processing recipe (industry) or gathering action (extraction)
# that makes the same symbol. {} = no link (power/buff buildings).
func get_building_mastery_link(building_id: String) -> Dictionary:
	if _mastery_link_cache.has(building_id):
		return _mastery_link_cache[building_id]
	# Don't cache until both source managers exist, or a startup miss freezes.
	if not (GameState.processing_manager and GameState.gathering_manager):
		return {}
	var link: Dictionary = _resolve_mastery_link(building_id)
	_mastery_link_cache[building_id] = link
	return link

func _resolve_mastery_link(building_id: String) -> Dictionary:
	var data: Dictionary = building_db.get(building_id, {})
	if data.is_empty(): return {}
	var yields: Dictionary = data.get("yield", {})
	if yields.is_empty(): return {}
	# Primary = highest-yield symbol (deterministic for multi-output buildings).
	var primary: String = ""
	var best: float = -1.0
	for sym in yields:
		var amt: float = float(yields[sym])
		if amt > best:
			best = amt
			primary = sym
	if primary == "": return {}
	var category: String = data.get("category", "")
	if category == "extraction":
		var aid: String = _gathering_action_for(primary)
		if aid != "": return {"mgr": "gathering", "id": aid, "symbol": primary}
		var rfx: String = _processing_recipe_for(primary)
		if rfx != "": return {"mgr": "processing", "id": rfx, "symbol": primary}
	else:
		var rid: String = _processing_recipe_for(primary)
		if rid != "": return {"mgr": "processing", "id": rid, "symbol": primary}
		var afx: String = _gathering_action_for(primary)
		if afx != "": return {"mgr": "gathering", "id": afx, "symbol": primary}
	return {}

func _processing_recipe_for(symbol: String) -> String:
	var pm = GameState.processing_manager
	if pm and pm.has_method("get_recipe_id_for_output"):
		return pm.get_recipe_id_for_output(symbol)
	return ""

func _gathering_action_for(symbol: String) -> String:
	var gm = GameState.gathering_manager
	if gm and gm.has_method("get_action_id_for_output"):
		return gm.get_action_id_for_output(symbol)
	return ""

func _linked_mastery_level(link: Dictionary) -> int:
	if link.is_empty(): return 0
	var mgr = GameState.processing_manager if link.get("mgr") == "processing" else GameState.gathering_manager
	if mgr and mgr.has_method("get_mastery_level"):
		return int(mgr.get_mastery_level(link.get("id", "")))
	return 0

# Bounded output multiplier from the linked Mastery (1.0 = no link / level 0).
func get_mastery_efficiency_mult(building_id: String) -> float:
	var link: Dictionary = get_building_mastery_link(building_id)
	if link.is_empty(): return 1.0
	var lvl: int = _linked_mastery_level(link)
	return 1.0 + min(float(lvl) * INFRA_MASTERY_EFF_PER_LEVEL, INFRA_MASTERY_EFF_MAX)

# UI helper for the building card: {"linked",[ "symbol","level","bonus_pct" ]}.
func get_building_mastery_info(building_id: String) -> Dictionary:
	var link: Dictionary = get_building_mastery_link(building_id)
	if link.is_empty():
		return {"linked": false}
	var lvl: int = _linked_mastery_level(link)
	var bonus: float = min(float(lvl) * INFRA_MASTERY_EFF_PER_LEVEL, INFRA_MASTERY_EFF_MAX)
	return {"linked": true, "symbol": link.get("symbol", ""), "level": lvl, "bonus_pct": bonus * 100.0}

# Award Mastery XP to the linked recipe/action (no-op if unlinked). One call per
# production cycle; `cycles` batches the offline catch-up.
func _award_infra_mastery_xp(building_id: String, cycles: float) -> void:
	if cycles <= 0.0: return
	var link: Dictionary = get_building_mastery_link(building_id)
	if link.is_empty(): return
	var mgr = GameState.processing_manager if link.get("mgr") == "processing" else GameState.gathering_manager
	if mgr and mgr.has_method("gain_mastery_xp"):
		mgr.gain_mastery_xp(link.get("id", ""), INFRA_MASTERY_XP_FACTOR * cycles)

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
	# Infra↔Mastery feedback: the produced material's Mastery raises output
	# (bounded). Shared by process_tick + offline so both stay consistent.
	base_qty *= get_mastery_efficiency_mult(building_id)
	# v122: Warp Tree ENG_S1 Resource Surge — +6% infra yield per level.
	if GameState.warp_manager:
		base_qty *= GameState.warp_manager.get_tree_infra_bonus()
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
				var qty = base_qty * _dr_units(bid, count) * total_yield_mult  # P0.2 DR
				
				# Apply Throttle
				var rate_per_min = (qty / eff_interval) * 60.0 * efficiency * throttle
				rates[res] = rates.get(res, 0.0) + rate_per_min
		
		# Consumptions
		if "input" in data:
			for res in data["input"]:
				var qty = float(data["input"][res]) * _dr_units(bid, count)  # P0.2 DR
				# Power generators consume at full speed? Maybe throttle should apply to them too now.
				# If user throttles a generator, they want less consumption.
				var consumption_eff = 1.0 if data.get("category") == "power" else efficiency
				
				# Apply Throttle to consumption — quadratic above 100% (v131 overclock cost).
				var rate_per_min = (qty / eff_interval) * 60.0 * consumption_eff * _overclock_input_mult(throttle)
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
			# v140: was recomputing eng_scale/ore_throttle/mastery by hand and so
			# silently MISSED the two multipliers get_effective_yield had gained —
			# research building_yield_mult and the Warp-tree ENG_S1 Resource Surge.
			# The card under-reported real output. Use the production truth directly.
			var base_qty = get_effective_yield(building_id, res)

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
	# v122 ENG_4 Industrial Memory: -20% infrastructure build cost (Warp Tree).
	var build_cost_mult: float = GameState.warp_manager.get_tree_build_cost_mult() if GameState.warp_manager else 1.0

	for res in data["cost"]:
		var base_cost = float(data["cost"][res])
		var total_mult = 0.0

		if res == "credits":
			total_mult = _get_total_scaling_credits(current_count, buy_qty)
		elif _is_resource_passively_produced(res):
			total_mult = _get_total_scaling_passive(current_count, buy_qty)
		else:
			total_mult = _get_total_scaling_non_passive(current_count, buy_qty)

		total_scaled_cost[res] = int(ceil(base_cost * total_mult * build_cost_mult))
			
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
				var needed = data["input"][res] * count * _overclock_input_mult(throttle) * (delta / eff_interval)
				if GameState.resources.get_element_amount(res) < needed:
					can_fuel = false
					break
			
			if can_fuel:
				# Consume Fuel
				for res in data["input"]:
					var qty = data["input"][res] * count * _overclock_input_mult(throttle) * (delta / eff_interval)
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
				production_timers[bid] += delta * energy_efficiency
				
				if production_timers[bid] >= eff_interval:
					# Check if building needs inputs
					var can_produce = true
					var throttle = get_building_throttle(bid)
					if throttle <= 0: can_produce = false
					
					if can_produce and "input" in data:
						for res in data["input"]:
							var qty_needed = data["input"][res] * _dr_units(bid, count) * _overclock_input_mult(throttle)  # P0.2 DR + v131 quadratic overclock cost
							if GameState.resources.get_element_amount(res) < qty_needed:
								can_produce = false
								break
					
					if can_produce:
						# Consume inputs if required
						if "input" in data:
							for res in data["input"]:
								var qty = data["input"][res] * _dr_units(bid, count) * _overclock_input_mult(throttle)  # P0.2 DR + v131 quadratic overclock cost
								# v131: integer economy — accrue fractional input, consume only WHOLE units.
								var _ikey: String = bid + "|" + res
								_in_carry[_ikey] = float(_in_carry.get(_ikey, 0.0)) + qty
								var _take: int = int(_in_carry[_ikey])
								if _take >= 1:
									GameState.resources.remove_element(res, _take)
									_in_carry[_ikey] -= _take
						
						# Production complete
						activity_occurred.emit()
						# Infra↔Mastery: one mastery tick per completed production cycle.
						_award_infra_mastery_xp(bid, 1.0)
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
							
							var _prod: float = qty * _dr_units(bid, count) * throttle * yield_mult  # P0.2 DR
							# v131: integer economy — accrue the fractional yield, grant only WHOLE units.
							var _okey: String = bid + "|" + res
							_out_carry[_okey] = float(_out_carry.get(_okey, 0.0)) + _prod
							var _give: int = int(_out_carry[_okey])
							if _give >= 1:
								GameState.resources.add_element(res, _give)
								GameState.note_production("infra", _give)  # P3.10
								_out_carry[_okey] -= _give
						
						# Statistical expectation (Audit v5.0 - O(1) Performance Foundation)
						if bid == "hydro_plant":
							if GameState.research_manager and GameState.research_manager.is_tech_unlocked("basic_engineering"):
								var expected = _dr_units(bid, count) * throttle * 0.2  # P0.2 DR
								var floor_exp = floor(expected)
								var extra = 1 if randf() < (expected - floor_exp) else 0
								GameState.resources.add_element("N", floor_exp + extra)
					
						if bid == "industrial_centrifuge":
							if GameState.research_manager and GameState.research_manager.is_tech_unlocked("advanced_mineralogy"):
								var expected = _dr_units(bid, count) * throttle * 0.2  # P0.2 DR
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
					GameState.resources.add_element("Cu", 1 * count); GameState.note_production("infra", count)  # P3.10

					production_timers[bid] = 0.0


func calculate_offline(delta: float):
	# Offline Industry
	# 1. Energy check (static)
	if net_energy < 0:
		# v112: structured offline block (was a formatted string).
		return {
			"category": "infrastructure", "title": "Infrastructure Grid", "action": "",
			"time_sec": int(delta), "actions": 0, "xp": 0,
			"gains": {}, "drains": {}, "status": "standby",
			"notes": ["Grid offline — negative energy."],
		}

	var loot_summary = {}

	# v132: online production applies yield_bonus buildings (global_yield_bonuses)
	# and the extractor_efficiency module affix — offline silently dropped both, so
	# synergy builds under-produced exactly while idle. Compute once, apply to
	# every yield total in BOTH passes below (same math as get_total_resource_rates).
	var _off_yield_bonuses := {}
	for _ob in buildings:
		var _od = building_db.get(_ob)
		if _od and _od.has("yield_bonus"):
			for _res in _od["yield_bonus"]:
				_off_yield_bonuses[_res] = _off_yield_bonuses.get(_res, 0.0) + (_od["yield_bonus"][_res] * buildings[_ob])
	var _off_affix_mult := 1.0
	if GameState.shipyard_manager:
		_off_affix_mult = 1.0 + GameState.shipyard_manager.affix_bonuses.get("extractor_efficiency", 0.0)

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
					var qty_per_cycle = data["input"][res] * _dr_units(bid, count)  # P0.2 DR
					var available = GameState.resources.get_element_amount(res)
					var possible = int(available / qty_per_cycle)
					max_cycles = min(max_cycles, possible)
				cycles = max_cycles
			
			if cycles > 0:
				if "input" in data:
					for res in data["input"]:
						GameState.resources.remove_element(res, floor(data["input"][res] * _dr_units(bid, count) * cycles))  # P0.2 DR + v131 integer
				for res in data["yield"]:
					var qty = get_effective_yield(bid, res)
					var total = floor(qty * _dr_units(bid, count) * cycles * (1.0 + _off_yield_bonuses.get(res, 0.0)) * _off_affix_mult)  # P0.2 DR + v131 integer + v132 online-parity bonuses
					GameState.resources.add_element(res, total); GameState.note_production("infra", total)  # P3.10
					loot_summary[res] = loot_summary.get(res, 0.0) + total
				_award_infra_mastery_xp(bid, float(cycles))

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
					var qty_per_cycle = data["input"][res] * _dr_units(bid, count)  # P0.2 DR
					var available = GameState.resources.get_element_amount(res)
					var possible = int(available / qty_per_cycle)
					max_cycles = min(max_cycles, possible)
				cycles = max_cycles
			
			if cycles > 0:
				# Consume inputs if required
				if "input" in data:
					for res in data["input"]:
						var qty = floor(data["input"][res] * _dr_units(bid, count) * cycles)  # P0.2 DR + v131 integer
						GameState.resources.remove_element(res, qty)
				
				# Produce outputs
				for res in data["yield"]:
					var qty = get_effective_yield(bid, res)
					var total = floor(qty * _dr_units(bid, count) * cycles * (1.0 + _off_yield_bonuses.get(res, 0.0)) * _off_affix_mult)  # P0.2 DR + v131 integer + v132 online-parity bonuses
					GameState.resources.add_element(res, total); GameState.note_production("infra", total)  # P3.10
					loot_summary[res] = loot_summary.get(res, 0.0) + total
				_award_infra_mastery_xp(bid, float(cycles))

	
	# v112: structured offline block (was a formatted string).
	var notes: Array = []

	if loot_summary.is_empty() and notes.is_empty():
		return null

	return {
		"category": "infrastructure",
		"title": "Infrastructure Grid",
		"action": "",
		"time_sec": int(delta),
		"actions": 0,
		"xp": 0,
		"gains": loot_summary.duplicate(),
		"drains": {},
		"notes": notes,
		"status": "active",
	}

func get_save_data_manager() -> Dictionary:
	var data = get_save_data()
	data["buildings"] = buildings
	data["building_throttles"] = building_throttles
	data["overclocks"] = overclocks.duplicate()  # v130: installed Boost Cards per building (copy — no aliasing)
	return data

func load_save_data_manager(data: Dictionary):
	load_save_data(data)
	if data.is_empty(): return

	buildings = data.get("buildings", {})
	building_throttles = data.get("building_throttles", {})
	overclocks = data.get("overclocks", {})  # v130: additive, pre-v130 saves default {}

	# Fix types if json loaded strings
	for k in buildings: buildings[k] = int(buildings[k])
	for k in overclocks: overclocks[k] = int(overclocks[k])
	for k in building_throttles: building_throttles[k] = float(building_throttles[k])
	
	recalc_energy()

func reset(decay_factor: float = 1.0) -> void:
	super.reset(decay_factor)
	# DESIGN (locked): buildings are RUN-state, not meta — they fully vanish on
	# every reset (warp AND hard reset), deliberately ignoring decay_factor, just
	# like materials/modules. You rebuild the infra layer each prestige (faster
	# each run via retained research + warp mults + the glut). This is NOT a
	# decay bug; do not "fix" it to persist. (Sanity checklist #10, confirmed.)
	buildings.clear()
	overclocks.clear()  # v130: installed cards are run-state, wiped with the buildings
	_out_carry.clear()   # v131: integer-economy remainders are run-state too
	_in_carry.clear()
	generation = 0.0
	consumption = 0.0
	net_energy = 0.0
	energy_efficiency = 1.0
	production_timers.clear()
	# Clear all per-building derived state too, so nothing points at a building
	# that no longer exists (stale throttles / mastery-link cache would
	# otherwise survive into the next run). Sanity checklist: "Hard reset clears
	# all infra state."
	building_throttles.clear()
	_mastery_link_cache.clear()
	grid_warning_sent = false
	recalc_energy()
