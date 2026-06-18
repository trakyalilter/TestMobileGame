extends Node

# ============================================================================
# RARITY x PENETRATION SPIKE (v115) — verifies the "tier dominates rarity +
# honest penetration wall" rebalance with REAL manager calls (no re-derivation).
#
#   SECTION 1  Rarity x tier DPS ladder. Drives generate_module_drop and the
#              tooltip DPS formula (atk_* / atk_interval). Asserts the design rule:
#                 Z(N) Common  >  Z(N-1) Legendary    (tier dominates rarity)
#                 Z(N) Unique  >  Z(N+1) Common        (Unique still leapfrogs)
#
#   SECTION 2  Honest penetration wall vs a tier_hardened enemy. Shows effective
#              DPS (= raw x module_tier_penetration) + ~TTK, and asserts:
#                 under-tier gear (incl. Legendary) is WALLED (pen < 1)
#                 tier-matched Common PIERCES; Z(N-1) Unique PIERCES (skip-key)
#                 eff_dps(Z(N) Common) > eff_dps(Z(N-1) Legendary)  <-- the thesis
#
# Rarity enum ints (mirror shipyard_manager): COMMON0 UNCOMMON1 RARE2 LEG3 UNIQ4.
# Run: res://scenes/rarity_pen_spike.tscn  (headless, self-quits).
# ============================================================================

const SAMPLES := 120          # rolls per rarity to estimate the ceiling (max roll)
const LADDER_ZONES := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
const WALL_TIERS := [2, 3, 4, 5, 6, 7, 8, 9, 10]   # every tier_hardened mainline zone

const R_COMMON := 0
const R_UNCOMMON := 1
const R_RARE := 2
const R_LEGENDARY := 3
const R_UNIQUE := 4

var _pass := 0
var _fail := 0

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	GameState.set_process(false)
	GameState.hard_reset()
	seed(2026)
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager

	_section_ladder(sm)
	_section_wall(sm, cm)

	print("[RPS] ============================================================")
	print("[RPS] RESULT: %d passed, %d failed" % [_pass, _fail])
	print("[RPS] %s" % ("ALL PASS" if _fail == 0 else "*** FAILURES ***"))
	get_tree().quit(0 if _fail == 0 else 1)

# ---------------------------------------------------------------------------
func _section_ladder(sm) -> void:
	print("[RPS] ===== SECTION 1: RARITY x TIER DPS LADDER (kinetic weapon, max roll) =====")
	print("[RPS] Zone |  Common | Uncmn(mx)| Rare(mx) | Lgnd(mx) | Uniq(mx)")
	var common := {}
	var legend := {}
	var uniq := {}
	for z in LADDER_ZONES:
		var base_id: String = "z%d_kinetic" % int(z)
		if not (base_id in sm.modules):
			continue
		var c: float = _dps_max(sm, base_id, R_COMMON, int(z), 1)
		var un: float = _dps_max(sm, base_id, R_UNCOMMON, int(z), SAMPLES)
		var r: float = _dps_max(sm, base_id, R_RARE, int(z), SAMPLES)
		var l: float = _dps_max(sm, base_id, R_LEGENDARY, int(z), SAMPLES)
		var u: float = _dps_max(sm, base_id, R_UNIQUE, int(z), SAMPLES)
		common[int(z)] = c
		legend[int(z)] = l
		uniq[int(z)] = u
		print("[RPS] Z%-3d | %7.1f | %8.1f | %8.1f | %8.1f | %8.1f" % [int(z), c, un, r, l, u])

	print("[RPS] ----- ordering asserts (tier dominates rarity) -----")
	for z in LADDER_ZONES:
		var zn: int = int(z) + 1
		if common.has(zn) and legend.has(int(z)):
			_chk("Z%d Common (%.1f) > Z%d Legendary-max (%.1f)" % [zn, float(common[zn]), int(z), float(legend[int(z)])], float(common[zn]) > float(legend[int(z)]))
	for z in LADDER_ZONES:
		var zn2: int = int(z) + 1
		if uniq.has(int(z)) and common.has(zn2):
			_chk("Z%d Unique-max (%.1f) > Z%d Common (%.1f) [leapfrog]" % [int(z), float(uniq[int(z)]), zn2, float(common[zn2])], float(uniq[int(z)]) > float(common[zn2]))

# ---------------------------------------------------------------------------
func _section_wall(sm, cm) -> void:
	print("[RPS] ===== SECTION 2: HONEST PENETRATION WALL across every hardened zone =====")
	print("[RPS] Per zone T: own-tier Common (craft path), under-tier (T-1) Legendary (should")
	print("[RPS] WALL), under-tier (T-1) Unique (skip-key). th = enemy tier_hardened. eff = DPS")
	print("[RPS] after penetration (raw x pen). PRC=pierces, WALL=walled.")
	print("[RPS] zone enemy(th)                  | T-1 Legendary    | T-1 Unique       | T Common")
	print("[RPS]                                  | pen / eff / vd   | pen / eff / vd   | pen / eff / vd")
	for T in WALL_TIERS:
		var ti: int = int(T)
		var enemy := _backhalf_enemy(cm, ti)
		if enemy.is_empty():
			print("[RPS] Z%-2d  (no hardened back-half enemy found - skip)" % ti)
			continue
		var th: int = int(enemy["th"])
		var legb := _gen_best(sm, "z%d_kinetic" % (ti - 1), R_LEGENDARY, ti - 1)
		var unib := _gen_best(sm, "z%d_kinetic" % (ti - 1), R_UNIQUE, ti - 1)
		var comb := _gen_best(sm, "z%d_kinetic" % ti, R_COMMON, ti)
		var lp: float = sm.module_tier_penetration(str(legb["mid"]), th)
		var up: float = sm.module_tier_penetration(str(unib["mid"]), th)
		var cp: float = sm.module_tier_penetration(str(comb["mid"]), th)
		var le: float = float(legb["dps"]) * lp
		var ue: float = float(unib["dps"]) * up
		var ce: float = float(comb["dps"]) * cp
		print("[RPS] Z%-2d  %-25s(%d)| %.2f %7.1f %-4s| %.2f %7.1f %-4s| %.2f %7.1f %-4s" % [
			ti, str(enemy["id"]), th,
			lp, le, _verdict(lp), up, ue, _verdict(up), cp, ce, _verdict(cp)])
		_chk("Z%d under-tier Legendary WALLED" % ti, lp < 1.0)
		_chk("Z%d under-tier Unique PIERCES (skip-key)" % ti, up >= 1.0)
		_chk("Z%d own-tier Common PIERCES (craft path)" % ti, cp >= 1.0)
		_chk("Z%d eff Common (%.1f) > eff under-Legendary (%.1f)" % [ti, ce, le], ce > le)

# ---------------------------------------------------------------------------
func _dps_max(sm, base_id: String, rarity: int, zone: int, samples: int) -> float:
	var best: float = 0.0
	for i in range(samples):
		var mid: String = sm.generate_module_drop(base_id, rarity, zone)
		if mid == "":
			continue
		var d: float = _wdps(sm.modules.get(mid, {}).get("stats", {}))
		if d > best:
			best = d
	return best

func _wdps(stats: Dictionary) -> float:
	var dmg: float = float(stats.get("atk_kinetic", 0)) + float(stats.get("atk_energy", 0)) + float(stats.get("atk_explosive", 0)) + float(stats.get("atk_cryo", 0))
	var interval: float = maxf(0.01, float(stats.get("atk_interval", 2.5)))
	return dmg / interval

func _gen_best(sm, base_id: String, rarity: int, zone: int) -> Dictionary:
	if not (base_id in sm.modules):
		return {"mid": "", "dps": 0.0}
	var best_mid: String = ""
	var best_dps: float = -1.0
	for i in range(SAMPLES):
		var mid: String = sm.generate_module_drop(base_id, rarity, zone)
		if mid == "":
			continue
		var d: float = _wdps(sm.modules.get(mid, {}).get("stats", {}))
		if d > best_dps:
			best_dps = d
			best_mid = mid
	return {"mid": best_mid, "dps": maxf(0.0, best_dps)}

func _verdict(p: float) -> String:
	return "PRC" if p >= 1.0 else "WALL"

func _backhalf_enemy(cm, t: int) -> Dictionary:
	for z in cm.zones:
		if int(cm.zones[z].get("difficulty", 0)) == t:
			var ens: Array = cm.zones[z].get("enemies", [])
			if ens.size() >= 3:
				var eid: String = str(ens[2])   # e3 = hardened back half
				var e = cm.enemy_db.get(eid, {})
				return {"id": eid, "hp": float(e.get("stats", {}).get("hp", 1)), "th": cm.get_enemy_tier_hardened(eid, str(z))}
	return {}

func _fmt_ttk(s: float) -> String:
	if s < 0.0:
		return "inf"
	if s >= 3600.0:
		return "%.0fh" % (s / 3600.0)
	if s >= 120.0:
		return "%.0fm" % (s / 60.0)
	return "%.0fs" % s

func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
	print("[RPS]   %s  %s" % [("PASS" if cond else "FAIL"), label])
