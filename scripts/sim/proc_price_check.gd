extends Node
# proc_price_check — the probe PROCUREMENT_UNIT_PRICE's own comment promises.
#
# Answers three questions the price table was never checked against:
#
#  A. DEAD ORDERS. claim_procurement() blocks outright when pool < reward_base
#     (quest_manager.gd:615) and the card NEVER resizes. So any order whose value
#     exceeds its family's pool CAP is permanently unclaimable — a dead card, not
#     a slow one. Order value = PROC_ORDER_MINUTES of the player's rate x price,
#     while the cap is frontier-keyed: a strong line at a low frontier is the
#     danger zone. Measured here per good, per frontier.
#
#  B. DOMINATED BOARD. The same material sits on the Stockpile/Supply board with
#     its own authored payout. Implied L/unit there vs the procurement price says
#     whether procurement is ever the rational place to send a good.
#
#  C. Price headroom: how far each price can rise before it creates dead orders.
#
# Reads the LIVE constants from quest_manager, not DEMAND_ENGINE.md — the doc's
# era table and the code's PROC_ERA_INCOME_PER_H already disagree (doc Z5 210K,
# code 352.5K).

const STACK := 400   # far past both DR knees (industry 10/10, primitive 30/30)

func _ready() -> void:
	if not GameState.sim_mode:
		push_error("proc_price_check: NOT in sim_mode — refusing to touch live state.")
		get_tree().quit(1)
		return
	call_deferred("_run")

func _run() -> void:
	var im = GameState.infrastructure_manager
	var qm = GameState.quest_manager
	var edb = ElementDB

	im.energy_efficiency = 1.0
	if GameState.processing_manager:
		GameState.processing_manager.level = 100

	# ---- ceiling rate per good (build only its producers, nothing consumes it)
	var producers: Dictionary = {}
	for bid in im.building_db:
		var d = im.building_db[bid]
		if not (d is Dictionary) or not d.has("yield"): continue
		for sym in d["yield"]:
			var s: String = str(sym)
			if not producers.has(s): producers[s] = []
			producers[s].append(bid)

	var ceil_rate: Dictionary = {}   # sym -> units/min at DR ceiling
	for fam in edb.PROCUREMENT_FAMILIES:
		for sym in edb.PROCUREMENT_FAMILIES[fam]:
			var s: String = str(sym)
			var bids: Array = producers.get(s, [])
			if bids.is_empty():
				ceil_rate[s] = 0.0
				continue
			im.buildings.clear()
			im.building_throttles.clear()
			for b in bids:
				im.buildings[b] = STACK
				im.building_throttles[b] = 1.0
			ceil_rate[s] = float(im.get_total_resource_rates().get(s, 0.0))

	var families: Array = []
	for fam in edb.PROCUREMENT_FAMILIES:
		families.append(str(fam))

	# get_pool_cap divides by the number of families ONLINE, not the 7 that
	# exist — so the cap is LARGEST early, when few lines are running. Using 7
	# everywhere would over-report dead cards at exactly the frontiers that
	# matter. Counts from DEMAND_ENGINE.md C2's "era online" column.
	var online_at := {2: 2, 3: 4, 4: 5, 5: 5, 6: 5, 7: 6, 8: 6, 9: 7, 10: 7}
	var n_fam: int = families.size()

	# ---- A. dead orders -----------------------------------------------------
	print("=== A. DEAD ORDERS — order value vs family pool CAP ===")
	print("cap = era_L/h x %.2f / families_online x %.0fh ; order = %.0f min of rate x price"
		% [qm.ENGINEER_SHARE, qm.PROC_POOL_HOURS, qm.PROC_ORDER_MINUTES])
	print("A DEAD row can never be claimed at any pool level.\n")

	# Drives the REAL _generate_procurement_order at a DR-ceiling line — the worst
	# case, and the one that produced dead cards. Re-implementing the sizing here
	# would only test my copy of it.
	# A family's frontier is not free to choose: its factories are gated behind
	# zone-access research (capital_fabrication needs zone_8_access,
	# dreadnought_yards needs zone_9_access). Testing a Z1 player who somehow owns
	# a frame yard measures an unreachable state, so unlock zones up to each
	# family's own gate and let _proc_frontier() derive the rest.
	var fam_gate_zone := {"refining": 2, "ordnance": 2, "chemical": 4, "structural": 4,
		"electronics": 4, "fabrication": 7, "capital": 9}
	var rm = GameState.research_manager

	var dead_rows: Array = []
	var checked: int = 0
	print("  %-20s %10s %12s %12s  %s" % ["good", "L/unit", "order L", "pool cap", "verdict"])
	for fam in families:
		var gate: int = int(fam_gate_zone.get(fam, 4))
		for z in range(2, gate + 1):
			var t := "zone_%d_access" % z
			if rm and not rm.unlocked_techs.has(t):
				rm.unlocked_techs.append(t)
		for sym in edb.PROCUREMENT_FAMILIES[fam]:
			var s: String = str(sym)
			var rate: float = float(ceil_rate.get(s, 0.0))
			if rate <= 0.0: continue
			var bids: Array = producers.get(s, [])
			im.buildings.clear()
			im.building_throttles.clear()
			for b in bids:
				im.buildings[b] = STACK
				im.building_throttles[b] = 1.0
			var cap: float = qm.get_pool_cap(fam)
			if cap <= 0.0: continue   # family not online at this frontier
			var order: Dictionary = qm._generate_procurement_order(fam, s, rate)
			var val: float = float(order["reward_credits"])
			checked += 1
			var dead: bool = val > cap
			if dead:
				dead_rows.append({"sym": s, "fam": fam, "order": val, "cap": cap})
				print("  %-20s %10s %12s %12s  DEAD — unclaimable at any pool level"
					% [s, _fmt(edb.get_procurement_unit_price(s)), _fmt(val), _fmt(cap)])
	print("  (%d goods checked at the live frontier; only DEAD rows listed)" % checked)
	if dead_rows.is_empty():
		print("  none — every ceiling-rate order fits its family pool cap.")
	print("\n  -> %d of %d goods generate a permanently unclaimable card." % [dead_rows.size(), checked])

	# ---- B. dominated board -------------------------------------------------
	print("\n=== B. SAME MATERIAL, OTHER BOARD — implied L/unit ===")
	print("Stockpile/Supply rows are [sym, min_qty, max_qty, credits]; implied")
	print("L/unit uses the MAX qty (the player's worst case on that board).\n")
	var other: Dictionary = {}   # sym -> [best_l_per_unit, tier, board]
	for tbl_name in ["gather_materials", "supply_goods"]:
		var tbl: Dictionary = qm.gather_materials if tbl_name == "gather_materials" else qm.supply_goods
		for tier in tbl:
			for row in tbl[tier]:
				var s: String = str(row[0])
				var per_unit: float = float(row[3]) / float(row[2])
				if not other.has(s) or per_unit < float(other[s]["lpu"]):
					other[s] = {"lpu": per_unit, "tier": int(tier), "board": tbl_name}

	print("  %-20s %12s %12s %10s  %s" % ["good", "procure L/u", "other L/u", "ratio", "board (tier)"])
	var dominated: Array = []
	for fam in families:
		for sym in edb.PROCUREMENT_FAMILIES[fam]:
			var s: String = str(sym)
			if not other.has(s): continue
			var p: float = edb.get_procurement_unit_price(s)
			var o: float = float(other[s]["lpu"])
			if p <= 0.0: continue
			var ratio: float = o / p
			var tag: String = "%s T%d" % [str(other[s]["board"]).replace("_materials", "").replace("_goods", ""), int(other[s]["tier"])]
			print("  %-20s %12s %12s %9.1fx  %s" % [s, _fmt(p), _fmt(o), ratio, tag])
			if ratio >= 2.0:
				dominated.append({"sym": s, "p": p, "o": o, "ratio": ratio})
	print("\n  -> %d shared goods pay >=2x more per unit on the other board." % dominated.size())

	# ---- C. headroom --------------------------------------------------------
	print("\n=== C. PRICE HEADROOM — max price before the card goes dead ===")
	print("Worst case: a DR-ceiling line at the LOWEST frontier the family is")
	print("plausibly online (refining/ordnance Z2, chem/struct/elec Z4, fab Z7, cap Z9).\n")
	var home_min := {"refining": 2, "ordnance": 2, "chemical": 4, "structural": 4,
		"electronics": 4, "fabrication": 7, "capital": 9}
	print("  %-20s %10s %12s %12s  %s" % ["good", "L/unit", "max L/unit", "headroom", "limiting frontier"])
	for fam in families:
		var fr: int = int(home_min.get(fam, 4))
		var era: float = float(qm.PROC_ERA_INCOME_PER_H.get(fr, 1700.0))
		var non_c: int = int(online_at.get(fr, n_fam))
		var cap: float = era * qm.ENGINEER_SHARE / float(non_c) * qm.PROC_POOL_HOURS
		for sym in edb.PROCUREMENT_FAMILIES[fam]:
			var s: String = str(sym)
			var rate: float = float(ceil_rate.get(s, 0.0))
			if rate <= 0.0: continue
			var qty: float = rate * qm.PROC_ORDER_MINUTES
			var max_price: float = cap / qty
			var p: float = edb.get_procurement_unit_price(s)
			var head: float = max_price / p if p > 0.0 else 0.0
			var mark: String = "  <-- ALREADY OVER" if head < 1.0 else ""
			print("  %-20s %10s %12s %11.2fx  Z%d%s" % [s, _fmt(p), _fmt(max_price), head, fr, mark])

	# ---- D. does the pool actually BIND? -----------------------------------
	# The load-bearing question for any price change. Income is pool-capped only
	# if the player's lines can out-produce the refill. If a normal player never
	# saturates the pool, a price rise is a straight income multiplier, NOT the
	# income-neutral regrain it looks like. Measured at realistic stacks, with
	# the CURRENT prices and a x10 table.
	print("\n=== D. DOES THE POOL BIND? (nominal earn/h vs pool refill/h) ===")
	print("Nominal earn/h = family rate/h x price (what you'd bank if unlimited).")
	print("Refill/h = pool cap / 24h — the true income ceiling for the family.\n")
	for stack in [3, 10, 30]:
		print("  --- %d buildings per producer ---" % stack)
		print("  %-14s %6s %14s %14s %12s  %s"
			% ["family", "front", "nominal/h x1", "nominal/h x10", "refill/h", "binds?"])
		for fam in families:
			var fr: int = int(home_min.get(fam, 4))
			var era: float = float(qm.PROC_ERA_INCOME_PER_H.get(fr, 1700.0))
			var non_d: int = int(online_at.get(fr, n_fam))
			var cap_d: float = era * qm.ENGINEER_SHARE / float(non_d) * qm.PROC_POOL_HOURS
			var refill: float = cap_d / qm.PROC_POOL_HOURS
			var nominal: float = 0.0
			for sym in edb.PROCUREMENT_FAMILIES[fam]:
				var s: String = str(sym)
				var bids: Array = producers.get(s, [])
				if bids.is_empty(): continue
				im.buildings.clear()
				im.building_throttles.clear()
				for b in bids:
					im.buildings[b] = stack
					im.building_throttles[b] = 1.0
				var r: float = float(im.get_total_resource_rates().get(s, 0.0)) * 60.0
				nominal += maxf(0.0, r) * edb.get_procurement_unit_price(s)
			var binds1: bool = nominal >= refill
			var binds10: bool = nominal * 10.0 >= refill
			var verdict: String = ""
			if binds1 and binds10:
				verdict = "BOTH — x10 is income-neutral"
			elif binds10:
				verdict = "only at x10 — x10 RAISES income here"
			else:
				verdict = "NEITHER — x10 is a straight 10x"
			print("  %-14s %6s %14s %14s %12s  %s"
				% [fam, "Z%d" % fr, _fmt(nominal), _fmt(nominal * 10.0), _fmt(refill), verdict])
		print("")

	# ---- E. the actual card ------------------------------------------------
	# The user-facing number. Prints real generated cards at a realistic line,
	# because "the total is fine, only the per-unit reads badly" is a claim about
	# a rendered string and deserves to be read off the real generator.
	print("=== E. REPRESENTATIVE CARDS (real generator, 10 buildings/producer) ===")
	for z in range(2, 5):
		var t := "zone_%d_access" % z
		if rm and not rm.unlocked_techs.has(t):
			rm.unlocked_techs.append(t)
	for probe in [["refining", "Fe"], ["refining", "Cu"], ["structural", "Steel"], ["electronics", "Circuit"]]:
		var fam: String = str(probe[0])
		var s: String = str(probe[1])
		var bids: Array = producers.get(s, [])
		if bids.is_empty(): continue
		im.buildings.clear()
		im.building_throttles.clear()
		for b in bids:
			im.buildings[b] = 10
			im.building_throttles[b] = 1.0
		var r: float = float(im.get_total_resource_rates().get(s, 0.0))
		if r <= 0.0: continue
		var o: Dictionary = qm._generate_procurement_order(fam, s, r)
		print("  %s" % o["desc"])
		print("      -> ask %s units, pays %s Liras   (pool cap %s)"
			% [_fmt(float(o["target_qty"])), _fmt(float(o["reward_credits"])), _fmt(qm.get_pool_cap(fam))])

	# ---- verdict ------------------------------------------------------------
	print("\n=== RESULT ===")
	var fails: int = 0

	# HARD 1 — correctness. A card the player can never claim is a bug at any price.
	if dead_rows.is_empty():
		print("  PASS  no order can be generated above its family's pool cap")
	else:
		fails += 1
		print("  FAIL  %d goods generate a permanently unclaimable card" % dead_rows.size())

	# HARD 2 — legibility. Income is pool-governed (see D), so the per-unit price
	# buys nothing but dignity; a good paying under a Lira or two makes the card
	# read as contempt no matter what the total says. This is the rule the v177
	# retune actually exists to satisfy.
	var floor_price := 3.0
	var illegible: Array = []
	for fam in families:
		for sym in edb.PROCUREMENT_FAMILIES[fam]:
			var s: String = str(sym)
			var p: float = edb.get_procurement_unit_price(s)
			if p > 0.0 and p < floor_price:
				illegible.append("%s (%s)" % [s, _fmt(p)])
	if illegible.is_empty():
		print("  PASS  every good pays at least %s Liras per unit" % _fmt(floor_price))
	else:
		fails += 1
		print("  FAIL  %d goods priced under the %s L/unit legibility floor: %s"
			% [illegible.size(), _fmt(floor_price), ", ".join(illegible)])

	# SOFT — reported, never failed. Per-unit parity with the Stockpile board is
	# NOT a valid invariant for bulk goods: the two boards ask for quantities that
	# differ by ~20x (a ceiling Steel order is ~40K units, the stockpile row asks
	# 2.5K), so equal L/unit would put a Steel card at millions. Fe/Circuit/
	# Superalloy landing at parity is a happy check, not a requirement.
	if dominated.is_empty():
		print("  note  no shared good pays >=2x more on the Stockpile board")
	else:
		print("  note  %d shared goods still pay >=2x more per unit on the Stockpile" % dominated.size())
		print("        board. Deliberate — these are bulk rows where procurement asks")
		print("        for far larger quantities. Not a failure:")
		for d in dominated:
			print("          %s  procurement %s vs stockpile %s" % [d["sym"], _fmt(d["p"]), _fmt(d["o"])])
	get_tree().quit(1 if fails > 0 else 0)

func _fmt(v: float) -> String:
	if v >= 1000000.0: return "%.2fM" % (v / 1000000.0)
	if v >= 1000.0: return "%.1fK" % (v / 1000.0)
	if v >= 10.0: return "%.0f" % v
	if v >= 1.0: return "%.1f" % v
	return "%.2f" % v
