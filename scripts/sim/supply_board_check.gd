extends Node
# ============================================================================
# STATION PROCUREMENT CHECK (v162, Demand Engine S1 — docs/design/DEMAND_ENGINE.md)
#  1) static data: every board good has an infra producer, a unit price, and is
#     never a zone signature alloy (freight must not eat processing's identity)
#  2) eligibility: no boards before a family is online; orders only for goods
#     with positive NET rate; dormant families generate nothing
#  3) qty/reward shape: qty rounded and >=10; reward == qty x unit price
#  4) pool math: born full; cap formula; lazy 12h refill lands at ~cap/2
#     (the SAME code path is the offline refill — no separate branch to test)
#  5) claim: pool-gate blocks (order+stock kept), stock re-verify un-completes,
#     success consumes stock + decrements pool by BASE reward + refills card
#  6) legacy pre-v162 "supply" actives on the Standing Orders board still claim
#  7) reset(): boards+pools regenerate (warp/hard-reset path)
#  8) price ladder print: ceiling L/h per good — the tuning eyeball table
#   Godot --headless --path <root> res://scenes/supply_board_check.tscn
# ============================================================================

func _ready() -> void:
	var qm = GameState.quest_manager
	var im = GameState.infrastructure_manager
	var res = GameState.resources
	var sm = GameState.shipyard_manager
	GameState.set_process(false)
	GameState.hard_reset()
	var fails := 0
	print("[PROC] ============ station procurement check (v162) ============")

	# ── 1) static data sanity ──
	var alloy_set := {}
	for z in sm.TIER_ALLOY_BY_ZONE:
		alloy_set[String(sm.TIER_ALLOY_BY_ZONE[z])] = true
	var producers := {}
	for bid in im.building_db:
		var bdata = im.building_db[bid]
		if bdata.has("yield"):
			for r2 in bdata["yield"]:
				producers[String(r2)] = true
	var bad_static := 0
	for fam in ElementDB.PROCUREMENT_FAMILIES:
		for sym in ElementDB.PROCUREMENT_FAMILIES[fam]:
			var s: String = String(sym)
			if not producers.has(s):
				print("[PROC]  STATIC FAIL: %s (%s) has no infra producer" % [s, fam])
				bad_static += 1
			if ElementDB.get_procurement_unit_price(s) <= 0.0:
				print("[PROC]  STATIC FAIL: %s (%s) has no unit price" % [s, fam])
				bad_static += 1
			if alloy_set.has(s):
				print("[PROC]  STATIC FAIL: %s is a zone signature alloy" % s)
				bad_static += 1
	if bad_static > 0: fails += 1
	print("[PROC] 1) static data (producer/price/no-alloy): %s" % ("PASS" if bad_static == 0 else "FAIL"))

	# ── 2) eligibility ──
	var pre_ok: bool = (not qm.is_procurement_unlocked()) and qm.get_online_families().is_empty()
	qm.ensure_procurement()
	pre_ok = pre_ok and qm.proc_boards.is_empty()
	if not pre_ok: fails += 1
	print("[PROC] 2a) fresh game: no families online, no boards: %s" % ("PASS" if pre_ok else "FAIL"))

	im.buildings["auto_smelter"] = 2   # structural family online (Steel)
	qm.ensure_procurement()
	var b: Array = qm.get_procurement_board("structural")
	var elig_ok: bool = b.size() == qm.PROC_CARDS_PER_FAMILY
	var rates: Dictionary = im.get_total_resource_rates()
	for q in b:
		if float(rates.get(q["target"], 0.0)) <= qm.PROC_RATE_EPS:
			elig_ok = false
	elig_ok = elig_ok and qm.get_procurement_board("refining").is_empty()
	elig_ok = elig_ok and qm.is_family_online("structural") and not qm.is_family_online("refining")
	if not elig_ok: fails += 1
	print("[PROC] 2b) online family fills %d cards, rate>0 targets only, dormant stays empty: %s" % [qm.PROC_CARDS_PER_FAMILY, "PASS" if elig_ok else "FAIL"])

	# ── 3) qty/reward shape ──
	var shape_ok := true
	for q in b:
		var qty: int = int(q["target_qty"])
		if qty < 10 or qty % 10 != 0: shape_ok = false
		var want: int = maxi(1, int(round(float(qty) * float(q["unit_price"]))))
		if int(q["reward_credits"]) != want: shape_ok = false
		if String(q["type"]) != "procurement": shape_ok = false
	if not shape_ok: fails += 1
	print("[PROC] 3) qty rounded >=10, reward == qty x price: %s" % ("PASS" if shape_ok else "FAIL"))

	# ── 4) pool math ──
	var cap: float = qm.get_pool_cap("structural")
	var era: float = float(qm.PROC_ERA_INCOME_PER_H.get(qm._proc_frontier(), 0.0))
	var want_cap: float = era * qm.ENGINEER_SHARE / float(maxi(1, qm.get_online_families().size())) * qm.PROC_POOL_HOURS
	var cap_ok: bool = absf(cap - want_cap) < 0.01 and absf(qm.get_pool_value("structural") - cap) < 0.01
	qm.proc_pools["structural"] = 0.0
	qm._proc_pool_ts = Time.get_unix_time_from_system() - (qm.PROC_POOL_HOURS * 3600.0 / 2.0)
	var half: float = qm.get_pool_value("structural")
	var refill_ok: bool = absf(half - cap * 0.5) < cap * 0.01
	if not (cap_ok and refill_ok): fails += 1
	print("[PROC] 4) pool cap formula + born-full + lazy 12h refill ~= cap/2: %s (cap %.0f, half %.0f)" % ["PASS" if cap_ok and refill_ok else "FAIL", cap, half])

	# ── 5) claim path ──
	var q0: Dictionary = b[0]
	var tgt: String = String(q0["target"])
	var need: int = int(q0["target_qty"])
	var reward_base: int = int(q0["reward_credits"])
	res.add_element(tgt, need)
	qm._resync_stock_quests()
	var claim_ok := true
	if not q0["completed"]: claim_ok = false
	# 5a: pool gate — empty pool blocks, loses nothing
	qm.proc_pools["structural"] = 0.0
	qm._proc_pool_ts = Time.get_unix_time_from_system()
	if qm.claim_procurement(String(q0["id"])): claim_ok = false
	if res.get_element_amount(tgt) != need: claim_ok = false
	if qm.get_procurement_board("structural").size() != qm.PROC_CARDS_PER_FAMILY: claim_ok = false
	# 5b: stock re-verify — pool fine, stock gone -> un-completes
	qm.proc_pools["structural"] = cap
	res.remove_element(tgt, need)
	if qm.claim_procurement(String(q0["id"])): claim_ok = false
	if q0["completed"]: claim_ok = false
	# 5c: success — consumes stock, pays, decrements pool by BASE, refills card
	res.add_element(tgt, need)
	qm._resync_stock_quests()
	var pool_before: float = qm.get_pool_value("structural")
	var creds_before: float = res.get_currency("credits")
	if not qm.claim_procurement(String(q0["id"])): claim_ok = false
	if res.get_element_amount(tgt) != 0: claim_ok = false
	if res.get_currency("credits") <= creds_before: claim_ok = false
	if absf((pool_before - qm.get_pool_value("structural")) - float(reward_base)) > float(reward_base) * 0.02 + 1.0: claim_ok = false
	if qm.get_procurement_board("structural").size() != qm.PROC_CARDS_PER_FAMILY: claim_ok = false
	if not claim_ok: fails += 1
	print("[PROC] 5) claim: pool-gate keeps all, stock re-verify un-completes, success pays+decrements+refills: %s" % ("PASS" if claim_ok else "FAIL"))

	# ── 6) legacy supply order still claims ──
	var legacy := {
		"id": "legacy_supply_1", "type": "supply",
		"title": "Supply Order: Steel", "desc": "legacy",
		"target": "Steel", "target_qty": 50, "current_qty": 50,
		"reward_credits": 12345, "difficulty": 2, "completed": true, "claimed": false
	}
	qm.board.append(legacy)
	res.add_element("Steel", 50)
	qm._resync_stock_quests()
	var c_before: float = res.get_currency("credits")
	var legacy_ok: bool = qm.claim_quest("legacy_supply_1")
	legacy_ok = legacy_ok and res.get_currency("credits") > c_before
	if not legacy_ok: fails += 1
	print("[PROC] 6) legacy pre-v162 supply active claims via claim_quest: %s" % ("PASS" if legacy_ok else "FAIL"))

	# ── 7) reset regenerates ──
	qm.reset()
	var reset_ok: bool = qm.proc_boards.is_empty() and qm.proc_pools.is_empty()
	qm.ensure_procurement()   # buildings persist in this sim -> family re-onlines
	reset_ok = reset_ok and qm.get_procurement_board("structural").size() == qm.PROC_CARDS_PER_FAMILY
	reset_ok = reset_ok and absf(qm.get_pool_value("structural") - qm.get_pool_cap("structural")) < 0.01
	if not reset_ok: fails += 1
	print("[PROC] 7) reset(): boards+pools cleared, regenerate born-full: %s" % ("PASS" if reset_ok else "FAIL"))

	# ── 8) price ladder — ceiling L/h per good (informational, for tuning) ──
	print("[PROC] 8) ceiling ladder (price x best-producer neutral rate x DR20, L/h):")
	for fam in ElementDB.PROCUREMENT_FAMILY_ORDER:
		var lines: Array = []
		for sym in ElementDB.PROCUREMENT_FAMILIES[fam]:
			var s: String = String(sym)
			var best: float = 0.0
			for bid in im.building_db:
				var bdata = im.building_db[bid]
				if bdata.has("yield") and bdata["yield"].has(s):
					var r3: float = float(bdata["yield"][s]) / float(bdata.get("interval", 10.0))
					if r3 > best: best = r3
			var lh: float = best * 20.0 * 3600.0 * ElementDB.get_procurement_unit_price(s)
			lines.append("%s %s" % [s, _fmt(lh)])
		print("[PROC]    %-12s %s" % [fam, " | ".join(lines)])

	print("[PROC] %s" % ("ALL PASS" if fails == 0 else "*** %d FAILURE(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)

func _fmt(v: float) -> String:
	if v >= 1000000000.0: return "%.1fB" % (v / 1000000000.0)
	if v >= 1000000.0: return "%.1fM" % (v / 1000000.0)
	if v >= 1000.0: return "%.0fK" % (v / 1000.0)
	return "%.0f" % v
