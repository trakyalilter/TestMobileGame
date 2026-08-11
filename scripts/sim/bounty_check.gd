extends Node
# ============================================================================
# BOUNTY/QUEST SPLIT CHECK (v139) — per-zone bounty boards + quest supply orders.
#  1) board composition per unlocked zone: 2 hunts + 1 boss bounty + 1 elite,
#     all zone-locked; elites NEVER target a boss
#  2) paid refresh escalates ×2 per use (per zone); natural refresh regenerates
#     ALL boards and resets heat
#  3) lazy-seed for a zone unlocked mid-window
#  4) save MIGRATION: legacy flat "available" pool discarded, ACTIVE contracts
#     (including a pre-v139 delivery) preserved and still claimable
#  5) quest board: hunts never generate; supply orders consume stock on claim,
#     un-complete when stock ran low; reroll heat escalates and cools on claim
#  6) reward-ladder print per tier (hunt/boss/elite) — eyeball table
#   Godot --headless --path <root> res://scenes/bounty_check.tscn
# ============================================================================

func _ready() -> void:
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	var bm = GameState.bounty_manager
	var qm = GameState.quest_manager
	var res = GameState.resources
	GameState.set_process(false)
	GameState.hard_reset()
	var fails := 0
	print("[BOUNTY] ============ bounty/quest split check (v139) ============")

	# Unlock a mid-game spread: research zones 2-5 + flag zone 11
	for tid in ["zone_2_access", "zone_3_access", "zone_4_access", "zone_5_access"]:
		if not (tid in rm.unlocked_techs):
			rm.unlocked_techs.append(tid)
	GameState.game_settings["z11_unlocked"] = true
	bm.generate_all_pools()

	# ── 1) composition + zone lock + elite-no-boss ──
	var zones: Array = bm.get_unlocked_zones()
	var ok_zones: bool = zones.size() >= 6  # Z1..Z5 + Z11
	var comp_ok := true
	var zone_lock_ok := true
	var elite_hit_boss := false
	var hunters_only := true  # v139b: hunts/elites must target e3/e4 (back-half trash), never e1/e2
	for z in zones:
		var pool: Array = bm.get_zone_contracts(z["id"])
		# Rebuild the zone's module-hunter set (last 2 non-boss enemies)
		var z_trash: Array = []
		for eid in cm.zones[z["id"]].get("enemies", []):
			if not cm.enemy_db.get(eid, {}).get("is_boss", false):
				z_trash.append(eid)
		var z_hunters: Array = z_trash.slice(maxi(0, z_trash.size() - 2))
		var hunts := 0
		var bosses := 0
		var elites := 0
		for c in pool:
			if c["zone_id"] != z["id"]:
				zone_lock_ok = false
			var tgt_boss: bool = cm.enemy_db.get(c["target"], {}).get("is_boss", false)
			if c.get("is_elite", false):
				elites += 1
				if tgt_boss: elite_hit_boss = true
				if not (c["target"] in z_hunters): hunters_only = false
			elif c.get("is_boss_hunt", false):
				bosses += 1
				if not tgt_boss: comp_ok = false
			else:
				hunts += 1
				if tgt_boss: comp_ok = false
				if not (c["target"] in z_hunters): hunters_only = false
		# v175: was a flat `hunts != 2`. _generate_zone_pool emits ONE hunt per
		# module-hunter, and hunters = the last two trash, so a zone with fewer than two
		# trash enemies legitimately ships a smaller board. Zone 1 was cut to a single
		# trash enemy by the staged damage-type ruling and has offered 1 hunt ever since;
		# this assertion has been red for that reason alone, on a board that is correct.
		# Derive the expectation from the roster the generator actually reads.
		var want_hunts: int = z_hunters.size()
		var want_elites: int = 1 if z_hunters.size() > 0 else 0
		var want_boss: int = 0
		for eid2 in cm.zones[z["id"]].get("enemies", []):
			if cm.enemy_db.get(eid2, {}).get("is_boss", false):
				want_boss = 1
		if hunts != want_hunts or bosses != want_boss or elites != want_elites:
			comp_ok = false
			print("[BOUNTY]   composition off in %s: hunts=%d/%d boss=%d/%d elite=%d/%d (trash=%d)" % [
				z["id"], hunts, want_hunts, bosses, want_boss, elites, want_elites, z_trash.size()])
	fails += 0 if (ok_zones and comp_ok and zone_lock_ok and not elite_hit_boss and hunters_only) else 1
	print("[BOUNTY] 1) zones=%d comp(roster-derived)=%s zone-lock=%s elite-no-boss=%s e3/e4-only=%s %s" % [
		zones.size(), comp_ok, zone_lock_ok, not elite_hit_boss, hunters_only,
		"OK" if (ok_zones and comp_ok and zone_lock_ok and not elite_hit_boss and hunters_only) else "*** FAIL"])

	# ── 2) paid refresh escalation + natural reset ──
	var zid: String = zones[2]["id"]  # a Z3-ish zone
	var zdiff: int = zones[2]["difficulty"]
	res.add_currency("credits", 100000000)
	var c0: int = bm.get_refresh_cost(zid)
	var esc_base_ok: bool = (c0 == 5000 * zdiff)
	bm.force_refresh(zid)
	var c1: int = bm.get_refresh_cost(zid)
	bm.force_refresh(zid)
	var c2: int = bm.get_refresh_cost(zid)
	var esc_ok: bool = (c1 == c0 * 2) and (c2 == c0 * 4)
	# other zones' heat untouched
	var other_cold: bool = (bm.get_refresh_cost(zones[0]["id"]) == 5000 * int(zones[0]["difficulty"]))
	# natural refresh: arm a near-expired timer, tick past it
	bm.refresh_timer = 0.01
	bm.process_tick(0.02)
	var after_nat: int = bm.get_refresh_cost(zid)
	var nat_ok: bool = (after_nat == c0) and (bm.refresh_timer > 28000.0)
	# v175: was `size() != 4`. Same stale premise as test 1 -- Zone 1 ships 3 cards
	# (1 hunt + boss + elite) because it has one trash enemy. Assert every board came
	# back NON-EMPTY and matching its roster, which is what "regenerated" means.
	var all_regen: bool = true
	for z in zones:
		var pool2: Array = bm.get_zone_contracts(z["id"])
		var trash2 := 0
		var boss2 := 0
		for eid3 in cm.zones[z["id"]].get("enemies", []):
			if cm.enemy_db.get(eid3, {}).get("is_boss", false):
				boss2 = 1
			else:
				trash2 += 1
		var want_size: int = mini(2, trash2) + boss2 + (1 if trash2 > 0 else 0)
		if pool2.size() != want_size:
			all_regen = false
			print("[BOUNTY]   regen off in %s: %d cards, roster wants %d" % [z["id"], pool2.size(), want_size])
	fails += 0 if (esc_base_ok and esc_ok and other_cold and nat_ok and all_regen) else 1
	print("[BOUNTY] 2) refresh cost %d→%d→%d (base=%s esc=%s other-zone-cold=%s) natural-reset=%s all-regen=%s %s" % [
		c0, c1, c2, esc_base_ok, esc_ok, other_cold, nat_ok, all_regen,
		"OK" if (esc_base_ok and esc_ok and other_cold and nat_ok and all_regen) else "*** FAIL"])

	# ── 3) lazy-seed a zone unlocked mid-window ──
	bm.available_by_zone.erase(zid)
	var lazy_pool: Array = bm.get_zone_contracts(zid)
	var lazy_ok: bool = lazy_pool.size() == 4
	fails += 0 if lazy_ok else 1
	print("[BOUNTY] 3) lazy-seed regenerated %d cards %s" % [lazy_pool.size(), "OK" if lazy_ok else "*** FAIL"])

	# ── 4) migration: legacy flat save with an active delivery ──
	var legacy_delivery := {
		"id": "bounty_legacy_1", "type": "delivery", "title": "Supply: Steel", "desc": "legacy",
		"target": "Steel", "target_qty": 100, "current_qty": 100, "reward_credits": 150000,
		"reward_module_pool": [], "zone_id": "", "difficulty": 3, "completed": true, "claimed": false
	}
	bm.load_save_data_manager({
		"available": [legacy_delivery.duplicate()],  # old flat pool — must be discarded
		"active": [legacy_delivery],
		"refresh_timer": 1234.0, "total_completed": 5, "id_counter": 7
	})
	var mig_active_ok: bool = bm.active_contracts.size() == 1 and bm.active_contracts[0]["type"] == "delivery"
	var mig_flat_gone: bool = bm.available_by_zone.is_empty()
	await get_tree().process_frame  # call_deferred("generate_all_pools") lands
	var mig_regen: bool = not bm.available_by_zone.is_empty()
	var cr_before: float = res.get_currency("credits")
	var mig_claim: bool = bm.claim_contract("bounty_legacy_1")
	var mig_paid: bool = res.get_currency("credits") > cr_before
	fails += 0 if (mig_active_ok and mig_flat_gone and mig_regen and mig_claim and mig_paid) else 1
	print("[BOUNTY] 4) migration: active-kept=%s flat-discarded=%s regen=%s legacy-claim=%s paid=%s %s" % [
		mig_active_ok, mig_flat_gone, mig_regen, mig_claim, mig_paid,
		"OK" if (mig_active_ok and mig_flat_gone and mig_regen and mig_claim and mig_paid) else "*** FAIL"])

	# ── 5) quest side: no hunts, supply consumes on claim + stock guard, reroll heat ──
	qm.reset()
	var q_hunts := 0
	var q_types_ok := true
	for q in qm.board:
		if q["type"] == "hunt": q_hunts += 1
		if not (q["type"] in ["gather", "supply"]): q_types_ok = false
	var no_hunts_ok: bool = (q_hunts == 0) and q_types_ok and qm.board.size() == 6
	# force a supply order onto the board deterministically
	var sq: Dictionary = qm._generate_supply_quest(3, 3)
	var sq_ok: bool = not sq.is_empty() and sq["type"] == "supply"
	var consume_ok := false
	var guard_ok := false
	if sq_ok:
		qm.board.append(sq)
		res.add_element(sq["target"], int(sq["target_qty"]) + 5, true)
		qm._resync_stock_quests()
		var completed_ok: bool = sq["completed"]
		var have_before: float = res.get_element_amount(sq["target"])
		var cq_before: float = res.get_currency("credits")
		var claimed: bool = qm.claim_quest(sq["id"])
		var have_after: float = res.get_element_amount(sq["target"])
		consume_ok = completed_ok and claimed and (have_before - have_after >= float(sq["target_qty"]) - 0.01) and res.get_currency("credits") > cq_before
		# stock guard: complete a second order, then spend the stock before claiming
		var sq2: Dictionary = qm._generate_supply_quest(3, 3)
		qm.board.append(sq2)
		res.add_element(sq2["target"], int(sq2["target_qty"]), true)
		qm._resync_stock_quests()
		res.remove_element(sq2["target"], int(sq2["target_qty"]))
		var claim2: bool = qm.claim_quest(sq2["id"])
		guard_ok = (not claim2) and (not sq2["completed"])
	fails += 0 if (no_hunts_ok and sq_ok and consume_ok and guard_ok) else 1
	print("[BOUNTY] 5) quests: no-hunts=%s supply-gen=%s consume-on-claim=%s stock-guard=%s %s" % [
		no_hunts_ok, sq_ok, consume_ok, guard_ok,
		"OK" if (no_hunts_ok and sq_ok and consume_ok and guard_ok) else "*** FAIL"])

	# reroll heat: ×2 per reroll, cools 1 step per claim
	var r0: int = qm.get_reroll_cost()
	qm.reroll_board()
	var r1: int = qm.get_reroll_cost()
	var heat_up_ok: bool = (r1 == r0 * 2)
	# claim any completed quest to cool (grant a gather target)
	var cooled := false
	for q in qm.board:
		if q["type"] == "gather":
			res.add_element(q["target"], int(q["target_qty"]), true)
			qm._resync_stock_quests()
			if q["completed"]:
				qm.claim_quest(q["id"])
				cooled = qm.get_reroll_cost() == r0
			break
	fails += 0 if (heat_up_ok and cooled) else 1
	print("[BOUNTY] 5b) reroll heat: %d→%d up=%s cooled-on-claim=%s %s" % [
		r0, r1, heat_up_ok, cooled, "OK" if (heat_up_ok and cooled) else "*** FAIL"])

	# ── 6) reward ladder (eyeball) ──
	print("[BOUNTY] 6) reward ladder (credits, pre warp/recursion mults):")
	for z in zones:
		var pool2: Array = bm.get_zone_contracts(z["id"])
		var h_lo := -1
		var h_hi := -1
		var b_val := -1
		var e_val := -1
		for c in pool2:
			var v: int = int(c["reward_credits"])
			if c.get("is_elite", false): e_val = v
			elif c.get("is_boss_hunt", false): b_val = v
			else:
				if h_lo < 0 or v < h_lo: h_lo = v
				if v > h_hi: h_hi = v
		print("[BOUNTY]    T%-2d %-22s hunt %s-%s | boss %s | elite %s" % [
			z["difficulty"], z["name"], _fmt(h_lo), _fmt(h_hi), _fmt(b_val), _fmt(e_val)])

	print("[BOUNTY] %s" % ("ALL PASS" if fails == 0 else "*** %d FAILURE(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)

func _fmt(v: int) -> String:
	if v < 0: return "-"
	if v >= 1000000: return "%.1fM" % (v / 1000000.0)
	if v >= 1000: return "%.0fK" % (v / 1000.0)
	return str(v)
