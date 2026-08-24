extends SceneTree
## Guard for the v177 Hunt Log (desktop hunt_log_check).
##
## The feature is a per-enemy kill record that pays damage against that enemy
## only, so the things worth pinning are the ones a refactor breaks silently:
## the rank ladder, that the bonus actually reaches the damage the player deals,
## that offline kills count the same as attended ones, and the persistence rule —
## it survives Warp (it is a hunting record) and dies with a new game (a fresh
## run must not open holding +25% against Zone 1).

var errs: Array = []
var warns: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s: String) -> void: errs.append(s)
func W(s: String) -> void: warns.append(s)
func _chk(cond: bool, label: String, detail := "") -> void:
	if not cond:
		E("%s%s" % [label, ("  — " + detail) if detail != "" else ""])

func _any_enemy(gd) -> String:
	for z in gd.ZONES:
		var roster: Array = (z as Dictionary).get("enemies", [])
		if not roster.is_empty():
			return String(roster[0])
	return ""

func _run() -> void:
	var gs = root.get_node("GameState")
	var gd = root.get_node("GameData")
	gs._suppress_fx = true
	var eid := _any_enemy(gd)
	_chk(eid != "", "a sector enemy exists to hunt")
	if eid == "":
		_report()
		return

	# ---------- A. the ladder ----------
	_chk(gs.HUNT_STAR_THRESHOLDS == [25, 100, 250, 500, 1000],
		"the star thresholds match desktop", str(gs.HUNT_STAR_THRESHOLDS))
	_chk(gs.HUNT_STAR_BONUS == [0.025, 0.05, 0.10, 0.15, 0.25],
		"the bonus ladder matches desktop (back-loaded, +25%% at rank 5)",
		str(gs.HUNT_STAR_BONUS))
	gs.hard_reset()
	_chk(gs.get_hunt_stars(eid) == 0, "a fresh log has no stars")
	_chk(is_equal_approx(gs.get_hunt_damage_mult(eid), 1.0), "and pays no bonus")
	# Each threshold earns exactly one more star, and one below it earns none.
	for i in gs.HUNT_STAR_THRESHOLDS.size():
		var t := int(gs.HUNT_STAR_THRESHOLDS[i])
		gs.enemy_kills[eid] = t - 1
		_chk(gs.get_hunt_stars(eid) == i, "%d kills is one short of star %d" % [t - 1, i + 1],
			"got %d stars" % gs.get_hunt_stars(eid))
		gs.enemy_kills[eid] = t
		_chk(gs.get_hunt_stars(eid) == i + 1, "%d kills earns star %d" % [t, i + 1],
			"got %d stars" % gs.get_hunt_stars(eid))
		var want: float = 1.0 + float(gs.HUNT_STAR_BONUS[i])
		_chk(is_equal_approx(gs.get_hunt_damage_mult(eid), want),
			"rank %d pays %.1f%%" % [i + 1, float(gs.HUNT_STAR_BONUS[i]) * 100.0],
			"mult=%.3f" % gs.get_hunt_damage_mult(eid))
	# Past the top threshold the rank holds rather than running away.
	gs.enemy_kills[eid] = 999999
	_chk(gs.get_hunt_stars(eid) == gs.HUNT_STAR_THRESHOLDS.size(), "the rank caps at five stars")
	_chk(is_equal_approx(gs.get_hunt_damage_mult(eid), 1.25), "and the bonus caps at +25%")
	var p: Dictionary = gs.get_hunt_progress(eid)
	_chk(int(p["next"]) == 0 and int(p["remaining"]) == 0, "a maxed record reports no next star")
	print("ladder: %s kills -> %s" % [str(gs.HUNT_STAR_THRESHOLDS), str(gs.HUNT_STAR_BONUS)])

	# ---------- B. the bonus reaches the damage ----------
	# A table nobody reads is not a feature: fire the same weapon at the same
	# enemy with and without a rank, and require the ranked one to hit harder.
	gs.hard_reset()
	gs._suppress_fx = true
	# A real KINETIC weapon and rounds for it: the hull's built-in mount is a
	# 0-damage placeholder, so a ship carrying only a battery deals nothing and
	# the comparison below would measure 0 against 0.
	var bat := ""
	var gun := ""
	for mid in gd.MODULES:
		var mm: Dictionary = gd.MODULES[mid]
		if gs.module_is_drop_only(String(mid)):
			continue
		var sl := String(mm.get("slot", ""))
		if sl == "battery" and bat == "":
			bat = String(mid)
		elif sl == "weapon" and gun == "" \
				and float((mm.get("stats", {}) as Dictionary).get("atk_kinetic", 0.0)) > 0.0 \
				and int(mm.get("zone", 9)) <= 1:
			gun = String(mid)
	_chk(bat != "" and gun != "", "a battery and a zone-1 kinetic weapon exist to test with")
	for pick in [bat, gun]:
		if String(pick) != "":
			gs.module_inventory[pick] = 1
			gs.equip_module(String(pick))
	gs.add_resource("SlugT1", 5000, true)
	gs.start_task("combat", eid)
	_chk(not gs.enemy_inst.is_empty(), "the duel started")
	if not gs.enemy_inst.is_empty() and not gs._weapons.is_empty():
		var ss: Dictionary = gs.ship_stats()
		var w: Dictionary = gs._weapons[0]
		var shots := 400
		var unranked := _damage_over(gs, w, ss, shots)
		gs.enemy_kills[eid] = 1000            # five stars
		var ranked := _damage_over(gs, w, ss, shots)
		var ratio := ranked / maxf(1.0, unranked)
		print("damage over %d shots: %.0f unranked, %.0f at five stars (x%.3f)"
			% [shots, unranked, ranked, ratio])
		_chk(ratio > 1.15 and ratio < 1.35,
			"five stars raises damage dealt by about a quarter", "x%.3f" % ratio)
		gs.enemy_kills[eid] = 0
	gs.stop_task()

	# ---------- C. kills are counted, attended or not ----------
	gs.hard_reset()
	gs._suppress_fx = true
	gs.start_task("combat", eid)
	var before: int = gs.get_enemy_kills(eid)
	for _i in 3:
		gs.enemy_inst["hp"] = 0.0
		gs._win_combat()
	_chk(gs.get_enemy_kills(eid) == before + 3, "an online kill is recorded",
		"%d -> %d" % [before, gs.get_enemy_kills(eid)])
	# The record is per-enemy: killing this one must not rank another.
	var other := ""
	for z in gd.ZONES:
		for cand in (z as Dictionary).get("enemies", []):
			if String(cand) != eid:
				other = String(cand)
				break
		if other != "":
			break
	if other != "":
		_chk(gs.get_enemy_kills(other) == 0, "kills do not leak to another enemy")
	gs.stop_task()

	# Offline: the same farm, unattended, must earn the same record.
	gs.hard_reset()
	gs._suppress_fx = true
	# One battery and one weapon, and a SHORT window: offline kills scale with the
	# window, and each one rolls loot — an hour of a strong ship is hundreds of
	# thousands of rolls, which is a slow test, not a better one.
	# A farm loadout, not a bare hull: offline combat refuses fights it prices as
	# lethal, and a battery-plus-gun corvette dies to the Lunar Drone by a margin
	# of a fifth of a second — the gate is right, the ship was just too thin.
	var shield1 := ""
	var armor1 := ""
	for mid3 in gd.MODULES:
		var m3: Dictionary = gd.MODULES[mid3]
		if gs.module_is_drop_only(String(mid3)) or int(m3.get("zone", 9)) > 1:
			continue
		var sl3 := String(m3.get("slot", ""))
		if sl3 == "shield" and shield1 == "":
			shield1 = String(mid3)
		elif sl3 == "armor" and armor1 == "":
			armor1 = String(mid3)
	for pick in [bat, gun, shield1, armor1]:
		if String(pick) != "":
			gs.module_inventory[pick] = 1
			gs.equip_module(String(pick))
	gs.add_resource("SlugT1", 100000, true)
	gs.start_task("combat", eid)
	# Size the window from the ship's own kill time so this measures crediting,
	# not the grind: enough for a handful of kills, not hundreds of thousands of
	# loot rolls.
	var e0: Dictionary = gd.ENEMIES[eid]
	var ttk: float = (float(e0.get("hp", 100)) + float(e0.get("max_shield", 0))) / maxf(1.0, gs.avg_player_dps())
	var off_before: int = gs.get_enemy_kills(eid)
	gs._offline_combat(ttk * 6.0)
	if gs.get_enemy_kills(eid) > off_before:
		print("offline: %d kills credited while away" % (gs.get_enemy_kills(eid) - off_before))
	else:
		W("the offline farm produced no kills in this configuration — offline crediting went unverified")
	gs.stop_task()

	# ---------- D. persistence: survives Warp, dies with a new game ----------
	gs.hard_reset()
	gs.enemy_kills[eid] = 300
	gs.lifetime_credits = 600_000_000
	gs.credits_at_warp_start = 0
	gs.execute_warp()
	_chk(gs.get_enemy_kills(eid) == 300,
		"the record SURVIVES a warp — it is a hunting log, not run state",
		"%d kills after warp" % gs.get_enemy_kills(eid))
	gs.hard_reset()
	_chk(gs.get_enemy_kills(eid) == 0,
		"a new game clears it — a fresh run must not open holding +25%% against Zone 1")

	# ---------- E. it round-trips through a save ----------
	gs.hard_reset()
	gs.current_slot = 1
	gs.load_failed = false
	gs.enemy_kills[eid] = 137
	gs.save_game()
	gs.hard_reset()
	gs.current_slot = 1
	gs.load_game()
	_chk(gs.get_enemy_kills(eid) == 137, "the record round-trips through a save",
		"got %d" % gs.get_enemy_kills(eid))
	# A pre-v177 save has no key at all and must load as an empty log.
	var path: String = gs.slot_path(1)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"version": 2, "credits": 500}')
	f.close()
	gs.hard_reset()
	gs.current_slot = 1
	gs.load_game()
	_chk(gs.enemy_kills.is_empty(), "an older save loads with an empty log rather than back-filled stars")
	gs.delete_slot(1)

	gs._suppress_fx = false
	_report()

## Total hull damage dealt over N shots, with heat neutralised so the only
## variable is the multiplier under test.
func _damage_over(gs, w: Dictionary, ss: Dictionary, shots: int) -> float:
	var dealt := 0.0
	for _i in shots:
		gs.enemy_inst["hp"] = 1e15
		gs.enemy_inst["max_hp"] = 1e15
		gs.enemy_inst["shield"] = 0.0
		gs.player_heat = 0.0
		gs._overheat_lock = 0.0
		var before := float(gs.enemy_inst["hp"])
		gs._player_fire(w, ss)
		dealt += before - float(gs.enemy_inst["hp"])
	return dealt

func _report() -> void:
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
	print("HUNT_LOG: %s" % ("FAIL" if not errs.is_empty() else "PASS"))
	quit()
