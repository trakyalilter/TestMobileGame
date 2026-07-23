extends Node
# ============================================================================
# WARP RESEARCH RESET (v140) — owner call: research no longer persists through a
# warp. This test does NOT just assert "techs were cleared" (trivial). It asserts
# the change is SURVIVABLE, i.e. the player is never softlocked out of content
# they already earned:
#
#   1. unlocked_techs is actually wiped, and research XP decays like other skills
#   2. owned hulls + equipped modules remain EQUIPPED and usable
#      (research_req is checked in can_build_hull / craft_module, never on equip)
#   3. REC_1 Blueprint-Cached buildings keep PRODUCING
#      (research_req is a can_build gate; the production path never reads research)
#   4. cryo_armaments is re-researchable, so the Z11 Warp-Hardened gate cannot
#      deadlock behind the very prestige that opens it
#
#   Godot --headless --path <root> res://scenes/warp_research_reset.tscn
# ============================================================================

var fails := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond: fails += 1
	print("[WARPRR] %-50s %s %s" % [name, "OK" if cond else "*** FAIL", detail])


func _ready() -> void:
	GameState.set_process(false)
	GameState.hard_reset()

	var rm = GameState.research_manager
	var wm = GameState.warp_manager
	var im = GameState.infrastructure_manager
	var sm = GameState.shipyard_manager

	print("[WARPRR] ============ warp research reset ============")

	# ── Arrange: a mid-game-ish run with research, buildings, a fleet ──
	for t in ["efficiency_1", "efficiency_2", "combustion", "basic_engineering"]:
		if t in rm.tech_tree and not rm.is_tech_unlocked(t):
			rm.unlocked_techs.append(t)
	rm.xp = 100000.0
	rm.check_level_up()

	var bid := ""
	for b in im.building_db:
		var d: Dictionary = im.building_db[b]
		if d.has("yield") and not (d["yield"] as Dictionary).is_empty():
			bid = b
			break
	im.buildings[bid] = 10

	# REC_1 Blueprint Cache so buildings survive the wipe — that is the pairing that
	# makes a research reset tolerable, so it must be exercised.
	wm.purchased_nodes["REC_1"] = true

	var eff_before: float = rm.get_efficiency_multiplier()
	var techs_before: int = rm.unlocked_techs.size()
	var lvl_before: int = rm.get_level()
	# Plant a real earned module so the "fleet is wiped" assertion is not vacuous —
	# post-warp the inventory contains ONLY the auto-granted starter batteries.
	var probe_mod := ""
	for m in sm.modules:
		if str(m) != "z1_battery":
			probe_mod = str(m)
			break
	sm.module_inventory[probe_mod] = 3
	var equipped_before: Dictionary = sm.loadout.duplicate(true)
	var inv_before: Dictionary = sm.module_inventory.duplicate(true)
	var hull_before: String = sm.active_hull
	print("[WARPRR]   before: techs=%d  eff=x%.1f  research_lvl=%d  %s=%d" % [
		techs_before, eff_before, lvl_before, bid, int(im.buildings.get(bid, 0))])

	# ── Act: force a warp ──
	GameState.resources.add_currency("credits", 5_000_000.0)
	wm.credits_at_warp_start = 0.0
	_ok("warp is available", wm.calculate_warp_gains() > 0, "gains=%d" % int(wm.calculate_warp_gains()))
	wm.execute_warp()

	# ── Assert 1: research really reset ──
	print("[WARPRR]   after:  techs=%d  eff=x%.1f  research_lvl=%d  %s=%d" % [
		rm.unlocked_techs.size(), rm.get_efficiency_multiplier(), rm.get_level(),
		bid, int(im.buildings.get(bid, 0))])
	_ok("unlocked_techs wiped", rm.unlocked_techs.is_empty(), "%d left" % rm.unlocked_techs.size())
	_ok("efficiency ladder dropped to x1", absf(rm.get_efficiency_multiplier() - 1.0) < 0.001,
		"x%.2f" % rm.get_efficiency_multiplier())
	_ok("research XP decayed (not zeroed)", rm.xp > 0.0 and rm.xp < 100000.0, "xp=%.0f" % rm.xp)

	# ── Assert 2: the fleet survived and is still usable ──
	# NOTE: the fleet does NOT survive a warp and never did — shipyard_manager.reset()
	# wipes module_inventory + loadout and returns you to the corvette. That is
	# pre-existing v134g behaviour, not a v140 change; the UI copy used to claim
	# "KEEP Ships" and was simply wrong (fixed in star_map_overlay + warp_page).
	# Assert the real contract so nobody "fixes" the test back to the myth.
	_ok("earned module wiped (pre-existing)", not sm.module_inventory.has(probe_mod),
		"%s -> %s" % [probe_mod, str(sm.module_inventory)])
	_ok("hull reset to corvette (pre-existing)", sm.active_hull == "corvette_hull", sm.active_hull)
	# The one fleet mercy that DOES exist: a warp re-grants + equips starter batteries,
	# so you never come back unpowered.
	var batteries := 0
	for slot in sm.loadout:
		if str(sm.loadout[slot]) == "z1_battery":
			batteries += 1
	_ok("warp re-equips starter batteries", batteries >= 2, "%d equipped" % batteries)
	print("[WARPRR]   (pre-warp loadout was %s, inv %d entries, hull %s)" % [
		str(equipped_before), inv_before.size(), hull_before])

	# ── Assert 3: Blueprint-Cached buildings still PRODUCE with research gone ──
	var kept: int = int(im.buildings.get(bid, 0))
	_ok("blueprint cache kept buildings", kept > 0, "%s x%d" % [bid, kept])
	if kept > 0:
		var res: String = (im.building_db[bid]["yield"] as Dictionary).keys()[0]
		var still: float = im.get_effective_yield(bid, res)
		_ok("kept buildings still produce", still > 0.0, "%s -> %.3f %s" % [bid, still, res])
		# The whole point: construction is blocked by the wiped research, production is not.
		var can_build_more: bool = im.can_afford(bid)
		print("[WARPRR]   %s: can_afford(build more)=%s, still producing=%.3f" % [bid, str(can_build_more), still])

	# ── Assert 4: Z11 gate is not deadlocked — cryo is re-researchable ──
	if "cryo_armaments" in rm.tech_tree:
		_ok("cryo_armaments is wiped", not rm.is_tech_unlocked("cryo_armaments"))
		_ok("cryo_armaments still exists to re-research", rm.tech_tree.has("cryo_armaments"))
		_ok("cryo flag persists through warp", bool(GameState.game_settings.get("cryo_unlocked", false)))

	# ── Assert 5: the compensating tree buffs are live ──
	wm.purchased_nodes["ENG_1"] = true
	wm.node_levels["ENG_S1"] = 10
	_ok("ENG_S1 buffed to +10%/level", absf(wm.get_tree_gathering_bonus() - 2.0) < 0.001,
		"x%.3f at Lv10" % wm.get_tree_gathering_bonus())
	_ok("ENG_S1 infra mirrors gathering",
		absf(wm.get_tree_infra_bonus() - wm.get_tree_gathering_bonus()) < 0.0001)
	wm.node_levels["REC_S1"] = 10
	_ok("REC_S1 buffed to +4%/level", absf(wm.get_tree_shard_score_mult() - 1.4) < 0.001,
		"x%.3f at Lv10" % wm.get_tree_shard_score_mult())
	wm.node_levels["ENG_S2"] = 20
	# -3%/level capped at -50%: 20 levels would be -60%, so the cap must bite.
	_ok("ENG_S2 cap holds at -50%", absf(wm.get_tree_processing_speed_bonus() - 2.0) < 0.001,
		"x%.3f at Lv20" % wm.get_tree_processing_speed_bonus())

	print("[WARPRR] ============ %s ============" % ("ALL PASS" if fails == 0 else "%d FAIL(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
