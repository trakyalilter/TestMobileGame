extends Node
# ARE THE Z13/Z14/Z15 BLOCKS REAL, OR IS THE HARNESS UNDER-EQUIPPING? (v175)
#
# Extending zone_gate_check to Z11-Z15 produced three BLOCKs: a clean COMMON set of the
# zone's OWN gear dies to that zone's e3 at Z13, Z14 and Z15. All three are the PHASED
# enemies, and the phase kit is the newest and least-tested part of the harness — a
# single-element loadout stalls on every band it cannot breach, so "dies" is exactly what
# a mis-built kit would also produce.
#
# So dump the kit before believing the verdict: which weapon ids actually got equipped,
# what the phase elements are, whether power held, and where the death lands.
#
#   Godot --headless --path <root> res://scenes/ngplus_gate_diag.tscn

const ZGC := preload("res://scripts/sim/zone_gate_check.gd")

var _z

func _ready() -> void:
	await get_tree().process_frame
	if not GameState.sim_mode:
		print("[NGG] ABORT: sim_mode false")
		get_tree().quit(1)
		return
	GameState.set_process(false)
	_z = ZGC.new()
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager

	for zn in [12, 13, 14, 15]:
		var zid: String = _z._zone_with_diff(cm, zn)
		var roster: Array = cm.zones[zid].get("enemies", [])
		var eid := str(roster[2])
		var e: Dictionary = cm.enemy_db.get(eid, {})
		var phases: Array = e.get("phases", [])
		var st: Dictionary = e.get("stats", {})

		GameState.hard_reset()
		GameState.game_settings["cryo_unlocked"] = true
		for z2 in range(11, 16):
			GameState.game_settings["z%d_unlocked" % z2] = true
		_z._unlock_research(rm, zn)
		_z._set_hull(sm, zn)
		var weak: String = _z._weak_type(e)
		_z._equip_common(sm, zn, weak, e)
		_z._ammo_kits(sm, weak, zn)
		sm.recalc_stats()
		sm.current_hp = sm.max_hp

		var want: Array = _z._weapons_for(sm, zn, weak, e)
		var got: Array = []
		for i in _z._slots(sm, "weapon"):
			var mid := str(sm.loadout.get(i, ""))
			got.append(mid if mid != "" else "EMPTY")
		print("[NGG] Z%d %s  phases=%s" % [zn, eid, str(phases)])
		print("[NGG]   wanted %s" % str(want))
		print("[NGG]   equipped %d/%d slots: %s" % [
			_z._slots(sm, "weapon").size(), _z._slots(sm, "weapon").size(), str(got)])
		print("[NGG]   hull=%s hp=%d shield=%d atk=%d | power %d/%d%s" % [
			str(sm.active_hull), int(sm.max_hp), int(sm.max_shield), int(sm.attack),
			int(sm.energy_used), int(sm.energy_capacity),
			"  *** UNPOWERED" if sm.energy_used > sm.energy_capacity else ""])
		print("[NGG]   enemy hp=%d shield=%d atk=%d phase_cut=%.2f" % [
			int(st.get("hp", 0)), int(st.get("max_shield", 0)), int(st.get("atk", 0)),
			float(e.get("phase_cut", 1.0))])

		# One real window: when does it die, and how far did it get?
		cm.total_kills = 0
		cm.start_expedition(zid)
		cm.set_target_enemy(eid)
		if cm.current_enemy == null:
			print("[NGG]   NOENT — could not spawn")
			continue
		var t := 0.0
		var died := -1.0
		while t < 180.0:
			_z._use_kits(sm, cm)
			cm.process_tick(0.1)
			t += 0.1
			if sm.current_hp <= 0 or not cm.in_combat:
				died = t
				break
		print("[NGG]   -> %d kills in %.0fs%s" % [
			int(cm.total_kills), (died if died >= 0.0 else 180.0),
			("  DIED at %.0fs" % died) if died >= 0.0 else ""])
	get_tree().quit(0)
