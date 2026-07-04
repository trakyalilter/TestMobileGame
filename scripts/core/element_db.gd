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
	"FocusingCrystal": "Focusing Crystal",  # v131: polished-Quartz optics for energy/cryo weapons
	"Pentlandite": "Pentlandite Ore",  # Audit v50.0
	"Chromite": "Chromite Ore",  # Audit v50.0
	"Germanit": "Germanite Mineral",
	
	# Components
	"Circuit": "Circuit Board",
	"AdvCircuit": "Advanced Circuit",
	"Chip": "Microchip",
	"Hydraulics": "Hydraulic System",
	"AlWire": "Aluminum Wiring",

	# Batteries
	# v134g: the ITEM is "Battery Cell" — the ship MODULE z1_battery keeps the name
	# "Basic Battery" (shipyard_manager). Two distinct objects must not share a label.
	"BatteryT1": "Battery Cell",
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
	# v134: display renamed (was "Exotic Matter") — collided with the PRESTIGE
	# currency "Exotic Matter Shards"; two different things shared one name.
	# Internal key stays ExoticMatter everywhere (saves, costs, drops).
	"ExoticMatter": "Exotic Condensate",
	"VoidCrystal": "Void Crystal",
	"Diamond": "Diamond",
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
	# v127: Hack Stones — module crafting currency (drag onto a module in the Designer)
	"SpliceChip": "Splice Chip",
	"FirmwareInjector": "Firmware Injector",
	"RootKey": "Root Key",
	"AnchorBolt": "Anchor Bolt",
	"CorruptionWorm": "Corruption Worm",
	"RefitBay": "Refit Bay",
	"SignalCalibrator": "Signal Calibrator",
	# v130: infrastructure overclock card (Satisfactory power-shard analog)
	"BoostCard": "Boost Card",

	# Combat Loot & Artifacts
	"MiteChitin": "Mite Chitin",
	"ChitinPatch": "Chitin Hull Patch",
	"SalvageData": "Salvage Data",
	"PirateSalvage": "Pirate Salvage",
	"MartianRelics": "Martian Relics",
	"CryoEssence": "Glacial Essence",
	"XenoFragment": "Xeno Fragment",
	"ColonySalvage": "Colony Salvage",
	"TurretCore": "Turret Core",
	"ColonyDataCore": "Colony Data Core",
	"TitanClearance": "Titan Clearance",

	"NitroCoolant": "Cryo-Shield Matrix",
	"RadIsotope": "Radioactive Isotope",  # Audit v50.0

	# v57.0: Sector Zeta & Late Sector Loot
	"BiohazardSample": "Biohazard Sample",
	"PathogenCore": "Pathogen Core",
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
	"CompositeWeave": "Composite Weave",
	"N": "Nitrogen",
	
	# Sector Epsilon Endgame Resources
	"VoidEssence": "Void Essence",
	"ChronoCore": "Chrono Core",
	"OmegaPlating": "Omega Plating",
	"PrimordialShard": "Primordial Shard",
	"CryoCatalyst": "Cryo Catalyst",
	"CoolantCell": "Coolant Cell",  # v131: Z4 drone drop — was the only unnamed drop id

	# v114 (Zone Tier-Gate): 2 minted signature raws (Z4/Z10) + 9 per-zone alloys
	# refined from each zone's signature material. See docs/ZONE_TIER_GATE.md.
	"RimeplateScrap": "Rimeplate Scrap",
	"AeonResiduum": "Aeon Residuum",
	"ChondriteAlloy": "Chondrite Alloy",
	"WreckforgedAlloy": "Wreckforged Alloy",
	"RimeAlloy": "Rime Alloy",
	"XenoforgedAlloy": "Xenoforged Alloy",
	"ColonyAlloy": "Colony-Forged Alloy",
	"GammaAlloy": "Gamma Alloy",
	"PrismaticAlloy": "Prismatic Alloy",
	"BioforgedAlloy": "Bioforged Alloy",
	"AeonAlloy": "Aeon Alloy",

	# P1-12: Endgame Crafted Items
	"VoidBattery": "Void Battery",
	"TemporalModule": "Temporal Stabilizer",
	"PrimordialArmor": "Primordial Armor",
	"OmegaAccelerator": "Omega Accelerator",

	# Phase B: late-tier deep-craft intermediates (Z8-10 module spine)
	"StructuralLattice": "Structural Lattice",
	"NeutroniumPlate": "Neutronium Plate",
	"OmegaComposite": "Omega Composite",
	"BioReactorCore": "Bio-Reactor Core",
	"PrimordialMatrix": "Primordial Matrix",
	"VoidLattice": "Void Lattice",

	# Reclaimed Components — combat-exclusive progression salvage (Tier 1).
	# Torn from specific enemy archetypes; gate crafting; hard-to-craft fallback.
	"SalvagedAlloy": "Salvaged Alloy",
	"DamagedCircuitry": "Damaged Circuitry",
	"ReinforcedPlating": "Reinforced Plating",

	# v132: names for ids that only existed in MATERIAL_TINT — tooltips and cost
	# labels rendered the raw camel-case symbol for these.
	"Malachite": "Malachite Ore",
	"Semiconductor": "Semiconductor",
	"StructuralComponent": "Structural Component",
	"AgCatalyst": "Silver Catalyst",
	"NuclearFuel": "Nuclear Fuel",
	"AdvMaintenanceKit": "Adv. Maintenance Kit",

	# Boss Cores
	"Z1_Core": "Lunar Core",
	"Z2_Core": "Asteroid Core",
	"Z3_Core": "Debris Core",
	"Z4_Core": "Glacier Core",
	"Z5_Core": "Alpha Core",
	"Z6_Core": "Beta Core",
	"Z7_Core": "Gamma Core",
	"Z8_Core": "Delta Core",
	"Z9_Core": "Epsilon Core",
	"Z10_Core": "Omega Core"
}

## Category mappings for inventory filtering
var CATEGORIES = {
	"ores": ["Dirt", "Bauxite", "Dolomite", "Cassiterite", "ZincOre", "Spodumene", "PtOre", "Germanit", "Malachite", "Quartz"],  # v132: both gatherable ores were uncategorized — invisible to the inventory ore filter
	"basic_metals": ["Fe", "Cu", "Al", "Mg", "Sn", "Zn"],
	"advanced_metals": ["Ti", "Co", "Ni", "Cr", "Mn", "W"],
	"rare_metals": ["Au", "Ag", "Pt", "Pd", "Ir", "Os", "Rh", "U", "Germanium"],
	"alloys": ["Steel", "Graphite", "StainlessSteel", "GalvanizedSteel", "Superalloy", "AlMgAlloy", "IrWAlloy",
				"ChondriteAlloy", "WreckforgedAlloy", "RimeAlloy", "XenoforgedAlloy", "ColonyAlloy", "GammaAlloy", "PrismaticAlloy", "BioforgedAlloy", "AeonAlloy"],
	"components": ["Circuit", "AdvCircuit", "Chip", "Hydraulics", "AlWire", "Resin", "Fiber", "ReinforcedPlating", "FocusingCrystal"],
	"batteries": ["BatteryT1", "BatteryT2", "BatteryT3", "CoBattery", "MgBattery", "PdFuelCell"],
	"consumables": ["Mesh", "Seal", "EmergencyPatch", "BasicBooster", "ChitinPatch", "NitroCoolant", "AdvMaintenanceKit", "CapacitorShard", "IonField", "ZeroPoint"],  # Audit v2.0: Early/Mid consumables
	"ammo": ["SlugT1", "SlugT1S", "SlugT2", "SlugT3", "SlugT4", "CellT1", "CellT2", "CellT3", "CellT4", "MissileT1", "MissileT2", "MissileT3", "MissileT4"],
	"special": ["VoidArtifact", "QuantumCore", "ExoticMatter", "VoidCrystal", "Diamond",
				"Neutronium", "AntimatterParticle", "ExoticIsotope", "ReactiveCore", "AICore", "AncientTech",
				"NavData", "IrPlate", "OsCore", "PtCatalyst",
				"Res1", "Res2", "Res3",
				"MiteChitin", "SalvageData", "ColonySalvage", "TurretCore",
				"ColonyDataCore", "RadIsotope",
				"PirateSalvage", "MartianRelics", "CryoEssence", "XenoFragment",
				"RimeplateScrap", "AeonResiduum"],  # v114: minted Zone Tier-Gate raws
	# Audit v4.0: Endgame category for ultimate items
	"endgame": ["VoidEssence", "ChronoCore", "OmegaPlating", "PrimordialShard", "CryoCatalyst",
				"VoidBattery", "TemporalModule", "PrimordialArmor", "OmegaAccelerator",
				"StructuralLattice", "NeutroniumPlate", "OmegaComposite", "BioReactorCore", "PrimordialMatrix", "VoidLattice"],
	"boss_cores": ["Z1_Core", "Z2_Core", "Z3_Core", "Z4_Core", "Z5_Core", 
					"Z6_Core", "Z7_Core", "Z8_Core", "Z9_Core", "Z10_Core"],
	"matrix_cores": ["CrackedCrimsonCore", "StableCrimsonCore", "PristineCrimsonCore",
					"CrackedCobaltCore", "StableCobaltCore", "PristineCobaltCore",
					"CrackedTopazCore", "StableTopazCore", "PristineTopazCore",
					"CrackedAmethystCore", "StableAmethystCore", "PristineAmethystCore"],
	# Combat-exclusive progression salvage (Inventory "Other", never Armory)
	"reclaimed_components": ["SalvagedAlloy", "DamagedCircuitry"],
	# v127: Hack Stone crafting currency
	"hack_stones": ["SpliceChip", "FirmwareInjector", "RootKey", "AnchorBolt", "CorruptionWorm", "RefitBay", "SignalCalibrator"],
	# v130: infrastructure overclock cards — mid/late craftable, installed per building unit
	"boost_cards": ["BoostCard"]
}

# v66.0: Consumable Slot System Data
var CONSUMABLE_DATA = {
	# Hull Consumables (restore HP % of Max Hull)
	"Mesh":           {"type": "hull",   "heal_pct": 0.25, "name": "Nanoweave Mesh"},
	"Seal":           {"type": "hull",   "heal_pct": 0.35, "name": "Hull Sealant"},
	"EmergencyPatch": {"type": "hull",   "heal_pct": 0.10, "name": "Emergency Patch"},
	"ChitinPatch":    {"type": "hull",   "heal_pct": 0.15, "name": "Chitin Hull Patch"},
	"AdvMaintenanceKit": {"type": "hull", "heal_pct": 0.35, "name": "Adv. Maintenance Kit"},  # v106: 0.50→0.25→0.35 (recalibrated middle ground after Z10 over-tuning)
	# Shield Consumables (restore Shield % of Max Shield)
	# Shield Consumables (restore Shield % of Max Shield)
	"CapacitorShard": {"type": "shield", "heal_pct": 0.10, "name": "Capacitor Shard"},
	"BasicBooster":   {"type": "shield", "heal_pct": 0.15, "name": "Shield Booster"},
	"IonField":       {"type": "shield", "heal_pct": 0.25, "name": "Ion Field Projector"},
	"NitroCoolant":   {"type": "shield", "heal_pct": 0.25, "name": "Cryo-Shield Matrix"},  # v106: 0.35→0.20→0.25 (recalibrated)
	"ZeroPoint":      {"type": "shield", "heal_pct": 0.35, "name": "Zero-Point Injector"},  # v106: 0.50→0.25→0.35 (recalibrated)
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

# Progression-critical, low-volume drops that must NOT be silently lost to the
# inventory slot cap (boss cores gate zone research; matrix cores socket gear;
# endgame/special are rare one-offs). Bulk basics keep the cap as a sink.
var _slot_protected: Dictionary = {}
func is_slot_protected(symbol: String) -> bool:
	if _slot_protected.is_empty():
		for cat in ["boss_cores", "matrix_cores", "endgame", "special", "hack_stones", "boost_cards"]:
			for s in CATEGORIES.get(cat, []):
				_slot_protected[s] = true
	return _slot_protected.has(symbol)

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

# ─────────────────────────────────────────────────────────────
# Material icons (Batch-0 foundation). Monochrome white SVGs live under
# res://assets/icons/materials/<id>.svg and are runtime-tinted via modulate to
# a per-material signature colour (falling back to the material's category).
# Icon coverage is intentionally PARTIAL during rollout: get_material_icon()
# returns null for any id without a file yet, and every UI site degrades to the
# existing text. Drop in a new <id>.svg and that material starts showing an icon
# with zero other changes.
# ─────────────────────────────────────────────────────────────

# Static so each id's texture imports exactly once across every card instance.
# Misses are negative-cached (value = null) so absent icons don't re-stat the
# filesystem on every inventory / recipe rebuild.
static var _mat_icon_cache: Dictionary = {}

static func get_material_icon(symbol: String) -> Texture2D:
	if _mat_icon_cache.has(symbol):
		return _mat_icon_cache[symbol]
	var tex: Texture2D = null
	var path: String = "res://assets/icons/materials/%s.svg" % symbol
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_mat_icon_cache[symbol] = tex
	return tex

# Default tint per material category (keys match CATEGORIES). Used when a
# material has no specific entry in MATERIAL_TINT.
var CATEGORY_TINT := {
	"ores": Color(0.61, 0.42, 0.25),
	"basic_metals": Color(0.72, 0.76, 0.80),
	"advanced_metals": Color(0.56, 0.63, 0.69),
	"rare_metals": Color(0.91, 0.76, 0.35),
	"alloys": Color(0.78, 0.81, 0.85),
	"components": Color(0.35, 0.78, 0.88),
	"batteries": Color(0.62, 0.83, 0.35),
	"consumables": Color(0.44, 0.82, 0.54),
	"ammo": Color(0.91, 0.58, 0.23),
	"special": Color(0.72, 0.52, 0.88),
	"endgame": Color(0.85, 0.45, 0.85),
	"boss_cores": Color(0.91, 0.71, 0.29),
	"matrix_cores": Color(0.85, 0.55, 0.85),
	"reclaimed_components": Color(0.75, 0.47, 0.29),
}

# Per-material signature tints (grows one batch at a time). A material's colour
# IS part of its identity (copper vs gold vs water), so a specific entry here
# wins; anything missing falls back to CATEGORY_TINT, then a warm neutral.
var MATERIAL_TINT := {
	# Batch 1 — first-session heroes
	"Dirt": Color(0.54, 0.42, 0.27),
	"Water": Color(0.31, 0.66, 0.88),
	"Wood": Color(0.80, 0.62, 0.38),  # honey-oak: lifted out of the warm-brown YIELD/cell bg so the glyph reads
	"Fe": Color(0.68, 0.71, 0.75),
	"Si": Color(0.56, 0.65, 0.73),
	"C": Color(0.37, 0.39, 0.42),
	"Cu": Color(0.82, 0.54, 0.29),
	"Steel": Color(0.54, 0.57, 0.61),
	"Circuit": Color(0.37, 0.76, 0.43),
	"credits": Color(1.0, 0.82, 0.30),
	# Batch 2 — early ores + light metals + gases
	"Bauxite": Color(0.71, 0.41, 0.25),
	"Malachite": Color(0.31, 0.68, 0.44),
	"Cassiterite": Color(0.56, 0.47, 0.39),
	"ZincOre": Color(0.60, 0.57, 0.52),
	"Dolomite": Color(0.80, 0.74, 0.61),
	"Spodumene": Color(0.79, 0.65, 0.70),
	"Quartz": Color(0.75, 0.81, 0.87),
	"FocusingCrystal": Color(0.62, 0.88, 0.96),
	"Al": Color(0.86, 0.88, 0.89),
	"Sn": Color(0.74, 0.70, 0.64),
	"Zn": Color(0.56, 0.71, 0.82),
	"Mg": Color(0.76, 0.83, 0.71),
	"Li": Color(0.80, 0.66, 0.70),
	"H": Color(0.62, 0.84, 0.90),
	"O": Color(0.52, 0.66, 0.92),
	# Batch 3 — early components, data & salvage chain
	"AdvCircuit": Color(0.36, 0.82, 0.69),
	"Chip": Color(0.44, 0.69, 0.88),
	"Semiconductor": Color(0.56, 0.69, 0.78),
	"Resin": Color(0.80, 0.62, 0.28),
	"Fiber": Color(0.42, 0.44, 0.48),
	"AlWire": Color(0.78, 0.80, 0.82),
	"SparePart": Color(0.66, 0.64, 0.60),
	"Res1": Color(0.56, 0.78, 0.42),
	"SalvageData": Color(0.36, 0.70, 0.84),
	"NavData": Color(0.44, 0.66, 0.90),
	"MiteChitin": Color(0.72, 0.55, 0.36),
	"SalvagedAlloy": Color(0.68, 0.56, 0.44),
	"DamagedCircuitry": Color(0.56, 0.66, 0.44),
	"ReinforcedPlating": Color(0.62, 0.66, 0.71),
	# Batch 4 — ammunition (kinetic slugs / energy cells / explosive missiles, escalating per tier)
	"SlugT1": Color(0.69, 0.66, 0.62),
	"SlugT1S": Color(0.68, 0.71, 0.75),
	"SlugT2": Color(0.78, 0.66, 0.35),
	"SlugT3": Color(0.62, 0.82, 0.42),
	"SlugT4": Color(0.91, 0.52, 0.23),
	"CellT1": Color(0.44, 0.82, 0.85),
	"CellT2": Color(0.35, 0.69, 0.88),
	"CellT3": Color(0.48, 0.54, 0.88),
	"CellT4": Color(0.69, 0.44, 0.88),
	"MissileT1": Color(0.88, 0.66, 0.29),
	"MissileT2": Color(0.88, 0.54, 0.25),
	"MissileT3": Color(0.88, 0.38, 0.23),
	"MissileT4": Color(0.91, 0.29, 0.42),
	# Batch 5 — consumables (hull heals = green objects, shield heals = blue shield+glyph)
	"EmergencyPatch": Color(0.56, 0.85, 0.60),
	"ChitinPatch": Color(0.66, 0.77, 0.42),
	"Mesh": Color(0.37, 0.77, 0.48),
	"Seal": Color(0.31, 0.75, 0.63),
	"AdvMaintenanceKit": Color(0.44, 0.82, 0.42),
	"CapacitorShard": Color(0.50, 0.82, 0.88),
	"BasicBooster": Color(0.35, 0.75, 0.88),
	"IonField": Color(0.35, 0.66, 0.88),
	"NitroCoolant": Color(0.56, 0.78, 0.91),
	"ZeroPoint": Color(0.44, 0.54, 0.88),
	# Batch 6 — mid-game metals (stamped ingots), alloys, gem, components, ores
	"Ti": Color(0.62, 0.69, 0.76),
	"Ni": Color(0.75, 0.77, 0.72),
	"Cr": Color(0.77, 0.80, 0.82),
	"Co": Color(0.44, 0.54, 0.78),
	"Mn": Color(0.60, 0.58, 0.66),
	"Au": Color(0.91, 0.76, 0.29),
	"Ag": Color(0.82, 0.85, 0.87),
	"Superalloy": Color(0.66, 0.74, 0.82),
	"StainlessSteel": Color(0.74, 0.79, 0.83),
	"GalvanizedSteel": Color(0.70, 0.74, 0.70),
	"AlMgAlloy": Color(0.80, 0.83, 0.80),
	"Graphite": Color(0.40, 0.42, 0.45),
	"Diamond": Color(0.80, 0.90, 0.94),
	"StructuralComponent": Color(0.58, 0.66, 0.74),
	"NanoSubstrate": Color(0.55, 0.72, 0.82),
	"Hydraulics": Color(0.45, 0.72, 0.78),
	"Pentlandite": Color(0.70, 0.66, 0.55),
	"Chromite": Color(0.55, 0.56, 0.58),
	# Batch 7 — power & catalysts (batteries / fuel cell / coolant / catalyst flasks / nuclear)
	"BatteryT1": Color(0.56, 0.77, 0.29),
	"BatteryT2": Color(0.77, 0.77, 0.29),
	"BatteryT3": Color(0.35, 0.78, 0.85),
	"CoBattery": Color(0.35, 0.47, 0.85),
	"MgBattery": Color(0.55, 0.80, 0.58),
	"PdFuelCell": Color(0.48, 0.77, 0.72),
	"VoidBattery": Color(0.54, 0.35, 0.85),
	"CoolantCell": Color(0.56, 0.85, 0.91),
	"AgCatalyst": Color(0.78, 0.80, 0.82),
	"PtCatalyst": Color(0.74, 0.83, 0.86),
	"NuclearFuel": Color(0.62, 0.77, 0.25),
	# Batch 8 — Matrix cores (hue = family, brightness escalates Cracked→Stable→Pristine)
	"CrackedCrimsonCore": Color(0.66, 0.23, 0.23),
	"StableCrimsonCore": Color(0.82, 0.29, 0.29),
	"PristineCrimsonCore": Color(0.91, 0.42, 0.42),
	"CrackedCobaltCore": Color(0.23, 0.35, 0.66),
	"StableCobaltCore": Color(0.29, 0.47, 0.85),
	"PristineCobaltCore": Color(0.42, 0.60, 0.91),
	"CrackedTopazCore": Color(0.69, 0.51, 0.16),
	"StableTopazCore": Color(0.88, 0.66, 0.23),
	"PristineTopazCore": Color(0.94, 0.77, 0.35),
	"CrackedAmethystCore": Color(0.54, 0.29, 0.72),
	"StableAmethystCore": Color(0.66, 0.37, 0.85),
	"PristineAmethystCore": Color(0.75, 0.53, 0.91),
	# Batch 9 — zone signature raws + alloys
	"PirateSalvage": Color(0.60, 0.54, 0.48),
	"MartianRelics": Color(0.78, 0.42, 0.23),
	"CryoEssence": Color(0.56, 0.85, 0.91),
	"RimeplateScrap": Color(0.66, 0.75, 0.78),
	"XenoFragment": Color(0.54, 0.69, 0.29),
	"ColonySalvage": Color(0.48, 0.58, 0.66),
	"AeonResiduum": Color(0.44, 0.75, 0.69),
	"ChondriteAlloy": Color(0.66, 0.58, 0.47),
	"WreckforgedAlloy": Color(0.60, 0.63, 0.66),
	"RimeAlloy": Color(0.60, 0.75, 0.80),
	"XenoforgedAlloy": Color(0.60, 0.72, 0.35),
	"ColonyAlloy": Color(0.54, 0.63, 0.72),
	"GammaAlloy": Color(0.72, 0.77, 0.29),
	"PrismaticAlloy": Color(0.75, 0.53, 0.85),
	"BioforgedAlloy": Color(0.48, 0.75, 0.54),
	"AeonAlloy": Color(0.44, 0.69, 0.75),
	# Batch 10 — rare/exotic metals (stamped ingots) + ores + plating/core/alloy + isotope
	"Ir": Color(0.78, 0.83, 0.86),
	"Os": Color(0.56, 0.63, 0.72),
	"U": Color(0.48, 0.72, 0.29),
	"Pd": Color(0.80, 0.82, 0.84),
	"Germanium": Color(0.66, 0.69, 0.69),
	"Pt": Color(0.84, 0.87, 0.89),
	"W": Color(0.54, 0.56, 0.58),
	"PtOre": Color(0.69, 0.71, 0.72),
	"Germanit": Color(0.54, 0.50, 0.45),
	"IrPlate": Color(0.74, 0.79, 0.83),
	"OsCore": Color(0.50, 0.58, 0.68),
	"IrWAlloy": Color(0.58, 0.60, 0.64),
	"RadIsotope": Color(0.66, 0.80, 0.30),
	# Batch 11 — exotics & prestige
	"ExoticMatter": Color(0.75, 0.38, 0.88),
	"VoidCrystal": Color(0.54, 0.29, 0.78),
	"VoidEssence": Color(0.42, 0.28, 0.72),
	"QuantumCore": Color(0.29, 0.75, 0.88),
	"Neutronium": Color(0.68, 0.75, 0.85),
	"ChronoCore": Color(0.35, 0.82, 0.69),
	"AntimatterParticle": Color(0.91, 0.29, 0.54),
	"PrimordialShard": Color(0.88, 0.54, 0.23),
	"ExoticIsotope": Color(0.35, 0.82, 0.56),
	"CryoCatalyst": Color(0.56, 0.82, 0.91),
	# Phase B intermediates (family hue of their parent precursor)
	"StructuralLattice": Color(0.66, 0.70, 0.74),
	"NeutroniumPlate":   Color(0.72, 0.78, 0.88),
	"OmegaComposite":    Color(0.80, 0.50, 0.30),
	"BioReactorCore":    Color(0.40, 0.78, 0.45),
	"PrimordialMatrix":  Color(0.90, 0.58, 0.28),
	"VoidLattice":       Color(0.46, 0.30, 0.74),
	# Batch 12 — zone boss cores (numeral stamp, tint escalates across the zone progression)
	"Z1_Core": Color(0.69, 0.72, 0.75),
	"Z2_Core": Color(0.72, 0.60, 0.42),
	"Z3_Core": Color(0.75, 0.44, 0.31),
	"Z4_Core": Color(0.48, 0.75, 0.85),
	"Z5_Core": Color(0.42, 0.75, 0.47),
	"Z6_Core": Color(0.35, 0.54, 0.85),
	"Z7_Core": Color(0.72, 0.77, 0.29),
	"Z8_Core": Color(0.60, 0.35, 0.85),
	"Z9_Core": Color(0.85, 0.35, 0.75),
	"Z10_Core": Color(0.91, 0.75, 0.29),
	# Batch 14 — bio / AI / endgame components + artifacts
	"BiohazardSample": Color(0.60, 0.77, 0.29),
	"PathogenCore": Color(0.69, 0.35, 0.75),
	"AICore": Color(0.29, 0.75, 0.85),
	"AIProcessor": Color(0.35, 0.54, 0.85),
	"RegenPlating": Color(0.35, 0.75, 0.50),
	"BioWeaponCoating": Color(0.54, 0.75, 0.31),
	"OmegaPlating": Color(0.88, 0.75, 0.38),
	"PurifiedCompound": Color(0.56, 0.82, 0.85),
	"TurretCore": Color(0.54, 0.58, 0.63),
	"TargetingChip": Color(0.88, 0.52, 0.23),
	"SuperconductingMagnet": Color(0.35, 0.54, 0.78),
	"VoidArtifact": Color(0.48, 0.29, 0.75),
	# Batch 15 (final) — gases, element/alloy completeness, artifacts, endgame passives,
	# Phase B deep-craft intermediates, and remaining loot/data items (full coverage)
	"He": Color(0.80, 0.74, 0.66),
	"N": Color(0.48, 0.60, 0.85),
	"S": Color(0.85, 0.78, 0.30),
	"Rh": Color(0.78, 0.80, 0.82),
	"Res2": Color(0.40, 0.66, 0.90),
	"Res3": Color(0.75, 0.45, 0.88),
	"TemporalModule": Color(0.40, 0.80, 0.85),
	"PrimordialArmor": Color(0.80, 0.50, 0.30),
	"OmegaAccelerator": Color(0.88, 0.72, 0.35),
	"CompositeWeave": Color(0.55, 0.60, 0.65),
	"AncientTech": Color(0.75, 0.62, 0.38),
	"ColonyDataCore": Color(0.45, 0.62, 0.72),
	"QuarantineClearance": Color(0.55, 0.75, 0.45),
	# v127: Hack Stones
	"SpliceChip": Color(0.55, 0.85, 0.70),
	"FirmwareInjector": Color(0.45, 0.80, 0.95),
	"RootKey": Color(0.90, 0.75, 0.35),
	"AnchorBolt": Color(0.70, 0.72, 0.78),
	"CorruptionWorm": Color(0.75, 0.40, 0.80),
	"RefitBay": Color(0.55, 0.70, 0.90),
	"SignalCalibrator": Color(0.95, 0.60, 0.85),
	"BoostCard": Color(1.0, 0.76, 0.28),
	"TitanClearance": Color(0.60, 0.66, 0.72),
	"ReactiveCore": Color(0.85, 0.45, 0.30),
}

func get_material_tint(symbol: String) -> Color:
	if symbol in MATERIAL_TINT:
		return MATERIAL_TINT[symbol]
	var cat: String = get_category(symbol)
	if cat in CATEGORY_TINT:
		return CATEGORY_TINT[cat]
	return Color(0.72, 0.68, 0.60)

# Inline material icon as a BBCode [img] fragment (with a trailing space) for
# RichTextLabel rows (gather yields, recipe inputs/outputs). Returns "" when no
# icon exists yet so callers degrade cleanly to plain text.
func material_icon_bbcode(symbol: String, px: int = 18) -> String:
	var path: String = "res://assets/icons/materials/%s.svg" % symbol
	if not ResourceLoader.exists(path):
		return ""
	var c: Color = get_material_tint(symbol)
	return "[img width=%d height=%d color=#%s]%s[/img] " % [px, px, c.to_html(false), path]
