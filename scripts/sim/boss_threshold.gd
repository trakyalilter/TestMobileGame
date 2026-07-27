extends Node
# ============================================================================
# BOSS THRESHOLD PROBE — finds the MINIMUM rare weak-type weapon count that
# beats each MANDATORY story boss with the MISSION-PROVIDED hull + kits.
#
# boss_gearcheck.gd only tests FULL rarity tiers (all-common / all-rare). That
# proves "Common loses, Rare wins" but NOT how many rare pieces a player farming
# up actually needs. This probe tests the realistic MIX: a common base loadout,
# then swap in K rare weak-type weapons one at a time (K = 0..weapon_slots), with
# repair kits. The min K that wins (>=3/5) = how many rare drops the FUNNEL must
# deliver, coach for, and bound the farm to.
#
#   Godot --headless --path <root> res://scenes/boss_threshold.tscn
# ============================================================================
const DT := 0.1
const MAXT := 300.0
# v154: TRIALS is now a var with a --trials=N CLI override. The brief-level
# warning stands: at 9 trials this probe has shown a 41% TTK spread on IDENTICAL
# code (Z4 all-LEGENDARY 160s vs 226s). Raise it before concluding anything.
var TRIALS := 9   # v139g: was 5 — cells swung ±2 across identical code (Z4 read 3/5 then 1/5, Z3 1/5 then 5/5). 9 is the boss_gearcheck-proven minimum for win-rate reads; bar scales via the >=0.60 fraction.
const SUFFIX := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}
const AMMO := {"kinetic": "Slug", "energy": "Cell", "explosive": "Missile"}

# Mandatory story bosses + the hull the mission chain ACTUALLY arms the player with
# by the time they reach each fight (traced from mission_manager construct/defeat
# order) — NOT boss_gearcheck's tier==zone hull. The gap (hull tier vs zone) is the
# whole point: +1 ahead at Z1/Z2, level at Z3, then the destroyer STALLS through
# Z4/Z5 (cruiser tier-4 is skipped by the funnel) → the player is 1-2 hull tiers
# BEHIND what the audit assumed. weak-type is computed from resists at runtime.
const CASES := [
	{"eid": "z1_boss_architect", "zone": "lunar_orbit", "hull": "frigate_hull", "gear_n": 1, "htier": 2},
	{"eid": "z2_boss_monolith", "zone": "asteroid_belt", "hull": "destroyer_hull", "gear_n": 2, "htier": 3},
	{"eid": "z3_boss_warmaster", "zone": "mars_debris", "hull": "destroyer_hull", "gear_n": 3, "htier": 3},
	# v135c: the player (and the bot, via player_like._best_better_hull) builds the Heavy
	# Cruiser (t4) themselves when the Destroyer stops cutting it — NO hand-holding mission.
	# Probe confirms Rare wins BOTH on the cruiser (Z4 4/5, Z5 4/5 at -1) — vs Rare LOSING
	# on the old destroyer (Z4 2/5, Z5 1/5). Z6 stays on the battlecruiser (t5, -1, Rare
	# 3/5) — a marginal pass; a tier-6 hull is a follow-up. These CASES model the intended
	# hull-at-zone the bot/player reaches on its own.
	{"eid": "z4_boss_overseer", "zone": "cryofield", "hull": "cruiser_hull", "gear_n": 4, "htier": 4},
	{"eid": "z5_boss_harbinger", "zone": "sector_alpha", "hull": "cruiser_hull", "gear_n": 5, "htier": 4},
	{"eid": "z6_boss_colossus", "zone": "sector_beta", "hull": "battlecruiser_hull", "gear_n": 6, "htier": 5},
]

func _weak(e: Dictionary) -> String:
	var rk := float(e.get("resist_k", 0.0))
	var re := float(e.get("resist_e", 0.0))
	var rx := float(e.get("resist_x", 0.0))
	var m: float = min(rk, min(re, rx))
	if m == rx: return "explosive"
	if m == re: return "energy"
	return "kinetic"

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	for _a in OS.get_cmdline_user_args():
		if String(_a).begins_with("--trials="):
			TRIALS = maxi(1, int(String(_a).split("=")[1]))
	print("[BTH] ===== BOSS THRESHOLD PROBE (mission-realistic mixes) =====")
	print("[BTH] base = ALL-common weak-type loadout + repair kits; then swap in K RARE weak-type weapons.")
	print("[BTH] min K with >=%d/%d wins (60%%) = the funnel's rare-weapon requirement for that boss." % [int(ceil(0.6 * TRIALS)), TRIALS])
	for c in CASES:
		_run_case(sm, cm, rm, c)
	print("[BTH] ===== done =====")
	get_tree().quit()

func _run_case(sm, cm, rm, c) -> void:
	var eid := String(c["eid"])
	var weak := _weak(cm.enemy_db.get(eid, {}))
	var wslots := _weapon_slot_count(sm, String(c["hull"]))
	var zone := int(c["gear_n"])
	var htier := int(c["htier"])
	var gap := htier - zone
	var gap_s := ("+%d" % gap) if gap >= 0 else str(gap)
	print("[BTH] ------------------------------------------------------------")
	print("[BTH] %s  Z%d  hull=%s(t%d, %s vs zone)  wpn_slots=%d  weak=%s" % [
		eid, zone, String(c["hull"]), htier, gap_s, wslots, weak])
	# Full-loadout ladder (weapons AND armor/shield at the tier) — the clean signal
	# vs boss_gearcheck (defense matters as much as weapon rarity on the harder bosses).
	print("[BTH]   all-UNCOMMON        : %s" % _fmt(_trials(sm, cm, rm, c, weak, 1, -1)))
	print("[BTH]   all-RARE            : %s" % _fmt(_trials(sm, cm, rm, c, weak, 2, -1)))
	# Realistic climb: common base + K rare weak-type weapons.
	for k in range(0, wslots + 1):
		var tag := "all-common" if k == 0 else "common + %d RARE wpn" % k
		print("[BTH]   %-20s: %s" % [tag, _fmt(_trials(sm, cm, rm, c, weak, 0, k))])
	# Full-Legendary reference — if even this loses, the boss is UNBEATABLE at this
	# hull tier (a hull wall, not a gear wall).
	print("[BTH]   all-LEGENDARY       : %s" % _fmt(_trials(sm, cm, rm, c, weak, 3, -1)))

func _weapon_slot_count(sm, hull) -> int:
	var n := 0
	for s in sm.hulls.get(hull, {}).get("slots", []):
		if String(s) == "weapon":
			n += 1
	return n

func _trials(sm, cm, rm, c, weak: String, base_rarity: int, k_rare: int) -> Dictionary:
	var wins := 0
	var ttks := []
	var worst := 100.0
	for _i in range(TRIALS):
		var r := _fight(sm, cm, rm, c, weak, base_rarity, k_rare)
		if String(r.get("r", "")) == "WIN":
			wins += 1
			ttks.append(float(r.get("ttk", 0)))
		else:
			worst = minf(worst, float(r.get("bpct", 100.0)))
	ttks.sort()
	var med: float = (float(ttks[ttks.size() / 2]) if ttks.size() > 0 else 0.0)
	return {"w": wins, "k": TRIALS, "ttk": med, "left": worst}

func _fmt(r: Dictionary) -> String:
	var w := int(r.get("w", 0))
	if w > 0:
		return "%d/%d WIN   (ttk %.0fs)" % [w, int(r.get("k", TRIALS)), float(r.get("ttk", 0))]
	return "%d/%d loss  (boss %.0f%% hp left)" % [w, int(r.get("k", TRIALS)), float(r.get("left", 100))]

func _fight(sm, cm, rm, c, weak: String, base_rarity: int, k_rare: int) -> Dictionary:
	GameState.hard_reset()
	cm.boss_kills.clear()
	cm.total_kills = 0
	_unlock_research(rm, int(c["gear_n"]))
	_set_hull(sm, String(c["hull"]))
	_equip_mix(sm, int(c["gear_n"]), weak, base_rarity, k_rare)
	_ammo_kits(sm, weak, int(c["gear_n"]))
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	if sm.energy_used > sm.energy_capacity:
		return {"r": "UNPWR"}
	cm.start_expedition(String(c["zone"]))
	cm.set_target_enemy(String(c["eid"]))
	if cm.current_enemy == null or String(cm.current_enemy.get("id", "")) != String(c["eid"]):
		return {"r": "NOENT"}
	var t := 0.0
	while t < MAXT:
		_kit(sm, cm)
		cm.process_tick(DT)
		t += DT
		if int(cm.boss_kills.get(String(c["eid"]), 0)) > 0:
			return {"r": "WIN", "ttk": t}
		if sm.current_hp <= 0 or not cm.in_combat:
			return {"r": "LOSS", "bpct": 100.0 * float(cm.enemy_hp) / maxf(1.0, float(cm.enemy_max_hp))}
	return {"r": "TIME", "bpct": 100.0 * float(cm.enemy_hp) / maxf(1.0, float(cm.enemy_max_hp))}

func _unlock_research(rm, n: int) -> void:
	for tid in rm.tech_tree:
		if int(rm.tech_tree[tid].get("tier", 99)) <= n and not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)

func _set_hull(sm, hid: String) -> void:
	sm.active_hull = hid
	sm.loadout.clear()
	sm.ammo_loadout.clear()
	sm.consumable_hull_slot = ""
	sm.consumable_shield_slot = ""

func _slots(sm, stype: String) -> Array:
	var out := []
	var slots: Array = sm.hulls.get(sm.active_hull, {}).get("slots", [])
	for i in range(slots.size()):
		if String(slots[i]) == stype:
			out.append(i)
	return out

# Common base loadout; first k_rare weapon slots upgraded to RARE. Batteries are
# over-provisioned (legendary) so power is never the variable under test. k_rare<0
# means "all weapons at base_rarity" (used for the all-uncommon reference).
func _equip_mix(sm, gear_n: int, weak: String, base_rarity: int, k_rare: int) -> void:
	var bat := "z%d_battery" % clampi(gear_n, 1, 10)
	for i in _slots(sm, "battery"):
		if bat in sm.modules:
			var cid := String(sm.generate_module_drop(bat, 3, gear_n))
			if cid != "":
				sm.equip_module(i, cid, true)
	for stype in ["armor", "shield"]:
		var did := "z%d_%s" % [gear_n, stype]
		for i in _slots(sm, stype):
			if did in sm.modules:
				var cid2 := String(sm.generate_module_drop(did, base_rarity, gear_n))
				if cid2 != "":
					sm.equip_module(i, cid2, true)
	var wbase := "z%d_%s" % [gear_n, SUFFIX[weak]]
	var wslots := _slots(sm, "weapon")
	for idx in range(wslots.size()):
		var rar := base_rarity
		if k_rare >= 0 and idx < k_rare:
			rar = 2
		if wbase in sm.modules:
			var cid3 := String(sm.generate_module_drop(wbase, rar, gear_n))
			if cid3 != "":
				sm.equip_module(int(wslots[idx]), cid3, true)

func _ammo_kits(sm, weak: String, n: int) -> void:
	var atier := clampi((n + 1) / 2, 1, 4)
	var ammo := "%sT%d" % [AMMO[weak], atier]
	if not ElementDB.ELEMENT_NAMES.has(ammo):
		ammo = "%sT1" % AMMO[weak]
	GameState.resources.add_element(ammo, 1000000)
	for i in _slots(sm, "weapon"):
		sm.ammo_loadout[i] = ammo
	GameState.resources.add_element("EmergencyPatch", 100000)
	GameState.resources.add_element("BasicBooster", 100000)
	sm.equip_consumable("hull", "EmergencyPatch")
	sm.equip_consumable("shield", "BasicBooster")

func _kit(sm, cm) -> void:
	if cm.consumable_cooldown > 0.0:
		return
	if sm.current_hp < sm.max_hp * 0.5 and sm.consumable_hull_slot != "":
		cm.use_manual_consumable("hull")
	elif cm.player_max_shield > 0 and cm.player_shield < cm.player_max_shield * 0.5 and sm.consumable_shield_slot != "":
		cm.use_manual_consumable("shield")
