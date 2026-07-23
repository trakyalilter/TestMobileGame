extends Node
# ============================================================================
# ITEM ECONOMY AUDIT (v141c) — the MATERIAL graph, not the Lira graph.
#
# Every material is a node; every recipe / building / module / tech is an edge.
# This walks the whole graph and answers the questions that actually govern a
# crafting idle:
#   1. what is produced and never consumed        (dead end -> cargo tax)
#   2. what is consumed and never produced        (deadlock -> hard wall)
#   3. what hangs off a SINGLE producer/consumer  (fragile chain)
#   4. what does one unit really cost, expanded to raw ore + active minutes
#   5. which raw materials are over-subscribed by the recipes that need them
#
# "Raw" = a material with no producing recipe: it comes from a gather action,
# a building, or combat loot. Acquisition time is priced against the BEST
# available source rate, because this is a single-active-task game — the player
# can only run one of them at a time, so the best rate is the real rate.
#
#   Godot --headless --path <root> res://scenes/item_economy_audit.tscn
# ============================================================================

const MAX_DEPTH := 24
const REF_KILL_SECONDS := 60.0   # combat loot -> units/min, same assumption as econ_audit

# Items whose sink is GAMEPLAY, not another recipe: ammo is spent firing,
# consumables are spent healing, modules are equipped, and these five are
# passive "while held" trinkets checked via get_element_amount (bounty_manager
# 53-59, shipyard_manager 2415/2478, infrastructure_manager 1074). None of them
# is a dead end; counting them as such buries the real ones in noise.
const HELD_TRINKETS := ["VoidBattery", "TemporalModule", "PrimordialArmor",
	"OmegaAccelerator", "BoostCard"]

var _terminal := {}


func _build_terminal_set() -> void:
	var sm = GameState.shipyard_manager
	# matrix_cores are socketed into modules (insert_gem, shipyard_manager 2171) —
	# the socket IS the sink. Resonant is the top fuse tier with no fuse-up, so
	# without this it reads as a dead end while being the best gem in the game.
	for cat in ["ammo", "consumables", "matrix_cores"]:
		for s in ElementDB.CATEGORIES.get(cat, []):
			_terminal[String(s)] = cat
	for mid in sm.modules:
		_terminal[String(mid)] = "module"
	for t in HELD_TRINKETS:
		_terminal[String(t)] = "trinket"

var producers := {}   # sym -> [ [kind, id, units_per_min] ]
var consumers := {}   # sym -> [ [kind, id, qty_per_cycle, units_per_min_or_-1] ]
var best_rate := {}   # sym -> best units/min from any NON-recipe source (raw supply)
var recipe_for := {}  # sym -> recipe_id that outputs it (cheapest by raw units)
var _raw_memo := {}
var _visiting := {}
var _all_syms := {}


func _pad(s: String, n: int) -> String:
	var out := s
	while out.length() < n:
		out += " "
	return out


func _note_prod(sym: String, kind: String, id: String, rate: float) -> void:
	var s := String(sym)
	_all_syms[s] = true
	if not producers.has(s):
		producers[s] = []
	producers[s].append([kind, id, rate])
	if kind != "recipe":
		best_rate[s] = maxf(float(best_rate.get(s, 0.0)), rate)


func _note_cons(sym: String, kind: String, id: String, qty: float, rate: float) -> void:
	var s := String(sym)
	_all_syms[s] = true
	if not consumers.has(s):
		consumers[s] = []
	consumers[s].append([kind, id, qty, rate])


func _ready() -> void:
	GameState.hard_reset()
	print("[ITEM] ============== ITEM ECONOMY AUDIT ==============")
	print("[ITEM] tier_gate_enabled = %s (drives the per-zone alloy module tax)" % str(
		GameState.game_settings.get("tier_gate_enabled", false)))
	_build_terminal_set()
	_index_gathering()
	_index_infra()
	_index_recipes()
	_index_modules()
	_index_research()
	_index_combat()
	print("[ITEM] indexed %d distinct materials" % _all_syms.size())
	_report_dead_ends()
	_report_deadlocks()
	_report_thin()
	_report_raw_cost()
	_report_raw_pressure()
	_report_tech_bom()
	_report_level_deflation()
	print("[ITEM] ============== END ==============")
	get_tree().quit()


# ── indexing ────────────────────────────────────────────────────────────────
func _index_gathering() -> void:
	var gm = GameState.gathering_manager
	for aid in gm.actions:
		var a = gm.actions[aid]
		var dur: float = float(a.get("duration", 4.0))
		var lt: Array = a.get("loot_table", [])
		for i in range(lt.size()):
			var e: Array = lt[i]
			var per_min: float = float(e[1]) * float(e[3]) / dur * 60.0
			_note_prod(String(e[0]), "gather", String(aid), per_min)


func _index_infra() -> void:
	var im = GameState.infrastructure_manager
	for bid in im.building_db:
		var d = im.building_db[bid]
		var rate: Dictionary = im.get_building_adjusted_rate(bid)
		for res in rate.get("yield", {}):
			_note_prod(String(res), "building", String(bid), float(rate["yield"][res]))
		for res in rate.get("input", {}):
			_note_cons(String(res), "building_feed", String(bid), 0.0, float(rate["input"][res]))
		# One-off construction cost is real demand too — a 2000-Steel building is
		# a bigger sink than most recipes ever are.
		for res in d.get("cost", {}):
			if String(res) == "credits":
				continue
			_note_cons(String(res), "build_cost", String(bid), float(d["cost"][res]), -1.0)


func _index_recipes() -> void:
	var pm = GameState.processing_manager
	for rid in pm.recipes:
		var rec = pm.recipes[rid]
		var dur: float = float(rec.get("duration", 5.0))
		for s in rec.get("input", {}):
			_note_cons(String(s), "recipe", String(rid), float(rec["input"][s]), float(rec["input"][s]) / dur * 60.0)
		for s in rec.get("output", {}):
			_note_prod(String(s), "recipe", String(rid), float(rec["output"][s]) / dur * 60.0)
			if not recipe_for.has(String(s)):
				recipe_for[String(s)] = String(rid)
		for entry in rec.get("output_table", []):
			var avg: float = (float(entry[2]) + float(entry[3])) * 0.5 * float(entry[1])
			_note_prod(String(entry[0]), "recipe_byproduct", String(rid), avg / dur * 60.0)


func _index_modules() -> void:
	var sm = GameState.shipyard_manager
	for mid in sm.modules:
		var m = sm.modules[mid]
		# v114 tier-gate injects the per-zone signature alloy at CRAFT time, so the
		# static cost dict understates demand — every Z2-Z10 common module also eats
		# its zone alloy. Reading the effective cost is the difference between "9
		# alloys are dead ends" and "9 alloys are the tier gate".
		var cost: Dictionary = sm.get_effective_module_cost(m)
		for s in cost:
			if String(s) == "credits":
				continue
			_note_cons(String(s), "module", String(mid), float(cost[s]), -1.0)
		# Gem synthesis lives in craft_module() as a special case, not in a data
		# table: matrix_synthesis rolls a Cracked core, and each gem_synth module
		# fuses two of one tier into the next. Coarse edge (all matrix_cores), but
		# it correctly stops the gem tree reading as 12 deadlocks.
		if String(mid) == "matrix_synthesis" or String(m.get("slot_type", "")) == "gem_synth":
			for g in ElementDB.CATEGORIES.get("matrix_cores", []):
				_note_prod(String(g), "gem_synth", String(mid), 0.0)
	for hid in sm.hulls:
		var h = sm.hulls[hid]
		for s in h.get("cost", {}):
			if String(s) == "credits":
				continue
			_note_cons(String(s), "hull", String(hid), float(h["cost"][s]), -1.0)


func _index_research() -> void:
	var rm = GameState.research_manager
	for tid in rm.tech_tree:
		var t = rm.tech_tree[tid]
		for s in t.get("cost_items", {}):
			_note_cons(String(s), "research", String(tid), float(t["cost_items"][s]), -1.0)


func _index_combat() -> void:
	var cm = GameState.combat_manager
	for eid in cm.enemy_db:
		var e = cm.enemy_db[eid]
		for entry in e.get("loot", []):
			if String(entry[0]) == "credits":
				continue
			var avg: float = (float(entry[1]) + float(entry[2])) * 0.5
			_note_prod(String(entry[0]), "combat", String(eid), avg / REF_KILL_SECONDS * 60.0)
		for entry in e.get("rare_loot", []):
			if String(entry[0]) == "credits":
				continue
			var avg2: float = (float(entry[2]) + float(entry[3])) * 0.5 * float(entry[1])
			_note_prod(String(entry[0]), "combat_rare", String(eid), avg2 / REF_KILL_SECONDS * 60.0)
		# Boss cores are granted from a dedicated field, NOT the loot arrays — miss
		# this and all ten zone cores read as deadlocks while being the single most
		# important gating item in the game (every zone_N_access tech eats one).
		var core := String(e.get("boss_core", ""))
		if core != "":
			var qty := float(e.get("boss_core_qty", 1))
			_note_prod(core, "boss_core", String(eid), qty / REF_KILL_SECONDS * 60.0)


# ── 1. dead ends ────────────────────────────────────────────────────────────
func _report_dead_ends() -> void:
	print("")
	print("[ITEM] == 1. DEAD ENDS (produced, ZERO consumers) ==")
	print("[ITEM]    a dead-end material is pure cargo tax: slots are capped, so it")
	print("[ITEM]    actively costs the player to keep producing it")
	print("[ITEM]    (ammo / consumables / modules / held trinkets excluded - their")
	print("[ITEM]     sink is gameplay, not a recipe)")
	var n := 0
	var excused := 0
	for sym in _all_syms:
		var s := String(sym)
		if producers.has(s) and not consumers.has(s):
			if _terminal.has(s):
				excused += 1
				continue
			var srcs: Array = producers[s]
			var kinds := {}
			for p in srcs:
				kinds[String(p[0])] = true
			print("[ITEM]    %s produced by %d source(s) %s" % [_pad(s, 24), srcs.size(), str(kinds.keys())])
			n += 1
	print("[ITEM]    TOTAL DEAD ENDS: %d   (+%d terminal-use, excused)" % [n, excused])


# ── 2. deadlocks ────────────────────────────────────────────────────────────
func _report_deadlocks() -> void:
	print("")
	print("[ITEM] == 2. DEADLOCKS (consumed, ZERO producers) ==")
	print("[ITEM]    anything demanded with no source is a hard progression wall")
	var n := 0
	for sym in _all_syms:
		var s := String(sym)
		if consumers.has(s) and not producers.has(s):
			var dst: Array = consumers[s]
			var who := []
			for c in dst:
				who.append("%s:%s" % [String(c[0]), String(c[1])])
			print("[ITEM]    %s demanded by %s" % [_pad(s, 24), str(who).substr(0, 110)])
			n += 1
	print("[ITEM]    TOTAL DEADLOCKS: %d" % n)


# ── 3. thin chains ──────────────────────────────────────────────────────────
func _report_thin() -> void:
	print("")
	print("[ITEM] == 3. THIN CHAINS (single producer AND >=3 consumers) ==")
	print("[ITEM]    one source feeding many sinks is the shape that becomes a")
	print("[ITEM]    bottleneck the moment that source is level- or research-gated")
	var rows := []
	for sym in _all_syms:
		var s := String(sym)
		if not producers.has(s) or not consumers.has(s):
			continue
		var np: int = (producers[s] as Array).size()
		var nc: int = (consumers[s] as Array).size()
		if np == 1 and nc >= 3:
			var p: Array = producers[s][0]
			rows.append([s, String(p[0]), String(p[1]), nc])
	rows.sort_custom(func(x, y): return int(x[3]) > int(y[3]))
	for r in rows:
		print("[ITEM]    %s only from %s:%s  ->  %d consumers" % [
			_pad(String(r[0]), 24), String(r[1]), _pad(String(r[2]), 24), int(r[3])])
	print("[ITEM]    TOTAL THIN: %d" % rows.size())


# ── 4. true cost of a crafted item ──────────────────────────────────────────
# Expands a material to raw inputs, then prices those raw units in ACTIVE
# MINUTES at the best non-recipe source rate. This is the number that decides
# whether a recipe is worth a player's evening.
func _raw_of(sym: String, depth: int) -> Dictionary:
	if _raw_memo.has(sym):
		return _raw_memo[sym]
	if depth > MAX_DEPTH or _visiting.has(sym):
		return {"raw": {sym: 1.0}, "craft_s": 0.0, "cyclic": true}
	if not recipe_for.has(sym):
		return {"raw": {sym: 1.0}, "craft_s": 0.0, "cyclic": false}

	_visiting[sym] = true
	var pm = GameState.processing_manager
	var rid: String = recipe_for[sym]
	var rec = pm.recipes[rid]
	# v141c: units produced per CYCLE at the current Engineering level — the flat
	# raises this, so a higher level needs fewer cycles, which cuts both the raw
	# inputs and the machine time for everything downstream. Reading the authored
	# dict here would price the whole tree at Lv1 forever.
	var out_qty: float = maxf(1.0, pm.get_display_output(rid, sym))
	var raw := {}
	var craft_s: float = float(rec.get("duration", 5.0)) / out_qty
	var cyclic := false
	for s in rec.get("input", {}):
		var need: float = float(rec["input"][s]) / out_qty
		var sub: Dictionary = _raw_of(String(s), depth + 1)
		if bool(sub.get("cyclic", false)):
			cyclic = true
		for r in sub["raw"]:
			raw[r] = float(raw.get(r, 0.0)) + float(sub["raw"][r]) * need
		craft_s += float(sub["craft_s"]) * need
	_visiting.erase(sym)
	var res := {"raw": raw, "craft_s": craft_s, "cyclic": cyclic}
	_raw_memo[sym] = res
	return res


func _report_raw_cost() -> void:
	print("")
	print("[ITEM] == 4. TRUE COST PER UNIT (expanded to raw, in active minutes) ==")
	print("[ITEM]    gather_min = raw units / best source rate; craft_min = machine time")
	print("[ITEM]    UNSOURCED = a raw input with no gather/building/combat source at all")
	var rows := []
	for sym in recipe_for:
		var s := String(sym)
		var r: Dictionary = _raw_of(s, 0)
		var gather_min := 0.0
		var unsourced := []
		var raw_units := 0.0
		for raw_sym in r["raw"]:
			var qty: float = float(r["raw"][raw_sym])
			raw_units += qty
			var rate: float = float(best_rate.get(String(raw_sym), 0.0))
			if rate <= 0.0:
				unsourced.append(String(raw_sym))
			else:
				gather_min += qty / rate
		rows.append([s, raw_units, gather_min, float(r["craft_s"]) / 60.0, unsourced, bool(r.get("cyclic", false))])
	rows.sort_custom(func(x, y): return float(x[2]) > float(y[2]))
	print("[ITEM]    %s %10s %11s %10s  %s" % [_pad("item", 26), "raw units", "gather_min", "craft_min", "flags"])
	for i in range(mini(25, rows.size())):
		var r = rows[i]
		var flags := ""
		if not (r[4] as Array).is_empty():
			flags += "UNSOURCED:%s " % str(r[4]).substr(0, 60)
		if bool(r[5]):
			flags += "CYCLIC"
		print("[ITEM]    %s %10.1f %11.1f %10.1f  %s" % [
			_pad(String(r[0]), 26), float(r[1]), float(r[2]), float(r[3]), flags])

	var bad := []
	for r in rows:
		if not (r[4] as Array).is_empty():
			bad.append(String(r[0]))
	print("[ITEM]    items whose raw tree contains an UNSOURCED input: %d" % bad.size())
	if not bad.is_empty():
		print("[ITEM]      %s" % str(bad).substr(0, 400))


# ── 5. raw supply pressure ──────────────────────────────────────────────────
# How many distinct recipes/buildings/modules pull on each RAW material. A raw
# with 30 consumers and one slow gather action is where the whole game queues.
func _report_raw_pressure() -> void:
	print("")
	print("[ITEM] == 5. RAW MATERIAL PRESSURE (consumers vs best supply rate) ==")
	var rows := []
	for sym in _all_syms:
		var s := String(sym)
		if recipe_for.has(s):
			continue   # not raw
		if not consumers.has(s):
			continue
		var nc: int = (consumers[s] as Array).size()
		var rate: float = float(best_rate.get(s, 0.0))
		rows.append([s, nc, rate])
	rows.sort_custom(func(x, y): return int(x[1]) > int(y[1]))
	print("[ITEM]    %s %10s %14s" % [_pad("raw material", 24), "consumers", "best units/min"])
	for i in range(mini(20, rows.size())):
		var r = rows[i]
		var warn := "   <-- NO SOURCE" if float(r[2]) <= 0.0 else ""
		print("[ITEM]    %s %10d %14.1f%s" % [_pad(String(r[0]), 24), int(r[1]), float(r[2]), warn])


# ── 6. research bill of materials ───────────────────────────────────────────
# Research is the single biggest material sink in the game and the only one
# whose costs are MULTIPLIED after authoring (_scale_mid_late_research_item_costs
# runs in _init: MID x2.5, LATE x7.5, ENDGAME x20). A tech authored as "5
# AIProcessor" ships as 100. Reading the tree at runtime is the only honest way
# to price it, and the craft-hours column is what the player actually spends.
func _report_tech_bom() -> void:
	var rm = GameState.research_manager
	print("")
	print("[ITEM] == 6. RESEARCH BILL OF MATERIALS (runtime-scaled costs) ==")
	print("[ITEM]    scaling: MID x%.1f  LATE x%.1f  ENDGAME x%.1f (zone techs exempt)" % [
		rm.MID_RESEARCH_ITEM_REQ_MULT, rm.LATE_RESEARCH_ITEM_REQ_MULT, rm.ENDGAME_RESEARCH_ITEM_REQ_MULT])
	var rows := []
	for tid in rm.tech_tree:
		var t = rm.tech_tree[tid]
		var items: Dictionary = t.get("cost_items", {})
		if items.is_empty():
			continue
		var raw_units := 0.0
		var gather_min := 0.0
		var craft_min := 0.0
		var drivers := []   # per cost item, so the fix can target the real culprit
		for s in items:
			# tech_tree holds the STAGE-scaled qty; can_unlock/unlock_tech then apply
			# MATERIAL_MULTIPLIER on top (_effective_item_requirement). Reading the
			# dict alone understates what the player actually pays by 2x.
			var qty := float(rm._effective_item_requirement(String(s), int(items[s])))
			var r: Dictionary = _raw_of(String(s), 0)
			var item_raw := 0.0
			craft_min += float(r["craft_s"]) / 60.0 * qty
			for raw_sym in r["raw"]:
				var q: float = float(r["raw"][raw_sym]) * qty
				item_raw += q
				var rate: float = float(best_rate.get(String(raw_sym), 0.0))
				if rate > 0.0:
					gather_min += q / rate
			raw_units += item_raw
			drivers.append([String(s), qty, item_raw])
		drivers.sort_custom(func(x, y): return float(x[2]) > float(y[2]))
		rows.append([String(tid), raw_units, gather_min, craft_min, drivers])
	rows.sort_custom(func(x, y): return float(x[3]) > float(y[3]))
	print("[ITEM]    %s %12s %11s %12s" % [_pad("tech", 26), "raw units", "gather_h", "CRAFT_H"])
	for i in range(mini(12, rows.size())):
		var r = rows[i]
		print("[ITEM]    %s %12.0f %11.1f %12.1f" % [
			_pad(String(r[0]), 26), float(r[1]), float(r[2]) / 60.0, float(r[3]) / 60.0])
		var d: Array = r[4]
		var top := []
		for j in range(mini(3, d.size())):
			top.append("%s x%d = %.0f raw" % [String(d[j][0]), int(d[j][1]), float(d[j][2])])
		print("[ITEM]        drivers: %s" % ", ".join(top))


# ── 7. skill-level cost deflation ───────────────────────────────────────────
# v141c added a flat +1-per-10-levels to gathering yield AND to every Engineering
# output. Both compound down a crafting tree: a higher Engineering level means
# fewer cycles per unit, which cuts the raw inputs AND the machine time of every
# parent recipe. This measures how much cheaper the SAME item gets purely from
# levelling, which is the number that decides whether requirements need raising.
const DEFLATION_LEVELS := [1, 25, 50, 75, 100]
const BASKET := ["Steel", "Circuit", "AdvCircuit", "BatteryT1", "Res2", "Res3",
	"AICore", "AIProcessor", "Superalloy", "Hydraulics"]
const BASKET_TECHS := ["quantum_dynamics", "perfect_automation", "zone_10_access",
	"efficiency_2", "capital_ship_armament"]


func _set_econ_level(lv: int) -> void:
	var gm = GameState.gathering_manager
	var pm = GameState.processing_manager
	for mgr in [gm, pm]:
		if mgr:
			mgr.xp = float(mgr.get_xp_for_level(lv))
			mgr.level = 1
			mgr.check_level_up()
	# Everything downstream is level-dependent now, so both caches must go.
	_raw_memo.clear()
	best_rate.clear()
	_index_gathering_rates()


# Gathering supply at the CURRENT level (get_display_yield folds the flat).
# Buildings/combat rates don't move with skill level, so they are re-added from
# the original index rather than recomputed.
func _index_gathering_rates() -> void:
	var gm = GameState.gathering_manager
	for aid in gm.actions:
		var a = gm.actions[aid]
		var dur: float = float(a.get("duration", 4.0))
		var lt: Array = a.get("loot_table", [])
		for i in range(lt.size()):
			var e: Array = lt[i]
			var per_min: float = float(e[1]) * float(gm.get_display_yield(e, i)) / dur * 60.0
			var s := String(e[0])
			best_rate[s] = maxf(float(best_rate.get(s, 0.0)), per_min)
	# Re-fold the non-skill sources so raw materials that only drop in combat or
	# come from a building still price.
	for s in producers:
		for p in producers[s]:
			if String(p[0]) != "gather" and String(p[0]) != "recipe":
				best_rate[String(s)] = maxf(float(best_rate.get(String(s), 0.0)), float(p[2]))


func _cost_minutes(sym: String, qty: float) -> Array:
	var r: Dictionary = _raw_of(sym, 0)
	var gather_min := 0.0
	for raw_sym in r["raw"]:
		var q: float = float(r["raw"][raw_sym]) * qty
		var rate: float = float(best_rate.get(String(raw_sym), 0.0))
		if rate > 0.0:
			gather_min += q / rate
	return [gather_min, float(r["craft_s"]) / 60.0 * qty]


func _report_level_deflation() -> void:
	var rm = GameState.research_manager
	print("")
	print("[ITEM] == 7. COST DEFLATION BY SKILL LEVEL (v141c flats) ==")
	print("[ITEM]    total active minutes (gather + craft) for ONE unit, by skill level")
	print("[ITEM]    %s %9s %9s %9s %9s %9s   %s" % [
		_pad("item", 20), "L1", "L25", "L50", "L75", "L100", "L1->L100"])
	for sym in BASKET:
		if not recipe_for.has(sym) and not best_rate.has(sym):
			continue
		var cells := []
		var first := 0.0
		var last := 0.0
		for lv in DEFLATION_LEVELS:
			_set_econ_level(int(lv))
			var c: Array = _cost_minutes(sym, 1.0)
			var total: float = float(c[0]) + float(c[1])
			cells.append(total)
			if int(lv) == DEFLATION_LEVELS[0]:
				first = total
			last = total
		var factor: String = "-" if last <= 0.0 else ("%.2fx cheaper" % (first / maxf(last, 0.0001)))
		var line := "[ITEM]    %s" % _pad(sym, 20)
		for c in cells:
			line += "%10.1f" % float(c)
		print(line + "   " + factor)

	print("")
	print("[ITEM]    research techs — total active HOURS (gather + craft), by skill level")
	print("[ITEM]    %s %9s %9s %9s %9s %9s   %s" % [
		_pad("tech", 24), "L1", "L25", "L50", "L75", "L100", "L1->L100"])
	for tid in BASKET_TECHS:
		if not rm.tech_tree.has(tid):
			continue
		var items: Dictionary = rm.tech_tree[tid].get("cost_items", {})
		var cells := []
		var first := 0.0
		var last := 0.0
		for lv in DEFLATION_LEVELS:
			_set_econ_level(int(lv))
			var total := 0.0
			for s in items:
				var qty := float(rm._effective_item_requirement(String(s), int(items[s])))
				var c: Array = _cost_minutes(String(s), qty)
				total += float(c[0]) + float(c[1])
			total /= 60.0
			cells.append(total)
			if int(lv) == DEFLATION_LEVELS[0]:
				first = total
			last = total
		var factor: String = "-" if last <= 0.0 else ("%.2fx cheaper" % (first / maxf(last, 0.0001)))
		var line := "[ITEM]    %s" % _pad(tid, 24)
		for c in cells:
			line += "%10.1f" % float(c)
		print(line + "   " + factor)
	_set_econ_level(1)
