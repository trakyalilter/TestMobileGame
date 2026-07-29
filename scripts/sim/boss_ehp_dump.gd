extends Node
# ============================================================================
# BOSS EFFECTIVE-HP DUMP (v156, read-only)
# Prints, for every Z2-Z10 zone boss, the EFFECTIVE max_hp the real spawn path
# produces: authored stats.hp -> _apply_enemy_tier_rebase -> FLATTEN_HP_CALIB
# -> spawn_enemy zone-steepening (warp mult = 1 on a fresh boot, no map mods).
# Used to prove the v156 weak-channel reassignment plus the authored-hp
# compensation lands boss effective hp back on its HEAD value.
#
#   Godot --headless --path <root> res://scenes/boss_ehp_dump.tscn
# ============================================================================

func _ready() -> void:
	var cm = GameState.combat_manager
	GameState.set_process(false)
	print("[BED] ===== BOSS EFFECTIVE HP (real spawn path, non-elite) =====")
	for z in range(2, 11):
		for zid in cm.zones:
			if int(cm.zones[zid].get("difficulty", 0)) != z:
				continue
			for eid in cm.zones[zid].get("enemies", []):
				var e: Dictionary = cm.enemy_db.get(String(eid), {})
				if not bool(e.get("is_boss", false)):
					continue
				cm.current_zone = cm.zones[zid]
				cm.target_enemy_id = String(eid)
				cm.next_spawn_elite = false
				# elite roll is 5% random — respawn until the plain boss lands
				var tries := 0
				cm.spawn_enemy()
				while bool(cm.current_enemy.get("is_elite", false)) and tries < 200:
					cm.next_spawn_elite = false
					cm.spawn_enemy()
					tries += 1
				print("[BED] Z%-3d %-24s db_hp=%-12d eff_hp=%d" % [
					z, String(eid),
					int(e.get("stats", {}).get("hp", 0)),
					int(cm.current_enemy.get("max_hp", 0))])
			break
	print("[BED] ===== DONE =====")
	get_tree().quit(0)
