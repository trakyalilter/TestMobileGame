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

	print("[YIELDP] ============ %s ============" % ("ALL PASS" if fails == 0 else "%d FAIL(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
