extends Node
# ============================================================================
# HULL GATE DIAGNOSTIC (v175)
#
# Why this exists: player_bot walls on the boss-core farm beats (m030i Z4, m032a
# Z5) with the status "farming rare+ <weak> gear for <boss>" — the bot loses,
# decides its gear is not ready, farms, and never gets ready. Three seeds walled
# on three DIFFERENT bosses (Z3/Z4/Z5), so it is not one boss's numbers.
#
# The suspicion is not gear at all. boss_gearcheck certifies every boss with
# _set_hull(n) — hull TIER == the boss's ZONE. But the mission chain builds:
#     m026b Frigate(2) -> m030c Destroyer(3) -> m032c Battlecruiser(5)
# cruiser_hull (tier 4) has NO construct mission, and the Battlecruiser lands at
# m032c — AFTER the Z4 boss farm (m030i) and AFTER the Z5 boss farm (m032a). So
# the guard passes a boss in a ship the chain has not handed over yet.
#
# This probe isolates HULL as the only variable: same full Rare Zone-N weak-type
# kit, same ammo/kits, power over-provisioned, fought from each hull tier the
# player could plausibly be flying. If the chain-real hull loses where the
# guard-assumed hull wins, the wall is chain ORDERING, not drop rates.
#
#   Godot --headless --path <root> res://scenes/hull_gate_diag.tscn -- --trials=21
# ============================================================================

const DT := 0.1
const MAXT := 1500.0
const SUFFIX := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}
const AMMO := {"kinetic": "Slug", "energy": "Cell", "explosive": "Missile"}

# The beat the player is actually on when the chain asks for this boss, and the
# hull the chain has given them by then. CHAIN_HULL is read off the mission list
# (last "construct <hull>" beat before that boss beat), GUARD_TIER is what
# boss_gearcheck assumes (== zone).
# Zone is LOOKED UP from cm.zones, never hardcoded. The first cut of this probe
# hardcoded "wreckage_field" for Z3 (the real id is "mars_debris") and every Z3
# cell read 0/21 L100% on all three hulls — a wrong zone means the wrong
# difficulty feeds the tier-penetration gate, so the player does no damage at
# all. That looked exactly like a catastrophic game finding and was a typo.
const CASES := [
	{"eid": "z3_boss_warmaster", "n": 3, "beat": "m030f2", "chain_hull": "destroyer_hull"},
	# chain_hull is cruiser_hull for these two as of the v175 m030h1 beat; it was
	# destroyer_hull when this probe first ran, which is the defect it found.
	{"eid": "z4_boss_overseer", "n": 4, "beat": "m030i", "chain_hull": "cruiser_hull"},
	{"eid": "z5_boss_harbinger", "n": 5, "beat": "m032a", "chain_hull": "cruiser_hull"},
]
# Columns are (hull, rarity). The destroyer appears TWICE — at Rare and at
# Legendary — because "the chain-given hull is too small" and "the chain-given
# hull needs better loot" are different defects with different fixes, and only a
# Legendary-on-destroyer cell separates them.
const COLS := [
	{"hull": "destroyer_hull", "rarity": 2, "label": "destr(3) R"},
	{"hull": "destroyer_hull", "rarity": 3, "label": "destr(3) L"},
	{"hull": "cruiser_hull", "rarity": 2, "label": "cruis(4) R"},
	{"hull": "battlecruiser_hull", "rarity": 2, "label": "battl(5) R"},
]

var TRIALS := 9

func _ready() -> void:
	# The sim harnesses drive the LIVE GameState and hard_reset() deletes the real
	# save. sim_mode must be on before anything here touches state.
	if not GameState.sim_mode:
		push_error("[HULL] sim_mode is OFF — refusing to run (this probe hard_resets).")
		get_tree().quit(1)
		return
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--trials="):
			TRIALS = maxi(1, int(String(a).split("=")[1]))
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	print("[HULL] ============ HULL GATE DIAGNOSTIC ============")
	print("[HULL] kit is IDENTICAL in every cell: full RARE Zone-N weak-type weapons,")
	print("[HULL] Zone-N armor/shield, tier ammo + kits, power over-provisioned.")
	print("[HULL] The ONLY variable is the hull. trials=%d" % TRIALS)
	print("[HULL] cell = <wins>/<trials> W<median ttk>s   or  L<boss hp %% left>  or  UNPWR")
	print("[HULL] ----------------------------------------------------------------------")
	print("[HULL] %-22s %-8s %-9s | %-13s %-13s %-13s %-13s" % [
		"boss", "beat", "weak", COLS[0]["label"], COLS[1]["label"],
		COLS[2]["label"], COLS[3]["label"]])
	for c in CASES:
		var e: Dictionary = cm.enemy_db.get(String(c["eid"]), {})
		var weak := _weak(e)
		var zid := _zone_of(cm, String(c["eid"]))
		if zid == "":
			print("[HULL] %-22s NO ZONE CONTAINS THIS ENEMY — skipped" % String(c["eid"]))
			continue
		var cells: Array = []
		for col in COLS:
			cells.append(_cell(_trials(sm, cm, rm, c, zid, weak,
				String(col["hull"]), int(col["rarity"]))))
		print("[HULL] %-22s %-8s %-9s | %-13s %-13s %-13s %-13s  chain gives: %s" % [
			String(c["eid"]), String(c["beat"]), weak,
			cells[0], cells[1], cells[2], cells[3], String(c["chain_hull"])])
	print("[HULL] ----------------------------------------------------------------------")
	# ---- PARTIAL SET -------------------------------------------------------
	# player_bot's _boss_gear_ready demands EVERY weapon slot hold a Rare+ weak-type
	# Zone-N gun before it will retry a boss. That bar scales with hull size, so the
	# tier-4 cruiser (5 weapon mounts) is a HARDER bar than the tier-3 destroyer (4)
	# — handing the bot a better ship made it farm longer, not less. Whether that is
	# the game or the bot hinges on one question this table answers: does a PARTIAL
	# Rare set win? K slots Rare weak-type, the remaining slots Common weak-type
	# (what the player crafts), on the hull the chain now actually gives them.
	print("[HULL] PARTIAL SET on the chain-given hull — K weapon slots RARE, rest COMMON")
	print("[HULL] %-22s %-14s | %s" % ["boss", "hull", "K=1  K=2  K=3  K=4  K=5 (all)"])
	for c in CASES:
		var e2: Dictionary = cm.enemy_db.get(String(c["eid"]), {})
		var weak2 := _weak(e2)
		var zid2 := _zone_of(cm, String(c["eid"]))
		if zid2 == "":
			continue
		var hull2 := String(c["chain_hull"])
		var nslots := _hull_weapon_slots(sm, hull2)
		var row: Array = []
		for k in range(1, nslots + 1):
			row.append(_cell(_trials_partial(sm, cm, rm, c, zid2, weak2, hull2, k)))
		print("[HULL] %-22s %-14s | %s" % [String(c["eid"]), hull2, " ".join(row)])
	print("[HULL] ----------------------------------------------------------------------")
	print("[HULL] done.")
	get_tree().quit(0)

func _hull_weapon_slots(sm, hull: String) -> int:
	var n := 0
	for s in sm.hulls.get(hull, {}).get("slots", []):
		if String(s) == "weapon":
			n += 1
	return n

func _trials_partial(sm, cm, rm, c: Dictionary, zid: String, weak: String,
		hull: String, k_rare: int) -> Dictionary:
	var wins := 0
	var ttks: Array = []
	var worst := 100.0
	var unpwr := 0
	for _i in range(TRIALS):
		var r := _fight(sm, cm, rm, c, zid, weak, hull, 2, k_rare)
		var v := String(r.get("r", ""))
		if v == "WIN":
			wins += 1
			ttks.append(float(r.get("ttk", 0)))
		elif v == "UNPWR":
			unpwr += 1
		else:
			worst = minf(worst, float(r.get("bpct", 100.0)))
	ttks.sort()
	var med: float = (float(ttks[ttks.size() / 2]) if ttks.size() > 0 else 0.0)
	return {"w": wins, "k": TRIALS, "ttk": med, "left": worst, "unpwr": unpwr}

func _zone_of(cm, eid: String) -> String:
	for zid in cm.zones:
		if eid in cm.zones[zid].get("enemies", []):
			return String(zid)
	return ""

func _weak(e: Dictionary) -> String:
	var rk := float(e.get("resist_k", 0.0))
	var re := float(e.get("resist_e", 0.0))
	var rx := float(e.get("resist_x", 0.0))
	var m := minf(rk, minf(re, rx))
	if m == rx: return "explosive"
	if m == re: return "energy"
	return "kinetic"

func _trials(sm, cm, rm, c: Dictionary, zid: String, weak: String,
		hull: String, rarity: int) -> Dictionary:
	var wins := 0
	var ttks: Array = []
	var worst := 100.0
	var unpwr := 0
	for _i in range(TRIALS):
		var r := _fight(sm, cm, rm, c, zid, weak, hull, rarity)
		var v := String(r.get("r", ""))
		if v == "WIN":
			wins += 1
			ttks.append(float(r.get("ttk", 0)))
		elif v == "UNPWR":
			unpwr += 1
		else:
			worst = minf(worst, float(r.get("bpct", 100.0)))
	ttks.sort()
	var med: float = (float(ttks[ttks.size() / 2]) if ttks.size() > 0 else 0.0)
	return {"w": wins, "k": TRIALS, "ttk": med, "left": worst, "unpwr": unpwr}

func _cell(r: Dictionary) -> String:
	if int(r.get("unpwr", 0)) >= int(r.get("k", 1)):
		return "UNPWR"
	var w := int(r.get("w", 0))
	if w > 0:
		return "%d/%d W%.0fs" % [w, int(r["k"]), float(r["ttk"])]
	return "%d/%d L%.0f%%" % [w, int(r["k"]), float(r["left"])]

# k_rare < 0 means "every weapon slot at `rarity`" (the hull table). k_rare >= 0
# fills the first k_rare weapon slots at `rarity` and the rest at COMMON — the
# mixed loadout a player actually flies while the weak-type Rares trickle in.
func _fight(sm, cm, rm, c: Dictionary, zid: String, weak: String,
		hull: String, rarity: int, k_rare: int = -1) -> Dictionary:
	GameState.hard_reset()
	cm.boss_kills.clear()
	cm.total_kills = 0
	var n := int(c["n"])
	_unlock_research(rm, n)
	if not hull in sm.hulls:
		return {"r": "NOHULL"}
	sm.active_hull = hull
	sm.loadout.clear()
	sm.ammo_loadout.clear()
	sm.consumable_hull_slot = ""
	sm.consumable_shield_slot = ""
	# Power first — equip_module's guard rejects a weapon that overdraws, and power
	# is not the variable under test. Batteries are Legendary and fill every slot.
	_fill(sm, "battery", "z%d_battery" % clampi(n, 1, 10), 3, n)
	if k_rare < 0:
		_fill(sm, "weapon", "z%d_%s" % [n, SUFFIX[weak]], rarity, n)
	else:
		_fill_partial(sm, "z%d_%s" % [n, SUFFIX[weak]], rarity, n, k_rare)
	_fill(sm, "armor", "z%d_armor" % n, rarity, n)
	_fill(sm, "shield", "z%d_shield" % n, rarity, n)
	_ammo_kits(sm, weak, n)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	if sm.energy_used > sm.energy_capacity:
		return {"r": "UNPWR"}
	cm.start_expedition(zid)
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

func _slots(sm, stype: String) -> Array:
	var out: Array = []
	var slots: Array = sm.hulls.get(sm.active_hull, {}).get("slots", [])
	for i in range(slots.size()):
		if String(slots[i]) == stype:
			out.append(i)
	return out

func _fill(sm, stype: String, base_id: String, rarity: int, zone: int) -> void:
	if not base_id in sm.modules:
		return
	for i in _slots(sm, stype):
		var cid := String(sm.generate_module_drop(base_id, rarity, zone))
		if cid != "":
			sm.equip_module(i, cid, true)

func _fill_partial(sm, base_id: String, rarity: int, zone: int, k_rare: int) -> void:
	if not base_id in sm.modules:
		return
	var slots := _slots(sm, "weapon")
	for i in range(slots.size()):
		# generate_module_drop returns the BASE id for Common (no custom instance is
		# made) — equipping that id is exactly what a crafted Common gun is.
		var r: int = (rarity if i < k_rare else 0)
		var cid := String(sm.generate_module_drop(base_id, r, zone))
		if cid != "":
			sm.equip_module(slots[i], cid, true)

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
	elif cm.player_max_shield > 0 and cm.player_shield < cm.player_max_shield * 0.5 \
			and sm.consumable_shield_slot != "":
		cm.use_manual_consumable("shield")
