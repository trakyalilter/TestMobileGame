extends Node
# ============================================================================
# DR_AUDIT — depth-rule audit + TRANSITIVE cost expansion.
#
# Every figure here is expanded to root gathered resources / combat drops via a
# fixed point over the SINGLE FOREGROUND SLOT. No figure is ever read off a
# recipe's own duration alone (that is the bug that made v157 report 1.01 h for
# a 2.2-4.1 h bundle).
#
#   minutes-per-unit(sym, z) = min over
#       gather action              : 1 / (units per min)
#       recipe                     : duration/out + SUM in qty/out * mpu(in)
#       AFFORDABLE building at z   : SUM in qty/out * mpu(in)   [convert = free]
#       combat drop at zone <= z   : (1/drop_per_kill) / KPH * 60
#
#   <godot> --headless --path <root> res://scenes/dr_audit.tscn
# ============================================================================

const KPH := 60.0
const COST_SLOTS := {
	"armor": true, "shield": true, "weapon": true,
	"engine": true, "battery": true, "sensor": true,
}
const ROOTS := ["Dirt", "Water", "Wood", "Fe", "Cu", "Si", "C"]
const INF := 1.0e18

var sm
var pm
var im
var gm
var cm

var gath_rate := {}          # sym -> units/min best gather action
var recipes_for := {}        # sym -> [rid]
var bldgs_for := {}          # sym -> [bid]
var all_syms := {}

var mpu := {}                # z -> {sym: minutes}
var srcs := {}               # z -> {sym: ["G"|"R:rid"|"B:bid"|"K:zone"]}


func _pad(s: String, n: int) -> String:
	var o := s
	while o.length() < n:
		o += " "
	return o


func _rpad(s: String, n: int) -> String:
	var o := s
	while o.length() < n:
		o = " " + o
	return o


func _f(v: float, dp: int = 2) -> String:
	return String.num(v, dp)


func _ready() -> void:
	sm = GameState.shipyard_manager
	pm = GameState.processing_manager
	im = GameState.infrastructure_manager
	gm = GameState.gathering_manager
	cm = GameState.combat_manager
	sm._build_cost_index()

	_index()
	_solve_all()

	_sec_depth_census()
	_sec_pdepth_census()
	_sec_srcdump()
	_sec_candidates()
	_sec_module_direct_depth()
	_sec_refit_roots()
	_sec_bundle()
	_sec_guided_chain()
	_sec_breadth()
	_sec_buildable()
	print("\n=== DR_AUDIT END ===")
	get_tree().quit()


func _index() -> void:
	for aid in gm.actions:
		var a: Dictionary = gm.actions[aid]
		var du: float = maxf(0.001, float(a.get("duration", 3.0)))
		for row in a.get("loot_table", []):
			var s := String(row[0])
			var avg: float = (float(row[2]) + float(row[3])) * 0.5 * float(row[1])
			gath_rate[s] = maxf(float(gath_rate.get(s, 0.0)), avg / du * 60.0)
			all_syms[s] = true
	for rid in pm.recipes:
		var r: Dictionary = pm.recipes[rid]
		for s2 in r.get("output", {}):
			var k := String(s2)
			if not recipes_for.has(k):
				recipes_for[k] = []
			(recipes_for[k] as Array).append(rid)
			all_syms[k] = true
		for s2i in r.get("input", {}):
			all_syms[String(s2i)] = true
	for bid in im.building_db:
		var b: Dictionary = im.building_db[bid]
		for s3 in b.get("yield", {}):
			var k3 := String(s3)
			if not bldgs_for.has(k3):
				bldgs_for[k3] = []
			(bldgs_for[k3] as Array).append(bid)
			all_syms[k3] = true
		for s3i in b.get("input", {}):
			all_syms[String(s3i)] = true
	for s4 in sm._cost_drop_rate:
		all_syms[String(s4)] = true


# matter_deconstructor converts 2500 Cu into 0.6 total output — a deliberate Cu
# SINK, but "the conversion itself is free" then makes it the cheapest source of
# Superalloy/Circuit in a pure-time model and poisons every root-demand figure
# routed through it (it alone produced the 57-million-Cu Z5 refit in the first
# baseline run). A conversion with an input:output mass ratio this extreme is not
# a production path a player uses to SOURCE the output, so it is excluded from
# path selection. Flagged as an out-of-scope finding, not silently patched.
const MASS_RATIO_MAX := 200.0
var _mr := {}
func _mass_ratio(bid: String) -> float:
	if _mr.has(bid):
		return float(_mr[bid])
	var b: Dictionary = im.building_db[bid]
	var i := 0.0
	var o := 0.0
	for k in b.get("input", {}):
		i += float(b["input"][k])
	for k2 in b.get("yield", {}):
		o += float(b["yield"][k2])
	var r: float = (i / o) if o > 0.0 else 0.0
	_mr[bid] = r
	return r


func _combat_min_min(sym: String, z: int) -> float:
	# best (cheapest) kill-time for sym across zones <= z
	var best := INF
	var d: Dictionary = sm._cost_drop_rate.get(sym, {})
	for zz in d:
		if int(zz) <= z:
			var dpk := float(d[zz])
			if dpk > 0.0:
				best = minf(best, (1.0 / dpk) / KPH * 60.0)
	return best


func _solve(z: int) -> void:
	var m := {}
	var sc := {}
	for s in all_syms:
		m[String(s)] = INF
		sc[String(s)] = "-"
	# seed: gather + combat
	for s in all_syms:
		var ss := String(s)
		if float(gath_rate.get(ss, 0.0)) > 0.0:
			var g := 1.0 / float(gath_rate[ss])
			if g < float(m[ss]):
				m[ss] = g
				sc[ss] = "G"
		var ck := _combat_min_min(ss, z)
		if ck < float(m[ss]):
			m[ss] = ck
			sc[ss] = "K"
	var budget: float = sm._cost_afford_at(z)
	for _it in range(60):
		var changed := false
		for s in all_syms:
			var ss := String(s)
			var cur: float = float(m[ss])
			# recipes
			for rid in recipes_for.get(ss, []):
				var r: Dictionary = pm.recipes[rid]
				var o: float = maxf(0.0001, float((r["output"] as Dictionary).get(ss, 1)))
				var c: float = float(r.get("duration", 1.0)) / 60.0 / o
				var ok := true
				for isym in r.get("input", {}):
					var iv: float = float(m.get(String(isym), INF))
					if iv >= INF:
						ok = false
						break
					c += float(r["input"][isym]) / o * iv
				if ok and c < cur - 1e-9:
					cur = c
					m[ss] = c
					sc[ss] = "R:" + String(rid)
					changed = true
			# affordable buildings (conversion free, inputs still paid)
			for bid in bldgs_for.get(ss, []):
				var b: Dictionary = im.building_db[bid]
				if float((b.get("cost", {}) as Dictionary).get("credits", 0)) > budget:
					continue
				if _mass_ratio(bid) > MASS_RATIO_MAX:
					continue
				var o2: float = maxf(0.0001, float((b["yield"] as Dictionary).get(ss, 1)))
				var c2 := 0.0
				var ok2 := true
				for isym2 in b.get("input", {}):
					var iv2: float = float(m.get(String(isym2), INF))
					if iv2 >= INF:
						ok2 = false
						break
					c2 += float(b["input"][isym2]) / o2 * iv2
				if ok2 and c2 < cur - 1e-9:
					cur = c2
					m[ss] = c2
					sc[ss] = "B:" + String(bid)
					changed = true
		if not changed:
			break
	mpu[z] = m
	srcs[z] = sc


func _solve_all() -> void:
	for z in range(1, 13):
		_solve(z)


# root vector along the chosen path
func _rootvec(sym: String, z: int, acc: Dictionary, mult: float, depth: int) -> void:
	if depth > 24:
		return
	if sym in ROOTS:
		acc[sym] = float(acc.get(sym, 0.0)) + mult
		return
	var src := String((srcs[z] as Dictionary).get(sym, "-"))
	if src.begins_with("R:"):
		var r: Dictionary = pm.recipes[src.substr(2)]
		var o: float = maxf(0.0001, float((r["output"] as Dictionary).get(sym, 1)))
		for isym in r.get("input", {}):
			_rootvec(String(isym), z, acc, mult * float(r["input"][isym]) / o, depth + 1)
	elif src.begins_with("B:"):
		var b: Dictionary = im.building_db[src.substr(2)]
		var o2: float = maxf(0.0001, float((b["yield"] as Dictionary).get(sym, 1)))
		for isym2 in b.get("input", {}):
			_rootvec(String(isym2), z, acc, mult * float(b["input"][isym2]) / o2, depth + 1)
	# G / K / - : terminal, contributes no root


func _cost_minutes(cost: Dictionary, z: int) -> float:
	var t := 0.0
	for s in cost:
		if String(s) == "credits":
			continue
		var v: float = float((mpu[z] as Dictionary).get(String(s), INF))
		if v >= INF:
			print("      !! UNREACHABLE ", s, " at z", z)
			continue
		t += float(cost[s]) * v
	return t


# ── [1] depth census ───────────────────────────────────────────────────────
func _sec_depth_census() -> void:
	print("\n=== [1] DEPTH CENSUS (infra-forest depth, min-over-producers) ===")
	var by := {}
	for s in all_syms:
		var ss := String(s)
		var d: int = sm._cost_depth_of(ss)
		if not by.has(d):
			by[d] = []
		(by[d] as Array).append(ss)
	var ks: Array = by.keys()
	ks.sort()
	for d in ks:
		var arr: Array = by[d]
		arr.sort()
		print("  depth ", d, "  n=", arr.size())
		print("    ", ", ".join(arr))


# production depth: min over ALL producers (buildings AND recipes) of
# 1 + max(input depth). No producer at all -> 0.
var _pd := {}
var _pd_vis := {}
func _pdepth(sym: String) -> int:
	if _pd.has(sym):
		return int(_pd[sym])
	if _pd_vis.has(sym):
		return 0
	_pd_vis[sym] = true
	var best := -1
	for bid in bldgs_for.get(sym, []):
		var b: Dictionary = im.building_db[bid]
		var inp: Dictionary = b.get("input", {})
		if inp.is_empty():
			best = 0
			break
		var mx := 0
		for i in inp:
			mx = maxi(mx, _pdepth(String(i)))
		if best < 0 or (1 + mx) < best:
			best = 1 + mx
	if best != 0:
		for rid in recipes_for.get(sym, []):
			var r: Dictionary = pm.recipes[rid]
			var inp2: Dictionary = r.get("input", {})
			if inp2.is_empty():
				best = 0
				break
			var mx2 := 0
			for i2 in inp2:
				mx2 = maxi(mx2, _pdepth(String(i2)))
			if best < 0 or (1 + mx2) < best:
				best = 1 + mx2
	_pd_vis.erase(sym)
	if best < 0:
		best = 0
	_pd[sym] = best
	return best


func _sec_pdepth_census() -> void:
	print("\n=== [1b] PRODUCTION-DEPTH CENSUS (buildings AND recipes) ===")
	var by := {}
	for s in all_syms:
		var ss := String(s)
		var d: int = _pdepth(ss)
		if not by.has(d):
			by[d] = []
		(by[d] as Array).append(ss)
	var ks: Array = by.keys()
	ks.sort()
	for d in ks:
		var arr: Array = by[d]
		arr.sort()
		print("  pdepth ", d, "  n=", arr.size())
		print("    ", ", ".join(arr))


func _sec_srcdump() -> void:
	print("\n=== [1c] CHOSEN SOURCE + mpu AT Z10 (min-time path) ===")
	var ks: Array = all_syms.keys()
	ks.sort()
	for s in ks:
		var ss := String(s)
		var v: float = float((mpu[10] as Dictionary).get(ss, INF))
		if v >= INF:
			continue
		print("  ", _pad(ss, 24), _rpad(_f(v, 5), 12), "  d", _cost_d(ss), "/p", _pdepth(ss),
			"  ", (srcs[10] as Dictionary).get(ss, "-"))


func _cost_d(s: String) -> int:
	return sm._cost_depth_of(s)


# transitive units of `target` inside ONE unit of `sym`, following the RECIPE/
# BUILDING structure (min-over-producers by pdepth, not by time), so this is a
# pure bill-of-materials figure independent of the affordability model.
var _bom_cache := {}
func _bom(sym: String, target: String, depth: int = 0) -> float:
	if sym == target:
		return 1.0
	if depth > 16:
		return 0.0
	var key := sym + "|" + target
	if _bom_cache.has(key):
		return float(_bom_cache[key])
	_bom_cache[key] = 0.0
	var best := 0.0
	var prod := _bom_producer(sym)
	if prod != "":
		if prod.begins_with("B:"):
			var b: Dictionary = im.building_db[prod.substr(2)]
			var o: float = maxf(0.0001, float((b["yield"] as Dictionary).get(sym, 1)))
			for i in b.get("input", {}):
				best += float(b["input"][i]) / o * _bom(String(i), target, depth + 1)
		else:
			var r: Dictionary = pm.recipes[prod.substr(2)]
			var o2: float = maxf(0.0001, float((r["output"] as Dictionary).get(sym, 1)))
			for i2 in r.get("input", {}):
				best += float(r["input"][i2]) / o2 * _bom(String(i2), target, depth + 1)
	_bom_cache[key] = best
	return best


# the producer that DEFINES pdepth (shallowest); buildings preferred on ties
var _bomp := {}
func _bom_producer(sym: String) -> String:
	if _bomp.has(sym):
		return String(_bomp[sym])
	_bomp[sym] = ""
	var want: int = _pdepth(sym)
	if want <= 0:
		return ""
	for bid in bldgs_for.get(sym, []):
		var b: Dictionary = im.building_db[bid]
		var inp: Dictionary = b.get("input", {})
		if inp.is_empty():
			continue
		var mx := 0
		for i in inp:
			mx = maxi(mx, _pdepth(String(i)))
		if 1 + mx == want:
			_bomp[sym] = "B:" + String(bid)
			return String(_bomp[sym])
	for rid in recipes_for.get(sym, []):
		var r: Dictionary = pm.recipes[rid]
		var inp2: Dictionary = r.get("input", {})
		if inp2.is_empty():
			continue
		var mx2 := 0
		for i2 in inp2:
			mx2 = maxi(mx2, _pdepth(String(i2)))
		if 1 + mx2 == want:
			_bomp[sym] = "R:" + String(rid)
			return String(_bomp[sym])
	return ""


const CANDIDATES := [
	"Steel", "Ti", "Si", "C", "Cu", "Circuit", "Semiconductor", "Graphite", "Au",
	"Superalloy", "Chip", "AdvCircuit", "StructuralComponent", "Cr", "Ni", "Co",
	"StainlessSteel", "GalvanizedSteel", "AlWire", "CompositeWeave", "Hydraulics",
	"ReinforcedPlating", "CoBattery", "SuperconductingMagnet", "IrPlate", "Mesh",
	"NeutroniumPlate", "TargetingChip", "AICore", "ReactiveCore", "NanoSubstrate",
	"RegenPlating", "VoidLattice", "OmegaComposite", "StructuralLattice",
	"PrimordialMatrix", "BioReactorCore", "OsCore", "IonField", "TemporalModule",
	"VoidCrystal", "VoidEssence", "Neutronium", "Zn", "Sn", "Li", "Al", "Mg",
	"CapacitorShard", "AlMgAlloy", "PtCatalyst", "AgCatalyst", "NuclearFuel",
	"PdFuelCell", "Seal", "Fiber", "Resin", "Mn", "CryoEssence", "PurifiedCompound",
]


func _sec_candidates() -> void:
	print("\n=== [1d] DEEP-ITEM CANDIDATE TABLE ===")
	print("  sym                     pdep infd  bldg? rate/min  BOM: Steel   Fe    Cu    Si     C  |  rate*Steel")
	for s in CANDIDATES:
		var ss := String(s)
		var pr := _bom_producer(ss)
		var rate: float = float(sm._cost_infra_rate.get(ss, 0.0))
		var srate: float = float(sm._cost_serial_rate.get(ss, 0.0))
		var use: float = rate if rate > 0.0 else srate
		var bs := _bom(ss, "Steel")
		print("  ", _pad(ss, 22), _rpad(str(_pdepth(ss)), 4), _rpad(str(_cost_d(ss)), 5),
			_rpad(("B" if rate > 0.0 else "-"), 6), _rpad(_f(use, 2), 9),
			_rpad(_f(bs, 3), 10), _rpad(_f(_bom(ss, "Fe"), 2), 7),
			_rpad(_f(_bom(ss, "Cu"), 2), 7), _rpad(_f(_bom(ss, "Si"), 2), 7),
			_rpad(_f(_bom(ss, "C"), 2), 7), "  | ", _f(use * bs, 2), "   ", pr)


# Which band a composed line belongs to, reproducing the composer's own
# classification. F = foundation (bands 1 / 1b, the ones the rule governs),
# A = signature alloy, K = own-zone combat, X = combat-fed composite,
# U = no known source.
var _violations := 0
func _band_of(sym: String, z: int, md: Dictionary) -> String:
	var st := String(md.get("slot_type", ""))
	if sym == String(sm.TIER_ALLOY_BY_ZONE.get(z, "")) \
			and (st == "weapon" or st == "armor" or st == "shield"):
		return "A"
	var cls := String(sm._cost_class_at(sym, z))
	if cls == "COMBAT":
		return "K"
	if cls == "UNKNOWN":
		return "U"
	if sm._cost_is_combat_fed(sym):
		return "X"
	return "F"


# ── [2] per-module direct depth ────────────────────────────────────────────
func _sec_module_direct_depth() -> void:
	print("\n=== [2] MODULE DIRECT-DEPTH (composed costs) ===")
	print("  zone | module            | mindepth | lines (sym:depth:qty)")
	var per_zone_min := {}
	var per_zone_sum := {}
	var per_zone_n := {}
	var ids: Array = sm.modules.keys()
	ids.sort()
	for mid in ids:
		var md: Dictionary = sm.modules[mid]
		var z: int = int(md.get("zone", 0))
		if z < 1 or z > 10:
			continue
		if md.get("is_custom", false) or md.get("unique", false):
			continue
		var c: Dictionary = md.get("cost", {})
		if c.is_empty():
			continue
		var lines: Array = []
		var mind := 99
		for s in c:
			var ss := String(s)
			if ss == "credits":
				continue
			var d: int = sm._cost_rdepth_of(ss)
			var tag := ""
			if _band_of(ss, z, md) == "F":
				mind = mini(mind, d)
				per_zone_sum[z] = float(per_zone_sum.get(z, 0.0)) + float(d)
				per_zone_n[z] = int(per_zone_n.get(z, 0)) + 1
				var fl: int = int(sm.COST_MIN_DIRECT_DEPTH.get(z, 0))
				if d < fl:
					tag = "  <<<VIOLATION(floor " + str(fl) + ")"
					_violations += 1
			lines.append(ss + ":" + _band_of(ss, z, md) + str(d) + ":" + str(int(c[s])) + tag)
		if mind == 99:
			continue
		per_zone_min[z] = mini(int(per_zone_min.get(z, 99)), mind)
		print("  ", _rpad(str(z), 4), " | ", _pad(String(mid), 17), " | ", _rpad(str(mind), 8), " | ", ", ".join(lines))
	print("\n  FOUNDATION-BAND FLOOR VIOLATIONS: ", _violations)
	print("\n  per-zone min/mean DIRECT depth (FOUNDATION lines only):")
	for z in range(1, 11):
		var n: int = int(per_zone_n.get(z, 0))
		if n == 0:
			continue
		print("    Z", z, "  min=", per_zone_min.get(z, "-"), "  mean=",
			_f(float(per_zone_sum.get(z, 0.0)) / float(n)), "  lines=", n)


# ── [3] refit transitive root demand ───────────────────────────────────────
func _refit_ids(z: int) -> Array:
	var out: Array = []
	for mid in sm.modules:
		var md: Dictionary = sm.modules[mid]
		if int(md.get("zone", 0)) != z:
			continue
		if md.get("is_custom", false) or md.get("unique", false):
			continue
		if md.has("rarity"):
			continue
		if not COST_SLOTS.has(String(md.get("slot_type", ""))):
			continue
		if (md.get("cost", {}) as Dictionary).is_empty():
			continue
		out.append(String(mid))
	out.sort()
	return out


# hull slot counts for a tier-matched refit, matching prior audits
const REFIT_SLOTS := {
	1: 4, 2: 6, 3: 9, 4: 12, 5: 15, 6: 18, 7: 20, 8: 22, 9: 24, 10: 26,
}


func _sec_refit_roots() -> void:
	print("\n=== [3] TRANSITIVE ROOT DEMAND PER FULL TIER-MATCHED REFIT ===")
	print("  (one of every zone-N module; roots along the cheapest path at zone N)")
	for z in [3, 4, 5, 6, 7, 8, 9, 10]:
		var ids := _refit_ids(z)
		var acc := {}
		var mins := 0.0
		for mid in ids:
			var c: Dictionary = sm.modules[mid].get("cost", {})
			for s in c:
				if String(s) == "credits":
					continue
				_rootvec(String(s), z, acc, float(c[s]), 0)
			mins += _cost_minutes(c, z)
		var parts: Array = []
		for r in ROOTS:
			parts.append(r + "=" + str(int(round(float(acc.get(r, 0.0))))))
		print("  Z", z, "  modules=", ids.size(), "  active_min=", _f(mins, 1),
			"  (", _f(mins / 60.0, 2), " h)")
		print("        roots: ", "  ".join(parts))
	print("\n  TRANSITIVE INTERMEDIATE DEMAND PER REFIT (the owner's Steel question)")
	for z2 in range(3, 11):
		var ids2 := _refit_ids(z2)
		var agg2 := {}
		for mid2 in ids2:
			var c2: Dictionary = sm.modules[mid2].get("cost", {})
			for s2 in c2:
				agg2[String(s2)] = float(agg2.get(String(s2), 0.0)) + float(c2[s2])
		print("    Z", z2, "  Steel=", int(_transitive_units(agg2, "Steel", z2)),
			"  Superalloy=", int(_transitive_units(agg2, "Superalloy", z2)),
			"  AdvCircuit=", int(_transitive_units(agg2, "AdvCircuit", z2)),
			"  StructuralComponent=", int(_transitive_units(agg2, "StructuralComponent", z2)),
			"  Circuit=", int(_transitive_units(agg2, "Circuit", z2)))


# ── [4] the m030 bundle ────────────────────────────────────────────────────
func _sec_bundle() -> void:
	print("\n=== [4] m030fa/fb/f1 PRE-WARMASTER BUNDLE (2 z3_armor + 2 z3_shield + 3 z3_energy) ===")
	var bundle := {"z3_armor": 2, "z3_shield": 2, "z3_energy": 3}
	var tot := 0.0
	var agg := {}
	for mid in bundle:
		var c: Dictionary = sm.modules[mid].get("cost", {})
		var n: int = int(bundle[mid])
		var one := _cost_minutes(c, 3)
		tot += one * float(n)
		print("  ", _pad(String(mid), 12), " x", n, "  ", _f(one, 2), " min each  -> ", _f(one * n, 2))
		for s in c:
			if String(s) == "credits":
				continue
			agg[String(s)] = float(agg.get(String(s), 0.0)) + float(c[s]) * n
	print("  TOTAL ACTIVE TIME = ", _f(tot, 1), " min = ", _f(tot / 60.0, 3), " h   (target <= 1.5 h)")
	print("  per-material breakdown (qty, min/unit, min total, src):")
	var ks: Array = agg.keys()
	ks.sort()
	for s in ks:
		var q: float = agg[s]
		var u: float = float((mpu[3] as Dictionary).get(String(s), INF))
		print("    ", _pad(String(s), 22), _rpad(str(int(round(q))), 8),
			_rpad(_f(u, 4), 10), _rpad(_f(q * u, 1), 9), "  ", (srcs[3] as Dictionary).get(String(s), "-"))
	# transitive roots
	var acc := {}
	for s2 in agg:
		_rootvec(String(s2), 3, acc, float(agg[s2]), 0)
	var parts: Array = []
	for r in ROOTS:
		parts.append(r + "=" + str(int(round(float(acc.get(r, 0.0))))))
	print("  bundle roots: ", "  ".join(parts))
	# Steel expansion sanity
	print("  Steel transitive units in bundle: ", _f(_transitive_units(agg, "Steel", 3), 1))


func _transitive_units(cost: Dictionary, target: String, z: int) -> float:
	var acc := {}
	for s in cost:
		if String(s) == "credits":
			continue
		_units_of(String(s), target, z, acc, float(cost[s]), 0)
	return float(acc.get("T", 0.0))


func _units_of(sym: String, target: String, z: int, acc: Dictionary, mult: float, depth: int) -> void:
	if depth > 24:
		return
	if sym == target:
		acc["T"] = float(acc.get("T", 0.0)) + mult
		return
	var src := String((srcs[z] as Dictionary).get(sym, "-"))
	if src.begins_with("R:"):
		var r: Dictionary = pm.recipes[src.substr(2)]
		var o: float = maxf(0.0001, float((r["output"] as Dictionary).get(sym, 1)))
		for isym in r.get("input", {}):
			_units_of(String(isym), target, z, acc, mult * float(r["input"][isym]) / o, depth + 1)
	elif src.begins_with("B:"):
		var b: Dictionary = im.building_db[src.substr(2)]
		var o2: float = maxf(0.0001, float((b["yield"] as Dictionary).get(sym, 1)))
		for isym2 in b.get("input", {}):
			_units_of(String(isym2), target, z, acc, mult * float(b["input"][isym2]) / o2, depth + 1)


# ── [5] every mandatory craft mission in the guided chain ──────────────────
func _sec_guided_chain() -> void:
	print("\n=== [5] EVERY GUIDED-CHAIN CRAFT MISSION, TRANSITIVE ===")
	var mm = GameState.mission_manager
	if mm == null:
		print("  (no mission manager)")
		return
	for mid in mm.missions:
		var d: Dictionary = mm.missions[mid]
		if String(d.get("type", "")) != "craft":
			continue
		var tgt := String(d.get("target", ""))
		var amt: int = int(d.get("target_qty", 1))
		if not sm.modules.has(tgt):
			continue
		var md: Dictionary = sm.modules[tgt]
		var z: int = maxi(1, int(md.get("zone", 1)))
		var one := _cost_minutes(md.get("cost", {}), z)
		var tot := one * float(amt)
		var flag := "" if tot <= 90.0 else "   <<< OVER 1.5 h"
		print("  ", _pad(String(mid), 10), _pad(tgt, 14), " x", _rpad(str(amt), 3),
			"  z", z, "  ", _rpad(_f(tot, 1), 9), " min = ", _f(tot / 60.0, 2), " h", flag)


# ── [6] breadth ────────────────────────────────────────────────────────────
func _sec_breadth() -> void:
	print("\n=== [6] BREADTH: distinct buildings a refit needs, new vs all earlier ===")
	var seen := {}
	for z in range(1, 11):
		var ids := _refit_ids(z)
		var need := {}
		for mid in ids:
			var c: Dictionary = sm.modules[mid].get("cost", {})
			for s in c:
				if String(s) == "credits":
					continue
				_collect_bldgs(String(s), z, need, 0)
		var newb: Array = []
		for b in need:
			if not seen.has(b):
				newb.append(String(b))
		newb.sort()
		for b2 in need:
			seen[b2] = true
		print("  Z", _rpad(str(z), 2), "  distinct=", _rpad(str(need.size()), 3),
			"  new=", _rpad(str(newb.size()), 3), "  ", ", ".join(newb))


func _collect_bldgs(sym: String, z: int, acc: Dictionary, depth: int) -> void:
	if depth > 24:
		return
	var src := String((srcs[z] as Dictionary).get(sym, "-"))
	if src.begins_with("B:"):
		acc[src.substr(2)] = true
		var b: Dictionary = im.building_db[src.substr(2)]
		for isym2 in b.get("input", {}):
			_collect_bldgs(String(isym2), z, acc, depth + 1)
	elif src.begins_with("R:"):
		var r: Dictionary = pm.recipes[src.substr(2)]
		for isym in r.get("input", {}):
			_collect_bldgs(String(isym), z, acc, depth + 1)


# ── [7] buildable on unlock ────────────────────────────────────────────────
func _sec_buildable() -> void:
	print("\n=== [7] BUILDABLE-ON-UNLOCK CHECK ===")
	var bad := 0
	for z in range(3, 11):
		var ids := _refit_ids(z)
		for mid in ids:
			var c: Dictionary = sm.modules[mid].get("cost", {})
			for s in c:
				var ss := String(s)
				if ss == "credits":
					continue
				var v: float = float((mpu[z] as Dictionary).get(ss, INF))
				if v >= INF:
					print("  UNREACHABLE at Z", z, ": ", mid, " needs ", ss)
					bad += 1
					continue
				# research gate on the chosen recipe
				var src := String((srcs[z] as Dictionary).get(ss, "-"))
				if src.begins_with("R:"):
					var r: Dictionary = pm.recipes[src.substr(2)]
					var rr := String(r.get("research_req", ""))
					var lv: int = int(r.get("level_req", 1))
					var gz := _gate_zone(rr)
					if gz > z:
						print("  GATE VIOLATION Z", z, ": ", mid, " -> ", ss,
							" via ", src, " needs research ", rr, " (zone ", gz, ")")
						bad += 1
					if lv > _expected_level(z):
						print("  LEVEL RISK Z", z, ": ", mid, " -> ", ss, " via ", src,
							" level_req ", lv, " vs expected ", _expected_level(z))
	print("  violations: ", bad)


func _gate_zone(rr: String) -> int:
	if rr == "":
		return 0
	if rr.begins_with("zone_") and rr.ends_with("_access"):
		return int(rr.substr(5, rr.length() - 12))
	return 0


func _expected_level(z: int) -> int:
	return mini(99, 10 + z * 8)
