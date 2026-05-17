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
	"Sn": "Tin",  # Audit v50.0
	
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
	"Germanium": "Germanium",
	
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
	"Quartz": "Quartz Crystal",  # Audit v50.0
	"Pentlandite": "Pentlandite Ore",  # Audit v50.0
	"Chromite": "Chromite Ore",  # Audit v50.0
	"Germanit": "Germanite Mineral",
	
	# Components
	"Circuit": "Circuit Board",
	"AdvCircuit": "Advanced Circuit",
	"Chip": "Microchip",
	"Hydraulics": "Hydraulic System",
	"AlWire": "Aluminum Wiring",
	"LaserSight": "Laser Sight",  # Audit v51.0
	
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
	"CapacitorShard": "Capacitor Shard",
	"IonField": "Ion Field Projector",
	"ZeroPoint": "Zero-Point Injector",
	
	# Ammo
	"SlugT1": "Ferrite Rounds",
	"SlugT1S": "Heavy Steel Slugs",
	"SlugT2": "Tungsten Sabot",
	"SlugT3": "Depleted Uranium Rounds",
	"SlugT4": "Hyper-Velocity Slug",
	"CellT1": "Focus Crystal",
	"CellT2": "Plasma Cell",
	"CellT3": "Vaporizer Cell",
	"CellT4": "Heavy Plasma Cell",
	"MissileT1": "HE Missile",
	"MissileT2": "Seeker Missile",
	"MissileT3": "Heavy Missile",
	"MissileT4": "Photon Torpedo",
	
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
	"MiteChitin": "Mite Chitin",
	"ChitinPatch": "Chitin Hull Patch",
	"DroneCore": "Drone Core",
	"SalvageData": "Salvage Data",
	"StolenCargo": "Stolen Cargo",
	"SwarmFragment": "Swarm Fragment",
	"PirateManifest": "Pirate Manifest",
	"PirateSalvage": "Pirate Salvage",
	"MartianRelics": "Martian Relics",
	"CryoEssence": "Cryo Essence",
	"XenoFragment": "Xeno Fragment",
	"ColonySalvage": "Colony Salvage",
	"TurretCore": "Turret Core",
	"ColonyDataCore": "Colony Data Core",
	"TitanClearance": "Titan Clearance",

	"CryoCell": "Cryogenic Cell",
	"NitroCoolant": "Cryo-Shield Matrix",
	"RadIsotope": "Radioactive Isotope",  # Audit v50.0
	"nanite_swarm": "Nanite Repair Swarm",  # Audit v50.0
	
	# v57.0: Sector Zeta & Late Sector Loot
	"BiohazardSample": "Biohazard Sample",
	"PathogenCore": "Pathogen Core",
	"MutatedTissue": "Mutated Tissue",
	"AIMatrix": "AI Matrix",
	"QuarantineClearance": "Quarantine Clearance",
	"BioWeaponCoating": "Biological Weapon Coating",
	"AIProcessor": "AI Processor Array",
	"RegenPlating": "Regenerative Hull Plating",
	"PurifiedCompound": "Purified Compound",
	
	# New Research Artifacts
	"Res1": "Common Artifact",
	"Res2": "Rare Artifact",
	"Res3": "Exotic Artifact",
	
	# Iter2 Dead Resource Sink Outputs
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
	"OmegaAccelerator": "Omega Accelerator",
	
	# Boss Cores
	"Z1_Core": "Lunar Core",
	"Z2_Core": "Asteroid Core",
	"Z3_Core": "Debris Core",
	"Z4_Core": "Cryofield Core",
	"Z5_Core": "Alpha Core",
	"Z6_Core": "Beta Core",
	"Z7_Core": "Gamma Core",
	"Z8_Core": "Delta Core",
	"Z9_Core": "Epsilon Core",
	"Z10_Core": "Omega Core"
}

## Category mappings for inventory filtering
var CATEGORIES = {
	"ores": ["Dirt", "Bauxite", "Dolomite", "Cassiterite", "ZincOre", "Spodumene", "PtOre", "Germanit"],
	"basic_metals": ["Fe", "Cu", "Al", "Mg", "Sn", "Zn"],
	"advanced_metals": ["Ti", "Co", "Ni", "Cr", "Mn", "W"],
	"rare_metals": ["Au", "Ag", "Pt", "Pd", "Ir", "Os", "Rh", "U", "Germanium"],
	"alloys": ["Steel", "Bronze", "Graphite", "StainlessSteel", "GalvanizedSteel", "Superalloy", "AlMgAlloy", "IrWAlloy"],
	"components": ["Circuit", "AdvCircuit", "Chip", "Hydraulics", "AlWire", "Resin", "Fiber"],
	"batteries": ["BatteryT1", "BatteryT2", "BatteryT3", "CoBattery", "MgBattery", "PdFuelCell"],
	"consumables": ["Mesh", "Seal", "EmergencyPatch", "BasicBooster", "ChitinPatch", "NitroCoolant", "AdvMaintenanceKit", "CapacitorShard", "IonField", "ZeroPoint"],  # Audit v2.0: Early/Mid consumables
	"ammo": ["SlugT1", "SlugT1S", "SlugT2", "SlugT3", "SlugT4", "CellT1", "CellT2", "CellT3", "CellT4", "MissileT1", "MissileT2", "MissileT3", "MissileT4"],
	"special": ["VoidArtifact", "QuantumCore", "ExoticMatter", "VoidCrystal", "Diamond", "SyntheticCrystal", 
				"Neutronium", "AntimatterParticle", "ExoticIsotope", "ReactiveCore", "AICore", "AncientTech",
				"NavData", "IrPlate", "OsCore", "PtCatalyst",
				"Res1", "Res2", "Res3",
				"MiteChitin", "DroneCore", "SalvageData", "StolenCargo", 
				"SwarmFragment", "PirateManifest", "ColonySalvage", "TurretCore", 
				"ColonyDataCore", "RadIsotope", "CryoCell",
				"PirateSalvage", "MartianRelics", "CryoEssence", "XenoFragment"],
	# Audit v4.0: Endgame category for ultimate items
	"endgame": ["VoidEssence", "ChronoCore", "OmegaPlating", "PrimordialShard", 
				"VoidBattery", "TemporalModule", "PrimordialArmor", "OmegaAccelerator"],
	"boss_cores": ["Z1_Core", "Z2_Core", "Z3_Core", "Z4_Core", "Z5_Core", 
					"Z6_Core", "Z7_Core", "Z8_Core", "Z9_Core", "Z10_Core"],
	"matrix_cores": ["CrackedCrimsonCore", "StableCrimsonCore", "PristineCrimsonCore",
					"CrackedCobaltCore", "StableCobaltCore", "PristineCobaltCore",
					"CrackedTopazCore", "StableTopazCore", "PristineTopazCore",
					"CrackedAmethystCore", "StableAmethystCore", "PristineAmethystCore"]
}

# v66.0: Consumable Slot System Data
var CONSUMABLE_DATA = {
	# Hull Consumables (restore HP % of Max Hull)
	"Mesh":           {"type": "hull",   "heal_pct": 0.25, "name": "Nanoweave Mesh"},
	"Seal":           {"type": "hull",   "heal_pct": 0.35, "name": "Hull Sealant"},
	"EmergencyPatch": {"type": "hull",   "heal_pct": 0.10, "name": "Emergency Patch"},
	"ChitinPatch":    {"type": "hull",   "heal_pct": 0.15, "name": "Chitin Hull Patch"},
	"AdvMaintenanceKit": {"type": "hull", "heal_pct": 0.50, "name": "Adv. Maintenance Kit"},
	# Shield Consumables (restore Shield % of Max Shield)
	# Shield Consumables (restore Shield % of Max Shield)
	"CapacitorShard": {"type": "shield", "heal_pct": 0.10, "name": "Capacitor Shard"},
	"BasicBooster":   {"type": "shield", "heal_pct": 0.15, "name": "Shield Booster"},
	"IonField":       {"type": "shield", "heal_pct": 0.25, "name": "Ion Field Projector"},
	"NitroCoolant":   {"type": "shield", "heal_pct": 0.35, "name": "Cryo-Shield Matrix"},
	"ZeroPoint":      {"type": "shield", "heal_pct": 0.50, "name": "Zero-Point Injector"},
}

## Get display name for an element
func get_display_name(symbol: String) -> String:
	# Currency is not an element; surface its proper name everywhere
	# (loot lists, rewards, bounties, costs). Word form is safe in both
	# plain Labels and BBCode; cost widgets override to the Lira icon.
	if symbol == "credits":
		return "Liras"
	if symbol in ELEMENT_NAMES:
		return ELEMENT_NAMES[symbol]
	
	# Fallback to JSON data if hardcoded name is missing
	if symbol in ELEMENT_DATA:
		return ELEMENT_DATA[symbol].get("name", symbol)
		
	return symbol

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

## Get consumable data (type, heal_pct)
func get_consumable_data(id: String) -> Dictionary:
	return CONSUMABLE_DATA.get(id, {})

# v62.0: Dynamic Data Loading
var ELEMENT_DATA = {}

func _ready():
	_load_element_data()

func _load_element_data():
	var file = FileAccess.open("res://assets/elements.json", FileAccess.READ)
	if not file:
		push_error("ElementDB: Could not open elements.json")
		return
	
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	if error == OK:
		var data = json.get_data()
		if typeof(data) == TYPE_ARRAY:
			for item in data:
				if "symbol" in item:
					ELEMENT_DATA[item["symbol"]] = item
	else:
		push_error("ElementDB: JSON Parse Error")

func get_element_value(symbol: String) -> int:
	if symbol in ELEMENT_DATA:
		return int(ELEMENT_DATA[symbol].get("base_value", 0))
	# Fallback for hardcoded categories if needed, but mostly should be in JSON
	return 0

func get_element_description(symbol: String) -> String:
	if symbol in ELEMENT_DATA:
		return ELEMENT_DATA[symbol].get("description", "")
	return ""
