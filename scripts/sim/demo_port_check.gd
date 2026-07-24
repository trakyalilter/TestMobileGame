extends Node
# v141 port verify: affix research gate + Field Manual mission wiring.
# No hard_reset / no save writes. Run with --user-dir <scratch>.
func _ready() -> void:
	var fails := 0
	var sm = GameState.shipyard_manager
	var rm = GameState.research_manager
	var mm = GameState.mission_manager

	# Affix gate: stone_drop_mult (research_req firmware_hacking) out of pool until unlocked.
	rm.unlocked_techs.erase("firmware_hacking")
	var locked_pool: Array = sm._legal_affix_pool("sensor")
	var c1 := not ("stone_drop_mult" in locked_pool)
	rm.unlocked_techs.append("firmware_hacking")
	var open_pool: Array = sm._legal_affix_pool("sensor")
	var c2 := "stone_drop_mult" in open_pool
	rm.unlocked_techs.erase("firmware_hacking")
	# dedup: generate_module_drop must not crash + produce a module id.
	var mid: String = sm.generate_module_drop("z1_sensor", sm.Rarity.RARE, 2) if "z1_sensor" in sm.modules else sm.generate_module_drop(sm.modules.keys()[0], sm.Rarity.RARE, 2)
	var c3 := mid != ""

	# Field Manual chain: m019d -> m019e (atlas_lookup Res1) -> m025.
	var e: Dictionary = mm.missions.get("m019e", {})
	var c4 := not e.is_empty() and String(e.get("type","")) == "atlas_lookup" and String(e.get("target","")) == "Res1"
	var c5 := String(mm.missions.get("m019d", {}).get("next_mission","")) == "m019e"
	var c6 := String(e.get("next_mission","")) == "m025"

	for pair in [["affix gated when locked", c1], ["affix present when unlocked", c2],
			["generate_module_drop ok", c3], ["m019e atlas_lookup Res1", c4],
			["m019d -> m019e", c5], ["m019e -> m025", c6]]:
		if not pair[1]: fails += 1
		print("[DEMOPORT] %-32s %s" % [pair[0], "OK" if pair[1] else "*** FAIL"])
	print("[DEMOPORT] %s" % ("ALL PASS" if fails == 0 else "*** %d FAIL" % fails))
	get_tree().quit(1 if fails > 0 else 0)
