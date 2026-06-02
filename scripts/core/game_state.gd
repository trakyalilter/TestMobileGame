extends Node
## Core game engine. Autoloaded as `GameState`.
## Single-active-task model with offline progress. Content from GameData (ported
## from horizonidle-godot): gather/craft/combat + a credit-funded research tree.

signal resources_changed
signal skills_changed
signal research_changed
signal action_changed

var resources: Dictionary = {}          # symbol -> int
var credits: int = 0                    # research currency (earned by selling)
var skills: Dictionary = {
	"harvesting": 0,
	"fabrication": 0,
	"combat": 0,
	"infrastructure": 0,
}
var unlocked_research: Dictionary = {}  # research_id -> true

# Single foreground task
var active_type: String = ""            # "gather" | "craft" | "combat" | ""
var active_id: String = ""
var progress: float = 0.0

# Combat
var combat_hp: float = 0.0
const HP_REGEN := 0.04

# Shipyard
var active_hull: String = ""
var owned_hulls: Dictionary = {}        # hull_id -> true
var module_inventory: Dictionary = {}   # module_id -> count (unequipped)
var loadout: Dictionary = {}            # slot_index (as String) -> module_id

# Infrastructure (passive production buildings — runs in the background always)
var buildings: Dictionary = {}          # id -> count
var building_throttle: Dictionary = {}  # id -> 0..1
var _build_timers: Dictionary = {}      # id -> accumulated time
var _build_frac: Dictionary = {}        # sym -> fractional carry
var _infra_dirty := false
var _infra_emit_accum := 0.0

var pending_offline: String = ""

const SAVE_PATH := "user://stellarforge_save.json"
const AUTOSAVE_INTERVAL := 15.0
var _save_accum := 0.0

func _ready() -> void:
	load_game()
	if active_hull == "":
		active_hull = "corvette_hull"
		owned_hulls["corvette_hull"] = true
	if combat_hp <= 0.0:
		combat_hp = combat_max_hp()
	if bounty_available.is_empty() and bounty_active.is_empty():
		generate_bounty_pool()

func _process(delta: float) -> void:
	_tick_active(delta)
	_tick_infra(delta)
	var mx := combat_max_hp()
	if combat_hp < mx:
		combat_hp = minf(mx, combat_hp + mx * HP_REGEN * delta)
	# Throttle resource-change signals from passive production to ~2/sec.
	_infra_emit_accum += delta
	if _infra_dirty and _infra_emit_accum >= 0.5:
		_infra_emit_accum = 0.0
		_infra_dirty = false
		resources_changed.emit()
	if bounty_refresh_timer > 0.0:
		bounty_refresh_timer -= delta
		if bounty_refresh_timer <= 0.0:
			generate_bounty_pool()
	_save_accum += delta
	if _save_accum >= AUTOSAVE_INTERVAL:
		_save_accum = 0.0
		save_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		save_game()

# ---------------- Resources / credits ----------------
func amount(sym: String) -> int:
	return int(resources.get(sym, 0))

func add_resource(sym: String, amt: int) -> void:
	resources[sym] = amount(sym) + amt
	resources_changed.emit()

func can_afford(cost: Dictionary) -> bool:
	for sym in cost:
		if amount(sym) < int(cost[sym]):
			return false
	return true

func spend(cost: Dictionary, times: int = 1) -> void:
	for sym in cost:
		resources[sym] = amount(sym) - int(cost[sym]) * times
	resources_changed.emit()

func sell_all(sym: String) -> void:
	var qty := amount(sym)
	if qty <= 0:
		return
	credits += qty * maxi(1, GameData.value_of(sym))
	resources[sym] = 0
	resources_changed.emit()

# ---------------- Skills ----------------
func xp_for_level(lvl: int) -> int:
	if lvl <= 1:
		return 0
	return int(40.0 * pow(lvl - 1, 1.6))

func level_of(skill_id: String) -> int:
	var xp := int(skills.get(skill_id, 0))
	var lvl := 1
	while xp >= xp_for_level(lvl + 1):
		lvl += 1
	return lvl

func add_xp(skill_id: String, amt: int) -> void:
	skills[skill_id] = int(skills.get(skill_id, 0)) + amt
	skills_changed.emit()

func yield_mult(skill_id: String) -> float:
	return 1.0 + level_of(skill_id) * 0.02

# ---------------- Combat stats ----------------
## Derived ship stats from the active hull + equipped modules.
## Returns {} when no ship is equipped.
func ship_stats() -> Dictionary:
	if active_hull == "" or not GameData.HULLS.has(active_hull):
		return {}
	var h: Dictionary = GameData.HULLS[active_hull]
	var s := {"atk": 0.0, "hp": float(h.get("hp", 100)), "def": 0.0, "shield": 0.0,
		"energy_cap": float(h.get("energy_capacity", 0)), "energy_load": 0.0}
	var dps := 0.0
	var spd_bonus := 0.0
	var spd_mult := 1.0
	for k in loadout:
		var m: Dictionary = GameData.MODULES.get(loadout[k], {})
		var st: Dictionary = m.get("stats", {})
		s.hp += float(st.get("hp", 0))
		s.def += float(st.get("def", 0))
		s.shield += float(st.get("max_shield", 0))
		s.energy_cap += float(st.get("energy_capacity", 0))
		s.energy_load += float(st.get("energy_load", 0))
		spd_bonus += float(st.get("atk_speed_bonus", 0))
		if st.has("atk_speed_mult"):
			spd_mult *= float(st["atk_speed_mult"])
		var dmg := float(st.get("atk_energy", 0)) + float(st.get("atk_kinetic", 0)) + float(st.get("atk_explosive", 0))
		if dmg > 0.0:
			dps += dmg / maxf(0.1, float(st.get("atk_interval", 1.0)))
	dps = dps * (1.0 + spd_bonus) * spd_mult + float(h.get("atk", 0))
	# Energy brownout: weapons underperform if load exceeds capacity.
	if s.energy_load > s.energy_cap and s.energy_cap > 0.0:
		dps *= s.energy_cap / s.energy_load
	s.atk = dps
	return s

func combat_max_hp() -> float:
	var s := ship_stats()
	if s.is_empty():
		return 100.0
	return s["hp"] + s["shield"] + level_of("combat") * 20.0

func combat_attack() -> float:
	var s := ship_stats()
	if s.is_empty():
		return 5.0
	return maxf(1.0, s["atk"] + level_of("combat") * 2.0)

func combat_defense() -> float:
	var s := ship_stats()
	return s.get("def", 0.0) if not s.is_empty() else 0.0

# ---------------- Shipyard ----------------
func _afford_cost(cost: Dictionary) -> bool:
	for sym in cost:
		if sym == "credits":
			if credits < int(cost[sym]):
				return false
		elif amount(sym) < int(cost[sym]):
			return false
	return true

func _pay_cost(cost: Dictionary) -> void:
	for sym in cost:
		if sym == "credits":
			credits -= int(cost[sym])
		else:
			resources[sym] = amount(sym) - int(cost[sym])

func hull_owned(hid: String) -> bool:
	return owned_hulls.has(hid)

func hull_unlocked(hid: String) -> bool:
	var rr: String = GameData.HULLS.get(hid, {}).get("research_req", "")
	return rr == "" or is_research_unlocked(rr)

func hull_can_get(hid: String) -> bool:
	if not hull_unlocked(hid):
		return false
	if hull_owned(hid):
		return true
	return _afford_cost(GameData.HULLS.get(hid, {}).get("cost", {}))

func select_hull(hid: String) -> bool:
	if not GameData.HULLS.has(hid) or not hull_unlocked(hid):
		return false
	if not hull_owned(hid):
		if not _afford_cost(GameData.HULLS[hid].get("cost", {})):
			return false
		_pay_cost(GameData.HULLS[hid].get("cost", {}))
		owned_hulls[hid] = true
	# Switching ships returns all equipped modules to inventory (slots differ).
	for k in loadout:
		module_inventory[loadout[k]] = int(module_inventory.get(loadout[k], 0)) + 1
	loadout = {}
	active_hull = hid
	resources_changed.emit()
	return true

func module_unlocked(mid: String) -> bool:
	var rr: String = GameData.MODULES.get(mid, {}).get("research_req", "")
	return rr == "" or is_research_unlocked(rr)

func module_can_buy(mid: String) -> bool:
	return module_unlocked(mid) and _afford_cost(GameData.MODULES.get(mid, {}).get("cost", {}))

func buy_module(mid: String) -> bool:
	if not module_can_buy(mid):
		return false
	_pay_cost(GameData.MODULES[mid].get("cost", {}))
	module_inventory[mid] = int(module_inventory.get(mid, 0)) + 1
	resources_changed.emit()
	return true

func equip_module(mid: String) -> bool:
	if int(module_inventory.get(mid, 0)) <= 0:
		return false
	var st: String = GameData.MODULES.get(mid, {}).get("slot", "")
	var slots: Array = GameData.HULLS.get(active_hull, {}).get("slots", [])
	for i in slots.size():
		if slots[i] == st and not loadout.has(str(i)):
			loadout[str(i)] = mid
			module_inventory[mid] = int(module_inventory[mid]) - 1
			resources_changed.emit()
			return true
	return false

func unequip_slot(idx: String) -> void:
	if loadout.has(idx):
		module_inventory[loadout[idx]] = int(module_inventory.get(loadout[idx], 0)) + 1
		loadout.erase(idx)
		resources_changed.emit()

# ---------------- Bounty board ----------------
signal bounty_changed

const BOUNTY_MAX_ACTIVE := 3
const BOUNTY_MAX_AVAIL := 6
const BOUNTY_REFRESH := 28800.0   # 8 hours
const DELIVERY_MATERIALS := {
	1: [["Cu", 500, 1000, 25000], ["Fe", 300, 600, 40000], ["Si", 200, 400, 30000]],
	2: [["Fe", 800, 1500, 100000], ["Cu", 300, 600, 75000], ["Steel", 100, 250, 150000]],
	3: [["Steel", 250, 500, 250000], ["Ti", 100, 250, 400000], ["Circuit", 100, 200, 300000]],
	4: [["Ti", 300, 600, 600000], ["W", 150, 300, 500000], ["Graphite", 200, 400, 400000]],
	5: [["AdvCircuit", 100, 200, 1250000], ["Superalloy", 50, 150, 1500000], ["NavData", 100, 250, 1000000]],
	6: [["ColonySalvage", 250, 500, 2000000], ["AdvCircuit", 150, 300, 1750000], ["Steel", 2000, 5000, 2500000]],
	7: [["RadIsotope", 200, 500, 3000000], ["Pt", 100, 250, 3750000], ["Superalloy", 150, 300, 2750000]],
	8: [["VoidCrystal", 50, 150, 5000000], ["Diamond", 30, 80, 4000000], ["ExoticMatter", 20, 50, 6000000]],
	9: [["BiohazardSample", 100, 250, 7500000], ["MutatedTissue", 50, 150, 9000000], ["PathogenCore", 20, 50, 10000000]],
	10: [["VoidEssence", 50, 100, 25000000], ["ChronoCore", 20, 50, 37500000], ["PrimordialShard", 10, 30, 50000000]],
}

var bounty_available: Array = []
var bounty_active: Array = []
var bounty_refresh_timer: float = 0.0
var bounty_total: int = 0
var _bounty_id := 0

func _gen_bid() -> String:
	_bounty_id += 1
	return "b%d" % _bounty_id

func bounty_max_diff() -> int:
	return clampi(1 + int(level_of("combat") / 4.0), 1, 10)

func _zones_in_range(mind: int, maxd: int) -> Array:
	var out := []
	for z in GameData.ZONES:
		var diff := int(z.get("difficulty", 1))
		if diff >= mind and diff <= maxd:
			out.append(z)
	return out

func generate_bounty_pool() -> void:
	bounty_available.clear()
	var maxd := bounty_max_diff()
	var mind := maxi(1, maxd - 1)
	var attempts := 0
	while bounty_available.size() < BOUNTY_MAX_AVAIL and attempts < 100:
		attempts += 1
		var c := {}
		var roll := randf()
		if roll < 0.4:
			c = _gen_hunt(mind, maxd, false)
		elif roll < 0.7:
			c = _gen_delivery(mind, maxd)
		else:
			c = _gen_hunt(maxd, maxd, true)
		if not c.is_empty():
			var dup := false
			for e in bounty_available:
				if e["target"] == c["target"] and e["type"] == c["type"] and e.get("is_elite", false) == c.get("is_elite", false):
					dup = true
					break
			if not dup:
				bounty_available.append(c)
	bounty_refresh_timer = BOUNTY_REFRESH
	bounty_changed.emit()

func _gen_hunt(mind: int, maxd: int, elite: bool) -> Dictionary:
	var zs := _zones_in_range(mind, maxd)
	if zs.is_empty():
		return {}
	var z: Dictionary = zs[randi() % zs.size()]
	var ens: Array = z.get("enemies", [])
	if ens.is_empty():
		return {}
	var eid: String = ens[randi() % ens.size()]
	var e: Dictionary = GameData.ENEMIES.get(eid, {})
	if e.is_empty():
		return {}
	var diff := int(z.get("difficulty", 1))
	var base_xp := float(e.get("xp", 10))
	var qty := 1 if elite else randi_range(5, 20)
	var reward := int(base_xp * 300.0 * pow(diff, 1.5)) if elite else int(base_xp * qty * 5.0 * pow(diff, 1.8))
	var title := ("★ ELITE: %s" % e["name"]) if elite else ("Hunt: %s" % e["name"])
	var desc := "Destroy %s%d %s in %s." % ["the ELITE " if elite else "", qty, e["name"], z.get("name", "")]
	return {"id": _gen_bid(), "type": "hunt", "title": title, "desc": desc,
		"target": eid, "target_qty": qty, "current_qty": 0, "reward_credits": reward,
		"zone_id": z.get("id", ""), "difficulty": diff, "completed": false, "is_elite": elite}

func _gen_delivery(mind: int, maxd: int) -> Dictionary:
	var tier := randi_range(mind, maxd)
	var tmpl: Array = DELIVERY_MATERIALS.get(tier, [])
	if tmpl.is_empty():
		return {}
	var t: Array = tmpl[randi() % tmpl.size()]
	var qty := randi_range(int(t[1]), int(t[2]))
	return {"id": _gen_bid(), "type": "delivery", "title": "Supply: %s" % GameData.res_name(t[0]),
		"desc": "Deliver %d %s to the station." % [qty, GameData.res_name(t[0])],
		"target": t[0], "target_qty": qty, "current_qty": 0, "reward_credits": int(t[3]),
		"zone_id": "", "difficulty": tier, "completed": false, "is_elite": false}

func _find_contract(arr: Array, cid: String) -> Variant:
	for c in arr:
		if c["id"] == cid:
			return c
	return null

func accept_contract(cid: String) -> bool:
	if bounty_active.size() >= BOUNTY_MAX_ACTIVE:
		return false
	var c = _find_contract(bounty_available, cid)
	if c == null:
		return false
	if c["type"] == "delivery":
		if amount(c["target"]) < int(c["target_qty"]):
			return false
		resources[c["target"]] = amount(c["target"]) - int(c["target_qty"])
		c["current_qty"] = int(c["target_qty"])
		c["completed"] = true
	bounty_available.erase(c)
	bounty_active.append(c)
	resources_changed.emit()
	bounty_changed.emit()
	return true

func claim_contract(cid: String) -> bool:
	var c = _find_contract(bounty_active, cid)
	if c == null or not c["completed"]:
		return false
	credits += int(c["reward_credits"])
	bounty_active.erase(c)
	bounty_total += 1
	resources_changed.emit()
	bounty_changed.emit()
	return true

func abandon_contract(cid: String) -> bool:
	var c = _find_contract(bounty_active, cid)
	if c == null:
		return false
	if c["type"] == "delivery" and int(c["current_qty"]) > 0:
		resources[c["target"]] = amount(c["target"]) + int(c["current_qty"])
	bounty_active.erase(c)
	resources_changed.emit()
	bounty_changed.emit()
	return true

func bounty_refresh_cost() -> int:
	return bounty_max_diff() * 5000

func force_refresh_bounty() -> bool:
	var cost := bounty_refresh_cost()
	if credits < cost:
		return false
	credits -= cost
	generate_bounty_pool()
	resources_changed.emit()
	return true

func bounty_on_kill(eid: String) -> void:
	var changed := false
	for c in bounty_active:
		if c["type"] == "hunt" and c["target"] == eid and not c["completed"]:
			c["current_qty"] = mini(int(c["current_qty"]) + 1, int(c["target_qty"]))
			if int(c["current_qty"]) >= int(c["target_qty"]):
				c["completed"] = true
			changed = true
	if changed:
		bounty_changed.emit()

# ---------------- Infrastructure ----------------
func building_count(bid: String) -> int:
	return int(buildings.get(bid, 0))

func get_throttle(bid: String) -> float:
	return float(building_throttle.get(bid, 1.0))

func set_throttle(bid: String, v: float) -> void:
	building_throttle[bid] = clampf(v, 0.0, 1.0)
	resources_changed.emit()

## Returns {"gen": kW, "cons": kW, "eff": 0..1}. Deficit throttles all production.
func infra_power() -> Dictionary:
	var gen := 0.0
	var cons := 0.0
	for bid in buildings:
		var d: Dictionary = GameData.BUILDINGS.get(bid, {})
		var t := get_throttle(bid)
		gen += float(d.get("energy_gen", 0.0)) * buildings[bid] * t
		cons += float(d.get("energy_cons", 0.0)) * buildings[bid] * t
	var eff := 1.0 if cons <= gen or cons <= 0.0 else gen / cons
	return {"gen": gen, "cons": cons, "eff": eff}

func _global_yield_bonus() -> Dictionary:
	var gyb := {}
	for bid in buildings:
		var yb: Dictionary = GameData.BUILDINGS.get(bid, {}).get("yield_bonus", {})
		for res in yb:
			gyb[res] = gyb.get(res, 0.0) + float(yb[res]) * buildings[bid]
	return gyb

func _tick_infra(delta: float) -> void:
	if buildings.is_empty():
		return
	var eff: float = infra_power()["eff"]
	var skill_speed := 1.0 + level_of("infrastructure") * 0.01
	var gyb := _global_yield_bonus()
	for bid in buildings:
		var count: int = buildings[bid]
		if count <= 0:
			continue
		var d: Dictionary = GameData.BUILDINGS.get(bid, {})
		if d.get("yield", {}).is_empty() and d.get("input", {}).is_empty():
			continue
		var eff_interval: float = maxf(0.05, float(d.get("interval", 1.0)) / skill_speed)
		var t := get_throttle(bid)
		_build_timers[bid] = float(_build_timers.get(bid, 0.0)) + delta * eff * t
		var guard := 0
		while float(_build_timers[bid]) >= eff_interval and guard < 200:
			guard += 1
			_build_timers[bid] = float(_build_timers[bid]) - eff_interval
			_produce_batch(bid, count, d, gyb)

func _produce_batch(bid: String, count: int, d: Dictionary, gyb: Dictionary) -> void:
	var inp: Dictionary = d.get("input", {})
	for res in inp:
		if amount(res) < int(inp[res]) * count:
			return  # not enough fuel/feedstock this cycle
	for res in inp:
		resources[res] = amount(res) - int(inp[res]) * count
		_infra_dirty = true
	var eng_scaled := ["auto_smelter", "hydro_plant", "industrial_centrifuge", "munitions_factory"]
	for res in d.get("yield", {}):
		var qty := float(d["yield"][res]) * count * (1.0 + float(gyb.get(res, 0.0)))
		if bid in eng_scaled:
			qty *= 1.0 + (log(1.0 + level_of("fabrication")) / log(10.0)) * 5.0
		_build_frac[res] = float(_build_frac.get(res, 0.0)) + qty
		var whole := int(_build_frac[res])
		if whole > 0:
			_build_frac[res] = float(_build_frac[res]) - whole
			if res == "credits":
				credits += whole
			else:
				resources[res] = amount(res) + whole
			_infra_dirty = true
	add_xp("infrastructure", 1)

func _credit_mult(c: int) -> float:
	if c < 10: return pow(1.15, c)
	if c < 25: return pow(1.15, 10) * pow(1.24, c - 10)
	return pow(1.15, 10) * pow(1.24, 15) * pow(1.32, c - 25)

func _item_mult(c: int) -> float:
	if c < 10: return pow(1.15, c)
	if c < 25: return pow(1.15, 10) * pow(1.20, c - 10)
	return pow(1.15, 10) * pow(1.20, 15) * pow(1.26, c - 25)

func building_cost(bid: String) -> Dictionary:
	var d: Dictionary = GameData.BUILDINGS.get(bid, {})
	var c := building_count(bid)
	var out := {}
	for res in d.get("cost", {}):
		var base := float(d["cost"][res])
		var m: float = _credit_mult(c) if res == "credits" else _item_mult(c)
		out[res] = int(ceil(base * m))
	return out

func building_unlocked(bid: String) -> bool:
	var rr: String = GameData.BUILDINGS.get(bid, {}).get("research_req", "")
	return rr == "" or is_research_unlocked(rr)

func building_can_afford(bid: String) -> bool:
	var d: Dictionary = GameData.BUILDINGS.get(bid, {})
	if not building_unlocked(bid):
		return false
	if d.has("max") and building_count(bid) >= int(d["max"]):
		return false
	var cost := building_cost(bid)
	for res in cost:
		if res == "credits":
			if credits < int(cost[res]):
				return false
		elif amount(res) < int(cost[res]):
			return false
	return true

func build_building(bid: String) -> bool:
	if not building_can_afford(bid):
		return false
	var cost := building_cost(bid)
	for res in cost:
		if res == "credits":
			credits -= int(cost[res])
		else:
			resources[res] = amount(res) - int(cost[res])
	buildings[bid] = building_count(bid) + 1
	resources_changed.emit()
	return true

# ---------------- Research ----------------
func is_research_unlocked(rid: String) -> bool:
	return unlocked_research.has(rid)

func research_available(rid: String) -> bool:
	if is_research_unlocked(rid):
		return false
	var t: Dictionary = GameData.RESEARCH.get(rid, {})
	var parent: String = t.get("parent", "")
	if parent != "" and not is_research_unlocked(parent):
		return false
	return credits >= int(t.get("credits", 0)) and can_afford(t.get("items", {}))

func unlock_research(rid: String) -> bool:
	if not research_available(rid):
		return false
	var t: Dictionary = GameData.RESEARCH[rid]
	credits -= int(t.get("credits", 0))
	spend(t.get("items", {}))
	unlocked_research[rid] = true
	research_changed.emit()
	return true

# ---------------- Requirements ----------------
func meets_requirements(def: Dictionary, skill_id: String) -> bool:
	if level_of(skill_id) < int(def.get("level_req", 1)):
		return false
	var rr: String = def.get("research_req", "")
	if rr != "" and not is_research_unlocked(rr):
		return false
	return true

# ---------------- Active task ----------------
func start_task(type: String, id: String) -> void:
	if active_type == type and active_id == id:
		stop_task()
		return
	active_type = type
	active_id = id
	progress = 0.0
	action_changed.emit()

func stop_task() -> void:
	active_type = ""
	active_id = ""
	progress = 0.0
	action_changed.emit()

func current_duration() -> float:
	return effective_duration(active_type, active_id)

func effective_duration(type: String, id: String) -> float:
	if type == "gather" and GameData.GATHER.has(id):
		return float(GameData.GATHER[id].get("duration", 4.0))
	elif type == "craft" and GameData.CRAFT.has(id):
		return float(GameData.CRAFT[id].get("duration", 4.0))
	elif type == "combat" and GameData.ENEMIES.has(id):
		var e: Dictionary = GameData.ENEMIES[id]
		var dps := maxf(1.0, combat_attack() - float(e.get("def", 0)))
		return maxf(0.5, float(e["hp"]) / dps)
	return 0.0

func _tick_active(delta: float) -> void:
	if active_type == "":
		return
	if active_type == "craft" and not can_afford(GameData.CRAFT[active_id].get("inputs", {})):
		stop_task()
		return
	progress += delta
	var dur := current_duration()
	if dur <= 0.0:
		return
	while progress >= dur:
		progress -= dur
		_complete_active()
		if active_type == "":
			break

## Rolls a loot table [[sym, chance, min, max], ...], applying a yield multiplier.
func _roll_loot(loot: Array, mult: float) -> void:
	for row in loot:
		if randf() < float(row[1]):
			var amt := maxi(1, int(round(randi_range(int(row[2]), int(row[3])) * mult)))
			if row[0] == "credits":
				credits += amt
				resources_changed.emit()
			else:
				add_resource(row[0], amt)

func _complete_active() -> void:
	if active_type == "gather":
		var a: Dictionary = GameData.GATHER[active_id]
		_roll_loot(a.get("loot", []), yield_mult("harvesting"))
		add_xp("harvesting", int(a.get("xp", 0)))
	elif active_type == "craft":
		var r: Dictionary = GameData.CRAFT[active_id]
		if not can_afford(r.get("inputs", {})):
			stop_task()
			return
		spend(r.get("inputs", {}))
		for sym in r.get("outputs", {}):
			add_resource(sym, int(r["outputs"][sym]))
		_roll_loot(r.get("bonus", []), 1.0)
		add_xp("fabrication", int(r.get("xp", 0)))
	elif active_type == "combat":
		var e: Dictionary = GameData.ENEMIES[active_id]
		_roll_loot(e.get("loot", []), 1.0)
		add_xp("combat", int(e.get("xp", 0)))
		bounty_on_kill(active_id)
		var dps: float = float(e.get("atk", 0)) / maxf(0.5, float(e.get("interval", 2.0)))
		dps *= 100.0 / (100.0 + combat_defense())   # armor mitigation
		combat_hp -= dps * current_duration()
		if combat_hp <= 0.0:
			combat_hp = combat_max_hp() * 0.25
			stop_task()

# ---------------- Offline ----------------
func _apply_offline(delta: float) -> void:
	if active_type == "" or delta < 5.0:
		return
	var dur := current_duration()
	if dur <= 0.0:
		return
	var reps := int(delta / dur)
	if reps <= 0:
		return

	if active_type == "gather":
		var a: Dictionary = GameData.GATHER[active_id]
		var summary := _offline_loot(a.get("loot", []), yield_mult("harvesting"), reps)
		add_xp("harvesting", int(a.get("xp", 0)) * reps)
		pending_offline = "Away for %s\n\n%s\n+%d Harvesting XP" % [_fmt_time(delta), summary, int(a.get("xp", 0)) * reps]
	elif active_type == "craft":
		var r: Dictionary = GameData.CRAFT[active_id]
		var by_inputs := 0x7FFFFFFF
		for sym in r.get("inputs", {}):
			by_inputs = mini(by_inputs, int(amount(sym) / int(r["inputs"][sym])))
		var count := mini(reps, by_inputs)
		if count <= 0:
			return
		spend(r.get("inputs", {}), count)
		var summary := ""
		for sym in r.get("outputs", {}):
			var made := int(r["outputs"][sym]) * count
			add_resource(sym, made)
			summary += "\n+%s %s" % [GameData.fmt(made), GameData.res_name(sym)]
		add_xp("fabrication", int(r.get("xp", 0)) * count)
		pending_offline = "Away for %s\n%s\n+%d Fabrication XP" % [_fmt_time(delta), summary, int(r.get("xp", 0)) * count]
	elif active_type == "combat":
		var e: Dictionary = GameData.ENEMIES[active_id]
		var dps: float = float(e.get("atk", 0)) / maxf(0.5, float(e.get("interval", 2.0)))
		dps *= 100.0 / (100.0 + combat_defense())
		if combat_max_hp() * HP_REGEN - dps < 0.0:
			return  # not sustainable; no offline farming
		var summary := _offline_loot(e.get("loot", []), 1.0, reps)
		add_xp("combat", int(e.get("xp", 0)) * reps)
		combat_hp = combat_max_hp()
		pending_offline = "Away for %s\n\nDestroyed %d %s\n%s\n+%d Combat XP" % [_fmt_time(delta), reps, e["name"], summary, int(e.get("xp", 0)) * reps]

func _offline_loot(loot: Array, mult: float, reps: int) -> String:
	var s := ""
	for row in loot:
		var avg: float = (int(row[2]) + int(row[3])) / 2.0 * float(row[1])
		var got := int(round(avg * mult * reps))
		if got > 0:
			if row[0] == "credits":
				credits += got
				s += "+₡%s  " % GameData.fmt(got)
			else:
				add_resource(row[0], got)
				s += "+%s %s  " % [GameData.fmt(got), GameData.res_name(row[0])]
	return s

## Buildings keep producing while away (bounded by available inputs).
func _offline_infra(delta: float) -> void:
	if buildings.is_empty() or delta < 5.0:
		return
	var eff: float = infra_power()["eff"]
	var skill_speed := 1.0 + level_of("infrastructure") * 0.01
	var gyb := _global_yield_bonus()
	var eng_scaled := ["auto_smelter", "hydro_plant", "industrial_centrifuge", "munitions_factory"]
	for bid in buildings:
		var count: int = buildings[bid]
		if count <= 0:
			continue
		var d: Dictionary = GameData.BUILDINGS.get(bid, {})
		if d.get("yield", {}).is_empty() and d.get("input", {}).is_empty():
			continue
		var eff_interval: float = maxf(0.05, float(d.get("interval", 1.0)) / skill_speed)
		var t := get_throttle(bid)
		var cycles := int(delta * eff * t / eff_interval)
		if cycles <= 0:
			continue
		var inp: Dictionary = d.get("input", {})
		for res in inp:
			cycles = mini(cycles, int(amount(res) / maxi(1, int(inp[res]) * count)))
		if cycles <= 0:
			continue
		for res in inp:
			resources[res] = amount(res) - int(inp[res]) * count * cycles
		for res in d.get("yield", {}):
			var qty := float(d["yield"][res]) * count * (1.0 + float(gyb.get(res, 0.0)))
			if bid in eng_scaled:
				qty *= 1.0 + (log(1.0 + level_of("fabrication")) / log(10.0)) * 5.0
			var total := int(qty * cycles)
			if total > 0:
				if res == "credits":
					credits += total
				else:
					resources[res] = amount(res) + total
		add_xp("infrastructure", cycles)

func _fmt_time(secs: float) -> String:
	var s := int(secs)
	var h := s / 3600
	var m := (s % 3600) / 60
	if h > 0: return "%dh %dm" % [h, m]
	if m > 0: return "%dm %ds" % [m, s % 60]
	return "%ds" % s

# ---------------- Save / load ----------------
func save_game() -> void:
	var data := {
		"version": 2,
		"resources": resources,
		"credits": credits,
		"skills": skills,
		"research": unlocked_research.keys(),
		"active_type": active_type,
		"active_id": active_id,
		"progress": progress,
		"combat_hp": combat_hp,
		"active_hull": active_hull,
		"owned_hulls": owned_hulls.keys(),
		"module_inventory": module_inventory,
		"loadout": loadout,
		"buildings": buildings,
		"building_throttle": building_throttle,
		"bounty_available": bounty_available,
		"bounty_active": bounty_active,
		"bounty_refresh_timer": bounty_refresh_timer,
		"bounty_total": bounty_total,
		"bounty_id": _bounty_id,
		"time": Time.get_unix_time_from_system(),
	}
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(SAVE_PATH, SAVE_PATH + ".bak")
	DirAccess.rename_absolute(tmp, SAVE_PATH)

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(txt) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	var data: Dictionary = json.data
	resources = data.get("resources", {})
	credits = int(data.get("credits", 0))
	skills = data.get("skills", skills)
	unlocked_research = {}
	for r in data.get("research", []):
		unlocked_research[r] = true
	active_type = data.get("active_type", "")
	active_id = data.get("active_id", "")
	progress = float(data.get("progress", 0.0))
	combat_hp = float(data.get("combat_hp", 0.0))
	active_hull = data.get("active_hull", "")
	owned_hulls = {}
	for hid in data.get("owned_hulls", []):
		owned_hulls[hid] = true
	module_inventory = data.get("module_inventory", {})
	for k in module_inventory:
		module_inventory[k] = int(module_inventory[k])
	loadout = data.get("loadout", {})
	buildings = data.get("buildings", {})
	for k in buildings:
		buildings[k] = int(buildings[k])
	building_throttle = data.get("building_throttle", {})
	bounty_available = data.get("bounty_available", [])
	bounty_active = data.get("bounty_active", [])
	bounty_refresh_timer = float(data.get("bounty_refresh_timer", 0.0))
	bounty_total = int(data.get("bounty_total", 0))
	_bounty_id = int(data.get("bounty_id", 0))
	var last := float(data.get("time", Time.get_unix_time_from_system()))
	var away := Time.get_unix_time_from_system() - last
	_apply_offline(away)
	_offline_infra(away)
	resources_changed.emit()
	skills_changed.emit()
	research_changed.emit()
	action_changed.emit()

func hard_reset() -> void:
	resources = {}
	credits = 0
	skills = {"harvesting": 0, "fabrication": 0, "combat": 0, "infrastructure": 0}
	unlocked_research = {}
	buildings = {}
	building_throttle = {}
	_build_timers = {}
	_build_frac = {}
	active_hull = "corvette_hull"
	owned_hulls = {"corvette_hull": true}
	module_inventory = {}
	loadout = {}
	bounty_available = []
	bounty_active = []
	bounty_refresh_timer = 0.0
	bounty_total = 0
	pending_offline = ""
	combat_hp = combat_max_hp()
	stop_task()
	generate_bounty_pool()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	resources_changed.emit()
	skills_changed.emit()
	research_changed.emit()
