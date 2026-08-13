extends Node
# ============================================================================
# CHAIN READINESS CHECK (v175)
#
# THE INVARIANT: by the time the mission chain asks the player to kill a Zone-N
# boss, the chain must actually have HANDED THEM the ship that fight assumes —
# a hull of tier >= N, and enough battery tier to mount a full Zone-N loadout on
# that hull.
#
# Why this guard exists. Two guards already certify boss fights, and BOTH assume
# gear the chain never gave:
#   * boss_gearcheck fights every boss from _set_hull(n) — hull tier == zone.
#   * energy_margin_check equips TIER-MATCHED batteries.
# Neither reads the mission table, so neither could see that:
#   * the hull ladder went Frigate(2) -> Destroyer(3) -> Battlecruiser(5) with NO
#     construct beat for cruiser_hull, and the Battlecruiser landed at m032c —
#     AFTER the Z4 boss farm (m030i) AND after the Z5 boss farm (m032a);
#   * the battery ladder ended at m030c2 (Zone-2 cells) and was never revisited,
#     so the player flew Belt-era power through Zones 3, 4, 5 and beyond.
# Measured cost of the first one (hull_gate_diag, identical full-Rare kit, only
# the hull varying, 21 trials): the Z4 and Z5 bosses go from 2-10/21 wins in the
# chain-given Destroyer to 17-21/21 in the tier-matched hull. player_bot spent
# 48h+ livelocked on m030i/m032a farming gear that could not lift that ceiling.
#
# The POWER half is measured by EQUIPPING, not by comparing draw to capacity
# after the fact. equip_module REFUSES a module when new_load > new_cap (v110
# battery-only guard), so a ship that cannot afford its guns simply never mounts
# them and reads as low-draw — a draw-vs-cap comparison would call that a PASS.
# The honest question is "how many consumer slots can this ship actually fill",
# which is also exactly what the player sees: "cannot fit <type> counter".
#
#   Godot --headless --path <root> res://scenes/chain_readiness_check.tscn
# ============================================================================

const BGC := preload("res://scripts/sim/boss_gearcheck.gd")

# Hull tiers only go to 10 and the NG+ sectors (Z11+) are post-warp content the
# chain gates through goals rather than the hull ladder. Checking them here would
# report a permanent, unfixable failure, so they are SKIPPED — and reported as
# skipped, never silently dropped.
const MAX_CHECKED_ZONE := 10

var _bgc
var _fails: Array = []
var _skipped: Array = []

func _ready() -> void:
	await get_tree().process_frame
	if not GameState.sim_mode:
		print("[CHAIN] ABORT: sim_mode false — refusing to run (this probe hard_resets).")
		get_tree().quit(1)
		return
	GameState.set_process(false)
	_bgc = BGC.new()

	var mm = GameState.mission_manager
	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager

	print("[CHAIN] ============ CHAIN READINESS CHECK ============")
	print("[CHAIN] rule: at every boss beat, the chain must already have given a hull of")
	print("[CHAIN] tier >= the boss zone, AND battery tier enough to fill every consumer slot.")
	print("[CHAIN] --------------------------------------------------------------------------")

	# PASS 1 — walk the chain and record what the player owns at each boss beat.
	# Done in one pass with NO hard_reset, because resetting would wipe the very
	# mission state being walked. The power fights happen in pass 2.
	var demands := _walk_chain(mm, cm, sm)
	if demands.is_empty():
		_fail("chain walk found NO boss beats — the walk itself is broken, not the chain")

	# PASS 2 — for each recorded demand, build the ship the chain gave and see how
	# much of a tier-matched loadout it can actually mount.
	print("[CHAIN] %-8s %-22s %-4s %-16s %-5s | %-9s %s" % [
		"beat", "boss", "zone", "chain hull", "tier", "batt", "consumer slots filled"])
	for d in demands:
		_check_one(sm, d)

	print("[CHAIN] --------------------------------------------------------------------------")
	for s in _skipped:
		print("[CHAIN] SKIPPED: %s" % s)
	for f in _fails:
		print("[CHAIN] FAIL: %s" % f)
	print("[CHAIN] RESULT: %s (%d failure(s), %d skipped)" % [
		"PASS" if _fails.is_empty() else "FAIL", _fails.size(), _skipped.size()])
	get_tree().quit(0 if _fails.is_empty() else 1)

func _fail(msg: String) -> void:
	_fails.append(msg)

# Walk the chain in topological order, tracking the best hull and the best
# battery the chain has handed over so far, and emit one record per boss beat.
func _walk_chain(mm, cm, sm) -> Array:
	var idx: Dictionary = mm.get_chain_index()
	var ordered: Array = idx.keys()
	ordered.sort_custom(func(a, b): return int(idx[a]) < int(idx[b]))

	# What a fresh game starts with, read at runtime rather than hardcoded.
	var hull_id := str(sm.active_hull)
	var hull_tier := int(sm.hulls.get(hull_id, {}).get("tier", 1))
	var batt_zone := _starting_battery_zone(sm)
	var out: Array = []

	for mid in ordered:
		var m: Dictionary = mm.missions.get(mid, {})
		if m.is_empty():
			continue
		var mtype := str(m.get("type", ""))
		var target := str(m.get("target", ""))

		if mtype == "construct" and target in sm.hulls:
			var t := int(sm.hulls[target].get("tier", 0))
			if t > hull_tier:
				hull_tier = t
				hull_id = target
		elif mtype == "craft":
			var mdef: Dictionary = sm.modules.get(target, {})
			if str(mdef.get("slot_type", "")) == "battery":
				batt_zone = maxi(batt_zone, int(mdef.get("zone", 0)))
		elif mtype == "defeat" or mtype == "defeat_retreat":
			var e: Dictionary = cm.enemy_db.get(target, {})
			if not bool(e.get("is_boss", false)):
				continue
			var bz := int(e.get("zone", 0))
			if bz <= 0 or bz > MAX_CHECKED_ZONE:
				_skipped.append("%s (%s) zone %d — beyond the tier-10 hull ladder (NG+/post-warp)"
					% [mid, target, bz])
				continue
			out.append({"beat": mid, "eid": target, "zone": bz,
				"hull": hull_id, "tier": hull_tier, "batt": batt_zone})
	return out

func _starting_battery_zone(sm) -> int:
	# shipyard reset() grants + equips starter batteries; read their zone rather
	# than assuming Z1, so a change to the starter kit cannot silently skew this.
	var best := 0
	for i in sm.loadout:
		var mid = sm.loadout[i]
		if not mid:
			continue
		var mdef: Dictionary = sm.modules.get(str(mid), {})
		if str(mdef.get("slot_type", "")) == "battery":
			best = maxi(best, int(mdef.get("zone", 1)))
	return maxi(best, 1)

func _check_one(sm, d: Dictionary) -> void:
	var bz := int(d["zone"])
	var beat := str(d["beat"])
	var hull := str(d["hull"])
	var tier := int(d["tier"])
	var batt := int(d["batt"])

	var fit := _fit_loadout(sm, hull, batt, bz)
	var filled := int(fit["filled"])
	var total := int(fit["total"])
	var hull_bad: bool = tier < bz
	var power_bad: bool = filled < total
	var note := ""
	if hull_bad:
		note += "  <-- HULL under-tier"
	if power_bad:
		note += "  <-- CANNOT POWER %d slot(s)" % (total - filled)

	print("[CHAIN] %-8s %-22s Z%-3d %-16s t%-4d | Z%-8d %d/%d%s" % [
		beat, str(d["eid"]), bz, hull, tier, batt, filled, total, note])

	if hull_bad:
		_fail("%s asks for the Z%d boss %s but the chain has only built %s (tier %d). boss_gearcheck certifies this fight at hull tier %d."
			% [beat, bz, str(d["eid"]), hull, tier, bz])
	if power_bad:
		_fail("%s: a %s running Z%d batteries can only fill %d of %d consumer slots with Z%d gear — the player owns the counter and cannot mount it."
			% [beat, hull, batt, filled, total, bz])

# Build the chain-given ship and count how many consumer slots accept a
# tier-matched COMMON module. Common (not Rare) is the honest floor: it is what
# the chain's own craft beats hand over, and rarity does not change energy load.
func _fit_loadout(sm, hull: String, batt_zone: int, boss_zone: int) -> Dictionary:
	GameState.hard_reset()
	_bgc._unlock_research(GameState.research_manager, boss_zone)
	if not hull in sm.hulls:
		return {"filled": 0, "total": 0}
	sm.active_hull = hull
	sm.loadout.clear()
	sm.ammo_loadout.clear()

	# Batteries FIRST — the equip guard blocks a consumer that overdraws, so the
	# supply has to exist before anything asks to draw on it.
	for slot in _bgc._slots(sm, "battery"):
		var bid := "z%d_battery" % clampi(batt_zone, 1, 10)
		var cid := str(sm.generate_module_drop(bid, 0, batt_zone))
		if cid != "":
			sm.equip_module(slot, cid, true)

	# Every consumer slot type, not just the offensive three — engine and sensor
	# draw power too (CONSUMER_SLOT_TYPES), and leaving them out would understate
	# the draw a real ship carries.
	const BASE_FOR := {
		"weapon": "z%d_kinetic", "armor": "z%d_armor", "shield": "z%d_shield",
		"engine": "z%d_engine", "sensor": "z%d_sensor",
	}
	var filled := 0
	var total := 0
	for stype in BASE_FOR:
		var base_id: String = (BASE_FOR[stype] as String) % boss_zone
		if not base_id in sm.modules:
			# No module of this type at this tier — not a power failure, so it is
			# not counted against the ship in either direction.
			continue
		for slot in _bgc._slots(sm, str(stype)):
			total += 1
			var cid := str(sm.generate_module_drop(base_id, 0, boss_zone))
			if cid != "" and sm.equip_module(slot, cid, true):
				filled += 1
	sm.recalc_stats()
	return {"filled": filled, "total": total}
