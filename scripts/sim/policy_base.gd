extends RefCounted

# ============================================================================
# Virtual-player policy base. Subclasses (optimizer / casual) override the three
# decision hooks; everything else is shared, faithful-to-the-real-game logic
# that calls the same manager/resource APIs the UI calls.
#
# Autoloads (GameState / ElementDB) are global identifiers — referenced directly.
# (Isolated --check-only will flag them as undefined; a full headless boot
# resolves them. CLAUDE.md documents this.)
# ============================================================================

const RESERVE_KEEP := 250.0   # units of a protected input retained when selling

# ---- Decision hooks (override in subclass) --------------------------------
func manage_meta() -> void: pass
# decide_session returns either a skilling task {"kind":"gather"/"process", "mgr":, "id":}
# or a combat task {"kind":"combat", "zone": <zone_id>, "enemy": <enemy_id>}.
func decide_session() -> Dictionary: return {}
func want_warp() -> bool: return false
# Called right before the offline gap. Lets a combat bot leave a GATHER task
# running so the away-time still funds the ship (offline combat is off by default).
func pre_offline() -> void: pass

# ---- Combat helpers -------------------------------------------------------
func is_armed() -> bool:
	# True if at least one weapon module is equipped on the active hull.
	var sm = GameState.shipyard_manager
	for slot in sm.loadout:
		var mid = sm.loadout[slot]
		if mid and mid in sm.modules and sm.modules[mid].get("slot_type", "") == "weapon":
			return true
	return false

func unlocked_zone_ids() -> Array:
	var out := []
	for z in GameState.combat_manager.get_available_zones():
		out.append(z["id"])
	return out

# ---- Enumeration ----------------------------------------------------------
func unlocked_gather_actions() -> Array:
	var out := []
	var gm = GameState.gathering_manager
	for aid in gm.actions:
		var a = gm.actions[aid]
		if gm.get_level() < int(a.get("level_req", 1)): continue
		var rr = a.get("research_req")
		if rr and not GameState.research_manager.is_tech_unlocked(rr): continue
		out.append(aid)
	return out

func unlocked_recipes() -> Array:
	var out := []
	var pm = GameState.processing_manager
	for rid in pm.recipes:
		var r = pm.recipes[rid]
		if pm.get_level() < int(r.get("level_req", 1)): continue
		var rr = r.get("research_req")
		if rr and not GameState.research_manager.is_tech_unlocked(rr): continue
		out.append(rid)
	return out

func recipe_runnable(rid: String) -> bool:
	var r = GameState.processing_manager.recipes[rid]
	for sym in r.get("input", {}):
		if GameState.resources.get_element_amount(sym) < float(r["input"][sym]):
			return false
	if float(r.get("credits_cost", 0)) > GameState.resources.get_currency("credits"):
		return false
	return true

# ---- Value model (credits/sec, xp/sec) ------------------------------------
func gather_cps(a: Dictionary) -> float:
	var dur := float(a.get("duration", 4.0))
	if dur <= 0.0: return 0.0
	var total := 0.0
	for entry in a.get("loot_table", []):
		var sym: String = entry[0]
		var chance := float(entry[1])
		var avg := (float(entry[2]) + float(entry[3])) / 2.0
		total += chance * avg * float(ElementDB.get_element_value(sym))
	return total / dur

func best_gather() -> Array:
	# Returns [id, credits_per_sec, xp_per_sec] for the highest-scoring unlocked
	# gather action (credits/sec dominant, xp/sec as a tiny tiebreaker).
	var gm = GameState.gathering_manager
	var best_id := "gather_dirt"
	var best_score := -1.0
	var best_cps := 0.0
	var best_xps := 0.0
	for aid in unlocked_gather_actions():
		var a = gm.actions[aid]
		var cps := gather_cps(a)
		var xps := float(a.get("xp", 0)) / float(a.get("duration", 4.0))
		var score := cps + 0.01 * xps
		if score > best_score:
			best_score = score; best_id = aid; best_cps = cps; best_xps = xps
	return [best_id, best_cps, best_xps]

func recipe_profit_per_sec(rid: String) -> float:
	var r = GameState.processing_manager.recipes[rid]
	var dur := float(r.get("duration", 5.0))
	if dur <= 0.0: return 0.0
	var out_val := 0.0
	if r.has("output"):
		for sym in r["output"]:
			out_val += float(r["output"][sym]) * float(ElementDB.get_element_value(sym))
	if r.has("output_table"):
		for e in r["output_table"]:
			out_val += float(e[1]) * ((float(e[2]) + float(e[3])) / 2.0) * float(ElementDB.get_element_value(e[0]))
	out_val += float(r.get("credits_output", 0))
	var in_val := 0.0
	for sym in r.get("input", {}):
		in_val += float(r["input"][sym]) * float(ElementDB.get_element_value(sym))
	in_val += float(r.get("credits_cost", 0))
	return (out_val - in_val) / dur

func recipe_xp_per_sec(rid: String) -> float:
	var r = GameState.processing_manager.recipes[rid]
	var dur := float(r.get("duration", 5.0))
	if dur <= 0.0: return 0.0
	return float(r.get("xp", 0)) / dur

func best_recipe_id() -> String:
	var best := ""
	var best_score := 0.0   # only pick a recipe if it's net-positive
	for rid in unlocked_recipes():
		var sc := recipe_profit_per_sec(rid) + 0.01 * recipe_xp_per_sec(rid)
		if sc > best_score:
			best_score = sc; best = rid
	return best

# ---- Economy actions (mirror inventory_page.perform_sale / infra build) ----
func sell_surplus(protected: Dictionary) -> float:
	# Sell every element above its protected reserve at market value. Mirrors
	# inventory_page.perform_sale(): remove_element + add_currency("credits").
	# add_currency feeds lifetime_credits -> the warp progress_score.
	var res = GameState.resources
	var earned := 0.0
	for sym in res.elements.keys():
		# Never vendor BOSS CORES (Z<N>_Core). A real player doesn't sell the Z2_Core
		# the very next zone-access research spends — the bot was, then re-farming the
		# Monolith for a replacement (the true m030e "wall"). Scoped to boss cores only:
		# the bot legitimately sells matrix cores etc. for credit income, so the broad
		# is_slot_protected guard starved it (0/3 reached Zone 3).
		if sym.begins_with("Z") and sym.ends_with("_Core"): continue
		var val := float(ElementDB.get_element_value(sym))
		if val <= 0.0: continue                      # unsellable junk — don't churn
		var keep := float(protected.get(sym, 0.0))
		var qty := int(res.get_element_amount(sym) - keep)
		if qty <= 0: continue
		if res.remove_element(sym, qty):
			res.add_currency("credits", qty * val)
			earned += qty * val
	return earned

func try_unlock_research(max_count: int) -> int:
	var rm = GameState.research_manager
	var n := 0
	var budget := max_count
	while budget > 0:
		# Re-scan each iteration: a purchase changes affordability of others.
		var pick := ""
		var pick_cost := 1.0e30
		for tid in rm.tech_tree:
			if rm.is_tech_unlocked(tid): continue
			if not rm.can_unlock(tid): continue
			var c := float(rm.tech_tree[tid].get("cost", 0))
			if c < pick_cost:
				pick_cost = c; pick = tid
		if pick == "": break
		if rm.unlock_tech(pick):
			n += 1; budget -= 1
		else:
			break
	return n

# Unlock a target tech by walking its prerequisite chain (parent / req_tech)
# and buying each step that's affordable, cheapest-prereq-first.
func unlock_toward(target: String) -> void:
	var rm = GameState.research_manager
	if not target in rm.tech_tree or rm.is_tech_unlocked(target):
		return
	var chain := []
	var cur = target
	var guard := 0
	while cur != null and str(cur) != "" and guard < 50:
		guard += 1
		if rm.is_tech_unlocked(cur):
			break
		chain.push_front(cur)
		var node = rm.tech_tree[cur]
		var parent = node.get("parent")
		var req = node.get("req_tech")
		if parent and not rm.is_tech_unlocked(parent):
			cur = parent
		elif req and not rm.is_tech_unlocked(req):
			cur = req
		else:
			cur = null
	for tid in chain:
		if rm.can_unlock(tid):
			rm.unlock_tech(tid)
		else:
			break

func buy_buildings(max_count: int) -> int:
	var im = GameState.infrastructure_manager
	var bought := 0
	var budget := max_count
	while budget > 0:
		var pick := ""
		var pick_cost := 1.0e30
		for bid in im.building_db:
			var b = im.building_db[bid]
			var rr = b.get("research_req")
			if rr and not GameState.research_manager.is_tech_unlocked(rr): continue
			if not im.can_afford(bid): continue
			var c = im.get_building_cost(bid)
			var cc := float(c.get("credits", 0))
			if cc < pick_cost:
				pick_cost = cc; pick = bid
		if pick == "": break
		if im.build(pick):
			bought += 1; budget -= 1
		else:
			break
	return bought

func maybe_upgrade_storage() -> void:
	var res = GameState.resources
	# Expand before output starts spilling (slot-limited inventory is a sink).
	if res.get_used_slots() >= res.get_max_slots() - 1:
		res.upgrade_storage()
