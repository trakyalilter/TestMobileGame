extends Node
# niv_0 — INDEPENDENT migration regression test (v149).
# Covers: alias case (modules[mid] IS custom_modules[mid]), non-alias copy case,
# every old-missile roll bound, the unchanged kinetic base, a Unique max roll,
# a legacy pre-0.15-coefficient roll in the (2.0, 2.4) gap, and idempotency
# (running the migration twice must not scale twice).

func _mk(sm, id, base, iv, dmg_key, dmg, alias: bool) -> void:
	var d := {"base_module": base, "rarity": 3,
		"stats": {dmg_key: dmg, "energy_load": 30, "atk_interval": iv}}
	sm.custom_modules[id] = d
	if alias:
		sm.modules[id] = d                      # same Dictionary object
	else:
		sm.modules[id] = d.duplicate(true)      # independent copy

func _dps(st: Dictionary) -> float:
	var a: float = 0.0
	for k in ["atk_kinetic", "atk_energy", "atk_explosive", "atk_cryo"]:
		a += float(st.get(k, 0.0))
	return a / maxf(0.0001, float(st["atk_interval"]))

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cases := [
		["alias_min",   "z3_missile", 2.40, "atk_explosive", 145.0, true],
		["alias_mid",   "z3_missile", 3.60, "atk_explosive", 113.0, true],
		["alias_max",   "z3_missile", 4.00, "atk_explosive",  87.0, true],
		["copy_mid",    "z9_missile", 3.10, "atk_explosive", 12000.0, false],
		["unique_roll", "z5_missile", 2.41, "atk_explosive", 1350.0, true],
		["kinetic_2_0", "z3_kinetic", 1.55, "atk_kinetic",    60.0,  true],
		["kinetic_max", "z3_kinetic", 2.00, "atk_kinetic",    45.0,  true],
		["legacy_gap",  "z3_missile", 2.13, "atk_explosive", 191.0, true],
	]
	var before := {}
	for c in cases:
		_mk(sm, c[0], c[1], c[2], c[3], c[4], c[5])
		before[c[0]] = _dps(sm.custom_modules[c[0]]["stats"])
	sm._migrate_uniform_atk_interval()
	print("[NIV0M] --- after 1st migration ---")
	var after1 := {}
	for c in cases:
		var st: Dictionary = sm.custom_modules[c[0]]["stats"]
		after1[c[0]] = _dps(st)
		var err: float = (after1[c[0]] / maxf(0.000001, before[c[0]]) - 1.0) * 100.0
		var mirror_ok: bool = is_equal_approx(float(sm.modules[c[0]]["stats"]["atk_interval"]), float(st["atk_interval"]))
		print("[NIV0M] %-12s iv %.4f -> %.4f  dps %.5f -> %.5f  err %+.6f%%  uniform=%s mirror=%s" % [
			c[0], float(c[2]), float(st["atk_interval"]), before[c[0]], after1[c[0]], err,
			str(float(st["atk_interval"]) <= 2.0001), str(mirror_ok)])
	sm._migrate_uniform_atk_interval()
	print("[NIV0M] --- idempotency (2nd run must be a no-op) ---")
	for c in cases:
		var st2: Dictionary = sm.custom_modules[c[0]]["stats"]
		var d2: float = _dps(st2)
		print("[NIV0M] %-12s dps %.5f -> %.5f  drift %+.6f%%" % [c[0], after1[c[0]], d2, (d2 / maxf(0.000001, after1[c[0]]) - 1.0) * 100.0])
	get_tree().quit()
