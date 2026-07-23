extends Node
# ============================================================================
# EARLY INFRASTRUCTURE BOOTSTRAP (v141) — can the player actually stand up the
# first two extractors during Zone 1, and does it cost the intended ~30 minutes
# of manual play plus a second boss kill?
#
# The design target (owner): by the time Z1's boss is dead, the player should be
# holding ~1 auto_excavator + ~1 industrial_pump. Buildings must feel EARNED, not
# free — but the earning must be progression (boss cores), not a dirt grind.
#
# Why it was broken: auto_excavator cost 250,000 Liras + Si 2500 + Fe 1000. At
# early income that is ~17-25 HOURS for the single most basic building in the
# game, while a tier-3 auto_smelter cost 6,250. The bottom of the cost curve was
# inverted, so nobody ever automated Dirt and the Infrastructure page was dead
# weight through the entire early game.
#
#   Godot --headless --path <root> res://scenes/infra_bootstrap_check.tscn
# ============================================================================

# Measured rates (gathering_manager / processing_manager), single active task:
#   gather_dirt     20 Dirt  / 3.0s
#   collect_water   20 Water / 3.0s
#   centrifuge_dirt 5 Dirt + 5 Water -> 5 Fe + 3 Si / 3.0s
# One craft therefore costs 3.0s craft + 0.75s dirt + 0.75s water = 4.5s.
const CRAFT_SECONDS := 4.5
const FE_PER_CRAFT := 5.0
const SI_PER_CRAFT := 3.0

var fails := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond: fails += 1
	print("[INFRA0] %-46s %s %s" % [name, "OK" if cond else "*** FAIL", detail])


# Minutes of single-active-task play to produce a cost's Fe+Si via centrifuge.
func _manual_minutes(cost: Dictionary) -> float:
	var fe := float(cost.get("Fe", 0))
	var si := float(cost.get("Si", 0))
	# Both come from the same craft, so the binding constraint sets the time.
	var crafts: float = max(fe / FE_PER_CRAFT, si / SI_PER_CRAFT)
	return crafts * CRAFT_SECONDS / 60.0


func _ready() -> void:
	GameState.set_process(false)
	GameState.hard_reset()
	var im = GameState.infrastructure_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager

	print("[INFRA0] ============ early infra bootstrap ============")

	# ── 1. Z1 boss pays 2 cores per kill ──
	var boss: Dictionary = cm.enemy_db.get("z1_boss_architect", {})
	_ok("Z1 boss grants 2 cores", int(boss.get("boss_core_qty", 1)) == 2,
		"qty=%d" % int(boss.get("boss_core_qty", 1)))

	# ── 2. Zone-2 gate still costs ONE kill (2 cores) ──
	var z2: Dictionary = rm.tech_tree.get("zone_2_access", {})
	var z2_cores: int = int((z2.get("cost_items", {}) as Dictionary).get("Z1_Core", 0))
	_ok("zone_2_access costs 2 cores", z2_cores == 2, "%d" % z2_cores)
	_ok("zone_2 still = 1 boss kill", z2_cores <= int(boss.get("boss_core_qty", 1)),
		"%d cores vs %d/kill" % [z2_cores, int(boss.get("boss_core_qty", 1))])

	# ── 3. Starter buildings: core-gated + ~30 min of manual materials ──
	for bid in ["auto_excavator", "industrial_pump"]:
		var c: Dictionary = im.building_db[bid]["cost"]
		var mins: float = _manual_minutes(c)
		var cores: int = int(c.get("Z1_Core", 0))
		print("[INFRA0]   %s -> %s   (~%.0f dk manuel)" % [bid, str(c), mins])
		_ok("%s core-gated" % bid, cores == 2, "Z1_Core=%d" % cores)
		_ok("%s ~30min materials" % bid, mins >= 20.0 and mins <= 45.0, "%.1f dk" % mins)
		_ok("%s liras sane" % bid, float(c.get("credits", 0)) <= 25000.0,
			"%.0f L" % float(c.get("credits", 0)))
		# Fe:Si must sit on the craft's own 5:3 ratio or the player overshoots one.
		var ratio: float = float(c.get("Fe", 0)) / maxf(float(c.get("Si", 1)), 1.0)
		_ok("%s Fe:Si on 5:3 ratio" % bid, absf(ratio - 5.0 / 3.0) < 0.02, "%.3f" % ratio)

	# ── 4. The whole Z1 story: 2 kills funds zone-2 research AND one building ──
	var per_kill: int = int(boss.get("boss_core_qty", 1))
	var got: int = per_kill * 2
	var need: int = z2_cores + int(im.building_db["auto_excavator"]["cost"].get("Z1_Core", 0))
	print("[INFRA0]   2 boss kill = %d core;  zone2(%d) + 1 bina(%d) = %d" % [
		got, z2_cores, need - z2_cores, need])
	_ok("2 kills fund research + 1 building", got >= need, "%d >= %d" % [got, need])

	# ── 5. The old pricing must never come back ──
	var exc: Dictionary = im.building_db["auto_excavator"]["cost"]
	_ok("no 250k-Lira dirt building", float(exc.get("credits", 0)) < 100000.0)
	_ok("dirt building cheaper than auto_smelter tier",
		float(exc.get("credits", 0)) < 250000.0)

	# ── 6. Yield untouched: a steady trickle, not a flood ──
	var dirt: float = float(im.building_db["auto_excavator"]["yield"].get("Dirt", 0))
	var iv: float = float(im.building_db["auto_excavator"].get("interval", 5.0))
	print("[INFRA0]   auto_excavator uretim = %.2f Dirt/s (manuel 6.67 Dirt/s)" % (dirt / iv))
	_ok("yield stays a trickle (<3/s)", dirt / iv < 3.0, "%.2f/s" % (dirt / iv))

	# ── 7. Online and offline must pay the SAME cores ──
	# The offline sweep used to add a flat 1-per-kill regardless of boss_core_qty,
	# so parking on the Z1 boss overnight paid half what killing it live did.
	var src: String = FileAccess.get_file_as_string("res://scripts/managers/combat_manager.gd")
	_ok("offline core award honours qty", src.contains("boss_core_qty\", 1)) * num_kills"),
		"offline path multiplies by qty")

	# ── 8. UI must show the SAME requirement the logic enforces ──
	# MATERIAL_MULTIPLIER (x2) applies to normal materials but NOT to boss cores
	# (v104/v135b exemption). Three UI sites re-implemented the formula locally and
	# so displayed 2x for any zone gate: "Z1_Core: 2" rendered as 4 while
	# can_unlock() wanted 2. Assert the exemption directly.
	_ok("core exempt from MATERIAL_MULTIPLIER",
		rm._effective_item_requirement("Z1_Core", 2) == 2,
		"= %d" % rm._effective_item_requirement("Z1_Core", 2))
	_ok("normal material still doubled",
		rm._effective_item_requirement("Fe", 40) == int(40 * rm.MATERIAL_MULTIPLIER),
		"Fe 40 -> %d" % rm._effective_item_requirement("Fe", 40))
	for f in ["scripts/ui/research_detail_modal.gd", "scripts/ui/research_node_widget.gd", "scripts/ui/atlas_page.gd"]:
		var txt: String = FileAccess.get_file_as_string("res://" + f)
		_ok("no local mult in %s" % f.get_file(),
			not txt.contains("* manager.MATERIAL_MULTIPLIER") and not txt.contains("* float(_manager.MATERIAL_MULTIPLIER)"))

	print("[INFRA0] ============ %s ============" % ("ALL PASS" if fails == 0 else "%d FAIL(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
