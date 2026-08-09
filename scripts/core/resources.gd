extends Node

signal element_added(symbol, amount)
signal currency_added(type, amount)
signal currency_removed(type, amount)
signal element_removed(symbol, amount)
signal energy_changed(current, maximum)

var elements: Dictionary = {}
var currencies: Dictionary = {}
var energy: float = 0.0
var max_energy: float = 0.0
var lifetime_credits: float = 0.0
var base_slots: int = 28
var storage_upgrades: int = 0 # Feature P65-X: Manual Storage Upgrade
var _was_full: bool = false  # one-shot guard: warn once on the empty→full transition; re-arms when a slot frees

func _ready():
	# Initial Starter Kit if elements are empty (New Game)
	if elements.is_empty() and currencies.is_empty():
		seed_starter_kit()

	cleanup_inventory()

# New-game "Distress Cache": a generous starter so a first-time player reaches their
# first fight in minutes instead of grinding ~10 materials up from zero. Granted on
# first launch (_ready, when empty) and on New Game (game_state.hard_reset) — NEVER
# on Warp (prestige has its own starter package). Tune the amounts here.
func seed_starter_kit() -> void:
	add_currency("credits", 1500)
	# Small HEAD-START only: every amount is below its mission target, so the player
	# still gathers and PROCESSES the rest of each. That's the crucial part — skipping
	# those actions skips the skill XP the chain's recipe gates depend on (e.g. Basic
	# Shield Booster needs Engineering Lv.2; the player clears Lv.2 while doing the
	# Si/Fe refine at m005). A little of everything, no auto-completes, no under-
	# levelling. Dirt is left short of m001's 350 so the first gather is still taught.
	# v174 (owner): trimmed to the four raws the opening actually uses. SlugT1
	# dropped — m016 teaches you to make ammo, and nothing before it fights, so
	# handing over 25 rounds only blunted that beat.
	var kit := {
		"Dirt": 120, "Water": 100,
		"Fe": 25, "Si": 30,
	}
	for sym in kit:
		add_element(sym, int(kit[sym]))

func get_max_slots() -> int:
	return base_slots + storage_upgrades

# Feature: Manual Storage Upgrade
func upgrade_storage() -> bool:
	var cost = get_storage_upgrade_cost()
	
	if get_currency("credits") >= cost:
		remove_currency("credits", cost)
		storage_upgrades += 1
		return true
	return false

func get_storage_upgrade_cost() -> float:
	# Cost scales with upgrades: 1000 * 1.25^level
	return floor(1000.0 * pow(1.25, storage_upgrades))

# v132: `force` bypasses the slot cap for EARNED payouts (quest/bounty rewards) —
# claim paths showed a "+N Material" toast while add_element silently dropped the
# goods at 28 slots. Farmed output still respects the cap (it IS the sink).
func add_element(symbol: String, amount: float, force: bool = false):
	if not is_finite(amount) or amount <= 0: return

	# Slot Check
	if not elements.has(symbol):
		# Progression-critical drops (boss cores, matrix cores, endgame, special)
		# are kept over-cap rather than silently lost — dropping a Z#_Core would
		# soft-lock zone-access research. Bulk basics still hit the cap (the sink).
		# v147: armory stock costs no slot at all, so it can never be capped out.
		if get_used_slots() >= get_max_slots() and not force \
				and not ElementDB.is_slot_protected(symbol) and not ElementDB.is_armory_item(symbol):
			# Inventory full: this output is silently lost. Warn ONCE on the
			# transition (the header slot meter is the persistent indicator);
			# re-arms when a slot frees (remove_element).
			if not _was_full:
				_was_full = true
				UITheme.show_notification(tr("Inventory full — new resources are being wasted. Sell or expand storage."), Color(1.0, 0.45, 0.35))
			return
		elements[symbol] = 0.0

	# No quantity limit per slot
	elements[symbol] = elements[symbol] + amount
	element_added.emit(symbol, amount)
	# Fire the warning once the LAST free slot just got used (filling up, not
	# just a refused drop) — same one-shot guard.
	if not _was_full and get_used_slots() >= get_max_slots():
		_was_full = true
		UITheme.show_notification(tr("Inventory full — new resources are being wasted. Sell or expand storage."), Color(1.0, 0.45, 0.35))

func remove_element(symbol: String, amount: float) -> bool:
	if not is_finite(amount) or amount <= 0: return false # Safety: Cannot "remove" negative or zero
	var current = elements.get(symbol, 0.0)
	if current >= amount:
		elements[symbol] = current - amount
		# Cleanup empty keys
		if elements[symbol] <= 0:
			elements.erase(symbol)
			_was_full = false   # a slot just freed → re-arm the full warning
		
		element_removed.emit(symbol, amount)
		return true
	return false

func get_element_amount(symbol: String) -> float:
	return elements.get(symbol, 0.0)

func has_element(symbol: String, amount: float) -> bool:
	return get_element_amount(symbol) >= amount

func add_currency(currency_type: String, amount: float):
	if not is_finite(amount) or amount <= 0: return
	if not currencies.has(currency_type):
		currencies[currency_type] = 0.0
	currencies[currency_type] += amount
	if currency_type == "credits" and amount > 0:
		lifetime_credits += amount
	currency_added.emit(currency_type, amount)

func remove_currency(currency_type: String, amount: float) -> bool:
	if not is_finite(amount) or amount <= 0: return false # Safety: Cannot "remove" negative or zero
	var current = currencies.get(currency_type, 0.0)
	if current >= amount:
		currencies[currency_type] = current - amount
		currency_removed.emit(currency_type, amount)
		return true
	return false

func get_currency(currency_type: String) -> float:
	return currencies.get(currency_type, 0.0)

func add_energy(amount: float):
	energy += amount
	if energy > max_energy:
		energy = max_energy
	if energy < 0:
		energy = 0.0
	energy_changed.emit(energy, max_energy)

func remove_energy(amount: float) -> bool:
	if energy >= amount:
		energy -= amount
		energy_changed.emit(energy, max_energy)
		return true
	return false

func get_energy() -> float:
	return energy

func set_max_energy(value: float):
	max_energy = value
	if energy > max_energy:
		energy = max_energy
	energy_changed.emit(energy, max_energy)


func get_save_data() -> Dictionary:
	return {
		"elements": elements,
		"currencies": currencies,
		"energy": energy,
		"max_energy": max_energy,
		"lifetime_credits": lifetime_credits,
		"storage_upgrades": storage_upgrades
	}

func load_save_data(data: Dictionary):
	if data.is_empty(): return
	elements = data.get("elements", {})
	currencies = data.get("currencies", {})
	energy = data.get("energy", 0.0)
	max_energy = data.get("max_energy", 0.0)
	lifetime_credits = data.get("lifetime_credits", 0.0)
	storage_upgrades = int(data.get("storage_upgrades", 0))
	
	# Fix types if JSON loaded ints
	for k in elements: elements[k] = float(elements[k])
	for k in currencies: currencies[k] = float(currencies[k])
	
	cleanup_inventory()

func cleanup_inventory():
	var to_remove = []
	for k in elements:
		if elements[k] <= 0:
			to_remove.append(k)
	
	for k in to_remove:
		elements.erase(k)

func get_used_slots() -> int:
	# v147: Armory stock (consumables / matrix cores / hack cards) does NOT occupy
	# a cargo slot. It is equipped from the Armory, not hauled as bulk material, so
	# it should not compete with ores and alloys for the 28-slot sink.
	var n := 0
	for sym in elements:
		if not ElementDB.is_armory_item(sym):
			n += 1
	return n

func reset(keep_storage := false):
	elements.clear()
	currencies.clear()
	energy = 0.0
	# Paid slot expansions are permanent meta — kept across warp (prestige),
	# cleared only on a hard reset.
	if not keep_storage:
		storage_upgrades = 0

# Resource Discovery System
func get_resource_info(symbol: String) -> Dictionary:
	"""Returns comprehensive information about where a resource comes from and what uses it"""
	return {
		"name": symbol,
		"owned": get_element_amount(symbol),
		"sources": get_resource_sources(symbol),
		"uses": get_resource_uses(symbol)
	}

func get_resource_sources(symbol: String) -> Array:
	"""Find all ways to obtain a resource"""
	var sources = []
	
	# Check gathering actions
	if GameState.gathering_manager:
		for action_id in GameState.gathering_manager.actions:
			var action = GameState.gathering_manager.actions[action_id]
			for entry in action.get("loot_table", []):
				if entry[0] == symbol:
					var source = {
						"type": "gathering",
						"name": action["name"],
						"action_id": action_id,
						"chance": entry[1] * 100.0,
						"amount": "%d-%d" % [entry[2], entry[3]]
					}
					# Check if locked
					var level_req = action.get("level_req", 1)
					var research_req = action.get("research_req")
					source["locked"] = (GameState.gathering_manager.get_level() < level_req)
					if research_req:
						source["locked"] = source["locked"] or not GameState.research_manager.is_tech_unlocked(research_req)
						source["research_req"] = research_req
					sources.append(source)
	
	# Check processing recipes
	if GameState.processing_manager:
		for recipe_id in GameState.processing_manager.recipes:
			var recipe = GameState.processing_manager.recipes[recipe_id]
			
			# Check standard output
			if "output" in recipe and symbol in recipe["output"]:
				var source = {
					"type": "processing",
					"name": recipe["name"],
					"recipe_id": recipe_id,
					"amount": str(recipe["output"][symbol])
				}
				# Check if locked
				var level_req = recipe.get("level_req", 1)
				var research_req = recipe.get("research_req")
				source["locked"] = (GameState.processing_manager.get_level() < level_req)
				if research_req:
					source["locked"] = source["locked"] or not GameState.research_manager.is_tech_unlocked(research_req)
					source["research_req"] = research_req
				sources.append(source)
			
			# Check loot table output
			if "output_table" in recipe:
				for entry in recipe["output_table"]:
					if entry[0] == symbol:
						var source = {
							"type": "processing",
							"name": recipe["name"],
							"recipe_id": recipe_id,
							"chance": entry[1] * 100.0,
							"amount": "%d-%d" % [entry[2], entry[3]]
						}
						var level_req = recipe.get("level_req", 1)
						var research_req = recipe.get("research_req")
						source["locked"] = (GameState.processing_manager.get_level() < level_req)
						if research_req:
							source["locked"] = source["locked"] or not GameState.research_manager.is_tech_unlocked(research_req)
							source["research_req"] = research_req
						sources.append(source)
	
	# Check combat loot
	if GameState.combat_manager:
		for enemy_id in GameState.combat_manager.enemy_db:
			var enemy = GameState.combat_manager.enemy_db[enemy_id]
			
			# Check standard loot
			for entry in enemy.get("loot", []):
				if entry[0] == symbol:
					sources.append({
						"type": "combat",
						"name": enemy["name"],
						"enemy_id": enemy_id,
						"guaranteed": true,
						"amount": "%d-%d" % [entry[1], entry[2]]
					})
			
			# Check rare loot
			for entry in enemy.get("rare_loot", []):
				if entry[0] == symbol:
					sources.append({
						"type": "combat",
						"name": enemy["name"],
						"enemy_id": enemy_id,
						"chance": entry[1] * 100.0,
						"amount": "%d-%d" % [entry[2], entry[3]]
					})
	
	# Check infrastructure production
	if GameState.infrastructure_manager:
		for building_id in GameState.infrastructure_manager.building_db:
			var building = GameState.infrastructure_manager.building_db[building_id]
			if "yield" in building and symbol in building["yield"]:
				var source = {
					"type": "infrastructure",
					"name": building["name"],
					"building_id": building_id,
					"amount": str(building["yield"][symbol]),
					"interval": building.get("interval", 5.0)
				}
				# Check if locked
				var research_req = building.get("research_req")
				if research_req:
					source["locked"] = not GameState.research_manager.is_tech_unlocked(research_req)
					source["research_req"] = research_req
				else:
					source["locked"] = false
				sources.append(source)
	
	return sources

func get_resource_uses(symbol: String) -> Array:
	"""Find all things that consume/use a resource"""
	var uses = []
	
	# Check processing recipes (inputs)
	if GameState.processing_manager:
		for recipe_id in GameState.processing_manager.recipes:
			var recipe = GameState.processing_manager.recipes[recipe_id]
			if "input" in recipe and symbol in recipe["input"]:
				uses.append({
					"type": "recipe_input",
					"name": recipe["name"],
					"amount": recipe["input"][symbol]
				})
	
	# Check infrastructure costs
	if GameState.infrastructure_manager:
		for building_id in GameState.infrastructure_manager.building_db:
			var building = GameState.infrastructure_manager.building_db[building_id]
			if "cost" in building and symbol in building["cost"]:
				uses.append({
					"type": "building_cost",
					"name": building["name"],
					"amount": building["cost"][symbol]
				})
			# Check building inputs
			if "input" in building and symbol in building["input"]:
				uses.append({
					"type": "building_input",
					"name": building["name"],
					"amount": building["input"][symbol]
				})
	
	# Check shipyard costs
	if GameState.shipyard_manager:
		# Hull costs
		for hull_id in GameState.shipyard_manager.hulls:
			var hull = GameState.shipyard_manager.hulls[hull_id]
			if "cost" in hull and symbol in hull["cost"]:
				uses.append({
					"type": "hull_cost",
					"name": hull["name"],
					"amount": hull["cost"][symbol]
				})
		
		# Module costs
		for module_id in GameState.shipyard_manager.modules:
			var module = GameState.shipyard_manager.modules[module_id]
			if "cost" in module and symbol in module["cost"]:
				uses.append({
					"type": "module_cost",
					"name": module["name"],
					"amount": module["cost"][symbol]
				})
	
	# Check research costs (item costs)
	if GameState.research_manager:
		for tech_id in GameState.research_manager.tech_tree:
			var tech = GameState.research_manager.tech_tree[tech_id]
			if "cost_items" in tech and symbol in tech["cost_items"]:
				uses.append({
					"type": "research_cost",
					"name": tech["name"],
					"amount": tech["cost_items"][symbol]
				})
	
	return uses
