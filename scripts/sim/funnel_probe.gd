extends Node
# v132 new-player funnel walk (static). Walks the tutorial chain from m001 in
# next_mission order, accumulating the techs the chain DIRECTED the player to
# research, and checks every ask is reachable with only those techs:
#   gather  → some unlocked action/recipe/zone-loot/building can source it
#   craft   → module ungated (or gate taught) + cost elements sourceable
#   construct → hull gate taught
#   defeat  → enemy's zone gate taught
#   research→ parent chain already taught (undirected prereq = friction)
# Also keeps a credits ledger: directed rewards vs directed research costs.
# Run: godot --headless --path <repo> res://scenes/funnel_probe.tscn

var taught := {}          # tech_id -> true (directed by the chain, incl. forced parents)
var flags: int = 0

func _ready():
	await get_tree().process_frame
	var mm = GameState.mission_manager
	var rm = GameState.research_manager

	# chain order from m001
	var chain: Array = []
	var cur := "m001"
	var hop := 0
	while cur != "" and cur in mm.missions and hop < 200:
		chain.append(cur)
		cur = str(mm.missions[cur].get("next_mission", ""))
		hop += 1
	print("[funnel] chain length %d: m001 → %s" % [chain.size(), chain[-1]])

	var credits: float = 0.0
	var min_credits: float = 0.0
	var min_at := ""
	var pre_combat := true
	for mid in chain:
		var m = mm.missions[mid]
		var t := str(m.get("type", ""))
		var target = m.get("target")
		match t:
			"research":
				var tid := str(target)
				# undirected prereqs? (walk BOTH gating fields: parent + req_tech)
				var frontier: Array = [tid]
				var missing: Array = []
				while not frontier.is_empty():
					var node = rm.tech_tree.get(str(frontier.pop_back()), {})
					for key in ["parent", "req_tech"]:
						var p = node.get(key)
						if p != null and str(p) != "" and not taught.has(str(p)):
							missing.append(str(p))
							taught[str(p)] = true   # player is forced to buy it — count cost
							credits -= float(rm.tech_tree.get(str(p), {}).get("cost", 0)) * rm.COST_MULTIPLIER
							frontier.append(str(p))
				if not missing.is_empty():
					_flag("%s directs research '%s' but its prereq(s) %s were never directed" % [mid, tid, str(missing)])
				taught[tid] = true
				credits -= float(rm.tech_tree.get(tid, {}).get("cost", 0)) * rm.COST_MULTIPLIER
			"gather":
				_check_source(mid, str(target))
			"gather_multi":
				if target is Dictionary:
					for el in target:
						_check_source(mid, str(el))
			"craft":
				var mod = GameState.shipyard_manager.modules.get(str(target), {})
				var req = mod.get("research_req")
				if req and not taught.has(str(req)):
					_flag("%s asks to craft %s — module gated on UNDIRECTED tech '%s'" % [mid, target, req])
				for el in mod.get("cost", {}):
					if str(el) == "credits":
						credits -= float(mod["cost"][el])
					else:
						_check_source(mid, str(el))
			"construct":
				var hull = GameState.shipyard_manager.hulls.get(str(target), {})
				var hreq = hull.get("research_req")
				if hreq and not taught.has(str(hreq)):
					_flag("%s asks to construct %s — hull gated on UNDIRECTED tech '%s'" % [mid, target, hreq])
				credits -= float(hull.get("cost", {}).get("credits", 0))
			"defeat":
				var zid := _zone_of_enemy(str(target))
				if zid == "":
					_flag("%s targets enemy '%s' that is in NO zone roster" % [mid, target])
				else:
					var zreq = GameState.combat_manager.zones[zid].get("research_req")
					if zreq and not taught.has(str(zreq)):
						_flag("%s asks to defeat %s (%s) — zone gated on UNDIRECTED tech '%s'" % [mid, target, zid, zreq])
			_:
				pass
		credits += float(m.get("reward_cr", 0))
		if credits < min_credits:
			min_credits = credits
			min_at = mid
		# pre-first-combat dips are real walls (no combat income exists yet)
		if mid == "m017":
			pre_combat = false
		if credits < 0 and pre_combat:
			print("  💸 balance %+d after %s (PRE-combat)" % [int(credits), mid])

	print("")
	print("[credits ledger] directed rewards minus directed research/craft costs:")
	print("  end balance %+d | worst dip %+d at %s (combat/selling income excluded)" % [int(credits), int(min_credits), min_at])
	print("")
	print("[funnel] %d friction flags" % flags)
	get_tree().quit()

func _flag(msg: String):
	flags += 1
	print("  ⚑ " + msg)

func _zone_of_enemy(eid: String) -> String:
	for zid in GameState.combat_manager.zones:
		if eid in GameState.combat_manager.zones[zid].get("enemies", []):
			return zid
	return ""

# Is `el` producible with only taught techs? Reports the gating techs if not.
func _check_source(mid: String, el: String):
	var blockers := {}
	if _sourceable(el, 6, blockers, {}):
		return
	if blockers.is_empty():
		_flag("%s asks for '%s' — NO source found at all (dead ask?)" % [mid, el])
	else:
		_flag("%s asks for '%s' — every source locked behind UNDIRECTED tech(s): %s" % [mid, el, str(blockers.keys())])

func _sourceable(el: String, depth: int, blockers: Dictionary, seen: Dictionary) -> bool:
	if depth <= 0 or seen.has(el):
		return false
	seen[el] = true
	var ok := false
	# gather actions
	for aid in GameState.gathering_manager.actions:
		var a = GameState.gathering_manager.actions[aid]
		var drops := false
		for entry in a.get("loot_table", []):
			if str(entry[0]) == el:
				drops = true
		if not drops: continue
		var req = a.get("research_req")
		if req == null or str(req) == "" or taught.has(str(req)):
			ok = true
		else:
			blockers[str(req)] = true
	# zone loot (incl. rare)
	for zid in GameState.combat_manager.zones:
		var z = GameState.combat_manager.zones[zid]
		var in_zone := false
		for eid in z.get("enemies", []):
			var e = GameState.combat_manager.enemy_db.get(eid, {})
			for entry in e.get("loot", []) + e.get("rare_loot", []):
				if str(entry[0]) == el:
					in_zone = true
		if not in_zone: continue
		var zreq = z.get("research_req")
		if zreq == null or str(zreq) == "" or taught.has(str(zreq)):
			ok = true
		else:
			blockers[str(zreq)] = true
	# buildings
	for bid in GameState.infrastructure_manager.building_db:
		var b = GameState.infrastructure_manager.building_db[bid]
		if not b.get("production", {}).has(el): continue
		var breq = b.get("research_req")
		if breq == null or str(breq) == "" or taught.has(str(breq)):
			ok = true
		else:
			blockers[str(breq)] = true
	# recipes (inputs must be recursively sourceable)
	for rid in GameState.processing_manager.recipes:
		var r = GameState.processing_manager.recipes[rid]
		if not r.get("output", {}).has(el): continue
		var rreq = r.get("research_req")
		if rreq != null and str(rreq) != "" and not taught.has(str(rreq)):
			blockers[str(rreq)] = true
			continue
		var inputs_ok := true
		for iel in r.get("input", {}):
			var sub_seen := seen.duplicate()
			if not _sourceable(str(iel), depth - 1, blockers, sub_seen):
				inputs_ok = false
				break
		if inputs_ok:
			ok = true
	return ok
