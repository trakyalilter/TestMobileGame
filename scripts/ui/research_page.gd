extends Control

@onready var tabs = $VBoxContainer/TabContainer


var manager: RefCounted

# Graph Data
# Each tab has a Control which acts as a Canvas for custom drawing
var node_scene = preload("res://scenes/ui/research_node_widget.tscn")

var graphs = {
	"Operations": {
		"nodes": [
			# Early Game - Mining & Drilling
			"energy_shields", "industrial_logistics",
			"diamond_drills", "ultrasonic_drills", "plasma_bore",
			
			# Liquids
			"high_flow_pumps", "superfluid_intake", "hydro_vortex",
			
			# Deforestation
			"laser_cutters", "mono_filament", "molecular_disassembler",
			
			# Gases / Nebula
			"magnetic_funnels", "deep_core_optics",
			
			# Exploration / Sectors
			"sector_alpha_decryption", "deep_space_nav", "radiation_shielding",
			"exotic_matter_analysis", "void_physics", "void_navigation",
			"field_theory",

			# Missing Techs Restored (Audit)
			"eff_scanning_1", "xeno_archaeology",
			
			# v80.4: Zone Access Gates (required for hulls, modules, and combat zones)
			"zone_2_access", "zone_3_access", "zone_4_access", "zone_5_access", "zone_6_access",
			"zone_7_access", "zone_8_access", "zone_9_access", "zone_10_access",
			
			# Efficiency Branch
			"efficiency_1", "efficiency_2", "efficiency_3", "efficiency_4", "efficiency_5"
		],
		"pos": {
			# Branch 1: Liquids (Pumps)
			"high_flow_pumps": Vector2(40, 40),
			"superfluid_intake": Vector2(240, 40),
			"hydro_vortex": Vector2(440, 40),
			
			# Branch 2: Deforestation (Lasers)
			"laser_cutters": Vector2(40, 150),
			"mono_filament": Vector2(240, 150),
			"molecular_disassembler": Vector2(440, 150),
			
			# Branch 3: Excavation (Drills) - Moved down
			"diamond_drills": Vector2(40, 260),
			"ultrasonic_drills": Vector2(240, 260),
			"plasma_bore": Vector2(440, 260),

			# Branch 4: Utility & Gases
			"energy_shields": Vector2(40, 370),
			"field_theory": Vector2(40, 430), # Child of Energy Fields — gates IonField consumable
			"magnetic_funnels": Vector2(240, 370),
			"eff_scanning_1": Vector2(40, 480), # Restored
			"deep_core_optics": Vector2(240, 480), # Shifted right
			
			# Branch 5: Exploration (The Path to the Void)
			"sector_alpha_decryption": Vector2(40, 600),
			"xeno_archaeology": Vector2(40, 700), # Restored (Child of Sector Alpha)
			
			"deep_space_nav": Vector2(240, 600),
			"radiation_shielding": Vector2(440, 600),
			"exotic_matter_analysis": Vector2(640, 600),
			"void_physics": Vector2(840, 600),
			"void_navigation": Vector2(1040, 600),
			
			
			# Branch 7: Zone Access Gates (v80.4 — Required for Hulls & Modules)
			"zone_2_access": Vector2(40, 850),
			"zone_3_access": Vector2(240, 850),
			"zone_4_access": Vector2(440, 850),
			"zone_5_access": Vector2(640, 850),
			"zone_6_access": Vector2(840, 850),
			"zone_7_access": Vector2(1040, 850),
			"zone_8_access": Vector2(1240, 850),
			"zone_9_access": Vector2(1440, 850),
			"zone_10_access": Vector2(1640, 850),
			
			# Branch 8: Efficiency (Yield Boosts)
			"efficiency_1": Vector2(240, 370),
			"efficiency_2": Vector2(440, 370),
			"efficiency_3": Vector2(640, 370),
			"efficiency_4": Vector2(840, 370),
			"efficiency_5": Vector2(1040, 370)
		},
		"container": null # Assigned in _ready
	},
	"Engineering": {
		"nodes": [
			# Layout 0
			"basic_engineering", "applied_physics", "materials_science", "industrial_logistics",
			
			# Layout 1: Fluids & Electro
			"fluid_dynamics", "catalytic_electrodes", "ion_exchange", "resonance_splitters",
			"industrial_electrolysis", "energy_metrics", "cryogenic_systems", "cryogenic_storage",
			
			# Layout 2: Combustion & Smelting
			"combustion", "pyrolysis_control", "smelting", "blast_furnace", "automated_smelting", 
			"oxygen_blast_furnace", "metallurgy_advanced", "superalloy_engineering", "iridium_metallurgy", "exotic_metallurgy",
			
			# Layout 3: Materials
			"adv_materials", "hydraulic_press", "molecular_compression",
			"kinetics_101", "laser_optics", "power_systems", "lightweight_alloys",
			
			# Layout 4: High Tech & Automation
			"fast_centrifuges", "maglev_bearings", "quantum_separators", "advanced_mineralogy",
			"automation", "automated_logistics", "industrial_automation", "molecular_recycling", "xeno_engineering",
			"mass_production_tactics", "nano_fabrication", "data_clustering",
			"precious_metal_refining", "industrial_catalysis", "fuel_cell_tech",
			"colony_automation", "perfect_automation",
			"basic_electronics", "advanced_batteries" # Added advanced_batteries
		],
		"pos": {
			"basic_engineering": Vector2(40, 400),
			
			# Upper Branch: Fluid Dynamics -> Electrolysis -> Cryo
			"fluid_dynamics": Vector2(240, 100),
			"catalytic_electrodes": Vector2(440, 40),
			"ion_exchange": Vector2(640, 40),
			"resonance_splitters": Vector2(840, 40),
			"industrial_electrolysis": Vector2(640, 110),
			
			"energy_metrics": Vector2(440, 180),
			"cryogenic_systems": Vector2(640, 180),
			"cryogenic_storage": Vector2(840, 180),
			
			# Mid-Upper: Combustion -> Smelting Chain (The Backbone)
			"combustion": Vector2(240, 300),
			"pyrolysis_control": Vector2(440, 300),
			
			"smelting": Vector2(240, 400),
			"blast_furnace": Vector2(440, 400),
			"automated_smelting": Vector2(640, 400),
			"oxygen_blast_furnace": Vector2(840, 400),
			
			"metallurgy_advanced": Vector2(640, 330),
			"superalloy_engineering": Vector2(840, 330),
			"iridium_metallurgy": Vector2(1040, 330),
			"exotic_metallurgy": Vector2(1240, 330),
			
			"precious_metal_refining": Vector2(1040, 250), # From Deep Space Nav (handled in graph logic or floating?)
			# Actually precious_metal_refining parent is deep_space_nav which is in Operations. 
			# We'll rely on cross-tab logic or just visualize it here as a root/floating node if parent missing
			"industrial_catalysis": Vector2(1240, 250),
			"fuel_cell_tech": Vector2(1240, 180),
			
			# Mid: Materials
			"materials_science": Vector2(240, 500),
			"lightweight_alloys": Vector2(440, 500),
			"adv_materials": Vector2(440, 580),
			"hydraulic_press": Vector2(640, 580),
			"molecular_compression": Vector2(840, 580),
			"advanced_batteries": Vector2(640, 650),
			"automation": Vector2(440, 650), # Added Factory Automation

			# Lower: Logistics & Centrifuges
			"industrial_logistics": Vector2(240, 750),
			"basic_electronics": Vector2(440, 820), # Restored Node
			"fast_centrifuges": Vector2(440, 750),
			"maglev_bearings": Vector2(640, 750),
			"quantum_separators": Vector2(840, 750),
			"advanced_mineralogy": Vector2(640, 820),
			
			"automated_logistics": Vector2(440, 900),
			"mass_production_tactics": Vector2(640, 900),
			"xeno_engineering": Vector2(640, 970),
			"industrial_automation": Vector2(640, 1040),
			"molecular_recycling": Vector2(840, 1040),
			
			"colony_automation": Vector2(840, 1120),
			"perfect_automation": Vector2(1040, 1120),
			
			"nano_fabrication": Vector2(640, 1190),
			"data_clustering": Vector2(440, 1190),
		},
		"container": null
	},
	"Ships": {
		"nodes": [
			# Early Gates (from Applied Physics)
			"kinetics_101", "power_systems", "laser_optics",
			
			# Shipwright Chain
			"shipwright_1", "shipwright_2", "molecular_printing",
			"capital_ship_engineering", "capital_ship_armament", "quantum_dynamics",

			# Warp & Navigation
			"warp_drive", "warp_stabilizer",

			# Military Techs (Processing Tungsten -> Ballistics)
			"processing_tungsten", "ballistics_optimization", "advanced_rocketry",

			# Void / Endgame
			"void_weaponry_1", "void_shielding_1",
			
			# Efficiency
			"combat_heuristics", "shield_harmonics", "hull_hardening", "core_overclocking",
			
			# Auto-Repair (Audit v66.0)
			"auto_repair_20", "auto_repair_40", "auto_repair_60", "auto_repair_80"
		],
		"pos": {
			# Column 1: Basics
			"kinetics_101": Vector2(40, 40),
			"power_systems": Vector2(40, 120),
			"laser_optics": Vector2(40, 200),
			
			# Column 2: Early Shipwright
			"shipwright_1": Vector2(240, 200),
			"shipwright_2": Vector2(440, 200),
			"molecular_printing": Vector2(640, 200),
			
			# Column 3: Advanced Ships
			"capital_ship_engineering": Vector2(440, 320),
			"capital_ship_armament": Vector2(640, 320),
			"quantum_dynamics": Vector2(840, 320),

			# Column 4: Weapons Tech (Lower Branch)
			"processing_tungsten": Vector2(40, 500),
			"ballistics_optimization": Vector2(240, 500),
			"advanced_rocketry": Vector2(440, 500), # Sits under automation usually, moved here for mil-tech coherence
			
			# Column 5: Warp
			"warp_drive": Vector2(440, 80),
			"warp_stabilizer": Vector2(640, 80),
			
			# Column 6: Void High-End
			"void_weaponry_1": Vector2(1040, 320),
			"void_shielding_1": Vector2(1040, 400),
			
			# Passives / Utilities
			"shield_harmonics": Vector2(240, 600),
			"hull_hardening": Vector2(240, 680),
			"core_overclocking": Vector2(240, 760),
			
			# Auto-Repair Branch (Right of Hull Hardening)
			"auto_repair_20": Vector2(440, 680),
			"auto_repair_40": Vector2(640, 680),
			"auto_repair_60": Vector2(840, 680),
			"auto_repair_80": Vector2(1040, 680),
			"combat_heuristics": Vector2(40, 840)
		},
		"container": null
	},
	"Recursion": {
		"nodes": ["production_focus", "combat_focus", "gathering_focus"],
		"pos": {
			"production_focus": Vector2(40, 40),
			"combat_focus": Vector2(40, 180),
			"gathering_focus": Vector2(40, 320)
		},
		"container": null
	}
}

func _ready():
	manager = GameState.research_manager
	
	# Premium Styling
	UITheme.apply_tab_style($VBoxContainer/TabContainer, "research")
	
	# Mission & Resource Integration
	GameState.mission_manager.mission_updated.connect(_on_mission_updated)
	if GameState.resources:
		GameState.resources.element_added.connect(_on_resource_changed)
		GameState.resources.currency_added.connect(_on_resource_changed)
	
	# Dynamic tab creation for Recursion
	var rec_tab = Control.new()
	rec_tab.name = "Recursion"
	tabs.add_child(rec_tab)
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rec_tab.add_child(scroll)
	var area = Control.new()
	area.name = "GraphArea"
	scroll.add_child(area)
	
	# Graphs are Panels inside TabContainer
	graphs["Operations"]["container"] = $VBoxContainer/TabContainer/Operations/ScrollContainer/GraphArea
	graphs["Engineering"]["container"] = $VBoxContainer/TabContainer/Engineering/ScrollContainer/GraphArea
	graphs["Ships"]["container"] = $VBoxContainer/TabContainer/Ships/ScrollContainer/GraphArea
	graphs["Recursion"]["container"] = area
	
	# Add panning support to all graph areas
	_setup_panning($VBoxContainer/TabContainer/Operations/ScrollContainer)
	_setup_panning($VBoxContainer/TabContainer/Engineering/ScrollContainer)
	_setup_panning($VBoxContainer/TabContainer/Ships/ScrollContainer)
	_setup_panning(scroll)
	
	call_deferred("build_graphs")
	call_deferred("_on_mission_updated") # Initial check

func _on_resource_changed(_a=null, _b=null):
	refresh_all()

func _on_mission_updated():
	_update_tab_alerts()

# ─────────────────────────────────────────────────
# PANNING SUPPORT (PHASE 22)
# ─────────────────────────────────────────────────

var _pan_containers: Array = []
var _is_panning: bool = false
var _pan_start_scroll: Vector2 = Vector2.ZERO
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _active_scroll: ScrollContainer = null

func _setup_panning(scroll_container: ScrollContainer):
	_pan_containers.append(scroll_container)
	scroll_container.gui_input.connect(_on_scroll_gui_input.bind(scroll_container))

func _on_scroll_gui_input(event: InputEvent, scroll: ScrollContainer):
	# Left-click drag for panning
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_panning = true
				_active_scroll = scroll
				_pan_start_scroll = Vector2(scroll.scroll_horizontal, scroll.scroll_vertical)
				_pan_start_mouse = event.global_position
				scroll.mouse_default_cursor_shape = Control.CURSOR_DRAG
			else:
				_is_panning = false
				_active_scroll = null
				scroll.mouse_default_cursor_shape = Control.CURSOR_ARROW
				
	elif event is InputEventMouseMotion and _is_panning and _active_scroll == scroll:
		var delta = _pan_start_mouse - event.global_position
		scroll.scroll_horizontal = int(_pan_start_scroll.x + delta.x)
		scroll.scroll_vertical = int(_pan_start_scroll.y + delta.y)

func on_page_enter():
	# SMART NAVIGATION: When a tutorial/active mission points at a research,
	# switch to its tab AND center the required node so the player isn't left
	# hunting the tree after clicking the beeping Research Lab button.
	var mm = GameState.mission_manager
	if not mm: return

	for mid in mm.active_missions:
		var m = mm.missions[mid]
		if m["type"] == "research":
			var tech_id = m["target"]

			# Only act if the target actually exists in a tab's node list
			for tab_name in graphs:
				if tech_id in graphs[tab_name]["nodes"]:
					focus_on_tech(tech_id)
					return # Found our target, stop searching

var active_alert_indices: Array = []

func _update_tab_alerts():
	var mm = GameState.mission_manager
	if not mm: return
	
	# 1. Calculate Desired State
	var desired_indices = []
	
	for mid in mm.active_missions:
		var m = mm.missions[mid]
		if m["type"] == "research":
			var tech_id = m["target"]
			
			for tab_name in graphs:
				if tech_id in graphs[tab_name]["nodes"]:
					# Find index
					for i in range(tabs.get_tab_count()):
						# Audit v16.3: Use Node Name (immutable) for matching
						if tabs.get_tab_control(i).name == tab_name:
							if not i in desired_indices:
								desired_indices.append(i)
							break
	
	# 2. Apply Diff (Anti-Disco Logic)
	# Turn OFF indicators no longer needed
	for idx in active_alert_indices:
		if not idx in desired_indices:
			UITheme.trigger_tab_alert(tabs, idx, false)
			
	# Turn ON new indicators
	for idx in desired_indices:
		if not idx in active_alert_indices:
			UITheme.trigger_tab_alert(tabs, idx, true)
			
	# 3. Update State Cache
	active_alert_indices = desired_indices.duplicate()

func build_graphs():
	for tab_name in graphs:
		var g_data = graphs[tab_name]
		var container = g_data["container"]
		
		# Clear existing
		for child in container.get_children():
			child.queue_free()
			
		# Dynamic Layout Calculation
		var layout_pos = calculate_layout(g_data["nodes"])
		
		# Track content size
		var max_pos = Vector2.ZERO
		
		# Add Nodes
		for nid in g_data["nodes"]:
			if nid not in manager.tech_tree: continue
			
			var data = manager.tech_tree[nid]
			var node_widget = node_scene.instantiate()
			container.add_child(node_widget)
			
			var pos = layout_pos.get(nid, Vector2(0,0))
			node_widget.position = pos
			node_widget.scale = Vector2(0.75, 0.75)
			node_widget.setup(nid, data, manager, self)
			
			# Approx size of scaled node (w=180, h=80 roughly)
			max_pos.x = max(max_pos.x, pos.x + 200.0)
			max_pos.y = max(max_pos.y, pos.y + 140.0)
			
		# Update container size for scrolling
		container.custom_minimum_size = max_pos + Vector2(50, 50) # Padding
			
		if not container.is_connected("draw", _on_graph_draw.bind(container, tab_name, layout_pos)):
			container.draw.connect(_on_graph_draw.bind(container, tab_name, layout_pos))
			
		container.queue_redraw()

# --- Dynamic Tree Layout Algorithm ---
func calculate_layout(nodes_list: Array) -> Dictionary:
	var final_pos = {}
	var local_tree = {} # { parent_id: [child_id, ...] }
	var roots = []
	
	# 1. Build Local Tree
	var nodes_set = {}
	for n in nodes_list: nodes_set[n] = true
	
	for nid in nodes_list:
		if nid not in manager.tech_tree: continue
		var p_id = manager.tech_tree[nid].get("parent")
		
		# If parent not in this tab, treat as root for this view
		if not p_id or p_id not in nodes_set:
			roots.append(nid)
		else:
			if not p_id in local_tree: local_tree[p_id] = []
			local_tree[p_id].append(nid)
			
	# 2. Layout Recursively
	var current_y = 40.0
	var level_x = 200.0 # Increased X spacing
	var node_height = 140.0 # Increased slot size for dynamic vertical growth
	
	# Helper to calculate subtree sizes and assign Y
	var _layout_recursive = func(f_self, node_id: String, depth: int, start_y: float) -> float:
		var children = local_tree.get(node_id, [])
		
		# Base case: Leaf
		if children.is_empty():
			final_pos[node_id] = Vector2(40 + depth * level_x, start_y)
			return node_height
		
		# Recursive Layout Children
		var children_total_h = 0.0
		var c_y = start_y
		
		for i in range(children.size()):
			var child = children[i]
			var h = f_self.call(f_self, child, depth + 1, c_y)
			children_total_h += h
			c_y += h
			
			# Add gap between siblings
			if i < children.size() - 1:
				var gap = 20.0
				children_total_h += gap
				c_y += gap
			
		# Center parent relative to children span
		# Span center = start_y + (children_total_h / 2.0)
		# Node center should align with Span center
		# Node top (pos.y) = Span center - (node_height / 2.0) # Assuming node visual is centered in slot
		var mid_y = start_y + (children_total_h / 2.0) - (node_height / 2.0)
		
		var used_h = max(node_height, children_total_h)
		
		final_pos[node_id] = Vector2(40 + depth * level_x, mid_y)
		return used_h

	# 3. Execute Layout
	for root in roots:
		var h = _layout_recursive.call(_layout_recursive, root, 0, current_y)
		current_y += h + 40.0 # Spacing between trees
		
	return final_pos

func _on_graph_draw(container, tab_name, positions):
	var g_data = graphs[tab_name]
	
	for nid in g_data["nodes"]:
		if nid not in manager.tech_tree: continue
		var node_data = manager.tech_tree[nid]
		var parent = node_data.get("parent")
		
		if parent and parent in positions and nid in positions:
			# Adjusted centers for 0.75 scaled nodes (W=160*0.75=120, H=100*0.75=75)
			# Exit from previous node (right side)
			var p1 = positions[parent] + Vector2(120, 37.5) 
			# Enter into current node (left side)
			var p2 = positions[nid] + Vector2(0, 37.5)
			
			# Determine Path State/Color
			var is_completed = manager.is_tech_unlocked(nid)
			var is_available = manager.can_unlock(nid)
			
			var base_col = Color(0.35, 0.35, 0.4) # Brighter Gray-Blue for visibility
			var glow_col = Color(0.1, 0.1, 0.15, 0.1) # Very faint background glow
			
			if is_completed:
				base_col = Color(0.2, 1.0, 0.5) # Brighter Emerald
				glow_col = Color(0.1, 0.8, 0.4, 0.4)
			elif is_available:
				base_col = Color(1.0, 0.8, 0.2) # Brighter Gold
				glow_col = Color(1.0, 0.7, 0.1, 0.4)
				
			_draw_bezier_path(container, p1, p2, base_col, glow_col)

func _draw_bezier_path(container: Control, p1: Vector2, p2: Vector2, color: Color, glow: Color):
	var points = PackedVector2Array()
	var steps = 16
	
	# Cubic Bezier: p1, cp1, cp2, p2
	# For horizontal trees, control points shift horizontally
	var cp_dist = abs(p2.x - p1.x) / 1.5
	var cp1 = p1 + Vector2(cp_dist, 0)
	var cp2 = p2 - Vector2(cp_dist, 0)
	
	for i in range(steps + 1):
		var t = float(i) / steps
		var q0 = p1.lerp(cp1, t)
		var q1 = cp1.lerp(cp2, t)
		var q2 = cp2.lerp(p2, t)
		var r0 = q0.lerp(q1, t)
		var r1 = q1.lerp(q2, t)
		var pt = r0.lerp(r1, t)
		points.append(pt)
		
	# Draw Glow (Wider, softer)
	if glow.a > 0:
		container.draw_polyline(points, glow, 6.0, true)
		container.draw_polyline(points, glow * 0.5, 10.0, true)
		
	# Draw Core Line
	container.draw_polyline(points, color, 2.5, true)

func refresh_all():
	# Re-check states of all nodes
	for tab_name in graphs:
		var container = graphs[tab_name]["container"]
		if container: container.queue_redraw()
		for child in container.get_children():
			if child.has_method("update_state"):
				child.update_state()

func get_coach_anchor(key: String) -> Control:
	match key:
		"tabs":
			return tabs
		"first_node":
			var w := get_node_widget("basic_engineering")
			if w: return w
			# Fallback: any built node widget in any tab.
			for tab_name in graphs:
				var container = graphs[tab_name]["container"]
				if container:
					for child in container.get_children():
						if child is Control and child.get("nid") != null:
							return child
	return null

func get_node_widget(tech_id: String) -> Control:
	for tab_name in graphs:
		var container = graphs[tab_name]["container"]
		if not container: continue
		for child in container.get_children():
			if child.get("nid") == tech_id:
				return child
	return null

func focus_on_tech(tech_id: String):
	# 1. Find Tab
	var target_tab_name = ""
	for tab_name in graphs:
		if tech_id in graphs[tab_name]["nodes"]:
			target_tab_name = tab_name
			break
	
	if target_tab_name == "": return
	
	# 2. Switch Tab
	for i in range(tabs.get_tab_count()):
		if tabs.get_tab_control(i).name == target_tab_name:
			tabs.current_tab = i
			break
	
	# 3. Center on Node. The freshly-shown tab's ScrollContainer only finalizes
	#    its scrollable range a couple of frames after becoming visible, so a
	#    single set gets clamped to 0. Wait, set, then re-apply.
	await get_tree().process_frame
	await get_tree().process_frame

	var node_widget = get_node_widget(tech_id)
	if not node_widget:
		return
	var tab_ctrl = tabs.get_current_tab_control()
	if not tab_ctrl or tab_ctrl.get_child_count() == 0:
		return
	var scroll = tab_ctrl.get_child(0) # ScrollContainer
	if scroll is ScrollContainer:
		_center_scroll_on(scroll, node_widget)
		await get_tree().process_frame
		_center_scroll_on(scroll, node_widget)

		# Visual Highlight
		var tween = node_widget.create_tween()
		tween.tween_property(node_widget, "modulate", Color(2, 2, 2), 0.2)
		tween.tween_property(node_widget, "modulate", Color(1, 1, 1), 0.5)

func _center_scroll_on(scroll: ScrollContainer, node_widget: Control) -> void:
	var target_pos = node_widget.position + (node_widget.size * node_widget.scale / 2.0)
	scroll.scroll_horizontal = int(max(0.0, target_pos.x - scroll.size.x / 2.0))
	scroll.scroll_vertical = int(max(0.0, target_pos.y - scroll.size.y / 2.0))
