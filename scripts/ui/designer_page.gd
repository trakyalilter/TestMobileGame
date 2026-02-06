extends Control

# PHASE 22: Ship Designer UI Overhaul
# Premium sci-fi aesthetic with expanded stats and module comparison

# Top info bar (full width, 1-line)
@onready var ship_name_lbl = $VBoxContainer/InfoPanel/InfoHBox/ShipNameLabel
@onready var stats_lbl = $VBoxContainer/InfoPanel/InfoHBox/StatsLabel

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
	UITheme.apply_card_style($VBoxContainer/InfoPanel, "shipyard")
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

# ─────────────────────────────────────────────────
# EXPANDED STATS DISPLAY (PHASE 22)
# ─────────────────────────────────────────────────

func update_header():
	if manager.active_hull and manager.active_hull in manager.hulls:
		var h = manager.hulls[manager.active_hull]
		ship_name_lbl.text = h["name"].to_upper()
		
		# Calculate energy capacity (hull + battery modules)
		var hull_data = manager.hulls.get(manager.active_hull, {})
		var e_cap = hull_data.get("stats", {}).get("energy_capacity", 100)
		for idx in manager.loadout:
			var mid = manager.loadout[idx]
			if mid and mid in manager.modules:
				e_cap += manager.modules[mid].get("stats", {}).get("energy_capacity", 0)
		var e_used = manager.energy_used
		
		# Calculate DPS
		var total_dps = _calculate_total_dps()
		
		# Get milestone bonuses from combat manager
		var cm = GameState.combat_manager
		var total_eva = manager.evasion + cm.get_milestone_evasion_bonus()
		var total_crit = (manager.crit_chance + cm.get_milestone_crit_bonus()) * 100.0
		
		# Build single-line stats display
		var stats_text = "HP: %d | SH: %s | ATK: %s | DEF: %s | ACC: %.0f | CRIT: %.0f%% | EVA: %.0f | DPS: %s | PWR: %d/%d" % [
			manager.max_hp,
			UITheme.format_num(manager.max_shield),
			UITheme.format_num(manager.attack),
			UITheme.format_num(manager.defense),
			manager.accuracy,
			total_crit,
			total_eva,
			UITheme.format_num(total_dps),
			e_used,
			e_cap
		]
		
		stats_lbl.text = stats_text
		
		# Power grid warning colors
		if e_used > e_cap:
			stats_lbl.modulate = Color(1, 0.3, 0.3)  # Red - overloaded
		elif e_used > e_cap * 0.8:
			stats_lbl.modulate = Color(1, 0.7, 0.2)  # Orange - nearing limit
		else:
			stats_lbl.modulate = Color(0.7, 0.7, 0.7)  # Normal
	else:
		ship_name_lbl.text = "NO HULL"
		stats_lbl.text = "Escape Pod Active"

func _calculate_total_dps() -> float:
	var total = 0.0
	for s_idx in manager.loadout:
		var mid = manager.loadout[s_idx]
		if mid and mid in manager.modules:
			var m_data = manager.modules[mid]
			if m_data.get("slot_type") == "weapon":
				var stats = m_data.get("stats", {})
				var dmg = stats.get("atk_kinetic", 0) + stats.get("atk_energy", 0) + stats.get("atk_explosive", 0)
				var interval = stats.get("atk_interval", 2.5)
				if interval > 0:
					total += float(dmg) / interval
	return total

# ─────────────────────────────────────────────────
# SLOT BLADES
# ─────────────────────────────────────────────────

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
			
	# Create Blades in Order with premium colors
	_create_blade("🔥 Weapons", blades["Weapons"], s_cont, Color(1.0, 0.4, 0.4, 0.8))
	_create_blade("💥 Ammunition", blades["Ammunition"], s_cont, Color(1.0, 0.6, 0.3, 0.8), true)
	_create_blade("🛡 Defense", blades["Defense"], s_cont, Color(0.4, 0.6, 1.0, 0.8))
	_create_blade("⚡ Systems", blades["Systems"], s_cont, Color(0.8, 1.0, 0.2, 0.8))
	_create_blade("🔧 Utility", blades["Utility"], s_cont, Color(0.6, 0.6, 0.6, 0.8))

func _create_blade(title: String, slot_list: Array, parent: Node, color: Color = Color.WHITE, is_ammo: bool = false):
	if slot_list.is_empty(): return
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	parent.add_child(vbox)
	
	var label = Label.new()
	label.text = "[ %s ]" % title.to_upper()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	vbox.add_child(label)
	
	# Horizontal scroll container for slots
	var scroll = ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.custom_minimum_size.y = 90
	vbox.add_child(scroll)
	
	# HBox for horizontal slot layout
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	scroll.add_child(hbox)
	
	for s_data in slot_list:
		var w
		if is_ammo:
			w = ammo_slot_scene.instantiate()
			hbox.add_child(w)
			w.setup(s_data["idx"], self, manager)
		else:
			w = slot_widget_scene.instantiate()
			hbox.add_child(w)
			w.setup(s_data["idx"], s_data["type"], self, manager)
			
	# Add separator
	var sep = HSeparator.new()
	sep.modulate = Color(color.r, color.g, color.b, 0.3)
	vbox.add_child(sep)

func sync_silhouette():
	if not manager.active_hull: return
	var h = manager.hulls.get(manager.active_hull)
	if h and h.has("visual"):
		var tex = load(h["visual"])
		if silhouette.texture != tex:
			silhouette.texture = tex
			# Holographic pulse effect
			var tween = create_tween()
			silhouette.modulate.a = 0.1
			tween.tween_property(silhouette, "modulate:a", 0.4, 0.5)

func rebuild_ammo_slots():
	pass # Integrated into blade system

# ─────────────────────────────────────────────────
# STORAGE GRID
# ─────────────────────────────────────────────────

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

# ─────────────────────────────────────────────────
# CIRCUIT LINES
# ─────────────────────────────────────────────────

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
