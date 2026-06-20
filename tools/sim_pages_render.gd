extends SceneTree
## PHASE 5 — UI / pages render. Instantiates the real main.tscn, creates a
## character, and drives EVERY page (and the meaningful sub-tab / combat states)
## through the actual builders. Asserts each page node stays valid, visible, and
## populates its "List" VBox. Catches null-node crashes, missing nodes, and empty
## renders. The bash wrapper additionally fails the run on any SCRIPT ERROR
## printed by a builder, so a runtime fault during a build is never silent.

var main
var gs
var gd
var errors: Array = []
var warns: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s): errors.append(s)
func W(s): warns.append(s)

func _list_count(pid: String) -> int:
	if not main.pages.has(pid):
		return -1
	var lst = main.pages[pid].find_child("List", true, false)
	return lst.get_child_count() if lst != null else -1

# Show a page and assert it rendered: node valid, visible, List populated.
func _visit(pid: String, expect_content: bool = true) -> void:
	main._show(pid)
	await process_frame
	if not main.pages.has(pid):
		E("page '%s' missing from pages dict" % pid); return
	var page = main.pages[pid]
	if not is_instance_valid(page):
		E("page '%s' node invalid after _show" % pid); return
	if not page.visible:
		E("page '%s' not visible after _show" % pid)
	if main.current != pid:
		E("current != '%s' after _show (got '%s')" % [pid, main.current])
	var n := _list_count(pid)
	if n < 0:
		E("page '%s' has no List container" % pid)
	elif expect_content and n == 0:
		E("page '%s' built EMPTY content (List has 0 children)" % pid)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	gs = root.get_node("GameState")
	gd = root.get_node("GameData")

	# Fresh character so loadout/skills/hull exist.
	for n in range(1, gs.SLOT_COUNT + 1):
		gs.delete_slot(n)
	gs.new_character(1, "RenderTester")
	if is_instance_valid(main._char_select):
		main._char_select.queue_free()
		main._char_select = null

	# Reveal gated features so their pages have real content to draw.
	gs.game_flags["warp_revealed"] = true
	gs.total_warps = 2                      # unlock fleet + show warp depth
	gs.game_flags["z11_unlocked"] = true
	gs.game_flags["z12_unlocked"] = true
	# Generous resources so build/shipyard/craft cards render in buyable state.
	gs.credits = 1_000_000_000
	main._refresh_all()
	await process_frame

	# (1) Every declared page renders. A handful are legitimately sparse depending on
	# state; only flag truly empty where content is always expected.
	var always_content := {
		"gather": true, "craft": true, "combat": true, "research": true, "more": true,
		"build": true, "shipyard": true, "ship": true, "missions": true, "atlas": true,
		"stats": true, "settings": true, "warp": true, "fleet": true,
	}
	for pid in main.PAGE_IDS:
		await _visit(pid, always_content.has(pid))

	# (2) Sub-tab variety — gather categories.
	for cat in gd.GATHER_CATS:
		main.gather_cat = String(cat["id"])
		main._show("gather")
		await process_frame
		if _list_count("gather") <= 0:
			W("gather category '%s' rendered empty" % cat["id"])

	# (3) Craft categories.
	for cat in gd.CRAFT_CATS:
		main.craft_cat = String(cat["id"])
		main._show("craft")
		await process_frame
		if _list_count("craft") < 0:
			E("craft category '%s' has no List" % cat["id"])

	# (4) Research tabs.
	for tab in gd.RESEARCH_GRAPHS:
		main.research_tab = String(tab)
		main._show("research")
		await process_frame
		if _list_count("research") <= 0:
			E("research tab '%s' rendered empty" % tab)

	# (5) Shipyard hulls + modules (each slot).
	main.shipyard_view = "hulls"
	main._show("shipyard")
	await process_frame
	if _list_count("shipyard") <= 0: E("shipyard hulls view empty")
	main.shipyard_view = "modules"
	for slot in ["weapon", "shield", "armor", "engine", "battery", "sensor"]:
		main.ship_mod_slot = slot
		main._show("shipyard")
		await process_frame
		if _list_count("shipyard") < 0: E("shipyard modules slot '%s' has no List" % slot)

	# (6) Combat: each zone roster renders.
	gs.stop_task()
	for zi in range(gd.ZONES.size()):
		main.combat_zone = zi
		main._show("combat")
		await process_frame
		if _list_count("combat") <= 0:
			E("combat zone %d (%s) rendered empty" % [zi, gd.ZONES[zi].get("name", "")])

	# (7) Live battle view — normal enemy.
	gs.start_task("combat", "z1_lunar_drone")
	await process_frame
	main._show("combat")
	await process_frame
	if gs.active_type != "combat" or gs.enemy_inst.is_empty():
		E("failed to enter combat vs z1_lunar_drone")
	elif _list_count("combat") <= 0:
		E("battle view (normal enemy) rendered empty")

	# (8) Live battle view — multi-phase boss (exercises the phase gate + swap panel).
	gs.stop_task()
	await process_frame
	gs.start_task("combat", "z12_boss_rift_warden")
	await process_frame
	main._show("combat")
	await process_frame
	if gs.enemy_inst.is_empty():
		E("failed to spawn z12_boss_rift_warden")
	else:
		if (gs.enemy_inst.get("phases", []) as Array).size() <= 1:
			W("z12_boss_rift_warden has no multi-phase data (swap panel won't show)")
		if not gs.can_swap_loadout_in_combat():
			W("can_swap_loadout_in_combat() false for the multi-phase boss")
		if _list_count("combat") <= 0:
			E("battle view (boss) rendered empty")
	gs.stop_task()
	await process_frame

	# (9) Drawer opens and lists its nav rows without error.
	main._open_drawer()
	await process_frame
	if main.nav_items.is_empty():
		E("nav drawer has no items")
	main._close_drawer()
	await process_frame

	print("\n===== PHASE 5: UI / PAGES RENDER =====")
	print("pages=%d gather_cats=%d craft_cats=%d research_tabs=%d zones=%d" % [
		main.PAGE_IDS.size(), gd.GATHER_CATS.size(), gd.CRAFT_CATS.size(),
		gd.RESEARCH_GRAPHS.size(), gd.ZONES.size()])
	print("errors=%d  warnings=%d" % [errors.size(), warns.size()])
	if not warns.is_empty():
		print("\n--- WARNINGS (%d) ---" % warns.size())
		for w in warns: print("  ⚠ " + w)
	if not errors.is_empty():
		print("\n--- ERRORS (%d) ---" % errors.size())
		for e in errors: print("  ✗ " + e)
		print("\nUI_RENDER: FAIL")
		quit(1)
		return
	print("\nUI_RENDER: PASS")
	quit()
