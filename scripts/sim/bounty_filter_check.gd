extends Node
# ============================================================================
# BOUNTY REWARD FILTER CHECK (v176)
#
# The zone bounty board is the game's stated deterministic bridge over drop RNG
# — m030d's mission text tells the player so: "hunt contracts pay a GUARANTEED
# Rare module on claim". Until v176 it was deterministic on RARITY ONLY. The
# base module came from `pool[randi() % pool.size()]`, a uniform pick that
# ignored the player's loot filters, while ordinary drops have respected them
# since v135a.
#
# That mattered because the wall the board exists to bridge is a TYPE wall: a
# Zone-N boss demands a weak-type Rare set, and farming one off trash is
# ~0.2%/kill (~470 kills, measured v175). A board that ignores the filter is not
# a bridge, it is another lottery ticket.
#
# What is checked, by CLAIMING REAL CONTRACTS through claim_contract():
#   1. with a weapon-damage-type filter set, every awarded WEAPON is that type
#   2. with a slot-type filter set, awarded modules are that slot type
#   3. an over-narrow filter still pays out (fallback), never nothing
#   4. batteries are never awarded (MODULE_DROP_WEIGHTS weight 0)
#   5. the Rare+ floor still holds — this must not have been traded away
#
#   Godot --headless --path <root> res://scenes/bounty_filter_check.tscn
# ============================================================================

const TRIALS := 60

var _fails: Array = []

func _ready() -> void:
	await get_tree().process_frame
	if not GameState.sim_mode:
		print("[BFILT] ABORT: sim_mode false — refusing to run (this probe hard_resets).")
		get_tree().quit(1)
		return
	GameState.set_process(false)
	print("[BFILT] ============ BOUNTY REWARD FILTER CHECK ============")
	print("[BFILT] claims %d real contracts per case through claim_contract()." % TRIALS)

	_case_weapon_type()
	_case_slot_type()
	_case_over_narrow()
	_case_rarity_floor()

	print("[BFILT] ---------------------------------------------------")
	for f in _fails:
		print("[BFILT] FAIL: %s" % f)
	print("[BFILT] RESULT: %s (%d failure(s))" % ["PASS" if _fails.is_empty() else "FAIL", _fails.size()])
	get_tree().quit(0 if _fails.is_empty() else 1)

func _fail(msg: String) -> void:
	_fails.append(msg)

# Deal a contract and claim it, returning the module ids the claim produced.
# Goes through the REAL claim path — a probe that called generate_module_drop
# itself would keep passing after claim_contract stopped filtering.
func _claim_awards(n: int) -> Array:
	var sm = GameState.shipyard_manager
	var bm = GameState.bounty_manager
	var out: Array = []
	for _i in range(n):
		var before: Dictionary = sm.module_inventory.duplicate()
		var c := _make_contract(bm)
		if c.is_empty():
			continue
		bm.claim_contract(str(c["id"]))
		for mid in sm.module_inventory:
			var gained: int = int(sm.module_inventory[mid]) - int(before.get(mid, 0))
			if gained > 0:
				out.append(str(mid))
	return out

# Build a completed contract on a zone whose pool spans several slot types and
# all three conventional damage types, then hand it to the real claim path.
func _make_contract(bm) -> Dictionary:
	var cm = GameState.combat_manager
	var pool: Array = []
	for eid in cm.enemy_db:
		var e: Dictionary = cm.enemy_db[eid]
		if int(e.get("zone", 0)) != 5:
			continue
		for m in e.get("module_drop_pool", []):
			if not str(m) in pool:
				pool.append(str(m))
	if pool.is_empty():
		return {}
	var c := {
		"id": "sim_%d" % bm.active_contracts.size(),
		"completed": true, "claimed": false, "difficulty": 5,
		"reward_credits": 0, "reward_module_pool": pool,
		"target": "z5_xenon_scout", "zone_id": "sector_alpha",
		"progress": 1, "required": 1,
	}
	bm.active_contracts.append(c)
	return c

func _setup(weapon_types: Dictionary, slot_types: Dictionary) -> void:
	GameState.hard_reset()
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	# Unlock through Zone 5 so the pool's research gate is not what is being measured.
	for tid in rm.tech_tree:
		if int(rm.tech_tree[tid].get("tier", 99)) <= 5 and not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)
	for k in weapon_types:
		cm.loot_weapon_type_filter[k] = bool(weapon_types[k])
	for k2 in slot_types:
		cm.loot_type_filter[k2] = bool(slot_types[k2])

# ---- 1. weapon damage-type filter ----------------------------------------
func _case_weapon_type() -> void:
	_setup({"kinetic": false, "energy": true, "explosive": false, "cryo": false}, {})
	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager
	var awards := _claim_awards(TRIALS)
	if awards.is_empty():
		_fail("weapon-type case awarded NOTHING across %d claims" % TRIALS)
		return
	var weapons := 0
	var wrong := 0
	for mid in awards:
		var d: Dictionary = sm.modules.get(str(mid), {})
		if str(d.get("slot_type", "")) != "weapon":
			continue
		weapons += 1
		if str(cm._weapon_dmg_type(str(mid))) != "energy":
			wrong += 1
	if weapons == 0:
		_fail("weapon-type case awarded %d module(s) but not one WEAPON — the filter should concentrate the pool, not empty it" % awards.size())
	if wrong > 0:
		_fail("%d of %d awarded weapons were not ENERGY despite the filter — the board still ignores loot_weapon_type_filter" % [wrong, weapons])
	print("[BFILT] weapon-type filter (energy only): %d award(s), %d weapon(s), %d off-type" % [awards.size(), weapons, wrong])

# ---- 2. slot-type filter --------------------------------------------------
func _case_slot_type() -> void:
	_setup({}, {"weapon": true, "shield": false, "armor": false, "sensor": false, "engine": false})
	var sm = GameState.shipyard_manager
	var awards := _claim_awards(TRIALS)
	if awards.is_empty():
		_fail("slot-type case awarded NOTHING across %d claims" % TRIALS)
		return
	var off := 0
	for mid in awards:
		if str((sm.modules.get(str(mid), {}) as Dictionary).get("slot_type", "")) != "weapon":
			off += 1
	if off > 0:
		_fail("%d of %d awards were not WEAPONS despite a weapon-only slot filter" % [off, awards.size()])
	# 4. batteries are weight 0 in MODULE_DROP_WEIGHTS and must never be awarded.
	var batteries := 0
	for mid2 in awards:
		if str((sm.modules.get(str(mid2), {}) as Dictionary).get("slot_type", "")) == "battery":
			batteries += 1
	if batteries > 0:
		_fail("%d batteries awarded — live drops exclude them (weight 0) and the board must match" % batteries)
	print("[BFILT] slot-type filter (weapon only): %d award(s), %d off-slot, %d batteries" % [awards.size(), off, batteries])

# ---- 3. an over-narrow filter must still pay ------------------------------
func _case_over_narrow() -> void:
	# Cryo is not in any Zone-5 pool, so this filter matches NOTHING. The shared
	# helper's fallback must keep the claim paying rather than silently voiding
	# the reward — a bounty that pays nothing is worse than one that pays wrong.
	_setup({"kinetic": false, "energy": false, "explosive": false, "cryo": true}, {})
	var awards := _claim_awards(20)
	if awards.is_empty():
		_fail("an over-narrow filter voided the reward entirely — _focused_drop_pool's fallback is not reaching the board")
	print("[BFILT] over-narrow filter still pays: %d award(s) from 20 claims" % awards.size())

# ---- 5. the Rare+ floor survives -----------------------------------------
func _case_rarity_floor() -> void:
	_setup({}, {})
	var sm = GameState.shipyard_manager
	var awards := _claim_awards(TRIALS)
	var below := 0
	for mid in awards:
		if int(sm.get_module_rarity(str(mid))) < sm.Rarity.RARE:
			below += 1
	if awards.is_empty():
		_fail("rarity-floor case awarded nothing")
	if below > 0:
		_fail("%d of %d awards were below RARE — the guaranteed floor was traded away" % [below, awards.size()])
	print("[BFILT] Rare+ floor: %d award(s), %d below Rare" % [awards.size(), below])
