extends Skill

signal activity_occurred

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
		"description": "+5.0 kW",
		"cost": {"credits": 125, "Si": 5}, 
		"energy_gen": 5.0, # REBALANCE v23.0: Reduced from 10 to discourage low-tier spam
		"energy_cons": 0.0,
		"category": "power"
	},
	"fusion_reactor": {
		"name": "Fusion Core",
		"description": "+5000.0 kW",
		"cost": {"credits": 2500000, "Superalloy": 200, "AdvCircuit": 100, "VoidEssence": 20},
		"energy_gen": 5000.0, # REBALANCE v23.0: Buffed from 1500 for endgame density
		"energy_cons": 0.0,
		"research_req": "quantum_dynamics",
		"category": "power"
	},
	"coal_burner": {
		"name": "Carbon Generator",
		"description": "+50.0 kW (-1 C)",
		"cost": {"credits": 375, "Fe": 10},
		"energy_gen": 50.0, 
		"energy_cons": 0.0,
		"input": {"C": 1},
		"interval": 10.0,
		"research_req": "combustion",
		"category": "power"
	},
	"auto_excavator": {
		"name": "Auto-Excavator (XL)",
		"description": "+10 Dirt",
		"cost": {"credits": 1250, "Si": 50, "Fe": 20},
		"energy_gen": 0.0,
		"energy_cons": 15.0,  # Audit v1.0: Reduced from 20 for better early-game energy balance
		"yield": {"Dirt": 10},
		"interval": 5.0,
		"category": "extraction"
	},
	"industrial_pump": {
		"name": "Industrial Pump",
		"description": "+10 Water",
		"cost": {"credits": 1250, "Si": 20, "Fe": 50}, 
		"energy_gen": 0.0,
		"energy_cons": 25.0,
		"yield": {"Water": 10},
		"interval": 5.0,
		"category": "extraction"
	},
	"drone_bay": {
		"name": "Drone Recovery Bay",
		"description": "+Scrap (Zone Scavenging)",
		"cost": {"credits": 5000, "Circuit": 10, "Ti": 20},
		"energy_gen": 0.0,
		"energy_cons": 50.0,
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
		"energy_cons": 100.0,
		"max": 1,
		"research_req": "molecular_printing",
		"special": "craft_buff",
		"category": "industry"
	},
	"auto_smelter": {
		"name": "Automated Smelter",
		"description": "+2 Steel",
		"cost": {"credits": 6250, "Ti": 20, "Circuit": 5},
		"energy_gen": 0.0,
		"energy_cons": 50.0,
		"yield": {"Steel": 2},
		"input": {"Fe": 2, "C": 1, "O": 2},
		"interval": 4.0,
		"research_req": "automated_smelting",
		"category": "industry"
	},
	"hydro_plant": {
		"name": "Industrial Electrolysis Plant",
		"description": "+2 H, +1 O (-1 Water)",
		"cost": {"credits": 6250, "Si": 50, "Circuit": 10},
		"energy_gen": 0.0,
		"energy_cons": 40.0,
		"yield": {"H": 2, "O": 1},
		"input": {"Water": 1},
		"interval": 2.0,
		"research_req": "industrial_electrolysis",
		"category": "industry"
	},
	"nitrogen_tank": {
		"name": "Cryo-Storage Array",
		"description": "+10% Nitrogen Yield",
		"cost": {"credits": 12500, "Ti": 100, "Circuit": 25},
		"energy_gen": 0.0,
		"energy_cons": 20.0,
		"yield_bonus": {"N": 0.10},
		"research_req": "cryogenic_storage",
		"category": "logistics"
	},
	"matter_deconstructor": {
		"name": "Matter De-constructor",
		"description": "+1 Circuit",
		"cost": {"credits": 250000, "Ti": 1000, "AdvCircuit": 50},
		"energy_gen": 0.0,
		"energy_cons": 250.0,
		"input": {"Scrap": 5000},  # Audit v38.0: Reduced from 10K for usability
		"yield": {"Circuit": 1, "Superalloy": 0.2},  # Scaled proportionally
		"interval": 10.0,
		"research_req": "molecular_recycling",
		"category": "industry"
	},
	"auto_press": {
		"name": "Automated Carbon Press",
		"description": "+1 Graphite",
		"cost": {"credits": 7500, "Fe": 100, "Hydraulics": 5},
		"energy_gen": 0.0,
		"energy_cons": 60.0,
		"yield": {"Graphite": 1},
		"input": {"C": 5},
		"interval": 6.0,
		"research_req": "molecular_compression",
		"category": "industry"
	},
	"basic_kinetic_foundry": {
		"name": "Basic Kinetic Foundry",
		"description": "+10 Slug T1",
		"cost": {"credits": 12500, "Fe": 100, "Si": 50},
		"energy_gen": 0.0,
		"energy_cons": 40.0,
		"yield": {"SlugT1": 10},
		"input": {"Fe": 5},
		"interval": 5.0,
		"research_req": "kinetics_101",
		"category": "industry"
	},
	"basic_cell_factory": {
		"name": "Basic Cell Factory",
		"description": "+10 Cell T1",
		"cost": {"credits": 12500, "Si": 100, "Cu": 20},
		"energy_gen": 0.0,
		"energy_cons": 40.0,
		"yield": {"CellT1": 10},
		"input": {"Si": 5},
		"interval": 5.0,
		"research_req": "power_systems",
		"category": "industry"
	},
	"advanced_ballistics_plant": {
		"name": "Advanced Ballistics Plant",
		"description": "+5 Slug T2",
		"cost": {"credits": 125000, "Steel": 100, "Al": 50},
		"energy_gen": 0.0,
		"energy_cons": 100.0,
		"yield": {"SlugT2": 5},
		"input": {"Steel": 5, "Al": 2},
		"interval": 8.0,
		"research_req": "processing_tungsten",
		"category": "industry"
	},
	"high_energy_cell_plant": {
		"name": "High-Energy Cell Plant",
		"description": "+5 Cell T2",
		"cost": {"credits": 125000, "Si": 100, "Resin": 50},
		"energy_gen": 0.0,
		"energy_cons": 100.0,
		"yield": {"CellT2": 5},
		"input": {"Si": 3, "Resin": 2},
		"interval": 8.0,
		"research_req": "advanced_batteries",
		"category": "industry"
	},
	"heavy_ordnance_works": {
		"name": "Heavy Ordnance Works",
		"description": "+2 Slug T3",
		"cost": {"credits": 2500000, "Superalloy": 50, "U": 20},
		"energy_gen": 0.0,
		"energy_cons": 250.0,
		"yield": {"SlugT3": 2},
		"input": {"U": 2, "Superalloy": 5},
		"interval": 12.0,
		"research_req": "capital_ship_armament",
		"category": "industry"
	},
	"zero_point_cell_synthesizer": {
		"name": "Zero-Point Cell Synthesizer",
		"description": "+2 Cell T3",
		"cost": {"credits": 1000000, "QuantumCore": 10, "ExoticMatter": 20},
		"energy_gen": 0.0,
		"energy_cons": 500.0,
		"yield": {"CellT3": 2},
		"input": {"ExoticMatter": 2, "QuantumCore": 2},
		"interval": 15.0,
		"research_req": "exotic_metallurgy",
		"category": "industry"
	},
	"repair_docks": {
		"name": "Fleet Repair Docks",
		"description": "-10% Repair Cost",
		"cost": {"credits": 100000, "AdvCircuit": 20, "Steel": 100},
		"energy_gen": 0.0,
		"energy_cons": 60.0,
		"max": 10, # Cap at 10 for 100% reduction potential? Or additive/multiplicative check later.
		"research_req": "fleet_logistics_1",
		"category": "logistics"
	},
	"catalyst_chamber": {
		"name": "Platinum Catalyst Chamber",
		"description": "+25% Processing Speed",
		"cost": {"credits": 500000, "PtCatalyst": 5, "AdvCircuit": 30, "Superalloy": 20},
		"energy_gen": 0.0,
		"energy_cons": 150.0,
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
		"energy_cons": 80.0,
		"max": 1,
		"research_req": "industrial_catalysis",
		"special": "global_catalyst",
		"category": "logistics"
	},
	"palladium_generator": {
		"name": "Palladium Fuel Cell Generator",
		"description": "+350.0 kW",
		"cost": {"credits": 250000, "PdFuelCell": 20, "Circuit": 40},
		"energy_gen": 350.0,  # Audit v38.0: Buffed from 200 to be viable vs H Reactor
		"energy_cons": 0.0,
		"input": {"H": 1},  # Consumes 1 H per cycle
		"interval": 10.0,
		"research_req": "fuel_cell_tech",
		"category": "power"
	},
	"hydrogen_reactor": {
		"name": "Hydrogen Reactor",
		"description": "+500.0 kW",
		"cost": {"credits": 50000, "Steel": 200, "Circuit": 50, "NavData": 5},
		"energy_gen": 500.0, # REBALANCE v23.0: Buffed from 100 for mid-game density
		"energy_cons": 0.0,
		"input": {"H": 10}, # REBALANCE v23.0: Increased from 5
		"interval": 10.0,
		"research_req": "energy_metrics",
		"category": "power"
	},
	"industrial_centrifuge": {
		"name": "Industrial Centrifuge",
		"description": "+3 Fe, +1 Si (-5 Dirt, -5 Water)",
		"cost": {"credits": 25000, "Steel": 100, "Si": 20, "DroneCore": 10},
		"energy_gen": 0.0,
		"energy_cons": 45.0,
		"yield": {"Fe": 3, "Si": 1},
		"input": {"Dirt": 5, "Water": 5},
		"interval": 3.0,
		"research_req": "automated_logistics",
		"category": "extraction"
	},
	"electronics_assembler": {
		"name": "Electronics Assembler",
		"description": "+2 Circuit",
		"cost": {"credits": 25000, "Ti": 50, "Circuit": 100, "SalvageData": 20},
		"energy_gen": 0.0,
		"energy_cons": 120.0,
		"yield": {"Circuit": 2},
		"input": {"Si": 4, "Cu": 4, "Resin": 2}, # Audit v18.0: Industrial Input (No DroneCore)
		"interval": 8.0,
		# "max": 1, # Audit v19.0: Removed max cap to allow infinite scaling for late game
		"research_req": "industrial_automation",
		"category": "industry"
	},
	# ITER2 P1: Dead Resource Sinks
	"hydroponics_bay": {
		"name": "Hydroponics Bay",
		"description": "+3 O, +1 Food (-10 Water)",
		"cost": {"credits": 10000, "Steel": 50, "Si": 30, "Resin": 10},
		"energy_gen": 0.0,
		"energy_cons": 30.0,
		"yield": {"O": 3, "Food": 1},
		"input": {"Water": 10},
		"interval": 5.0,
		"research_req": "fluid_dynamics",
		"category": "extraction"
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
	"composite_loom": {
		"name": "Composite Loom",
		"description": "+1 Composite Weave",
		"cost": {"credits": 15000, "Steel": 75, "Fiber": 20},
		"energy_gen": 0.0,
		"energy_cons": 40.0,
		"yield": {"CompositeWeave": 1},
		"input": {"Fiber": 10, "Resin": 2},
		"interval": 8.0,
		"research_req": "adv_materials",
		"category": "industry"
	},
	# ITER5 FIX: Food/FertileSoil uses
	"crew_quarters": {
		"name": "Crew Quarters",
		"description": "+10% XP Gain",
		"cost": {"credits": 25000, "Steel": 100, "Circuit": 20},
		"energy_gen": 0.0,
		"energy_cons": 20.0,
		"input": {"Food": 1},
		"interval": 30.0,
		"max": 3,
		"research_req": "industrial_logistics",
		"special": "xp_buff",
		"category": "logistics"
	},
	"biosphere_dome": {
		"name": "Biosphere Dome",
		"description": "+5% Gather Speed",
		"cost": {"credits": 30000, "Steel": 150, "Si": 50, "FertileSoil": 10},
		"energy_gen": 0.0,
		"energy_cons": 15.0,
		"max": 5,
		"research_req": "industrial_logistics",
		"special": "gather_speed_buff",
		"category": "logistics"
	},
	"repair_gantry": {
		"name": "Automated Repair Gantry",
		"description": "+Passive Ship Repair",
		"cost": {"credits": 250000, "AdvCircuit": 50, "Superalloy": 50},
		"energy_gen": 0.0,
		"energy_cons": 200.0,
		"max": 5,
		"research_req": "fleet_logistics_2",
		"category": "logistics"
	},
	# ========== AUDIT v21.0: EXTRACTION EXPANSION ==========
	"brine_extractor": {
		"name": "Lithium Brine Well",
		"description": "+2 Spodumene",
		"cost": {"credits": 2500, "Si": 100, "Steel": 50},
		"energy_gen": 0.0,
		"energy_cons": 35.0,
		"yield": {"Spodumene": 2},
		"interval": 6.0,
		"research_req": "basic_engineering",
		"category": "extraction"
	},
	"deep_crust_drill": {
		"name": "Deep-Crust Drill",
		"description": "+2 Malachite",
		"cost": {"credits": 2500, "Si": 50, "Steel": 100},
		"energy_gen": 0.0,
		"energy_cons": 40.0,
		"yield": {"Malachite": 2},
		"interval": 6.0,
		"research_req": "basic_engineering",
		"category": "extraction"
	},
	"bauxite_miner": {
		"name": "Bauxite Strip Miner",
		"description": "+4 Bauxite",
		"cost": {"credits": 10000, "Steel": 250, "Hydraulics": 10},
		"energy_gen": 0.0,
		"energy_cons": 60.0,
		"yield": {"Bauxite": 4},
		"interval": 8.0,
		"research_req": "adv_materials",
		"category": "extraction"
	},
	"quartz_excavator": {
		"name": "Quartz Resonator",
		"description": "+4 Quartz",
		"cost": {"credits": 12000, "Ti": 100, "Circuit": 20},
		"energy_gen": 0.0,
		"energy_cons": 75.0,
		"yield": {"Quartz": 4},
		"interval": 8.0,
		"research_req": "adv_materials",
		"category": "extraction"
	},
	"orbital_siphon": {
		"name": "Orbital Gas Siphon",
		"description": "+2 H, +1 He, +1 N",
		"cost": {"credits": 50000, "Ti": 200, "AdvCircuit": 10},
		"energy_gen": 0.0,
		"energy_cons": 150.0,
		"yield": {"H": 2, "He": 1, "N": 1},
		"interval": 5.0,
		"research_req": "energy_metrics",
		"category": "extraction"
	},
	"precious_dredge": {
		"name": "Precious Metal Dredge",
		"description": "+2 Pt, +1 Ir",
		"cost": {"credits": 150000, "Superalloy": 50, "AdvCircuit": 25},
		"energy_gen": 0.0,
		"energy_cons": 300.0,
		"yield": {"PtOre": 2, "Ir": 1},
		"interval": 10.0,
		"research_req": "precious_metal_refining",
		"category": "extraction"
	},
	"void_anchor": {
		"name": "Void Rift Anchor",
		"description": "+2 Void Essence",
		"cost": {"credits": 5000000, "Superalloy": 500, "QuantumCore": 10},
		"energy_gen": 0.0,
		"energy_cons": 1000.0,
		"yield": {"VoidEssence": 2},
		"interval": 15.0,
		"research_req": "void_navigation",
		"category": "extraction"
	},
	"chrono_siphon": {
		"name": "Chrono-Siphon",
		"description": "+1 Chrono Core",
		"cost": {"credits": 25000000, "Superalloy": 1000, "AntimatterFuel": 10},
		"energy_gen": 0.0,
		"energy_cons": 2500.0,
		"yield": {"ChronoCore": 1},
		"interval": 30.0,
		"research_req": "void_navigation",
		"category": "extraction"
	},
	# ========== AUDIT v24.0: INDUSTRIAL COMPLETION ==========
	"uranium_centrifuge": {
		"name": "Uranium Isotope Centrifuge",
		"description": "+2 Uranium",
		"cost": {"credits": 50000, "Steel": 500, "Si": 250, "AdvCircuit": 5},
		"energy_gen": 0.0,
		"energy_cons": 150.0,
		"yield": {"U": 2},
		"interval": 10.0,
		"research_req": "energy_metrics",
		"category": "extraction"
	},
	"tungsten_drill": {
		"name": "Heavy Tungsten Drill",
		"description": "+4 Tungsten",
		"cost": {"credits": 45000, "Ti": 300, "Steel": 500, "Hydraulics": 15},
		"energy_gen": 0.0,
		"energy_cons": 120.0,
		"yield": {"W": 4},
		"interval": 10.0,
		"research_req": "smelting",  # Audit v38.0: Changed from adv_materials for earlier T2 ammo access
		"category": "extraction"
	},
	"void_crystallizer": {
		"name": "Void Crystallizer",
		"description": "+2 Void Crystal (-5 Essence)",
		"cost": {"credits": 10000000, "Superalloy": 1000, "QuantumCore": 25},
		"energy_gen": 0.0,
		"energy_cons": 2000.0,
		"input": {"VoidEssence": 5},
		"yield": {"VoidCrystal": 2},
		"interval": 20.0,
		"research_req": "void_navigation",
		"category": "industry"
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
			var qty = base_qty * total_yield_mult * warp_mult * skill_yield_mult
			results["yield"][res] = (qty / interval) * 60.0 * efficiency
			
	if "input" in data:
		for res in data["input"]:
			var qty = float(data["input"][res])
			results["input"][res] = (qty / interval) * 60.0 * efficiency
			
	return results

func get_building_cost(building_id: String) -> Dictionary:
	"""Calculates exponential cost scaling: Base * (1.15 ^ current_count)"""
	if not building_id in building_db: return {}
	
	var data = building_db[building_id]
	var count = get_building_count(building_id)
	var multiplier = pow(1.15, float(count))
	
	var scaled_cost = {}
	for res in data["cost"]:
		scaled_cost[res] = int(data["cost"][res] * multiplier)
		
	return scaled_cost

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
		buildings[building_id] = count + 1
		recalc_energy()
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
	
	# Phase 6: Ship Reactor Link (Ship Gen adds to Grid, Load does NOT drain Grid)
	if GameState.shipyard_manager:
		gen += GameState.shipyard_manager.ship_energy_gen # Reactors power the base
		# cons += GameState.shipyard_manager.energy_used # REMOVED: Gun Tax (Passive Drain)
	
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
					
					# Audit v8.0: Passive Scrap Logic
					# Always generate 1 Scrap per 10s per Drone Bay
					GameState.resources.add_element("Scrap", 1 * count)
					
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
