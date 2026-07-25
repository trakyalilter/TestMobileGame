extends Node
# ============================================================================
# TWO-STRIKE DURABILITY CHECK (v147)
#   strike 1 — a defeat wears equipped modules to 50%. NOTHING is destroyed.
#   strike 2 — a defeat taken while a module is ALREADY <=50% can destroy it
#              (owner spec: INDEPENDENT flat 50% roll per worn module, NO cap --
#              a full worn loadout can be wiped by one defeat).
# Also asserts the teardown is complete (the destroyed id must not survive in
# ANY container) and that socketed matrix cores come back to the player.
#   Godot --headless --path <root> res://scenes/durability_strike_check.tscn
# ============================================================================

var fails := 0
func _ok(nm: String, cond: bool, detail: String = "") -> void:
	if not cond: fails += 1
	print("[DUR] %-46s %s %s" % [nm, "OK" if cond else "*** FAIL", detail])

func _mk(sm, slot: int, mid: String, dur: int, sockets: Array = []) -> void:
	var d := {
		"id": mid, "name": mid.to_upper(), "slot_type": "weapon",
		"rarity": 2, "zone": 1, "is_custom": true, "base_module": "z1_kinetic",
		"durability": dur, "stats": {"atk_kinetic": 10}, "sockets": sockets.duplicate(),
	}
	sm.modules[mid] = d
	sm.custom_modules[mid] = d
	sm.loadout[slot] = mid
	sm.ammo_loadout[slot] = "SlugT1"

func _armed(sm) -> int:
	var n := 0
	for s in sm.loadout.keys():
		var m = sm.loadout[s]
		if m != null and String(m) != "":
			n += 1
	return n

func _ready() -> void:
	var sm = GameState.shipyard_manager
	GameState.set_process(false)
	GameState.hard_reset()
	sm.active_hull = "corvette_hull"
	print("[DUR] ============ two-strike durability check ============")

	# ── STRIKE 1: pristine gear is never destroyed, and lands at exactly 50. ──
	var s1_destroyed := 0
	for _t in range(300):
		sm.loadout.clear(); sm.ammo_loadout.clear()
		sm.modules.erase("custom_a"); sm.custom_modules.erase("custom_a")
		sm.modules.erase("custom_b"); sm.custom_modules.erase("custom_b")
		_mk(sm, 0, "custom_a", 100)
		_mk(sm, 1, "custom_b", 100)
		sm.handle_module_defeat()
		if _armed(sm) < 2:
			s1_destroyed += 1
	_ok("strike 1 never destroys (300 trials)", s1_destroyed == 0, "lost=%d" % s1_destroyed)
	_ok("strike 1 floors durability to 50",
		int(sm.modules["custom_a"]["durability"]) == 50 and int(sm.modules["custom_b"]["durability"]) == 50)

	# ── STRIKE 2: worn gear CAN die — one roll, at most one module. ──
	var trials := 3000
	var hits := 0
	var multi := 0
	for _t in range(trials):
		sm.loadout.clear(); sm.ammo_loadout.clear()
		for k in ["custom_w0", "custom_w1", "custom_w2", "custom_w3"]:
			sm.modules.erase(k); sm.custom_modules.erase(k)
		_mk(sm, 0, "custom_w0", 50)
		_mk(sm, 1, "custom_w1", 50)
		_mk(sm, 2, "custom_w2", 50)
		_mk(sm, 3, "custom_w3", 50)
		sm.handle_module_defeat()
		var lost := 4 - _armed(sm)
		if lost > 0: hits += 1
		if lost > 1: multi += 1
	var rate := float(hits) / float(trials)
	# 4 worn modules at an independent 0.5 each -> P(at least one lost) = 1-0.5^4 = 0.9375.
	_ok("strike 2: >=1 loss at ~1-0.5^n", rate > 0.90 and rate < 0.97, "rate=%.3f (want ~0.938)" % rate)
	# Multi-loss is now REQUIRED, not a bug: the owner rule is "you can lose all your
	# loadout or none". Assert it actually happens rather than that it cannot.
	_ok("strike 2 CAN lose multiple modules", multi > 0, "multi=%d" % multi)

	# ── TEARDOWN: the destroyed id must not survive anywhere. ──
	sm.loadout.clear(); sm.ammo_loadout.clear()
	sm.module_inventory.clear(); sm.unseen_modules.clear(); sm.armory_layout.clear()
	_mk(sm, 0, "custom_dead", 50, ["StableCrimsonCore", null])
	sm.unseen_modules["custom_dead"] = true
	sm.armory_layout["custom_dead"] = {"x": 0, "y": 0}
	sm.module_inventory["custom_dead"] = 1   # defensive: shouldn't happen while equipped
	for pi in [1, 2, 3]:
		sm.loadout_presets[pi]["loadout"] = {0: "custom_dead"}
		sm.loadout_presets[pi]["ammo_loadout"] = {0: "SlugT1"}
	var gems_before: int = int(GameState.resources.get_element_amount("StableCrimsonCore"))

	var disp: String = sm._destroy_equipped_module(0)
	_ok("teardown returns display name", disp == "CUSTOM_DEAD", disp)
	_ok("teardown clears loadout slot", sm.loadout.get(0) == null)
	_ok("teardown clears ammo binding", not sm.ammo_loadout.has(0) and not sm.ammo_loadout.has("0"))
	_ok("teardown erases modules", not sm.modules.has("custom_dead"))
	_ok("teardown erases custom_modules", not sm.custom_modules.has("custom_dead"))
	_ok("teardown erases module_inventory", not sm.module_inventory.has("custom_dead"))
	_ok("teardown erases unseen_modules", not sm.unseen_modules.has("custom_dead"))
	_ok("teardown erases armory_layout", not sm.armory_layout.has("custom_dead"))
	var presets_clean := true
	for pi in sm.loadout_presets.keys():
		var pl = sm.loadout_presets[pi].get("loadout", {})
		for sk in pl.keys():
			if pl[sk] != null and String(pl[sk]) == "custom_dead":
				presets_clean = false
	_ok("teardown scrubs every build preset", presets_clean)
	var gems_after: int = int(GameState.resources.get_element_amount("StableCrimsonCore"))
	_ok("socketed matrix core refunded (remove_gem parity)", gems_after == gems_before + 1,
		"before=%d after=%d" % [gems_before, gems_after])

	# ── OFFLINE PARITY: never harsher than one online defeat, never >1 module. ──
	var off_hits := 0
	var off_multi := 0
	for _t in range(3000):
		sm.loadout.clear(); sm.ammo_loadout.clear()
		for k in ["custom_o0", "custom_o1", "custom_o2", "custom_o3"]:
			sm.modules.erase(k); sm.custom_modules.erase(k)
		_mk(sm, 0, "custom_o0", 50)
		_mk(sm, 1, "custom_o1", 50)
		_mk(sm, 2, "custom_o2", 50)
		_mk(sm, 3, "custom_o3", 50)
		var lost_names: Array = sm.apply_offline_durability_risk(28800.0)   # 8 hours
		if lost_names.size() > 0: off_hits += 1
		if lost_names.size() > 1: off_multi += 1
	var off_rate := float(off_hits) / 3000.0
	# Offline stays deliberately gentler than online: ONE roll, at most one module,
	# ramped over the first hour. Offline combat is winnability-gated so it never
	# produces a real defeat, and the player is not present to react.
	_ok("offline 8h capped at one-module risk", off_rate > 0.44 and off_rate < 0.56, "rate=%.3f" % off_rate)
	_ok("offline never loses >1 module", off_multi == 0, "multi=%d" % off_multi)

	# Pristine gear is safe offline no matter how long the absence.
	sm.loadout.clear(); sm.ammo_loadout.clear()
	sm.modules.erase("custom_p"); sm.custom_modules.erase("custom_p")
	_mk(sm, 0, "custom_p", 100)
	var safe := true
	for _t in range(300):
		if sm.apply_offline_durability_risk(86400.0).size() > 0:
			safe = false
	_ok("offline never touches modules above 50%", safe)

	print("[DUR] %s" % ("ALL PASS" if fails == 0 else "*** %d FAILURE(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
