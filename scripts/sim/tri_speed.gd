extends Node
# ============================================================================
# TRIANGLE SPEED DUEL (owner rule, 2026-07-26)
#
# The funnel (z3_funnel.gd) always equips the enemy's LOWEST-resist weapon, so
# it only ever measures the FAST path. It CANNOT tell you whether the resisted
# type is unfarmable or whether natural is meaningfully slower than weak.
#
# This probe fixes the gear (row 9 of the funnel: clean Common tier-N set on a
# tier-N hull, real consumables) and varies ONLY the weapon damage channel:
#
#   RESISTED = the channel with the enemy's highest resist  -> must NOT farm
#   NATURAL  = the channel at 0.0                           -> farms, slowly
#   WEAK     = the channel with the enemy's lowest resist    -> farms fast
#
# Reports kills in a 180s window and seconds-per-kill for each.
#
#   Godot --headless --path <root> res://scenes/tri_speed.tscn -- --zone=N
# ============================================================================

const DT := 0.1
const WINDOW := 180.0
const FARM_KILLS := 5
const TRIALS := 5

const SUFFIX := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}
const AMMO := {"kinetic": "Slug", "energy": "Cell", "explosive": "Missile"}

# --neutral mode: same fixed gear, but every spawned enemy's resist_k/e/x are
# forced to 0.0, so what is left is the INTRINSIC channel throughput (weapon base
# atk x channel coefficient x armour divisor x shield weight). Measured as
# time-to-N-kills rather than kills-in-a-window: kills-in-180s quantises to
# integers and cannot express a 12% ratio difference.
const NEUT_KILLS := 20
const NEUT_CAP := 1200.0
const NEUT_TRIALS := 5

var ZONES := [2, 3, 4, 5, 6, 7, 8, 9, 10]
var NEUTRAL := false
# --fine: same time-to-N-kills instrument as --neutral, but resists are LEFT ON.
# Integer kills-in-180s cannot resolve a weak-vs-natural margin under ~1.2x; this
# can. Reports s/kill for RESISTED / NATURAL / WEAK and the weak:natural ratio.
var FINE := false

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--zone="):
			ZONES = [int(String(a).split("=")[1])]
		if String(a) == "--neutral":
			NEUTRAL = true
		if String(a) == "--fine":
			FINE = true
			NEUTRAL = true
		if String(a).begins_with("--zones="):
			ZONES = []
			for p in String(a).split("=")[1].split(","):
				ZONES.append(int(p))
	if NEUTRAL:
		_neutral_report(sm, cm, rm)
		get_tree().quit(0)
		return
	print("[TRI] ===== TRIANGLE SPEED DUEL — gear FIXED (Common tier-N, hull N), weapon channel VARIED =====")
	print("[TRI] farm bar = >=%d kills in %ds with no death. s/kill = %d/kills." % [FARM_KILLS, int(WINDOW), int(WINDOW)])
	var _bands: Array = []
	for _z in ZONES:
		_bands.append("Z%d=%s" % [_z, ElementDB.get_ammo_band_for_zone(int(_z))])
	print("[TRI] ammo band per zone (ElementDB.get_ammo_band_for_zone): " + ", ".join(_bands))
	print("[TRI] %-24s %-22s %-22s %-22s" % ["zone / enemy", "RESISTED", "NATURAL", "WEAK"])
	print("[TRI] " + "-".repeat(94))
	for tz in ZONES:
		var zid := ""
		for z in cm.zones:
			if int(cm.zones[z].get("difficulty", 0)) == tz:
				zid = String(z)
				break
		if zid == "":
			continue
		for eid in cm.zones[zid].get("enemies", []):
			var e: Dictionary = cm.enemy_db.get(String(eid), {})
			# Bosses are excluded: a clean Common set loses to every boss by design
			# (boss_gearcheck owns that invariant), so all three channels read "D"
			# and tell you nothing about relative speed.
			if e.is_empty() or bool(e.get("is_boss", false)):
				continue
			var roles := _roles(e)
			var line := "[TRI] %-24s" % ("Z%d %s" % [tz, String(e.get("name", eid)).substr(0, 18)])
			for role in ["resisted", "natural", "weak"]:
				var ch: String = String(roles[role])
				var r: Dictionary = _cell(sm, cm, rm, String(eid), zid, tz, ch)
				var k: int = int(r["kills"])
				var spk := ("%.0f" % (WINDOW / float(k))) if k > 0 else "inf"
				var mark := "D" if bool(r["died"]) else ("*" if k >= FARM_KILLS else " ")
				line += " %-22s" % ("%s %d%s (%ss/kill)" % [ch.substr(0, 3).to_upper(), k, mark, spk])
			print(line)
		print("[TRI] " + "-".repeat(94))
	print("[TRI] * = farms | D = DIED | RESISTED must be blank/D, NATURAL should farm slowly, WEAK fast.")
	get_tree().quit(0)

# Highest resist = resisted, lowest = weak, remainder = natural.
func _roles(e: Dictionary) -> Dictionary:
	var v := {"kinetic": float(e.get("resist_k", 0.0)), "energy": float(e.get("resist_e", 0.0)), "explosive": float(e.get("resist_x", 0.0))}
	var hi := "kinetic"
	var lo := "kinetic"
	for c in v:
		if float(v[c]) > float(v[hi]):
			hi = String(c)
		if float(v[c]) < float(v[lo]):
			lo = String(c)
	var mid := "kinetic"
	for c in v:
		if String(c) != hi and String(c) != lo:
			mid = String(c)
	return {"resisted": hi, "natural": mid, "weak": lo}

func _cell(sm, cm, rm, eid: String, zid: String, tz: int, chan: String) -> Dictionary:
	var ks: Array = []
	var died := false
	for _t in range(TRIALS):
		var r: Dictionary = _run(sm, cm, rm, eid, zid, tz, chan)
		ks.append(int(r["kills"]))
		if bool(r["died"]):
			died = true
	ks.sort()
	return {"kills": ks[ks.size() / 2], "died": died}

func _setup(sm, cm, rm, eid: String, zid: String, tz: int, chan: String) -> bool:
	GameState.hard_reset()
	cm.total_kills = 0
	for tid in rm.tech_tree:
		if int(rm.tech_tree[tid].get("tier", 99)) <= tz and not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)
	_set_hull(sm, tz)
	_fill(sm, "battery", "z%d_battery" % tz, tz)
	_fill(sm, "weapon", "z%d_%s" % [tz, SUFFIX[chan]], tz)
	_fill(sm, "armor", "z%d_armor" % tz, tz)
	_fill(sm, "shield", "z%d_shield" % tz, tz)
	_fill(sm, "engine", "z%d_engine" % tz, tz)
	_fill(sm, "sensor", "z%d_sensor" % tz, tz)
	_ammo_kits(sm, chan, tz)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	if sm.energy_used > sm.energy_capacity:
		return false
	cm.start_expedition(zid)
	cm.set_target_enemy(eid)
	return cm.current_enemy != null

func _run(sm, cm, rm, eid: String, zid: String, tz: int, chan: String) -> Dictionary:
	if not _setup(sm, cm, rm, eid, zid, tz, chan):
		return {"kills": 0, "died": false}
	var t := 0.0
	var k0: int = int(cm.total_kills)
	while t < WINDOW:
		_kits(sm, cm)
		cm.process_tick(DT)
		t += DT
		if sm.current_hp <= 0 or not cm.in_combat:
			return {"kills": int(cm.total_kills) - k0, "died": true}
	return {"kills": int(cm.total_kills) - k0, "died": false}

func _fill(sm, stype: String, base_id: String, zone: int) -> void:
	if not base_id in sm.modules:
		return
	for i in _slots(sm, stype):
		var cid := String(sm.generate_module_drop(base_id, 0, zone))
		if cid == "":
			continue
		sm.equip_module(i, cid, true)

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

func _ammo_kits(sm, chan: String, tz: int) -> void:
	# v152 PROBE-HONESTY FIX. This used to hardcode "T2" at EVERY zone, which is
	# wrong in BOTH directions since the v150 ammo bands shipped: it over-fed
	# Z1-Z3 (band T1, so +10% free damage that no real player has there) and
	# under-fed Z7-Z10 (band T3, so -9% vs what a real player runs). Both errors
	# land squarely on the channel-throughput ratio this probe exists to measure.
	# Single source of truth is ElementDB — do NOT re-derive the band here.
	var band := ElementDB.get_ammo_band_for_zone(tz)
	var ammo := String(ElementDB.get_band_ammo_id(chan, band))
	if ammo == "" or not ElementDB.ELEMENT_NAMES.has(ammo):
		ammo = "%sT1" % AMMO[chan]
	GameState.resources.add_element(ammo, 1000000)
	for i in _slots(sm, "weapon"):
		sm.ammo_loadout[i] = ammo
	GameState.resources.add_element("EmergencyPatch", 100000)
	GameState.resources.add_element("BasicBooster", 100000)
	sm.equip_consumable("hull", "EmergencyPatch")
	sm.equip_consumable("shield", "BasicBooster")

# ── NEUTRAL MODE ────────────────────────────────────────────────────────────
# Zero every resist on the live enemy each tick (spawn_enemy re-copies them from
# the def on every respawn, so a one-shot patch would only hold for one kill),
# then measure seconds-per-kill. Enemy EHP is identical across the three runs,
# so 1 / (s/kill) IS the normalized intrinsic throughput of the channel.
func _run_neutral(sm, cm, rm, eid: String, zid: String, tz: int, chan: String) -> Dictionary:
	if not _setup(sm, cm, rm, eid, zid, tz, chan):
		return {"kills": 0, "t": 0.0, "died": true}
	var t := 0.0
	var k0: int = int(cm.total_kills)
	while t < NEUT_CAP:
		if cm.current_enemy != null and not FINE:
			cm.current_enemy["resist_k"] = 0.0
			cm.current_enemy["resist_e"] = 0.0
			cm.current_enemy["resist_x"] = 0.0
		_kits(sm, cm)
		cm.process_tick(DT)
		t += DT
		if sm.current_hp <= 0 or not cm.in_combat:
			return {"kills": int(cm.total_kills) - k0, "t": t, "died": true}
		if int(cm.total_kills) - k0 >= NEUT_KILLS:
			return {"kills": int(cm.total_kills) - k0, "t": t, "died": false}
	return {"kills": int(cm.total_kills) - k0, "t": t, "died": false}

func _neutral_report(sm, cm, rm) -> void:
	if FINE:
		_fine_report(sm, cm, rm)
		return
	print("[NEU] ===== NEUTRAL-ENEMY CHANNEL THROUGHPUT (all resists forced 0.0) =====")
	print("[NEU] same fixed gear as the duel; target %d kills, cap %ds, median of %d trials." % [NEUT_KILLS, int(NEUT_CAP), NEUT_TRIALS])
	print("[NEU] %-26s %-16s %-16s %-16s %s" % ["zone / enemy", "KIN s/kill", "NRG s/kill", "EXP s/kill", "ratio KIN:NRG:EXP"])
	for tz in ZONES:
		var zid := ""
		for z in cm.zones:
			if int(cm.zones[z].get("difficulty", 0)) == tz:
				zid = String(z)
				break
		if zid == "":
			continue
		var zsum := {"kinetic": 0.0, "energy": 0.0, "explosive": 0.0}
		var zn := 0
		for eid in cm.zones[zid].get("enemies", []):
			var e: Dictionary = cm.enemy_db.get(String(eid), {})
			if e.is_empty() or bool(e.get("is_boss", false)):
				continue
			var spk := {}
			var line := "[NEU] %-26s" % ("Z%d %s" % [tz, String(e.get("name", eid)).substr(0, 20)])
			var ok := true
			for ch in ["kinetic", "energy", "explosive"]:
				var vals: Array = []
				var died := false
				for _t in range(NEUT_TRIALS):
					var r: Dictionary = _run_neutral(sm, cm, rm, String(eid), zid, tz, String(ch))
					if int(r["kills"]) <= 0:
						vals.append(9999.0)
						died = true
						continue
					if bool(r["died"]):
						died = true
					vals.append(float(r["t"]) / float(r["kills"]))
				vals.sort()
				spk[ch] = float(vals[vals.size() / 2])
				if died:
					ok = false
				line += " %-16s" % ("%.1f%s" % [spk[ch], "D" if died else ""])
			# throughput = 1/(s/kill); normalize so the smallest is 1.00
			var tp := {}
			for ch in ["kinetic", "energy", "explosive"]:
				tp[ch] = (1.0 / float(spk[ch])) if float(spk[ch]) > 0.0 else 0.0
			var lo: float = min(min(float(tp["kinetic"]), float(tp["energy"])), float(tp["explosive"]))
			if lo > 0.0:
				line += " %.2f : %.2f : %.2f" % [float(tp["kinetic"]) / lo, float(tp["energy"]) / lo, float(tp["explosive"]) / lo]
				if ok:
					for ch in ["kinetic", "energy", "explosive"]:
						zsum[ch] = float(zsum[ch]) + float(tp[ch]) / lo
					zn += 1
			print(line)
		if zn > 0:
			var zlo: float = min(min(float(zsum["kinetic"]), float(zsum["energy"])), float(zsum["explosive"])) / float(zn)
			print("[NEU] ZONE %d MEAN RATIO KIN:NRG:EXP = %.2f : %.2f : %.2f  (over %d clean cells)" % [tz, (float(zsum["kinetic"]) / float(zn)) / zlo, (float(zsum["energy"]) / float(zn)) / zlo, (float(zsum["explosive"]) / float(zn)) / zlo, zn])
		print("[NEU] " + "-".repeat(94))

func _kits(sm, cm) -> void:
	if not cm.in_combat:
		return
	if sm.current_hp < sm.max_hp * 0.20 and sm.consumable_hull_slot != "":
		cm.use_manual_consumable("hull")
	if cm.player_shield < cm.player_max_shield * 0.30 and sm.consumable_shield_slot != "":
		cm.use_manual_consumable("shield")


# ── FINE MODE ───────────────────────────────────────────────────────────────
# Resists ON, measured as time-to-N-kills so a sub-1.2x weak-vs-natural margin
# is visible (the 180s kill-count duel quantises it away).
func _fine_report(sm, cm, rm) -> void:
	print("[FIN] ===== TRIANGLE, FINE (resists ON, time-to-%d-kills, median of %d) =====" % [NEUT_KILLS, NEUT_TRIALS])
	print("[FIN] %-26s %-18s %-18s %-18s %s" % ["zone / enemy", "RESISTED s/kill", "NATURAL s/kill", "WEAK s/kill", "weak:natural  natural:resisted"])
	for tz in ZONES:
		var zid := ""
		for z in cm.zones:
			if int(cm.zones[z].get("difficulty", 0)) == tz:
				zid = String(z)
				break
		if zid == "":
			continue
		for eid in cm.zones[zid].get("enemies", []):
			var e: Dictionary = cm.enemy_db.get(String(eid), {})
			if e.is_empty() or bool(e.get("is_boss", false)):
				continue
			var roles := _roles(e)
			var spk := {}
			var line := "[FIN] %-26s" % ("Z%d %s" % [tz, String(e.get("name", eid)).substr(0, 20)])
			for role in ["resisted", "natural", "weak"]:
				var ch: String = String(roles[role])
				var vals: Array = []
				var died := false
				for _t in range(NEUT_TRIALS):
					var r: Dictionary = _run_neutral(sm, cm, rm, String(eid), zid, tz, ch)
					if int(r["kills"]) <= 0:
						vals.append(99999.0)
						died = true
						continue
					if bool(r["died"]):
						died = true
					vals.append(float(r["t"]) / float(r["kills"]))
				vals.sort()
				spk[role] = float(vals[vals.size() / 2])
				line += " %-18s" % ("%s %.1f%s" % [ch.substr(0, 3).to_upper(), spk[role], "D" if died else ""])
			var wn: float = float(spk["natural"]) / maxf(0.001, float(spk["weak"]))
			var nr: float = float(spk["resisted"]) / maxf(0.001, float(spk["natural"]))
			line += " %.2fx  %.2fx" % [wn, nr]
			print(line)
		print("[FIN] " + "-".repeat(110))
	print("[FIN] weak:natural must be > 1.00. natural:resisted is the experienced cut (authored target 2.93x = 65.9%%).")
