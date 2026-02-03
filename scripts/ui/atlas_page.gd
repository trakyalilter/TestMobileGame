extends Control

## Material Atlas Page
## Shows all materials in the game with their sources and uses

@onready var item_list = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/ScrollContainer/ItemList
@onready var search_box = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/SearchBox
@onready var name_label = $HBoxContainer/RightPanel/MarginContainer/VBoxContainer/NameLabel
@onready var desc_label = $HBoxContainer/RightPanel/MarginContainer/VBoxContainer/ScrollContainer/Details/DescLabel
@onready var sources_list = $HBoxContainer/RightPanel/MarginContainer/VBoxContainer/ScrollContainer/Details/SourcesList
@onready var uses_list = $HBoxContainer/RightPanel/MarginContainer/VBoxContainer/ScrollContainer/Details/UsesList
@onready var net_label = $HBoxContainer/RightPanel/MarginContainer/VBoxContainer/ScrollContainer/Details/NetLabel # Needs to be added to scene or handled

var current_filter = "all"
var material_db = {}  # {material_id: {name, sources: [], uses: []}}
var selected_material = ""

func _ready():
	build_material_database()

func _on_visibility_changed():
	if visible:
		build_material_database()
		refresh_list()

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
			
			# Outputs = Sources
			if "output" in recipe:
				for mat_id in recipe["output"]:
					ensure_material(mat_id)
					material_db[mat_id]["sources"].append({
						"type": "processing",
						"name": recipe_name,
						"rate": "%d per cycle" % recipe["output"][mat_id]
					})
			
			# Inputs = Uses
			if "input" in recipe:
				for mat_id in recipe["input"]:
					ensure_material(mat_id)
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
			
			# Base loot
			for entry in enemy.get("loot", []):
				var mat_id = entry[0]
				ensure_material(mat_id)
				material_db[mat_id]["sources"].append({
					"type": "combat",
					"name": enemy_name,
					"rate": "%d-%d per kill" % [entry[1], entry[2]]
				})
			
			# Rare loot
			for entry in enemy.get("rare_loot", []):
				var mat_id = entry[0]
				ensure_material(mat_id)
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
			
			# Yield = Sources
			if "yield" in bdata:
				for mat_id in bdata["yield"]:
					ensure_material(mat_id)
					material_db[mat_id]["sources"].append({
						"type": "building",
						"name": bname,
						"rate": "%d per cycle" % bdata["yield"][mat_id]
					})
			
			# Input = Uses
			if "input" in bdata:
				for mat_id in bdata["input"]:
					ensure_material(mat_id)
					material_db[mat_id]["uses"].append({
						"type": "building",
						"name": bname,
						"rate": "%d per cycle" % bdata["input"][mat_id]
					})
			
			# Construction costs = Uses
			if "cost" in bdata:
				for mat_id in bdata["cost"]:
					if mat_id == "credits": continue
					ensure_material(mat_id)
					material_db[mat_id]["uses"].append({
						"type": "building",
						"name": bname + " (Build)",
						"rate": "%d required" % bdata["cost"][mat_id]
					})
	
	# --- SHIPYARD USES ---
	var sm = GameState.shipyard_manager
	if sm:
		# Hulls
		for hull_id in sm.hulls:
			var hull = sm.hulls[hull_id]
			var hull_name = hull.get("name", hull_id)
			if "cost" in hull:
				for mat_id in hull["cost"]:
					if mat_id == "credits": continue
					ensure_material(mat_id)
					material_db[mat_id]["uses"].append({
						"type": "shipyard",
						"name": hull_name + " (Hull)",
						"rate": "%d required" % hull["cost"][mat_id]
					})
		
		# Modules
		for mod_id in sm.modules:
			var mod = sm.modules[mod_id]
			var mod_name = mod.get("name", mod_id)
			if "cost" in mod:
				for mat_id in mod["cost"]:
					if mat_id == "credits": continue
					ensure_material(mat_id)
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
					material_db[mat_id]["uses"].append({
						"type": "research",
						"name": tech_name,
						"rate": "%d required" % tech["cost_items"][mat_id]
					})

func ensure_material(mat_id: String):
	if not mat_id in material_db:
		material_db[mat_id] = {
			"name": ElementDB.get_display_name(mat_id),
			"sources": [],
			"uses": []
		}

func refresh_list():
	# Guard against null nodes
	if not item_list or not search_box:
		return
	
	# Clear existing
	for child in item_list.get_children():
		child.queue_free()
	
	var search_term = search_box.text.to_lower()
	var sorted_keys = material_db.keys()
	sorted_keys.sort()
	
	for mat_id in sorted_keys:
		var mat = material_db[mat_id]
		var mat_name = mat["name"]
		
		# Filter by search
		if search_term != "" and not mat_name.to_lower().contains(search_term) and not mat_id.to_lower().contains(search_term):
			continue
		
		# Filter by category
		if current_filter != "all":
			var has_match = false
			for source in mat["sources"]:
				if source["type"] == current_filter:
					has_match = true
					break
			if not has_match:
				continue
		
		var btn = Button.new()
		btn.text = mat_name
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.connect("pressed", _on_material_selected.bind(mat_id))
		item_list.add_child(btn)

func _on_material_selected(mat_id: String):
	# Guard against null nodes
	if not name_label or not desc_label or not sources_list or not uses_list:
		return
	
	selected_material = mat_id
	var mat = material_db[mat_id]
	
	name_label.text = mat["name"]
	desc_label.text = "ID: %s" % mat_id
	
	# Update Net Rate
	var im = GameState.infrastructure_manager
	var net_rates = im.get_total_resource_rates()
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
	
	# Clear old entries
	for child in sources_list.get_children():
		child.queue_free()
	for child in uses_list.get_children():
		child.queue_free()
	
	# Populate sources
	if mat["sources"].is_empty():
		var lbl = Label.new()
		lbl.text = "No sources found"
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		sources_list.add_child(lbl)
	else:
		for source in mat["sources"]:
			var lbl = Label.new()
			var icon = _get_type_icon(source["type"])
			lbl.text = "%s %s (%s)" % [icon, source["name"], source["rate"]]
			lbl.add_theme_color_override("font_color", _get_type_color(source["type"]))
			sources_list.add_child(lbl)
	
	# Populate uses
	if mat["uses"].is_empty():
		var lbl = Label.new()
		lbl.text = "No uses found"
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		uses_list.add_child(lbl)
	else:
		for use in mat["uses"]:
			var lbl = Label.new()
			var icon = _get_type_icon(use["type"])
			lbl.text = "%s %s (%s)" % [icon, use["name"], use["rate"]]
			lbl.add_theme_color_override("font_color", _get_type_color(use["type"]))
			uses_list.add_child(lbl)

func _get_type_icon(type: String) -> String:
	match type:
		"gathering": return "⛏️"
		"processing": return "⚙️"
		"combat": return "⚔️"
		"building": return "🏭"
		"shipyard": return "🚀"
		"research": return "🔬"
		_: return "📦"

func _get_type_color(type: String) -> Color:
	match type:
		"gathering": return Color(0.6, 0.4, 0.2)
		"processing": return Color(0.5, 0.5, 0.8)
		"combat": return Color(0.9, 0.3, 0.3)
		"building": return Color(0.4, 0.7, 0.4)
		"shipyard": return Color(0.3, 0.7, 0.9)
		"research": return Color(0.8, 0.6, 0.9)
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

func _update_filter_buttons(active_btn: String):
	var filter_container = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/CategoryFilter
	for child in filter_container.get_children():
		if child is Button:
			child.button_pressed = (child.name == active_btn)
