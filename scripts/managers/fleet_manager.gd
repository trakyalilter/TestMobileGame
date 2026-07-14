extends RefCounted
# Fleet Manager — SOFT ROLE, shipped scope (owner decision 2026-07-14).
# See docs/FLEET_SIEGE_GATES.md.
#
# Build battle-ships from the material glut; capacity is gated by warp count, so
# the fleet is a prestige-tied meta layer that grows every warp. The soft combat
# role is LIVE (get_combat_dps_mult → combat_manager's damage path): each ship
# adds +25% of the main ship's damage, capped at +100%. The siege/hard role is
# CUT — NG+ loop boundaries stay plain clear→Warp; capacity past the +100% cap
# is roster head-room, not a promise of a future siege system.
#
# Persistence: the roster is prestige meta-progression — it PERSISTS across warp
# (execute_warp resets skills/combat with decay but never touches the fleet) and
# is cleared only on hard reset.

signal fleet_changed

# capacity = FLEET_CAP_BASE + total_warps  →  W1=2, W2=3, … W10=11
const FLEET_CAP_BASE := 1
const UNLOCK_MIN_WARPS := 1

# Buildable hull classes. Costs are deliberately glut basics (Water/Dirt/Steel/
# Circuit) — this IS the sink. `min_warps` gates tiers by prestige depth so the
# roster scales with warps, not just credits.
# v138a cost retune: warp 1 moved from ~Zone-6 research to the ZONE-3 boss (the
# Singularity), so the warp-1 player is far earlier — the old frigate bill
# (Water 40K / Steel 5K / Circuit 2K) would leave the freshly-revealed Fleet tab
# dead for days. Re-sized per the design doc's own rule ("soak ~30-60 min of
# infra output at that depth"): frigate ÷5, destroyer ÷2, cruiser ÷~1.5.
# PLAYTEST-TUNABLE — these are sizing-rule estimates, not measured numbers.
const FLEET_HULLS := {
	"fleet_frigate": {
		"name": "Fleet Frigate",
		"cost": {"Water": 8000, "Dirt": 4000, "Steel": 800, "Circuit": 150},
		"power": 100,
		"min_warps": 1,
	},
	"fleet_destroyer": {
		"name": "Fleet Destroyer",
		"cost": {"Water": 60000, "Dirt": 30000, "Steel": 9000, "Circuit": 4000, "AdvCircuit": 250},
		"power": 320,
		"min_warps": 3,
	},
	"fleet_cruiser": {
		"name": "Fleet Cruiser",
		"cost": {"Water": 200000, "Dirt": 100000, "Steel": 35000, "AdvCircuit": 1500, "Superalloy": 500},
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

# v112 (P2 — soft role): combat contribution. Each fleet ship adds a flat
# fraction of the MAIN ship's effective damage (the doc's "0.25x the main
# ship's power"), capped at +100% so a full cap-4 fleet ~doubles output while
# the main ship stays the single biggest piece. Capacity past 4 grows the
# roster for the FUTURE siege (hard) role — it does NOT keep raising the soft
# zone-combat bonus. Returned as a damage MULTIPLIER folded into
# combat_manager's skill_dmg_mult. 1.0 when the fleet is locked or empty, so
# pre-warp / fleetless combat is byte-identical to before.
const FLEET_COMBAT_FRACTION := 0.25   # per ship, of the main ship's damage
const FLEET_COMBAT_CAP := 1.0         # max +100% (full cap-4 fleet)

func get_combat_dps_mult() -> float:
	if not is_unlocked():
		return 1.0
	var n: int = get_fleet_count()
	if n <= 0:
		return 1.0
	return 1.0 + min(FLEET_COMBAT_CAP, FLEET_COMBAT_FRACTION * float(n))

# +X% the fleet currently contributes to ship damage (for the combat HUD line).
func get_combat_bonus_pct() -> int:
	return int(round((get_combat_dps_mult() - 1.0) * 100.0))

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
