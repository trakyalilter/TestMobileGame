extends SceneTree
## Threshold Relic (v113 NG+ P2) — the master-key lifecycle.
##
## The dangerous part is the interaction with Warp. The relic is granted ONCE and
## flagged earned, but Warp wipes module_inventory: without an explicit re-grant
## the key vanishes on the first Warp and the earned flag guarantees it can never
## drop again, permanently un-farming the gate boss. That path is tested here.

var _fail := false

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		print("PASS %s" % label)
	else:
		print("FAIL %s%s" % [label, ("  — " + detail) if detail != "" else ""])
		_fail = true

## A combat-ready enemy_inst built from the real row, so _win_combat finds every
## field it reads (xp, loot, drop pools) instead of tripping on a stub.
func _spawn(gd, eid: String) -> Dictionary:
	var e: Dictionary = (gd.ENEMIES[eid] as Dictionary).duplicate(true)
	e["id"] = eid
	e["hp"] = 0.0
	e["shield"] = 0.0
	e["def"] = 0.0
	return e

func _run() -> void:
	var gs = root.get_node("GameState")
	var gd = root.get_node("GameData")

	# ---- the data the feature rests on ----
	var relic := ""
	var dropper := ""
	for eid in gd.ENEMIES:
		var rd := String((gd.ENEMIES[eid] as Dictionary).get("relic_drop", ""))
		if rd != "":
			relic = rd
			dropper = String(eid)
			break
	_ok(relic != "", "an enemy declares a relic_drop", "relic=%s from=%s" % [relic, dropper])
	if relic == "":
		print("RELIC: FAIL")
		quit()
		return
	var r: Dictionary = gd.MODULES.get(relic, {})
	_ok(String(r.get("slot", "")) == "relic", "the relic uses the relic slot")
	var zone_id := String(r.get("relic_zone", ""))
	_ok(zone_id != "", "the relic names the sector it is keyed to", "zone=%s" % zone_id)
	_ok(float(r.get("relic_reduction", 0.0)) > 0.0, "the relic carries a reduction",
		"reduction=%.2f" % float(r.get("relic_reduction", 0.0)))

	# ---- it is inert before it is earned ----
	gs.equipped_relic = ""
	gs.module_inventory.erase(relic)
	gs.game_flags.erase(relic + "_earned")
	_ok(is_equal_approx(gs.relic_reduction_factor(zone_id), 1.0), "no relic means no reduction")

	# ---- first clear grants it, auto-equipped ----
	gs.enemy_inst = _spawn(gd, dropper)
	gs.active_id = dropper
	gs._win_combat()
	_ok(int(gs.module_inventory.get(relic, 0)) >= 1, "first clear grants the relic")
	_ok(bool(gs.game_flags.get(relic + "_earned", false)), "the earned flag is set")
	_ok(gs.equipped_relic == relic, "it auto-equips into an empty slot")

	# ---- the reduction applies ONLY in its keyed sector ----
	var f_in: float = gs.relic_reduction_factor(zone_id)
	var f_out: float = gs.relic_reduction_factor("lunar_orbit")
	_ok(f_in < 1.0, "damage is cut inside the keyed sector", "factor=%.3f" % f_in)
	_ok(is_equal_approx(f_out, 1.0), "it is inert in every other sector", "factor=%.3f" % f_out)
	_ok(abs(f_in - (1.0 - float(r.get("relic_reduction", 0.0)))) < 0.001,
		"the factor matches the declared reduction")

	# ---- a second clear does not duplicate it ----
	var before := int(gs.module_inventory.get(relic, 0))
	gs.enemy_inst = _spawn(gd, dropper)
	gs._win_combat()
	_ok(int(gs.module_inventory.get(relic, 0)) == before, "re-killing the boss does not duplicate the key")

	# ---- THE WARP PATH: inventory is wiped, the key must survive ----
	gs.warp_shards = 999.0
	gs.credits = 999999999
	gs.execute_warp()
	_ok(int(gs.module_inventory.get(relic, 0)) >= 1, "the relic survives a Warp (re-granted)",
		"held=%d" % int(gs.module_inventory.get(relic, 0)))
	_ok(gs.equipped_relic == relic, "it is re-equipped after the Warp")
	_ok(gs.relic_reduction_factor(zone_id) < 1.0, "it still works after the Warp")

	# ---- unequip / re-equip ----
	gs.unequip_relic()
	_ok(gs.equipped_relic == "", "unequip clears the slot")
	_ok(is_equal_approx(gs.relic_reduction_factor(zone_id), 1.0), "an unequipped relic does nothing")
	_ok(gs.equip_relic(relic), "it can be re-equipped")
	_ok(gs.equipped_relic == relic, "the slot holds it again")

	# ---- a hard reset must re-lock it ----
	gs.hard_reset()
	_ok(not bool(gs.game_flags.get(relic + "_earned", false)),
		"hard reset un-earns the key so a fresh run must win it again")

	print("RELIC: %s" % ("FAIL" if _fail else "PASS"))
	quit()
