extends SceneTree
## Audit of the combat SESSION and the hazard gauntlets.
##
## sim_combat and sim_combat_math already check that a single swing does the right
## damage. What neither touches is the session around it: the state a fight leaves
## behind when it ends the ways players actually end fights — retreating, dying,
## warping, switching character — and the gauntlet mode that hangs off that same
## state machine.
##
## Hazard zones are the sharpest case. They are the only content that overrides
## the active task with a NON-enemy id and keeps a second state machine (wave,
## max_waves) running alongside it. Every exit path has to tear that down, because
## a hazard left "active" after the fight is over silently hijacks the next normal
## engagement: the kill advances a wave nobody is in, and a gauntlet enemy spawns
## in a sector fight.
##
## So this runs whole gauntlets and whole exit paths, rather than reading tables.

var errs: Array = []
var warns: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s: String) -> void: errs.append(s)
func W(s: String) -> void: warns.append(s)
func _chk(cond: bool, label: String, detail := "") -> void:
	if not cond:
		E("%s%s" % [label, ("  — " + detail) if detail != "" else ""])

## Kill whatever is in front of the player, through the real win path.
func _kill(gs) -> void:
	if gs.enemy_inst.is_empty():
		return
	gs.enemy_inst["hp"] = 0.0
	gs._win_combat()

## A fresh hull has no power capacity of its own (v134: batteries supply all of
## it), so anything with an energy load needs a battery in the grid first.
func _power(gs) -> void:
	var best := ""
	var best_cap := 0.0
	for mid in GameData.MODULES:
		var m: Dictionary = GameData.MODULES[mid]
		if String(m.get("slot", "")) != "battery":
			continue
		var cap := float((m.get("stats", {}) as Dictionary).get("energy_capacity", 0.0))
		if cap > best_cap:
			best_cap = cap
			best = String(mid)
	if best == "":
		E("no battery module exists — nothing with an energy load can be fitted")
		return
	gs.module_inventory[best] = int(gs.module_inventory.get(best, 0)) + 1
	if not gs.equip_module(best):
		E("the '%s' battery could not be equipped — the grid stays at zero capacity" % best)

## Put the player in a state that can actually enter the EMP Nexus: the unlock
## boss on the kill board and the counter module bolted on.
func _prepare_entry(gs, zid: String) -> String:
	var hz: Dictionary = GameData.HAZARD_ZONES.get(zid, {})
	var boss: String = String(hz.get("unlock_boss", ""))
	if boss != "":
		gs.boss_kills[boss] = 1
	var counter: String = String(hz.get("counter_module", ""))
	if counter != "":
		_power(gs)
		gs.module_inventory[counter] = int(gs.module_inventory.get(counter, 0)) + 1
		if not gs.equip_module(counter):
			E("the '%s' counter module could not be equipped (%s) — hazard entry is untestable"
				% [counter, gs.equip_notice])
	return counter

func _run() -> void:
	var gs = root.get_node("GameState")
	var gd = root.get_node("GameData")
	gs._suppress_fx = true

	# ---------- A. hazard content integrity ----------
	# Every id a gauntlet names has to resolve, or the run dies mid-wave with an
	# empty enemy and no way out.
	print("hazard zones: %d" % gd.HAZARD_ZONES.size())
	for zid in gd.HAZARD_ZONES:
		var hz: Dictionary = gd.HAZARD_ZONES[zid]
		var pool: Array = hz.get("enemy_pool", [])
		_chk(not pool.is_empty(), "hazard '%s' has an enemy pool" % zid)
		for eid in pool:
			_chk(gd.ENEMIES.has(String(eid)),
				"hazard '%s' pool enemy '%s' exists" % [zid, eid])
		for key in ["elite_enemy", "boss_enemy"]:
			var eid: String = String(hz.get(key, ""))
			_chk(eid != "" and gd.ENEMIES.has(eid),
				"hazard '%s' %s resolves" % [zid, key], "'%s'" % eid)
		var mw := int(hz.get("max_waves", 0))
		# Below 3 waves the elite and boss slots collide with each other.
		_chk(mw >= 3, "hazard '%s' runs at least 3 waves" % zid, "max_waves=%d" % mw)
		_chk(pool.size() >= 1 and mw - 2 <= pool.size() + 2,
			"hazard '%s' has enough pool entries for its regular waves" % zid)
		_chk(int(hz.get("difficulty", 0)) > 0,
			"hazard '%s' has a combat difficulty" % zid,
			"a missing one silently drops loot scaling to zone 1")
		var ub: String = String(hz.get("unlock_boss", ""))
		if ub != "":
			_chk(gd.ENEMIES.has(ub), "hazard '%s' unlock boss '%s' exists" % [zid, ub])
			_chk(bool(gd.ENEMIES.get(ub, {}).get("is_boss", false)),
				"hazard '%s' unlock boss is flagged is_boss" % zid,
				"only is_boss kills are counted, so a non-boss gate never opens")
		var cm: String = String(hz.get("counter_module", ""))
		if cm != "":
			_chk(gd.MODULES.has(cm), "hazard '%s' counter module '%s' exists" % [zid, cm])
			# A hard-gated module with no source is a zone nobody can ever enter.
			var obtainable := false
			for eid2 in gd.ENEMIES:
				for row in (gd.ENEMIES[eid2] as Dictionary).get("loot", []):
					if String((row as Array)[0]) == cm:
						obtainable = true
			for rid in gd.CRAFT:
				if (gd.CRAFT[rid] as Dictionary).get("outputs", {}).has(cm):
					obtainable = true
			_chk(obtainable, "hazard '%s' counter module '%s' has a source" % [zid, cm],
				"no drop and no recipe means the zone can never be entered")
		var fcr: String = String(hz.get("first_clear_reward", ""))
		if fcr != "":
			_chk(gd.RESOURCES.has(fcr) or gd.MODULES.has(fcr),
				"hazard '%s' first-clear reward '%s' is a real item" % [zid, fcr])

	# Declared out here because the session checks below use them whether or not
	# any gauntlet content exists.
	var zid0 := ""
	var sector_enemy := ""
	for z in gd.ZONES:
		var roster0: Array = (z as Dictionary).get("enemies", [])
		if not roster0.is_empty():
			sector_enemy = String(roster0[0])
			break

	# The EMP Nexus was removed upstream and no gauntlet has replaced it. The
	# hazard FRAMEWORK is kept deliberately — it costs nothing while empty and a
	# future zone is one dict entry — so these sections stand ready rather than
	# being deleted, and the session checks below still run on an empty table.
	if gd.HAZARD_ZONES.is_empty():
		print("hazard sections skipped: no zones in the data")
	else:
		# ---------- B. the entry gate ----------
		for z in gd.HAZARD_ZONES:
			zid0 = String(z)
			break
		if zid0 == "":
			W("no hazard zone in the data — the gauntlet checks did not run")
		var hz0: Dictionary = gd.HAZARD_ZONES[zid0]
		var max_waves := int(hz0.get("max_waves", 7))

		gs.hard_reset()
		_chk(not gs.is_hazard_unlocked(zid0), "a hazard is locked before its unlock boss dies")
		_chk(not gs.start_hazard(zid0), "entering a locked hazard is refused")
		_chk(not bool(gs.hazard_state.get("active", false)),
			"a refused entry leaves no half-open run behind")
		var counter := _prepare_entry(gs, zid0)
		_chk(gs.is_hazard_unlocked(zid0), "one boss kill unlocks the hazard")
		if counter != "":
			# The counter is a HARD gate: unlocked but unequipped must still refuse.
			var idx := ""
			for k in gs.loadout:
				if String(gs.loadout[k]) == counter:
					idx = String(k)
			gs.unequip_slot(idx)
			_chk(not gs.has_counter_module(zid0), "the counter module reads as absent once removed")
			_chk(not gs.start_hazard(zid0), "entry is refused without the counter module")
			_chk(not bool(gs.hazard_state.get("active", false)), "the refusal leaves no run open")
			gs.equip_module(counter)

		# ---------- C. a full gauntlet, wave by wave ----------
		var reward: String = String(hz0.get("first_clear_reward", ""))
		var reward_before: int = gs.amount(reward) if reward != "" else 0
		_chk(gs.start_hazard(zid0), "entry succeeds once unlocked and countered")
		_chk(bool(gs.hazard_state.get("active", false)), "the run registers as active")
		_chk(gs.active_type == "combat" and gs.active_id == zid0,
			"the active task points at the hazard zone", "%s/%s" % [gs.active_type, gs.active_id])
		_chk(gs.session_loot.is_empty(), "a fresh gauntlet starts with an empty session tally")
		_chk(gs._combat_difficulty() == int(hz0.get("difficulty", 3)),
			"combat difficulty follows the hazard zone, not the sector ladder",
			"%d" % gs._combat_difficulty())

		var seen: Array = []
		var hp_by_wave: Array = []
		var guard := 0
		while bool(gs.hazard_state.get("active", false)) and guard < max_waves + 3:
			guard += 1
			seen.append(String(gs.enemy_inst.get("id", "")))
			hp_by_wave.append(float(gs.enemy_inst.get("max_hp", 0.0)))
			_kill(gs)
		print("gauntlet '%s': %d waves fought -> %s" % [zid0, seen.size(), str(seen)])
		_chk(seen.size() == max_waves, "the gauntlet is exactly max_waves long",
			"fought %d of %d" % [seen.size(), max_waves])
		var pool0: Array = hz0.get("enemy_pool", [])
		for w in mini(seen.size(), max_waves - 2):
			_chk(String(seen[w]) == String(pool0[w % pool0.size()]),
				"wave %d draws from the regular pool" % (w + 1),
				"got '%s', expected '%s'" % [seen[w], pool0[w % pool0.size()]])
		if seen.size() == max_waves:
			_chk(String(seen[max_waves - 2]) == String(hz0.get("elite_enemy", "")),
				"the penultimate wave is the elite", "got '%s'" % seen[max_waves - 2])
			_chk(String(seen[max_waves - 1]) == String(hz0.get("boss_enemy", "")),
				"the final wave is the boss", "got '%s'" % seen[max_waves - 1])
			# +20% per wave. Compare the boss's scaled HP against an unscaled spawn of
			# the same enemy rather than trusting the constant in two places.
			gs._spawn_enemy_inst(String(hz0.get("boss_enemy", "")))
			var base_hp := float(gs.enemy_inst.get("max_hp", 0.0))
			var want := base_hp * (1.0 + float(max_waves - 1) * 0.20)
			var got := float(hp_by_wave[max_waves - 1])
			_chk(base_hp > 0.0 and abs(got - want) / maxf(1.0, want) < 0.02,
				"the final wave carries its wave scaling", "%.0f vs %.0f expected" % [got, want])
			print("wave scaling: boss at %.0f HP vs %.0f unscaled (x%.2f)"
				% [got, base_hp, got / maxf(1.0, base_hp)])

		# ---------- D. clearing it ----------
		_chk(not bool(gs.hazard_state.get("active", false)), "clearing the last wave ends the run")
		_chk(gs.active_type == "", "a cleared gauntlet stops the task rather than re-engaging",
			"active_type='%s'" % gs.active_type)
		_chk(bool(gs.hazard_clears.get(zid0, false)), "the clear is recorded")
		if reward != "":
			_chk(gs.amount(reward) == reward_before + 1, "the first clear pays its reward once",
				"%d -> %d" % [reward_before, gs.amount(reward)])
		# Second clear: the reward must NOT repeat.
		var reward_after_first: int = gs.amount(reward) if reward != "" else 0
		gs.start_hazard(zid0)
		guard = 0
		while bool(gs.hazard_state.get("active", false)) and guard < max_waves + 3:
			guard += 1
			_kill(gs)
		if reward != "":
			_chk(gs.amount(reward) == reward_after_first,
				"a repeat clear does not pay the first-clear reward again",
				"%d -> %d" % [reward_after_first, gs.amount(reward)])
		_chk(int(gs.boss_kills.get(String(hz0.get("boss_enemy", "")), 0)) > 0,
			"the gauntlet boss is credited to the kill board")

		# ---------- E. every exit path must tear the run down ----------
		# These are the paths that leave a hazard "running" with no fight attached.
		# Each one is checked from a fresh entry so a failure names its own path.
		_chk(gs.start_hazard(zid0), "re-entry after a clear works")
		gs._lose_combat()
		_chk(not bool(gs.hazard_state.get("active", false)),
			"DEATH ejects from the gauntlet")
		_chk(gs.active_type == "", "death also clears the active task")

		_chk(gs.start_hazard(zid0), "entry for the retreat check")
		gs.stop_task()
		_chk(not bool(gs.hazard_state.get("active", false)),
			"RETREAT ends the gauntlet — a run left active hijacks the next normal fight")

		# Proof of the consequence, not just the flag: after retreating, a normal
		# engagement must fight its own enemy and re-engage it on a kill.

		if sector_enemy != "":
			gs.start_task("combat", sector_enemy)
			_kill(gs)
			_chk(String(gs.enemy_inst.get("id", "")) == sector_enemy,
				"a normal fight re-engages its own enemy after a hazard was abandoned",
				"spawned '%s'" % String(gs.enemy_inst.get("id", "")))
			_chk(gs.active_type == "combat", "the normal fight is still running")
			gs.stop_task()

		_chk(gs.start_hazard(zid0), "entry for the reset check")
		gs.hard_reset()
		_chk(not bool(gs.hazard_state.get("active", false)),
			"HARD RESET clears the gauntlet — a new character must not start mid-wave")

		# A slot switch loads a different character; the run belongs to the old one.
		gs.hard_reset()
		gs.current_slot = 1
		gs.load_failed = false
		gs.save_game()
		_prepare_entry(gs, zid0)
		_chk(gs.start_hazard(zid0), "entry for the load check")
		gs.load_game()
		_chk(not bool(gs.hazard_state.get("active", false)),
			"LOADING a save clears the gauntlet — it is not part of the save")
		gs.delete_slot(1)

		# Warping wipes the module inventory, so a run cannot survive it either.
		gs.hard_reset()
		_prepare_entry(gs, zid0)
		gs.lifetime_credits = 500_000_000
		gs.credits_at_warp_start = 0
		_chk(gs.start_hazard(zid0), "entry for the warp check")
		gs.execute_warp()
		_chk(not bool(gs.hazard_state.get("active", false)),
			"WARPING clears the gauntlet — the counter module is wiped by the reset")

		# ---------- F. the entry gates agree with normal combat ----------
		# start_task refuses to engage on an overloaded power grid. start_hazard is a
		# second door into the same combat loop and has to hold the same line.
		gs.hard_reset()
		_prepare_entry(gs, zid0)
		# The realistic way to overload a grid is to strip the battery out of a fitted
		# ship, which is exactly what a player does when swapping gear. Removing it
		# from the inventory too denies the auto-rescue, so the gate has to fire.
		for k in gs.loadout.keys():
			if String(gs.module_def(gs.loadout[k]).get("slot", "")) == "battery":
				var bat: String = String(gs.loadout[k])
				gs.unequip_slot(String(k))
				gs.module_inventory.erase(bat)
		var ss1: Dictionary = gs.ship_stats()
		if float(ss1.get("energy_load", 0.0)) > float(ss1.get("energy_cap", 0.0)):
			gs.start_task("combat", sector_enemy)
			var normal_blocked: bool = gs.active_type == ""
			var haz_ok: bool = gs.start_hazard(zid0)
			_chk(normal_blocked == (not haz_ok),
				"both combat doors treat an overloaded grid the same way",
				"normal blocked=%s, hazard entered=%s" % [normal_blocked, haz_ok])
			gs.stop_task()
		else:
			W("no module was heavy enough to overload the grid — the entry-gate parity check did not run")

		# ---------- G. hazard kills credit the enemy, not the zone ----------
		# During a run the active task id is the ZONE. Anything that reads active_id
		# to identify what died attributes the kill to a zone id that matches no enemy.
		gs.hard_reset()
		_prepare_entry(gs, zid0)
		gs.generate_bounty_pool()
		gs.start_hazard(zid0)
		var live_id: String = String(gs.enemy_inst.get("id", ""))
		_chk(live_id != "" and live_id != zid0,
			"the live enemy is a real enemy, not the zone", "'%s'" % live_id)
		var kills_before: int = gs.total_kills
		_kill(gs)
		_chk(gs.total_kills == kills_before + 1, "a hazard kill counts as a kill")
		_chk(not gs.session_loot.is_empty(), "a hazard kill pays into the session tally")
		print("hazard kill: session tally has %d entries" % gs.session_loot.size())

		# ---------- H. the EMP jam actually keys off the counter module ----------
		# The one hazard mechanic with a gameplay effect. Measured, not read.
		if String(hz0.get("hazard_type", "")) == "emp_storm":
			_chk(gs._active_hazard_type() == "emp_storm", "the active hazard type reads through")
			var with_counter := _jam_rate(gs)
			var idx2 := ""
			for k in gs.loadout:
				if String(gs.loadout[k]) == counter:
					idx2 = String(k)
			gs.unequip_slot(idx2)
			var without := _jam_rate(gs)
			print("EMP jam rate: %.0f%% with the Faraday Hull, %.0f%% without"
				% [with_counter * 100.0, without * 100.0])
			_chk(with_counter < without, "the counter module cuts the jam rate",
				"%.2f vs %.2f" % [with_counter, without])
			_chk(abs(with_counter - 0.10) < 0.06, "the countered jam rate is ~10%",
				"%.2f" % with_counter)
			_chk(abs(without - 0.40) < 0.09, "the uncountered jam rate is ~40%", "%.2f" % without)
		gs.stop_task()

		# ---------- I. no jamming outside a hazard ----------
		if sector_enemy != "":
			gs.hard_reset()
			gs.start_task("combat", sector_enemy)
			var jam_outside := _jam_rate(gs)
			_chk(jam_outside == 0.0, "weapons never jam in a normal sector fight",
				"%.2f" % jam_outside)
			gs.stop_task()

	# ---------- J. session lifecycle around a normal fight ----------
	if sector_enemy != "":
		gs.hard_reset()
		gs.start_task("combat", sector_enemy)
		gs._log_session_loot("Fe", 5)
		gs.stop_task()
		gs.start_task("combat", sector_enemy)
		_chk(gs.session_loot.is_empty(), "each engagement starts a fresh session tally")

		# Heat: firing builds heat, and hitting the ceiling locks the guns.
		gs.player_heat = 0.0
		gs._overheat_lock = 0.0
		var ss: Dictionary = gs.ship_stats()
		var w0: Dictionary = gs._weapons[0] if not gs._weapons.is_empty() else {}
		_chk(not w0.is_empty(), "the ship has a weapon to fire")
		if not w0.is_empty():
			var heat0: float = gs.player_heat
			gs.enemy_inst["hp"] = 1e12
			gs.enemy_inst["max_hp"] = 1e12
			gs._player_fire(w0, ss)
			_chk(gs.player_heat > heat0, "firing builds heat", "%.1f" % gs.player_heat)
			var hguard := 0
			while gs._overheat_lock <= 0.0 and hguard < 500:
				hguard += 1
				gs._player_fire(w0, ss)
			_chk(gs._overheat_lock > 0.0, "sustained fire overheats the guns",
				"heat %.0f of %.0f" % [gs.player_heat, gs.MAX_HEAT])
			var hp_locked: float = float(gs.enemy_inst["hp"])
			gs._player_fire(w0, ss)
			_chk(float(gs.enemy_inst["hp"]) == hp_locked,
				"an overheated ship deals no damage until the lock clears")
			gs.player_heat = 0.0
			gs._overheat_lock = 0.0

		# Consumables share one cooldown, and it is the real constant.
		var kit := ""
		for cid in gd.CONSUMABLES:
			if String((gd.CONSUMABLES[cid] as Dictionary).get("type", "hull")) == "hull":
				kit = String(cid)
				break
		if kit != "":
			gs.resources[kit] = 10
			gs.set_consumable("hull", kit)
			gs.combat_hp = 1.0
			gs._consume_cd = 0.0
			gs.use_manual_consumable("hull")
			_chk(gs.amount(kit) == 9, "a manual consumable is spent", "%d left" % gs.amount(kit))
			_chk(abs(gs._consume_cd - gs.CONSUME_CD) < 0.01,
				"using one starts the full cooldown", "%.1fs of %.1fs" % [gs._consume_cd, gs.CONSUME_CD])
			gs.use_manual_consumable("hull")
			_chk(gs.amount(kit) == 9, "a second use inside the cooldown is refused")
			gs._consume_cd = 0.0
			gs.use_manual_consumable("hull")
			_chk(gs.amount(kit) == 8, "it works again once the cooldown elapses")

		# Defeat: the hull comes back, the modules take the hit, the task ends.
		gs.combat_hp = 1.0
		gs._lose_combat()
		_chk(gs.combat_hp == gs.combat_max_hp(), "defeat restores the hull")
		_chk(gs.active_type == "", "defeat ends the engagement")
		_chk(gs.player_shield == 0.0, "defeat drops the shield")

	# ---------- K. ammo gating ----------
	# A slotted weapon with no compatible ammo must not fire at all.
	if sector_enemy != "":
		gs.hard_reset()
		var wep := ""
		for mid in gd.MODULES:
			var m: Dictionary = gd.MODULES[mid]
			if String(m.get("slot", "")) != "weapon":
				continue
			if float((m.get("stats", {}) as Dictionary).get("atk_kinetic", 0.0)) <= 0.0:
				continue
			if float((m.get("stats", {}) as Dictionary).get("energy_load", 0.0)) > 10.0:
				continue
			wep = String(mid)
			break
		if wep == "":
			W("no light kinetic weapon module was found — the ammo gate check did not run")
		else:
			_power(gs)
			gs.module_inventory[wep] = 1
			if gs.equip_module(wep):
				gs.start_task("combat", sector_enemy)
				gs.enemy_inst["hp"] = 1e12
				gs.enemy_inst["max_hp"] = 1e12
				gs.enemy_inst["shield"] = 0.0
				var slotw: Dictionary = {}
				for w in gs._weapons:
					if String((w as Dictionary).get("slot", "")) != "":
						slotw = w
				_chk(not slotw.is_empty(), "the equipped weapon occupies a real slot")
				if not slotw.is_empty():
					var ss2: Dictionary = gs.ship_stats()
					# Dry: no Slug in the hold at all.
					for sym in gs.resources.keys():
						if String(sym).begins_with("Slug"):
							gs.resources.erase(sym)
					var dry_hp: float = float(gs.enemy_inst["hp"])
					for _i in 40:
						gs.player_heat = 0.0
						gs._overheat_lock = 0.0
						gs._player_fire(slotw, ss2)
					_chk(float(gs.enemy_inst["hp"]) == dry_hp,
						"a slotted weapon with no compatible ammo deals nothing")
					# Loaded: rounds are spent, damage lands.
					gs.resources["SlugT1"] = 40
					if gs.amount("SlugT1") == 0:
						W("SlugT1 is not a known ammo id — the ammo spend check did not run")
					else:
						var hp1: float = float(gs.enemy_inst["hp"])
						gs.player_heat = 0.0
						gs._overheat_lock = 0.0
						gs._player_fire(slotw, ss2)
						_chk(float(gs.enemy_inst["hp"]) < hp1, "a loaded weapon deals damage")
						_chk(gs.amount("SlugT1") <= 39, "firing spends a round",
							"%d left" % gs.amount("SlugT1"))
				gs.stop_task()

	if not gd.HAZARD_ZONES.is_empty():
		# ---------- L. offline while a gauntlet is open ----------
		# The offline path resolves the enemy from the ACTIVE ID, which during a run
		# is a zone. It must no-op rather than mis-resolve or corrupt the run.
		gs.hard_reset()
		_prepare_entry(gs, zid0)
		gs.start_hazard(zid0)
		var wave_before := int(gs.hazard_state.get("wave", 0))
		var cred_before: int = gs.credits
		gs._apply_offline(3600.0)
		_chk(int(gs.hazard_state.get("wave", 0)) == wave_before,
			"an away window does not advance gauntlet waves")
		_chk(gs.credits == cred_before, "an away window pays nothing for an open gauntlet")
		_chk(bool(gs.hazard_state.get("active", false)) or gs.active_type == "",
			"the run is either intact or fully torn down after an away window")
		gs.stop_task()

	# ---------- M. the kill-then-retreat beat ----------
	# m017 teaches Retreat: the kill alone must not finish it, disengaging must.
	# Nothing credited the defeat_retreat type at all, so the objective sat at 0/1
	# through any number of kills and the tutorial dead-ended on it.
	var dr_id := ""
	for mid in gd.MISSION_ORDER:
		if String((gd.MISSIONS[mid] as Dictionary).get("type", "")) == "defeat_retreat":
			dr_id = String(mid)
			break
	if dr_id == "":
		W("no defeat_retreat mission in the chain — the kill-then-retreat check did not run")
	else:
		var dm: Dictionary = gd.MISSIONS[dr_id]
		var prey := String(dm.get("target", ""))
		gs.hard_reset()
		gs.missions_active = {dr_id: true}
		gs.missions_progress.erase(dr_id)
		gs._mission_completed_seen.erase(dr_id)
		_chk(not gs.mission_completed(dr_id), "the beat starts incomplete")
		gs.start_task("combat", prey)
		_kill(gs)
		_chk(int(gs.missions_progress.get(dr_id, 0)) >= int(dm.get("qty", 1)),
			"the kill is credited as progress",
			"%d/%d" % [int(gs.missions_progress.get(dr_id, 0)), int(dm.get("qty", 1))])
		_chk(not gs.mission_completed(dr_id),
			"the kill ALONE does not complete it — the retreat is the gate")
		gs.stop_task()
		_chk(gs.mission_completed(dr_id),
			"disengaging completes it")
		_chk(gs.claim_mission(dr_id), "and it can then be claimed")
		print("kill-then-retreat: %s completes on disengage, not on the kill" % dr_id)

	gs._suppress_fx = false
	_report()

## Fire the first weapon many times with heat neutralised and report the share of
## shots that came back as an EMP jam.
func _jam_rate(gs) -> float:
	if gs.enemy_inst.is_empty() or gs._weapons.is_empty():
		return 0.0
	var ss: Dictionary = gs.ship_stats()
	var w: Dictionary = gs._weapons[0]
	var shots := 400
	var jams := 0
	for _i in shots:
		gs.enemy_inst["hp"] = 1e12
		gs.enemy_inst["max_hp"] = 1e12
		gs.player_heat = 0.0
		gs._overheat_lock = 0.0
		gs.combat_events.clear()
		gs._player_fire(w, ss)
		for ev in gs.combat_events:
			if String((ev as Dictionary).get("text", "")) == "EMP JAM":
				jams += 1
	return float(jams) / float(shots)

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
	print("COMBAT_SESSION_AUDIT: %s" % ("FAIL" if not errs.is_empty() else "PASS"))
	quit()
