extends Node
# ============================================================================
# BOSS GEAR-CHECK MATRIX (v135a)
# Verifies the load-bearing design rule (user, 2026-07-12):
#   "a Zone-N boss must be killable ONLY with rare+ Zone-N module sets, or with
#    the Unique set of N-1."
# For every zone boss it fights the REAL combat loop with a full loadout of the
# boss's weak-type Zone-N weapons + Zone-N armor/shield, at each rarity tier, and
# with the researches a diligent player would have by that zone unlocked + a
# tier-appropriate ammo + repair kits. Then it asserts the invariant:
#   Common LOSE, Uncommon LOSE, Rare WIN (or Legendary WIN), N-1 Unique set WIN.
# Power (batteries) is always over-provisioned so the ONLY variable is combat gear.
#
#   Godot --headless --path <root> res://scenes/boss_gearcheck.tscn
# ============================================================================

const DT := 0.1
const MAXT := 1500.0   # v135c: was 300 — Z9/Z10 wins hit that cap and Z11 (~19min cryo kill) needs the room
const TRIALS := 5   # per (boss,rarity) — smooths rarity-roll + affix + combat RNG
const RN := {0: "Common", 1: "Uncmn", 2: "Rare", 3: "Legnd", 4: "Uniq"}
const SUFFIX := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}
const AMMO := {"kinetic": "Slug", "energy": "Cell", "explosive": "Missile"}

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	print("[BGC] ================= BOSS GEAR-CHECK MATRIX =================")
	print("[BGC] rule: Common+Uncommon must LOSE; Rare+ (or Zone N-1 Unique set) must WIN.")
	print("[BGC] loadout: ALL weapon slots = weak-type Z-N weapon; Z-N armor/shield; power over-provisioned.")
	print("[BGC] researches tier<=N unlocked; tier-appropriate ammo + repair kits stocked.")
	print("[BGC] cell = W<ttk>s win / L<boss-hp%% left> loss / TIME stalemate.")
	print("[BGC] --------------------------------------------------------------------------------")
	var bosses := _bosses(cm)
	var passed := 0
	var failed := 0
	for b in bosses:
		if _test(sm, cm, rm, b):
			passed += 1
		else:
			failed += 1
	print("[BGC] --------------------------------------------------------------------------------")
	print("[BGC] ===== %d bosses: %d honor the rule, %d VIOLATE =====" % [bosses.size(), passed, failed])
	get_tree().quit()

func _bosses(cm) -> Array:
	var out := []
	var seen := {}
	for zid in cm.zones:
		var zd := int(cm.zones[zid].get("difficulty", 0))
		for eid in cm.zones[zid].get("enemies", []):
			var e = cm.enemy_db.get(eid, {})
			if e.get("is_boss", false) and not seen.has(eid):
				seen[eid] = true
				out.append({"zone": zid, "eid": String(eid), "n": zd, "e": e, "weak": _weak(e)})
	out.sort_custom(func(a, c): return int(a["n"]) < int(c["n"]))
	return out

func _weak(e) -> String:
	var rk := float(e.get("resist_k", 0.0))
	var re := float(e.get("resist_e", 0.0))
	var rx := float(e.get("resist_x", 0.0))
	var m := minf(rk, minf(re, rx))
	if m == rx: return "explosive"
	if m == re: return "energy"
	return "kinetic"

func _test(sm, cm, rm, b) -> bool:
	var n := int(b["n"])
	var weak := String(b["weak"])
	var hp := float(b["e"].get("stats", {}).get("hp", 0))
	var cells := {}
	for rarity in [0, 1, 2, 3]:
		cells[rarity] = _trials(sm, cm, rm, b, n, weak, rarity)
	var uni := {}
	if n >= 2 and ("z%d_unique_weapon" % (n - 1)) in sm.modules:
		uni = _trials(sm, cm, rm, b, n - 1, weak, 4)
	# Rule (OR): Common+Uncommon must mostly LOSE (<=1/5); AND a Rare/Legendary
	# Zone-N set OR the Zone-(N-1) Unique set must mostly WIN (>=3/5).
	var c_ok: bool = int(cells[0]["w"]) <= 1
	var u_ok: bool = int(cells[1]["w"]) <= 1
	var rare_win: bool = int(cells[2]["w"]) >= 3
	var leg_win: bool = int(cells[3]["w"]) >= 3
	var uni_win: bool = not uni.is_empty() and int(uni["w"]) >= 3
	var ok: bool = c_ok and u_ok and (rare_win or leg_win or uni_win)
	var flag := "OK  " if ok else "FAIL"
	print("[BGC] %s Z%-2d %-22s w:%-9s hp:%-8.0f | C %-8s U %-8s R %-8s L %-8s | N-1uniq %-8s" % [
		flag, n, String(b["eid"]), weak, hp,
		_cell(cells[0]), _cell(cells[1]), _cell(cells[2]), _cell(cells[3]),
		(_cell(uni) if not uni.is_empty() else "n/a")])
	return ok

func _trials(sm, cm, rm, b, gear_n, weak, rarity) -> Dictionary:
	var wins := 0
	var ttks := []
	var worst_left := 100.0
	for _i in range(TRIALS):
		var r := _fight(sm, cm, rm, b, int(gear_n), String(weak), int(rarity))
		if String(r.get("r", "")) == "WIN":
			wins += 1
			ttks.append(float(r.get("ttk", 0)))
		else:
			worst_left = minf(worst_left, float(r.get("bpct", 100.0)))
	ttks.sort()
	var med := (float(ttks[ttks.size() / 2]) if ttks.size() > 0 else 0.0)
	return {"w": wins, "k": TRIALS, "ttk": med, "left": worst_left}

func _cell(r) -> String:
	if r.is_empty(): return "----"
	var w := int(r.get("w", 0))
	if w > 0:
		return "%d/%d W%.0f" % [w, int(r.get("k", TRIALS)), float(r.get("ttk", 0))]
	return "%d/%d L%.0f%%" % [w, int(r.get("k", TRIALS)), float(r.get("left", 100))]

func _fight(sm, cm, rm, b, gear_n, weak, rarity) -> Dictionary:
	GameState.hard_reset()
	cm.boss_kills.clear()
	cm.total_kills = 0
	# v135c: cryo-gated bosses (Z11/Z12 warp_hardened — non-cryo cut ~98%). The intended
	# answer is the Cryo-Lance (post-first-warp). Unlock cryo + fight with cryo weapons so
	# these get a real verdict instead of a false "everything loses".
	var cryo: bool = bool(b["e"].get("warp_hardened", false))
	if cryo:
		GameState.game_settings["cryo_unlocked"] = true
		if not ("cryo_armaments" in rm.unlocked_techs):
			rm.unlocked_techs.append("cryo_armaments")
	_unlock_research(rm, int(b["n"]))
	_set_hull(sm, int(b["n"]))
	_equip_gear(sm, int(gear_n), String(weak), int(rarity), cryo)
	_ammo_kits(sm, String(weak), int(b["n"]))
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	if sm.energy_used > sm.energy_capacity:
		return {"r": "UNPWR"}
	cm.start_expedition(String(b["zone"]))
	cm.set_target_enemy(String(b["eid"]))
	if cm.current_enemy == null or String(cm.current_enemy.get("id", "")) != String(b["eid"]):
		return {"r": "NOENT"}
	var t := 0.0
	while t < MAXT:
		_kit(sm, cm)
		cm.process_tick(DT)
		t += DT
		if int(cm.boss_kills.get(String(b["eid"]), 0)) > 0:
			return {"r": "WIN", "ttk": t}
		if sm.current_hp <= 0 or not cm.in_combat:
			return {"r": "LOSS", "bpct": 100.0 * float(cm.enemy_hp) / maxf(1.0, float(cm.enemy_max_hp))}
	return {"r": "TIME", "bpct": 100.0 * float(cm.enemy_hp) / maxf(1.0, float(cm.enemy_max_hp))}

func _unlock_research(rm, n) -> void:
	for tid in rm.tech_tree:
		if int(rm.tech_tree[tid].get("tier", 99)) <= n and not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)

func _set_hull(sm, n) -> void:
	var want := clampi(n, 1, 10)
	var hid := ""
	for h in sm.hulls:
		if int(sm.hulls[h].get("tier", 0)) == want:
			hid = String(h)
			break
	if hid == "":
		hid = "destroyer_hull"
	sm.active_hull = hid
	sm.loadout.clear()
	sm.ammo_loadout.clear()
	sm.consumable_hull_slot = ""
	sm.consumable_shield_slot = ""

func _slots(sm, stype) -> Array:
	var out := []
	var slots: Array = sm.hulls.get(sm.active_hull, {}).get("slots", [])
	for i in range(slots.size()):
		if String(slots[i]) == stype:
			out.append(i)
	return out

func _equip_gear(sm, gear_n, weak, rarity, cryo := false) -> void:
	# Power FIRST: equip_module's power guard blocks a weapon whose load exceeds
	# current capacity, so batteries must be in the loadout before the weapons.
	# Power is NOT the gear-check variable — over-provision (legendary batteries)
	# so the only thing under test is weapon/armor/shield rarity.
	_fill(sm, "battery", "z%d_battery" % clampi(gear_n, 1, 10), 3, gear_n)
	if cryo:
		# Cryo-gated boss: Cryo-Lance weapons (the only thing that breaches warp-hardened).
		# Z11+ has no armor/shield modules of its own (only Cryo-Lance drops), so defense
		# falls back to the highest normal tier (z10).
		var dn: int = min(int(gear_n), 10)
		_fill(sm, "weapon", "cryo_lance", rarity, dn)
		_fill(sm, "armor", "z%d_armor" % dn, rarity, dn)
		_fill(sm, "shield", "z%d_shield" % dn, rarity, dn)
	elif rarity == 4:
		_fill(sm, "weapon", "z%d_unique_weapon" % gear_n, 4, gear_n)
		_fill(sm, "armor", "z%d_unique_armor" % gear_n, 4, gear_n)
		_fill(sm, "shield", "z%d_unique_shield" % gear_n, 4, gear_n)
	else:
		_fill(sm, "weapon", "z%d_%s" % [gear_n, SUFFIX[weak]], rarity, gear_n)
		_fill(sm, "armor", "z%d_armor" % gear_n, rarity, gear_n)
		_fill(sm, "shield", "z%d_shield" % gear_n, rarity, gear_n)

func _fill(sm, stype, base_id, rarity, zone) -> void:
	if not base_id in sm.modules:
		return
	for i in _slots(sm, stype):
		var cid := String(sm.generate_module_drop(base_id, rarity, zone))
		if cid != "":
			sm.equip_module(i, cid, true)

func _ammo_kits(sm, weak, n) -> void:
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
