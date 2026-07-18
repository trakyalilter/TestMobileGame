extends Skill

# We assume GameState is a global Autoload or accessible static
# If not, we might need to pass it, but RefCounted doesn't support convenient dependency injection 
# without custom init. We'll use the Autoload 'GameState'.

var is_active: bool = false
var current_action: Dictionary = {}
var current_action_id: String = ""
var action_progress: float = 0.0
# v132: the cached `action_duration` member is GONE. It was set only in
# start_action, so a save/load resume (which restores current_action directly,
# never via start_action) left it at its stale 4.0 default — the tick then
# completed on 4.0s while the UI showed the action's real duration (bar fills →
# hangs at 100% → resets, every cycle). All paths now read
# current_action["duration"] live, exactly like processing_manager.

var events: Array = [] # Buffer for UI

# P1 Mastery — per-action long-tail layered learning. Each gather action
# accumulates its own XP; milestones at 10/25/50/75/100 grant cumulative
# duration reductions (capped at 30%). Lv 50 is a "big-step" milestone
# (+10% in one shot, not +5%) — replaces the v1 alt-recipe unlock with raw
# speed so the long-grind midpoint still feels like a reward, not just
# another linear step. Lv 100 caps with a Hearthstone-style gold cosmetic.
# Persists across warps (true meta-progression); cleared only on hard reset.
const MASTERY_XP_PER_COMPLETION := 1.0
const MASTERY_MILESTONES: Array[int] = [10, 25, 50, 75, 100]
# v109: per-milestone cumulative bonus table (was a flat 5% step). Index =
# number of milestones passed (0..5). Lv 50 (index 3) jumps +10% instead of
# the prior +5% so the midpoint reads as a real reward.
const MASTERY_DURATION_BONUS_TABLE: Array[float] = [0.0, 0.05, 0.10, 0.20, 0.25, 0.30]
const MASTERY_DURATION_BONUS_MAX := 0.30
const MASTERY_LEVEL_CAP := 100

var mastery: Dictionary = {}  # {action_id: xp_total_float}

var actions: Dictionary = {
	"gather_dirt": {
		"name": "Excavate Soil",
		"loot_table": [["Dirt", 1.0, 8, 20]],
		"xp": 12,
		"level_req": 1,
		"category": "terrestrial",
		"duration": 3.0
	},
	# v62.0 Fix: Added Manganese source (Gathering)
	"extract_manganese": {
		"name": "Extract Manganese",
		"loot_table": [["Mn", 1.0, 1, 2], ["Fe", 0.5, 1, 2]],
		"xp": 18,
		"level_req": 15,
		"research_req": "adv_materials",
		"category": "terrestrial"
	},
	"collect_water": {
		"name": "Pump Water",
		"loot_table": [["Water", 1.0, 8, 20]],
		"xp": 15,
		"level_req": 2,
		"research_req": "basic_engineering",
		"category": "terrestrial"
	},
	"mine_cassiterite": {
		"name": "Mine Cassiterite",
		"loot_table": [["Cassiterite", 1.0, 1, 2]],
		"xp": 20,
		"level_req": 8,
		"research_req": "basic_engineering",
		"category": "terrestrial"
	},
	"gather_wood": {
		"name": "Deforest Zone",
		"loot_table": [["Wood", 1.0, 8, 10]],
		"xp": 10,
		"level_req": 4,
		"category": "terrestrial"
	},
	"mine_dolomite": {
		"name": "Quarry Dolomite",
		"loot_table": [["Dolomite", 1.0, 1, 3], ["Dirt", 0.5, 1, 2]],
		"xp": 18,
		"level_req": 15,
		"research_req": "adv_materials",
		"category": "terrestrial"
	},
	"mine_bauxite": {
		"name": "Strip Mine Bauxite",
		"loot_table": [["Bauxite", 1.0, 1, 2]],
		"xp": 11,
		"level_req": 12,
		"research_req": "lightweight_alloys",
		"category": "terrestrial"
	},
	# v62.0 Fix: Added Pentlandite source (Gathering)
	"extract_pentlandite": {
		"name": "Extract Pentlandite",
		"loot_table": [["Pentlandite", 1.0, 1, 2], ["Fe", 0.5, 1, 2]],
		"xp": 25,
		"level_req": 25,
		"research_req": "adv_materials",
		"category": "terrestrial"
	},
	# v62.0 Fix: Added Chromite source (Gathering)
	"extract_chromite": {
		"name": "Extract Chromite",
		"loot_table": [["Chromite", 1.0, 1, 2], ["Fe", 0.5, 1, 2]],
		"xp": 30,
		"level_req": 30,
		"research_req": "adv_materials",
		"category": "terrestrial"
	},
	"extract_salts": {
		"name": "Mine Lithium Ore",
		"loot_table": [["Spodumene", 1.0, 1, 3]],
		"xp": 10,
		"level_req": 6,
		"research_req": "basic_engineering",
		"category": "terrestrial"
	},
	"mine_zinc_ore": {
		"name": "Extract Zinc Ore",
		"loot_table": [["ZincOre", 1.0, 1, 3], ["Si", 0.4, 1, 1]],
		"xp": 25,
		"level_req": 25,
		"research_req": "smelting",
		"category": "terrestrial"
	},
	"mine_malachite": {
		"name": "Extract Malachite",
		"loot_table": [["Malachite", 1.0, 8, 10]],
		"xp": 14,
		"level_req": 7,
		"research_req": "basic_engineering",
		"category": "terrestrial"
	},
	"mine_quartz": {
		"name": "Collect Quartz Clusters",
		"loot_table": [["Quartz", 1.0, 1, 3]],
		"xp": 22,
		"level_req": 22,
		"research_req": "adv_materials", # Audit v43.0: Added missing research gate
			"category": "terrestrial"
		},
	"harvest_nebula": {
		"name": "Harvest Nebula",
		"loot_table": [
			["H", 1.0, 1, 2],
			["He", 1.0, 1, 1]
		],
		"xp": 15, # ITER3 FIX: Reduced from 60 (was 4x higher than intended)
		"level_req": 40,
		"research_req": "energy_metrics",
		"category": "orbital"
	},
	"mine_germanit": {
		"name": "Excavate Germanite Deposits",
		"loot_table": [["Germanit", 1.0, 1, 2]],
		"xp": 35,
		"level_req": 35,
		"category": "terrestrial"
	},
	# v80.4 Fix: Tungsten had no early source (only late-game infrastructure drill)
	"mine_tungsten": {
		"name": "Tungsten Vein Mining",
		"loot_table": [["W", 1.0, 1, 2], ["Fe", 0.3, 1, 2]],
		"xp": 30,
		"level_req": 20,
		"research_req": "smelting",
		"category": "terrestrial"
	},
	"extract_platinum": {
		"name": "Extract Platinum samples",
		"loot_table": [["PtOre", 1.0, 1, 3], ["Ti", 0.2, 1, 2]],
		"xp": 80,
		"level_req": 45,
		"research_req": "precious_metal_refining",
		"category": "orbital"
	},
	"mine_iridium": {
		"name": "Mine Iridium Crystals",
		"loot_table": [["Ir", 1.0, 1, 2], ["PtOre", 0.3, 1, 1]],
		"xp": 150,
		"level_req": 60,
		"research_req": "iridium_metallurgy",
		"category": "void"
	},
	"harvest_osmium": {
		"name": "Condense Osmium Vapor",
		"loot_table": [["Os", 1.0, 1, 1], ["Ir", 0.2, 1, 1]],
		"xp": 300,
		"level_req": 75,
		"research_req": "exotic_metallurgy",
		"category": "void"
	},
	# Audit v6.0 P1-20: Endgame Gathering Actions
	"harvest_void_essence": {
		"name": "Harvest Void Essence",
		"loot_table": [["VoidEssence", 1.0, 1, 2]],
		"xp": 500,
		"level_req": 85,
		"research_req": "void_navigation",
		"category": "void"
	},
	"extract_chrono_crystals": {
		"name": "Extract Chrono Crystals",
		"loot_table": [["ChronoCore", 1.0, 1, 1], ["VoidEssence", 0.3, 1, 1]],
		"xp": 800,
		"level_req": 92,
		"research_req": "void_navigation",
		"category": "void"
	}
}

func _init():
	super._init("Planetary Operations")

# --- P1 Mastery helpers ---
# XP curve: 25 + (next_level × 5) per level. Total to 100 ≈ 27,000 XP,
# i.e. multi-day per maxed action — matches the Melvor-like prestige arc.
func _mastery_xp_needed_for_level(target: int) -> float:
	# Returns XP required to *reach* level `target` from level (target-1).
	if target <= 0 or target > MASTERY_LEVEL_CAP:
		return 0.0
	return float(25 + target * 5)

func gain_mastery_xp(action_id: String, amount: float = MASTERY_XP_PER_COMPLETION) -> void:
	if action_id == "" or amount <= 0.0:
		return
	# v107: First-encounter intro — fires once per save when ANY mastery XP
	# is first awarded. Tells the player Mastery exists and points them at
	# the bar's tooltip for the full schedule. Without this the system is
	# silent; the bar exists but a new player has no idea what it does.
	if not GameState.game_settings.get("mastery_intro_seen", false):
		GameState.game_settings["mastery_intro_seen"] = true
		UITheme.show_notification(
			tr("MASTERY UNLOCKED — Keep using actions for permanent speed bonuses. Hover the mastery bar for the milestone schedule."),
			Color(1.0, 0.84, 0.45)
		)
	var prev_level: int = get_mastery_level(action_id)
	mastery[action_id] = float(mastery.get(action_id, 0.0)) + amount
	var new_level: int = get_mastery_level(action_id)
	if new_level > prev_level:
		_notify_mastery_milestones(action_id, prev_level, new_level)

func get_mastery_xp(action_id: String) -> float:
	return float(mastery.get(action_id, 0.0))

func get_mastery_level(action_id: String) -> int:
	var xp: float = get_mastery_xp(action_id)
	var level: int = 0
	var threshold: float = 0.0
	while level < MASTERY_LEVEL_CAP:
		var needed: float = _mastery_xp_needed_for_level(level + 1)
		if xp < threshold + needed:
			break
		threshold += needed
		level += 1
	return level

# Returns {in_level: float, needed: float, at_cap: bool} for UI progress bars.
func get_mastery_progress(action_id: String) -> Dictionary:
	var xp: float = get_mastery_xp(action_id)
	var level: int = get_mastery_level(action_id)
	if level >= MASTERY_LEVEL_CAP:
		return {"in_level": xp, "needed": 0.0, "at_cap": true}
	var threshold: float = 0.0
	for n in range(1, level + 1):
		threshold += _mastery_xp_needed_for_level(n)
	var next_req: float = _mastery_xp_needed_for_level(level + 1)
	return {"in_level": xp - threshold, "needed": next_req, "at_cap": false}

# Returns the duration multiplier (1.0 = full duration, 0.70 = 30% faster).
# Used by get_action_speed_multiplier to turn it into a speed boost.
# v109: table-driven so Lv 50 can be a +10% "big-step" milestone (replacing
# the cut alt-recipe unlock) without retrofitting every call site.
func get_mastery_duration_mult(action_id: String) -> float:
	var level: int = get_mastery_level(action_id)
	var milestones_passed: int = 0
	for m in MASTERY_MILESTONES:
		if level >= m:
			milestones_passed += 1
	var idx: int = clamp(milestones_passed, 0, MASTERY_DURATION_BONUS_TABLE.size() - 1)
	var reduction: float = MASTERY_DURATION_BONUS_TABLE[idx]
	return 1.0 - reduction

func is_mastery_alt_unlocked(action_id: String) -> bool:
	return get_mastery_level(action_id) >= 50

# Infra↔Mastery link: first action whose PRIMARY loot (first entry) is `symbol`.
# Lets extraction buildings attribute to the gathering action's Mastery.
func get_action_id_for_output(symbol: String) -> String:
	for aid in actions:
		var lt = actions[aid].get("loot_table", [])
		if lt is Array and lt.size() > 0 and lt[0] is Array and lt[0].size() > 0:
			if String(lt[0][0]) == symbol:
				return aid
	return ""

# P1.3 Alt-recipe framework — returns the configured alt-recipe id for this
# action IF mastery is unlocked AND the action has an `alt_recipe_id` field.
# Content (per-action alt-recipes) is backfilled separately; until an action
# defines `alt_recipe_id`, this returns "" and the toggle never surfaces.
# The plumbing being live means content additions are pure data, no code.
func get_alt_recipe_id_for(action_id: String) -> String:
	if not is_mastery_alt_unlocked(action_id):
		return ""
	return actions.get(action_id, {}).get("alt_recipe_id", "")

func _notify_mastery_milestones(action_id: String, prev_level: int, new_level: int) -> void:
	# v110: uniform message format across all milestones. Lv 50 jump and
	# Lv 100 cap are visible from the % itself + the card's tint shift —
	# we don't shout "Big Step" or "Gold Tier" in the toast.
	var action_name: String = actions.get(action_id, {}).get("name", action_id)
	for m in MASTERY_MILESTONES:
		if prev_level < m and new_level >= m:
			var idx: int = MASTERY_MILESTONES.find(m) + 1
			var pct: int = int(round(MASTERY_DURATION_BONUS_TABLE[idx] * 100.0))
			var msg: String = tr("%s — Mastery %d · −%d%% Duration") % [action_name, m, pct]
			UITheme.show_notification(msg, Color(1.0, 0.84, 0.45))

# Audit v6.0 P1-19: Planetary Operations skill bonus - +1% yield per level
func get_yield_multiplier() -> float:
	var mult = 1.0 + (get_level() * 0.01)
	if is_milestone_unlocked(10): mult *= 1.10 # +10% Yield
	
	# v72.8: Trophy Buffs
	if GameState.bounty_manager:
		mult *= GameState.bounty_manager.get_trophy_buff("mining_yield")
		
	# Efficiency Research Branch
	if GameState.research_manager:
		mult *= GameState.research_manager.get_efficiency_multiplier()

	# v107: Warp Mastery Tree — E1 Yield Calibration (+10% gathering yield)
	if GameState.warp_manager:
		mult *= GameState.warp_manager.get_tree_gathering_bonus()

	return mult

func get_action_speed_multiplier(action_id: String) -> float:
	var multiplier = 1.0
	
	# Structure: action_id: [{tech_id: "xxx", bonus: 0.25}, ...]
	var upgrades_db = {
		"gather_dirt": [
			{"id": "diamond_drills", "bonus": 0.50},
			{"id": "ultrasonic_drills", "bonus": 0.50},
			{"id": "plasma_bore", "bonus": 0.75}
		],
		"collect_water": [
			{"id": "high_flow_pumps", "bonus": 0.50},
			{"id": "superfluid_intake", "bonus": 0.50},
			{"id": "hydro_vortex", "bonus": 0.75}
		],
		"gather_wood": [
			{"id": "laser_cutters", "bonus": 0.50},
			{"id": "mono_filament", "bonus": 0.50},
			{"id": "molecular_disassembler", "bonus": 0.75}
		],
		"harvest_nebula": [
			{"id": "magnetic_funnels", "bonus": 0.25}
		]
	}
	
	if action_id in upgrades_db:
		for upgrade in upgrades_db[action_id]:
			if GameState.research_manager and GameState.research_manager.is_tech_unlocked(upgrade["id"]):
				multiplier += upgrade["bonus"]
	
	# Audit v2.0 P1-9: Apply prestige gathering multiplier globally so UI can see it
	if GameState.warp_manager:
		multiplier *= GameState.warp_manager.get_gathering_multiplier()

	# P1 Mastery: per-action duration reduction. Returns 1.0 → 0.75 (max).
	# Inverting to a speed factor (1/dur) keeps the existing "effective_duration
	# = base / multiplier" math intact.
	var dur_mult: float = get_mastery_duration_mult(action_id)
	if dur_mult > 0.0:
		multiplier /= dur_mult

	return multiplier

func start_action(action_id: String):
	if action_id in actions:
		var action = actions[action_id]
		
		var lvl = get_level()
		var req = action.get("level_req", 1)
		
		if lvl < req:
			print("Level too low.")
			return
		
		# Research
		var res_req = action.get("research_req")
		if res_req and not GameState.research_manager.is_tech_unlocked(res_req):
			print("Research required: ", res_req)
			return
		
		current_action = action
		current_action_id = action_id
		action_progress = 0.0
		is_active = true

func stop_action():
	is_active = false
	current_action = {}
	current_action_id = ""
	action_progress = 0.0

func reset(decay_factor: float = 1.0) -> void:
	super.reset(decay_factor)
	stop_action()
	# P1 Mastery is true meta-progression — persists across warp (decay_factor<1.0)
	# and clears only on hard reset (decay_factor==1.0).
	if decay_factor >= 1.0:
		mastery = {}
	print("Gathering Reset.")

# Called by Engine
func process_tick(delta_time: float):
	if not is_active or current_action.is_empty():
		return

	action_progress += delta_time

	var speed_mult = get_action_speed_multiplier(current_action_id)
	var required_time = current_action.get("duration", 4.0) / speed_mult

	if action_progress >= required_time:
		complete_action()
		action_progress = 0.0

func complete_action():
	var loot_table = current_action["loot_table"]
	var xp_reward = current_action.get("xp", 0)
	
	# ENG_1 Yield Calibration: flat +N units on the PRIMARY drop (loot_table[0]).
	var flat_bonus := 0
	if GameState.warp_manager:
		flat_bonus = GameState.warp_manager.get_tree_gathering_flat()

	var dropped_any = false
	for i in range(loot_table.size()):
		var entry = loot_table[i]
		var element = entry[0]
		var chance = entry[1]
		# v112: deterministic gather yield — the fixed value shown on the card
		# (top of the old min-max range). Quantity RNG on the most-repeated
		# action added noise without a decision; deterministic reads cleaner and
		# makes offline closed-form. The drop CHANCE still gates bonus drops.
		if randf() < chance:
			var amount = int(entry[3])

			# Apply Yield Bonus from research
			if GameState.research_manager:
				amount += int(GameState.research_manager.get_efficiency_bonus("gathering_yield"))
				# v105: gathering_focus (Recursive Logistics) +5%/level multiplicative.
				# Previously bonus_type "gathering_yield_mult" had no consumer.
				amount = int(float(amount) * (1.0 + GameState.research_manager.get_efficiency_bonus("gathering_yield_mult")))

			# Audit v6.0 P1-19: Apply skill yield multiplier
			amount = int(float(amount) * get_yield_multiplier())

			if i == 0:
				amount += flat_bonus   # ENG_1 flat bonus on the primary resource

			GameState.resources.add_element(element, amount)
			GameState.note_production("gather", amount)  # P3.10
			events.append(["loot", {"symbol": element, "amount": amount}, current_action_id])
			dropped_any = true

	if not dropped_any:
		var entry = loot_table[0]
		var element = entry[0]
		var amount = int(entry[3]) + flat_bonus
		GameState.resources.add_element(element, amount)
		GameState.note_production("gather", amount)  # P3.10
		events.append(["loot", {"symbol": element, "amount": amount}, current_action_id])

	add_xp(xp_reward)
	events.append(["xp", "+%d XP" % xp_reward, current_action_id])

	# P1 Mastery: per-action XP (one tick per completion).
	gain_mastery_xp(current_action_id)

func calculate_offline(delta: float):
	if not is_active or current_action.is_empty():
		return null
		
	# v132: NO extra warp multiplication here — get_action_speed_multiplier already
	# includes warp.get_gathering_multiplier() (the old v62 line predated that and
	# DOUBLE-applied it, so offline counted more completions than online pace).
	var speed_mult = get_action_speed_multiplier(current_action_id)
	var effective_duration = current_action.get("duration", 4.0) / speed_mult

	# v132: fold in the saved partial tick and KEEP the remainder — the fractional
	# leftover used to be discarded, so the bar restarted from zero on every resume
	# instead of continuing where the offline stretch actually landed.
	var total_time: float = action_progress + delta
	var num_actions = int(total_time / effective_duration)
	action_progress = fmod(total_time, effective_duration)
	if num_actions <= 0: return null
	
	var loot_summary = {}
	var loot_table = current_action["loot_table"]
	var xp_per_action = current_action.get("xp", 0)
	
	var total_xp = num_actions * xp_per_action
	add_xp(total_xp)

	# P1 Mastery: batch-grant offline mastery XP (one per completion).
	# Single call avoids spawning N notifications during a long catch-up.
	gain_mastery_xp(current_action_id, float(num_actions) * MASTERY_XP_PER_COMPLETION)

	# v62.0 Fix: Get yield multiplier once for offline (same as online)
	var yield_mult = get_yield_multiplier()
	
	# v112: CLOSED-FORM offline gather. With deterministic yields each entry just
	# contributes fixed_qty x drop_chance x num_actions (chance<1 => expected
	# value, matching the old sampled average). No per-action loop -> no ~28k-iter
	# randf hitch on resume (the checklist's ANR/mobile risk). Mult order mirrors
	# the online complete_action path so online and offline stay consistent.
	var yield_flat := 0
	var yield_mult2 := 1.0
	if GameState.research_manager:
		yield_flat = int(GameState.research_manager.get_efficiency_bonus("gathering_yield"))
		yield_mult2 = 1.0 + GameState.research_manager.get_efficiency_bonus("gathering_yield_mult")
	var tree_flat := 0
	if GameState.warp_manager:
		tree_flat = GameState.warp_manager.get_tree_gathering_flat()   # ENG_1 flat +N/action on primary
	for i in range(loot_table.size()):
		var entry = loot_table[i]
		var element = entry[0]
		var chance: float = float(entry[1])
		# Per-action yield when it drops — same truncation order as online.
		var per_drop: int = int(entry[3]) + yield_flat
		per_drop = int(float(per_drop) * yield_mult2)
		per_drop = int(float(per_drop) * yield_mult)
		var total: int = int(float(per_drop) * chance * float(num_actions))
		if i == 0:
			total += tree_flat * num_actions   # ENG_1 flat on the primary resource, per action
		if total <= 0:
			continue
		GameState.resources.add_element(element, total)
		loot_summary[element] = loot_summary.get(element, 0) + total
		GameState.note_production("gather", total)  # P3.10
	
	# v112: structured offline block (was a formatted string) — the telemetry
	# welcome modal aggregates these numerically. See game_state.offline_report_data.
	return {
		"category": "gathering",
		"title": "Off-World Operations",
		"action": current_action.get("name", current_action_id),
		"time_sec": int(delta),
		"actions": num_actions,
		"xp": total_xp,
		"gains": loot_summary.duplicate(),
		"drains": {},
		"notes": [],
		"status": "active",
	}

func get_save_data_manager() -> Dictionary:
	var data = get_save_data() # super
	data["is_active"] = is_active
	data["current_action_id"] = current_action_id
	data["action_progress"] = action_progress  # v132: resume the partial tick
	data["mastery"] = mastery  # P1
	return data

func load_save_data_manager(data: Dictionary):
	load_save_data(data) # super
	if data.is_empty(): return

	is_active = data.get("is_active", false)
	current_action_id = data.get("current_action_id", "")
	action_progress = float(data.get("action_progress", 0.0))  # v132: pre-v132 saves default 0
	# P1 Mastery — defaults to empty so v1 saves load unchanged.
	var saved_mastery = data.get("mastery", {})
	if saved_mastery is Dictionary:
		mastery = saved_mastery.duplicate()

	if is_active and not current_action_id.is_empty():
		if current_action_id in actions:
			current_action = actions[current_action_id]
		else:
			is_active = false
			action_progress = 0.0
			
func get_current_rate() -> Dictionary:
	"""Returns estimated yield per minute for the active action"""
	if not is_active or current_action.is_empty():
		return {}
		
	var speed_mult = get_action_speed_multiplier(current_action_id)
	var effective_duration = current_action.get("duration", 4.0) / speed_mult
	var actions_per_min = 60.0 / effective_duration
	
	var rates = {}
	var loot_table = current_action["loot_table"]
	
	for entry in loot_table:
		var symbol = entry[0]
		var chance = entry[1]
		# v112: yields are deterministic now (fixed at the top of the old range),
		# so project the fixed value, not a min/max average.
		var avg_amt = float(entry[3])

		# Resource Yield Bonus
		if GameState.research_manager:
			avg_amt += GameState.research_manager.get_efficiency_bonus("gathering_yield")
			# v105: gathering_focus multiplicative bonus (see runtime drop path)
			avg_amt *= (1.0 + GameState.research_manager.get_efficiency_bonus("gathering_yield_mult"))

		rates[symbol] = avg_amt * chance * actions_per_min
		
	return rates
