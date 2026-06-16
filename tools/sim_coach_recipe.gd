extends SceneTree
## Verifies the coach picks the research-appropriate recipe for a material-target
## mission: Advanced Circuit (research Automation, unlocked) over Process Colony
## Salvage (lower level but research Deep Space Nav, NOT unlocked).

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

	# m029b state: Automation researched (from m029a4), Deep Space Nav NOT yet.
	gs.unlocked_research["automation"] = true
	# (deep_space_nav intentionally left locked)

	var pick: String = main._craft_recipe_for("AdvCircuit")
	print("recipe for AdvCircuit (automation only) = %s" % pick)
	if pick == "craft_adv_circuit":
		print("PASS coach targets the research-unlocked Advanced Circuit recipe")
	else:
		print("FAIL coach targets '%s' (expected craft_adv_circuit)" % pick)
		fail = true

	# The coach resolution for the actual mission points at craft (not the wrong card).
	var m: Dictionary = GameData.MISSIONS["m029b"]
	var res: Dictionary = main._coach_resolve(m)
	print("m029b coach resolve: page=%s card=%s" % [res.get("page", ""), res.get("card", "")])
	if res.get("page", "") == "craft" and res.get("card", "") == "craft_adv_circuit":
		print("PASS m029b coach points at Advanced Circuit on Craft")
	else:
		print("FAIL m029b coach resolve wrong")
		fail = true

	# Once Deep Space Nav is ALSO unlocked and the player out-levels both, the
	# lower-level craftable recipe is acceptable (either completes the material goal).
	gs.unlocked_research["deep_space_nav"] = true
	gs.add_xp("fabrication", 100000000)   # high level so both are craftable
	var pick2: String = main._craft_recipe_for("AdvCircuit")
	print("recipe when both unlocked + high level = %s (lvl-pref ok)" % pick2)
	if pick2 != "":
		print("PASS still resolves a craftable recipe when multiple are available")
	else:
		print("FAIL resolved nothing")
		fail = true

	if fail:
		print("COACH_RECIPE: FAIL")
		quit(1)
	print("COACH_RECIPE: PASS")
	quit()
