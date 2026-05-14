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

# Sort controls (built in _setup_sort_bar)
var sort_bar: HBoxContainer
var btn_sort_az: Button
var btn_sort_inv: Button
var btn_sort_tier: Button

var current_mode = "materials" # "materials" or "enemies"
var current_filter = "all"
var current_sort = "az"  # "az" | "inv" | "tier"
var material_db = {}  # {material_id: {name, sources: [], uses: []}}
var enemy_db = {} # {enemy_id: {name, zone, zone_difficulty, stats, loot}}
var selected_id = ""

# Tier index by ElementDB category — drives badge color & sort order
const TIER_ORDER = {
	"ores": 1, "basic_metals": 1,
	"advanced_metals": 2, "components": 2, "alloys": 2,
	"rare_metals": 3, "ammo": 3, "batteries": 3,
	"consumables": 3,
	"special": 4,
	"endgame": 5, "boss_cores": 5, "matrix_cores": 5
}
const TIER_COLORS = {
	1: Color(0.65, 0.65, 0.70),         # gray  — basic
	2: Color(0.40, 0.85, 0.50),         # green — refined
	3: Color(0.35, 0.65, 1.00),         # blue  — advanced
	4: Color(0.85, 0.45, 1.00),         # purple — exotic
	5: Color(1.00, 0.65, 0.20)          # gold  — endgame
}
const CATEGORY_STRIPE = {
	"gathering":  Color(0.85, 0.55, 0.20),  # orange — pickaxe
	"processing": Color(0.45, 0.55, 0.95),  # blue   — gear
	"combat":     Color(0.95, 0.30, 0.30),  # red    — sword
	"building":   Color(0.40, 0.80, 0.45),  # green  — factory
	"shipyard":   Color(0.30, 0.70, 0.95),  # cyan   — rocket
	"research":   Color(0.80, 0.55, 0.95),  # violet — science
}

func _ready():
	_setup_mode_switch()
	_setup_sort_bar()
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

func _setup_sort_bar():
	# Sort row below the search box — A→Z / Inventory / Tier
	var left_vbox = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer

	sort_bar = HBoxContainer.new()
	sort_bar.name = "SortBar"
	sort_bar.add_theme_constant_override("separation", 6)

	var label = Label.new()
	label.text = "Sort:"
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.72))
	sort_bar.add_child(label)

	btn_sort_az = _make_sort_btn("A→Z", "az")
	btn_sort_inv = _make_sort_btn("Inventory", "inv")
	btn_sort_tier = _make_sort_btn("Tier", "tier")
	sort_bar.add_child(btn_sort_az)
	sort_bar.add_child(btn_sort_inv)
	sort_bar.add_child(btn_sort_tier)

	# Insert below SearchBox
	left_vbox.add_child(sort_bar)
	var search_box_node = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/SearchBox
	left_vbox.move_child(sort_bar, search_box_node.get_index() + 1)
	_update_sort_buttons()

func _make_sort_btn(label: String, mode: String) -> Button:
	var b = Button.new()
	b.text = label
	b.toggle_mode = true
	b.add_theme_font_size_override("font_size", 11)
	b.button_pressed = (current_sort == mode)
	b.pressed.connect(func():
		current_sort = mode
		_update_sort_buttons()
		refresh_list()
	)
	return b

func _update_sort_buttons():
	if btn_sort_az: btn_sort_az.button_pressed = (current_sort == "az")
	if btn_sort_inv: btn_sort_inv.button_pressed = (current_sort == "inv")
	if btn_sort_tier: btn_sort_tier.button_pressed = (current_sort == "tier")

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
	desc_label.text = "Pick %s from the list to view full details." % ("a material" if current_mode == "materials" else "an enemy")
	desc_label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
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
			"boss_core": e_data.get("boss_core", ""),
			"xp": e_data.get("xp", 0),
			"dmg_type": e_data.get("dmg_type", "kinetic")
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
			
			if "boss_core" in enemy and enemy["boss_core"] != "":
				var core_id = enemy["boss_core"]
				ensure_material(core_id)
				if core_id in material_db:
					material_db[core_id]["sources"].append({
						"type": "combat",
						"name": enemy_name + " (Boss)",
						"rate": "100% (Guaranteed)"
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

func _get_material_tier(mat_id: String) -> int:
	var cat = ElementDB.get_category(mat_id)
	return TIER_ORDER.get(cat, 2)

func _get_primary_source_type(mat: Dictionary) -> String:
	# Pick a source-type to color-code by; prefer gathering > combat > processing > building
	var priority = ["gathering", "combat", "processing", "building", "shipyard", "research"]
	var seen = {}
	for s in mat.get("sources", []):
		seen[s["type"]] = true
	for p in priority:
		if p in seen: return p
	return ""

func _populate_materials_list(search_term):
	var sorted_keys = material_db.keys()

	match current_sort:
		"az":
			sorted_keys.sort()
		"inv":
			sorted_keys.sort_custom(func(a, b):
				return GameState.resources.get_element_amount(a) > GameState.resources.get_element_amount(b))
		"tier":
			sorted_keys.sort_custom(func(a, b):
				var ta = _get_material_tier(a)
				var tb = _get_material_tier(b)
				if ta != tb: return ta < tb
				return material_db[a]["name"] < material_db[b]["name"])

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

		var card = _build_material_card(mat_id, mat)
		item_list.add_child(card)

func _build_material_card(mat_id: String, mat: Dictionary) -> Control:
	var tier = _get_material_tier(mat_id)
	var tier_color = TIER_COLORS.get(tier, Color.WHITE)
	var stripe_color = CATEGORY_STRIPE.get(_get_primary_source_type(mat), Color(0.4, 0.4, 0.45))
	var owned = GameState.resources.get_element_amount(mat_id) if GameState.resources else 0.0

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 44)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.17, 0.95)
	style.border_color = stripe_color
	style.border_width_left = 4
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)

	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(0.16, 0.20, 0.28, 1.0)
	hover.border_color = stripe_color
	hover.border_width_left = 4
	hover.corner_radius_top_left = 4
	hover.corner_radius_top_right = 4
	hover.corner_radius_bottom_left = 4
	hover.corner_radius_bottom_right = 4

	# Clickable button overlay
	var btn = Button.new()
	btn.flat = true
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.pressed.connect(_on_item_selected.bind(mat_id))
	btn.mouse_entered.connect(func(): panel.add_theme_stylebox_override("panel", hover))
	btn.mouse_exited.connect(func(): panel.add_theme_stylebox_override("panel", style))

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(hbox)

	# Tier badge
	var tier_lbl = Label.new()
	tier_lbl.text = "T%d" % tier
	tier_lbl.add_theme_font_size_override("font_size", 11)
	tier_lbl.add_theme_color_override("font_color", tier_color)
	tier_lbl.custom_minimum_size = Vector2(26, 0)
	tier_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(tier_lbl)

	# Name
	var name_lbl = Label.new()
	name_lbl.text = mat["name"]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(name_lbl)

	# Inventory count
	var inv_lbl = Label.new()
	inv_lbl.text = "x%s" % UITheme.format_num(owned)
	inv_lbl.add_theme_font_size_override("font_size", 11)
	inv_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if owned <= 0:
		inv_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.50))
	elif owned >= 1000:
		inv_lbl.add_theme_color_override("font_color", Color(0.45, 1.00, 0.55))
	else:
		inv_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	hbox.add_child(inv_lbl)

	panel.add_child(btn)
	return panel

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
		header.text = "—  %s  ★%d  —" % [zone, diff]
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_theme_color_override("font_color", UITheme.COLORS["text_accent"])
		header.add_theme_font_size_override("font_size", 12)
		item_list.add_child(header)

		for eid in enemies_by_zone[zone]:
			var card = _build_enemy_card(eid, enemy_db[eid])
			item_list.add_child(card)

func _build_enemy_card(eid: String, e: Dictionary) -> Control:
	# Compute threat color for stripe — same logic as detail panel but compressed
	var sm = GameState.shipyard_manager
	var atk = e["stats"].get("atk", 0)
	var interval = e["stats"].get("atk_interval", 2.0)
	var enemy_dps = float(atk) / max(0.5, interval)
	var enemy_ehp = e["stats"].get("hp", 0) + e["stats"].get("max_shield", 0)
	var stripe_color = Color(0.5, 0.5, 0.55)
	var threat_short = ""
	if sm and sm.attack_kinetic + sm.attack_energy + sm.attack_explosive > 0 and sm.max_hp > 0:
		var p_dps = float(sm.attack_kinetic + sm.attack_energy + sm.attack_explosive)
		var p_ehp = float(sm.max_hp + sm.max_shield)
		var p_ttk = float(enemy_ehp) / max(1.0, p_dps)
		var e_ttk = float(p_ehp) / max(1.0, enemy_dps)
		var ratio = e_ttk / max(0.01, p_ttk)
		if ratio >= 3.0:    stripe_color = Color(0.45, 1.00, 0.50); threat_short = "TRIVIAL"
		elif ratio >= 1.5:  stripe_color = Color(0.55, 0.95, 0.70); threat_short = "OK"
		elif ratio >= 0.75: stripe_color = Color(1.00, 0.85, 0.30); threat_short = "TOUGH"
		elif ratio >= 0.35: stripe_color = Color(1.00, 0.50, 0.20); threat_short = "LETHAL"
		else:               stripe_color = Color(1.00, 0.30, 0.30); threat_short = "★ DEADLY"

	var is_boss = e.get("boss_core", "") != ""
	if is_boss:
		stripe_color = stripe_color.lerp(Color(1.0, 0.85, 0.20), 0.4)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 44)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.17, 0.95)
	style.border_color = stripe_color
	style.border_width_left = 4
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)

	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(0.16, 0.20, 0.28, 1.0)
	hover.border_color = stripe_color
	hover.border_width_left = 4
	hover.corner_radius_top_left = 4
	hover.corner_radius_top_right = 4
	hover.corner_radius_bottom_left = 4
	hover.corner_radius_bottom_right = 4

	var btn = Button.new()
	btn.flat = true
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.pressed.connect(_on_item_selected.bind(eid))
	btn.mouse_entered.connect(func(): panel.add_theme_stylebox_override("panel", hover))
	btn.mouse_exited.connect(func(): panel.add_theme_stylebox_override("panel", style))

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(hbox)

	if is_boss:
		var boss_lbl = Label.new()
		boss_lbl.text = "★"
		boss_lbl.add_theme_font_size_override("font_size", 14)
		boss_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.20))
		boss_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(boss_lbl)

	var name_lbl = Label.new()
	name_lbl.text = e["name"]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(name_lbl)

	if threat_short != "":
		var th_lbl = Label.new()
		th_lbl.text = threat_short
		th_lbl.add_theme_font_size_override("font_size", 10)
		th_lbl.add_theme_color_override("font_color", stripe_color)
		th_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(th_lbl)

	panel.add_child(btn)
	return panel

func _on_item_selected(id: String):
	selected_id = id
	
	if current_mode == "materials":
		_display_material_details(id)
	else:
		_display_enemy_details(id)

func _display_material_details(mat_id):
	var mat = material_db[mat_id]

	name_label.text = mat["name"]

	# Stat block (rendered inline via desc_label BBCode-like single string, plus net_label)
	var tier = _get_material_tier(mat_id)
	var tier_color = TIER_COLORS.get(tier, Color.WHITE)
	var owned = GameState.resources.get_element_amount(mat_id) if GameState.resources else 0.0
	var market_value = ElementDB.get_element_value(mat_id)
	var cat = ElementDB.get_category(mat_id).replace("_", " ").capitalize()
	var elem_desc = ElementDB.get_element_description(mat_id)

	var stat_lines = []
	stat_lines.append("OWNED: %s    |    TIER %d (%s)    |    VALUE: %s Cr" % [
		UITheme.format_num(owned),
		tier,
		cat,
		UITheme.format_num(market_value) if market_value > 0 else "—"
	])
	stat_lines.append("ID: %s" % mat_id)
	if elem_desc != "":
		stat_lines.append("")
		stat_lines.append(elem_desc)

	desc_label.text = "\n".join(stat_lines)
	desc_label.add_theme_color_override("font_color", tier_color)

	# Net Rate
	var im_mgr = GameState.infrastructure_manager
	var net_rates = im_mgr.get_total_resource_rates()
	var rate = net_rates.get(mat_id, 0.0)

	if net_label:
		if rate == 0:
			net_label.text = "⏸  NET GROWTH: 0.00 /min"
			net_label.modulate = Color(0.7, 0.7, 0.7)
		elif rate > 0:
			net_label.text = "▲ NET GROWTH: +%.2f /min" % rate
			net_label.modulate = Color(0.4, 1.0, 0.4)
		else:
			net_label.text = "▼ NET DRAIN: %.2f /min" % rate
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

	var e_raw = GameState.combat_manager.enemy_db.get(eid, {})

	# Compute effective DPS / EHP
	var atk = e["stats"].get("atk", 0)
	var interval = e["stats"].get("atk_interval", 2.0)
	var enemy_dps = float(atk) / max(0.5, interval)
	var enemy_ehp = e["stats"].get("hp", 0) + e["stats"].get("max_shield", 0)

	# Compute player power
	var sm = GameState.shipyard_manager
	var player_dps = 0.0
	var player_ehp = 0.0
	if sm:
		player_dps = float(sm.attack_kinetic + sm.attack_energy + sm.attack_explosive)
		player_ehp = float(sm.max_hp + sm.max_shield)

	# Threat rating
	var threat = "UNKNOWN"
	var threat_color = Color(0.7, 0.7, 0.7)
	if player_dps > 0 and player_ehp > 0:
		# Time to kill comparison: how much HP enemy strips of player vs player strips of enemy
		var player_ttk = float(enemy_ehp) / max(1.0, player_dps)
		var enemy_ttk = float(player_ehp) / max(1.0, enemy_dps)
		var ratio = enemy_ttk / max(0.01, player_ttk)
		if ratio >= 3.0:
			threat = "TRIVIAL"
			threat_color = Color(0.45, 1.00, 0.50)
		elif ratio >= 1.5:
			threat = "MANAGEABLE"
			threat_color = Color(0.55, 0.95, 0.70)
		elif ratio >= 0.75:
			threat = "DANGEROUS"
			threat_color = Color(1.0, 0.85, 0.30)
		elif ratio >= 0.35:
			threat = "LETHAL"
			threat_color = Color(1.0, 0.50, 0.20)
		else:
			threat = "OVERWHELMING"
			threat_color = Color(1.0, 0.30, 0.30)

	# Build resistance & weakness chip strings
	var rk = e_raw.get("resist_k", 0.0)
	var re = e_raw.get("resist_e", 0.0)
	var rx = e_raw.get("resist_x", 0.0)
	var resist_chips = []
	var weak_chips = []
	if rk >= 0.10: resist_chips.append("KIN +%d%%" % int(rk * 100))
	elif rk <= -0.10: weak_chips.append("KIN %d%%" % int(rk * 100))
	if re >= 0.10: resist_chips.append("ENG +%d%%" % int(re * 100))
	elif re <= -0.10: weak_chips.append("ENG %d%%" % int(re * 100))
	if rx >= 0.10: resist_chips.append("EXP +%d%%" % int(rx * 100))
	elif rx <= -0.10: weak_chips.append("EXP %d%%" % int(rx * 100))

	var desc_parts = []
	desc_parts.append("ZONE: %s  ★%d   |   XP: %d" % [e["zone"], e["zone_difficulty"], e["xp"]])
	desc_parts.append("THREAT: %s" % threat)
	desc_parts.append("Effective HP: %s    |    DPS: %.1f    |    Attacks with: %s" % [
		UITheme.format_num(enemy_ehp),
		enemy_dps,
		e.get("dmg_type", "kinetic").to_upper()
	])
	if not resist_chips.is_empty():
		desc_parts.append("RESISTS: " + "  ".join(resist_chips))
	if not weak_chips.is_empty():
		desc_parts.append("WEAK TO: " + "  ".join(weak_chips))

	desc_label.text = "\n".join(desc_parts)
	desc_label.add_theme_color_override("font_color", threat_color)

	if net_label: net_label.text = ""
	
	_clear_list(sources_list)
	_clear_list(uses_list)
	
	# Use "Sources List" for Stats
	var stats_header = Label.new()
	stats_header.text = "COMBAT STATISTICS"
	stats_header.add_theme_font_size_override("font_size", 16)
	stats_header.add_theme_color_override("font_color", UITheme.COLORS["text_accent"])
	sources_list.add_child(stats_header)
	
	_add_stat_row(sources_list, "Health", e["stats"].get("hp", 0))
	_add_stat_row(sources_list, "Shield", e["stats"].get("max_shield", 0))
	_add_stat_row(sources_list, "Attack", e["stats"].get("atk", 0))
	_add_stat_row(sources_list, "Defense", e["stats"].get("def", 0))
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
		var mat_name = _get_pretty_name(entry[0])
		var qty = "%d-%d" % [entry[1], entry[2]]
		_add_label(uses_list, "• %s (%s)" % [mat_name, qty], Color.WHITE)
		
	var core_id = e.get("boss_core", "")
	if core_id != "":
		var core_name = _get_pretty_name(core_id)
		_add_label(uses_list, "★ %s (100%% Guaranteed)" % core_name, Color.ORANGE)
		
	var rare_loot = e.get("rare_loot", [])
	if not rare_loot.is_empty():
		_add_label(uses_list, "-- RARE DROPS --", UITheme.COLORS["warning"])
		for entry in rare_loot:
			var mat_name = _get_pretty_name(entry[0])
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

func _on_filter_shipyard():
	current_filter = "shipyard"
	_update_filter_buttons("ShipyardBtn")
	refresh_list()

func _on_filter_research():
	current_filter = "research"
	_update_filter_buttons("ResearchBtn")
	refresh_list()


func _update_filter_buttons(active_btn: String):
	var filter_container = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/CategoryFilter
	for child in filter_container.get_children():
		if child is Button:
			child.button_pressed = (child.name == active_btn)

func _get_pretty_name(id: String) -> String:
	# Try Element DB first
	var name = ElementDB.get_display_name(id)
	if name != id:
		return name
	
	# Try Module DB
	if GameState.shipyard_manager and id in GameState.shipyard_manager.modules:
		return GameState.shipyard_manager.modules[id].get("name", id)
		
	return id
