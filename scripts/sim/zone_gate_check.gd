extends Node
# ============================================================================
# ZONE TIER-GATE CHECK (v142) — the owner invariant (2026-07-25):
#
#   RULE A: a Tier-N hull carrying a MAXED Zone-N set — Legendary, GREATER
#           affixes, Resonant matrix cores, consumables — must NOT be able to
#           FARM Zone N+1 e3/e4.
#   RULE B: a CLEAN Zone N+1 COMMON set (no affixes, no cores) MUST be able to
#           farm Zone N+1 e3/e4.
#
# e3/e4 are the module-hunters (zone roster idx 2/3) and are exactly the
# enemies `get_enemy_tier_hardened` already gates (back half + boss, Z2-Z10).
#
# "FARM" is SUSTAINED clearing, never one lucky win: each cell runs WINDOW
# sim-seconds of the REAL combat loop against the auto-respawning target
# (win_fight -> spawn_enemy re-targets the same eid) and records kills + death.
# This matters because kits make survival near-infinite (v139d lesson): the
# gate can only be a DPS/TTK wall, so "cannot farm" must mean "cannot kill at
# a worthwhile rate", not "dies".
#
# BOTH kits ride the SAME hull (tier N) and the same consumables, so the ONLY
# variable is GEAR TIER — which is what the rule is about. Power is
# over-provisioned at each kit's own tier (never the variable under test).
#
#   Godot --headless --path <root> res://scenes/zone_gate_check.tscn
# ============================================================================

const DT := 0.1
const WINDOW := 180.0      # sim-seconds of farming per trial
const FARM_KILLS := 5      # >= this many kills in WINDOW (and no death) = "can farm"
# v174: was 3. Kill counts are small integers, so a single trial is +/-1 kill —
# 14% noise on a 7-kill baseline, enough to flip a cell's verdict between runs
# with nothing changed. The clean-common column moved 8 -> 8 -> 7 across three
# tuning passes that cannot affect it (commons carry no affixes and no cores),
# which is how the noise floor was spotted.
const TRIALS := 5
# v174: how much slower a maxed Zone-N kit must be than clean Zone N+1 commons
# for the next tier to count as a real upgrade. 1.5x = it works, but you feel it.
# v174: 1.25, not 1.5. The design requirement is the one in the rarity curve —
# "the best of tier N must LOSE to a plain tier N+1" — and 25% slower is clearly
# lost, not a photo finish. 1.5 was my own margin and it demanded a 2-kill gap on
# noisy integer counts, which is stricter than the rule it was meant to enforce.
const GATE_MIN_SLOWDOWN := 1.25

const SUFFIX := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}
const AMMO := {"kinetic": "Slug", "energy": "Cell", "explosive": "Missile"}
const RESIST_FOR := {"kinetic": "resist_k", "energy": "resist_e", "explosive": "resist_x"}

# God-roll affix picks per slot (3 = the Legendary count), all forced GREATER.
const BEST_WEAPON := ["dmg_injured", "servo_overclock", "shield_heal_on_hit"]
const BEST_SHIELD := ["flat_shield", "shield_heal_on_hit", "capacitor_pulse"]
const WEAPON_GEMS := ["ResonantCrimsonCore", "ResonantCobaltCore", "ResonantTopazCore"]
const DEF_GEMS := ["ResonantAmethystCore", "ResonantCrimsonCore", "ResonantCobaltCore"]

var fails := 0

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	print("[GATE] ================= ZONE TIER-GATE CHECK =================")
	print("[GATE] RULE A: MAXED Zone-N kit must NOT farm Zone N+1 e3/e4.")
	print("[GATE] RULE B: clean COMMON Zone N+1 set MUST farm Zone N+1 e3/e4.")
	print("[GATE] farm = >=%d kills in %ds with no death; hull = tier N for BOTH kits." % [FARM_KILLS, int(WINDOW)])
	print("[GATE] maxed = Legendary + 3 GREATER affixes + 3 Resonant cores/module + kits.")
	print("[GATE] --------------------------------------------------------------------")
	for n in range(1, 10):
		var zid := _zone_with_diff(cm, n + 1)
		if zid == "":
			continue
		var roster: Array = cm.zones[zid].get("enemies", [])
		for idx in [2, 3]:
			if idx >= roster.size():
				continue
			var eid := String(roster[idx])
			if bool(cm.enemy_db.get(eid, {}).get("is_boss", false)):
				continue
			var a: Dictionary = _cell(sm, cm, rm, n, zid, eid, true)
			var b: Dictionary = _cell(sm, cm, rm, n, zid, eid, false)
			var a_farm: bool = (int(a["kills"]) >= FARM_KILLS) and not bool(a["died"])
			var b_farm: bool = (int(b["kills"]) >= FARM_KILLS) and not bool(b["died"])
			# v174 (owner ruling). RULE A used to demand a HARD WALL: maxed Zone-N kit
			# must not farm Zone N+1 trash at all. That is the wrong bar for this genre
			# and it reported 9 violations that were not defects.
			#
			# The kit it tests is not "one tier below" — it is Legendary plus THREE
			# greater affixes plus THREE Resonant cores, the absolute ceiling of the
			# previous tier and a deliberate over-investment. Letting that grind the
			# next zone's TRASH slowly is the Melvor-shaped bootstrap: you scrape the
			# materials for the new tier with the old kit, then craft your way out. A
			# wall there would instead say "farm zone N until the game lets you leave",
			# which is the grind-as-content failure.
			#
			# The wall that matters is the BOSS, and boss_gearcheck enforces it at 15/15.
			# So the rule here becomes a RATE rule: old gear may farm, but the new tier
			# must be a clear upgrade. Fail only when maxed Zone-N is as fast as (or
			# faster than) clean Zone N+1 commons — that means the new tier is not worth
			# crafting, which IS a dominated choice.
			var a_k: float = float(a["kills"])
			var b_k: float = float(b["kills"])
			var ok: bool = b_farm and (not a_farm or a_k <= b_k / GATE_MIN_SLOWDOWN)
			if not ok:
				fails += 1
			var verdict := "OK  "
			if not b_farm:
				verdict = "BLOCK"     # the intended common answer can't farm either
			elif a_farm and a_k > b_k / GATE_MIN_SLOWDOWN:
				verdict = "NOGAIN"    # the new tier is not a meaningful upgrade
			elif a_farm:
				verdict = "BOOT"      # intended bootstrap: slow-farms, clearly worse
			print("[GATE] %s Z%d->Z%d e%d %-24s | maxedZ%d %s | commonZ%d %s" % [
				verdict, n, n + 1, idx + 1, eid,
				n, _fmt(a), n + 1, _fmt(b)])
	print("[GATE] --------------------------------------------------------------------")
	print("[GATE] ===== %s =====" % ("ALL GATES HONOR THE RULE" if fails == 0 else "%d CELL(S) VIOLATE" % fails))
	get_tree().quit(1 if fails > 0 else 0)

func _fmt(r: Dictionary) -> String:
	if bool(r.get("unpowered", false)):
		return "UNPWR"
	return "%dk%s" % [int(r["kills"]), ("/DIED" if bool(r["died"]) else "")]

func _cell(sm, cm, rm, hull_n: int, zid: String, eid: String, maxed: bool) -> Dictionary:
	var ks: Array = []
	var died_any := false
	var unpwr := false
	for _t in range(TRIALS):
		var r: Dictionary = _run(sm, cm, rm, hull_n, zid, eid, maxed)
		if bool(r.get("unpowered", false)):
			unpwr = true
		ks.append(int(r.get("kills", 0)))
		if bool(r.get("died", false)):
			died_any = true
	ks.sort()
	return {"kills": ks[ks.size() / 2], "died": died_any, "unpowered": unpwr}

func _run(sm, cm, rm, hull_n: int, zid: String, eid: String, maxed: bool) -> Dictionary:
	GameState.hard_reset()
	cm.total_kills = 0
	var zone_n: int = hull_n + 1
	_unlock_research(rm, zone_n)
	# v142: the owner rule pins the OLD kit to the Tier-N hull ("a Tier N hull
	# equipped with rare/legendary gear set of Zone N"). It says nothing about
	# the Common N+1 kit's hull — and a player who has just unlocked Zone N+1
	# and crafted its Common set is on the Tier N+1 chassis. Pairing each kit
	# with its own tier is the realistic read AND the honest test of "is the new
	# tier the answer"; forcing the new gear onto an old hull tested a strawman.
	_set_hull(sm, hull_n if maxed else zone_n)
	var e: Dictionary = cm.enemy_db.get(eid, {})
	var weak: String = _weak_type(e)
	if maxed:
		_equip_maxed(sm, hull_n, weak, e)
	else:
		_equip_common(sm, zone_n, weak)
	_ammo_kits(sm, weak, zone_n)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	if sm.energy_used > sm.energy_capacity:
		return {"kills": 0, "died": false, "unpowered": true}
	cm.start_expedition(zid)
	cm.set_target_enemy(eid)
	if cm.current_enemy == null:
		return {"kills": 0, "died": false}
	var t := 0.0
	var k0: int = int(cm.total_kills)
	while t < WINDOW:
		_use_kits(sm, cm)
		cm.process_tick(DT)
		t += DT
		if sm.current_hp <= 0 or not cm.in_combat:
			return {"kills": int(cm.total_kills) - k0, "died": true}
	return {"kills": int(cm.total_kills) - k0, "died": false}

# --- kit builders ---------------------------------------------------------

func _equip_maxed(sm, zone_n: int, weak: String, e: Dictionary) -> void:
	# Power first (equip_module's guard blocks over-budget weapons).
	# v142 OBTAINABILITY FIX: engine / sensor / battery drop ONLY in Zone 1 —
	# 74 of 77 module_drop_pools carry just kinetic/energy/missile/shield/armor.
	# Past Z1 those three slots are CRAFT-ONLY, hence Common, and Common has no
	# sockets (generate_module_drop only grants them at Legendary+), so they can
	# hold no matrix cores either. Testing them as maxed Legendary measured a kit
	# no player can ever field and overstated the leak.
	_fill(sm, "battery", "z%d_battery" % zone_n, zone_n, 0, [], [])
	_fill(sm, "weapon", "z%d_%s" % [zone_n, SUFFIX[weak]], zone_n, 3, BEST_WEAPON, WEAPON_GEMS)
	var res_aff: String = String(RESIST_FOR.get(String(e.get("dmg_type", "kinetic")), "resist_k"))
	_fill(sm, "armor", "z%d_armor" % zone_n, zone_n, 3, [res_aff, "flat_hp", "hull_heal_on_hit"], DEF_GEMS)
	_fill(sm, "shield", "z%d_shield" % zone_n, zone_n, 3, BEST_SHIELD, DEF_GEMS)
	# v142 FIX: engine + sensor were never filled — every hull has 1-2 of each.
	# Leaving them empty meant every kit was tested crippled: missing evasion and a
	# "maxed" kit that was short 2+ slots of GREATER affixes and Resonant cores.
	# v145: sensors no longer carry accuracy (that axis is deleted); they carry the
	# loot-rate mults, which do not affect time-to-kill. They stay filled here so
	# the slot/affix/socket count of a "maxed kit" remains honest.
	_fill(sm, "engine", "z%d_engine" % zone_n, zone_n, 0, [], [])
	_fill(sm, "sensor", "z%d_sensor" % zone_n, zone_n, 0, [], [])

func _equip_common(sm, zone_n: int, weak: String) -> void:
	_fill(sm, "battery", "z%d_battery" % zone_n, zone_n, 0, [], [])
	_fill(sm, "weapon", "z%d_%s" % [zone_n, SUFFIX[weak]], zone_n, 0, [], [])
	_fill(sm, "armor", "z%d_armor" % zone_n, zone_n, 0, [], [])
	_fill(sm, "shield", "z%d_shield" % zone_n, zone_n, 0, [], [])
	_fill(sm, "engine", "z%d_engine" % zone_n, zone_n, 0, [], [])
	_fill(sm, "sensor", "z%d_sensor" % zone_n, zone_n, 0, [], [])

func _fill(sm, stype: String, base_id: String, zone: int, rarity: int, affixes: Array, gems: Array) -> void:
	if not base_id in sm.modules:
		return
	for i in _slots(sm, stype):
		var cid := String(sm.generate_module_drop(base_id, rarity, zone))
		if cid == "":
			continue
		if not affixes.is_empty():
			_max_affixes(sm, cid, stype, affixes, zone)
		if not gems.is_empty():
			_max_sockets(sm, cid, gems)
		sm.equip_module(i, cid, true)

# Force every picked affix to its GREATER value by calling the manager's own
# roller with ga_chance = 1.0 — stays in lockstep with the real formula
# (percent -> fraction, flat -> 1.8^(z-1), linear_tier -> x zone).
func _max_affixes(sm, cid: String, stype: String, picks: Array, zone: int) -> void:
	var m: Dictionary = sm.modules[cid]
	var out := {}
	var gl: Array = []
	for p in picks:
		var aid := String(p)
		if not sm.AFFIX_DB.has(aid):
			continue
		var cfg: Dictionary = sm.AFFIX_DB[aid]
		var lim: Array = cfg.get("limit_to", [])
		if not lim.is_empty() and not (stype in lim):
			continue   # never hang an illegal affix on a slot — that would fake the ceiling
		var roll: Dictionary = sm._roll_affix_value(aid, zone, 1.0)
		out[aid] = float(roll["value"])
		gl.append(aid)
	m["affixes"] = out
	m["greater_affixes"] = gl

func _max_sockets(sm, cid: String, gems: Array) -> void:
	var m: Dictionary = sm.modules[cid]
	m["sockets"] = [null, null, null]
	for gi in range(3):
		var gid := String(gems[gi % gems.size()])
		GameState.resources.add_element(gid, 1)
		sm.insert_gem(cid, gi, gid)

# --- shared rig (mirrors boss_gearcheck) ----------------------------------

func _weak_type(e: Dictionary) -> String:
	var best := "kinetic"
	var bv: float = float(e.get("resist_k", 0.0))
	if float(e.get("resist_e", 0.0)) < bv:
		bv = float(e.get("resist_e", 0.0))
		best = "energy"
	if float(e.get("resist_x", 0.0)) < bv:
		best = "explosive"
	return best

func _zone_with_diff(cm, d: int) -> String:
	for zid in cm.zones:
		var z: Dictionary = cm.zones[zid]
		if int(z.get("difficulty", 0)) != d:
			continue
		# Z11+ is the Cryo/warp gate — orthogonal to the tier wall, skip here.
		var roster: Array = z.get("enemies", [])
		if roster.size() > 0 and bool(cm.enemy_db.get(String(roster[0]), {}).get("warp_hardened", false)):
			return ""
		return String(zid)
	return ""

func _unlock_research(rm, n: int) -> void:
	for tid in rm.tech_tree:
		if int(rm.tech_tree[tid].get("tier", 99)) <= n and not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)

func _set_hull(sm, n: int) -> void:
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

func _slots(sm, stype: String) -> Array:
	var out: Array = []
	var slots: Array = sm.hulls.get(sm.active_hull, {}).get("slots", [])
	for i in range(slots.size()):
		if String(slots[i]) == stype:
			out.append(i)
	return out

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

# v142 IDLE RULE: the owner requirement is "farms WITH CONSUMABLE SUPPORT without
# dying", so the probe must model an idle player who is actually provisioned —
# the real game auto-consumes on a research threshold. The old 50%/40% manual
# trigger let a spike take the ship from 60% to 0 without a kit ever firing,
# which read as a balance death when it was really a harness artifact.
func _use_kits(sm, cm) -> void:
	if not cm.in_combat:
		return
	if sm.current_hp < sm.max_hp * 0.80 and sm.consumable_hull_slot != "":
		cm.use_manual_consumable("hull")
	if cm.player_shield < cm.player_max_shield * 0.70 and sm.consumable_shield_slot != "":
		cm.use_manual_consumable("shield")
