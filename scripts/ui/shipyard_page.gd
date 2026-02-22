extends Control

@onready var hp_lbl = $VBoxContainer/StatsPanel/HBoxContainer/HPLabel
@onready var atk_lbl = $VBoxContainer/StatsPanel/HBoxContainer/AtkLabel
@onready var def_lbl = $VBoxContainer/StatsPanel/HBoxContainer/DefLabel
@onready var eva_lbl = $VBoxContainer/StatsPanel/HBoxContainer/EvaLabel
@onready var energy_lbl = $VBoxContainer/StatsPanel/HBoxContainer/EnergyLabel
@onready var rack_container = $VBoxContainer/ScrollContainer/RackContainer

var repair_btn: Button
var manager: RefCounted
var hull_widget_scene = preload("res://scenes/ui/hull_widget.tscn")
var module_widget_scene = preload("res://scenes/ui/module_widget.tscn")
var widgets = []
var racks = {} # {category_id: GridContainer/HBoxContainer}

func _ready():
	manager = GameState.shipyard_manager
	
	# Mission & Resource Integration
	GameState.mission_manager.mission_updated.connect(_on_mission_updated)
	if GameState.resources:
		if not GameState.resources.element_added.is_connected(_on_resource_changed):
			GameState.resources.element_added.connect(_on_resource_changed)
		if not GameState.resources.currency_added.is_connected(_on_resource_changed):
			GameState.resources.currency_added.connect(_on_resource_changed)
		if not GameState.resources.element_removed.is_connected(_on_resource_changed):
			GameState.resources.element_removed.connect(_on_resource_changed)
		if not GameState.resources.currency_removed.is_connected(_on_resource_changed):
			GameState.resources.currency_removed.connect(_on_resource_changed)
	if manager and not manager.inventory_updated.is_connected(_on_inventory_updated):
		manager.inventory_updated.connect(_on_inventory_updated)
	
	# UI Robustness: Ensure parent containers don't block mouse events
	$VBoxContainer/StatsPanel.mouse_filter = Control.MOUSE_FILTER_PASS
	$VBoxContainer/StatsPanel/HBoxContainer.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Create Repair Button dynamically
	repair_btn = Button.new()
	repair_btn.text = "Repair (0 Cr)"
	repair_btn.custom_minimum_size = Vector2(120, 30) # Ensure it's clickable
	repair_btn.mouse_filter = Control.MOUSE_FILTER_STOP # Detect clicks
	repair_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	repair_btn.pressed.connect(_on_repair_pressed)
	$VBoxContainer/StatsPanel/HBoxContainer.add_child(repair_btn)
	UITheme.apply_premium_button_style(repair_btn, "shipyard")
	
	call_deferred("refresh_list")

func _process(_delta):
	_update_repair_button()
	_update_stats_display()

func _on_mission_updated():
	pass # No tab alerts needed with blade architecture

func _on_resource_changed(_a=null, _b=null):
	for w in widgets:
		if w.has_method("update_state"):
			w.update_state()

func _on_inventory_updated():
	_on_resource_changed()

func _update_repair_button():
	if not repair_btn: return
	var cost = manager.get_repair_cost()
	
	# Audit v68.0: Combat awareness for repairing
	if GameState.combat_manager and GameState.combat_manager.in_combat:
		repair_btn.text = "In Combat (Blocked)"
		repair_btn.disabled = true
	elif cost == 0:
		repair_btn.text = "Hull OK"
		repair_btn.disabled = true
	else:
		repair_btn.text = "Repair (%d Cr)" % cost
		repair_btn.disabled = not manager.can_repair()

func _update_stats_display():
	if hp_lbl:
		hp_lbl.text = "HP: %d / %d" % [manager.current_hp, manager.max_hp]
	if atk_lbl:
		atk_lbl.text = "Atk: %s" % UITheme.format_num(manager.attack)
	if def_lbl:
		def_lbl.text = "Shield: %s" % UITheme.format_num(manager.max_shield)
	if eva_lbl:
		eva_lbl.text = "Eva: %.1f%%" % manager.evasion
	if energy_lbl:
		var e_max = GameState.resources.max_energy
		var e_used = manager.energy_used
		energy_lbl.text = "Energy: %d/%d" % [e_used, e_max]
		energy_lbl.modulate = Color(1, 0.3, 0.3) if e_used > e_max else Color.WHITE

func _on_repair_pressed():
	print("[UI] Repair button pressed!")
	if manager.repair_hull():
		print("[UI] Repair successful, refreshing UI...")
		_update_stats_display()
		_update_repair_button()


func refresh_list():
	# Clear previous racks
	for child in rack_container.get_children():
		child.queue_free()
	widgets.clear()
	racks.clear()
	
	# Create racks - Hulls use HBoxContainer for horizontal slider feel
	_create_rack("hulls", "Capital Hulls", Color(0.4, 0.9, 0.6, 0.5), rack_container, true)
	_create_rack("kinetic", "Kinetic Weapons", Color(1.0, 0.32, 0.32, 0.5), rack_container)
	_create_rack("explosive", "Explosive Weapons", Color(1.0, 0.5, 0.0, 0.5), rack_container) # Added
	_create_rack("energy", "Energy Weapons", Color(0.0, 0.9, 1.0, 0.5), rack_container)
	_create_rack("shield", "Shield Generators", Color(0.4, 0.6, 1.0, 0.5), rack_container)
	_create_rack("armor", "Hull Armor", Color(0.6, 0.6, 0.6, 0.5), rack_container)
	_create_rack("engine", "Engine Systems", Color(0.8, 1.0, 0.2, 0.5), rack_container)
	_create_rack("battery", "Power Cores", Color(1.0, 1.0, 0.2, 0.5), rack_container)
	_create_rack("cooling", "Cooling Systems", Color(0.0, 0.5, 1.0, 0.5), rack_container)
	_create_rack("sensor", "Sensor & EW Suites", Color(0.6, 0.2, 1.0, 0.5), rack_container)
	_create_rack("ammo", "Ordnance", Color(1.0, 0.6, 0.3, 0.5), rack_container)
	
	# Hulls
	var sorted_hulls = manager.hulls.keys()
	sorted_hulls.sort_custom(func(a,b): return manager.hulls[a]["cost"].get("credits",0) < manager.hulls[b]["cost"].get("credits",0))
	
	for hid in sorted_hulls:
		var w = hull_widget_scene.instantiate()
		racks["hulls"].add_child(w)
		w.setup(hid, manager.hulls[hid], manager, self)
		widgets.append(w)
		
	# Modules Categorization & Sorting (Audit v70.0)
	var sorted_mods = manager.modules.keys()
	
	# Custom Sort: Sort by "Power Score" (Tier) ascending
	sorted_mods.sort_custom(func(a, b):
		return _get_module_power_score(a, manager.modules[a]) < _get_module_power_score(b, manager.modules[b])
	)
	
	for mid in sorted_mods:
		var data = manager.modules[mid]
		if data.get("is_custom", false): continue # Skip dropped loot in Shipyard (Crafting)
		
		var type = data.get("slot_type", "weapon")
		var cat = "kinetic"
		
		# Category Logic
		match type:
			"weapon":
				var stats = data.get("stats", {})
				if stats.get("atk_explosive", 0) > 0:
					cat = "explosive"
				elif stats.get("atk_kinetic", 0) > stats.get("atk_energy", 0):
					cat = "kinetic"
				else:
					cat = "energy"
			"shield": cat = "shield"
			"armor": cat = "armor" # Added armor mapping
			"engine": cat = "engine"
			"battery": cat = "battery"
			"cooling": cat = "cooling"
			"sensor": cat = "sensor"
			"ammo", "slug": cat = "ammo"
			_: cat = "energy" # Default
		
		if cat not in racks: continue
		
		var w = module_widget_scene.instantiate()
		racks[cat].add_child(w)
		w.setup(mid, data, manager, self)
		w.update_state()
		widgets.append(w)

func _get_module_power_score(id: String, data: Dictionary) -> int:
	# Tier Heuristic: Calculate a "Power Score" based on primary stat or cost
	# Used for sorting modules from Weakest -> Strongest
	
	var score = 0
	var stats = data.get("stats", {})
	
	# 1. Base Score from Cost (Expensive = Better)
	# Logarithmic scale prevents late game items from dwarfing everything
	var cost = data.get("cost", {})
	var credits = cost.get("credits", 0)
	if credits > 0:
		score += int(log(credits) * 10)
	else:
		# Battery T1/T2 have 0 credits cost, check material rarity manually
		if "BatteryT1" in cost: score += 10
		elif "BatteryT2" in cost: score += 20
		elif "BatteryT3" in cost: score += 30
		else: score += 5 # Fallback
		
	# 2. Stat Bonus
	# Add raw stats to differentiate items with verify similar costs
	if stats.get("atk_kinetic", 0) > 0: score += stats["atk_kinetic"]
	if stats.get("atk_energy", 0) > 0: score += stats["atk_energy"]
	if stats.get("atk_explosive", 0) > 0: score += stats["atk_explosive"]
	if stats.get("max_shield", 0) > 0: score += stats["max_shield"] / 5
	if stats.get("hp", 0) > 0: score += stats["hp"] / 10
	if stats.get("energy_capacity", 0) > 0: score += stats["energy_capacity"]
	if stats.get("eva", 0) > 0: score += stats["eva"] * 2
	if stats.get("atk_speed_bonus", 0) > 0: score += int(stats["atk_speed_bonus"] * 100)
	
	# 3. Explicit Overrides for known oddities
	if id == "mining_laser_mk1": score = 10
	if id == "mining_laser_mk2": score = 50
	if id == "railgun_mk1": score = 20
	
	return score

func _create_rack(id: String, title: String, color: Color, parent: Node, horizontal: bool = false):
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
	
	var rack_grid: Control
	if horizontal:
		# Create a horizontal scroll for hulls
		var scroll = ScrollContainer.new()
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size.y = 145  # Reduced 20% from 180
		rack_vbox.add_child(scroll)
		
		rack_grid = HBoxContainer.new()
		rack_grid.add_theme_constant_override("separation", 20)
		scroll.add_child(rack_grid)
	else:
		rack_grid = GridContainer.new()
		rack_grid.columns = 5
		rack_grid.add_theme_constant_override("h_separation", 10)
		rack_grid.add_theme_constant_override("v_separation", 10)
		rack_vbox.add_child(rack_grid)
	
	var sep = HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.1)
	rack_vbox.add_child(sep)
	
	racks[id] = rack_grid

func get_module_widget(module_id: String) -> Control:
	for w in widgets:
		if w.get("mid") == module_id:
			return w
	return null

func focus_module_tab(_module_id: String):
	pass # No longer using tabs
