extends SceneTree
## Page-render smoke: load the real main scene and build every page so any
## UI build error against the new data surfaces as a SCRIPT ERROR in stderr.
## Phase 4 extension: also asserts the resist/weakness/hazard/trinity UI text is
## actually present in the built tree.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

# Recursively collect all Label AND Button text under a node (button labels carry
# load-bearing UI like "Save"/"Load"/"Reroll"/"Claim").
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
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	# Boot now lands on character-select (no slot loaded). Enter a fresh slot so the
	# in-game state (hull, standing board, missions, bounty) is initialized, then
	# dismiss the select overlay before driving the pages.
	var gs = root.get_node("GameState")
	for n in range(1, gs.SLOT_COUNT + 1):
		gs.delete_slot(n)
	gs.new_character(1, "Tester")
	if is_instance_valid(main._char_select):
		main._char_select.queue_free()
		main._char_select = null
	main._refresh_all()
	await process_frame
	# Give the player gear + research so combat/ship/research pages have content.
	for mid in ["z1_kinetic", "z1_energy", "z1_shield", "z1_battery"]:
		gs.module_inventory[mid] = 1
		gs.equip_module(mid)
	for pid in main.PAGE_IDS:
		main._show(pid)
		await process_frame
		print("built page: %s" % pid)
	var fail := false

	# --- Task 1: enemy card + Intel for an enemy WITH resists (z1_lunar_drone).
	var card = main._enemy_card("z1_lunar_drone", GameData.ENEMIES["z1_lunar_drone"])
	root.add_child(card)
	await process_frame
	var ct := []
	_collect_text(card, ct)
	if _has(ct, "WEAK") and _has(ct, "KIN") and _has(ct, "DEALS"):
		print("PASS enemy_card affinity: WEAK/KIN/DEALS present")
	else:
		print("FAIL enemy_card affinity missing — got: %s" % str(ct))
		fail = true
	card.queue_free()

	main._show_enemy_intel("z1_lunar_drone")
	await process_frame
	var it := []
	_collect_text(main, it)
	if _has(it, "WEAK") and _has(it, "RESIST"):
		print("PASS intel modal: WEAK + RESIST present")
	else:
		print("FAIL intel modal missing WEAK/RESIST — got: %s" % str(it))
		fail = true

	# --- Task 3: hazard view (locked + a hazard name present).
	main._show("hazard")
	await process_frame
	var hz := []
	_collect_text(main.pages["hazard"], hz)
	if _has(hz, "EMP Nexus") and _has(hz, "Waves"):
		print("PASS hazard view: zone name + wave info present")
	else:
		print("FAIL hazard view missing — got: %s" % str(hz))
		fail = true

	# --- Task 4: trinity view on the ship loadout. The trinity panel now only
	# surfaces sets the player has a piece equipped for, so fit one Architect's
	# Regalia module first.
	gs.module_inventory["z1_unique_armor"] = 1
	gs.equip_module("z1_unique_armor")
	main.ship_view = "loadout"
	main._show("ship")
	await process_frame
	var tv := []
	_collect_text(main.pages["ship"], tv)
	if _has(tv, "TRINITY SET BONUSES") and _has(tv, "Architect's Regalia"):
		print("PASS trinity view: header + set name present")
	else:
		print("FAIL trinity view missing — got: %s" % str(tv))
		fail = true
	# And it must NOT list a set the player has zero pieces of (Leviathan's Crown).
	if _has(tv, "Leviathan's Crown"):
		print("FAIL trinity view shows an un-owned set (Leviathan's Crown)")
		fail = true
	else:
		print("PASS trinity view: un-owned sets hidden")

	# --- Task 2: battle view with a hazard-style enemy; affinity + wave readout.
	gs.start_task("combat", "z1_lunar_drone")
	main._show("combat")
	await process_frame
	main._refresh_current()
	await process_frame
	var bt := []
	_collect_text(main.pages["combat"], bt)
	if _has(bt, "DEALS") and (_has(bt, "WEAK") or _has(bt, "RESIST")):
		print("PASS battle view: live affinity readout present")
	else:
		print("FAIL battle view affinity missing — got: %s" % str(bt))
		fail = true

	# A few combat ticks to make sure the live combat readout doesn't error.
	for _i in range(40):
		gs._tick_combat(0.5)
		main._process(0.016)
		await process_frame

	# --- Hazard run: start one to confirm the wave counter renders.
	gs.boss_kills["z2_boss_monolith"] = 1   # unlock EMP Nexus
	# Fit the counter module so start_hazard succeeds.
	gs.module_inventory["faraday_hull"] = 1
	gs.equip_module("faraday_hull")
	if gs.start_hazard("emp_nexus"):
		main._show("combat")
		await process_frame
		main._refresh_current()
		await process_frame
		var wt := []
		_collect_text(main.pages["combat"], wt)
		if _has(wt, "WAVE"):
			print("PASS hazard run: WAVE counter present in battle view")
		else:
			print("FAIL hazard run WAVE counter missing — got: %s" % str(wt))
			fail = true
		gs.stop_task()
	else:
		print("NOTE hazard run did not start (unlock/counter gate) — skipping wave assert")

	# --- Phase 8 Task 2: Standing Orders board page (6 orders, claim/reroll).
	main._show("standing")
	await process_frame
	var so := []
	_collect_text(main.pages["standing"], so)
	# An order title is "Stockpile: X" (gather) or "Sweep: X" (hunt), plus a Reroll
	# button and a Progress readout.
	if (_has(so, "Stockpile") or _has(so, "Sweep")) and _has(so, "Reroll") and _has(so, "Progress"):
		print("PASS standing orders: order target + Reroll + Progress present")
	else:
		print("FAIL standing orders missing — got: %s" % str(so))
		fail = true

	# --- Phase 8 Task 1: Warp Mastery Tree sub-view (branch + node names).
	# Give the player warps so both branches reveal, and shards to spend.
	gs.total_warps = 2
	gs.warp_shards = 20.0
	main.warp_view = "mastery"
	main._show("warp")
	await process_frame
	var wm := []
	_collect_text(main.pages["warp"], wm)
	if _has(wm, "ENGINEERING") and _has(wm, "COMBAT") and _has(wm, "Yield Calibration") and _has(wm, "Hardened Hull"):
		print("PASS warp mastery: branch headers + node names present")
	else:
		print("FAIL warp mastery missing — got: %s" % str(wm))
		fail = true
	main.warp_view = "core"

	# --- Phase 8 Task 3: loadout preset controls (Save / Load / Clear).
	main.ship_view = "loadout"
	main._show("ship")
	await process_frame
	var lp := []
	_collect_text(main.pages["ship"], lp)
	if _has(lp, "LOADOUT PRESETS") and _has(lp, "Save") and _has(lp, "Load") and _has(lp, "Slot 1"):
		print("PASS loadout presets: Save/Load + Slot label present")
	else:
		print("FAIL loadout presets missing — got: %s" % str(lp))
		fail = true

	# --- Ship split: Shipyard (Modules+Hulls) vs Ship Designer (Loadout/Armory/Fittings).
	# Shipyard · Modules sub-tab → must show the MODULE SHOP.
	main.shipyard_view = "modules"
	main._show("shipyard")
	await process_frame
	var sm := []
	_collect_text(main.pages["shipyard"], sm)
	if _has(sm, "SHIPYARD") and _has(sm, "MODULE SHOP"):
		print("PASS shipyard modules: MODULE SHOP present")
	else:
		print("FAIL shipyard modules missing MODULE SHOP — got: %s" % str(sm))
		fail = true
	# Shipyard · Hulls sub-tab → must show the HULLS section.
	main.shipyard_view = "hulls"
	main._show("shipyard")
	await process_frame
	var sh := []
	_collect_text(main.pages["shipyard"], sh)
	if _has(sh, "HULLS"):
		print("PASS shipyard hulls: HULLS section present")
	else:
		print("FAIL shipyard hulls missing — got: %s" % str(sh))
		fail = true

	# Ship Designer · Armory sub-tab → owned-pool with a sort control (Power/Zone/Rarity)
	# and a tap-to-equip action. The starter gear was equipped above, so add a spare
	# owned module so the Armory has at least one card.
	gs.module_inventory["z1_armor"] = int(gs.module_inventory.get("z1_armor", 0)) + 1
	main.ship_mod_slot = "armor"
	main.ship_view = "armory"
	main._show("ship")
	await process_frame
	var ar := []
	_collect_text(main.pages["ship"], ar)
	# "Armory" label (sub-tab) + sort control (Power/Zone/Rarity) + tap-to-detail tiles
	# (Equip now lives in the per-module detail modal, not inline on the tile).
	if _has(ar, "Armory") and _has(ar, "Power") and _has(ar, "Zone") and _has(ar, "Rarity") and _has(ar, "details"):
		print("PASS armory: label + sort (Power/Zone/Rarity) + tap-to-detail tiles")
	else:
		print("FAIL armory missing — got: %s" % str(ar))
		fail = true
	# Ship Designer must NOT show the MODULE SHOP anymore (fabrication moved).
	if _has(ar, "MODULE SHOP"):
		print("FAIL ship designer still shows MODULE SHOP — got: %s" % str(ar))
		fail = true
	else:
		print("PASS ship designer: no MODULE SHOP (fabrication split out)")

	# --- COACH_PAGE routing for the split.
	if main.COACH_PAGE.get("craft", "") == "shipyard" and main.COACH_PAGE.get("construct", "") == "shipyard" and main.COACH_PAGE.get("loadout_check", "") == "ship":
		print("PASS coach routing: craft/construct→shipyard, loadout_check→ship")
	else:
		print("FAIL coach routing wrong — got: %s" % str(main.COACH_PAGE))
		fail = true

	if fail:
		print("PAGES: FAIL")
		quit(1)
	print("PAGES: PASS")
	quit()
