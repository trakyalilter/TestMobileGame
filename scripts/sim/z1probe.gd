extends Node

func _ready() -> void:
	GameState.hard_reset()
	GameState.set_seed(1) if GameState.has_method("set_seed") else null
	var sm = GameState.shipyard_manager
	var gm = GameState.gathering_manager
	var pm = GameState.processing_manager
	var rm = GameState.research_manager

	print("=== levels: g", gm.get_level(), " p", pm.get_level(), " hull=", sm.active_hull)
	print("=== slots: ", sm.hulls.get(sm.active_hull, {}).get("slots", []))

	for mid in ["z1_kinetic", "z1_missile", "z1_battery", "z1_energy"]:
		if not mid in sm.modules:
			print("MODULE MISSING: ", mid); continue
		var m = sm.modules[mid]
		var cost = sm.get_effective_module_cost(m)
		print("\n--- ", mid, " research_req=", m.get("research_req"), " cost=", cost)
		for sym in cost:
			if String(sym) == "credits":
				continue
			_explain_material(String(sym), 0)

	print("\n=== ammo recipes ===")
	for rid in ["craft_slug_t1", "craft_cell_t1", "craft_missile_t1"]:
		if rid in pm.recipes:
			var r = pm.recipes[rid]
			print(rid, " lvl_req=", r.get("level_req",1), " research_req=", r.get("research_req"), " input=", r.get("input"), " output=", r.get("output"))

	get_tree().quit()

func _explain_material(sym: String, depth: int) -> void:
	var pad := ""
	for i in range(depth): pad += "  "
	var gm = GameState.gathering_manager
	var pm = GameState.processing_manager
	# gather sources
	var gsrc := []
	for aid in gm.actions:
		for entry in gm.actions[aid].get("loot_table", []):
			if String(entry[0]) == sym:
				gsrc.append("%s(lvl%d,res=%s)" % [aid, int(gm.actions[aid].get("level_req",1)), str(gm.actions[aid].get("research_req"))])
	# recipe sources
	var rsrc := []
	for rid in pm.recipes:
		if sym in pm.recipes[rid].get("output", {}):
			var r = pm.recipes[rid]
			rsrc.append("%s(lvl%d,res=%s,in=%s)" % [rid, int(r.get("level_req",1)), str(r.get("research_req")), str(r.get("input"))])
	print(pad, sym, "  GATHER<", gsrc, ">  RECIPE<", rsrc, ">")
	if depth < 2 and gsrc.is_empty() and not rsrc.is_empty():
		# recurse into first recipe inputs
		var rid0 = ""
		for rid in pm.recipes:
			if sym in pm.recipes[rid].get("output", {}):
				rid0 = rid; break
		if rid0 != "":
			for inp in pm.recipes[rid0].get("input", {}):
				_explain_material(String(inp), depth + 1)
