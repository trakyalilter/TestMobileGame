extends SceneTree
## Combat-parity sim: fresh game, basic Zone-1 loadout, kill z1_lunar_drone.
## Desktop kills it in ~9s with basic gear; expect ~5-15s here.

func _init() -> void:
	# Autoloads aren't attached during SceneTree._init; run after the first frame.
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var gs = root.get_node("GameState")
	gs.hard_reset()
	# v110 battery-only energy model: hulls supply ZERO energy, batteries supply
	# all capacity. The basic z1 starter (kinetic+energy+shield+armor = 4 consumers
	# @ 10 load = 40) needs the corvette's TWO battery slots (2 x 30 = 60 cap) to
	# fit the grid. Batteries first so capacity exists before consumers load it.
	var fit_ok := true
	for mid in ["z1_battery", "z1_battery", "z1_kinetic", "z1_energy", "z1_shield", "z1_armor"]:
		gs.module_inventory[mid] = int(gs.module_inventory.get(mid, 0)) + 1
		var ok: bool = gs.equip_module(mid)
		print("equip %s -> %s" % [mid, ok])
		if not ok:
			fit_ok = false

	# Ammo (desktop v109): kinetic→Slug, energy→Cell — weapons can't fire dry.
	gs.add_resource("SlugT1", 9999)
	gs.add_resource("CellT1", 9999)
	for k in gs.loadout:
		var wm: Dictionary = gs.module_def(gs.loadout[k])
		if wm.get("slot", "") == "weapon":
			var wst: Dictionary = wm.get("stats", {})
			if float(wst.get("atk_kinetic", 0)) > 0: gs.set_ammo(str(k), "SlugT1")
			elif float(wst.get("atk_energy", 0)) > 0: gs.set_ammo(str(k), "CellT1")

	var ss: Dictionary = gs.ship_stats()
	print("ship: hp=%.0f def=%.0f shield=%.0f acc=%.0f energy_load=%.0f/%.0f" % [
		float(ss.get("hp", 0)), float(ss.get("def", 0)), float(ss.get("shield", 0)),
		float(ss.get("acc", 0)), float(ss.get("energy_load", 0)), float(ss.get("energy_cap", 0))])
	var grid_ok: bool = fit_ok and float(ss.get("energy_load", 0)) <= float(ss.get("energy_cap", 0)) + 0.01
	print("GRID: %s (load %.0f <= cap %.0f)" % ["FITS" if grid_ok else "OVERLOAD",
		float(ss.get("energy_load", 0)), float(ss.get("energy_cap", 0))])
	print("weapons: %d  avg_dps=%.1f" % [gs.ship_weapons().size(), gs.avg_player_dps()])

	gs.start_task("combat", "z1_lunar_drone")
	print("enemy: %s hp=%.0f atk=%.0f def=%.0f dmg_type=%s rk=%.2f" % [
		gs.enemy_inst.get("name", "?"), float(gs.enemy_inst.get("hp", 0)),
		float(gs.enemy_inst.get("atk", 0)), float(gs.enemy_inst.get("def", 0)),
		gs.enemy_inst.get("dmg_type", "?"), float(gs.enemy_inst.get("resist_k", 0))])

	var start_hp: float = float(gs.enemy_inst.get("hp", 0))
	var t := 0.0
	var dt := 0.1
	var killed := false
	var prev_hp := start_hp
	# _win_combat auto re-engages by re-spawning a full-HP drone; detect the first
	# kill as the tick where the enemy HP jumps back UP (respawn) after dropping.
	while t < 120.0:
		gs._tick_combat(dt)
		t += dt
		var ehp := float(gs.enemy_inst.get("hp", 0))
		if gs.active_type != "combat":
			break
		if ehp > prev_hp + 1.0:
			killed = true
			break
		prev_hp = ehp

	print("---")
	print("kill_time=%.1fs  player_hp=%.0f/%.0f  killed=%s" % [
		t, gs.combat_hp, gs.combat_max_hp(), str(killed)])
	if grid_ok and killed and gs.combat_hp > 0.0 and t >= 5.0 and t <= 15.0:
		print("RESULT: PASS (starter fits grid, drone killed in ~%.1fs, player survived)" % t)
	elif not grid_ok:
		print("RESULT: FAIL (starter loadout overloads the grid)")
	elif killed and gs.combat_hp > 0.0:
		print("RESULT: KILLED but timing outside 5-15s window (t=%.1f)" % t)
	else:
		print("RESULT: FAIL")
	quit()
