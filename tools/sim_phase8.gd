extends SceneTree
## Phase 8 verification: Warp Mastery Tree + Standing Orders board + loadout
## presets + combat resist feedback. PASS/FAIL printed per gate.

var _pass := 0
var _fail := 0

func _ck(name: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else: _fail += 1
	print("[%s] %s%s" % ["PASS" if ok else "FAIL", name, ("  " + detail) if detail != "" else ""])

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var gs = root.get_node("GameState")
	gs.hard_reset()

	# ===== TASK 1: Warp Mastery Tree =====
	# Fresh game: no warps → engineering branch hidden, combat branch hidden.
	_ck("E-branch hidden at 0 warps", not gs.is_branch_revealed("engineering"))
	_ck("C-branch hidden at 0 warps", not gs.is_branch_revealed("combat"))
	_ck("combat node locked at 0 warps", not gs.can_purchase_node("CMB_1"))

	# Give the player warps + shards directly (isolate the tree from prestige math).
	gs.total_warps = 1
	gs.warp_shards = 10.0
	gs.warp_shards_spent = 0.0
	_ck("E-branch revealed at warp 1", gs.is_branch_revealed("engineering"))
	_ck("C-branch STILL hidden at warp 1", not gs.is_branch_revealed("combat"))
	_ck("CMB_1 locked until 2 warps", not gs.can_purchase_node("CMB_1"))
	_ck("available shards = earned - spent", gs.available_warp_shards() == 10.0)

	# Purchase ENG_1 (Yield Calibration, cost 1). v122 turned it from a +10%
	# multiplier into a FLAT +1 per gather, so it no longer moves yield_mult.
	var flat_before: int = gs.tree_gathering_flat()
	_ck("ENG_1 purchasable at warp 1", gs.can_purchase_node("ENG_1"))
	var bought: bool = gs.purchase_tree_node("ENG_1")
	_ck("ENG_1 purchase succeeds", bought)
	_ck("ENG_1 marked purchased", gs.is_node_purchased("ENG_1"))
	_ck("shards spent += cost", gs.warp_shards_spent == 1.0, "spent=%.0f" % gs.warp_shards_spent)
	_ck("available shards drop", gs.available_warp_shards() == 9.0)
	var flat_after: int = gs.tree_gathering_flat()
	_ck("ENG_1 grants a flat +1 gathering yield", flat_before == 0 and flat_after == 1,
		"%d -> %d" % [flat_before, flat_after])
	_ck("cannot re-buy ENG_1", not gs.can_purchase_node("ENG_1"))

	# Nodes are INDEPENDENT (no in-branch prereq chain — faithful to the ref).
	# E2 is buyable without owning E1 first; verify its processing-speed effect.
	_ck("ENG_2 purchasable (no chain gate)", gs.can_purchase_node("ENG_2"))
	var proc_before: float = gs.recipe_speed_mult("smelt_steel_basic")
	gs.purchase_tree_node("ENG_2")
	var proc_after: float = gs.recipe_speed_mult("smelt_steel_basic")
	_ck("ENG_2 raises processing speed", proc_after > proc_before + 0.001,
		"%.4f -> %.4f" % [proc_before, proc_after])
	# ENG_3 is implemented now (-1 input material per craft). The
	# unimplemented-refuses-purchase rule is checked against a node that really is
	# unimplemented, and ENG_3 is checked for its actual effect instead.
	var unimplemented := ""
	for nid in gs.TREE_NODES:
		if not bool((gs.TREE_NODES[nid] as Dictionary).get("implemented", true)):
			unimplemented = String(nid)
			break
	if unimplemented == "":
		_ck("an unimplemented node exists to check the refusal rule", false)
	else:
		_ck("%s (unimplemented) refuses purchase" % unimplemented,
			not gs.can_purchase_node(unimplemented))
	var inputs_before: Dictionary = gs.effective_craft_inputs({"Fe": 5, "Si": 3})
	gs.purchase_tree_node("ENG_3")
	var inputs_after: Dictionary = gs.effective_craft_inputs({"Fe": 5, "Si": 3})
	_ck("ENG_3 cuts one of each craft input",
		int(inputs_after["Fe"]) == int(inputs_before["Fe"]) - 1
		and int(inputs_after["Si"]) == int(inputs_before["Si"]) - 1,
		"Fe %d->%d, Si %d->%d" % [int(inputs_before["Fe"]), int(inputs_after["Fe"]),
			int(inputs_before["Si"]), int(inputs_after["Si"])])

	# Combat branch at 2 warps: HP + damage + cryo nodes fold into stats.
	gs.total_warps = 2
	gs.warp_shards = 30.0
	_ck("C-branch revealed at warp 2", gs.is_branch_revealed("combat"))
	# Equip a basic hull/weapon so stats are non-trivial.
	gs.module_inventory["z1_battery"] = 2
	gs.module_inventory["z1_kinetic"] = 1
	gs.equip_module("z1_battery")
	gs.equip_module("z1_battery")
	gs.equip_module("z1_kinetic")
	var hp_before: float = gs.combat_max_hp()
	var dps_before: float = gs.avg_player_dps()
	gs.purchase_tree_node("CMB_1")   # +10% hull HP
	gs.purchase_tree_node("CMB_2")   # +10% module damage
	var hp_after: float = gs.combat_max_hp()
	var dps_after: float = gs.avg_player_dps()
	_ck("CMB_1 raises hull HP", hp_after > hp_before + 0.5, "%.1f -> %.1f" % [hp_before, hp_after])
	_ck("CMB_2 raises weapon DPS", dps_after > dps_before + 0.001, "%.2f -> %.2f" % [dps_before, dps_after])
	# CMB_5 "Cryo Overcharge" was briefly shipped and then retired — desktop's v2
	# tree has no cryo amplifier. It must be absent from the tree, refunded out of
	# old saves, and its bonus must stay neutral. This block used to buy it.
	_ck("the retired cryo node is gone from the tree", not gs.TREE_NODES.has("CMB_5"))
	_ck("the retired cryo node cannot be bought", not gs.can_purchase_node("CMB_5"))
	_ck("cryo damage carries no tree amplifier", gs.tree_cryo_bonus() == 1.0,
		"%.3f" % gs.tree_cryo_bonus())
	# A save that still holds it is cleaned up and refunded on load.
	gs.purchased_nodes["CMB_5"] = true
	var spent_before_refund: float = gs.warp_shards_spent
	gs._refund_retired_nodes()
	_ck("an old save's retired node is removed", not gs.purchased_nodes.has("CMB_5"))
	_ck("and its shards are refunded", gs.warp_shards_spent < spent_before_refund,
		"%.0f -> %.0f" % [spent_before_refund, gs.warp_shards_spent])
	# The v1 ids still migrate, so a pre-v122 save keeps what it bought.
	gs.purchased_nodes["E1"] = true
	gs._migrate_v1_node_ids()
	_ck("pre-v122 node ids migrate (E1 -> ENG_1)",
		gs.is_node_purchased("ENG_1") and not gs.purchased_nodes.has("E1"))

	# Persistence across warp: purchased nodes survive execute_warp.
	gs.lifetime_credits = 600000000
	var warps_before: int = gs.total_warps
	gs.execute_warp()
	_ck("tree purchases persist across warp", gs.is_node_purchased("ENG_1") and gs.is_node_purchased("CMB_1"))
	_ck("warp increments total_warps", gs.total_warps == warps_before + 1)
	# Hard reset clears the tree.
	gs.hard_reset()
	_ck("hard_reset clears purchased nodes", gs.purchased_nodes.is_empty())
	_ck("hard_reset clears shards spent", gs.warp_shards_spent == 0.0)

	# ===== TASK 2: Standing Orders board =====
	gs.hard_reset()
	var board: Array = gs.standing_orders()
	# v168: one order per GOOD. A fresh game only has three tier-1 materials, so
	# the board legitimately opens short — desktop holds fewer orders rather than
	# offering the same good twice. Assert the real contract: never over the cap,
	# never empty, never a duplicate.
	_ck("board within cap", board.size() <= 6 and board.size() > 0, "size=%d" % board.size())
	var seen_targets := {}
	var dupes := false
	for q in board:
		if seen_targets.has(q["target"]):
			dupes = true
		seen_targets[q["target"]] = true
	_ck("board goods are unique", not dupes, "size=%d unique=%d" % [board.size(), seen_targets.size()])
	# Reroll cost = 2500 × max_diff.
	var maxd: int = gs.standing_max_diff()
	_ck("reroll cost = 2500 x max_diff", gs.standing_reroll_cost() == 2500 * maxd,
		"cost=%d maxd=%d" % [gs.standing_reroll_cost(), maxd])
	# Force a gather order we can complete: inject a small gather order.
	var sym := "Fe"
	var inj := {
		"id": "test_gather", "type": "gather", "title": "Stockpile: Iron",
		"desc": "test", "target": sym, "target_qty": 10, "current_qty": 0,
		"reward_credits": 1000, "reward_material": {"id": "Cu", "qty": 50},
		"difficulty": 1, "completed": false, "claimed": false,
	}
	gs.standing_board[0] = inj
	# Gather progress syncs on resource gain.
	gs.add_resource(sym, 4)
	_ck("gather order progresses on resource gain", int(gs.standing_board[0]["current_qty"]) == 4,
		"cur=%d" % int(gs.standing_board[0]["current_qty"]))
	gs.add_resource(sym, 10)   # overshoot — should cap + complete
	_ck("gather order completes at target", gs.standing_board[0].get("completed", false))
	_ck("gather progress caps at target", int(gs.standing_board[0]["current_qty"]) == 10)
	# Claim grants the material reward + credits and auto-replaces the slot.
	var cu_before: int = gs.amount("Cu")
	var cred_before: int = gs.credits
	var ok_claim: bool = gs.claim_standing_order(0)
	_ck("claim succeeds when complete", ok_claim)
	_ck("claim grants material reward", gs.amount("Cu") == cu_before + 50, "Cu %d -> %d" % [cu_before, gs.amount("Cu")])
	_ck("claim grants credits", gs.credits > cred_before)
	_ck("board refills after claim", gs.standing_orders().size() > 0 and gs.standing_orders().size() <= 6)
	_ck("claimed order removed (slot 0 differs)", gs.standing_board[0].get("id", "") != "test_gather")
	# Hunt progress on kill.
	var hunt := {
		"id": "test_hunt", "type": "hunt", "title": "Sweep: Drone",
		"desc": "test", "target": "z1_lunar_drone", "target_qty": 5, "current_qty": 0,
		"reward_credits": 500, "reward_material": {}, "difficulty": 1,
		"completed": false, "claimed": false,
	}
	gs.standing_board[1] = hunt
	gs.standing_on_kill("z1_lunar_drone")
	_ck("hunt order increments on kill", int(gs.standing_board[1]["current_qty"]) == 1)
	# Reroll: keeps completed-unclaimed, rerolls rest, charges credits.
	gs.credits = 9_999_999
	var rcost: int = gs.standing_reroll_cost()
	var cr_before: int = gs.credits
	var ok_reroll: bool = gs.reroll_standing_orders()
	_ck("reroll succeeds with credits", ok_reroll)
	_ck("reroll charges cost", gs.credits == cr_before - rcost, "%d - %d = %d" % [cr_before, rcost, gs.credits])
	_ck("reroll refills the board", gs.standing_orders().size() > 0 and gs.standing_orders().size() <= 6)

	# Persistence: standing board survives a save/load round-trip.
	gs.save_game()
	var board_n: int = gs.standing_orders().size()
	gs.load_game()
	_ck("standing board persists save/load", gs.standing_orders().size() == board_n)

	# ===== TASK 3: Loadout presets (engine already Phase-7 verified; sanity) =====
	gs.hard_reset()
	# Battery first so capacity exists, then armor (which draws energy).
	gs.module_inventory["z1_battery"] = 1
	gs.module_inventory["z1_armor"] = 1
	gs.equip_module("z1_battery")
	var eq_ok: bool = gs.equip_module("z1_armor")
	_ck("test module equips", eq_ok and not gs.loadout.is_empty())
	# Slot 2, not slot 1: under v134g the active slot mirrors live edits, so it is
	# already filled by the equips above — "empty initially" could never hold.
	_ck("preset slot 2 empty initially", gs.is_loadout_preset_empty(2))
	gs.save_loadout_preset(2)
	_ck("preset slot 2 filled after save", not gs.is_loadout_preset_empty(2))
	if not gs.loadout.is_empty():
		gs.unequip_slot(gs.loadout.keys()[0])
	var res = gs.load_loadout_preset(2)
	_ck("load_loadout_preset restores a module", int(res.get("loaded", 0)) >= 1)
	gs.clear_loadout_preset(2)
	_ck("clear_loadout_preset empties slot", gs.is_loadout_preset_empty(2))

	print("\nPhase 8: %d passed, %d failed" % [_pass, _fail])
	if _fail > 0:
		quit(1)
	quit()
