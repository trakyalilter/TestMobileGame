extends Node
# STAGED DAMAGE-TYPE GUARD (Zones 1-3).
#
# The onboarding contract: one new damage type per zone. Zone 1 is kinetic only,
# Zone 2 adds energy, Zone 3 completes the triangle. Before v174 Zone 1 shipped
# all three — two of its three trash enemies demanded weapons a new player had
# not crafted, and the m017 tutorial chain taught the whole triangle plus the
# 3-preset loadout system inside the first zone.
#
# Four ways that contract can silently rot, all checked here:
#   1. an enemy RESISTS or is WEAK TO a type its zone has not unlocked — the
#      player sees a RESISTED/WEAK SPOT message naming a type they do not have;
#   2. a loot pool rolls a weapon of a type they cannot use yet;
#   3. a weapon or its ammo is craftable before its zone opens;
#   4. a mission targets an enemy that no longer exists.
#
#   Godot --headless --path <root> res://scenes/type_unlock_check.tscn

# zone -> the damage types live by then
const LIVE := {1: ["k"], 2: ["k", "e"], 3: ["k", "e", "x"]}
const RESIST_KEY := {"k": "resist_k", "e": "resist_e", "x": "resist_x"}
const TYPE_WORD := {"k": "kinetic", "e": "energy", "x": "explosive"}
# module id suffix -> the type it deals
const SUFFIX_TYPE := {"kinetic": "k", "energy": "e", "missile": "x"}
# what must be researched before each type may be crafted
const TYPE_GATE := {"e": "zone_2_access", "x": "zone_3_access"}

var fails: int = 0

func _ready() -> void:
	await get_tree().process_frame
	GameState.set_process(false)
	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager

	# ---- 1 + 2: enemies may not reference an unreleased type ---------------
	for zid in cm.zones:
		var zd: Dictionary = cm.zones[zid]
		var n: int = int(zd.get("difficulty", 0))
		if not LIVE.has(n):
			continue
		var live: Array = LIVE[n]
		var roster: Array = zd.get("enemies", [])
		print("[TYPE] Z%d %-18s roster=%d  live types: %s" % [
			n, zid, roster.size(), ", ".join(live)])
		for eid in roster:
			var e: Dictionary = cm.enemy_db.get(String(eid), {})
			if e.is_empty():
				_fail("Z%d roster names %s, which is not in enemy_db" % [n, eid])
				continue
			for t in RESIST_KEY:
				if t in live:
					continue
				var v: float = float(e.get(RESIST_KEY[t], 0.0))
				if absf(v) > 0.001:
					_fail("%s carries %s = %.2f, but %s is not unlocked until Z%d" % [
						eid, RESIST_KEY[t], v, TYPE_WORD[t], _zone_of_type(t)])
			for mid in e.get("module_drop_pool", []):
				var t2 := _type_of_module(String(mid))
				if t2 != "" and not (t2 in live):
					_fail("%s can drop %s (%s) before that type is unlocked" % [
						eid, mid, TYPE_WORD[t2]])

	# ---- 3: weapons and their ammo gate on the same zone -------------------
	# The rule is NOT "every energy module gates on zone_2_access" — a Z3-tier
	# energy weapon gating at Z3 is correct. The rule is that a CRAFTABLE weapon
	# may not become available EARLIER than its type. Unique modules are boss
	# drops with no cost, so no research gates them and none should.
	for mid in sm.modules:
		var t := _type_of_module(String(mid))
		if t == "" or not TYPE_GATE.has(t):
			continue
		var md: Dictionary = sm.modules[mid]
		if (md.get("cost", {}) as Dictionary).is_empty():
			continue                                   # drop-only, never craftable
		var gate_z := _gate_zone(String(md.get("research_req", "")))
		var need_z := _zone_of_type(t)
		if gate_z < need_z:
			_fail("%s is %s (unlocks Z%d) but its research gate '%s' opens at Z%d" % [
				mid, TYPE_WORD[t], need_z,
				String(md.get("research_req", "")) if String(md.get("research_req", "")) != "" else "NONE",
				gate_z])
	for pair in [["CellT1", "e"], ["MissileT1", "x"]]:
		var sym := String(pair[0])
		var want := String(TYPE_GATE[String(pair[1])])
		var got := _ammo_gate(sym)
		if got != want:
			_fail("ammo %s gates on '%s', expected '%s' — a gated weapon with ungated bullets" % [
				sym, got if got != "" else "NONE", want])

	# ---- 4: no mission may point at a retired enemy ------------------------
	var mm = GameState.mission_manager
	for mid2 in mm.missions:
		var m: Dictionary = mm.missions[mid2]
		if not (String(m.get("type", "")) in ["defeat", "defeat_retreat"]):
			continue
		var tgt := String(m.get("target", ""))
		if tgt != "" and not cm.enemy_db.has(tgt):
			_fail("mission %s targets %s, which no longer exists" % [mid2, tgt])

	# ---- 5: no mission may demand a material gated past its own zone --------
	# m026d2 asked for 60 MissileT1 before the Zone 1 boss. Once explosive moved to
	# zone_3_access that became unbuildable, i.e. a softlock for anyone standing on
	# it. Walk the chain, track the zone the player is in, and check every material
	# a beat demands against the research that gates it.
	var mm3 = GameState.mission_manager
	var pm3 = GameState.processing_manager
	var zone_now := 1
	var cur := "m001"
	var steps := 0
	while cur != "" and steps < 60:
		var m: Dictionary = mm3.missions.get(cur, {})
		if m.is_empty():
			break
		var tgt := str(m.get("target", ""))
		if str(m.get("type", "")) == "research" and tgt.begins_with("zone_") and tgt.ends_with("_access"):
			zone_now = maxi(zone_now, _gate_zone(tgt))
		var wants: Array = []
		if str(m.get("type", "")) == "gather":
			wants.append(tgt)
		elif str(m.get("type", "")) == "gather_multi":
			for k in (m.get("target", {}) as Dictionary):
				wants.append(str(k))
		for w in wants:
			var need := _gate_zone(_ammo_gate(str(w)))
			if need > zone_now:
				_fail("%s demands %s at zone %d, but it gates on zone %d" % [
					cur, w, zone_now, need])
		cur = str(m.get("next_mission", ""))
		steps += 1
	print("[TYPE] gated-material walk: %d beats, player reaches zone %d" % [steps, zone_now])

	print("[TYPE] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _type_of_module(mid: String) -> String:
	for suffix in SUFFIX_TYPE:
		if mid.ends_with("_" + String(suffix)):
			return String(SUFFIX_TYPE[suffix])
	return ""


# "zone_N_access" -> N. Anything else (or no gate) counts as zone 1 — available
# from the start, which is exactly what makes an ungated energy weapon a failure.
func _gate_zone(tech: String) -> int:
	if tech.begins_with("zone_") and tech.ends_with("_access"):
		return int(tech.trim_prefix("zone_").trim_suffix("_access"))
	return 1


func _zone_of_type(t: String) -> int:
	for n in [1, 2, 3]:
		if t in LIVE[n]:
			return n
	return 99


func _ammo_gate(sym: String) -> String:
	var pm = GameState.processing_manager
	for rid in pm.recipes:
		var r: Dictionary = pm.recipes[rid]
		if (r.get("output", {}) as Dictionary).has(sym):
			return String(r.get("research_req", ""))
	return ""


func _fail(msg: String) -> void:
	print("[TYPE] FAIL: %s" % msg)
	fails += 1
