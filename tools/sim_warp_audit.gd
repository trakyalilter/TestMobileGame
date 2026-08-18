extends SceneTree
## Audit of Warp and prestige — the system where a bug is least recoverable.
##
## Everything else can be re-earned in a session. A prestige bug destroys a run:
## shards that vanish, tree purchases that evaporate, a hard reset that leaks the
## previous playthrough's power into a "fresh" game, or the infinite-shard loop
## that desktop keeps an entire state variable around to prevent.
##
## So this EXERCISES a real warp cycle rather than reading the tables: warp, check
## what survived and what reset, warp again, hard reset, check again.

var errs: Array = []
var warns: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s: String) -> void: errs.append(s)
func W(s: String) -> void: warns.append(s)
func _chk(cond: bool, label: String, detail := "") -> void:
	if not cond:
		E("%s%s" % [label, ("  — " + detail) if detail != "" else ""])

func _run() -> void:
	var gs = root.get_node("GameState")
	var gd = root.get_node("GameData")

	# ---------- A. tree structure ----------
	var nodes := 0
	for nid in gs.TREE_NODES:
		nodes += 1
		var n: Dictionary = gs.TREE_NODES[nid]
		if int(n.get("cost", 0)) <= 0:
			E("tree node '%s' costs nothing" % nid)
		for p in n.get("prereq", []):
			if not gs.TREE_NODES.has(String(p)):
				E("tree node '%s' requires '%s' which does not exist" % [nid, p])
		if String(n.get("branch", "")) == "":
			E("tree node '%s' has no branch" % nid)
	# Every node must appear in exactly one branch order, or the UI never shows it.
	var listed := {}
	for br in gs.TREE_BRANCH_ORDER:
		for nid in gs.TREE_BRANCH_ORDER[br]:
			if not gs.TREE_NODES.has(String(nid)):
				E("branch '%s' lists node '%s' which does not exist" % [br, nid])
			if listed.has(String(nid)):
				E("node '%s' appears in more than one branch order" % nid)
			listed[String(nid)] = true
	for nid in gs.TREE_NODES:
		if not listed.has(String(nid)):
			E("node '%s' is in no branch order — unreachable in the UI" % nid)
	print("tree nodes: %d (all branch-listed)" % nodes)

	# ---------- B. purchase rules ----------
	gs.hard_reset()
	gs.total_warps = 5              # reveal every branch
	gs.warp_shards = 0.0
	gs.warp_shards_spent = 0.0
	var first := String(gs.TREE_BRANCH_ORDER["engineering"][0])
	_chk(not gs.can_purchase_node(first), "a node cannot be bought with zero shards")
	gs.warp_shards = 500.0
	_chk(gs.can_purchase_node(first), "an affordable, unblocked node can be bought")
	# A node behind an unmet prereq must stay locked.
	var blocked := ""
	for nid in gs.TREE_NODES:
		var pr: Array = (gs.TREE_NODES[nid] as Dictionary).get("prereq", [])
		if pr.size() > 0 and not gs.is_node_purchased(String(pr[0])):
			blocked = String(nid)
			break
	if blocked != "":
		_chk(not gs.can_purchase_node(blocked), "a node with an unmet prerequisite stays locked",
			"node=%s" % blocked)
	# Unimplemented nodes must never be purchasable.
	for nid in gs.TREE_NODES:
		if not bool((gs.TREE_NODES[nid] as Dictionary).get("implemented", true)):
			_chk(not gs.can_purchase_node(String(nid)),
				"unimplemented node '%s' is not purchasable" % nid)

	# ---------- C. spending accounting ----------
	var cost: int = gs.get_node_cost(first)
	var before_avail: float = gs.available_warp_shards()
	_chk(gs.purchase_tree_node(first), "purchase succeeds")
	_chk(gs.is_node_purchased(first), "the node registers as purchased")
	_chk(abs(gs.available_warp_shards() - (before_avail - cost)) < 0.001,
		"available shards drop by exactly the cost",
		"%.0f -> %.0f, cost %d" % [before_avail, gs.available_warp_shards(), cost])
	_chk(gs.warp_shards_spent <= gs.warp_shards, "spent never exceeds earned")
	_chk(gs.available_warp_shards() >= 0.0, "available shards never go negative")
	# A repeatable spine must get MORE expensive per level.
	for nid in gs.TREE_NODES:
		if not bool((gs.TREE_NODES[nid] as Dictionary).get("repeatable", false)):
			continue
		var c0: int = gs.get_node_cost(String(nid))
		gs.node_levels[nid] = int(gs.node_levels.get(nid, 0)) + 1
		var c1: int = gs.get_node_cost(String(nid))
		gs.node_levels[nid] = int(gs.node_levels[nid]) - 1
		_chk(c1 > c0, "spine '%s' costs more at the next level" % nid, "%d -> %d" % [c0, c1])

	# ---------- D. multipliers scale with shards and tier ----------
	gs.warp_shards = 0.0
	gs.total_warps = 0
	var base_prod: float = gs.warp_production_mult()
	gs.warp_shards = 100.0
	var with_shards: float = gs.warp_production_mult()
	_chk(with_shards > base_prod, "shards raise the production multiplier")
	gs.total_warps = 5              # one tier
	_chk(gs.warp_production_mult() > with_shards, "a warp tier raises it further")
	for f in [gs.warp_production_mult(), gs.warp_combat_mult(),
			gs.warp_gathering_mult(), gs.warp_xp_mult()]:
		_chk(f >= 1.0, "every warp multiplier is at least 1.0")

	# ---------- E. a real warp cycle ----------
	gs.hard_reset()
	gs.total_warps = 5
	gs.warp_shards = 200.0
	gs.warp_shards_spent = 0.0
	var node := String(gs.TREE_BRANCH_ORDER["engineering"][0])
	gs.purchase_tree_node(node)
	gs.skills["harvesting"] = 100000
	gs.resources["Fe"] = 5000
	gs.buildings["solar_panel"] = 3
	gs.unlocked_research["basic_engineering"] = true
	gs.lifetime_credits = 500_000_000
	gs.credits_at_warp_start = 0
	var shards_before: float = gs.warp_shards
	var spent_before: float = gs.warp_shards_spent
	var xp_before := int(gs.skills["harvesting"])
	var gained: int = gs.execute_warp()
	_chk(gained > 0, "a warp with a real score pays shards", "gained=%d" % gained)
	_chk(gs.warp_shards > shards_before, "earned shards increase")
	_chk(abs(gs.warp_shards_spent - spent_before) < 0.001, "spending is untouched by a warp")
	_chk(gs.is_node_purchased(node), "tree purchases SURVIVE the warp")
	_chk(gs.total_warps > 0, "the warp counter advances")
	_chk(bool(gs.unlocked_research.get("basic_engineering", false)),
		"research survives the warp")
	_chk(int(gs.skills["harvesting"]) < xp_before, "XP decays on warp")
	_chk(int(gs.skills["harvesting"]) > 0, "XP is not wiped entirely")
	var keep: float = float(gs.skills["harvesting"]) / float(xp_before)
	_chk(keep > 0.25 and keep < 0.60, "the XP kept is within the 30-55%% band",
		"kept=%.0f%%" % (keep * 100.0))
	_chk(int(gs.buildings.get("solar_panel", 0)) == 0 or gs.tree_blueprint_rebuild_frac() > 0.0,
		"buildings reset unless a rebuild node is owned")
	print("warp cycle: +%d shards, XP kept %.0f%%, buildings left %d, warps now %d"
		% [gained, keep * 100.0, int(gs.buildings.get("solar_panel", 0)), gs.total_warps])

	# ---------- F. the infinite-shard loop guard ----------
	# Desktop keeps credits_at_warp_start solely to stop this: without it the
	# shards just granted re-clear the threshold, so Warp re-enables instantly and
	# total_warps runs away into overflow.
	var immediate: int = gs.warp_gain_preview()
	_chk(immediate == 0, "warping again immediately pays nothing (loop guard holds)",
		"preview=%d" % immediate)
	_chk(gs.credits_at_warp_start == gs.lifetime_credits,
		"the warp baseline is re-anchored to lifetime credits")
	print("loop guard: immediate re-warp pays %d (baseline re-anchored at %d)"
		% [immediate, gs.credits_at_warp_start])

	# ---------- G. hard reset must leak nothing ----------
	# The documented bug class: a "new game" that inherits prestige power.
	gs.hard_reset()
	_chk(gs.warp_shards == 0.0, "hard reset clears earned shards", "%.0f" % gs.warp_shards)
	_chk(gs.warp_shards_spent == 0.0, "hard reset clears spent shards")
	_chk(gs.total_warps == 0, "hard reset clears the warp counter")
	_chk(gs.purchased_nodes.is_empty(), "hard reset clears tree purchases")
	_chk(gs.node_levels.is_empty(), "hard reset clears spine levels")
	_chk(gs.credits_at_warp_start == 0, "hard reset re-anchors the warp baseline")
	_chk(not bool(gs.cryo_unlocked), "hard reset re-locks the cryo unlock")
	for f in ["z11_unlocked", "z12_unlocked", "z13_unlocked", "z14_unlocked", "z15_unlocked"]:
		_chk(not bool(gs.game_flags.get(f, false)), "hard reset re-locks %s" % f)
	_chk(gs.equipped_relic == "", "hard reset clears the relic slot")
	_chk(is_equal_approx(gs.warp_production_mult(), 1.0),
		"every multiplier is back to 1.0 after a hard reset",
		"prod=%.3f" % gs.warp_production_mult())
	print("hard reset: shards %.0f, warps %d, nodes %d, prod mult %.2f"
		% [gs.warp_shards, gs.total_warps, gs.purchased_nodes.size(), gs.warp_production_mult()])

	# ---------- report ----------
	print("")
	if errs.is_empty():
		print("ERRORS: none")
	else:
		print("--- ERRORS (%d) ---" % errs.size())
		for e in errs:
			print("  x %s" % e)
	if not warns.is_empty():
		print("--- WARNINGS (%d) ---" % warns.size())
		for w in warns:
			print("  ! %s" % w)
	print("WARP_AUDIT: %s" % ("FAIL" if not errs.is_empty() else "PASS"))
	quit()
