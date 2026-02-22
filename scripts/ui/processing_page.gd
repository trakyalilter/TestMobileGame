extends Control

@onready var level_label = $VBoxContainer/Header/LevelLabel
@onready var xp_label = $VBoxContainer/Header/XPLabel
@onready var xp_bar = $VBoxContainer/XPBar
@onready var rack_container = $VBoxContainer/ScrollContainer/RackContainer

var manager: RefCounted
var recipe_widget_scene = preload("res://scenes/ui/processing_recipe_widget.tscn")
var widgets = []
var racks = {} # {category_id: GridContainer}

func _ready():
	manager = GameState.processing_manager
	
	# Premium Styling
	UITheme.apply_progress_bar_style(xp_bar, "engineering")
	$VBoxContainer/ScrollContainer.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	
	# Mission & Resource Integration
	GameState.mission_manager.mission_updated.connect(_on_mission_updated)
	if GameState.resources:
		GameState.resources.element_added.connect(_on_resource_changed)
		GameState.resources.currency_added.connect(_on_resource_changed)
	
	call_deferred("refresh_recipes")
	call_deferred("_on_mission_updated")

func _on_mission_updated():
	pass # Tab alerts no longer needed with blade architecture

func _on_resource_changed(_a = null, _b = null):
	for w in widgets:
		if w.has_method("update_state"):
			w.update_state()

func refresh_recipes():
	# Clear previous racks
	for child in rack_container.get_children():
		child.queue_free()
	widgets.clear()
	racks.clear()
	
	# Create racks for each category
	_create_rack("basics", "Basic Operations", Color(0.8, 0.8, 0.8, 0.5), rack_container) # NEW
	_create_rack("smelting", "Refining", Color(0.9, 0.5, 0.2, 0.5), rack_container)
	_create_rack("alloys", "Alloy Fabrication", Color(0.7, 0.7, 0.7, 0.5), rack_container)
	_create_rack("materials", "Advanced Materials", Color(0.4, 0.8, 0.6, 0.5), rack_container)
	_create_rack("electronics", "Electronics & Components", Color(0.2, 0.8, 1.0, 0.5), rack_container)
	_create_rack("batteries", "Power Cells & Batteries", Color(1.0, 1.0, 0.3, 0.5), rack_container)
	_create_rack("munitions", "Munitions Factory", Color(1.0, 0.4, 0.3, 0.5), rack_container)
	# Split Consumables
	_create_rack("consumables_hull", "Hull Repair Kits", Color(0.2, 1.0, 0.5, 0.5), rack_container)
	_create_rack("consumables_shield", "Shield Repair Kits", Color(0.2, 0.6, 1.0, 0.5), rack_container)
	_create_rack("research", "Research & Artifacts", Color(0.8, 0.4, 1.0, 0.5), rack_container)
	
	var sorted_keys = manager.recipes.keys()
	sorted_keys.sort_custom(func(a, b):
		var ra = manager.recipes[a]
		var rb = manager.recipes[b]
		if ra["level_req"] != rb["level_req"]:
			return ra["level_req"] < rb["level_req"]
		return ra["name"] < rb["name"]
	)
	
	for rid in sorted_keys:
		var data = manager.recipes[rid]
		var w = recipe_widget_scene.instantiate()
		var cat = _get_recipe_category(rid, data)
		
		if cat in racks:
			racks[cat].add_child(w)
			w.setup(rid, data, manager, self)
			widgets.append(w)

func _get_recipe_category(rid: String, data: Dictionary) -> String:
	# Priority: Explicit Category
	if data.get("category"):
		return data.get("category")

	# Munitions - ammo for weapons
	if "slug" in rid or "cell_t" in rid or "craft_cell" in rid or "rounds" in rid:
		return "munitions"
	
	# Batteries - power storage
	if "battery" in rid:
		return "batteries"
	
	# Electronics - circuits, chips, semiconductors
	if "circuit" in rid or "chip" in rid or "semiconductor" in rid or "hydraulics" in rid:
		return "electronics"
	
	# Research/Artifacts - analysis, upgrading research fragments
	if "artifact" in rid or "res1" in rid or "res2" in rid or "res3" in rid or "nav_data" in rid or "decrypt" in rid:
		return "research"
	
	# Alloys - metal combinations
	if "bronze" in rid or "steel" in rid or "alloy" in rid or "galvanize" in rid or "stainless" in rid:
		return "alloys"
	
	# Ore Smelting - extracting pure elements from ores
	if "smelt" in rid or "refine" in rid or "extract" in rid or "centrifuge" in rid or "electrolysis" in rid or "leach" in rid or "process_" in rid or "panning" in rid:
		return "smelting"
	
	# Basics check (before materials fallback)
	if "sift" in rid or "charcoal" in rid or "burn" in rid or "wash" in rid:
		return "basics"
	
	# Advanced Materials - composites, polymers, fibers
	if "fiber" in rid or "polymer" in rid or "graphite" in rid or "nanoweave" in rid or "mesh" in rid or "sealant" in rid or "coolant" in rid or "charcoal" in rid or "carbon" in rid or "scrap" in rid:
		return "materials"
	
	# Default to materials if no match
	return "materials"


func _create_rack(id: String, title: String, color: Color, parent: Node):
	var rack_vbox = VBoxContainer.new()
	rack_vbox.name = id + "_rack"
	rack_vbox.add_theme_constant_override("separation", 10)
	parent.add_child(rack_vbox)
	
	var header = Label.new()
	header.text = "[ %s ]" % title.to_upper()
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", color)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rack_vbox.add_child(header)
	
	# Use GridContainer with 4 columns for uniform stretch
	var rack_grid = GridContainer.new()
	rack_grid.columns = 5
	rack_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rack_grid.add_theme_constant_override("h_separation", 10)
	rack_grid.add_theme_constant_override("v_separation", 10)
	rack_vbox.add_child(rack_grid)
	
	var sep = HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.1)
	rack_vbox.add_child(sep)
	
	racks[id] = rack_grid

func get_widget_by_aid(rid_in: String) -> Control:
	for w in widgets:
		if w.get("rid") == rid_in:
			return w
	return null

func focus_tab(_rid_in: String):
	pass # No longer using tabs

func _process(_delta):
	update_ui()

func update_ui():
	if not manager: return
	
	level_label.text = "Level: %d" % manager.get_level()
	xp_label.text = "XP: %d" % int(manager.xp)
	xp_bar.value = manager.get_progress_to_next_level()
	
	for w in widgets:
		w.update_state()
	
	while not manager.events.is_empty():
		var ev = manager.events.pop_front()
		var type = ev[0]
		var text = ev[1]
		var target_id = ev[2]
		
		var target_w = null
		for w in widgets:
			if w.rid == target_id:
				target_w = w
				break
				
		if target_w:
			var color = Color(0.4, 0.9, 0.6)
			if type == "xp": color = Color(1.0, 0.8, 0.15)
			
			UITheme.show_notification(text, color)
