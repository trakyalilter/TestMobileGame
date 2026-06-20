extends SceneTree
## PHASE 2 — Economy & balance. Surfaces design anomalies and real exploits in
## the value economy: zero-value harvestable resources, credit-printing recipe
## arbitrage, non-monotonic sell/spare-part tables, non-positive buildable costs,
## gather value-per-second outliers, and empty building yields. Errors are
## genuine breakage (a loop that prints credits, a free build); warnings are
## design smells worth a human eye.

var gd
var gs
var errors: Array = []
var warns: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s): errors.append(s)
func W(s): warns.append(s)

# Sale value of a resource symbol (credits is itself worth its face value).
func _val(sym) -> int:
	if sym == "credits": return 1
	return gd.value_of(sym)

# Expected (deterministic) gather/bonus units for a loot row [sym, chance, min, max].
# Gather yields are deterministic at `max` (v0.2.1); bonus rows still roll, so we
# weight by chance and use the max for an upper-bound value estimate.
func _row_units_det(row) -> float:
	return float(row[3])
func _row_units_exp(row) -> float:
	return float(row[1]) * float(row[3])

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	gd = root.get_node("GameData")
	gs = root.get_node("GameState")

	_check_rarity_tables()
	_check_zero_value_harvestables()
	_check_recipe_arbitrage()
	_check_positive_costs()
	_check_gather_vps()
	_check_building_yields()
	_check_delivery_bounties()

	# --- Report ---
	print("\n===== PHASE 2: ECONOMY & BALANCE =====")
	print("resources=%d gather=%d craft=%d buildings=%d hulls=%d modules=%d" % [
		gd.RESOURCES.size(), gd.GATHER.size(), gd.CRAFT.size(), gd.BUILDINGS.size(), gd.HULLS.size(), gd.MODULES.size()])
	print("errors=%d  warnings=%d" % [errors.size(), warns.size()])
	if not warns.is_empty():
		print("\n--- WARNINGS (%d) ---" % warns.size())
		for w in warns: print("  ⚠ " + w)
	if not errors.is_empty():
		print("\n--- ERRORS (%d) ---" % errors.size())
		for e in errors: print("  ✗ " + e)
		print("\nECONOMY: FAIL")
		quit(1)
		return
	print("\nECONOMY: PASS")
	quit()

# (a) Rarity sell + spare-part tables must be strictly increasing with rarity, so
# a higher-rarity drop is never worth less than a lower one.
func _check_rarity_tables() -> void:
	var keys := [0, 1, 2, 3, 4]
	var prev_sell := -1
	for k in keys:
		var v: int = int(gs.RARITY_SELL.get(k, -1))
		if v <= 0: E("RARITY_SELL[%d] = %d (must be positive)" % [k, v])
		elif v <= prev_sell: E("RARITY_SELL not increasing at rarity %d (%d <= %d)" % [k, v, prev_sell])
		prev_sell = v
	var prev_sp := -1
	for k in keys:
		var v: int = int(gs.RARITY_SPARE_PARTS.get(k, -1))
		if v <= 0: E("RARITY_SPARE_PARTS[%d] = %d (must be positive)" % [k, v])
		elif v <= prev_sp: E("RARITY_SPARE_PARTS not increasing at rarity %d (%d <= %d)" % [k, v, prev_sp])
		prev_sp = v

# (b) Any resource a player can actually harvest (gather) or loot from an enemy
# should have a sell value — otherwise the harvest action has no economic payoff.
# Crafted-only intermediates are exempt (their value is the thing they build).
func _check_zero_value_harvestables() -> void:
	var harvestable := {}
	for gid in gd.GATHER:
		for row in gd.GATHER[gid].get("loot", []):
			harvestable[row[0]] = "gather %s" % gid
	for eid in gd.ENEMIES:
		for row in gd.ENEMIES[eid].get("loot", []):
			var s = row[0]
			if gd.RESOURCES.has(s):
				harvestable[s] = "enemy %s" % eid
	for sym in harvestable:
		if _val(sym) <= 0:
			W("harvestable resource '%s' has 0 sell value (via %s)" % [sym, harvestable[sym]])

# (c) Credit-printing arbitrage. Refining ore→product for a higher sell value is the
# INTENDED idle loop and not an exploit, because raw inputs aren't buyable with
# credits (gather is time-gated) — there's no closed loop to spin. The real exploit
# would be a recipe that consumes literal `credits` and outputs a strictly higher
# credits/sell value: that IS a printing loop -> ERROR. We also surface the refining
# value-add distribution as an informational summary (no per-recipe warnings).
func _check_recipe_arbitrage() -> void:
	var refine_count := 0
	var max_mult := 0.0
	var max_cid := ""
	for cid in gd.CRAFT:
		var r: Dictionary = gd.CRAFT[cid]
		var in_val := 0.0
		var in_credits := 0.0
		for sym in r.get("inputs", {}):
			var qty: float = float(r["inputs"][sym])
			if sym == "credits":
				in_credits += qty
				in_val += qty
			else:
				in_val += _val(sym) * qty
		var out_val := 0.0
		for sym in r.get("outputs", {}):
			out_val += _val(sym) * float(r["outputs"][sym])
		var bonus_val := 0.0
		for row in r.get("bonus", []):
			if gd.RESOURCES.has(row[0]):
				bonus_val += _val(row[0]) * _row_units_exp(row)
		var total_out := out_val + bonus_val
		if in_credits > 0.0 and out_val > in_credits and out_val > in_val:
			E("CRAFT %s consumes %d credits but outputs sell for %d (printing loop)" % [cid, int(in_credits), int(out_val)])
		if in_val > 0.0 and total_out > in_val:
			refine_count += 1
			var mult := total_out / in_val
			if mult > max_mult:
				max_mult = mult
				max_cid = cid
	print("refining value-add: %d/%d recipes net-positive (intended); max %.1fx at %s" % [
		refine_count, gd.CRAFT.size(), max_mult, max_cid])

# (d) Every PURCHASABLE thing must cost something positive — no free buys. An item
# with an EMPTY cost dict is a granted/reward item (mission/boss drop), not part of
# the buy economy, so it's exempt. A NON-empty cost that still totals zero is a
# misconfiguration — except the tier-1 starter hull, which is intentionally free.
func _check_positive_costs() -> void:
	# Identify the cheapest/lowest tier hull as the intended free starter.
	var starter_hull := ""
	var min_tier := 1 << 30
	for hid in gd.HULLS:
		var ti: int = int(gd.HULLS[hid].get("tier", 99))
		if ti < min_tier:
			min_tier = ti
			starter_hull = hid
	for hid in gd.HULLS:
		var c: Dictionary = gd.HULLS[hid].get("cost", {})
		if c.is_empty():
			continue  # granted hull, not bought
		if _cost_total(c) <= 0 and hid != starter_hull:
			E("HULL %s has a cost entry that totals zero (free buy)" % hid)
	for mid in gd.MODULES:
		var c: Dictionary = gd.MODULES[mid].get("cost", {})
		if c.is_empty():
			continue  # granted/reward module, not bought
		if _cost_total(c) <= 0:
			E("MODULE %s has a cost entry that totals zero (free buy)" % mid)
	for bid in gd.BUILDINGS:
		var c: Dictionary = gd.BUILDINGS[bid].get("cost", {})
		if c.is_empty():
			continue  # granted building
		if _cost_total(c) <= 0:
			E("BUILDING %s has a cost entry that totals zero (free buy)" % bid)
	# Storage upgrade curve must be positive and strictly increasing for a few steps.
	var prev := -1
	var saved: int = gs.storage_upgrades
	for i in range(6):
		gs.storage_upgrades = i
		var c: int = gs.storage_upgrade_cost()
		if c <= 0: E("storage_upgrade_cost at step %d = %d" % [i, c])
		elif c <= prev: E("storage_upgrade_cost not increasing at step %d (%d <= %d)" % [i, c, prev])
		prev = c
	gs.storage_upgrades = saved

func _cost_total(cost: Dictionary) -> float:
	var t := 0.0
	for sym in cost:
		t += float(cost[sym])
	return t

# Is `sym` consumed by any craft recipe? If so its economic value is realized
# downstream (refining), and its low DIRECT sell value/sec is by design.
func _is_refining_input(sym) -> bool:
	for cid in gd.CRAFT:
		if (gd.CRAFT[cid].get("inputs", {}) as Dictionary).has(sym):
			return true
	return false

# (e) Gather value-per-second: distribution + outliers. value/sec = sum(unit_value
# * expected_units) / duration. We expect this to broadly RISE with level_req.
# Flag a higher-tier gather that pays far LESS direct val/s than a lower tier — BUT
# only for resources sold directly; ores that feed refining are exempt (their value
# is realized in the crafted product, not at the ore counter). Also catch any
# non-positive gather duration as a hard error.
func _check_gather_vps() -> void:
	var rows := []  # [level_req, vps, gid, refines]
	for gid in gd.GATHER:
		var a: Dictionary = gd.GATHER[gid]
		var dur: float = float(a.get("duration", 4.0))
		if dur <= 0.0:
			E("GATHER %s has non-positive duration %f" % [gid, dur]); continue
		var v := 0.0
		var refines := false
		for row in a.get("loot", []):
			v += _val(row[0]) * _row_units_exp(row)
			if _is_refining_input(row[0]): refines = true
		var vps := v / dur
		rows.append([int(a.get("level_req", 1)), vps, gid, refines])
	rows.sort_custom(func(x, y): return x[0] < y[0])
	# Walk in level order; warn when a higher-level DIRECT-SALE gather pays less
	# value/sec than the best seen so far by a wide margin (a dominated tier).
	var best := 0.0
	var best_gid := ""
	for r in rows:
		var lvl: int = r[0]
		var vps: float = r[1]
		var gid: String = r[2]
		var refines: bool = r[3]
		if not refines and vps > 0.0 and best > 0.0 and vps < best * 0.5 and lvl > 1:
			W("GATHER %s (Lv %d) pays %.0f direct val/s, far below peak %.0f (%s) — dominated" % [gid, lvl, vps, best, best_gid])
		if vps > best:
			best = vps
			best_gid = gid

# (f) Every yield-producing building should actually produce something; an infra
# building with neither yield nor a meaningful effect is dead weight.
func _check_building_yields() -> void:
	for bid in gd.BUILDINGS:
		var b: Dictionary = gd.BUILDINGS[bid]
		var has_yield := not (b.get("yield", {}) as Dictionary).is_empty()
		var has_effect := b.has("effect") or b.has("slots") or b.has("storage") or b.has("power") or b.has("desc")
		if not has_yield and not has_effect:
			W("BUILDING %s produces no yield and has no listed effect" % bid)

# (g) Delivery bounties: the credit reward should exceed the raw sell value of the
# materials demanded, otherwise it's better to just sell them. Flag inversions.
func _check_delivery_bounties() -> void:
	for tier in gs.DELIVERY_MATERIALS:
		for tmpl in gs.DELIVERY_MATERIALS[tier]:
			# tmpl = [sym, qty_min, qty_max, reward]
			var sym: String = tmpl[0]
			var qty_max: float = float(tmpl[2])
			var reward: float = float(tmpl[3])
			var raw := _val(sym) * qty_max
			if reward <= 0.0:
				E("DELIVERY tier %s '%s' reward non-positive (%d)" % [str(tier), sym, int(reward)])
			elif raw > 0.0 and reward < raw:
				W("DELIVERY tier %s '%s': reward %d < raw sell value %d (sell-instead)" % [str(tier), sym, int(reward), int(raw)])
