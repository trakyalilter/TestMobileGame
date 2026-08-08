extends Node
# SKILL MILESTONE RE-DERIVATION GUARD.
#
# `unlocked_milestones` is derived from xp, never saved. But _check_milestones
# only ever APPENDS, and rebuild_level_silently() used to leave the old array in
# place -- so any rebuild that LOWERED the level kept every milestone above it.
# After a warp (30% XP keep, ~12 levels down) processing kept its milestone-10
# and -25 speed multipliers and its milestone-50 double-output roll for the rest
# of the session, and re-crossing a milestone fired no toast because it was
# already in the array.
#
# Checks the array AND the multipliers that ride on it, on all three rebuild
# paths (warp, load, debug set-level).
#
#   Godot --headless --path <root> res://scenes/milestone_reset_check.tscn

var fails: int = 0

func _ready() -> void:
	await get_tree().process_frame
	var pm = GameState.processing_manager

	# ---- 1. warp: milestones must fall with the level ----------------------
	pm.xp = float(pm.get_xp_for_level(60))
	pm.rebuild_level_silently()
	var lvl_before: int = pm.level
	var ms_before: Array = pm.unlocked_milestones.duplicate()
	var probe_recipe: String = ""
	for rid in pm.recipes:
		probe_recipe = String(rid)
		break
	var mult_before: float = pm.get_recipe_speed_multiplier(probe_recipe)
	_expect(lvl_before == 60, "setup: level 60, got %d" % lvl_before)
	_expect(ms_before.has(50), "setup: milestone 50 unlocked at level 60, got %s" % str(ms_before))

	pm.reset(0.7)  # execute_warp's decay: keep 30%
	print("[MS] warp: level %d -> %d, milestones %s -> %s" % [lvl_before, pm.level, str(ms_before), str(pm.unlocked_milestones)])
	_expect(pm.level < lvl_before, "warp must lower the level (still %d)" % pm.level)
	for m in pm.unlocked_milestones:
		_expect(int(m) <= pm.level, "ghost milestone %d retained at level %d" % [int(m), pm.level])
	# The multiplier is the thing the player actually feels.
	var mult_after: float = pm.get_recipe_speed_multiplier(probe_recipe)
	if pm.level < 25 and lvl_before >= 25:
		_expect(mult_after < mult_before, "speed multiplier %.3f unchanged after losing milestones (was %.3f)" % [mult_after, mult_before])

	# ---- 2. re-crossing must re-fire the toast -----------------------------
	var refired: Array = []
	pm.milestone_unlocked.connect(func(m): refired.append(int(m)))
	var lost: int = 0
	for m in ms_before:
		if not pm.unlocked_milestones.has(m):
			lost = int(m)
			break
	if lost > 0:
		pm.add_xp(float(pm.get_xp_for_level(lost)) - pm.xp + 1.0)
		_expect(refired.has(lost), "re-crossing milestone %d fired no toast (refired=%s)" % [lost, str(refired)])
	else:
		_expect(false, "warp lost no milestone at all -- test is not exercising the bug")

	# ---- 3. loading a LOWER save over a live skill -------------------------
	pm.xp = float(pm.get_xp_for_level(80))
	pm.rebuild_level_silently()
	pm.load_save_data({"xp": float(pm.get_xp_for_level(12))})
	print("[MS] load 80 -> 12: level %d, milestones %s" % [pm.level, str(pm.unlocked_milestones)])
	_expect(pm.level == 12, "load of a lower save left level at %d, expected 12" % pm.level)
	_expect(not pm.unlocked_milestones.has(25), "milestone 25 survived a load down to level 12")
	_expect(pm.unlocked_milestones.has(10), "milestone 10 missing at level 12 -- array not refilled")

	# ---- 4. debug set-level downward ---------------------------------------
	pm.xp = float(pm.get_xp_for_level(100))
	pm.rebuild_level_silently()
	_expect(pm.unlocked_milestones.has(100), "setup: capstone at level 100")
	pm.xp = float(pm.get_xp_for_level(30))
	pm.rebuild_level_silently()
	print("[MS] set-level 100 -> 30: level %d, milestones %s" % [pm.level, str(pm.unlocked_milestones)])
	_expect(pm.level == 30, "set-level down left level at %d, expected 30" % pm.level)
	_expect(not pm.unlocked_milestones.has(50), "milestone 50 survived set-level down to 30")
	_expect(pm.unlocked_milestones.has(25), "milestone 25 missing at level 30 -- array not refilled")

	print("[MS] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[MS] FAIL: %s" % msg)
		fails += 1
