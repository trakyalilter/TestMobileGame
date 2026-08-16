extends SceneTree
## Dumps the live MissionFlow data into the JSON shapes tools/gen_data.py consumes.
func _init() -> void: process_frame.connect(_run, CONNECT_ONE_SHOT)

func _w(name: String, data) -> void:
	var f := FileAccess.open("/tmp/export/" + name, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	print("%-24s %d" % [name, (data.size() if (data is Dictionary or data is Array) else 0)])

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/export")
	var gs = root.get_node("GameState")
	var cm = gs.combat_manager
	var sm = gs.shipyard_manager
	var rm = gs.research_manager
	_w("enemies.json", cm.enemy_db)
	_w("zones.json", cm.zones)
	_w("hazard_zones.json", cm.hazard_zones)
	_w("trinity_sets.json", cm.TRINITY_SET_BONUSES)
	_w("tech_tree.json", rm.tech_tree)
	_w("recipes.json", gs.processing_manager.recipes)
	_w("gather.json", gs.gathering_manager.actions)
	_w("buildings.json", gs.infrastructure_manager.building_db)
	_w("modules.json", sm.modules)
	_w("hulls.json", sm.hulls)
	_w("missions.json", gs.mission_manager.missions)
	if "GEM_EFFECTS" in sm: _w("gems.json", sm.GEM_EFFECTS)
	if "repeatable_tech_db" in rm and rm.repeatable_tech_db.size() > 0:
		_w("repeatable_tech.json", rm.repeatable_tech_db)
	var consts := {}
	for c in ["DEF_K_CONSTANT", "DEF_K_ZONE_SCALE", "DEF_K_ZONE_EXP", "MAX_DAMAGE_REDUCTION"]:
		if c in cm: consts[c] = cm.get(c)
	_w("combat_consts.json", consts)
	quit()
