extends Skill

# We assume GameState is a global Autoload or accessible static
# If not, we might need to pass it, but RefCounted doesn't support convenient dependency injection 
# without custom init. We'll use the Autoload 'GameState'.

var is_active: bool = false
var current_action: Dictionary = {}
var current_action_id: String = ""
var action_progress: float = 0.0
var action_duration: float = 4.0

var events: Array = [] # Buffer for UI

# P1 Mastery — per-action long-tail layered learning. Each gather action
# accumulates its own XP; milestones at 10/25/50/75/100 grant cumulative
# duration reductions (capped at 25%), an alt-recipe unlock flag at 50,
# and a Hearthstone-style gold-card cosmetic at 100. Persists across warps
# (true meta-progression); cleared only on hard reset.
const MASTERY_XP_PER_COMPLETION := 1.0
const MASTERY_MILESTONES: Array[int] = [10, 25, 50, 75, 100]
const MASTERY_DURATION_BONUS_PER_MILESTONE := 0.05
const MASTERY_DURATION_BONUS_MAX := 0.25
const MASTERY_LEVEL_CAP := 100

var mastery: Dictionary = {}  # {action_id: xp_total_float}

var actions: Dictionary = {
	"gather_dirt": {
		"name": "Excavate Soil",
		"loot_table": [["Dirt", 1.0, 8, 10]],
		"xp": 8,
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
		"loot_table": [["Water", 1.0, 8, 10]],
		"xp": 12,
		"level_req": 3,
		"research_req": "fluid_dynamics",
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
		"level_req": 5,
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
		"name": "Extract Lithium Salt",
		"loot_table": [["Spodumene", 1.0, 1, 3]],
		"xp": 10,
		"level_req": 4,
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
		"level_req": 10,
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

# Returns the duration multiplier (1.0 = full duration, 0.75 = 25% faster).
# Used by get_action_speed_multiplier to turn it into a speed boost.
func get_mastery_duration_mult(action_id: String) -> float:
	var level: int = get_mastery_level(action_id)
	var milestones_passed: int = 0
	for m in MASTERY_MILESTONES:
		if level >= m:
			milestones_passed += 1
	var reduction: float = min(MASTERY_DURATION_BONUS_MAX,
		float(milestones_passed) * MASTERY_DURATION_BONUS_PER_MILESTONE)
	return 1.0 - reduction

func is_mastery_alt_unlocked(action_id: String) -> bool:
	return get_mastery_level(action_id) >= 50

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
	var action_name: String = actions.get(action_id, {}).get("name", action_id)
	for m in MASTERY_MILESTONES:
		if prev_level < m and new_level >= m:
			var msg: String = ""
			if m == 50:
				msg = "%s — Mastery 50 ★ Alt-Recipe Unlocked" % action_name
			elif m == 100:
				msg = "%s — Mastery 100 ★ Gold Tier ★" % action_name
			else:
				var idx: int = MASTERY_MILESTONES.find(m) + 1
				msg = "%s — Mastery %d · −%d%% Duration" % [action_name, m, idx * 5]
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
		# v61.0 Fix: Use per-action duration instead of fixed 4.0
		action_duration = action.get("duration", 4.0)

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
	var required_time = action_duration / speed_mult
	
	if action_progress >= required_time:
		complete_action()
		action_progress = 0.0

func complete_action():
	var loot_table = current_action["loot_table"]
	var xp_reward = current_action.get("xp", 0)
	
	var dropped_any = false
	for entry in loot_table:
		var element = entry[0]
		var chance = entry[1]
		var min_amt = entry[2]
		var max_amt = entry[3]
		
		if randf() < chance:
			var amount = randi_range(min_amt, max_amt)

			# Apply Yield Bonus from research
			if GameState.research_manager:
				amount += int(GameState.research_manager.get_efficiency_bonus("gathering_yield"))
				# v105: gathering_focus (Recursive Logistics) +5%/level multiplicative.
				# Previously bonus_type "gathering_yield_mult" had no consumer.
				amount = int(float(amount) * (1.0 + GameState.research_manager.get_efficiency_bonus("gathering_yield_mult")))

			# Audit v6.0 P1-19: Apply skill yield multiplier
			amount = int(float(amount) * get_yield_multiplier())
				
			GameState.resources.add_element(element, amount)
			GameState.note_production("gather", amount)  # P3.10
			events.append(["loot", {"symbol": element, "amount": amount}, current_action_id])
			dropped_any = true
			
	if not dropped_any:
		var entry = loot_table[0]
		var element = entry[0]
		var min_amt = entry[2]
		var max_amt = entry[3]
		var amount = randi_range(min_amt, max_amt)
		GameState.resources.add_element(element, amount)
		GameState.note_production("gather", amount)  # P3.10
		events.append(["loot", {"symbol": element, "amount": amount}, current_action_id])

	if GameState.bounty_manager:
		xp_reward = int(xp_reward * GameState.bounty_manager.get_trophy_buff("gathering_xp"))
		
	add_xp(xp_reward)
	events.append(["xp", "+%d XP" % xp_reward, current_action_id])

	# P1 Mastery: per-action XP (one tick per completion).
	gain_mastery_xp(current_action_id)

func calculate_offline(delta: float):
	if not is_active or current_action.is_empty():
		return null
		
	var speed_mult = get_action_speed_multiplier(current_action_id)
	# v62.0 Fix: Apply warp multiplier to match online behavior
	if GameState.warp_manager:
		speed_mult *= GameState.warp_manager.get_gathering_multiplier()
	var effective_duration = action_duration / speed_mult
	
	var num_actions = int(delta / effective_duration)
	if num_actions <= 0: return null
	
	var loot_summary = {}
	var loot_table = current_action["loot_table"]
	var xp_per_action = current_action.get("xp", 0)
	
	var total_xp = num_actions * xp_per_action
	if GameState.bounty_manager:
		total_xp = int(total_xp * GameState.bounty_manager.get_trophy_buff("gathering_xp"))
		
	add_xp(total_xp)

	# P1 Mastery: batch-grant offline mastery XP (one per completion).
	# Single call avoids spawning N notifications during a long catch-up.
	gain_mastery_xp(current_action_id, float(num_actions) * MASTERY_XP_PER_COMPLETION)

	# v62.0 Fix: Get yield multiplier once for offline (same as online)
	var yield_mult = get_yield_multiplier()
	
	for i in range(num_actions):
		var dropped_any = false
		for entry in loot_table:
			var element = entry[0]
			var chance = entry[1]
			var min_amt = entry[2]
			var max_amt = entry[3]
			
			if randf() < chance:
				var amount = randi_range(min_amt, max_amt)

				if GameState.research_manager:
					amount += int(GameState.research_manager.get_efficiency_bonus("gathering_yield"))
					# v105: gathering_focus multiplicative bonus (see online path)
					amount = int(float(amount) * (1.0 + GameState.research_manager.get_efficiency_bonus("gathering_yield_mult")))

				# v62.0 Fix: Apply yield multiplier like online does
				amount = int(float(amount) * yield_mult)
					
				GameState.resources.add_element(element, amount)
				loot_summary[element] = loot_summary.get(element, 0) + amount; GameState.note_production("gather", amount)  # P3.10
				dropped_any = true
		
		if not dropped_any:
			var entry = loot_table[0]
			var element = entry[0]
			var min_amt = entry[2]
			var max_amt = entry[3]
			var amount = randi_range(min_amt, max_amt)
			
			if GameState.research_manager:
				amount += int(GameState.research_manager.get_efficiency_bonus("gathering_yield"))
				# v105: gathering_focus multiplicative bonus (see online path)
				amount = int(float(amount) * (1.0 + GameState.research_manager.get_efficiency_bonus("gathering_yield_mult")))

			# v62.0 Fix: Apply yield multiplier for fallback drops too
			amount = int(float(amount) * yield_mult)
				
			GameState.resources.add_element(element, amount)
			loot_summary[element] = loot_summary.get(element, 0) + amount; GameState.note_production("gather", amount)  # P3.10
	
	var report = "Off-World Operations (%s):\n" % current_action['name']
	report += "Time: %dm %ds\n" % [int(delta / 60), int(delta) % 60]
	report += "Actions Completed: %d\n" % num_actions
	report += "XP Gained: %d\n" % total_xp
	report += "Loot Gathered:\n"
	
	for item in loot_summary:
		report += " - %s: %d\n" % [item, loot_summary[item]]
		
	return report

func get_save_data_manager() -> Dictionary:
	var data = get_save_data() # super
	data["is_active"] = is_active
	data["current_action_id"] = current_action_id
	data["mastery"] = mastery  # P1
	return data

func load_save_data_manager(data: Dictionary):
	load_save_data(data) # super
	if data.is_empty(): return

	is_active = data.get("is_active", false)
	current_action_id = data.get("current_action_id", "")
	# P1 Mastery — defaults to empty so v1 saves load unchanged.
	var saved_mastery = data.get("mastery", {})
	if saved_mastery is Dictionary:
		mastery = saved_mastery.duplicate()
	
	if is_active and not current_action_id.is_empty():
		if current_action_id in actions:
			current_action = actions[current_action_id]
		else:
			is_active = false
			
func get_current_rate() -> Dictionary:
	"""Returns estimated yield per minute for the active action"""
	if not is_active or current_action.is_empty():
		return {}
		
	var speed_mult = get_action_speed_multiplier(current_action_id)
	var effective_duration = action_duration / speed_mult
	var actions_per_min = 60.0 / effective_duration
	
	var rates = {}
	var loot_table = current_action["loot_table"]
	
	for entry in loot_table:
		var symbol = entry[0]
		var chance = entry[1]
		var min_amt = entry[2]
		var max_amt = entry[3]
		var avg_amt = (min_amt + max_amt) / 2.0
		
		# Resource Yield Bonus
		if GameState.research_manager:
			avg_amt += GameState.research_manager.get_efficiency_bonus("gathering_yield")
			# v105: gathering_focus multiplicative bonus (see runtime drop path)
			avg_amt *= (1.0 + GameState.research_manager.get_efficiency_bonus("gathering_yield_mult"))

		rates[symbol] = avg_amt * chance * actions_per_min
		
	return rates
