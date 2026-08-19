extends SceneTree
## Audit of navigation and page rendering in a LATE-GAME state.
##
## sim_pages_render already drives every page on a fresh character. What it
## cannot see is the half of the UI that only exists once the game is advanced:
## the relic slot, the capstone panel, Station Procurement, the NG+ sectors, a
## revealed warp tree. Those panels are all written as "render only when
## unlocked", so on a fresh save the untested branch is the one that ships.
##
## It also checks navigation in BOTH directions. A page with no menu entry is
## unreachable; a menu entry with no page is a dead tap. Both are silent.

var main
var gs
var gd
var errs: Array = []
var warns: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s: String) -> void: errs.append(s)
func W(s: String) -> void: warns.append(s)

func _list_count(pid: String) -> int:
	if not main.pages.has(pid):
		return -1
	var lst = main.pages[pid].find_child("List", true, false)
	return lst.get_child_count() if lst != null else -1

func _visit(pid: String) -> int:
	main._show(pid)
	await process_frame
	if not main.pages.has(pid):
		E("page '%s' missing after _show" % pid)
		return -1
	if not is_instance_valid(main.pages[pid]):
		E("page '%s' node invalid after _show" % pid)
		return -1
	return _list_count(pid)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	gs = root.get_node("GameState")
	gd = root.get_node("GameData")
	for n in range(1, gs.SLOT_COUNT + 1):
		gs.delete_slot(n)
	gs.new_character(1, "UITester")
	if is_instance_valid(main._char_select):
		main._char_select.queue_free()
		main._char_select = null
	await process_frame

	# ---------- A. navigation completeness, both directions ----------
	var menu_ids := {}
	for tbl in [main.BOTTOM, main.MORE_MENU, main.NAV_ALL]:
		for entry in tbl:
			menu_ids[String((entry as Dictionary)["id"])] = true
	for pid in main.PAGE_IDS:
		if not menu_ids.has(String(pid)):
			W("page '%s' has no menu entry — reachable only in code" % pid)
	for mid in menu_ids:
		if not (String(mid) in main.PAGE_IDS):
			E("menu entry '%s' points at no page — a dead tap" % mid)
	print("pages=%d, menu entries=%d" % [main.PAGE_IDS.size(), menu_ids.size()])

	# ---------- B. advance the save into a late-game state ----------
	# Everything a conditional panel keys off, turned on at once.
	gs.total_warps = 6
	gs.warp_shards = 400.0
	gs.warp_shards_spent = 0.0
	gs.cryo_unlocked = true
	for f in ["z11_unlocked", "z12_unlocked", "z13_unlocked", "z14_unlocked", "z15_unlocked",
			"warp_revealed", "recursion_revealed"]:
		gs.game_flags[f] = true
	# A relic in its slot (the Ship Designer panel only exists once earned).
	for mid in gd.MODULES:
		if String((gd.MODULES[mid] as Dictionary).get("slot", "")) == "relic":
			gs.module_inventory[mid] = 1
			gs.equipped_relic = String(mid)
			gs.game_flags[String(mid) + "_earned"] = true
			break
	# Capstones held (the Exotic Fabrication panel lists them).
	for c in ["OmegaAccelerator", "TemporalModule", "PrimordialArmor"]:
		gs.resources[c] = 1
	# Buildings, so Station Procurement has an online family.
	for bid in gd.BUILDINGS:
		if not (gd.BUILDINGS[bid] as Dictionary).get("yield", {}).is_empty():
			gs.buildings[bid] = 10
	gs.credits = 5_000_000_000
	gs.lifetime_credits = 5_000_000_000
	gs.skills["harvesting"] = 1_000_000
	gs.skills["fabrication"] = 1_000_000
	gs.skills["combat"] = 1_000_000
	gs.skills["infrastructure"] = 1_000_000
	for tid in gd.RESEARCH:
		gs.unlocked_research[tid] = true
	for sym in gd.RESOURCES:
		gs.resources[sym] = 100000
	gs.ensure_procurement()
	gs.ensure_standing_board()
	gs.generate_bounty_pool()
	await process_frame

	# ---------- C. every page must build in that state ----------
	var empty: Array = []
	for pid in main.PAGE_IDS:
		var n: int = await _visit(String(pid))
		if n == 0:
			empty.append(String(pid))
	if not empty.is_empty():
		E("pages built EMPTY in a late-game state: %s" % str(empty))
	print("late-game render: %d pages visited" % main.PAGE_IDS.size())

	# ---------- D. the panels that only exist when advanced ----------
	# Each of these is a branch that a fresh-save render can never reach.
	main._show("ship")
	await process_frame
	var ship_txt := _collect(main.pages["ship"])
	# Guarding on "if a relic is equipped" would let this check skip silently the
	# day the relic module is renamed, so a missing test subject is itself an error.
	if gs.equipped_relic == "":
		E("no relic module could be equipped — the Relic Slot panel went untested")
	elif ship_txt.find("RELIC") < 0:
		E("the Relic Slot panel does not render even with a relic equipped")
	main.craft_cat = "endgame"
	main._show("craft")
	await process_frame
	var craft_txt := _collect(main.pages["craft"])
	if craft_txt.find("CAPSTONE") < 0:
		E("the capstone panel does not render on the Exotic Fabrication tab")
	main._show("procurement")
	await process_frame
	var proc_txt := _collect(main.pages["procurement"])
	if proc_txt.find("DEMAND POOL") < 0:
		E("Station Procurement does not render its pool meter with families online")
	main.warp_view = "mastery"
	main._show("warp")
	await process_frame
	var warp_txt := _collect(main.pages["warp"])
	if warp_txt.find("ENGINEERING") < 0 or warp_txt.find("RECURSION") < 0:
		E("the warp tree does not render every revealed branch")
	print("conditional panels: relic, capstones, procurement, warp tree all rendered")

	# ---------- D2. a locked tech must say what is blocking it ----------
	# The research modal listed the parent edge but not req_tech, so a tech gated
	# on another tech showed every cost green with a dead Research button and
	# nothing naming what it was waiting for. Asserted on a FRESH save, since the
	# late-game state above has everything unlocked.
	var blocked := ""
	var blocker := ""
	gs.hard_reset()
	for tid in gd.RESEARCH:
		var t: Dictionary = gd.RESEARCH[tid]
		for rt in t.get("req_tech", []):
			if String(rt) != "" and String(rt) != String(t.get("parent", "")):
				blocked = String(tid)
				blocker = String(rt)
				break
		if blocked != "":
			break
	if blocked == "":
		W("no tech is gated on a req_tech — the prerequisite-visibility check did not run")
	else:
		gs.credits = 1_000_000_000
		for sym in gd.RESOURCES:
			gs.resources[sym] = 1_000_000
		main._show_research_detail(blocked)
		await process_frame
		# Read the MODAL, not the whole screen: the research page behind it lists
		# every tech name, so a screen-wide search passes on a modal that says
		# nothing — which is exactly how the first version of this check missed
		# the bug it was written for.
		var modal: Node = main._modal_stack.back() if not main._modal_stack.is_empty() else null
		var rt_txt := _collect(modal) if modal != null else ""
		var blocker_name := String((gd.RESEARCH[blocker] as Dictionary).get("name", blocker))
		if modal == null:
			E("the research detail modal did not open — its contents went unchecked")
		elif gs.research_available(blocked):
			E("'%s' should still be gated on '%s' — the check lost its subject" % [blocked, blocker])
		elif rt_txt.find("⊘ First research: " + blocker_name) < 0:
			E("the research modal does not name '%s', the tech blocking '%s' — the player sees every cost met and a dead button"
				% [blocker_name, blocked])
		else:
			print("locked tech '%s' names its blocker in the modal: %s" % [blocked, blocker_name])
		# Close the modal so it cannot leak into the rebuild checks below.
		for o in main._modal_stack.duplicate():
			if is_instance_valid(o):
				o.queue_free()
		await process_frame

	# ---------- E. rebuilding a page must not grow it ----------
	# Every page is rebuilt on refresh; a builder that appends instead of
	# clearing leaks children on every tick and eventually chokes the scroll.
	for pid in ["gather", "craft", "combat", "build", "ship", "warp", "procurement"]:
		main._show(String(pid))
		await process_frame
		var a := _list_count(String(pid))
		main._show("stats")
		await process_frame
		main._show(String(pid))
		await process_frame
		var b := _list_count(String(pid))
		if a != b:
			E("page '%s' changed size on rebuild (%d -> %d) — content is leaking" % [pid, a, b])

	# ---------- report ----------
	print("")
	if errs.is_empty():
		print("ERRORS: none")
	else:
		print("--- ERRORS (%d) ---" % errs.size())
		for e in errs:
			print("  x %s" % e)
	if not warns.is_empty():
		print("--- WARNINGS (%d) ---" % warns.size())
		for w in warns:
			print("  ! %s" % w)
	print("UI_AUDIT: %s" % ("FAIL" if not errs.is_empty() else "PASS"))
	quit()

## Flatten every Label/Button caption under a node so a panel's presence can be
## asserted by the words it puts on screen.
func _collect(node: Node) -> String:
	var out := ""
	if node is Label:
		out += (node as Label).text + "\n"
	elif node is Button:
		out += (node as Button).text + "\n"
	for c in node.get_children():
		out += _collect(c)
	return out
