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

	_section_resist(sm, cm)
	_section_ttk(sm, cm)
	_section_cores(sm, cm)

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
# SECTION 3: damage-type resistance via the REAL resolve_damage. armor=shield=0
# isolates the resist axis; ±10% variance averaged over N. Confirms resist
# reduces same-type damage, the triangle rewards switching, and resist composes
# with the tier-penetration wall (independent multipliers).
func _section_resist(sm, cm) -> void:
	print("[RPS] ##### SECTION 3: DAMAGE-TYPE RESISTANCE (real resolve_damage, armor/shield=0) #####")
	var N: int = 400
	var A: float = 1000.0
	var none: Dictionary = {"resist_k": 0.0, "resist_e": 0.0, "resist_x": 0.0}
	var base_k: float = _avg_hull(cm, A, 0.0, 0.0, none, N)
	var base_e: float = _avg_hull(cm, 0.0, A, 0.0, none, N)
	var base_x: float = _avg_hull(cm, 0.0, 0.0, A, none, N)
	print("[RPS] no-resist hull (atk=1000): KIN %.0f  NRG %.0f  EXP %.0f  (intrinsic type-vs-hull)" % [base_k, base_e, base_x])

	# 1) kin-RESIST vs KIN weapon. v116: authored 0.5 AMPLIFIES to 0.80 -> does ~20%.
	var kr: Dictionary = {"resist_k": 0.5, "resist_e": 0.0, "resist_x": 0.0}
	var kin_vs_kr: float = _avg_hull(cm, A, 0.0, 0.0, kr, N)
	print("[RPS] kin-RESIST(0.5->amp0.80) vs KIN: %.0f  (x%.2f of no-resist %.0f)" % [kin_vs_kr, kin_vs_kr / base_k, base_k])
	_chk("KIN vs kin-resist(0.5->0.80) ~= 0.20x", abs(kin_vs_kr / base_k - 0.20) < 0.05)
	# v116: explicit amplification curve (positives scaled to <=0.80, weakness intact)
	_chk("amp(0.45) ~= 0.80", abs(float(cm._amp_resist(0.45)) - 0.80) < 0.01)
	_chk("amp(0.25) ~= 0.445", abs(float(cm._amp_resist(0.25)) - 0.445) < 0.01)
	_chk("amp(-0.40) = -0.40 (weakness intact)", abs(float(cm._amp_resist(-0.40)) + 0.40) < 0.001)

	# 2) vs that kin-resist enemy, the other types out-damage kinetic (switch!)
	var nrg_vs_kr: float = _avg_hull(cm, 0.0, A, 0.0, kr, N)
	var exp_vs_kr: float = _avg_hull(cm, 0.0, 0.0, A, kr, N)
	print("[RPS] vs kin-RESIST enemy: KIN %.0f  NRG %.0f  EXP %.0f  (-> switch off kinetic)" % [kin_vs_kr, nrg_vs_kr, exp_vs_kr])
	_chk("NRG out-damages resisted KIN", nrg_vs_kr > kin_vs_kr)
	_chk("EXP out-damages resisted KIN", exp_vs_kr > kin_vs_kr)

	# 3) WEAKNESS (resist_k = -0.40): KIN does ~1.4x
	var kw: Dictionary = {"resist_k": -0.40, "resist_e": 0.0, "resist_x": 0.0}
	var kin_vs_kw: float = _avg_hull(cm, A, 0.0, 0.0, kw, N)
	print("[RPS] kin-WEAK(-0.40) vs KIN: %.0f  (x%.2f)" % [kin_vs_kw, kin_vs_kw / base_k])
	_chk("KIN vs kin-WEAK(-0.40) ~= 1.4x", abs(kin_vs_kw / base_k - 1.4) < 0.05)

	# 4) resist COMPOSES with the tier-penetration wall (both reductions apply).
	#    under-tier kin weapon = pen 0.15 applied to atk BEFORE resolve_damage.
	var pen: float = 0.15
	var kin_pen_resist: float = _avg_hull(cm, A * pen, 0.0, 0.0, kr, N)
	print("[RPS] under-tier KIN (pen .15) vs kin-RESIST(amp0.80): %.0f  (expect ~%.0f = base x.15 x.20)" % [kin_pen_resist, base_k * pen * 0.20])
	_chk("penetration x resistance compose (~base*0.030)", abs(kin_pen_resist / base_k - pen * 0.20) < 0.02)

	# context: do real enemies actually carry resistances?
	var with_resist: int = 0
	for eid in cm.enemy_db:
		var e = cm.enemy_db[eid]
		if abs(float(e.get("resist_k", 0.0))) > 0.001 or abs(float(e.get("resist_e", 0.0))) > 0.001 or abs(float(e.get("resist_x", 0.0))) > 0.001:
			with_resist += 1
	print("[RPS] enemy_db: %d / %d enemies carry K/E/X resistances" % [with_resist, cm.enemy_db.size()])

func _avg_hull(cm, atk_k: float, atk_e: float, atk_x: float, enemy: Dictionary, samples: int) -> float:
	cm.current_enemy = enemy
	cm.enemy_hp = 100
	cm.enemy_max_hp = 100
	cm.current_zone_id = ""
	cm.has_reactive = false
	cm.enemy_vulnerable_timer = 0.0
	var tot: float = 0.0
	for i in range(samples):
		var res: Array = cm.resolve_damage(atk_k, atk_e, atk_x, 0.0, 0.0, 1, 0.0, true, 0.0, "cryo")
		tot += float(res[1])
	return tot / float(samples)

# ---------------------------------------------------------------------------
# SECTION 4: real TTK by weapon type vs strongly-resisted enemies. Builds the
# current-tier Common weapon of each type, computes hull dps via resolve_damage
# (armor/shield=0 isolates resist), TTK = hp/dps. Shows the wrong type is now a
# big TTK penalty (force switch) and asserts every enemy still has a viable type.
func _section_ttk(sm, cm) -> void:
	print("[RPS] ##### SECTION 4: TTK BY WEAPON TYPE vs resisted enemies (amplified <=80%) #####")
	print("[RPS] current-tier Common weapon each type; armor/shield=0; TTK = hp / eff-dps.")
	print("[RPS] enemy (tier, hp)                  | KIN ttk | NRG ttk | EXP ttk | wrong/right")
	var tier_map: Dictionary = _enemy_tier_map(cm)
	var shown: int = 0
	for eid in cm.enemy_db:
		if shown >= 8:
			break
		var e = cm.enemy_db[eid]
		if e.get("is_boss", false) or e.get("warp_hardened", false):
			continue
		var tier: int = int(tier_map.get(str(eid), 0))
		if tier < 1 or not (("z%d_kinetic" % tier) in sm.modules):
			continue
		if max(float(e.get("resist_k", 0.0)), max(float(e.get("resist_e", 0.0)), float(e.get("resist_x", 0.0)))) < 0.40:
			continue   # only enemies that strongly resist a type
		var hp: float = float(e.get("stats", {}).get("hp", 1))
		var tk: float = _ttk_for(sm, cm, e, tier, hp, "kinetic")
		var tn: float = _ttk_for(sm, cm, e, tier, hp, "energy")
		var tx: float = _ttk_for(sm, cm, e, tier, hp, "missile")
		var best: float = min(tk, min(tn, tx))
		var worst: float = max(tk, max(tn, tx))
		var gap: float = (worst / best) if best > 0.0 else 0.0
		print("[RPS] %-32s(t%d,%d)| %6.0fs | %6.0fs | %6.0fs | %.1fx" % [str(eid), tier, int(hp), tk, tn, tx, gap])
		shown += 1
	# safety: amplification must never leave an enemy with NO viable type
	var trapped: int = 0
	for eid in cm.enemy_db:
		var e = cm.enemy_db[eid]
		if e.get("warp_hardened", false):
			continue
		var amin: float = min(_amp(float(e.get("resist_k", 0.0))), min(_amp(float(e.get("resist_e", 0.0))), _amp(float(e.get("resist_x", 0.0)))))
		if amin >= 0.60:
			trapped += 1
	_chk("no enemy resists ALL K/E/X >= 0.60 (a viable type always exists)", trapped == 0)
	print("[RPS] trapped enemies (no viable type): %d" % trapped)

func _enemy_tier_map(cm) -> Dictionary:
	var m: Dictionary = {}
	for z in cm.zones:
		var diff: int = int(cm.zones[z].get("difficulty", 0))
		for eid in cm.zones[z].get("enemies", []):
			m[str(eid)] = diff
	return m

func _ttk_for(sm, cm, enemy: Dictionary, tier: int, hp: float, wtype: String) -> float:
	var base_id: String = "z%d_%s" % [tier, wtype]
	if not (base_id in sm.modules):
		return -1.0
	var st: Dictionary = sm.modules[base_id].get("stats", {})
	var ak: float = float(st.get("atk_kinetic", 0))
	var ae: float = float(st.get("atk_energy", 0))
	var ax: float = float(st.get("atk_explosive", 0))
	var interval: float = maxf(0.1, float(st.get("atk_interval", 2.5)))
	var per_hit: float = _avg_hull(cm, ak, ae, ax, enemy, 250)
	var dps: float = per_hit / interval
	return (hp / dps) if dps > 0.0 else -1.0

func _amp(r: float) -> float:
	if r > 0.0:
		return minf(r * 1.78, 0.80)
	return r

# ---------------------------------------------------------------------------
# SECTION 5 (v118): matrix-core TYPE-MATCHING. The SAME core yields a different
# facet by host slot category. Verifies the Phase-1 aggregation: Crimson in a
# weapon -> crit_damage (offense); in armor -> damage_reduction (defense), NEVER
# offense; in engine -> heat_eff (utility). (Phase 2 wires facets into combat.)
func _section_cores(sm, cm) -> void:
	print("[RPS] ##### SECTION 5: MATRIX CORE FACETS (v118 type-matching) #####")
	GameState.resources.add_element("PristineCrimsonCore", 3)
	# Pristine Crimson: weapon crit_damage 0.30 / defense damage_reduction 0.06 / utility heat_eff 0.20
	var wb: Dictionary = _socket_and_aggregate(sm, sm.generate_module_drop("z5_kinetic", R_LEGENDARY, 5), "PristineCrimsonCore")
	print("[RPS] Crimson in WEAPON -> %s" % str(wb))
	_chk("Crimson/weapon = crit_damage 0.30 (offense facet)", abs(float(wb.get("crit_damage", 0.0)) - 0.30) < 0.001)
	_chk("Crimson/weapon has NO defense bonus", not wb.has("damage_reduction"))
	var ab: Dictionary = _socket_and_aggregate(sm, sm.generate_module_drop("z5_armor", R_LEGENDARY, 5), "PristineCrimsonCore")
	print("[RPS] Crimson in ARMOR  -> %s" % str(ab))
	_chk("Crimson/armor = damage_reduction 0.06 (defense facet)", abs(float(ab.get("damage_reduction", 0.0)) - 0.06) < 0.001)
	_chk("Crimson/armor has NO offense (no aggro on armor)", not ab.has("crit_damage"))
	var eb: Dictionary = _socket_and_aggregate(sm, sm.generate_module_drop("z5_engine", R_LEGENDARY, 5), "PristineCrimsonCore")
	if not eb.is_empty():
		print("[RPS] Crimson in ENGINE -> %s" % str(eb))
		_chk("Crimson/engine = heat_eff 0.20 (utility facet)", abs(float(eb.get("heat_eff", 0.0)) - 0.20) < 0.001)
		_chk("Crimson/engine has NO offense", not eb.has("crit_damage"))

# Equip a single socketed module, insert one core, recalc, return a copy of the
# resulting gem_bonuses (the facet chosen by the host slot category).
func _socket_and_aggregate(sm, mid: String, core: String) -> Dictionary:
	if mid == "" or sm.modules.get(mid, {}).get("sockets", []).size() == 0:
		return {}
	var hull_id: String = ""
	for h in sm.hulls:
		hull_id = str(h)
		break
	sm.active_hull = hull_id
	sm.loadout = {0: mid}
	sm.insert_gem(mid, 0, core)
	return sm.gem_bonuses.duplicate(true)

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
