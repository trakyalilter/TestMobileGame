extends SceneTree
## Verifies the v0.2.1 Fleet system: warp-gated unlock, capacity = 1+warps,
## build/scrap from resources, combat damage multiplier (25%/ship, cap +100%),
## save/load, and the Fleet page builds + is nav-gated.

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

	var fail := false

	# Locked before any warp.
	if not gs.fleet_unlocked() and gs.fleet_combat_mult() == 1.0 and not main._nav_visible("fleet"):
		print("PASS fleet locked + hidden pre-warp, combat mult = 1.0")
	else:
		print("FAIL fleet should be locked pre-warp")
		fail = true

	# After 1 warp: unlocked, capacity 2, nav visible.
	gs.total_warps = 1
	if gs.fleet_unlocked() and gs.fleet_capacity() == 2 and main._nav_visible("fleet"):
		print("PASS fleet unlocks after first warp (cap=2)")
	else:
		print("FAIL fleet unlock/capacity wrong (cap=%d)" % gs.fleet_capacity())
		fail = true

	# Build a frigate (give resources).
	for r in ["Water", "Dirt", "Steel", "Circuit"]:
		gs.resources[r] = 1000000
	var ok: bool = gs.fleet_build("fleet_frigate")
	print("build frigate: %s, count=%d, mult=%.2f" % [str(ok), gs.fleet_count(), gs.fleet_combat_mult()])
	if ok and gs.fleet_count() == 1 and abs(gs.fleet_combat_mult() - 1.25) < 0.001:
		print("PASS 1 ship => +25% combat")
	else:
		print("FAIL build/mult wrong")
		fail = true
	# Resources were spent.
	if gs.amount("Water") == 1000000 - 40000:
		print("PASS build spent resources")
	else:
		print("FAIL build did not spend correctly")
		fail = true

	# Capacity cap: cap is 2 at 1 warp, so a 2nd build works, a 3rd is blocked.
	gs.fleet_build("fleet_frigate")
	var blocked: bool = not gs.fleet_can_build("fleet_frigate")  # at cap (2/2)
	print("at cap %d/%d, can_build=%s" % [gs.fleet_count(), gs.fleet_capacity(), str(not blocked)])
	if gs.fleet_count() == 2 and blocked:
		print("PASS capacity cap enforced")
	else:
		print("FAIL capacity cap not enforced")
		fail = true

	# Combat cap: at high warps build 5 ships -> +100% (capped), not +125%.
	gs.total_warps = 9
	for i in range(3):
		gs.fleet_build("fleet_frigate")
	print("5 ships mult=%.2f (cap +100%%)" % gs.fleet_combat_mult())
	if abs(gs.fleet_combat_mult() - 2.0) < 0.001:
		print("PASS combat bonus capped at +100%")
	else:
		print("FAIL combat cap wrong (%.2f)" % gs.fleet_combat_mult())
		fail = true

	# Scrap reduces count.
	var before: int = gs.fleet_count()
	gs.fleet_scrap(0)
	if gs.fleet_count() == before - 1:
		print("PASS scrap removes a ship")
	else:
		print("FAIL scrap failed")
		fail = true

	# Save/load round-trip.
	gs.save_game()
	var saved: int = gs.fleet_count()
	gs.fleet_ships = []
	gs.load_game()
	if gs.fleet_count() == saved:
		print("PASS fleet persists through save/load (%d)" % saved)
	else:
		print("FAIL fleet not persisted (%d vs %d)" % [gs.fleet_count(), saved])
		fail = true

	# Higher-tier hull gated by min_warps.
	gs.total_warps = 2
	if not gs.fleet_can_build("fleet_cruiser"):  # needs 6 warps
		print("PASS higher-tier hull gated by warps")
	else:
		print("FAIL cruiser buildable too early")
		fail = true

	# Fleet page builds without error and shows the bonus.
	main._refresh_all()
	main._show("fleet")
	await process_frame
	var t := []
	_collect_text(main.pages["fleet"], t)
	if _has(t, "FLEET COMMAND") and _has(t, "COMBAT DAMAGE"):
		print("PASS fleet page renders")
	else:
		print("FAIL fleet page missing content")
		fail = true

	if fail:
		print("FLEET: FAIL")
		quit(1)
	print("FLEET: PASS")
	quit()

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
