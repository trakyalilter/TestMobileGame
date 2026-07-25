extends RefCounted

# ============================================================================
# mission_actions — stateless (mission type, target) -> concrete-verb resolver
# for the player-like bot (v135). The ONE content-coupled piece of the sim,
# isolated so chain edits break HERE (loudly, via dry_walk_chain) and nowhere
# else. Pure READS of live game state — it never performs actions, never
# spends, never grants; the policy executes what this returns.
#
# Autoloads (GameState / ElementDB) are global identifiers — referenced
# directly (isolated --check-only flags them; a full headless boot resolves).
# ============================================================================

# Hack-stone symbols have NO loot-table/recipe source: they drop from a
# code-level roll in combat_manager._roll_hack_stone_drops (per-kill chance in
# ANY zone, gated on firmware_hacking research). Documented named exception to
# the "everything scanned from live tables" rule.
const HACK_STONE_SYMBOLS := ["SpliceChip", "FirmwareInjector", "RootKey",
	"AnchorBolt", "CorruptionWorm", "RefitBay", "SignalCalibrator"]

const KNOWN_PAGES := ["gathering", "processing", "infrastructure", "shipyard",
	"research", "combat", "mission", "designer", "inventory", "options",
	"atlas", "bounty", "quest", "warp", "fleet"]

# ---------------------------------------------------------------------------
# Top-level: mission dict (mission_manager.missions[mid]) -> verb dict.
# ---------------------------------------------------------------------------
func resolve(m: Dictionary) -> Dictionary:
	var t := String(m.get("type", ""))
	var target = m.get("target")
	match t:
		"gather":
			return {"verb": "acquire", "sym": String(target),
				"need": float(m.get("target_qty", 1)) - float(m.get("current_qty", 0))}
		"gather_multi":
			# Scarcest missing symbol vs its own target (player works the list).
			var worst := ""
			var worst_frac := 2.0
			for sym in target:
				var need := float(target[sym])
				if need <= 0.0:
					continue
				var prog := float(m.get("multi_progress", {}).get(sym, 0.0))
				var frac := prog / need
				if frac < worst_frac:
					worst_frac = frac
					worst = String(sym)
			if worst == "":
				return {"verb": "wait"}
			return {"verb": "acquire", "sym": worst,
				"need": float(target[worst]) - float(m.get("multi_progress", {}).get(worst, 0.0))}
		"research":
			return {"verb": "research", "tid": String(target)}
		"research_multi":
			for tid in target:
				if not GameState.research_manager.is_tech_unlocked(String(tid)):
					return {"verb": "research", "tid": String(tid)}
			return {"verb": "wait"}
		"craft":
			return {"verb": "craft", "mid": String(target),
				"count": int(m.get("target_qty", 1)) - int(m.get("current_qty", 0))}
		"construct":
			return {"verb": "construct", "hid": String(target)}
		"build":
			return {"verb": "build", "bid": String(target)}
		"loadout_check":
			return {"verb": "equip_slot", "slot_type": String(target),
				"count": int(m.get("target_qty", 1))}
		"equip_consumables":
			return {"verb": "equip_kits", "count": int(str(target))}
		"visit_page":
			return {"verb": "auto_ui", "page": String(target)}
		"defeat":
			var zid := zone_of_enemy(String(target))
			if zid == "":
				return {"verb": "unmapped", "why": "enemy %s in no zone roster" % target}
			return {"verb": "combat", "zone": zid, "enemy": String(target),
				"need": int(m.get("target_qty", 1)) - int(m.get("current_qty", 0))}
		"discover":
			return {"verb": "discover", "zone": String(target)}
		"drop_rarity":
			return {"verb": "farm_rarity", "rarity": int(str(target))}
		"loadout_rare_weapon":
			return {"verb": "equip_rare_weapon", "rarity": int(str(target))}
		"loadout_rare_weapon_type":
			return {"verb": "equip_rare_weapon_type", "wtype": String(target)}
		"warp_perform":
			return {"verb": "warp"}
		"hack_apply":
			return {"verb": "hack_apply", "stone": String(target)}
		"overclock_install":
			return {"verb": "overclock"}
		_:
			return {"verb": "unmapped", "why": "unknown mission type '%s'" % t}

# ---------------------------------------------------------------------------
# source_for(sym) — the single next player-step toward obtaining one unit of
# `sym`, honoring CURRENT levels/research/inventory (attainability, not just
# existence). Grant-free port of progression._acquire, split into pure
# resolution: the policy performs whatever step this names.
# Returns one of:
#   {"kind":"gather", "id":aid}                        — unlocked action yields sym
#   {"kind":"gather_locked", "id":aid, "lvl":n}        — action exists, level short
#   {"kind":"process", "id":rid}                       — recipe runnable NOW
#   {"kind":"research", "tid":t, "for":rid}            — recipe research gate next
#   {"kind":"grind_processing", "for":rid}             — recipe level-locked
#   {"kind":"credits", "amount":a, "for":rid}          — recipe credit cost short
#   {"kind":"zone_farm", "zone":zid, "enemy":eid, "research":rr} — combat loot
#   {"kind":"none"}                                    — unsourceable right now
# ---------------------------------------------------------------------------
func source_for(sym: String, depth: int = 0) -> Dictionary:
	if depth > 6:
		return {"kind": "none"}
	var gm = GameState.gathering_manager
	var pm = GameState.processing_manager
	var rm = GameState.research_manager

	# 1) gathering action listing the symbol (the source mission text points at)
	var locked_aid := ""
	var locked_lvl := 0
	# v143: a gather action whose research_req is LOCKED used to be discarded
	# silently (the `research_ok and ...` guards below never recorded it), so
	# source_for("Bauxite") returned {"kind":"none"} -> Al none -> Superalloy fell
	# through to the locked-zone last resort and named its OWN gate (zone_5_access),
	# which the policy then chased in an infinite _do_research/_do_acquire ping-pong
	# until Godot aborted at 1024 frames. Mirror the recipe branch: remember the
	# research-gated action and offer its tech as the next step.
	var gated_aid := ""
	var gated_rr := ""
	for aid in gm.actions:
		var a: Dictionary = gm.actions[aid]
		var yields := false
		for entry in a.get("loot_table", []):
			if String(entry[0]) == sym:
				yields = true
				break
		if not yields:
			continue
		var rr = a.get("research_req")
		var research_ok: bool = (rr == null) or rm.is_tech_unlocked(String(rr))
		var lvl_ok: bool = gm.get_level() >= int(a.get("level_req", 1))
		if research_ok and lvl_ok:
			return {"kind": "gather", "id": String(aid)}
		if research_ok and locked_aid == "":
			locked_aid = String(aid)
			locked_lvl = int(a.get("level_req", 1))
		if not research_ok and gated_rr == "":
			gated_aid = String(aid)
			gated_rr = String(rr)
	if locked_aid != "":
		return {"kind": "gather_locked", "id": locked_aid, "lvl": locked_lvl}

	# 2) processing recipe — but ONLY commit to the craft chain when it is
	# actually walkable from here: ready now, or missing inputs that are
	# themselves attainable WITHOUT a locked zone. The 45-day tail run chose
	# "Synthesize Rare Artifact" (100 Res1 + 5 MartianRelics -> 1 Res2) over
	# farming unlocked Z2 Claim Jumpers, then chased the Z3-locked relics.
	var rid := recipe_producing(sym)
	var drop_open := _zone_dropping_unlocked(sym)
	if rid != "":
		var r: Dictionary = pm.recipes[rid]
		var rr2 = r.get("research_req")
		var research_ok2: bool = (rr2 == null) or rm.is_tech_unlocked(String(rr2))
		var lvl_ok2: bool = pm.get_level() >= int(r.get("level_req", 1))
		if research_ok2 and lvl_ok2:
			var cr_cost := float(r.get("credits_cost", 0))
			if cr_cost > GameState.resources.get_currency("credits"):
				return {"kind": "credits", "amount": cr_cost, "for": rid}
			if _inputs_on_hand(rid):
				return {"kind": "process", "id": rid}
			var sub := _first_missing_input_step(rid, depth)
			if not sub.is_empty():
				return sub
			# every missing input is locked-zone-gated or unsourceable —
			# recipe not viable from here; fall through to open-zone loot.
		if drop_open.is_empty():
			# no open loot source either: pursue the recipe's own gates.
			if not research_ok2:
				return {"kind": "research", "tid": String(rr2), "for": rid}
			if not lvl_ok2:
				if _inputs_on_hand(rid):
					return {"kind": "grind_processing", "for": rid}
				var sub2 := _first_missing_input_step(rid, depth)
				if not sub2.is_empty():
					return sub2
				return {"kind": "grind_processing", "for": rid}

	# 3) combat loot from an UNLOCKED zone (what a player farms).
	if not drop_open.is_empty():
		return {"kind": "zone_farm", "zone": String(drop_open["zone"]),
			"enemy": String(drop_open["enemy"]), "research": ""}

	# 4) hack stones: code-level combat roll, any zone, firmware_hacking gate.
	if sym in HACK_STONE_SYMBOLS:
		var z := _best_unlocked_zone()
		if z.is_empty():
			return {"kind": "none"}
		var need_rr := ""
		if not rm.is_tech_unlocked("firmware_hacking"):
			need_rr = "firmware_hacking"
		return {"kind": "zone_farm", "zone": String(z["zone"]),
			"enemy": String(z["enemy"]), "research": need_rr}

	# 5) locked-zone loot as the LAST resort — carries the zone's research gate
	# so the policy deliberately researches the door first (paid, directed).
	var drop_locked := _zone_dropping_locked(sym)
	if not drop_locked.is_empty():
		var gate := String(drop_locked.get("gate", ""))
		# v143 safety net: never hand back a gate that itself BILLS `sym` — that is
		# a self-referential step ("farm Superalloy by researching the tech that
		# costs Superalloy") and the policy has no cycle guard, so it recurses to a
		# stack overflow whose only visible symptom is "unsourceable:<sym>".
		var self_ref: bool = (gate != "" and sym in rm.tech_tree.get(gate, {}).get("cost_items", {}))
		if not self_ref:
			return {"kind": "zone_farm", "zone": String(drop_locked["zone"]),
				"enemy": String(drop_locked["enemy"]), "research": gate}

	# 6) research-gated GATHER action, recorded in step 1. Deliberately dead last:
	# it only fills the hole where this function used to answer {"kind":"none"}.
	# Returning it from step 1 pre-empts the recipe branch and regresses symbols
	# that craft fine (measured: Ti walled m029a7 on day 2). Bauxite is the case
	# this exists for — no recipe, no open loot, only `mine_bauxite` behind the
	# 200-Lira tier-1 tech `lightweight_alloys`.
	if gated_rr != "":
		return {"kind": "research", "tid": gated_rr, "for": gated_aid}
	return {"kind": "none"}

func _first_missing_input_step(rid: String, depth: int) -> Dictionary:
	# Prefer inputs attainable WITHOUT a locked zone; a sub-step that resolves
	# to gated loot means this input is out of reach for now — try the next.
	var r: Dictionary = GameState.processing_manager.recipes[rid]
	for inp in r.get("input", {}):
		if GameState.resources.get_element_amount(String(inp)) < float(r["input"][inp]):
			var sub := source_for(String(inp), depth + 1)
			var k := String(sub.get("kind", "none"))
			if k == "none":
				continue
			if k == "zone_farm" and String(sub.get("research", "")) != "":
				continue
			return sub
	return {}

func _inputs_on_hand(rid: String) -> bool:
	var r: Dictionary = GameState.processing_manager.recipes[rid]
	for sym in r.get("input", {}):
		if GameState.resources.get_element_amount(String(sym)) < float(r["input"][sym]):
			return false
	return true

func recipe_producing(sym: String) -> String:
	var pm = GameState.processing_manager
	for rid in pm.recipes:
		if sym in pm.recipes[rid].get("output", {}):
			return String(rid)
	# output_table (chance rolls) as a weaker fallback source
	for rid in pm.recipes:
		for e in pm.recipes[rid].get("output_table", []):
			if String(e[0]) == sym:
				return String(rid)
	return ""

# ---------------------------------------------------------------------------
# Combat-source scans (pure).
# ---------------------------------------------------------------------------
func zone_of_enemy(eid: String) -> String:
	var cm = GameState.combat_manager
	for zid in cm.zones:
		if eid in cm.zones[zid].get("enemies", []):
			return String(zid)
	return ""

func _zone_dropping_unlocked(sym: String) -> Dictionary:
	var cm = GameState.combat_manager
	for z in cm.get_available_zones():
		var hit := _roster_drops(String(z["id"]), sym)
		if not hit.is_empty():
			return hit
	return {}

func _zone_dropping_locked(sym: String) -> Dictionary:
	var cm = GameState.combat_manager
	for zid in cm.zones:
		var hit := _roster_drops(String(zid), sym)
		if not hit.is_empty():
			hit["gate"] = String(cm.zones[zid].get("research_req", ""))
			return hit
	return {}

# Combined view (probe/dry-walk convenience): unlocked first, gated fallback.
func _zone_dropping(sym: String) -> Dictionary:
	var open := _zone_dropping_unlocked(sym)
	if not open.is_empty():
		return open
	return _zone_dropping_locked(sym)

func _roster_drops(zid: String, sym: String) -> Dictionary:
	var cm = GameState.combat_manager
	for eid in cm.zones.get(zid, {}).get("enemies", []):
		var e: Dictionary = cm.enemy_db.get(String(eid), {})
		for entry in e.get("loot", []):
			if String(entry[0]) == sym:
				return {"zone": zid, "enemy": String(eid)}
		for entry2 in e.get("rare_loot", []):
			if String(entry2[0]) == sym:
				return {"zone": zid, "enemy": String(eid)}
		if String(e.get("boss_core", "")) == sym:
			return {"zone": zid, "enemy": String(eid)}
	return {}

func _best_unlocked_zone() -> Dictionary:
	# Highest-difficulty unlocked zone's first trash enemy (where a player farms).
	var cm = GameState.combat_manager
	var best := {}
	var best_diff := -1
	for z in cm.get_available_zones():
		var zid := String(z["id"])
		var diff := int(cm.zones.get(zid, {}).get("difficulty", 0))
		var en: Array = cm.zones.get(zid, {}).get("enemies", [])
		if en.is_empty():
			continue
		if diff > best_diff:
			best_diff = diff
			best = {"zone": zid, "enemy": String(en[0])}
	return best

# ---------------------------------------------------------------------------
# Blocker helpers the policy uses to act on "research"/"craft"/"construct".
# ---------------------------------------------------------------------------
# Walk target's prereq chain to the FIRST locked node; report what stops it.
#   {"kind":"unlockable", "tid":t}          — can_unlock true, just buy it
#   {"kind":"credits", "tid":t, "amount":a} — chain node short on credits
#   {"kind":"item", "tid":t, "sym":s, "need":n} — chain node short on a material
#   {"kind":"flag", "tid":t, "why":...}     — requires_warp / requires_flag gate
#   {"kind":"done"}                         — target already unlocked
func research_blocker(target: String) -> Dictionary:
	var rm = GameState.research_manager
	if not target in rm.tech_tree:
		return {"kind": "flag", "tid": target, "why": "tech id not in tree"}
	if rm.is_tech_unlocked(target):
		return {"kind": "done"}
	# Build the locked prereq chain root-first (progression.unlock_toward shape).
	var chain := []
	var cur = target
	var guard := 0
	while cur != null and str(cur) != "" and guard < 50:
		guard += 1
		if rm.is_tech_unlocked(str(cur)):
			break
		chain.push_front(str(cur))
		var node: Dictionary = rm.tech_tree[str(cur)]
		var parent = node.get("parent")
		var req = node.get("req_tech")
		if parent and not rm.is_tech_unlocked(str(parent)):
			cur = parent
		elif req and not rm.is_tech_unlocked(str(req)):
			cur = req
		else:
			cur = null
	for tid in chain:
		if rm.can_unlock(tid):
			return {"kind": "unlockable", "tid": tid}
		var node2: Dictionary = rm.tech_tree[tid]
		if node2.get("requires_warp", false) and not GameState.game_settings.get("cryo_unlocked", false):
			return {"kind": "flag", "tid": tid, "why": "requires_warp"}
		var rflag = node2.get("requires_flag")
		if rflag and not GameState.game_settings.get(String(rflag), false):
			return {"kind": "flag", "tid": tid, "why": "requires_flag:%s" % rflag}
		var cr_need := float(node2.get("cost", 0)) * float(rm.COST_MULTIPLIER)
		var items: Dictionary = node2.get("cost_items", {})
		for sym in items:
			# v143: was `* rm.MATERIAL_MULTIPLIER` by hand, which ignores the game's
			# boss-core exemption in _effective_item_requirement -> the harness made
			# the bot farm Z4_Core 4x when zone_5_access only bills 2.
			var need := float(rm._effective_item_requirement(String(sym), int(items[sym])))
			if GameState.resources.get_element_amount(String(sym)) < need:
				return {"kind": "item", "tid": tid, "sym": String(sym),
					"need": need - GameState.resources.get_element_amount(String(sym))}
		if GameState.resources.get_currency("credits") < cr_need:
			return {"kind": "credits", "tid": tid,
				"amount": cr_need - GameState.resources.get_currency("credits")}
		# can_unlock false but nothing identifiable — surface as flag.
		return {"kind": "flag", "tid": tid, "why": "can_unlock false (unidentified gate)"}
	return {"kind": "done"}

# What's stopping crafting `mid`? Includes the module's OWN research_req (a
# player sees RESEARCH REQUIRED on the card) and the tier-gate effective cost.
#   {"kind":"ready"} | {"kind":"research","tid"} | {"kind":"credits","amount"}
#   | {"kind":"item","sym","need"} | {"kind":"flag","why"}
func craft_blocker(mid: String) -> Dictionary:
	var sm = GameState.shipyard_manager
	if not mid in sm.modules:
		return {"kind": "flag", "why": "module id %s unknown" % mid}
	var rr = sm.modules[mid].get("research_req")
	if rr and not GameState.research_manager.is_tech_unlocked(String(rr)):
		return {"kind": "research", "tid": String(rr)}
	var cost: Dictionary = sm.get_effective_module_cost(sm.modules[mid])
	for sym in cost:
		if String(sym) == "credits":
			continue
		var need := float(cost[sym])
		if GameState.resources.get_element_amount(String(sym)) < need:
			return {"kind": "item", "sym": String(sym),
				"need": need - GameState.resources.get_element_amount(String(sym))}
	var cr := float(cost.get("credits", 0))
	if GameState.resources.get_currency("credits") < cr:
		return {"kind": "credits", "amount": cr - GameState.resources.get_currency("credits")}
	return {"kind": "ready"}

func build_blocker(bid: String) -> Dictionary:
	var im = GameState.infrastructure_manager
	if not bid in im.building_db:
		return {"kind": "flag", "why": "building id %s unknown" % bid}
	var b: Dictionary = im.building_db[bid]
	var rr = b.get("research_req")
	if rr and not GameState.research_manager.is_tech_unlocked(String(rr)):
		return {"kind": "research", "tid": String(rr)}
	if im.get_level() < int(b.get("level_req", 1)):
		return {"kind": "flag", "why": "infra level %d required" % int(b.get("level_req", 1))}
	var cost: Dictionary = im.get_building_cost(bid)
	for sym in cost:
		if String(sym) == "credits":
			continue
		var need := float(cost[sym])
		if GameState.resources.get_element_amount(String(sym)) < need:
			return {"kind": "item", "sym": String(sym),
				"need": need - GameState.resources.get_element_amount(String(sym))}
	var cr := float(cost.get("credits", 0))
	if GameState.resources.get_currency("credits") < cr:
		return {"kind": "credits", "amount": cr - GameState.resources.get_currency("credits")}
	return {"kind": "ready"}

func construct_blocker(hid: String) -> Dictionary:
	var sm = GameState.shipyard_manager
	if not hid in sm.hulls:
		return {"kind": "flag", "why": "hull id %s unknown" % hid}
	var rr = sm.hulls[hid].get("research_req")
	if rr and not GameState.research_manager.is_tech_unlocked(String(rr)):
		return {"kind": "research", "tid": String(rr)}
	var cost: Dictionary = sm.hulls[hid].get("cost", {})
	for sym in cost:
		if String(sym) == "credits":
			continue
		var need := float(cost[sym])
		if GameState.resources.get_element_amount(String(sym)) < need:
			return {"kind": "item", "sym": String(sym),
				"need": need - GameState.resources.get_element_amount(String(sym))}
	var cr := float(cost.get("credits", 0))
	if GameState.resources.get_currency("credits") < cr:
		return {"kind": "credits", "amount": cr - GameState.resources.get_currency("credits")}
	return {"kind": "ready"}

# ---------------------------------------------------------------------------
# dry_walk_chain — boot-time static validation. Walks the LIVE chain from m001
# (next_mission order) plus every goal arc, and verifies each step is mappable
# with exists-anywhere semantics (levels/inventory ignored — that's runtime).
# Returns an Array of issue strings; empty = chain fully mappable.
# ---------------------------------------------------------------------------
func dry_walk_chain() -> Array:
	var mm = GameState.mission_manager
	var issues: Array = []
	var walked := {}
	var starts := ["m001", "goal_001", "goal_002", "goal_003",
		"goal_cryo_1", "goal_hack_1", "goal_boost_1"]
	for start in starts:
		var mid: String = String(start)
		var guard := 0
		while mid != "" and guard < 200:
			guard += 1
			if walked.has(mid):
				break
			walked[mid] = true
			if not mid in mm.missions:
				issues.append("%s: id missing from missions dict" % mid)
				break
			var m: Dictionary = mm.missions[mid]
			var issue := _static_check(mid, m)
			if issue != "":
				issues.append(issue)
			mid = String(m.get("next_mission", ""))
	return issues

func _static_check(mid: String, m: Dictionary) -> String:
	var t := String(m.get("type", ""))
	var target = m.get("target")
	var rm = GameState.research_manager
	var sm = GameState.shipyard_manager
	match t:
		"gather":
			if not _sym_has_any_source(String(target)):
				return "%s: gather target %s has NO source (action/recipe/loot/hack-roll)" % [mid, target]
		"gather_multi":
			for sym in target:
				if not _sym_has_any_source(String(sym)):
					return "%s: gather_multi target %s has NO source" % [mid, sym]
		"research", "research_multi":
			var tids: Array = [target] if t == "research" else target
			for tid in tids:
				if not String(tid) in rm.tech_tree:
					return "%s: research target %s not in tech_tree" % [mid, tid]
		"craft":
			if not String(target) in sm.modules:
				return "%s: craft target %s not in modules" % [mid, target]
		"construct":
			if not String(target) in sm.hulls:
				return "%s: construct target %s not in hulls" % [mid, target]
		"build":
			if not String(target) in GameState.infrastructure_manager.building_db:
				return "%s: build target %s not in building_db" % [mid, target]
		"defeat":
			if zone_of_enemy(String(target)) == "":
				return "%s: defeat target %s in no zone roster" % [mid, target]
		"discover":
			if not String(target) in GameState.combat_manager.zones:
				return "%s: discover target %s not a zone" % [mid, target]
		"visit_page":
			if not String(target) in KNOWN_PAGES:
				return "%s: visit_page target %s unknown" % [mid, target]
		"loadout_check":
			if not String(target) in ["weapon", "shield", "engine", "battery", "armor", "sensor", "combat_ready"]:
				return "%s: loadout_check target %s unknown" % [mid, target]
		"equip_consumables", "drop_rarity", "loadout_rare_weapon", "warp_perform", "overclock_install":
			pass
		"loadout_rare_weapon_type":
			if not String(target) in ["kinetic", "energy", "explosive", "cryo"]:
				return "%s: weapon type %s unknown" % [mid, target]
		"hack_apply":
			if not String(target) in HACK_STONE_SYMBOLS:
				return "%s: hack_apply stone %s not a known hack stone" % [mid, target]
		_:
			return "%s: UNKNOWN mission type '%s' — mission_actions needs a verb for it" % [mid, t]
	return ""

func _sym_has_any_source(sym: String) -> bool:
	if sym in HACK_STONE_SYMBOLS:
		return true
	var gm = GameState.gathering_manager
	for aid in gm.actions:
		for entry in gm.actions[aid].get("loot_table", []):
			if String(entry[0]) == sym:
				return true
	if recipe_producing(sym) != "":
		return true
	var cm = GameState.combat_manager
	for zid in cm.zones:
		if not _roster_drops(String(zid), sym).is_empty():
			return true
	return false
