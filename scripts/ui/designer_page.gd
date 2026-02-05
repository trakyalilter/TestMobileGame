extends Control

@onready var ship_name_lbl = $VBoxContainer/MainLayout/LeftPanel/InfoPanel/Margin/VBox/ShipNameLabel
@onready var stats_lbl = $VBoxContainer/MainLayout/LeftPanel/InfoPanel/Margin/VBox/StatsLabel



# Storage
@onready var storage_grid = $VBoxContainer/MainLayout/RightPanel/Scroll/UnifiedStorageGrid
@onready var silhouette = $VBoxContainer/MainLayout/SchematicArea/Silhouette
@onready var circuit_bg = $VBoxContainer/MainLayout/SchematicArea/CircuitBackground

# Filter Buttons
@onready var f_all = $VBoxContainer/MainLayout/RightPanel/FilterConsole/FilterStrip/AllBtn
@onready var f_wpn = $VBoxContainer/MainLayout/RightPanel/FilterConsole/FilterStrip/WpnBtn
@onready var f_sys = $VBoxContainer/MainLayout/RightPanel/FilterConsole/FilterStrip/SysBtn
@onready var f_ord = $VBoxContainer/MainLayout/RightPanel/FilterConsole/FilterStrip/OrdBtn

var manager: RefCounted
var active_filter = "all"
var slot_widget_scene = preload("res://scenes/ui/designer_slot_widget.tscn")
var ammo_slot_scene = preload("res://scenes/ui/designer_ammo_slot_widget.tscn")
var draggable_icon_scene = preload("res://scenes/ui/module_card.tscn") 

func _ready():
	manager = GameState.shipyard_manager
	visibility_changed.connect(_on_visibility_changed)
	GameState.game_loaded.connect(trigger_refresh)
	
	# Premium Styling
	UITheme.apply_card_style($VBoxContainer/MainLayout/LeftPanel/InfoPanel, "shipyard")
	UITheme.apply_card_style($VBoxContainer/MainLayout/RightPanel, "engineering")
	
	$VBoxContainer/Label.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["shipyard"])
	
	f_all.pressed.connect(func(): _on_filter_changed("all"))
	f_wpn.pressed.connect(func(): _on_filter_changed("wpn"))
	f_sys.pressed.connect(func(): _on_filter_changed("sys"))
	f_ord.pressed.connect(func(): _on_filter_changed("ord"))
	
	circuit_bg.draw.connect(_on_circuit_draw)
	
	trigger_refresh()

func _on_visibility_changed():
	if visible:
		trigger_refresh()

func trigger_refresh():
	update_header()
	sync_silhouette()
	rebuild_slots()
	rebuild_ammo_slots()
	rebuild_storage()
	# rebuild_ammo_storage() -> Consolidated into rebuild_storage

func update_header():
	if manager.active_hull and manager.active_hull in manager.hulls:
		var h = manager.hulls[manager.active_hull]
		ship_name_lbl.text = h["name"]
		var e_max = GameState.resources.max_energy
		var e_used = manager.energy_used
		stats_lbl.text = "HP: %d | SHIELD: %d\nENERGY: %d/%d\nATK: %d | DEF: %d" % [manager.max_hp, manager.max_shield, e_used, e_max, manager.attack, manager.defense]
		stats_lbl.modulate = Color(1, 0.3, 0.3) if e_used > e_max else Color(0.8, 0.8, 0.8)
	else:
		ship_name_lbl.text = "No Structure"
		stats_lbl.text = "Escape Pod Active"

func rebuild_slots():
	var s_cont = $VBoxContainer/MainLayout/SchematicArea/SlotMap/SchematicContainer
	if s_cont:
		for child in s_cont.get_children():
			child.queue_free()
			
	if not manager.active_hull in manager.hulls: return
	
	var h_data = manager.hulls[manager.active_hull]
	var slots = h_data["slots"]
	
	# Categorize Slots
	var blades = {
		"Weapons": [],
		"Defense": [],
		"Systems": [],
		"Utility": [],
		"Ammunition": []
	}
	
	for i in range(slots.size()):
		var s_type = slots[i]
		if s_type == "weapon":
			blades["Weapons"].append({"idx": i, "type": s_type})
			# Add ammo slot for every weapon slot
			blades["Ammunition"].append({"idx": i, "type": "ammo"})
		elif s_type == "shield" or s_type == "armor":
			blades["Defense"].append({"idx": i, "type": s_type})
		elif s_type == "engine" or s_type == "reactor" or s_type == "battery":
			blades["Systems"].append({"idx": i, "type": s_type})
		else:
			blades["Utility"].append({"idx": i, "type": s_type})
			
	# Create Blades in Order
	_create_blade("Weapons", blades["Weapons"], s_cont)
	_create_blade("Ammunition", blades["Ammunition"], s_cont, true)
	_create_blade("Defense", blades["Defense"], s_cont)
	_create_blade("Systems", blades["Systems"], s_cont)
	_create_blade("Utility", blades["Utility"], s_cont)

func _create_blade(title: String, slot_list: Array, parent: Node, is_ammo: bool = false):
	if slot_list.is_empty(): return
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	parent.add_child(vbox)
	
	var label = Label.new()
	label.text = "[ %s ]" % title.to_upper()
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	vbox.add_child(label)
	
	var flow = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	vbox.add_child(flow)
	
	for s_data in slot_list:
		var w
		if is_ammo:
			w = ammo_slot_scene.instantiate()
			flow.add_child(w)
			w.setup(s_data["idx"], self, manager)
		else:
			w = slot_widget_scene.instantiate()
			flow.add_child(w)
			w.setup(s_data["idx"], s_data["type"], self, manager)
			
	# Add Spacer
	var sep = Control.new()
	sep.custom_minimum_size = Vector2(0, 10)
	parent.add_child(sep)

func sync_silhouette():
	if not manager.active_hull: return
	var h = manager.hulls.get(manager.active_hull)
	if h and h.has("visual"):
		silhouette.texture = load(h["visual"])

func rebuild_ammo_slots():
	pass # Integrated into blade system

func rebuild_storage():
	for child in storage_grid.get_children(): child.queue_free()
	
	# Modules
	var inv = manager.module_inventory
	for mid in inv:
		var count = inv[mid]
		if count > 0 and mid in manager.modules:
			var data = manager.modules[mid]
			var type = data.get("slot_type", "weapon")
			
			var show = false
			if active_filter == "all": show = true
			elif active_filter == "wpn" and type == "weapon": show = true
			elif active_filter == "sys" and type in ["shield", "engine", "battery"]: show = true
			
			if show:
				var item = draggable_icon_scene.instantiate()
				storage_grid.add_child(item)
				item.setup(mid, data, count)
			
	# Ammo
	if active_filter in ["all", "ord"]:
		var ammo_list = [
			{"id": "SlugT1"},
			{"id": "SlugT2"},
			{"id": "SlugT3"},
			{"id": "CellT1"},
			{"id": "CellT2"},
			{"id": "CellT3"}
		]
		for ammo in ammo_list:
			var qty = GameState.resources.get_element_amount(ammo["id"])
			if qty > 0:
				var card = draggable_icon_scene.instantiate()
				storage_grid.add_child(card)
				var dname = ElementDB.get_display_name(ammo["id"])
				var fake_data = {"name": dname, "slot_type": "ammo", "stats": {}}
				card.setup(ammo["id"], fake_data, qty)

func rebuild_ammo_storage():
	pass # Unified into rebuild_storage

func _on_filter_changed(filter_id: String):
	active_filter = filter_id
	# Sync buttons
	f_all.button_pressed = (filter_id == "all")
	f_wpn.button_pressed = (filter_id == "wpn")
	f_sys.button_pressed = (filter_id == "sys")
	f_ord.button_pressed = (filter_id == "ord")
	
	rebuild_storage()

func get_module_widget(module_id: String) -> Control:
	for child in storage_grid.get_children():
		if child.get("mid") == module_id:
			return child
	return null

func _on_circuit_draw():
	# Draw glowing lines between slots that are next to each other
	var accent = UITheme.COLORS["accent_bright"]
	var s_cont = $VBoxContainer/MainLayout/SchematicArea/SlotMap/SchematicContainer
	if not s_cont: return
	
	for blade_vbox in s_cont.get_children():
		if not blade_vbox is VBoxContainer: continue
		var flow = null
		for child in blade_vbox.get_children():
			if child is HFlowContainer:
				flow = child
				break
		
		if not flow: continue
		var children = flow.get_children()
		if children.size() < 2: continue
		
		for i in range(children.size() - 1):
			var s1 = children[i]
			var s2 = children[i+1]
			
			# Only draw if BOTH are occupied
			if s1.get("is_occupied") and s2.get("is_occupied"):
				var p1 = s1.global_position + (s1.size / 2.0) - circuit_bg.global_position
				var p2 = s2.global_position + (s2.size / 2.0) - circuit_bg.global_position
				
				# Glow line (thick blurred behind)
				circuit_bg.draw_line(p1, p2, Color(accent, 0.3), 6.0, true)
				# Core line (thin bright)
				circuit_bg.draw_line(p1, p2, accent, 1.5, true)

func _process(_delta):
	# Refresh circuit lines
	circuit_bg.queue_redraw()
