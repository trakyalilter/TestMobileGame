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

# --- Research / tech (instant unlocks paid with resources) ---
const TECH := {
	"prospecting": {
		"name": "Prospecting", "desc": "Unlock Crystal mining.",
		"cost": {"IronPlate": 5}, "req": [],
	},
	"electronics": {
		"name": "Electronics", "desc": "Unlock Circuit assembly.",
		"cost": {"IronPlate": 8, "Crystal": 3}, "req": ["prospecting"],
	},
	"automation": {
		"name": "Automation Core", "desc": "+25% global yield, permanently.",
		"cost": {"Circuit": 5}, "req": ["electronics"],
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
