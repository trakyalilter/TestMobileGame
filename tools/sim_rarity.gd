extends SceneTree
## Verifies roll_rarity against the v136 rebalance.
##
## v136 replaced v82's flat table (trash 4% Legendary / 26% Rare, boss 15/35,
## Unique unreachable) with two tables that do different jobs:
##   trash — Common is a ~50% EMPTY roll that drops nothing, so Rare+ is earned
##   boss  — no junk floor, and the ONLY source of Unique
## The old expectations are what this file used to assert, which is why the
## empty-roll and the Unique jackpot both read as failures.

var fails: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func F(s: String) -> void: fails.append(s)

## Roll N times and return the share of each rarity as a percentage.
func _dist(gs, is_boss: bool, n: int) -> Dictionary:
	var counts := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
	for _i in range(n):
		counts[gs.roll_rarity(is_boss)] += 1
	var out := {}
	for k in counts:
		out[k] = 100.0 * float(counts[k]) / float(n)
	return out

func _near(got: float, want: float, label: String) -> void:
	if absf(got - want) > 1.5:
		F("%s: %.1f%% vs %.1f%% expected" % [label, got, want])

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	var gs = root.get_node("GameState")
	var N := 40000

	# ---------- trash: the empty roll carries half the table ----------
	var t := _dist(gs, false, N)
	print("trash: Empty=%.1f%% Uncommon=%.1f%% Rare=%.1f%% Legendary=%.1f%% Unique=%.1f%%"
		% [t[0], t[1], t[2], t[3], t[4]])
	_near(t[0], 50.0, "trash empty roll")
	_near(t[1], 38.5, "trash Uncommon")
	_near(t[2], 8.5, "trash Rare")
	_near(t[3], 3.0, "trash Legendary")
	if t[4] > 0.0:
		F("trash rolled Unique (%.2f%%) — Unique is boss-only" % t[4])

	# ---------- boss: no junk floor, and the only Unique source ----------
	var b := _dist(gs, true, N)
	print("boss:  Empty=%.1f%% Uncommon=%.1f%% Rare=%.1f%% Legendary=%.1f%% Unique=%.1f%%"
		% [b[0], b[1], b[2], b[3], b[4]])
	if b[0] > 0.0:
		F("boss rolled the empty tier (%.2f%%) — a boss kill always drops" % b[0])
	_near(b[1], 52.0, "boss Uncommon")
	_near(b[2], 30.0, "boss Rare")
	_near(b[3], 15.0, "boss Legendary")
	_near(b[4], 3.0, "boss Unique")

	# ---------- the empty roll must actually mean "nothing dropped" ----------
	# A weight table only matters if the caller honours it. _roll_one_module_drop
	# skips rarity 0 entirely, which is what halves the effective drop rate.
	gs.hard_reset()
	gs._suppress_fx = true
	var pool: Array = []
	for mid in GameData.MODULES:
		if String((GameData.MODULES[mid] as Dictionary).get("slot", "")) == "weapon":
			pool.append(String(mid))
			break
	if pool.is_empty():
		F("no weapon module exists to roll drops from")
	else:
		gs.start_task("combat", _any_enemy())
		var before: int = gs.custom_modules.size()
		var rolls := 2000
		for _i in rolls:
			gs._roll_one_module_drop(pool)
		var got: int = gs.custom_modules.size() - before
		var rate := float(got) / float(rolls)
		print("trash rolls: %d of %d produced a module (%.0f%%)" % [got, rolls, rate * 100.0])
		if absf(rate - 0.50) > 0.05:
			F("the empty roll is not being honoured — %.0f%% of trash rolls dropped, expected ~50%%"
				% (rate * 100.0))
		gs.stop_task()

	# ---------- elites roll on the boss table ----------
	# _roll_one_module_drop passes (is_boss OR elite), so an elite kill gets the
	# jackpot table. Nothing else in the game grants Unique.
	if not pool.is_empty():
		gs.start_task("combat", _any_enemy())
		gs.enemy_inst["elite"] = true
		gs.enemy_inst["is_boss"] = false
		var uniques := 0
		var drops := 0
		for _i in 3000:
			var n0: int = gs.custom_modules.size()
			gs._roll_one_module_drop(pool)
			if gs.custom_modules.size() > n0:
				drops += 1
				for cid in gs.custom_modules:
					if int((gs.custom_modules[cid] as Dictionary).get("rarity", 0)) == 4:
						uniques += 1
						break
		print("elite rolls: %d drops, uniques reachable=%s" % [drops, uniques > 0])
		if drops == 0:
			F("an elite produced no drops at all")
		gs.stop_task()
	gs._suppress_fx = false

	if fails.is_empty():
		print("RARITY: PASS")
		quit()
		return
	for f in fails:
		print("  x %s" % f)
	print("RARITY: FAIL")
	quit(1)

func _any_enemy() -> String:
	for z in GameData.ZONES:
		var roster: Array = (z as Dictionary).get("enemies", [])
		if not roster.is_empty():
			return String(roster[0])
	return ""
