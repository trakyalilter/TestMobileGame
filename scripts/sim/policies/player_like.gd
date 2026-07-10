extends "res://scripts/sim/policy_base.gd"

# ============================================================================
# player_like — the mission-follower policy (v135). ONE class; the four
# archetypes are parameter presets, never forked code. It reads the SAME
# objective oracle the player reads (mission_manager.get_active_objective),
# maps it to a concrete verb via mission_actions.gd, and EARNS everything —
# zero grants (statically enforced by tools/check_player_policy.ps1).
#
# Deliberately NOT extending progression.gd: inheritance could silently leak
# its grant helpers. The read-only machinery it proved out (_combat_ready,
# ammo tables, slot scans) is PORTED here with every grant line stripped.
# ============================================================================

const MissionActions := preload("res://scripts/sim/mission_actions.gd")

const AMMO_FOR := {"kinetic": "SlugT1", "energy": "CellT1", "explosive": "MissileT1"}
const KIT_HULL := "EmergencyPatch"     # 8 Fe, lvl 1, research-free (anti-softlock kit)
const KIT_SHIELD := "BasicBooster"     # Si 20 + BatteryT1, lvl 2

# Archetype presets. day0_len = one continuous first-day sit; then sessions x
# session_len per day, offline gaps filling 24h. claim_latency = seconds a
# completed mission sits before the bot notices (DRIFTER: only at session
# start). smart_income: policy_base cps knowledge vs "looks strong" (highest
# level_req unlocked gather). boredom_s: dead-time streak that ends a session.
const ARCHETYPES := {
	"follower": {"day0_len": 7200.0, "sessions": 3, "session_len": 1200.0,
		"claim_latency": 30.0, "claims_at_start_only": false, "smart_income": false,
		"precraft": false, "boredom_s": 600.0, "kit_pct": 0.45, "ammo_buffer": 100,
		"switch_losses": 3, "id": 1},
	"efficient": {"day0_len": 7200.0, "sessions": 5, "session_len": 900.0,
		"claim_latency": 0.0, "claims_at_start_only": false, "smart_income": true,
		"precraft": true, "boredom_s": 1800.0, "kit_pct": 0.55, "ammo_buffer": 500,
		"switch_losses": 1, "id": 2},
	"drifter": {"day0_len": 3600.0, "sessions": 4, "session_len": 480.0,
		"claim_latency": 0.0, "claims_at_start_only": true, "smart_income": false,
		"precraft": false, "boredom_s": 240.0, "kit_pct": 0.35, "ammo_buffer": 60,
		"switch_losses": 3, "id": 3},
	"overnighter": {"day0_len": 1800.0, "sessions": 1, "session_len": 900.0,
		"claim_latency": 0.0, "claims_at_start_only": false, "smart_income": false,
		"precraft": false, "boredom_s": 900.0, "kit_pct": 0.45, "ammo_buffer": 100,
		"switch_losses": 3, "id": 4},
}

var params: Dictionary = {}
var archetype := ""
var actions = null   # mission_actions.gd instance (untyped: duck-typed sim helper)
var jitter := RandomNumberGenerator.new()   # private stream — never touches game RNG

# Learning state machines: untaught -> taught at the teaching mission (or run
# start for EFFICIENT). Deterministic, never regresses (random forgetting is
# banned — indistinguishable from the historical false-signal holes).
var kits_taught := false
var type_match_taught := false

var at_session_start := false      # runner sets at each session begin (DRIFTER claims)
# Current verb's cost materials, shielded from sell_surplus. TWO generations
# (this slice + last) rotated in decide_step: without rotation the set grew
# forever — eventually everything was protected, sells freed nothing, cargo
# pinned at max slots and ALL new loot was lost (45-day m029b park, r3).
var _protect_syms := {}
var _protect_prev := {}
var status := "boot"               # heartbeat / stall-evidence string
var pending_events: Array = []     # instants performed this step; runner drains to telemetry
var _completed_seen := {}          # mid -> sim_s first seen completed (claim latency)
var _losses := {}                  # enemy id -> consecutive losses
var _detoured_this_session := {}   # enemy id -> true (retried later, not this session)
var _want_switch := {}             # enemy id -> true (EFFICIENT after 1 loss)

func setup(p_archetype: String, run_seed: int) -> void:
	archetype = p_archetype
	params = ARCHETYPES[p_archetype].duplicate()
	jitter.seed = run_seed * 7919 + int(params["id"])
	actions = MissionActions.new()
	# EFFICIENT is the wiki-reader: disciplines known from the start.
	kits_taught = (p_archetype == "efficient")
	type_match_taught = (p_archetype == "efficient")

func on_session_start() -> void:
	at_session_start = true
	_detoured_this_session.clear()

# ---------------------------------------------------------------------------
# Claim pump — runner calls every sim-second (after mm.sync_progress()).
# Claiming is THE chain advancer; latency models the player noticing.
# ---------------------------------------------------------------------------
func pump_claims(sim_s: float) -> Array:
	var mm = GameState.mission_manager
	var claimed: Array = []
	if bool(params["claims_at_start_only"]) and not at_session_start:
		# DRIFTER only checks the board at login; completed missions sit.
		return claimed
	for mid in mm.active_missions.duplicate():
		var m: Dictionary = mm.missions[mid]
		if not m["completed"] or m["claimed"]:
			continue
		if not _completed_seen.has(mid):
			_completed_seen[mid] = sim_s
		if sim_s - float(_completed_seen[mid]) < float(params["claim_latency"]):
			continue
		if mm.claim_reward(mid):
			claimed.append(mid)
			_on_claimed(String(mid))
	return claimed

func _on_claimed(mid: String) -> void:
	# Teaching beats flip discipline states the moment the player completes them.
	if mid == "m024b2":
		kits_taught = true
	if mid == "m017a":
		type_match_taught = true

# ---------------------------------------------------------------------------
# decide_step — the per-slice brain. Executes INSTANT actions inline (research
# buys, crafts, equips, auto-UI) with a small guard, then returns ONE timed
# task for the runner to tick. Every return carries:
#   kind: gather|process|combat|combat_farm|idle|warp
#   attr: direct|detour|blocked   (funnel time-split attribution)
#   obj:  mission id served       why: human-readable gate
# ---------------------------------------------------------------------------
func decide_step() -> Dictionary:
	var mm = GameState.mission_manager
	_maintain_kits()
	_protect_prev = _protect_syms
	_protect_syms = {}
	# Slot pressure lived, not designed out: sell surplus PROTECTING mission
	# targets/ammo/kit feedstock, then expand storage — the player-like response
	# to a full 28-slot cargo (the second historical fake-DNF source).
	var res = GameState.resources
	if res.get_used_slots() >= res.get_max_slots():
		var earned := sell_surplus(_protected())
		maybe_upgrade_storage()
		pending_events.append({"t": "slot_pressure", "sold_cr": round(earned),
			"used": res.get_used_slots(), "max": res.get_max_slots()})
	for _guard in range(8):
		var obj: Dictionary = mm.get_active_objective()
		if obj.is_empty():
			return _income("freeplay", "", "detour")
		var mid := String(obj.get("id", ""))
		if bool(obj.get("completed", false)):
			# Completed but unclaimed (latency window) — the player is done with
			# the ask; they skill while the claim sits. Income, not dead time.
			return _income("claim-pending %s" % mid, mid, "detour")
		var verb: Dictionary = actions.resolve(obj)
		var d := _execute_verb(mid, verb)
		if d.is_empty():
			continue      # an instant landed — re-read the objective (it may have advanced)
		at_session_start = false
		return d
	at_session_start = false
	return _income("instant-loop guard", "", "detour")

# {} = performed an instant, loop again. Non-empty = timed task for the runner.
func _execute_verb(mid: String, verb: Dictionary) -> Dictionary:
	var v := String(verb.get("verb", "unmapped"))
	match v:
		"acquire":
			return _do_acquire(mid, String(verb["sym"]))
		"research":
			return _do_research(mid, String(verb["tid"]))
		"craft":
			return _do_craft(mid, String(verb["mid"]))
		"construct":
			return _do_construct(mid, String(verb["hid"]))
		"build":
			return _do_build(mid, String(verb["bid"]))
		"equip_slot":
			return _do_equip_slot(mid, String(verb["slot_type"]), int(verb.get("count", 1)))
		"equip_kits":
			return _do_equip_kits(mid, int(verb.get("count", 1)))
		"auto_ui":
			GameState.mission_manager._update_progress("visit_page", String(verb["page"]), 1)
			pending_events.append({"t": "auto_ui", "mid": mid, "page": String(verb["page"])})
			return {}
		"combat":
			return _do_combat(mid, String(verb["zone"]), String(verb["enemy"]))
		"discover":
			var zid := String(verb["zone"])
			var en: Array = GameState.combat_manager.zones.get(zid, {}).get("enemies", [])
			if en.is_empty():
				return _blocked(mid, "discover: zone %s empty" % zid)
			return _do_combat(mid, zid, String(en[0]))
		"farm_rarity":
			return _do_farm_rarity(mid, int(verb.get("rarity", 2)))
		"equip_rare_weapon":
			return _do_equip_rare_weapon(mid, int(verb.get("rarity", 2)), "")
		"equip_rare_weapon_type":
			return _do_equip_rare_weapon(mid, 2, String(verb.get("wtype", "")))
		"warp":
			if GameState.warp_manager.calculate_warp_gains() >= 1:
				return {"kind": "warp", "attr": "direct", "obj": mid, "why": "warp", "length": 0.0}
			status = "warp:gains<1"
			return _income("warp gains<1 — pushing score", mid, "detour")
		"hack_apply":
			return _do_hack_apply(mid, String(verb.get("stone", "SpliceChip")))
		"overclock":
			return _do_overclock(mid)
		"wait":
			return _blocked(mid, "verb wait (nothing actionable)")
		_:
			# Unknown mission type = hard error, never a silent skip.
			pending_events.append({"t": "error", "mid": mid,
				"why": String(verb.get("why", "unmapped verb"))})
			return _blocked(mid, "UNMAPPED:%s" % String(verb.get("why", "?")))

# ---------------------------------------------------------------------------
# Verb executors.
# ---------------------------------------------------------------------------
func _do_acquire(mid: String, sym: String) -> Dictionary:
	# Whatever we're acquiring — INCLUDING recursion intermediates like the
	# Res1 feeding an artifact-upgrade recipe — must never be sold out from
	# under the chase by a slot-pressure sell (the 45-day-park leak).
	_protect_syms[sym] = true
	var src: Dictionary = actions.source_for(sym)
	match String(src.get("kind", "none")):
		"gather":
			return {"kind": "gather", "mgr": GameState.gathering_manager,
				"id": String(src["id"]), "length": 30.0, "attr": "direct",
				"obj": mid, "why": "gather %s" % sym}
		"gather_locked":
			# The right action is level-locked — a player grinds another gather.
			status = "gather-level %d for %s" % [int(src.get("lvl", 0)), sym]
			return _income(status, mid, "detour")
		"process":
			return {"kind": "process", "mgr": GameState.processing_manager,
				"id": String(src["id"]), "length": 30.0, "attr": "direct",
				"obj": mid, "why": "process %s" % sym}
		"research":
			return _do_research(mid, String(src["tid"]))
		"grind_processing":
			var g := _grind_processing_step(mid)
			if not g.is_empty():
				return g
			return _blocked(mid, "grind_processing: no runnable recipe")
		"credits":
			return _earn_credits(mid, "recipe credits for %s" % sym)
		"zone_farm":
			var rr := String(src.get("research", ""))
			if rr != "":
				return _do_research(mid, rr)
			# MUST route through the prep pipeline (ammo/kits/repair) like every
			# other combat path — returning a raw combat task here livelocked on
			# the runner's CANT_FIRE assert (smoke run, m026 Res-artifact farm).
			return _do_combat_farm(mid, String(src["zone"]), String(src["enemy"]), "detour")
		_:
			return _blocked(mid, "unsourceable:%s" % sym)

func _do_research(mid: String, tid: String) -> Dictionary:
	var b: Dictionary = actions.research_blocker(tid)
	status = "research:%s blk=%s" % [tid, String(b.get("kind", "?"))]
	match String(b.get("kind", "")):
		"done":
			return {}
		"unlockable":
			if GameState.research_manager.unlock_tech(String(b["tid"])):
				pending_events.append({"t": "research", "mid": mid, "tid": String(b["tid"])})
				_after_research_unlock(String(b["tid"]))
				return {}
			return _blocked(mid, "unlock_tech(%s) false" % String(b["tid"]))
		"credits":
			_protect_cost_items(GameState.research_manager.tech_tree.get(String(b["tid"]), {}).get("cost_items", {}))
			return _earn_credits(mid, "research %s needs %d cr" % [String(b["tid"]), int(b["amount"])])
		"item":
			# Shield EVERY cost material of the gating tech from sell_surplus —
			# the 45-day tail run showed slot-pressure sells dumping the very
			# Res2 the bot was farming for m030 (farm 0.5/kill, sell all, loop).
			_protect_cost_items(GameState.research_manager.tech_tree.get(String(b["tid"]), {}).get("cost_items", {}))
			return _do_acquire(mid, String(b["sym"]))
		_:
			return _blocked(mid, "research flag-gate: %s (%s)" % [String(b.get("tid", tid)), String(b.get("why", "?"))])

func _after_research_unlock(tid: String) -> void:
	# AUTO_UI contract: main.gd's fanfare hook sets warp_first_revealed on
	# zone_6_access in the real game; headless must mirror it or goal_002 never
	# reveals (verifier finding). Zero-time, logged, auditable.
	if tid == "zone_6_access" and not GameState.game_settings.get("warp_first_revealed", false):
		GameState.game_settings["warp_first_revealed"] = true
		pending_events.append({"t": "auto_ui", "mid": "-", "page": "warp_reveal"})

func _do_craft(mid: String, module_id: String) -> Dictionary:
	var b: Dictionary = actions.craft_blocker(module_id)
	match String(b.get("kind", "")):
		"ready":
			if GameState.shipyard_manager.craft_module(module_id):
				pending_events.append({"t": "craft", "mid": mid, "module": module_id})
				return {}
			return _blocked(mid, "craft_module(%s) false" % module_id)
		"research":
			return _do_research(mid, String(b["tid"]))
		"credits":
			_protect_cost_items(GameState.shipyard_manager.get_effective_module_cost(GameState.shipyard_manager.modules[module_id]))
			return _earn_credits(mid, "craft %s needs %d cr" % [module_id, int(b["amount"])])
		"item":
			_protect_cost_items(GameState.shipyard_manager.get_effective_module_cost(GameState.shipyard_manager.modules[module_id]))
			return _do_acquire(mid, String(b["sym"]))
		_:
			return _blocked(mid, "craft %s: %s" % [module_id, String(b.get("why", "?"))])

func _do_construct(mid: String, hid: String) -> Dictionary:
	var b: Dictionary = actions.construct_blocker(hid)
	match String(b.get("kind", "")):
		"ready":
			if GameState.shipyard_manager.construct_hull(hid):
				pending_events.append({"t": "construct", "mid": mid, "hull": hid})
				return {}
			return _blocked(mid, "construct_hull(%s) false" % hid)
		"research":
			return _do_research(mid, String(b["tid"]))
		"credits":
			_protect_cost_items(GameState.shipyard_manager.hulls.get(hid, {}).get("cost", {}))
			return _earn_credits(mid, "hull %s needs %d cr" % [hid, int(b["amount"])])
		"item":
			_protect_cost_items(GameState.shipyard_manager.hulls.get(hid, {}).get("cost", {}))
			return _do_acquire(mid, String(b["sym"]))
		_:
			return _blocked(mid, "construct %s: %s" % [hid, String(b.get("why", "?"))])

func _do_build(mid: String, bid: String) -> Dictionary:
	# Blocker-analyzed like craft/construct — the naive "earn credits until
	# affordable" loop livelocked on m019d when the MATERIAL (Si 5) was the
	# real blocker: income gathering never sources Si, credits rose forever.
	var b: Dictionary = actions.build_blocker(bid)
	match String(b.get("kind", "")):
		"ready":
			if GameState.infrastructure_manager.build(bid):
				pending_events.append({"t": "build", "mid": mid, "building": bid})
				return {}
			return _blocked(mid, "build(%s) false" % bid)
		"research":
			return _do_research(mid, String(b["tid"]))
		"credits":
			_protect_cost_items(GameState.infrastructure_manager.get_building_cost(bid))
			return _earn_credits(mid, "building %s needs %d cr" % [bid, int(b["amount"])])
		"item":
			_protect_cost_items(GameState.infrastructure_manager.get_building_cost(bid))
			return _do_acquire(mid, String(b["sym"]))
		_:
			return _blocked(mid, "build %s: %s" % [bid, String(b.get("why", "?"))])

# Equip `count` modules of slot_type from inventory into empty matching slots.
# The chain's craft step precedes each equip step, so inventory should hold
# them; if not (player sold/lost), fall back to crafting the T1 module.
func _do_equip_slot(mid: String, slot_type: String, count: int) -> Dictionary:
	var sm = GameState.shipyard_manager
	if slot_type == "combat_ready":
		# Legacy orphan (m016b): weapon + shield each.
		var dw := _do_equip_slot(mid, "weapon", 1)
		if not dw.is_empty():
			return dw
		return _do_equip_slot(mid, "shield", 1)
	var have := 0
	for i in _slot_indices(slot_type):
		if sm.loadout.get(i, null):
			have += 1
	if have >= count:
		return {}       # sync_progress completes it on the next pump
	# best inventory candidate of this slot_type (rarity, then tier)
	var cand := _best_inventory_module(slot_type)
	if cand == "":
		var t1 := "z1_%s" % ("kinetic" if slot_type == "weapon" else slot_type)
		return _do_craft(mid, t1)
	for i in _slot_indices(slot_type):
		if sm.loadout.get(i, null):
			continue
		if sm.equip_module(i, cand, true):
			sm.recalc_stats()
			pending_events.append({"t": "equip", "mid": mid, "slot": slot_type,
				"module": _norm_mid(cand)})
			return {}
		# Power guard rejected it (shouldn't pre-batteries thanks to the
		# power-first chain, but surface it honestly if it happens).
		return _blocked(mid, "equip %s rejected (power guard? used=%d cap=%d)" % [
			cand, sm.energy_used, sm.energy_capacity])
	return _blocked(mid, "no empty %s slot" % slot_type)

func _do_equip_kits(mid: String, count: int) -> Dictionary:
	var sm = GameState.shipyard_manager
	var res = GameState.resources
	# Craft stock first (m024b already had the player make 5 of each; this is
	# the top-up path), then assign both consumable slots and verify.
	if res.get_element_amount(KIT_HULL) < count:
		return _do_acquire(mid, KIT_HULL)
	if res.get_element_amount(KIT_SHIELD) < count:
		return _do_acquire(mid, KIT_SHIELD)
	if sm.consumable_hull_slot == "":
		sm.equip_consumable("hull", KIT_HULL)
	if sm.consumable_shield_slot == "":
		sm.equip_consumable("shield", KIT_SHIELD)
	if sm.consumable_hull_slot != "" and sm.consumable_shield_slot != "":
		pending_events.append({"t": "equip_kits", "mid": mid})
		return {}
	return _blocked(mid, "equip_consumable silently failed (hull=%s shield=%s)" % [
		sm.consumable_hull_slot, sm.consumable_shield_slot])

func _do_combat(mid: String, zid: String, eid: String) -> Dictionary:
	var cm = GameState.combat_manager
	# Zone locked? The chain researches gates first, but belt-and-braces.
	var zrr = cm.zones.get(zid, {}).get("research_req")
	if zrr and not GameState.research_manager.is_tech_unlocked(String(zrr)):
		return _do_research(mid, String(zrr))
	# Losses discipline: after 2 consecutive losses, do something else THIS
	# session and retry next. Walled players grind GEAR, not dirt — farm the
	# best unlocked zone for module drops (rarity re-rolls feed
	# _optimize_loadout) instead of income-idling; the v135 matrix showed an
	# unlucky-drops run parked 52h at the Architect on pure income backoff.
	if int(_losses.get(eid, 0)) >= 2 and _detoured_this_session.get(eid, false):
		var z: Dictionary = actions._best_unlocked_zone()
		if not z.is_empty() and String(z["enemy"]) != eid:
			status = "gear-farm after losses to %s" % eid
			return _do_combat_farm(mid, String(z["zone"]), String(z["enemy"]), "detour")
		return _income("boss-loss backoff %s" % eid, mid, "detour")
	var prep := _prep_for_fight(mid, eid)
	if not prep.is_empty():
		return prep
	return {"kind": "combat", "zone": zid, "enemy": eid, "length": 240.0,
		"attr": "direct", "obj": mid, "why": "fight %s" % eid}

# Readiness pipeline before any fight: weapon equipped (type-matched when
# taught), ammo stocked + ASSIGNED, kits stocked + equipped when taught,
# hull repaired. Returns {} when ready, else the prep task.
func _prep_for_fight(mid: String, eid: String) -> Dictionary:
	var sm = GameState.shipyard_manager
	if not is_armed():
		var d := _do_equip_slot(mid, "weapon", 1)
		if not d.is_empty():
			return d
	# Players equip what they loot: fill every empty slot with the best owned
	# module ("bigger number better"), upgrade-swap strictly better rarities.
	# Without this the bot fought bosses with one directed weapon and bare
	# slots — a fidelity gap, not a game gate (smoke run: Architect losses).
	_optimize_loadout()
	# Type matching once taught (or EFFICIENT after 1 loss wants the switch).
	if type_match_taught or _want_switch.get(eid, false):
		var weak := _enemy_weak_type(eid)
		if weak != "" and not _has_weapon_of_type_equipped(weak):
			var got := _equip_weapon_of_type(mid, weak)
			if not got.is_empty():
				return got
	# Ammo for every equipped weapon: stocked + assigned. Bosses get a full
	# fight's worth up front (players stock up before a boss).
	var eb: bool = bool(GameState.combat_manager.enemy_db.get(eid, {}).get("is_boss", false))
	var ammo_task := _ensure_ammo_real(mid, eb)
	if not ammo_task.is_empty():
		return ammo_task
	# Repair FIRST — repair_hull consumes equipped hull kits (free out of
	# combat), so it must run BEFORE the kit-stock invariant is established or
	# healing up eats the very kits the boss fight requires (smoke-run livelock).
	if sm.current_hp <= 0 or sm.current_hp < sm.max_hp * 0.6:
		if sm.consumable_hull_slot == "" \
				and GameState.resources.get_element_amount(KIT_HULL) >= 1:
			sm.equip_consumable("hull", KIT_HULL)
		if not sm.repair_hull():
			if sm.current_hp <= 0:
				# Dead and can't heal: craft the anti-softlock kit from earned
				# Fe, or report no_repair_path — a genuine softlock finding,
				# never absorbed into dps_wall.
				if GameState.resources.get_element_amount(KIT_HULL) < 1:
					var kd2 := _do_acquire(mid, KIT_HULL)
					if not kd2.is_empty():
						return kd2
					pending_events.append({"t": "error", "mid": mid, "why": "no_repair_path"})
					return _blocked(mid, "no_repair_path")
				if sm.consumable_hull_slot == "":
					sm.equip_consumable("hull", KIT_HULL)
				if not sm.repair_hull():
					pending_events.append({"t": "error", "mid": mid, "why": "no_repair_path"})
					return _blocked(mid, "no_repair_path")
	# Kits LAST: top the stock back up (post-repair) + both slots assigned.
	if kits_taught:
		var kd := _do_equip_kits(mid, 2)
		if not kd.is_empty():
			return kd
	if sm.energy_used > sm.energy_capacity:
		return _blocked(mid, "power_wall used=%d cap=%d" % [sm.energy_used, sm.energy_capacity])
	return {}

func _do_farm_rarity(mid: String, _rarity: int) -> Dictionary:
	# "Farm Lunar Orbit until a RARE drops" — farm the best unlocked zone's
	# trash with full combat discipline; sync completes the mission.
	var z: Dictionary = actions._best_unlocked_zone()
	if z.is_empty():
		return _blocked(mid, "no unlocked zone to farm")
	return _do_combat_farm(mid, String(z["zone"]), String(z["enemy"]))

func _do_combat_farm(mid: String, zid: String, eid: String, attr: String = "direct") -> Dictionary:
	var prep := _prep_for_fight(mid, eid)
	if not prep.is_empty():
		return prep
	return {"kind": "combat_farm", "zone": zid, "enemy": eid, "length": 120.0,
		"attr": attr, "obj": mid, "why": "farm %s @%s" % [eid, zid]}

func _do_equip_rare_weapon(mid: String, rarity: int, wtype: String) -> Dictionary:
	var sm = GameState.shipyard_manager
	var best := ""
	var best_r := -1
	for inv_mid in sm.module_inventory:
		if int(sm.module_inventory.get(inv_mid, 0)) <= 0:
			continue
		var def: Dictionary = sm.modules.get(String(inv_mid), {})
		if String(def.get("slot_type", "")) != "weapon":
			continue
		var r := int(sm.get_module_rarity(String(inv_mid)))
		if r < rarity:
			continue
		if wtype != "" and _weapon_atype(String(inv_mid)) != wtype:
			continue
		if r > best_r:
			best_r = r
			best = String(inv_mid)
	if best == "":
		# Already equipped one? sync_progress completes it.
		for i in _slot_indices("weapon"):
			var l = sm.loadout.get(i, null)
			if l and int(sm.get_module_rarity(String(l))) >= rarity \
					and (wtype == "" or _weapon_atype(String(l)) == wtype):
				return {}
		return _do_farm_rarity(mid, rarity)
	var idxs := _slot_indices("weapon")
	for i in idxs:
		if not sm.loadout.get(i, null):
			if sm.equip_module(i, best, true):
				sm.recalc_stats()
				pending_events.append({"t": "equip", "mid": mid, "slot": "weapon",
					"module": _norm_mid(best)})
				return {}
	# No empty slot: swap the first weapon slot.
	if idxs.size() > 0:
		if sm.equip_module(int(idxs[0]), best, true):
			sm.recalc_stats()
			pending_events.append({"t": "equip", "mid": mid, "slot": "weapon",
				"module": _norm_mid(best)})
			return {}
	return _blocked(mid, "equip rare weapon failed (power guard?)")

func _do_hack_apply(mid: String, stone: String) -> Dictionary:
	var sm = GameState.shipyard_manager
	if GameState.resources.get_element_amount(stone) < 1:
		return _do_acquire(mid, stone)
	# Target: any owned non-custom COMMON module (mission: awaken a Common component).
	for inv_mid in sm.module_inventory:
		if int(sm.module_inventory.get(inv_mid, 0)) <= 0:
			continue
		var s := String(inv_mid)
		if s.begins_with("custom_"):
			continue
		if int(sm.get_module_rarity(s)) != 0:
			continue
		# Return shape is version-dependent ({ok,msg} dict vs bool) — accept both.
		var r = sm.apply_hack_stone(stone, s)
		var ok := false
		var msg := "?"
		if r is Dictionary:
			ok = bool(r.get("ok", false))
			msg = str(r.get("msg", "?"))
		elif r is bool:
			ok = r
		if ok:
			pending_events.append({"t": "hack_apply", "mid": mid, "base": s})
			return {}
		return _blocked(mid, "apply_hack_stone: %s" % msg)
	# Nothing Common on hand — craft the cheapest T1 module as a target.
	return _do_craft(mid, "z1_engine")

func _do_overclock(mid: String) -> Dictionary:
	var im = GameState.infrastructure_manager
	if GameState.resources.get_element_amount("BoostCard") < 1:
		return _do_acquire(mid, "BoostCard")
	for bid in im.building_db:
		if im.get_building_count(bid) > 0:
			var r: Dictionary = im.install_boost_card(bid)
			if bool(r.get("ok", false)):
				pending_events.append({"t": "overclock", "mid": mid, "building": String(bid)})
				return {}
			return _blocked(mid, "install_boost_card: %s" % String(r.get("msg", "?")))
	# Owns no building — buy the cheapest one (player would).
	if buy_buildings(1) > 0:
		return {}
	return _earn_credits(mid, "no building owned for overclock")

# ---------------------------------------------------------------------------
# Income / blocked fallbacks.
# ---------------------------------------------------------------------------
func _income(why: String, obj: String, attr: String) -> Dictionary:
	status = why
	if bool(params["smart_income"]):
		var rid := best_recipe_id()
		if rid != "" and recipe_runnable(rid):
			return {"kind": "process", "mgr": GameState.processing_manager, "id": rid,
				"length": 45.0, "attr": attr, "obj": obj, "why": why}
		var bg := best_gather()
		return {"kind": "gather", "mgr": GameState.gathering_manager, "id": String(bg[0]),
			"length": 45.0, "attr": attr, "obj": obj, "why": why}
	return {"kind": "gather", "mgr": GameState.gathering_manager,
		"id": _looks_strong_gather(), "length": 45.0, "attr": attr, "obj": obj, "why": why}

func _looks_strong_gather() -> String:
	# Casual heuristic ported from policies/casual.gd: highest level_req
	# unlocked action "looks strongest" — deliberately not cps-optimal.
	var gm = GameState.gathering_manager
	var best := "gather_dirt"
	var best_req := -1
	for aid in unlocked_gather_actions():
		var req := int(gm.actions[aid].get("level_req", 1))
		if req > best_req:
			best_req = req
			best = String(aid)
	return best

func _earn_credits(obj: String, why: String) -> Dictionary:
	sell_surplus(_protected())
	return _income("earn: %s" % why, obj, "detour")

func _blocked(obj: String, why: String) -> Dictionary:
	status = why
	return {"kind": "idle", "length": 30.0, "attr": "blocked", "obj": obj, "why": why}

# Never sell: the active objective's targets, ammo, kit feedstock, cores,
# battery cells (BasicBooster input), mission-directed craft materials.
func _protect_cost_items(cost: Dictionary) -> void:
	for sym in cost:
		if String(sym) != "credits":
			_protect_syms[String(sym)] = true

func _protected() -> Dictionary:
	var p := {"Fe": 300.0, "Si": 200.0, "Li": 60.0, "BatteryT1": 10.0,
		KIT_HULL: 10.0, KIT_SHIELD: 10.0, "O": 60.0, "C": 100.0}
	for a in AMMO_FOR.values():
		p[String(a)] = 9.0e9
	for n in range(1, 11):
		p["Z%d_Core" % n] = 9.0e9
	# Current verb's cost materials (research items, craft/hull/building mats) —
	# a player farming 25 Res2 for a tech does not sell their Res2 stack.
	# Two generations: the slot-pressure sell runs before this slice's verb
	# re-registers its chase, so last slice's protections still hold.
	for s in _protect_syms:
		p[String(s)] = 9.0e9
	for s2 in _protect_prev:
		p[String(s2)] = 9.0e9
	var obj: Dictionary = GameState.mission_manager.get_active_objective()
	var t = obj.get("target")
	if t is Dictionary:
		for sym in t:
			p[String(sym)] = 9.0e9
	elif t != null and String(obj.get("type", "")) in ["gather", "gather_multi"]:
		p[String(t)] = 9.0e9
	return p

# ---------------------------------------------------------------------------
# Combat support (grant-free ports of progression.gd machinery).
# ---------------------------------------------------------------------------
func _slot_indices(slot_type: String) -> Array:
	var sm = GameState.shipyard_manager
	var slots: Array = sm.hulls.get(sm.active_hull, {}).get("slots", [])
	var out := []
	for i in range(slots.size()):
		if String(slots[i]) == slot_type:
			out.append(i)
	return out

func _weapon_atype(mid: String) -> String:
	var st: Dictionary = GameState.shipyard_manager.modules.get(mid, {}).get("stats", {})
	if float(st.get("atk_cryo", 0)) > 0: return "cryo"
	if float(st.get("atk_explosive", 0)) > 0: return "explosive"
	if float(st.get("atk_energy", 0)) > 0: return "energy"
	return "kinetic"

func _enemy_weak_type(eid: String) -> String:
	var e: Dictionary = GameState.combat_manager.enemy_db.get(eid, {})
	if e.is_empty():
		return ""
	var rk := float(e.get("resist_k", 0.0))
	var re := float(e.get("resist_e", 0.0))
	var rx := float(e.get("resist_x", 0.0))
	var m: float = min(rk, min(re, rx))
	if m == rx: return "explosive"
	if m == re: return "energy"
	return "kinetic"

func _has_weapon_of_type_equipped(wtype: String) -> bool:
	var sm = GameState.shipyard_manager
	for i in _slot_indices("weapon"):
		var mid = sm.loadout.get(i, null)
		if mid and _weapon_atype(String(mid)) == wtype:
			return true
	return false

# Equip an owned weapon of `wtype` (craft the best-tier one if not owned).
# {} = done/equipped; task = what to do first.
func _equip_weapon_of_type(mid: String, wtype: String) -> Dictionary:
	var sm = GameState.shipyard_manager
	var cand := ""
	var cand_r := -1
	for inv_mid in sm.module_inventory:
		if int(sm.module_inventory.get(inv_mid, 0)) <= 0:
			continue
		var s := String(inv_mid)
		var def: Dictionary = sm.modules.get(s, {})
		if String(def.get("slot_type", "")) != "weapon":
			continue
		if _weapon_atype(s) != wtype:
			continue
		var r := int(sm.get_module_rarity(s))
		if r > cand_r:
			cand_r = r
			cand = s
	if cand == "":
		var suffix: String = {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}.get(wtype, "")
		if suffix == "":
			return {}
		return _do_craft(mid, "z1_%s" % suffix)
	var idxs := _slot_indices("weapon")
	for i in idxs:
		if not sm.loadout.get(i, null):
			if sm.equip_module(i, cand, true):
				sm.recalc_stats()
				return {}
	if idxs.size() > 0 and sm.equip_module(int(idxs[0]), cand, true):
		sm.recalc_stats()
		return {}
	return {}

# Real-economy ammo: craft to the archetype's buffer via the REAL recipe,
# then ASSIGN it (0-ammo weapons fire 0 damage silently — the fake-DNF hole).
# BOSS prep stocks a full fight's worth: with the 20-round trash floor, half of
# every session went to mid-fight re-crafting and the boss reset at each
# session boundary — 284 stalemate slices vs the Z2 Monolith (tail r4).
func _ensure_ammo_real(mid: String, for_boss: bool = false) -> Dictionary:
	var sm = GameState.shipyard_manager
	var res = GameState.resources
	for i in _slot_indices("weapon"):
		var w = sm.loadout.get(i, null)
		if not w:
			continue
		var atype := _weapon_atype(String(w))
		if atype == "cryo":
			continue
		var ammo := String(AMMO_FOR.get(atype, ""))
		if ammo == "":
			continue
		var floor_need := 20.0
		var buffer := float(params["ammo_buffer"])
		if for_boss:
			floor_need = max(buffer, 300.0)
		if res.get_element_amount(ammo) < floor_need:
			var d := _do_acquire(mid, ammo)
			if not d.is_empty():
				d["attr"] = "detour"
				return d
		elif bool(params["precraft"]) and res.get_element_amount(ammo) < buffer:
			var d2 := _do_acquire(mid, ammo)
			if not d2.is_empty():
				d2["attr"] = "detour"
				return d2
		if res.get_element_amount(ammo) > 0 and String(sm.ammo_loadout.get(i, "")) == "":
			sm.set_slot_ammo(i, ammo)
	return {}

# CANT_FIRE contract: armed + powered + every non-cryo weapon has stocked AND
# assigned ammo. Runner asserts this before every fight verdict.
func combat_ready() -> bool:
	var sm = GameState.shipyard_manager
	if not is_armed():
		return false
	if sm.energy_used > sm.energy_capacity:
		return false
	for i in _slot_indices("weapon"):
		var mid = sm.loadout.get(i, null)
		if not mid:
			continue
		if _weapon_atype(String(mid)) == "cryo":
			return true
		var ammo := String(AMMO_FOR.get(_weapon_atype(String(mid)), ""))
		if GameState.resources.get_element_amount(ammo) > 0 \
				and String(sm.ammo_loadout.get(i, "")) != "":
			return true
	return false

func kit_invariant_ok() -> bool:
	# From m024b2 claimed onward, no boss verdict counts without both kit slots
	# equipped + stocked (the fake-dps_wall guard).
	if not kits_taught:
		return true
	var sm = GameState.shipyard_manager
	if sm.consumable_hull_slot == "" or sm.consumable_shield_slot == "":
		return false
	if GameState.resources.get_element_amount(sm.consumable_hull_slot) < 1:
		return false
	if GameState.resources.get_element_amount(sm.consumable_shield_slot) < 1:
		return false
	return true

func _maintain_kits() -> void:
	# Post-teach kit upkeep: keep a small stock via the real recipes when
	# ingredients are on hand (no timed session burned; recipes run in-session
	# when stocks run dry via _prep_for_fight -> _do_acquire).
	if not kits_taught:
		return
	var sm = GameState.shipyard_manager
	if sm.consumable_hull_slot == "" \
			and GameState.resources.get_element_amount(KIT_HULL) >= 1:
		sm.equip_consumable("hull", KIT_HULL)
	if sm.consumable_shield_slot == "" \
			and GameState.resources.get_element_amount(KIT_SHIELD) >= 1:
		sm.equip_consumable("shield", KIT_SHIELD)

func _grind_processing_step(obj: String) -> Dictionary:
	# Run the highest-XP runnable recipe (real spend) to level processing.
	var pm = GameState.processing_manager
	var best := ""
	var best_xp := -1.0
	for rid in unlocked_recipes():
		if not recipe_runnable(rid):
			continue
		var xp := float(pm.recipes[rid].get("xp", 1))
		if xp > best_xp:
			best_xp = xp
			best = String(rid)
	if best == "":
		return {}
	return {"kind": "process", "mgr": pm, "id": best, "length": 30.0,
		"attr": "detour", "obj": obj, "why": "grind processing"}

# Fill empty slots (batteries first — power supply before consumers), then
# upgrade-swap equipped modules that are strictly lower rarity than the best
# owned. All via equip_module (power guard honored, return checked).
func _optimize_loadout() -> void:
	var sm = GameState.shipyard_manager
	for stype in ["battery", "shield", "armor", "engine", "sensor", "weapon"]:
		for i in _slot_indices(String(stype)):
			if sm.loadout.get(i, null):
				continue
			var cand := _best_inventory_module(String(stype))
			if cand != "":
				if sm.equip_module(i, cand, true):
					sm.recalc_stats()
	for stype in ["weapon", "shield", "armor"]:
		for i in _slot_indices(String(stype)):
			var cur = sm.loadout.get(i, null)
			if cur == null:
				continue
			var cand2 := _best_inventory_module(String(stype))
			if cand2 == "":
				continue
			if int(sm.get_module_rarity(cand2)) > int(sm.get_module_rarity(String(cur))):
				if sm.equip_module(i, cand2, true):
					sm.recalc_stats()

func _best_inventory_module(slot_type: String) -> String:
	var sm = GameState.shipyard_manager
	var best := ""
	var best_key := -1
	for inv_mid in sm.module_inventory:
		if int(sm.module_inventory.get(inv_mid, 0)) <= 0:
			continue
		var s := String(inv_mid)
		var def: Dictionary = sm.modules.get(s, {})
		if String(def.get("slot_type", "")) != slot_type:
			continue
		var key := int(sm.get_module_rarity(s)) * 100 + int(def.get("zone", 1))
		if key > best_key:
			best_key = key
			best = s
	return best

func _norm_mid(mid: String) -> String:
	# Telemetry determinism: custom ids embed wallclock ticks — log base+rarity.
	if mid.begins_with("custom_"):
		var def: Dictionary = GameState.shipyard_manager.modules.get(mid, {})
		return "custom:%s:r%d" % [String(def.get("base_module", "?")),
			int(GameState.shipyard_manager.get_module_rarity(mid))]
	return mid

# ---------------------------------------------------------------------------
# Fight-outcome learning (runner calls after each fight).
# ---------------------------------------------------------------------------
func note_fight_result(eid: String, won: bool) -> void:
	if won:
		_losses[eid] = 0
		_want_switch.erase(eid)
		return
	_losses[eid] = int(_losses.get(eid, 0)) + 1
	if int(_losses[eid]) >= int(params["switch_losses"]):
		_want_switch[eid] = true
	if int(_losses.get(eid, 0)) >= 2:
		_detoured_this_session[eid] = true

# ---------------------------------------------------------------------------
# Offline: leave the mission-relevant task running or offline yields nothing.
# ---------------------------------------------------------------------------
func pre_offline() -> void:
	# Always leave a GATHER running for the night. Processing offline is
	# ingredient-bounded (calculate_offline stops when inputs run out), so a
	# "smart" crafting away-task starves mid-gap — the matrix showed EFFICIENT
	# losing to FOLLOWER on the offline-carried cliffs because of exactly this.
	# Mission-relevant gather wins; else the archetype's income gather.
	var d := decide_step()
	var task: Dictionary = d
	if String(d.get("kind", "")) != "gather":
		task = _income("pre_offline", String(d.get("obj", "")), "detour")
		if String(task.get("kind", "")) != "gather":
			var bg := best_gather()
			task = {"kind": "gather", "mgr": GameState.gathering_manager, "id": String(bg[0])}
	var mgr = task["mgr"]
	if GameState.active_manager and GameState.active_manager != mgr:
		GameState.active_manager.stop_action()
	GameState.active_manager = mgr
	mgr.start_action(String(task["id"]))
