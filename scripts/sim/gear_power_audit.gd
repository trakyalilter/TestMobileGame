extends Node
# ============================================================================
# GEAR POWER AUDIT (v142) — the numbers behind the tier-gate invariant.
#
# The owner rule ("maxed Zone-N set must NOT farm Zone N+1 e3/e4; clean Common
# Zone N+1 MUST") is an ORDERING on player power:
#
#       power(Common N+1)  >  power(maxed Legendary N)
#
# No enemy number can create that ordering — a threshold cannot let the weaker
# kit through while blocking the stronger one. So this audit measures the real
# multiplier stack, per zone, with NO combat sim: build each kit, recalc_stats,
# print effective offense/defense. The ratio column IS the tuning target.
#
#   ratio = power(maxed Legendary N) / power(Common N+1)
#   ratio > 1  -> old gear wins  -> gate inverted (today)
#   ratio < 1  -> new tier wins  -> gate holds
#
# Kits (all on the SAME tier-N hull, so gear is the only variable):
#   COM_N1  clean Common Zone N+1        (the intended answer)
#   LEG_N   clean Legendary Zone N       (rarity only)
#   LEG_GA  + 3 GREATER affixes          (rarity x affixes)
#   LEG_PRI + Pristine cores             (pre-warp realistic ceiling)
#   LEG_RES + Resonant cores             (post-warp absolute ceiling)
#
#   Godot --headless --path <root> res://scenes/gear_power_audit.tscn
# ============================================================================

const SUFFIX := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}
const BEST_WEAPON := ["dmg_injured", "servo_overclock", "shield_heal_on_hit"]
const BEST_SHIELD := ["flat_shield", "shield_heal_on_hit", "capacitor_pulse"]
const BEST_ARMOR := ["resist_k", "flat_hp", "hull_heal_on_hit"]
const PRI_W := ["PristineCrimsonCore", "PristineCobaltCore", "PristineTopazCore"]
const PRI_D := ["PristineAmethystCore", "PristineCrimsonCore", "PristineCobaltCore"]
const RES_W := ["ResonantCrimsonCore", "ResonantCobaltCore", "ResonantTopazCore"]
const RES_D := ["ResonantAmethystCore", "ResonantCrimsonCore", "ResonantCobaltCore"]

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	print("[POWER] ============== GEAR POWER AUDIT ==============")
	print("[POWER] offense = sum(atk) x atk_speed x crit_mult ; ehp = hp x (1+dr) + shield")
	print("[POWER] ratio = maxed Legendary Z-N / clean Common Z-(N+1). >1.0 = gate INVERTED.")
	print("[POWER] tier step between zones is 2.2x — the ceiling must stay UNDER it.")
	print("[POWER] ------------------------------------------------------------------")
	print("[POWER] %-5s %-9s %-9s %-9s %-9s %-9s | %-7s %-7s" % [
		"trans", "COM_N1", "LEG_N", "LEG_GA", "LEG_PRI", "LEG_RES", "r(PRI)", "r(RES)"])
	for n in range(1, 10):
		var com: Dictionary = _measure(sm, rm, n, n + 1, 0, [], [], [])
		var leg: Dictionary = _measure(sm, rm, n, n, 3, [], [], [])
		var lga: Dictionary = _measure(sm, rm, n, n, 3, BEST_WEAPON, BEST_ARMOR, [])
		var lpr: Dictionary = _measure(sm, rm, n, n, 3, BEST_WEAPON, BEST_ARMOR, PRI_W)
		var lre: Dictionary = _measure(sm, rm, n, n, 3, BEST_WEAPON, BEST_ARMOR, RES_W)
		var base: float = maxf(1.0, float(com["off"]))
		var ebase: float = maxf(1.0, float(com["ehp"]))
		print("[POWER] Z%d->%-2d off %-7s>%-7s r=%.2f | EHP %-8s>%-8s r=%.2f | mit %.2f>%.2f heal %.0f" % [
			n, n + 1,
			_fmt(com), _fmt(lre), float(lre["off"]) / base,
			"%.0f" % float(com["ehp"]), "%.0f" % float(lre["ehp"]), float(lre["ehp"]) / ebase,
			float(com["mit"]), float(lre["mit"]), float(lre["heal"])])
	print("[POWER] ------------------------------------------------------------------")
	print("[POWER] any ratio >= 1.00 means old maxed gear out-damages the new tier.")
	get_tree().quit(0)

func _fmt(r: Dictionary) -> String:
	return "%.0f" % float(r["off"])

# Build one kit and read its effective offense/EHP off the real recalc_stats.
func _measure(sm, rm, hull_n: int, gear_n: int, rarity: int, w_aff: Array, a_aff: Array, gems: Array) -> Dictionary:
	GameState.hard_reset()
	_unlock_research(rm, gear_n)
	_set_hull(sm, hull_n)
	var weak := "kinetic"
	_fill(sm, "battery", "z%d_battery" % gear_n, gear_n, maxi(rarity, 0), [], [])
	_fill(sm, "weapon", "z%d_%s" % [gear_n, SUFFIX[weak]], gear_n, rarity, w_aff, gems)
	_fill(sm, "armor", "z%d_armor" % gear_n, gear_n, rarity, a_aff, (PRI_D if gems == PRI_W else (RES_D if gems == RES_W else [])))
	_fill(sm, "shield", "z%d_shield" % gear_n, gear_n, rarity, (BEST_SHIELD if not w_aff.is_empty() else []), (PRI_D if gems == PRI_W else (RES_D if gems == RES_W else [])))
	_fill(sm, "engine", "z%d_engine" % gear_n, gear_n, rarity, [], (PRI_D if gems == PRI_W else (RES_D if gems == RES_W else [])))
	_fill(sm, "sensor", "z%d_sensor" % gear_n, gear_n, rarity, [], gems)
	sm.recalc_stats()
	# Effective offense: raw attack x attack-speed x expected crit multiplier.
	var spd: float = 1.0 + float(sm.affix_bonuses.get("servo_overclock", 0.0)) + float(sm.gem_bonuses.get("attack_speed", 0.0))
	var cc: float = float(sm.crit_chance) + float(sm.gem_bonuses.get("crit_chance", 0.0))
	var cd: float = 1.5 + float(sm.gem_bonuses.get("crit_damage", 0.0))
	var off: float = float(sm.attack) * spd * (1.0 + cc * maxf(0.0, cd - 1.0))
	# Mitigation stack: per-type resist affixes + matrix damage_reduction. This is
	# the multiplier that turns raw EHP into EFFECTIVE EHP.
	var dr: float = float(sm.gem_bonuses.get("damage_reduction", 0.0))
	var rk: float = float(sm.resist_k) if "resist_k" in sm else 0.0
	var mit: float = 1.0 / maxf(0.05, (1.0 - rk) * (1.0 - dr))
	var ehp: float = (float(sm.max_hp) + float(sm.max_shield)) * mit
	# Sustain: heal-on-hit affixes are UNBOUNDED regen (scale x zone, per hit).
	var heal: float = float(sm.affix_bonuses.get("hull_heal_on_hit", 0.0)) \
		+ float(sm.affix_bonuses.get("shield_heal_on_hit", 0.0))
	return {"off": off, "ehp": ehp, "mit": mit, "heal": heal,
		"atk": float(sm.attack), "hp": float(sm.max_hp)}

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
			continue
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

func _slots(sm, stype: String) -> Array:
	var out: Array = []
	var slots: Array = sm.hulls.get(sm.active_hull, {}).get("slots", [])
	for i in range(slots.size()):
		if String(slots[i]) == stype:
			out.append(i)
	return out
