extends Node
# MODULE REACHABILITY GUARD — the composer's own rule 4.
#
# shipyard_manager states it plainly: "nothing may be unbuildable when its zone
# unlocks" (see COST_ZONE_PROC_LEVEL). That rule is enforced when the composer
# places an ANCHOR and when it LIFTS a shallow ingredient — but not on the
# composite bands, which bill whatever material the authored dict happens to
# name. So a module can ship with an ingredient the player provably cannot make
# yet, and nothing anywhere notices.
#
# For every module, this asks of each DIRECT ingredient in its composed cost:
# at this module's zone, can the player obtain this at all? Obtainable means one
# of — gathered, produced by a building, dropped by an enemy of that zone or
# earlier, or craftable at or below the processing level the zone expects.
#
#   Godot --headless --path <root> res://scenes/module_reach_check.tscn

var fails: int = 0

# symbol -> lowest processing level that can make it ("" source kinds are free)
var _craft_lvl: Dictionary = {}
var _from_building: Dictionary = {}
var _from_gather: Dictionary = {}
var _drop_zone: Dictionary = {}   # symbol -> lowest zone that drops it

func _ready() -> void:
	await get_tree().process_frame
	GameState.set_process(false)
	var sm = GameState.shipyard_manager
	var pm = GameState.processing_manager
	var im = GameState.infrastructure_manager
	var cm = GameState.combat_manager

	for rid in pm.recipes:
		var r: Dictionary = pm.recipes[rid]
		var lvl: int = int(r.get("level_req", 1))
		for sym in r.get("output", {}):
			var k := String(sym)
			if not _craft_lvl.has(k) or lvl < int(_craft_lvl[k]):
				_craft_lvl[k] = lvl
	for bid in im.building_db:
		for sym in im.building_db[bid].get("yield", {}):
			_from_building[String(sym)] = true
	for aid in GameState.gathering_manager.actions:
		for row in GameState.gathering_manager.actions[aid].get("loot_table", []):
			_from_gather[String((row as Array)[0])] = true
	for eid in cm.enemy_db:
		var e: Dictionary = cm.enemy_db[eid]
		var z: int = int(e.get("zone", 99))
		for key in ["loot", "rare_loot"]:
			for row in e.get(key, []):
				var sy := String((row as Array)[0])
				if not _drop_zone.has(sy) or z < int(_drop_zone[sy]):
					_drop_zone[sy] = z

	print("[REACH] sources indexed: %d craftable, %d building, %d gathered, %d dropped" % [
		_craft_lvl.size(), _from_building.size(), _from_gather.size(), _drop_zone.size()])

	var checked := 0
	var gem_unsourced := 0
	for mid in sm.modules:
		var m: Dictionary = sm.modules[mid]
		var zone: int = int(m.get("zone", 0))
		if zone <= 0 or not sm.COST_ZONE_PROC_LEVEL.has(zone):
			continue   # relics, exotics with no zone curve, etc.
		# Matrix cores are fused FROM cores, and cores have no faucet anywhere in
		# the game — a known-open owner decision (see docs/HANDOFF.md, 2026-08-02
		# economy audit), not a rule-4 break the composer introduced. Counted and
		# reported separately so this guard stays actionable instead of permanently
		# red on a design question it cannot answer.
		var st := String(m.get("slot_type", ""))
		if st == "gem" or st == "gem_synth":
			gem_unsourced += 1
			continue
		var expect_lvl: int = int(sm.COST_ZONE_PROC_LEVEL[zone])
		checked += 1
		for sym in m.get("cost", {}):
			var k := String(sym)
			if k == "credits":
				continue
			var why := _unreachable_reason(k, zone, expect_lvl)
			if why != "":
				_fail("%s (zone %d, expects proc lvl %d) bills %s — %s" % [mid, zone, expect_lvl, k, why])

	print("[REACH] %d zoned modules checked" % checked)
	if gem_unsourced > 0:
		print("[REACH] NOTE: %d matrix-core modules skipped — cores have no faucet (open owner decision)" % gem_unsourced)
	print("[REACH] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


# "" when reachable; otherwise why not.
func _unreachable_reason(sym: String, zone: int, expect_lvl: int) -> String:
	if _from_gather.has(sym) or _from_building.has(sym):
		return ""
	if _drop_zone.has(sym) and int(_drop_zone[sym]) <= zone:
		return ""
	if _craft_lvl.has(sym):
		var lvl: int = int(_craft_lvl[sym])
		if lvl <= expect_lvl:
			return ""
		return "craftable only at processing level %d" % lvl
	if _drop_zone.has(sym):
		return "drops only from zone %d" % int(_drop_zone[sym])
	return "no producer anywhere (no recipe, building, gather or drop)"


func _fail(msg: String) -> void:
	print("[REACH] FAIL: %s" % msg)
	fails += 1
