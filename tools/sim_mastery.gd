extends SceneTree
## Verification harness for the per-action Mastery system (engine + UI).
## Mirrors the desktop gathering_manager / processing_manager spec. PASS/FAIL each.

var _fail := false

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		print("PASS %s" % label)
	else:
		print("FAIL %s%s" % [label, (" — " + detail) if detail != "" else ""])
		_fail = true

func _collect_text(node: Node, out: Array) -> void:
	if node is Label or node is Button:
		out.append(node.text)
	for c in node.get_children():
		_collect_text(c, out)

func _has(texts: Array, needle: String) -> bool:
	for t in texts:
		if needle in t:
			return true
	return false

func _run() -> void:
	var gs = root.get_node("GameState")

	# ---- Level math (spec) ----
	_ok(gs.mastery_xp_needed(1) == 30.0, "xp_needed(1)=30", str(gs.mastery_xp_needed(1)))
	gs.mastery["t_lvl"] = 30.0
	_ok(gs.mastery_level("t_lvl") == 1, "level at xp=30 is 1", str(gs.mastery_level("t_lvl")))

	# Milestone table → reductions at the five milestone levels.
	var checks := {10: 0.05, 25: 0.10, 50: 0.20, 75: 0.25, 100: 0.30}
	for lvl in checks:
		var id := "t_m%d" % lvl
		gs.mastery[id] = _xp_for_level(gs, lvl)
		_ok(gs.mastery_level(id) == lvl, "reach level %d" % lvl, str(gs.mastery_level(id)))
		var reduction: float = 1.0 - gs.mastery_dur_mult(id)
		_ok(abs(reduction - float(checks[lvl])) < 0.0001, "level %d → %.2f reduction" % [lvl, checks[lvl]], str(reduction))

	# next_mastery_milestone teaser.
	gs.mastery["t_next"] = _xp_for_level(gs, 12)
	_ok(gs.next_mastery_milestone("t_next") == 25, "next milestone after L12 is 25", str(gs.next_mastery_milestone("t_next")))

	# ---- Accrual: drive ~40 gather_dirt completions ----
	gs.mastery.erase("gather_dirt")
	gs.start_task("gather", "gather_dirt")
	var before_xp: float = gs.mastery_xp("gather_dirt")
	var before_lvl: int = gs.mastery_level("gather_dirt")
	for _i in range(40):
		gs._complete_active()
	var gained: float = gs.mastery_xp("gather_dirt") - before_xp
	_ok(abs(gained - 40.0) < 0.001, "accrual: +40 mastery XP over 40 completions", str(gained))
	_ok(gs.mastery_level("gather_dirt") > before_lvl, "accrual: mastery level rose", str(gs.mastery_level("gather_dirt")))

	# ---- Speed: effective_duration faster at L>=10 than L0 ----
	gs.mastery.erase("gather_dirt")
	var dur_l0: float = gs.effective_duration("gather", "gather_dirt")
	gs.mastery["gather_dirt"] = _xp_for_level(gs, 10)
	var dur_l10: float = gs.effective_duration("gather", "gather_dirt")
	_ok(dur_l10 < dur_l0, "speed: L10 duration < L0 duration", "%.4f < %.4f" % [dur_l10, dur_l0])
	# ~5% faster at L10: dur_l10 ≈ dur_l0 * 0.95.
	_ok(abs(dur_l10 - dur_l0 * 0.95) < 0.0001, "speed: L10 ≈ 5% faster", "%.4f vs %.4f" % [dur_l10, dur_l0 * 0.95])
	gs.mastery.erase("gather_dirt")

	# ---- Persistence round-trip ----
	# Saves now target the active slot; activate one so save/load hit disk.
	for n in range(1, gs.SLOT_COUNT + 1):
		gs.delete_slot(n)
	gs.current_slot = 1
	gs.stop_task()                                 # don't persist a live task into the save file
	gs.mastery["gather_dirt"] = 123.0
	gs.mastery["smelt_steel_basic"] = 7.5
	gs.save_game()
	gs.mastery = {}
	gs.load_game()
	_ok(abs(gs.mastery_xp("gather_dirt") - 123.0) < 0.001 and abs(gs.mastery_xp("smelt_steel_basic") - 7.5) < 0.001,
		"persistence: mastery round-trips", str(gs.mastery))

	# ---- UI: mastery row present + live-updating on the active card ----
	await _ui_checks(gs)

	if _fail:
		print("MASTERY: FAIL")
		quit(1)
	print("MASTERY: PASS")
	quit()

# Build the cumulative XP needed to be exactly AT `level` (start of that level).
func _xp_for_level(gs, level: int) -> float:
	var total := 0.0
	for n in range(1, level + 1):
		total += gs.mastery_xp_needed(n)
	return total

func _ui_checks(gs) -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	# Gather page: an unlocked card (gather_dirt, level_req 1) must carry a MASTERY row.
	main._show("gather")
	await process_frame
	var gt := []
	_collect_text(main.pages["gather"], gt)
	_ok(_has(gt, "MASTERY"), "UI: MASTERY label on unlocked gather card", "no MASTERY label")

	# Craft page: an unlocked recipe card must carry a MASTERY row too. Unlock the
	# basics gate so at least one recipe is buildable.
	gs.unlocked_research["basic_engineering"] = true
	gs.unlocked_research["fluid_dynamics"] = true
	main._show("craft")
	await process_frame
	var ct := []
	_collect_text(main.pages["craft"], ct)
	_ok(_has(ct, "MASTERY"), "UI: MASTERY label on unlocked craft card", "no MASTERY label")

	# Live update: start gather_dirt, rebuild the page so the active card's mastery
	# nodes are captured into members, then drive completions WITHOUT a rebuild and
	# assert the captured bar advances (the page-not-rebuilt-on-completion path).
	gs.mastery.erase("gather_dirt")
	gs.stop_task()                                 # clean slate (start_task toggles)
	gs.start_task("gather", "gather_dirt")
	main._show("gather")
	await process_frame
	_ok(is_instance_valid(main._mastery_bar) and main._mastery_id == "gather_dirt",
		"UI: active card mastery bar captured as a member", "id=%s" % main._mastery_id)
	var v0: float = main._mastery_bar.value
	# Several completions raise the in-level XP; _process() refreshes the captured bar.
	for _i in range(5):
		gs._complete_active()
	main._process(0.016)
	await process_frame
	var v1: float = main._mastery_bar.value
	_ok(v1 > v0, "UI: active mastery bar advances live without page rebuild", "%.2f -> %.2f" % [v0, v1])
	gs.stop_task()
	main.queue_free()
