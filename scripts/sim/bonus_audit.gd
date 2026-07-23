extends Node
# ============================================================================
# BONUS AUDIT (v141c) — every bonus must pay the SAME amount three ways:
#
#     what the CARD shows  ==  what ONLINE grants  ==  what OFFLINE grants
#
# and stacking two bonuses must not break either one.
#
# Why this exists: the yield pipeline has four independent surfaces (card,
# complete_*, calculate_offline, get_current_rate) and every one of them has, at
# some point, re-derived the same number by hand. Each hand-rolled copy silently
# stopped matching the moment a new bonus landed:
#   v112  offline Steel x2 vs online x5
#   v140  card missed the Warp-tree multiplier
#   v141b card cache signed the multiplier, missed the per-level flat
#   v141c offline gathering kept the RAW flat after the bonus went proportional
# Grep can't catch these. Only paying the same window both ways can.
#
#   Godot --headless --path <root> res://scenes/bonus_audit.tscn
# ============================================================================

const CYCLES := 40          # completions to compare across
const TOL := 0.02           # 2% — closed-form offline vs summed online rounding

var fails := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		fails += 1
	print("[BONUS] %-50s %s %s" % [name, "OK" if cond else "*** FAIL", detail])


func _close(a: float, b: float) -> bool:
	if absf(a - b) < 0.51:      # sub-unit rounding is fine
		return true
	return absf(a - b) / maxf(absf(a), 1.0) <= TOL


func _set_level(mgr, lv: int) -> void:
	mgr.xp = float(mgr.get_xp_for_level(lv))
	mgr.level = 1
	mgr.check_level_up()


func _amount(sym: String) -> float:
	return float(GameState.resources.get_element_amount(sym))


# ── gathering: card vs online vs offline, under a given bonus stack ──────────
func _gather_case(label: String, lv: int, tree_levels: int) -> void:
	var gm = GameState.gathering_manager
	var wm = GameState.warp_manager
	GameState.hard_reset()
	_set_level(gm, lv)
	# Optional Warp-tree stack — ENG_1 is a FLAT on the primary drop, so it rides
	# alongside the skill bonus and is the most likely to double-count.
	if tree_levels > 0:
		wm.total_warps = 5
		wm.warp_shards = 999.0
		wm.purchased_nodes["ENG_1"] = true
		for i in range(tree_levels):
			if wm.can_purchase_node("ENG_S1"):
				wm.purchase_node("ENG_S1")
		_set_level(gm, lv)   # purchases don't touch level, but re-pin it anyway

	var aid := "gather_dirt"          # single loot entry, chance 1.0 -> deterministic
	var entry: Array = gm.actions[aid]["loot_table"][0]
	var sym := String(entry[0])
	var shown := float(gm.get_display_yield(entry, 0))

	# ONLINE: N real completions. The level is RE-PINNED every cycle because each
	# gather grants XP — at low levels 40 gathers level you up mid-loop and the
	# average would mix two different yields, which measures the XP curve rather
	# than the bonus. Freezing the level is what isolates the thing under test.
	gm.start_action(aid)
	var before := _amount(sym)
	for i in range(CYCLES):
		_set_level(gm, lv)
		gm.complete_action()
	var online := (_amount(sym) - before) / float(CYCLES)

	# OFFLINE: the same number of cycles as one closed-form window. Level is
	# re-pinned first because the online loop above granted XP.
	_set_level(gm, lv)
	gm.start_action(aid)
	var dur: float = float(gm.actions[aid].get("duration", 4.0)) / gm.get_action_speed_multiplier(aid)
	before = _amount(sym)
	gm.calculate_offline(dur * float(CYCLES) + 0.01)
	var offline := (_amount(sym) - before) / float(CYCLES)

	# Offline grants the whole window's XP BEFORE computing yield, so a level-up
	# inside the window applies to ALL of it (documented closed-form behaviour).
	# Comparing that against a level-pinned online run measures the XP curve, not
	# the bonus — so offline is checked against the card AT THE POST-WINDOW LEVEL.
	var shown_after := float(gm.get_display_yield(entry, 0))
	_ok("%s: card == online" % label, _close(shown, online), "card %.2f vs online %.2f" % [shown, online])
	_ok("%s: offline == card@post-window" % label, _close(offline, shown_after),
		"offline %.2f vs card %.2f (post-window L%d)" % [offline, shown_after, gm.get_level()])


# ── processing: card vs online vs offline ───────────────────────────────────
func _craft_case(label: String, lv: int, rid: String) -> void:
	var pm = GameState.processing_manager
	GameState.hard_reset()
	_set_level(pm, lv)
	var rec: Dictionary = pm.recipes[rid]
	# start_action refuses a recipe below its level gate, leaving current_recipe
	# empty — complete_process then reads current_recipe["input"] and errors. Skip
	# rather than assert on a recipe the player couldn't run at this level anyway.
	if lv < int(rec.get("level_req", 1)):
		print("[BONUS] %-50s SKIP (level_req %d)" % [label, int(rec.get("level_req", 1))])
		return
	# hard_reset() clears research, and start_action silently refuses a recipe whose
	# research_req isn't met — leaving current_recipe empty so complete_process
	# awards nothing (online reads 0.00 against a non-zero card). Grant the gate.
	var req := String(rec.get("research_req", ""))
	if req != "" and GameState.research_manager and not GameState.research_manager.is_tech_unlocked(req):
		GameState.research_manager.unlocked_techs.append(req)
	var prim := String(pm.get_primary_output(rec))
	# Explicit type: pm is untyped, so `:=` can't infer from a Variant return.
	var shown: float = pm.get_display_output(rid, prim)

	# Stock inputs generously so neither path stalls on materials.
	for s in rec.get("input", {}):
		GameState.resources.add_element(String(s), float(rec["input"][s]) * float(CYCLES) * 4.0)
	if rec.get("credits_cost", 0) > 0:
		GameState.resources.add_currency("credits", int(rec["credits_cost"]) * CYCLES * 4)

	pm.start_action(rid)
	var before := _amount(prim)
	for i in range(CYCLES):
		_set_level(pm, lv)   # freeze the level — see _gather_case
		pm.complete_process()
	var online := (_amount(prim) - before) / float(CYCLES)

	_set_level(pm, lv)
	pm.start_action(rid)
	var dur: float = float(rec.get("duration", 5.0)) / pm.get_recipe_speed_multiplier(rid)
	before = _amount(prim)
	pm.calculate_offline(dur * float(CYCLES) + 0.01)
	var offline := (_amount(prim) - before) / float(CYCLES)

	# From Lv50 the milestone grants a 5% chance of double output. Online rolls it
	# per craft (so a 40-cycle average runs ~5% hot with variance); offline applies
	# the expected value. Fold the same EV into the expected card figure so the
	# comparison stays honest instead of being papered over by tolerance.
	var ev := 1.0
	if pm.is_milestone_unlocked(50):
		ev += pm.MILESTONE_50_DOUBLE_CHANCE
	_ok("%s: card == online" % label, _close(shown * ev, online),
		"card %.2f (ev %.2f) vs online %.2f" % [shown, shown * ev, online])
	_ok("%s: online == offline" % label, _close(online, offline), "online %.2f vs offline %.2f" % [online, offline])


func _ready() -> void:
	print("[BONUS] ============ bonus parity audit ============")

	# 1. Skill level alone, across the whole curve. Lv40 is the case the owner
	# caught live (singleton recipes showed no bonus); Lv100 is the cap.
	for lv in [1, 10, 40, 50, 100]:
		_gather_case("gather L%d" % lv, lv, 0)

	# 2. Skill bonus STACKED with the Warp-tree flat + multiplier. Two flats on the
	# same primary drop is the shape most likely to double-count or cancel.
	for lv in [1, 50, 100]:
		_gather_case("gather L%d + warp tree" % lv, lv, 2)

	# 3. Processing: a bulk recipe (proportional term dominates) and a SINGLETON
	# recipe (the +1 floor dominates, and its cap is the tightest).
	for lv in [1, 10, 40, 100]:
		_craft_case("craft bulk L%d" % lv, lv, "electrolysis")
	for lv in [1, 10, 100]:
		_craft_case("craft singleton L%d" % lv, lv, "smelt_copper")

	# 4. The rate readout is a fourth surface — it must project the same number.
	var gm = GameState.gathering_manager
	GameState.hard_reset()
	_set_level(gm, 60)
	gm.start_action("gather_dirt")
	var e: Array = gm.actions["gather_dirt"]["loot_table"][0]
	var per_min_expected: float = float(gm.get_display_yield(e, 0)) * float(e[1]) \
		/ (float(gm.actions["gather_dirt"].get("duration", 4.0)) / gm.get_action_speed_multiplier("gather_dirt")) * 60.0
	var rates: Dictionary = gm.get_current_rate()
	_ok("gather /min rate matches card", _close(float(rates.get(String(e[0]), 0.0)), per_min_expected),
		"rate %.1f vs expected %.1f" % [float(rates.get(String(e[0]), 0.0)), per_min_expected])

	var pm = GameState.processing_manager
	GameState.hard_reset()
	_set_level(pm, 60)
	var rec: Dictionary = pm.recipes["electrolysis"]
	var rreq := String(rec.get("research_req", ""))
	if rreq != "" and GameState.research_manager and not GameState.research_manager.is_tech_unlocked(rreq):
		GameState.research_manager.unlocked_techs.append(rreq)
	for s in rec.get("input", {}):
		GameState.resources.add_element(String(s), 9999.0)
	pm.start_action("electrolysis")
	var prim := String(pm.get_primary_output(rec))
	var pexp: float = pm.get_display_output("electrolysis", prim) \
		/ (float(rec["duration"]) / pm.get_recipe_speed_multiplier("electrolysis")) * 60.0
	var prates: Dictionary = pm.get_current_rate()
	_ok("craft /min rate matches card", _close(float(prates.get(prim, 0.0)), pexp),
		"rate %.1f vs expected %.1f" % [float(prates.get(prim, 0.0)), pexp])

	# 5. The flat is UNCAPPED by design: at Lv100 every output must gain exactly 10,
	# including 1-unit ones. A recipe that quietly gains less is the "I levelled 100
	# and nothing changed" bug the cap removal was meant to kill.
	GameState.hard_reset()
	_set_level(pm, 100)
	var short := []
	for r2 in pm.recipes:
		for it in (pm.recipes[r2].get("output", {}) as Dictionary):
			var b := float(pm.recipes[r2]["output"][it])
			if b > 0.0 and pm.get_skill_yield_bonus(b) != 10:
				short.append("%s:%s" % [String(r2), String(it)])
	_ok("every recipe output gains exactly +10 at Lv100", short.is_empty(), str(short).substr(0, 120))

	print("[BONUS] ============ %s ============" % ("ALL PASS" if fails == 0 else "%d FAIL(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
