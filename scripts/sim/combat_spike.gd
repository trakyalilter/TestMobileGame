extends Node

# ============================================================================
# Phase 2 COMBAT SPIKE — validate the fight loop runs headless before building
# the funded combat-progression policy.
#
# Cheats the supply chain (grant_module + dumped ammo) to isolate ONE question:
# does combat_manager resolve fights, loot, win/lose, and auto-respawn when
# driven by manual process_tick() calls with no UI? Also yields a real datapoint:
# how a basic Z1 corvette loadout fares vs Z1 trash and the Z1 boss.
# ============================================================================

const DT := 0.25

var kills := 0
var losses := 0

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	GameState.set_process(false)
	GameState.hard_reset()
	GameState.resources.add_currency("credits", 100)
	seed(777)

	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager

	# --- Arm the corvette: grant + equip a full Z1 loadout (free, to isolate
	#     combat from the funding chain). Reset already gave 2 z1_battery. ---
	sm.grant_module("z1_kinetic", 2)
	sm.grant_module("z1_shield", 1)
	sm.grant_module("z1_armor", 1)
	sm.grant_module("z1_engine", 1)
	sm.grant_module("z1_sensor", 1)
	# Ammo so kinetic weapons can actually fire (no-ammo = 0 damage).
	GameState.resources.add_element("SlugT1", 2000)

	# Equip into corvette slots:
	# ["weapon","weapon","shield","armor","engine","battery","battery","sensor"]
	_eq(sm, 0, "z1_kinetic")
	_eq(sm, 1, "z1_kinetic")
	_eq(sm, 2, "z1_shield")
	_eq(sm, 3, "z1_armor")
	_eq(sm, 4, "z1_engine")
	_eq(sm, 7, "z1_sensor")
	sm.recalc_stats()

	print("[CSPIKE] loadout: hull=%s hp=%d/%d  atk(k/e/x)=%d/%d/%d  energy=%d/%d" % [
		sm.active_hull, sm.current_hp, sm.max_hp,
		int(sm.attack_kinetic), int(sm.attack_energy), int(sm.attack_explosive),
		int(sm.energy_used), int(sm.energy_capacity)])
	if sm.energy_used > sm.energy_capacity:
		print("[CSPIKE] WARNING ship would be UNPOWERED — combat entry will be blocked")

	if cm.has_signal("enemy_defeated"):
		cm.enemy_defeated.connect(_on_kill)

	# --- Test 1: farm Z1 trash for 600 sim-seconds ---
	var cr0: float = GameState.resources.get_currency("credits")
	cm.start_expedition("lunar_orbit")
	cm.set_target_enemy("z1_dust_mite")
	_fight_for(cm, sm, 600.0)
	var cr1: float = GameState.resources.get_currency("credits")
	print("[CSPIKE] TRASH 600s: kills=%d  credits +%d  hp=%d/%d  in_combat=%s" % [
		kills, int(cr1 - cr0), sm.current_hp, sm.max_hp, str(cm.in_combat)])

	# --- Test 2: attempt the Z1 boss for up to 300 sim-seconds ---
	var k0 := kills
	var l0 := losses
	cm.start_expedition("lunar_orbit")
	cm.set_target_enemy("z1_boss_architect")
	_fight_for(cm, sm, 300.0)
	var core: float = GameState.resources.get_element_amount("Z1_Core")
	print("[CSPIKE] BOSS 300s: boss_kills~%d  losses=%d  Z1_Core=%d  hp=%d/%d  in_combat=%s" % [
		kills - k0, losses - l0, int(core), sm.current_hp, sm.max_hp, str(cm.in_combat)])

	print("[CSPIKE] done")
	get_tree().quit(0)

func _fight_for(cm, sm, seconds: float) -> void:
	var steps := int(seconds / DT)
	for _i in range(steps):
		# Keep fighting: if a loss/retreat dropped us out of combat, re-enter.
		if not cm.in_combat:
			if sm.current_hp <= 0:
				losses += 1
			cm.start_expedition(cm.current_zone_id if cm.current_zone_id else "lunar_orbit")
		cm.process_tick(DT)

func _eq(sm, slot: int, mid: String) -> void:
	var ok = sm.equip_module(slot, mid)
	if not ok:
		print("[CSPIKE] equip FAILED slot %d <- %s (%s)" % [slot, mid, str(sm.can_equip_module(mid))])

func _on_kill(_enemy_id = null) -> void:
	kills += 1
