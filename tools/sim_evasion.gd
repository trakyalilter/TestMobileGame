extends SceneTree
## Verifies module evasion renders as a flat value (e.g. "Evasion 15"), not a
## bogus percentage ("Evasion 1500%").

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	var fail := false

	# A module with a flat evasion stat.
	var lines: Array = main._module_stat_lines({"eva": 15.0, "energy_load": 10.0})
	var txts := []
	for l in lines:
		txts.append(str(l.get("text", "")))
	print("stat lines: %s" % str(txts))
	var eva_line := ""
	for t in txts:
		if "Evasion" in t:
			eva_line = t
	if eva_line == "Evasion 15":
		print("PASS evasion shows flat (Evasion 15)")
	else:
		print("FAIL evasion line wrong: '%s'" % eva_line)
		fail = true
	if "%" in eva_line:
		print("FAIL evasion still shows a percent")
		fail = true

	# Fractional evasion keeps one decimal.
	var lines2: Array = main._module_stat_lines({"eva": 5.4})
	var t2 := str(lines2[0].get("text", ""))
	print("fractional: %s" % t2)
	if t2 == "Evasion 5.4":
		print("PASS fractional evasion trimmed to 5.4")
	else:
		print("FAIL fractional evasion wrong: '%s'" % t2)
		fail = true

	# crit_chance / atk_speed_bonus must STILL be percentages.
	var lines3: Array = main._module_stat_lines({"crit_chance": 0.05, "atk_speed_bonus": 0.1})
	var pcts := []
	for l in lines3:
		pcts.append(str(l.get("text", "")))
	print("pct stats: %s" % str(pcts))
	var crit_ok := false
	for t in pcts:
		if "Crit 5%" in t:
			crit_ok = true
	if crit_ok:
		print("PASS crit still shows as percent")
	else:
		print("FAIL crit percent broke")
		fail = true

	if fail:
		print("EVASION: FAIL")
		quit(1)
	print("EVASION: PASS")
	quit()
