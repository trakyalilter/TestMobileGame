extends Node
# ============================================================================
# DESIGN AUDIT — the DEMAND economy.
#
# Owner call: raw materials have no sell value and the sell path is being removed.
# So "which action do I run?" is NOT an income question — it is a DEMAND question:
# "which material am I short of for the thing I want next?" That makes the demand
# graph the core loop. This audits that graph.
#
#   1. DEAD-END      — a material produced but consumed by NOTHING. Its action is
#                      a dead button: the player can never have a reason to run it.
#   2. UNOBTAINABLE  — a material consumed but produced by NOTHING. Hard softlock:
#                      whatever needs it can never be built.
#   3. BOTTLENECK    — a material with exactly ONE source. Fine by design (that IS
#                      the decision), but a single source that is itself gated deep
#                      is where funnels stall — so they are listed, not failed.
#   4. SINK BREADTH  — how many distinct consumers each material has. Breadth is
#                      what makes a material feel worth stockpiling.
#   5. LIRA SOURCES  — with selling gone, where does currency come from at all?
#
#   Godot --headless --path <root> res://scenes/design_audit.tscn
# ============================================================================

var producers := {}    # sym -> [source strings]
var consumers := {}    # sym -> [sink strings]

func _prod(sym: String, src: String) -> void:
	if sym == "" or sym == "credits": return
	if not producers.has(sym): producers[sym] = []
	(producers[sym] as Array).append(src)

func _cons(sym: String, sink: String) -> void:
	if sym == "" or sym == "credits": return
	if not consumers.has(sym): consumers[sym] = []
	(consumers[sym] as Array).append(sink)


func _ready() -> void:
	GameState.set_process(false)
	GameState.hard_reset()
	var gm = GameState.gathering_manager
	var pm = GameState.processing_manager
	var im = GameState.infrastructure_manager
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager

	# ── PRODUCERS ──
	for aid in gm.actions:
		for e in ((gm.actions[aid] as Dictionary).get("loot_table", []) as Array):
			_prod(String((e as Array)[0]), "gather:%s" % aid)
	for rid in pm.recipes:
		for s in ((pm.recipes[rid] as Dictionary).get("output", {}) as Dictionary):
			_prod(String(s), "craft:%s" % rid)
		# output_table = probabilistic BYPRODUCTS. Skipping it wrongly reported Pd and
		# AncientTech as unobtainable softlocks — both are byproduct-only materials.
		for e in ((pm.recipes[rid] as Dictionary).get("output_table", []) as Array):
			_prod(String((e as Array)[0]), "byproduct:%s" % rid)
	for bid in im.building_db:
		for s in ((im.building_db[bid] as Dictionary).get("yield", {}) as Dictionary):
			_prod(String(s), "bld:%s" % bid)
	for eid in cm.enemy_db:
		for e in ((cm.enemy_db[eid] as Dictionary).get("loot", []) as Array):
			_prod(String((e as Array)[0]), "kill:%s" % eid)
		for e in ((cm.enemy_db[eid] as Dictionary).get("rare_loot", []) as Array):
			_prod(String((e as Array)[0]), "rare:%s" % eid)
		var bc := String((cm.enemy_db[eid] as Dictionary).get("boss_core", ""))
		if bc != "": _prod(bc, "boss:%s" % eid)

	# ── CONSUMERS ──
	for rid in pm.recipes:
		for s in ((pm.recipes[rid] as Dictionary).get("input", {}) as Dictionary):
			_cons(String(s), "craft:%s" % rid)
	for bid in im.building_db:
		for s in ((im.building_db[bid] as Dictionary).get("cost", {}) as Dictionary):
			_cons(String(s), "bldcost:%s" % bid)
		for s in ((im.building_db[bid] as Dictionary).get("input", {}) as Dictionary):
			_cons(String(s), "bldfeed:%s" % bid)
	for tid in rm.tech_tree:
		for s in ((rm.tech_tree[tid] as Dictionary).get("cost_items", {}) as Dictionary):
			_cons(String(s), "research:%s" % tid)
	for mid in sm.modules:
		for s in ((sm.modules[mid] as Dictionary).get("cost", {}) as Dictionary):
			_cons(String(s), "module:%s" % mid)
	for hid in sm.hulls:
		for s in ((sm.hulls[hid] as Dictionary).get("cost", {}) as Dictionary):
			_cons(String(s), "hull:%s" % hid)

	# Special production paths that live in CODE, not in a data table — the scan
	# cannot see them, and without these entries they read as hard softlocks.
	for gid in sm.GEM_FACETS:
		_prod(String(gid), "shipyard:matrix_synthesis/gem_synth")   # craft_module special-case
	for st in sm.HACK_STONE_IDS:
		_prod(String(st), "combat:_roll_hack_stone_drops")          # gated on firmware_hacking

	# ── TERMINALS: consumed by GAMEPLAY, not by a recipe/cost table. Without this
	# the scan calls every module, ammo tier and repair kit a "dead end", which is
	# nonsense — a boss-drop unique weapon is the REWARD, not an orphan material. ──
	# Modules and hulls are EQUIPMENT, not materials: crafted from materials, then
	# equipped. Including them in the material graph made every one of them read as
	# "unobtainable" (nothing in a loot/yield/output table produces a module id) —
	# an artifact of the scan, not a design fault. They are the graph's exit, so the
	# graph is scoped to ELEMENTS and equipment is counted only as a material SINK.
	for cid in ElementDB.CONSUMABLE_DATA:
		_cons(String(cid), "USE (combat consumable)")
	for sym in ElementDB.ELEMENT_DATA:
		var s := String(sym)
		# ammo tiers: SlugTn / CellTn / MissileTn (+ the T1S special) burn in combat
		if s.begins_with("Slug") or s.begins_with("Cell") or s.begins_with("Missile"):
			_cons(s, "FIRE (ammo)")
	for st in sm.HACK_STONE_IDS:
		_cons(String(st), "APPLY (hack card)")
	# Gems go INTO module sockets (insert_gem). Lower tiers also fuse upward, which
	# the cost tables already show; the TOP tier (Resonant) has no fusion above it,
	# so socket insertion is its only sink — terminal by design, not a dead end.
	for gid in sm.GEM_FACETS:
		_cons(String(gid), "INSERT (socket)")
	_cons("BoostCard", "APPLY (building boost)")

	# HOLD-TO-BENEFIT capstones (v112). Some endgame items are never consumed: simply
	# OWNING one grants a permanent passive (PrimordialArmor +30% hull, VoidBattery
	# +40% energy, OmegaAccelerator +50% mining/infra, TemporalModule +30% speed).
	# A consumption-only scan calls these dead, which is backwards — they are the most
	# rewarding sink shape in the game. Their signature in code is a presence check,
	# so detect it directly rather than hardcoding a list that will rot.
	var _src_scan := ["res://scripts/managers/shipyard_manager.gd",
		"res://scripts/managers/bounty_manager.gd",
		"res://scripts/managers/infrastructure_manager.gd",
		"res://scripts/managers/combat_manager.gd",
		"res://scripts/managers/processing_manager.gd",
		"res://scripts/managers/gathering_manager.gd"]
	var _presence := RegEx.new()
	_presence.compile("get_element_amount\\(\"([A-Za-z0-9_]+)\"\\)\\s*>\\s*0")
	for f in _src_scan:
		var txt := FileAccess.get_file_as_string(f)
		if txt == "":
			continue
		for m in _presence.search_all(txt):
			_cons(String(m.get_string(1)), "HOLD (passive capstone)")

	# Scope to real elements. Module/hull ids leak into the graph via cost tables
	# (a module's cost can name another module, e.g. matrix-core fusion) — those are
	# equipment-to-equipment edges, not material supply, so drop them here.
	var is_mat := func(s: String) -> bool:
		if sm.modules.has(s) or sm.hulls.has(s):
			return false
		return ElementDB.ELEMENT_DATA.has(s) or ElementDB.ELEMENT_NAMES.has(s)
	for d in [producers, consumers]:
		for s in (d as Dictionary).keys():
			if not is_mat.call(String(s)):
				(d as Dictionary).erase(s)

	var all := {}
	for s in producers: all[s] = true
	for s in consumers: all[s] = true

	print("[DESIGN] ================================================================")
	print("[DESIGN] DEMAND ECONOMY (no sell value — demand IS the core loop)")
	print("[DESIGN]   materials in play: %d" % all.size())

	# ── 1. DEAD-END: produced, never consumed ──
	var dead := []
	for s in producers:
		if not consumers.has(s):
			dead.append(String(s))
	dead.sort()
	print("[DESIGN] ----------------------------------------------------------------")
	print("[DESIGN] DEAD-END materials (produced, consumed by NOTHING): %d" % dead.size())
	for s in dead:
		print("[DESIGN]   %-22s from %s" % [s, str(producers[s]).substr(0, 90)])

	# ── 2. UNOBTAINABLE: consumed, never produced ──
	var unob := []
	for s in consumers:
		if not producers.has(s):
			unob.append(String(s))
	unob.sort()
	print("[DESIGN] ----------------------------------------------------------------")
	print("[DESIGN] UNOBTAINABLE materials (needed, produced by NOTHING): %d" % unob.size())
	for s in unob:
		print("[DESIGN]   %-22s needed by %s" % [s, str(consumers[s]).substr(0, 90)])

	# ── 3/4. Source + sink breadth ──
	var single := []
	var thin := []
	for s in all:
		var np: int = (producers[s] as Array).size() if producers.has(s) else 0
		var nc: int = (consumers[s] as Array).size() if consumers.has(s) else 0
		if np == 1: single.append(String(s))
		if nc == 1 and np > 0: thin.append("%s (only %s)" % [s, str((consumers[s] as Array)[0])])
	print("[DESIGN] ----------------------------------------------------------------")
	print("[DESIGN] single-source materials: %d  (the intended decision, but also the stall risk)" % single.size())
	print("[DESIGN] single-consumer materials: %d  (thin demand — stockpiling feels pointless)" % thin.size())
	for t in thin:
		print("[DESIGN]   %s" % t)

	# ── 5. Where do Liras come from once selling is gone? ──
	var lira_src := {"combat": 0, "mission": 0, "quest": 0, "bounty": 0}
	for eid in cm.enemy_db:
		for e in ((cm.enemy_db[eid] as Dictionary).get("loot", []) as Array):
			if String((e as Array)[0]) == "credits":
				lira_src["combat"] += 1
	# CORRECTION: an earlier version of this audit concluded "gathering+crafting pay
	# ZERO Liras, combat is the only repeatable tap". That was wrong — it read loot
	# tables only and never looked at the QUEST layer, which is where the designed
	# material→Lira conversion lives. v139 removed hunt quests entirely (they moved to
	# the bounty boards), so the quest board is now 55% stockpile / 45% supply order:
	# 100% skilling. Measure both taps side by side instead of asserting.
	var qm = GameState.quest_manager
	var q_max := {"gather": 0, "supply": 0}
	for tbl_name in ["gather_materials", "supply_goods"]:
		var tbl: Dictionary = qm.get(tbl_name)
		var key := "gather" if tbl_name == "gather_materials" else "supply"
		for tier in tbl:
			for row in (tbl[tier] as Array):
				q_max[key] = maxi(int(q_max[key]), int((row as Array)[3]))
	var kill_max := 0
	for eid in cm.enemy_db:
		for e in ((cm.enemy_db[eid] as Dictionary).get("loot", []) as Array):
			if String((e as Array)[0]) == "credits":
				kill_max = maxi(kill_max, int((e as Array)[2]))
	print("[DESIGN] ----------------------------------------------------------------")
	print("[DESIGN] LIRA TAPS (selling removed — these are the real sources)")
	print("[DESIGN]   SKILLING  quest board: 55% stockpile + 45% supply order")
	print("[DESIGN]             top gather quest : %s L" % FormatUtils.format_number(float(q_max["gather"])))
	print("[DESIGN]             top supply quest : %s L" % FormatUtils.format_number(float(q_max["supply"])))
	print("[DESIGN]   COMBAT    enemies dropping Liras: %d / %d" % [lira_src["combat"], cm.enemy_db.size()])
	print("[DESIGN]             top per-kill drop: %s L" % FormatUtils.format_number(float(kill_max)))
	print("[DESIGN]   Both axes fund themselves. Combat pays per-kill and is uncapped by")
	print("[DESIGN]   board slots; skilling pays in bigger lumps but is board-paced.")
	print("[DESIGN] ================================================================")
	get_tree().quit()
