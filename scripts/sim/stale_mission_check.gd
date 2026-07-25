extends Node
# v141d: stale atlas_lookup beat (m019e re-activated on an old save) must auto-
# complete when the material is already owned, and the frontier pick must prefer the
# later chapter beat. No hard_reset / no save writes. Run with --user-dir <scratch>.
func _ready() -> void:
	var fails := 0
	var mm = GameState.mission_manager
	var res = GameState.resources

	# Simulate the reported save: m019e active+incomplete, m029a8 active (real current).
	for mid in ["m019e", "m029a8"]:
		if mid in mm.missions:
			mm.missions[mid]["active"] = true
			mm.missions[mid]["completed"] = false
			mm.missions[mid]["current_qty"] = 0.0
			if not mid in mm.active_missions: mm.active_missions.append(mid)

	# Res1 NOT owned -> lesson stays live (genuine first-timer keeps the beat).
	res.elements["Res1"] = 0.0
	mm.sync_progress()
	# v145: was `:=`. Dictionary subscripting yields Variant, so the inference fails
	# with "Cannot infer the type of c1" — the script never loaded, the scene fell
	# through to the real game, and the probe appeared to "run long" forever instead
	# of reporting. Explicit bool, per the documented GDScript gotcha.
	var c1: bool = not mm.missions["m019e"]["completed"]

	# Res1 owned (the 27h save) -> m019e auto-completes, can't drive the arrow.
	res.add_element("Res1", 5)
	mm.sync_progress()
	var c2: bool = mm.missions["m019e"]["completed"]

	# Frontier pick data: among active tutorial missions, the LATER-defined one wins.
	var chosen := ""
	for mid in mm.missions:
		if not mid in mm.active_missions: continue
		var m = mm.missions[mid]
		if m.get("completed", false) or String(m.get("tag","")) != "[TUTORIAL]": continue
		chosen = mid
	var c3 := chosen == "m029a8"   # m019e now completed -> skipped; frontier = m029a8

	for pair in [["lesson live when Res1 unowned", c1], ["m019e auto-completes when owned", c2],
			["frontier = m029a8 (not stale m019e)", c3]]:
		if not pair[1]: fails += 1
		print("[STALE] %-38s %s" % [pair[0], "OK" if pair[1] else "*** FAIL (chosen=%s)" % chosen])
	print("[STALE] %s" % ("ALL PASS" if fails == 0 else "*** %d FAIL" % fails))
	get_tree().quit(1 if fails > 0 else 0)
