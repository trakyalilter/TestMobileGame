extends RefCounted

var missions = {}
var active_missions = []

signal mission_updated()

func _init():
	init_missions()

func connect_signals():
	if GameState.resources:
		if not GameState.resources.element_added.is_connected(_on_element_added):
			GameState.resources.element_added.connect(_on_element_added)
		if not GameState.resources.currency_added.is_connected(_on_currency_added):
			GameState.resources.currency_added.connect(_on_currency_added)
			
	if GameState.research_manager:
		if not GameState.research_manager.tech_unlocked.is_connected(_on_tech_unlocked):
			GameState.research_manager.tech_unlocked.connect(_on_tech_unlocked)
			
	if GameState.shipyard_manager:
		if not GameState.shipyard_manager.module_crafted.is_connected(_on_module_crafted):
			GameState.shipyard_manager.module_crafted.connect(_on_module_crafted)
		if not GameState.shipyard_manager.hull_constructed.is_connected(_on_hull_constructed):
			GameState.shipyard_manager.hull_constructed.connect(_on_hull_constructed)
		if not GameState.shipyard_manager.inventory_updated.is_connected(_on_shipyard_updated):
			GameState.shipyard_manager.inventory_updated.connect(_on_shipyard_updated)
			
	if GameState.combat_manager:
		if not GameState.combat_manager.enemy_defeated.is_connected(_on_enemy_defeated):
			GameState.combat_manager.enemy_defeated.connect(_on_enemy_defeated)
			
	if GameState.infrastructure_manager:
		if not GameState.infrastructure_manager.building_constructed.is_connected(_on_building_constructed):
			GameState.infrastructure_manager.building_constructed.connect(_on_building_constructed)
			
	sync_progress()

func init_missions():
	missions.clear()
	active_missions.clear()
	
	# Tutorial Missions Sequence
	# Structure: [id, name, description, type, target, target_qty, reward_cr, reward_xp, next_mission_id]
	var m_list = [
		# ID, Name, Desc, Type, Target, TargetQty, RewardCr, RewardXP, NextID
		["m001", "Stranded in Orbit", "Gather 350 Dirt to begin basic repairs.", "gather", "Dirt", 350, 600, 50, "m002"],
		["m002", "Analytical Breakthrough", "Research 'Basic Engineering' to unlock refining.", "research", "basic_engineering", 1, 300, 50, "m002b"],
		# P0-30: Physics Paradox Fix - Applied Physics moved here
		["m002b", "Applied Physics", "Research the 'Applied Physics' hub.", "research", "applied_physics", 1, 300, 100, "m003"],
		["m003", "Pump Master", "Research 'Fluid Dynamics' to unlock water collection.", "research", "fluid_dynamics", 1, 300, 50, "m004"],
		["m004", "Hydration", "Gather 350 units of Water.", "gather", "Water", 350, 500, 100, "m005"],
		["m005", "Mineral Washing", "Recover 75 Silicon and 75 Iron from Dirt.", "gather_multi", {"Si": 75, "Fe": 75}, 150, 1000, 200, "m007"],
		
		# m006 Removed (Moved to m002b)
		["m007", "Mobility Check", "Craft a 'Basic Thruster' in the Shipyard.", "craft", "z1_engine", 1, 1000, 100, "m008"],
		["m008", "Materials Science", "Research the 'Materials Science' hub.", "research", "materials_science", 1, 300, 100, "m009"],
		["m009", "Deforestation", "Gather 100 units of Wood.", "gather", "Wood", 100, 500, 100, "m010"],
		["m010", "Organic Combustion", "Research 'Organic Combustion' to unlock the Kiln.", "research", "combustion", 1, 500, 150, "m011"],
		["m011", "Essential Carbon", "Use the Charcoal Kiln to produce 50 Carbon.", "gather", "C", 50, 600, 150, "m012"],
		["m012", "Lithium Discovery", "Gather 60 Lithium Ore.", "gather", "Spodumene", 60, 800, 200, "m013"],
		["m013", "Voltaic Storage", "Refine 30 Lithium in the Engineering tab.", "gather", "Li", 30, 1000, 250, "m020"],
		["m014", "Ballistics Theory", "Research 'Kinetics 101' for weapons technology.", "research", "kinetics_101", 1, 1200, 100, "m015"],
		["m015", "Prototype Arsenal", "Craft a 'Mass Driver Mk.I' in the Shipyard.", "craft", "z1_kinetic", 1, 1500, 200, "m016"],
		["m016", "Kinetic Munitions", "Produce 100 Ferrite Rounds for your weapon.", "gather", "SlugT1", 100, 1000, 100, "m023"],
		# Shield Section Moved Here (m023 -> m024)
		# P2-12: Combat Readiness Checkpoint - ensure player is equipped before first combat
		["m016b", "Combat Ready", "Equip a WEAPON and SHIELD in your Ship Designer.", "loadout_check", "combat_ready", 1, 300, 100, "m017"],
		["m017", "Target Locked", "Defeat 1 Lunar Drone in Lunar Orbit.", "defeat", "z1_lunar_drone", 1, 2500, 500, "m018"],
		["m018", "Industrial Logistics", "Research the 'Industrial Logistics' hub.", "research", "industrial_logistics", 1, 500, 100, "m018b"],
		["m018b", "Automated Intelligence", "Research 'Automated Logistics' for circuitry.", "research", "automated_logistics", 1, 1000, 200, "m019"],
		["m019", "Cybernetic Integration", "Craft 5 Basic Circuitry in the Engineering tab.", "gather", "Circuit", 5, 2000, 300, "m025"],
		["m020", "Advanced Energy", "Research 'Power Systems' for batteries.", "research", "power_systems", 1, 500, 100, "m021"],
		["m021", "Industrial Energy", "Craft 5 Basic Batteries in the Engineering tab.", "gather", "BatteryT1", 5, 1000, 100, "m022"],
		["m022", "Power Storage", "Craft a 'Basic Battery' in the Shipyard.", "craft", "z1_battery", 1, 1500, 150, "m014"],
		["m023", "Hull Integrity", "Research 'Energy Fields' to unlock shielding.", "research", "energy_shields", 1, 1000, 150, "m024"],
		["m024", "Aegis System", "Craft a 'Basic Shield' for protection.", "craft", "z1_shield", 1, 2500, 200, "m016b"],
		["m025", "Refining Mastery", "Research 'Efficient Smelting' for alloys.", "research", "smelting", 1, 15000, 500, "m026"],
		["m026", "Master Constructor", "Research 'Shipwright I' for hull reinforcement.", "research", "shipwright_1", 1, 5000, 500, "m026b"],
		# P0-25: Missing Beepings - Fleet Modernization I
		["m026b", "Fleet Modernization I", "Construct an 'Industrial Frigate' in the Shipyard.", "construct", "frigate_hull", 1, 10000, 1000, "m027"],
		# P0 Fix: Progression Deadlock Re-alignment
		["m027", "Scanning Horizon", "Unlock 'Asteroid Belt' to expand operations.", "research", "asteroid_clearance", 1, 5000, 500, "m028"],
		["m028", "Belt Mining", "Mine 1000 Cassiterite in the Asteroid Belt.", "gather", "Cassiterite", 1000, 10000, 2000, "m029"],
		["m029", "Hardened Shell", "Craft 'Carbon Fiber Plate' in the Shipyard.", "craft", "z2_armor", 1, 15000, 5000, "m029b"],
		["m029b", "Complex Electronics", "Craft 10 Advanced Circuits to prepare for heavier ships.", "gather", "AdvCircuit", 10, 20000, 5000, "m030"],
		# P0-31: Fabricator Paradox Fix - Shipwright II moved before Fabricator
		["m030", "Naval Expansion", "Research 'Shipwright II' to unlock Destroyer-class hulls.", "research", "shipwright_2", 1, 4000, 1000, "m030b"],
		["m030b", "Deep Space Comms", "Build a 'Fabricator' to prepare for the long journey.", "build", "fabricator", 1, 30000, 5000, "m030c"],
		# P0-25: Missing Beepings - Fleet Modernization II
		["m030c", "Fleet Modernization II", "Construct an 'Escort Destroyer' in the Shipyard.", "construct", "destroyer_hull", 1, 25000, 2000, "m031"],
		
		# P0 Fix: Sector Alpha Push
		["m031", "Deep Space Signal", "Unlock 'Sector Alpha' via decryption.", "research", "sector_alpha_decryption", 1, 50000, 10000, "m032"],
		["m032", "Alpha Sector Dominance", "Defeat 3 Alien Frigates in Sector Alpha.", "defeat", "z5_alien_frigate", 3, 75000, 15000, "m032b"],
		# P0-27: Unlock Sector Beta
		["m032b", "Expanding Horizons", "Research 'Deep Space Navigation' to unlock Sector Beta.", "research", "deep_space_nav", 1, 50000, 5000, "m032d"],
		["m032d", "Void Research", "Gather 5 Void Artifacts dropped by Sector Alpha ships.", "gather", "VoidArtifact", 5, 100000, 10000, "m032c"],
		# P0-28: Construct Battlecruiser
		["m032c", "Capital Doctrine", "Construct a 'Battlecruiser' in the Shipyard.", "construct", "battlecruiser_hull", 1, 250000, 25000, "m033"],
		
		# v80.3 Fix: Remapped to v80.1 enemy IDs
		["m033", "Beta Sector Expansion", "Defeat 5 Ore Guardians in Sector Beta to expand your influence.", "defeat", "z6_ore_guardian", 5, 150000, 25000, "m033b"],
		# P0-27: Unlock Sector Gamma
		["m033b", "Deep Space Signals", "Research 'Radiation Shielding Theory' to unlock Sector Gamma.", "research", "radiation_shielding", 1, 100000, 10000, "m033c"],
		# P0-28: Construct Dreadnought
		["m033c", "Titan Construction", "Construct a 'Dreadnought' in the Shipyard.", "construct", "dreadnought_hull", 1, 1000000, 50000, "m034"],
		
		# v80.3 Fix: Remapped to v80.1 enemy IDs
		["m034", "Gamma Sector Control", "Defeat 3 Gamma Colossus in Sector Gamma to finalize supremacy.", "defeat", "z6_boss_colossus", 3, 300000, 50000, ""],
		["goal_001", "THE GREAT EXPEDITION", "Reach Sector Epsilon and discover the Primordial Core.", "discover", "sector_epsilon", 1, 0, 1000000, ""]
	]
	
	for i in range(m_list.size()):
		var entry = m_list[i]
		var mid = entry[0]
		var stage = i + 1 # missions index for scaling
		
		# Use hand-tuned base reward from mission definition
		# Apply gentle linear scaling: Base * (1 + 0.05 * stage)
		# This gives ~50% more at stage 10, ~150% more at stage 30
		# Much gentler than the old 1.15^stage which was causing hyperinflation
		var base_reward = entry[6]
		var scaled_reward = int(float(base_reward) * (1.0 + 0.05 * float(stage)))
		
		# Cutoff Enforcement: m034 ends the linear progression chain
		var next_id = entry[8]
		if mid == "m034": next_id = ""
		
		var m_name = entry[1]
		if mid.begins_with("m"): m_name = "[TUTORIAL] " + m_name
		else: m_name = "[CORE GOAL] " + m_name
		
		missions[mid] = {
			"id": mid,
			"name": m_name,
			"description": entry[2],
			"type": entry[3],
			"target": entry[4],
			"target_qty": entry[5],
			"reward_cr": scaled_reward,
			"reward_xp": entry[7],
			"next_mission": next_id,
			"current_qty": 0.0,
			"multi_progress": {}, # For gather_multi
			"completed": false,
			"claimed": false,
			"active": (mid == "m001" or mid.begins_with("goal")) # Tutorial starts at m001, Core Goals always active
		}
		if missions[mid]["active"]:
			active_missions.append(mid)
	
	mission_updated.emit()

func _on_element_added(symbol, amount):
	_update_progress("gather", symbol, amount)
	_update_multi_progress(symbol, amount)

func _on_currency_added(type, amount):
	_update_progress("sell", type, amount)

func _on_tech_unlocked(tech_id):
	_update_progress("research", tech_id, 1)

func _on_module_crafted(module_id):
	_update_progress("craft", module_id, 1)

func _on_hull_constructed(hull_id):
	_update_progress("construct", hull_id, 1)

func _on_enemy_defeated(enemy_id):
	_update_progress("defeat", enemy_id, 1)

func _on_building_constructed(building_id):
	_update_progress("build", building_id, 1)

func _on_shipyard_updated():
	sync_progress()

func _update_progress(type, target, amount):
	for mid in active_missions:
		var m = missions[mid]
		if not m["completed"] and m["type"] == type and m["target"] == target:
			m["current_qty"] += amount
			print("[MissionDebug] ID: %s, Progress: %d/%d (added %d)" % [mid, m["current_qty"], m["target_qty"], amount])
			check_completion(m)
			mission_updated.emit()

func _update_multi_progress(symbol, amount):
	for mid in active_missions:
		var m = missions[mid]
		if not m["completed"] and m["type"] == "gather_multi":
			if symbol in m["target"]:
				var current = m["multi_progress"].get(symbol, 0.0)
				var to_add = min(amount, m["target"][symbol] - current)
				if to_add > 0:
					m["multi_progress"][symbol] = current + to_add
					m["current_qty"] += to_add
					print("[MissionDebug] ID: %s, Multi-Progress: %d/%d (added %d %s)" % [mid, m["current_qty"], m["target_qty"], to_add, symbol])
				
				# Check overall completion
				var all_done = true
				for s in m["target"]:
					if m["multi_progress"].get(s, 0.0) < m["target"][s]:
						all_done = false
						break
				if all_done:
					check_completion(m)
				
				mission_updated.emit()


func check_completion(mission):
	if mission["current_qty"] >= mission["target_qty"]:
		mission["current_qty"] = mission["target_qty"]
		mission["completed"] = true

func claim_reward(mission_id) -> bool:
	if not mission_id in missions: return false
	var m = missions[mission_id]
	if m["completed"] and not m["claimed"]:
		m["claimed"] = true
		
		# Remove from active list
		active_missions.erase(mission_id)
		
		# Grant Rewards
		if m["reward_cr"] > 0:
			var reward = m["reward_cr"]
			# Audit v3.0: Apply prestige multiplier to mission rewards
			if GameState.warp_manager:
				reward = int(reward * GameState.warp_manager.get_production_multiplier())
			GameState.resources.add_currency("credits", reward)
		
		# Auto-unlock next mission
		if m["next_mission"] != "" and m["next_mission"] in missions:
			var next_id = m["next_mission"]
			missions[next_id]["active"] = true
			if not next_id in active_missions:
				active_missions.append(next_id)
		
		sync_progress() # Sync the new mission immediately
		mission_updated.emit()
		return true
	return false

func get_save_data_manager() -> Dictionary:
	var m_data = {}
	for mid in missions:
		var m = missions[mid]
		m_data[mid] = {
			"current_qty": m["current_qty"],
			"multi_progress": m["multi_progress"],
			"completed": m["completed"],
			"claimed": m["claimed"],
			"active": m["active"]
		}
	return {"missions": m_data}

func sync_progress():
	if not GameState.resources: return
	
	var changed = false
	for mid in active_missions:
		var m = missions[mid]
		if m["completed"]: continue
		
		var old_qty = m["current_qty"]
		
		if m["type"] == "gather":
			var inv_qty = GameState.resources.get_element_amount(m["target"])
			# Persistence: Only update if it helps progression or if we haven't hit completion yet
			m["current_qty"] = max(m["current_qty"], min(inv_qty, m["target_qty"]))
		
		elif m["type"] == "gather_multi":
			for s in m["target"]:
				var inv_qty = GameState.resources.get_element_amount(s)
				var req = m["target"][s]
				var prog = min(inv_qty, req)
				m["multi_progress"][s] = max(m["multi_progress"].get(s, 0.0), prog)
			
			# Recalculate total current_qty from locked-in sub-progress
			var total_p = 0.0
			for s in m["multi_progress"]:
				total_p += m["multi_progress"][s]
			m["current_qty"] = total_p
		
		elif m["type"] == "research":
			if GameState.research_manager.is_tech_unlocked(m["target"]):
				m["current_qty"] = 1
				
		elif m["type"] == "craft":
			var inv_count = GameState.shipyard_manager.module_inventory.get(m["target"], 0)
			# Also check if equipped
			for slot in GameState.shipyard_manager.loadout:
				if GameState.shipyard_manager.loadout[slot] == m["target"]:
					inv_count += 1
			m["current_qty"] = max(m["current_qty"], min(inv_count, m["target_qty"]))

		elif m["type"] == "construct":
			if GameState.shipyard_manager.active_hull == m["target"]:
				m["current_qty"] = 1
			# Also check if we passed this tier (e.g. have a Destroyer but mission wants Frigate)
			# Assuming linear progression: Corvette -> Frigate -> Destroyer
			# Quick hack: Check if current tier >= target tier
			var target_tier = GameState.shipyard_manager.hulls[m["target"]].get("tier", 0)
			var current_tier = GameState.shipyard_manager.hulls[GameState.shipyard_manager.active_hull].get("tier", 0)
			if current_tier >= target_tier:
				m["current_qty"] = 1

		elif m["type"] == "build":
			if GameState.infrastructure_manager:
				var count = GameState.infrastructure_manager.get_building_count(m["target"])
				m["current_qty"] = max(m["current_qty"], min(count, m["target_qty"]))

		# P2-12: Combat readiness checkpoint - checks loadout for weapon AND shield
		elif m["type"] == "loadout_check" and m["target"] == "combat_ready":
			var has_weapon = false
			var has_shield = false
			var sm = GameState.shipyard_manager
			for mid_equipped in sm.loadout.values():
				if mid_equipped and mid_equipped in sm.modules:
					var mod = sm.modules[mid_equipped]
					var st = mod.get("slot_type", "")
					if st == "weapon": has_weapon = true
					elif st == "shield": has_shield = true
			
			# Fail-safe: Check calculated stats (Base Corvette has 0 shield, >0 means shield equipped)
			if sm.max_shield > 0: has_shield = true
			# Base Corvette has 10 atk. If total attack > base, they have a weapon.
			var base_atk = 0
			if sm.active_hull in sm.hulls:
				base_atk = sm.hulls[sm.active_hull]["stats"].get("atk", 0)
			if (sm.attack_kinetic + sm.attack_energy + sm.attack_explosive) > base_atk:
				has_weapon = true
				
			if has_weapon and has_shield:
				m["current_qty"] = 1

		if m["current_qty"] != old_qty:
			changed = true
			
		check_completion(m)
	
	if changed:
		mission_updated.emit()

func load_save_data_manager(data: Dictionary):
	if data.is_empty(): return
	var m_data = data.get("missions", {})
	active_missions.clear()
	for mid in m_data:
		if mid in missions:
			var saved = m_data[mid]
			var m = missions[mid]
			m["current_qty"] = saved.get("current_qty", 0.0)
			m["multi_progress"] = saved.get("multi_progress", {})
			m["completed"] = saved.get("completed", false)
			m["claimed"] = saved.get("claimed", false)
			m["active"] = saved.get("active", false)
			if m["active"] and not m["claimed"]:
				active_missions.append(mid)

func reset():
	init_missions()

func has_progress() -> bool:
	for mid in missions:
		var m = missions[mid]
		if m["claimed"] or m["completed"]:
			return true
	return false
