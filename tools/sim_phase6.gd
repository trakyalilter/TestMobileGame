extends SceneTree
## Phase 6 verification: affix/rarity system + combat-loot economy.
## Runs all hard-gate checks (loot mult, affixes, rarity ranges, boss multi-roll,
## sell values) and a combat regression. PASS/FAIL printed per check.

var _pass := 0
var _fail := 0

func _ck(name: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else: _fail += 1
	print("[%s] %s%s" % ["PASS" if ok else "FAIL", name, ("  " + detail) if detail != "" else ""])

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var gs = root.get_node("GameState")
	var GD = root.get_node("GameData")
	gs.hard_reset()

	# --- Gate 7: Sell values match desktop ---
	_ck("sell values", gs.RARITY_SELL[0] == 100 and gs.RARITY_SELL[1] == 750 \
		and gs.RARITY_SELL[2] == 5000 and gs.RARITY_SELL[3] == 30000 and gs.RARITY_SELL[4] == 100000,
		str(gs.RARITY_SELL))

	# --- Gate 3: Loot mult ~1 at base, >5 with high level/zone/efficiency/warp ---
	gs.active_id = "z1_lunar_drone"   # difficulty 1
	var base_mult: float = gs.get_combat_loot_multiplier()
	# Desktop adds level*0.01, so a level-1 fresh game = 1.01 (no zone/research/warp).
	_ck("loot mult base ~1", base_mult < 1.05, "got %.3f" % base_mult)

	gs.skills["combat"] = gs.xp_for_level(50)   # combat level 50
	gs.unlocked_research["efficiency_5"] = true
	gs.warp_shards = 20.0
	gs.total_warps = 10                          # warp_tier 2
	gs.active_id = "z10_boss_leviathan"  # difficulty 10
	var hi_mult: float = gs.get_combat_loot_multiplier()
	_ck("loot mult high >5", hi_mult > 5.0, "got %.1f" % hi_mult)
	# reset
	gs.hard_reset()

	# --- Gate 5: Legendary rolled stat multiplier in [2.0,2.8]x base ---
	# Pick a base module with a clear boostable stat and roll Legendary at zone 1
	# (zone mult = 1.0) so the multiplier is the pure rarity factor.
	var base_id := "z1_armor"
	var base_def: Dictionary = GD.MODULES.get(base_id, {})
	var base_hp := float(base_def.get("stats", {}).get("hp", 0))
	var range_ok := true
	var min_seen := 99.0
	var max_seen := 0.0
	for i in 30:
		var cid: String = gs.generate_module(base_id, 3, 1)  # Legendary, zone 1
		var rolled := float(gs.custom_modules[cid].get("stats", {}).get("hp", 0))
		var factor := rolled / maxf(1.0, base_hp)
		min_seen = minf(min_seen, factor)
		max_seen = maxf(max_seen, factor)
		# allow tiny snapping slack
		if factor < 2.95 or factor > 3.85:  # base 1.0 + [2.0,2.8]
			range_ok = false
		gs.custom_modules.erase(cid)
		gs.module_inventory.erase(cid)
	_ck("legendary stat range [3.0,3.8]x", range_ok, "factors %.2f..%.2f" % [min_seen, max_seen])

	# --- Gate 4: Legendary in high zone has 3 affixes, flat scaling, occasional GA ---
	gs.unlocked_research["zone_10_access"] = true
	var hi_zone := 8
	var weapon_base := "z8_void_stalker_w" # may not exist; pick a real weapon
	# find a real weapon base id
	weapon_base = ""
	for mid in GD.MODULES:
		if GD.MODULES[mid].get("slot", "") == "weapon":
			weapon_base = mid
			break
	var saw_three := false
	var saw_flat_scaled := false
	var saw_greater := false
	var saw_nonzero_keys := {"lucky_hit_chance": false, "vuln_on_hit": false, "dmg_healthy": false, "dmg_injured": false}
	for i in 60:
		var cid: String = gs.generate_module(weapon_base, 3, hi_zone)  # Legendary z8
		var cm: Dictionary = gs.custom_modules[cid]
		var aff: Dictionary = cm.get("affixes", {})
		if aff.size() == 3:
			saw_three = true
		# flat-scaling affixes (flat_atk on weapon) should be >= the unscaled range
		# floor(2 * 1.8^7) for zone 8 — i.e. far above the raw 2..5.
		for ak in aff:
			var cfg: Dictionary = gs.AFFIX_DB[ak]
			if cfg.get("scaling", "") == "flat" and float(aff[ak]) > float(cfg["range"][1]):
				saw_flat_scaled = true
			if ak in saw_nonzero_keys and float(aff[ak]) > 0.0:
				saw_nonzero_keys[ak] = true
		if not cm.get("greater_affixes", []).is_empty():
			saw_greater = true
		gs.custom_modules.erase(cid)
		gs.module_inventory.erase(cid)
	_ck("legendary has 3 affixes", saw_three)
	_ck("flat affix scaled by zone", saw_flat_scaled)
	_ck("greater affix occurs", saw_greater)
	# The 4 previously-undefined keys can now source nonzero values from a weapon roll.
	var keys_ok: bool = saw_nonzero_keys["lucky_hit_chance"] and saw_nonzero_keys["vuln_on_hit"] \
		and saw_nonzero_keys["dmg_healthy"] and saw_nonzero_keys["dmg_injured"]
	_ck("lucky/vuln/dmg_healthy/dmg_injured source nonzero", keys_ok, str(saw_nonzero_keys))

	# --- Gate 4b: flat_hp / flat_def affix raises ship_stats when equipped ---
	gs.hard_reset()
	for mid in ["z1_battery", "z1_kinetic", "z1_armor"]:
		gs.module_inventory[mid] = int(gs.module_inventory.get(mid, 0)) + 1
		gs.equip_module(mid)
	var base_stats: Dictionary = gs.ship_stats()
	# craft a custom armor that definitely has flat_hp + flat_def by forcing affixes
	var cid_armor: String = gs.generate_module("z1_armor", 3, 1)
	var cm_armor: Dictionary = gs.custom_modules[cid_armor]
	cm_armor["affixes"] = {"flat_hp": 500.0, "flat_def": 50.0}
	# replace an equipped armor slot with this custom one
	var armor_slot := ""
	for k in gs.loadout:
		if gs.module_def(gs.loadout[k]).get("slot", "") == "armor":
			armor_slot = str(k)
			break
	if armor_slot != "":
		gs.loadout[armor_slot] = cid_armor
	var aff_stats: Dictionary = gs.ship_stats()
	_ck("flat_hp/flat_def affix raises ship_stats",
		float(aff_stats.get("hp", 0)) > float(base_stats.get("hp", 0)) + 400.0 \
		and float(aff_stats.get("def", 0)) > float(base_stats.get("def", 0)) + 40.0,
		"hp %.0f->%.0f def %.0f->%.0f" % [float(base_stats.hp), float(aff_stats.hp), float(base_stats.def), float(aff_stats.def)])

	# --- Gate 6: Boss multi-roll yields >1 module drop attempt ---
	gs.hard_reset()
	# unlock all zone access so boss drop pool is fully unlocked
	for rid in ["zone_2_access","zone_3_access"]:
		gs.unlocked_research[rid] = true
	# count generated custom modules before/after a boss kill
	var before: int = gs.custom_modules.size()
	# build a fake boss enemy_inst with a drop pool
	gs.active_id = "z1_boss_architect"
	gs.start_task("combat", "z1_boss_architect")
	# ensure is_boss + a populated unlocked pool
	gs.enemy_inst["is_boss"] = true
	if (gs.enemy_inst.get("drop_pool", []) as Array).is_empty():
		gs.enemy_inst["drop_pool"] = ["z1_kinetic", "z1_shield", "z1_armor"]
	gs.enemy_inst["hp"] = 0.0
	gs._win_combat()
	var after: int = gs.custom_modules.size()
	# bosses drop 4-10 modules but some may be Common (no custom id). Assert the
	# rare_loot drop bypassed the gate by checking we got multiple custom drops
	# across a few attempts, OR re-run if RNG gave all-common.
	var dropped := after - before
	if dropped <= 1:
		# retry a few times to dodge unlucky all-Common rolls
		for attempt in 5:
			gs.start_task("combat", "z1_boss_architect")
			gs.enemy_inst["is_boss"] = true
			if (gs.enemy_inst.get("drop_pool", []) as Array).is_empty():
				gs.enemy_inst["drop_pool"] = ["z1_kinetic", "z1_shield", "z1_armor"]
			gs.enemy_inst["hp"] = 0.0
			var b2: int = gs.custom_modules.size()
			gs._win_combat()
			dropped = gs.custom_modules.size() - b2
			if dropped > 1: break
	_ck("boss multi-roll >1 module", dropped > 1, "dropped %d custom modules" % dropped)

	# --- Gate 2: Combat regression — basic z1 loadout kills the drone, survives ---
	gs.hard_reset()
	for mid in ["z1_battery", "z1_kinetic", "z1_energy", "z1_shield", "z1_engine"]:
		gs.module_inventory[mid] = int(gs.module_inventory.get(mid, 0)) + 1
		gs.equip_module(mid)
	gs.add_resource("SlugT1", 9999)
	gs.add_resource("CellT1", 9999)
	for k in gs.loadout:
		var wm: Dictionary = gs.module_def(gs.loadout[k])
		if wm.get("slot", "") == "weapon":
			var wst: Dictionary = wm.get("stats", {})
			if float(wst.get("atk_kinetic", 0)) > 0: gs.set_ammo(str(k), "SlugT1")
			elif float(wst.get("atk_energy", 0)) > 0: gs.set_ammo(str(k), "CellT1")
	gs.start_task("combat", "z1_lunar_drone")
	var t := 0.0
	var prev_hp := float(gs.enemy_inst.get("hp", 0))
	var killed := false
	while t < 120.0:
		gs._tick_combat(0.1)
		t += 0.1
		if gs.active_type != "combat":
			break
		var ehp := float(gs.enemy_inst.get("hp", 0))
		if ehp > prev_hp + 1.0:
			killed = true
			break
		prev_hp = ehp
	_ck("combat regression (drone killed, survived)", killed and gs.combat_hp > 0.0,
		"kill_time=%.1fs hp=%.0f/%.0f" % [t, gs.combat_hp, gs.combat_max_hp()])

	print("=== Phase 6: %d PASS / %d FAIL ===" % [_pass, _fail])
	quit()
