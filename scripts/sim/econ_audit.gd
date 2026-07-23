extends Node
# ============================================================================
# ECONOMY AUDIT (v141c) — the FOUR income sources on one axis: Liras/minute.
#
# Gathering / Crafting / Infrastructure / Combat are balanced by different
# people at different times against different units (per-action yield, recipe
# margin, per-interval rate, per-kill loot). This converts all four to the same
# number so "is the parallel layer decorative?" and "is one source a printer?"
# become measurable instead of vibes.
#
# Valuation: every material is priced at ElementDB base_value (its vendor
# price). That is the only common denominator the game actually has. Materials
# whose real worth is as a CRAFTING INPUT are therefore undervalued here — call
# that out when reading, don't "fix" it by inventing shadow prices.
#
#   Godot --headless --path <root> res://scenes/econ_audit.tscn
# ============================================================================

# Combat has no intrinsic clock — kill time is a function of player DPS, which
# is the free variable. Everything combat-side is reported BOTH as value-per-
# 1000-enemy-HP (DPS-neutral, the honest comparator) and as cr/min at this
# stated reference kill time.
const REF_KILL_SECONDS := 60.0
const RARITY_SAMPLES := 40000
const GATHER_SNAPSHOT_LEVELS := [1, 50]

var _rarity_ev := 0.0        # E[module sell price] at zone 10; scale by zone/10


func _v(sym) -> float:
	return float(ElementDB.get_element_value(String(sym)))


func _pad(s: String, n: int) -> String:
	# %-*s isn't available in GDScript's format; pad manually so columns line up
	# with multi-byte-free ASCII ids.
	var out := s
	while out.length() < n:
		out += " "
	return out


func _set_skill_level(mgr, lv: int) -> void:
	mgr.xp = float(mgr.get_xp_for_level(lv))
	mgr.level = 1
	mgr.check_level_up()


func _ready() -> void:
	GameState.hard_reset()
	print("[ECON] ================= ECONOMY AUDIT =================")
	print("[ECON] valuation = ElementDB base_value; combat ref kill = %.0fs" % REF_KILL_SECONDS)
	_sample_rarity()
	_audit_gather()
	_audit_craft()
	_audit_infra()
	_audit_combat()
	print("[ECON] ================= END =================")
	get_tree().quit()


# ── module-drop expected value ───────────────────────────────────────────────
# Sampled, not hardcoded: roll_rarity's table has been retuned repeatedly and a
# stale copy here would silently mis-price every combat row. COMMON is the
# "empty" roll (combat_manager._roll_one_module_drop returns early), so it
# contributes 0 to the EV rather than 100.
func _sample_rarity() -> void:
	var sm = GameState.shipyard_manager
	var counts := {}
	for i in range(RARITY_SAMPLES):
		var r: int = sm.roll_rarity(false)
		counts[r] = int(counts.get(r, 0)) + 1
	var ev := 0.0
	var parts := []
	for r in counts:
		var p: float = float(counts[r]) / float(RARITY_SAMPLES)
		var price: float = 0.0 if r == sm.Rarity.COMMON else float(sm.RARITY_SELL_PRICES.get(r, 100))
		ev += p * price
		parts.append("r%d=%.1f%%" % [int(r), p * 100.0])
	_rarity_ev = ev
	print("[ECON] trash-drop rarity mix: %s" % ", ".join(parts))
	print("[ECON] E[module sell] = %.0f Liras at zone 10 (scales x zone/10)" % ev)


# ── 1. GATHERING ─────────────────────────────────────────────────────────────
func _audit_gather() -> void:
	var gm = GameState.gathering_manager
	print("")
	print("[ECON] == 1. GATHERING (cr/min, single active task) ==")
	var head := "[ECON]   %s %s" % [_pad("lvl", 5), _pad("action", 26)]
	for lv in GATHER_SNAPSHOT_LEVELS:
		head += _pad("  @L%d" % lv, 12)
	print(head + "  note")

	var rows := []
	for aid in gm.actions:
		var a = gm.actions[aid]
		var per_lv := {}
		for lv in GATHER_SNAPSHOT_LEVELS:
			_set_skill_level(gm, int(lv))
			var dur: float = float(a.get("duration", 4.0)) / gm.get_action_speed_multiplier(aid)
			var per_action := 0.0
			var lt: Array = a.get("loot_table", [])
			for i in range(lt.size()):
				var e: Array = lt[i]
				per_action += float(e[1]) * float(gm.get_display_yield(e, i)) * _v(e[0])
			per_lv[lv] = (per_action / dur) * 60.0 if dur > 0.0 else 0.0
		rows.append([aid, int(a.get("level_req", 1)), per_lv])
	rows.sort_custom(func(x, y): return x[1] < y[1])

	# "Dominated" = a strictly-later unlock that earns no more than something the
	# player already had. In a single-active-task game a dominated action is dead
	# content: there is never a reason to select it.
	var best := 0.0
	var dominated := 0
	for r in rows:
		var line := "[ECON]   %s %s" % [_pad("L%d" % int(r[1]), 5), _pad(String(r[0]), 26)]
		for lv in GATHER_SNAPSHOT_LEVELS:
			line += _pad("%10.1f" % float(r[2][lv]), 12)
		var top: float = float(r[2][GATHER_SNAPSHOT_LEVELS[0]])
		var note := ""
		if top <= best and top > 0.0:
			note = "DOMINATED"
			dominated += 1
		best = maxf(best, top)
		print(line + "  " + note)
	print("[ECON]   dominated gather actions: %d / %d" % [dominated, rows.size()])
	_set_skill_level(gm, 1)


# ── 2. CRAFTING ──────────────────────────────────────────────────────────────
# A recipe's income is the VALUE IT ADDS: output value minus input value minus
# any Lira cost. A positive margin on cheap/abundant inputs is a printer; a
# negative margin means the recipe is a pure sink you only run for the item.
func _audit_craft() -> void:
	var pm = GameState.processing_manager
	print("")
	print("[ECON] == 2. CRAFTING (value added, cr/min) ==")
	var margins := []
	var zero_out := []
	for rid in pm.recipes:
		var rec = pm.recipes[rid]
		var iv := 0.0
		for s in rec.get("input", {}):
			iv += float(rec["input"][s]) * _v(s)
		var ov := 0.0
		var zeros := []
		for s in rec.get("output", {}):
			var v: float = _v(s)
			ov += float(rec["output"][s]) * v
			if v <= 0.0:
				zeros.append(String(s))
		for entry in rec.get("output_table", []):
			var avg: float = (float(entry[2]) + float(entry[3])) * 0.5
			ov += float(entry[1]) * avg * _v(entry[0])
		if not zeros.is_empty():
			zero_out.append([rid, zeros])
		var profit: float = ov - iv - float(rec.get("credits_cost", 0))
		var dur: float = float(rec.get("duration", 5.0))
		var ratio: float = (ov / iv) if iv > 0.0 else 999.0
		margins.append([rid, int(rec.get("level_req", 1)), iv, ov, profit, (profit / dur) * 60.0, ratio])

	margins.sort_custom(func(x, y): return x[5] > y[5])
	print("[ECON]   -- TOP 12 by value added / min (printer candidates) --")
	for i in range(mini(12, margins.size())):
		var m = margins[i]
		print("[ECON]   %s %s in=%9.0f out=%9.0f  x%-6.2f %10.1f cr/min" % [
			_pad("L%d" % int(m[1]), 5), _pad(String(m[0]), 26), float(m[2]), float(m[3]), float(m[6]), float(m[5])])
	print("[ECON]   -- BOTTOM 6 (value-destroying: craft costs more than it makes) --")
	for i in range(maxi(0, margins.size() - 6), margins.size()):
		var m = margins[i]
		print("[ECON]   %s %s in=%9.0f out=%9.0f  x%-6.2f %10.1f cr/min" % [
			_pad("L%d" % int(m[1]), 5), _pad(String(m[0]), 26), float(m[2]), float(m[3]), float(m[6]), float(m[5])])
	print("[ECON]   -- ZERO-VALUE outputs (unsellable; only worth their use) --")
	for z in zero_out:
		print("[ECON]   %s %s" % [_pad(String(z[0]), 26), str(z[1])])


# ── 3. INFRASTRUCTURE ────────────────────────────────────────────────────────
# The always-on parallel layer. The genre test: background yield must be a
# meaningful fraction of active yield, or the layer is decorative. Reported per
# ONE building at a fresh account (no warp/research multipliers), which is the
# floor, not the ceiling.
func _audit_infra() -> void:
	var im = GameState.infrastructure_manager
	print("")
	print("[ECON] == 3. INFRASTRUCTURE (net cr/min per building, payback) ==")
	var rows := []
	for bid in im.building_db:
		var d = im.building_db[bid]
		if not d.has("yield") or (d["yield"] as Dictionary).is_empty():
			continue
		var rate: Dictionary = im.get_building_adjusted_rate(bid)
		var gross := 0.0
		for res in rate.get("yield", {}):
			gross += float(rate["yield"][res]) * _v(res)
		var feed := 0.0
		for res in rate.get("input", {}):
			feed += float(rate["input"][res]) * _v(res)
		var net: float = gross - feed
		var cost: Dictionary = d.get("cost", {})
		var build_cost := float(cost.get("credits", 0))
		for s in cost:
			if String(s) != "credits":
				build_cost += float(cost[s]) * _v(s)
		var payback: float = (build_cost / net) if net > 0.0 else -1.0
		rows.append([bid, gross, feed, net, build_cost, payback])
	rows.sort_custom(func(x, y): return x[3] > y[3])
	print("[ECON]   %s %10s %10s %10s %12s %10s" % [_pad("building", 26), "gross", "feed", "NET", "cost", "payback"])
	for r in rows:
		var pb := "never" if float(r[5]) < 0.0 else ("%.0f min" % float(r[5]))
		print("[ECON]   %s %10.1f %10.1f %10.1f %12.0f %10s" % [
			_pad(String(r[0]), 26), float(r[1]), float(r[2]), float(r[3]), float(r[4]), pb])
	var negatives := 0
	for r in rows:
		if float(r[3]) <= 0.0:
			negatives += 1
	print("[ECON]   buildings with NON-POSITIVE net value: %d / %d" % [negatives, rows.size()])


# ── 4. COMBAT ────────────────────────────────────────────────────────────────
func _audit_combat() -> void:
	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager
	print("")
	print("[ECON] == 4. COMBAT (per kill; per 1000 enemy HP; cr/min @ %.0fs kill) ==" % REF_KILL_SECONDS)
	print("[ECON]   %s %8s %9s %9s %9s %10s %9s %10s" % [
		_pad("enemy", 26), "hp", "credits", "mats", "modules", "TOTAL", "per1kHP", "cr/min"])

	var zone_tot := {}
	for zid in cm.zones:
		var z = cm.zones[zid]
		var diff := int(z.get("difficulty", 1))
		print("[ECON]   -- %s (Z%d) --" % [String(z.get("name", zid)), diff])
		for eid in z.get("enemies", []):
			var e = cm.enemy_db.get(eid, {})
			if e.is_empty():
				continue
			var hp := float(e.get("stats", {}).get("hp", 1))
			var cr := 0.0
			var mats := 0.0
			for entry in e.get("loot", []):
				var avg: float = (float(entry[1]) + float(entry[2])) * 0.5
				if String(entry[0]) == "credits":
					cr += avg
				else:
					mats += avg * _v(entry[0])
			for entry in e.get("rare_loot", []):
				var avg2: float = (float(entry[2]) + float(entry[3])) * 0.5
				var ev: float = float(entry[1]) * avg2
				if String(entry[0]) == "credits":
					cr += ev
				elif sm and String(entry[0]) in sm.modules:
					mats += float(entry[1]) * float(sm.get_sell_price(String(entry[0])))
				else:
					mats += ev * _v(entry[0])
			# Module drops: front-half trash is materials-only (v114), and the
			# drop chance is the post-v109 base (accuracy no longer inflates it).
			var mods := 0.0
			var drops: bool = bool(e.get("drops_modules", not cm.enemy_is_front_salvage(eid)))
			if drops:
				mods = float(e.get("module_drop_chance", 0.0)) * _rarity_ev * (float(diff) / 10.0)
			var total: float = cr + mats + mods
			var per1k: float = total / hp * 1000.0
			var crmin: float = total / REF_KILL_SECONDS * 60.0
			print("[ECON]   %s %8.0f %9.0f %9.0f %9.0f %10.0f %9.1f %10.0f" % [
				_pad(eid, 26), hp, cr, mats, mods, total, per1k, crmin])
			if not e.get("is_boss", false):
				var acc: Array = zone_tot.get(diff, [0.0, 0.0, 0])
				acc[0] += per1k
				acc[1] += total
				acc[2] += 1
				zone_tot[diff] = acc

	print("")
	print("[ECON]   -- ZONE AVERAGES (trash only; bosses excluded) --")
	print("[ECON]   %s %12s %12s" % [_pad("zone", 10), "avg/1kHP", "avg total"])
	var keys := zone_tot.keys()
	keys.sort()
	var prev := 0.0
	for k in keys:
		var acc: Array = zone_tot[k]
		var n := float(acc[2])
		var avg1k: float = float(acc[0]) / n
		var flag := ""
		if prev > 0.0 and avg1k < prev:
			flag = "  <-- DENSITY DROP vs previous zone (farm-down incentive)"
		prev = avg1k
		print("[ECON]   %s %12.1f %12.0f%s" % [_pad("Z%d" % int(k), 10), avg1k, float(acc[1]) / n, flag])
