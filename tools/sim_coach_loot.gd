extends SceneTree
## Verifier for the two mobile-UX features:
##   Task 1 — mission coaching (routing + unmissable on-target pointer)
##   Task 2 — combat session-loot ("SALVAGE THIS RUN") engine + live panel
## Builds the real main scene headless and asserts behavior via the node tree
## (screenshot grab is broken here, so everything is checked structurally).

var fail := false

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

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

func _ok(cond: bool, label: String) -> void:
	if cond:
		print("PASS %s" % label)
	else:
		print("FAIL %s" % label)
		fail = true

# Unlock everything so every coach target card actually renders.
func _unlock_all(gs) -> void:
	for sk in gs.skills:
		gs.skills[sk] = 99999999
	for rid in GameData.RESEARCH:
		gs.unlocked_research[rid] = true
	# Zone/hazard unlock flags + boss kills.
	for z in GameData.ZONES:
		var fl: String = z.get("unlock_flag", "")
		if fl != "":
			gs.game_flags[fl] = true
	gs.game_flags["z11_unlocked"] = true
	gs.game_flags["warp_revealed"] = true
	for eid in GameData.ENEMIES:
		if GameData.ENEMIES[eid].get("is_boss", false):
			gs.boss_kills[eid] = 1

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main._welcome_done = true
	if main._welcome != null:
		main._welcome.queue_free()
		main._welcome = null
	var gs = root.get_node("GameState")
	_unlock_all(gs)

	# ============================================================ TASK 1: COACH
	# (2) Resolution for EVERY mission in MISSION_ORDER (+ the core goals).
	var card_types := ["gather", "gather_multi", "research", "craft", "construct", "build", "defeat"]
	var unresolved := []
	var all_ids: Array = GameData.MISSION_ORDER.duplicate()
	for gid in GameData.MISSION_GOALS:
		all_ids.append(gid)
	for mid in all_ids:
		var m: Dictionary = GameData.MISSIONS[mid]
		var res: Dictionary = main._coach_resolve(m)
		var page: String = res["page"]
		var card: String = res["card"]
		# Every mission must resolve to a real page id.
		if page == "" or not main.pages.has(page):
			unresolved.append("%s(%s): bad page '%s'" % [mid, m.get("type", ""), page])
			continue
		# Card-targeted types must resolve a node once we navigate to the page.
		var mtype: String = m.get("type", "")
		if mtype in card_types:
			# Drive the coach so _show applies sub-tab/zone selection, then navigate.
			gs.missions_active = {mid: true}
			main._show(page)
			await process_frame
			await process_frame
			var node = main._coach_find_card(card)
			if node == null:
				unresolved.append("%s(%s): card '%s' not found on '%s'" % [mid, mtype, card, page])
	_ok(unresolved.is_empty(), "coach resolution: every mission resolves (unresolved=%s)" % str(unresolved))

	# (3) Pointer lifecycle: target -> overlay built + visible; clear -> hidden; no leak.
	# Put the player on a gather mission and navigate to its page.
	gs.missions_active = {"m001": true}     # gather Dirt -> gather page
	main._show("gather")
	await process_frame
	await process_frame
	main._update_coach()
	await process_frame
	main._process(0.016)
	var ptr_built := main._coach_ptr != null and is_instance_valid(main._coach_ptr)
	var ptr_target := is_instance_valid(main._pulse_target)
	_ok(ptr_built and ptr_target and main._coach_ptr.visible, "coach pointer: ring+chip overlay built and visible on target")
	# Chip text present.
	var pt := []
	if ptr_built:
		_collect_text(main._coach_ptr, pt)
	_ok(_has(pt, "Tap here"), "coach pointer: '👆 Tap here' chip present")

	# Switching pages with no card target must remove the pointer cleanly (no error).
	gs.missions_active = {"m007b": true}    # loadout_check -> ship page, navigate-only
	main._show("ship")
	await process_frame
	main._update_coach()
	await process_frame
	main._process(0.016)
	_ok(not main._coach_ptr.visible, "coach pointer: hidden on navigate-only step (no card)")

	# Clearing the active mission entirely hides banner + pointer.
	gs.missions_active = {}
	main._update_coach()
	await process_frame
	_ok((not main._coach_ptr.visible) and (not main._coach_banner.visible) and main._pulse_target == null,
		"coach pointer: fully cleared when no active mission")

	# ============================================================ TASK 2: LOOT
	# (4) session_loot accumulates per combat grant and resets on a new engagement.
	gs.missions_active = {}
	# Give weapons so combat ticks deal damage / kills resolve.
	for mid2 in ["z1_kinetic", "z1_battery"]:
		gs.module_inventory[mid2] = 1
		gs.equip_module(mid2)
	gs.start_task("combat", "z1_lunar_drone")
	await process_frame
	_ok(gs.session_loot.is_empty(), "session loot: empty on fresh engagement")
	# Drive several kills directly via the loot path so the accumulation is deterministic.
	for _i in range(6):
		gs.enemy_inst["hp"] = 0.0
		gs.enemy_inst["shield"] = 0.0
		gs._win_combat()
	var total := 0
	for q in gs.session_loot.values():
		total += int(q)
	_ok(not gs.session_loot.is_empty() and total > 0, "session loot: accumulates combat drops (entries=%d total=%d)" % [gs.session_loot.size(), total])
	# Direct helper accounting check.
	var before := int(gs.session_loot.get("Fe", 0))
	gs._log_session_loot("Fe", 5)
	gs._log_session_loot("Fe", 3)
	_ok(int(gs.session_loot["Fe"]) == before + 8, "session loot: _log_session_loot adds quantities correctly")
	# New engagement resets.
	gs.start_task("combat", "z1_lunar_drone")     # toggles off (same target)
	gs.start_task("combat", "z1_lunar_drone")     # new engagement -> _init_combat reset
	await process_frame
	_ok(gs.session_loot.is_empty(), "session loot: resets when a new engagement starts")

	# (5) Battle panel: empty state then live update.
	gs.stop_task()
	gs.start_task("combat", "z1_lunar_drone")
	main._show("combat")
	await process_frame
	main._refresh_current()
	await process_frame
	var bt0 := []
	_collect_text(main.pages["combat"], bt0)
	_ok(_has(bt0, "SALVAGE THIS RUN"), "battle panel: SALVAGE THIS RUN panel present")
	_ok(_has(bt0, "NO YIELD YET"), "battle panel: empty state shown with no loot")
	# Log loot and run _process so the live-update path rebuilds rows.
	gs._log_session_loot("Fe", 12)
	gs._log_session_loot("credits", 500)
	main._process(0.016)
	await process_frame
	var bt1 := []
	_collect_text(main.pages["combat"], bt1)
	_ok(_has(bt1, "Iron") and not _has(bt1, "NO YIELD YET"), "battle panel: live-updates with logged loot")

	# (6) Regression: 2-battery z1 starter + ammo kills z1_lunar_drone in a sane time.
	gs.stop_task()
	# Fresh-ish loadout: clear, fit the starter kinetic + 2 batteries + ammo.
	gs.module_inventory["z1_kinetic"] = int(gs.module_inventory.get("z1_kinetic", 0)) + 1
	gs.equip_module("z1_kinetic")
	gs.module_inventory["z1_battery"] = 2
	gs.equip_module("z1_battery")
	gs.equip_module("z1_battery")
	gs.add_resource("SlugT1", 500)
	for slot in gs.ammo_loadout.keys():
		gs.set_ammo(slot, "SlugT1")
	# Set ammo on weapon slot 0 explicitly if loadout empty.
	gs.set_ammo("0", "SlugT1")
	gs.combat_hp = gs.combat_max_hp()
	gs.start_task("combat", "z1_lunar_drone")
	await process_frame
	var killed := false
	var t := 0.0
	while t < 30.0:
		gs._tick_combat(0.5)
		t += 0.5
		if int(gs.session_loot.size()) > 0 or gs.enemy_inst.get("max_hp", 0) != gs.enemy_inst.get("hp", 0):
			pass
		# A kill is detected by session_loot gaining at least one entry (drops on kill).
		if not gs.session_loot.is_empty():
			killed = true
			break
	_ok(killed and t <= 20.0, "regression: 2-battery starter kills z1_lunar_drone (~%ss)" % str(t))

	if fail:
		print("COACH_LOOT: FAIL")
		quit(1)
	print("COACH_LOOT: PASS")
	quit()
