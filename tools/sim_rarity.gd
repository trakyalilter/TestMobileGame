extends SceneTree
## Verifies roll_rarity matches desktop "Restricted Rarity": never Common (0),
## Uncommon floor, with ~desktop weights for regular and boss kills.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	var gs = root.get_node("GameState")

	var fail := false
	var N := 40000

	for is_boss in [false, true]:
		var counts := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
		for _i in range(N):
			counts[gs.roll_rarity(is_boss)] += 1
		var label = "boss" if is_boss else "regular"
		var leg: float = 100.0 * counts[3] / float(N)
		var rare: float = 100.0 * counts[2] / float(N)
		var unc: float = 100.0 * counts[1] / float(N)
		print("%s: Common=%d Uncommon=%.1f%% Rare=%.1f%% Legendary=%.1f%%" % [label, counts[0], unc, rare, leg])
		if counts[0] != 0:
			print("FAIL %s dropped Commons (%d)" % [label, counts[0]])
			fail = true
		if counts[4] != 0:
			print("FAIL %s rolled Unique from the rarity table" % label)
			fail = true
		# Expected: regular leg 4 / rare 26 ; boss leg 15 / rare 35 (±1.5% tolerance).
		var exp_leg := 15.0 if is_boss else 4.0
		var exp_rare := 35.0 if is_boss else 26.0
		if absf(leg - exp_leg) <= 1.5 and absf(rare - exp_rare) <= 1.5:
			print("PASS %s weights match desktop" % label)
		else:
			print("FAIL %s weights off (leg %.1f vs %.1f, rare %.1f vs %.1f)" % [label, leg, exp_leg, rare, exp_rare])
			fail = true

	if fail:
		print("RARITY: FAIL")
		quit(1)
	print("RARITY: PASS")
	quit()
