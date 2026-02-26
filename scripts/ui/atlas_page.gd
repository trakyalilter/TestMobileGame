extends Control

## Atlas Page — Game Wiki
## Detailed encyclopedia of all Materials and Enemies

@onready var item_list = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/ScrollContainer/ItemList
@onready var search_box = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/SearchBox
@onready var name_label = $HBoxContainer/RightPanel/MarginContainer/VBoxContainer/NameLabel
@onready var desc_label = $HBoxContainer/RightPanel/MarginContainer/VBoxContainer/ScrollContainer/Details/DescLabel
@onready var sources_list = $HBoxContainer/RightPanel/MarginContainer/VBoxContainer/ScrollContainer/Details/SourcesList
@onready var uses_list = $HBoxContainer/RightPanel/MarginContainer/VBoxContainer/ScrollContainer/Details/UsesList
@onready var net_label = $HBoxContainer/RightPanel/MarginContainer/VBoxContainer/ScrollContainer/Details/NetLabel

# UI Components
var mode_switch_container: HBoxContainer
var btn_materials: Button
var btn_enemies: Button

var current_mode = "materials" # "materials" or "enemies"
var current_filter = "all"
var material_db = {}  # {material_id: {name, sources: [], uses: []}}
var enemy_db = {} # {enemy_id: {name, zone, zone_difficulty, stats, loot}}
var selected_id = ""

func _ready():
	_setup_mode_switch()
	build_databases()

func _setup_mode_switch():
	var left_vbox = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer
	
	mode_switch_container = HBoxContainer.new()
	mode_switch_container.name = "ModeSwitch"
	
	btn_materials = Button.new()
	btn_materials.text = "MATERIALS"
	btn_materials.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_materials.toggle_mode = true
	btn_materials.button_pressed = true
	btn_materials.connect("pressed", _on_mode_materials)
	
	btn_enemies = Button.new()
	btn_enemies.text = "ENEMIES"
	btn_enemies.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_enemies.toggle_mode = true
	btn_enemies.connect("pressed", _on_mode_enemies)
	
	mode_switch_container.add_child(btn_materials)
	mode_switch_container.add_child(btn_enemies)
	
	left_vbox.add_child(mode_switch_container)
	left_vbox.move_child(mode_switch_container, 0)

func _on_visibility_changed():
	if visible:
		build_databases()
		refresh_list()

func _on_mode_materials():
	current_mode = "materials"
	_update_mode_buttons()
	refresh_list()

func _on_mode_enemies():
	current_mode = "enemies"
	_update_mode_buttons()
	refresh_list()

func _update_mode_buttons():
	btn_materials.button_pressed = (current_mode == "materials")
	btn_enemies.button_pressed = (current_mode == "enemies")
	
	var filter_container = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/CategoryFilter
	filter_container.visible = (current_mode == "materials")
	
	name_label.text = "Select an Item"
	desc_label.text = ""
	_clear_list(sources_list)
	_clear_list(uses_list)
	if net_label: net_label.text = ""

func build_databases():
	build_material_database()
	build_enemy_database()

func build_enemy_database():
	enemy_db.clear()
	var cm = GameState.combat_manager
	if not cm: return
	
	# Map enemies to zones with difficulty
	var enemy_to_zone = {}
	var enemy_to_zone_diff = {}
	for zid in cm.zones:
		var zdata = cm.zones[zid]
		for eid in zdata["enemies"]:
			enemy_to_zone[eid] = zdata["name"]
			enemy_to_zone_diff[eid] = zdata.get("difficulty", 0)
	
	for eid in cm.enemy_db:
		var e_data = cm.enemy_db[eid]
		enemy_db[eid] = {
			"name": e_data["name"],
			"zone": enemy_to_zone.get(eid, "Unknown Region"),
			"zone_difficulty": enemy_to_zone_diff.get(eid, 0),
			"stats": e_data["stats"],
			"loot": e_data["loot"],
			"rare_loot": e_data.get("rare_loot", []),
			"xp": e_data.get("xp", 0)
		}

func build_material_database():
	material_db.clear()
	
	# --- GATHERING SOURCES ---
	var gm = GameState.gathering_manager
	if gm:
		for action_id in gm.actions:
			var action = gm.actions[action_id]
			var action_name = action.get("name", action_id)
			for entry in action.get("loot_table", []):
				var mat_id = entry[0]
				ensure_material(mat_id)
				if mat_id in material_db:
					material_db[mat_id]["sources"].append({
						"type": "gathering",
						"name": action_name,
						"rate": "%.0f%% chance" % (entry[1] * 100)
					})
	
	# --- PROCESSING SOURCES & USES ---
	var pm = GameState.processing_manager
	if pm:
		for recipe_id in pm.recipes:
			var recipe = pm.recipes[recipe_id]
			var recipe_name = recipe.get("name", recipe_id)
			
			if "output" in recipe:
				for mat_id in recipe["output"]:
					ensure_material(mat_id)
					if mat_id in material_db:
						material_db[mat_id]["sources"].append({
							"type": "processing",
							"name": recipe_name,
							"rate": "%d per cycle" % recipe["output"][mat_id]
						})
			
			if "input" in recipe:
				for mat_id in recipe["input"]:
					ensure_material(mat_id)
					if mat_id in material_db:
						material_db[mat_id]["uses"].append({
							"type": "processing",
							"name": recipe_name,
							"rate": "%d per cycle" % recipe["input"][mat_id]
						})
	
	# --- COMBAT SOURCES ---
	var cm = GameState.combat_manager
	if cm:
		for enemy_id in cm.enemy_db:
			var enemy = cm.enemy_db[enemy_id]
			var enemy_name = enemy.get("name", enemy_id)
			
			for entry in enemy.get("loot", []):
				var mat_id = entry[0]
				ensure_material(mat_id)
				if mat_id in material_db:
					material_db[mat_id]["sources"].append({
						"type": "combat",
						"name": enemy_name,
						"rate": "%d-%d per kill" % [entry[1], entry[2]]
					})
			
			for entry in enemy.get("rare_loot", []):
				var mat_id = entry[0]
				ensure_material(mat_id)
				if mat_id in material_db:
					material_db[mat_id]["sources"].append({
						"type": "combat",
						"name": enemy_name + " (Rare)",
						"rate": "%.0f%% chance" % (entry[1] * 100)
					})
	
	# --- INFRASTRUCTURE SOURCES & USES ---
	var im = GameState.infrastructure_manager
	if im:
		for bid in im.building_db:
			var bdata = im.building_db[bid]
			var bname = bdata.get("name", bid)
			
			if "yield" in bdata:
				for mat_id in bdata["yield"]:
					ensure_material(mat_id)
					if mat_id in material_db:
						material_db[mat_id]["sources"].append({
							"type": "building",
							"name": bname,
							"rate": "%d per cycle" % bdata["yield"][mat_id]
						})
			
			if "input" in bdata:
				for mat_id in bdata["input"]:
					ensure_material(mat_id)
					if mat_id in material_db:
						material_db[mat_id]["uses"].append({
							"type": "building",
							"name": bname,
							"rate": "%d per cycle" % bdata["input"][mat_id]
						})
			
			if "cost" in bdata:
				for mat_id in bdata["cost"]:
					if mat_id == "credits": continue
					ensure_material(mat_id)
					if mat_id in material_db:
						material_db[mat_id]["uses"].append({
							"type": "building",
							"name": bname + " (Build)",
							"rate": "%d required" % bdata["cost"][mat_id]
						})
	
	# --- SHIPYARD USES ---
	var sm = GameState.shipyard_manager
	if sm:
		for hull_id in sm.hulls:
			var hull = sm.hulls[hull_id]
			var hull_name = hull.get("name", hull_id)
			if "cost" in hull:
				for mat_id in hull["cost"]:
					if mat_id == "credits": continue
					ensure_material(mat_id)
					if mat_id in material_db:
						material_db[mat_id]["uses"].append({
							"type": "shipyard",
							"name": hull_name + " (Hull)",
							"rate": "%d required" % hull["cost"][mat_id]
						})
		
		for mod_id in sm.modules:
			var mod = sm.modules[mod_id]
			var mod_name = mod.get("name", mod_id)
			if "cost" in mod:
				for mat_id in mod["cost"]:
					if mat_id == "credits": continue
					ensure_material(mat_id)
					if mat_id in material_db:
						material_db[mat_id]["uses"].append({
							"type": "shipyard",
							"name": mod_name + " (Module)",
							"rate": "%d required" % mod["cost"][mat_id]
						})
	
	# --- RESEARCH USES ---
	var rm = GameState.research_manager
	if rm:
		for tech_id in rm.tech_tree:
			var tech = rm.tech_tree[tech_id]
			var tech_name = tech.get("name", tech_id)
			if "cost_items" in tech:
				for mat_id in tech["cost_items"]:
					ensure_material(mat_id)
					if mat_id in material_db:
						material_db[mat_id]["uses"].append({
							"type": "research",
							"name": tech_name,
							"rate": "%d required" % tech["cost_items"][mat_id]
						})
	
	# --- FLEET EXPEDITION SOURCES ---
	var fm = GameState.fleet_manager
	if fm:
		for mid in fm.missions:
			var mission = fm.missions[mid]
			var mission_name = mission.get("name", mid)
			if "yield" in mission:
				for mat_id in mission["yield"]:
					if mat_id == "credits": continue
					ensure_material(mat_id)
					if mat_id in material_db:
						material_db[mat_id]["sources"].append({
							"type": "fleet",
							"name": mission_name,
							"rate": "%.1f per cycle" % mission["yield"][mat_id]
						})

func ensure_material(mat_id: String):
	# v73.0: Filter out items that are functionally modules (Boss Drops, Unique Items)
	if GameState.shipyard_manager and mat_id in GameState.shipyard_manager.modules:
		return
		
	if not mat_id in material_db:
		material_db[mat_id] = {
			"name": ElementDB.get_display_name(mat_id),
			"sources": [],
			"uses": []
		}

func refresh_list():
	if not item_list: return
	
	_clear_list(item_list)
	
	var search_term = search_box.text.to_lower()
	
	if current_mode == "materials":
		_populate_materials_list(search_term)
	else:
		_populate_enemies_list(search_term)

func _populate_materials_list(search_term):
	var sorted_keys = material_db.keys()
	sorted_keys.sort()
	
	for mat_id in sorted_keys:
		var mat = material_db[mat_id]
		var mat_name = mat["name"]
		
		if search_term != "" and not mat_name.to_lower().contains(search_term):
			continue
		
		if current_filter != "all":
			var has_match = false
			for source in mat["sources"]:
				if source["type"] == current_filter:
					has_match = true
					break
			if not has_match:
				for use in mat["uses"]:
					if use["type"] == current_filter:
						has_match = true
						break
			if not has_match:
				continue
		
		var btn = Button.new()
		btn.text = mat_name
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.connect("pressed", _on_item_selected.bind(mat_id))
		item_list.add_child(btn)

func _populate_enemies_list(search_term):
	# Group by Zone, sort by difficulty (ascending)
	var enemies_by_zone = {} # {ZoneName: [eid, eid]}
	var zone_difficulty = {} # {ZoneName: difficulty_int}
	
	for eid in enemy_db:
		var e = enemy_db[eid]
		var zone = e["zone"]
		
		if search_term != "" and not e["name"].to_lower().contains(search_term):
			continue
			
		if not zone in enemies_by_zone:
			enemies_by_zone[zone] = []
			zone_difficulty[zone] = e["zone_difficulty"]
		enemies_by_zone[zone].append(eid)
	
	# Sort zones by difficulty (ascending)
	var sorted_zones = enemies_by_zone.keys()
	sorted_zones.sort_custom(func(a, b): return zone_difficulty.get(a, 0) < zone_difficulty.get(b, 0))
	
	for zone in sorted_zones:
		var header = Label.new()
		var diff = zone_difficulty.get(zone, 0)
		header.text = "— %s (★%d) —" % [zone, diff]
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_theme_color_override("font_color", UITheme.COLORS["text_accent"])
		item_list.add_child(header)
		
		for eid in enemies_by_zone[zone]:
			var e = enemy_db[eid]
			var btn = Button.new()
			btn.text = e["name"]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.connect("pressed", _on_item_selected.bind(eid))
			item_list.add_child(btn)

func _on_item_selected(id: String):
	selected_id = id
	
	if current_mode == "materials":
		_display_material_details(id)
	else:
		_display_enemy_details(id)

func _display_material_details(mat_id):
	var mat = material_db[mat_id]
	
	name_label.text = mat["name"]
	
	# Wiki-style description block
	var desc_parts = []
	desc_parts.append("ID: %s" % mat_id)
	
	# Element description from JSON
	var elem_desc = ElementDB.get_element_description(mat_id)
	if elem_desc != "":
		desc_parts.append(elem_desc)
	
	# Market value
	var market_value = ElementDB.get_element_value(mat_id)
	if market_value > 0:
		desc_parts.append("Market Value: %d Cr" % market_value)
	
	# Current inventory
	var owned = GameState.resources.get_element_amount(mat_id)
	if owned > 0:
		desc_parts.append("In Inventory: %d" % owned)
	
	desc_label.text = "\n".join(desc_parts)
	
	# Net Rate
	var im_mgr = GameState.infrastructure_manager
	var net_rates = im_mgr.get_total_resource_rates()
	var rate = net_rates.get(mat_id, 0.0)
	
	if net_label:
		if rate == 0:
			net_label.text = "NET GROWTH: 0.00 /min"
			net_label.modulate = Color(0.7, 0.7, 0.7)
		elif rate > 0:
			net_label.text = "NET GROWTH: +%.2f /min" % rate
			net_label.modulate = Color(0.4, 1.0, 0.4)
		else:
			net_label.text = "NET GROWTH: %.2f /min" % rate
			net_label.modulate = Color(1.0, 0.4, 0.4)
	
	_clear_list(sources_list)
	_clear_list(uses_list)
	
	if mat["sources"].is_empty(): _add_label(sources_list, "No sources found", Color(0.5, 0.5, 0.5))
	else:
		for source in mat["sources"]:
			var icon = _get_type_icon(source["type"])
			_add_label(sources_list, "%s %s (%s)" % [icon, source["name"], source["rate"]], _get_type_color(source["type"]))
	
	if mat["uses"].is_empty(): _add_label(uses_list, "No uses found", Color(0.5, 0.5, 0.5))
	else:
		for use in mat["uses"]:
			var icon = _get_type_icon(use["type"])
			_add_label(uses_list, "%s %s (%s)" % [icon, use["name"], use["rate"]], _get_type_color(use["type"]))

func _display_enemy_details(eid):
	var e = enemy_db.get(eid)
	if not e: return
	
	name_label.text = e["name"]
	
	# Wiki-style description block
	var desc_parts = []
	desc_parts.append("Zone: %s" % e["zone"])
	desc_parts.append("Zone Difficulty: ★%d" % e["zone_difficulty"])
	desc_parts.append("XP Value: %d" % e["xp"])
	
	# Compute effective DPS
	var atk = e["stats"]["atk"]
	var interval = e["stats"].get("atk_interval", 2.0)
	if interval > 0:
		desc_parts.append("Effective DPS: %.1f" % (float(atk) / interval))
	
	# Compute effective HP (HP + Shield)
	var total_ehp = e["stats"]["hp"] + e["stats"]["max_shield"]
	desc_parts.append("Effective HP: %d" % total_ehp)
	
	desc_label.text = "\n".join(desc_parts)
	if net_label: net_label.text = ""
	
	_clear_list(sources_list)
	_clear_list(uses_list)
	
	# Use "Sources List" for Stats
	var stats_header = Label.new()
	stats_header.text = "COMBAT STATISTICS"
	stats_header.add_theme_font_size_override("font_size", 16)
	stats_header.add_theme_color_override("font_color", UITheme.COLORS["text_accent"])
	sources_list.add_child(stats_header)
	
	_add_stat_row(sources_list, "Health", e["stats"]["hp"])
	_add_stat_row(sources_list, "Shield", e["stats"]["max_shield"])
	_add_stat_row(sources_list, "Attack", e["stats"]["atk"])
	_add_stat_row(sources_list, "Defense", e["stats"]["def"])
	_add_stat_row(sources_list, "Attack Interval", "%.1fs" % e["stats"].get("atk_interval", 2.0))
	_add_stat_row(sources_list, "Accuracy", e["stats"].get("accuracy", 0))
	_add_stat_row(sources_list, "Evasion", e["stats"].get("eva", 0))
	
	# Use "Uses List" for Loot Table
	var loot_header = Label.new()
	loot_header.text = "DROPS"
	loot_header.add_theme_font_size_override("font_size", 16)
	loot_header.add_theme_color_override("font_color", UITheme.COLORS["text_accent"])
	uses_list.add_child(loot_header)
	
	for entry in e.get("loot", []):
		var mat_name = ElementDB.get_display_name(entry[0])
		var qty = "%d-%d" % [entry[1], entry[2]]
		_add_label(uses_list, "• %s (%s)" % [mat_name, qty], Color.WHITE)
		
	var rare_loot = e.get("rare_loot", [])
	if not rare_loot.is_empty():
		_add_label(uses_list, "-- RARE DROPS --", UITheme.COLORS["warning"])
		for entry in rare_loot:
			var mat_name = ElementDB.get_display_name(entry[0])
			var chance = "%.1f%%" % (entry[1] * 100)
			var qty = "%d-%d" % [entry[2], entry[3]]
			_add_label(uses_list, "★ %s (%s, %s)" % [mat_name, chance, qty], UITheme.COLORS["warning"])

	# Module Drops
	var drop_chance = e.get("module_drop_chance", 0.0)
	var drop_pool = e.get("module_drop_pool", [])
	if drop_chance > 0.0 and not drop_pool.is_empty() and GameState.shipyard_manager:
		_add_label(uses_list, "-- MODULE DROPS --", UITheme.CATEGORY_COLORS["shipyard"])
		_add_label(uses_list, "Drop Chance: %.1f%%" % (drop_chance * 100), UITheme.COLORS["text_accent"])
		for mod_id in drop_pool:
			var mod = GameState.shipyard_manager.modules.get(mod_id, {})
			var mod_name = mod.get("name", mod_id)
			_add_label(uses_list, "• %s" % mod_name, Color.WHITE)

func _add_stat_row(parent, label, value):
	var lbl = Label.new()
	lbl.text = "%s: %s" % [label, str(value)]
	parent.add_child(lbl)

func _clear_list(node):
	for child in node.get_children():
		child.queue_free()

func _add_label(parent, text, color):
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)

func _get_type_icon(type: String) -> String:
	match type:
		"gathering": return "⛏️"
		"processing": return "⚙️"
		"combat": return "⚔️"
		"building": return "🏭"
		"shipyard": return "🚀"
		"research": return "🔬"
		"fleet": return "🛸"
		_: return "📦"

func _get_type_color(type: String) -> Color:
	match type:
		"gathering": return Color(0.6, 0.4, 0.2)
		"processing": return Color(0.5, 0.5, 0.8)
		"combat": return Color(0.9, 0.3, 0.3)
		"building": return Color(0.4, 0.7, 0.4)
		"shipyard": return Color(0.3, 0.7, 0.9)
		"research": return Color(0.8, 0.6, 0.9)
		"fleet": return Color(0.9, 0.7, 0.3)
		_: return Color(0.7, 0.7, 0.7)

func _on_search_changed(_text):
	refresh_list()

func _on_filter_all():
	current_filter = "all"
	_update_filter_buttons("AllBtn")
	refresh_list()

func _on_filter_gather():
	current_filter = "gathering"
	_update_filter_buttons("GatherBtn")
	refresh_list()

func _on_filter_process():
	current_filter = "processing"
	_update_filter_buttons("ProcessBtn")
	refresh_list()

func _on_filter_combat():
	current_filter = "combat"
	_update_filter_buttons("CombatBtn")
	refresh_list()

func _on_filter_building():
	current_filter = "building"
	_update_filter_buttons("BuildingBtn")
	refresh_list()

func _on_filter_shipyard():
	current_filter = "shipyard"
	_update_filter_buttons("ShipyardBtn")
	refresh_list()

func _on_filter_research():
	current_filter = "research"
	_update_filter_buttons("ResearchBtn")
	refresh_list()

func _on_filter_fleet():
	current_filter = "fleet"
	_update_filter_buttons("FleetBtn")
	refresh_list()

func _update_filter_buttons(active_btn: String):
	var filter_container = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/CategoryFilter
	for child in filter_container.get_children():
		if child is Button:
			child.button_pressed = (child.name == active_btn)
