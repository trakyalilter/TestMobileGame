extends Node
# ============================================================================
# Z12 RIFT WARDEN TUNING PROBE (NG+ P5 balance pass)
# ----------------------------------------------------------------------------
# boss_gearcheck CANNOT judge Z12: its cryo path keys on `warp_hardened`, but the
# Rift Warden uses `phases:["cryo","corrosion"]` instead — so gearcheck fights it
# with weak-type kinetic/energy weapons that get phase-cut ×0.15 and reports a
# FALSE loss. This probe fights the Warden with the INTENDED answer:
#   * Leviathan (tier-10, the top buildable hull) + Z10 armor/shield/batteries
#   * a CRYO preset (cryo_lance) for phase 1, which SWAPS to a CORROSION preset
#     (corrosion_blaster) the instant HP crosses the 50% phase flip — exactly
#     what the player does at the phase-2 telegraph.
# It reports WIN/LOSS/TTK + per-phase timing, sweeps gear rarity + boss-HP, and
# proves the gate HOLDS:
#   * intended (cryo→corrosion swap): must WIN
#   * all-cryo, NO swap: must STALL at ~50% (corrosion band cuts cryo ×0.15)
#   * conventional kinetic: must barely dent phase 1 (cryo-hardened ×0.15)
# Power is over-provisioned; NO Threshold Relic (first-clear is the hard case).
#   Godot --headless --path <root> res://scenes/z12_tune.tscn
# ============================================================================

const DT := 0.1
const MAXT := 1200.0   # tuned wins land <13 min; caps the cost of stalemate losses
const TRIALS := 9      # survivability-variance-dominated — need power to read win rate
const RN := {2: "Rare ", 3: "Legnd"}
const WARDEN := "z12_boss_rift_warden"

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	var wd: Dictionary = cm.enemy_db.get(WARDEN, {})
	var st: Dictionary = wd.get("stats", {})
	var base_hp := float(st.get("hp", 0))
	var atk := float(st.get("atk", 0))
	var lev_hp := int(sm.hulls.get("leviathan_hull", {}).get("stats", {}).get("hp", 0))
	print("[Z12] ================= RIFT WARDEN TUNING PROBE =================")
	print("[Z12] current def: hp=%.0f atk=%.0f interval=%.1f enrage@%.2f x%.1f | leviathan hp=%d" % [
		base_hp, atk, float(st.get("atk_interval", 0)),
		float(wd.get("enrage_at", 0)), float(wd.get("enrage_atk_mult", 1)), lev_hp])
	print("[Z12] cryo_lance atk=%.0f (RARE) | corrosion_blaster atk=%.0f (LEG)" % [
		float(sm.modules.get("cryo_lance", {}).get("stats", {}).get("atk_cryo", 0)),
		float(sm.modules.get("corrosion_blaster", {}).get("stats", {}).get("atk_cryo", 0))])
	print("[Z12] cell = W<ttk>s [p1<t> p2<t>] / L<boss%% left> / TIME<boss%% left>   (median over %d)" % TRIALS)
	print("[Z12] ------------------------------------------------------------------------")

	# 1) INTENDED answer at each rarity, current HP.
	print("[Z12] INTENDED (cryo -> corrosion swap @50%%), boss HP = %.0f (current):" % base_hp)
	for rarity in [2, 3]:
		print("[Z12]   %s  %s" % [RN[rarity], _cell(_trials(sm, cm, rm, base_hp, rarity, "swap"))])

	# 2) GATE CHECK — the wrong loadouts MUST fail.
	print("[Z12] GATE CHECK (these MUST lose/stall):")
	print("[Z12]   all-cryo NO swap (Legnd)  %s   <- must STALL ~50%% (forces the swap)" % _cell(_trials(sm, cm, rm, base_hp, 3, "cryo_only")))
	print("[Z12]   conventional kinetic(Leg) %s   <- must barely dent (cryo-hardened p1)" % _cell(_trials(sm, cm, rm, base_hp, 3, "conventional")))

	# 3) HP SWEEP with the intended Legendary answer — find the tuned point.
	print("[Z12] HP SWEEP (intended Legendary cryo->corrosion):")
	for hp in [22000000.0, 28000000.0, 34000000.0, 45000000.0]:
		print("[Z12]   hp=%-11.0f %s" % [hp, _cell(_trials(sm, cm, rm, hp, 3, "swap"))])

	print("[Z12] ========================================================================")
	get_tree().quit(0)

func _trials(sm, cm, rm, hp_over, rarity, mode) -> Dictionary:
	var wins := 0
	var ttks := []
	var p1s := []
	var p2s := []
	var worst_left := 100.0
	for _i in range(TRIALS):
		var r := _fight(sm, cm, rm, float(hp_over), int(rarity), String(mode))
		if String(r.get("r", "")) == "WIN":
			wins += 1
			ttks.append(float(r.get("ttk", 0)))
			p1s.append(float(r.get("p1", 0)))
			p2s.append(float(r.get("p2", 0)))
		elif String(r.get("r", "")) in ["UNPWR", "NOENT"]:
			return {"w": 0, "k": TRIALS, "err": String(r.get("r"))}
		else:
			worst_left = minf(worst_left, float(r.get("bpct", 100.0)))
	ttks.sort()
	p1s.sort()
	p2s.sort()
	return {
		"w": wins, "k": TRIALS,
		"ttk": (float(ttks[ttks.size() / 2]) if ttks.size() > 0 else 0.0),
		"p1": (float(p1s[p1s.size() / 2]) if p1s.size() > 0 else 0.0),
		"p2": (float(p2s[p2s.size() / 2]) if p2s.size() > 0 else 0.0),
		"left": worst_left}

func _cell(r) -> String:
	if r.has("err"):
		return "%s" % String(r["err"])
	var w := int(r.get("w", 0))
	if w > 0:
		return "%d/%d W%.0fs [p1 %.0f p2 %.0f]" % [w, int(r.get("k", TRIALS)), float(r.get("ttk", 0)), float(r.get("p1", 0)), float(r.get("p2", 0))]
	return "%d/%d L%.0f%%left" % [w, int(r.get("k", TRIALS)), float(r.get("left", 100))]

func _fight(sm, cm, rm, hp_over, rarity, mode) -> Dictionary:
	GameState.hard_reset()
	cm.boss_kills.clear()
	cm.total_kills = 0
	# Post-warp NG+ context: Cryo + Corrosion armaments unlocked, Z12 reachable.
	GameState.game_settings["cryo_unlocked"] = true
	GameState.game_settings["z11_unlocked"] = true
	GameState.game_settings["z12_unlocked"] = true
	for t in ["cryo_armaments", "corrosion_armaments"]:
		if not (t in rm.unlocked_techs):
			rm.unlocked_techs.append(t)
	_unlock_research(rm, 12)
	_set_hull(sm, 10)   # leviathan (top buildable hull)
	# Power FIRST (equip guard blocks weapons over-budget), then defense, then the
	# phase-1 weapon preset. Over-provision batteries — power is NOT the variable.
	_fill(sm, "battery", "z10_battery", 3, 10)
	_fill(sm, "armor", "z10_armor", rarity, 10)
	_fill(sm, "shield", "z10_shield", rarity, 10)
	if String(mode) == "conventional":
		_fill(sm, "weapon", "z10_kinetic", rarity, 10)
	else:
		_fill(sm, "weapon", "cryo_lance", rarity, 11)   # cryo preset (phase 1)
	_kits(sm)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	if sm.energy_used > sm.energy_capacity:
		return {"r": "UNPWR"}
	cm.start_expedition("the_rift")
	cm.set_target_enemy(WARDEN)
	if cm.current_enemy == null or String(cm.current_enemy.get("id", "")) != WARDEN:
		return {"r": "NOENT"}
	# Override HP for the sweep (phased bosses skip zone-steepening, so base=live).
	cm.enemy_max_hp = float(hp_over)
	cm.enemy_hp = float(hp_over)
	var t := 0.0
	var swapped := false
	var p1_end := 0.0
	while t < MAXT:
		# Phase flip: at 50% HP the boss becomes Corrosion-hardened. The player
		# swaps the Cryo preset for the Corrosion preset at the telegraph.
		if String(mode) == "swap" and not swapped and cm._phase_index(2) >= 1:
			_swap_weapons(sm, cm, "corrosion_blaster", int(rarity))
			swapped = true
			p1_end = t
		_kit(sm, cm)
		cm.process_tick(DT)
		t += DT
		if int(cm.boss_kills.get(WARDEN, 0)) > 0:
			return {"r": "WIN", "ttk": t, "p1": p1_end, "p2": maxf(0.0, t - p1_end)}
		if sm.current_hp <= 0 or not cm.in_combat:
			return {"r": "LOSS", "bpct": 100.0 * float(cm.enemy_hp) / maxf(1.0, float(cm.enemy_max_hp))}
	return {"r": "TIME", "bpct": 100.0 * float(cm.enemy_hp) / maxf(1.0, float(cm.enemy_max_hp))}

# Swap every weapon slot to a fresh rarity-rolled copy of base_id, then rebuild
# the live weapon states so the new exotic_type takes effect this tick.
func _swap_weapons(sm, cm, base_id: String, rarity: int) -> void:
	if not (base_id in sm.modules):
		return
	for i in _slots(sm, "weapon"):
		var cid := String(sm.generate_module_drop(base_id, rarity, 12))
		if cid != "":
			sm.equip_module(i, cid, true)
	sm.recalc_stats()
	cm._rebuild_player_weapon_states()

func _unlock_research(rm, n) -> void:
	for tid in rm.tech_tree:
		if int(rm.tech_tree[tid].get("tier", 99)) <= n and not (tid in rm.unlocked_techs):
			rm.unlocked_techs.append(tid)

func _set_hull(sm, n) -> void:
	var want := clampi(n, 1, 10)
	var hid := ""
	for h in sm.hulls:
		if int(sm.hulls[h].get("tier", 0)) == want:
			hid = String(h)
			break
	if hid == "":
		hid = "leviathan_hull"
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

func _fill(sm, stype, base_id, rarity, zone) -> void:
	if not (base_id in sm.modules):
		return
	for i in _slots(sm, stype):
		var cid := String(sm.generate_module_drop(base_id, rarity, zone))
		if cid != "":
			sm.equip_module(i, cid, true)

# Realistic endgame kits: AdvMaintenanceKit (hull 0.35) + ZeroPoint (shield 0.35).
func _kits(sm) -> void:
	GameState.resources.add_element("AdvMaintenanceKit", 100000)
	GameState.resources.add_element("ZeroPoint", 100000)
	sm.equip_consumable("hull", "AdvMaintenanceKit")
	sm.equip_consumable("shield", "ZeroPoint")

func _kit(sm, cm) -> void:
	if cm.consumable_cooldown > 0.0:
		return
	if sm.current_hp < sm.max_hp * 0.5 and sm.consumable_hull_slot != "":
		cm.use_manual_consumable("hull")
	elif cm.player_max_shield > 0 and cm.player_shield < cm.player_max_shield * 0.5 and sm.consumable_shield_slot != "":
		cm.use_manual_consumable("shield")
