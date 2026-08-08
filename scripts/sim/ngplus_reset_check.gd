extends Node
# NG+ PROGRESSION-FLAG RESET GUARD.
#
# Two invariants, opposite directions:
#   hard reset (New Game) must RE-LOCK the entire sector ladder;
#   warp        must PRESERVE it (NG+ carry-over is the whole point).
#
# v137 added Sectors 13-15 while GameState.hard_reset() kept a hand-written list
# of five flags, so a New Game shipped with z13/z14/z15_unlocked still set and
# those sectors enterable from minute one. The list is now derived from
# combat_manager.get_progression_flags(); this check is what keeps it honest.
#
#   Godot --headless --path <root> res://scenes/ngplus_reset_check.tscn

var fails: int = 0

func _ready() -> void:
	await get_tree().process_frame
	var cm = GameState.combat_manager
	var flags: Array = cm.get_progression_flags()
	print("[NG] derived progression flags (%d): %s" % [flags.size(), ", ".join(flags)])

	# The set must actually cover the ladder -- a get_progression_flags() that
	# returned [] would pass every erase assertion below while fixing nothing.
	for expect in ["z10_cleared", "z11_cleared", "z12_cleared", "z13_cleared", "z14_cleared",
				   "z11_unlocked", "z12_unlocked", "z13_unlocked", "z14_unlocked", "z15_unlocked",
				   "rift_relic_earned"]:
		if not flags.has(expect):
			print("[NG] FAIL coverage: %s missing from get_progression_flags()" % expect)
			fails += 1

	# ---- hard reset must clear every one of them --------------------------
	_arm(flags)
	GameState.hard_reset()
	for f in flags:
		if GameState.game_settings.get(f, false):
			print("[NG] FAIL hard_reset: %s survived a New Game" % f)
			fails += 1
	# The visible symptom, checked through the real gate rather than the flags.
	var open_ids: Array = []
	for z in GameState.combat_manager.get_available_zones():
		open_ids.append(String(z["id"]))
	for locked in ["the_threshold", "the_rift", "the_verdigris", "the_dissolution", "the_caustic_core"]:
		if open_ids.has(locked):
			print("[NG] FAIL hard_reset: sector '%s' enterable on a fresh game" % locked)
			fails += 1
	if GameState.shipyard_manager and String(GameState.shipyard_manager.equipped_relic) != "":
		print("[NG] FAIL hard_reset: relic still equipped (%s)" % GameState.shipyard_manager.equipped_relic)
		fails += 1

	# ---- warp must NOT clear them (NG+ carry-over) ------------------------
	_arm(flags)
	GameState.game_settings["cryo_unlocked"] = true
	GameState.warp_manager.execute_warp()
	await get_tree().process_frame
	for f in flags:
		if not GameState.game_settings.get(f, false):
			print("[NG] FAIL warp: %s was cleared -- NG+ progress lost on prestige" % f)
			fails += 1
	if not GameState.game_settings.get("cryo_unlocked", false):
		print("[NG] FAIL warp: cryo_unlocked cleared")
		fails += 1

	print("[NG] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


# Simulate an endgame save: whole ladder cleared and unlocked.
func _arm(flags: Array) -> void:
	for f in flags:
		GameState.game_settings[f] = true
	if GameState.shipyard_manager:
		GameState.shipyard_manager.equipped_relic = "rift_relic"
