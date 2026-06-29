extends "res://scripts/sim/policy_base.gd"

# ============================================================================
# Progression policy — a greedy AI player that takes a FRESH game from Z1 to
# Z10-cleared. Used by progression_bot.gd across 3 scenarios (0/1/2 warps).
# Build on policy_base (unlock_toward / buy_buildings / sell_surplus / best_gather
# / recipe_runnable / unlocked_*). Combat is driven by the runner (boss_kills
# delta = win); this policy only DECIDES and does instant meta unblocks.
# All facts verified against live code — see _botspec.md / memory progression-bot.
# ============================================================================

const ZONE_KEY := {1:"lunar_orbit", 2:"asteroid_belt", 3:"mars_debris", 4:"cryofield",
	5:"sector_alpha", 6:"sector_beta", 7:"sector_gamma", 8:"sector_delta",
	9:"sector_zeta", 10:"sector_epsilon"}
const AMMO_FOR := {"kinetic":"SlugT1", "energy":"CellT1", "explosive":"MissileT1"}
const AMMO_RECIPE := {"SlugT1":"craft_slug_t1", "CellT1":"craft_cell_t1", "MissileT1":"craft_missile_t1"}

# --- representative-drops combat model -------------------------------------
# Combat power = gear (drops) only. We model the real spine (credits, research,
# hull upgrades, boss-core farming, trash-farm TIME) but GRANT the module drops
# a player would farm, sized per zone, so bosses are winnable. See memory
# progression-bot "COMBAT REALITY".
const HULL_RANK := {"corvette_hull":0, "frigate_hull":1, "destroyer_hull":2, "cruiser_hull":3,
	"battlecruiser_hull":4, "capital_hull":5, "carrier_hull":6, "dreadnought_hull":7}
const HULL_BY_RANK := ["corvette_hull", "frigate_hull", "destroyer_hull", "cruiser_hull",
	"battlecruiser_hull", "capital_hull", "carrier_hull", "dreadnought_hull"]
# per-zone baseline hull the bot funds toward (escalated further by _hull_bump on
# a hard dps wall). Cruiser+ are zone-gated; _build_hull caps at what's researched.
const HULL_FOR_ZONE := {1:"frigate_hull", 2:"frigate_hull", 3:"frigate_hull", 4:"destroyer_hull",
	5:"destroyer_hull", 6:"cruiser_hull", 7:"cruiser_hull", 8:"battlecruiser_hull",
	9:"battlecruiser_hull", 10:"capital_hull"}
const RARITY_FARM := 1            # UNCOMMON drops for trash-farming
const RARITY_BOSS := 2            # RARE baseline for boss; escalates LEG(3)/UNIQUE(4) on loss
# industrial/research materials we GRANT on demand (deep processing chains the
# economy could make, abstracted as farm/refine output). Credits + boss cores
# stay REAL (earned / fought).
const GRANTABLE := ["Steel","Circuit","AdvCircuit","Ti","Superalloy","QuantumCore","VoidArtifact",
	"Res1","Res2","Res3","SalvagedAlloy","DamagedCircuitry"]

var target_warps := 0
var cleared := {}                 # {tier:int -> true}; set by runner on boss_kills delta
var farm_kills := {}              # {zone:int -> trash kills done}; gates the drop grant
var drops_granted := {}           # {zone:int -> true} once farmed enough -> boss-tier drops
var _hull_bump := {}              # {zone:int -> extra hull ranks} when maxed drops still wall
var _armed_for := -1              # zone the current granted loadout is sized for
var _armed_rarity := -1
var _force_fresh_rearm := false
var last_gate_reason := "none"    # filled by decide_session for telemetry
var _boss_loss := {}              # {zone:int -> consecutive losses}; drives drop-rarity escalation

# ---------------------------------------------------------------------------
func _next_uncleared_zone() -> int:
	for n in range(1, 11):
		if not cleared.get(n, false):
			return n
	return 11

func _tier_of(zid: String) -> int:
	for n in ZONE_KEY:
		if ZONE_KEY[n] == zid:
			return int(n)
	return 0

func _boss_id(n: int) -> String:
	var cm = GameState.combat_manager
	var zid: String = ZONE_KEY.get(n, "")
	if zid == "" or not zid in cm.zones:
		return ""
	var enemies: Array = cm.zones[zid].get("enemies", [])
	return String(enemies[4]) if enemies.size() >= 5 else ""

func _boss_weak_type(n: int) -> String:
	var cm = GameState.combat_manager
	var e: Dictionary = cm.enemy_db.get(_boss_id(n), {})
	var rk := float(e.get("resist_k", 0.0))
	var re := float(e.get("resist_e", 0.0))
	var rx := float(e.get("resist_x", 0.0))
	var m: float = min(rk, min(re, rx))
	if m == rx: return "explosive"
	if m == re: return "energy"
	return "kinetic"

func _gate_tech(n: int) -> String:
	return "zone_%d_access" % n

# Shortfall over zone_N_access: {sym|"credits": amount_still_needed}. Empty = affordable/owned.
func _gate_shortfall(n: int) -> Dictionary:
	var rm = GameState.research_manager
	var res = GameState.resources
	var out := {}
	var tid := _gate_tech(n)
	if not tid in rm.tech_tree:
		return out
	var node: Dictionary = rm.tech_tree[tid]
	var cr_need := int(float(node.get("cost", 0)) * rm.COST_MULTIPLIER)
	var cr_have := int(res.get_currency("credits"))
	if cr_need - cr_have > 0:
		out["credits"] = cr_need - cr_have
	var items: Dictionary = node.get("cost_items", {})
	for sym in items:
		var need := int(float(items[sym]) * rm.MATERIAL_MULTIPLIER)
		var have := int(res.get_element_amount(String(sym)))
		if need - have > 0:
			out[String(sym)] = need - have
	return out

# ---- ammo ------------------------------------------------------------------
func _ammo_supportable(atype: String) -> bool:
	# Can we feed this weapon type? cryo needs no ammo; others need their ammo
	# element stocked OR its recipe attainable (research-reachable).
	if atype == "cryo":
		return true
	var ammo: String = AMMO_FOR.get(atype, "")
	if ammo == "":
		return false
	if GameState.resources.get_element_amount(ammo) > 0:
		return true
	var rid: String = AMMO_RECIPE.get(ammo, "")
	if rid == "" or not rid in GameState.processing_manager.recipes:
		return false
	var rr = GameState.processing_manager.recipes[rid].get("research_req")
	return (rr == null) or GameState.research_manager.is_tech_unlocked(rr) or GameState.research_manager.can_unlock(rr)

func _weapon_atype(mid: String) -> String:
	var st: Dictionary = GameState.shipyard_manager.modules.get(mid, {}).get("stats", {})
	if float(st.get("atk_cryo", 0)) > 0: return "cryo"
	if float(st.get("atk_explosive", 0)) > 0: return "explosive"
	if float(st.get("atk_energy", 0)) > 0: return "energy"
	return "kinetic"

# ---- gear ------------------------------------------------------------------
func _slot_indices(slot_type: String) -> Array:
	var sm = GameState.shipyard_manager
	var slots: Array = sm.hulls.get(sm.active_hull, {}).get("slots", [])
	var out := []
	for i in range(slots.size()):
		if String(slots[i]) == slot_type:
			out.append(i)
	return out

func _module_id(n: int, suffix: String) -> String:
	return "z%d_%s" % [n, suffix]

# Craft + equip the best affordable module of slot_type at tier<=N into a free slot.
func _equip_best(slot_type: String, suffix_for_zone, N: int) -> bool:
	var sm = GameState.shipyard_manager
	var idxs := _slot_indices(slot_type)
	if idxs.is_empty():
		return false
	# already have one equipped? keep it (re-equip handled by _force_fresh_rearm).
	for i in idxs:
		if sm.loadout.get(i, null):
			return true
	for k in range(N, 0, -1):
		var mid := _module_id(k, suffix_for_zone) if typeof(suffix_for_zone) == TYPE_STRING else ""
		if mid == "" or not mid in sm.modules:
			continue
		# craft if not in inventory, then equip into the first free matching slot.
		if int(sm.module_inventory.get(mid, 0)) <= 0:
			if not sm.craft_module(mid):
				continue
		for i in idxs:
			if not sm.loadout.get(i, null):
				if sm.equip_module(i, mid, true):
					sm.recalc_stats()
					return true
	return false

const TYPE_SUFFIX := {"kinetic":"kinetic", "energy":"energy", "explosive":"missile"}

# Highest tier<=N module of `suffix` whose non-credit cost mats are reachable now;
# falls back to the highest existing module so callers can still drive toward it.
func _best_tier_module(N: int, suffix: String) -> String:
	var sm = GameState.shipyard_manager
	var fallback := ""
	for k in range(N, 0, -1):
		var mid := "z%d_%s" % [k, suffix]
		if not mid in sm.modules:
			continue
		if fallback == "":
			fallback = mid
		var cost: Dictionary = sm.get_effective_module_cost(sm.modules[mid])
		var ok := true
		for sym in cost:
			if String(sym) == "credits":
				continue
			if not _reachable_now(String(sym), 0):
				ok = false
				break
		if ok:
			return mid
	return fallback

# Can we build a weapon of this damage type now (module exists, ammo feedable,
# mats reachable with current levels)?
func _weapon_buildable(N: int, atype: String) -> bool:
	if not _ammo_supportable(atype):
		return false
	var suffix: String = TYPE_SUFFIX.get(atype, "")
	if suffix == "":
		return false
	var sm = GameState.shipyard_manager
	for k in range(N, 0, -1):
		var mid := "z%d_%s" % [k, suffix]
		if not mid in sm.modules:
			continue
		var cost: Dictionary = sm.get_effective_module_cost(sm.modules[mid])
		var ok := true
		for sym in cost:
			if String(sym) == "credits":
				continue
			if not _reachable_now(String(sym), 0):
				ok = false
				break
		if ok:
			return true
	return false

# Kinetic is the reliable backbone (Fe-only weapon + SlugT1 ammo from Fe), so we
# commit to it by default — chasing the weak type early just thrashes on its ammo
# / alloy chain. We only ESCALATE to the boss's weak type after kinetic has lost
# to that boss a few times (set via note_fight), and only if it's buildable.
func _choose_weapon_type(N: int) -> String:
	if _boss_loss.get(N, 0) >= 3:
		var weak := _boss_weak_type(N)
		if weak != "kinetic" and _weapon_buildable(N, weak):
			return weak
	if _weapon_buildable(N, "kinetic"):
		return "kinetic"
	var w := _boss_weak_type(N)
	if _weapon_buildable(N, w):
		return w
	for t in ["energy", "explosive"]:
		if _weapon_buildable(N, t):
			return t
	return "kinetic"

# Called by the runner after each boss fight so the policy can escalate power:
# first drop rarity (RARE->LEG->UNIQUE), then — if maxed and still losing — the hull.
func note_fight(N: int, won: bool) -> void:
	if won:
		_boss_loss[N] = 0
		return
	_boss_loss[N] = int(_boss_loss.get(N, 0)) + 1
	if _boss_loss[N] >= 3:                 # rarity maxed (UNIQUE) and still walling -> bigger hull
		_hull_bump[N] = int(_hull_bump.get(N, 0)) + 1
		_boss_loss[N] = 0
		_armed_for = -1

# Equip the best tier<=N module of `suffix` into the FIRST EMPTY slot of this
# type (craft if needed). Unlike _equip_best it doesn't stop at one — used to
# fill BOTH battery slots so the weapon always has power headroom.
func _equip_into_empty(slot_type: String, suffix: String, N: int) -> bool:
	var sm = GameState.shipyard_manager
	var free := -1
	for i in _slot_indices(slot_type):
		if not sm.loadout.get(i, null):
			free = i
			break
	if free == -1:
		return false
	for k in range(N, 0, -1):
		var mid := "z%d_%s" % [k, suffix]
		if not mid in sm.modules:
			continue
		if int(sm.module_inventory.get(mid, 0)) <= 0:
			if not sm.craft_module(mid):
				continue
		if sm.equip_module(free, mid, true):
			sm.recalc_stats()
			return true
	return false

func _fill_batteries(N: int) -> void:
	var guard := 0
	while guard < 4 and _equip_into_empty("battery", "battery", N):
		guard += 1

func _arm_for_zone(N: int) -> void:
	if _force_fresh_rearm:
		_force_fresh_rearm = false
		_armed_for = -1
	var rarity: int = _drop_rarity(N) if drops_granted.get(N, false) else RARITY_FARM
	_ensure_combat_loadout(N, rarity)
	_restock_ammo()

# ---- representative-drops combat prep --------------------------------------
func _drop_rarity(N: int) -> int:
	return int(min(4, RARITY_BOSS + int(_boss_loss.get(N, 0))))   # RARE -> LEG -> UNIQUE on losses

func _hull_rank(h: String) -> int:
	return int(HULL_RANK.get(h, 0))

func _desired_hull(N: int) -> String:
	var base_rank: int = _hull_rank(String(HULL_FOR_ZONE.get(N, "corvette_hull")))
	var r: int = int(min(HULL_BY_RANK.size() - 1, base_rank + int(_hull_bump.get(N, 0))))
	r = int(min(r, _max_fundable_rank()))      # don't chase a hull we can't research yet
	return String(HULL_BY_RANK[r])

# A hull is fundable if its research is unlocked or is a credit-only tech (shipwright);
# zone-gated hulls (cruiser+ need zone_N_access) only become fundable once that zone
# gate is unlocked — i.e. after the gating zone is cleared.
func _hull_fundable(hid: String) -> bool:
	var rr = GameState.shipyard_manager.hulls.get(hid, {}).get("research_req")
	if rr == null or String(rr) == "":
		return true
	if GameState.research_manager.is_tech_unlocked(String(rr)):
		return true
	return not String(rr).begins_with("zone_")

func _max_fundable_rank() -> int:
	var sm = GameState.shipyard_manager
	var best := 0
	for hid in HULL_RANK:
		if hid in sm.hulls and _hull_fundable(hid):
			best = int(max(best, _hull_rank(hid)))
	return best

func _trash_id(N: int) -> String:
	var cm = GameState.combat_manager
	var zid: String = ZONE_KEY.get(N, "")
	var en: Array = cm.zones.get(zid, {}).get("enemies", [])
	return String(en[0]) if en.size() >= 1 else ""

func _farm_target(N: int) -> int:
	return 20 + N * 5                       # representative trash kills before boss-tier drops

# Grant the shortfall of a tech's NON-CORE materials (boss cores stay real), so
# research never stalls on a deep industrial chain (abstracted as farm/refine).
func _grant_tech_materials(tid: String) -> void:
	var rm = GameState.research_manager
	if not tid in rm.tech_tree:
		return
	var items: Dictionary = rm.tech_tree[tid].get("cost_items", {})
	for sym in items:
		var s := String(sym)
		if s.begins_with("Z") and s.ends_with("_Core"):
			continue
		var need := int(float(items[sym]) * rm.MATERIAL_MULTIPLIER)
		var have := int(GameState.resources.get_element_amount(s))
		if have < need:
			GameState.resources.add_element(s, need - have)

func _grant_tech_chain_materials(tid: String) -> void:
	var rm = GameState.research_manager
	var seen := {}
	var stack := [tid]
	while not stack.is_empty():
		var t = stack.pop_back()
		if t == null or String(t) == "" or seen.has(t) or not String(t) in rm.tech_tree:
			continue
		seen[t] = true
		if not rm.is_tech_unlocked(String(t)):
			_grant_tech_materials(String(t))
		var node: Dictionary = rm.tech_tree[String(t)]
		for key in ["parent", "req_tech"]:
			var p = node.get(key)
			if p:
				stack.append(p)

func _best_researched_hull(N: int) -> String:
	var sm = GameState.shipyard_manager
	var best: String = sm.active_hull
	for hid in HULL_RANK:
		if not hid in sm.hulls:
			continue
		if _hull_rank(hid) > _hull_rank(_desired_hull(N)):
			continue
		var rr = sm.hulls[hid].get("research_req")
		if rr and not GameState.research_manager.is_tech_unlocked(rr):
			continue
		if _hull_rank(hid) > _hull_rank(best):
			best = hid
	return best

func _build_hull(N: int) -> void:
	var sm = GameState.shipyard_manager
	var target := _desired_hull(N)
	var rr = sm.hulls.get(target, {}).get("research_req")
	if rr and not GameState.research_manager.is_tech_unlocked(rr):
		_grant_tech_chain_materials(rr)
		unlock_toward(rr)
	if rr and not GameState.research_manager.is_tech_unlocked(rr):
		target = _best_researched_hull(N)       # fall to best we can actually build
	if target == "" or not target in sm.hulls:
		return
	if _hull_rank(sm.active_hull) >= _hull_rank(target):
		return
	var cost: Dictionary = sm.hulls[target].get("cost", {})
	if GameState.resources.get_currency("credits") < float(cost.get("credits", 0)):
		return                                   # credits are REAL — earn them first
	for sym in cost:
		if String(sym) == "credits":
			continue
		var have: float = GameState.resources.get_element_amount(String(sym))
		if have < float(cost[sym]):
			GameState.resources.add_element(String(sym), int(float(cost[sym]) - have))
	if sm.construct_hull(target):
		_armed_for = -1                          # re-grant into the bigger hull

func _research_chain_credit_cost(tid) -> float:
	var rm = GameState.research_manager
	var total := 0.0
	var seen := {}
	var stack := [tid]
	while not stack.is_empty():
		var t = stack.pop_back()
		if t == null or String(t) == "" or seen.has(t) or not String(t) in rm.tech_tree:
			continue
		seen[t] = true
		if not rm.is_tech_unlocked(String(t)):
			total += float(rm.tech_tree[String(t)].get("cost", 0)) * rm.COST_MULTIPLIER
		var node: Dictionary = rm.tech_tree[String(t)]
		for k in ["parent", "req_tech"]:
			var p = node.get(k)
			if p:
				stack.append(p)
	return total

# Can we afford to research + build the zone's desired hull right now?
func _can_afford_hull(N: int) -> bool:
	var sm = GameState.shipyard_manager
	var target := _desired_hull(N)
	if not target in sm.hulls:
		return true
	var need: float = float(sm.hulls[target].get("cost", {}).get("credits", 0))
	var rr = sm.hulls[target].get("research_req")
	if rr:
		need += _research_chain_credit_cost(rr)
	return GameState.resources.get_currency("credits") >= need

func _drop_weapon_suffix(N: int) -> String:
	var weak := _boss_weak_type(N)
	if not _ammo_supportable(weak):
		weak = "kinetic"
	return TYPE_SUFFIX.get(weak, "kinetic")

# Grant + equip a full representative drop loadout sized to zone N at `rarity`,
# power-gated. Re-runs only when the hull/zone/rarity changed or gear was lost.
func _ensure_combat_loadout(N: int, rarity: int) -> void:
	var sm = GameState.shipyard_manager
	if _armed_for == N and _armed_rarity == rarity and _combat_ready(N):
		return
	var slots: Array = sm.hulls.get(sm.active_hull, {}).get("slots", [])
	for i in range(slots.size()):
		if sm.loadout.get(i, null):
			sm.unequip_slot(i)
	sm.recalc_stats()
	var wsuffix := _drop_weapon_suffix(N)
	for i in range(slots.size()):
		if String(slots[i]) == "battery":
			_equip_drop(i, "battery", N, rarity)
	var smap := {"weapon":wsuffix, "shield":"shield", "armor":"armor", "engine":"engine", "sensor":"sensor"}
	for want in ["weapon", "shield", "armor", "engine", "sensor"]:
		for i in range(slots.size()):
			if String(slots[i]) != want or sm.loadout.get(i, null):
				continue
			_equip_drop(i, String(smap[want]), N, rarity)
			if sm.energy_used > sm.energy_capacity:
				sm.unequip_slot(i)
				sm.recalc_stats()
	sm.recalc_stats()
	_restock_ammo()
	_armed_for = N
	_armed_rarity = rarity

# Roll a rarity-boosted drop of the best base module (tier<=N) for `suffix`, equip it.
func _equip_drop(idx: int, suffix: String, N: int, rarity: int) -> bool:
	var sm = GameState.shipyard_manager
	var base := ""
	for k in range(N, 0, -1):
		var cand := "z%d_%s" % [k, suffix]
		if cand in sm.modules:
			var rr = sm.modules[cand].get("research_req")
			if rr and not GameState.research_manager.is_tech_unlocked(rr):
				GameState.research_manager.unlocked_techs.append(rr)   # representative: module fab researched
			base = cand
			break
	if base == "":
		return false
	var mid: String = sm.generate_module_drop(base, rarity, N)
	if mid == "":
		mid = base
		if int(sm.module_inventory.get(mid, 0)) <= 0:
			sm.craft_module(mid)
	else:
		sm.module_inventory[mid] = int(sm.module_inventory.get(mid, 0)) + 1
	var ok: bool = sm.equip_module(idx, mid, true)
	sm.recalc_stats()
	return ok

func _restock_ammo() -> void:
	var sm = GameState.shipyard_manager
	for i in _slot_indices("weapon"):
		var mid = sm.loadout.get(i, null)
		if not mid:
			continue
		var atype := _weapon_atype(String(mid))
		if atype == "cryo":
			continue
		var ammo: String = AMMO_FOR.get(atype, "")
		if ammo == "":
			continue
		if GameState.resources.get_element_amount(ammo) < 200.0:
			GameState.resources.add_element(ammo, 1000)
		if String(sm.ammo_loadout.get(i, "")) == "":
			sm.set_slot_ammo(i, ammo)

func _ensure_powered(N: int) -> void:
	var sm = GameState.shipyard_manager
	# 1) add batteries into any empty battery slot
	var guard := 0
	while sm.energy_used > sm.energy_capacity and guard < 4:
		guard += 1
		if not _equip_into_empty("battery", "battery", N):
			break
	# 2) still over capacity -> strip optional modules (keep weapon+battery+defense)
	for stype in ["sensor", "engine"]:
		if sm.energy_used <= sm.energy_capacity:
			break
		for i in _slot_indices(stype):
			if sm.loadout.get(i, null):
				sm.unequip_slot(i)
				sm.recalc_stats()

func _ensure_ammo(N: int) -> void:
	var sm = GameState.shipyard_manager
	var pm = GameState.processing_manager
	var res = GameState.resources
	var widx := _slot_indices("weapon")
	for i in widx:
		var mid = sm.loadout.get(i, null)
		if not mid:
			continue
		var atype := _weapon_atype(String(mid))
		if atype == "cryo":
			continue
		var ammo: String = AMMO_FOR.get(atype, "")
		if ammo == "":
			continue
		# stock it if empty: run its recipe (unlock the gate first if needed).
		if res.get_element_amount(ammo) < 1.0:
			var rid: String = AMMO_RECIPE.get(ammo, "")
			if rid in pm.recipes:
				var rr = pm.recipes[rid].get("research_req")
				if rr and not GameState.research_manager.is_tech_unlocked(rr):
					unlock_toward(rr)
				if _recipe_ready(rid):
					pm.start_action(rid)
					pm.process_tick(8.0)   # one batch (recipes complete ~per duration)
		# ASSIGN it (0-ammo weapon fires 0 dmg silently).
		if res.get_element_amount(ammo) > 0:
			sm.set_slot_ammo(i, ammo)

func _combat_ready(N: int) -> bool:
	var sm = GameState.shipyard_manager
	if not is_armed():
		return false
	if sm.energy_used > sm.energy_capacity:
		return false
	for i in _slot_indices("weapon"):
		var mid = sm.loadout.get(i, null)
		if not mid:
			continue
		var atype := _weapon_atype(String(mid))
		if atype == "cryo":
			return true
		var ammo: String = AMMO_FOR.get(atype, "")
		if GameState.resources.get_element_amount(ammo) > 0 and sm.ammo_loadout.get(i, "") != "":
			return true
	return false

# ---- material planner ------------------------------------------------------
func _is_refinable(sym: String) -> bool:
	return _recipe_producing(sym) != ""

func _recipe_producing(sym: String) -> String:
	for rid in GameState.processing_manager.recipes:
		var out = GameState.processing_manager.recipes[rid].get("output", {})
		if sym in out:
			return rid
	return ""

func _gather_for(sym: String) -> String:
	# a gather action whose loot_table yields sym (unlocked); else best_gather.
	for aid in unlocked_gather_actions():
		for entry in GameState.gathering_manager.actions[aid].get("loot_table", []):
			if String(entry[0]) == sym:
				return aid
	return ""

# ---- level / readiness gates ----------------------------------------------
func _proc_level_ok(rid: String) -> bool:
	var pm = GameState.processing_manager
	return pm.get_level() >= int(pm.recipes[rid].get("level_req", 1))

func _inputs_on_hand(rid: String) -> bool:
	var r: Dictionary = GameState.processing_manager.recipes[rid]
	for sym in r.get("input", {}):
		if GameState.resources.get_element_amount(String(sym)) < float(r["input"][sym]):
			return false
	return true

# A recipe runnable RIGHT NOW: processing level met + research unlocked + inputs/credits present.
func _recipe_ready(rid: String) -> bool:
	if not rid in GameState.processing_manager.recipes:
		return false
	if not _proc_level_ok(rid):
		return false
	var rr = GameState.processing_manager.recipes[rid].get("research_req")
	if rr and not GameState.research_manager.is_tech_unlocked(rr):
		return false
	return recipe_runnable(rid)

# Find the single best material action toward obtaining `sym`. Recurses into a
# recipe's missing inputs; if a recipe is blocked only by PROCESSING LEVEL it
# returns a process-grind session so the skill levels up. {} = no path now.
func _acquire(sym: String) -> Dictionary:
	var gid := _gather_for(sym)
	if gid != "":
		return {"kind":"gather", "mgr":GameState.gathering_manager, "id":gid, "length":30.0}
	var rid := _recipe_producing(sym)
	if rid == "":
		return {}
	var r: Dictionary = GameState.processing_manager.recipes[rid]
	var rr = r.get("research_req")
	if rr and not GameState.research_manager.is_tech_unlocked(rr):
		unlock_toward(rr)
	if rr and not GameState.research_manager.is_tech_unlocked(rr):
		return {}                              # research not yet reachable -> dead end for now
	if _recipe_ready(rid):
		return {"kind":"process", "mgr":GameState.processing_manager, "id":rid, "length":30.0}
	# inputs present but processing level too low -> grind processing XP
	if _inputs_on_hand(rid) and not _proc_level_ok(rid):
		return _grind_processing()
	# otherwise gather/refine the scarcest missing input
	for inp in r.get("input", {}):
		if GameState.resources.get_element_amount(String(inp)) < float(r["input"][inp]):
			var sub := _acquire(String(inp))
			if not sub.is_empty():
				return sub
	# inputs satisfied but still not ready and not a credit issue -> grind level
	if not _proc_level_ok(rid):
		return _grind_processing()
	return {}

# Run the highest-XP recipe we can actually run (level+research+inputs) to gain
# processing XP; if none is runnable, gather inputs for the cheapest level-ok one.
func _grind_processing() -> Dictionary:
	var pm = GameState.processing_manager
	var best_run := ""
	var best_run_xp := -1.0
	var base_rid := ""
	var base_lvl := 9999
	for rid in pm.recipes:
		var r: Dictionary = pm.recipes[rid]
		var lreq := int(r.get("level_req", 1))
		if pm.get_level() < lreq:
			continue
		var rr = r.get("research_req")
		if rr and not GameState.research_manager.is_tech_unlocked(rr):
			continue
		if lreq < base_lvl:
			base_lvl = lreq; base_rid = rid
		if recipe_runnable(rid):
			var xp := float(r.get("xp", 1))
			if xp > best_run_xp:
				best_run_xp = xp; best_run = rid
	if best_run != "":
		return {"kind":"process", "mgr":pm, "id":best_run, "length":30.0}
	if base_rid != "":
		for inp in pm.recipes[base_rid].get("input", {}):
			if GameState.resources.get_element_amount(String(inp)) < float(pm.recipes[base_rid]["input"][inp]):
				var sub := _acquire(String(inp))
				if not sub.is_empty():
					return sub
	return _best_income_session()

# Is `sym` obtainable with the bot's CURRENT unlocked actions/recipes (no new
# level needed)? Used to choose a buildable weapon type instead of chasing one
# whose materials sit behind a long grind.
func _reachable_now(sym: String, depth: int) -> bool:
	if depth > 5:
		return false
	if GameState.resources.get_element_amount(sym) > 0.0:
		return true
	if _gather_for(sym) != "":
		return true
	var rid := _recipe_producing(sym)
	if rid == "":
		return false
	if not _proc_level_ok(rid):
		return false
	var r: Dictionary = GameState.processing_manager.recipes[rid]
	var rr = r.get("research_req")
	if rr and not GameState.research_manager.is_tech_unlocked(rr) and not GameState.research_manager.can_unlock(rr):
		return false
	for inp in r.get("input", {}):
		if not _reachable_now(String(inp), depth + 1):
			return false
	return true

# What does crafting the chosen weapon + a battery still need? returns a decision.
func _acquire_gear_inputs(N: int) -> Dictionary:
	var sm = GameState.shipyard_manager
	var atype := _choose_weapon_type(N)
	var wsuffix: String = TYPE_SUFFIX.get(atype, "kinetic")
	for suffix in [wsuffix, "battery", "shield", "armor"]:
		var mid := _best_tier_module(N, suffix)
		if mid == "" or not mid in sm.modules:
			continue
		var cost: Dictionary = sm.get_effective_module_cost(sm.modules[mid])
		for sym in cost:
			if String(sym) == "credits":
				continue
			if GameState.resources.get_element_amount(String(sym)) < float(cost[sym]):
				var d := _acquire(String(sym))
				if not d.is_empty():
					return d
	return {}

# Make/stock ammo for the equipped weapon(s). Grinds processing if the ammo
# recipe is level-locked. {} = nothing to do (ammo already stocked / cryo).
func _acquire_ammo(N: int) -> Dictionary:
	var sm = GameState.shipyard_manager
	for i in _slot_indices("weapon"):
		var mid = sm.loadout.get(i, null)
		if not mid:
			continue
		var atype := _weapon_atype(String(mid))
		if atype == "cryo":
			continue
		var ammo: String = AMMO_FOR.get(atype, "")
		if ammo == "":
			continue
		if GameState.resources.get_element_amount(ammo) < 20.0:
			var d := _acquire(ammo)
			if not d.is_empty():
				return d
	return {}

func _has_module_type(slot_type: String) -> bool:
	for i in _slot_indices(slot_type):
		if GameState.shipyard_manager.loadout.get(i, null):
			return true
	return false

# What's stopping us crafting `mid` right now? "" = craftable, "credits" = only
# credits short, else the first missing material symbol (gather/refine it first).
func _craft_blocker(mid: String, credits: float) -> String:
	var sm = GameState.shipyard_manager
	if mid == "" or not mid in sm.modules:
		return ""
	var cost: Dictionary = sm.get_effective_module_cost(sm.modules[mid])
	var mat_short := ""
	var cr_short := false
	for sym in cost:
		if String(sym) == "credits":
			if credits < float(cost[sym]):
				cr_short = true
		elif GameState.resources.get_element_amount(String(sym)) < float(cost[sym]):
			if mat_short == "":
				mat_short = String(sym)
	if mat_short != "":
		return mat_short
	if cr_short:
		return "credits"
	return ""

func _best_income_session() -> Dictionary:
	# fund credits: gather the highest-value unlocked action.
	var bg := best_gather()
	return {"kind":"gather", "mgr":GameState.gathering_manager, "id":String(bg[0]), "length":45.0}

# ---------------------------------------------------------------------------
func manage_meta() -> void:
	var rm = GameState.research_manager
	var N := _next_uncleared_zone()
	if N > 10:
		return
	if N >= 2 and not rm.is_tech_unlocked(_gate_tech(N)):
		_grant_tech_chain_materials(_gate_tech(N))
		unlock_toward(_gate_tech(N))
	unlock_toward("combustion")        # opens explosive ammo
	_build_hull(N)                     # upgrade to the zone's hull (credits real, mats granted)
	_arm_for_zone(N)                   # grant + equip the representative drop loadout
	_ensure_powered(N)
	# only spend on infra/storage once the hull goal is met — else it starves hull funding
	if _hull_rank(GameState.shipyard_manager.active_hull) >= _hull_rank(_desired_hull(N)):
		buy_buildings(1)
		maybe_upgrade_storage()
	var sm = GameState.shipyard_manager
	if not GameState.combat_manager.in_combat and sm.current_hp < sm.max_hp * 0.5 \
			and _combat_ready(N) and GameState.resources.get_currency("credits") > 1500.0:
		sm.repair_hull()

func decide_session() -> Dictionary:
	var rm = GameState.research_manager
	var sm = GameState.shipyard_manager
	var N := _next_uncleared_zone()
	if N > 10:
		last_gate_reason = "none"
		return {"kind":"noop", "gap":600.0}

	# 0) the zone needs a bigger hull -> earn credits toward it (gather+sell, which
	#    also levels gathering so income ramps). manage_meta builds it when affordable.
	if _hull_rank(sm.active_hull) < _hull_rank(_desired_hull(N)) and not _can_afford_hull(N):
		sell_surplus(_protected())
		last_gate_reason = "hull:earn(%s->%s cr=%d)" % [
			sm.active_hull, _desired_hull(N), int(GameState.resources.get_currency("credits"))]
		return _best_income_session()

	# A) research gate for zone N (materials granted in manage_meta; cores are real)
	if N >= 2 and not rm.is_tech_unlocked(_gate_tech(N)):
		var short := _gate_shortfall(N)
		var core_key := "Z%d_Core" % (N - 1)
		if short.has(core_key):
			# farm the previous boss for its cores (current drop loadout handles it)
			var pid := _boss_id(N - 1)
			var need_total := int(float(rm.tech_tree[_gate_tech(N)]["cost_items"][core_key]) * rm.MATERIAL_MULTIPLIER)
			last_gate_reason = "gate:%s x%d" % [core_key, need_total]
			return {"kind":"combat", "mgr":GameState.combat_manager, "zone":ZONE_KEY[N - 1],
				"enemy":pid, "length":120.0, "farm_to":need_total}
		# gate/research needs credits (the tech cost itself) -> earn by selling surplus
		sell_surplus(_protected())
		last_gate_reason = "gate:credits"
		return _best_income_session()

	# B) combat prep: farm trash for representative drops, then face the boss
	if not drops_granted.get(N, false):
		if int(farm_kills.get(N, 0)) >= _farm_target(N):
			drops_granted[N] = true
			_armed_for = -1                # re-arm to boss-tier drops next manage_meta
		else:
			sell_surplus(_protected())     # convert farm/gather loot to credits (free)
			last_gate_reason = "farm:trash %d/%d" % [int(farm_kills.get(N, 0)), _farm_target(N)]
			return {"kind":"trash", "mgr":GameState.combat_manager, "zone":ZONE_KEY[N],
				"enemy":_trash_id(N), "length":120.0}

	# C) boss-ready -> clear zone N
	if _combat_ready(N):
		last_gate_reason = "none"
		return {"kind":"combat", "mgr":GameState.combat_manager, "zone":ZONE_KEY[N],
			"enemy":_boss_id(N), "length":60.0, "farm_to":1}
	sell_surplus(_protected())
	last_gate_reason = "boss:not-ready"
	return _best_income_session()

func _protected() -> Dictionary:
	# never sell boss cores, ammo, granted industrial materials, or gate materials.
	var p := {}
	for n in range(1, 11):
		p["Z%d_Core" % n] = 9999.0
	for a in AMMO_FOR.values():
		p[String(a)] = 9.0e9
	for g in GRANTABLE:
		p[g] = 9.0e9
	var N := _next_uncleared_zone()
	if N > 10:
		return p
	if N >= 2:
		for sym in _gate_shortfall(N):
			if String(sym) != "credits":
				p[String(sym)] = 9.0e9
	return p

func want_warp() -> bool:
	return _should_warp()

func _should_warp() -> bool:
	var wm = GameState.warp_manager
	if wm.total_warps >= target_warps:
		return false
	if wm.calculate_warp_gains() < 1:
		return false
	# guard the prestige trap: only warp once we've actually cleared a zone this climb.
	return cleared.size() >= 1

# Stall taxonomy for the watchdog (representative-drops model).
func classify_stall(N: int) -> String:
	var rm = GameState.research_manager
	var sm = GameState.shipyard_manager
	var hull: String = sm.active_hull
	if N >= 2 and not rm.is_tech_unlocked(_gate_tech(N)):
		var short := _gate_shortfall(N)
		if short.has("Z%d_Core" % (N - 1)):
			return "gate:core_farm(prev boss z%d unbeatable on %s, drops r%d)" % [N - 1, hull, _drop_rarity(N)]
		if short.get("credits", 0) > 0:
			return "gate:credits(x%d — income too slow)" % int(short.get("credits", 0))
		return "gate:research(%s blocked)" % _gate_tech(N)
	if not drops_granted.get(N, false):
		return "farm:trash(z%d %s unbeatable on %s, %d/%d kills)" % [
			N, _trash_id(N), hull, int(farm_kills.get(N, 0)), _farm_target(N)]
	if sm.energy_used > sm.energy_capacity:
		return "power_wall(used %d>cap %d on %s)" % [sm.energy_used, sm.energy_capacity, hull]
	return "dps_wall(boss %s unbeatable on %s w/ rarity-%d drops)" % [_boss_id(N), hull, _drop_rarity(N)]
