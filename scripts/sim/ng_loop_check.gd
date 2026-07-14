extends Node
# ============================================================================
# NG+ LOOP 1 (Z13-Z15) WIRING CHECK (v137 NG+ step 2) — verifies the Corrosion-
# loop content: the 3 zones exist with the right difficulty + unlock_flag, each
# boss carries the correct `phases`, spawn_enemy copies them, the multi-phase
# breach gate resolves per band, get_available_zones honors the flags, and the
# clear->Warp->unlock chain fires (z12_cleared + Warp -> z13_unlocked).
#   Godot --headless --path <root> res://scenes/ng_loop_check.tscn
# ============================================================================

func _ready() -> void:
	var cm = GameState.combat_manager
	var wm = GameState.warp_manager
	GameState.set_process(false)
	GameState.hard_reset()
	var fails := 0
	print("[NGLOOP] ============ Z13-Z15 Corrosion loop check ============")
	# 1) zones exist, correct difficulty + flag
	for z in [["the_verdigris", 13, "z13_unlocked"], ["the_dissolution", 14, "z14_unlocked"], ["the_caustic_core", 15, "z15_unlocked"]]:
		var zd: Dictionary = cm.zones.get(z[0], {})
		var ok: bool = int(zd.get("difficulty", 0)) == int(z[1]) and String(zd.get("unlock_flag", "")) == String(z[2])
		if not ok: fails += 1
		print("[NGLOOP] %-18s diff=%d flag=%-13s %s" % [z[0], int(zd.get("difficulty", 0)), zd.get("unlock_flag", ""), "OK" if ok else "*** FAIL"])
	# 2) boss phases correct
	for b in [["z13_boss_verdigris_warden", ["corrosion", "cryo"]], ["z14_boss_dissolution_tyrant", ["cryo", "corrosion", "cryo"]], ["z15_boss_caustic_sovereign", ["corrosion", "cryo", "corrosion"]]]:
		var ph: Array = cm.enemy_db.get(b[0], {}).get("phases", [])
		var ok: bool = ph == b[1]
		if not ok: fails += 1
		print("[NGLOOP] %-30s phases=%-30s %s" % [b[0], str(ph), "OK" if ok else "*** FAIL exp %s" % str(b[1])])
	# 3) spawn copies phases (Z14 3-phase boss)
	cm.current_zone = cm.zones["the_dissolution"]
	cm.target_enemy_id = "z14_boss_dissolution_tyrant"
	cm.spawn_enemy()
	var sp: bool = cm.current_enemy.get("phases", []) == ["cryo", "corrosion", "cryo"]
	if not sp: fails += 1
	print("[NGLOOP] spawn copies phases: %s %s" % [str(cm.current_enemy.get("phases", [])), "OK" if sp else "*** FAIL"])
	# 4) multi-phase breach gate (bands cryo / corrosion / cryo)
	cm.enemy_max_hp = 900
	cm.enemy_hp = 900   # band 0 -> cryo
	var b0: bool = abs(float(cm._get_breach_factors(true, "cryo").get("cryo", 0)) - 1.0) < 0.01
	cm.enemy_hp = 500   # band 1 -> corrosion
	var b1c: bool = abs(float(cm._get_breach_factors(true, "corrosion").get("cryo", 0)) - 1.0) < 0.01
	var b1x: bool = abs(float(cm._get_breach_factors(true, "cryo").get("cryo", 0)) - 0.15) < 0.01
	cm.enemy_hp = 100   # band 2 -> cryo
	var b2: bool = abs(float(cm._get_breach_factors(true, "cryo").get("cryo", 0)) - 1.0) < 0.01
	if not (b0 and b1c and b1x and b2): fails += 1
	print("[NGLOOP] gate: b0 cryo=%s | b1 corr=%s cryo-stall=%s | b2 cryo=%s  %s" % [b0, b1c, b1x, b2, "OK" if (b0 and b1c and b1x and b2) else "*** FAIL"])
	# 5) get_available_zones honors the flag
	GameState.game_settings["z13_unlocked"] = false
	var hidden: bool = not _has(cm.get_available_zones(), "the_verdigris")
	GameState.game_settings["z13_unlocked"] = true
	var shown: bool = _has(cm.get_available_zones(), "the_verdigris")
	if not (hidden and shown): fails += 1
	print("[NGLOOP] flag-gate: hidden-when-locked=%s shown-when-unlocked=%s %s" % [hidden, shown, "OK" if (hidden and shown) else "*** FAIL"])
	# 6) clear -> Warp -> unlock chain: z12_cleared + Warp -> z13_unlocked
	GameState.game_settings["z13_unlocked"] = false
	GameState.game_settings["z12_cleared"] = true
	GameState.resources.lifetime_credits = 5_000_000_000.0
	wm.credits_at_warp_start = 0.0
	wm.execute_warp()
	var chain: bool = bool(GameState.game_settings.get("z13_unlocked", false))
	if not chain: fails += 1
	print("[NGLOOP] chain: (z12_cleared + Warp) -> z13_unlocked=%s %s" % [chain, "OK" if chain else "*** FAIL"])
	print("[NGLOOP] %s" % ("ALL PASS" if fails == 0 else "*** %d FAILURE(S)" % fails))
	get_tree().quit(0)

func _has(zlist: Array, zid: String) -> bool:
	for z in zlist:
		if String(z.get("id", "")) == zid:
			return true
	return false
