extends Node
## Static game content + helpers. Autoloaded as `GameData`.
## All progression is data-driven here so the UI never needs editing to add content.

# --- Resources (display name + accent color) ---
const RESOURCES := {
	"Scrap":     {"name": "Scrap",      "color": "9aa3af"},
	"IronOre":   {"name": "Iron Ore",   "color": "c08457"},
	"Water":     {"name": "Water",      "color": "4aa3e0"},
	"IronPlate": {"name": "Iron Plate", "color": "d7dbe0"},
	"Crystal":   {"name": "Crystal",    "color": "5ad1e0"},
	"Circuit":   {"name": "Circuit",    "color": "6ad36a"},
	"Artifact":  {"name": "Artifact",   "color": "b07ad6"},
}

# --- Combat targets (Skill: combat). loot rows = [symbol, chance, min, max] ---
const ENEMIES := {
	"scrap_drone": {
		"name": "Scrap Drone", "hp": 20, "dmg": 0.8, "xp": 15, "level_req": 1,
		"loot": [["Scrap", 1.0, 3, 6], ["IronOre", 0.5, 1, 2]],
	},
	"iron_raider": {
		"name": "Iron Raider", "hp": 70, "dmg": 1.5, "xp": 45, "level_req": 3,
		"loot": [["IronOre", 1.0, 3, 6], ["Artifact", 0.2, 1, 1]],
	},
	"crystal_sentinel": {
		"name": "Crystal Sentinel", "hp": 180, "dmg": 3.0, "xp": 150, "level_req": 6,
		"loot": [["Crystal", 1.0, 2, 4], ["Artifact", 0.5, 1, 2]],
	},
	"void_marauder": {
		"name": "Void Marauder", "hp": 420, "dmg": 5.0, "xp": 420, "level_req": 10,
		"loot": [["Crystal", 1.0, 4, 8], ["Circuit", 0.3, 1, 2], ["Artifact", 1.0, 1, 3]],
	},
}

# --- Gathering actions (Skill: harvesting) ---
const GATHER := {
	"gather_scrap": {
		"name": "Salvage Scrap", "resource": "Scrap",
		"min": 2, "max": 4, "duration": 2.0, "xp": 5, "level_req": 1,
	},
	"mine_ore": {
		"name": "Mine Iron Ore", "resource": "IronOre",
		"min": 1, "max": 3, "duration": 3.0, "xp": 8, "level_req": 1,
	},
	"pump_water": {
		"name": "Pump Water", "resource": "Water",
		"min": 2, "max": 4, "duration": 2.5, "xp": 6, "level_req": 1,
	},
	"mine_crystal": {
		"name": "Mine Crystal", "resource": "Crystal",
		"min": 1, "max": 2, "duration": 4.5, "xp": 18, "level_req": 5,
		"tech_req": "prospecting",
	},
}

# --- Crafting recipes (Skill: fabrication) ---
const CRAFT := {
	"smelt_iron": {
		"name": "Smelt Iron Plate",
		"inputs": {"IronOre": 3, "Water": 1}, "output": "IronPlate", "amount": 1,
		"duration": 3.0, "xp": 12, "level_req": 1,
	},
	"make_circuit": {
		"name": "Assemble Circuit",
		"inputs": {"IronPlate": 2, "Crystal": 1}, "output": "Circuit", "amount": 1,
		"duration": 4.5, "xp": 30, "level_req": 3, "tech_req": "electronics",
	},
}

# --- Research / tech trees (instant unlocks paid with resources) ---
# Each tech belongs to a category (a sub-tab) and connects to prereqs via "req".
# "effects" grant passive bonuses applied by GameState.
const TECH_CATS := [
	{"id": "operations",  "label": "Operations"},
	{"id": "engineering", "label": "Engineering"},
]

const TECH := {
	# --- Operations tree (gathering) ---
	"prospecting": {
		"name": "Prospecting", "cat": "operations", "req": [],
		"cost": {"IronPlate": 5}, "desc": "Unlock Crystal mining", "effects": {},
	},
	"deep_drilling": {
		"name": "Deep Drilling", "cat": "operations", "req": ["prospecting"],
		"cost": {"IronPlate": 15}, "desc": "+15% gather yield", "effects": {"gather_yield": 0.15},
	},
	"auto_excavator": {
		"name": "Auto-Excavator", "cat": "operations", "req": ["deep_drilling"],
		"cost": {"Circuit": 3}, "desc": "+20% gather speed", "effects": {"gather_speed": 0.20},
	},
	"rich_veins": {
		"name": "Rich Veins", "cat": "operations", "req": ["deep_drilling"],
		"cost": {"Crystal": 10}, "desc": "+25% gather yield", "effects": {"gather_yield": 0.25},
	},
	"salvage_analysis": {
		"name": "Salvage Analysis", "cat": "operations", "req": ["rich_veins"],
		"cost": {"Artifact": 5}, "desc": "+30% gather yield", "effects": {"gather_yield": 0.30},
	},
	# --- Engineering tree (fabrication) ---
	"electronics": {
		"name": "Electronics", "cat": "engineering", "req": ["prospecting"],
		"cost": {"IronPlate": 8, "Crystal": 3}, "desc": "Unlock Circuit assembly", "effects": {},
	},
	"automation": {
		"name": "Automation Core", "cat": "engineering", "req": ["electronics"],
		"cost": {"Circuit": 5}, "desc": "+25% gather yield", "effects": {"gather_yield": 0.25},
	},
	"mass_fabrication": {
		"name": "Mass Fabrication", "cat": "engineering", "req": ["automation"],
		"cost": {"Circuit": 10}, "desc": "+30% craft speed", "effects": {"craft_speed": 0.30},
	},
}

# --- Helpers ---
func res_name(sym: String) -> String:
	return RESOURCES.get(sym, {}).get("name", sym)

func color_for(sym: String) -> Color:
	return Color.html(RESOURCES.get(sym, {}).get("color", "ffffff"))

func fmt(n) -> String:
	var v := int(n)
	if v >= 1000000:
		return "%.2fM" % (v / 1000000.0)
	if v >= 1000:
		return "%.1fK" % (v / 1000.0)
	return str(v)
