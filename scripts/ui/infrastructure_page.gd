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
var logistics_grid: HFlowContainer

func _ready():
	manager = GameState.infrastructure_manager
	$VBoxContainer/ScrollContainer.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_setup_logistics_rack()
	call_deferred("refresh_list")

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
	
	logistics_grid = HFlowContainer.new()
	logistics_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	logistics_grid.add_theme_constant_override("h_separation", 15)
	logistics_grid.add_theme_constant_override("v_separation", 15)
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
			cons_lbl.text = "CONS: %.1f kW [color=#ff6666](Grid Stalled: %d%%)[/color]" % [cons, int(eff * 100)]
		else:
			cons_lbl.text = "CONS: %.1f kW" % cons

	for w in widgets:
		w.update_state()
