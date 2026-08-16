extends Node
# ============================================================================
# FLEET SYSTEM CHECK (v177 audit)  — docs/FLEET_SIEGE_GATES.md
#
# The fleet system had NO guard: its three load-bearing invariants (roster
# persists across warp, clears on hard reset, +25%/ship capped at +100%) were
# held by omission — execute_warp simply never touches fleet_manager, which is
# exactly the shape of bug the hard-reset/vault history keeps producing.
#
# What is checked, against real code paths:
#   1. every FLEET_HULLS cost element exists in ElementDB (typo guard)
#   2. dps mult: 0 ships = 1.0, 4 ships = 2.0, capped at 2.0 beyond, and a
#      cruiser contributes EXACTLY what a frigate does (measuring, not assuming,
#      the dominance question)
#   3. build_ship deducts exactly the cost; refuses over-capacity and
#      unaffordable builds with NO partial deduction; scrap refunds nothing
#   4. the bonus lands in a REAL fight: mean boss TTK with a 4-ship fleet is
#      ~half the fleetless TTK (same kit, same warp state, only ships differ)
#   5. roster survives execute_warp(); capacity grows by 1
#   6. hard_reset() clears the roster
#   7. MEASURED, not asserted: the offline model's TTK with and without the
#      fleet — documents whether the fleet exists offline (audit finding)
#
#   Godot --headless --path <root> res://scenes/fleet_check.tscn
# ============================================================================

const DT := 0.1
const MAXT := 300.0
const TRIALS := 7

var _fails: Array = []

func _ready() -> void:
	await get_tree().process_frame
	if not GameState.sim_mode:
		print("[FLEET] ABORT: sim_mode false — refusing to run (this probe warps and hard-resets).")
		get_tree().quit(1)
		return
	GameState.set_process(false)
	print("[FLEET] ============ FLEET SYSTEM CHECK ============")

	_check_costs_exist()
	_check_mult_math()
	_check_build_economy()
	_check_combat_effect()
	_check_warp_persistence()
	_check_hard_reset()

	print("[FLEET] --------------------------------------------")
	for f in _fails:
		print("[FLEET] FAIL: %s" % f)
	print("[FLEET] RESULT: %s (%d failure(s))" % ["PASS" if _fails.is_empty() else "FAIL", _fails.size()])
	get_tree().quit(0 if _fails.is_empty() else 1)

func _fail(msg: String) -> void:
	_fails.append(msg)

func _grant_cost(cost: Dictionary, times: int = 1) -> void:
	for res in cost:
		GameState.resources.add_element(str(res), float(cost[res]) * float(times))

func _build_n(hull: String, n: int) -> int:
	var fm = GameState.fleet_manager
	var built := 0
	for _i in range(n):
		_grant_cost(fm.get_hull_cost(hull))
		if fm.build_ship(hull):
			built += 1
	return built

# ---- 1. cost elements exist ----------------------------------------------
func _check_costs_exist() -> void:
	var fm = GameState.fleet_manager
	var bad := 0
	for hid in fm.FLEET_HULLS:
		for res in fm.FLEET_HULLS[hid].get("cost", {}):
			if not ElementDB.ELEMENT_NAMES.has(str(res)):
				_fail("%s cost element '%s' is not in ElementDB — the bill can never be paid" % [str(hid), str(res)])
				bad += 1
	print("[FLEET] cost elements: %s" % ("all exist" if bad == 0 else "%d unknown" % bad))

# ---- 2. multiplier math ---------------------------------------------------
func _check_mult_math() -> void:
	var fm = GameState.fleet_manager
	var wm = GameState.warp_manager
	GameState.hard_reset()
	wm.total_warps = 9   # capacity 10 — room for every case below

	if absf(float(fm.get_combat_dps_mult()) - 1.0) > 0.0001:
		_fail("empty fleet mult is %.3f, expected 1.0" % float(fm.get_combat_dps_mult()))
	_build_n("fleet_frigate", 4)
	var four: float = float(fm.get_combat_dps_mult())
	if absf(four - 2.0) > 0.0001:
		_fail("4-ship mult is %.3f, expected 2.0" % four)
	_build_n("fleet_frigate", 3)
	var seven: float = float(fm.get_combat_dps_mult())
	if absf(seven - 2.0) > 0.0001:
		_fail("7-ship mult is %.3f — the +100%% cap is not holding" % seven)

	# Dominance measurement: replace one frigate with a cruiser; the live bonus
	# must not move, because it counts SHIPS. This pins the audit's central
	# design finding as a fact rather than a reading.
	fm.ships = []
	_build_n("fleet_cruiser", 1)
	_build_n("fleet_frigate", 3)
	var mixed: float = float(fm.get_combat_dps_mult())
	if absf(mixed - four) > 0.0001:
		_fail("cruiser+3 frigates mult %.3f != 4 frigates %.3f — update the dominance finding" % [mixed, four])
	print("[FLEET] mult: empty 1.0, four 2.0, capped %.2f, cruiser==frigate per ship: %s" % [
		seven, "CONFIRMED" if absf(mixed - four) <= 0.0001 else "NO"])

# ---- 3. build/scrap economy ----------------------------------------------
func _check_build_economy() -> void:
	var fm = GameState.fleet_manager
	var wm = GameState.warp_manager
	var res = GameState.resources
	GameState.hard_reset()
	wm.total_warps = 1   # capacity 2

	var cost: Dictionary = fm.get_hull_cost("fleet_frigate")
	_grant_cost(cost)
	var before := {}
	for r in cost:
		before[str(r)] = float(res.get_element_amount(str(r)))
	if not fm.build_ship("fleet_frigate"):
		_fail("build_ship refused with exact materials granted")
		return
	for r2 in cost:
		var left: float = float(res.get_element_amount(str(r2)))
		var want: float = float(before[str(r2)]) - float(cost[r2])
		if absf(left - want) > 0.01:
			_fail("build deducted %s to %.0f, expected %.0f" % [str(r2), left, want])

	# Unaffordable: refuse, and deduct NOTHING (no partial payment).
	var snap := {}
	for r3 in cost:
		snap[str(r3)] = float(res.get_element_amount(str(r3)))
	if fm.build_ship("fleet_frigate") and float(res.get_element_amount("Water")) < float(cost.get("Water", 0)):
		_fail("build_ship succeeded without materials")
	for r4 in cost:
		if absf(float(res.get_element_amount(str(r4))) - float(snap[str(r4)])) > 0.01:
			_fail("failed build still deducted %s" % str(r4))

	# Capacity: fill to cap (2), then a funded build must refuse.
	_build_n("fleet_frigate", 1)
	_grant_cost(cost)
	if fm.build_ship("fleet_frigate"):
		_fail("build_ship exceeded capacity %d" % int(fm.get_fleet_capacity()))

	# Scrap: slot freed, nothing refunded.
	var w_before: float = float(res.get_element_amount("Water"))
	var n_before: int = int(fm.get_fleet_count())
	fm.scrap_ship(0)
	if int(fm.get_fleet_count()) != n_before - 1:
		_fail("scrap_ship did not remove a ship")
	if absf(float(res.get_element_amount("Water")) - w_before) > 0.01:
		_fail("scrap_ship refunded materials — the sink is supposed to be one-way")
	print("[FLEET] build/scrap economy: exact deduction, no partial pay, cap enforced, no refund")

# ---- 4. the bonus lands in a real fight -----------------------------------
func _check_combat_effect() -> void:
	var with_fleet := _ttk_trials(true)
	var without := _ttk_trials(false)
	var wf: float = float(with_fleet.get("mean", 0.0))
	var wo: float = float(without.get("mean", 0.0))
	var w1: int = int(with_fleet.get("wins", 0))
	var w0: int = int(without.get("wins", 0))
	if w1 < TRIALS - 1 or w0 < TRIALS - 1:
		_fail("combat trials unreliable (wins %d/%d fleet, %d/%d bare) — kit setup broken, TTK ratio meaningless" % [w1, TRIALS, w0, TRIALS])
		return
	var ratio: float = wo / maxf(0.001, wf)
	# +100% damage does not halve TTK exactly (overkill, shield phase, crits) —
	# accept a wide band; the effect under test is 2x, far above trial noise.
	if ratio < 1.5 or ratio > 2.8:
		_fail("fleet TTK effect off-spec: bare %.1fs / fleet %.1fs = x%.2f, expected ~x2 in [1.5, 2.8]" % [wo, wf, ratio])
	print("[FLEET] combat effect: bare %.1fs -> fleet %.1fs (x%.2f speedup, %d+%d wins)" % [wo, wf, ratio, w0, w1])

	# ---- 7. offline model, MEASURED (finding, not assertion) --------------
	# ONE kit, measured twice — fleetless, then with 4 frigates built onto the
	# SAME ship mid-measurement. The first cut of this case set up two fights
	# independently, so each rolled its own Rare weapons, and 3s of roll variance
	# crossed a naive >0.5s threshold and printed "IS PRICED" — in the WRONG
	# direction (fleet read slower). If the fleet were priced the ratio would be
	# ~2x, not 4%. Same-kit makes the answer exact: equal = does not exist.
	_setup_fight(false)
	var cm = GameState.combat_manager
	var fm = GameState.fleet_manager
	cm._offline_winnable()
	var off_bare: float = float(cm._offline_ttk)
	_build_n("fleet_frigate", 4)
	var mult_now: float = float(fm.get_combat_dps_mult())
	cm._offline_winnable()
	var off_fleet: float = float(cm._offline_ttk)
	print("[FLEET] MEASURED offline model (same kit): bare %.1fs -> fleet(x%.2f online) %.1fs -> fleet %s offline" % [
		off_bare, mult_now, off_fleet,
		"IS PRICED" if off_fleet < off_bare * 0.75 else "DOES NOT EXIST"])

# Build the standard Z1 kit (mirrors boss_gearcheck: rare weapons, legendary
# batteries, ammo + kits) and enter the Architect fight. fleet=true adds 4
# frigates at warp state 3; fleet=false keeps the SAME warp state, zero ships.
func _setup_fight(fleet: bool) -> void:
	GameState.hard_reset()
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var wm = GameState.warp_manager
	wm.total_warps = 3   # capacity 4; tier floor(3/5)=0 and 0 shards — combat mult unchanged
	# Unlock research BEFORE equipping: equip_module routes through
	# can_equip_module, and a refused module fails SILENTLY here (silent=true),
	# leaving the ship unarmed. First run of this probe lost 14/14 fights in both
	# configs for exactly this reason — boss_gearcheck unlocks first, this didn't.
	var rm = GameState.research_manager
	for tid in rm.tech_tree:
		if not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)
	if fleet:
		_build_n("fleet_frigate", 4)
	for i in _slots(sm, "battery"):
		var bid := str(sm.generate_module_drop("z1_battery", 3, 1))
		if bid != "":
			sm.equip_module(i, bid, true)
	for i2 in _slots(sm, "weapon"):
		var widd := str(sm.generate_module_drop("z1_kinetic", 2, 1))
		if widd != "":
			sm.equip_module(i2, widd, true)
	# Armor + shield too — the first cut equipped weapons only and the bare
	# corvette died before the kill in BOTH configs (0/14), which reads exactly
	# like a wiring failure. boss_gearcheck's kit fills these; match it.
	for i2b in _slots(sm, "armor"):
		var aid := str(sm.generate_module_drop("z1_armor", 2, 1))
		if aid != "":
			sm.equip_module(i2b, aid, true)
	for i2c in _slots(sm, "shield"):
		var sid := str(sm.generate_module_drop("z1_shield", 2, 1))
		if sid != "":
			sm.equip_module(i2c, sid, true)
	GameState.resources.add_element("SlugT1", 1000000)
	for i3 in _slots(sm, "weapon"):
		sm.ammo_loadout[i3] = "SlugT1"
	GameState.resources.add_element("EmergencyPatch", 100000)
	GameState.resources.add_element("BasicBooster", 100000)
	sm.equip_consumable("hull", "EmergencyPatch")
	sm.equip_consumable("shield", "BasicBooster")
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	var boss := ""
	var zid := ""
	for z in cm.zones:
		for eid in cm.zones[z].get("enemies", []):
			if int(cm.enemy_db.get(str(eid), {}).get("zone", 0)) == 1 \
					and bool(cm.enemy_db.get(str(eid), {}).get("is_boss", false)):
				boss = str(eid)
				zid = str(z)
	cm.boss_kills.clear()
	cm.start_expedition(zid)
	cm.set_target_enemy(boss)

func _ttk_trials(fleet: bool) -> Dictionary:
	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager
	var wins := 0
	var ttks: Array = []
	for _i in range(TRIALS):
		_setup_fight(fleet)
		var boss_id := str(cm.current_enemy.get("id", "")) if cm.current_enemy else ""
		if boss_id == "":
			continue
		var t := 0.0
		while t < MAXT:
			if cm.consumable_cooldown <= 0.0:
				if sm.current_hp < sm.max_hp * 0.5 and sm.consumable_hull_slot != "":
					cm.use_manual_consumable("hull")
				elif cm.player_max_shield > 0 and cm.player_shield < cm.player_max_shield * 0.5 \
						and sm.consumable_shield_slot != "":
					cm.use_manual_consumable("shield")
			cm.process_tick(DT)
			t += DT
			if int(cm.boss_kills.get(boss_id, 0)) > 0:
				wins += 1
				ttks.append(t)
				break
			if sm.current_hp <= 0 or not cm.in_combat:
				break
	var mean := 0.0
	for v in ttks:
		mean += float(v)
	mean = (mean / float(ttks.size())) if ttks.size() > 0 else 0.0
	return {"wins": wins, "mean": mean}

func _slots(sm, stype: String) -> Array:
	var out: Array = []
	var slots: Array = sm.hulls.get(sm.active_hull, {}).get("slots", [])
	for i in range(slots.size()):
		if str(slots[i]) == stype:
			out.append(i)
	return out

# ---- 5. warp persistence --------------------------------------------------
func _check_warp_persistence() -> void:
	var fm = GameState.fleet_manager
	var wm = GameState.warp_manager
	GameState.hard_reset()
	wm.total_warps = 1
	_build_n("fleet_frigate", 2)
	var before: Array = fm.ships.duplicate(true)
	var cap_before: int = int(fm.get_fleet_capacity())
	GameState.resources.lifetime_credits = 50_000_000.0
	var warps_before: int = int(wm.total_warps)
	wm.execute_warp()
	if int(wm.total_warps) <= warps_before:
		_fail("execute_warp did not fire — persistence case is vacuous")
		return
	if fm.ships.size() != before.size():
		_fail("roster changed across warp: %d -> %d ships (design: fleet PERSISTS)" % [before.size(), fm.ships.size()])
	if int(fm.get_fleet_capacity()) != cap_before + 1:
		_fail("capacity did not grow with the warp: %d -> %d" % [cap_before, int(fm.get_fleet_capacity())])
	print("[FLEET] warp persistence: %d ships held, capacity %d -> %d" % [
		fm.ships.size(), cap_before, int(fm.get_fleet_capacity())])

# ---- 6. hard reset clears -------------------------------------------------
func _check_hard_reset() -> void:
	var fm = GameState.fleet_manager
	var wm = GameState.warp_manager
	wm.total_warps = 1
	if fm.get_fleet_count() == 0:
		_build_n("fleet_frigate", 1)
	GameState.hard_reset()
	if fm.get_fleet_count() != 0:
		_fail("hard_reset left %d ship(s) — a NEW GAME starts with a fleet" % int(fm.get_fleet_count()))
	print("[FLEET] hard reset clears roster: OK")
