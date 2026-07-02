extends Node
# v132 content cross-reference integrity probe.
# Every id referenced by actions/recipes/enemies/zones/hazards/missions/
# buildings/research/quests must exist in its registry, and every explicit
# recipe category must be reachable via a processing-page tab.
# Run: godot --headless --path <repo> res://scenes/integrity_probe.tscn

var issues: int = 0
var warns: int = 0

func _ready():
	await get_tree().process_frame
	var valid_elements := _collect_valid_elements()
	print("[registry] elements=%d techs=%d actions=%d recipes=%d enemies=%d zones=%d hazards=%d buildings=%d modules=%d" % [
		valid_elements.size(),
		GameState.research_manager.tech_tree.size(),
		GameState.gathering_manager.actions.size(),
		GameState.processing_manager.recipes.size(),
		GameState.combat_manager.enemy_db.size(),
		GameState.combat_manager.zones.size(),
		GameState.combat_manager.hazard_zones.size(),
		GameState.infrastructure_manager.building_db.size(),
		GameState.shipyard_manager.modules.size(),
	])

	_check_gathering(valid_elements)
	_check_recipes(valid_elements)
	_check_enemies(valid_elements)
	_check_zones_hazards(valid_elements)
	_check_buildings(valid_elements)
	_check_missions(valid_elements)
	_check_research_reqs()
	_check_quests(valid_elements)

	print("")
	if issues == 0:
		print("[integrity] CLEAN — 0 broken refs, %d warnings" % warns)
	else:
		print("[integrity] %d BROKEN refs, %d warnings" % [issues, warns])
	get_tree().quit()

func _err(msg: String):
	issues += 1
	print("  ✖ " + msg)

func _warn(msg: String):
	warns += 1
	print("  ⚠ " + msg)

func _collect_valid_elements() -> Dictionary:
	var v := {}
	for e in GameState.elements_db:
		v[str(e.get("symbol", ""))] = true
	for k in ElementDB.ELEMENT_NAMES:
		v[str(k)] = true
	v["credits"] = true   # loot tables use it as a pseudo-element
	return v

func _tech_exists(tid) -> bool:
	if tid == null or str(tid) == "":
		return true
	var rm = GameState.research_manager
	return str(tid) in rm.tech_tree or str(tid) in rm.repeatable_tech_db

# ── gathering ──────────────────────────────────────────────────────────
func _check_gathering(valid: Dictionary):
	print("[gathering actions]")
	for aid in GameState.gathering_manager.actions:
		var a = GameState.gathering_manager.actions[aid]
		for entry in a.get("loot_table", []):
			var el = str(entry[0])
			if not valid.has(el):
				_err("action %s drops unknown element '%s'" % [aid, el])
		if not _tech_exists(a.get("research_req")):
			_err("action %s gated on missing tech '%s'" % [aid, a.get("research_req")])

# ── processing ─────────────────────────────────────────────────────────
const TAB_CATS := ["basics", "smelting", "alloys", "materials", "electronics",
	"components", "salvage", "batteries", "munitions_kinetic", "munitions_energy",
	"munitions_explosive", "consumables_hull", "consumables_shield", "research", "endgame"]

func _check_recipes(valid: Dictionary):
	print("[recipes]")
	for rid in GameState.processing_manager.recipes:
		var r = GameState.processing_manager.recipes[rid]
		for el in r.get("input", {}):
			if not valid.has(str(el)):
				_err("recipe %s consumes unknown element '%s'" % [rid, el])
		for el in r.get("output", {}):
			if not valid.has(str(el)):
				_err("recipe %s produces unknown element '%s'" % [rid, el])
		if not _tech_exists(r.get("research_req")):
			_err("recipe %s gated on missing tech '%s'" % [rid, r.get("research_req")])
		var cat = r.get("category", "")
		if cat != "" and not cat in TAB_CATS:
			_err("recipe %s category '%s' has NO processing-page tab (invisible in-game)" % [rid, cat])

# ── combat ─────────────────────────────────────────────────────────────
func _check_enemies(valid: Dictionary):
	print("[enemies]")
	var sm = GameState.shipyard_manager
	for eid in GameState.combat_manager.enemy_db:
		var e = GameState.combat_manager.enemy_db[eid]
		for entry in e.get("loot", []):
			# main loot is element/credits only — the online handler add_element()s
			# blindly here, so a module id in THIS table would corrupt inventory
			if not valid.has(str(entry[0])):
				_err("enemy %s loot has unknown element '%s'" % [eid, entry[0]])
		for entry in e.get("rare_loot", []):
			# rare_loot may be an element OR a module id (win_fight branches)
			var lid := str(entry[0])
			if not valid.has(lid) and not lid in sm.modules:
				_err("enemy %s rare_loot id '%s' is neither element nor module" % [eid, lid])
		var core = str(e.get("boss_core", ""))
		if core != "" and not valid.has(core):
			_err("enemy %s boss_core unknown element '%s'" % [eid, core])
		for mid in e.get("module_drop_pool", []):
			if not str(mid) in sm.modules:
				_err("enemy %s drops unknown module '%s'" % [eid, mid])

func _check_zones_hazards(valid: Dictionary):
	print("[zones + hazards]")
	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager
	for zid in cm.zones:
		var z = cm.zones[zid]
		for eid in z.get("enemies", []):
			if not str(eid) in cm.enemy_db:
				_err("zone %s roster has unknown enemy '%s'" % [zid, eid])
		if not _tech_exists(z.get("research_req")):
			_err("zone %s gated on missing tech '%s'" % [zid, z.get("research_req")])
	for hid in cm.hazard_zones:
		var hz = cm.hazard_zones[hid]
		for eid in hz.get("enemy_pool", []):
			if not str(eid) in cm.enemy_db:
				_err("hazard %s pool has unknown enemy '%s'" % [hid, eid])
		for key in ["elite_enemy", "boss_enemy"]:
			var eid = str(hz.get(key, ""))
			if eid != "" and not eid in cm.enemy_db:
				_err("hazard %s %s unknown enemy '%s'" % [hid, key, eid])
		var ub = str(hz.get("unlock_boss", ""))
		if ub != "" and not ub in cm.enemy_db:
			_err("hazard %s unlock_boss unknown enemy '%s'" % [hid, ub])
		var counter = str(hz.get("counter_module", ""))
		if counter != "" and not counter in sm.modules:
			_err("hazard %s counter_module unknown module '%s'" % [hid, counter])
		var reward = str(hz.get("first_clear_reward", ""))
		if reward != "" and not valid.has(reward):
			_err("hazard %s first_clear_reward unknown element '%s'" % [hid, reward])

# ── infrastructure ─────────────────────────────────────────────────────
func _check_buildings(valid: Dictionary):
	print("[buildings]")
	for bid in GameState.infrastructure_manager.building_db:
		var b = GameState.infrastructure_manager.building_db[bid]
		for el in b.get("cost", {}):
			if str(el) != "credits" and not valid.has(str(el)):
				_err("building %s cost has unknown element '%s'" % [bid, el])
		for el in b.get("production", {}):
			if not valid.has(str(el)):
				_err("building %s produces unknown element '%s'" % [bid, el])
		for el in b.get("upkeep", {}):
			if str(el) != "credits" and not valid.has(str(el)):
				_err("building %s upkeep has unknown element '%s'" % [bid, el])
		if not _tech_exists(b.get("research_req")):
			_err("building %s gated on missing tech '%s'" % [bid, b.get("research_req")])

# ── missions ───────────────────────────────────────────────────────────
func _check_missions(valid: Dictionary):
	print("[missions]")
	var mm = GameState.mission_manager
	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager
	var seen_types := {}
	for mid in mm.missions:
		var m = mm.missions[mid]
		var t = str(m.get("type", ""))
		seen_types[t] = seen_types.get(t, 0) + 1
		var target = m.get("target")
		var nid = str(m.get("next_mission", ""))
		if nid != "" and not nid in mm.missions:
			_err("mission %s next_mission '%s' does not exist" % [mid, nid])
		match t:
			"gather", "sell":
				if target is Dictionary:
					for el in target:
						if str(el) != "credits" and not valid.has(str(el)):
							_err("mission %s targets unknown element '%s'" % [mid, el])
				elif str(target) != "credits" and not valid.has(str(target)):
					_err("mission %s targets unknown element '%s'" % [mid, target])
			"research":
				if target is Dictionary or target is Array:
					for tid in target:
						if not _tech_exists(tid):
							_err("mission %s targets missing tech '%s'" % [mid, tid])
				elif not _tech_exists(target):
					_err("mission %s targets missing tech '%s'" % [mid, target])
			"craft", "module":
				if not str(target) in sm.modules:
					_err("mission %s targets unknown module '%s'" % [mid, target])
			"defeat":
				if not str(target) in cm.enemy_db:
					_err("mission %s targets unknown enemy '%s'" % [mid, target])
			"discover":
				if not (str(target) in cm.zones or str(target) in cm.hazard_zones):
					_err("mission %s targets unknown zone '%s'" % [mid, target])
			"construct":
				# fires on hull_constructed → targets are HULL ids
				if not str(target) in sm.hulls:
					_err("mission %s targets unknown hull '%s'" % [mid, target])
			"build":
				# fires on building_constructed → building ids
				if not str(target) in GameState.infrastructure_manager.building_db:
					_err("mission %s targets unknown building '%s'" % [mid, target])
			"loadout_check":
				# target is a slot_type keyword (or the combat_ready composite)
				if str(target) != "combat_ready":
					var slot_types := {}
					for m_id in sm.modules:
						slot_types[str(sm.modules[m_id].get("slot_type", ""))] = true
					if not slot_types.has(str(target)):
						_err("mission %s loadout_check slot_type '%s' matches no module" % [mid, target])
			"equip_consumables":
				if int(str(m.get("target"))) <= 0:
					_err("mission %s equip_consumables target '%s' is not a positive count" % [mid, target])
			_:
				pass   # counter-driven types (warp, hack_apply, …) have no registry
	print("  mission types seen: %s" % str(seen_types))

# ── research back-refs ─────────────────────────────────────────────────
func _check_research_reqs():
	print("[research gates]")
	# Ammo/consumable gates: ELEMENT_RESEARCH_REQS {element_id: tech_id}.
	# can_equip_module only consults this map for ids found in the ammo or
	# consumables ElementDB categories — a key outside both is a DEAD gate
	# (the item equips ungated or doesn't exist at all).
	var sm = GameState.shipyard_manager
	var reqs = sm.get("ELEMENT_RESEARCH_REQS")
	if reqs != null:
		var gateable := {}
		for id in ElementDB.CATEGORIES.get("ammo", []):
			gateable[str(id)] = true
		for id in ElementDB.CATEGORIES.get("consumables", []):
			gateable[str(id)] = true
		for mid in reqs:
			if not gateable.has(str(mid)):
				_err("ELEMENT_RESEARCH_REQS key '%s' not in ammo/consumables categories — gate is DEAD" % mid)
			if not _tech_exists(reqs[mid]):
				_err("gate for '%s' points at missing tech '%s'" % [mid, reqs[mid]])
	# Tech prereqs must reference real techs
	var rm = GameState.research_manager
	for tid in rm.tech_tree:
		for pre in rm.tech_tree[tid].get("requires", []):
			if not _tech_exists(pre):
				_err("tech %s requires missing tech '%s'" % [tid, pre])
		for el in rm.tech_tree[tid].get("cost_items", {}):
			if not ElementDB.ELEMENT_NAMES.has(str(el)) and GameState.get_element_data(str(el)).is_empty():
				_err("tech %s costs unknown element '%s'" % [tid, el])

# ── quests ─────────────────────────────────────────────────────────────
func _check_quests(valid: Dictionary):
	print("[quests]")
	var qm = GameState.quest_manager
	if qm == null:
		return
	for k in qm.material_rewards:
		for mat in qm.material_rewards[k]:
			# entries are [element_id, min, max]
			var mid = mat[0] if mat is Array else mat
			if not valid.has(str(mid)):
				_err("quest material_rewards[%s] unknown element '%s'" % [k, mid])
