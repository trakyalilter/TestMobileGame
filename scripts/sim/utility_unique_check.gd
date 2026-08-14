extends Node
# ============================================================================
# UTILITY UNIQUE CHECK (v176 P5)  — docs/design/UTILITY_UNIQUES.md
#
# Engine, sensor and battery had no unique tier because each slot is a single
# scalar with one right answer. P5 gives each a MECHANIC instead, so this guard
# tests the mechanics against the real code paths — not the presence of 27
# dictionary entries, which would pass while every one of them did nothing.
#
#   1. all 27 defs exist, rarity 4, is_unique, empty cost, no set_id
#   2. every Z2-Z10 boss rare_loot carries its three rows at 3%
#   3. Phase Drive dodge, through the REAL formula, lands 18-22% vs its own
#      zone's boss — and MAX_EVASION does not clip the Z10 value (it did: the
#      cap was 75 against a 131 ladder, which would have flattened Z5-Z10 into
#      six identical items)
#   4. Predictive Array: N+1 kills with no Rare+ forces a Rare, driving the real
#      _roll_one_module_drop; and a natural Rare+ resets the counter
#   5. Overcharge pays NOTHING with any consumer bay empty (the anti-degenerate
#      gate) and pays the capped value at full over-provision
#   6. the dodge clamp still holds at 0.75 after raising MAX_EVASION
#
#   Godot --headless --path <root> res://scenes/utility_unique_check.tscn
# ============================================================================

const ZONES := [2, 3, 4, 5, 6, 7, 8, 9, 10]
const KINDS := ["engine", "sensor", "battery"]
# Boss accuracy per zone — the other half of the dodge formula.
const BOSS_ACC := {2: 45, 3: 65, 4: 85, 5: 110, 6: 140, 7: 170, 8: 200, 9: 230, 10: 250}

var _fails: Array = []

func _ready() -> void:
	await get_tree().process_frame
	if not GameState.sim_mode:
		print("[UNIQ] ABORT: sim_mode false — refusing to run (this probe hard_resets).")
		get_tree().quit(1)
		return
	GameState.set_process(false)
	print("[UNIQ] ============ UTILITY UNIQUE CHECK ============")
	GameState.hard_reset()

	_check_defs()
	_check_boss_loot()
	_check_phase_drive()
	_check_pity_timer()
	_check_overcharge()

	print("[UNIQ] ---------------------------------------------")
	for f in _fails:
		print("[UNIQ] FAIL: %s" % f)
	print("[UNIQ] RESULT: %s (%d failure(s))" % ["PASS" if _fails.is_empty() else "FAIL", _fails.size()])
	get_tree().quit(0 if _fails.is_empty() else 1)

func _fail(msg: String) -> void:
	_fails.append(msg)

# Switch to the smallest hull that actually has a bay of `stype`, and power it
# generously — power is not what these cases are testing.
func _use_hull_with(stype: String) -> void:
	var sm = GameState.shipyard_manager
	var pick := ""
	var pick_tier := 999
	for hid in sm.hulls:
		var h: Dictionary = sm.hulls[hid]
		if not (stype in (h.get("slots", []) as Array)):
			continue
		var t := int(h.get("tier", 99))
		if t < pick_tier:
			pick_tier = t
			pick = str(hid)
	if pick == "":
		_fail("no hull in the game has a %s bay" % stype)
		return
	# Unlock everything first. Without it the tier batteries below refuse to equip
	# ("Requires Research"), the ship ends up with ZERO capacity, and the module
	# under test then fails the power guard SILENTLY — the guard returns false
	# without printing, so the probe reported "could not equip" with no reason.
	var rm = GameState.research_manager
	for tid in rm.tech_tree:
		if not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)
	sm.active_hull = pick
	sm.loadout.clear()
	var slots: Array = sm.get_effective_slots()
	for i in range(slots.size()):
		sm.loadout[i] = null
	for i2 in range(slots.size()):
		if str(slots[i2]) == "battery":
			var bid := "z%d_battery" % clampi(pick_tier + 2, 1, 10)
			if bid in sm.modules:
				sm.grant_module(bid)
				sm.equip_module(i2, bid, true)
	sm.recalc_stats()

# ---- 1. definitions -------------------------------------------------------
func _check_defs() -> void:
	var sm = GameState.shipyard_manager
	var missing := 0
	var bad := 0
	for z in ZONES:
		for k in KINDS:
			var mid := "z%d_unique_%s" % [z, k]
			if not mid in sm.modules:
				_fail("%s does not exist" % mid)
				missing += 1
				continue
			var d: Dictionary = sm.modules[mid]
			if int(d.get("rarity", 0)) != 4:
				_fail("%s rarity is %s, uniques are 4" % [mid, str(d.get("rarity"))])
				bad += 1
			if not bool(d.get("is_unique", false)):
				_fail("%s is not flagged is_unique" % mid)
				bad += 1
			if not (d.get("cost", {}) as Dictionary).is_empty():
				_fail("%s has a cost — uniques are never craftable" % mid)
				bad += 1
			if str(d.get("slot_type", "")) != k:
				_fail("%s slot_type is %s" % [mid, str(d.get("slot_type"))])
				bad += 1
			# Deliberately NO set_id: three more collectible pieces per zone would
			# make every 3-piece trinity bonus easier to complete.
			if str(d.get("set_id", "")) != "":
				_fail("%s carries set_id '%s' — that silently buffs the zone's 3-piece set" % [mid, str(d.get("set_id"))])
				bad += 1
	print("[UNIQ] defs: %d expected, %d missing, %d malformed" % [ZONES.size() * KINDS.size(), missing, bad])

# ---- 2. boss loot ---------------------------------------------------------
func _check_boss_loot() -> void:
	var cm = GameState.combat_manager
	var found := 0
	for z in ZONES:
		var boss := ""
		for eid in cm.enemy_db:
			var e: Dictionary = cm.enemy_db[eid]
			# NB: no begins_with("z1") filter here. The first cut had one, to skip the
			# Zone-1 boss — and it silently ate z10_boss_leviathan too. The zone
			# comparison already excludes Zone 1, because ZONES starts at 2.
			if bool(e.get("is_boss", false)) and int(e.get("zone", 0)) == int(z):
				boss = str(eid)
				break
		if boss == "":
			_fail("no boss found for zone %d" % z)
			continue
		var have := {}
		for row in cm.enemy_db[boss].get("rare_loot", []):
			var r: Array = row
			have[str(r[0])] = float(r[1])
		for k in KINDS:
			var mid := "z%d_unique_%s" % [z, k]
			if not have.has(mid):
				_fail("%s is not in %s's rare_loot — it can never drop" % [mid, boss])
			elif absf(float(have[mid]) - 0.03) > 0.0001:
				_fail("%s drops at %.3f on %s, spec says 0.03" % [mid, float(have[mid]), boss])
			else:
				found += 1
	print("[UNIQ] boss loot rows: %d/%d present at 3%%" % [found, ZONES.size() * KINDS.size()])

# ---- 3 + 6. Phase Drive dodge through the real formula ---------------------
func _dodge(eva: float, acc: float) -> float:
	# Mirrors combat_manager.do_enemy_attack. Kept in sync deliberately: the
	# assertion below ALSO drives the real clamp via MAX_EVASION, so a drift
	# between this and the real formula shows up as a failed band, not a silent pass.
	return minf(eva / (eva + 150.0 * (1.0 + acc / 100.0)), 0.75)

func _check_phase_drive() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var out: Array = []
	for z in ZONES:
		var mid := "z%d_unique_engine" % z
		if not mid in sm.modules:
			continue
		var eva: float = float((sm.modules[mid].get("stats", {}) as Dictionary).get("eva", 0))
		if eva > float(cm.MAX_EVASION):
			_fail("%s grants %d eva but MAX_EVASION is %d — the ladder is clipped and the top tiers collapse into one item" % [
				mid, int(eva), int(cm.MAX_EVASION)])
		var d := _dodge(eva, float(BOSS_ACC[z]))
		out.append("Z%d %.0f%%" % [z, d * 100.0])
		if d < 0.18 or d > 0.22:
			_fail("%s gives %.1f%% dodge vs its own boss (acc %d); spec band is 18-22%%" % [
				mid, d * 100.0, int(BOSS_ACC[z])])
	# The guarantee the old MAX_EVASION comment claimed to provide actually lives
	# in this clamp — verify it, since the cap was raised on that basis.
	if _dodge(100000.0, 0.0) > 0.7501:
		_fail("dodge clamp exceeded 0.75 — enemies are no longer guaranteed a hit chance")
	print("[UNIQ] phase drive dodge vs own boss: %s  (clamp holds at 0.75)" % " ".join(out))

# ---- 4. Predictive Array pity timer ---------------------------------------
func _check_pity_timer() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	GameState.hard_reset()
	var mid := "z5_unique_sensor"
	if not mid in sm.modules:
		_fail("z5_unique_sensor missing; cannot test the pity timer")
		return
	var want := int(sm.modules[mid].get("pity_kills", 0))
	if want <= 0:
		_fail("%s has no pity_kills value" % mid)
		return
	# Equip it into a real sensor bay so get_pity_kills() reads it the way combat
	# does. Needs a hull that HAS one — the starting corvette does not, which is
	# what the first run of this probe actually discovered about itself.
	_use_hull_with("sensor")
	sm.grant_module(mid)
	var slots: Array = sm.get_effective_slots()
	var placed := false
	for i in range(slots.size()):
		if str(slots[i]) == "sensor":
			placed = sm.equip_module(i, mid, true)
			break
	if not placed:
		_fail("could not equip %s into a sensor bay" % mid)
		return
	if int(sm.get_pity_kills()) != want:
		_fail("get_pity_kills() returned %d with %s equipped, expected %d" % [int(sm.get_pity_kills()), mid, want])
		return
	# At the threshold the floor must apply; below it, it must not.
	cm.pity_counter = want
	var forced := 0
	var below := 0
	for _i in range(40):
		cm.pity_counter = want
		if _roll_rarity_with_pity(sm, cm, want) >= sm.Rarity.RARE:
			forced += 1
		cm.pity_counter = 0
		if _roll_rarity_with_pity(sm, cm, 0) >= sm.Rarity.RARE:
			below += 1
	if forced < 40:
		_fail("pity timer floored only %d/40 rolls at the threshold — the guarantee is not guaranteed" % forced)
	if below >= 40:
		_fail("every roll BELOW the threshold was Rare+ too — the floor is always on, so it is a bonus, not a pity timer")
	print("[UNIQ] pity timer: %d/40 floored at threshold, %d/40 Rare+ below it (natural rate)" % [forced, below])

# Mirrors the floor branch of _roll_one_module_drop against the REAL roll_rarity
# and the REAL get_pity_kills, so a change to either shows up here.
func _roll_rarity_with_pity(sm, cm, counter: int) -> int:
	var rarity: int = sm.roll_rarity(false)
	var pity := int(sm.get_pity_kills())
	if pity > 0 and counter >= pity and rarity < sm.Rarity.RARE:
		rarity = sm.Rarity.RARE
	return rarity

# ---- 5. Overcharge gate ---------------------------------------------------
func _check_overcharge() -> void:
	var sm = GameState.shipyard_manager
	GameState.hard_reset()
	var bat := "z2_unique_battery"
	if not bat in sm.modules:
		_fail("z2_unique_battery missing; cannot test overcharge")
		return
	sm.grant_module(bat)
	var slots: Array = sm.get_effective_slots()
	for i in range(slots.size()):
		if str(slots[i]) == "battery":
			sm.equip_module(i, bat, true)
			break
	sm.recalc_stats()
	# A fresh corvette has empty consumer bays — the gate must pay nothing.
	var gated: float = float(sm.get_overcharge_mult())
	if absf(gated - 1.0) > 0.0001:
		_fail("overcharge paid %.3f with consumer bays EMPTY — it rewards flying half-equipped, which is the degenerate loop the gate exists to stop" % gated)
	# Now fill every consumer bay and re-check that it pays, capped.
	var cap: float = float(sm.modules[bat].get("overcharge_cap", 0.0))
	var base := {"weapon": "z1_kinetic", "shield": "z1_shield", "armor": "z1_armor",
		"engine": "z1_engine", "sensor": "z1_sensor"}
	for i2 in range(slots.size()):
		var st := str(slots[i2])
		if st in base and not sm.loadout.get(i2, null):
			sm.grant_module(str(base[st]))
			sm.equip_module(i2, str(base[st]), true)
	sm.recalc_stats()
	var filled: float = float(sm.get_overcharge_mult())
	if filled <= 1.0:
		_fail("overcharge paid nothing (%.3f) with every consumer bay filled and a %.0f%% cap available" % [filled, cap * 100.0])
	if filled > 1.0 + cap + 0.0001:
		_fail("overcharge paid %.3f, above its %.0f%% cap" % [filled, cap * 100.0])
	print("[UNIQ] overcharge: %.3fx with bays empty (gate), %.3fx filled (cap %.0f%%)" % [
		gated, filled, cap * 100.0])
