extends Node
# v163: verifies the per-enemy module_drop_weights override actually reaches the
# roll. The field is read off current_enemy, which spawn_enemy builds field by
# field -- the exact shape that silently dropped resist_cryo and boss_core_qty.
# Measures the real _pick_weighted_base over the live z1_lunar_drone pool.
const N := 60000

func _ready() -> void:
	GameState.set_process(false)
	GameState.hard_reset()
	seed(99)
	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager
	var fails := 0

	# 1. spawn the real enemy and confirm the override survived the copy.
	cm.start_expedition("lunar_orbit")
	cm.set_target_enemy("z1_lunar_drone")
	var ov: Dictionary = cm.current_enemy.get("module_drop_weights", {})
	var c1: bool = int(ov.get("weapon", 0)) == 20
	if not c1: fails += 1
	print("[Z1POOL] override reached current_enemy   %s (%s)" % ["OK" if c1 else "*** FAIL", str(ov)])

	# 2. sample the live weighted pick with that override.
	var pool: Array = cm.current_enemy.get("module_drop_pool", [])
	var hits := {}
	for _i in range(N):
		var b: String = cm._pick_weighted_base(pool, sm, ov)
		hits[b] = int(hits.get(b, 0)) + 1
	var wpct := 100.0 * float(hits.get("z1_kinetic", 0)) / float(N)
	var c2: bool = wpct > 45.0 and wpct < 55.0
	if not c2: fails += 1
	print("[Z1POOL] weapon share ~50%%                 %s (%.1f%%)" % ["OK" if c2 else "*** FAIL", wpct])

	# 3. battery must still never drop (global weight 0 not overridden).
	var c3: bool = int(hits.get("z1_battery", 0)) == 0
	if not c3: fails += 1
	print("[Z1POOL] battery never drops              %s" % ["OK" if c3 else "*** FAIL"])

	# 4. an enemy WITHOUT the field is unchanged (weapon 1/3 of a 3-way pool).
	var base_hits := {}
	for _i in range(N):
		var b2: String = cm._pick_weighted_base(pool, sm, {})
		base_hits[b2] = int(base_hits.get(b2, 0)) + 1
	var bpct := 100.0 * float(base_hits.get("z1_kinetic", 0)) / float(N)
	var c4: bool = bpct > 30.0 and bpct < 37.0
	if not c4: fails += 1
	print("[Z1POOL] no-override still 1/3            %s (%.1f%%)" % ["OK" if c4 else "*** FAIL", bpct])

	print("[Z1POOL] %s" % ("ALL PASS" if fails == 0 else "*** %d FAIL" % fails))
	get_tree().quit(1 if fails > 0 else 0)
