extends SceneTree
## Save-slot engine sim: independence, summaries, legacy migration, delete.
## Each block prints PASS/FAIL; exits non-zero if any fails.

var _fail := false

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("PASS " + msg)
	else:
		print("FAIL " + msg)
		_fail = true

func _wipe(gs) -> void:
	for n in range(1, gs.SLOT_COUNT + 1):
		gs.delete_slot(n)
	if FileAccess.file_exists(gs.SAVE_PATH):
		DirAccess.remove_absolute(gs.SAVE_PATH)

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var gs = root.get_node("GameState")
	_wipe(gs)

	# --- Slots independent: build A in slot 2, B in slot 3, differently.
	gs.new_character(2, "A")
	gs.gain_credits(1234)
	gs.skills["combat"] = gs.xp_for_level(12)
	gs.unlocked_research["zone_2_access"] = true
	gs.save_game()

	gs.new_character(3, "B")
	gs.gain_credits(9876)
	gs.skills["combat"] = gs.xp_for_level(5)
	gs.save_game()

	var s2 = gs.slot_summary(2)
	var s3 = gs.slot_summary(3)
	_ck(s2.get("exists", false) and s3.get("exists", false), "both slots exist after creation")
	_ck(s2.get("name", "") == "A" and s3.get("name", "") == "B", "names don't bleed (A/B)")
	_ck(s2.get("credits", 0) == 1234 and s3.get("credits", 0) == 9876, "credits isolated per slot")
	_ck(s2.get("combat_level", 0) == 12, "slot 2 combat level 12 (got %d)" % int(s2.get("combat_level", -1)))
	_ck(s3.get("combat_level", 0) == 5, "slot 3 combat level 5 (got %d)" % int(s3.get("combat_level", -1)))
	_ck(s2.get("sector", "") == "Asteroid Belt", "slot 2 sector = Asteroid Belt (got %s)" % str(s2.get("sector", "")))
	_ck(s3.get("sector", "") == "Lunar Orbit", "slot 3 sector = Lunar Orbit (got %s)" % str(s3.get("sector", "")))
	_ck(s2.has("last_played") and float(s2.get("last_played", 0)) > 0.0, "slot 2 has last_played")

	# --- select_slot loads the right state.
	gs.select_slot(2)
	_ck(gs.current_slot == 2 and gs.credits == 1234 and gs.character_name == "A", "select_slot(2) loads A")
	gs.select_slot(3)
	_ck(gs.current_slot == 3 and gs.credits == 9876 and gs.character_name == "B", "select_slot(3) loads B")

	# --- Empty slot summary.
	var s4 = gs.slot_summary(4)
	_ck(s4.get("exists", true) == false, "untouched slot 4 returns exists=false")

	# --- Delete.
	gs.delete_slot(2)
	_ck(gs.slot_summary(2).get("exists", true) == false, "delete_slot(2) -> exists false")

	# --- Legacy migration.
	_wipe(gs)
	var legacy := {"version": 2, "credits": 555, "skills": {"combat": gs.xp_for_level(8)}, "time": Time.get_unix_time_from_system()}
	var lf := FileAccess.open(gs.SAVE_PATH, FileAccess.WRITE)
	lf.store_string(JSON.stringify(legacy, "\t"))
	lf.close()
	gs._migrate_legacy_save()
	var sm = gs.slot_summary(1)
	_ck(sm.get("exists", false), "legacy migration created slot 1")
	_ck(int(sm.get("credits", 0)) == 555, "migrated slot 1 keeps legacy credits (got %d)" % int(sm.get("credits", -1)))
	_ck(sm.get("name", "") == "Commander", "migrated slot 1 default name Commander")
	gs.select_slot(1)
	_ck(gs.credits == 555 and gs.current_slot == 1, "select_slot(1) loads migrated legacy data")

	# --- has_any_save.
	_ck(gs.has_any_save(), "has_any_save true with slot 1 present")

	_wipe(gs)
	_ck(not gs.has_any_save(), "has_any_save false after wipe")

	if _fail:
		print("SLOTS: FAIL")
		quit(1)
	print("SLOTS: PASS")
	quit()
