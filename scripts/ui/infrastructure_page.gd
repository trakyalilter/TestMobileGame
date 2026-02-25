extends Control

@onready var net_lbl = $VBoxContainer/Header/NetLabel
@onready var gen_lbl = $VBoxContainer/Header/StatsVBox/GenLabel
@onready var cons_lbl = $VBoxContainer/Header/StatsVBox/ConsLabel

@onready var energy_grid = $VBoxContainer/ScrollContainer/BladeContainer/EnergyRack/Grid
@onready var mining_grid = $VBoxContainer/ScrollContainer/BladeContainer/MiningRack/Grid
@onready var production_grid = $VBoxContainer/ScrollContainer/BladeContainer/ProductionRack/Grid

@onready var blade_container = $VBoxContainer/ScrollContainer/BladeContainer

var manager: RefCounted
var building_widget_scene = preload("res://scenes/ui/building_widget.tscn")
var widgets = []

var logistics_rack: VBoxContainer
var logistics_grid: GridContainer

func _ready():
	manager = GameState.infrastructure_manager
	$VBoxContainer/ScrollContainer.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_setup_logistics_rack()
	_setup_multi_buy_toggles()
	call_deferred("refresh_list")

var btn_x1: Button
var btn_x10: Button
var btn_x100: Button

func _setup_multi_buy_toggles():
	var header = $VBoxContainer/Header
	var toggle_box = HBoxContainer.new()
	toggle_box.add_theme_constant_override("separation", 10)
	toggle_box.alignment = BoxContainer.ALIGNMENT_CENTER
	# Insert below StatsVBox
	header.add_child(toggle_box)
	
	btn_x1 = Button.new()
	btn_x1.text = "BUILD x1"
	btn_x1.toggle_mode = true
	btn_x1.button_pressed = true
	
	btn_x10 = Button.new()
	btn_x10.text = "BUILD x10"
	btn_x10.toggle_mode = true
	
	btn_x100 = Button.new()
	btn_x100.text = "BUILD x100"
	btn_x100.toggle_mode = true
	
	toggle_box.add_child(btn_x1)
	toggle_box.add_child(btn_x10)
	toggle_box.add_child(btn_x100)
	
	UITheme.apply_sharp_button_style(btn_x1, "infrastructure")
	UITheme.apply_sharp_button_style(btn_x10, "infrastructure")
	UITheme.apply_sharp_button_style(btn_x100, "infrastructure")
	
	btn_x1.pressed.connect(func(): _set_multiplier(1))
	btn_x10.pressed.connect(func(): _set_multiplier(10))
	btn_x100.pressed.connect(func(): _set_multiplier(100))

func _set_multiplier(mult: int):
	manager.set_buy_multiplier(mult)
	btn_x1.button_pressed = (mult == 1)
	btn_x10.button_pressed = (mult == 10)
	btn_x100.button_pressed = (mult == 100)
	
	# Force refresh cost labels immediately
	for w in widgets:
		w.update_state()

func _setup_logistics_rack():
	# Create a new rack for Command/Logistics since it was dynamically added
	logistics_rack = VBoxContainer.new()
	logistics_rack.name = "LogisticsRack"
	logistics_rack.add_theme_constant_override("separation", 10)
	
	var header = Label.new()
	header.text = "[ COMMAND & LOGISTICS ]"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.6, 0.4, 1.0, 0.5))
	logistics_rack.add_child(header)
	
	logistics_grid = GridContainer.new()
	logistics_grid.columns = 4
	logistics_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	logistics_grid.add_theme_constant_override("h_separation", 10)
	logistics_grid.add_theme_constant_override("v_separation", 10)
	logistics_rack.add_child(logistics_grid)
	
	# Cleaner look (no separator)
	blade_container.add_child(logistics_rack)

func refresh_list():
	for grid in [energy_grid, mining_grid, production_grid, logistics_grid]:
		if not grid: continue
		for child in grid.get_children():
			child.queue_free()
	widgets.clear()
	
	for bid in manager.building_db:
		var data = manager.building_db[bid]
		var w = building_widget_scene.instantiate()
		
		var cat = data.get("category", "industry")
		var target_grid = production_grid
		
		match cat:
			"power": target_grid = energy_grid
			"extraction": target_grid = mining_grid
			"industry": target_grid = production_grid
			"logistics": target_grid = logistics_grid
		
		if target_grid:
			target_grid.add_child(w)
			w.setup(bid, data, manager, self)
			widgets.append(w)

func _process(_delta):
	# Update UI elements
	update_ui()

func update_ui():
	if not manager: return
	
	manager.recalc_energy()
	
	var net = manager.net_energy
	var gen = manager.generation
	var cons = manager.consumption
	
	if net_lbl:
		net_lbl.text = "NET: %+.1f kW" % net
		if net >= 0:
			net_lbl.add_theme_color_override("font_color", Color.CYAN)
		else:
			net_lbl.add_theme_color_override("font_color", Color.ORANGE_RED)
	
	if gen_lbl:
		gen_lbl.text = "GEN: %.1f kW" % gen
	
	if cons_lbl:
		# Forensic 3: Efficiency Visibility
		var eff = manager.energy_efficiency
		if eff < 1.0:
			cons_lbl.text = "CONS: %.1f kW (Grid Stalled: %d%%)" % [cons, int(eff * 100)]
		else:
			cons_lbl.text = "CONS: %.1f kW" % cons

	for w in widgets:
		w.update_state()

func get_building_widget(building_id: String) -> Control:
	for w in widgets:
		if w.bid == building_id:
			return w
	return null
