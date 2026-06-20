extends SceneTree
## PHASE 3 — Combat math. Exercises the damage pipeline for invariants that, if
## broken, silently corrupt every fight: phase-band indexing, breach gating
## (warp-hardened + multi-phase bosses), damage-reduction floor, armor/shield
## monotonicity, enemy resist clamp, fleet multiplier cap, and DPS non-negativity.
## Also a design-integrity pass: every multi-phase boss must be breachable by a
## weapon the game actually contains (no element with no answer = soft-lock).

var gd
var gs
var errors: Array = []
var warns: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s): errors.append(s)
func W(s): warns.append(s)
func approx(a: float, b: float) -> bool: return absf(a - b) <= 0.0001

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	gd = root.get_node("GameData")
	gs = root.get_node("GameState")

	_check_phase_index()
	_check_breach_factors()
	_check_resolve_invariants()
	_check_resist_clamp()
	_check_fleet_mult()
	_check_dps()
	_check_enemy_stats()
	_check_phase_breachability()

	print("\n===== PHASE 3: COMBAT MATH =====")
	print("enemies=%d zones=%d weapon-modules=%d" % [gd.ENEMIES.size(), gd.ZONES.size(), _weapon_module_count()])
	print("errors=%d  warnings=%d" % [errors.size(), warns.size()])
	if not warns.is_empty():
		print("\n--- WARNINGS (%d) ---" % warns.size())
		for w in warns: print("  ⚠ " + w)
	if not errors.is_empty():
		print("\n--- ERRORS (%d) ---" % errors.size())
		for e in errors: print("  ✗ " + e)
		print("\nCOMBAT_MATH: FAIL")
		quit(1)
		return
	print("\nCOMBAT_MATH: PASS")
	quit()

# --- _phase_index: full HP -> band 0, near-death -> n-1, monotone as HP drops. ---
func _check_phase_index() -> void:
	for n in [2, 3, 4]:
		gs.enemy_inst = {"max_hp": 1000.0, "hp": 1000.0}
		if gs._phase_index(n) != 0:
			E("_phase_index(n=%d) at full HP = %d, expected 0" % [n, gs._phase_index(n)])
		gs.enemy_inst = {"max_hp": 1000.0, "hp": 0.0}
		if gs._phase_index(n) != n - 1:
			E("_phase_index(n=%d) at 0 HP = %d, expected %d" % [n, gs._phase_index(n), n - 1])
		# Monotone non-decreasing as HP falls from max to 0.
		var prev := -1
		var hp := 1000.0
		while hp >= 0.0:
			gs.enemy_inst = {"max_hp": 1000.0, "hp": hp}
			var idx: int = gs._phase_index(n)
			if idx < prev:
				E("_phase_index(n=%d) non-monotone: hp=%.0f gave band %d after %d" % [n, hp, idx, prev])
				break
			if idx < 0 or idx > n - 1:
				E("_phase_index(n=%d) out of range: hp=%.0f -> %d" % [n, hp, idx])
				break
			prev = idx
			hp -= 50.0
	gs.enemy_inst = {}

# --- _breach_factors: empty/normal pass-through, warp-hardened cryo wall, and
# multi-phase element gating with cryo-channel exotic matching. ---
func _check_breach_factors() -> void:
	gs.enemy_inst = {}
	var bf: Dictionary = gs._breach_factors("cryo")
	if not (approx(bf["k"], 1.0) and approx(bf["e"], 1.0) and approx(bf["x"], 1.0) and approx(bf["cryo"], 1.0)):
		E("_breach_factors with no enemy should be all 1.0, got %s" % str(bf))

	# Warp-hardened: only a cryo-exotic weapon breaches.
	gs.enemy_inst = {"warp_hardened": true}
	var bw: Dictionary = gs._breach_factors("cryo")
	if not (approx(bw["k"], 0.02) and approx(bw["cryo"], 1.0)):
		E("warp_hardened+cryo weapon: expected k=0.02 cryo=1.0, got %s" % str(bw))
	var bwc: Dictionary = gs._breach_factors("corrosion")
	if not approx(bwc["cryo"], 0.02):
		E("warp_hardened+non-cryo weapon: cryo channel should be sealed (0.02), got %.3f" % bwc["cryo"])

	# Multi-phase boss: current band's element breaches at 1.0, others at phase_cut.
	gs.enemy_inst = {"max_hp": 1000.0, "hp": 1000.0, "phases": ["kinetic", "corrosion"], "phase_cut": 0.15}
	var b0: Dictionary = gs._breach_factors("corrosion")   # band 0 -> kinetic breaches
	if not (approx(b0["k"], 1.0) and approx(b0["e"], 0.15) and approx(b0["x"], 0.15) and approx(b0["cryo"], 0.15)):
		E("phase band0 (kinetic): expected k=1.0 others=0.15, got %s" % str(b0))
	gs.enemy_inst = {"max_hp": 1000.0, "hp": 1.0, "phases": ["kinetic", "corrosion"], "phase_cut": 0.15}
	var b1: Dictionary = gs._breach_factors("corrosion")   # band1 -> corrosion; cryo channel matches
	if not (approx(b1["cryo"], 1.0) and approx(b1["k"], 0.15)):
		E("phase band1 (corrosion) + corrosion weapon: expected cryo=1.0 k=0.15, got %s" % str(b1))
	var b1w: Dictionary = gs._breach_factors("cryo")       # wrong exotic -> sealed
	if not approx(b1w["cryo"], 0.15):
		E("phase band1 (corrosion) + cryo weapon: cryo channel should be cut (0.15), got %.3f" % b1w["cryo"])
	gs.enemy_inst = {}

# --- resolve_damage: non-negative outputs; damage-reduction floor honored; more
# armor never raises hull damage; more shield never lowers shield absorbed. ---
func _check_resolve_invariants() -> void:
	var min_factor: float = 1.0 - float(gd.MAX_DAMAGE_REDUCTION)
	# Non-negativity sweep across difficulties / armor / shield.
	for diff in [1, 5, 11, 12]:
		for armor in [0.0, 100.0, 5000.0]:
			for shield in [0.0, 500.0]:
				seed(42)
				var r: Array = gs.resolve_damage(100.0, 80.0, 60.0, shield, armor, diff, 0.0, true, 40.0, "cryo")
				if float(r[0]) < 0.0 or float(r[1]) < 0.0:
					E("resolve_damage negative output diff=%d armor=%.0f shield=%.0f -> %s" % [diff, armor, shield, str(r)])

	# Damage-reduction floor: even at absurd armor, hull damage stays >= the floor
	# share of the raw per-type damage (variance pinned by seed, crit off).
	seed(7)
	var huge: Array = gs.resolve_damage(1000.0, 0.0, 0.0, 0.0, 1.0e9, 1, 0.0, true, 0.0, "cryo")
	# raw kinetic potential = 1000 * 1.2; floor share = min_factor; variance in [0.9,1.1].
	var floor_hull: float = 1000.0 * 1.2 * min_factor * 0.9
	if float(huge[1]) < floor_hull - 0.001:
		E("damage-reduction floor breached: hull=%.2f below floor %.2f at 1e9 armor" % [huge[1], floor_hull])

	# Armor monotonicity: hull damage non-increasing as armor rises (seed pinned).
	var prev_hull := 1.0e30
	for armor in [0.0, 50.0, 200.0, 1000.0, 5000.0, 50000.0]:
		seed(99)
		var rr: Array = gs.resolve_damage(200.0, 0.0, 0.0, 0.0, armor, 5, 0.0, true, 0.0, "cryo")
		if float(rr[1]) > prev_hull + 0.001:
			E("hull damage rose with armor (%.0f): %.2f > %.2f" % [armor, rr[1], prev_hull])
		prev_hull = float(rr[1])

	# Shield monotonicity: shield absorbed non-decreasing as shield pool grows.
	var prev_sh := -1.0
	for shield in [0.0, 50.0, 200.0, 1000.0, 5000.0]:
		seed(99)
		var rs: Array = gs.resolve_damage(200.0, 100.0, 50.0, shield, 0.0, 5, 0.0, true, 0.0, "cryo")
		if float(rs[0]) < prev_sh - 0.001:
			E("shield absorbed fell as shield pool grew (%.0f): %.2f < %.2f" % [shield, rs[0], prev_sh])
		prev_sh = float(rs[0])
	gs.enemy_inst = {}

# --- Enemy resist clamp: resist is bounded to [-0.40, 0.50] so a data typo can't
# make an enemy immune or take 10x damage. ---
func _check_resist_clamp() -> void:
	# Baseline (no resist).
	seed(123)
	gs.enemy_inst = {"hp": 1000.0, "max_hp": 1000.0}
	var base: Array = gs.resolve_damage(500.0, 0.0, 0.0, 0.0, 0.0, 3, 0.0, true, 0.0, "cryo")
	# Extreme positive resist -> clamped to 0.50 -> hull ~ 0.5x baseline.
	seed(123)
	gs.enemy_inst = {"hp": 1000.0, "max_hp": 1000.0, "resist_k": 99.0}
	var hi: Array = gs.resolve_damage(500.0, 0.0, 0.0, 0.0, 0.0, 3, 0.0, true, 0.0, "cryo")
	if not approx(float(hi[1]), float(base[1]) * 0.5):
		E("resist_k=99 not clamped to 0.50: hull %.2f vs expected %.2f" % [hi[1], base[1] * 0.5])
	# Extreme weakness -> clamped to -0.40 -> hull ~ 1.4x baseline.
	seed(123)
	gs.enemy_inst = {"hp": 1000.0, "max_hp": 1000.0, "resist_k": -99.0}
	var lo: Array = gs.resolve_damage(500.0, 0.0, 0.0, 0.0, 0.0, 3, 0.0, true, 0.0, "cryo")
	if not approx(float(lo[1]), float(base[1]) * 1.4):
		E("resist_k=-99 not clamped to -0.40: hull %.2f vs expected %.2f" % [lo[1], base[1] * 1.4])
	gs.enemy_inst = {}

# --- Fleet multiplier: 1.0 when locked/empty; rises 0.25/ship; hard-capped at 2.0. ---
func _check_fleet_mult() -> void:
	var saved_warps: int = gs.total_warps
	var saved_ships: Array = gs.fleet_ships.duplicate()
	gs.total_warps = 0
	gs.fleet_ships = [{"hull_id": "fleet_frigate"}]
	if not approx(gs.fleet_combat_mult(), 1.0):
		E("fleet locked (0 warps) should give 1.0x, got %.3f" % gs.fleet_combat_mult())
	gs.total_warps = 10
	gs.fleet_ships = []
	if not approx(gs.fleet_combat_mult(), 1.0):
		E("empty fleet should give 1.0x, got %.3f" % gs.fleet_combat_mult())
	var prev := 0.0
	for n in range(1, 9):
		gs.fleet_ships = []
		for i in range(n): gs.fleet_ships.append({"hull_id": "fleet_frigate"})
		var m: float = gs.fleet_combat_mult()
		if m < prev - 0.0001:
			E("fleet mult non-monotone at %d ships: %.3f < %.3f" % [n, m, prev])
		if m > 2.0 + 0.0001:
			E("fleet mult exceeds 2.0 cap at %d ships: %.3f" % [n, m])
		prev = m
	gs.total_warps = saved_warps
	gs.fleet_ships = saved_ships

# --- DPS readout must be finite and non-negative for a fresh ship. ---
func _check_dps() -> void:
	var dps: float = gs.avg_player_dps()
	if dps < 0.0 or not is_finite(dps):
		E("avg_player_dps() returned %f (must be finite, >= 0)" % dps)

# --- Enemy stat sanity: positive HP, non-negative atk/xp, valid phase_cut. ---
func _check_enemy_stats() -> void:
	for eid in gd.ENEMIES:
		var e: Dictionary = gd.ENEMIES[eid]
		if float(e.get("hp", 0.0)) <= 0.0: E("ENEMY %s hp <= 0" % eid)
		if float(e.get("atk", 0.0)) < 0.0: E("ENEMY %s atk < 0" % eid)
		if int(e.get("xp", 0)) < 0: E("ENEMY %s xp < 0" % eid)
		var pc := float(e.get("phase_cut", 0.15))
		if (e.get("phases", []) as Array).size() > 1 and (pc <= 0.0 or pc > 1.0):
			E("ENEMY %s phase_cut %.3f out of (0,1]" % [eid, pc])

# --- Design integrity: every multi-phase boss must be breachable. Base elements
# (kinetic/energy/explosive) are always coverable; an exotic phase element needs a
# weapon module whose exotic channel matches it, or the boss is a soft-lock. ---
func _check_phase_breachability() -> void:
	var exotic_weapons := {}   # exotic_element -> mid
	for mid in gd.MODULES:
		var m: Dictionary = gd.MODULES[mid]
		if m.get("slot", "") != "weapon": continue
		var st: Dictionary = m.get("stats", {})
		if float(st.get("atk_cryo", 0.0)) > 0.0:
			var ex: String = String(st.get("exotic_element", m.get("exotic_type", "cryo")))
			exotic_weapons[ex] = mid
	var base := {"kinetic": true, "energy": true, "explosive": true}
	for eid in gd.ENEMIES:
		var phases: Array = gd.ENEMIES[eid].get("phases", [])
		if phases.size() <= 1: continue
		for elem in phases:
			var e: String = str(elem).to_lower()
			if base.has(e): continue
			if not exotic_weapons.has(e):
				E("BOSS %s phase '%s' has NO obtainable exotic weapon (soft-lock)" % [eid, e])
	# warp_hardened enemies require a cryo weapon to exist at all.
	for eid in gd.ENEMIES:
		if bool(gd.ENEMIES[eid].get("warp_hardened", false)) and not exotic_weapons.has("cryo"):
			E("WARP-HARDENED %s but no cryo weapon exists (soft-lock)" % eid)

func _weapon_module_count() -> int:
	var n := 0
	for mid in gd.MODULES:
		if gd.MODULES[mid].get("slot", "") == "weapon": n += 1
	return n
