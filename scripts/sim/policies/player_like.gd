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
		"switch_losses": 3, "econ_infra": false, "id": 1},
	"efficient": {"day0_len": 7200.0, "sessions": 5, "session_len": 900.0,
		"claim_latency": 0.0, "claims_at_start_only": false, "smart_income": true,
		"precraft": true, "boredom_s": 1800.0, "kit_pct": 0.55, "ammo_buffer": 500,
		"switch_losses": 1, "econ_infra": true, "id": 2},
	"drifter": {"day0_len": 3600.0, "sessions": 4, "session_len": 480.0,
		"claim_latency": 0.0, "claims_at_start_only": true, "smart_income": false,
		"precraft": false, "boredom_s": 240.0, "kit_pct": 0.35, "ammo_buffer": 60,
		"switch_losses": 3, "econ_infra": false, "id": 3},
	"overnighter": {"day0_len": 1800.0, "sessions": 1, "session_len": 900.0,
		"claim_latency": 0.0, "claims_at_start_only": false, "smart_income": false,
		"precraft": false, "boredom_s": 900.0, "kit_pct": 0.45, "ammo_buffer": 100,
		"switch_losses": 3, "econ_infra": false, "id": 4},
}

# Discretionary economy-infra investment (EFFICIENT only). A real optimizer sinks
# surplus crafted mats + Liras into always-on buildings to support their economy;
# the mission-follower baseline only holds what missions mandate. Bounded so it
# never sabotages the funnel: capped per session, spends ONLY true surplus above
# every protected reserve + a Liras float, and provisions power BEFORE consumers
# (process_tick zeroes a starved grid's efficiency → an unpowered extractor yields 0).
const ECON_BUILDS_PER_SESSION := 3
const ECON_LIRA_RESERVE := 25000.0     # keep at least this many Liras after a build
const ECON_INPUT_FEED_CYCLES := 20     # hold >= input_qty x this to treat an input as self-produced
# An infra investor does NOT vendor their industrial mats to zero — they hoard a
# building stock. For econ_infra archetypes these amounts are ADDED to the sell
# reserve so the mats accumulate; builds then spend them down to WORKING_FLOOR.
const INFRA_KEEP := {"Si": 3000.0, "Fe": 1500.0, "Steel": 700.0, "Circuit": 80.0,
	"Ti": 250.0, "AdvCircuit": 80.0, "Hydraulics": 20.0}
# Working stock a build must leave behind (so a build never starves same-slice crafts).
const WORKING_FLOOR := {"Si": 150.0, "Fe": 200.0, "Steel": 50.0, "Circuit": 10.0,
	"Ti": 20.0, "AdvCircuit": 10.0, "Hydraulics": 5.0, "C": 50.0}

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
var _econ_builds_this_session := 0  # discretionary infra buys this session (EFFICIENT, capped)

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
	_econ_builds_this_session = 0

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
	_pump_bounties()
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
	# EFFICIENT sinks TRUE surplus into always-on economy infra (bounded, power-first).
	# BEFORE the slot-pressure vendor — a real optimizer builds with surplus mats
	# rather than selling them off first. (Post-sell, every mat sits at its reserve,
	# so nothing would ever read as surplus at build time.)
	_maybe_build_economy_infra()
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
	# v139c: protect the WHOLE recipe chain, not just the top symbol — the m030
	# AdvCircuit stall was slot-pressure sells vendoring Au/Ag/Semiconductor/
	# StructuralComponent as fast as the rotation produced them (advc froze at 5
	# for 90 sim-hours while credits rose ~1.9M at ~1/unit vendor prices).
	_protect_chain(sym)
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
	# diag: surface the exact blocking symbol (b.sym) so walls name what's short,
	# instead of a generic "blk=item" that leaves us guessing the bottleneck.
	status = "research:%s blk=%s%s" % [tid, String(b.get("kind", "?")),
		((" need=" + String(b.get("sym", "")) + " x" + str(b.get("amount", "?"))) if b.has("sym") else "")]
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

func _after_research_unlock(_tid: String) -> void:
	# v138: the old zone_6 AUTO_UI mirror is gone — warp_first_revealed now flips in
	# GAME LOGIC (combat_manager win_fight -> warp_manager.open_rift on a Zone-3+
	# boss kill), so headless earns it naturally; no UI contract to mirror.
	pass

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
	# v135a: bosses are gear-checks — the penetration wall walls common/uncommon, so
	# rare+ weak-type Zone-N gear is the intended answer. REACTIVE + targeted: attempt
	# with current gear FIRST (many bosses fall to the current hull + mixed loot); on
	# 2+ losses, farm the boss's OWN zone for rare weak-type gear until ready, THEN
	# retry — gear up and try again, don't detour away. Non-bosses keep the old
	# best-zone detour / income backoff (the v135 matrix showed pure income-idling
	# parked a run 52h at the Architect).
	if bool(cm.enemy_db.get(eid, {}).get("is_boss", false)):
		var _bl := int(_losses.get(eid, 0))
		# Escalate the gear bar on SUSTAINED losses: Uncommon by default, Rare after 5
		# real losses. Self-correcting — a boss winnable at Uncommon wins before the
		# streak escalates (no over-farm); one that needs Rare escalates on true losses.
		var _bar: int = 2 if _bl >= 5 else 1
		if _bl >= 2 and not _boss_gear_ready(eid, _bar):
			var reg := _regular_enemy_in_zone(zid)
			if reg != "" and reg != eid:
				status = "farming %s+ %s gear for %s" % [
					("rare" if _bar >= 2 else "uncommon"), _enemy_weak_type(eid), eid]
				return _do_combat_farm(mid, zid, reg, "detour")
		# Gear-ready but STILL losing → maybe the HULL is the bottleneck. A real player
		# figures out to build a bigger ship; the bot works it out ITSELF (NO hand-holding
		# mission). But ONLY when genuinely UNDER-HULLED — hull tier < the boss's zone —
		# else the loss is a gear/RNG problem and rebuilding just burns resources (an early
		# version rebuilt hulls at every hard boss and regressed the funnel). At/above the
		# zone tier the answer is better gear, not a bigger ship.
		var _htier := int(GameState.shipyard_manager.hulls.get(GameState.shipyard_manager.active_hull, {}).get("tier", 0))
		var _bzone := int(cm.enemy_db.get(eid, {}).get("zone", 0))
		if _bl >= 5 and _htier < _bzone:
			var _up := _best_better_hull()
			if _up != "":
				status = "hull too small for %s -> building %s" % [eid, _up]
				return _do_construct(mid, _up)
	elif int(_losses.get(eid, 0)) >= 2 and _detoured_this_session.get(eid, false):
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
	# Type matching once taught (or EFFICIENT after 1 loss wants the switch). Commit
	# the FULL weapon loadout to the enemy's weak type, not just one slot — the helper
	# is idempotent (skips slots already carrying the counter).
	if type_match_taught or _want_switch.get(eid, false):
		var weak := _enemy_weak_type(eid)
		if weak != "":
			var got := _equip_weapon_of_type(mid, weak)
			if not got.is_empty():
				return got
	# Power BEFORE ammo: re-power (craft/equip batteries) with the weapon loadout now
	# settled, so ammo is assigned LAST against the final loadout. Doing power after
	# ammo let a re-power change the loadout post-ammo → prep passed but combat_ready
	# was false (CANT_FIRE). A real player re-powers after offline combat destroys a
	# battery (intended risk) — the funnel then counts the re-craft time.
	var pw := _ensure_powered(mid)
	if not pw.is_empty():
		return pw
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
	_work_zone_board(zid, eid)
	return {"kind": "combat_farm", "zone": zid, "enemy": eid, "length": 120.0,
		"attr": attr, "obj": mid, "why": "farm %s @%s" % [eid, zid]}

# v139c: recursive sell-protection for an acquire chase — the target symbol
# AND every input down its recipe chain (depth-capped). A real player does not
# vendor the semiconductor stock they are crafting circuits from.
func _protect_chain(sym: String, depth: int = 0) -> void:
	if depth > 4 or _protect_syms.has(sym):
		return
	_protect_syms[sym] = true
	var rid: String = actions.recipe_producing(sym)
	if rid == "":
		return
	for inp in GameState.processing_manager.recipes.get(rid, {}).get("input", {}):
		_protect_chain(String(inp), depth + 1)

# --- Bounty board play (v139c) ---------------------------------------------
# Real players work the zone contract board while farming: kills count toward
# an accepted hunt passively, and a claimed contract pays a GUARANTEED
# Rare-floor module — the designed deterministic bridge over drop-RNG gear
# walls (m030d teaches this in-game as of v139c). No grants: accept + claim
# are ordinary player actions through the manager API.
func _pump_bounties() -> void:
	var bm = GameState.bounty_manager
	if bm == null:
		return
	for c in bm.active_contracts.duplicate():
		if bool(c.get("completed", false)) and not bool(c.get("claimed", false)):
			bm.claim_contract(String(c.get("id", "")))

func _work_zone_board(zid: String, eid: String) -> void:
	var bm = GameState.bounty_manager
	if bm == null or bm.active_contracts.size() >= bm.MAX_ACTIVE:
		return
	var have := {}
	for c in bm.active_contracts:
		have[String(c.get("target", ""))] = true
	for c in bm.get_zone_contracts(zid):
		# The farming bot takes the plain hunt on the enemy it is ALREADY
		# killing — elites spike danger and boss bounties are deliberate runs.
		if bool(c.get("is_elite", false)) or bool(c.get("is_boss_hunt", false)):
			continue
		var tgt := String(c.get("target", ""))
		if tgt == eid and not have.has(tgt):
			bm.accept_contract(String(c.get("id", "")))
			return

# --- Gear-check readiness (v135a) ---------------------------------------------
# A Zone-N boss is a gear-check: rare+ weak-type weapons + rare+ armor/shield beat
# it, while common/uncommon are walled by the v115 penetration wall. The bot farms
# the boss's OWN zone (drops Zone-N modules, Uncommon+ always, ~30% Rare+) until it
# owns that set, then attempts — modelling the intended "loot the tier" play instead
# of throwing common-gear attempts. Bounded by the sim day-cap, so an impossibly
# long grind surfaces honestly as a wall rather than an infinite loop.
# Zone tier of a module: z1_* -> 1, z2_missile -> 2, a dropped/custom module -> its
# base_module's zone. v120 removed the under-tier damage wall, so zone is now a proxy
# for RAW POWER — per-zone enemy tuning means out-damaging a Zone-N boss needs ~Zone-N
# gear. Returns 0 for a non-z-prefixed id (unknown -> treated as under-tier).
func _module_zone(mid: String) -> int:
	var base := String(GameState.shipyard_manager.modules.get(mid, {}).get("base_module", mid))
	if base.length() >= 2 and base[0] == "z":
		var d := ""
		var i := 1
		while i < base.length() and base[i] >= "0" and base[i] <= "9":
			d += base[i]
			i += 1
		if d != "":
			return int(d)
	return 0

# min_zone (default 0 = any): also require the module to be at least that zone tier.
func _count_owned(slot_type: String, wtype: String, min_rarity: int, min_zone: int = 0) -> int:
	var sm = GameState.shipyard_manager
	var n := 0
	for inv_mid in sm.module_inventory:
		var c := int(sm.module_inventory.get(inv_mid, 0))
		if c <= 0:
			continue
		var s := String(inv_mid)
		if String(sm.modules.get(s, {}).get("slot_type", "")) != slot_type:
			continue
		if wtype != "" and _weapon_atype(s) != wtype:
			continue
		if min_zone > 0 and _module_zone(s) < min_zone:
			continue
		if int(sm.get_module_rarity(s)) >= min_rarity:
			n += c
	for i in _slot_indices(slot_type):
		var l = sm.loadout.get(i, null)
		if l:
			var ls := String(l)
			if (wtype == "" or _weapon_atype(ls) == wtype) \
					and (min_zone <= 0 or _module_zone(ls) >= min_zone) \
					and int(sm.get_module_rarity(ls)) >= min_rarity:
				n += 1
	return n

func _boss_gear_ready(eid: String, min_rarity: int = 1) -> bool:
	# v120 removed the under-tier damage wall — a boss is now a pure DPS-vs-EHP race,
	# so "ready" must mean gear strong enough to actually out-damage/out-last it, not
	# merely the right rarity+type. Require the loadout to be at least the boss's ZONE
	# tier (per-zone enemy tuning makes zone a faithful proxy for raw power: a Z1 rare
	# gun can't out-DPS a Z2 boss's HP/DEF). This is the designed "rare+ Zone-N gear"
	# check (weapons AND armor AND shield) — it stops the bot livelocking against the
	# Z2 Monolith with Z1 weapons it miscounted as "ready" (54 lost attempts, 0 farming).
	# min_rarity is the Uncommon(1)/Rare(2) bar _do_combat escalates after sustained losses.
	var weak := _enemy_weak_type(eid)
	var bz: int = int(GameState.combat_manager.enemy_db.get(eid, {}).get("zone", 0))
	# weak=="" (zeroed-resist rarity boss, e.g. Z1 Architect) => any type; else strong type.
	# Only the WEAPON is zone-gated — it's the DPS driver, and the Z1-gun-vs-Z2-boss
	# under-DPS livelock is a weapon problem. Armor/shield stay rarity-only: defensive
	# slots a tier behind still work if the weapon out-damages fast enough, so zone-
	# gating them too was over-strict (it demanded a full boss-zone set no follower
	# farms in 14 days, when 2/3 beat the Monolith with a mixed loadout).
	if _count_owned("weapon", weak, min_rarity, bz) < _slot_indices("weapon").size():
		return false
	if _slot_indices("armor").size() > 0 and _count_owned("armor", "", min_rarity) < 1:
		return false
	if _slot_indices("shield").size() > 0 and _count_owned("shield", "", min_rarity) < 1:
		return false
	return true

# The next hull tier the bot has UNLOCKED (research-gated by zone access) above its
# current one — the ship a real player builds to push forward. Smallest tier > current
# (incremental, not a leap to an unaffordable capital). _do_construct then handles
# affordability (acquire mats/credits); construct_hull auto-transfers the loadout.
func _best_better_hull() -> String:
	var sm = GameState.shipyard_manager
	var cur_tier := int(sm.hulls.get(sm.active_hull, {}).get("tier", 0))
	var pick := ""
	var pick_tier := 999
	for hid in sm.hulls:
		var h: Dictionary = sm.hulls[hid]
		var t := int(h.get("tier", 0))
		if t <= cur_tier or t >= pick_tier:
			continue
		var rr = h.get("research_req")
		if rr and not GameState.research_manager.is_tech_unlocked(String(rr)):
			continue
		pick = String(hid)
		pick_tier = t
	return pick

func _regular_enemy_in_zone(zid: String) -> String:
	# Only BACK-half enemies (e3+) drop MODULES — front (e1/e2) are materials-only
	# (enemy_is_front_salvage), so farming them yields ZERO modules. Prefer a
	# module-dropper whose pool includes WEAPONS (the gear-check bottleneck), then
	# armor/shield; fall back to any non-boss if none qualifies.
	var cm = GameState.combat_manager
	var fallback := ""
	var best := ""
	var best_score := -1
	for e in cm.zones.get(zid, {}).get("enemies", []):
		var es := String(e)
		var ed: Dictionary = cm.enemy_db.get(es, {})
		if bool(ed.get("is_boss", false)):
			continue
		if fallback == "":
			fallback = es
		if cm.enemy_is_front_salvage(es, zid):
			continue
		var has_w := false
		var has_a := false
		var has_s := false
		for m in ed.get("module_drop_pool", []):
			var st := String(GameState.shipyard_manager.modules.get(String(m), {}).get("slot_type", ""))
			if st == "weapon": has_w = true
			elif st == "armor": has_a = true
			elif st == "shield": has_s = true
		var score := int(has_w) * 4 + int(has_a) + int(has_s)
		if score > best_score:
			best_score = score
			best = es
	return best if best != "" else fallback

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
# Discretionary economy infrastructure (EFFICIENT archetype only).
# Instant (no timed slice) — mirrors research/craft buys. Called once per
# decide_step BEFORE the mission loop; builds at most one building, so it
# interleaves naturally with play. Every safety lives in the pick/afford gates:
# true-surplus spend (never dips a protected reserve), a Liras float, input
# self-sufficiency, and power-before-consumers. FOLLOWER/DRIFTER/OVERNIGHTER keep
# econ_infra=false → they stay the clean mission-minimum baseline to compare against.
# ---------------------------------------------------------------------------
func _maybe_build_economy_infra() -> void:
	if not bool(params.get("econ_infra", false)):
		return
	if _econ_builds_this_session >= ECON_BUILDS_PER_SESSION:
		return
	# The best sustainable, affordable YIELD building we'd like to own (power aside).
	# Power generators are NEVER built speculatively — only to unblock a concrete
	# extractor/refinery, so the bot never stacks pointless solar arrays.
	var y := _pick_yield_building()
	if y == "":
		return
	var im = GameState.infrastructure_manager
	var cons := float(im.building_db[y].get("energy_cons", 0.0))
	if cons <= max(0.0, im.net_energy):
		_build_econ(y)                       # grid can power it → build the yield building
	else:
		var p := _pick_power_building()      # need power first → best affordable generator
		if p != "":
			_build_econ(p)                   # next slice the yield building is powerable

# Best affordable, input-sustainable production building, ranked by Liras/sec output.
func _pick_yield_building() -> String:
	var im = GameState.infrastructure_manager
	var pick := ""
	var pick_score := -1.0
	for bid in im.building_db:
		var b: Dictionary = im.building_db[bid]
		if (b.get("yield", {}) as Dictionary).is_empty():
			continue
		var rr = b.get("research_req")
		if rr and not GameState.research_manager.is_tech_unlocked(String(rr)):
			continue
		if not _input_sustainable(b):
			continue
		if not _econ_affordable(String(bid)):
			continue
		var score := _yield_value_per_sec(b)
		if score > pick_score:
			pick_score = score
			pick = String(bid)
	return pick

# Best affordable, fuel-sustainable generator, ranked by raw energy_gen.
func _pick_power_building() -> String:
	var im = GameState.infrastructure_manager
	var pick := ""
	var pick_gen := -1.0
	for bid in im.building_db:
		var b: Dictionary = im.building_db[bid]
		var gen := float(b.get("energy_gen", 0.0))
		if gen <= 0.0:
			continue
		var rr = b.get("research_req")
		if rr and not GameState.research_manager.is_tech_unlocked(String(rr)):
			continue
		if not _input_sustainable(b):
			continue
		if not _econ_affordable(String(bid)):
			continue
		if gen > pick_gen:
			pick_gen = gen
			pick = String(bid)
	return pick

# A building's ongoing input counts as "self-produced" when we already hold many
# cycles of feed — a real player builds a smelter only once they're mining its ore.
func _input_sustainable(b: Dictionary) -> bool:
	var res = GameState.resources
	var inp: Dictionary = b.get("input", {})
	for sym in inp:
		if res.get_element_amount(String(sym)) < float(inp[sym]) * float(ECON_INPUT_FEED_CYCLES):
			return false
	return true

# Spend only accumulated surplus: every cost material must remain above its WORKING
# floor after paying (and NEVER touch an actively-chased mission mat), Liras above
# the float. The high sell-reserve (INFRA_KEEP, applied in _protected) is what let
# the stock accumulate; the low build-floor here is what lets a build spend it.
func _econ_affordable(bid: String) -> bool:
	var res = GameState.resources
	var cost: Dictionary = GameState.infrastructure_manager.get_building_cost(bid)
	for sym in cost:
		var s := String(sym)
		var qty := float(cost[sym])
		if s == "credits":
			if res.get_currency("credits") - qty < ECON_LIRA_RESERVE:
				return false
		elif res.get_element_amount(s) - qty < _build_floor(s):
			return false
	return true

# Minimum of a cost mat a build must leave behind. Actively-chased mats (this slice
# or last) are untouchable — a build must never eat what a mission is farming for.
func _build_floor(sym: String) -> float:
	if _protect_syms.has(sym) or _protect_prev.has(sym):
		return 9.0e9
	return float(WORKING_FLOOR.get(sym, 0.0))

func _yield_value_per_sec(b: Dictionary) -> float:
	var interval := float(b.get("interval", 1.0))
	if interval <= 0.0:
		interval = 1.0
	var v := 0.0
	var yld: Dictionary = b.get("yield", {})
	for sym in yld:
		v += float(ElementDB.get_element_value(String(sym))) * float(yld[sym])
	return v / interval

func _build_econ(bid: String) -> void:
	if GameState.infrastructure_manager.build(bid):
		_econ_builds_this_session += 1
		pending_events.append({"t": "build_econ", "building": bid,
			"n": GameState.infrastructure_manager.get_building_count(bid)})

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
	# Infra investors (EFFICIENT) hoard a building stock rather than vendoring
	# industrial mats to zero — so a discretionary build has something to spend.
	if bool(params.get("econ_infra", false)):
		for sym in INFRA_KEEP:
			p[String(sym)] = max(float(p.get(String(sym), 0.0)), float(INFRA_KEEP[sym]))
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
	# No meaningful weakness (e.g. the Z1 Architect ZEROES all resists as a pure
	# rarity/tier check — any RARE+ type kills it). Don't fabricate a phantom weak
	# type: the old min() tie on (0,0,0) always resolved to "explosive", sending the
	# bot to farm a type constraint that doesn't exist. "" => any type works.
	if rk == re and re == rx:
		return ""
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

# Highest EFFECTIVE-DPS owned (unequipped, count>0) weapon of `wtype`, else "".
# Ranks by DAMAGE, not rarity: a full tier step is ~2.2x (shipyard v115 note), so a
# common Z3 gun out-damages a rare Z2 one. The old rarity-first pick fought the
# 17k-hull Z3 Warmaster with a shiny-but-weak Z2 weapon and couldn't out-DPS it.
func _best_counter_in_inventory(wtype: String) -> String:
	var sm = GameState.shipyard_manager
	var pick := ""
	var pick_dps := -1.0
	for inv_mid in sm.module_inventory:
		if int(sm.module_inventory.get(inv_mid, 0)) <= 0:
			continue
		var s := String(inv_mid)
		if String(sm.modules.get(s, {}).get("slot_type", "")) != "weapon":
			continue
		if _weapon_atype(s) != wtype:
			continue
		var st: Dictionary = sm.modules.get(s, {}).get("stats", {})
		var interval := float(st.get("atk_interval", 1.0))
		if interval <= 0.0:
			interval = 1.0
		var dps := float(st.get("atk_%s" % wtype, 0.0)) / interval
		if dps > pick_dps:
			pick_dps = dps
			pick = s
	return pick

# Commit EVERY weapon slot to the counter type (a boss weak to `wtype` wants a
# FULL counter loadout, not one slot — the old one-slot swap left the boss's
# resisted majority in the other slots and lost razor-thin fights). Unequip-first
# frees each slot's power so a heavier counter (Concussion Missile = load 18 vs
# 15) fits under equip_module's power guard once Z2 batteries provide headroom.
# Owned copies are consumed from module_inventory as we go; slots beyond the
# owned count keep their optimized weapon. Craft the best fabricable tier (Z2 if
# its research is unlocked) when none is owned. {} = done/equipped; task = craft first.
func _equip_weapon_of_type(mid: String, wtype: String) -> Dictionary:
	var sm = GameState.shipyard_manager
	# None owned (inventory) and none equipped -> craft the best tier we can make.
	if _best_counter_in_inventory(wtype) == "" and not _has_weapon_of_type_equipped(wtype):
		var suffix: String = {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}.get(wtype, "")
		if suffix == "":
			return {}
		var z2id := "z2_%s" % suffix
		var z2req := String(sm.modules.get(z2id, {}).get("research_req", ""))
		if sm.modules.has(z2id) and (z2req == "" or GameState.research_manager.is_tech_unlocked(z2req)):
			return _do_craft(mid, z2id)
		return _do_craft(mid, "z1_%s" % suffix)
	for i in _slot_indices("weapon"):
		var cur = sm.loadout.get(i, null)
		if cur and _weapon_atype(String(cur)) == wtype:
			continue                                   # slot already the counter
		var pick := _best_counter_in_inventory(wtype)
		if pick == "":
			break                                      # out of owned counters
		if cur:
			sm.unequip_slot(int(i))                    # free power; return cur to inv
		if not sm.equip_module(int(i), pick, true):
			if cur:
				sm.equip_module(int(i), String(cur), true)  # power-blocked -> restore
			break
	sm.recalc_stats()
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

# Re-power the ship by equipping owned batteries into empty slots, then CRAFTING
# more when the stock is dry — the real recovery after offline combat destroys a
# battery (intended risk) or a hull upgrade raises draw. Equipping is instant, so
# loop it; crafting returns a timed task the runner ticks (the funnel then counts
# the re-craft time). Blocks only when a battery is genuinely unsourceable.
func _ensure_powered(mid: String) -> Dictionary:
	var sm = GameState.shipyard_manager
	for _guard in range(8):
		if sm.energy_used <= sm.energy_capacity:
			return {}
		var empty := -1
		for i in _slot_indices("battery"):
			if not sm.loadout.get(i, null):
				empty = int(i)
				break
		if empty < 0:
			return _blocked(mid, "power_wall used=%d cap=%d (battery slots full)" % [sm.energy_used, sm.energy_capacity])
		var bat := _best_owned_or_craftable_battery()
		if bat == "":
			return _blocked(mid, "power_wall used=%d cap=%d (no craftable battery)" % [sm.energy_used, sm.energy_capacity])
		if int(sm.module_inventory.get(bat, 0)) > 0:
			if not sm.equip_module(empty, bat, true):
				return _blocked(mid, "battery equip rejected (%s)" % bat)
			sm.recalc_stats()
			pending_events.append({"t": "equip", "mid": mid, "slot": "battery", "module": _norm_mid(bat)})
			continue
		return _do_craft(mid, bat)   # none owned → craft a replacement (timed task)
	return _blocked(mid, "power_wall recovery guard")

# Highest-capacity battery the bot can slot: research-unlocked, and either already
# owned or craftable (has a cost). Base modules only — customs are drops, not crafted.
func _best_owned_or_craftable_battery() -> String:
	var sm = GameState.shipyard_manager
	var best := ""
	var best_cap := -1
	for bid in sm.modules:
		var s := String(bid)
		if s.begins_with("custom_"):
			continue
		var d: Dictionary = sm.modules[bid]
		if String(d.get("slot_type", "")) != "battery":
			continue
		var rr = d.get("research_req")
		if rr and not GameState.research_manager.is_tech_unlocked(String(rr)):
			continue
		var owned: bool = int(sm.module_inventory.get(s, 0)) > 0
		var craftable: bool = not (d.get("cost", {}) as Dictionary).is_empty()
		if not (owned or craftable):
			continue
		var cap := int(sm.get_module_energy_capacity(s))
		if cap > best_cap:
			best_cap = cap
			best = s
	return best

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
			if _module_rank(cand2) > _module_rank(String(cur)):
				if sm.equip_module(i, cand2, true):
					sm.recalc_stats()

# Tier-first module rank: a full zone step (~2.2x stats) out-scales every rarity
# (shipyard v115), so zone dominates and rarity only tiebreaks within a tier. The
# old rarity-first key preferred a rare low-tier module over a common high-tier one.
func _module_rank(mid: String) -> int:
	var sm = GameState.shipyard_manager
	return int(sm.modules.get(mid, {}).get("zone", 1)) * 100 + int(sm.get_module_rarity(mid))

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
		var key := _module_rank(s)
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
	var d := decide_step()
	# v135a: if we're actively (gear-)farming combat, leave COMBAT running for the
	# night — offline combat now drops the module pool, so the gear-check grind
	# amortizes while away (models a player parking on a winnable farm zone). The
	# winnability gate in calculate_offline protects an unwinnable pin.
	var dk := String(d.get("kind", ""))
	if dk == "combat" or dk == "combat_farm":
		var zid := String(d.get("zone", ""))
		var eid := String(d.get("enemy", ""))
		if zid != "" and eid != "" and _prep_for_fight(String(d.get("obj", "")), eid).is_empty():
			var cm = GameState.combat_manager
			if GameState.active_manager and GameState.active_manager != cm:
				GameState.active_manager.stop_action()
			cm.start_expedition(zid)
			cm.set_target_enemy(eid)
			if cm.current_enemy != null and String(cm.current_enemy.get("id", "")) == eid:
				return   # combat pinned — offline farming loots the gear
	# Otherwise leave a GATHER running for the night. Processing offline is
	# ingredient-bounded (calculate_offline stops when inputs run out), so a
	# "smart" crafting away-task starves mid-gap — the matrix showed EFFICIENT
	# losing to FOLLOWER on the offline-carried cliffs because of exactly this.
	# Mission-relevant gather wins; else the archetype's income gather.
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
