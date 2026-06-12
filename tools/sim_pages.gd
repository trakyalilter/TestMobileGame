extends SceneTree
## Page-render smoke: load the real main scene and build every page so any
## UI build error against the new data surfaces as a SCRIPT ERROR in stderr.
## Phase 4 extension: also asserts the resist/weakness/hazard/trinity UI text is
## actually present in the built tree.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

# Recursively collect all Label text under a node.
func _collect_text(node: Node, out: Array) -> void:
	if node is Label:
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
	# Give the player gear + research so combat/ship/research pages have content.
	var gs = root.get_node("GameState")
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

	# --- Task 4: trinity view on the ship loadout.
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

	if fail:
		print("PAGES: FAIL")
		quit(1)
	print("PAGES: PASS")
	quit()
