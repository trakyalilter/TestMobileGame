extends Node
# DIMINISHING-RETURNS CEILING CHECK.
#
# Every producer has a HARD asymptote: _dr_units approaches KNEE+TAIL as copy
# count grows, so a building type can never exceed
#     ceiling = neutral_rate_per_min x (knee + tail) x eng_cap x ore_mult
# no matter how many copies are built. A chain that demands more than that is
# unsatisfiable at ANY scale -- not slow, impossible.
#
# This expands a reference complex to a fixed point and reports demand against
# ceiling for every material in it. Run after any change to the endgame chains.
#   Godot --headless --path <root> res://scenes/dr_ceiling_check.tscn -- --yards=3

const ENG_CAP := 2.0   # INFRA_ENG_SCALE cap

var im
var pm

func _ready() -> void:
	im = GameState.infrastructure_manager
	pm = GameState.processing_manager
	GameState.set_process(false)
	var yards := 1.0
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--yards="):
			yards = float(String(a).split("=")[1])

	# ---- ceilings ----------------------------------------------------------
	var ceil_of: Dictionary = {}     # material -> units/min hard ceiling
	var producer_of: Dictionary = {} # material -> building id
	for bid in im.building_db:
		var b: Dictionary = im.building_db[bid]
		var ys: Dictionary = b.get("yield", {})
		if ys.is_empty():
			continue
		var iv: float = maxf(float(b.get("interval", 5.0)), 0.001)
		var knee: int = im.INFRA_PRIMITIVE_DR_KNEE if bid in im.PRIMITIVE_EXTRACTORS else im.INFRA_DR_KNEE
		var tail: int = im.INFRA_PRIMITIVE_DR_TAIL if bid in im.PRIMITIVE_EXTRACTORS else im.INFRA_DR_TAIL
		var ore: float = im.INFRA_ORE_EXTRACTION_MULT if bid in im.INFRA_ORE_EXTRACTORS else 1.0
		for sym in ys:
			var per_min: float = float(ys[sym]) / iv * 60.0
			var c: float = per_min * float(knee + tail) * ENG_CAP * ore
			if c > float(ceil_of.get(String(sym), 0.0)):
				ceil_of[String(sym)] = c
				producer_of[String(sym)] = bid

	# ---- demand: recursive expansion to LEAF materials ---------------------
	# The earlier iterative version re-pushed intermediates every pass and never
	# converged, inflating demand ~40x. Expand recursively instead: a material
	# with an input-bearing producer is replaced by its inputs, scaled; anything
	# else is a leaf and accumulates. _seen guards the recursion against cycles.
	var demand: Dictionary = {}
	# Seed ONLY the true end products. frame_yard already pulls CapitalSpar ->
	# FabricationBus -> PrecisionLattice -> SinteredCarbide, so seeding those
	# separately counts the same chain several times over.
	for seed_id in ["frame_yard", "diamond_litho_hall"]:
		if not seed_id in im.building_db:
			continue
		var b: Dictionary = im.building_db[seed_id]
		var iv: float = maxf(float(b.get("interval", 5.0)), 0.001)
		for k in b.get("input", {}):
			_expand(String(k), float(b["input"][k]) / iv * 60.0 * yards, demand, producer_of, {})

	# ---- report ------------------------------------------------------------
	print("[DR] reference complex at %.0f frame yard(s) — demand vs HARD ceiling" % yards)
	print("[DR] %-20s %14s %14s %9s" % ["material", "need/min", "ceiling/min", "used"])
	print("[DR] " + "-".repeat(64))
	var rows: Array = []
	for sym in demand:
		var need: float = float(demand[sym])
		if need <= 0.01:
			continue
		var c: float = float(ceil_of.get(String(sym), 0.0))
		rows.append([String(sym), need, c, (need / c * 100.0) if c > 0.0 else -1.0])
	rows.sort_custom(func(a, b): return float(a[3]) > float(b[3]))
	var breaches := 0
	for r in rows:
		var pct: float = float(r[3])
		var mark := ""
		if pct < 0.0:
			mark = "  NO INFRA PRODUCER (serial only)"
		elif pct > 100.0:
			mark = "  *** BREACH ***"
			breaches += 1
		elif pct > 70.0:
			mark = "  (tight)"
		print("[DR] %-20s %14.1f %14.1f %8.1f%%%s" % [r[0], r[1], r[2], pct, mark])
	print("[DR] " + "-".repeat(64))
	print("[DR] BREACHES: %d" % breaches)
	get_tree().quit(0)


# Replace a material by its producer's inputs, scaled; accumulate leaves.
func _expand(sym: String, rate: float, out: Dictionary, producer_of: Dictionary, seen: Dictionary) -> void:
	if rate <= 0.000001:
		return
	if sym in seen:                      # cycle: treat as a leaf
		out[sym] = float(out.get(sym, 0.0)) + rate
		return
	if not sym in producer_of:
		out[sym] = float(out.get(sym, 0.0)) + rate
		return
	var bid: String = String(producer_of[sym])
	var b: Dictionary = im.building_db[bid]
	var ins: Dictionary = b.get("input", {})
	if ins.is_empty():                   # a drill: this IS the leaf
		out[sym] = float(out.get(sym, 0.0)) + rate
		return
	var iv: float = maxf(float(b.get("interval", 5.0)), 0.001)
	var out_per_min: float = float(b["yield"][sym]) / iv * 60.0
	if out_per_min <= 0.0:
		out[sym] = float(out.get(sym, 0.0)) + rate
		return
	# This intermediate is itself produced -- record its own load too, since it
	# has a ceiling of its own, then push its inputs upstream.
	out[sym] = float(out.get(sym, 0.0)) + rate
	var runs: float = rate / out_per_min
	var seen2: Dictionary = seen.duplicate()
	seen2[sym] = true
	for k in ins:
		_expand(String(k), float(ins[k]) / iv * 60.0 * runs, out, producer_of, seen2)
