extends Node
# ============================================================================
# Z10 BOSS vs WARP COUNT — how hard is the Leviathan at warp 0,1,2,...?
#
# Question: "how many attempts to kill the Zone 10 boss at each warp, with shard
# bonuses spent?" Combat here is near-deterministic (no crit RNG on the main
# damage path), so "attempts" is really a WIN RATE: if the loadout+multipliers
# clear the DPS/EHP bar you win every time, if not you never win. This reports
# wins/TRIALS and median TTK, and converts win rate to expected attempts.
#
# Two power sources scale with warping, and they are NOT the same thing:
#   1. GLOBAL   get_combat_multiplier() = (1 + shards*0.03) * 2^warp_tier
#              — passive, applies whether or not you spend a single shard.
#   2. TREE     CMB_1/2/3/4 + CMB_S1 spine — only if you SPEND.
# Columns are reported for both so the tree's real contribution is visible
# instead of being hidden inside the global curve.
#
# Shard budget is not invented: each warp's gain is read from the live
# calculate_warp_gains() with lifetime_credits set to an end-of-Z10 run, then
# accumulated, so the spend budget matches what a real player would hold.
#
#   Godot --headless --path <root> res://scenes/z10_warp_scaling.tscn
# ============================================================================

const DT := 0.1
const MAXT := 1000.0     # Z10 boss is tuned to ~13 min for tier-matched legendary
const TRIALS := 5
const BOSS := "z10_boss_leviathan"
const ZONE := "sector_epsilon"
const HULL := "dreadnought_hull"
const GEAR_N := 10
const SUFFIX := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}
const AMMO := {"kinetic": "Slug", "energy": "Cell", "explosive": "Missile"}

# Credits a player is holding when they finish a Z10 run. Drives the shard gain.
const END_OF_RUN_CREDITS := 2.0e10

const WARPS := [0, 1, 2, 3, 4, 5, 6, 8, 10]
# 1 = uncommon, 2 = rare, 3 = legendary
const GEAR_TIERS := [{"r": 1, "tag": "UNCOMMON"}, {"r": 2, "tag": "RARE"}]


func _weak(e: Dictionary) -> String:
	var rk := float(e.get("resist_k", 0.0))
	var re := float(e.get("resist_e", 0.0))
	var rx := float(e.get("resist_x", 0.0))
	var m: float = min(rk, min(re, rx))
	if m == rx: return "explosive"
	if m == re: return "energy"
	return "kinetic"


# Replay the real shard formula warp-by-warp so the budget is the game's, not mine.
func _cumulative_shards(wm, n: int) -> float:
	var shards := 0.0
	for w in range(n):
		wm.total_warps = w
		wm.warp_shards = shards
		wm.warp_shards_spent = 0.0
		wm.credits_at_warp_start = 0.0
		GameState.resources.lifetime_credits = END_OF_RUN_CREDITS
		shards += float(wm.calculate_warp_gains())
	return shards


# Greedy spend, boss-killing priority. Branch reveal is honoured by the manager
# (Engineering opens at warp 1, Combat + Recursion only at warp 2) — which is why
# warp 1 buys nothing that helps a fight.
func _spend(wm) -> Dictionary:
	var order := ["CMB_1", "CMB_2", "CMB_3", "CMB_4"]
	var bought := {}
	for nid in order:
		if wm.can_purchase_node(nid):
			wm.purchase_node(nid)
			bought[nid] = 1
	# Dump the remainder into the repeatable damage spine, then engineering spine.
	for spine in ["CMB_S1", "ENG_1", "ENG_S1"]:
		var guard := 0
		while wm.can_purchase_node(spine) and guard < 200:
			wm.purchase_node(spine)
			bought[spine] = int(bought.get(spine, 0)) + 1
			guard += 1
	return bought


func _slots(sm, stype: String) -> Array:
	var out := []
	var slots: Array = sm.hulls.get(sm.active_hull, {}).get("slots", [])
	for i in range(slots.size()):
		if String(slots[i]) == stype:
			out.append(i)
	return out


func _equip(sm, weak: String, rarity: int) -> void:
	sm.active_hull = HULL
	sm.loadout.clear()
	sm.ammo_loadout.clear()
	sm.consumable_hull_slot = ""
	sm.consumable_shield_slot = ""
	# Batteries over-provisioned so power is never the variable under test.
	for i in _slots(sm, "battery"):
		if "z10_battery" in sm.modules:
			var b := String(sm.generate_module_drop("z10_battery", 3, GEAR_N))
			if b != "": sm.equip_module(i, b, true)
	for stype in ["armor", "shield"]:
		var did := "z%d_%s" % [GEAR_N, stype]
		for i in _slots(sm, stype):
			if did in sm.modules:
				var cid := String(sm.generate_module_drop(did, rarity, GEAR_N))
				if cid != "": sm.equip_module(i, cid, true)
	var wbase := "z%d_%s" % [GEAR_N, SUFFIX[weak]]
	for i in _slots(sm, "weapon"):
		if wbase in sm.modules:
			var cid2 := String(sm.generate_module_drop(wbase, rarity, GEAR_N))
			if cid2 != "": sm.equip_module(i, cid2, true)
	var ammo := "%sT4" % AMMO[weak]
	if not ElementDB.ELEMENT_NAMES.has(ammo):
		ammo = "%sT1" % AMMO[weak]
	GameState.resources.add_element(ammo, 100000000)
	for i in _slots(sm, "weapon"):
		sm.ammo_loadout[i] = ammo
	GameState.resources.add_element("EmergencyPatch", 1000000)
	GameState.resources.add_element("BasicBooster", 1000000)
	sm.equip_consumable("hull", "EmergencyPatch")
	sm.equip_consumable("shield", "BasicBooster")


func _kit(sm, cm) -> void:
	if cm.consumable_cooldown > 0.0:
		return
	if sm.current_hp < sm.max_hp * 0.5 and sm.consumable_hull_slot != "":
		cm.use_manual_consumable("hull")
	elif cm.player_max_shield > 0 and cm.player_shield < cm.player_max_shield * 0.5 and sm.consumable_shield_slot != "":
		cm.use_manual_consumable("shield")


func _fight(sm, cm, rm, wm, warps: int, rarity: int, weak: String, spend: bool) -> Dictionary:
	GameState.hard_reset()
	cm.boss_kills.clear()
	cm.total_kills = 0
	for tid in rm.tech_tree:
		if not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)      # gear/zone access is not what we measure
	var shards := _cumulative_shards(wm, warps)
	wm.total_warps = warps
	wm.warp_shards = shards
	wm.warp_shards_spent = 0.0
	wm.purchased_nodes.clear()
	wm.node_levels.clear()
	var bought := {}
	if spend:
		bought = _spend(wm)
	_equip(sm, weak, rarity)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	if sm.energy_used > sm.energy_capacity:
		return {"r": "UNPOWERED"}
	cm.start_expedition(ZONE)
	cm.set_target_enemy(BOSS)
	if cm.current_enemy == null or String(cm.current_enemy.get("id", "")) != BOSS:
		return {"r": "NOENTRY"}
	var t := 0.0
	while t < MAXT:
		_kit(sm, cm)
		cm.process_tick(DT)
		t += DT
		if int(cm.boss_kills.get(BOSS, 0)) > 0:
			return {"r": "WIN", "ttk": t, "shards": shards, "bought": bought}
		if sm.current_hp <= 0 or not cm.in_combat:
			return {"r": "LOSS", "ttk": t, "shards": shards, "bought": bought,
				"left": 100.0 * float(cm.enemy_hp) / maxf(1.0, float(cm.enemy_max_hp))}
	return {"r": "TIME", "ttk": MAXT, "shards": shards, "bought": bought,
		"left": 100.0 * float(cm.enemy_hp) / maxf(1.0, float(cm.enemy_max_hp))}


func _trials(sm, cm, rm, wm, warps: int, rarity: int, weak: String, spend: bool) -> Dictionary:
	var wins := 0
	var ttks := []
	var worst := 100.0
	var shards := 0.0
	var bought := {}
	for _i in range(TRIALS):
		var r := _fight(sm, cm, rm, wm, warps, rarity, weak, spend)
		shards = float(r.get("shards", 0.0))
		bought = r.get("bought", {})
		if String(r.get("r", "")) == "WIN":
			wins += 1
			ttks.append(float(r.get("ttk", 0.0)))
		else:
			worst = minf(worst, float(r.get("left", 100.0)))
	ttks.sort()
	var med: float = float(ttks[ttks.size() / 2]) if ttks.size() > 0 else 0.0
	return {"w": wins, "ttk": med, "left": worst, "shards": shards, "bought": bought}


func _cell(r: Dictionary) -> String:
	var w := int(r.get("w", 0))
	if w == 0:
		return "%d/%d  never      (%.0f%% hp left)" % [w, TRIALS, float(r.get("left", 100.0))]
	var att := float(TRIALS) / float(w)
	return "%d/%d  ~%.1f tries  (ttk %.0fs = %.1f min)" % [
		w, TRIALS, att, float(r.get("ttk", 0.0)), float(r.get("ttk", 0.0)) / 60.0]


func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	var wm = GameState.warp_manager
	GameState.set_process(false)

	var boss: Dictionary = cm.enemy_db.get(BOSS, {})
	var weak := _weak(boss)
	print("[Z10W] ================================================================")
	print("[Z10W] Z10 LEVIATHAN vs WARP COUNT   hull=%s  gear=Z%d  weak=%s" % [HULL, GEAR_N, weak])
	print("[Z10W] boss hp=%s  atk=%s  resist k/e/x = %.2f/%.2f/%.2f" % [
		str(boss.get("hp", 0)), str(boss.get("attack", 0)),
		float(boss.get("resist_k", 0.0)), float(boss.get("resist_e", 0.0)), float(boss.get("resist_x", 0.0))])
	print("[Z10W] %d trials/cell, sim cap %.0fs" % [TRIALS, MAXT])

	for g in GEAR_TIERS:
		var rarity := int(g["r"])
		print("[Z10W] ----------------------------------------------------------------")
		print("[Z10W] GEAR = all-%s Z10" % String(g["tag"]))
		print("[Z10W]  warp  shards  globalx   SPENT on tree                    UNSPENT")
		for warps in WARPS:
			var sp := _trials(sm, cm, rm, wm, warps, rarity, weak, true)
			var un := _trials(sm, cm, rm, wm, warps, rarity, weak, false)
			# Recompute the global multiplier for display at this warp count.
			wm.total_warps = warps
			wm.warp_shards = float(sp.get("shards", 0.0))
			# `wm` is an untyped manager ref, so `:=` can't infer a return type
			# off it (CLAUDE.md gotcha). Declare explicitly.
			var gmul: float = wm.get_combat_multiplier()
			print("[Z10W]  %4d  %6.0f  %7.1fx  %-32s %s" % [
				warps, float(sp.get("shards", 0.0)), gmul, _cell(sp), _cell(un)])
			var b: Dictionary = sp.get("bought", {})
			if not b.is_empty():
				print("[Z10W]        bought: %s" % str(b))
	print("[Z10W] ================================================================")
	get_tree().quit()
