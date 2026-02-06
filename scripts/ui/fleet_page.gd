extends Control

@onready var scroll_container = $VBoxContainer/ScrollContainer
@onready var stats_lbl = $VBoxContainer/FleetDash/HBoxContainer/StatsLabel

var manager: RefCounted
var slot_widget_scene = preload("res://scenes/ui/fleet_slot_widget.tscn")
var widgets = []
var rack_container: VBoxContainer

func _ready():
	manager = GameState.fleet_manager
	
	UITheme.setup_page_background(self)
	
	# Create blade-style rack container dynamically
	_setup_rack_container()
	call_deferred("refresh_list")

func _setup_rack_container():
	# Remove existing GridContainer and replace with blade rack
	var old_grid = scroll_container.get_node_or_null("GridContainer")
	if old_grid:
		old_grid.queue_free()
	
	rack_container = VBoxContainer.new()
	rack_container.name = "RackContainer"
	rack_container.add_theme_constant_override("separation", 20)
	scroll_container.add_child(rack_container)

func refresh_list():
	if not manager: return
	if not rack_container: return
	
	for child in rack_container.get_children():
		child.queue_free()
	widgets.clear()
	
	# Create rack header
	var header = Label.new()
	header.text = "[ ACTIVE EXPEDITIONS ]"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0, 0.5))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rack_container.add_child(header)
	
	# Create grid for fleet slots
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	rack_container.add_child(grid)
	
	# Current max slots from research
	var max_slots = manager.max_slots
	
	for i in range(max_slots):
		var w = slot_widget_scene.instantiate()
		grid.add_child(w)
		w.setup(i, manager, self)
		widgets.append(w)
	
	var sep = HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.1)
	rack_container.add_child(sep)

func _process(_delta):
	update_ui()

func update_ui():
	if not manager: return
	
	var active_count = manager.active_expeditions.size()
	var max_slots = manager.max_slots
	
	# P2-10: Show pending repairs in fleet stats
	var pending_total = manager.get_total_pending_repairs()
	if pending_total > 0:
		stats_lbl.text = "Active: %d/%d | REPAIRS NEEDED: %d Cr" % [active_count, max_slots, pending_total]
		stats_lbl.add_theme_color_override("font_color", Color.ORANGE)
	else:
		stats_lbl.text = "Active Fleets: %d / %d" % [active_count, max_slots]
		stats_lbl.add_theme_color_override("font_color", Color.WHITE)
	
	# Widgets poll their own status in their _process

# P2-10: Fleet repair function called from UI
func _on_repair_all_pressed():
	if manager:
		var repaired = manager.repair_all_ships()
		if repaired > 0:
			refresh_list()
