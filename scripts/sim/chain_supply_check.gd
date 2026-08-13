extends Node
# A BEAT MUST NOT DEMAND A DROP THE PLAYER CANNOT FARM YET (v175).
#
# type_unlock_check already asks whether a demanded material is gated behind RESEARCH the
# player has not reached. This asks the other half: whether the material has any FAUCET at
# all in a zone the chain has opened by that point.
#
# m029a8 is the case that motivated it. It commissions the Electronics Assembler, whose
# cost includes 12 SalvageData, at chain index 55 — and SalvageData's only source in the
# entire game was z3_derelict_frigate in Mars Debris, which the chain does not open until
# m030e at index 63. A chain-obedient player arrived with zero reachable sources, and the
# mission text told them to "run a sector if you are short" when no enterable sector
# dropped it.
#
# Scope is deliberately narrow: only materials whose sources are ALL combat drops. A
# material that can be mined, refined or produced by a building is reachable by definition
# and is not this failure mode. Keeping the scope tight is what keeps the guard readable
# and stops it drowning in false positives.
#
#   Godot --headless --path <root> res://scenes/chain_supply_check.tscn

# The chain's own observed ceiling for a combat-drop demand, measured before this guard
# existed. A demand costing more kills than this is a grind wall, not a supply line.
const MAX_KILLS := 20

var fails: int = 0

func _ready() -> void:
	await get_tree().process_frame
	GameState.set_process(false)
	var mm = GameState.mission_manager
	var cm = GameState.combat_manager
	var im = GameState.infrastructure_manager
	var sm = GameState.shipyard_manager
	var pm = GameState.processing_manager
	var gm = GameState.gathering_manager

	# Which zone each combat-drop material first becomes farmable in.
	var drop_zone: Dictionary = {}      # symbol -> lowest zone difficulty that drops it
	for eid in cm.enemy_db:
		var e: Dictionary = cm.enemy_db[eid]
		var z: int = int(e.get("zone", 0))
		if z <= 0:
			continue
		for row in e.get("loot", []):
			_note(drop_zone, str((row as Array)[0]), z)
		for row2 in e.get("rare_loot", []):
			_note(drop_zone, str((row2 as Array)[0]), z)
		# Boss cores are granted by a dedicated field, not by the loot tables. Missing
		# this made the guard report six phantom "nothing produces Z1_Core" failures --
		# every one of them a boss core the player gets automatically for the kill.
		var core := str(e.get("boss_core", ""))
		if core != "":
			_note(drop_zone, core, z)

	# THE EARLIEST ZONE AT WHICH EACH MATERIAL BECOMES OBTAINABLE, BY ANY PATH.
	#
	# The first version marked a symbol "obtainable without fighting" if ANY recipe merely
	# OUTPUT it, then skipped the beat -- never asking whether that recipe's own INPUTS were
	# reachable. One level of indirection defeated the whole check: bury an unreachable
	# material one recipe deep and the guard waved it through while still printing its own
	# headline message about materials nothing produces.
	#
	# Proper resolver. req[sym] = the shallowest zone that can produce sym:
	#   * gathered            -> 0 (no zone needed)
	#   * dropped by an enemy -> that enemy's zone
	#   * made by a recipe    -> MAX over its inputs (you need all of them)
	#   * made by a building  -> MAX over its inputs AND its construction cost
	# then MIN across every path. Relaxed to a fixed point rather than recursed, so
	# production cycles simply never lower a value and resolve to unreachable on their own
	# instead of needing a visited-set.
	var req: Dictionary = {}
	for aid in gm.actions:
		for row3 in gm.actions[aid].get("loot_table", []):
			_note(req, str((row3 as Array)[0]), 0)
	for sym0 in drop_zone:
		_note(req, str(sym0), int(drop_zone[sym0]))

	var producers: Array = []
	for rid in pm.recipes:
		var rc: Dictionary = pm.recipes[rid]
		producers.append({"out": (rc.get("output", {}) as Dictionary).keys(),
			"needs": (rc.get("input", {}) as Dictionary).keys()})
	for bid in im.building_db:
		var bd: Dictionary = im.building_db[bid]
		var needs: Array = (bd.get("input", {}) as Dictionary).keys()
		for ci in (bd.get("cost", {}) as Dictionary):
			if str(ci) != "credits":
				needs.append(ci)
		producers.append({"out": (bd.get("output", {}) as Dictionary).keys(), "needs": needs})

	var gathered: Dictionary = {}
	for aid2 in gm.actions:
		for row4 in gm.actions[aid2].get("loot_table", []):
			_note(gathered, str((row4 as Array)[0]), 0)

	# QUANTIFIED producers, for the effort maths below. `producers` above keeps only
	# KEYS because reachability does not care how many; effort does. Buildings
	# contribute their ongoing input -> output conversion only: the one-off
	# construction cost is not a per-unit price, and reachability already accounts
	# for it via `producers`.
	var qprod: Array = []
	for rid2 in pm.recipes:
		var rc2: Dictionary = pm.recipes[rid2]
		qprod.append({"inp": rc2.get("input", {}), "out": rc2.get("output", {})})
	for bid2 in im.building_db:
		var bd2: Dictionary = im.building_db[bid2]
		if not (bd2.get("output", {}) as Dictionary).is_empty():
			qprod.append({"inp": bd2.get("input", {}), "out": bd2.get("output", {})})

	# CRAFTABLE = reachable with no fighting at all, inputs verified transitively. This is
	# what the original naive `non_combat` claimed to be and was not.
	var craftable: Dictionary = _relax(gathered.duplicate(), producers)
	req = _relax(req, producers)
	print("[SUPPLY] %d combat-drop material(s); %d craftable without fighting; %d reachable by any path" % [
		drop_zone.size(), craftable.size(), req.size()])

	# PRE-PASS: the step at which the chain first tells the player to fight each enemy.
	# That is what makes "is this boss a usable faucet yet" answerable -- a boss the chain
	# has not sent you at is one the chain has not geared you for.
	var first_fight: Dictionary = {}
	var pc := "m001"
	var pstep := 0
	while pc != "" and pstep < 200:
		var pm2: Dictionary = mm.missions.get(pc, {})
		if pm2.is_empty():
			break
		pstep += 1
		if str(pm2.get("type", "")) in ["defeat", "defeat_retreat"]:
			var eid2 := str(pm2.get("target", ""))
			if eid2 != "" and not first_fight.has(eid2):
				first_fight[eid2] = pstep
		pc = str(pm2.get("next_mission", ""))
	print("[SUPPLY] chain schedules %d distinct enemy fight(s)" % first_fight.size())

	# Walk the chain carrying the deepest zone the player can enter.
	var zone_now := 1
	var cur := "m001"
	var steps := 0
	var checked := 0
	while cur != "" and steps < 200:
		var m: Dictionary = mm.missions.get(cur, {})
		if m.is_empty():
			break
		steps += 1
		var tgt := str(m.get("target", ""))
		if str(m.get("type", "")) == "research" and tgt.begins_with("zone_") and tgt.ends_with("_access"):
			zone_now = maxi(zone_now, int(tgt.trim_prefix("zone_").trim_suffix("_access")))

		# What this beat makes the player pay for.
		var cost: Dictionary = {}
		var kind := str(m.get("type", ""))
		if kind == "build" and im.building_db.has(tgt):
			cost = im.building_db[tgt].get("cost", {})
		elif kind == "craft" and sm.modules.has(tgt):
			cost = sm.modules[tgt].get("cost", {})
		elif kind == "construct" and sm.hulls.has(tgt):
			cost = sm.hulls[tgt].get("cost", {})
		elif kind == "research" and GameState.research_manager.tech_tree.has(tgt):
			cost = GameState.research_manager.tech_tree[tgt].get("cost_items", {})
		elif kind == "gather":
			# v175: gather/gather_multi were walked past entirely -- 24 of 85 beats, and
			# the most literal form of "this beat demands N of a material" there is.
			cost = {tgt: int(m.get("target_qty", 1))}
		elif kind == "gather_multi":
			for k in (m.get("target", {}) as Dictionary):
				cost[str(k)] = int((m.get("target", {}) as Dictionary)[k])
		elif kind in ["build", "craft", "construct"]:
			# The branches above are `kind == X and db.has(tgt)`. A miss on the second
			# half used to drop the beat silently, shrinking coverage while still
			# printing PASS. Say so instead.
			print("[SUPPLY] note: %s is a %s beat but '%s' is in no matching DB -- not checked" % [cur, kind, tgt])

		for item in cost:
			var sym := str(item)
			if sym == "credits":
				continue
			if not req.has(sym):
				_fail("%s needs %s, which nothing in the game produces or drops" % [cur, sym])
				continue
			var need_zone: int = int(req[sym])
			if need_zone > zone_now:
				var indirect: bool = not (drop_zone.has(sym) and int(drop_zone[sym]) == need_zone)
				_fail("%s (step %d) needs %d %s, whose shallowest production path needs Zone %d but the chain has opened Zone %d%s" % [
					cur, steps, int(cost[item]), sym, need_zone, zone_now,
					"  (via an intermediate, not a direct drop)" if indirect else ""])
			if craftable.has(sym):
				continue          # refined or mined; nobody farms 80 Fe off drones
			if not drop_zone.has(sym) or int(drop_zone[sym]) > zone_now:
				continue          # not obtainable by fighting here -- kill maths is moot
			checked += 1
			# Reachable is necessary but not sufficient — a faucet that yields 0.02 per
			# kill is technically a source and practically a wall. Report the best rate
			# available at this point and what the quota costs in kills, so a future
			# tuning pass argues from a number instead of a vibe.
			var src: Dictionary = _cheapest_source(cm, sym, zone_now, first_fight)
			var best: float = float(src.get("rate", 0.0))
			if best > 0.0:
				var qty: float = float(cost[item])
				var ehp_ref: float = maxf(1.0, float(src.get("ehp", 0.0)))
				var direct_unit: float = ehp_ref / best
				# v175: price the cheapest PATH, not just the cheapest direct drop. The
				# guard used to read only the loot tables, so an item with a cheap RECIPE
				# whose inputs happen to be combat-fed was billed at its rare_loot rate.
				# Live case: m033a2 needs 8 ReactiveCore. Direct drop is 0.08/kill off
				# z6_defense_turret = ~100 kills, and the guard failed the beat. But
				# craft_reactive_core turns 6 ColonySalvage into 2 cores, and the SAME
				# turret drops 5-12 ColonySalvage a kill — the real bill is ~3 kills.
				# It could not see that because `craftable` (line ~173) means "reachable
				# with NO fighting at all", which a combat-fed recipe never satisfies.
				var unit: float = float(_effort_at(cm, gm, qprod, zone_now).get(sym, direct_unit))
				var via_recipe: bool = unit < direct_unit * 0.999
				# Budget stated in EHP so both paths are judged on one scale. When the
				# direct drop IS the cheapest path this is algebraically the old test:
				# effort = qty*ehp/rate = kills*ehp, budget = MAX_KILLS*ehp, so
				# effort > budget <=> kills > MAX_KILLS — verdict and printed kill count
				# both unchanged (verified: every row of this chain except ReactiveCore
				# still prints its old number). Where a recipe IS cheaper the guard gets
				# strictly more permissive, never stricter, because `unit` is a minimum
				# over paths. That is the intended direction: a path the player can
				# actually take is not a wall just because the loot table is stingy.
				var effort: float = qty * unit
				var budget: float = float(MAX_KILLS) * ehp_ref
				var kills: int = int(ceil(effort / ehp_ref))
				var is_boss: bool = bool(src.get("boss", false))
				print("[SUPPLY]   %-9s needs %3d %-16s %.2f/kill from %-22s ~%2d kill(s)  %d EHP%s%s" % [
					cur, int(qty), sym, best, str(src.get("eid", "?")), kills,
					int(effort), "  [BOSS]" if is_boss and not via_recipe else "",
					"  [via recipe]" if via_recipe else ""])
				# A boss the chain has not yet told the player to fight is not a faucet.
				# The v175 SalvageData fix put a demand at step 56 behind a boss whose
				# gear arrives at steps 60-62; every plausible step-56 loadout lost 0/21.
				# The guard called it "~4 kills, matches the norm" because it priced a
				# capstone identically to a trash mob.
				# Skipped when a recipe path is cheaper — then the boss is not the only
				# source and "can only source from BOSS" would be a false statement.
				if is_boss and not via_recipe and int(src.get("first_fight_step", 9999)) > steps:
					_fail("%s (step %d) can only source %s from BOSS %s, which the chain does not send the player at until step %d" % [
						cur, steps, sym, str(src.get("eid", "?")), int(src.get("first_fight_step", 9999))])
				# The kill count was printed and never asserted, so any nonzero faucet
				# produced the same green. The chain's own observed maximum is 4 kills;
				# allow headroom, but not a grind wall wearing a faucet's clothes.
				if effort > budget:
					_fail("%s needs %d %s = ~%d kills of %s%s; the chain's norm is <= %d" % [
						cur, int(qty), sym, kills, str(src.get("eid", "?")),
						" even via its cheapest recipe path" if via_recipe else "", MAX_KILLS])
		cur = str(m.get("next_mission", ""))

	print("[SUPPLY] walked %d beats, checked %d combat-drop demand(s), player reaches Zone %d" % [
		steps, checked, zone_now])
	# A floor, not a > 0 tripwire: a rename or a moved DB used to shrink coverage silently
	# while the guard kept printing PASS.
	if checked < 17:
		_fail("only %d combat-drop demand(s) checked; coverage has regressed (expected >= 17)" % checked)

	print("[SUPPLY] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


# The CHEAPEST source by total effort, not the richest by per-kill yield. Picking the
# highest rate made the guard prefer a Zone-2 boss (17,897 EHP) over the trash the player
# actually kills (633 EHP) and then report both as "~4 kills", which is how it certified
# a wall. Effort = EHP per unit of material.
# Guaranteed `loot` rows always drop; `rare_loot` rows are [symbol, chance, min, max].
func _cheapest_source(cm, sym: String, max_zone: int, first_fight: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_cost := INF
	for eid in cm.enemy_db:
		var e: Dictionary = cm.enemy_db[eid]
		var z: int = int(e.get("zone", 0))
		if z <= 0 or z > max_zone:
			continue
		var rate := 0.0
		for row in e.get("loot", []):
			var r: Array = row
			if str(r[0]) == sym:
				rate = maxf(rate, (float(r[1]) + float(r[2])) / 2.0)
		for row2 in e.get("rare_loot", []):
			var r2: Array = row2
			if str(r2[0]) == sym:
				rate = maxf(rate, float(r2[1]) * (float(r2[2]) + float(r2[3])) / 2.0)
		if str(e.get("boss_core", "")) == sym:
			rate = maxf(rate, float(e.get("boss_core_qty", 1)))
		if rate <= 0.0:
			continue
		var st: Dictionary = e.get("stats", {})
		var ehp: float = float(st.get("hp", 1)) + float(st.get("max_shield", 0))
		var per_unit: float = ehp / rate
		if per_unit < best_cost:
			best_cost = per_unit
			best = {"eid": str(eid), "rate": rate, "ehp": ehp,
				"boss": bool(str(e.get("boss_core", "")) != "" or str(eid).find("_boss_") >= 0),
				"first_fight_step": int(first_fight.get(str(eid), 9999))}
	return best


# EHP cost of ONE unit of each material, by the cheapest path available to a player
# who can enter zones 1..max_zone. Free things (gathered, or refined from gathered)
# cost 0. Everything else is priced in the only currency a combat demand really has:
# enemy effective HP that must be chewed through.
#
# Cached per zone — the chain walk only ever sees ten distinct zone values, and
# rebuilding this for all 85 beats would be pure waste.
var _effort_cache: Dictionary = {}

func _effort_at(cm, gm, qprod: Array, max_zone: int) -> Dictionary:
	if _effort_cache.has(max_zone):
		return _effort_cache[max_zone]

	var eff: Dictionary = {}
	# Gathered materials are free: a mining action costs time, not fights, and the
	# guard's whole subject is combat demands.
	for aid in gm.actions:
		for row in gm.actions[aid].get("loot_table", []):
			eff[str((row as Array)[0])] = 0.0
	# Seed every combat drop reachable in these zones at its best EHP-per-unit.
	for eid in cm.enemy_db:
		var e: Dictionary = cm.enemy_db[eid]
		var z: int = int(e.get("zone", 0))
		if z <= 0 or z > max_zone:
			continue
		var st: Dictionary = e.get("stats", {})
		var ehp: float = maxf(1.0, float(st.get("hp", 1)) + float(st.get("max_shield", 0)))
		var rates: Dictionary = {}
		for row2 in e.get("loot", []):
			var r: Array = row2
			rates[str(r[0])] = maxf(float(rates.get(str(r[0]), 0.0)), (float(r[1]) + float(r[2])) / 2.0)
		for row3 in e.get("rare_loot", []):
			var r3: Array = row3
			rates[str(r3[0])] = maxf(float(rates.get(str(r3[0]), 0.0)),
				float(r3[1]) * (float(r3[2]) + float(r3[3])) / 2.0)
		var core := str(e.get("boss_core", ""))
		if core != "":
			rates[core] = maxf(float(rates.get(core, 0.0)), float(e.get("boss_core_qty", 1)))
		for sym in rates:
			var rate: float = float(rates[sym])
			if rate <= 0.0:
				continue
			var per_unit: float = ehp / rate
			if not eff.has(str(sym)) or float(eff[str(sym)]) > per_unit:
				eff[str(sym)] = per_unit

	# Relax through quantified recipes to a fixed point, exactly as _relax does for
	# reachability: a candidate price only ever LOWERS an entry, so a production cycle
	# can never talk itself cheaper and simply never converges downward.
	var changed := true
	var passes := 0
	while changed and passes < 64:
		changed = false
		passes += 1
		for prod in qprod:
			var inp: Dictionary = prod["inp"]
			var outp: Dictionary = prod["out"]
			var total := 0.0
			var ok := true
			for i_sym in inp:
				if str(i_sym) == "credits":
					continue
				if not eff.has(str(i_sym)):
					ok = false
					break
				total += float(inp[i_sym]) * float(eff[str(i_sym)])
			if not ok:
				continue
			var out_qty := 0.0
			for o_sym in outp:
				out_qty += float(outp[o_sym])
			if out_qty <= 0.0:
				continue
			# Joint products share the bill by unit count. Crude, but it never prices a
			# by-product ABOVE making it alone, which is the direction that matters.
			var per: float = total / out_qty
			for o_sym2 in outp:
				if not eff.has(str(o_sym2)) or float(eff[str(o_sym2)]) > per:
					eff[str(o_sym2)] = per
					changed = true

	_effort_cache[max_zone] = eff
	return eff


# Relax `seed` through every producer until nothing improves. Cycles never lower a value,
# so they resolve to unreachable without a visited-set.
func _relax(seed: Dictionary, producers: Array) -> Dictionary:
	var out: Dictionary = seed
	var changed := true
	var passes := 0
	while changed and passes < 64:
		changed = false
		passes += 1
		for prod in producers:
			var worst := 0
			var reachable := true
			for need in (prod["needs"] as Array):
				if not out.has(str(need)):
					reachable = false
					break
				worst = maxi(worst, int(out[str(need)]))
			if not reachable:
				continue
			for outp in (prod["out"] as Array):
				if not out.has(str(outp)) or int(out[str(outp)]) > worst:
					out[str(outp)] = worst
					changed = true
	return out


func _note(d: Dictionary, sym: String, z: int) -> void:
	if not d.has(sym) or int(d[sym]) > z:
		d[sym] = z


func _fail(msg: String) -> void:
	print("[SUPPLY] FAIL: %s" % msg)
	fails += 1
