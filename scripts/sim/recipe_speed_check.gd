extends Node
# PER-RECIPE PROCESSING SPEED TECHS MUST ACTUALLY DO SOMETHING (v175).
#
# processing_manager.get_recipe_speed_multiplier() builds a 6-recipe `upgrades_db`
# table of per-recipe speed techs and then never iterates it. The gathering twin
# (gathering_manager.gd, "if action_id in upgrades_db: for upgrade in ...") has the
# apply loop; the processing copy does not. Ten research nodes — fast_centrifuges,
# maglev_bearings, quantum_separators, catalytic_electrodes, ion_exchange,
# resonance_splitters, pyrolysis_control, blast_furnace, basic_electronics,
# hydraulic_press — were sold to the player, paid for, and produced a zero delta.
#
# Checked here, in the order that matters:
#   1. every tech named in upgrades_db exists in the research tree (a typo'd id is
#      the same dead purchase wearing a different hat);
#   2. unlocking each tech moves get_recipe_speed_multiplier for ITS recipe;
#   3. and does NOT move it for a different recipe (a wildcard apply would "fix"
#      check 2 while silently buffing everything);
#   4. the multiplier turns into real throughput — 60 s of ticks at 60 fps, counting
#      completed crafts. process_tick() completes at most ONE craft per tick and
#      complete_process() discards the overflow, so a multiplier that does not
#      survive into output is not a buff.
#
#   Godot --headless --path <root> res://scenes/recipe_speed_check.tscn

const FPS_DT := 1.0 / 60.0
const SIM_SECONDS := 60.0

var fails: int = 0

func _ready() -> void:
	await get_tree().process_frame
	if not GameState.sim_mode:
		print("[RSPD] ABORT: sim_mode is false")
		get_tree().quit(1)
		return
	GameState.set_process(false)
	var pm = GameState.processing_manager
	var rm = GameState.research_manager

	# The table lives inside the function as a local, so it cannot be read from
	# outside. Mirrored here ONLY as the list of things to test; every assertion below
	# is made against the real get_recipe_speed_multiplier(), never against this copy.
	# Check 1 catches the mirror drifting out of sync with the tree.
	var expect := {
		"centrifuge_dirt": [["fast_centrifuges", 0.25], ["maglev_bearings", 0.50], ["quantum_separators", 0.75]],
		"electrolysis": [["catalytic_electrodes", 0.25], ["ion_exchange", 0.50], ["resonance_splitters", 0.75]],
		"charcoal_burning": [["pyrolysis_control", 0.25]],
		"smelt_steel_basic": [["blast_furnace", 0.25]],
		"craft_circuit": [["basic_electronics", 0.25]],
		"press_graphite": [["hydraulic_press", 0.25]],
	}

	# ---- 1. the techs and recipes referenced must exist --------------------
	for rid in expect:
		if not pm.recipes.has(rid):
			_fail("upgrades_db names recipe '%s', which is not in processing_manager.recipes" % rid)
		for pair in expect[rid]:
			if not rm.tech_tree.has(str(pair[0])):
				_fail("upgrades_db names tech '%s', which is not in the research tree" % str(pair[0]))

	# ---- 2 + 3. each tech moves its own recipe and only its own ------------
	print("[RSPD] %-20s %-22s %8s %8s %8s   %s" % [
		"recipe", "tech", "before", "after", "delta", "verdict"])
	var other := "smelt_steel_basic"
	# Downstream multiplicative tail, measured rather than assumed. See the note below.
	var scale := 0.0
	for rid2 in expect:
		for pair2 in expect[rid2]:
			var tech := str(pair2[0])
			var want := float(pair2[1])
			rm.unlocked_techs.erase(tech)
			var before: float = pm.get_recipe_speed_multiplier(rid2)
			var cross_before: float = pm.get_recipe_speed_multiplier(other)
			rm.unlocked_techs.append(tech)
			var after: float = pm.get_recipe_speed_multiplier(rid2)
			var cross_after: float = pm.get_recipe_speed_multiplier(other)
			rm.unlocked_techs.erase(tech)
			var delta: float = after - before
			# The authored bonus is added into `multiplier` and THEN scaled by the
			# multiplicative tail of the same function (currently x1.10 x 1.11 = x1.221
			# from two building buffs, plus the warp tree). So a +0.25 tech correctly
			# shows up as +0.305 today. Asserting the raw authored number would fail on
			# a working game — it did on the first run of this probe — and hardcoding
			# 1.221 would rot the moment a building or the warp tree moves. Derive the
			# scale from the first measurement and require the rest to be proportional.
			if scale <= 0.0 and delta > 0.0:
				scale = delta / want
				print("[RSPD] derived downstream scale from the first live tech: x%.4f" % scale)
			var expect_delta: float = want * maxf(scale, 1.0)
			var ok: bool = delta > 0.0 and absf(delta - expect_delta) < 0.01
			print("[RSPD] %-20s %-22s %8.3f %8.3f %8.3f   %s" % [
				rid2, tech, before, after, delta,
				"OK" if ok else ("*** DEAD — pays nothing" if delta <= 0.0
					else "*** off — expected +%.3f" % expect_delta)])
			if delta <= 0.0:
				_fail("%s pays nothing on %s (authored +%.2f, measured %+.3f)" % [tech, rid2, want, delta])
			elif not ok:
				_fail("%s on %s is out of proportion: authored +%.2f should scale to +%.3f, measured %+.3f" % [
					tech, rid2, want, expect_delta, delta])
			if rid2 != other and absf(cross_after - cross_before) > 0.001:
				_fail("%s also moved an unrelated recipe (%s %+.3f) — the apply is not per-recipe" % [
					tech, other, cross_after - cross_before])

	# ---- 4. the multiplier must survive into real output -------------------
	# A speed number that never becomes a craft is not a buff. Tick at 60 fps because
	# complete_process() discards progress overflow: at a coarse tick the recipe would
	# be capped at one craft per tick and the whole gain would vanish into rounding.
	print("[RSPD] --- throughput, %.0f s at %d fps ---" % [SIM_SECONDS, int(1.0 / FPS_DT)])
	for rid3 in ["centrifuge_dirt", "electrolysis"]:
		var base_n: int = _throughput(pm, rm, rid3, [])
		var techs: Array = []
		for p3 in expect[rid3]:
			techs.append(str(p3[0]))
		var up_n: int = _throughput(pm, rm, rid3, techs)
		var ratio: float = float(up_n) / maxf(1.0, float(base_n))
		print("[RSPD] %-20s %4d crafts -> %4d crafts   x%.2f  (all %d techs)" % [
			rid3, base_n, up_n, ratio, techs.size()])
		# Not `up_n > base_n`: the dead-techs baseline measured electrolysis at 51 -> 52,
		# a single craft of boundary rounding, which would have passed a bare
		# greater-than and hidden the bug on that row. All three techs sum to +1.50 on a
		# base near 1.65, i.e. a theoretical ~1.9x, so require clearly more than noise.
		if ratio < 1.5:
			_fail("%s gained only x%.2f with every speed tech owned (%d -> %d crafts); +1.50 on this base should be ~x1.9" % [
				rid3, ratio, base_n, up_n])

	print("[RSPD] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


# Run the real recipe for SIM_SECONDS and count completions. Inputs are topped up every
# tick so the run measures SPEED, not whether the probe remembered to stock a reagent.
func _throughput(pm, rm, rid: String, techs: Array) -> int:
	for t in techs:
		if not (str(t) in rm.unlocked_techs):
			rm.unlocked_techs.append(str(t))
	var recipe: Dictionary = pm.recipes.get(rid, {})
	var made := 0
	var out_key := ""
	for k in (recipe.get("output", {}) as Dictionary):
		out_key = str(k)
		break
	pm.stop_action()
	_stock(recipe)
	pm.start_action(rid)
	var t2 := 0.0
	var before_out: float = GameState.resources.get_element_amount(out_key)
	while t2 < SIM_SECONDS:
		_stock(recipe)
		var had: float = GameState.resources.get_element_amount(out_key)
		pm.process_tick(FPS_DT)
		if GameState.resources.get_element_amount(out_key) > had:
			made += 1
		t2 += FPS_DT
	pm.stop_action()
	for t3 in techs:
		rm.unlocked_techs.erase(str(t3))
	# Guard against measuring a recipe that never started: zero output both sides would
	# read as "no regression" and pass check 4 vacuously.
	if made == 0 and before_out >= 0.0:
		print("[RSPD] note: %s completed 0 crafts — check stock/gating, not speed" % rid)
	return made


func _stock(recipe: Dictionary) -> void:
	GameState.resources.add_currency("credits", 1.0e9)
	for item in (recipe.get("input", {}) as Dictionary):
		GameState.resources.add_element(str(item), 1000.0, true)


func _fail(msg: String) -> void:
	print("[RSPD] FAIL: %s" % msg)
	fails += 1
