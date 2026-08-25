extends SceneTree
## Plays the mission chain the way a player does, beat by beat, and reports the
## first one that cannot be finished.
##
## Every other mission sim checks the chain from the outside: ids resolve, the
## next-pointers form a line, targets exist. None of them ever DID what a mission
## asks. That is how m017 shipped with no completion path at all (its type had no
## arm anywhere in the engine), and how "craft 5 Battery Cells" landed six steps
## before the chain taught Lithium.
##
## So this one performs each objective through the real engine calls — research
## the tech, craft the item, buy and fit the module, kill the enemy, disengage —
## and asserts the beat then reads as complete and claimable. Raw materials are
## granted directly (grind is not what this is testing); everything that gates
## an ACTION — research, level, recipe, cost, slot, mission logic — is real.

var errs: Array = []
var warns: Array = []
var gs
var gd
var main

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s: String) -> void: errs.append(s)
func W(s: String) -> void: warns.append(s)

## Put `qty` of `sym` in the hold, making it the way the game makes it: raw
## materials are granted, crafted ones are crafted through the real recipe (which
## fails loudly if the recipe is gated, missing, or its inputs are unobtainable).
func _obtain(sym: String, qty: int, depth := 0) -> bool:
	if gs.amount(sym) >= qty:
		return true
	if depth > 4:
		W("stopped recursing for '%s' at depth %d" % [sym, depth])
		return false
	# Raw: any gather action that drops it.
	for gid in gd.GATHER:
		for row in (gd.GATHER[gid] as Dictionary).get("loot", []):
			if String((row as Array)[0]) == sym:
				gs.add_resource(sym, qty - gs.amount(sym))
				return true
	# Crafted: try EVERY recipe that makes it, not just the first one found.
	# Several materials have both a gated recipe and an ungated one (Steel has a
	# smelting line and a salvage line), and stopping at the first gated match
	# reported a dead end the player does not actually have.
	for rid in gd.CRAFT:
		var r: Dictionary = gd.CRAFT[rid]
		if not r.get("outputs", {}).has(sym):
			continue
		var rr: String = String(r.get("research_req", ""))
		if rr != "" and not gs.is_research_unlocked(rr):
			continue                      # gated for the player right now — try another
		var need: int = qty - gs.amount(sym)
		var per := int((r["outputs"] as Dictionary)[sym])
		var runs := int(ceil(float(need) / float(maxi(1, per))))
		var inputs_ok := true
		for i in r.get("inputs", {}):
			if not _obtain(String(i), int((r["inputs"] as Dictionary)[i]) * runs + 5, depth + 1):
				inputs_ok = false
				break
		if not inputs_ok:
			continue
		if gs.level_of("fabrication") < int(r.get("level_req", 1)):
			gs.skills["fabrication"] = gs.xp_for_level(int(r.get("level_req", 1)))
		gs._grant_craft_outputs(rid, r, runs)
		if gs.amount(sym) >= qty:
			return true
	# Combat drop or building output: grant it rather than farming.
	gs.add_resource(sym, qty - gs.amount(sym), true)
	return true

## Unlock a tech the chain never asks for, the way a player would have to: walk
## its prerequisites, pay it, research it. Returns "" if it worked. Used when a
## beat is gated on research no earlier beat teaches — the chain still runs, but
## the gap is reported, because on a real save that is where the player meets a
## LOCKED card with no hint about which node opens it.
func _self_research(tid: String) -> String:
	if tid == "":
		return "no research_req to satisfy"
	if gs.is_research_unlocked(tid):
		return ""
	var rt: Dictionary = gd.RESEARCH.get(tid, {})
	if rt.is_empty():
		return "tech '%s' does not exist" % tid
	var par := String(rt.get("parent", ""))
	if par != "":
		var pw: String = _self_research(par)
		if pw != "":
			return pw
	for req in rt.get("req_tech", []):
		if String(req) == "":
			continue
		var rw: String = _self_research(String(req))
		if rw != "":
			return rw
	gs.credits = maxi(gs.credits, int(rt.get("credits", 0)) * 2 + 100000)
	var ritems: Dictionary = gs.research_items(tid)
	for sym in ritems:
		if not _obtain(String(sym), int(ritems[sym]) * 2 + 10):
			return "could not obtain %s for '%s'" % [sym, tid]
	if not gs.research_available(tid):
		return "'%s' is still not researchable" % tid
	if not gs.unlock_research(tid):
		return "unlock_research('%s') refused" % tid
	return ""

## Do what the mission asks. Returns "" on success, else why it could not be done.
func _perform(mid: String) -> String:
	var mid_ctx := mid
	var m: Dictionary = gd.MISSIONS[mid]
	var ty := String(m.get("type", ""))
	var tgt = m.get("target", "")
	var qty := int(m.get("qty", 1))
	match ty:
		"gather":
			if not _obtain(String(tgt), qty):
				return "could not obtain %d %s" % [qty, tgt]
		"gather_multi":
			for sym in (tgt as Dictionary):
				if not _obtain(String(sym), int((tgt as Dictionary)[sym])):
					return "could not obtain %s" % sym
		"research", "research_multi":
			var techs: Array = tgt if tgt is Array else [tgt]
			for t in techs:
				var tid := String(t)
				# The real gate: everything research_available() checks.
				var rt: Dictionary = gd.RESEARCH.get(tid, {})
				if gs.is_research_unlocked(tid):
					continue          # an earlier beat already taught this one
				if rt.is_empty():
					return "tech '%s' does not exist" % tid
				gs.credits = maxi(gs.credits, int(rt.get("credits", 0)) * 2 + 10000)
				# Obtain with margin, then re-check: crafting one input can spend
				# another, so an exact-amount pass can leave the tech unaffordable
				# and make a harness shortfall look like a game gate.
				var items: Dictionary = gs.research_items(tid)
				for sym in items:
					if not _obtain(String(sym), int(items[sym]) * 2 + 10):
						return "could not obtain %s for tech '%s'" % [sym, tid]
				for sym2 in items:
					if gs.amount(String(sym2)) < int(items[sym2]):
						return "HARNESS: short %d %s for tech '%s'" % [
							int(items[sym2]) - gs.amount(String(sym2)), sym2, tid]
				if not gs.research_available(tid):
					var why := "unmet prerequisite"
					var par := String(rt.get("parent", ""))
					if par != "" and not gs.is_research_unlocked(par):
						why = "parent tech '%s' not unlocked" % par
					for req in rt.get("req_tech", []):
						if String(req) != "" and not gs.is_research_unlocked(String(req)):
							why = "req_tech '%s' not unlocked" % req
					if bool(rt.get("requires_warp", false)) and not gs.cryo_unlocked:
						why = "needs a Warp first"
					return "tech '%s' is not researchable here: %s" % [tid, why]
				if not gs.unlock_research(tid):
					return "unlock_research('%s') refused" % tid
		"craft":
			var cid := String(tgt)
			if not gd.MODULES.has(cid):
				return "module '%s' does not exist" % cid
			if gs.module_is_drop_only(cid):
				return "module '%s' is drop-only — it cannot be crafted at all" % cid
			for _i in qty:
				gs.credits = maxi(gs.credits, 10_000_000)
				for sym in gs.effective_module_cost(cid):
					if String(sym) == "credits":
						continue
					if not _obtain(String(sym), int(gs.effective_module_cost(cid)[sym])):
						return "could not obtain %s for module '%s'" % [sym, cid]
				if not gs.module_unlocked(cid):
					var mreq := String((gd.MODULES[cid] as Dictionary).get("research_req", ""))
					var mw := _self_research(mreq)
					if mw != "":
						return "module '%s' is locked behind '%s' and that cannot be researched: %s" % [cid, mreq, mw]
					W("beat '%s' asks for module '%s' but no earlier beat teaches '%s'"
						% [mid_ctx, cid, mreq])
				if not gs.buy_module(cid):
					return "buy_module('%s') refused" % cid
		"loadout_check":
			var slot := String(tgt)
			if slot == "" or slot == "combat_ready":
				for s in ["battery", "weapon", "shield"]:
					_fit_slot(s)
			elif _fit_slot(slot) != "":
				return _fit_slot(slot)
		"equip_consumables":
			var hull_c := ""
			var shield_c := ""
			for cid2 in gd.CONSUMABLES:
				var kind := String((gd.CONSUMABLES[cid2] as Dictionary).get("type", "hull"))
				if kind == "hull" and hull_c == "":
					hull_c = String(cid2)
				elif kind == "shield" and shield_c == "":
					shield_c = String(cid2)
			if hull_c == "" or shield_c == "":
				return "no hull/shield consumable exists to fit"
			if not _obtain(hull_c, qty) or not _obtain(shield_c, qty):
				return "could not obtain the consumables"
			gs.set_consumable("hull", hull_c)
			gs.set_consumable("shield", shield_c)
		"defeat", "defeat_retreat":
			var eid := String(tgt)
			if not gd.ENEMIES.has(eid):
				return "enemy '%s' does not exist" % eid
			for _i in qty:
				# The v134 entry gate refuses combat on an overloaded grid, so a
				# ship that has grown past its batteries cannot engage at all.
				var ss3: Dictionary = gs.ship_stats()
				if float(ss3.get("energy_load", 0.0)) > float(ss3.get("energy_cap", 0.0)):
					var pw3 := _fit_slot("battery")
					if pw3 != "":
						return "cannot power the ship to engage '%s': %s" % [eid, pw3]
				# Winning auto-re-engages the same enemy, and start_task TOGGLES when
				# handed the id already running — so engage from a stopped state.
				gs.stop_task()
				gs.start_task("combat", eid)
				if gs.enemy_inst.is_empty():
					return "engaging '%s' produced no enemy (notice='%s')" % [eid, gs.equip_notice]
				gs.enemy_inst["hp"] = 0.0
				gs._win_combat()
			gs.stop_task()          # the retreat half of defeat_retreat
		"visit_page":
			gs.mission_visit_page(String(tgt))
		"build":
			var bid := String(tgt)
			if not gd.BUILDINGS.has(bid):
				return "building '%s' does not exist" % bid
			for _i in qty:
				gs.credits = maxi(gs.credits, 10_000_000)
				var bcost: Dictionary = (gd.BUILDINGS[bid] as Dictionary).get("cost", {})
				for sym in bcost:
					if String(sym) == "credits":
						continue
					_obtain(String(sym), int(bcost[sym]) * 2 + 5)
				if not gs.build_building(bid):
					return "build_building('%s') refused" % bid
		"construct":
			var hid := String(tgt)
			if not gd.HULLS.has(hid):
				return "hull '%s' does not exist" % hid
			gs.credits = maxi(gs.credits, 100_000_000)
			var hcost: Dictionary = (gd.HULLS[hid] as Dictionary).get("cost", {})
			for sym in hcost:
				if String(sym) == "credits":
					continue
				_obtain(String(sym), int(hcost[sym]) * 2 + 5)
			if not gs.hull_unlocked(hid):
				var hreq := String((gd.HULLS[hid] as Dictionary).get("research_req", ""))
				var hw: String = _self_research(hreq)
				if hw != "":
					return "hull '%s' is locked behind '%s' and that cannot be researched: %s" % [hid, hreq, hw]
				W("beat '%s' asks for hull '%s' but no earlier beat teaches '%s' — the player meets a LOCKED card with no hint"
					% [mid_ctx, hid, hreq])
			for sym in hcost:
				if String(sym) != "credits" and gs.amount(String(sym)) < int(hcost[sym]):
					return "HARNESS: short %d %s for hull '%s'" % [
						int(hcost[sym]) - gs.amount(String(sym)), sym, hid]
			if not gs.select_hull(hid):
				return "select_hull('%s') refused" % hid
		"drop_rarity", "loadout_rare_weapon":
			var want := int(str(tgt))
			# The LOWEST-zone weapon, not the first in the table: a drop at this
			# point in the chain is a Zone-1 weapon, and rolling a Zone-10 base
			# produces a module whose energy load no early ship can carry.
			var base := ""
			var base_zone := 999
			for wid in gd.MODULES:
				var wm: Dictionary = gd.MODULES[wid]
				if String(wm.get("slot", "")) != "weapon" or gs.module_is_drop_only(String(wid)):
					continue
				if not gs.module_unlocked(String(wid)):
					continue
				if int(wm.get("zone", 99)) < base_zone:
					base_zone = int(wm.get("zone", 99))
					base = String(wid)
			if base == "":
				return "no weapon module to roll"
			var inst: String = gs.generate_module(base, want, 1)
			if inst == "":
				return "generate_module refused"
			if ty == "loadout_rare_weapon":
				# This beat is about FITTING the drop, so clear a weapon slot
				# rather than reporting a ship that is merely full.
				for k in gs.loadout.keys():
					if String(gs.module_def(gs.loadout[k]).get("slot", "")) == "weapon":
						gs.unequip_slot(String(k))
			var pw2 := _fit_slot("battery")
			if pw2 != "":
				return pw2
			if not gs.equip_module(inst):
				var ss: Dictionary = gs.ship_stats()
				return "the rare weapon could not be equipped: %s [hull=%s load=%.0f cap=%.0f loadout=%s inst_load=%s]" % [
					gs.equip_notice, gs.active_hull,
					float(ss.get("energy_load", 0.0)), float(ss.get("energy_cap", 0.0)),
					str(gs.loadout), str(gs.module_def(inst).get("stats", {}).get("energy_load", "?"))]
		"discover":
			gs._mission_event("discover", String(tgt), qty)
		"atlas_lookup", "socket_check", "craft_matrix", "hack_apply", "overclock_install", "warp_perform":
			return "SKIP"
		_:
			return "SKIP"
	return ""

## Buy and fit any module of `slot`, powering the grid first. Returns "" on success.
func _fit_slot(slot: String) -> String:
	for k in gs.loadout:
		if String(gs.module_def(gs.loadout[k]).get("slot", "")) == slot:
			return ""
	if slot != "battery":
		var pw := _fit_slot("battery")
		if pw != "":
			return pw
	var pick := ""
	for mid in gd.MODULES:
		var m: Dictionary = gd.MODULES[mid]
		if String(m.get("slot", "")) != slot or gs.module_is_drop_only(String(mid)):
			continue
		if not gs.module_unlocked(String(mid)):
			continue
		pick = String(mid)
		break
	if pick == "":
		return "no buyable %s module is unlocked yet" % slot
	gs.credits = maxi(gs.credits, 10_000_000)
	for sym in gs.effective_module_cost(pick):
		if String(sym) != "credits":
			_obtain(String(sym), int(gs.effective_module_cost(pick)[sym]))
	if int(gs.module_inventory.get(pick, 0)) <= 0 and not gs.buy_module(pick):
		return "could not buy a %s module ('%s')" % [slot, pick]
	if not gs.equip_module(pick):
		return "could not equip the %s module ('%s'): %s" % [slot, pick, gs.equip_notice]
	return ""

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	gs = root.get_node("GameState")
	gd = root.get_node("GameData")
	gs._suppress_fx = true
	for n in range(1, gs.SLOT_COUNT + 1):
		gs.delete_slot(n)
	gs.new_character(1, "Playthrough")
	if is_instance_valid(main._char_select):
		main._char_select.queue_free()
		main._char_select = null
	# The 28-slot hold is real pressure in play, but here it just silently drops
	# granted materials and makes a harness shortfall look like a dead chain.
	# Storage capacity is not what this sim is testing.
	gs.storage_upgrades = 500

	var walked := 0
	var skipped := 0
	var stopped_at := ""
	for mid in gd.MISSION_ORDER:
		var m: Dictionary = gd.MISSIONS[mid]
		var ty := String(m.get("type", ""))
		# The chain must have handed this beat to the player by now.
		if not gs.missions_active.has(mid):
			E("beat '%s' (%s) never became active — the chain stops before it" % [mid, m.get("name", mid)])
			stopped_at = mid
			break
		# Where the coach sends the player, judged in the state they are ACTUALLY
		# in at this beat. A page that is still hidden in the menu makes the hint
		# "tap ☰ → Warp Core" a dead end, and a static check cannot see it because
		# nav visibility depends on how far the run has got.
		var route: Dictionary = main._coach_resolve(m)
		var rpage := String(route.get("page", ""))
		if rpage != "" and main.pages.has(rpage) and not main._nav_visible(rpage):
			E("beat '%s' (%s) points at '%s', which is not in the menu yet at this point in the run"
				% [mid, m.get("name", mid), rpage])
		var why := _perform(mid)
		if why == "SKIP":
			skipped += 1
			gs.missions_progress[mid] = int(m.get("qty", 1))
			gs.missions_active.erase(mid)
			gs.missions_claimed[mid] = true
			var nxt := String(m.get("next", ""))
			if nxt != "":
				gs.missions_active[nxt] = true
			continue
		if why != "":
			E("beat '%s' (%s, %s) cannot be done: %s" % [mid, m.get("name", mid), ty, why])
			stopped_at = mid
			break
		gs._mission_sync()
		if not gs.mission_completed(mid):
			print("  [state] hull=%s loadout=%s" % [gs.active_hull, str(gs.loadout)])
			for k in gs.loadout:
				print("  [state] slot %s = %s (slot_type=%s rarity=%d)" % [k, gs.loadout[k],
					gs.module_def(gs.loadout[k]).get("slot", ""), gs.module_rarity(String(gs.loadout[k]))])
			E("beat '%s' (%s, %s) was performed but does not register as complete (%d/%d)"
				% [mid, m.get("name", mid), ty,
					int(gs.missions_progress.get(mid, 0)), int(m.get("qty", 1))])
			stopped_at = mid
			break
		if not gs.claim_mission(mid):
			E("beat '%s' completed but claim_mission refused it" % mid)
			stopped_at = mid
			break
		walked += 1
	print("tutorial playthrough: %d beats played, %d skipped (untestable types), %d in the chain"
		% [walked, skipped, gd.MISSION_ORDER.size()])
	if stopped_at != "":
		print("stopped at: %s" % stopped_at)

	gs._suppress_fx = false
	print("")
	if errs.is_empty():
		print("ERRORS: none")
	else:
		print("--- ERRORS (%d) ---" % errs.size())
		for e in errs:
			print("  x %s" % e)
	if not warns.is_empty():
		print("--- WARNINGS (%d) ---" % warns.size())
		for w in warns:
			print("  ! %s" % w)
	print("TUTORIAL_PLAYTHROUGH: %s" % ("FAIL" if not errs.is_empty() else "PASS"))
	quit()
