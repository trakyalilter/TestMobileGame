extends Node

# ============================================================================
# RARITY x PENETRATION SPIKE (v115) — verifies the "tier dominates rarity +
# honest penetration wall" rebalance with REAL manager calls, across ALL three
# conventional weapon types (kinetic / energy / missile=explosive).
#
#   SECTION 1  Rarity x tier DPS ladder, per weapon type. Drives
#              generate_module_drop + the tooltip DPS formula. Asserts:
#                 Z(N) Common  >  Z(N-1) Legendary   (tier dominates rarity)
#                 Z(N) Unique  >  Z(N+1) Common       (Unique leapfrogs)
#
#   SECTION 2  Penetration wall at every hardened zone Z2..Z10, per weapon type:
#                 under-tier Legendary WALLED, under-tier Unique PIERCES
#                 (skip-key), own-tier Common PIERCES & out-effs the Legendary.
#
# Rarity enum ints (mirror shipyard_manager): COMMON0 UNCOMMON1 RARE2 LEG3 UNIQ4.
# Run: res://scenes/rarity_pen_spike.tscn  (headless, self-quits).
# ============================================================================

const SAMPLES := 120          # rolls per rarity to estimate the ceiling (max roll)
const LADDER_ZONES := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
const WALL_TIERS := [2, 3, 4, 5, 6, 7, 8, 9, 10]   # every tier_hardened mainline zone
const WTYPES := ["kinetic", "energy", "missile"]    # missile = explosive damage type

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

	print("[RPS] ##### SECTION 1: RARITY x TIER DPS LADDER (per weapon type) #####")
	for wt in WTYPES:
		_section_ladder(sm, str(wt))
	print("[RPS] ##### SECTION 2: HONEST PENETRATION WALL Z2..Z10 (per weapon type) #####")
	for wt in WTYPES:
		_section_wall(sm, cm, str(wt))

	print("[RPS] ============================================================")
	print("[RPS] RESULT: %d passed, %d failed" % [_pass, _fail])
	print("[RPS] %s" % ("ALL PASS" if _fail == 0 else "*** FAILURES ***"))
	get_tree().quit(0 if _fail == 0 else 1)

# ---------------------------------------------------------------------------
func _section_ladder(sm, wtype: String) -> void:
	print("[RPS] --- LADDER [%s] (max-roll DPS) ---" % wtype)
	print("[RPS] Zone |  Common | Uncmn | Rare  | Lgnd  |  Uniq")
	var common := {}
	var legend := {}
	var uniq := {}
	for z in LADDER_ZONES:
		var zi: int = int(z)
		var base_id: String = "z%d_%s" % [zi, wtype]
		if not (base_id in sm.modules):
			continue
		var c: float = _dps_max(sm, base_id, R_COMMON, zi, 1)
		var un: float = _dps_max(sm, base_id, R_UNCOMMON, zi, SAMPLES)
		var r: float = _dps_max(sm, base_id, R_RARE, zi, SAMPLES)
		var l: float = _dps_max(sm, base_id, R_LEGENDARY, zi, SAMPLES)
		var u: float = _dps_max(sm, base_id, R_UNIQUE, zi, SAMPLES)
		common[zi] = c
		legend[zi] = l
		uniq[zi] = u
		print("[RPS] Z%-3d | %7.1f | %5.1f | %5.1f | %5.1f | %6.1f" % [zi, c, un, r, l, u])
	for z in LADDER_ZONES:
		var zi2: int = int(z)
		var zn: int = zi2 + 1
		if common.has(zn) and legend.has(zi2):
			_chk("[%s] Z%d Common (%.1f) > Z%d Legendary (%.1f)" % [wtype, zn, float(common[zn]), zi2, float(legend[zi2])], float(common[zn]) > float(legend[zi2]))
		if uniq.has(zi2) and common.has(zn):
			_chk("[%s] Z%d Unique (%.1f) > Z%d Common (%.1f) [leapfrog]" % [wtype, zi2, float(uniq[zi2]), zn, float(common[zn])], float(uniq[zi2]) > float(common[zn]))

# ---------------------------------------------------------------------------
func _section_wall(sm, cm, wtype: String) -> void:
	print("[RPS] --- WALL [%s] (under-tier Legendary should WALL, own Common PIERCE) ---" % wtype)
	var ok: int = 0
	var tot: int = 0
	for T in WALL_TIERS:
		var ti: int = int(T)
		var enemy := _backhalf_enemy(cm, ti)
		if enemy.is_empty():
			continue
		var th: int = int(enemy["th"])
		var legb := _gen_best(sm, "z%d_%s" % [ti - 1, wtype], R_LEGENDARY, ti - 1)
		var unib := _gen_best(sm, "z%d_%s" % [ti - 1, wtype], R_UNIQUE, ti - 1)
		var comb := _gen_best(sm, "z%d_%s" % [ti, wtype], R_COMMON, ti)
		var lp: float = sm.module_tier_penetration(str(legb["mid"]), th)
		var up: float = sm.module_tier_penetration(str(unib["mid"]), th)
		var cp: float = sm.module_tier_penetration(str(comb["mid"]), th)
		var le: float = float(legb["dps"]) * lp
		var ce: float = float(comb["dps"]) * cp
		print("[RPS] Z%-2d %-22s| underLeg %.2f %-4s eff%8.1f | Uniq %.2f %-4s | Common %.2f %-4s eff%8.1f" % [
			ti, str(enemy["id"]), lp, _verdict(lp), le, up, _verdict(up), cp, _verdict(cp), ce])
		var a: bool = lp < 1.0          # under-tier Legendary walled
		var b: bool = up >= 1.0         # under-tier Unique pierces (skip-key)
		var c2: bool = cp >= 1.0        # own-tier Common pierces
		var d: bool = ce > le           # weaker-raw Common out-effs the Legendary
		for cond in [a, b, c2, d]:
			tot += 1
			if cond:
				ok += 1
		if not (a and b and c2 and d):
			print("[RPS]   FAIL [%s] Z%d  (leg<1=%s uniq>=1=%s com>=1=%s effCom>effLeg=%s)" % [wtype, ti, str(a), str(b), str(c2), str(d)])
	_pass += ok
	_fail += (tot - ok)
	print("[RPS]   [%s] wall checks: %d/%d passed" % [wtype, ok, tot])

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

func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
	print("[RPS]   %s  %s" % [("PASS" if cond else "FAIL"), label])
