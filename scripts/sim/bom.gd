extends Node
# ============================================================================
# BOM — BILL OF MATERIALS RESOLVER  (v1, 2026-07-27)
#
# THE PROBLEM THIS EXISTS TO KILL. Every cost question in this project has been
# answered by a throwaway probe that walked the recipe tree by hand, and two of
# them got it wrong the same way: they priced a material at its own recipe's
# duration and never recursed into that recipe's inputs. WreckforgedAlloy was
# billed at 13 seconds while actually needing ChondriteAlloy + Steel 12 +
# MartianRelics 2, which understated one mission bundle's Steel demand by 2.6x
# (737 vs 1,925) and its active time by 2-4x. There is now ONE resolver and
# every cost question goes through it.
#
# THE ALGORITHM. The production graph is an AND-OR hypergraph: a recipe is an
# AND over its inputs, and several producers of the same material are an OR.
# Plain Dijkstra does not apply. This is Knuth's generalisation of Dijkstra to
# grammar/derivation problems: settle materials in increasing cost order, and
# relax a producer only once EVERY one of its inputs is already settled. That
# is exact, terminates on cyclic graphs (scrap -> Steel -> ... -> scrap), and
# runs in O((V + E) log V) — microseconds for this game's ~200 materials, versus
# the minutes a headless combat sim costs.
#
# TWO METRICS, because the owner's rules turn on the difference:
#   fg   FOREGROUND MINUTES per unit. The game is a single-active-task idle, so
#        gathering, processing and combat all compete for ONE slot. An
#        INFRASTRUCTURE building converts in PARALLEL, so its conversion time is
#        free here and only its inputs are charged. This is the "what does it
#        actually cost the player" number.
#   raw  Vector of ROOT resources per unit — gathered raws and combat drops.
#        This is the "do early materials still matter at Z10" number, and it is
#        the one that must go UP when a direct Steel line is replaced by a deep
#        item that eats Steel in its own recipe.
#
# depth is the same metric the cost composer uses: a combat drop or a material
# with no infra producer is 0, an infra building with no input is 0 (a drill),
# otherwise 1 + max(depth of inputs), minimised over producers — so a deep path
# nobody takes cannot flatter it.
#
#   Godot --headless --path <root> res://scenes/bom.tscn -- --item=AeonAlloy
#   Godot --headless --path <root> res://scenes/bom.tscn -- --module=z10_armor
#   Godot --headless --path <root> res://scenes/bom.tscn -- --refit=10
#   (no args) prints the per-zone refit table: fg hours, early-root demand, depth
# ============================================================================

const KILLS_PER_HOUR := 60.0          # matches the cost composer's COST_KILLS_PER_HOUR
const EARLY_ROOTS := ["Dirt", "Water", "Wood", "Fe", "Cu", "Si", "C", "O"]
const BIG := 1.0e18

# material -> cheapest foreground minutes per unit
var fg: Dictionary = {}
# material -> {root_symbol: units_per_unit}
var raw: Dictionary = {}
# material -> production depth
var depth: Dictionary = {}
# material -> human-readable description of the chosen producer
var via: Dictionary = {}

# every producer, flattened: {out: sym, per: units produced, mins: foreground
# minutes for one firing, inputs: {sym: qty}, kind: String, id: String, depth0: bool}
var _producers: Array = []
var _by_out: Dictionary = {}


func _ready() -> void:
	GameState.set_process(false)
	_collect_producers()
	_solve()
	var mode := ""
	var arg := ""
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		for k in ["item", "module", "refit"]:
			if s.begins_with("--%s=" % k):
				mode = k
				arg = s.split("=")[1]
	match mode:
		"item": _report_item(arg)
		"module": _report_module(arg)
		"refit": _report_refit(int(arg))
		_: _report_all()
	get_tree().quit(0)


# ---------------------------------------------------------------- graph build
func _collect_producers() -> void:
	# GATHERING — foreground, and a root. loot_table rows are [sym, chance, min, max].
	var gm = GameState.gathering_manager
	for aid in gm.actions:
		var a: Dictionary = gm.actions[aid]
		var dur: float = float(a.get("duration", 3.0))
		for row in a.get("loot_table", []):
			var sym: String = String(row[0])
			var chance: float = float(row[1])
			var avg: float = (float(row[2]) + float(row[3])) * 0.5 * chance
			if avg <= 0.0:
				continue
			_add(sym, avg, dur / 60.0, {}, "gather", String(aid), true)

	# PROCESSING — foreground. Cost is the recipe duration plus its inputs.
	var pm = GameState.processing_manager
	for rid in pm.recipes:
		var r: Dictionary = pm.recipes[rid]
		var ins: Dictionary = r.get("input", {})
		var outs: Dictionary = r.get("output", {})
		var dur2: float = float(r.get("duration", 5.0))
		for osym in outs:
			var q: float = float(outs[osym])
			if q <= 0.0:
				continue
			_add(String(osym), q, dur2 / 60.0, ins, "craft", String(rid), false)

	# INFRASTRUCTURE — PARALLEL. The conversion itself costs the player nothing
	# in foreground; only the inputs are charged. A building with no `input` is
	# a drill: depth 0, and free, so it terminates the chain.
	var im = GameState.infrastructure_manager
	for bid in im.building_db:
		var b: Dictionary = im.building_db[bid]
		var ys: Dictionary = b.get("yield", {})
		var ins2: Dictionary = b.get("input", {})
		var iv: float = maxf(float(b.get("interval", 5.0)), 0.001)
		for ysym in ys:
			var yq: float = float(ys[ysym])
			if yq <= 0.0:
				continue
			# per one unit of output, the building consumes inputs scaled by
			# (1 / yield). Interval is wall-clock, not foreground, so mins = 0.
			var scaled: Dictionary = {}
			for k in ins2:
				scaled[String(k)] = float(ins2[k]) / yq
			_add(String(ysym), 1.0, 0.0, scaled, "infra", String(bid), ins2.is_empty())

	# COMBAT DROPS — foreground (one enemy at a time), and a root.
	var cm = GameState.combat_manager
	var per_kill_min: float = 60.0 / KILLS_PER_HOUR
	for eid in cm.enemy_db:
		var e: Dictionary = cm.enemy_db[eid]
		for row2 in e.get("loot", []):
			var s2: String = String(row2[0])
			if s2 == "credits":
				continue
			var avg2: float = (float(row2[1]) + float(row2[2])) * 0.5
			if avg2 > 0.0:
				_add(s2, avg2, per_kill_min, {}, "combat", String(eid), true)
		for row3 in e.get("rare_loot", []):
			var s3: String = String(row3[0])
			if s3 == "credits":
				continue
			var avg3: float = (float(row3[2]) + float(row3[3])) * 0.5 * float(row3[1])
			if avg3 > 0.0:
				_add(s3, avg3, per_kill_min, {}, "combat", String(eid), true)


func _add(out_sym: String, per: float, mins: float, inputs: Dictionary, kind: String, id: String, is_root: bool) -> void:
	var p: Dictionary = {
		"out": out_sym, "per": per, "mins": mins, "inputs": inputs,
		"kind": kind, "id": id, "root": is_root
	}
	_producers.append(p)
	if not out_sym in _by_out:
		_by_out[out_sym] = []
	(_by_out[out_sym] as Array).append(_producers.size() - 1)


# ------------------------------------------------------- Knuth / Dijkstra AND-OR
func _solve() -> void:
	var settled: Dictionary = {}
	# seed: every producer with no inputs is immediately evaluable
	var best: Dictionary = {}
	var best_p: Dictionary = {}
	for i in range(_producers.size()):
		var p: Dictionary = _producers[i]
		if not (p["inputs"] as Dictionary).is_empty():
			continue
		var c: float = float(p["mins"]) / maxf(float(p["per"]), 1e-9)
		var o: String = String(p["out"])
		if not o in best or c < float(best[o]):
			best[o] = c
			best_p[o] = i

	while true:
		# pick the cheapest unsettled candidate
		var pick := ""
		var pc: float = BIG
		for m in best:
			if m in settled:
				continue
			if float(best[m]) < pc:
				pc = float(best[m])
				pick = String(m)
		if pick == "":
			break
		settled[pick] = true
		fg[pick] = pc
		var chosen: Dictionary = _producers[int(best_p[pick])]
		via[pick] = "%s:%s" % [chosen["kind"], chosen["id"]]
		# raw vector + depth for the chosen derivation
		var ins: Dictionary = chosen["inputs"]
		var per: float = maxf(float(chosen["per"]), 1e-9)
		if bool(chosen["root"]) or ins.is_empty():
			raw[pick] = {pick: 1.0} if bool(chosen["root"]) else {}
			depth[pick] = 0
		else:
			var rv: Dictionary = {}
			var dmax: int = 0
			for k in ins:
				var ks := String(k)
				var qty: float = float(ins[k]) / per
				for rk in (raw.get(ks, {}) as Dictionary):
					rv[rk] = float(rv.get(rk, 0.0)) + float((raw[ks] as Dictionary)[rk]) * qty
				dmax = maxi(dmax, int(depth.get(ks, 0)))
			raw[pick] = rv
			depth[pick] = dmax + 1

		# relax: any producer whose inputs are ALL settled can now be evaluated
		for i2 in range(_producers.size()):
			var p2: Dictionary = _producers[i2]
			var o2: String = String(p2["out"])
			if o2 in settled:
				continue
			var ready: bool = true
			var acc: float = 0.0
			for k2 in (p2["inputs"] as Dictionary):
				var ks2 := String(k2)
				if not ks2 in settled:
					ready = false
					break
				acc += float(fg[ks2]) * float((p2["inputs"] as Dictionary)[k2])
			if not ready:
				continue
			var c2: float = (float(p2["mins"]) + acc) / maxf(float(p2["per"]), 1e-9)
			if not o2 in best or c2 < float(best[o2]):
				best[o2] = c2
				best_p[o2] = i2


# ------------------------------------------------------------------- reporting
func cost_of(bill: Dictionary) -> Dictionary:
	# bill {sym: qty} -> {fg_min, raw:{}, unresolved:[]}
	var mins: float = 0.0
	var rv: Dictionary = {}
	var miss: Array = []
	for s in bill:
		var sym := String(s)
		if sym == "credits":
			continue
		var q: float = float(bill[s])
		if not sym in fg:
			miss.append(sym)
			continue
		mins += float(fg[sym]) * q
		for rk in (raw.get(sym, {}) as Dictionary):
			rv[rk] = float(rv.get(rk, 0.0)) + float((raw[sym] as Dictionary)[rk]) * q
	return {"fg_min": mins, "raw": rv, "unresolved": miss}


func _refit_bill(zone: int) -> Dictionary:
	# a full tier-matched Common loadout for that zone's hull
	var sm = GameState.shipyard_manager
	var hull_id := ""
	for h in sm.hulls:
		if int(sm.hulls[h].get("tier", 0)) == zone:
			hull_id = String(h)
			break
	var bill: Dictionary = {}
	if hull_id == "":
		return bill
	for slot in sm.hulls[hull_id].get("slots", []):
		var st := String(slot)
		var mid := "z%d_%s" % [zone, ("kinetic" if st == "weapon" else st)]
		if not mid in sm.modules:
			continue
		var c: Dictionary = sm.get_effective_module_cost(sm.modules[mid])
		for k in c:
			if String(k) == "credits":
				continue
			bill[String(k)] = float(bill.get(String(k), 0.0)) + float(c[k])
	return bill


func _early(rv: Dictionary) -> String:
	var parts: Array = []
	for r in EARLY_ROOTS:
		var v: float = float(rv.get(r, 0.0))
		if v >= 1.0:
			parts.append("%s %d" % [r, int(round(v))])
	return " ".join(parts) if not parts.is_empty() else "-"


func _report_all() -> void:
	print("[BOM] materials solved: %d / producers: %d" % [fg.size(), _producers.size()])
	print("[BOM] fg = FOREGROUND minutes (single active slot; infra conversion is free)")
	print("[BOM] %-6s %10s %10s  %s" % ["zone", "fg_hours", "maxdepth", "early roots (transitive)"])
	print("[BOM] " + "-".repeat(96))
	for z in range(2, 11):
		var bill: Dictionary = _refit_bill(z)
		if bill.is_empty():
			continue
		var r: Dictionary = cost_of(bill)
		var dmax: int = 0
		for s in bill:
			dmax = maxi(dmax, int(depth.get(String(s), 0)))
		print("[BOM] Z%-5d %10.2f %10d  %s" % [z, float(r["fg_min"]) / 60.0, dmax, _early(r["raw"])])
		if not (r["unresolved"] as Array).is_empty():
			print("[BOM]        UNRESOLVED: %s" % str(r["unresolved"]))
	print("[BOM] " + "-".repeat(96))
	print("[BOM] direct-line depth per zone module (owner rule: late recipes may not name shallow materials)")
	var sm2 = GameState.shipyard_manager
	for z2 in range(2, 11):
		for st2 in ["armor", "shield", "kinetic"]:
			var mid2 := "z%d_%s" % [z2, st2]
			if not mid2 in sm2.modules:
				continue
			var c2: Dictionary = sm2.get_effective_module_cost(sm2.modules[mid2])
			var line: Array = []
			for k2 in c2:
				if String(k2) == "credits":
					continue
				line.append("%s d%d" % [String(k2), int(depth.get(String(k2), -1))])
			print("[BOM] %-14s %s" % [mid2, " | ".join(line)])


func _report_item(sym: String) -> void:
	if not sym in fg:
		print("[BOM] %s — NO PRODUCER FOUND" % sym)
		return
	print("[BOM] %s" % sym)
	print("[BOM]   foreground minutes / unit : %.4f" % float(fg[sym]))
	print("[BOM]   depth                     : %d" % int(depth.get(sym, 0)))
	print("[BOM]   via                       : %s" % String(via.get(sym, "?")))
	print("[BOM]   raw roots / unit          :")
	var rv: Dictionary = raw.get(sym, {})
	var keys: Array = rv.keys()
	keys.sort_custom(func(a, b): return float(rv[a]) > float(rv[b]))
	for k in keys:
		if float(rv[k]) >= 0.001:
			print("[BOM]      %-22s %12.3f" % [String(k), float(rv[k])])


func _report_module(mid: String) -> void:
	var sm = GameState.shipyard_manager
	if not mid in sm.modules:
		print("[BOM] no such module: %s" % mid)
		return
	var c: Dictionary = sm.get_effective_module_cost(sm.modules[mid])
	print("[BOM] %s — charged cost and its transitive expansion" % mid)
	for k in c:
		var ks := String(k)
		if ks == "credits":
			print("[BOM]   %-22s %12d  (currency)" % [ks, int(c[k])])
			continue
		print("[BOM]   %-22s %12d  d%d  %.3f fg-min/unit  via %s" % [
			ks, int(c[k]), int(depth.get(ks, -1)), float(fg.get(ks, -1.0)), String(via.get(ks, "?"))])
	var r: Dictionary = cost_of(c)
	print("[BOM]   TOTAL foreground: %.1f min (%.2f h)" % [float(r["fg_min"]), float(r["fg_min"]) / 60.0])
	print("[BOM]   early roots: %s" % _early(r["raw"]))


func _report_refit(zone: int) -> void:
	var bill: Dictionary = _refit_bill(zone)
	if bill.is_empty():
		print("[BOM] no hull at tier %d" % zone)
		return
	print("[BOM] FULL TIER-MATCHED REFIT — zone %d" % zone)
	var keys: Array = bill.keys()
	keys.sort()
	for k in keys:
		var ks := String(k)
		print("[BOM]   %-22s %12d  d%d  %.3f fg-min/unit" % [
			ks, int(bill[k]), int(depth.get(ks, -1)), float(fg.get(ks, -1.0))])
	var r: Dictionary = cost_of(bill)
	print("[BOM]   TOTAL foreground: %.1f min (%.2f h)" % [float(r["fg_min"]), float(r["fg_min"]) / 60.0])
	print("[BOM]   TRANSITIVE ROOTS:")
	var rv: Dictionary = r["raw"]
	var rk: Array = rv.keys()
	rk.sort_custom(func(a, b): return float(rv[a]) > float(rv[b]))
	for k2 in rk:
		if float(rv[k2]) >= 1.0:
			print("[BOM]      %-22s %14d" % [String(k2), int(round(float(rv[k2])))])
