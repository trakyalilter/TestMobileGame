extends SceneTree
## Guard for the P5 utility uniques (desktop utility_unique_check).
##
## Engine, sensor and battery were the only slots with no unique tier, because
## each is a single scalar with one right answer — a unique battery that merely
## holds MORE is a dominated pickup the moment your power fits. The unique tier
## therefore grants MECHANICS, and mechanics are what a port drops silently: the
## modules arrive in the data looking special and do nothing.
##
## So this checks the rules, not the stat blocks: that the Overcharge Cell pays
## for genuine over-provisioning and NOT for flying half-equipped, and that the
## Predictive Array's pity timer actually floors a drop and cannot be banked.

var errs: Array = []
var warns: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s: String) -> void: errs.append(s)
func W(s: String) -> void: warns.append(s)
func _chk(cond: bool, label: String, detail := "") -> void:
	if not cond:
		E("%s%s" % [label, ("  — " + detail) if detail != "" else ""])

## Fit `mid` by writing the loadout directly — these are drop-only modules, and
## the point here is the mechanic, not the fitting rules (covered elsewhere).
func _fit(gs, gd, mid: String) -> bool:
	var want := String((gd.MODULES[mid] as Dictionary).get("slot", ""))
	var slots: Array = gs.effective_slots()
	for i in slots.size():
		if String(slots[i]) == want and not gs.loadout.has(str(i)):
			gs.loadout[str(i)] = mid
			return true
	return false

func _run() -> void:
	var gs = root.get_node("GameState")
	var gd = root.get_node("GameData")
	gs._suppress_fx = true

	# ---------- A. the data carries the mechanics ----------
	var cells: Array = []
	var arrays: Array = []
	var drives: Array = []
	for mid in gd.MODULES:
		var m: Dictionary = gd.MODULES[mid]
		if float(m.get("overcharge_cap", 0.0)) > 0.0:
			cells.append(String(mid))
		if int(m.get("pity_kills", 0)) > 0:
			arrays.append(String(mid))
		if String(m.get("slot", "")) == "engine" and bool(m.get("is_unique", false)):
			drives.append(String(mid))
	print("utility uniques: %d overcharge cells, %d predictive arrays, %d phase drives"
		% [cells.size(), arrays.size(), drives.size()])
	_chk(cells.size() >= 9, "every zone tier has an Overcharge Cell", "%d found" % cells.size())
	_chk(arrays.size() >= 9, "every zone tier has a Predictive Array", "%d found" % arrays.size())
	_chk(drives.size() >= 9, "every zone tier has a Phase Drive", "%d found" % drives.size())
	# The ceilings ladder up rather than being flat.
	var caps := {}
	for c in cells:
		caps[float((gd.MODULES[c] as Dictionary)["overcharge_cap"])] = true
	_chk(caps.size() >= 2, "the overcharge ceiling rises across tiers", str(caps.keys()))
	# The Phase Drive is the only evasion that can move the dodge formula.
	for d in drives:
		var eva := float(((gd.MODULES[d] as Dictionary).get("stats", {}) as Dictionary).get("eva", 0.0))
		_chk(eva > 0.0, "phase drive '%s' carries evasion" % d)

	# ---------- B. overcharge pays for over-provisioning, not for nakedness ----------
	gs.hard_reset()
	var cell := ""
	for c in cells:
		if int((gd.MODULES[c] as Dictionary).get("zone", 99)) <= 2:
			cell = String(c)
			break
	if cell == "":
		cell = String(cells[0]) if not cells.is_empty() else ""
	_chk(cell != "", "an Overcharge Cell exists to test with")
	if cell != "":
		_chk(is_equal_approx(gs.overcharge_mult(), 1.0), "no cell fitted means no bonus")
		_chk(_fit(gs, gd, cell), "the cell fits a battery bay")
		# Bays still empty: the ship is half-built, so the bonus must stay off.
		_chk(is_equal_approx(gs.overcharge_mult(), 1.0),
			"an unfinished ship earns NOTHING — stripping armour must not be a damage build",
			"mult=%.3f" % gs.overcharge_mult())
		# Fill every consumer bay with the cheapest thing that fits it.
		var slots: Array = gs.effective_slots()
		for i in slots.size():
			var want := String(slots[i])
			if not (want in gs.CONSUMER_SLOT_TYPES) or gs.loadout.has(str(i)):
				continue
			for mid2 in gd.MODULES:
				var m2: Dictionary = gd.MODULES[mid2]
				if String(m2.get("slot", "")) == want and int(m2.get("zone", 99)) <= 1:
					gs.loadout[str(i)] = String(mid2)
					break
		var filled := true
		for i in slots.size():
			if String(slots[i]) in gs.CONSUMER_SLOT_TYPES and not gs.loadout.has(str(i)):
				filled = false
		if not filled:
			W("could not fill every consumer bay — the overcharge payout check did not run")
		else:
			var mult: float = gs.overcharge_mult()
			var ss: Dictionary = gs.ship_stats()
			print("fitted ship: load %.0f of %.0f cap -> overcharge x%.3f"
				% [float(ss.get("energy_load", 0.0)), float(ss.get("energy_cap", 0.0)), mult])
			_chk(mult > 1.0, "a fully fitted ship with spare capacity IS paid", "mult=%.3f" % mult)
			var cap_v := float((gd.MODULES[cell] as Dictionary)["overcharge_cap"])
			_chk(mult <= 1.0 + cap_v + 0.0001, "the payout is ceilinged by the fitted cell",
				"mult=%.3f, cap=%.2f" % [mult, cap_v])
			# And it reaches the guns, not just the getter.
			var w: Array = gs.ship_weapons()
			if w.is_empty():
				W("no weapon in the test loadout — the damage path went unverified")
			else:
				var armed := 0.0
				for wd in w:
					armed += float((wd as Dictionary).get("dmg_k", 0.0)) + float((wd as Dictionary).get("dmg_e", 0.0))
				gs.loadout.erase(_slot_of(gs, cell))
				var bare := 0.0
				for wd2 in gs.ship_weapons():
					bare += float((wd2 as Dictionary).get("dmg_k", 0.0)) + float((wd2 as Dictionary).get("dmg_e", 0.0))
				_chk(armed > bare, "the cell raises actual weapon damage",
					"%.1f with vs %.1f without" % [armed, bare])

	# ---------- C. the pity timer floors a drop, and cannot be banked ----------
	gs.hard_reset()
	var arr := ""
	for a in arrays:
		if int((gd.MODULES[a] as Dictionary).get("zone", 99)) <= 2:
			arr = String(a)
			break
	if arr == "":
		arr = String(arrays[0]) if not arrays.is_empty() else ""
	if arr == "":
		E("no Predictive Array exists to test with")
	else:
		_chk(gs.pity_kills() == 0, "no array fitted means no pity timer")
		_chk(_fit(gs, gd, arr), "the array fits a sensor bay")
		var n: int = gs.pity_kills()
		_chk(n > 0, "a fitted array reports its window", "%d kills" % n)
		# Sitting one kill short of the window, a trash roll must still be able to
		# come up empty; at the window, the next drop is Rare or better.
		var pool: Array = []
		for mid3 in gd.MODULES:
			var m3: Dictionary = gd.MODULES[mid3]
			if String(m3.get("slot", "")) == "weapon" and not gs.module_is_drop_only(String(mid3)) \
					and int(m3.get("zone", 99)) <= 1:
				pool.append(String(mid3))
		if pool.is_empty():
			W("no zone-1 weapon to roll — the pity floor went unverified")
		else:
			var eid := ""
			for z in gd.ZONES:
				var roster: Array = (z as Dictionary).get("enemies", [])
				if not roster.is_empty():
					eid = String(roster[0])
					break
			gs.start_task("combat", eid)
			gs.pity_counter = n
			var before: int = gs.custom_modules.size()
			gs._roll_one_module_drop(pool)
			var got: int = gs.custom_modules.size() - before
			_chk(got == 1, "at the window the next roll always drops", "%d dropped" % got)
			if got == 1:
				var rar := 0
				for cid in gs.custom_modules:
					rar = maxi(rar, int((gs.custom_modules[cid] as Dictionary).get("rarity", 0)))
				_chk(rar >= 2, "and it is floored to Rare", "rarity %d" % rar)
				_chk(gs.pity_counter == 0, "the payout resets the window",
					"counter=%d" % gs.pity_counter)
			gs.stop_task()
		# Never persisted: a timer that survived a reload could be banked by quitting.
		gs.current_slot = 1
		gs.load_failed = false
		gs.pity_counter = 999
		gs.save_game()
		gs.hard_reset()
		gs.current_slot = 1
		gs.load_game()
		_chk(gs.pity_counter == 0, "the pity counter is NOT saved — it cannot be banked by quitting",
			"counter=%d after load" % gs.pity_counter)
		gs.delete_slot(1)

	gs._suppress_fx = false
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
	print("UTILITY_UNIQUES: %s" % ("FAIL" if not errs.is_empty() else "PASS"))
	quit()

func _slot_of(gs, mid: String) -> String:
	for k in gs.loadout:
		if String(gs.loadout[k]) == mid:
			return String(k)
	return ""
