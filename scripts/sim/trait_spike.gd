extends Node
# ============================================================================
# P3 TRAIT-ENGINE SPIKE (v139d) — asserts each boss-trait block's math with
# synthetic trait data injected onto a real spawned enemy (no shipped enemy
# carries trait data yet, so the engine must be balance-neutral by default).
#   Godot --headless --path <root> res://scenes/trait_spike.tscn
# ============================================================================

var fails := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		fails += 1
	print("[TRAIT] %-34s %s %s" % [name, "OK" if cond else "*** FAIL", detail])

func _ready() -> void:
	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager
	GameState.set_process(false)
	GameState.hard_reset()
	print("[TRAIT] ============ P3 trait engine spike ============")

	# Live fight context on a real Z1 enemy.
	cm.start_expedition("lunar_orbit")
	cm.set_target_enemy("z1_lunar_drone")
	var have_enemy: bool = cm.current_enemy != null
	_ok("spawn context", have_enemy)
	if not have_enemy:
		get_tree().quit(1)
		return

	# 1) Balance-neutral by default: no trait data -> all no-ops
	_ok("default def_mult 1.0", cm._trait_def_mult() == 1.0)
	var shield0: float = float(cm.enemy_shield)
	cm._trait_tick(5.0)
	_ok("default tick no-op", float(cm.enemy_shield) == shield0)

	# 2) Reactive Armor: step per N hits, capped
	cm._reset_trait_state()
	cm.current_enemy["reactive_armor"] = {"per_hits": 3, "def_mult": 1.5, "cap": 2.0}
	for _i in range(3):
		cm._trait_note_player_hit("kinetic")
	_ok("reactive step1 = 1.5", is_equal_approx(cm._trait_def_mult(), 1.5))
	for _i in range(3):
		cm._trait_note_player_hit("kinetic")
	_ok("reactive capped = 2.0", is_equal_approx(cm._trait_def_mult(), 2.0))
	cm.current_enemy.erase("reactive_armor")

	# 3) Adaptive Grid: hit channel gains resist, capped; missile maps to explosive
	cm._reset_trait_state()
	cm.current_enemy["adaptive_grid"] = {"per_hit_resist": 0.1, "cap": 0.3}
	var rk0: float = float(cm.current_enemy.get("resist_k", 0.0))
	for _i in range(5):
		cm._trait_note_player_hit("kinetic")
	var rk_gain: float = float(cm.current_enemy.get("resist_k", 0.0)) - rk0
	_ok("adaptive k capped +0.3", is_equal_approx(rk_gain, 0.3), "gain=%.2f" % rk_gain)
	var rx0: float = float(cm.current_enemy.get("resist_x", 0.0))
	cm._trait_note_player_hit("missile")
	_ok("adaptive missile->explosive", float(cm.current_enemy.get("resist_x", 0.0)) > rx0)
	cm.current_enemy.erase("adaptive_grid")

	# 4) Sustain pulse: +pct max_shield every N s
	cm._reset_trait_state()
	cm.current_enemy["sustain"] = {"kind": "pulse", "every_s": 2.0, "pct": 0.10}
	cm.enemy_max_shield = 1000.0
	cm.enemy_shield = 0.0
	cm._trait_tick(2.1)
	_ok("pulse +10% shield", abs(float(cm.enemy_shield) - 100.0) < 1.0, "shield=%.0f" % float(cm.enemy_shield))

	# 5) Sustain nanite: below threshold, regen for dur, once per fight
	cm.current_enemy["sustain"] = {"kind": "nanite", "below": 0.30, "dur": 2.0, "hull_pct_per_s": 0.10}
	cm._reset_trait_state()
	cm.enemy_max_hp = 1000
	cm.enemy_hp = 250
	cm._trait_tick(1.0)
	_ok("nanite regen ~+100", abs(float(cm.enemy_hp) - 350.0) < 5.0, "hp=%.0f" % float(cm.enemy_hp))
	cm._trait_tick(5.0)  # duration expires; second trigger must NOT re-arm
	var hp_after: float = float(cm.enemy_hp)
	cm.enemy_hp = 200
	cm._trait_tick(1.0)
	_ok("nanite once per fight", abs(float(cm.enemy_hp) - 200.0) < 5.0, "hp=%.0f (was %.0f)" % [float(cm.enemy_hp), hp_after])
	cm.current_enemy.erase("sustain")

	# 6) Corrosive field: shield-bypassing hull DoT
	cm._reset_trait_state()
	cm.current_enemy["corrosive_field"] = {"hull_dps_pct": 0.01}
	sm.current_hp = sm.max_hp
	var hp0: float = float(sm.current_hp)
	cm._trait_tick(1.0)
	var dot: float = hp0 - float(sm.current_hp)
	_ok("corrosive ~1%/s hull", abs(dot - sm.max_hp * 0.01) < 1.0, "dot=%.1f" % dot)
	cm.current_enemy.erase("corrosive_field")
	sm.current_hp = sm.max_hp

	# 7) Charge nuke: counter cycle — telegraph on N-1, nuke on N
	cm._reset_trait_state()
	cm.current_enemy["charge_nuke"] = {"every_n": 3, "mult": 4.0}
	cm.current_enemy["atk"] = 0  # harmless swings; we assert the counter cycle
	cm.current_enemy["accuracy"] = 0
	cm._execute_enemy_attack()
	var c1: int = cm._cn_count
	cm._execute_enemy_attack()
	var c2: int = cm._cn_count
	var telegraphed := false
	for ev in cm.combat_events:
		if String(ev.get("text", "")) == "CHARGING MAIN CANNON":
			telegraphed = true
	cm._execute_enemy_attack()
	_ok("nuke counter cycle 1,2,0", c1 == 1 and c2 == 2 and cm._cn_count == 0, "%d,%d,%d" % [c1, c2, cm._cn_count])
	_ok("nuke telegraph on N-1", telegraphed)
	cm.current_enemy.erase("charge_nuke")

	# 8) Volatile: death burst before victory; shields absorb; lethal = loss
	cm._reset_trait_state()
	cm.current_enemy["volatile"] = {"mult": 2.0}
	cm.current_enemy["atk"] = 100
	cm.player_shield = 500.0
	cm.player_max_shield = 500.0
	sm.current_hp = sm.max_hp
	cm.enemy_hp = 0
	var k0: int = int(cm.total_kills)
	cm.win_fight()
	_ok("volatile absorbed by shield", abs(float(cm.player_shield) - 300.0) < 1.0, "shield=%.0f" % float(cm.player_shield))
	# win_fight auto-continues the expedition (spawns the next target), so the
	# survivor check is the KILL landing, not combat ending.
	_ok("volatile survivor still wins", int(cm.total_kills) == k0 + 1 and float(sm.current_hp) > 0.0)

	# 9) Volatile lethal: burst through hull = LOSS (no kill credit path taken)
	if cm.current_enemy != null and cm.in_combat:
		cm._reset_trait_state()
		cm.current_enemy["volatile"] = {"mult": 2.0}
		cm.current_enemy["atk"] = 100000
		cm.player_shield = 0.0
		sm.current_hp = 10.0
		cm.enemy_hp = 0
		cm.win_fight()
		_ok("volatile lethal = loss", not cm.in_combat, "hp=%.0f" % float(sm.current_hp))

	print("[TRAIT] %s" % ("ALL PASS" if fails == 0 else "*** %d FAILURE(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
