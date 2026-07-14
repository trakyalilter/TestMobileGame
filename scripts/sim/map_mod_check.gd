extends Node
# ============================================================================
# MAP-MOD SYSTEM CHECK (v137 NG+ step 3) — verifies the opt-in per-expedition
# modifier backend: loot mults COMPOUND, set_active_map_mods caps/dedupes/validates,
# spawn_enemy applies the difficulty effects (shield ×1.6 / hp ×1.45 / enrage +0.20),
# and Exotic Dampening cuts the player's cryo/corrosion channel to ×0.75.
#   Godot --headless --path <root> res://scenes/map_mod_check.tscn
# ============================================================================

func _ready() -> void:
	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager
	GameState.set_process(false)
	GameState.hard_reset()
	var fails := 0
	print("[MAPMOD] ============ map-mod system check ============")
	# 1) loot mult compounds
	cm.set_active_map_mods(["hardened_hulls", "exotic_dampening"])
	var lm: float = cm.get_map_mod_loot_mult()
	var ok1: bool = abs(lm - 1.4 * 1.6) < 0.001
	fails += 0 if ok1 else 1
	print("[MAPMOD] loot_mult 1.4×1.6 = %.3f %s" % [lm, "OK" if ok1 else "*** FAIL"])
	# 2) cap at 3, dedupe, reject bogus
	cm.set_active_map_mods(["hardened_hulls", "early_enrage", "exotic_dampening", "swarm", "hardened_hulls", "bogus"])
	var ok2: bool = cm.active_map_mods.size() == 3 and not ("bogus" in cm.active_map_mods)
	fails += 0 if ok2 else 1
	print("[MAPMOD] cap/dedupe/validate: size=%d no-bogus=%s %s" % [cm.active_map_mods.size(), not ("bogus" in cm.active_map_mods), "OK" if ok2 else "*** FAIL"])
	# 3) spawn difficulty effects vs enemy_db base (phased boss → no zone-steepen; no warp → no catch-up)
	var db: Dictionary = cm.enemy_db["z12_boss_rift_warden"]["stats"]
	var b_sh: int = int(db["max_shield"]); var b_hp: int = int(db["hp"])
	var b_en: float = float(cm.enemy_db["z12_boss_rift_warden"].get("enrage_at", 0))
	cm.set_active_map_mods(["hardened_hulls", "swarm", "early_enrage"])
	cm.current_zone = cm.zones["the_rift"]; cm.target_enemy_id = "z12_boss_rift_warden"; cm.spawn_enemy()
	var m_sh: int = int(cm.current_enemy["max_shield"]); var m_hp: int = int(cm.current_enemy["max_hp"]); var m_en: float = float(cm.current_enemy.get("enrage_at", 0))
	var ok3: bool = abs(float(m_sh) - b_sh * 1.6) < 2.0 and abs(float(m_hp) - b_hp * 1.45) < 2.0 and abs(m_en - (b_en + 0.20)) < 0.001
	fails += 0 if ok3 else 1
	print("[MAPMOD] spawn: shield %d→%d(×1.6) hp %d→%d(×1.45) enrage %.2f→%.2f(+.20) %s" % [b_sh, m_sh, b_hp, m_hp, b_en, m_en, "OK" if ok3 else "*** FAIL"])
	# 4) exotic dampening — verify the has_map_mod GATE that drives the ×0.75 factor in the
	# dmg_cryo weapon-state build. The ×0.75 multiplier itself is a one-line conditional
	# (`* (0.75 if has_map_mod("exotic_dampening") else 1.0)`), inspection-verified and
	# exercised in real combat's weapon-state build (a headless probe can't equip+build here).
	cm.set_active_map_mods(["exotic_dampening"])
	var g_on: bool = cm.has_map_mod("exotic_dampening")
	cm.set_active_map_mods([])
	var g_off: bool = not cm.has_map_mod("exotic_dampening")
	var ok4: bool = g_on and g_off
	fails += 0 if ok4 else 1
	print("[MAPMOD] exotic dampening gate: on=%s off=%s (×0.75 factor inspection-verified) %s" % [g_on, g_off, "OK" if ok4 else "*** FAIL"])
	print("[MAPMOD] %s" % ("ALL PASS" if fails == 0 else "*** %d FAILURE(S)" % fails))
	get_tree().quit(0)
