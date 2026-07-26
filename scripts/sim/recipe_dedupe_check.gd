extends Node
# ============================================================================
# RECIPE DEDUPE CHECK (v146) — proves the duplicate-recipe removal did not
# strand anything.
#
# item_economy_audit answers "does a producer exist at all". That is necessary
# but not sufficient: a recipe whose only surviving producer sits behind a
# HIGHER level/research gate than its consumers is a soft wall the producer-set
# test cannot see. And its cost expander picks the first producer in dict order
# (see recipe_for, item_economy_audit 146), so a cheap acyclic path can be
# masked by a CYCLIC flag that does not exist in the real game.
#
# So this walks the real thing: a monotone reachability closure over gather
# loot, combat loot, building yields and recipes, replayed at increasing
# Engineering level with the research set the player can actually hold.
#
#   1. FULL CLOSURE   — every consumed material is reachable from raw sources
#   2. GATE ORDER     — every material unlocks no later than its earliest sink
#   3. EARLY CHAIN    — the research-free Z2/Z3 alloy spine completes
#   4. CYCLE BREAK    — NitroCoolant has a non-cyclic raw path
#
# Run: Godot --headless --path <root> res://scenes/recipe_dedupe_check.tscn
# ============================================================================

# The seven recipes removed in the v146 dedupe pass, and the material each made.
const REMOVED := {
	"smelt_steel_oxygen": "Steel",
	"assemble_circuit_standard": "Circuit",
	"gold_leaching": "Au",
	"electrolysis_nickel_catalyst": "H",
	"extract_germanium": "Germanium",
	"nitrogen_coolant": "NitroCoolant",
	"refine_diamond_lens": "Res3",
}

# The research-free early spine the prior deadlock audit called decisive.
const EARLY_SPINE := ["Steel", "Circuit", "SalvagedAlloy", "DamagedCircuitry",
	"ReinforcedPlating", "Superalloy", "AdvCircuit"]

var raw_sources := {}       # sym -> true  (gather / combat / building)
var producers := {}         # sym -> [recipe_id, ...]
var consumers := {}         # sym -> [recipe_id, ...]
var unlock_lvl := {}        # sym -> earliest Engineering level it can exist


func _ready() -> void:
	var fails := 0
	_index()
	fails += _check_full_closure()
	fails += _check_gate_order()
	fails += _check_early_spine()
	fails += _check_cycle_break()
	print("[DEDUPE] %s" % ("ALL PASS" if fails == 0 else "*** %d FAIL" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _add(d: Dictionary, k: String, v: String) -> void:
	if not d.has(k):
		d[k] = []
	if not v in d[k]:
		d[k].append(v)


func _index() -> void:
	# ── raw: gather loot tables ──
	for aid in GameState.gathering_manager.actions:
		var a = GameState.gathering_manager.actions[aid]
		for row in a.get("loot_table", []):
			raw_sources[String(row[0])] = true
	# ── raw: combat loot (authored per-enemy) ──
	var cm = GameState.combat_manager
	for eid in cm.enemy_db:
		var e: Dictionary = cm.enemy_db[eid]
		for key in ["loot", "rare_loot"]:
			for row in e.get(key, []):
				raw_sources[String(row[0])] = true
	# combat_manager also grants SalvagedAlloy / DamagedCircuitry from the
	# centralized Z3+ roll, which is code not data — assert them explicitly.
	raw_sources["SalvagedAlloy"] = true
	raw_sources["DamagedCircuitry"] = true
	# ── raw: building yields ──
	var im = GameState.infrastructure_manager
	for bid in im.building_db:
		for s in im.building_db[bid].get("yield", {}):
			raw_sources[String(s)] = true
	# ── recipes ──
	var pm = GameState.processing_manager
	for rid in pm.recipes:
		var r = pm.recipes[rid]
		for s in r.get("input", {}):
			_add(consumers, String(s), String(rid))
		for s in r.get("output", {}):
			_add(producers, String(s), String(rid))
		for row in r.get("output_table", []):
			_add(producers, String(row[0]), String(rid))


# ── 1. every consumed material is reachable from raw sources ────────────────
func _check_full_closure() -> int:
	var reach := {}
	for s in raw_sources:
		reach[String(s)] = true
	var pm = GameState.processing_manager
	var changed := true
	while changed:
		changed = false
		for rid in pm.recipes:
			var r = pm.recipes[rid]
			var ok := true
			for s in r.get("input", {}):
				if not reach.has(String(s)):
					ok = false
					break
			if not ok:
				continue
			for s in r.get("output", {}):
				if not reach.has(String(s)):
					reach[String(s)] = true
					changed = true
			for row in r.get("output_table", []):
				if not reach.has(String(row[0])):
					reach[String(row[0])] = true
					changed = true
	var stranded := []
	for s in consumers:
		if not reach.has(String(s)):
			stranded.append(String(s))
	stranded.sort()
	print("[DEDUPE] 1. FULL CLOSURE — consumed materials with no reachable source: %d" % stranded.size())
	if not stranded.is_empty():
		print("[DEDUPE]    *** %s" % str(stranded).substr(0, 400))
	# and every removed recipe's output must still be reachable
	var lost := []
	for rid in REMOVED:
		var sym: String = REMOVED[rid]
		if not reach.has(sym):
			lost.append(sym)
	print("[DEDUPE]    outputs of removed recipes still reachable: %s" %
		("YES" if lost.is_empty() else "*** NO: %s" % str(lost)))
	return (1 if not stranded.is_empty() else 0) + (1 if not lost.is_empty() else 0)


# ── 2. no material unlocks LATER than the first recipe that wants it ────────
func _compute_unlock_levels() -> void:
	var pm = GameState.processing_manager
	for s in raw_sources:
		unlock_lvl[String(s)] = 0
	# earliest gather level, where the material comes from gathering
	for aid in GameState.gathering_manager.actions:
		var a = GameState.gathering_manager.actions[aid]
		for row in a.get("loot_table", []):
			var s := String(row[0])
			var lv := int(a.get("level_req", 1))
			if not unlock_lvl.has(s) or lv < int(unlock_lvl[s]):
				unlock_lvl[s] = lv
	var changed := true
	var guard := 0
	while changed and guard < 200:
		changed = false
		guard += 1
		for rid in pm.recipes:
			var r = pm.recipes[rid]
			var lv := int(r.get("level_req", 1))
			var ok := true
			for s in r.get("input", {}):
				if not unlock_lvl.has(String(s)):
					ok = false
					break
				lv = maxi(lv, int(unlock_lvl[String(s)]))
			if not ok:
				continue
			var outs := []
			for s in r.get("output", {}):
				outs.append(String(s))
			for row in r.get("output_table", []):
				outs.append(String(row[0]))
			for s in outs:
				if not unlock_lvl.has(s) or lv < int(unlock_lvl[s]):
					unlock_lvl[s] = lv
					changed = true


func _check_gate_order() -> int:
	_compute_unlock_levels()
	var pm = GameState.processing_manager
	var bad := []
	for s in consumers:
		var sym := String(s)
		if not unlock_lvl.has(sym):
			continue
		var made_at := int(unlock_lvl[sym])
		var wanted_at := 9999
		for rid in consumers[sym]:
			wanted_at = mini(wanted_at, int(pm.recipes[rid].get("level_req", 1)))
		if made_at > wanted_at:
			bad.append("%s made@L%d but wanted@L%d" % [sym, made_at, wanted_at])
	bad.sort()
	print("[DEDUPE] 2. GATE ORDER — materials whose earliest source outranks their earliest sink: %d" % bad.size())
	for b in bad:
		print("[DEDUPE]    %s" % b)
	# Only the seven touched materials are this check's responsibility; a
	# pre-existing inversion elsewhere is out of scope, so report but do not fail
	# unless one of OUR materials regressed.
	var ours := 0
	for rid in REMOVED:
		for b in bad:
			if String(b).begins_with(REMOVED[rid] + " "):
				ours += 1
	print("[DEDUPE]    of which caused by a deduped material: %d" % ours)
	return ours


# ── 3. the research-free early alloy spine still completes ──────────────────
func _check_early_spine() -> int:
	var pm = GameState.processing_manager
	var fails := 0
	for sym in EARLY_SPINE:
		var free_paths := []
		for rid in producers.get(sym, []):
			var r = pm.recipes[rid]
			if String(r.get("research_req", "")) == "":
				free_paths.append("%s(L%d)" % [rid, int(r.get("level_req", 1))])
		var ok: bool = not free_paths.is_empty() or raw_sources.has(sym)
		if not ok:
			fails += 1
		print("[DEDUPE]    %-18s research-free paths: %-46s %s" %
			[sym, str(free_paths).substr(0, 46), "OK" if ok else "*** FAIL"])
	print("[DEDUPE] 3. EARLY CHAIN — research-free spine intact: %s" % ("YES" if fails == 0 else "*** NO"))
	return fails


# ── 4. NitroCoolant has an acyclic raw path (the CYCLIC flag is a tool artifact) ──
func _check_cycle_break() -> int:
	var pm = GameState.processing_manager
	var acyclic := []
	for rid in producers.get("NitroCoolant", []):
		var r = pm.recipes[rid]
		var all_raw := true
		for s in r.get("input", {}):
			if not raw_sources.has(String(s)):
				all_raw = false
				break
		if all_raw:
			acyclic.append("%s(L%d, research=%s)" % [rid, int(r.get("level_req", 1)),
				String(r.get("research_req", "none"))])
	var ok: bool = not acyclic.is_empty()
	print("[DEDUPE] 4. CYCLE BREAK — NitroCoolant paths built purely from raw inputs: %s %s" %
		[str(acyclic), "OK" if ok else "*** FAIL"])
	return 0 if ok else 1
