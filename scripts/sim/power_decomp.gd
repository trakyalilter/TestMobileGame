extends Node
# ============================================================================
# POWER DECOMPOSITION PROBE — why does z3_funnel config 1 == config 9?
#
# Builds, per zone transition N in 4..10, the two kits z3_funnel builds:
#   A = "config 1": Rare  z(N-1) gear on hull tier N-1
#   B = "config 9": Common z(N)  gear on hull tier N
# Both fully slotted (battery/weapon/armor/shield/engine/sensor), identical
# research, ammo and consumables — bit-identical kit builder to z3_funnel.
#
# Then dumps EVERY term that turns raw item stats into kill rate:
#   raw per-module stat ratio, hull/module-base/rarity/affix/gem split,
#   fire-rate multipliers, hit chance, per-shot damage vs a real enemy,
#   theoretical DPS, then a real 180s fight (kills / TTK / measured DPS).
#
#   Godot --headless --path <root> res://scenes/power_decomp.tscn
#   optional: -- --zones=4,10  --window=180
# ============================================================================

const DT := 0.1
var WINDOW := 180.0
const TRIALS := 3

const SUFFIX := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}
const AMMO := {"kinetic": "Slug", "energy": "Cell", "explosive": "Missile"}
const W_AFF := ["dmg_injured", "servo_overclock", "shield_heal_on_hit"]
const A_AFF := ["resist_k", "flat_hp", "hull_heal_on_hit"]
const S_AFF := ["flat_shield", "shield_heal_on_hit", "capacitor_pulse"]
const SLOTS := ["battery", "weapon", "armor", "shield", "engine", "sensor"]

var _base_affix_backup: Dictionary = {}   # base module id -> original affixes dict

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	var zones: Array = [4, 5, 6, 7, 8, 9, 10]
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--zones="):
			zones = []
			for p in s.split("=")[1].split(","):
				zones.append(int(p))
		elif s.begins_with("--window="):
			WINDOW = float(s.split("=")[1])

	print("[PWD] ================= POWER DECOMPOSITION =================")
	_dump_constants(sm, cm)
	_dump_raw_module_table(sm)
	_dump_hull_table(sm)
	for z in zones:
		_zone_report(sm, cm, rm, int(z))
	print("[PWD] ================= DONE =================")
	get_tree().quit(0)

# ---------------------------------------------------------------- constants

func _dump_constants(sm, cm) -> void:
	print("[PWD] --- SOURCE CONSTANTS (read live, not quoted) ---")
	for r in [0, 1, 2, 3, 4]:
		var rng: Array = sm.RARITY_STAT_RANGE.get(r, [0.0, 0.0])
		print("[PWD]   RARITY_STAT_RANGE[%d] = [%.2f, %.2f]  -> stat mult %.2fx..%.2fx (mid %.3fx)" % [
			r, float(rng[0]), float(rng[1]), 1.0 + float(rng[0]), 1.0 + float(rng[1]),
			1.0 + (float(rng[0]) + float(rng[1])) * 0.5])
	print("[PWD]   TIER_STEP_OLD=%.2f TIER_STEP_NEW=%.2f  rebase(z)= (%.4f)^(z-1)" % [
		sm.TIER_STEP_OLD, sm.TIER_STEP_NEW, sm.TIER_STEP_NEW / sm.TIER_STEP_OLD])
	print("[PWD]   TIER_PEN_PER_TIER=%.2f TIER_PEN_FLOOR=%.2f  (module_tier_penetration)" % [
		sm.TIER_PEN_PER_TIER, sm.TIER_PEN_FLOOR])
	print("[PWD]   MAX_DAMAGE_REDUCTION=%.2f  DEF_K = %.0f + %.0f*z^%.2f  ARMOR_K_FLOOR=%.2f" % [
		cm.MAX_DAMAGE_REDUCTION, cm.DEF_K_CONSTANT, cm.DEF_K_ZONE_SCALE, cm.DEF_K_ZONE_EXP, cm.ARMOR_K_FLOOR])
	print("[PWD]   MIN_INCOMING_FRAC=%.2f MIN_ATTACK_INTERVAL=%.2f MAX_ATK_SPEED_MULT=%.2f" % [
		cm.MIN_INCOMING_FRAC, cm.MIN_ATTACK_INTERVAL, cm.MAX_ATK_SPEED_MULT])
	print("[PWD]   ENEMY_COMP reg hp/sh/atk = %.2f/%.2f/%.2f  def %.2f" % [
		cm.ENEMY_COMP_REGULAR_HP, cm.ENEMY_COMP_REGULAR_SHIELD, cm.ENEMY_COMP_REGULAR_ATK, cm.ENEMY_COMP_DEF])
	print("[PWD]   GA_MULT=%.2f AFFIX_ZONE_CAP=%d  flat affix scale = 1.8^(z-1)" % [sm.GA_MULT, sm.AFFIX_ZONE_CAP])
	print("[PWD]   tier_gate_enabled=%s   (game_settings)" % str(GameState.game_settings.get("tier_gate_enabled", false)))
	# Is the tier wall actually WIRED into combat? grep-equivalent, done live.
	print("[PWD]   NOTE: combat_manager sets _tier_def_factor/_tier_shield_factor = 1.0 unconditionally")
	print("[PWD]         and _execute_player_attack applies NO module_tier_penetration (v120 removal).")
	print("[PWD]   --- legal affix pool per slot (the probe hand-picks 3; real Rare draws 2 at random) ---")
	for st in SLOTS:
		var pool: Array = sm._legal_affix_pool(st)
		print("[PWD]     %-8s pool=%d  %s" % [st, pool.size(), str(pool)])
	print("[PWD]   real Rare = 2 affixes, 15%% GA. probe = 3 hand-picked, ga_chance=1.0 -> max_roll*GA_MULT.")

func _dump_raw_module_table(sm) -> void:
	print("[PWD] --- RAW AUTHORED MODULE STATS (post tier_rebase, as loaded) ---")
	print("[PWD]   %-14s %-12s %-12s %-12s %-12s" % ["zone", "kinetic atk", "energy atk", "armor def/hp", "shield"])
	var prev := {}
	for z in range(1, 11):
		var k: float = _mstat(sm, "z%d_kinetic" % z, "atk_kinetic")
		var e: float = _mstat(sm, "z%d_energy" % z, "atk_energy")
		var ad: float = _mstat(sm, "z%d_armor" % z, "def")
		var ah: float = _mstat(sm, "z%d_armor" % z, "hp")
		var sh: float = _mstat(sm, "z%d_shield" % z, "max_shield")
		var rline := ""
		if prev.has("k") and float(prev["k"]) > 0.0:
			rline = "  step vs z%d: kin x%.3f  arm_hp x%.3f  shield x%.3f" % [
				z - 1, k / float(prev["k"]), ah / maxf(1.0, float(prev["ah"])), sh / maxf(1.0, float(prev["sh"]))]
		print("[PWD]   z%-13d %-12.0f %-12.0f %-12s %-12.0f%s" % [z, k, e, "%.0f/%.0f" % [ad, ah], sh, rline])
		prev = {"k": k, "ah": ah, "sh": sh}

func _dump_hull_table(sm) -> void:
	print("[PWD] --- HULLS ---")
	for t in range(1, 11):
		var hid := _hull_of_tier(sm, t)
		if hid == "":
			continue
		var h: Dictionary = sm.hulls[hid]
		var slots: Array = h.get("slots", [])
		var counts := {}
		for s in slots:
			counts[String(s)] = int(counts.get(String(s), 0)) + 1
		var cs := ""
		for st in SLOTS:
			cs += "%s=%d " % [st.substr(0, 3), int(counts.get(st, 0))]
		print("[PWD]   t%-2d %-22s hp=%-10.0f def=%-6.0f  %s" % [
			t, hid, float((h.get("stats", {}) as Dictionary).get("hp", 0)),
			float((h.get("stats", {}) as Dictionary).get("def", 0)), cs])

func _mstat(sm, mid: String, key: String) -> float:
	if not mid in sm.modules:
		return 0.0
	return float((sm.modules[mid].get("stats", {}) as Dictionary).get(key, 0))

func _hull_of_tier(sm, t: int) -> String:
	for h in sm.hulls:
		if int(sm.hulls[h].get("tier", 0)) == t:
			return String(h)
	return ""

# ---------------------------------------------------------------- per zone

func _zone_report(sm, cm, rm, tz: int) -> void:
	var zid := ""
	for z in cm.zones:
		if int(cm.zones[z].get("difficulty", 0)) == tz:
			zid = String(z)
			break
	if zid == "":
		print("[PWD] zone %d NOT FOUND" % tz)
		return
	var roster: Array = []
	for eid in cm.zones[zid].get("enemies", []):
		if roster.size() >= 4:
			break
		if not bool(cm.enemy_db.get(String(eid), {}).get("is_boss", false)):
			roster.append(String(eid))
	print("")
	print("[PWD] ############ ZONE %d (%s) ############" % [tz, zid])

	# The three kits. cfg = [label, gear_zone, rarity, hull_tier, forced_affixes]
	var cfgA: Array = ["A cfg1 Rare z%d FORCED" % (tz - 1), tz - 1, 2, tz - 1, true]
	var cfgR: Array = ["R cfg1 Rare z%d REALROLL" % (tz - 1), tz - 1, 2, tz - 1, false]
	var cfgB: Array = ["B cfg9 Common z%d" % tz, tz, 0, tz, true]

	# per-module raw ratio for the same slot type (the key number)
	_raw_pair_ratio(sm, tz)

	for i in range(roster.size()):
		var eid: String = roster[i]
		if i != 0 and i != 2:
			continue    # e1 (soft front) + e3 (hardened back half) are enough
		print("[PWD] ---- vs e%d %s  (hardened=%d) ----" % [
			i + 1, eid, cm.get_enemy_tier_hardened(eid, zid)])
		var ra: Dictionary = _measure(sm, cm, rm, tz, zid, eid, cfgA)
		var rr: Dictionary = _measure(sm, cm, rm, tz, zid, eid, cfgR)
		var rb: Dictionary = _measure(sm, cm, rm, tz, zid, eid, cfgB)
		_print_pair(ra, rb, tz)
		print("[PWD]   ===== CONTROL: probe-forced Rare (A) vs REAL-ROLL Rare (R) vs Common (B) =====")
		print("[PWD]   %-30s A=%-10.0f R=%-10.0f B=%-10.0f | B/A=%s  B/R=%s" % ["sm.attack",
			a_f(ra, "attack"), a_f(rr, "attack"), a_f(rb, "attack"),
			_rat(a_f(rb, "attack"), a_f(ra, "attack")), _rat(a_f(rb, "attack"), a_f(rr, "attack"))])
		print("[PWD]   %-30s A=%-10.0f R=%-10.0f B=%-10.0f | B/A=%s  B/R=%s" % ["measured DPS",
			a_f(ra, "dps"), a_f(rr, "dps"), a_f(rb, "dps"),
			_rat(a_f(rb, "dps"), a_f(ra, "dps")), _rat(a_f(rb, "dps"), a_f(rr, "dps"))])
		print("[PWD]   %-30s A=%-10.0f R=%-10.0f B=%-10.0f | B/A=%s  B/R=%s" % ["kills in %ds" % int(WINDOW),
			a_f(ra, "kills"), a_f(rr, "kills"), a_f(rb, "kills"),
			_rat(a_f(rb, "kills"), a_f(ra, "kills")), _rat(a_f(rb, "kills"), a_f(rr, "kills"))])
		print("[PWD]   %-30s A=%-10.0f R=%-10.0f B=%-10.0f | B/A=%s  B/R=%s" % ["EHP (max_hp+shield)",
			a_f(ra, "max_hp") + a_f(ra, "max_shield"), a_f(rr, "max_hp") + a_f(rr, "max_shield"),
			a_f(rb, "max_hp") + a_f(rb, "max_shield"),
			_rat(a_f(rb, "max_hp") + a_f(rb, "max_shield"), a_f(ra, "max_hp") + a_f(ra, "max_shield")),
			_rat(a_f(rb, "max_hp") + a_f(rb, "max_shield"), a_f(rr, "max_hp") + a_f(rr, "max_shield"))])
		print("[PWD]   %-30s A=%-10.2f R=%-10.2f B=%-10.2f" % ["p_speed_mult",
			a_f(ra, "p_speed_mult"), a_f(rr, "p_speed_mult"), a_f(rb, "p_speed_mult")])
		print("[PWD]   %-30s A=%-10.2f R=%-10.2f B=%-10.2f" % ["dmg_injured affix",
			float((ra["affix"] as Dictionary).get("dmg_injured", 0.0)),
			float((rr["affix"] as Dictionary).get("dmg_injured", 0.0)),
			float((rb["affix"] as Dictionary).get("dmg_injured", 0.0))])
		print("[PWD]   %-30s A=%-10.2f R=%-10.2f B=%-10.2f" % ["ship resist_k (cap .75)",
			a_f(ra, "resist_k"), a_f(rr, "resist_k"), a_f(rb, "resist_k")])
		print("[PWD]   R affixes: %s" % _nz(rr["affix"]))
		print("[PWD]   died  A=%s R=%s B=%s" % [str(ra.get("died", false)), str(rr.get("died", false)), str(rb.get("died", false))])

func a_f(d: Dictionary, k: String) -> float:
	return float(d.get(k, 0.0))

# Ratio of the raw stat on the SAME slot type: Common z(N) base vs a Rare z(N-1) roll.
func _raw_pair_ratio(sm, tz: int) -> void:
	print("[PWD] -- per-module RAW stat ratio Common z%d  vs  Rare z%d --" % [tz, tz - 1])
	var pairs := [
		["weapon kin", "z%d_kinetic" % tz, "z%d_kinetic" % (tz - 1), "atk_kinetic"],
		["weapon nrg", "z%d_energy" % tz, "z%d_energy" % (tz - 1), "atk_energy"],
		["weapon exp", "z%d_missile" % tz, "z%d_missile" % (tz - 1), "atk_explosive"],
		["armor def ", "z%d_armor" % tz, "z%d_armor" % (tz - 1), "def"],
		["armor hp  ", "z%d_armor" % tz, "z%d_armor" % (tz - 1), "hp"],
		["shield    ", "z%d_shield" % tz, "z%d_shield" % (tz - 1), "max_shield"],
	]
	for p in pairs:
		var newv: float = _mstat(sm, String(p[1]), String(p[3]))
		var oldv: float = _mstat(sm, String(p[2]), String(p[3]))
		if oldv <= 0.0 or newv <= 0.0:
			continue
		# empirical Rare roll: average 200 generated drops (rarity mult is random in range)
		var acc := 0.0
		var n := 200
		for _i in range(n):
			var cid := String(sm.generate_module_drop(String(p[2]), 2, tz - 1))
			if cid == "":
				continue
			acc += float((sm.modules[cid].get("stats", {}) as Dictionary).get(String(p[3]), 0))
			sm.modules.erase(cid)
			sm.custom_modules.erase(cid)
			sm.module_inventory.erase(cid)
		var rare_avg: float = acc / float(n)
		print("[PWD]    %s base z%d=%-11.0f base z%d=%-11.0f  tier step x%.3f | Rare z%d avg=%-11.0f | Common-N / Rare-(N-1) = x%.3f" % [
			String(p[0]), tz, newv, tz - 1, oldv, newv / oldv, tz - 1, rare_avg, newv / maxf(1.0, rare_avg)])

# ---------------------------------------------------------------- measure

func _measure(sm, cm, rm, tz: int, zid: String, eid: String, cfg: Array) -> Dictionary:
	var out: Dictionary = {"label": String(cfg[0])}
	# --- build once, snapshot every stat + the analytic damage model ---
	_build(sm, cm, rm, tz, zid, eid, cfg)
	if cm.current_enemy == null:
		out["fail"] = "no enemy"
		return out
	out.merge(_snapshot(sm, cm, cfg), true)
	out.merge(_analytic(sm, cm), true)
	_restore_base_affixes(sm)

	# --- fights ---
	var kills: Array = []
	var ttks: Array = []
	var dps: Array = []
	var died := false
	for _t in range(TRIALS):
		_build(sm, cm, rm, tz, zid, eid, cfg)
		if cm.current_enemy == null:
			continue
		var r: Dictionary = _fight(sm, cm)
		kills.append(int(r["kills"]))
		if float(r["ttk"]) > 0.0:
			ttks.append(float(r["ttk"]))
		dps.append(float(r["dps"]))
		if bool(r["died"]):
			died = true
		_restore_base_affixes(sm)
	kills.sort()
	ttks.sort()
	dps.sort()
	out["kills"] = int(kills[kills.size() / 2]) if not kills.is_empty() else 0
	out["ttk"] = float(ttks[ttks.size() / 2]) if not ttks.is_empty() else -1.0
	out["dps"] = float(dps[dps.size() / 2]) if not dps.is_empty() else 0.0
	out["died"] = died
	return out

func _fight(sm, cm) -> Dictionary:
	var t := 0.0
	var k0: int = int(cm.total_kills)
	var dmg := 0.0
	var ttk := -1.0
	var prev_pool: float = float(cm.enemy_hp) + float(cm.enemy_shield)
	var prev_k: int = int(cm.total_kills)
	while t < WINDOW:
		_kits(sm, cm)
		cm.process_tick(DT)
		t += DT
		var k: int = int(cm.total_kills)
		if k > prev_k:
			dmg += prev_pool                       # finished off the remaining pool
			if ttk < 0.0:
				ttk = t
			prev_k = k
			prev_pool = float(cm.enemy_hp) + float(cm.enemy_shield)
		else:
			var pool: float = float(cm.enemy_hp) + float(cm.enemy_shield)
			if pool < prev_pool:
				dmg += prev_pool - pool
			prev_pool = pool
		if sm.current_hp <= 0 or not cm.in_combat:
			return {"kills": int(cm.total_kills) - k0, "died": true, "ttk": ttk, "dps": dmg / maxf(0.1, t)}
	return {"kills": int(cm.total_kills) - k0, "died": false, "ttk": ttk, "dps": dmg / WINDOW}

# Stat + contribution snapshot of the CURRENT built ship.
func _snapshot(sm, cm, cfg: Array) -> Dictionary:
	var o: Dictionary = {}
	o["attack"] = float(sm.attack)
	o["defense"] = float(sm.defense)
	o["max_hp"] = float(sm.max_hp)
	o["max_shield"] = float(sm.max_shield)
	o["evasion"] = float(sm.evasion)
	o["crit"] = float(sm.crit_chance)
	o["e_used"] = float(sm.energy_used)
	o["e_cap"] = float(sm.energy_capacity)
	o["resist_k"] = float(sm.resist_k)
	o["resist_e"] = float(sm.resist_e)
	o["resist_x"] = float(sm.resist_x)
	o["atk_speed_bonus"] = float(sm.attack_speed_bonus)
	o["hull"] = String(sm.active_hull)
	o["hull_hp"] = float((sm.hulls[sm.active_hull].get("stats", {}) as Dictionary).get("hp", 0))
	o["hull_def"] = float((sm.hulls[sm.active_hull].get("stats", {}) as Dictionary).get("def", 0))

	# module base vs rarity delta, per stat
	var mb := {"atk": 0.0, "hp": 0.0, "def": 0.0, "shield": 0.0}
	var mr := {"atk": 0.0, "hp": 0.0, "def": 0.0, "shield": 0.0}
	var wcount := 0
	var wlines: Array = []
	var slot_fill := {}
	for i in sm.loadout:
		var mid = sm.loadout[i]
		if mid == null or not mid in sm.modules:
			continue
		var m: Dictionary = sm.modules[mid]
		var st: Dictionary = m.get("stats", {})
		var stype := String(m.get("slot_type", ""))
		slot_fill[stype] = int(slot_fill.get(stype, 0)) + 1
		var bid := String(m.get("base_module", mid))
		var bst: Dictionary = (sm.modules[bid].get("stats", {}) as Dictionary) if bid in sm.modules else st
		var a: float = float(st.get("atk_kinetic", 0)) + float(st.get("atk_energy", 0)) + float(st.get("atk_explosive", 0))
		var ba: float = float(bst.get("atk_kinetic", 0)) + float(bst.get("atk_energy", 0)) + float(bst.get("atk_explosive", 0))
		mb["atk"] += ba
		mr["atk"] += a - ba
		mb["hp"] += float(bst.get("hp", 0)); mr["hp"] += float(st.get("hp", 0)) - float(bst.get("hp", 0))
		mb["def"] += float(bst.get("def", 0)); mr["def"] += float(st.get("def", 0)) - float(bst.get("def", 0))
		mb["shield"] += float(bst.get("max_shield", 0)); mr["shield"] += float(st.get("max_shield", 0)) - float(bst.get("max_shield", 0))
		if stype == "weapon":
			wcount += 1
			wlines.append("slot%d %s atk=%.0f int=%.2f base_atk=%.0f rar=%d tier=%d pen(z)=%.3f affixes=%s" % [
				int(i), String(m.get("name", "?")), a, float(st.get("atk_interval", 2.5)), ba,
				int(sm.get_module_rarity(mid)), int(sm.get_module_tier(mid)),
				sm.module_tier_penetration(mid, int(cfg[1]) if false else int(cm.current_zone.get("difficulty", 1))),
				str((m.get("affixes", {}) as Dictionary).keys())])
	o["w_count"] = wcount
	o["w_lines"] = wlines
	o["slot_fill"] = slot_fill
	o["mod_base"] = mb
	o["mod_rarity"] = mr
	o["affix"] = sm.affix_bonuses.duplicate()
	o["gems"] = sm.gem_bonuses.duplicate()
	return o

# Analytic per-shot / per-second damage against the CURRENT enemy.
func _analytic(sm, cm) -> Dictionary:
	var o: Dictionary = {}
	var rm = GameState.research_manager
	var p_speed_mult: float = 1.0 + rm.get_efficiency_bonus("attack_speed")
	p_speed_mult += float(sm.affix_bonuses.get("servo_overclock", 0.0))
	var cooling_mult: float = 1.0 + float(sm.attack_speed_bonus)
	o["p_speed_mult"] = p_speed_mult
	o["cooling_mult"] = cooling_mult
	# v145: accuracy/evasion hit roll deleted from combat — every shot lands.
	o["hit_chance"] = 1.0
	o["e_hp"] = float(cm.enemy_max_hp)
	o["e_shield"] = float(cm.enemy_max_shield)
	o["e_def"] = float(cm.current_enemy.get("def", 0))
	o["e_atk"] = float(cm.current_enemy.get("atk", 0))

	# average one landed shot per weapon through the REAL resolve_damage
	var total_hull := 0.0
	var total_shield := 0.0
	var shots_per_sec := 0.0
	var saved_hp: float = float(cm.enemy_hp)
	var saved_sh: float = float(cm.enemy_shield)
	for w in cm.player_weapon_states:
		var interval: float = maxf(cm.MIN_ATTACK_INTERVAL, float(w["interval"]) / (p_speed_mult * cooling_mult))
		shots_per_sec += 1.0 / interval
		var sub_h := 0.0
		var sub_s := 0.0
		var n := 240
		for _i in range(n):
			# fresh full-HP enemy state so dmg_healthy/injured bands are honest:
			# sample half the shots at full HP, half in the injured band.
			cm.enemy_hp = int(cm.enemy_max_hp * (1.0 if _i % 2 == 0 else 0.2))
			cm.enemy_shield = 0.0
			var res: Array = cm.resolve_damage(
				float(w["dmg_k"]), float(w["dmg_e"]), float(w["dmg_x"]),
				0.0, float(cm.current_enemy.get("def", 0)),
				int(cm.current_zone.get("difficulty", 1)),
				float(sm.crit_chance), true, float(w.get("dmg_cryo", 0.0)), String(w.get("exotic_type", "cryo")))
			sub_h += float(res[1])
			# shield-side potential: re-run with a huge shield pool
			cm.enemy_shield = 1e12
			var res2: Array = cm.resolve_damage(
				float(w["dmg_k"]), float(w["dmg_e"]), float(w["dmg_x"]),
				1e12, float(cm.current_enemy.get("def", 0)),
				int(cm.current_zone.get("difficulty", 1)),
				float(sm.crit_chance), true, float(w.get("dmg_cryo", 0.0)), String(w.get("exotic_type", "cryo")))
			sub_s += float(res2[0])
		total_hull += sub_h / float(n)
		total_shield += sub_s / float(n)
	cm.enemy_hp = int(saved_hp)
	cm.enemy_shield = saved_sh
	o["shot_hull"] = total_hull            # summed over all weapons, one volley
	o["shot_shield"] = total_shield
	o["shots_per_sec"] = shots_per_sec
	o["hull_dps"] = total_hull * (shots_per_sec / maxf(1.0, float(cm.player_weapon_states.size()))) * float(o["hit_chance"])
	return o

# ---------------------------------------------------------------- print

func _print_pair(a: Dictionary, b: Dictionary, tz: int) -> void:
	if a.has("fail") or b.has("fail"):
		print("[PWD]   BUILD FAILED a=%s b=%s" % [str(a.get("fail", "")), str(b.get("fail", ""))])
		return
	print("[PWD]   %-38s | %-18s | %-18s | B/A" % ["metric", String(a["label"]), String(b["label"])])
	_row("hull", a, b, "hull", true)
	_rown("hull base hp", a, b, "hull_hp")
	_rown("sm.attack", a, b, "attack")
	_rown("sm.defense", a, b, "defense")
	_rown("sm.max_hp", a, b, "max_hp")
	_rown("sm.max_shield", a, b, "max_shield")
	_rown("crit_chance", a, b, "crit")
	print("[PWD]   %-38s | %-18s | %-18s |" % ["energy used/cap",
		"%.0f/%.0f" % [a["e_used"], a["e_cap"]], "%.0f/%.0f" % [b["e_used"], b["e_cap"]]])
	print("[PWD]   %-38s | %-18s | %-18s |" % ["slots filled", str(a["slot_fill"]), str(b["slot_fill"])])
	_rown("weapons equipped", a, b, "w_count")
	print("[PWD]   %-38s | %-18s | %-18s |" % ["ship resist k/e/x",
		"%.2f/%.2f/%.2f" % [a["resist_k"], a["resist_e"], a["resist_x"]],
		"%.2f/%.2f/%.2f" % [b["resist_k"], b["resist_e"], b["resist_x"]]])

	print("[PWD]   -- contribution split --")
	var am: Dictionary = a["mod_base"]; var bm: Dictionary = b["mod_base"]
	var ar: Dictionary = a["mod_rarity"]; var br: Dictionary = b["mod_rarity"]
	print("[PWD]   %-38s | %-18s | %-18s | %s" % ["ATK  module-base",
		"%.0f" % am["atk"], "%.0f" % bm["atk"], _rat(bm["atk"], am["atk"])])
	print("[PWD]   %-38s | %-18s | %-18s |" % ["ATK  rarity delta", "%.0f" % ar["atk"], "%.0f" % br["atk"]])
	print("[PWD]   %-38s | %-18s | %-18s |" % ["ATK  flat_atk affix",
		"%.0f" % float(a["affix"].get("flat_atk", 0.0)), "%.0f" % float(b["affix"].get("flat_atk", 0.0))])
	print("[PWD]   %-38s | %-18s | %-18s | %s" % ["HP   hull base",
		"%.0f" % a["hull_hp"], "%.0f" % b["hull_hp"], _rat(b["hull_hp"], a["hull_hp"])])
	print("[PWD]   %-38s | %-18s | %-18s | %s" % ["HP   module-base",
		"%.0f" % am["hp"], "%.0f" % bm["hp"], _rat(bm["hp"], am["hp"])])
	print("[PWD]   %-38s | %-18s | %-18s |" % ["HP   rarity delta", "%.0f" % ar["hp"], "%.0f" % br["hp"]])
	print("[PWD]   %-38s | %-18s | %-18s |" % ["HP   flat_hp AFFIX",
		"%.0f" % float(a["affix"].get("flat_hp", 0.0)), "%.0f" % float(b["affix"].get("flat_hp", 0.0))])
	print("[PWD]   %-38s | %-18s | %-18s |" % ["SHLD module-base+rarity",
		"%.0f" % (float(am["shield"]) + float(ar["shield"])), "%.0f" % (float(bm["shield"]) + float(br["shield"]))])
	print("[PWD]   %-38s | %-18s | %-18s |" % ["SHLD flat_shield AFFIX",
		"%.0f" % float(a["affix"].get("flat_shield", 0.0)), "%.0f" % float(b["affix"].get("flat_shield", 0.0))])
	print("[PWD]   %-38s | %-18s | %-18s |" % ["DEF  hull+module-base",
		"%.0f" % (float(a["hull_def"]) + float(am["def"])), "%.0f" % (float(b["hull_def"]) + float(bm["def"]))])
	print("[PWD]   %-38s | %-18s | %-18s |" % ["gem bonuses", str(a["gems"]), str(b["gems"])])

	print("[PWD]   -- live affix_bonuses (non-zero only) --")
	print("[PWD]     A: %s" % _nz(a["affix"]))
	print("[PWD]     B: %s" % _nz(b["affix"]))

	print("[PWD]   -- damage pipeline --")
	_rown("p_speed_mult (research+servo)", a, b, "p_speed_mult")
	_rown("cooling_mult (1+atk_speed_bonus)", a, b, "cooling_mult")
	_rown("volley shots/sec (all weapons)", a, b, "shots_per_sec")
	_rown("avg HULL dmg / landed volley", a, b, "shot_hull")
	_rown("avg SHIELD dmg / landed volley", a, b, "shot_shield")
	_rown("analytic hull DPS", a, b, "hull_dps")
	print("[PWD]   -- enemy --  hp=%.0f shield=%.0f def=%.0f atk=%.0f" % [
		a["e_hp"], a["e_shield"], a["e_def"], a["e_atk"]])

	print("[PWD]   -- measured fight (%ds, median of %d) --" % [int(WINDOW), TRIALS])
	_rown("kills", a, b, "kills")
	_rown("time-to-first-kill (s)", a, b, "ttk")
	_rown("measured DPS (hp+shield/s)", a, b, "dps")
	print("[PWD]   %-38s | %-18s | %-18s |" % ["died", str(a["died"]), str(b["died"])])
	for l in a["w_lines"]:
		print("[PWD]     A weapon: %s" % String(l))
	for l in b["w_lines"]:
		print("[PWD]     B weapon: %s" % String(l))

func _row(label: String, a: Dictionary, b: Dictionary, key: String, _s: bool) -> void:
	print("[PWD]   %-38s | %-18s | %-18s |" % [label, str(a.get(key, "")), str(b.get(key, ""))])

func _rown(label: String, a: Dictionary, b: Dictionary, key: String) -> void:
	var av: float = float(a.get(key, 0.0))
	var bv: float = float(b.get(key, 0.0))
	print("[PWD]   %-38s | %-18.3f | %-18.3f | %s" % [label, av, bv, _rat(bv, av)])

func _rat(bv: float, av: float) -> String:
	if absf(av) < 1e-9:
		return "n/a"
	return "x%.3f" % (bv / av)

func _nz(d: Dictionary) -> String:
	var out: Array = []
	for k in d:
		if absf(float(d[k])) > 1e-9:
			out.append("%s=%.3f" % [String(k), float(d[k])])
	return ", ".join(out)

# ---------------------------------------------------------------- kit build
# Bit-identical to z3_funnel._run / _fill for configs 1 and 9.

func _build(sm, cm, rm, tz: int, zid: String, eid: String, cfg: Array) -> void:
	GameState.hard_reset()
	cm.total_kills = 0
	var gz: int = int(cfg[1])
	var rar: int = int(cfg[2])
	var ht: int = int(cfg[3])
	for tid in rm.tech_tree:
		if int(rm.tech_tree[tid].get("tier", 99)) <= tz and not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)
	_set_hull(sm, ht)
	var e: Dictionary = cm.enemy_db.get(eid, {})
	var weak := _weak(e)
	var side_rar: int = 2 if rar == 4 else rar
	var forced: bool = true
	if cfg.size() > 4:
		forced = bool(cfg[4])
	var wa: Array = W_AFF if forced else []
	var aa: Array = A_AFF if forced else []
	var sa: Array = S_AFF if forced else []
	_fill(sm, "battery", "z%d_battery" % gz, gz, min(side_rar, 3), [])
	_fill(sm, "weapon", "z%d_%s" % [gz, SUFFIX[weak]], gz, rar, wa)
	_fill(sm, "armor", "z%d_armor" % gz, gz, rar, aa)
	_fill(sm, "shield", "z%d_shield" % gz, gz, rar, sa)
	_fill(sm, "engine", "z%d_engine" % gz, gz, 0, [])
	_fill(sm, "sensor", "z%d_sensor" % gz, gz, min(side_rar, 3), [])
	_ammo_kits(sm, weak)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	cm.start_expedition(zid)
	cm.set_target_enemy(eid)

func _fill(sm, stype: String, base_id: String, zone: int, rarity: int, affixes: Array) -> void:
	if not base_id in sm.modules:
		return
	for i in _slots(sm, stype):
		var cid := String(sm.generate_module_drop(base_id, rarity, zone))
		if cid == "":
			continue
		var m: Dictionary = sm.modules[cid]
		if not affixes.is_empty():
			# NOTE: for rarity COMMON, cid == base_id, so this MUTATES the shared base
			# module. Back it up so the mutation cannot leak into the next build.
			if cid == base_id and not _base_affix_backup.has(cid):
				_base_affix_backup[cid] = (m.get("affixes", {}) as Dictionary).duplicate()
			var out := {}
			for p in affixes:
				var aid := String(p)
				if not sm.AFFIX_DB.has(aid):
					continue
				var lim: Array = sm.AFFIX_DB[aid].get("limit_to", [])
				if lim.is_empty() or (stype in lim):
					out[aid] = float(sm._roll_affix_value(aid, zone, 1.0)["value"])
			m["affixes"] = out
		sm.equip_module(i, cid, true)

func _restore_base_affixes(sm) -> void:
	for mid in _base_affix_backup:
		if mid in sm.modules:
			sm.modules[mid]["affixes"] = (_base_affix_backup[mid] as Dictionary).duplicate()
	_base_affix_backup.clear()

func _weak(e: Dictionary) -> String:
	var best := "kinetic"
	var bv: float = float(e.get("resist_k", 0.0))
	if float(e.get("resist_e", 0.0)) < bv:
		bv = float(e.get("resist_e", 0.0)); best = "energy"
	if float(e.get("resist_x", 0.0)) < bv:
		best = "explosive"
	return best

func _set_hull(sm, n: int) -> void:
	for h in sm.hulls:
		if int(sm.hulls[h].get("tier", 0)) == clampi(n, 1, 10):
			sm.active_hull = String(h)
			break
	sm.loadout.clear()
	sm.ammo_loadout.clear()
	sm.consumable_hull_slot = ""
	sm.consumable_shield_slot = ""

func _slots(sm, stype: String) -> Array:
	var out: Array = []
	var slots: Array = sm.hulls.get(sm.active_hull, {}).get("slots", [])
	for i in range(slots.size()):
		if String(slots[i]) == stype:
			out.append(i)
	return out

func _ammo_kits(sm, weak: String) -> void:
	var ammo := "%sT2" % AMMO[weak]
	if not ElementDB.ELEMENT_NAMES.has(ammo):
		ammo = "%sT1" % AMMO[weak]
	GameState.resources.add_element(ammo, 1000000)
	for i in _slots(sm, "weapon"):
		sm.ammo_loadout[i] = ammo
	GameState.resources.add_element("EmergencyPatch", 100000)
	GameState.resources.add_element("BasicBooster", 100000)
	sm.equip_consumable("hull", "EmergencyPatch")
	sm.equip_consumable("shield", "BasicBooster")

func _kits(sm, cm) -> void:
	if not cm.in_combat:
		return
	if sm.current_hp < sm.max_hp * 0.20 and sm.consumable_hull_slot != "":
		cm.use_manual_consumable("hull")
	if cm.player_shield < cm.player_max_shield * 0.30 and sm.consumable_shield_slot != "":
		cm.use_manual_consumable("shield")
