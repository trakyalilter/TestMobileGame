extends Node
# A WARP MUST NOT LEAVE CLAIMABLE CONTRACTS BEHIND (v175).
#
# execute_warp() resets seven managers and never touched bounty_manager — before v175
# `bounty_manager.reset()` had exactly one caller, hard_reset. A completed-but-unclaimed
# contract therefore survived the warp, and claiming it afterwards added to
# lifetime_credits AFTER `credits_at_warp_start` was snapshotted. The payout counted in
# full as post-warp progress, so banking the 3-contract cap and delaying one button press
# bought a second warp for free.
#
# Measured per zone as FREE EXTRA SHARDS: bank contracts, warp, then claim what survived
# and ask calculate_warp_gains() what the new run is already worth. On a correct build the
# answer is 0 at every zone, and active_contracts is empty the moment the warp completes.
#
# Two things this deliberately does NOT do, because the original audit did and got the
# severity wrong: it does not force every progression flag on, and it does not reach for
# the single richest contract on any board (that produced a Zone-15 bounty worth 7.2
# BILLION dropped into a run with 8 million lifetime credits — a ~900x mismatch that is
# not a player scenario). Contracts are drawn from the zone the run is actually in.
#
#   Godot --headless --path <root> res://scenes/bounty_warp_check.tscn

const ZONES := [3, 5, 6, 8, 10]

var fails: int = 0

func _ready() -> void:
	await get_tree().process_frame
	if not GameState.sim_mode:
		print("[BWARP] ABORT: sim_mode is false — this probe warps and resets state.")
		get_tree().quit(1)
		return
	GameState.set_process(false)

	print("[BWARP] %-6s %10s %12s %10s %12s %14s" % [
		"zone", "shards", "banked", "left open", "claimed", "FREE SHARDS"])
	for z in ZONES:
		var r: Dictionary = _run(z)
		var free: int = int(r["free"])
		print("[BWARP] Z%-5d %10s %12d %10d %12s %14s%s" % [
			z, "%d -> %d" % [int(r["shards_before"]), int(r["shards_after"])],
			int(r["banked"]), int(r["left_open"]),
			_fmt(float(r["claimed"])), str(free),
			"   <-- EXPLOIT" if free > 0 else ""])
		# TRIPWIRE. If nothing was banked, the scenario never happened and a green row
		# means nothing. This must fail loudly rather than read as "no exploit".
		if int(r["banked"]) == 0:
			_fail("Z%d: banked 0 contracts — the probe did not set up the exploit, so its verdict is meaningless" % z)
		if int(r["left_open"]) > 0:
			_fail("Z%d: %d contract(s) survived the warp and were still claimable" % [z, int(r["left_open"])])
		if free > 0:
			_fail("Z%d: claiming banked contracts after the warp re-armed the gate for %d free shard(s)" % [z, free])

	# ---- the settlement must actually PAY -----------------------------------
	# Closing the exploit by silently deleting completed contracts would also pass every
	# assertion above, and would quietly rob a player who earned them. A/B the same zone
	# with and without banked contracts and require the banked run to come out of the
	# warp richer by roughly what it banked.
	var with_bank: Dictionary = _run(8)
	var without: Dictionary = _run(8, true)
	var paid: float = float(with_bank["post_credits"]) - float(without["post_credits"])
	print("[BWARP] settlement A/B at Z8: banked run leaves the warp with %s more Liras than the empty run" % _fmt(paid))
	print("[BWARP]   (banked contract face value %s)" % _fmt(float(with_bank["banked_value"])))
	if paid <= 0.0:
		_fail("banked contracts were destroyed by the warp instead of settled — the player lost %s Liras of earned reward" % _fmt(float(with_bank["banked_value"])))
	elif paid < float(with_bank["banked_value"]) * 0.5:
		_fail("settlement paid only %s of %s banked — most of the earned reward vanished" % [
			_fmt(paid), _fmt(float(with_bank["banked_value"]))])

	print("[BWARP] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _run(zone: int, skip_bank: bool = false) -> Dictionary:
	var wm = GameState.warp_manager
	var bm = GameState.bounty_manager
	var rm = GameState.research_manager
	GameState.hard_reset()

	# A run that reached zone N: its research, and a lifetime_credits total that clears
	# the shard threshold the way real play would.
	for tid in rm.tech_tree:
		if int(rm.tech_tree[tid].get("tier", 99)) <= zone and not (tid in rm.unlocked_techs):
			rm.unlocked_techs.append(str(tid))
	for z2 in range(1, zone + 1):
		GameState.game_settings["zone_%d_access" % z2] = true
	bm.generate_all_pools()
	GameState.resources.lifetime_credits = wm.get_tree_shard_threshold() * pow(2.0, maxi(0, zone - 3))

	# Bank the cap: accept up to MAX_ACTIVE from THIS run's zones and mark them done.
	# get_unlocked_zones() returns DICTIONARIES ({id, name, difficulty}), not ids. The
	# first version of this probe passed str() over them, built a board for a zone key
	# that does not exist, banked nothing, and reported "no exploit" at every zone — a
	# clean green from a probe that never ran the scenario. Hence the tripwire below.
	# get_unlocked_zones() sorts ASCENDING by difficulty, so taking the first three
	# banked Zone-1 trash contracts inside a Zone-10 run and made the payout look
	# trivial. A player banking contracts before a warp banks their most valuable ones.
	# Rank every contract the run can actually reach and take the top MAX_ACTIVE — rich,
	# but drawn only from THIS run's own zones, not from an endgame board it cannot see.
	var pool_all: Array = []
	var top_zone := 0
	for zrec in bm.get_unlocked_zones():
		var zrd: Dictionary = zrec
		top_zone = maxi(top_zone, int(zrd.get("difficulty", 0)))
		for c in bm.get_zone_contracts(str(zrd["id"])):
			pool_all.append(c)
	pool_all.sort_custom(func(a, b): return float(a["reward_credits"]) > float(b["reward_credits"]))
	var banked := 0
	var banked_value := 0.0
	for c4 in pool_all:
		if skip_bank or banked >= bm.MAX_ACTIVE:
			break
		if bm.accept_contract(str(c4["id"])):
			banked += 1
			banked_value += float(c4["reward_credits"])
	for c2 in bm.active_contracts:
		c2["completed"] = true
		c2["progress"] = c2.get("required", 1)

	var shards_before: int = int(wm.warp_shards)
	wm.execute_warp()
	var shards_after: int = int(wm.warp_shards)
	var post_credits: float = GameState.resources.get_currency("credits")

	# Everything below is the exploit: whatever is still open gets claimed AFTER the
	# baseline snapshot, and we ask what that alone made the fresh run worth.
	var left_open: int = bm.active_contracts.size()
	var before_lc: float = GameState.resources.lifetime_credits
	var ids: Array = []
	for c3 in bm.active_contracts:
		ids.append(str(c3["id"]))
	for cid in ids:
		bm.claim_contract(str(cid))
	var claimed: float = GameState.resources.lifetime_credits - before_lc
	return {
		"shards_before": shards_before, "shards_after": shards_after,
		"banked": banked, "left_open": left_open, "claimed": claimed,
		"free": wm.calculate_warp_gains(), "top_zone": top_zone,
		"post_credits": post_credits, "banked_value": banked_value,
	}


func _fmt(v: float) -> String:
	if v >= 1.0e9:
		return "%.2fB" % (v / 1.0e9)
	if v >= 1.0e6:
		return "%.2fM" % (v / 1.0e6)
	if v >= 1000.0:
		return "%.1fK" % (v / 1000.0)
	return "%.0f" % v


func _fail(msg: String) -> void:
	print("[BWARP] FAIL: %s" % msg)
	fails += 1
