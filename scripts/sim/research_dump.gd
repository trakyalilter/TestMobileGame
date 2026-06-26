extends Node
# ============================================================================
# RESEARCH TIME — REALISTIC wall-clock estimate (invested player).
#
# Effective material qty = cost_items × MATERIAL_MULTIPLIER (stage-scaling baked in).
#
# REALISTIC rate model (transparent; tune the consts below):
#   • Efficiency research is the dominant lever and is GATHER+PROCESS only
#     (×2/4/8/16/32 via get_efficiency_multiplier) — it does NOT touch infra.
#     Assumed tier-appropriate: t<=2 ×1, t3 ×4, t4 ×16, t5+ ×32.
#   • Active processing rate  = base_proc  × eff × PROC_SPEED (recipe speed upgrades)
#   • Active gathering rate   = base_gather × eff × GATHER_LEVEL (skill-level yield)
#   • Infrastructure rate     = base_infra_per_bldg × N_BUILDINGS × INFRA_BONUS
#       (eng-scale × Recursion × mastery; NO ×32 efficiency). Scales with count.
#   • realistic rate(mat) = max(proc, gather, infra).  Parallel = bottleneck (max),
#     active-seq = sum. Combat-gated mats (Res1/2/3, cores, drops) reported separate.
#
# These are still ESTIMATES — real time scales further with building count, warp
# (×2^tier global production), Recursion levels, and mastery. Stated so it's tunable.
#
# Run: Godot_console.exe --headless --path <proj> res://scenes/research_dump.tscn
# ============================================================================

const N_BUILDINGS := 10.0   # infra buildings per bottleneck material (no in-game cap)
const PROC_SPEED  := 1.5    # active processing speed upgrades (~+50%)
const GATHER_LEVEL := 2.0   # gather yield from skill level (~lvl 100 = ×2)
const INFRA_BONUS := 2.0    # infra eng-scale × Recursion × mastery (modest, ~×2)

const COMBAT_GATED := {
	"Res1": true, "Res2": true, "Res3": true,
	"NavData": true, "SalvageData": true, "MiteChitin": true, "VoidArtifact": true,
	"ColonyDataCore": true, "ColonySalvage": true, "RadIsotope": true, "ExoticIsotope": true,
	"BiohazardSample": true, "QuarantineClearance": true, "AncientTech": true,
	"OmegaPlating": true, "PrimordialShard": true, "Neutronium": true, "PirateSalvage": true,
}

func _eff(tier: int) -> float:
	if tier <= 2: return 1.0
	if tier == 3: return 4.0
	if tier == 4: return 16.0
	return 32.0

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	GameState.set_process(false)
	var rm = GameState.research_manager
	if rm.has_method("_scale_mid_late_research_item_costs"):
		rm._scale_mid_late_research_item_costs()
	var mat_mult: float = float(rm.MATERIAL_MULTIPLIER)

	# --- base per-source rates, split by path ---
	var proc_b := {}; var infra_b := {}; var gather_b := {}
	var gm = GameState.gathering_manager
	var pm = GameState.processing_manager
	var im = GameState.infrastructure_manager
	for aid in gm.actions:
		var a = gm.actions[aid]
		var dur := float(a.get("duration", 4.0))
		for e in a.get("loot_table", []):
			if e is Array and e.size() >= 4 and dur > 0.0:
				var rpm: float = float(e[1]) * (float(e[2]) + float(e[3])) / 2.0 / dur * 60.0
				gather_b[e[0]] = max(gather_b.get(e[0], 0.0), rpm)
	for rid in pm.recipes:
		var r = pm.recipes[rid]
		var d2 := float(r.get("duration", 0.0))
		var out = r.get("output", {})
		if out is Dictionary and d2 > 0.0:
			for m in out:
				proc_b[m] = max(proc_b.get(m, 0.0), float(out[m]) / d2 * 60.0)
	for bid in im.building_db:
		var b = im.building_db[bid]
		var iv := float(b.get("interval", 0.0))
		var by = b.get("yield", {})
		if by is Dictionary and iv > 0.0:
			for m in by:
				infra_b[m] = max(infra_b.get(m, 0.0), float(by[m]) / iv * 60.0)

	var ids: Array = rm.tech_tree.keys()
	ids.sort_custom(func(a, b):
		var na = rm.tech_tree[a]; var nb = rm.tech_tree[b]
		var ta := int(na.get("tier", 0)); var tb := int(nb.get("tier", 0))
		if ta != tb: return ta < tb
		return int(na.get("cost", 0)) < int(nb.get("cost", 0)))

	print("[T] tier | research | credits | realistic_parallel | realistic_seq | bottleneck | combat-gated")
	var cum_par := {}; var cum_seq := {}
	for tid in ids:
		var node = rm.tech_tree[tid]
		var tier := int(node.get("tier", 0))
		var e := _eff(tier)
		var par := 0.0; var seq := 0.0; var bneck := "-"; var combat := []
		if "cost_items" in node:
			for it in node["cost_items"]:
				var q := int(int(node["cost_items"][it]) * mat_mult)
				if q <= 0: continue
				if it in COMBAT_GATED:
					combat.append("%s×%d" % [it, q]); continue
				var rate: float = max(
					float(proc_b.get(it, 0.0)) * e * PROC_SPEED,
					max(float(gather_b.get(it, 0.0)) * e * GATHER_LEVEL,
						float(infra_b.get(it, 0.0)) * N_BUILDINGS * INFRA_BONUS))
				if rate <= 0.0:
					combat.append("%s×%d(?)" % [it, q]); continue
				var t: float = float(q) / rate
				seq += t
				if t > par:
					par = t; bneck = "%s×%d=%.0fm" % [it, q, t]
		cum_par[tier] = cum_par.get(tier, 0.0) + par
		cum_seq[tier] = cum_seq.get(tier, 0.0) + seq
		print("[T] t%d | %-26s | %10d | %7.0fm | %7.0fm | %-22s | %s" % [
			tier, tid, int(node.get("cost", 0)), par, seq, bneck, (", ".join(combat) if not combat.is_empty() else "-")])

	print("[SUM] tier | parallel (h) | active-seq (h)   [eff t3×4 t4×16 t5+×32; %d infra bldgs; combat+credits separate]" % int(N_BUILDINGS))
	var tp := 0.0; var ts := 0.0
	var tiers: Array = cum_par.keys(); tiers.sort()
	for t in tiers:
		tp += cum_par[t]; ts += cum_seq[t]
		print("[SUM] t%-2d | %7.0fm (%.1fh) | %7.0fm (%.1fh)" % [t, cum_par[t], cum_par[t]/60.0, cum_seq[t], cum_seq[t]/60.0])
	print("[SUM] TOTAL | %7.0fm (%.1fh) | %7.0fm (%.1fh)" % [tp, tp/60.0, ts, ts/60.0])
	print("[T] done")
	get_tree().quit(0)
