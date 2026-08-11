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

	# Everything obtainable WITHOUT fighting: gathered, refined, or produced.
	var non_combat: Dictionary = {}
	for aid in gm.actions:
		for row3 in gm.actions[aid].get("loot_table", []):
			non_combat[str((row3 as Array)[0])] = true
	for rid in pm.recipes:
		for o in (pm.recipes[rid].get("output", {}) as Dictionary):
			non_combat[str(o)] = true
	for bid in im.building_db:
		for o2 in (im.building_db[bid].get("output", {}) as Dictionary):
			non_combat[str(o2)] = true

	print("[SUPPLY] %d combat-drop material(s), %d obtainable without fighting" % [
		drop_zone.size(), non_combat.size()])

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
			if sym == "credits" or non_combat.has(sym):
				continue                       # mineable / craftable / produced
			if not drop_zone.has(sym):
				_fail("%s needs %s, which nothing in the game produces or drops" % [cur, sym])
				continue
			checked += 1
			# Reachable is necessary but not sufficient — a faucet that yields 0.02 per
			# kill is technically a source and practically a wall. Report the best rate
			# available at this point and what the quota costs in kills, so a future
			# tuning pass argues from a number instead of a vibe.
			var src: Dictionary = _cheapest_source(cm, sym, zone_now, first_fight)
			var best: float = float(src.get("rate", 0.0))
			if best > 0.0:
				var kills: int = int(ceil(float(cost[item]) / best))
				var is_boss: bool = bool(src.get("boss", false))
				print("[SUPPLY]   %-9s needs %3d %-16s %.2f/kill from %-22s ~%2d kill(s)  %d EHP%s" % [
					cur, int(cost[item]), sym, best, str(src.get("eid", "?")), kills,
					int(float(src.get("ehp", 0.0)) * float(kills)),
					"  [BOSS]" if is_boss else ""])
				# A boss the chain has not yet told the player to fight is not a faucet.
				# The v175 SalvageData fix put a demand at step 56 behind a boss whose
				# gear arrives at steps 60-62; every plausible step-56 loadout lost 0/21.
				# The guard called it "~4 kills, matches the norm" because it priced a
				# capstone identically to a trash mob.
				if is_boss and int(src.get("first_fight_step", 9999)) > steps:
					_fail("%s (step %d) can only source %s from BOSS %s, which the chain does not send the player at until step %d" % [
						cur, steps, sym, str(src.get("eid", "?")), int(src.get("first_fight_step", 9999))])
				# The kill count was printed and never asserted, so any nonzero faucet
				# produced the same green. The chain's own observed maximum is 4 kills;
				# allow headroom, but not a grind wall wearing a faucet's clothes.
				if kills > MAX_KILLS:
					_fail("%s needs %d %s = ~%d kills of %s; the chain's norm is <= %d" % [
						cur, int(cost[item]), sym, kills, str(src.get("eid", "?")), MAX_KILLS])
			var need_z: int = int(drop_zone[sym])
			if need_z > zone_now:
				_fail("%s (chain step %d) needs %d %s, but its only faucet is Zone %d and the chain has opened Zone %d" % [
					cur, steps, int(cost[item]), sym, need_z, zone_now])
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


func _note(d: Dictionary, sym: String, z: int) -> void:
	if not d.has(sym) or int(d[sym]) > z:
		d[sym] = z


func _fail(msg: String) -> void:
	print("[SUPPLY] FAIL: %s" % msg)
	fails += 1
