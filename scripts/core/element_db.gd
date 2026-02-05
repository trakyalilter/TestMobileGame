extends Node

## Element Display Names Database
## Maps chemical symbols to full names for UI display

var ELEMENT_NAMES = {
	# Basic Elements
	"H": "Hydrogen",
	"He": "Helium",
	"C": "Carbon",
	"O": "Oxygen",
	"Si": "Silicon",
	"S": "Sulfur",
	
	# Common Metals
	"Fe": "Iron",
	"Cu": "Copper",
	"Al": "Aluminum",
	"Mg": "Magnesium",
	"Zn": "Zinc",
	"Sn": "Tin",
	
	# Industrial Metals
	"Ti": "Titanium",
	"Co": "Cobalt",
	"Ni": "Nickel",
	"Cr": "Chromium",
	"Mn": "Manganese",
	"W": "Tungsten",
	
	# Precious/Rare Metals
	"Au": "Gold",
	"Ag": "Silver",
	"Pt": "Platinum",
	"Pd": "Palladium",
	"Ir": "Iridium",
	"Os": "Osmium",
	"Rh": "Rhodium",
	
	# Radioactive
	"U": "Uranium",
	
	# Special Materials
	"Li": "Lithium",
	
	# Processed Materials
	"Steel": "Steel",
	"Bronze": "Bronze",
	"Graphite": "Graphite",
	"StainlessSteel": "Stainless Steel",
	"GalvanizedSteel": "Galvanized Steel",
	"Superalloy": "Superalloy",
	"AlMgAlloy": "Aluminum-Magnesium Alloy",
	"IrWAlloy": "Iridium-Tungsten Alloy",
	
	# Ores
	"Dirt": "Dirt",
	"Bauxite": "Bauxite Ore",
	"Dolomite": "Dolomite",
	"Cassiterite": "Tin Ore",
	"ZincOre": "Zinc Ore",
	"Spodumene": "Lithium Ore",
	"PtOre": "Platinum Ore",
	
	# Components
	"Circuit": "Circuit Board",
	"AdvCircuit": "Advanced Circuit",
	"Chip": "Microchip",
	"Hydraulics": "Hydraulic System",
	"AlWire": "Aluminum Wiring",
	
	# Batteries
	"BatteryT1": "Basic Battery",
	"BatteryT2": "Improved Battery",
	"BatteryT3": "Zero-Point Battery",
	"CoBattery": "Cobalt-Lithium Battery",
	"MgBattery": "Magnesium-Ion Battery",
	"PdFuelCell": "Palladium Fuel Cell",
	"PtCatalyst": "Platinum Catalyst",
	
	# Consumables
	"Mesh": "Nanoweave Mesh",
	"Seal": "Hull Sealant",
	"EmergencyPatch": "Emergency Patch",   # Audit v3.0
	"BasicBooster": "Shield Booster",       # Audit v3.0
	"Resin": "Polymer Resin",
	"Fiber": "Carbon Fiber",
	
	# Ammo
	"SlugT1": "Ferrite Rounds",
	"SlugT2": "Tungsten Sabot",
	"SlugT3": "Depleted Uranium Rounds",
	"CellT1": "Focus Crystal",
	"CellT2": "Plasma Cell",
	"CellT3": "Vaporizer Cell",
	
	# Special/Exotic
	"VoidArtifact": "Void Artifact",
	"QuantumCore": "Quantum Core",
	"ExoticMatter": "Exotic Matter",
	"VoidCrystal": "Void Crystal",
	"Diamond": "Diamond",
	"SyntheticCrystal": "Synthetic Crystal",
	"Neutronium": "Neutronium",
	"AntimatterParticle": "Antimatter Particle",
	"ExoticIsotope": "Exotic Isotope",
	"ReactiveCore": "Reactive Core",
	"AICore": "AI Core",
	"AncientTech": "Ancient Technology",
	
	# Other
	"Wood": "Wood",
	"Water": "Water",
	"NavData": "Navigation Data",
	"IrPlate": "Iridium Plating",
	"OsCore": "Osmium Core",
	
	# Combat Loot & Artifacts
	"Scrap": "Recycled Scrap",
	"MiteChitin": "Mite Chitin",
	"ChitinPatch": "Chitin Hull Patch",
	"DroneCore": "Drone Core",
	"SalvageData": "Salvage Data",
	"StolenCargo": "Stolen Cargo",
	"SwarmFragment": "Swarm Fragment",
	"PirateManifest": "Pirate Manifest",
	"ColonySalvage": "Colony Salvage",
	"TurretCore": "Turret Core",
	"ColonyDataCore": "Colony Data Core",
	"RadIsotope": "Radiation Isotope",
	"CryoCell": "Cryogenic Cell",
	"NitroCoolant": "Liquid Nitrogen Coolant",
	
	# New Research Artifacts
	"Res1": "Common Artifact",
	"Res2": "Rare Artifact",
	"Res3": "Exotic Artifact",
	
	# Iter2 Dead Resource Sink Outputs
	"Food": "Hydroponic Food",
	"FertileSoil": "Fertile Soil",
	"CompositeWeave": "Composite Weave",
	"N": "Nitrogen",
	
	# Sector Epsilon Endgame Resources
	"VoidEssence": "Void Essence",
	"ChronoCore": "Chrono Core",
	"OmegaPlating": "Omega Plating",
	"PrimordialShard": "Primordial Shard",
	
	# P1-12: Endgame Crafted Items
	"VoidBattery": "Void Battery",
	"TemporalModule": "Temporal Stabilizer",
	"PrimordialArmor": "Primordial Armor",
	"OmegaAccelerator": "Omega Accelerator"
}

## Category mappings for inventory filtering
var CATEGORIES = {
	"ores": ["Dirt", "Bauxite", "Dolomite", "Cassiterite", "ZincOre", "Spodumene", "PtOre"],
	"basic_metals": ["Fe", "Cu", "Al", "Mg", "Sn", "Zn"],
	"advanced_metals": ["Ti", "Co", "Ni", "Cr", "Mn", "W"],
	"rare_metals": ["Au", "Ag", "Pt", "Pd", "Ir", "Os", "Rh", "U"],
	"alloys": ["Steel", "Bronze", "Graphite", "StainlessSteel", "GalvanizedSteel", "Superalloy", "AlMgAlloy", "IrWAlloy"],
	"components": ["Circuit", "AdvCircuit", "Chip", "Hydraulics", "AlWire", "Resin", "Fiber"],
	"batteries": ["BatteryT1", "BatteryT2", "BatteryT3", "CoBattery", "MgBattery", "PdFuelCell"],
	"consumables": ["Mesh", "Seal", "EmergencyPatch", "BasicBooster", "ChitinPatch", "NitroCoolant"],  # Audit v2.0: Early/Mid consumables
	"ammo": ["SlugT1", "SlugT2", "SlugT3", "CellT1", "CellT2", "CellT3"],
	"special": ["VoidArtifact", "QuantumCore", "ExoticMatter", "VoidCrystal", "Diamond", "SyntheticCrystal", 
				"Neutronium", "AntimatterParticle", "ExoticIsotope", "ReactiveCore", "AICore", "AncientTech",
				"NavData", "IrPlate", "OsCore", "PtCatalyst",
				"Res1", "Res2", "Res3",
				"Scrap", "MiteChitin", "DroneCore", "SalvageData", "StolenCargo", 
				"SwarmFragment", "PirateManifest", "ColonySalvage", "TurretCore", 
				"ColonyDataCore", "RadIsotope", "CryoCell"],
	"basic": ["H", "He", "C", "O", "Si", "S", "Li", "Wood", "Water", "N", "Food", "FertileSoil", "CompositeWeave"],
	# Audit v4.0: Endgame category for ultimate items
	"endgame": ["VoidEssence", "ChronoCore", "OmegaPlating", "PrimordialShard", 
				"VoidBattery", "TemporalModule", "PrimordialArmor", "OmegaAccelerator"]
}

## Get display name for an element
func get_display_name(symbol: String) -> String:
	return ELEMENT_NAMES.get(symbol, symbol)

## Get display name with symbol in parentheses
func get_full_display(symbol: String) -> String:
	var name = get_display_name(symbol)
	if name != symbol and symbol.length() <= 4:  # Extended to 4 for things like Ni, Au, etc.
		return "%s (%s)" % [name, symbol]
	return name

## Get category for an element
func get_category(symbol: String) -> String:
	for cat in CATEGORIES:
		if symbol in CATEGORIES[cat]:
			return cat
	return "other"

## Get all elements in a category
func get_elements_in_category(category: String) -> Array:
	return CATEGORIES.get(category, [])
