extends Control

@onready var tabs = $VBoxContainer/TabContainer


var manager: RefCounted

# Graph Data
# Each tab has a Control which acts as a Canvas for custom drawing
var node_scene = preload("res://scenes/ui/research_node_widget.tscn")

# ── Research tabs (data-driven) ─────────────────────────────────────────────
# Each entry is just a list of tech ids. Node POSITIONS are auto-computed by
# calculate_layout() from each tech's `parent`, so there are no manual
# coordinates — re-categorizing is purely editing these lists. A tech whose
# parent lives in another tab is drawn as a floating root in its own tab. Tabs
# are created (in this order) by the loop in _ready().
var graphs = {
	"Gathering": {
		"nodes": [
			"diamond_drills", "ultrasonic_drills", "plasma_bore",
			"high_flow_pumps", "superfluid_intake", "hydro_vortex",
			"laser_cutters", "mono_filament", "molecular_disassembler",
			"magnetic_funnels", "deep_core_optics",
		],
		"container": null
	},
	"Industry": {
		"nodes": [
			"basic_engineering", "materials_science",
			"combustion", "pyrolysis_control", "smelting", "blast_furnace",
			"automated_smelting", "oxygen_blast_furnace",
			# v145 FIX: refractory_metallurgy + industrial_chemistry were in tech_tree
			# but MISSING from every tab (third recurrence of the firmware_hacking bug)
			# → never rendered → unresearchable → their 8 buildings + 1 recipe were
			# permanently dead. Each is placed in its PARENT's tab so calculate_layout
			# draws the prereq line (a node whose parent is in another tab is laid out
			# as a rootless orphan — see the "not in this tab → treat as root" branch).
			"metallurgy_advanced", "superalloy_engineering", "refractory_metallurgy",
			"iridium_metallurgy", "exotic_metallurgy",
			"adv_materials", "hydraulic_press", "molecular_compression", "lightweight_alloys",
			"catalytic_electrodes", "ion_exchange", "resonance_splitters",
			"industrial_electrolysis", "industrial_chemistry", "energy_metrics",
			"cryogenic_systems", "cryogenic_storage",
			"precious_metal_refining", "industrial_catalysis", "fuel_cell_tech",
		],
		"container": null
	},
	"Automation": {
		"nodes": [
			"industrial_logistics",  # v136: automated_logistics removed (collapsed)
			"industrial_automation", "molecular_recycling", "colony_automation", "perfect_automation",
			"fast_centrifuges", "maglev_bearings", "quantum_separators", "advanced_mineralogy",
			"automation", "xeno_engineering",  # v136: nano_fabrication removed (collapsed)
			"basic_electronics", "advanced_batteries",
			"efficiency_1", "efficiency_2", "efficiency_3", "efficiency_4", "efficiency_5",
		],
		"container": null
	},
	"Ships": {
		"nodes": [
			"shipwright_1", "shipwright_2", "molecular_printing",
			"capital_ship_armament", "quantum_dynamics",
			"warp_drive",
		],
		"container": null
	},
	"Combat": {
		"nodes": [
			# v137 FIX: firmware_hacking was defined in the tech_tree (parent kinetics_101,
			# category combat) + targeted by the [CORE GOAL] "Rewrite the Firmware" mission +
			# fully wired (Hack Card combat drops, Ship Designer crafting), but was MISSING
			# from every tab list here — so it never rendered and the mission softlocked at 0%
			# (the whole Hack Card system was unreachable). Placed after its parent kinetics_101;
			# calculate_layout() auto-positions it as a sibling of power_systems.
			# v144: ordnance_101 added — it gates the Munitions Factory (T1 explosive
			# auto-foundry). Placed after its parent kinetics_101, alongside the other
			# two tier-1 ammo techs; calculate_layout() positions it as their sibling.
			"kinetics_101", "firmware_hacking", "power_systems", "ordnance_101", "laser_optics",
			"processing_tungsten", "ballistics_optimization", "advanced_rocketry",
			"energy_shields", "field_theory", "shield_harmonics", "hull_hardening", "core_overclocking",
			"auto_repair_20", "auto_repair_40", "auto_repair_60", "auto_repair_80",
			"void_weaponry_1", "void_shielding_1",
			"combat_heuristics",
		],
		"container": null
	},
	"Warp Tech": {
		"nodes": [
			"cryo_armaments", "corrosion_armaments",
		],
		"container": null
	},
	"Sectors": {
		"nodes": [
			# v145 FIX: the three fabrication techs hang off zone_6/8/9_access, so they
			# live HERE beside their parents (same rule as the v137 fixes below) — that
			# is what makes their prereq line render. They are category "infrastructure"
			# rather than "zone", so they read as the building-unlock payoff of reaching
			# that sector; moving them to Industry would orphan them from their gate.
			"zone_2_access", "zone_3_access", "zone_4_access", "zone_5_access",
			"zone_6_access", "precision_fabrication",
			"zone_7_access", "zone_8_access", "capital_fabrication",
			"zone_9_access", "dreadnought_yards", "zone_10_access",
			"sector_alpha_decryption", "deep_space_nav", "radiation_shielding",
			"exotic_matter_analysis", "void_navigation", "xeno_archaeology",
			# v137 FIX: these two were in tech_tree but MISSING from every tab (same bug as
			# firmware_hacking) → never rendered → unresearchable → their 4 processing recipes
			# + 4 buildings each were permanently dead endgame content. Placed on the Sectors
			# branch beside void_navigation.
			"neutronium_synthesis", "primordial_engineering",
		],
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

	# v130 fix: refresh node states when ANY tech unlocks. A player click already
	# refreshes via the detail modal, but EXTERNAL unlocks — e.g. the Testing-panel
	# "Unlock All Research" button — emit tech_unlocked WITHOUT a resource change,
	# so the tree rendered stale (unlocked in data, still lock-iconed on screen).
	# Mirrors combat_page / shipyard_page, which already listen to this signal.
	if manager and not manager.tech_unlocked.is_connected(_on_tech_unlocked_refresh):
		manager.tech_unlocked.connect(_on_tech_unlocked_refresh)
	
	# All research tabs are built dynamically from `graphs` (the scene's
	# TabContainer starts empty), in dictionary order. Each tab is a
	# Control → ScrollContainer → GraphArea; node positions inside are computed
	# by calculate_layout() during build_graphs().
	for tab_name in graphs:
		var tab_root := Control.new()
		tab_root.name = tab_name
		tabs.add_child(tab_root)
		tabs.set_tab_title(tab_root.get_index(), tr(tab_name))
		var tab_scroll := ScrollContainer.new()
		tab_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tab_root.add_child(tab_scroll)
		var area := Control.new()
		area.name = "GraphArea"
		area.mouse_filter = Control.MOUSE_FILTER_PASS
		tab_scroll.add_child(area)
		graphs[tab_name]["container"] = area
		_setup_panning(tab_scroll)
	
	call_deferred("build_graphs")
	call_deferred("_on_mission_updated") # Initial check
	call_deferred("_update_tab_visibility") # v113: hide all-gated tabs (e.g. Warp Tech pre-warp)

func _on_resource_changed(_a=null, _b=null):
	refresh_all()

func _on_tech_unlocked_refresh(_id = null) -> void:
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
	# SMART NAVIGATION: when an active research mission points at a tab, switch to it and
	# center the node so the player isn't left hunting the tree.
	#
	# v139h: focus the mission the objective ARROW is guiding — the earliest beat in the
	# mission chain (tutorial/chapter before side goals), NOT whichever mission activated
	# first. active_missions is APPEND order, so the old code focused whatever revealed
	# first (e.g. a Combat-tab firmware GOAL), sending a player following the Industry-tab
	# metallurgy CHAPTER beat to the wrong tab. Iterating missions in DEFINITION order
	# matches the arrow (which also skips branch-less goals): the primary chain beat wins
	# its tab; co-active side goals keep their per-tab alert dots (_update_tab_alerts).
	# (Supersedes the v139g "skip when ambiguous" guard, which stopped switching at all.)
	var mm = GameState.mission_manager
	if not mm: return

	_update_tab_alerts()

	for mid in mm.missions:                        # definition order: m0xx before goal_*
		if not mid in mm.active_missions:
			continue
		var m = mm.missions[mid]
		if m.get("completed", false) or m["type"] != "research":
			continue
		var tech_id = str(m["target"])
		for tab_name in graphs:
			if tech_id in graphs[tab_name]["nodes"]:
				focus_on_tech(tech_id)
				return

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
			# Recursion tab nodes live in repeatable_tech_db, not tech_tree.
			if nid not in manager.tech_tree and not manager.repeatable_tech_db.has(nid): continue

			var data = manager.tech_tree[nid] if nid in manager.tech_tree else manager.repeatable_tech_db[nid]
			var node_widget = node_scene.instantiate()
			container.add_child(node_widget)
			
			var pos = layout_pos.get(nid, Vector2(0,0))
			node_widget.position = pos
			node_widget.scale = Vector2(0.75, 0.75)
			node_widget.setup(nid, data, manager, self)
			node_widget.visible = not _is_node_hidden(nid)  # v113: tier-gated visibility
			
			# Approx size of scaled node (w=180, h=80 roughly)
			max_pos.x = max(max_pos.x, pos.x + 200.0)
			max_pos.y = max(max_pos.y, pos.y + 140.0)
			
		# Update container size for scrolling
		container.custom_minimum_size = max_pos + Vector2(50, 50) # Padding
			
		if not container.is_connected("draw", _on_graph_draw.bind(container, tab_name, layout_pos)):
			container.draw.connect(_on_graph_draw.bind(container, tab_name, layout_pos))
			
		container.queue_redraw()

# --- Dynamic Tree Layout Algorithm ---
# v113 (NG+): a tech with requires_flag stays HIDDEN (not rendered) until that
# game_settings flag is set — e.g. Corrosion Armaments appears only once Z12 is
# unlocked, so the Warp Tech tab isn't cluttered with next-tier tech at Z11.
func _is_node_hidden(nid: String) -> bool:
	if not nid in manager.tech_tree: return false
	if manager.is_tech_unlocked(nid): return false
	var rf := str(manager.tech_tree[nid].get("requires_flag", ""))
	return rf != "" and not GameState.game_settings.get(rf, false)

func calculate_layout(nodes_list: Array) -> Dictionary:
	var final_pos = {}
	var local_tree = {} # { parent_id: [child_id, ...] }
	var roots = []
	
	# 1. Build Local Tree
	var nodes_set = {}
	for n in nodes_list: nodes_set[n] = true
	
	for nid in nodes_list:
		if nid not in manager.tech_tree and not manager.repeatable_tech_db.has(nid): continue
		# Repeatables have no parent → laid out as roots in their tab.
		var p_id = manager.tech_tree[nid].get("parent") if nid in manager.tech_tree else null
		
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
		if nid not in manager.tech_tree and not manager.repeatable_tech_db.has(nid): continue
		var node_data = manager.tech_tree[nid] if nid in manager.tech_tree else manager.repeatable_tech_db[nid]
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

# v113 (NG+): hide a whole tab when every node in it is tier-gated-hidden — so
# the Warp Tech tab doesn't show (empty) until the first warp reveals Cryogenic
# Armaments, and so it reappears the moment cryo_unlocked / z12_unlocked flips.
func _update_tab_visibility() -> void:
	for i in range(tabs.get_tab_count()):
		var ctrl = tabs.get_tab_control(i)
		if ctrl == null or not (ctrl.name in graphs): continue
		var all_hidden := true
		for nid in graphs[ctrl.name]["nodes"]:
			if not _is_node_hidden(nid):
				all_hidden = false
				break
		tabs.set_tab_hidden(i, all_hidden)

func refresh_all():
	# Re-check states of all nodes
	for tab_name in graphs:
		var container = graphs[tab_name]["container"]
		if container: container.queue_redraw()
		for child in container.get_children():
			if child.has_method("update_state"):
				child.update_state()
			# v113: tier-gated nodes show/hide as their flag flips (Cryogenic
			# Armaments on first warp, Corrosion on Z12 unlock).
			var _cnid = child.get("nid")
			if _cnid != null:
				child.visible = not _is_node_hidden(str(_cnid))
	_update_tab_visibility()

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
