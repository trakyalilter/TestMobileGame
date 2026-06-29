extends Node

const POLICY := preload("res://scripts/sim/policies/progression.gd")

func _ready() -> void:
	GameState.hard_reset()
	GameState.combat_manager.boss_kills.clear()
	GameState.combat_manager.total_kills = 0
	var p = POLICY.new()
	p.target_warps = 0
	var sm = GameState.shipyard_manager
	print("hull=", sm.active_hull, " slots=", sm.hulls[sm.active_hull].get("slots", []))
	p.manage_meta()      # builds hull + arms
	print("after manage_meta: hull=", sm.active_hull)
	print("  loadout=", sm.loadout)
	print("  armed=", p.is_armed(), " eu=", sm.energy_used, " ec=", sm.energy_capacity)
	print("  ammo_loadout=", sm.ammo_loadout)
	print("  combat_ready=", p._combat_ready(1))
	# weapon slot detail
	for i in p._slot_indices("weapon"):
		var mid = sm.loadout.get(i, null)
		print("  wslot ", i, " = ", mid, " atype=", (p._weapon_atype(String(mid)) if mid else "-"),
			" ammo=", sm.ammo_loadout.get(i, ""))
	# manual grant trace
	print("--- direct _equip_drop test ---")
	for i in range(8):
		sm.loadout[i] = null
	sm.recalc_stats()
	print("  battery slot 5 equip=", p._equip_drop(5, "battery", 1, 1), " ec=", sm.energy_capacity)
	print("  weapon slot 0 equip=", p._equip_drop(0, "missile", 1, 1), " eu=", sm.energy_used, " ec=", sm.energy_capacity)
	print("  loadout=", sm.loadout)
	get_tree().quit()
