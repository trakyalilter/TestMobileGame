extends Node
# ============================================================================
# SALVAGE VAULT CARRY CHECK (v176)  — docs/design/SALVAGE_VAULT.md
#
# The Vault lets the player nominate K modules that survive a Warp. Everything
# about it is a chance to lose or duplicate player property, so every claim the
# design makes is asserted here against the REAL execute_warp() — never against
# a reimplementation of it, which would keep passing after the real path broke.
#
# What is checked:
#   1. nominated ids survive the warp; un-nominated ones do NOT
#   2. a carried custom drop keeps its ROLLED stats + affixes (restoring the id
#      without its custom_modules entry would silently downgrade a god-roll to
#      base stats — the failure a player would never report but always feel)
#   3. the research gate still bites: a carried above-tier module cannot be
#      equipped, and CAN once its tech is back. This is the whole anti-power-
#      creep argument for the feature, so it needs a test that has been seen red.
#   4. capacity matches the design table across total_warps 1..7
#   5. hard_reset() empties the vault ("New Game" must not start with a rifle)
#   6. over-cap selections are refused
#
#   Godot --headless --path <root> res://scenes/vault_carry_check.tscn
# ============================================================================

var _fails: Array = []

func _ready() -> void:
	await get_tree().process_frame
	# execute_warp + hard_reset are exercised below, and hard_reset deletes the
	# real savegame. Refuse to run outside the sim guard.
	if not GameState.sim_mode:
		print("[VAULT] ABORT: sim_mode false — refusing to run (this probe warps and hard-resets).")
		get_tree().quit(1)
		return
	GameState.set_process(false)
	print("[VAULT] ============ SALVAGE VAULT CARRY CHECK ============")

	_check_capacity_table()
	_check_over_cap_refused()
	_check_carry_and_drop()
	_check_research_gate()
	_check_hard_reset_clears()

	print("[VAULT] --------------------------------------------------")
	for f in _fails:
		print("[VAULT] FAIL: %s" % f)
	print("[VAULT] RESULT: %s (%d failure(s))" % ["PASS" if _fails.is_empty() else "FAIL", _fails.size()])
	get_tree().quit(0 if _fails.is_empty() else 1)

func _fail(msg: String) -> void:
	_fails.append(msg)

# Enough lifetime credits that calculate_warp_gains() clears its threshold —
# otherwise execute_warp() early-returns and every later assertion passes
# vacuously against a warp that never happened.
func _arm_warp() -> void:
	GameState.resources.lifetime_credits = 50_000_000.0

func _do_warp() -> bool:
	var wm = GameState.warp_manager
	var before := int(wm.total_warps)
	_arm_warp()
	wm.execute_warp()
	if int(wm.total_warps) <= before:
		_fail("execute_warp() did not warp (total_warps stayed %d) — the probe is not testing what it claims" % before)
		return false
	return true

# ---- 4. capacity table ----------------------------------------------------
func _check_capacity_table() -> void:
	var wm = GameState.warp_manager
	var want := {1: 3, 2: 4, 3: 5, 4: 6, 5: 7, 6: 8, 7: 8}
	var saved := int(wm.total_warps)
	var bad := 0
	for w in want:
		wm.total_warps = int(w)
		var got := int(wm.get_vault_capacity())
		if got != int(want[w]):
			_fail("capacity at total_warps=%d is %d, design table says %d" % [w, got, int(want[w])])
			bad += 1
	wm.total_warps = saved
	print("[VAULT] capacity table 1..7: %s" % ("OK" if bad == 0 else "%d wrong" % bad))

# ---- 6. over-cap selection ------------------------------------------------
func _check_over_cap_refused() -> void:
	GameState.hard_reset()
	var wm = GameState.warp_manager
	var sm = GameState.shipyard_manager
	var ids: Array = []
	for i in range(12):
		var cid := str(sm.generate_module_drop("z1_kinetic", 2, 1))
		if cid != "":
			ids.append(cid)
	wm.set_vault_selection(ids)
	var cap := int(wm.get_vault_capacity_next())
	if wm.vault_selection.size() > cap:
		_fail("set_vault_selection accepted %d ids with capacity %d" % [wm.vault_selection.size(), cap])
	# A module the player does not hold must not be selectable.
	wm.set_vault_selection(["z9_kinetic"])
	if wm.vault_selection.size() != 0:
		_fail("set_vault_selection accepted a module the player does not own")
	print("[VAULT] over-cap + unowned selection refused: OK (cap %d)" % cap)

# ---- 1 + 2. carry, drop, and roll fidelity --------------------------------
func _check_carry_and_drop() -> void:
	var fails_before := _fails.size()
	GameState.hard_reset()
	var wm = GameState.warp_manager
	var sm = GameState.shipyard_manager
	# Two ROLLED drops so stat fidelity is meaningful (base modules would pass
	# trivially by re-resolving from the static table).
	var keep := str(sm.generate_module_drop("z1_kinetic", 2, 1))
	var drop := str(sm.generate_module_drop("z1_kinetic", 2, 1))
	if keep == "" or drop == "" or keep == drop:
		_fail("could not create two distinct rolled drops to test with")
		return
	var keep_stats: Dictionary = (sm.modules[keep].get("stats", {}) as Dictionary).duplicate(true)
	var keep_affix: Dictionary = (sm.modules[keep].get("affixes", {}) as Dictionary).duplicate(true)

	wm.set_vault_selection([keep])
	if not _do_warp():
		return

	if int(sm.module_inventory.get(keep, 0)) <= 0:
		_fail("nominated module %s did NOT survive the warp" % keep)
	if int(sm.module_inventory.get(drop, 0)) > 0:
		_fail("un-nominated module %s survived the warp — the wipe is leaking" % drop)
	if not sm.modules.has(keep):
		_fail("carried module %s is not in the module table after the warp" % keep)
		return

	var now_stats: Dictionary = sm.modules[keep].get("stats", {})
	var lost: Array = []
	for k in keep_stats:
		if absf(float(now_stats.get(k, 0.0)) - float(keep_stats[k])) > 0.001:
			lost.append(str(k))
	if not lost.is_empty():
		_fail("carried %s lost its rolled stats (%s) — restored from base instead of the snapshot" % [keep, str(lost)])
	var now_affix: Dictionary = sm.modules[keep].get("affixes", {})
	if now_affix.size() != keep_affix.size():
		_fail("carried %s had %d affix(es) before the warp and %d after" % [keep, keep_affix.size(), now_affix.size()])
	# The vault is a carry, not a duplicator.
	if int(sm.module_inventory.get(keep, 0)) != 1:
		_fail("carried %s arrived x%d — the vault duplicated it" % [keep, int(sm.module_inventory.get(keep, 0))])
	# It must arrive UNEQUIPPED; equipping is what surfaces the research gate.
	if keep in sm.loadout.values():
		_fail("carried %s came back pre-equipped; it must land in inventory only" % keep)
	# Report the ACTUAL outcome. The first cut printed "intact" unconditionally and
	# happily said so on the same run three assertions below it were failing.
	if _fails.size() == fails_before:
		print("[VAULT] carry/drop/roll fidelity: kept %s (stats+affixes intact), dropped %s" % [keep, drop])
	else:
		print("[VAULT] carry/drop/roll fidelity: %d FAILURE(S) — see below" % (_fails.size() - fails_before))

# ---- 3. the research gate still bites -------------------------------------
# This is the load-bearing anti-power-creep claim: carried gear cannot skip
# progression because equipping enforces research, and warp resets research.
func _check_research_gate() -> void:
	var fails_before := _fails.size()
	GameState.hard_reset()
	var wm = GameState.warp_manager
	var sm = GameState.shipyard_manager
	var rm = GameState.research_manager

	# A high-tier gun the player could only hold by having been deep in a prior run.
	var base_id := "z5_kinetic"
	if not base_id in sm.modules:
		print("[VAULT] research gate: SKIPPED (%s not in module table)" % base_id)
		return
	var req := str(sm.modules[base_id].get("research_req", ""))
	if req == "":
		print("[VAULT] research gate: SKIPPED (%s has no research_req to gate on)" % base_id)
		return
	if not (req in rm.unlocked_techs):
		rm.unlocked_techs.append(req)
	var gun := str(sm.generate_module_drop(base_id, 2, 5))
	if gun == "":
		_fail("could not roll a %s to test the research gate" % base_id)
		return

	wm.set_vault_selection([gun])
	if not _do_warp():
		return

	if int(sm.module_inventory.get(gun, 0)) <= 0:
		_fail("high-tier %s did not survive the warp" % gun)
		return
	# Post-warp research is reset, so the gate must refuse the equip.
	if rm.is_tech_unlocked(req):
		_fail("warp did not reset %s — the research gate cannot be tested" % req)
		return
	var blocked: Dictionary = sm.can_equip_module(gun)
	if bool(blocked.get("can_equip", false)):
		_fail("carried above-tier %s is equippable with %s unresearched — POWER CREEP: the vault skips progression" % [gun, req])
	# ...and becomes legal again once the tech is re-earned.
	rm.unlocked_techs.append(req)
	var allowed: Dictionary = sm.can_equip_module(gun)
	if not bool(allowed.get("can_equip", false)):
		_fail("carried %s is STILL blocked after re-researching %s (reason: %s) — the carry is dead weight forever" % [
			gun, req, str(allowed.get("reason", ""))])
	if _fails.size() == fails_before:
		print("[VAULT] research gate: %s blocked pre-research, allowed post-research" % gun)
	else:
		print("[VAULT] research gate: %d FAILURE(S) — see below" % (_fails.size() - fails_before))

# ---- 5. hard reset clears the vault ---------------------------------------
func _check_hard_reset_clears() -> void:
	var wm = GameState.warp_manager
	var sm = GameState.shipyard_manager
	GameState.hard_reset()
	var cid := str(sm.generate_module_drop("z1_kinetic", 2, 1))
	wm.set_vault_selection([cid])
	if not _do_warp():
		return
	if wm.vault.is_empty():
		_fail("vault is empty right after a warp that carried a module")
	GameState.hard_reset()
	if not wm.vault.is_empty() or not wm.vault_defs.is_empty() or not wm.vault_selection.is_empty():
		_fail("hard_reset() left vault=%d defs=%d selection=%d — a NEW GAME would start holding carried gear" % [
			wm.vault.size(), wm.vault_defs.size(), wm.vault_selection.size()])
	if int(sm.module_inventory.get(cid, 0)) > 0:
		_fail("hard_reset() left the carried module %s in inventory" % cid)
	print("[VAULT] hard_reset clears vault + inventory: OK")
