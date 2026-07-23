extends Node
# ============================================================================
# ANALYTICAL RUN-TIME MODEL — "how long from a fresh post-warp reset to being
# Z10-ready, at each warp count?"
#
# WHY ANALYTICAL: the behaviour bots cannot answer this. The `combat` archetype
# scores combat_kills=0 / highest_zone_diff=0 over 12 sim-days (it maxes gathering
# and idles), and even the good `player_like` funnel bot walls around Z4. Nothing
# in the harness reaches Z10, so there is no simulated number to read. This model
# computes the answer from the live game tables instead.
#
# MODEL:  time(N) = WORK / RATE(N)
#   WORK    credits-equivalent a run must re-earn to stand up a Z10 loadout.
#           Research is included because v140 wipes it on warp, so the whole tech
#           tree is re-bought every run. Read from the real cost tables.
#   RATE(N) credits/hour from THREE streams, all read off live game functions:
#             gathering  get_display_yield() over get_action_speed_multiplier()
#                        (note these are different axes: shards buy SPEED via the
#                        warp gathering mult, the tree buys YIELD via ENG_S1)
#             infra      blueprint-cached buildings that survived the warp
#             combat     averaged trash income for the tier being paid for
#           WORK is bucketed BY TIER and integrated tier-by-tier, because Z8 trash
#           pays ~150-300k/kill and Z10 trash 5-10M/kill — crediting that to the
#           whole run assumes access you have not re-earned yet.
#
# CALIBRATION: warp_accel measures the 500k gate at 11.77h (warp 0) -> 9.38h
# (warp 1) = 1.25x. The model recomputes that same ratio from its own rate curve
# and prints both, so you can see how much of the model is trustworthy before
# reading the Z10 column. If the check drifts far from 1.25 the model is wrong.
#
# ASSUMPTIONS (stated, not hidden):
#   - a run ends at gathering level END_LVL; the next run starts with the XP the
#     warp tree lets you keep (REC_2/REC_6), so early levels are not re-ground
#   - one active gathering action; no processing income
#   - END_BUILDINGS buildings at end of run, kept per get_blueprint_rebuild_frac()
#   - combat = averaged non-boss trash of the tier, rare gear, weak-type weapons
#   - the combat term is the LEAST stable input: it spans 17k/h (T1) to 1.4B/h
#     (T10) and one tier (T6) dips ~150x below its neighbours. Trust the SHAPE and
#     the warp-to-warp ratios; treat single-tier values as soft.
#
#   Godot --headless --path <root> res://scenes/warp_z10_model.tscn
# ============================================================================

const WARPS := [0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20]
const END_LVL := 90          # gathering level a Z10-capable run finishes around
const END_OF_RUN_CREDITS := 2.0e10
const GATE := 500000.0       # first-warp progress gate, for the calibration check

# --- income streams beyond gathering -----------------------------------------
# INFRA: a Z10-ready run ends with a mature grid. On warp, REC_1 Blueprint Cache
# keeps a fraction of it (+REC_S2), and those kept buildings KEEP PRODUCING even
# though research is wiped (research_req is a can_build gate; the production path
# never reads it). So infra income is strongly warp-dependent — at warp 0 it is
# literally zero because REC_1 does not exist yet.
const END_BUILDINGS := 120   # total buildings a Z10-ready run finishes with
# COMBAT: farming trash in this zone. Kill speed scales with
# get_combat_multiplier() = (1 + shards*0.03) * 2^tier, so combat income inherits
# the tier staircase directly.
const FARM_ZONE := 8
const FARM_GEAR_RARITY := 2  # rare — a realistic farm loadout, not best-in-slot
const WEAPON_INTERVAL := 2.5  # module atk_interval default; attack_* is per-volley
const KILL_OVERHEAD_S := 3.0  # respawn/approach between trash kills

var _tier_trace: Array = []


func _cumulative_shards(wm, n: int) -> float:
	var shards := 0.0
	for w in range(n):
		wm.total_warps = w
		wm.warp_shards = shards
		wm.warp_shards_spent = 0.0
		wm.credits_at_warp_start = 0.0
		GameState.resources.lifetime_credits = END_OF_RUN_CREDITS
		shards += float(wm.calculate_warp_gains())
	return shards


# Economy-priority spend: this models a player optimising RUN SPEED, not a boss
# kill, so yield/duration/rebuild nodes come before combat ones.
func _spend(wm) -> Dictionary:
	var bought := {}
	for nid in ["ENG_1", "ENG_2", "ENG_4", "REC_1", "REC_2", "REC_6"]:
		if wm.can_purchase_node(nid):
			wm.purchase_node(nid)
			bought[nid] = 1
	for spine in ["ENG_S1", "ENG_S2", "REC_S2", "REC_S1"]:
		var guard := 0
		while wm.can_purchase_node(spine) and guard < 500:
			wm.purchase_node(spine)
			bought[spine] = int(bought.get(spine, 0)) + 1
			guard += 1
	return bought


# WORK bucketed BY TIER (1..10), not as one lump.
#
# This matters more than it looks. Combat income at Z8 is ~150-300k credits per
# trash kill — thousands of times a fresh run's gathering rate. Crediting that to
# the whole run assumes you can farm Z8 from the moment you warp, but Z8 access is
# gated behind the very research and gear this WORK number represents. Summing it
# flat produced "Z10 in 2.6 hours at warp 0", which is nonsense.
#
# So work is attributed to the tier that unlocks it, and the run is integrated
# tier by tier with only the combat income available AT that tier.
func _work_by_tier(rm, sm) -> Array:
	var buckets := []
	buckets.resize(11)
	for i in range(11):
		buckets[i] = 0.0
	for tid in rm.tech_tree:
		var t: Dictionary = rm.tech_tree[tid]
		var tier: int = clampi(int(t.get("tier", 5)), 1, 10)
		var c := float(t.get("cost", 0))
		for sym in (t.get("items", {}) as Dictionary):
			c += float(t["items"][sym]) * float(ElementDB.get_element_value(String(sym)))
		buckets[tier] += c
	# hulls: spread by their own tier order (corvette..dreadnought -> 1..10)
	var hull_ids: Array = sm.hulls.keys()
	for hi in range(hull_ids.size()):
		var tier2: int = clampi(int(round(float(hi + 1) / float(hull_ids.size()) * 10.0)), 1, 10)
		for sym in (sm.hulls[hull_ids[hi]].get("cost", {}) as Dictionary):
			var v: float = float(sm.hulls[hull_ids[hi]]["cost"][sym])
			buckets[tier2] += v if String(sym) == "credits" else v * float(ElementDB.get_element_value(String(sym)))
	# modules: bucket by their zN_ prefix
	for mid in sm.modules:
		var name := String(mid)
		if not name.begins_with("z"):
			continue
		var us := name.find("_")
		if us < 2:
			continue
		var zn := int(name.substr(1, us - 1))
		if zn < 1 or zn > 10:
			continue
		for sym in (sm.modules[mid].get("cost", {}) as Dictionary):
			var v2: float = float(sm.modules[mid]["cost"][sym])
			buckets[zn] += v2 if String(sym) == "credits" else v2 * float(ElementDB.get_element_value(String(sym)))
	return buckets


# Best credits/hour across unlocked gathering actions at the current state.
func _rate_per_hour(gm) -> Dictionary:
	var best := 0.0
	var best_id := ""
	for aid in gm.actions:
		var a: Dictionary = gm.actions[aid]
		if int(a.get("level_req", 1)) > gm.get_level():
			continue
		if String(a.get("research_req", "")) != "":
			continue                      # research is wiped post-warp
		var dur := float(a.get("duration", 3.0))
		var spd := float(gm.get_action_speed_multiplier(aid))
		if dur <= 0.0 or spd <= 0.0:
			continue
		var per_action := 0.0
		var lt: Array = a.get("loot_table", [])
		for i in range(lt.size()):
			var e: Array = lt[i]
			var qty := float(gm.get_display_yield(e, i)) * float(e[1])   # x drop chance
			per_action += qty * float(ElementDB.get_element_value(String(e[0])))
		var cph := per_action / (dur / spd) * 3600.0
		if cph > best:
			best = cph
			best_id = aid
	return {"cph": best, "id": best_id}


# Credits/hour from the buildings the Blueprint Cache carried through the warp.
# Uses the real get_effective_yield (tree ENG_S1 + mastery) over the real
# get_effective_interval (warp production multiplier), so both warp axes land.
func _infra_cph(im, wm) -> float:
	var frac: float = wm.get_blueprint_rebuild_frac()
	if frac <= 0.0:
		return 0.0                       # no REC_1 => nothing survives the warp
	var producers: Array = []
	for bid in im.building_db:
		var d: Dictionary = im.building_db[bid]
		if d.has("yield") and not (d["yield"] as Dictionary).is_empty():
			producers.append(bid)
	if producers.is_empty():
		return 0.0
	# END_BUILDINGS spread across the producer types, then the kept fraction.
	var per_type: float = float(END_BUILDINGS) / float(producers.size()) * frac
	var total := 0.0
	for bid in producers:
		var iv: float = im.get_effective_interval(bid)
		if iv <= 0.0:
			continue
		for res in (im.building_db[bid]["yield"] as Dictionary):
			var q: float = im.get_effective_yield(bid, String(res))
			total += q / iv * 3600.0 * per_type * float(ElementDB.get_element_value(String(res)))
	return total


# Credits/hour farming trash in FARM_ZONE. Kill time comes from the player's real
# recalc'd attack times get_combat_multiplier(); loot value from the enemy's real
# loot table times get_combat_loot_multiplier().
func _combat_cph(cm, sm, wm, farm_zone: int) -> float:
	var zid := ""
	for z in cm.zones:
		if int(cm.zones[z].get("difficulty", 0)) == farm_zone:
			zid = String(z)
			break
	if zid == "":
		return 0.0
	# Average over ALL non-boss trash in the zone. Picking a single representative
	# (the last in the list) made the curve swing 43,000x between adjacent tiers —
	# that was enemy-selection variance, not economy. A farmer meets the whole mix.
	var trash: Array = []
	for e in (cm.zones[zid].get("enemies", []) as Array):
		var ed: Dictionary = cm.enemy_db.get(String(e), {})
		if ed.is_empty() or bool(ed.get("is_boss", false)):
			continue
		trash.append(ed)
	if trash.is_empty():
		return 0.0
	var ed2: Dictionary = trash[0]
	# Fight the weak type. Equipping kinetic into z8_nebula_phantom's resist_k 0.40
	# understated kill speed badly; a real player reads the resist and brings the
	# counter (resist_x -0.30 here = 1.30x damage).
	var rk := float(ed2.get("resist_k", 0.0))
	var re2 := float(ed2.get("resist_e", 0.0))
	var rx := float(ed2.get("resist_x", 0.0))
	var mn: float = min(rk, min(re2, rx))
	var wsuffix := "kinetic"
	var wresist := rk
	if mn == rx:
		wsuffix = "missile"; wresist = rx
	elif mn == re2:
		wsuffix = "energy"; wresist = re2

	# equip_module() enforces research via can_equip_module(), so with research wiped
	# nothing equips and this read 0 combat income. That is correct game behaviour but
	# wrong for THIS question: you only farm Z8 once you have re-researched zone_8
	# access, so by then the gear is equippable. Unlock for the rate calculation.
	# Unlock ONLY up to this tier. Unlocking the whole tree handed every tier
	# efficiency_5's x10 combat-loot multiplier, so tier-1 farming was priced with
	# endgame research. get_combat_loot_multiplier() reads that ladder directly.
	var rm2 = GameState.research_manager
	rm2.unlocked_techs = []
	for tid in rm2.tech_tree:
		if int(rm2.tech_tree[tid].get("tier", 99)) <= farm_zone:
			rm2.unlocked_techs.append(tid)

	# Gear a farm loadout at the zone tier.
	sm.active_hull = "battlecruiser_hull"
	sm.loadout.clear()
	var slots: Array = sm.hulls.get(sm.active_hull, {}).get("slots", [])
	# BATTERIES FIRST. The equip guard rejects anything that pushes energy_used past
	# capacity, and the battlecruiser lists its weapon slots before its battery slots
	# — equipping in raw slot order blocked every weapon and read as 0 combat income.
	for pass_type in ["battery", "armor", "shield", "weapon"]:
		for i in range(slots.size()):
			if String(slots[i]) != pass_type:
				continue
			var base := ""
			match pass_type:
				"weapon": base = "z%d_%s" % [farm_zone, wsuffix]
				"armor":  base = "z%d_armor" % farm_zone
				"shield": base = "z%d_shield" % farm_zone
				"battery": base = "z%d_battery" % farm_zone
			if base != "" and base in sm.modules:
				var cid := String(sm.generate_module_drop(base, FARM_GEAR_RARITY, farm_zone))
				if cid != "":
					sm.equip_module(i, cid, true)
	sm.recalc_stats()

	var raw_atk: float = float(sm.attack_kinetic + sm.attack_energy + sm.attack_explosive)
	if raw_atk <= 0.0:
		return 0.0
	# attack_* is damage PER VOLLEY, not per second — weapons fire on atk_interval
	# (2.5s default). Treating it as DPS inflated combat income 2.5x on its own.
	var burst: float = raw_atk / WEAPON_INTERVAL * wm.get_combat_multiplier()
	var rkey := "resist_k"
	if wsuffix == "missile":
		rkey = "resist_x"
	elif wsuffix == "energy":
		rkey = "resist_e"

	cm.current_zone = cm.zones[zid]
	var lmult: float = cm.get_combat_loot_multiplier()

	# Average credits/hour across the zone's trash mix. One loadout, many targets,
	# so resist varies per enemy — that is the real farming experience.
	var acc := 0.0
	for ed in trash:
		var res: float = float((ed as Dictionary).get(rkey, 0.0))
		var dps: float = maxf(burst * (1.0 - res), 1.0)
		var stats: Dictionary = (ed as Dictionary).get("stats", {})
		var ehp: float = float(stats.get("hp", 1)) + float(stats.get("max_shield", 0))
		# + per-kill overhead: respawn/approach between trash kills is not free.
		var ttk: float = maxf(ehp / dps, 0.5) + KILL_OVERHEAD_S
		var per_kill := 0.0
		for entry in ((ed as Dictionary).get("loot", []) as Array):
			var avg: float = (float(entry[1]) + float(entry[2])) * 0.5 * lmult
			per_kill += avg if String(entry[0]) == "credits" else avg * float(ElementDB.get_element_value(String(entry[0])))
		acc += per_kill / ttk * 3600.0
	return acc / float(trash.size())


# Set gathering to the level a warp actually leaves you at.
func _seed_retained_level(gm, keep: float) -> void:
	var end_xp := float(gm.get_xp_for_level(END_LVL))
	gm.xp = end_xp * keep
	gm.level = 1
	gm.check_level_up()


# A run is not played at its STARTING level — you level from start_lvl up to
# END_LVL while doing the work, and the rate rises the whole way. Pricing the run
# at the starting rate is what made the first cut of this model claim 2.87x for
# warp 1 against a measured 1.25x: warp 0 was charged level-1 rates for an entire
# run it spends mostly at level 40+.
#
# For fixed work, time = sum(work_band / rate_band), so the correct summary rate
# is the HARMONIC mean over the level arc, not the arithmetic one.
func _run_rate(gm, start_lvl: int, end_lvl: int = END_LVL) -> Dictionary:
	var saved_xp: float = gm.xp
	var saved_lvl: int = gm.level
	var inv_sum := 0.0
	var n := 0
	var best_id := ""
	var lvl := maxi(start_lvl, 1)
	while lvl <= end_lvl:
		gm.xp = float(gm.get_xp_for_level(lvl))
		gm.level = 1
		gm.check_level_up()
		var r: Dictionary = _rate_per_hour(gm)
		var c: float = float(r["cph"])
		if c > 0.0:
			inv_sum += 1.0 / c
			n += 1
			if best_id == "":
				best_id = String(r["id"])
		lvl += 5
	gm.xp = saved_xp
	gm.level = saved_lvl
	gm.check_level_up()
	if n == 0:
		return {"cph": 0.0, "id": ""}
	return {"cph": float(n) / inv_sum, "id": best_id}


func _ready() -> void:
	var wm = GameState.warp_manager
	var rm = GameState.research_manager
	var sm = GameState.shipyard_manager
	var gm = GameState.gathering_manager
	GameState.set_process(false)
	GameState.hard_reset()

	var work: Array = _work_by_tier(rm, sm)
	print("[Z10MODEL] ================================================================")
	print("[Z10MODEL] WORK to re-stand a Z10 loadout (credits-equivalent)")
	var work_total := 0.0
	for t in range(1, 11):
		work_total += float(work[t])
		print("[Z10MODEL]   tier %2d : %16.0f" % [t, float(work[t])])
	print("[Z10MODEL]   TOTAL   : %16.0f" % work_total)
	print("[Z10MODEL] ================================================================")
	print("[Z10MODEL]  warp  shards  tier  keepXP  lvl      gather/h     infra/h    combat/h      TOTAL/h  Z10 hours   vs warp0")
	var base_h := 0.0
	var rows := []
	for n in WARPS:
		GameState.hard_reset()
		var shards := _cumulative_shards(wm, n)
		wm.total_warps = n
		wm.warp_shards = shards
		wm.warp_shards_spent = 0.0
		wm.purchased_nodes.clear()
		wm.node_levels.clear()
		if n > 0:
			_spend(wm)
		var keep: float = wm.get_tree_xp_keep() if n > 0 else 0.0
		_seed_retained_level(gm, keep)
		_seed_retained_level(GameState.infrastructure_manager, keep)
		var start_lvl: int = gm.get_level()
		var r: Dictionary = _run_rate(gm, start_lvl)
		var gath: float = float(r["cph"])
		var infra: float = _infra_cph(GameState.infrastructure_manager, wm)

		# Integrate tier by tier. At tier T you are fighting zone T, so only zone-T
		# combat income is available to pay for tier-T work. Tier 1-2 has effectively
		# no combat income; the late tiers are carried almost entirely by it.
		var hours := 0.0
		var combat_at_end := 0.0
		for tier in range(1, 11):
			var w_t: float = float(work[tier])
			if w_t <= 0.0:
				continue
			var cmb: float = _combat_cph(GameState.combat_manager, sm, wm, tier)
			combat_at_end = cmb
			var rate_t: float = gath + infra + cmb
			if rate_t <= 0.0:
				continue
			hours += w_t / rate_t
			if n == 0:
				_tier_trace.append("T%d %.0fh (cmb %.0f/h)" % [tier, w_t / rate_t, cmb])
		var combat: float = combat_at_end
		var cph: float = gath + infra + combat
		if n == 0:
			base_h = hours
		var rel: String = "-" if n == 0 else ("%.2fx faster" % (base_h / hours) if hours > 0.0 else "n/a")
		print("[Z10MODEL]  %4d  %6.0f  %4d  %5.0f%%  %3d  %11.0f %11.0f %11.0f %12.0f  %8.1f   %s" % [
			n, shards, wm.get_warp_tier(), keep * 100.0, gm.get_level(),
			gath, infra, combat, cph, hours, rel])
		rows.append({"n": n, "h": hours, "cph": cph, "g": gath, "i": infra, "c": combat})

	# ── calibration: reproduce warp_accel's measured 11.77h -> 9.38h (1.25x) ──
	# This must mirror THAT run, not the Z10 run: warp_accel stops at the 500k gate,
	# so it only reaches gathering level ~56 and banks exactly 1 shard. Scoring it
	# with the Z10 arc (level 90, 16 shards) is what made the first two cuts of this
	# calibration read 2.87x and 2.18x against a measured 1.25x.
	const CAL_END_LVL := 56     # level warp_accel phase 1 actually finished at
	const CAL_POST_LVL := 44    # level it retained after the warp
	print("[Z10MODEL] ----------------------------------------------------------------")
	print("[Z10MODEL] warp-0 run shape, tier by tier:")
	for line in _tier_trace:
		print("[Z10MODEL]   %s" % line)
	print("[Z10MODEL] ================================================================")
	print("[Z10MODEL] CALIBRATION vs warp_accel (measured 11.77h -> 9.38h = 1.25x)")

	GameState.hard_reset()
	wm.total_warps = 0
	wm.warp_shards = 0.0
	wm.warp_shards_spent = 0.0
	wm.purchased_nodes.clear()
	wm.node_levels.clear()
	var cal0: float = float(_run_rate(gm, 1, CAL_END_LVL)["cph"])

	GameState.hard_reset()
	wm.total_warps = 1
	wm.warp_shards = 1.0        # warp_accel banked exactly +1 shard at the gate
	wm.warp_shards_spent = 0.0
	wm.purchased_nodes.clear()
	wm.node_levels.clear()
	_spend(wm)
	var cal1: float = float(_run_rate(gm, CAL_POST_LVL, CAL_END_LVL)["cph"])

	var model_ratio: float = (cal1 / cal0) if cal0 > 0.0 else 0.0
	print("[Z10MODEL]   model gate-time: warp0 %.2fh -> warp1 %.2fh  (%.2fx)" % [
		GATE / cal0, GATE / cal1, model_ratio])
	print("[Z10MODEL]   measured       : warp0 11.77h -> warp1  9.38h  (1.25x)")
	if absf(model_ratio - 1.25) > 0.35:
		print("[Z10MODEL]   !! model disagrees with measurement — Z10 column is INDICATIVE ONLY")
	else:
		print("[Z10MODEL]   model tracks the measured speedup; Z10 column rests on the same math")
	print("[Z10MODEL] ================================================================")
	get_tree().quit()
