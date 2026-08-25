extends SceneTree
## Verifies the coach pointer: prefers an actionable mission over a [CORE GOAL],
## and when the drawer is open it points at the target nav row (or nothing for an
## unreachable target) — never dead-ends on the hamburger.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	for n in range(1, gs.SLOT_COUNT + 1):
		gs.delete_slot(n)
	gs.new_character(1, "Tester")
	if is_instance_valid(main._char_select):
		main._char_select.queue_free()
		main._char_select = null
	main._refresh_all()
	await process_frame

	var fail := false

	# Find a [CORE GOAL] mission and a research-type mission.
	var core := ""
	var research_m := ""
	for mid in GameData.MISSIONS:
		var nm: String = GameData.MISSIONS[mid].get("name", "")
		if core == "" and nm.begins_with("[CORE GOAL]"):
			core = mid
		if research_m == "" and GameData.MISSIONS[mid].get("type", "") == "research":
			research_m = mid
	print("core=%s research=%s" % [core, research_m])

	# (1) Coach prefers the actionable mission over a core goal.
	gs.missions_active = {core: true, research_m: true}
	if main._coach_active_mission() == research_m:
		print("PASS coach prefers actionable mission over core goal")
	else:
		print("FAIL coach picked %s" % main._coach_active_mission())
		fail = true
	# Core goal alone still drives the banner.
	gs.missions_active = {core: true}
	if main._coach_active_mission() == core:
		print("PASS core goal still used when it's the only active mission")
	else:
		print("FAIL core-goal fallback wrong")
		fail = true

	# (2) Drawer open, target reachable (Research) -> pulse on the Research nav row.
	gs.missions_active = {research_m: true}
	main._show("gather")          # not on research, so it's a navigate step
	await process_frame
	main._open_drawer()
	await process_frame
	var research_btn = main.nav_items.get("research", {}).get("btn", null)
	print("pulse target == research row: %s" % str(main._pulse_target == research_btn))
	if main._pulse_target == research_btn and research_btn != null:
		print("PASS drawer-open points at the Research nav row")
	else:
		print("FAIL drawer-open did not target the Research row")
		fail = true
	main._close_drawer()
	await process_frame

	# (3) Drawer open, target NOT in the menu (warp hidden) -> no hamburger dead-end.
	gs.game_flags["warp_revealed"] = false
	# A warp_perform core goal resolves to page "warp"; force it as the only mission.
	var warp_m := ""
	for mid in GameData.MISSIONS:
		if GameData.MISSIONS[mid].get("type", "") == "warp_perform":
			warp_m = mid
			break
	if warp_m == "":
		print("NOTE no warp_perform mission found — skipping unreachable check")
	else:
		gs.missions_active = {warp_m: true}
		main._show("gather")
		await process_frame
		main._open_drawer()
		await process_frame
		print("warp hidden, drawer open: pulse==ham? %s" % str(main._pulse_target == main._ham_btn))
		if main._pulse_target != main._ham_btn:
			print("PASS no hamburger dead-end for an unreachable target")
		else:
			print("FAIL coach dead-ends on the hamburger with menu open")
			fail = true
		main._close_drawer()

	# ---- mission guidance can be switched off ----
	# "The tutorial is there constantly" was desktop's first demo complaint. Off
	# must silence the POINTER without hiding what you are working towards, and
	# missions must still run and pay — a toggle that quietly stops progress
	# would be worse than the nagging.
	gs.missions_active = {"m001": true}
	gs.missions_progress.erase("m001")
	main._show("gather")
	await process_frame
	gs.mission_guidance = true
	main._update_coach()
	await process_frame
	var guided_visible: bool = main._coach_banner.visible
	var guided_hint: String = main._coach_hint.text
	gs.mission_guidance = false
	main._update_coach()
	await process_frame
	if main._coach_banner.visible and guided_visible:
		print("PASS the objective banner stays with guidance off")
	else:
		print("FAIL guidance off hid the objective entirely")
		fail = true
	if main._coach_hint.text != guided_hint:
		print("PASS the step-by-step directive is silenced")
	else:
		print("FAIL the directive text is unchanged with guidance off")
		fail = true
	# Missions keep working regardless of the toggle.
	gs.add_resource("Dirt", 100000, true)
	gs._mission_sync()
	if gs.mission_completed("m001"):
		print("PASS missions still progress with guidance off")
	else:
		print("FAIL guidance off stopped mission progress")
		fail = true
	# ---- and the banner claims in place ----
	var claimed_before: bool = gs.missions_claimed.has("m001")
	main._update_coach()
	await process_frame
	main._coach_tapped()
	await process_frame
	if not claimed_before and gs.missions_claimed.has("m001"):
		print("PASS tapping the banner claims the reward in place")
	else:
		print("FAIL banner tap did not claim (claimed=%s)" % str(gs.missions_claimed.has("m001")))
		fail = true
	gs.mission_guidance = true

	if fail:
		print("COACH_NAV: FAIL")
		quit(1)
	print("COACH_NAV: PASS")
	quit()
