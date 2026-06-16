extends Node

# ============================================================================
# PHASE-GATE SPIKE (NG+ P1) — verifies the multi-phase boss damage gate that
# generalizes the Z11 warp_hardened Cryo wall:
#   * _phase_index splits HP into N even bands (full HP -> 0, dead -> N-1)
#   * _get_breach_factors gives FULL damage only to the current phase's element
#     and cuts every other channel to phase_cut
#   * Z11 warp_hardened stays BYTE-IDENTICAL (k/e/x x0.02, cryo full)
#   * enemy attacks + non-gated enemies are untouched (all 1.0) -> existing
#     conventional combat is mathematically unchanged
#   * an element with no weapon channel yet (corrosion/thermal/…) cuts the whole
#     band -> the intended forward gate (unbeatable until P3 ships the weapon)
#
# Deterministic (no RNG): asserts the gate logic directly, not via sampled DPS.
# Run: tools/run_sim.ps1 -Scene "res://scenes/phase_gate_spike.tscn"
# ============================================================================

var _fails := 0

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	GameState.set_process(false)
	var cm = GameState.combat_manager
	cm.enemy_max_hp = 1000

	print("[PHASE] ---- _phase_index (HP -> band) ----")
	_eq_i("n1 full", _pi(cm, 1000, 1), 0)
	_eq_i("n1 dead", _pi(cm, 0, 1), 0)
	_eq_i("n3 full", _pi(cm, 1000, 3), 0)
	_eq_i("n3 0.70", _pi(cm, 700, 3), 0)
	_eq_i("n3 0.60", _pi(cm, 600, 3), 1)
	_eq_i("n3 0.40", _pi(cm, 400, 3), 1)
	_eq_i("n3 0.30", _pi(cm, 300, 3), 2)
	_eq_i("n3 dead", _pi(cm, 0, 3), 2)
	_eq_i("n5 full", _pi(cm, 1000, 5), 0)
	_eq_i("n5 0.50", _pi(cm, 500, 5), 2)
	_eq_i("n5 dead", _pi(cm, 0, 5), 4)

	print("[PHASE] ---- _get_breach_factors ----")
	cm.enemy_max_hp = 1000
	cm.enemy_hp = 1000

	cm.current_enemy = {"resist_k": 0.0}
	_eq_f("nogate", cm._get_breach_factors(true), {"k": 1.0, "e": 1.0, "x": 1.0, "cryo": 1.0})

	cm.current_enemy = {"warp_hardened": true}
	_eq_f("enemyatk (gated but enemy)", cm._get_breach_factors(false), {"k": 1.0, "e": 1.0, "x": 1.0, "cryo": 1.0})
	_eq_f("z11 warp_hardened", cm._get_breach_factors(true), {"k": 0.02, "e": 0.02, "x": 0.02, "cryo": 1.0})

	var pb = {"phases": ["cryo", "kinetic", "energy"], "phase_cut": 0.15}
	cm.current_enemy = pb
	cm.enemy_max_hp = 1000
	cm.enemy_hp = 1000
	_eq_f("ph0 cryo", cm._get_breach_factors(true), {"k": 0.15, "e": 0.15, "x": 0.15, "cryo": 1.0})
	cm.enemy_hp = 500
	_eq_f("ph1 kinetic", cm._get_breach_factors(true), {"k": 1.0, "e": 0.15, "x": 0.15, "cryo": 0.15})
	cm.enemy_hp = 100
	_eq_f("ph2 energy", cm._get_breach_factors(true), {"k": 0.15, "e": 1.0, "x": 0.15, "cryo": 0.15})

	cm.current_enemy = {"phases": ["corrosion"], "phase_cut": 0.15}
	cm.enemy_hp = 1000
	_eq_f("unmappable corrosion -> all cut", cm._get_breach_factors(true), {"k": 0.15, "e": 0.15, "x": 0.15, "cryo": 0.15})

	cm.current_enemy = {"phases": ["kinetic", "energy"]}
	cm.enemy_max_hp = 1000
	cm.enemy_hp = 1000
	_eq_f("default phase_cut=0.15", cm._get_breach_factors(true), {"k": 1.0, "e": 0.15, "x": 0.15, "cryo": 0.15})

	print("[PHASE] ---- typed exotic (weapon element vs phase) ----")
	var tb = {"phases": ["cryo", "corrosion", "kinetic"], "phase_cut": 0.15}
	cm.current_enemy = tb
	cm.enemy_max_hp = 1000
	cm.enemy_hp = 1000
	_eq_f("cryo wpn / cryo phase", cm._get_breach_factors(true, "cryo"), {"k": 0.15, "e": 0.15, "x": 0.15, "cryo": 1.0})
	cm.enemy_hp = 500
	_eq_f("cryo wpn / corrosion phase", cm._get_breach_factors(true, "cryo"), {"k": 0.15, "e": 0.15, "x": 0.15, "cryo": 0.15})
	cm.enemy_hp = 1000
	_eq_f("corr wpn / cryo phase", cm._get_breach_factors(true, "corrosion"), {"k": 0.15, "e": 0.15, "x": 0.15, "cryo": 0.15})
	cm.enemy_hp = 500
	_eq_f("corr wpn / corrosion phase", cm._get_breach_factors(true, "corrosion"), {"k": 0.15, "e": 0.15, "x": 0.15, "cryo": 1.0})
	cm.enemy_hp = 100
	_eq_f("corr wpn / kinetic phase", cm._get_breach_factors(true, "corrosion"), {"k": 1.0, "e": 0.15, "x": 0.15, "cryo": 0.15})
	cm.current_enemy = {"warp_hardened": true}
	_eq_f("z11 / corrosion wpn (no breach)", cm._get_breach_factors(true, "corrosion"), {"k": 0.02, "e": 0.02, "x": 0.02, "cryo": 0.02})
	_eq_f("z11 / cryo wpn (identical)", cm._get_breach_factors(true, "cryo"), {"k": 0.02, "e": 0.02, "x": 0.02, "cryo": 1.0})

	print("[PHASE] ---- can_swap_loadout_in_combat gate ----")
	cm.in_combat = false
	cm.current_enemy = {"phases": ["cryo", "corrosion"]}
	_eq_b("not in combat", cm.can_swap_loadout_in_combat(), false)
	cm.in_combat = true
	cm.current_enemy = {}
	_eq_b("in combat, no phases", cm.can_swap_loadout_in_combat(), false)
	cm.current_enemy = {"phases": ["cryo"]}
	_eq_b("in combat, single phase", cm.can_swap_loadout_in_combat(), false)
	cm.current_enemy = {"phases": ["cryo", "corrosion"]}
	_eq_b("in combat, multi phase", cm.can_swap_loadout_in_combat(), true)
	cm.in_combat = false

	print("[PHASE] ---- _rebuild_player_weapon_states (runtime, no crash) ----")
	cm._rebuild_player_weapon_states()
	_eq_b("weapon states is Array", cm.player_weapon_states is Array, true)
	print("[PHASE]   (rebuilt %d weapon state(s))" % cm.player_weapon_states.size())

	print("[PHASE] ---- Z12 Rift Warden (end-to-end spawn wiring) ----")
	cm.current_zone = cm.zones["the_rift"]
	cm.target_enemy_id = "z12_boss_rift_warden"
	cm.spawn_enemy()
	_eq_b("warden phases copied", cm.current_enemy.get("phases", []) == ["cryo", "corrosion"], true)
	_eq_b("warden phase_cut copied", abs(float(cm.current_enemy.get("phase_cut", -1.0)) - 0.15) < 0.0001, true)
	# Phase 0 (full HP) = Cryo-hardened
	cm.enemy_hp = cm.enemy_max_hp
	_eq_b("p0 cryo wpn breaches", abs(float(cm._get_breach_factors(true, "cryo")["cryo"]) - 1.0) < 0.0001, true)
	_eq_b("p0 corrosion wpn stalls", abs(float(cm._get_breach_factors(true, "corrosion")["cryo"]) - 0.15) < 0.0001, true)
	# Phase 1 (low HP) = Corrosion-hardened — THE swap-forcing proof
	cm.enemy_hp = int(cm.enemy_max_hp * 0.1)
	_eq_b("p1 cryo wpn STALLS (swap!)", abs(float(cm._get_breach_factors(true, "cryo")["cryo"]) - 0.15) < 0.0001, true)
	_eq_b("p1 corrosion wpn breaches", abs(float(cm._get_breach_factors(true, "corrosion")["cryo"]) - 1.0) < 0.0001, true)
	cm.in_combat = true
	_eq_b("warden allows in-fight swap", cm.can_swap_loadout_in_combat(), true)
	cm.in_combat = false
	# Trash enemy is NOT gated (any weapon clears it)
	cm.target_enemy_id = "z12_acid_revenant"
	cm.spawn_enemy()
	_eq_b("trash not gated (no phases)", (cm.current_enemy.get("phases", []) as Array).is_empty(), true)

	print("[PHASE] ---- Z12 reachability + content wiring ----")
	GameState.game_settings["z12_unlocked"] = false
	_eq_b("the_rift hidden when locked", not _has_zone(cm.get_available_zones(), "the_rift"), true)
	GameState.game_settings["z12_unlocked"] = true
	_eq_b("the_rift shown when unlocked", _has_zone(cm.get_available_zones(), "the_rift"), true)
	GameState.game_settings["z12_unlocked"] = false
	_eq_b("corrosion_armaments tech exists", "corrosion_armaments" in GameState.research_manager.tech_tree, true)
	var sm2 = GameState.shipyard_manager
	_eq_b("corrosion_blaster module exists", "corrosion_blaster" in sm2.modules, true)
	var cb_stats: Dictionary = sm2.modules.get("corrosion_blaster", {}).get("stats", {})
	_eq_b("corrosion_blaster tagged corrosion", str(cb_stats.get("exotic_element", "")) == "corrosion", true)
	_eq_b("corrosion_blaster gated by tech", str(sm2.modules.get("corrosion_blaster", {}).get("research_req", "")) == "corrosion_armaments", true)

	if _fails == 0:
		print("[PHASE] ALL PASS")
	else:
		print("[PHASE] *** %d FAILURE(S)" % _fails)
	get_tree().quit(0)

func _pi(cm, hp: int, n: int) -> int:
	cm.enemy_hp = hp
	return cm._phase_index(n)

func _eq_i(label: String, got: int, want: int) -> void:
	var ok: bool = got == want
	if not ok: _fails += 1
	print("[PHASE]   %-28s got=%d want=%d  %s" % [label, got, want, "OK" if ok else "*** FAIL"])

func _eq_f(label: String, got: Dictionary, want: Dictionary) -> void:
	var ok: bool = true
	for key in want:
		if abs(float(got.get(key, -999.0)) - float(want[key])) > 0.0001:
			ok = false
	if not ok: _fails += 1
	print("[PHASE]   %-32s got=%s  %s" % [label, str(got), "OK" if ok else "*** FAIL want=%s" % str(want)])

func _eq_b(label: String, got: bool, want: bool) -> void:
	var ok: bool = got == want
	if not ok: _fails += 1
	print("[PHASE]   %-32s got=%s want=%s  %s" % [label, str(got), str(want), "OK" if ok else "*** FAIL"])

func _has_zone(zlist: Array, zid: String) -> bool:
	for z in zlist:
		if z.get("id", "") == zid:
			return true
	return false
