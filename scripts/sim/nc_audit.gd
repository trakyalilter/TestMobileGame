extends Node
# ============================================================================
# NC_AUDIT — the module-cost-curve audit. Runs identically before and after the
# new curve, so every number in the report is a measured delta, not an estimate.
#
#  [A] reference throughput per material  (infra: units/min PER BUILDING at a
#      neutral reference; serial: units/min of the best processing recipe)
#  [B] classification + which zone(s) a combat-only material drops in
#  [C] per-module effective cost, band-tagged, via get_effective_module_cost
#  [D] per-zone tier-matched REFIT: building-minutes / material, buildings
#      needed for a DWELL_H stay, serial minutes, alloy chain minutes
#  [E] dependency forest -> root chains, NEW chain per zone
#  [F] backward combat debt per alloy and per refit
#  [G] monotonicity series (armor / weapon / shield, all zones)
#  [H] channel credit + material parity
#  [I] buildability on unlock: research gate + processing level_req
#
#   <godot> --headless --path <root> res://scenes/nc_audit.tscn
# ============================================================================

const DWELL_H := 3.0            # design assumption: hours a player spends in a zone
const REF_BUILDINGS := 10       # "a real factory line" for the buildings-needed math

# MEASURED per-building output, units/min, from scripts/sim/infra_yield_measure.gd
# run at 10 buildings of the single best producer with inputs guaranteed and
# energy at 100% — i.e. it already contains _eng_scale, the skill yield multiplier,
# the ore throttle and mastery. Throttle 1.0, overclock OFF (an unlocked overclock
# multiplies all of these by up to 2.0 and quadruples the input draw).
# The neutral rate the COST CURVE uses (qty/interval*60) is deliberately different:
# it must not move when a player levels Engineering.
const MEASURED := {
	"Steel": 58.54, "Ti": 35.12, "Superalloy": 23.41, "AdvCircuit": 28.10,
	"Chip": 18.73, "Circuit": 23.40, "Si": 39.81, "Fe": 117.09, "C": 108.0,
	"Cu": 18.0, "Au": 35.12, "Mn": 11.70, "Ir": 4.50, "Os": 1.35,
	"VoidCrystal": 9.0, "VoidEssence": 11.70, "ChronoCore": 2.70,
	"Neutronium": 3.60, "OmegaComposite": 1.35, "PrimordialMatrix": 0.90,
	"BioReactorCore": 1.80, "Graphite": 14.40, "W": 18.0, "U": 18.0,
	"StructuralComponent": 23.41, "Ni": 30.60, "Cr": 23.40, "Co": 27.0,
	"Li": 18.0, "Zn": 45.0, "Sn": 36.0, "Semiconductor": 35.12,
	"Dirt": 180.0, "Water": 180.0, "Wood": 180.0,
}

var infra_out := {}     # sym -> [bid]
var proc_out := {}      # sym -> [rid]
var gath_out := {}      # sym -> [aid]
var combat_z := {}      # sym -> [zone,...]

var infra_rate := {}    # sym -> units/min for ONE building (neutral reference)
var serial_rate := {}   # sym -> units/min of the best single processing recipe
var chain_secs := {}    # sym -> transitive processing seconds for 1 unit

var sm
var pm
var im
var gm
var cm


func _pad(s: String, n: int) -> String:
	var o := s
	while o.length() < n: o += " "
	return o

func _lp(s: String, n: int) -> String:
	var o := s
	while o.length() < n: o = " " + o
	return o


func _classify(sym: String) -> String:
	if infra_out.has(sym): return "INFRA"
	if gath_out.has(sym): return "GATHER"
	if proc_out.has(sym): return "PROCESS"
	if combat_z.has(sym): return "COMBAT"
	return "???"

func _auto(sym: String) -> bool:
	return _classify(sym) in ["INFRA", "GATHER", "PROCESS"]


# ── index every producer ────────────────────────────────────────────────────
func _index() -> void:
	for bid in im.building_db:
		var d: Dictionary = im.building_db[bid]
		for sym in d.get("yield", {}):
			var s := String(sym)
			if not infra_out.has(s): infra_out[s] = []
			infra_out[s].append(String(bid))
			# neutral reference rate for ONE building: qty / interval * 60
			var r: float = float(d["yield"][sym]) / max(0.001, float(d.get("interval", 1.0))) * 60.0
			infra_rate[s] = max(float(infra_rate.get(s, 0.0)), r)
	for rid in pm.recipes:
		var r2: Dictionary = pm.recipes[rid]
		for sym in r2.get("output", {}):
			var s2 := String(sym)
			if not proc_out.has(s2): proc_out[s2] = []
			proc_out[s2].append(String(rid))
			var rate: float = float(r2["output"][sym]) / max(0.001, float(r2.get("duration", 1.0))) * 60.0
			serial_rate[s2] = max(float(serial_rate.get(s2, 0.0)), rate)
	for aid in gm.actions:
		var a: Dictionary = gm.actions[aid]
		for row in a.get("loot_table", []):
			var s3 := String(row[0])
			if not gath_out.has(s3): gath_out[s3] = []
			gath_out[s3].append(String(aid))
			var avg: float = (float(row[2]) + float(row[3])) * 0.5 * float(row[1])
			var gr: float = avg / max(0.001, float(a.get("duration", 3.0))) * 60.0
			serial_rate[s3] = max(float(serial_rate.get(s3, 0.0)), gr)
	for zid in cm.zones:
		var z: Dictionary = cm.zones[zid]
		var zd: int = int(z.get("difficulty", 0))
		var elist: Array = z.get("enemies", []).duplicate()
		if z.has("boss"): elist.append(z["boss"])
		for eid in elist:
			var e: Dictionary = cm.enemy_db.get(String(eid), {})
			for row in e.get("loot", []):
				var s4 := String(row[0])
				if not combat_z.has(s4): combat_z[s4] = []
				if not (zd in combat_z[s4]): combat_z[s4].append(zd)
			for row in e.get("rare_loot", []):
				var s5 := String(row[0])
				if not combat_z.has(s5): combat_z[s5] = []
				if not (zd in combat_z[s5]): combat_z[s5].append(zd)
	for s in combat_z:
		combat_z[s].sort()


# transitive SERIAL processing seconds to make 1 unit of sym (alloy ladder depth).
# An INFRA material costs the player ZERO serial time — a building makes it in
# parallel while they do something else. Recursing into it would count factory
# output as active-task time, which is the whole distinction the cost bands rest
# on. (Measured: without this stop the Z10 AeonAlloy reads 2076 s/unit instead of
# its true 136 s of chained rung duration.)
func _chain_secs(sym: String, depth: int = 0) -> float:
	if chain_secs.has(sym): return float(chain_secs[sym])
	if depth > 14: return 0.0
	if _classify(sym) == "INFRA": return 0.0
	if not proc_out.has(sym): return 0.0
	var best := 1.0e18
	for rid in proc_out[sym]:
		var r: Dictionary = pm.recipes[rid]
		var outq: float = max(1.0, float(r.get("output", {}).get(sym, 1)))
		var t: float = float(r.get("duration", 1.0)) / outq
		for isym in r.get("input", {}):
			var ratio: float = float(r["input"][isym]) / outq
			t += ratio * _chain_secs(String(isym), depth + 1)
		best = min(best, t)
	chain_secs[sym] = best
	return best


# transitive BACKWARD combat-only units per 1 unit of sym, relative to zone z.
func _back_combat(sym: String, z: int, depth: int = 0) -> float:
	if depth > 14: return 0.0
	var cls := _classify(sym)
	if cls == "COMBAT":
		var zs: Array = combat_z.get(sym, [])
		# own-zone (or later) drops cost the player nothing extra; only reaching
		# BACK into a zone they have left is serial, unautomatable grind.
		for zz in zs:
			if int(zz) >= z: return 0.0
		return 1.0
	var best := 1.0e18
	# The BUILDING path. A material a building yields is obtained through that
	# building's inputs, not through a hand recipe that happens to share the name.
	if infra_out.has(sym):
		for bid in infra_out[sym]:
			var d: Dictionary = im.building_db[String(bid)]
			var oq: float = max(0.0001, float(d.get("yield", {}).get(sym, 1.0)))
			var acc0 := 0.0
			for isym in d.get("input", {}):
				acc0 += float(d["input"][isym]) / oq * _back_combat(String(isym), z, depth + 1)
			best = min(best, acc0)
	if proc_out.has(sym):
		for rid in proc_out[sym]:
			var r: Dictionary = pm.recipes[rid]
			var outq: float = max(1.0, float(r.get("output", {}).get(sym, 1)))
			var acc := 0.0
			for isym in r.get("input", {}):
				acc += float(r["input"][isym]) / outq * _back_combat(String(isym), z, depth + 1)
			best = min(best, acc)
	return 0.0 if best > 1.0e17 else best


# root gathered/primitive chains a material depends on
var _root_cache := {}
func _roots(sym: String, depth: int = 0) -> Array:
	if _root_cache.has(sym): return _root_cache[sym]
	if depth > 12: return []
	var out := {}
	var cls := _classify(sym)
	if cls == "GATHER" or cls == "COMBAT" or cls == "???":
		out[sym] = true
		_root_cache[sym] = out.keys()
		return out.keys()
	_root_cache[sym] = []          # cycle guard
	if cls == "INFRA":
		var bid: String = String(infra_out[sym][0])
		var d: Dictionary = im.building_db[bid]
		if d.get("input", {}).is_empty():
			out[sym] = true          # primitive extractor: it IS a root chain
		else:
			for isym in d.get("input", {}):
				for r in _roots(String(isym), depth + 1): out[r] = true
	elif cls == "PROCESS":
		var rid: String = String(proc_out[sym][0])
		var r2: Dictionary = pm.recipes[rid]
		if r2.get("input", {}).is_empty():
			out[sym] = true
		else:
			for isym in r2.get("input", {}):
				for r in _roots(String(isym), depth + 1): out[r] = true
	var res: Array = out.keys()
	res.sort()
	_root_cache[sym] = res
	return res


# deepest zone_N_access in a tech's transitive parent chain (0 == none)
func _tech_gate(tech: String, depth: int = 0) -> int:
	if tech == "" or depth > 20: return 0
	var rm = GameState.research_manager
	if not rm or not rm.tech_tree.has(tech): return 0
	var worst := 0
	if tech.begins_with("zone_") and tech.ends_with("_access"):
		worst = int(tech.substr(5, tech.length() - 12))
	var par = rm.tech_tree[tech].get("parent", "")
	if par is Array:
		for p in par: worst = max(worst, _tech_gate(str(p), depth + 1))
	elif par != null and str(par) != "":
		worst = max(worst, _tech_gate(str(par), depth + 1))
	return worst

# lowest zone gate across every source (building / recipe / gather) of a material
var _gate_cache := {}
func _mat_gate_zone(sym: String) -> int:
	if _gate_cache.has(sym): return int(_gate_cache[sym])
	_gate_cache[sym] = 0
	var best := 999
	for bid in infra_out.get(sym, []):
		best = min(best, _tech_gate(str(im.building_db[String(bid)].get("research_req", ""))))
	for rid in proc_out.get(sym, []):
		var rr := String(rid).rstrip("*")
		if pm.recipes.has(rr):
			best = min(best, _tech_gate(str(pm.recipes[rr].get("research_req", ""))))
	for aid in gath_out.get(sym, []):
		best = min(best, _tech_gate(str(gm.actions[String(aid)].get("research_req", ""))))
	for zz in combat_z.get(sym, []):
		best = min(best, int(zz))
	if best > 900: best = 0
	_gate_cache[sym] = best
	return best


func _hull_tier_slots(t: int) -> Dictionary:
	for hid in sm.hulls:
		if int(sm.hulls[hid].get("tier", 0)) == t:
			var c := {}
			for s in sm.hulls[hid].get("slots", []):
				c[String(s)] = int(c.get(String(s), 0)) + 1
			return c
	return {}


func _mods_for_zone(z: int) -> Array:
	var out := []
	for mid in sm.modules:
		var m: Dictionary = sm.modules[mid]
		if m.get("is_custom", false) or m.get("unique", false): continue
		if String(m.get("slot_type", "")) in ["gem", "gem_synth", "relic"]: continue
		if int(m.get("zone", 0)) != z: continue
		if m.has("power_tier"): continue     # exotics live outside the zone ladder
		if not m.has("cost"): continue
		if (m["cost"] as Dictionary).is_empty(): continue
		out.append(String(mid))
	out.sort()
	return out


func _ready() -> void:
	sm = GameState.shipyard_manager
	pm = GameState.processing_manager
	im = GameState.infrastructure_manager
	gm = GameState.gathering_manager
	cm = GameState.combat_manager
	_index()

	print("[NC] tier_gate_enabled = %s" % str(GameState.game_settings.get("tier_gate_enabled", "MISSING")))
	print("")

	# ── [A] reference throughput ────────────────────────────────────────────
	print("=== [A] REFERENCE THROUGHPUT (neutral: qty/interval*60, no player mults) ===")
	print("    material              class     infra/min/bld   serial/min   chain_s/unit")
	var mats := {}
	for mid in sm.modules:
		var m: Dictionary = sm.modules[mid]
		if not m.has("cost"): continue
		for k in (m["cost"] as Dictionary):
			if String(k) != "credits": mats[String(k)] = true
	var mk: Array = mats.keys(); mk.sort()
	for s in mk:
		var cs := _chain_secs(String(s))
		print("    %s%s%s%s%s" % [_pad(String(s), 22), _pad(_classify(String(s)), 10),
			_lp("%.2f" % float(infra_rate.get(s, 0.0)), 13),
			_lp("%.2f" % float(serial_rate.get(s, 0.0)), 13),
			_lp("%.0f" % cs, 15)])
	print("")

	# ── [B] combat materials, drop zones ────────────────────────────────────
	print("=== [B] COMBAT-ONLY MATERIALS USED IN MODULE COSTS -> drop zones ===")
	for s in mk:
		if _classify(String(s)) == "COMBAT":
			print("    %s %s" % [_pad(String(s), 22), str(combat_z.get(s, []))])
	print("")

	# ── [C] per-module band-tagged effective cost ───────────────────────────
	print("=== [C] EFFECTIVE COST, BAND-TAGGED  (SIG=own-zone alloy, OWNC=own-zone combat,")
	print("        BACK=earlier-zone combat, F=automatable foundation) ===")
	for z in range(1, 13):
		var ids := _mods_for_zone(z)
		if ids.is_empty(): continue
		for mid in ids:
			var m: Dictionary = sm.modules[mid]
			var eff: Dictionary = sm.get_effective_module_cost(m)
			var alloy := String(sm.TIER_ALLOY_BY_ZONE.get(z, ""))
			var parts := []
			var keys: Array = eff.keys(); keys.sort()
			for k in keys:
				var ks := String(k)
				if ks == "credits": continue
				var tag := "F"
				if ks == alloy: tag = "SIG"
				elif _classify(ks) == "COMBAT":
					tag = "BACK"
					for zz in combat_z.get(ks, []):
						if int(zz) >= z: tag = "OWNC"
				elif sm._cost_is_combat_fed(ks): tag = "COMP"
				elif _classify(ks) != "INFRA": tag = "SER"
				parts.append("%s %s[%s]" % [ks, str(eff[k]), tag])
			print("    %s %s cr=%-10s %s" % [_pad(mid, 16), _pad(String(m.get("slot_type","")), 8),
				str(int(eff.get("credits", 0))), ", ".join(parts)])
	print("")

	# ── [G] monotonicity ────────────────────────────────────────────────────
	print("=== [G] MONOTONICITY: per-zone series (charged units) ===")
	for slot in ["armor", "kinetic", "energy", "missile", "shield"]:
		var prev_f := 0.0
		var line := "    %s " % _pad(slot, 9)
		for z in range(1, 11):
			var mid := "z%d_%s" % [z, slot]
			if not sm.modules.has(mid): continue
			var eff: Dictionary = sm.get_effective_module_cost(sm.modules[mid])
			var alloy := String(sm.TIER_ALLOY_BY_ZONE.get(z, ""))
			var fmin := 0.0     # foundation cost in building-minutes
			var smin := 0.0     # serial minutes
			var sig := 0.0
			var ownc := 0.0
			var back := 0.0
			for k in eff:
				var ks := String(k)
				if ks == "credits": continue
				var q := float(eff[k])
				if ks == alloy: sig += q; continue
				if _classify(ks) == "COMBAT":
					var own := false
					for zz in combat_z.get(ks, []):
						if int(zz) >= z: own = true
					if own: ownc += q
					else: back += q
					continue
				if float(infra_rate.get(ks, 0.0)) > 0.0:
					fmin += q / float(infra_rate[ks])
				elif float(serial_rate.get(ks, 0.0)) > 0.0:
					smin += q / float(serial_rate[ks])
			var d := 0.0 if prev_f <= 0.0 else fmin / prev_f
			prev_f = fmin
			print("      z%-3d %-9s Fmin=%-10.1f Smin=%-8.1f SIG=%-6.0f OWNC=%-6.0f BACK=%-6.0f  x_prev=%.2f" % [
				z, slot, fmin, smin, sig, ownc, back, d])
		if line != "":
			pass
	print("")

	# ── [D] refit: building-minutes, buildings needed, serial + alloy time ──
	print("=== [D] TIER-MATCHED REFIT PER ZONE (hull tier == zone) ===")
	print("    DWELL_H=%.1f  REF_BUILDINGS=%d" % [DWELL_H, REF_BUILDINGS])
	for z in range(1, 11):
		var slots := _hull_tier_slots(z)
		if slots.is_empty(): continue
		var need := {}       # sym -> units
		var cr := 0.0
		for st in slots:
			var count: int = int(slots[st])
			var pick := ""
			if st == "weapon": pick = "z%d_kinetic" % z
			else: pick = "z%d_%s" % [z, st]
			if not sm.modules.has(pick): continue
			var eff: Dictionary = sm.get_effective_module_cost(sm.modules[pick])
			for k in eff:
				var ks := String(k)
				if ks == "credits": cr += float(eff[k]) * count
				else: need[ks] = float(need.get(ks, 0.0)) + float(eff[k]) * count
		var tot_bmin := 0.0
		var tot_meas := 0.0
		var tot_smin := 0.0
		var tot_bld := 0.0
		var lines := []
		var nk: Array = need.keys(); nk.sort()
		for s in nk:
			var q: float = float(need[s])
			var cls := _classify(String(s))
			if cls == "COMBAT":
				var own := false
				for zz in combat_z.get(s, []):
					if int(zz) >= z: own = true
				lines.append("      %s %-9.0f %s" % [_pad(String(s), 20), q, "OWN-ZONE COMBAT" if own else "*** BACKWARD COMBAT ***"])
				continue
			if float(infra_rate.get(s, 0.0)) > 0.0:
				var bmin: float = q / float(infra_rate[s])
				var blds: float = bmin / (DWELL_H * 60.0)
				tot_bmin += bmin; tot_bld += blds
				var mr: float = float(MEASURED.get(s, 0.0))
				var mb: float = (q / mr) / (DWELL_H * 60.0) if mr > 0.0 else -1.0
				tot_meas += (mb if mb > 0.0 else blds)
				lines.append("      %s %-9.0f INFRA  %8.1f bld-min -> %6.2f buildings (neutral) | %6.2f buildings (MEASURED %.2f/min)" % [
					_pad(String(s), 20), q, bmin, blds, mb, mr])
			elif float(serial_rate.get(s, 0.0)) > 0.0:
				var smin2: float = q / float(serial_rate[s])
				var chs: float = _chain_secs(String(s)) * q / 60.0
				tot_smin += chs
				lines.append("      %s %-9.0f SERIAL %8.1f min (top rung)  chain %8.1f min" % [
					_pad(String(s), 20), q, smin2, chs])
			else:
				lines.append("      %s %-9.0f ???" % [_pad(String(s), 20), q])
		print("  ZONE %d  hull slots %s   credits=%.0f" % [z, str(slots), cr])
		for l in lines: print(l)
		print("    TOTAL infra %.0f bld-min | buildings over %.0fh: %.1f neutral / %.1f MEASURED | serial chain %.1f min (%.2f h)" % [
			tot_bmin, DWELL_H, tot_bld, tot_meas, tot_smin, tot_smin / 60.0])
	print("")

	# ── [E] dependency forest / breadth ─────────────────────────────────────
	print("=== [E] BREADTH: root chains per zone module set, and what is NEW ===")
	var seen := {}
	var seen_auto := {}
	for z in range(1, 11):
		var ids := _mods_for_zone(z)
		var roots := {}
		for mid in ids:
			var eff: Dictionary = sm.get_effective_module_cost(sm.modules[mid])
			for k in eff:
				if String(k) == "credits": continue
				if not _auto(String(k)): continue
				for r in _roots(String(k)): roots[r] = true
		var rk: Array = roots.keys(); rk.sort()
		var fresh := []
		var fresh_auto := []
		for r in rk:
			if not seen.has(r): fresh.append(r)
			if _auto(String(r)) and not seen_auto.has(r): fresh_auto.append(r)
		for r in rk:
			seen[r] = true
			if _auto(String(r)): seen_auto[r] = true
		print("  Z%-3d roots(%d): %s" % [z, rk.size(), ", ".join(rk)])
		print("       NEW root       : %s" % ("(none)" if fresh.is_empty() else ", ".join(fresh)))
		if fresh_auto.is_empty():
			print("       NEW AUTOMATABLE PRODUCTION CHAIN: *** NONE — DESIGN HOLE ***")
		else:
			print("       NEW AUTOMATABLE PRODUCTION CHAIN: %s" % ", ".join(fresh_auto))
	print("")

	# ── [F] backward combat debt ────────────────────────────────────────────
	print("=== [F] BACKWARD COMBAT DEBT ===")
	print("    per 1 unit of each signature alloy (units of EARLIER-zone combat-only loot):")
	for z in sm.TIER_ALLOY_BY_ZONE:
		var al := String(sm.TIER_ALLOY_BY_ZONE[z])
		print("      z%-3d %s%.2f" % [int(z), _pad(al, 20), _back_combat(al, int(z))])
	print("    per FULL TIER-MATCHED REFIT (top contributors listed):")
	for z in [5, 7, 10]:
		var slots := _hull_tier_slots(z)
		var debt := 0.0
		var direct := 0.0
		var alloy_debt := 0.0
		var by_mat := {}
		var alloy_z := String(sm.TIER_ALLOY_BY_ZONE.get(z, ""))
		for st in slots:
			var count: int = int(slots[st])
			var pick := ("z%d_kinetic" % z) if st == "weapon" else ("z%d_%s" % [z, st])
			if not sm.modules.has(pick): continue
			var eff: Dictionary = sm.get_effective_module_cost(sm.modules[pick])
			for k in eff:
				var ks := String(k)
				if ks == "credits": continue
				var q := float(eff[k]) * count
				if _classify(ks) == "COMBAT":
					var own := false
					for zz in combat_z.get(ks, []):
						if int(zz) >= z: own = true
					if not own:
						direct += q
						by_mat[ks] = float(by_mat.get(ks, 0.0)) + q
				else:
					var dd: float = q * _back_combat(ks, z)
					debt += dd
					if ks == alloy_z: alloy_debt += dd
					if dd > 0.0: by_mat[ks] = float(by_mat.get(ks, 0.0)) + dd
		var mk2: Array = by_mat.keys()
		mk2.sort_custom(func(a, b): return float(by_mat[a]) > float(by_mat[b]))
		var top := []
		for i in range(min(5, mk2.size())):
			top.append("%s %.0f" % [String(mk2[i]), float(by_mat[mk2[i]])])
		print("      Z%-3d transitive=%.0f (of which via the signature alloy=%.0f)  direct-backward=%.0f  TOTAL=%.0f" % [
			z, debt, alloy_debt, direct, debt + direct])
		print("           top: %s" % ", ".join(top))
	print("")

	# ── [H] channel parity ──────────────────────────────────────────────────
	print("=== [H] CHANNEL PARITY (kinetic / energy / missile) ===")
	for z in range(1, 11):
		var k: Dictionary = sm.get_effective_module_cost(sm.modules.get("z%d_kinetic" % z, {}))
		var e: Dictionary = sm.get_effective_module_cost(sm.modules.get("z%d_energy" % z, {}))
		var x: Dictionary = sm.get_effective_module_cost(sm.modules.get("z%d_missile" % z, {}))
		var ck := float(k.get("credits", 0)); var ce := float(e.get("credits", 0)); var cx := float(x.get("credits", 0))
		# foundation cost in building-minutes as the neutral material yardstick
		var mm := []
		for d in [k, e, x]:
			var t := 0.0
			for kk in d:
				var ks := String(kk)
				if ks == "credits": continue
				if float(infra_rate.get(ks, 0.0)) > 0.0: t += float(d[kk]) / float(infra_rate[ks])
				elif float(serial_rate.get(ks, 0.0)) > 0.0: t += float(d[kk]) / float(serial_rate[ks])
			mm.append(t)
		print("    z%-3d cr k=%-10.0f e=%-10.0f x=%-10.0f | e/k=%.3f x/k=%.3f || mat-min k=%.0f e=%.0f x=%.0f (e/k=%.2f x/k=%.2f)" % [
			z, ck, ce, cx, ce / max(1.0, ck), cx / max(1.0, ck), mm[0], mm[1], mm[2],
			mm[1] / max(0.01, mm[0]), mm[2] / max(0.01, mm[0])])
	print("")

	# ── [I] buildability on unlock ──────────────────────────────────────────
	print("=== [I] BUILDABILITY ON UNLOCK: every module material must have a reachable source ===")
	var rm = GameState.research_manager
	for z in range(2, 13):
		var ids := _mods_for_zone(z)
		for mid in ids:
			var m: Dictionary = sm.modules[mid]
			var eff: Dictionary = sm.get_effective_module_cost(m)
			var bad := []
			for k in eff:
				var ks := String(k)
				if ks == "credits": continue
				if _classify(ks) == "???":
					bad.append("%s NO SOURCE" % ks)
					continue
				# processing level requirement of the cheapest producing recipe
				if proc_out.has(ks):
					var lo := 999
					for rid in proc_out[ks]:
						lo = min(lo, int(pm.recipes[rid].get("level_req", 1)))
					if lo > 100: bad.append("%s lvl%d" % [ks, lo])
			if not bad.is_empty():
				print("    %s : %s" % [_pad(mid, 16), ", ".join(bad)])
	print("    (recipe level_req ladder per zone alloy:)")
	for z in sm.TIER_ALLOY_BY_ZONE:
		var al := String(sm.TIER_ALLOY_BY_ZONE[z])
		var lo2 := 999
		for rid in proc_out.get(al, []):
			lo2 = min(lo2, int(pm.recipes[rid].get("level_req", 1)))
		print("      z%-3d %s lvl_req=%d" % [int(z), _pad(al, 20), lo2])
	print("")

	# ── [J] band-2b supply + band-1 anchor reachability ────────────────────
	print("=== [J] ZONE SIGNATURE DROP SUPPLY (regular enemies only, no boss) ===")
	for z in range(2, 11):
		var drop := String(sm.COST_ZONE_DROP.get(z, ""))
		var srcs := []
		var avg_per_kill := 0.0
		var n_reg := 0
		for zid in cm.zones:
			var zz: Dictionary = cm.zones[zid]
			if int(zz.get("difficulty", 0)) != z: continue
			for eid in zz.get("enemies", []):
				n_reg += 1
				var e: Dictionary = cm.enemy_db.get(String(eid), {})
				for row in e.get("loot", []):
					if String(row[0]) == drop:
						srcs.append("%s %d-%d" % [String(eid), int(row[1]), int(row[2])])
						avg_per_kill += (float(row[1]) + float(row[2])) * 0.5
		var per_kill: float = avg_per_kill / maxf(1.0, float(n_reg))
		print("  Z%-3d %s : %d/%d regular enemies drop it, avg %.2f/kill  [%s]" % [
			z, _pad(drop, 20), srcs.size(), n_reg, per_kill, ", ".join(srcs)])
	print("")
	print("=== [J2] BAND-1 ZONE ANCHOR REACHABILITY ===")
	for z in sm.COST_ZONE_ANCHOR:
		var an := String(sm.COST_ZONE_ANCHOR[z])
		var blds: Array = infra_out.get(an, [])
		var info := []
		for b in blds:
			var d: Dictionary = im.building_db[String(b)]
			var req := String(d.get("research_req", ""))
			info.append("%s (req=%s -> %s, cost=%s)" % [
				String(b), req if req != "" else "-", _tech_gate(req), str(d.get("cost", {}))])
		print("  Z%-3d anchor %s  %s" % [int(z), _pad(an, 20), " | ".join(info)])
	print("")
	print("=== [J3] UNBUILDABLE-ON-UNLOCK SWEEP: every Z2-Z10 module material vs the")
	print("        deepest zone_N_access in its cheapest source's research ancestry ===")
	for z in range(2, 11):
		for mid in _mods_for_zone(z):
			var eff: Dictionary = sm.get_effective_module_cost(sm.modules[mid])
			var bad := []
			for k in eff:
				var ks := String(k)
				if ks == "credits": continue
				var g := _mat_gate_zone(ks)
				if g > z:
					bad.append("%s needs zone_%d_access" % [ks, g])
			if bad.is_empty():
				continue
			print("    *** %s (zone %d): %s" % [mid, z, ", ".join(bad)])
	print("    (blank above == nothing becomes unbuildable when its zone unlocks)")
	print("")
	print("[NC] done.")
	get_tree().quit(0)
