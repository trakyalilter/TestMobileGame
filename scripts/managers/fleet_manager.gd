extends RefCounted
# Fleet Manager — P1 (sink + roster). See docs/FLEET_SIEGE_GATES.md.
#
# Build battle-ships from the material glut; capacity is gated by warp count, so
# the fleet is a prestige-tied meta layer that grows every warp. No combat yet
# (that's P2) — P1 exists to give infinite infra/gather output a real sink and
# to stand up the roster + persistence.
#
# Persistence: the roster is prestige meta-progression — it PERSISTS across warp
# (execute_warp resets skills/combat with decay but never touches the fleet) and
# is cleared only on hard reset.

signal fleet_changed

# capacity = FLEET_CAP_BASE + total_warps  →  W1=2, W2=3, … W10=11
const FLEET_CAP_BASE := 1
const UNLOCK_MIN_WARPS := 1

# Buildable hull classes. Costs are deliberately glut basics (Water/Dirt/Steel/
# Circuit) — this IS the sink. `power` is nominal for now; P2 wires real combat
# contribution off an equipped loadout. `min_warps` gates tiers by prestige
# depth so the roster scales with warps, not just credits.
const FLEET_HULLS := {
	"fleet_frigate": {
		"name": "Fleet Frigate",
		"cost": {"Water": 40000, "Dirt": 20000, "Steel": 5000, "Circuit": 2000},
		"power": 100,
		"min_warps": 1,
	},
	"fleet_destroyer": {
		"name": "Fleet Destroyer",
		"cost": {"Water": 120000, "Dirt": 60000, "Steel": 18000, "Circuit": 8000, "AdvCircuit": 500},
		"power": 320,
		"min_warps": 3,
	},
	"fleet_cruiser": {
		"name": "Fleet Cruiser",
		"cost": {"Water": 300000, "Dirt": 150000, "Steel": 50000, "AdvCircuit": 2500, "Superalloy": 800},
		"power": 850,
		"min_warps": 6,
	},
}

# Roster: Array of {hull_id: String, loadout: Dictionary}. `loadout` is reserved
# for P2 (fleet ships will reference a saved shipyard loadout); empty for now.
var ships: Array = []

func _warps() -> int:
	if GameState and GameState.warp_manager:
		return int(GameState.warp_manager.total_warps)
	return 0

func is_unlocked() -> bool:
	return _warps() >= UNLOCK_MIN_WARPS

func get_fleet_capacity() -> int:
	return FLEET_CAP_BASE + _warps()

func get_fleet_count() -> int:
	return ships.size()

func get_fleet_power() -> float:
	var total: float = 0.0
	for s in ships:
		total += get_hull_power(String(s.get("hull_id", "")))
	return total

func get_hull_name(hull_id: String) -> String:
	return String(FLEET_HULLS.get(hull_id, {}).get("name", hull_id))

func get_hull_power(hull_id: String) -> float:
	return float(FLEET_HULLS.get(hull_id, {}).get("power", 0))

func get_hull_cost(hull_id: String) -> Dictionary:
	return FLEET_HULLS.get(hull_id, {}).get("cost", {})

# Hull ids unlocked at the current warp depth, in definition order.
func get_buildable_hulls() -> Array:
	var out: Array = []
	var w: int = _warps()
	for hid in FLEET_HULLS:
		if w >= int(FLEET_HULLS[hid].get("min_warps", 1)):
			out.append(hid)
	return out

func can_build(hull_id: String) -> bool:
	if not is_unlocked(): return false
	if not FLEET_HULLS.has(hull_id): return false
	if _warps() < int(FLEET_HULLS[hull_id].get("min_warps", 1)): return false
	if get_fleet_count() >= get_fleet_capacity(): return false
	var cost: Dictionary = get_hull_cost(hull_id)
	for res in cost:
		if GameState.resources.get_element_amount(res) < float(cost[res]):
			return false
	return true

func build_ship(hull_id: String) -> bool:
	if not can_build(hull_id): return false
	var cost: Dictionary = get_hull_cost(hull_id)
	for res in cost:
		GameState.resources.remove_element(res, float(cost[res]))
	ships.append({"hull_id": hull_id, "loadout": {}})
	fleet_changed.emit()
	return true

# Free a capacity slot. No material refund — keeps the sink honest.
func scrap_ship(index: int) -> bool:
	if index < 0 or index >= ships.size(): return false
	ships.remove_at(index)
	fleet_changed.emit()
	return true

# ── Persistence ─────────────────────────────────────────────────────────────
func get_save_data_manager() -> Dictionary:
	return {"ships": ships}

func load_save_data_manager(data: Dictionary) -> void:
	var saved = data.get("ships", []) if data is Dictionary else []
	ships = saved.duplicate(true) if saved is Array else []

func reset(_decay_factor: float = 1.0) -> void:
	# hard_reset only — warp preserves the fleet (see file header).
	ships = []
	fleet_changed.emit()
