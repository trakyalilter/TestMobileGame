extends Control

@onready var tabs = $VBoxContainer/TabContainer
@onready var credits_lbl = $VBoxContainer/Header/CreditsLabel

var manager: RefCounted

# Graph Data
# Each tab has a Control which acts as a Canvas for custom drawing
var node_scene = preload("res://scenes/ui/research_node_widget.tscn")

var graphs = {
	"Operations": {
		"nodes": [
			"energy_shields", "industrial_logistics",
			"diamond_drills", "ultrasonic_drills", "plasma_bore",
			"high_flow_pumps", "superfluid_intake", "hydro_vortex",
			"laser_cutters", "mono_filament", "molecular_disassembler",
			"magnetic_funnels", "deep_core_optics"
		],
		"pos": {
			"high_flow_pumps": Vector2(40, 40),
			"superfluid_intake": Vector2(240, 40),
			"hydro_vortex": Vector2(440, 40),
			
			"laser_cutters": Vector2(40, 150),
			"mono_filament": Vector2(240, 150),
			"molecular_disassembler": Vector2(440, 150),
			
			"energy_shields": Vector2(40, 260),
			"magnetic_funnels": Vector2(240, 260),
			
			"diamond_drills": Vector2(40, 370),
			"ultrasonic_drills": Vector2(240, 370),
			"plasma_bore": Vector2(440, 370)
		},
		"container": null # Assigned in _ready
	},
	"Engineering": {
		"nodes": [
			"basic_engineering", "applied_physics", "materials_science", "industrial_logistics",
			"fluid_dynamics", "combustion", "smelting", "adv_materials",
			"fast_centrifuges", "maglev_bearings", "quantum_separators",
			"catalytic_electrodes", "ion_exchange", "resonance_splitters",
			"pyrolysis_control", "blast_furnace", "hydraulic_press",
			"automated_logistics", "processing_tungsten", "ballistics_optimization", "energy_metrics",
			"automated_smelting", "industrial_electrolysis", "molecular_compression", "mass_production_tactics",
			"kinetics_101", "laser_optics", "power_systems", "bronze_smithing", "lightweight_alloys",
			"salvage_heuristics", "scavenger_protocol", "combat_heuristics", "shield_harmonics", "hull_hardening", 
			"core_overclocking", "nano_fabrication", "data_clustering"
		],
		"pos": {
			"basic_engineering": Vector2(40, 350),
			
			# Upper Branch: Fluid Dynamics
			"fluid_dynamics": Vector2(240, 100),
			"catalytic_electrodes": Vector2(440, 40),
			"ion_exchange": Vector2(640, 40),
			"resonance_splitters": Vector2(840, 40),
			"energy_metrics": Vector2(440, 140),
			"industrial_electrolysis": Vector2(640, 140),
			
			# Mid-Upper: Combustion
			"combustion": Vector2(240, 250),
			"pyrolysis_control": Vector2(440, 250),
			
			# Mid: Alloy Synthesis (Major Hub)
			"smelting": Vector2(440, 350),
			"blast_furnace": Vector2(640, 350),
			"automated_smelting": Vector2(840, 350),
			"processing_tungsten": Vector2(640, 430),
			"ballistics_optimization": Vector2(840, 430),
			
			# Mid-Lower: Advanced Materials (Child of Alloy)
			"adv_materials": Vector2(640, 520),
			"hydraulic_press": Vector2(840, 520),
			"molecular_compression": Vector2(1040, 520),
			
			# Lower: Centrifuges
			"fast_centrifuges": Vector2(240, 620), # Moved down significantly
			"maglev_bearings": Vector2(440, 620), 
			"quantum_separators": Vector2(640, 620),
			
			# Bottom: Logistics
			"automated_logistics": Vector2(240, 720),
			"mass_production_tactics": Vector2(440, 720),
			
			# New Early Game Gates
			"kinetics_101": Vector2(40, 460),
			"power_systems": Vector2(40, 540),
			"lightweight_alloys": Vector2(40, 620),
			"laser_optics": Vector2(440, 180),
			"bronze_smithing": Vector2(640, 260)
		},
		"container": null
	},
	"Ships": {
		"nodes": [
			"smelting",
			"shipwright_1", "shipwright_2", "sector_alpha_decryption", "warp_drive",
			"molecular_printing", "capital_ship_engineering", "quantum_dynamics"
		],
		"pos": {
			"smelting": Vector2(40, 150),
			"shipwright_1": Vector2(240, 150),
			"shipwright_2": Vector2(440, 150),
			"sector_alpha_decryption": Vector2(440, 40),
			"warp_drive": Vector2(640, 150),
			"molecular_printing": Vector2(640, 260),
			"capital_ship_engineering": Vector2(640, 40),
			"quantum_dynamics": Vector2(840, 40)
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
	
	call_deferred("build_graphs")
	call_deferred("_on_mission_updated") # Initial check

func _on_resource_changed(_a=null, _b=null):
	refresh_all()

func _on_mission_updated():
	_update_tab_alerts()

func on_page_enter():
	# SMART NAVIGATION: Auto-focus tab based on active mission
	var mm = GameState.mission_manager
	if not mm: return
	
	for mid in mm.active_missions:
		var m = mm.missions[mid]
		if m["type"] == "research":
			var tech_id = m["target"]
			
			# Find which tab holds this tech
			for tab_name in graphs:
				if tech_id in graphs[tab_name]["nodes"]:
					# Switch to this tab immediately
					for i in range(tabs.get_tab_count()):
						# Audit v16.2: Use Node Name (immutable) instead of Title
						if tabs.get_tab_control(i).name == tab_name:
							tabs.current_tab = i
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
			var p1 = positions[parent] + Vector2(105, 22.5) # Right-Center (140*0.75, 30*0.75)
			var p2 = positions[nid] + Vector2(0, 22.5) # Left-Center
			
			container.draw_line(p1, p2, Color(0.5, 0.5, 0.5), 2.0)

func refresh_all():
	# Re-check states of all nodes
	for tab_name in graphs:
		var container = graphs[tab_name]["container"]
		for child in container.get_children():
			if child.has_method("update_state"):
				child.update_state()
	update_ui()

func get_node_widget(tech_id: String) -> Control:
	for tab_name in graphs:
		var container = graphs[tab_name]["container"]
		if not container: continue
		for child in container.get_children():
			if child.get("nid") == tech_id:
				return child
	return null

func _process(delta):
	# Poll for currency upates
	update_ui()

func update_ui():
	# Update text
	if not manager: return
	# Credits now handled by GlobalHeader
	pass
