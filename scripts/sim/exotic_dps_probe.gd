extends Node
# EXOTIC LADDER DPS PROBE (one-shot diagnostic).
#
# The v174 ladder values were solved as HP / 400s using an assumed 0.575
# phase-mix throughput, and the fights came in ~7x slower than that predicted.
# Rather than theorise about where the model is wrong, measure the achieved DPS
# directly: what is equipped, and how much boss HP actually falls per second.
#
#   Godot --headless --path <root> res://scenes/exotic_dps_probe.tscn

const BGC := preload("res://scripts/sim/boss_gearcheck.gd")
const DT := 0.1
const WINDOW := 120.0

var _bgc

func _ready() -> void:
	await get_tree().process_frame
	if not GameState.sim_mode:
		print("[EX] ABORT: sim_mode false")
		get_tree().quit(1)
		return
	GameState.set_process(false)
	# NOT add_child: BGC._ready() runs the entire gear-check matrix and quits.
	_bgc = BGC.new()

	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager
	var rm = GameState.research_manager

	for row in [["the_threshold", "z11_boss_threshold_warden", 11],
				["the_rift", "z12_boss_rift_warden", 12],
				["the_verdigris", "z13_boss_verdigris_warden", 13],
				["the_dissolution", "z14_boss_dissolution_tyrant", 14],
				["the_caustic_core", "z15_boss_caustic_sovereign", 15]]:
		_measure(sm, cm, rm, String(row[0]), String(row[1]), int(row[2]))

	print("[EX] done")
	get_tree().quit(0)


func _measure(sm, cm, rm, zone_id: String, eid: String, zone: int) -> void:
	GameState.hard_reset()
	cm.boss_kills.clear()
	cm.total_kills = 0
	var e: Dictionary = cm.enemy_db[eid]
	var phases: Array = e.get("phases", [])
	GameState.game_settings["cryo_unlocked"] = true
	for t in ["cryo_armaments", "corrosion_armaments", "rift_armaments",
			"verdigris_armaments", "dissolution_armaments", "caustic_armaments"]:
		if not (t in rm.unlocked_techs):
			rm.unlocked_techs.append(t)
	for f in ["z11_unlocked", "z12_unlocked", "z13_unlocked", "z14_unlocked", "z15_unlocked"]:
		GameState.game_settings[f] = true
	_bgc._unlock_research(rm, 10)
	_bgc._set_hull(sm, zone)
	_bgc._equip_gear(sm, zone, "explosive", 3, bool(e.get("warp_hardened", false)), phases)
	_bgc._ammo_kits(sm, "explosive", zone)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp

	print("[EX] Z%d setup: hull=%s slots=%d energy=%d/%d" % [
		zone, String(sm.active_hull), sm.loadout.size(), int(sm.energy_used), int(sm.energy_capacity)])
	cm.start_expedition(zone_id)
	cm.set_target_enemy(eid)
	if cm.current_enemy == null or cm.current_enemy.is_empty():
		print("[EX] Z%-2d %-28s COULD NOT SPAWN" % [zone, eid])
		return

	var names: Array = []
	for w in cm.player_weapon_states:
		names.append("%s(%s/%.0f)" % [String(w.get("mid", "?")), String(w.get("exotic_type", "-")),
			float(w.get("dmg_cryo", 0.0))])
	# Snapshot before the loop: a lethal hit calls lose_fight(), which nulls
	# current_enemy — reading it afterwards is how the first run of this probe died.
	var e_def: int = int(cm.current_enemy.get("def", 0))
	var full_hp: float = float(cm.enemy_max_hp) + float(cm.enemy_max_shield)
	# Measure TTK by actually killing it. Every indirect proxy tried here lied:
	# hp0-minus-final counted the whole bar when the fight ended (Z15 "5.6 billion
	# dps"), and summing per-tick drops double-counts anything the boss regenerates.
	# Keep the player alive so this isolates offence; survivability is the second
	# pass below.
	var t := 0.0
	var killed := false
	while t < 1500.0:
		sm.current_hp = sm.max_hp
		_bgc._kit(sm, cm)
		cm.process_tick(DT)
		t += DT
		if int(cm.boss_kills.get(eid, 0)) > 0:
			killed = true
			break
		if not cm.in_combat:
			break
	var left: float = 100.0 * float(cm.enemy_hp) / maxf(1.0, float(cm.enemy_max_hp)) if cm.current_enemy != null else 0.0
	print("[EX] Z%-2d %-26s phases=%-2d slots=%d  -> %s" % [
		zone, eid, phases.size(), cm.player_weapon_states.size(),
		("KILLED in %.0fs" % t) if killed else ("NO KILL in %.0fs (%.0f%% left)" % [t, left])])
	print("[EX]      equipped: %s" % ", ".join(names))

	# Second pass, same loadout, WITHOUT the keep-alive: how long does the player
	# actually last? If survival < TTK the gate is defensive, not offensive, and
	# more weapon damage is the wrong lever.
	GameState.hard_reset()
	cm.boss_kills.clear()
	GameState.game_settings["cryo_unlocked"] = true
	for t2 in ["cryo_armaments", "corrosion_armaments", "rift_armaments",
			"verdigris_armaments", "dissolution_armaments", "caustic_armaments"]:
		if not (t2 in rm.unlocked_techs):
			rm.unlocked_techs.append(t2)
	for f2 in ["z11_unlocked", "z12_unlocked", "z13_unlocked", "z14_unlocked", "z15_unlocked"]:
		GameState.game_settings[f2] = true
	_bgc._unlock_research(rm, 10)
	_bgc._set_hull(sm, zone)
	_bgc._equip_gear(sm, zone, "explosive", 3, bool(e.get("warp_hardened", false)), phases)
	_bgc._ammo_kits(sm, "explosive", zone)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	var php: float = sm.max_hp
	cm.start_expedition(zone_id)
	cm.set_target_enemy(eid)
	var st := 0.0
	while st < 900.0 and cm.in_combat and sm.current_hp > 0:
		_bgc._kit(sm, cm)
		cm.process_tick(DT)
		st += DT
	var ttk: float = t
	print("[EX]      survives %.0fs on z%d defence (hull %.0f) vs %.0fs needed -> %s" % [
		st, min(zone, 10), php, ttk, "OK" if st >= ttk else "DEFENCE-LIMITED"])
