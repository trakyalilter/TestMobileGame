extends Node
# ============================================================================
# NG+ LOOP-1 WARP-AWARE TUNE PROBE (v137 #35) — the z12_tune successor that models
# the WARP-BOOSTED player. Player combat damage = weapon × get_tree_damage_bonus()
# × get_combat_multiplier() where get_combat_multiplier = (1 + shards×0.03) × 2^(warps/5).
# z12_tune modeled NONE of this (hard_reset → 0 shards / 0 warps → ×1), so it under-
# read player damage ~2.6× at Z12 and ~8.6× at Z15. This probe sets the per-sector
# warp context (shards + total_warps + combat-tree nodes), fights each Corrosion-loop
# boss with the intended cryo/corrosion dual-preset auto-swapping across ALL phase
# bands (2 swaps on the 3-phase bosses), and sweeps HP to find ~75% Legendary win @
# ~10-12 min. Leviathan + Z10 armor/shield, no relic (first-clear = the hard case).
#   Godot --headless --path <root> res://scenes/ng_tune.tscn
# ============================================================================

const DT := 0.1
const MAXT := 1500.0
const TRIALS := 9
# {boss, zone, phases, shards, warps, cmb_s1, hp_candidates[]}. shards/warps estimate the
# state a player is in AT that sector (Z11 warp1 ~16 shards; ~+14/warp; tier every 5 warps).
const SECTORS := [
	{"boss": "z12_boss_rift_warden",        "zone": "the_rift",          "phases": ["cryo", "corrosion"],            "shards": 30, "warps": 2, "cmb_s1": 5, "hp": [28000000, 50000000, 70000000, 95000000]},
	{"boss": "z13_boss_verdigris_warden",   "zone": "the_verdigris",     "phases": ["corrosion", "cryo"],            "shards": 44, "warps": 3, "cmb_s1": 5, "hp": [48000000, 75000000, 100000000, 130000000]},
	{"boss": "z14_boss_dissolution_tyrant", "zone": "the_dissolution",   "phases": ["cryo", "corrosion", "cryo"],    "shards": 58, "warps": 4, "cmb_s1": 6, "hp": [82000000, 110000000, 145000000, 185000000]},
	{"boss": "z15_boss_caustic_sovereign",  "zone": "the_caustic_core",  "phases": ["corrosion", "cryo", "corrosion"],"shards": 72, "warps": 5, "cmb_s1": 7, "hp": [140000000, 220000000, 300000000, 400000000]},
]

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	var wm = GameState.warp_manager
	GameState.set_process(false)
	print("[NGTUNE] ============ NG+ Loop-1 warp-aware tune (Legendary, %d trials) ============" % TRIALS)
	print("[NGTUNE] target: ~75%% win @ ~10-12 min. combat_mult shown = (1+shards*0.03)*2^(warps/5).")
	for s in SECTORS:
		# combat mult preview (informational)
		wm.warp_shards = float(s["shards"]); wm.total_warps = int(s["warps"])
		var cmult: float = wm.get_combat_multiplier()
		print("[NGTUNE] ---- %s : shards=%d warps=%d -> combat×%.2f, tree_dmg×%.2f (%d phases) ----" % [
			String(s["boss"]), int(s["shards"]), int(s["warps"]), cmult, _tree_dmg(wm, int(s["cmb_s1"])), (s["phases"] as Array).size()])
		var r := _trials(sm, cm, rm, wm, s, 0.0, 3)
		print("[NGTUNE]   REAL fight (base x catch-up): %s" % _cell(r))
		# gate check: NO swap (all-cryo) must fail even with warp power
		var g := _trials(sm, cm, rm, wm, s, float(s["hp"][0]), 3, true)
		print("[NGTUNE]   [gate] no-swap all-cryo @%.0f: %s  (must LOSE)" % [float(s["hp"][0]), _cell(g)])
	print("[NGTUNE] ======================================================================")
	get_tree().quit(0)

func _tree_dmg(wm, cmb_s1: int) -> float:
	return 1.10 * (1.0 + 0.06 * float(cmb_s1))   # CMB_2 + CMB_S1 spine (matches get_tree_damage_bonus)

func _trials(sm, cm, rm, wm, s, hp_over, rarity, no_swap := false) -> Dictionary:
	var wins := 0
	var ttks := []
	var worst := 100.0
	for _i in range(TRIALS):
		var r := _fight(sm, cm, rm, wm, s, float(hp_over), int(rarity), bool(no_swap))
		if String(r.get("r", "")) == "WIN":
			wins += 1; ttks.append(float(r.get("ttk", 0)))
		elif String(r.get("r", "")) in ["UNPWR", "NOENT"]:
			return {"w": 0, "k": TRIALS, "err": String(r.get("r"))}
		else:
			worst = minf(worst, float(r.get("bpct", 100.0)))
	ttks.sort()
	return {"w": wins, "k": TRIALS, "ttk": (float(ttks[ttks.size() / 2]) if ttks.size() > 0 else 0.0), "left": worst}

func _cell(r) -> String:
	if r.has("err"): return String(r["err"])
	var w := int(r.get("w", 0))
	if w > 0: return "%d/%d W%.0fs (%.1fmin)" % [w, int(r.get("k", TRIALS)), float(r.get("ttk", 0)), float(r.get("ttk", 0)) / 60.0]
	return "%d/%d L%.0f%%left" % [w, int(r.get("k", TRIALS)), float(r.get("left", 100))]

func _fight(sm, cm, rm, wm, s, hp_over, rarity, no_swap) -> Dictionary:
	GameState.hard_reset()
	cm.boss_kills.clear(); cm.total_kills = 0
	# --- WARP CONTEXT: what makes this the warp-aware tune ---
	wm.warp_shards = float(s["shards"])
	wm.total_warps = int(s["warps"])
	wm.warp_shards_spent = 0.0
	wm.purchased_nodes = {"CMB_1": true, "CMB_2": true}   # +15% hull, +10% weapon
	wm.node_levels = {"CMB_S1": int(s["cmb_s1"])}         # +6%/level weapon spine
	# --- unlocks + gear (mirror z12_tune) ---
	GameState.game_settings["cryo_unlocked"] = true
	GameState.game_settings["z11_unlocked"] = true
	for f in ["z12_unlocked", "z13_unlocked", "z14_unlocked", "z15_unlocked"]:
		GameState.game_settings[f] = true
	for t in ["cryo_armaments", "corrosion_armaments"]:
		if not (t in rm.unlocked_techs): rm.unlocked_techs.append(t)
	_unlock_research(rm, 15)
	_set_hull(sm, 10)
	_fill(sm, "battery", "z10_battery", 3, 10)
	_fill(sm, "armor", "z10_armor", rarity, 10)
	_fill(sm, "shield", "z10_shield", rarity, 10)
	_equip_exotic(sm, "cryo_lance", rarity)   # start on cryo
	_kits(sm)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	if sm.energy_used > sm.energy_capacity: return {"r": "UNPWR"}
	cm.start_expedition(String(s["zone"]))
	cm.set_target_enemy(String(s["boss"]))
	if cm.current_enemy == null or String(cm.current_enemy.get("id", "")) != String(s["boss"]):
		return {"r": "NOENT"}
	# v137 #35 final: NO override — fight the real base x warp-catch-up HP
	var phases: Array = s["phases"]
	var n: int = phases.size()
	var cur := "cryo"
	var t := 0.0
	while t < MAXT:
		if not no_swap:
			var band: int = cm._phase_index(n)
			var need: String = String(phases[band])
			if need != cur:
				_equip_exotic(sm, "cryo_lance" if need == "cryo" else "corrosion_blaster", rarity)
				sm.recalc_stats(); cm._rebuild_player_weapon_states()
				cur = need
		_kit(sm, cm)
		cm.process_tick(DT)
		t += DT
		if int(cm.boss_kills.get(String(s["boss"]), 0)) > 0:
			return {"r": "WIN", "ttk": t}
		if sm.current_hp <= 0 or not cm.in_combat:
			return {"r": "LOSS", "bpct": 100.0 * float(cm.enemy_hp) / maxf(1.0, float(cm.enemy_max_hp))}
	return {"r": "TIME", "bpct": 100.0 * float(cm.enemy_hp) / maxf(1.0, float(cm.enemy_max_hp))}

func _equip_exotic(sm, base_id: String, rarity: int) -> void:
	for i in _slots(sm, "weapon"):
		var cid := String(sm.generate_module_drop(base_id, rarity, 12))
		if cid != "": sm.equip_module(i, cid, true)

func _unlock_research(rm, n) -> void:
	for tid in rm.tech_tree:
		if int(rm.tech_tree[tid].get("tier", 99)) <= n and not (tid in rm.unlocked_techs):
			rm.unlocked_techs.append(tid)

func _set_hull(sm, n) -> void:
	var want := clampi(n, 1, 10)
	var hid := ""
	for h in sm.hulls:
		if int(sm.hulls[h].get("tier", 0)) == want: hid = String(h); break
	if hid == "": hid = "leviathan_hull"
	sm.active_hull = hid
	sm.loadout.clear(); sm.ammo_loadout.clear()
	sm.consumable_hull_slot = ""; sm.consumable_shield_slot = ""

func _slots(sm, stype) -> Array:
	var out := []
	var slots: Array = sm.hulls.get(sm.active_hull, {}).get("slots", [])
	for i in range(slots.size()):
		if String(slots[i]) == stype: out.append(i)
	return out

func _fill(sm, stype, base_id, rarity, zone) -> void:
	if not (base_id in sm.modules): return
	for i in _slots(sm, stype):
		var cid := String(sm.generate_module_drop(base_id, rarity, zone))
		if cid != "": sm.equip_module(i, cid, true)

func _kits(sm) -> void:
	GameState.resources.add_element("AdvMaintenanceKit", 100000)
	GameState.resources.add_element("ZeroPoint", 100000)
	sm.equip_consumable("hull", "AdvMaintenanceKit")
	sm.equip_consumable("shield", "ZeroPoint")

func _kit(sm, cm) -> void:
	if cm.consumable_cooldown > 0.0: return
	if sm.current_hp < sm.max_hp * 0.5 and sm.consumable_hull_slot != "":
		cm.use_manual_consumable("hull")
	elif cm.player_max_shield > 0 and cm.player_shield < cm.player_max_shield * 0.5 and sm.consumable_shield_slot != "":
		cm.use_manual_consumable("shield")
