extends Node
## Core game engine. Autoloaded as `GameState`.
## Single-active-task model with offline progress. Content from GameData (ported
## from horizonidle-godot): gather/craft/combat + a credit-funded research tree.

signal resources_changed
signal skills_changed
signal research_changed
signal action_changed
signal missions_changed
signal offline_ready          # emitted after a background-resume catch-up, for the UI modal
signal action_reward(text: String, accent: String)   # floating "+N" feedback on the active page

# Missions (tutorial chain)
var missions_active: Dictionary = {}     # mid -> true
var missions_progress: Dictionary = {}   # mid -> count
var missions_claimed: Dictionary = {}    # mid -> true

var resources: Dictionary = {}          # symbol -> int
var credits: int = 0                    # research currency (earned by selling)
var lifetime_credits: int = 0           # total credits ever earned (for prestige)
# Warp / prestige
var warp_shards: float = 0.0
var total_warps: int = 0
var credits_at_warp_start: int = 0
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

# Combat (real-time ship duel)
var combat_hp: float = 0.0            # persistent hull HP
var player_shield: float = 0.0        # regenerates fast in combat
var player_heat: float = 0.0          # weapons add heat; overheat locks fire
var _overheat_lock: float = 0.0
var _broadside_timer: float = 0.0     # unique module: Broadside Array
var _weapons: Array = []              # live weapon states built from loadout
var enemy_inst: Dictionary = {}       # live enemy instance
var _enemy_timer: float = 0.0
var combat_events: Array = []         # transient [{text,color,side,seq}] for UI popups
var _event_seq: int = 0
# Ammo + consumables (fittings)
var ammo_loadout: Dictionary = {}      # weapon slot index (String) -> ammo item id
var consumable_hull_slot: String = ""
var consumable_shield_slot: String = ""
var _consume_cd: float = 0.0
const MAX_LEVEL := 99                  # skill level cap (matches desktop)
var _xp_table: Array = []              # lazily built cumulative XP-to-level table
const CONSUME_CD := 1.5
const CONSUME_THRESHOLD := 0.5         # auto-trigger at 50% hull/shield
const HP_REGEN := 0.04                # hull regen/sec (fraction) out of combat
const MAX_HEAT := 100.0
const VENT_RATE := 8.0

# Shipyard
var active_hull: String = ""
var owned_hulls: Dictionary = {}        # hull_id -> true
var module_inventory: Dictionary = {}   # module_id -> count (unequipped)
var loadout: Dictionary = {}            # slot_index (as String) -> module_id
var custom_modules: Dictionary = {}     # custom_id -> rolled module instance (rarity + affixes)

# --- Module rarity / affix system ---
const RARITY_LABEL := {0: "", 1: "Uncommon", 2: "Rare", 3: "Legendary", 4: "Unique"}
const RARITY_COLOR := {0: "9aa7c2", 1: "35d935", 2: "3a9fff", 3: "ffcc33", 4: "ff44cc"}
const RARITY_RANGE := {1: [0.05, 0.08], 2: [0.11, 0.15], 3: [0.18, 0.22], 4: [0.23, 0.27]}
const RARITY_SELL := {0: 100, 1: 500, 2: 2500, 3: 15000, 4: 40000}
const BOOSTABLE := ["atk_kinetic", "atk_energy", "atk_explosive", "hp", "def", "eva", "accuracy",
	"crit_chance", "max_shield", "shield_regen", "energy_capacity", "atk_speed_bonus",
	"shield_regen_mult", "atk_speed_mult", "jamming_strength", "atk_interval"]
const ZONE_SCALABLE := ["atk_kinetic", "atk_energy", "atk_explosive", "hp", "def", "eva",
	"accuracy", "max_shield", "shield_regen", "energy_capacity", "atk_interval"]
const AFFIX_DB := {
	"static_burst":     {"name": "Static Burst", "type": "tactical", "range": [0.03, 0.08], "limit_to": ["weapon"], "desc": "%d%% shock on hit (resets enemy timer)"},
	"void_strike":      {"name": "Void Strike", "type": "tactical", "range": [0.03, 0.08], "limit_to": ["weapon"], "desc": "%d%% chance to bypass shields"},
	"heat_sync_focus":  {"name": "Heat-Sync Focus", "type": "tactical", "range": [0.05, 0.12], "limit_to": ["weapon", "cooling"], "desc": "+%d%% fire rate while Heat > 40%%"},
	"capacitor_pulse":  {"name": "Capacitor Pulse", "type": "tactical", "range": [0.02, 0.05], "limit_to": ["shield", "battery"], "desc": "Restore %d%% shield on kill"},
	"nanite_resurgence":{"name": "Nanite Resurgence", "type": "tactical", "range": [0.02, 0.05], "limit_to": ["armor"], "desc": "Restore %d%% hull on kill"},
	"extractor_efficiency": {"name": "Extractor Efficiency", "type": "industrial", "range": [0.03, 0.10], "limit_to": ["sensor"], "desc": "+%d%% gather yield"},
	"refinery_link":    {"name": "Refinery Link", "type": "industrial", "range": [0.03, 0.10], "limit_to": ["sensor"], "desc": "+%d%% craft speed"},
	"nano_scavenger":   {"name": "Nano-Scavenger", "type": "industrial", "range": [0.03, 0.10], "limit_to": ["sensor"], "desc": "%d%% chance to scavenge parts on kill"},
	"contract_negotiation": {"name": "Contract Negotiation", "type": "economy", "range": [0.03, 0.10], "limit_to": ["sensor"], "desc": "+%d%% bounty credits"},
	"logistician_edge": {"name": "Logistician's Edge", "type": "economy", "range": [0.03, 0.10], "limit_to": ["sensor"], "desc": "-%d%% delivery material cost"},
}

# Infrastructure (passive production buildings — runs in the background always)
var buildings: Dictionary = {}          # id -> count
var building_throttle: Dictionary = {}  # id -> 0..1
var infra_energy: float = 0.0           # grid battery (capacity = ship energy_cap)
var _fuel_frac: Dictionary = {}         # fractional fuel-generator consumption accumulator
var _build_timers: Dictionary = {}      # id -> accumulated time
var _build_frac: Dictionary = {}        # sym -> fractional carry
var _infra_dirty := false
var _infra_emit_accum := 0.0

var pending_offline: String = ""
var _bg_time := 0.0             # wall-clock when the app was backgrounded (0 = foreground)
var offline_combat := false             # option: process combat while away (off by default, like desktop)

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
	_mission_init()
	_mission_repair()

func _process(delta: float) -> void:
	_tick_active(delta)
	_tick_infra(delta)
	# Hull does NOT passively regenerate — repair via credits or in-combat consumables/sets.
	combat_hp = minf(combat_hp, combat_max_hp())
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
	# Android freezes the process while backgrounded (no _process ticks), so we
	# record when we leave and credit the elapsed time on return — same as a cold
	# launch, but without needing a full reload.
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if _bg_time == 0.0:
			_bg_time = Time.get_unix_time_from_system()
			save_game()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		if _bg_time > 0.0:
			var delta := Time.get_unix_time_from_system() - _bg_time
			_bg_time = 0.0
			_catch_up_offline(delta)

## Apply offline progress for `delta` seconds while the app was backgrounded
## (mirrors the cold-launch path) and notify the UI to show the report.
func _catch_up_offline(delta: float) -> void:
	if delta < 5.0:
		return
	pending_offline = ""
	_apply_offline(delta)
	var infra := _offline_infra(delta)
	if infra != "":
		if pending_offline == "":
			pending_offline = "Away for %s\n\n%s" % [_fmt_time(delta), infra]
		else:
			pending_offline += "\n" + infra
	resources_changed.emit()
	skills_changed.emit()
	if pending_offline != "":
		offline_ready.emit()

# ---------------- Resources / credits ----------------
func amount(sym: String) -> int:
	return int(resources.get(sym, 0))

func add_resource(sym: String, amt: int) -> void:
	# Storage cap: a new material is dropped when all slots are full (desktop
	# resources.gd). Existing stacks are unbounded.
	if amt > 0 and amount(sym) <= 0 and used_slots() >= max_slots():
		return
	resources[sym] = amount(sym) + amt
	if amt > 0 and not missions_active.is_empty():
		_mission_event("gather", sym, amt)
	resources_changed.emit()

# ---- Storage slots ----
const BASE_SLOTS := 28
var storage_upgrades := 0

func used_slots() -> int:
	var n := 0
	for sym in resources:
		if int(resources[sym]) > 0:
			n += 1
	return n

func max_slots() -> int:
	return BASE_SLOTS + storage_upgrades

func storage_upgrade_cost() -> int:
	return int(floor(1000.0 * pow(1.5, storage_upgrades)))

func upgrade_storage() -> bool:
	var cost := storage_upgrade_cost()
	if credits < cost:
		return false
	credits -= cost
	storage_upgrades += 1
	resources_changed.emit()
	return true

func gain_credits(n: int) -> void:
	credits += n
	lifetime_credits += n   # lifetime total drives prestige gains

# ---------------- Warp / prestige multipliers ----------------
func warp_tier() -> int:
	return total_warps / 5

func warp_gathering_mult() -> float:
	return (1.0 + warp_shards * 0.015) * pow(2.0, warp_tier())

func warp_xp_mult() -> float:
	return (1.0 + warp_shards * 0.025) * pow(2.0, warp_tier())

func warp_production_mult() -> float:
	return (1.0 + warp_shards * 0.02) * pow(2.0, warp_tier())

func warp_combat_mult() -> float:
	return (1.0 + warp_shards * 0.03) * pow(2.0, warp_tier())

## Shards that would be gained by warping now (0 = below threshold).
func warp_gain_preview() -> int:
	var earned := lifetime_credits - credits_at_warp_start
	var bcount := 0
	for bid in buildings:
		bcount += int(buildings[bid])
	var score := float(earned) + bcount * 1000.0
	if score < 500000.0:
		return 0
	return int(floor(log(maxf(1.0, score / 500000.0)) / log(2.0)) + 1.0)

func execute_warp() -> int:
	var gains := warp_gain_preview()
	if gains <= 0:
		return 0
	warp_shards += gains
	total_warps += 1
	credits_at_warp_start = lifetime_credits
	var bonus := int(warp_shards)
	# Reset the world. Research unlocks PERSIST (soft reset); skills keep 30% XP.
	resources = {}
	credits = 0
	for sk in skills:
		skills[sk] = int(skills[sk] * 0.3)
	buildings = {}
	building_throttle = {}
	infra_energy = 0.0
	_build_timers = {}
	_build_frac = {}
	active_hull = "corvette_hull"
	owned_hulls = {"corvette_hull": true}
	module_inventory = {}
	loadout = {}
	bounty_active = []
	stop_task()
	# Starting package (does not feed the next prestige).
	credits = bonus * 5000
	for r in {"Fe": 50, "Si": 30, "Wood": 20, "Water": 50}:
		resources[r] = {"Fe": 50, "Si": 30, "Wood": 20, "Water": 50}[r] * bonus
	combat_hp = combat_max_hp()
	generate_bounty_pool()
	resources_changed.emit()
	skills_changed.emit()
	research_changed.emit()
	action_changed.emit()
	save_game()
	return gains

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
	gain_credits(qty * maxi(1, GameData.value_of(sym)))
	resources[sym] = 0
	resources_changed.emit()

# ---------------- Skills ----------------
func xp_for_level(lvl: int) -> int:
	# RuneScape-style table (matches the desktop Skill class): steeper early game,
	# capped at level 99.
	if _xp_table.is_empty():
		var total := 0.0
		_xp_table.resize(MAX_LEVEL + 1)
		for l in range(1, MAX_LEVEL + 1):
			_xp_table[l] = int(total)
			var boost := 200.0 if l < 20 else 0.0
			total += floor(l + boost + 300.0 * pow(2.0, float(l) / 7.0)) / 4.0
	if lvl <= 1:
		return 0
	if lvl > MAX_LEVEL:
		return 0x7FFFFFFFFFFF       # unreachable — enforces the level cap
	return int(_xp_table[lvl])

func level_of(skill_id: String) -> int:
	var xp := int(skills.get(skill_id, 0))
	var lvl := 1
	while lvl < MAX_LEVEL and xp >= xp_for_level(lvl + 1):
		lvl += 1
	return lvl

func add_xp(skill_id: String, amt: int) -> void:
	# Crew Quarters: +10% XP gain per building (desktop infrastructure xp_buff).
	var xp_mult := warp_xp_mult() * (1.0 + building_count("crew_quarters") * 0.10)
	skills[skill_id] = int(skills.get(skill_id, 0)) + int(round(amt * xp_mult))
	skills_changed.emit()

func yield_mult(skill_id: String) -> float:
	if skill_id != "harvesting":
		return 1.0 + level_of(skill_id) * 0.01
	var m := 1.0 + level_of("harvesting") * 0.01          # +1% per level (Planetary Operations)
	if level_of("harvesting") >= 10:
		m *= 1.10                                          # milestone 10: +10% yield
	m *= research_efficiency_mult()                        # Efficiency I-V: 2x..32x
	m *= 1.0 + affix_total("extractor_efficiency")
	m *= 1.0 + research_bonus("gathering_yield_mult")      # Recursion: gathering_focus
	# NB: warp prestige boosts gathering via SPEED (see gather_speed_mult), not yield.
	return m

# ---------------- Combat stats ----------------
## Derived ship stats from the active hull + equipped modules.
## Returns {} when no ship is equipped.
func ship_stats() -> Dictionary:
	if active_hull == "" or not GameData.HULLS.has(active_hull):
		return {}
	var h: Dictionary = GameData.HULLS[active_hull]
	var s := {"atk": 0.0, "hp": float(h.get("hp", 100)), "def": 0.0, "shield": 0.0,
		"energy_cap": float(h.get("energy_capacity", 0)), "energy_load": 0.0,
		"acc": 15.0, "eva": 0.0, "crit": 0.05, "shield_regen": 0.0}
	var dps := 0.0
	var spd_bonus := 0.0
	var spd_mult := 1.0
	for k in loadout:
		var m: Dictionary = module_def(loadout[k])
		var st: Dictionary = m.get("stats", {})
		s.hp += float(st.get("hp", 0))
		s.def += float(st.get("def", 0))
		s.shield += float(st.get("max_shield", 0))
		s.energy_cap += float(st.get("energy_capacity", 0))
		s.energy_load += float(st.get("energy_load", 0))
		s.acc += float(st.get("accuracy", 0))
		s.eva += float(st.get("eva", 0))
		s.crit += float(st.get("crit_chance", 0))
		s.shield_regen += float(st.get("shield_regen", 0))
		spd_bonus += float(st.get("atk_speed_bonus", 0))
		if st.has("atk_speed_mult"):
			spd_mult *= float(st["atk_speed_mult"])
		var dmg := float(st.get("atk_energy", 0)) + float(st.get("atk_kinetic", 0)) + float(st.get("atk_explosive", 0))
		if dmg > 0.0:
			dps += dmg / maxf(0.1, float(st.get("atk_interval", 1.0)))
	s.atk = dps * (1.0 + spd_bonus) * spd_mult + float(h.get("atk", 0))
	# Gem core global multipliers
	s.crit += gem_bonus("crit_chance")
	s.hp *= 1.0 + gem_bonus("hp_mult")
	s.def *= 1.0 + gem_bonus("def_mult")
	s.shield *= 1.0 + gem_bonus("max_shield_mult")
	s.shield_regen *= 1.0 + gem_bonus("shield_regen_mult")
	s.eva *= 1.0 + gem_bonus("eva_mult")
	s.energy_cap *= 1.0 + gem_bonus("energy_capacity_mult") + research_bonus("applied_physics")
	# Combat skill milestones (desktop Phase 21): +5% crit @ L10, +15 eva @ L25.
	if level_of("combat") >= 10:
		s.crit += 0.05
	if level_of("combat") >= 25:
		s.eva += 15.0
	return s

## Live weapon list built from equipped weapon modules (or the hull cannon).
func ship_weapons() -> Array:
	var spd_bonus := 0.0
	var spd_mult := 1.0
	for k in loadout:
		var st: Dictionary = module_def(loadout[k]).get("stats", {})
		spd_bonus += float(st.get("atk_speed_bonus", 0))
		if st.has("atk_speed_mult"):
			spd_mult *= float(st["atk_speed_mult"])
	var speed := (1.0 + spd_bonus) * spd_mult
	var dmg_mult := (1.0 + level_of("combat") * 0.005) * warp_combat_mult() * (1.0 + research_bonus("combat_damage"))
	var eng_mult := 1.0 + level_of("fabrication") * 0.01
	var out := []
	for k in loadout:
		var m: Dictionary = module_def(loadout[k])
		if m.get("slot", "") != "weapon":
			continue
		var st: Dictionary = m.get("stats", {})
		var ke := float(st.get("atk_energy", 0))
		var kk := float(st.get("atk_kinetic", 0))
		var kx := float(st.get("atk_explosive", 0))
		var type := "kinetic"
		if ke > 0: type = "energy"
		elif kx > 0: type = "explosive"
		var gk := 1.0 + gem_bonus("atk_kinetic_mult")
		var ge := 1.0 + gem_bonus("atk_energy_mult")
		out.append({"name": m.get("name", "Weapon"), "type": type, "slot": str(k),
			"dmg_k": kk * eng_mult * dmg_mult * gk, "dmg_e": ke * eng_mult * dmg_mult * ge, "dmg_x": kx * eng_mult * dmg_mult,
			"interval": maxf(0.3, float(st.get("atk_interval", 2.5)) / maxf(0.2, speed)), "timer": randf_range(0.0, 0.4)})
	if out.is_empty():
		var h: Dictionary = GameData.HULLS.get(active_hull, {})
		out.append({"name": "Standard Cannon", "type": "kinetic", "slot": "",
			"dmg_k": float(h.get("atk", 5)) * dmg_mult, "dmg_e": 0.0, "dmg_x": 0.0,
			"interval": maxf(0.3, 3.0 / maxf(0.2, speed)), "timer": 0.0})
	return out

## Flat ammo damage bonus by item id (faithful tiers), and which damage type it feeds.
func ammo_bonus(ammo_id: String) -> Array:
	if ammo_id.begins_with("Slug"):
		var b := 5.0
		if "T1S" in ammo_id: b = 10.0
		elif "T2" in ammo_id: b = 15.0
		elif "T3" in ammo_id: b = 30.0
		elif "T4" in ammo_id: b = 60.0
		return ["k", b]
	elif ammo_id.begins_with("Cell"):
		var b := 5.0
		if "T2" in ammo_id: b = 15.0
		elif "T3" in ammo_id: b = 30.0
		elif "T4" in ammo_id: b = 60.0
		return ["e", b]
	elif "issile" in ammo_id or "orpedo" in ammo_id or "eeker" in ammo_id:
		var b := 10.0
		if "Seeker" in ammo_id: b = 25.0
		elif "orpedo" in ammo_id: b = 60.0
		return ["x", b]
	return ["", 0.0]

func combat_max_hp() -> float:
	var s := ship_stats()
	if s.is_empty():
		return 100.0
	var base: float = s["hp"] + level_of("combat") * 20.0
	return base * (1.0 + research_bonus("max_hp_mult") + research_bonus("materials_science"))

func player_max_shield() -> float:
	var s := ship_stats()
	return s.get("shield", 0.0) if not s.is_empty() else 0.0

## Average sustained DPS vs a target (used for offline + UI readout).
func avg_player_dps() -> float:
	var total := 0.0
	for w in ship_weapons():
		total += (float(w["dmg_k"]) + float(w["dmg_e"]) + float(w["dmg_x"])) / maxf(0.3, float(w["interval"]))
	return total

func combat_attack() -> float:
	return avg_player_dps()

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
		_mission_event("construct", hid, 1)
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
	_mission_event("craft", mid, 1)
	resources_changed.emit()
	return true

var equip_notice := ""                  # last equip rejection reason (shown in UI)

func equip_module(mid: String) -> bool:
	if int(module_inventory.get(mid, 0)) <= 0:
		return false
	var st: String = module_def(mid).get("slot", "")
	var slots: Array = GameData.HULLS.get(active_hull, {}).get("slots", [])
	for i in slots.size():
		if slots[i] == st and not loadout.has(str(i)):
			# Grid-overload guard (desktop Phase 18): reject if equipping pushes
			# energy load past capacity, unless the module itself adds capacity
			# (a battery — anti-softlock exception).
			var before := ship_stats()
			loadout[str(i)] = mid
			var after := ship_stats()
			if float(after.get("energy_load", 0.0)) > float(after.get("energy_cap", 0.0)) \
					and float(after.get("energy_cap", 0.0)) <= float(before.get("energy_cap", 0.0)) + 0.1:
				loadout.erase(str(i))
				equip_notice = "Grid overload — equip a Battery for more power."
				resources_changed.emit()
				return false
			module_inventory[mid] = int(module_inventory[mid]) - 1
			equip_notice = ""
			resources_changed.emit()
			return true
	return false

func unequip_slot(idx: String) -> void:
	if loadout.has(idx):
		module_inventory[loadout[idx]] = int(module_inventory.get(loadout[idx], 0)) + 1
		loadout.erase(idx)
		resources_changed.emit()

# ---------------- Module rarity / affixes ----------------
## Unified lookup: rolled custom instance, else the base catalogue module.
func module_def(mid: String) -> Dictionary:
	if custom_modules.has(mid):
		return custom_modules[mid]
	if GameData.SET_MODULES.has(mid):
		return GameData.SET_MODULES[mid]
	return GameData.MODULES.get(mid, {})

## True if a module (base id) is equipped — including rolled instances of it.
func loadout_has_module(base_id: String) -> bool:
	for mid in loadout.values():
		if mid == base_id or module_def(mid).get("base", "") == base_id:
			return true
	return false

func _current_zone_id() -> String:
	for z in GameData.ZONES:
		if active_id in z.get("enemies", []):
			return z.get("id", "")
	return ""

# ---------------- Set bonuses + gem sockets ----------------
func equipped_set_counts() -> Dictionary:
	var counts := {}
	for mid in loadout.values():
		var sn: String = module_def(mid).get("set", "")
		if sn != "":
			counts[sn] = int(counts.get(sn, 0)) + 1
	return counts

func has_set_bonus(bonus_key: String) -> bool:
	var counts := equipped_set_counts()
	for sn in counts:
		if counts[sn] >= 3 and GameData.SETS.get(sn, {}).get("bonus", "") == bonus_key:
			return true
	return false

## Sum of a gem effect across gems socketed into equipped modules.
func gem_bonus(key: String) -> float:
	var s := 0.0
	for mid in loadout.values():
		for gid in module_def(mid).get("sockets", []):
			if gid != null and gid != "" and GameData.GEMS.has(gid):
				s += float(GameData.GEMS[gid]["effects"].get(key, 0.0))
	return s

## Insert a gem (from inventory) into the first empty socket of a custom module.
func socket_gem(cid: String, gem_id: String) -> bool:
	if not custom_modules.has(cid) or amount(gem_id) <= 0:
		return false
	var sockets: Array = custom_modules[cid].get("sockets", [])
	for i in sockets.size():
		if sockets[i] == null or sockets[i] == "":
			sockets[i] = gem_id
			resources[gem_id] = amount(gem_id) - 1
			resources_changed.emit()
			return true
	return false

func unsocket_gem(cid: String, idx: int) -> void:
	if not custom_modules.has(cid):
		return
	var sockets: Array = custom_modules[cid].get("sockets", [])
	if idx >= 0 and idx < sockets.size() and sockets[idx] != null and sockets[idx] != "":
		add_resource(sockets[idx], 1)
		sockets[idx] = null
		resources_changed.emit()

## Drop a set piece as a mutable custom instance (with sockets).
func _grant_set_piece(base_id: String) -> void:
	var t: Dictionary = GameData.SET_MODULES.get(base_id, {})
	if t.is_empty():
		return
	var cid := "set_%s_%d" % [base_id, randi() % 1000000]
	custom_modules[cid] = {
		"name": t.get("name", base_id), "slot": t.get("slot", ""), "stats": t.get("stats", {}).duplicate(),
		"desc": t.get("desc", ""), "rarity": 4, "affixes": {}, "set": t.get("set", ""),
		"base": base_id, "sockets": [null, null, null],
	}
	module_inventory[cid] = int(module_inventory.get(cid, 0)) + 1

func roll_rarity(is_boss: bool) -> int:
	var r := randf()
	var leg := 0.05 if is_boss else 0.02
	if r < leg:
		return 3
	elif r < leg + 0.10:
		return 2
	elif r < leg + 0.40:
		return 1
	return 0

## Creates a rolled module instance (or the base for Common); returns its id.
func generate_module(base_id: String, rarity: int, zone_diff: int) -> String:
	if not GameData.MODULES.has(base_id):
		return ""
	if rarity == 0:
		module_inventory[base_id] = int(module_inventory.get(base_id, 0)) + 1
		return base_id
	var base: Dictionary = GameData.MODULES[base_id]
	var zmult := pow(1.30, maxi(0, zone_diff - 1))
	var rng: Array = RARITY_RANGE[rarity]
	var stats := {}
	for sk in base.get("stats", {}):
		var bv := float(base["stats"][sk])
		if BOOSTABLE.has(sk):
			var scaled := bv
			if ZONE_SCALABLE.has(sk):
				scaled = maxf(0.25, bv / zmult) if sk == "atk_interval" else bv * zmult
			var bonus := randf_range(rng[0], rng[1])
			if sk == "atk_interval":
				stats[sk] = snappedf(maxf(0.25, scaled / (1.0 + bonus * 0.4)), 0.01)
			else:
				stats[sk] = snappedf(scaled * (1.0 + bonus), 0.1) if scaled < 50.0 else float(int(round(scaled * (1.0 + bonus))))
		else:
			stats[sk] = bv
	# Affixes: pick N from the slot-eligible pool.
	var slot: String = base.get("slot", "")
	var pool := []
	for aid in AFFIX_DB:
		if (AFFIX_DB[aid]["limit_to"] as Array).has(slot):
			pool.append(aid)
	if pool.is_empty():
		for aid in AFFIX_DB:
			if AFFIX_DB[aid]["type"] in ["industrial", "economy"]:
				pool.append(aid)
	var n: int = mini({2: 1, 3: 2, 4: 3}.get(rarity, 0), pool.size())
	pool.shuffle()
	var affixes := {}
	for i in n:
		affixes[pool[i]] = randf_range(AFFIX_DB[pool[i]]["range"][0], AFFIX_DB[pool[i]]["range"][1])
	# Sockets: Unique = 3, Legendary = 1-3, Rare = 30% chance of 1.
	var sockets := []
	if rarity == 4:
		sockets = [null, null, null]
	elif rarity == 3:
		for _i in randi() % 3 + 1:
			sockets.append(null)
	elif rarity == 2 and randf() < 0.3:
		sockets = [null]
	var cid := "cm_%s_%d_%d" % [base_id, Time.get_ticks_msec(), randi() % 100000]
	custom_modules[cid] = {
		"name": "%s (%s)" % [base.get("name", base_id), RARITY_LABEL[rarity]],
		"slot": slot, "stats": stats, "desc": base.get("desc", ""),
		"rarity": rarity, "affixes": affixes, "base": base_id, "sockets": sockets,
	}
	module_inventory[cid] = int(module_inventory.get(cid, 0)) + 1
	return cid

## Sum of an affix value across equipped (loadout) custom modules.
func affix_total(key: String) -> float:
	var s := 0.0
	for mid in loadout.values():
		if custom_modules.has(mid):
			s += float(custom_modules[mid].get("affixes", {}).get(key, 0.0))
	return s

func sell_module(mid: String) -> bool:
	if int(module_inventory.get(mid, 0)) <= 0:
		return false
	var price := 100
	if custom_modules.has(mid):
		price = int(RARITY_SELL.get(int(custom_modules[mid].get("rarity", 0)), 100))
	else:
		price = maxi(50, int(float(GameData.MODULES.get(mid, {}).get("cost", {}).get("credits", 200)) * 0.25))
	module_inventory[mid] = int(module_inventory[mid]) - 1
	if module_inventory[mid] <= 0:
		module_inventory.erase(mid)
		if custom_modules.has(mid):
			custom_modules.erase(mid)
	gain_credits(price)
	resources_changed.emit()
	return true

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

## Unlocked module ids dropped by a zone's enemies (for bounty rewards).
func _zone_module_pool(z: Dictionary) -> Array:
	var pool := []
	for eid in z.get("enemies", []):
		for mid in GameData.ENEMIES.get(eid, {}).get("drop_pool", []):
			if GameData.MODULES.has(mid) and module_unlocked(mid) and not pool.has(mid):
				pool.append(mid)
	return pool

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
		"reward_pool": _zone_module_pool(z),
		"zone_id": z.get("id", ""), "difficulty": diff, "completed": false, "is_elite": elite}

func _gen_delivery(mind: int, maxd: int) -> Dictionary:
	var tier := randi_range(mind, maxd)
	var tmpl: Array = DELIVERY_MATERIALS.get(tier, [])
	if tmpl.is_empty():
		return {}
	var t: Array = tmpl[randi() % tmpl.size()]
	var qty := randi_range(int(t[1]), int(t[2]))
	var rpool := []
	for z in GameData.ZONES:
		if int(z.get("difficulty", 1)) == tier:
			rpool = _zone_module_pool(z)
			break
	return {"id": _gen_bid(), "type": "delivery", "title": "Supply: %s" % GameData.res_name(t[0]),
		"desc": "Deliver %d %s to the station." % [qty, GameData.res_name(t[0])],
		"target": t[0], "target_qty": qty, "current_qty": 0, "reward_credits": int(t[3]),
		"reward_pool": rpool, "zone_id": "", "difficulty": tier, "completed": false, "is_elite": false}

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
		var need := int(c["target_qty"] * (1.0 - affix_total("logistician_edge")))  # Logistician's Edge
		if amount(c["target"]) < need:
			return false
		resources[c["target"]] = amount(c["target"]) - need
		c["current_qty"] = need
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
	gain_credits(int(c["reward_credits"] * (1.0 + affix_total("contract_negotiation"))))  # Contract Negotiation
	# Module reward: bounties have a high rarity floor (Rare+).
	var rpool: Array = c.get("reward_pool", [])
	if not rpool.is_empty():
		var rarity := 3 if (int(c.get("difficulty", 1)) >= 8 or randf() < 0.25) else 2  # Legendary or Rare
		generate_module(rpool[randi() % rpool.size()], rarity, int(c.get("difficulty", 1)))
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

func _is_fuel_gen(d: Dictionary) -> bool:
	return float(d.get("energy_gen", 0.0)) > 0.0 and not d.get("input", {}).is_empty()

## Returns {"gen": kW, "cons": kW, "eff": 0..1}. Nominal readout for the UI
## (assumes fuel available); the live tick also banks/drains the grid battery.
func infra_power() -> Dictionary:
	var gen := 0.0
	var cons := 0.0
	for bid in buildings:
		var d: Dictionary = GameData.BUILDINGS.get(bid, {})
		var t := get_throttle(bid)
		gen += float(d.get("energy_gen", 0.0)) * buildings[bid] * t
		cons += float(d.get("energy_cons", 0.0)) * buildings[bid] * t
	if level_of("infrastructure") >= 10:
		gen *= 1.10                                       # milestone 10: +10% generation
	var eff := 1.0 if cons <= gen or cons <= 0.0 else gen / cons
	return {"gen": gen, "cons": cons, "eff": eff}

func _global_yield_bonus() -> Dictionary:
	var gyb := {}
	for bid in buildings:
		var yb: Dictionary = GameData.BUILDINGS.get(bid, {}).get("yield_bonus", {})
		for res in yb:
			gyb[res] = gyb.get(res, 0.0) + float(yb[res]) * buildings[bid]
	return gyb

func _infra_skill_speed() -> float:
	return 1.0 + level_of("infrastructure") * 0.01 + research_bonus("industrial_logistics") + research_bonus("industrial_catalysis")

## Energy phase: pure generators always run; fuel generators run at 100% (ignoring
## grid efficiency) to jumpstart, consuming fuel; surplus banks into the grid
## battery (capacity = ship energy_cap) and is drained to cover deficits.
## Returns grid efficiency 0..1 for the production phase.
func _infra_energy_step(delta: float) -> float:
	var skill_speed := _infra_skill_speed()
	var gen := 0.0
	var cons := 0.0
	for bid in buildings:
		var count: int = buildings[bid]
		if count <= 0:
			continue
		var d: Dictionary = GameData.BUILDINGS.get(bid, {})
		var t := get_throttle(bid)
		cons += float(d.get("energy_cons", 0.0)) * count * t
		var eg := float(d.get("energy_gen", 0.0))
		if eg <= 0.0:
			continue
		if d.get("input", {}).is_empty():
			gen += eg * count * t                          # pure generator (solar)
		else:
			var ei: float = maxf(0.05, float(d.get("interval", 1.0)) / skill_speed)
			var inp: Dictionary = d["input"]
			var can_fuel := true
			for res in inp:
				if amount(res) < float(inp[res]) * count * t * (delta / ei):
					can_fuel = false
					break
			if can_fuel:
				# Fractional fuel draw accumulated so small per-frame amounts don't
				# round up to a whole unit every frame.
				for res in inp:
					var need := float(inp[res]) * count * t * (delta / ei)
					_fuel_frac[res] = float(_fuel_frac.get(res, 0.0)) + need
					var whole := int(_fuel_frac[res])
					if whole > 0:
						resources[res] = amount(res) - whole
						_fuel_frac[res] = float(_fuel_frac[res]) - whole
						_infra_dirty = true
				gen += eg * count * t
	if level_of("infrastructure") >= 10:
		gen *= 1.10
	var cap: float = ship_stats().get("energy_cap", 0.0)
	var net := gen - cons
	if net >= 0.0:
		infra_energy = minf(cap, infra_energy + net * delta)
		return 1.0
	var deficit := -net * delta
	if infra_energy >= deficit:
		infra_energy -= deficit
		return 1.0
	if infra_energy > 0.0:
		var eff := infra_energy / deficit
		infra_energy = 0.0
		return eff
	return 0.0

func _tick_infra(delta: float) -> void:
	if buildings.is_empty():
		return
	var eff := _infra_energy_step(delta)
	var skill_speed := _infra_skill_speed()
	var gyb := _global_yield_bonus()
	for bid in buildings:
		var count: int = buildings[bid]
		if count <= 0:
			continue
		var d: Dictionary = GameData.BUILDINGS.get(bid, {})
		if d.get("special", "") == "passive_gather":
			_passive_gather_step(bid, count, delta * eff)
			continue
		# Process producers AND upkeep consumers (e.g. Crew Quarters' Food); skip
		# pure/fuel generators (handled in the energy step).
		if not _is_production_building(d):
			continue
		var eff_interval: float = maxf(0.05, float(d.get("interval", 1.0)) / skill_speed)
		var t := get_throttle(bid)
		_build_timers[bid] = float(_build_timers.get(bid, 0.0)) + delta * eff * t
		var guard := 0
		while float(_build_timers[bid]) >= eff_interval and guard < 200:
			guard += 1
			_build_timers[bid] = float(_build_timers[bid]) - eff_interval
			_produce_batch(bid, count, d, gyb)

func _is_production_building(d: Dictionary) -> bool:
	if not d.get("yield", {}).is_empty():
		return true
	# Upkeep consumer (has input, isn't a generator) — e.g. Crew Quarters.
	return not d.get("input", {}).is_empty() and float(d.get("energy_gen", 0.0)) <= 0.0

## Drone Recovery Bay: every 10s, each bay has a 25% chance to roll one entry
## from a random unlocked gathering action's loot table (desktop passive_gather).
func _passive_gather_step(bid: String, count: int, eff_delta: float) -> void:
	var key := "_pg_" + bid
	_build_timers[key] = float(_build_timers.get(key, 0.0)) + eff_delta
	while float(_build_timers[key]) >= 10.0:
		_build_timers[key] = float(_build_timers[key]) - 10.0
		_passive_gather_roll(count)

func _passive_gather_roll(bays: int) -> void:
	var unlocked := []
	for aid in GameData.GATHER:
		var a: Dictionary = GameData.GATHER[aid]
		if level_of("harvesting") < int(a.get("level_req", 1)):
			continue
		var req: String = a.get("research_req", "")
		if req != "" and not is_research_unlocked(req):
			continue
		if not a.get("loot", []).is_empty():
			unlocked.append(a)
	if unlocked.is_empty():
		return
	for _i in range(bays):
		if randf() < 0.25:
			var a: Dictionary = unlocked.pick_random()
			var row = (a["loot"] as Array).pick_random()
			add_resource(row[0], maxi(1, randi_range(int(row[2]), int(row[3]))))

## Offline infrastructure catch-up: runs the grid + production over `delta`,
## returns a short loot summary (or "").
func _offline_infra(delta: float) -> String:
	if buildings.is_empty():
		return ""
	var eff := _infra_energy_step(delta)
	if eff <= 0.0:
		return ""
	var skill_speed := _infra_skill_speed()
	var gyb := _global_yield_bonus()
	var before := {}
	for sym in resources:
		before[sym] = amount(sym)
	var cr_before := credits
	for bid in buildings:
		var count: int = buildings[bid]
		if count <= 0:
			continue
		var d: Dictionary = GameData.BUILDINGS.get(bid, {})
		if d.get("special", "") == "passive_gather":
			var pg_cycles: int = int(delta * eff * get_throttle(bid) / 10.0)
			for _p in range(mini(pg_cycles, 500000)):
				_passive_gather_roll(count)
			continue
		if not _is_production_building(d):
			continue
		var eff_interval: float = maxf(0.05, float(d.get("interval", 1.0)) / skill_speed)
		var cycles: int = int(delta * eff * get_throttle(bid) / eff_interval)
		for _i in range(mini(cycles, 500000)):
			_produce_batch(bid, count, d, gyb)            # self-limits when feedstock runs out
		if cycles > 0:
			add_xp("infrastructure", mini(cycles, 500000))
	var parts := []
	for sym in resources:
		var made := amount(sym) - int(before.get(sym, 0))
		if made > 0:
			parts.append("+%s %s" % [GameData.fmt(made), GameData.res_name(sym)])
	if credits - cr_before > 0:
		parts.append("+₡%s" % GameData.fmt(credits - cr_before))
	if parts.is_empty():
		return ""
	return "Infrastructure: " + ", ".join(parts)

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
		var qty := float(d["yield"][res]) * count * (1.0 + float(gyb.get(res, 0.0))) * warp_production_mult()
		if bid in eng_scaled:
			qty *= 1.0 + (log(1.0 + level_of("fabrication")) / log(10.0)) * 5.0
		_build_frac[res] = float(_build_frac.get(res, 0.0)) + qty
		var whole := int(_build_frac[res])
		if whole > 0:
			_build_frac[res] = float(_build_frac[res]) - whole
			if res == "credits":
				gain_credits(whole)
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
	_mission_event("build", bid, 1)
	resources_changed.emit()
	return true

# ---------------- Research ----------------
func is_research_unlocked(rid: String) -> bool:
	return unlocked_research.has(rid)

# --- Research passive efficiency bonuses (ported from research_manager) ---
func research_efficiency_mult() -> float:
	if is_research_unlocked("efficiency_5"): return 32.0
	if is_research_unlocked("efficiency_4"): return 16.0
	if is_research_unlocked("efficiency_3"): return 8.0
	if is_research_unlocked("efficiency_2"): return 4.0
	if is_research_unlocked("efficiency_1"): return 2.0
	return 1.0

func auto_consume_threshold() -> float:
	if is_research_unlocked("auto_repair_80"): return 0.8
	if is_research_unlocked("auto_repair_60"): return 0.6
	if is_research_unlocked("auto_repair_40"): return 0.4
	if is_research_unlocked("auto_repair_20"): return 0.2
	return 0.0

func research_bonus(key: String) -> float:
	match key:
		"combat_xp": return 0.20 if is_research_unlocked("combat_heuristics") else 0.0
		"shield_regen": return 0.20 if is_research_unlocked("shield_harmonics") else 0.0
		"max_hp_mult": return 0.15 if is_research_unlocked("hull_hardening") else 0.0
		"attack_speed": return 0.10 if is_research_unlocked("core_overclocking") else 0.0
		"gathering_yield":
			var y := 0.0
			if is_research_unlocked("deep_core_optics"): y += 1.0
			if is_research_unlocked("colony_automation"): y += 5.0
			return y
		"processing_speed":
			var p := 0.0
			if is_research_unlocked("nano_fabrication"): p += 0.15
			if is_research_unlocked("perfect_automation"): p += 0.30
			return p + _repeatable_bonus("processing_speed")
	if key == "applied_physics" and is_research_unlocked("applied_physics"): return 0.10
	if key == "materials_science" and is_research_unlocked("materials_science"): return 0.10
	if key == "industrial_logistics" and is_research_unlocked("industrial_logistics"): return 0.10
	if key == "industrial_catalysis" and is_research_unlocked("industrial_catalysis"): return 0.15
	if key == "xeno_engineering" and is_research_unlocked("xeno_engineering"): return 0.25
	# gathering_yield_mult / combat_damage come purely from repeatable research.
	return _repeatable_bonus(key)

# ---- Repeatable / Recursion research (infinite +5%/level sinks) ----
const REPEATABLE := {
	"production_focus": {"name": "Recursive Optimization", "field": "Industry", "desc": "+5% Global Processing Speed / level", "base_cost": 100000, "items": {"VoidArtifact": 5, "AdvCircuit": 50, "Bauxite": 100, "Quartz": 100, "PtOre": 25}, "bonus_type": "processing_speed", "bonus_value": 0.05},
	"combat_focus": {"name": "Recursive Calibration", "field": "Combat", "desc": "+5% Total Ship Damage / level", "base_cost": 100000, "items": {"VoidArtifact": 5, "QuantumCore": 5, "Malachite": 100}, "bonus_type": "combat_damage", "bonus_value": 0.05},
	"gathering_focus": {"name": "Recursive Logistics", "field": "Gathering", "desc": "+5% Global Gathering Yield / level", "base_cost": 100000, "items": {"VoidArtifact": 5, "DroneCore": 50, "Spodumene": 100}, "bonus_type": "gathering_yield_mult", "bonus_value": 0.05},
}
const REPEATABLE_ORDER := ["production_focus", "combat_focus", "gathering_focus"]
var repeatable_research: Dictionary = {}   # id -> level

func _repeatable_bonus(bonus_type: String) -> float:
	var b := 0.0
	for rid in repeatable_research:
		var rd: Dictionary = REPEATABLE.get(rid, {})
		if rd.get("bonus_type", "") == bonus_type:
			b += int(repeatable_research[rid]) * float(rd.get("bonus_value", 0.0))
	return b

func repeatable_level(rid: String) -> int:
	return int(repeatable_research.get(rid, 0))

func repeatable_cost(rid: String) -> Dictionary:
	var rd: Dictionary = REPEATABLE[rid]
	var lvl := repeatable_level(rid)
	var c := {"credits": int(float(rd["base_cost"]) * pow(1.3, lvl))}
	for res in rd.get("items", {}):
		c[res] = int(float(rd["items"][res]) * pow(1.2, lvl))
	return c

func can_unlock_repeatable(rid: String) -> bool:
	var c := repeatable_cost(rid)
	if credits < int(c["credits"]):
		return false
	for res in c:
		if res == "credits":
			continue
		if amount(res) < int(c[res]):
			return false
	return true

func unlock_repeatable(rid: String) -> bool:
	if not can_unlock_repeatable(rid):
		return false
	var c := repeatable_cost(rid)
	credits -= int(c["credits"])
	for res in c:
		if res != "credits":
			resources[res] = amount(res) - int(c[res])
	repeatable_research[rid] = repeatable_level(rid) + 1
	research_changed.emit()
	return true

const REPAIR_COST := {"corvette_hull": 1000, "frigate_hull": 5000, "destroyer_hull": 25000,
	"battlecruiser_hull": 100000, "dreadnought_hull": 500000}

func repair_cost() -> int:
	return int(REPAIR_COST.get(active_hull, 1000))

func repair_hull() -> bool:
	if combat_hp >= combat_max_hp():
		return false
	var cost := repair_cost()
	if credits < cost:
		return false
	credits -= cost
	combat_hp = combat_max_hp()
	resources_changed.emit()
	return true

# --- Missions ---
func _mission_init() -> void:
	if missions_active.is_empty() and missions_claimed.is_empty() and not GameData.MISSION_ORDER.is_empty():
		missions_active[GameData.MISSION_ORDER[0]] = true
	_mission_sync()

## Recover a stalled tutorial chain: if there's no active mission but unclaimed
## ones remain (e.g. an old save whose chain hit a since-fixed dead link),
## re-activate the next unclaimed mission by walking the chain from the start.
func _mission_repair() -> void:
	if not missions_active.is_empty() or missions_claimed.is_empty():
		return
	if GameData.MISSION_ORDER.is_empty():
		return
	var cur: String = GameData.MISSION_ORDER[0]
	var guard := 0
	while cur != "" and missions_claimed.has(cur) and guard < 200:
		guard += 1
		cur = GameData.MISSIONS.get(cur, {}).get("next", "")
	if cur != "" and GameData.MISSIONS.has(cur) and not missions_claimed.has(cur):
		missions_active[cur] = true
		_mission_sync()
		missions_changed.emit()

func mission_completed(mid: String) -> bool:
	var m: Dictionary = GameData.MISSIONS.get(mid, {})
	match m.get("type", ""):
		"gather_multi":               # need N of each material at once (inventory-based)
			return multi_have(m) >= int(m.get("qty", 1))
		"loadout_check":              # ship has a weapon + a shield equipped
			return is_combat_ready()
	return int(missions_progress.get(mid, 0)) >= int(m.get("qty", 1))

## Summed inventory progress toward a gather_multi mission's per-material goals.
func multi_have(m: Dictionary) -> int:
	var p := 0
	var tgt = m.get("target", {})
	if tgt is Dictionary:
		for s in tgt:
			p += mini(amount(s), int(tgt[s]))
	return p

func is_combat_ready() -> bool:
	var has_w := false
	var has_s := false
	for k in loadout:
		var st: String = module_def(loadout[k]).get("slot", "")
		if st == "weapon":
			has_w = true
		elif st == "shield":
			has_s = true
	if not has_s and ship_stats().get("shield", 0.0) > 0.0:
		has_s = true
	return has_w and has_s

## True once the player has started the tutorial chain (claimed or made progress).
func has_mission_progress() -> bool:
	if not missions_claimed.is_empty():
		return true
	for mid in missions_progress:
		if int(missions_progress[mid]) > 0:
			return true
	return false

## True when at least one active mission is finished and waiting to be claimed.
func has_claimable_mission() -> bool:
	for mid in missions_active:
		if mission_completed(mid) and not missions_claimed.has(mid):
			return true
	return false

# Retroactively reconcile active missions with current state (ported from the
# desktop sync_progress). Lets a mission that became active AFTER its requirement
# was already met — e.g. you researched Applied Physics before the mission asked —
# register as done instead of waiting for an event that already fired.
func _mission_sync() -> void:
	var changed := false
	for mid in missions_active.keys():
		if missions_claimed.has(mid) or mission_completed(mid):
			continue
		var m: Dictionary = GameData.MISSIONS.get(mid, {})
		var t: String = m.get("type", "")
		var target = m.get("target", "")   # may be a Dictionary for gather_multi
		var qty: int = int(m.get("qty", 1))
		var cur: int = int(missions_progress.get(mid, 0))
		var nv := cur
		match t:
			"research":
				if is_research_unlocked(target):
					nv = qty
			"gather":
				nv = maxi(cur, mini(amount(target), qty))
			"craft":
				var have := int(module_inventory.get(target, 0))
				for k in loadout:
					if loadout[k] == target:
						have += 1
				nv = maxi(cur, mini(have, qty))
			"build":
				nv = maxi(cur, mini(int(buildings.get(target, 0)), qty))
			"construct":
				var cur_tier := int(GameData.HULLS.get(active_hull, {}).get("tier", 0))
				var tgt_tier := int(GameData.HULLS.get(target, {}).get("tier", 0))
				if active_hull == target or hull_owned(target) or cur_tier >= tgt_tier:
					nv = qty
			# "defeat" is event-only (no persistent state to reconcile).
		if nv != cur:
			missions_progress[mid] = nv
			changed = true
	if changed:
		missions_changed.emit()

func _mission_event(type: String, target: String, amount: int) -> void:
	var changed := false
	for mid in missions_active.keys():
		var m: Dictionary = GameData.MISSIONS.get(mid, {})
		if m.get("type", "") == type and m.get("target", "") == target and not mission_completed(mid):
			missions_progress[mid] = mini(int(m.get("qty", 1)), int(missions_progress.get(mid, 0)) + amount)
			changed = true
	if changed:
		missions_changed.emit()

func claim_mission(mid: String) -> bool:
	if not missions_active.has(mid) or not mission_completed(mid) or missions_claimed.has(mid):
		return false
	var m: Dictionary = GameData.MISSIONS[mid]
	gain_credits(int(int(m.get("cr", 0)) * warp_production_mult()))   # prestige-scaled reward
	missions_claimed[mid] = true
	missions_active.erase(mid)
	var nxt: String = m.get("next", "")
	if nxt != "" and GameData.MISSIONS.has(nxt) and not missions_claimed.has(nxt):
		missions_active[nxt] = true
	_mission_sync()   # the newly-activated mission may already be satisfied
	missions_changed.emit()
	return true

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
	_mission_event("research", rid, 1)
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
	if type == "combat":
		_init_combat(id)
	action_changed.emit()

func stop_task() -> void:
	active_type = ""
	active_id = ""
	progress = 0.0
	enemy_inst = {}
	action_changed.emit()

# ---------------- Real-time combat ----------------
func _init_combat(eid: String) -> void:
	_weapons = ship_weapons()
	player_shield = player_max_shield()
	player_heat = 0.0
	_overheat_lock = 0.0
	_enemy_timer = 0.0
	combat_events.clear()
	if combat_hp <= 0.0:
		combat_hp = combat_max_hp()
	_spawn_enemy_inst(eid)

func _spawn_enemy_inst(eid: String) -> void:
	var e: Dictionary = GameData.ENEMIES.get(eid, {})
	var elite := randf() < 0.05
	for c in bounty_active:   # elite-hunt contracts force an elite spawn
		if c.get("is_elite", false) and not c["completed"] and c["target"] == eid:
			elite = true
			break
	var hp := float(e.get("hp", 10))
	var atk := float(e.get("atk", 1))
	var xp := int(e.get("xp", 0))
	var nm: String = e.get("name", eid)
	var loot: Array = e.get("loot", [])
	if elite:
		hp *= 2.5
		atk *= 1.8
		xp = int(xp * 3)
		nm = "ELITE " + nm
		loot = loot.duplicate(true)
		for row in loot:
			row[2] = int(row[2] * 2.5)
			row[3] = int(row[3] * 2.5)
	enemy_inst = {
		"id": eid, "name": nm, "elite": elite,
		"hp": hp, "max_hp": hp,
		"shield": float(e.get("max_shield", 0)), "max_shield": float(e.get("max_shield", 0)),
		"atk": atk, "def": float(e.get("def", 0)),
		"acc": float(e.get("accuracy", 0)), "eva": float(e.get("eva", 0)),
		"interval": maxf(0.5, float(e.get("interval", 2.5))),
		"loot": loot, "xp": xp,
		"drop_chance": float(e.get("drop_chance", 0.0)), "drop_pool": e.get("drop_pool", []),
	}

func _combat_difficulty() -> int:
	for z in GameData.ZONES:
		if active_id in z.get("enemies", []):
			return int(z.get("difficulty", 1))
	return 1

func _event(text: String, color: String, side: String) -> void:
	combat_events.append({"text": text, "color": color, "side": side, "seq": _event_seq})
	_event_seq += 1
	while combat_events.size() > 14:
		combat_events.pop_front()

func _tick_combat(delta: float) -> void:
	if enemy_inst.is_empty():
		return
	var ss := ship_stats()
	var maxsh := player_max_shield()
	# Heat venting (4x while overloaded / locked; +25% milestone @ combat L75)
	if player_heat > 0.0:
		var vent := VENT_RATE
		if level_of("combat") >= 75:
			vent *= 1.25
		if player_heat > MAX_HEAT or _overheat_lock > 0.0:
			vent *= 4.0
		player_heat = maxf(0.0, player_heat - vent * delta)
	if _overheat_lock > 0.0 and player_heat <= 0.0:
		_overheat_lock = 0.0
	# Shield regen (both sides)
	if player_shield < maxsh:
		player_shield = minf(maxsh, player_shield + float(ss.get("shield_regen", 0.0)) * (1.0 + research_bonus("shield_regen")) * delta)
	if enemy_inst["shield"] < enemy_inst["max_shield"]:
		enemy_inst["shield"] = minf(enemy_inst["max_shield"], enemy_inst["shield"] + minf(enemy_inst["max_shield"] * 0.01, 50.0) * delta)
	# Set bonus: Patient Zero's Strain — hull regen during combat
	if has_set_bonus("patient_zero") and combat_hp < combat_max_hp():
		combat_hp = minf(combat_max_hp(), combat_hp + combat_max_hp() * 0.015 * delta)
	# Player weapons fire on their own intervals (Heat-Sync Focus boosts rate when hot)
	var fire_sf := 1.0 + research_bonus("attack_speed")
	if player_heat >= MAX_HEAT * 0.4:
		fire_sf += affix_total("heat_sync_focus")
	if loadout_has_module("warp_stabilizer"):
		fire_sf += 0.15
	# Broadside Array: periodic heavy kinetic salvo
	if loadout_has_module("broadside_array"):
		_broadside_timer += delta
		if _broadside_timer >= 20.0:
			_broadside_timer = 0.0
			_broadside_fire()
			if active_type != "combat":
				return
	for w in _weapons:
		w["timer"] = float(w["timer"]) + delta * fire_sf
		var guard := 0
		while float(w["timer"]) >= float(w["interval"]) and guard < 20:
			guard += 1
			w["timer"] = float(w["timer"]) - float(w["interval"])
			_player_fire(w, ss)
			if active_type != "combat":
				return
	# Enemy fires on its interval
	# Enemy attack slow: Cryo-Lord set (-15%) and Chrono Stabilizer (-20%)
	var eslow := 1.0
	if has_set_bonus("cryo"):
		eslow *= 0.85
	if loadout_has_module("chrono_stabilizer"):
		eslow *= 0.8
	_enemy_timer += delta * eslow
	var eguard := 0
	while _enemy_timer >= float(enemy_inst["interval"]) and eguard < 20:
		eguard += 1
		_enemy_timer -= float(enemy_inst["interval"])
		_enemy_fire(ss)
		if active_type != "combat":
			return
	# Auto-consumables (repair / shield) when low
	if _consume_cd > 0.0:
		_consume_cd -= delta
	else:
		_check_consume(maxsh)

func _check_consume(maxsh: float) -> void:
	if level_of("combat") < 50:          # auto-consume unlocks at combat L50 (desktop)
		return
	var th := auto_consume_threshold()   # gated by Auto-Repair research
	if th <= 0.0:
		return
	if consumable_hull_slot != "" and amount(consumable_hull_slot) > 0:
		if combat_hp / maxf(1.0, combat_max_hp()) <= th:
			_trigger_consume(consumable_hull_slot)
			return
	if consumable_shield_slot != "" and amount(consumable_shield_slot) > 0 and maxsh > 0.0:
		if player_shield / maxsh <= th:
			_trigger_consume(consumable_shield_slot)

func _trigger_consume(item_id: String) -> void:
	var d: Dictionary = GameData.CONSUMABLES.get(item_id, {})
	if d.is_empty() or amount(item_id) < 1:
		return
	resources[item_id] = amount(item_id) - 1
	_consume_cd = CONSUME_CD
	var pct := float(d.get("heal_pct", 0.0))
	if d.get("type", "hull") == "hull":
		var amt := combat_max_hp() * pct
		combat_hp = minf(combat_max_hp(), combat_hp + amt)
		_event("+%d HP" % int(amt), "5fd585", "player")
	else:
		var amt := player_max_shield() * pct
		player_shield = minf(player_max_shield(), player_shield + amt)
		_event("+%d SHLD" % int(amt), "55d3e6", "player")

func set_ammo(slot: String, ammo_id: String) -> void:
	if ammo_id == "":
		ammo_loadout.erase(slot)
	else:
		ammo_loadout[slot] = ammo_id
	resources_changed.emit()

func set_consumable(kind: String, item_id: String) -> void:
	if kind == "hull":
		consumable_hull_slot = item_id
	else:
		consumable_shield_slot = item_id
	resources_changed.emit()

func _player_fire(w: Dictionary, ss: Dictionary) -> void:
	if _overheat_lock > 0.0:
		return
	var dtot := float(w["dmg_k"]) + float(w["dmg_e"]) + float(w["dmg_x"])
	player_heat += 2.0 + dtot / 100.0
	if player_heat >= MAX_HEAT:
		_overheat_lock = 1.0
		_event("OVERHEAT", "ef9a54", "player")
		return
	var acc := float(ss.get("acc", 15.0))
	var hit := clampf(acc / (acc + float(enemy_inst["eva"])), 0.2, 1.0)
	if randf() > hit:
		_event("MISS", "9aa7c2", "enemy")
		return
	# Ammo: consume one round of the slot's loaded ammo for bonus damage.
	var dk := float(w["dmg_k"])
	var de := float(w["dmg_e"])
	var dx := float(w["dmg_x"])
	if w.get("type", "") == "energy" and loadout_has_module("plasma_overcharger"):
		de *= 2.0   # Plasma Overcharger
	var ammo: String = ammo_loadout.get(w.get("slot", ""), "")
	if ammo != "" and amount(ammo) > 0:
		var ab := ammo_bonus(ammo)
		if ab[0] != "":
			resources[ammo] = amount(ammo) - 1
			match ab[0]:
				"k": dk += ab[1]
				"e": de += ab[1]
				"x": dx += ab[1]
	# Static Burst: chance to reset the enemy's attack timer on hit.
	var sb := affix_total("static_burst")
	if sb > 0.0 and randf() < sb:
		_enemy_timer = 0.0
		_event("SHOCK", "ecb44a", "enemy")
	# Void Strike: chance to bypass the shield entirely.
	var vs := affix_total("void_strike")
	var voided: bool = vs > 0.0 and randf() < vs
	var res := resolve_damage(dk, de, dx, 0.0 if voided else float(enemy_inst["shield"]), enemy_inst["def"], _combat_difficulty(), float(ss.get("crit", 0.05)))
	if voided:
		_event("VOID", "ff44cc", "enemy")
	else:
		enemy_inst["shield"] = maxf(0.0, enemy_inst["shield"] - res[0])
	enemy_inst["hp"] -= res[1]
	if res[0] > 0:
		_event("-%d" % int(res[0]), "55d3e6", "enemy")
	if res[1] > 0:
		_event(("CRIT %d" % int(res[1])) if res[2] else ("-%d" % int(res[1])), "ecb44a" if res[2] else "ef6a52", "enemy")
	if enemy_inst["hp"] <= 0.0:
		_win_combat()

func _enemy_fire(ss: Dictionary) -> void:
	var eva := float(ss.get("eva", 0.0))
	var e_acc := float(enemy_inst["acc"])
	var dodge := minf(eva / (eva + 150.0 * (1.0 + e_acc / 100.0)), 0.75)
	if randf() < dodge:
		_event("DODGE", "9aa7c2", "player")
		return
	var pdef := float(ss.get("def", 0.0))
	if loadout_has_module("reactive_armor"):
		pdef *= 1.0 + (1.0 - combat_hp / maxf(1.0, combat_max_hp()))   # Reactive Armor
	var res := resolve_damage(float(enemy_inst["atk"]), 0.0, 0.0, player_shield, pdef, _combat_difficulty(), 0.05)
	# Exotic Shield Matrix: 30% damage reduction in Sector Gamma
	if loadout_has_module("exotic_shield_matrix") and _current_zone_id() == "sector_gamma":
		res[1] = int(res[1] * 0.7)
	# Set bonus: Sovereign's Prism — 15% chance to fully reflect incoming damage
	if has_set_bonus("sovereign") and randf() < 0.15:
		var refl: float = res[0] + res[1]
		enemy_inst["hp"] -= refl
		_event("REFLECT %d" % int(refl), "ff44cc", "enemy")
		if enemy_inst["hp"] <= 0.0:
			_win_combat()
		return
	# Reflective Sheath: 20% chance to reflect 50% back (player still takes the hit)
	if loadout_has_module("reflective_sheath") and randf() < 0.20:
		enemy_inst["hp"] -= int((res[0] + res[1]) * 0.5)
		_event("REFL", "9aa7c2", "enemy")
	player_shield = maxf(0.0, player_shield - res[0])
	combat_hp -= res[1]
	if res[0] > 0:
		_event("-%d" % int(res[0]), "55d3e6", "player")
	if res[1] > 0:
		_event("-%d" % int(res[1]), "ef6a52", "player")
	if combat_hp <= 0.0:
		_lose_combat()

## Broadside Array: a heavy kinetic salvo (5x equipped kinetic damage).
func _broadside_fire() -> void:
	var total_k := 0.0
	for w in _weapons:
		if w["type"] == "kinetic":
			total_k += float(w["dmg_k"])
	if total_k <= 0.0:
		return
	var res := resolve_damage(total_k * 5.0, 0.0, 0.0, float(enemy_inst["shield"]), enemy_inst["def"], _combat_difficulty(), 0.10)
	enemy_inst["shield"] = maxf(0.0, enemy_inst["shield"] - res[0])
	enemy_inst["hp"] -= res[1]
	_event("BROADSIDE %d" % int(res[0] + res[1]), "ecb44a", "enemy")
	if enemy_inst["hp"] <= 0.0:
		_win_combat()

## Damage-type resolution: kinetic/energy/explosive vs shields then armor.
func resolve_damage(atk_k: float, atk_e: float, atk_x: float, c_shield: float, c_armor: float, difficulty: int, crit_chance: float) -> Array:
	var shield_pot := atk_k * 0.5 + atk_e * 1.5 + atk_x * 1.1
	var dmg_shield := minf(c_shield, shield_pot)
	var bleed := (shield_pot - dmg_shield) / shield_pot if shield_pot > 0.0 else 1.0
	var k := maxf(20.0, float(difficulty) * 50.0)
	var hk := atk_k * 1.2 * (1.0 - c_armor / (c_armor + k))
	var he := atk_e * 0.9 * (1.0 - (c_armor * 0.7) / (c_armor * 0.7 + k))
	var hx := atk_x * 1.0 * (1.0 - (c_armor * 0.2) / (c_armor * 0.2 + k))
	var hull := (hk + he + hx) * bleed
	var variance := randf_range(0.9, 1.1)
	var is_crit := randf() < crit_chance
	if is_crit:
		variance *= 1.5
	var minhull := 1.0 if (atk_k + atk_e + atk_x) > 0.0 else 0.0
	return [dmg_shield * variance, maxf(minhull, hull * variance), is_crit]

func _win_combat() -> void:
	_roll_loot(enemy_inst["loot"], 1.0)
	add_xp("combat", int(enemy_inst["xp"] * (1.0 + research_bonus("combat_xp"))))
	bounty_on_kill(active_id)
	_mission_event("defeat", active_id, 1)
	_event("DESTROYED", "5fd585", "enemy")
	# On-kill affixes
	var cap := minf(affix_total("capacitor_pulse"), 0.30)
	if cap > 0.0:
		player_shield = minf(player_max_shield(), player_shield + player_max_shield() * cap)
	var nan := minf(affix_total("nanite_resurgence"), 0.30)
	if nan > 0.0:
		combat_hp = minf(combat_max_hp(), combat_hp + combat_max_hp() * nan)
	var scav := affix_total("nano_scavenger")
	if scav > 0.0 and randf() < scav:
		var parts := ["Circuit", "Chip", "AdvCircuit"]
		var p: String = parts[randi() % parts.size()]
		add_resource(p, 1 + int(_combat_difficulty() / 3.0))
		_event("SCAVENGED " + GameData.res_name(p), "55d3e6", "enemy")
	# Rolled module drop (rarity + affixes)
	var dc: float = float(enemy_inst.get("drop_chance", 0.0)) * (1.0 + research_bonus("xeno_engineering"))
	if enemy_inst.get("elite", false):
		dc = minf(1.0, dc * 3.0)
	if dc > 0.0 and randf() < dc:
		var pool := []
		for mid in enemy_inst.get("drop_pool", []):
			if GameData.MODULES.has(mid) and module_unlocked(mid):
				pool.append(mid)
		if not pool.is_empty():
			var base_id: String = pool[randi() % pool.size()]
			var rarity := roll_rarity(enemy_inst.get("elite", false))
			var cid := generate_module(base_id, rarity, _combat_difficulty())
			if cid != "":
				_event("%s DROP" % (RARITY_LABEL[rarity] if rarity > 0 else "MODULE").to_upper(), RARITY_COLOR.get(rarity, "b78ae8"), "enemy")
	# Set-piece drop: bosses drop their themed set pieces (8% chance).
	for sn in GameData.SETS:
		var sd: Dictionary = GameData.SETS[sn]
		if sd.get("boss", "") == active_id and randf() < 0.08:
			var pieces: Array = sd.get("pieces", [])
			if not pieces.is_empty():
				_grant_set_piece(pieces[randi() % pieces.size()])
				_event("SET PIECE!", "ff44cc", "enemy")
			break
	# Gem drop (rare; quality scales with zone difficulty).
	if randf() < 0.03:
		var diff := _combat_difficulty()
		var tier := "Cracked" if diff < 4 else ("Stable" if diff < 8 else "Pristine")
		var colors := ["Crimson", "Cobalt", "Topaz", "Amethyst"]
		var gid := "%s%sCore" % [tier, colors[randi() % colors.size()]]
		if GameData.GEMS.has(gid):
			add_resource(gid, 1)
			_event("GEM: " + GameData.GEMS[gid]["name"], "3a9fff", "enemy")
	_spawn_enemy_inst(active_id)   # auto re-engage (idle farming)

func _lose_combat() -> void:
	var cost := mini(repair_cost(), credits)   # repair fee on defeat (capped at available credits)
	credits -= cost
	combat_hp = combat_max_hp()
	player_shield = 0.0
	_event("HULL BREACH  −₡%s" % GameData.fmt(cost), "ef6a52", "player")
	stop_task()

func _offline_combat(delta: float) -> void:
	var e: Dictionary = GameData.ENEMIES.get(active_id, {})
	if e.is_empty():
		return
	var diff := _combat_difficulty()
	var k := maxf(20.0, float(diff) * 50.0)
	var pdps := avg_player_dps() * (1.0 - float(e.get("def", 0)) / (float(e.get("def", 0)) + k))
	pdps = maxf(1.0, pdps)
	var ehp := float(e.get("hp", 10)) + float(e.get("max_shield", 0))
	var kill_time := ehp / pdps
	if kill_time <= 0.0:
		return
	var reps := int(delta / kill_time)
	if reps <= 0:
		return
	var pdef := float(ship_stats().get("def", 0.0))
	var edps := float(e.get("atk", 0)) / maxf(0.5, float(e.get("interval", 2.5))) * (1.0 - pdef / (pdef + k))
	var sustain := combat_max_hp() * HP_REGEN + float(ship_stats().get("shield_regen", 0.0))
	if edps > sustain:
		return   # not survivable unattended
	var summary := _offline_loot(e.get("loot", []), 1.0, reps)
	add_xp("combat", int(e.get("xp", 0)) * reps)
	combat_hp = combat_max_hp()
	player_shield = player_max_shield()
	pending_offline = "Away for %s\n\nDestroyed %d %s\n%s\n+%d Combat XP" % [_fmt_time(delta), reps, e.get("name", ""), summary, int(e.get("xp", 0)) * reps]

func current_duration() -> float:
	return effective_duration(active_type, active_id)

func effective_duration(type: String, id: String) -> float:
	if type == "gather" and GameData.GATHER.has(id):
		return float(GameData.GATHER[id].get("duration", 4.0)) / gather_speed_mult(id)
	elif type == "craft" and GameData.CRAFT.has(id):
		return float(GameData.CRAFT[id].get("duration", 4.0)) / recipe_speed_mult(id)
	return 0.0

# Per-action gathering speed techs (ported from gathering_manager.get_action_speed_multiplier)
const GATHER_SPEED_TECH := {
	"gather_dirt": [["diamond_drills", 0.50], ["ultrasonic_drills", 0.50], ["plasma_bore", 0.75]],
	"collect_water": [["high_flow_pumps", 0.50], ["superfluid_intake", 0.50], ["hydro_vortex", 0.75]],
	"gather_wood": [["laser_cutters", 0.50], ["mono_filament", 0.50], ["molecular_disassembler", 0.75]],
	"harvest_nebula": [["magnetic_funnels", 0.25]],
}

func gather_speed_mult(id: String) -> float:
	var m := 1.0
	for row in GATHER_SPEED_TECH.get(id, []):
		if is_research_unlocked(row[0]):
			m += float(row[1])
	m += building_count("biosphere_dome") * 0.05           # Biosphere Dome: +5% gather speed/bldg
	return m * warp_gathering_mult()                       # prestige boosts gather via speed

# Per-recipe processing speed techs (ported from processing_manager.get_recipe_speed_multiplier)
const RECIPE_SPEED_TECH := {
	"centrifuge_dirt": [["fast_centrifuges", 0.25], ["maglev_bearings", 0.50], ["quantum_separators", 0.75]],
	"electrolysis": [["catalytic_electrodes", 0.25], ["ion_exchange", 0.50], ["resonance_splitters", 0.75]],
	"charcoal_burning": [["pyrolysis_control", 0.25]],
	"smelt_steel_basic": [["blast_furnace", 0.25]],
	"smelt_steel_oxygen": [["blast_furnace", 0.25]],
	"press_graphite": [["hydraulic_press", 0.25]],
}

func recipe_speed_mult(id: String) -> float:
	var m := 1.0 + level_of("fabrication") * 0.01           # +1% Engineering / level
	for row in RECIPE_SPEED_TECH.get(id, []):
		if is_research_unlocked(row[0]):
			m += float(row[1])
	m += research_bonus("processing_speed")                 # nano_fabrication / perfect_automation
	m += research_bonus("industrial_logistics")             # hub +10%
	m += affix_total("refinery_link")                       # module affix
	# Infrastructure speed buildings
	if int(buildings.get("fabricator", 0)) > 0: m += 0.20
	if int(buildings.get("catalyst_chamber", 0)) > 0: m += 0.25
	if int(buildings.get("silver_catalyst_bay", 0)) > 0: m += 0.15
	if level_of("fabrication") >= 10: m *= 1.10             # milestone 10
	if level_of("fabrication") >= 25: m *= 1.11             # milestone 25
	return m

func _tick_active(delta: float) -> void:
	if active_type == "":
		return
	if active_type == "combat":
		_tick_combat(delta)
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
func _roll_loot(loot: Array, mult: float, flat: int = 0) -> void:
	for row in loot:
		if randf() < float(row[1]):
			var amt := maxi(1, int(round((randi_range(int(row[2]), int(row[3])) + flat) * mult)))
			if row[0] == "credits":
				gain_credits(amt)
				resources_changed.emit()
			else:
				add_resource(row[0], amt)

func _loot_snapshot(items) -> Dictionary:
	var snap := {}
	for it in items:
		var sym = it[0] if it is Array else it
		snap[sym] = amount(sym)
	return snap

## Surface the single largest gain from the just-completed action as floating text.
func _emit_reward(before: Dictionary, items) -> void:
	var best := ""
	var bestg := 0
	for it in items:
		var sym = it[0] if it is Array else it
		if sym == "credits":
			continue
		var g := amount(sym) - int(before.get(sym, 0))
		if g > bestg:
			bestg = g
			best = sym
	if best != "":
		action_reward.emit("+%s %s" % [GameData.fmt(bestg), GameData.res_name(best)], RESOURCES_COLOR(best))

func RESOURCES_COLOR(sym: String) -> String:
	return GameData.RESOURCES.get(sym, {}).get("color", "5fd585")

func _complete_active() -> void:
	if active_type == "gather":
		var a: Dictionary = GameData.GATHER[active_id]
		var before := _loot_snapshot(a.get("loot", []))
		_roll_loot(a.get("loot", []), yield_mult("harvesting"), int(research_bonus("gathering_yield")))
		_emit_reward(before, a.get("loot", []))
		add_xp("harvesting", int(a.get("xp", 0)))
	elif active_type == "craft":
		var r: Dictionary = GameData.CRAFT[active_id]
		if not can_afford(r.get("inputs", {})):
			stop_task()
			return
		spend(r.get("inputs", {}))
		var before := _loot_snapshot(r.get("outputs", {}).keys())
		_grant_craft_outputs(active_id, r, 1)
		_emit_reward(before, r.get("outputs", {}).keys())
		add_xp("fabrication", int(r.get("xp", 0)))

## Grants a recipe's outputs for `count` completions, applying the same yield
## rules as the desktop processing_manager: efficiency multiplier (2–32×),
## oxygen-blast-furnace ×5 Steel, milestone-50 5% double, plus the bonus table
## (efficiency-scaled, with scrap-recycling extra rolls).
func _grant_craft_outputs(rid: String, r: Dictionary, count: int) -> void:
	var eff := research_efficiency_mult()
	var oxy_steel: bool = is_research_unlocked("oxygen_blast_furnace")
	var m50 := level_of("fabrication") >= 50
	for sym in r.get("outputs", {}):
		var per := float(r["outputs"][sym])
		if sym == "Steel" and oxy_steel:
			per *= 5.0
		per *= eff
		var total := per * count
		if m50:                                            # 5% chance per unit to double
			var doubles := 0
			for _i in range(mini(count, 4096)):
				if randf() < 0.05:
					doubles += 1
			total += per * doubles
		add_resource(sym, int(round(total)))
	# Bonus / output table — efficiency-scaled, scrap recycling adds rolls.
	var rolls := 1
	if rid == "recycle_scrap":
		rolls += int(research_bonus("scrap_rolls"))
	for _r in range(rolls):
		for _c in range(count):
			_roll_loot(r.get("bonus", []), eff)

# ---------------- Offline ----------------
func _apply_offline(delta: float) -> void:
	if active_type == "" or delta < 5.0:
		return
	if active_type == "combat":
		if offline_combat:
			_offline_combat(delta)
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
		var before := {}
		for sym in r.get("outputs", {}):
			before[sym] = amount(sym)
		_grant_craft_outputs(active_id, r, count)
		var summary := ""
		for sym in r.get("outputs", {}):
			var made := amount(sym) - int(before[sym])
			summary += "\n+%s %s" % [GameData.fmt(made), GameData.res_name(sym)]
		add_xp("fabrication", int(r.get("xp", 0)) * count)
		pending_offline = "Away for %s\n%s\n+%d Fabrication XP" % [_fmt_time(delta), summary, int(r.get("xp", 0)) * count]

func _offline_loot(loot: Array, mult: float, reps: int) -> String:
	var s := ""
	for row in loot:
		var avg: float = (int(row[2]) + int(row[3])) / 2.0 * float(row[1])
		var got := int(round(avg * mult * reps))
		if got > 0:
			if row[0] == "credits":
				gain_credits(got)
				s += "+₡%s  " % GameData.fmt(got)
			else:
				add_resource(row[0], got)
				s += "+%s %s  " % [GameData.fmt(got), GameData.res_name(row[0])]
	return s

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
		"lifetime_credits": lifetime_credits,
		"storage_upgrades": storage_upgrades,
		"repeatable_research": repeatable_research,
		"offline_combat": offline_combat,
		"warp_shards": warp_shards,
		"total_warps": total_warps,
		"credits_at_warp_start": credits_at_warp_start,
		"skills": skills,
		"research": unlocked_research.keys(),
		"active_type": active_type,
		"active_id": active_id,
		"progress": progress,
		"combat_hp": combat_hp,
		"active_hull": active_hull,
		"owned_hulls": owned_hulls.keys(),
		"module_inventory": module_inventory,
		"custom_modules": custom_modules,
		"loadout": loadout,
		"ammo_loadout": ammo_loadout,
		"consumable_hull_slot": consumable_hull_slot,
		"consumable_shield_slot": consumable_shield_slot,
		"buildings": buildings,
		"building_throttle": building_throttle,
		"infra_energy": infra_energy,
		"bounty_available": bounty_available,
		"bounty_active": bounty_active,
		"bounty_refresh_timer": bounty_refresh_timer,
		"bounty_total": bounty_total,
		"bounty_id": _bounty_id,
		"missions_active": missions_active.keys(),
		"missions_progress": missions_progress,
		"missions_claimed": missions_claimed.keys(),
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
	lifetime_credits = int(data.get("lifetime_credits", credits))
	storage_upgrades = int(data.get("storage_upgrades", 0))
	repeatable_research = data.get("repeatable_research", {})
	offline_combat = bool(data.get("offline_combat", false))
	for k in repeatable_research:
		repeatable_research[k] = int(repeatable_research[k])
	warp_shards = float(data.get("warp_shards", 0.0))
	total_warps = int(data.get("total_warps", 0))
	credits_at_warp_start = int(data.get("credits_at_warp_start", 0))
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
	custom_modules = data.get("custom_modules", {})
	ammo_loadout = data.get("ammo_loadout", {})
	consumable_hull_slot = data.get("consumable_hull_slot", "")
	consumable_shield_slot = data.get("consumable_shield_slot", "")
	loadout = data.get("loadout", {})
	buildings = data.get("buildings", {})
	for k in buildings:
		buildings[k] = int(buildings[k])
	building_throttle = data.get("building_throttle", {})
	infra_energy = float(data.get("infra_energy", 0.0))
	bounty_available = data.get("bounty_available", [])
	bounty_active = data.get("bounty_active", [])
	bounty_refresh_timer = float(data.get("bounty_refresh_timer", 0.0))
	bounty_total = int(data.get("bounty_total", 0))
	_bounty_id = int(data.get("bounty_id", 0))
	missions_active = {}
	for mid in data.get("missions_active", []):
		missions_active[mid] = true
	missions_progress = data.get("missions_progress", {})
	for k in missions_progress:
		missions_progress[k] = int(missions_progress[k])
	missions_claimed = {}
	for mid in data.get("missions_claimed", []):
		missions_claimed[mid] = true
	_mission_sync()   # reconcile active missions with already-satisfied state on load
	var last := float(data.get("time", Time.get_unix_time_from_system()))
	var away := Time.get_unix_time_from_system() - last
	_apply_offline(away)
	var infra_report := _offline_infra(away)   # buildings keep producing while away
	if infra_report != "":
		if pending_offline == "":
			pending_offline = "Away for %s\n\n%s" % [_fmt_time(away), infra_report]
		else:
			pending_offline += "\n" + infra_report
	# Re-arm the live duel if a combat task was active (transient state isn't saved).
	if active_type == "combat":
		if GameData.ENEMIES.has(active_id):
			_init_combat(active_id)
		else:
			active_type = ""
			active_id = ""
	resources_changed.emit()
	skills_changed.emit()
	research_changed.emit()
	action_changed.emit()

func hard_reset() -> void:
	resources = {}
	credits = 0
	lifetime_credits = 0
	warp_shards = 0.0
	total_warps = 0
	credits_at_warp_start = 0
	skills = {"harvesting": 0, "fabrication": 0, "combat": 0, "infrastructure": 0}
	unlocked_research = {}
	buildings = {}
	building_throttle = {}
	infra_energy = 0.0
	storage_upgrades = 0
	repeatable_research = {}
	_build_timers = {}
	_build_frac = {}
	active_hull = "corvette_hull"
	owned_hulls = {"corvette_hull": true}
	module_inventory = {}
	custom_modules = {}
	loadout = {}
	ammo_loadout = {}
	consumable_hull_slot = ""
	consumable_shield_slot = ""
	bounty_available = []
	bounty_active = []
	bounty_refresh_timer = 0.0
	bounty_total = 0
	missions_active = {}
	missions_progress = {}
	missions_claimed = {}
	_mission_init()
	pending_offline = ""
	player_shield = 0.0
	player_heat = 0.0
	enemy_inst = {}
	combat_hp = combat_max_hp()
	stop_task()
	generate_bounty_pool()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	resources_changed.emit()
	skills_changed.emit()
	research_changed.emit()
