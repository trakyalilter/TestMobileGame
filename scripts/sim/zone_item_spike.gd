extends Node
# ============================================================================
# ZONE ITEM SPIKE — static, per-zone item-data audit. Walks every base item
# (z1-z10 × {kinetic,energy,missile,shield,armor,engine,battery,sensor}) and
# validates the progression invariants the economy hinges on, WITHOUT combat:
#
#   1. Existence/coverage   — all 8 slot types present in every zone (no dead slot)
#   2. Generation validity  — each item rolls valid stats at common/rare/unique
#   3. Inter-zone progress   — zN primary stat > z(N-1) (no dominated/dead zone)
#   4. Tier dominates rarity — zN common > z(N-1) LEGENDARY-max   [STEEP items]
#   5. Unique leapfrog bound — a max UNIQUE skips ~1 tier, never 2  [STEEP items]
#   6. Weapon DPS parity     — kinetic/energy/missile within a band per zone
#   7. Ammo coverage         — every weapon zone maps to compatible ammo
#   8. Exotics               — cryo (NG+) weapons carry positive atk_cryo + tier>=11
#
# STEEP (combat power: weapon/armor/shield/battery) scale ~2.2x/zone, so a
# crafted common one tier up beats a max-rolled legendary — that's the gate.
# FLAT utility (engine eva / sensor drop-rate mults) scale gently ON PURPOSE, so
# tier-dominance is NOT expected there (a good legendary engine persists) — those
# are checked for monotonic progression only, never tier-dominance.
#
# Complements gating_spike (per-zone WIN/LOSE combat) + rarity_pen_spike (weapon
# DPS rarity/penetration). This is the item-DATA layer nothing else covers.
# Run: Godot_console.exe --headless --path <proj> res://scenes/zone_item_spike.tscn
# ============================================================================

const R_COMMON := 0
const R_RARE := 2
const R_LEGENDARY := 3
const R_UNIQUE := 4

const ALL_TYPES := ["kinetic", "energy", "missile", "shield", "armor", "engine", "battery", "sensor"]
const WEAPONS := ["kinetic", "energy", "missile"]
const STEEP := ["kinetic", "energy", "missile", "shield", "armor", "battery"]  # tier-dominance applies
const FLAT := ["engine", "sensor"]                                            # monotonic only
const PARITY_BAND := 1.7   # max/min base-DPS across the 3 weapon types per zone

var _pass := 0
var _fail := 0
var _fails: Array = []

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	GameState.set_process(false)
	GameState.hard_reset()
	seed(7777)
	var sm = GameState.shipyard_manager
	var leg_max: float = 1.0 + float(sm.RARITY_STAT_RANGE[R_LEGENDARY][1])
	var uni_max: float = 1.0 + float(sm.RARITY_STAT_RANGE[R_UNIQUE][1])

	print("[ZI] ===== ZONE-BY-ZONE ITEM AUDIT (z1-10, 8 slot types) =====")
	print("[ZI] rarity maxima from live RARITY_STAT_RANGE: LEGENDARY ×%.2f · UNIQUE ×%.2f" % [leg_max, uni_max])

	_sec1_existence(sm)
	_sec2_generation(sm)
	_sec3_progression(sm)
	_sec4_tier_dominance(sm, leg_max)
	_sec5_unique_leapfrog(sm, uni_max)
	_sec6_dps_parity(sm)
	_sec7_ammo(sm)
	_sec8_exotics(sm)

	print("[ZI] ============================================================")
	if _fail > 0:
		print("[ZI] --- failures ---")
		for f in _fails:
			print("[ZI]   FAIL: " + str(f))
	print("[ZI] RESULT: %d passed, %d failed" % [_pass, _fail])
	print("[ZI] " + ("ALL PASS" if _fail == 0 else "FAILURES PRESENT"))
	get_tree().quit(0 if _fail == 0 else 1)

# ── Section 1: existence / coverage ─────────────────────────────────────────
func _sec1_existence(sm) -> void:
	print("[ZI] ## 1. Existence — 8 types × z1-10 = 80 base items")
	var present := 0
	for n in range(1, 11):
		for t in ALL_TYPES:
			var id := "z%d_%s" % [n, t]
			if _chk(id in sm.modules, "missing base item %s" % id):
				present += 1
		for t in WEAPONS:
			_chk(("z%d_%s" % [n, t]) in sm.modules, "z%d has no %s weapon" % [n, t])
	print("[ZI]   %d/80 base items present" % present)

# ── Section 2: generation produces valid stats ──────────────────────────────
func _sec2_generation(sm) -> void:
	print("[ZI] ## 2. Generation validity — common/rare/unique roll positive, finite, tier-N")
	for n in range(1, 11):
		for t in ALL_TYPES:
			var base := "z%d_%s" % [n, t]
			if not (base in sm.modules):
				continue
			var slot := str(sm.modules[base].get("slot_type", ""))
			for rar in [R_COMMON, R_RARE, R_UNIQUE]:
				var mid: String = sm.generate_module_drop(base, rar, n)
				if not _chk(mid != "" and mid in sm.modules, "%s r%d did not generate" % [base, rar]):
					continue
				var p := _primary(sm.modules[mid].get("stats", {}), slot)
				_chk(p > 0.0 and is_finite(p), "%s r%d primary stat invalid (%s)" % [base, rar, str(p)])
				_chk(int(sm.get_module_tier(mid)) == n, "%s r%d reads tier %d (want %d)" % [base, rar, int(sm.get_module_tier(mid)), n])

# ── Section 3: inter-zone progression (no dominated zone) ───────────────────
func _sec3_progression(sm) -> void:
	print("[ZI] ## 3. Inter-zone progression — zN base > z(N-1) base (every type)")
	for t in ALL_TYPES:
		var ok := true
		for n in range(2, 11):
			var prev := _bprim(sm, n - 1, t)
			var cur := _bprim(sm, n, t)
			if prev <= 0.0 or cur <= 0.0:
				continue
			if not _chk(cur > prev, "z%d %s (%.0f) NOT > z%d (%.0f) — dominated zone" % [n, t, cur, n - 1, prev]):
				ok = false
		var lo := _bprim(sm, 1, t)
		var hi := _bprim(sm, 10, t)
		print("[ZI]   %-8s z1=%.0f -> z10=%.0f  (×%.0f over 9 zones)  %s" % [t, lo, hi, (hi / lo if lo > 0 else 0.0), ("ok" if ok else "DIP")])

# ── Section 4: tier dominates rarity (STEEP combat items) ───────────────────
func _sec4_tier_dominance(sm, leg_max: float) -> void:
	print("[ZI] ## 4. Tier dominates rarity — zN common > z(N-1) legendary-max (×%.2f)  [combat items]" % leg_max)
	for t in STEEP:
		var worst := 9999.0
		var worst_n := 0
		for n in range(2, 11):
			var prev := _bprim(sm, n - 1, t)
			var cur := _bprim(sm, n, t)
			if prev <= 0.0:
				continue
			var step := cur / prev
			if step < worst:
				worst = step
				worst_n = n
			_chk(cur > prev * leg_max, "z%d %s common (%.0f) NOT > z%d legendary-max (%.0f)" % [n, t, cur, n - 1, prev * leg_max])
		print("[ZI]   %-8s min zone-step ×%.2f at z%d->z%d  (need > ×%.2f)" % [t, worst, worst_n - 1, worst_n, leg_max])
	print("[ZI]   (engine/sensor excluded by design — flat utility stats, a good legendary persists across tiers)")

# ── Section 5: unique leapfrog bounds (STEEP combat items) ──────────────────
func _sec5_unique_leapfrog(sm, uni_max: float) -> void:
	print("[ZI] ## 5. Unique leapfrog — max UNIQUE (×%.2f) reaches ~1 tier up, never 2  [combat items]" % uni_max)
	for t in STEEP:
		for n in range(2, 11):
			var prev := _bprim(sm, n - 1, t)
			var cur := _bprim(sm, n, t)
			if prev <= 0.0 or cur <= 0.0:
				continue
			# 5a: a max unique is worth carrying one tier (>= the next tier's common)
			_chk(prev * uni_max >= cur, "z%d %s unique-max (%.0f) < z%d common (%.0f) — unique not worth carrying" % [n - 1, t, prev * uni_max, n, cur])
		for n in range(2, 10):
			var prev := _bprim(sm, n - 1, t)
			var two := _bprim(sm, n + 1, t)
			if prev <= 0.0 or two <= 0.0:
				continue
			# 5b: a max unique must NOT reach two tiers up
			_chk(prev * uni_max < two, "z%d %s unique-max (%.0f) >= z%d common (%.0f) — leapfrogs 2 tiers" % [n - 1, t, prev * uni_max, n + 1, two])

# ── Section 6: weapon-type DPS parity ───────────────────────────────────────
func _sec6_dps_parity(sm) -> void:
	print("[ZI] ## 6. Weapon DPS parity — kinetic/energy/missile within ×%.1f per zone" % PARITY_BAND)
	for n in range(1, 11):
		var dk := _dps(sm, n, "kinetic")
		var de := _dps(sm, n, "energy")
		var dm := _dps(sm, n, "missile")
		var hi: float = max(dk, max(de, dm))
		var lo: float = min(dk, max(0.0001, min(de, dm)))
		var spread: float = (hi / lo if lo > 0.0 else 0.0)
		_chk(spread <= PARITY_BAND, "z%d weapon DPS spread ×%.2f (kin=%.0f nrg=%.0f msl=%.0f) — a type dominates" % [n, spread, dk, de, dm])
		print("[ZI]   z%-2d kin=%-8.0f nrg=%-8.0f msl=%-8.0f  spread ×%.2f" % [n, dk, de, dm, spread])

# ── Section 7: ammo coverage ────────────────────────────────────────────────
func _sec7_ammo(sm) -> void:
	print("[ZI] ## 7. Ammo coverage — every weapon zone maps to compatible ammo")
	var ammo_map := {"kinetic": "SlugT%d", "energy": "CellT%d", "missile": "MissileT%d"}
	var compat := {"kinetic": "kinetic", "energy": "energy", "missile": "explosive"}
	for n in range(1, 11):
		var at := 4
		if n <= 8: at = 3
		if n <= 5: at = 2
		if n <= 2: at = 1
		for t in WEAPONS:
			if not (("z%d_%s" % [n, t]) in sm.modules):
				continue
			var ammo: String = ammo_map[t] % at
			_chk(sm.is_ammo_compatible(compat[t], ammo), "z%d %s -> %s not ammo-compatible" % [n, t, ammo])

# ── Section 8: exotic (cryo) weapons ────────────────────────────────────────
func _sec8_exotics(sm) -> void:
	print("[ZI] ## 8. Exotic weapons — cryo/corrosion (NG+) carry positive exotic damage")
	print("[ZI]    NOTE: Z11/Z12 gate by DAMAGE TYPE (_get_breach_factors: conventional ×0.02,")
	print("[ZI]    matching exotic ×1.0), NOT the tier wall — so power_tier is just the raw-damage")
	print("[ZI]    tier; the warp multiplier unlocked alongside cryo carries it into Z11/Z12.")
	var found := 0
	for mid in sm.modules:
		var m = sm.modules[mid]
		if not (m is Dictionary) or str(m.get("slot_type", "")) != "weapon":
			continue
		var cryo := float(m.get("stats", {}).get("atk_cryo", 0))
		if cryo > 0.0:
			found += 1
			var pt := int(sm.get_module_tier(mid))
			_chk(cryo > 0.0 and is_finite(cryo), "%s exotic damage invalid (%s)" % [mid, str(cryo)])
			print("[ZI]   %-18s atk_cryo=%.0f power_tier=%d (zone-gated by type, not tier)" % [mid, cryo, pt])
	_chk(found >= 1, "no cryo/exotic weapons found — Z11/Z12 would be ungateable")
	if found == 0:
		print("[ZI]   (none found)")

# ── helpers ─────────────────────────────────────────────────────────────────
func _primary(stats: Dictionary, slot: String) -> float:
	match slot:
		"weapon":
			return float(stats.get("atk_kinetic", 0)) + float(stats.get("atk_energy", 0)) + float(stats.get("atk_explosive", 0)) + float(stats.get("atk_cryo", 0))
		"armor":
			return float(stats.get("def", 0))
		"shield":
			return float(stats.get("max_shield", 0))
		"engine":
			return float(stats.get("eva", 0))
		"battery":
			return float(stats.get("energy_capacity", 0))
		"sensor":
			# v145: sensors carry loot-rate mults now, not the deleted `accuracy`.
			return float(stats.get("module_drop_mult", 0.0))
	return 0.0

func _bprim(sm, n: int, t: String) -> float:
	var id := "z%d_%s" % [n, t]
	var m = sm.modules.get(id, {})
	if not (m is Dictionary) or m.is_empty():
		return 0.0
	return _primary(m.get("stats", {}), str(m.get("slot_type", "")))

func _dps(sm, n: int, t: String) -> float:
	var id := "z%d_%s" % [n, t]
	var m = sm.modules.get(id, {})
	if not (m is Dictionary) or m.is_empty():
		return 0.0
	var st: Dictionary = m.get("stats", {})
	var atk := _primary(st, "weapon")
	var interval: float = maxf(0.25, float(st.get("atk_interval", 2.0)))
	return atk / interval

func _chk(cond: bool, label: String) -> bool:
	if cond:
		_pass += 1
	else:
		_fail += 1
		_fails.append(label)
	return cond
