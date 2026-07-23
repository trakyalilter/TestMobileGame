extends Node
# ============================================================================
# YIELD DISPLAY PARITY (v140) — the number on a card must equal the number the
# player actually receives.
#
# Bug this guards: gathering_action_widget rendered base_qty x research-efficiency
# only, while the award path also applied skill level, milestone 10, trophy buffs
# and the Warp-tree ENG_S1 "Resource Surge" spine. Buying Resource Surge moved the
# real payout and left the card frozen. infrastructure's get_building_adjusted_rate
# had the same defect (missing building_yield_mult + get_tree_infra_bonus).
#
# Strategy: read a yield, buy Resource Surge levels, read again. Display MUST move
# by the same ratio as the award math.
#   Godot --headless --path <root> res://scenes/yield_display_parity.tscn
# ============================================================================

var fails := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond: fails += 1
	print("[YIELDP] %-46s %s %s" % [name, "OK" if cond else "*** FAIL", detail])


func _ready() -> void:
	GameState.set_process(false)
	GameState.hard_reset()

	var gm = GameState.gathering_manager
	var im = GameState.infrastructure_manager
	var wm = GameState.warp_manager

	print("[YIELDP] ============ yield display parity ============")

	# Warp STATE first, purchases later. total_warps feeds get_production_multiplier,
	# which the infra card also folds in — changing it in the same step as the node
	# purchase would smear two effects into one ratio and prove nothing.
	wm.total_warps = 3
	wm.warp_shards = 500.0
	wm.purchased_nodes["ENG_1"] = true          # ENG_S1 prereq

	# ── Gathering: card number must BE the award number ──
	var act_id: String = gm.actions.keys()[0]
	var entry: Array = gm.actions[act_id]["loot_table"][0]
	var shown_0: int = gm.get_display_yield(entry, 0)
	var mult_0: float = gm.get_yield_multiplier()
	_ok("gather display > 0", shown_0 > 0, "%s -> %d" % [act_id, shown_0])

	# Infra baseline, captured BEFORE the purchase so the delta is measurable.
	var bid := ""
	var res := ""
	for b in im.building_db:
		var d: Dictionary = im.building_db[b]
		if d.has("yield") and not (d["yield"] as Dictionary).is_empty():
			bid = b
			res = (d["yield"] as Dictionary).keys()[0]
			break
	_ok("found a producing building", bid != "", "%s -> %s" % [bid, res])
	var infra_0: float = float(im.get_building_adjusted_rate(bid)["yield"].get(res, 0.0)) if bid != "" else 0.0

	# Buy Resource Surge (ENG_S1, repeatable) — the ONLY thing changing from here.
	var bought := 0
	for i in range(2):
		if wm.can_purchase_node("ENG_S1"):
			wm.purchase_node("ENG_S1")
			bought += 1
	_ok("bought Resource Surge x2", bought == 2, "level=%d" % int(wm.get_node_level("ENG_S1")))
	_ok("tree gathering bonus moved", wm.get_tree_gathering_bonus() > 1.0,
		"x%.3f" % wm.get_tree_gathering_bonus())

	var shown_1: int = gm.get_display_yield(entry, 0)
	var mult_1: float = gm.get_yield_multiplier()
	print("[YIELDP]   gather shown %d -> %d   (mult %.4f -> %.4f)" % [shown_0, shown_1, mult_0, mult_1])
	_ok("award multiplier rose", mult_1 > mult_0)
	# THE REGRESSION: the displayed number must track the multiplier, not sit still.
	_ok("gather CARD number rose", shown_1 > shown_0, "%d -> %d" % [shown_0, shown_1])

	# ── Infrastructure: the card rate must move by the SAME ratio as production ──
	# Comparing card-vs-effective absolutely is useless (the card also folds warp
	# production mult, skill yield and yield_bonus affixes, so it legitimately sits
	# ~10x higher). The meaningful invariant is that both respond to the surge.
	if bid != "":
		var infra_1: float = float(im.get_building_adjusted_rate(bid)["yield"].get(res, 0.0))
		var want: float = wm.get_tree_infra_bonus()     # x1.12 at ENG_S1 Lv2
		var got: float = infra_1 / max(infra_0, 0.0001)
		print("[YIELDP]   infra card %.4f -> %.4f  (ratio %.4f, want %.4f)" % [infra_0, infra_1, got, want])
		_ok("infra CARD rate rose", infra_1 > infra_0, "%.3f -> %.3f" % [infra_0, infra_1])
		_ok("infra card ratio == surge bonus", absf(got - want) < 0.001,
			"got %.4f want %.4f" % [got, want])

	# ── v141c: skill level pays a FLAT +1 per 10 levels and NOTHING else ──
	# The milestone multiplier ladder (x1.10/1.25/1.50/1.75/2.00) was removed by
	# owner call. These asserts pin the replacement: level must contribute zero
	# multiplier, and the flat must step on every 10th level (not just at the five
	# old milestone points).
	print("[YIELDP] --- skill yield: flat only, no milestone mult ---")
	# Reset warp/tree so only the skill level varies.
	GameState.hard_reset()
	var e2: Array = gm.actions[gm.actions.keys()[0]]["loot_table"][0]
	gm.xp = 0.0; gm.level = 1; gm.check_level_up()
	_ok("Lv1: flat = 0", gm.get_skill_yield_flat() == 0)
	var mult_base: float = gm.get_yield_multiplier()
	# Flat steps every 10 levels — including 20/30/40, which the old ladder skipped.
	for lv in [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]:
		gm.xp = float(gm.get_xp_for_level(lv)); gm.level = 1; gm.check_level_up()
		_ok("Lv%d flat = +%d" % [lv, int(lv / 10)],
			gm.get_skill_yield_flat() == int(lv / 10), "+%d" % gm.get_skill_yield_flat())
	# THE REGRESSION GUARD: level must no longer move the multiplier at all. If a
	# milestone table ever creeps back in, this fires at Lv100.
	_ok("Lv100 multiplier unchanged by level",
		absf(gm.get_yield_multiplier() - mult_base) < 0.0001,
		"%.4f vs %.4f" % [gm.get_yield_multiplier(), mult_base])
	# Card == award: get_display_yield is base + flat on the primary drop.
	gm.xp = float(gm.get_xp_for_level(50)); gm.level = 1; gm.check_level_up()
	var base: int = int(e2[3])
	var shown: int = gm.get_display_yield(e2, 0)
	_ok("Lv50 card = base + flat", shown == base + 5, "base %d -> shown %d" % [base, shown])
	# Secondary drops get NO skill scaling at all now (flat is primary-only).
	if gm.actions[gm.actions.keys()[0]]["loot_table"].size() > 1:
		var sec: Array = gm.actions[gm.actions.keys()[0]]["loot_table"][1]
		var sec_shown: int = gm.get_display_yield(sec, 1)
		_ok("secondary drop = base (no skill scaling)", sec_shown == int(sec[3]), "%d" % sec_shown)

	# ── v141b: the WIDGET CACHE must not be signed by the multiplier alone ──
	# Skill level moves the award without touching the multiplier (v141c: it moves
	# NOTHING else). Lv19 -> Lv21 is the proof case: identical multiplier, different
	# award. gathering_action_widget's _loot_sig used to sign the multiplier, so the
	# card froze at the Lv19 number while the loot popup paid the Lv21 one. The sig
	# now signs the resulting AMOUNTS — this asserts the two inputs really do
	# diverge, so that signature choice stays the load-bearing one.
	print("[YIELDP] --- widget cache signature (mult constant, flat steps) ---")
	gm.xp = float(gm.get_xp_for_level(19)); gm.level = 1; gm.check_level_up()
	var mult_19: float = gm.get_yield_multiplier()
	var shown_19: int = gm.get_display_yield(e2, 0)
	gm.xp = float(gm.get_xp_for_level(21)); gm.level = 1; gm.check_level_up()
	var mult_21: float = gm.get_yield_multiplier()
	var shown_21: int = gm.get_display_yield(e2, 0)
	print("[YIELDP]   Lv19 shown %d (mult %.4f)  ->  Lv21 shown %d (mult %.4f)" % [shown_19, mult_19, shown_21, mult_21])
	_ok("Lv19/Lv21 multiplier IDENTICAL", absf(mult_21 - mult_19) < 0.0001, "%.4f" % mult_21)
	_ok("Lv19/Lv21 award DIFFERS (flat)", shown_21 == shown_19 + 1, "%d -> %d" % [shown_19, shown_21])

	# ── v141c: ENGINEERING gets the same flat +1 per 10 levels on EVERY output ──
	# Processing is a converter, so the flat moves the input:output ratio. These
	# asserts pin the contract: every fixed output takes the flat (a 2-product
	# recipe pays it twice per cycle), and the card path (get_display_output) is
	# the same call the award path makes.
	print("[YIELDP] --- engineering output flat ---")
	var pm = GameState.processing_manager
	GameState.hard_reset()
	# A multi-output recipe proves the primary-only rule; electrolysis is H + O.
	var rid := "electrolysis"
	_ok("multi-output recipe present", pm.recipes.has(rid), rid)
	if pm.recipes.has(rid):
		var out: Dictionary = pm.recipes[rid]["output"]
		var primary: String = pm.get_primary_output(pm.recipes[rid])
		var secondary := ""
		for k in out:
			if String(k) != primary:
				secondary = String(k)
				break
		pm.xp = 0.0; pm.level = 1; pm.check_level_up()
		_ok("Lv1: craft flat = 0", pm.get_skill_yield_flat() == 0)
		var base_p := float(out[primary])
		var base_s := float(out[secondary]) if secondary != "" else 0.0
		_ok("Lv1 primary = base", absf(pm.get_display_output(rid, primary) - base_p) < 0.001,
			"%s %.1f" % [primary, pm.get_display_output(rid, primary)])
		# v141c: FLAT +1 per 10 levels, UNCAPPED — the badge must equal level/10 on
		# every recipe regardless of its base size.
		for lv in [10, 30, 50, 100]:
			pm.xp = float(pm.get_xp_for_level(lv)); pm.level = 1; pm.check_level_up()
			var want: float = base_p + float(int(lv / 10))
			_ok("Lv%d primary %s = %.0f" % [lv, primary, want],
				absf(pm.get_display_output(rid, primary) - want) < 0.001,
				"%.1f" % pm.get_display_output(rid, primary))
		# Secondary output scales too — a 2-product recipe pays on both.
		if secondary != "":
			_ok("Lv100 secondary %s doubles" % secondary,
				absf(pm.get_display_output(rid, secondary) - (base_s * 2.0)) < 0.001,
				"%.1f vs base %.1f" % [pm.get_display_output(rid, secondary), base_s])
		# THE CAP: a singleton-output recipe must never exceed double. Uncapped this
		# was 11 at Lv100 and compounded to 2065x down the AIProcessor tree.
		# The smallest output in the game must still show the FULL flat — this is the
		# "why did I waste 50 levels" case that drove removing the cap.
		if pm.recipes.has("smelt_copper"):
			pm.xp = float(pm.get_xp_for_level(10)); pm.level = 1; pm.check_level_up()
			var cu10: float = pm.get_display_output("smelt_copper", "Cu")
			_ok("Lv10 Copper Smelting = 2 (base 1 + flat 1)", absf(cu10 - 2.0) < 0.001, "%.1f" % cu10)
			pm.xp = float(pm.get_xp_for_level(100)); pm.level = 1; pm.check_level_up()
			var cu: float = pm.get_display_output("smelt_copper", "Cu")
			_ok("Lv100 Copper Smelting = 11 (base 1 + flat 10)", absf(cu - 11.0) < 0.001, "%.1f" % cu)
		# EVERY fixed output must gain exactly the step count — no recipe shape may
		# silently get less than the badge promises.
		pm.xp = float(pm.get_xp_for_level(100)); pm.level = 1; pm.check_level_up()
		var short := []
		for r2 in pm.recipes:
			for it in (pm.recipes[r2].get("output", {}) as Dictionary):
				var b := float(pm.recipes[r2]["output"][it])
				if b <= 0.0:
					continue
				if absf(pm.get_display_output(String(r2), String(it)) - (b + 10.0)) > 0.001:
					short.append("%s:%s" % [String(r2), String(it)])
		_ok("every output gains the full +10 at Lv100", short.is_empty(), str(short).substr(0, 120))

	# v141c: Zinc Reduction's Silver was promoted from output_table to a stated
	# output. It must appear EXACTLY once — leaving the old output_table entry in
	# place would pay it twice per craft (and Ag gates the m029b AdvCircuit chain).
	if pm.recipes.has("smelt_zinc"):
		var zr: Dictionary = pm.recipes["smelt_zinc"]
		_ok("Zinc Reduction lists Ag as an output", (zr.get("output", {}) as Dictionary).has("Ag"))
		var dupe := false
		for ot_entry in zr.get("output_table", []):
			if String(ot_entry[0]) == "Ag":
				dupe = true
		_ok("Ag NOT also in output_table (no double-pay)", not dupe)
		pm.xp = 0.0; pm.level = 1; pm.check_level_up()
		_ok("Lv1 Ag = 1", absf(pm.get_display_output("smelt_zinc", "Ag") - 1.0) < 0.001,
			"%.1f" % pm.get_display_output("smelt_zinc", "Ag"))

	print("[YIELDP] ============ %s ============" % ("ALL PASS" if fails == 0 else "%d FAIL(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
