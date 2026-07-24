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

# v124: datasheet detail-panel redesign. Code-built blocks inserted at the top of
# Details, tracked here so they are freed + rebuilt on every selection / mode
# switch (never stacking, never bleeding across material↔enemy modes).
var _hero_block: HBoxContainer = null
var _identity_row: HBoxContainer = null

# Coach card + gold highlight box for the m019e "Field Manual" atlas-lookup
# lesson (both freed on any re-selection / mode switch via _clear_inserted_blocks).
var _coach_card: Control = null
var _coach_hl: Control = null

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
# v116: source/use type icons reuse the (white, tintable) nav SVGs instead of
# colourful emoji. Tinted per-type via modulate.
const TYPE_ICON_PATHS = {
	"gathering":  "res://assets/icons/nav/mine.svg",
	"processing": "res://assets/icons/nav/engineering.svg",
	"combat":     "res://assets/icons/nav/combat.svg",
	"building":   "res://assets/icons/nav/infrastructure.svg",
	"shipyard":   "res://assets/icons/nav/shipyard.svg",
	"research":   "res://assets/icons/nav/research.svg",
}

func _ready():
	_setup_mode_switch()
	_setup_sort_bar()
	build_databases()
	# Clean placeholder: the .tscn "Sources"/"Uses" static titles and the centered
	# NET-zero line shouldn't show until (and unless) an item is selected.
	_hide_static_titles()
	if net_label: net_label.visible = false

func get_coach_anchor(key: String) -> Control:
	match key:
		"list":
			return item_list
		"details":
			return $HBoxContainer/RightPanel
	return null

func _setup_mode_switch():
	var left_vbox = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer
	
	mode_switch_container = HBoxContainer.new()
	mode_switch_container.name = "ModeSwitch"
	
	btn_materials = Button.new()
	btn_materials.text = tr("MATERIALS")
	btn_materials.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_materials.toggle_mode = true
	btn_materials.button_pressed = true
	btn_materials.connect("pressed", _on_mode_materials)
	
	btn_enemies = Button.new()
	btn_enemies.text = tr("ENEMIES")
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
	label.text = tr("Sort:")
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
	else:
		# The Field Manual coach card + highlight box are parented to ModalLayer (they
		# float above the page), so they must be freed when the Atlas hides or they
		# strand over other pages.
		if _coach_card and is_instance_valid(_coach_card):
			_coach_card.queue_free()
		_coach_card = null
		if _coach_hl and is_instance_valid(_coach_hl):
			_coach_hl.queue_free()
		_coach_hl = null

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

	# Reset to a clean placeholder — no stale hero/identity block, stat grid, or
	# Sources/Uses titles from the other mode.
	_clear_inserted_blocks()
	_hide_static_titles()
	name_label.text = tr("Select an Item")
	desc_label.visible = true
	desc_label.text = tr("Pick %s from the list to view full details.") % (tr("a material") if current_mode == "materials" else tr("an enemy"))
	desc_label.add_theme_color_override("font_color", UITheme.COLORS["text_dim"])
	_clear_list(sources_list)
	_clear_list(uses_list)
	if net_label: net_label.visible = false

func build_databases():
	build_material_database()
	build_enemy_database()

func build_enemy_database():
	enemy_db.clear()
	var cm = GameState.combat_manager
	if not cm: return
	
	# v116: only enemies from UNLOCKED zones — the atlas shouldn't list (or
	# spoil) enemies the player can't yet reach. Built from available zones only
	# (get_available_zones honours unlock_flag + research_req + hazards).
	var enemy_to_zone = {}
	var enemy_to_zone_diff = {}
	var enemy_to_zone_desc = {}
	for entry in cm.get_available_zones():
		var zdata = entry["data"]
		var z_enemies = zdata.get("enemies", [])
		if z_enemies.is_empty() and entry.get("is_hazard", false):
			z_enemies = cm.hazard_zones.get(entry["id"], {}).get("enemies", [])
		for eid in z_enemies:
			enemy_to_zone[eid] = zdata["name"]
			enemy_to_zone_diff[eid] = zdata.get("difficulty", 0)
			enemy_to_zone_desc[eid] = zdata.get("desc", "")

	for eid in cm.enemy_db:
		if not eid in enemy_to_zone:
			continue   # belongs only to locked/unreachable zones — hide it
		var e_data = cm.enemy_db[eid]
		enemy_db[eid] = {
			"name": e_data["name"],
			"zone": enemy_to_zone[eid],
			"zone_difficulty": enemy_to_zone_diff[eid],
			"zone_desc": enemy_to_zone_desc.get(eid, ""),
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
						"rate": tr("%.0f%% chance") % (entry[1] * 100)
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
							"rate": tr("%d per cycle") % recipe["output"][mat_id]
						})

			# v139k: byproducts declared via output_table were NEVER scanned — so a
			# material with NO plain `output` recipe (Ag from Zinc Reduction, Co from Ni
			# refining, Pd, PathogenCore…) read as "No known source" in the Atlas even
			# though it's fully obtainable (owner: Silver shows unsourced but feeds Adv
			# Circuits). Entry format: [item, chance, min_q, max_q].
			if "output_table" in recipe:
				for entry in recipe["output_table"]:
					if not (entry is Array and entry.size() >= 4):
						continue
					var ot_id: String = str(entry[0])
					var chance: float = float(entry[1])
					var min_q: int = int(entry[2])
					var max_q: int = int(entry[3])
					ensure_material(ot_id)
					if ot_id in material_db:
						var rate_str: String
						if chance >= 1.0:
							rate_str = (tr("%d per cycle") % min_q) if min_q == max_q else (tr("%d-%d per cycle") % [min_q, max_q])
						else:
							rate_str = tr("%.0f%% chance") % (chance * 100.0)
						material_db[ot_id]["sources"].append({
							"type": "processing",
							"name": recipe_name,
							"rate": rate_str
						})

			if "input" in recipe:
				for mat_id in recipe["input"]:
					ensure_material(mat_id)
					if mat_id in material_db:
						material_db[mat_id]["uses"].append({
							"type": "processing",
							"name": recipe_name,
							"rate": tr("%d per cycle") % recipe["input"][mat_id]
						})
	
	# --- COMBAT SOURCES ---
	var cm = GameState.combat_manager
	if cm:
		# v135: zone display name per difficulty tier — enemy defs carry
		# "zone": int, so combat sources can be GROUPED by sector in the UI.
		var zone_names := {}
		for zid in cm.zones:
			zone_names[int(cm.zones[zid].get("difficulty", 0))] = String(cm.zones[zid].get("name", zid))
		for enemy_id in cm.enemy_db:
			var enemy = cm.enemy_db[enemy_id]
			var enemy_name = enemy.get("name", enemy_id)
			var z_ord := int(enemy.get("zone", 0))
			var z_name := String(zone_names.get(z_ord, "Zone %d" % z_ord))

			for entry in enemy.get("loot", []):
				var mat_id = entry[0]
				ensure_material(mat_id)
				if mat_id in material_db:
					material_db[mat_id]["sources"].append({
						"type": "combat",
						"name": enemy_name,
						"rate": tr("%d-%d per kill") % [entry[1], entry[2]],
						"zone_name": z_name, "zone_ord": z_ord
					})

			for entry in enemy.get("rare_loot", []):
				var mat_id = entry[0]
				ensure_material(mat_id)
				if mat_id in material_db:
					material_db[mat_id]["sources"].append({
						"type": "combat",
						"name": tr(enemy_name) + tr(" (Rare)"),   # v137: tr() the name before concat, else the whole "Name (Rare)" string misses the key
						"rate": tr("%.0f%% chance") % (entry[1] * 100),
						"zone_name": z_name, "zone_ord": z_ord
					})

			if "boss_core" in enemy and enemy["boss_core"] != "":
				var core_id = enemy["boss_core"]
				ensure_material(core_id)
				if core_id in material_db:
					material_db[core_id]["sources"].append({
						"type": "combat",
						"name": tr(enemy_name) + tr(" (Boss)"),
						"rate": tr("100% (Guaranteed)"),
						"zone_name": z_name, "zone_ord": z_ord
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
							"rate": tr("%d per cycle") % bdata["yield"][mat_id]
						})
			
			if "input" in bdata:
				for mat_id in bdata["input"]:
					ensure_material(mat_id)
					if mat_id in material_db:
						material_db[mat_id]["uses"].append({
							"type": "building",
							"name": bname,
							"rate": tr("%d per cycle") % bdata["input"][mat_id]
						})
			
			if "cost" in bdata:
				for mat_id in bdata["cost"]:
					if mat_id == "credits": continue
					ensure_material(mat_id)
					if mat_id in material_db:
						material_db[mat_id]["uses"].append({
							"type": "building",
							"name": bname + " (Build)",
							"rate": tr("%d required") % bdata["cost"][mat_id]
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
							# v141: raw authored qty understated every scalable material
							# by MATERIAL_MULTIPLIER (Steel/Circuit/… are doubled).
							# Same helper as can_unlock so the Atlas cannot drift.
							"rate": "%d required" % rm._effective_item_requirement(String(mat_id), int(tech["cost_items"][mat_id]))
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
	tier_lbl.text = tr("T%d") % tier
	tier_lbl.add_theme_font_size_override("font_size", 11)
	tier_lbl.add_theme_color_override("font_color", tier_color)
	tier_lbl.custom_minimum_size = Vector2(26, 0)
	tier_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(tier_lbl)

	# Name
	var name_lbl = Label.new()
	name_lbl.text = tr(mat["name"])
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(name_lbl)

	# Inventory count
	var inv_lbl = Label.new()
	inv_lbl.text = tr("x%s") % UITheme.format_num(owned)
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
		header.text = tr("—  %s  T%d  —") % [zone, diff]
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
	# v116: the stripe still colour-codes danger at a glance, but the threat
	# WORD (TRIVIAL / OK / LETHAL / …) is no longer shown.
	var stripe_color = Color(0.5, 0.5, 0.55)
	if sm and sm.attack_kinetic + sm.attack_energy + sm.attack_explosive > 0 and sm.max_hp > 0:
		var p_dps = float(sm.attack_kinetic + sm.attack_energy + sm.attack_explosive)
		var p_ehp = float(sm.max_hp + sm.max_shield)
		var p_ttk = float(enemy_ehp) / max(1.0, p_dps)
		var e_ttk = float(p_ehp) / max(1.0, enemy_dps)
		var ratio = e_ttk / max(0.01, p_ttk)
		if ratio >= 3.0:    stripe_color = Color(0.45, 1.00, 0.50)
		elif ratio >= 1.5:  stripe_color = Color(0.55, 0.95, 0.70)
		elif ratio >= 0.75: stripe_color = Color(1.00, 0.85, 0.30)
		elif ratio >= 0.35: stripe_color = Color(1.00, 0.50, 0.20)
		else:               stripe_color = Color(1.00, 0.30, 0.30)

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
		boss_lbl.text = tr("BOSS")
		boss_lbl.add_theme_font_size_override("font_size", 14)
		boss_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.20))
		boss_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(boss_lbl)

	var name_lbl = Label.new()
	name_lbl.text = tr(e["name"])
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(name_lbl)

	panel.add_child(btn)
	return panel

# v137: public deep-link entry (mirrors research_page.focus_on_tech). Opens the
# Materials tab focused on mat_id. Guards against ids that aren't materials (modules,
# source-less ids) which would crash _display_material_details' unchecked lookup.
func focus_material(mat_id: String) -> void:
	if not material_db.has(mat_id):
		return
	if current_mode != "materials":
		_on_mode_materials()
	_on_item_selected(mat_id)

func _on_item_selected(id: String):
	selected_id = id
	
	if current_mode == "materials":
		_display_material_details(id)
	else:
		_display_enemy_details(id)

func _display_material_details(mat_id):
	var mat = material_db[mat_id]
	_hide_static_titles()
	_clear_inserted_blocks()

	name_label.text = tr(mat["name"])

	var tier = _get_material_tier(mat_id)
	var tier_color: Color = TIER_COLORS.get(tier, Color.WHITE)
	var owned = GameState.resources.get_element_amount(mat_id) if GameState.resources else 0.0
	var market_value = ElementDB.get_element_value(mat_id)
	var details = desc_label.get_parent()

	# --- HERO BLOCK: 48px tinted icon + identity chips ---
	_hero_block = HBoxContainer.new()
	_hero_block.add_theme_constant_override("separation", 12)
	_hero_block.add_child(_make_hero_icon(mat_id, tier, tier_color))

	var chips = HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chips.add_child(_make_chip("T%d" % tier, tier_color, 10))
	chips.add_child(_make_chip(ElementDB.get_category(mat_id).replace("_", " ").capitalize(), UITheme.element_accent(mat_id), 10))
	if market_value > 0:
		chips.add_child(_make_value_chip(tr("VALUE %s %s") % [UITheme.format_num(market_value), UITheme.LIRA_ICON_BB], UITheme.COLORS["warning"]))
	var own_col: Color = UITheme.COLORS["positive"] if owned > 0 else UITheme.COLORS["text_dim"]
	chips.add_child(_make_chip(tr("OWNED %s") % UITheme.format_num(owned), own_col, 10))
	_hero_block.add_child(chips)

	details.add_child(_hero_block)
	details.move_child(_hero_block, 0)

	# --- Flavor (description only; hidden when empty) ---
	var elem_desc: String = ElementDB.get_element_description(mat_id)
	desc_label.text = elem_desc
	desc_label.visible = (elem_desc != "")
	desc_label.add_theme_color_override("font_color", UITheme.COLORS["text_dim"])
	desc_label.add_theme_font_size_override("font_size", 13)

	# --- Net rate (left-aligned badge; hidden at zero) ---
	var im_mgr = GameState.infrastructure_manager
	var net_rates = im_mgr.get_total_resource_rates()
	var rate = net_rates.get(mat_id, 0.0)
	net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	net_label.modulate = Color.WHITE
	if rate > 0:
		net_label.text = tr("▲ NET +%.2f /min") % rate
		net_label.add_theme_color_override("font_color", UITheme.COLORS["positive"])
		net_label.visible = true
	elif rate < 0:
		net_label.text = tr("▼ NET %.2f /min") % rate
		net_label.add_theme_color_override("font_color", UITheme.COLORS["negative"])
		net_label.visible = true
	else:
		net_label.visible = false

	# --- SOURCED FROM / CONSUMED BY ---
	_clear_list(sources_list)
	_clear_list(uses_list)

	_make_caption(sources_list, tr("SOURCED FROM"), UITheme.COLORS["positive"])
	if mat["sources"].is_empty():
		_add_label(sources_list, tr("No known sources."), UITheme.COLORS["text_dim"])
	else:
		# v135: combat sources grouped under their SECTOR (Lunar Orbit > mites,
		# drones...). Non-combat sources (gather/recipes/buildings) stay flat
		# on top; zones render in ascending tier with indented enemy rows.
		var zone_groups := {}
		for source in mat["sources"]:
			if String(source.get("type", "")) == "combat" and source.has("zone_name"):
				var z_o := int(source.get("zone_ord", 0))
				if not zone_groups.has(z_o):
					zone_groups[z_o] = {"name": String(source["zone_name"]), "rows": []}
				zone_groups[z_o]["rows"].append(source)
			else:
				_add_source_row(sources_list, source["type"], "%s (%s)" % [tr(source["name"]), tr(source["rate"])], _get_type_color(source["type"]))
		var z_ords: Array = zone_groups.keys()
		z_ords.sort()
		for z_o2 in z_ords:
			_add_label(sources_list, String(zone_groups[z_o2]["name"]), Color(UITheme.COLORS["accent"], 0.95))
			for src in zone_groups[z_o2]["rows"]:
				_add_source_row(sources_list, src["type"], "%s (%s)" % [tr(src["name"]), tr(src["rate"])], _get_type_color(src["type"]), 14)

	_make_caption(uses_list, tr("CONSUMED BY"), UITheme.COLORS["warning"])
	if mat["uses"].is_empty():
		_add_label(uses_list, tr("Not used anywhere."), UITheme.COLORS["text_dim"])
	else:
		for use in mat["uses"]:
			_add_source_row(uses_list, use["type"], "%s (%s)" % [tr(use["name"]), tr(use["rate"])], _get_type_color(use["type"]))

	_maybe_atlas_lesson(mat_id)

func _display_enemy_details(eid):
	var e = enemy_db.get(eid)
	if not e: return
	_hide_static_titles()
	_clear_inserted_blocks()
	if net_label: net_label.visible = false

	name_label.text = tr(e["name"])

	var e_raw = GameState.combat_manager.enemy_db.get(eid, {})
	var details = desc_label.get_parent()

	var atk = e["stats"].get("atk", 0)
	var interval = e["stats"].get("atk_interval", 2.0)
	var hp = e["stats"].get("hp", 0)
	var shield = e["stats"].get("max_shield", 0)

	# Damage-type tag + color (mirrors the live combat card).
	var dmg_tag: String = "KIN"
	var dmg_col: Color = Color(0.439, 0.533, 0.949)
	match e.get("dmg_type", "kinetic"):
		"energy":
			dmg_tag = "NRG"
			dmg_col = Color(0.373, 0.878, 0.784)
		"explosive":
			dmg_tag = "EXP"
			dmg_col = Color(1.0, 0.761, 0.302)

	# --- IDENTITY ROW: zone / xp / dmg-type + resist/weak/cryo/enrage chips ---
	_identity_row = HBoxContainer.new()
	_identity_row.add_theme_constant_override("separation", 6)
	_identity_row.add_child(_make_chip("ZONE T%d" % e["zone_difficulty"], UITheme.COLORS["text_accent"], 10))
	_identity_row.add_child(_make_chip("XP %d" % e["xp"], UITheme.COLORS["positive"], 10))
	_identity_row.add_child(_make_chip(dmg_tag, dmg_col, 10))

	if e_raw.get("warp_hardened", false):
		_identity_row.add_child(_make_chip("CRYO-ONLY", Color(0.373, 0.878, 0.784), 9))
	# v139d P3: boss-trait chips (shared vocabulary with the pre-fight card).
	for tc in load("res://scripts/ui/combat_enemy_card.gd")._trait_chips(e_raw):
		_identity_row.add_child(_make_chip(tc[0], tc[1], 9))
	if e_raw.get("is_boss", false):
		_identity_row.add_child(_make_chip(tr("NEEDS RARE GEAR"), Color(1.0, 0.76, 0.30), 9))
	for entry in [
		[float(e_raw.get("resist_k", 0.0)), "KIN"],
		[float(e_raw.get("resist_e", 0.0)), "NRG"],
		[float(e_raw.get("resist_x", 0.0)), "EXP"],
		[float(e_raw.get("resist_cryo", 0.0)), "CRY"],
	]:
		var val: float = entry[0]
		var tag: String = entry[1]
		if val > 0.05:
			_identity_row.add_child(_make_chip("▲%s" % tag, Color(1.0, 0.392, 0.451), 9))
		elif val < -0.05:
			_identity_row.add_child(_make_chip("▼%s" % tag, Color(0.275, 0.878, 0.627), 9))
	if e_raw.get("enrage_at", 0.0) > 0.0:
		_identity_row.add_child(_make_chip("ENRAGE<%d%%" % int(e_raw["enrage_at"] * 100), UITheme.COLORS["warning"], 9))

	details.add_child(_identity_row)
	details.move_child(_identity_row, 0)

	# --- Flavor (per-zone desc; enemies have no element description) ---
	var zdesc: String = e.get("zone_desc", "")
	desc_label.text = zdesc
	desc_label.visible = (zdesc != "")
	desc_label.add_theme_color_override("font_color", UITheme.COLORS["text_dim"])
	desc_label.add_theme_font_size_override("font_size", 13)

	# --- COMBAT DATA stat grid ---
	_clear_list(sources_list)
	_clear_list(uses_list)
	_make_caption(sources_list, "COMBAT DATA", UITheme.COLORS["text_accent"])
	var main_col: Color = UITheme.COLORS["text_main"]
	_spec_row(sources_list, "HP", UITheme.format_num(hp), main_col)
	if shield > 0:
		_spec_row(sources_list, "Shield", UITheme.format_num(shield), main_col)
	_spec_row(sources_list, "ATK", "%s %s" % [UITheme.format_num(atk), dmg_tag], dmg_col)
	_spec_row(sources_list, "DEF", UITheme.format_num(e["stats"].get("def", 0)), main_col)
	_spec_row(sources_list, "Interval", "%.1f s" % interval, main_col)
	_spec_row(sources_list, "Accuracy", str(e["stats"].get("accuracy", 0)), main_col)
	var eva = e_raw.get("eva", e["stats"].get("eva", 0))
	if eva > 0:
		_spec_row(sources_list, "Evasion", str(eva), main_col)
	var dps = float(atk) / max(0.5, interval)
	_add_label(sources_list, tr("Eff. HP %s   ·   DPS %s/s") % [UITheme.format_num(hp + shield), UITheme.format_num(dps)], UITheme.COLORS["text_dim"])

	# --- DROPS ---
	_make_caption(uses_list, "DROPS", UITheme.COLORS["text_accent"])
	for entry in e.get("loot", []):
		_add_loot_row(uses_list, entry[0], "%d–%d" % [int(entry[1]), int(entry[2])], UITheme.COLORS["text_main"])
	var core_id = e.get("boss_core", "")
	if core_id != "":
		_add_loot_row(uses_list, core_id, "(100%)", UITheme.COLORS["warning"], "")

	var rare_loot = e.get("rare_loot", [])
	if not rare_loot.is_empty():
		_make_caption(uses_list, tr("RARE DROPS"), UITheme.COLORS["warning"])
		for entry in rare_loot:
			_add_loot_row(uses_list, entry[0], "(%.1f%%, %d–%d)" % [entry[1] * 100.0, int(entry[2]), int(entry[3])], UITheme.COLORS["warning"], "")

	# Module drops (read from e_raw — the local enemy_db row doesn't carry these).
	var drop_chance = e_raw.get("module_drop_chance", 0.0)
	var drop_pool = e_raw.get("module_drop_pool", [])
	if drop_chance > 0.0 and not drop_pool.is_empty() and GameState.shipyard_manager:
		_make_caption(uses_list, tr("MODULE DROPS (%d%%)") % int(drop_chance * 100), UITheme.CATEGORY_COLORS["shipyard"])
		for mod_id in drop_pool:
			var mod = GameState.shipyard_manager.modules.get(mod_id, {})
			_add_label(uses_list, "▸ %s" % mod.get("name", mod_id), UITheme.COLORS["text_main"])

func _clear_list(node):
	for child in node.get_children():
		child.queue_free()

func _add_label(parent, text, color):
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)

func _type_icon_tex(type: String) -> Texture2D:
	var path = TYPE_ICON_PATHS.get(type, "res://assets/icons/nav/inventory.svg")
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

# Source/use row: tinted nav icon + "Name (rate)" label (replaces the old
# emoji-prefixed plain label).
func _add_source_row(parent, type: String, text: String, color: Color, indent: int = 0):
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if indent > 0:
		var sp = Control.new()
		sp.custom_minimum_size = Vector2(indent, 0)
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sp)
	# v137: name the SOURCE PAGE in text ("Engineering", "Mine", "Combat", …) instead of a
	# type icon — the icon alone didn't tell the player WHERE to craft/gather this (QoL).
	var rtl = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rtl.add_theme_font_size_override("normal_font_size", 13)
	rtl.add_theme_font_size_override("bold_font_size", 13)
	var chex := color.to_html(false)
	var safe_text := text.replace("[", "[lb]")
	var page := _source_page_name(type)
	if page != "":
		rtl.text = "[b][color=#%s]%s[/color][/b]  [color=#c3ccca]%s[/color]" % [chex, tr(page), safe_text]
	else:
		rtl.text = "[color=#%s]%s[/color]" % [chex, safe_text]
	row.add_child(rtl)
	parent.add_child(row)

# v137: the in-game page a source/use lives on — shown as a text tag so the player
# knows exactly where to go (matches the sidebar page names, translated via tr()).
func _source_page_name(type: String) -> String:
	match type:
		"gathering": return "Mine"
		"processing": return "Engineering"
		"combat": return "Combat"
		"building": return "Infrastructure"
		"shipyard": return "Shipyard"
		"research": return "Research"
	return ""

func _get_type_color(type: String) -> Color:
	match type:
		"gathering": return Color(0.6, 0.4, 0.2)
		"processing": return Color(0.5, 0.5, 0.8)
		"combat": return Color(0.9, 0.3, 0.3)
		"building": return Color(0.4, 0.7, 0.4)
		"shipyard": return Color(0.3, 0.7, 0.9)
		"research": return Color(0.8, 0.6, 0.9)
		_: return Color(0.7, 0.7, 0.7)


# ── Field Manual teaching beat (mission m019e) ───────────────────────────────
# Fires when the player opens, in the Atlas, the material an active atlas_lookup
# mission names. Completes the mission (event-driven, can't soft-lock), glows the
# SOURCED FROM panel, and pops a coach card generalising the lookup skill. Self-
# guards: completion removes the mission from active_missions, so reopening the
# same entry finds no active mission and stays quiet.
func _maybe_atlas_lesson(mat_id: String) -> void:
	var mm = GameState.mission_manager
	if mm == null:
		return
	var matched := false
	for amid in mm.active_missions:
		var m: Dictionary = mm.missions.get(amid, {})
		if String(m.get("type", "")) == "atlas_lookup" \
				and String(m.get("target", "")) == mat_id \
				and not m.get("completed", false):
			matched = true
			break
	if not matched:
		return
	mm._update_progress("atlas_lookup", mat_id, 1)
	_highlight_sources()
	_show_source_coach(tr(material_db.get(mat_id, {}).get("name", mat_id)))

# Persistent gold-bordered box around the SOURCED FROM section — floats over it and
# gently breathes, staying up for the life of the coach card (freed with it). A box
# rather than a text tint so the color-coded source rows keep their meaning.
func _highlight_sources() -> void:
	if _coach_hl and is_instance_valid(_coach_hl):
		_coach_hl.queue_free()
	_coach_hl = null
	if sources_list == null or not is_instance_valid(sources_list):
		return
	var modal := get_tree().root.find_child("ModalLayer", true, false)
	var parent: Node = modal if modal else get_tree().current_scene
	if parent == null:
		return
	var box := Panel.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.z_index = 99
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.86, 0.32, 0.07)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = Color(1.0, 0.86, 0.32, 0.95)
	box.add_theme_stylebox_override("panel", sb)
	parent.add_child(box)
	_coach_hl = box
	# Rect is only correct after the list has laid out its rows — wait one frame.
	await get_tree().process_frame
	if not (is_instance_valid(box) and is_instance_valid(sources_list)):
		return
	var r: Rect2 = sources_list.get_global_rect()
	var pad := 7.0
	box.global_position = r.position - Vector2(pad, pad)
	box.size = r.size + Vector2(pad * 2.0, pad * 2.0)
	var tw := create_tween().set_loops()
	tw.tween_property(box, "modulate:a", 0.45, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(box, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)

# Compact dismissable coach card floated over the detail panel. Teaches the
# generalisable skill, not just this one material.
func _show_source_coach(mat_name: String) -> void:
	if _coach_card and is_instance_valid(_coach_card):
		_coach_card.queue_free()
	_coach_card = null
	var modal := get_tree().root.find_child("ModalLayer", true, false)
	var parent: Node = modal if modal else get_tree().current_scene
	if parent == null:
		return

	var card := PanelContainer.new()
	card.z_index = 100
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.039, 0.086, 0.078, 0.98)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.216, 0.788, 0.690, 0.6)
	sb.border_width_top = 3
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 13
	sb.content_margin_bottom = 13
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(0, 4)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(330, 0)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)

	var title := Label.new()
	title.text = tr("HOW TO FIND ANYTHING")
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.373, 0.878, 0.784))
	vb.add_child(title)

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(298, 0)
	body.add_theme_font_size_override("normal_font_size", 12)
	body.add_theme_font_size_override("bold_font_size", 12)
	body.add_theme_color_override("default_color", Color(0.894, 0.961, 0.933))
	body.text = tr("The highlighted [b]SOURCED FROM[/b] panel lists every place [color=#5fe0c8]%s[/color] comes from — here, it drops from Lunar Orbit hostiles in Combat. Any time a mission names a material you don't recognise, look it up here: switch to MATERIALS, search its name, and read its sources.") % mat_name
	vb.add_child(body)

	var btn := Button.new()
	btn.text = tr("Got it")
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.pressed.connect(func():
		if _coach_card and is_instance_valid(_coach_card):
			_coach_card.queue_free()
		_coach_card = null
		if _coach_hl and is_instance_valid(_coach_hl):
			_coach_hl.queue_free()
		_coach_hl = null)
	vb.add_child(btn)

	parent.add_child(card)
	_coach_card = card

	# Float over the right (detail) panel — fixed offset from the panel's rect, no
	# dependency on the card's not-yet-measured size (see show_info_card's note).
	var rp := get_node_or_null("HBoxContainer/RightPanel")
	if rp and rp is Control:
		var rr: Rect2 = (rp as Control).get_global_rect()
		var est_w := 330.0
		var px: float = rr.position.x + max(8.0, (rr.size.x - est_w) * 0.5)
		var py: float = rr.position.y + 54.0
		card.global_position = Vector2(px, py)


# ── Datasheet detail-panel helpers ───────────────────────────────────────────

# Hides the .tscn static "Sources"/"Uses" titles (the enemy-mode wart). Defensive
# get_node_or_null so a future .tscn rename simply no-ops. Mode-correct captions
# are rendered in-code as the first child of each list instead.
func _hide_static_titles() -> void:
	var base := "HBoxContainer/RightPanel/MarginContainer/VBoxContainer/ScrollContainer/Details/"
	var st := get_node_or_null(base + "SourcesTitle")
	if st: st.visible = false
	var ut := get_node_or_null(base + "UsesTitle")
	if ut: ut.visible = false

# Frees the code-inserted hero/identity block so it never stacks or bleeds across
# a material↔enemy mode switch. remove_child is immediate (queue_free is deferred),
# so the Details child order is correct again right after this call.
func _clear_inserted_blocks() -> void:
	if _coach_card and is_instance_valid(_coach_card):
		_coach_card.queue_free()
	_coach_card = null
	if _coach_hl and is_instance_valid(_coach_hl):
		_coach_hl.queue_free()
	_coach_hl = null
	if _hero_block and is_instance_valid(_hero_block):
		if _hero_block.get_parent(): _hero_block.get_parent().remove_child(_hero_block)
		_hero_block.queue_free()
	_hero_block = null
	if _identity_row and is_instance_valid(_identity_row):
		if _identity_row.get_parent(): _identity_row.get_parent().remove_child(_identity_row)
		_identity_row.queue_free()
	_identity_row = null

# Pill chip — verbatim recipe from combat_enemy_card.gd so chips read identically.
func _make_chip(text: String, color: Color, font_size: int) -> Control:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _chip_stylebox(color))
	chip.add_child(lbl)
	return chip

# Like _make_chip but the inner node is a RichTextLabel so the inline lira icon
# (LIRA_ICON_BB, BBCode [img]) renders — a plain Label/chip cannot embed it.
func _make_value_chip(value_bb: String, color: Color) -> Control:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
	rtl.text = tr("[color=#%s]%s[/color]") % [color.to_html(false), value_bb]
	rtl.add_theme_font_size_override("normal_font_size", 10)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _chip_stylebox(color))
	chip.add_child(rtl)
	return chip

func _chip_stylebox(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.bg_color.a = 0.15
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	var border := color
	border.a = 0.45
	sb.border_color = border
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb

# 48px tinted material icon, or a tinted tier-badge panel when no SVG exists.
func _make_hero_icon(mat_id: String, tier: int, tier_color: Color) -> Control:
	var tex: Texture2D = ElementDB.get_material_icon(mat_id)
	if tex != null:
		var ir := TextureRect.new()
		ir.texture = tex
		ir.modulate = ElementDB.get_material_tint(mat_id)
		ir.custom_minimum_size = Vector2(48, 48)
		ir.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ir.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ir.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return ir
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(48, 48)
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = tier_color
	sb.bg_color.a = 0.16
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	var bc := tier_color
	bc.a = 0.5
	sb.border_color = bc
	pc.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = tr("T%d") % tier
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", tier_color)
	l.add_theme_font_size_override("font_size", 16)
	pc.add_child(l)
	return pc

# Section caption (SOURCED FROM / CONSUMED BY / COMBAT DATA / DROPS / …).
func _make_caption(parent, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)

# Key/value spec row: key (dim, expands) ... value (right-aligned). No [right]/[table].
func _spec_row(parent, key: String, value: String, val_color: Color) -> void:
	var row := HBoxContainer.new()
	var kl := Label.new()
	kl.text = key
	kl.add_theme_color_override("font_color", UITheme.COLORS["text_dim"])
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(kl)
	var vl := Label.new()
	vl.text = value
	vl.add_theme_color_override("font_color", val_color)
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vl.custom_minimum_size = Vector2(90, 0)
	row.add_child(vl)
	parent.add_child(row)

# Loot row: inline material icon (degrades to text if no SVG) + colored name + dim qty.
func _add_loot_row(parent, item_id: String, qty_str: String, name_color: Color, prefix: String = "") -> void:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var icon: String = ElementDB.material_icon_bbcode(item_id, 16)
	rtl.text = tr("%s[color=#%s]%s%s[/color]  [color=#%s]%s[/color]") % [icon, name_color.to_html(false), prefix, ElementDB.get_display_name(item_id), UITheme.COLORS["text_dim"].to_html(false), qty_str]
	parent.add_child(rtl)

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
