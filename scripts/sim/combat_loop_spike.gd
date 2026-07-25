extends Node

# ============================================================================
# COMBAT LOOP SPIKE — the DEFENSIVE side of a real fight, which the offense-
# focused spikes (rarity_pen / combat_spike) never exercise. Drives the REAL
# _execute_enemy_attack / _execute_player_attack with controlled state to assert:
#   * armor mitigation reduces incoming damage
#   * evasion dodges attacks
#   * shield absorbs before hull
#   * lethal hit -> lose_fight -> retreat (combat ends; player CAN die)
#   * lifesteal affix (hull_heal_on_hit) heals on a player hit
#   * ammo drains ~1/shot, and ammo_eff saves a slice
#   * restore_on_kill heals on a kill
# Run: res://scenes/combat_loop_spike.tscn (headless, self-quits).
# ============================================================================

var _pass := 0
var _fail := 0

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	GameState.set_process(false)
	GameState.hard_reset()
	seed(909)
	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager
	GameState.resources.add_currency("credits", 1000000000.0)  # lose_fight repair is free

	_setup(cm)
	_test_mitigation(cm, sm)
	_test_evasion(cm, sm)
	_test_shield(cm, sm)
	_test_lifesteal(cm, sm)
	_test_ammo(cm, sm)
	_test_restore_on_kill(cm, sm)
	_test_death(cm, sm)   # last: lose_fight mutates module durability

	print("[CLS] ============================================================")
	print("[CLS] RESULT: %d passed, %d failed" % [_pass, _fail])
	print("[CLS] %s" % ("ALL PASS" if _fail == 0 else "*** FAILURES ***"))
	get_tree().quit(0 if _fail == 0 else 1)

# ---------------------------------------------------------------------------
func _setup(cm) -> void:
	cm.level = 1                 # < 25 so milestone evasion = 0
	cm.current_zone = {"difficulty": 1, "id": "", "enemies": []}
	cm.current_zone_id = ""      # no relic reduction
	cm._tier_def_factor = 1.0
	cm._tier_shield_factor = 1.0
	cm._enemy_enraged = false
	cm.has_reflective = false
	cm.has_exotic_matrix = false
	cm.has_reactive = false
	cm.in_combat = true

func _kin_enemy(atk: int, acc: int) -> Dictionary:
	return {"name": "Dummy", "id": "dummy", "atk": atk, "accuracy": acc, "dmg_type": "kinetic",
		"def": 0, "max_shield": 0, "hp": 99999999, "max_hp": 99999999,
		"loot": [], "xp": 0, "module_drop_pool": [], "module_drop_chance": 0.0,
		"rare_loot": [], "resist_k": 0.0, "resist_e": 0.0, "resist_x": 0.0}

# Fire n enemy attacks at an effectively-immortal player; return total hull damage.
func _enemy_dmg_over(cm, sm, n: int) -> float:
	sm.max_hp = 100000000
	sm.current_hp = sm.max_hp
	var hp0: float = float(sm.current_hp)
	for i in range(n):
		cm._execute_enemy_attack()
	return hp0 - float(sm.current_hp)

func _test_mitigation(cm, sm) -> void:
	cm.current_enemy = _kin_enemy(2000, 0)
	cm.enemy_hp = 99999999
	cm.enemy_max_hp = 99999999
	sm.evasion = 0
	cm.player_shield = 0.0
	cm.player_max_shield = 0.0
	sm.defense = 0
	var d0: float = _enemy_dmg_over(cm, sm, 200)
	sm.defense = 2000
	var dA: float = _enemy_dmg_over(cm, sm, 200)
	print("[CLS] mitigation: 200 hits  def=0 -> %.0f   def=2000 -> %.0f" % [d0, dA])
	_chk("armor reduces incoming damage (def 2000 takes < 85%% of def 0)", dA < d0 * 0.85 and dA > 0.0)

func _test_evasion(cm, sm) -> void:
	cm.current_enemy = _kin_enemy(2000, 0)
	cm.enemy_hp = 99999999
	cm.enemy_max_hp = 99999999
	sm.defense = 0
	cm.player_shield = 0.0
	cm.player_max_shield = 0.0
	sm.evasion = 0
	var d0: float = _enemy_dmg_over(cm, sm, 300)
	sm.evasion = 2000           # dodge ~0.93 -> capped at 0.75
	var dE: float = _enemy_dmg_over(cm, sm, 300)
	print("[CLS] evasion: 300 hits  eva=0 -> %.0f   eva=2000 -> %.0f (~25%% land)" % [d0, dE])
	_chk("evasion dodges most attacks (eva 2000 takes < half)", dE < d0 * 0.5 and dE > 0.0)

func _test_shield(cm, sm) -> void:
	cm.current_enemy = _kin_enemy(2000, 0)
	cm.enemy_hp = 99999999
	cm.enemy_max_hp = 99999999
	sm.defense = 0
	sm.evasion = 0
	sm.max_hp = 100000
	sm.current_hp = 100000
	cm.player_max_shield = 100000.0
	cm.player_shield = 100000.0
	cm._execute_enemy_attack()
	print("[CLS] shield: after 1 hit  shield=%.0f  hull=%.0f" % [cm.player_shield, float(sm.current_hp)])
	_chk("shield absorbs the hit (shield dropped)", cm.player_shield < 100000.0)
	_chk("hull essentially untouched (shield absorbs all but the 1-dmg floor)", (100000.0 - float(sm.current_hp)) <= 2.0)

func _test_death(cm, sm) -> void:
	cm.current_enemy = _kin_enemy(100000, 0)   # one-shots
	cm.enemy_hp = 99999999
	cm.enemy_max_hp = 99999999
	sm.defense = 0
	sm.evasion = 0
	cm.player_max_shield = 0.0
	cm.player_shield = 0.0
	sm.max_hp = 100
	sm.current_hp = 100
	cm.in_combat = true
	cm._execute_enemy_attack()                 # lethal -> current_hp<=0 -> lose_fight -> retreat
	print("[CLS] death: in_combat after lethal hit = %s" % str(cm.in_combat))
	_chk("lethal hit ends the fight (lose_fight/retreat ran, in_combat false)", not cm.in_combat)

# ---------------------------------------------------------------------------
# Player-attack tests need a real fitted weapon + ammo.
func _fit_weapon(cm, sm) -> bool:
	var hull_id: String = ""
	for h in sm.hulls:
		hull_id = str(h)
		break
	sm.active_hull = hull_id
	sm.loadout = {0: "z1_kinetic"}
	sm.ammo_loadout = {0: "SlugT1"}
	GameState.resources.add_element("SlugT1", 2000000)
	sm.recalc_stats()
	cm._rebuild_player_weapon_states()
	sm.energy_used = 0                    # force "powered" (no battery in this stub loadout)
	cm.is_jammed = false
	cm.in_combat = true
	return not cm.player_weapon_states.is_empty()

func _test_lifesteal(cm, sm) -> void:
	if not _fit_weapon(cm, sm):
		print("[CLS] lifesteal: no weapon fitted - skip")
		return
	cm.current_enemy = _kin_enemy(1, 0)
	cm.enemy_hp = 99999999
	cm.enemy_max_hp = 99999999
	cm.enemy_shield = 0
	sm.gem_bonuses = {}
	sm.affix_bonuses["hull_heal_on_hit"] = 100.0
	sm.max_hp = 100000
	sm.current_hp = 1000
	var hp0: float = float(sm.current_hp)
	cm._execute_player_attack(0)
	print("[CLS] lifesteal: hp %.0f -> %.0f (hull_heal_on_hit 100)" % [hp0, float(sm.current_hp)])
	_chk("hull_heal_on_hit heals on a player attack", float(sm.current_hp) > hp0)
	sm.affix_bonuses["hull_heal_on_hit"] = 0.0

func _test_ammo(cm, sm) -> void:
	if not _fit_weapon(cm, sm):
		print("[CLS] ammo: no weapon fitted - skip")
		return
	cm.current_enemy = _kin_enemy(1, 0)
	cm.enemy_hp = 99999999
	cm.enemy_max_hp = 99999999
	cm.enemy_shield = 0
	var shots: int = 200
	sm.gem_bonuses = {}
	var a0: float = GameState.resources.get_element_amount("SlugT1")
	for i in range(shots):
		cm._execute_player_attack(0)
	var used: float = a0 - GameState.resources.get_element_amount("SlugT1")
	print("[CLS] ammo: %d shots, no ammo_eff -> %.0f consumed" % [shots, used])
	_chk("ammo drains ~1/shot (no ammo_eff)", abs(used - float(shots)) < float(shots) * 0.05)
	sm.gem_bonuses = {"ammo_eff": 0.40}
	var b0: float = GameState.resources.get_element_amount("SlugT1")
	for i in range(shots):
		cm._execute_player_attack(0)
	var used2: float = b0 - GameState.resources.get_element_amount("SlugT1")
	print("[CLS] ammo: %d shots, ammo_eff 0.40 -> %.0f consumed (expect ~%d)" % [shots, used2, int(float(shots) * 0.6)])
	_chk("ammo_eff 0.40 saves ~40%% of ammo", abs(used2 - float(shots) * 0.60) < float(shots) * 0.10)
	sm.gem_bonuses = {}

func _test_restore_on_kill(cm, sm) -> void:
	if not _fit_weapon(cm, sm):
		print("[CLS] restore_on_kill: no weapon fitted - skip")
		return
	# real Z1 zone so win_fight's auto-respawn (spawn_enemy) has a valid enemy list
	for z in cm.zones:
		if int(cm.zones[z].get("difficulty", 0)) == 1:
			cm.current_zone = cm.zones[z]
			cm.current_zone_id = str(z)
			break
	sm.gem_bonuses = {"restore_on_kill": 0.10}
	sm.max_hp = 10000
	sm.current_hp = 1000
	cm.current_enemy = _kin_enemy(1, 0)
	cm.enemy_shield = 0
	cm.enemy_hp = 1
	cm.enemy_max_hp = 1
	var hp0: float = float(sm.current_hp)
	cm.win_fight()                  # runs restore_on_kill, then auto-respawns next enemy
	print("[CLS] restore_on_kill: hp %.0f -> %.0f (rok 0.10 of 10000 = +1000)" % [hp0, float(sm.current_hp)])
	_chk("restore_on_kill heals %% max HP on kill", float(sm.current_hp) > hp0)
	sm.gem_bonuses = {}

# ---------------------------------------------------------------------------

func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
	print("[CLS]   %s  %s" % [("PASS" if cond else "FAIL"), label])
