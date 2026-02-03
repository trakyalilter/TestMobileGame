extends Control

@onready var net_lbl = $VBoxContainer/EnergyDash/HBoxContainer/NetLabel
@onready var gen_lbl = $VBoxContainer/EnergyDash/HBoxContainer/VBoxContainer/GenLabel
@onready var cons_lbl = $VBoxContainer/EnergyDash/HBoxContainer/VBoxContainer/ConsLabel
@onready var energy_grid = $VBoxContainer/ScrollContainer/BladeContainer/EnergyRack/Grid
@onready var mining_grid = $VBoxContainer/ScrollContainer/BladeContainer/MiningRack/Grid
@onready var production_grid = $VBoxContainer/ScrollContainer/BladeContainer/ProductionRack/Grid

@onready var blade_container = $VBoxContainer/ScrollContainer/BladeContainer

var manager: RefCounted
var building_widget_scene = preload("res://scenes/ui/building_widget.tscn")
var widgets = []

var logistics_grid: GridContainer
var logistics_rack: VBoxContainer

func _ready():
	manager = GameState.infrastructure_manager
	$VBoxContainer/ScrollContainer.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_setup_logistics_rack()
	call_deferred("refresh_list")

func _setup_logistics_rack():
	# Create a new rack for Command/Logistics since it's missing in .tscn
	logistics_rack = VBoxContainer.new()
	logistics_rack.name = "LogisticsRack"
	logistics_rack.add_theme_constant_override("separation", 10)
	
	var header = Label.new()
	header.text = "[ COMMAND & LOGISTICS ]"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.6, 0.4, 1.0, 0.5))
	logistics_rack.add_child(header)
	
	logistics_grid = GridContainer.new()
	logistics_grid.columns = 5
	logistics_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	logistics_grid.add_theme_constant_override("h_separation", 15)
	logistics_grid.add_theme_constant_override("v_separation", 15)
	logistics_rack.add_child(logistics_grid)
	
	var sep = HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.2)
	logistics_rack.add_child(sep)
	
	blade_container.add_child(logistics_rack)

func refresh_list():
	for grid in [energy_grid, mining_grid, production_grid, logistics_grid]:
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
		
		target_grid.add_child(w)
		w.setup(bid, data, manager, self)
		widgets.append(w)

func _process(delta):
	# Update UI elements
	update_ui()
	# Manager ticks handled by GameState process

func update_ui():
	if not manager: return
	
	manager.recalc_energy() # Ensure fresh stats? Process loop handles actual logic
	
	var net = manager.net_energy
	var gen = manager.generation
	var cons = manager.consumption
	
	net_lbl.text = "NET: %+.1f kW" % net
	gen_lbl.text = "GEN: %.1f kW" % gen
	cons_lbl.text = "CONS: %.1f kW" % cons
	
	if net >= 0:
		net_lbl.add_theme_color_override("font_color", Color.CYAN)
	else:
		net_lbl.add_theme_color_override("font_color", Color.ORANGE_RED)
	
	# Widgets update themselves in _process usually, or we can force it
	for w in widgets:
		w.update_state()
