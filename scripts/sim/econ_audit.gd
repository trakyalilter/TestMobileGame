extends Node
# Economy audit: (1) craft-and-sell printers — recipes whose OUTPUT sell value
# beats input value + credit cost (profit/sec vs best gather); (2) dominated
# gather actions (strictly worse credits/sec at same-or-higher level req);
# (3) zero-value recipe outputs (unsellable dead ends).
func _ready() -> void:
	GameState.hard_reset()
	var pm = GameState.processing_manager
	var gm = GameState.gathering_manager
	# gather cps table
	var rows := []
	for aid in gm.actions:
		var a = gm.actions[aid]
		var dur: float = float(a.get("duration", 4.0))
		var cps := 0.0
		for e in a.get("loot_table", []):
			cps += float(e[1]) * float(e[3]) * float(ElementDB.get_element_value(String(e[0]))) / dur
		rows.append([aid, int(a.get("level_req", 1)), cps])
	rows.sort_custom(func(x, y): return x[1] < y[1])
	var best_so_far := 0.0
	print("== GATHER cps by level (flag = dominated: cps <= a lower-level action) ==")
	for r in rows:
		var flag := "  "
		if r[2] <= best_so_far and r[2] > 0.0: flag = "DOMINATED"
		best_so_far = max(best_so_far, r[2])
		print("  lvl%-3d %-26s %8.2f cr/s %s" % [r[1], r[0], r[2], flag])
	# recipe margins
	print("== RECIPE margins (profit = out_value - in_value - credits_cost; /s = per craft-second) ==")
	var margins := []
	for rid in pm.recipes:
		var rec = pm.recipes[rid]
		var iv := 0.0
		for s in rec.get("input", {}): iv += float(rec["input"][s]) * float(ElementDB.get_element_value(String(s)))
		var ov := 0.0
		var zero_out := []
		for s in rec.get("output", {}):
			var v: float = float(ElementDB.get_element_value(String(s)))
			ov += float(rec["output"][s]) * v
			if v <= 0.0: zero_out.append(s)
		var profit: float = ov - iv - float(rec.get("credits_cost", 0))
		var dur: float = float(rec.get("duration", 5.0))
		margins.append([rid, profit, profit / dur, iv, ov, zero_out, int(rec.get("level_req", 1))])
	margins.sort_custom(func(x, y): return x[2] > y[2])
	print("-- top 12 by profit/sec --")
	for i in range(min(12, margins.size())):
		var m = margins[i]
		print("  %-28s lvl%-3d in=%-9.0f out=%-9.0f profit=%-9.0f  %7.1f cr/s" % [m[0], m[6], m[3], m[4], m[1], m[2]])
	print("-- recipes with ZERO-VALUE outputs (unsellable results) --")
	for m in margins:
		if not m[5].is_empty():
			print("  %-28s zero-value: %s" % [m[0], m[5]])
	print("[DONE]")
	get_tree().quit()
