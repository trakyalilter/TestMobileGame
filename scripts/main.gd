extends Control

@onready var page_container = $HBoxContainer/Content/PageContainer
# Sidebar Buttons
@onready var gathering_btn = $HBoxContainer/Sidebar/VBoxContainer/GatheringBtn
@onready var processing_btn = $HBoxContainer/Sidebar/VBoxContainer/ProcessingBtn
@onready var infrastructure_btn = $HBoxContainer/Sidebar/VBoxContainer/InfrastructureBtn
@onready var shipyard_btn = $HBoxContainer/Sidebar/VBoxContainer/ShipyardBtn
@onready var research_btn = $HBoxContainer/Sidebar/VBoxContainer/ResearchBtn
@onready var combat_btn = $HBoxContainer/Sidebar/VBoxContainer/CombatBtn
@onready var mission_btn = $HBoxContainer/Sidebar/VBoxContainer/MissionBtn
@onready var designer_btn = $HBoxContainer/Sidebar/VBoxContainer/DesignerBtn
@onready var inventory_btn = $HBoxContainer/Sidebar/VBoxContainer/InventoryBtn
@onready var atlas_btn = $HBoxContainer/Sidebar/VBoxContainer/AtlasBtn
@onready var options_btn = $HBoxContainer/Sidebar/VBoxContainer/OptionsBtn
@onready var fleet_btn = $HBoxContainer/Sidebar/VBoxContainer/FleetBtn
@onready var warp_btn = $HBoxContainer/Sidebar/VBoxContainer/WarpBtn
@onready var sidebar_list = $HBoxContainer/Sidebar/VBoxContainer

@onready var modal_layer = $ModalLayer
var offline_modal

@onready var background = $Background

var pages = {}
var current_page_name = ""
var header_widget: Control

func _ready():
	_init_pages()
	_apply_global_styles()
	
	GameState.game_resetted.connect(_on_game_resetted)
	
	if not GameState.mission_manager.has_progress():
		switch_to("mission")
	else:
		switch_to("gathering")

func _apply_global_styles():
	background.color = UITheme.COLORS["background"]
	_update_sidebar_styling()

func _init_pages():
	# ... (same as before)
	var p_gathering = preload("res://scenes/ui/gathering_page.tscn").instantiate()
	page_container.add_child(p_gathering)
	p_gathering.visible = false
	pages["gathering"] = p_gathering
	
	var p_processing = preload("res://scenes/ui/processing_page.tscn").instantiate()
	page_container.add_child(p_processing)
	p_processing.visible = false
	pages["processing"] = p_processing
	
	var p_infrastructure = preload("res://scenes/ui/infrastructure_page.tscn").instantiate()
	page_container.add_child(p_infrastructure)
	p_infrastructure.visible = false
	pages["infrastructure"] = p_infrastructure
	
	var p_shipyard = preload("res://scenes/ui/shipyard_page.tscn").instantiate()
	page_container.add_child(p_shipyard)
	p_shipyard.visible = false
	pages["shipyard"] = p_shipyard
	
	var p_research = preload("res://scenes/ui/research_page.tscn").instantiate()
	page_container.add_child(p_research)
	p_research.visible = false
	pages["research"] = p_research
	
	var p_combat = preload("res://scenes/ui/combat_page.tscn").instantiate()
	page_container.add_child(p_combat)
	p_combat.visible = false
	pages["combat"] = p_combat
	
	var p_mission = preload("res://scenes/ui/mission_page.tscn").instantiate()
	page_container.add_child(p_mission)
	p_mission.visible = false
	pages["mission"] = p_mission
	
	var p_designer = preload("res://scenes/ui/designer_page.tscn").instantiate()
	page_container.add_child(p_designer)
	p_designer.visible = false
	pages["designer"] = p_designer
	
	var p_inventory = preload("res://scenes/ui/inventory_page.tscn").instantiate()
	page_container.add_child(p_inventory)
	p_inventory.visible = false
	pages["inventory"] = p_inventory
	
	var p_options = preload("res://scenes/ui/options_page.tscn").instantiate()
	page_container.add_child(p_options)
	p_options.visible = false
	pages["options"] = p_options

	var p_atlas = preload("res://scenes/ui/atlas_page.tscn").instantiate()
	page_container.add_child(p_atlas)
	p_atlas.visible = false
	pages["atlas"] = p_atlas
	
	# v1.0 Feature: Renamed to generic "Atlas" for Enemies + Materials
	atlas_btn.text = "Atlas"

	var p_fleet = preload("res://scenes/ui/fleet_page.tscn").instantiate()
	page_container.add_child(p_fleet)
	p_fleet.visible = false
	pages["fleet"] = p_fleet
	
	var p_warp = preload("res://scenes/ui/warp_page.tscn").instantiate()
	page_container.add_child(p_warp)
	p_warp.visible = false
	pages["warp"] = p_warp

	if modal_layer:
		offline_modal = preload("res://scenes/ui/offline_boot_modal.tscn").instantiate()
		modal_layer.add_child(offline_modal)
		offline_modal.visible = false
		offline_modal.check_and_show()
		
	# 3. Create & Inject Global HUD
	header_widget = preload("res://scenes/ui/global_header.tscn").instantiate()
	$HBoxContainer/Content.add_child(header_widget)
	$HBoxContainer/Content.move_child(header_widget, 0) # Top of VBox

func switch_to(page_name):
	if current_page_name == page_name: return
	
	for p_name in pages:
		pages[p_name].visible = (p_name == page_name)
		
	if page_name in pages:
		# Guard: Don't switch to pages that are currently hidden (gated)
		var btn = _get_btn_for_page(page_name)
		if btn and not btn.visible:
			return

		current_page_name = page_name
		_update_sidebar_styling()
		
		# INTERACTION: Tactile feedback on switch
		UITheme.trigger_ui_thud(sidebar_list, 2.0)
		
		# SMART NAVIGATION: Notify page it's been opened
		if pages[page_name].has_method("on_page_enter"):
			pages[page_name].on_page_enter()

func _get_btn_for_page(page_name: String) -> Button:
	match page_name:
		"gathering": return gathering_btn
		"processing": return processing_btn
		"infrastructure": return infrastructure_btn
		"shipyard": return shipyard_btn
		"research": return research_btn
		"combat": return combat_btn
		"mission": return mission_btn
		"designer": return designer_btn
		"inventory": return inventory_btn
		"atlas": return atlas_btn
		"options": return options_btn
		"fleet": return fleet_btn
		"warp": return warp_btn
	return null

func _update_sidebar_styling():
	UITheme.apply_sidebar_button_style(gathering_btn, current_page_name == "gathering")
	UITheme.apply_sidebar_button_style(processing_btn, current_page_name == "processing")
	UITheme.apply_sidebar_button_style(infrastructure_btn, current_page_name == "infrastructure")
	UITheme.apply_sidebar_button_style(shipyard_btn, current_page_name == "shipyard")
	UITheme.apply_sidebar_button_style(research_btn, current_page_name == "research")
	UITheme.apply_sidebar_button_style(combat_btn, current_page_name == "combat")
	UITheme.apply_sidebar_button_style(mission_btn, current_page_name == "mission")
	UITheme.apply_sidebar_button_style(designer_btn, current_page_name == "designer")
	UITheme.apply_sidebar_button_style(inventory_btn, current_page_name == "inventory")
	UITheme.apply_sidebar_button_style(atlas_btn, current_page_name == "atlas")
	UITheme.apply_sidebar_button_style(options_btn, current_page_name == "options")
	UITheme.apply_sidebar_button_style(fleet_btn, current_page_name == "fleet")
	
	# THEMATIC: Progressive Disclosure (Early & Mid-Game Gates)
	var has_basic_eng = GameState.research_manager.is_tech_unlocked("applied_physics")
	var has_shipwright = GameState.research_manager.is_tech_unlocked("shipwright_1")
	
	# 1. Ship management & Combat become available at Applied Physics
	shipyard_btn.visible = has_basic_eng
	designer_btn.visible = has_basic_eng
	combat_btn.visible = has_basic_eng
	$HBoxContainer/Sidebar/VBoxContainer/EngHeader.visible = true # Engineering is core
	
	# 2. Mid Game: Fleet Command unlocks at Shipwright 1
	fleet_btn.visible = has_shipwright
	
	# 3. Late Game: Warp Core unlocks at Warp Drive Theory
	var has_warp = GameState.research_manager.is_tech_unlocked("warp_drive")
	warp_btn.visible = has_warp
	
	# Tactical Category Header gating
	$HBoxContainer/Sidebar/VBoxContainer/CombatHeader.visible = has_basic_eng or has_warp
	
	# Command Cluster Header: Always visible (Missions are day 1)
	$HBoxContainer/Sidebar/VBoxContainer/CmdHeader.visible = true
	
	# Apply Physical Switch Styling
	for child in sidebar_list.get_children():
		if child is Button:
			UITheme.apply_instrument_style(child)
		elif child is Label:
			child.add_theme_font_size_override("font_size", 10)
			child.modulate = Color(0.4, 0.4, 0.6, 0.5) # Dim, terminal navy

func _process(delta):
	# 1. Navigation Logic & Disclosure Check (Once per second is enough)
	if Engine.get_frames_drawn() % 60 == 0:
		_update_sidebar_styling()
		
	# 2. Tutorial Navigation Guidance
	_update_navigation_hints()

func _update_navigation_hints():
	var mm = GameState.mission_manager
	if not mm: return
	
	var target_to_pulse: Control = null
	
	# 1. Claim Reminder (Top Priority)
	var can_claim_tutorial = false
	for mid in mm.missions:
		if mid.begins_with("m0") and mm.missions[mid]["completed"] and not mm.missions[mid]["claimed"]:
			can_claim_tutorial = true
			break
	
	if can_claim_tutorial:
		if current_page_name != "mission":
			target_to_pulse = mission_btn
	
	# 2. Contextual Guidance based on Active Mission
	elif "m001" in mm.active_missions:
		# Gather Dirt
		if current_page_name != "gathering": target_to_pulse = gathering_btn
		else:
			var widget = pages["gathering"].get_widget_by_aid("gather_dirt")
			if widget and not (GameState.gathering_manager.is_active and GameState.gathering_manager.current_action_id == "gather_dirt"):
				target_to_pulse = widget.btn
				
	elif "m002" in mm.active_missions:
		# Research Basic Engineering
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("basic_engineering")
			if widget: target_to_pulse = widget
			
	elif "m003" in mm.active_missions:
		# Research Fluid Dynamics
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("fluid_dynamics")
			if widget: target_to_pulse = widget
			
	elif "m004" in mm.active_missions:
		# Gather Water
		if current_page_name != "gathering": target_to_pulse = gathering_btn
		else:
			var widget = pages["gathering"].get_widget_by_aid("collect_water")
			if widget and not (GameState.gathering_manager.is_active and GameState.gathering_manager.current_action_id == "collect_water"):
				target_to_pulse = widget.btn
				
	elif "m005" in mm.active_missions:
		# Processing: Si, Fe (Mineral Washing)
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("centrifuge_dirt")
			var widget = page.get_widget_by_aid("centrifuge_dirt")
			if widget and not (pm.is_active and pm.current_recipe_id == "centrifuge_dirt"):
				target_to_pulse = widget.btn
				
			if widget: target_to_pulse = widget
			
	elif "m007" in mm.active_missions:
		# Shipyard: Ion Thrusters
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			var page = pages["shipyard"]
			page.focus_module_tab("basic_thruster")
			target_to_pulse = page.get_module_widget("basic_thruster")
		
	elif "m008" in mm.active_missions:
		# Research: Materials Science Hub
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("materials_science")
			if widget: target_to_pulse = widget

	elif "m009" in mm.active_missions:
		# Gather Wood
		if current_page_name != "gathering": target_to_pulse = gathering_btn
		else:
			var widget = pages["gathering"].get_widget_by_aid("gather_wood")
			if widget and not (GameState.gathering_manager.is_active and GameState.gathering_manager.current_action_id == "gather_wood"):
				target_to_pulse = widget.btn

	elif "m010" in mm.active_missions:
		# Research: Combustion
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("combustion")
			if widget: target_to_pulse = widget
			
	elif "m011" in mm.active_missions:
		# Processing: Carbon (Kiln)
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("charcoal_burning") # Updated to exact recipe ID
			var widget = page.get_widget_by_aid("charcoal_burning")
			if widget and not (pm.is_active and pm.current_recipe_id == "charcoal_burning"):
				target_to_pulse = widget.btn
				
	elif "m012" in mm.active_missions:
		# Gather Spodumene
		if current_page_name != "gathering": target_to_pulse = gathering_btn
		else:
			var widget = pages["gathering"].get_widget_by_aid("extract_salts")
			if widget and not (GameState.gathering_manager.is_active and GameState.gathering_manager.current_action_id == "extract_salts"):
				target_to_pulse = widget.btn
				
	elif "m013" in mm.active_missions:
		# Processing: Refine Lithium
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("refine_lithium")
			var widget = page.get_widget_by_aid("refine_lithium")
			if widget and not (pm.is_active and pm.current_recipe_id == "refine_lithium"):
				target_to_pulse = widget.btn

	elif "m014" in mm.active_missions:
		# Research: Kinetics 101
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("kinetics_101")
			if widget: target_to_pulse = widget
				
	elif "m015" in mm.active_missions:
		# Shipyard: Mass Driver
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			var page = pages["shipyard"]
			page.focus_module_tab("railgun_mk1")
			target_to_pulse = page.get_module_widget("railgun_mk1")
		
	elif "m016" in mm.active_missions:
		# Processing: Ferrite Rounds
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("craft_slug_t1")
			var widget = page.get_widget_by_aid("craft_slug_t1")
			if widget and not (pm.is_active and pm.current_recipe_id == "craft_slug_t1"):
				target_to_pulse = widget.btn
				
	elif "m017" in mm.active_missions:
		# Combat: Lunar Orbit Target
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("lunar_orbit")
			target_to_pulse = page.get_enemy_card("lunar_drone")

	elif "m018" in mm.active_missions:
		# Research: Industrial Logistics Hub
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("industrial_logistics")
			if widget: target_to_pulse = widget

	elif "m018b" in mm.active_missions:
		# Research: Automated Logistics Hub
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("automated_logistics")
			if widget: target_to_pulse = widget
			
	elif "m019" in mm.active_missions:
		# Processing: Circuits
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("craft_circuit")
			var widget = page.get_widget_by_aid("craft_circuit")
			if widget and not (pm.is_active and pm.current_recipe_id == "craft_circuit"):
				target_to_pulse = widget.btn

	elif "m020" in mm.active_missions:
		# Research: Power Systems
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("power_systems")
			if widget: target_to_pulse = widget
				
	elif "m021" in mm.active_missions:
		# Processing: Batteries
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("craft_battery_t1")
			var widget = page.get_widget_by_aid("craft_battery_t1")
			if widget and not (pm.is_active and pm.current_recipe_id == "craft_battery_t1"):
				target_to_pulse = widget.btn
				
	elif "m022" in mm.active_missions:
		# Shipyard: Battery Module
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			var page = pages["shipyard"]
			page.focus_module_tab("battery_t1")
			target_to_pulse = page.get_module_widget("battery_t1")

	elif "m023" in mm.active_missions:
		# Research: Energy Shields
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("energy_shields")
			if widget: target_to_pulse = widget
			
	elif "m024" in mm.active_missions:
		# Shipyard: Deflector Shield
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			var page = pages["shipyard"]
			page.focus_module_tab("basic_shield")
			target_to_pulse = page.get_module_widget("basic_shield")

	elif "m025" in mm.active_missions:
		# Research: Smelting
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("smelting")
			if widget: target_to_pulse = widget

	elif "m026" in mm.active_missions:
		# Research: Shipwright I
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("shipwright_1")
			if widget: target_to_pulse = widget

	elif "m027" in mm.active_missions:
		# Research: Sector Alpha Case
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("sector_alpha_decryption")
			if widget: target_to_pulse = widget

	elif "m028" in mm.active_missions:
		# Gathering: Sector Alpha (Cassiterite)
		if current_page_name != "gathering": target_to_pulse = gathering_btn
		else:
			var widget = pages["gathering"].get_widget_by_aid("mine_cassiterite")
			if widget and not (GameState.gathering_manager.is_active and GameState.gathering_manager.current_action_id == "mine_cassiterite"):
				target_to_pulse = widget.btn

	elif "m029" in mm.active_missions:
		# Shipyard: Titanium Plating
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			var page = pages["shipyard"]
			page.focus_module_tab("titanium_armor")
			target_to_pulse = page.get_module_widget("titanium_armor")

			target_to_pulse = page.get_module_widget("titanium_armor")

	elif "m030" in mm.active_missions:
		# Research: Shipwright II (Audit v15.0)
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("shipwright_2")
			if widget: target_to_pulse = widget
			
	elif "m030b" in mm.active_missions:
		# Infrastructure: Fabricator (Audit v15.0)
		if current_page_name != "infrastructure": target_to_pulse = infrastructure_btn
		else:
			var widget = pages["infrastructure"].get_building_widget("fabricator")
			if widget: target_to_pulse = widget.btn
			
	elif "m030c" in mm.active_missions:
		# Shipyard: Escort Destroyer
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			target_to_pulse = pages["shipyard"].get_hull_widget("destroyer_hull")

	elif "m032b" in mm.active_missions:
		# Research: Deep Space Nav (Sector Beta)
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("deep_space_nav")
			if widget: target_to_pulse = widget
			
	elif "m032c" in mm.active_missions:
		# Shipyard: Battlecruiser
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			target_to_pulse = pages["shipyard"].get_hull_widget("battlecruiser_hull")
			
	elif "m033b" in mm.active_missions:
		# Research: Radiation Shielding (Sector Gamma)
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("radiation_shielding")
			if widget: target_to_pulse = widget
			
	elif "m033c" in mm.active_missions:
		# Shipyard: Dreadnought
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			target_to_pulse = pages["shipyard"].get_hull_widget("dreadnought_hull")

	elif "m031" in mm.active_missions:
		# Research: Warp Drive
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("warp_drive")
			if widget: target_to_pulse = widget

	# Apply final decision
	if target_to_pulse:
		start_hint_pulse(target_to_pulse)
	else:
		stop_hint_pulse()


var hint_tween: Tween
var pulsing_button: Control = null

func start_hint_pulse(control: Control):
	if pulsing_button == control: return
	
	stop_hint_pulse()
	pulsing_button = control
	
	# Set pivot to center for scale pulse
	control.pivot_offset = control.size / 2
	
	hint_tween = create_tween().set_loops()
	# Vivid Golden Glow + Scale Pulse
	var pulse_color = Color(1.2, 0.9, 0.2) # Over-bright for HDR/Glow feel
	hint_tween.parallel().tween_property(control, "modulate", pulse_color, 0.4).set_trans(Tween.TRANS_SINE)
	hint_tween.parallel().tween_property(control, "scale", Vector2(1.05, 1.05), 0.4).set_trans(Tween.TRANS_SINE)
	
	hint_tween.parallel().tween_property(control, "modulate", Color.WHITE, 0.4).set_trans(Tween.TRANS_SINE).set_delay(0.4)
	hint_tween.parallel().tween_property(control, "scale", Vector2(1.0, 1.0), 0.4).set_trans(Tween.TRANS_SINE).set_delay(0.4)

func stop_hint_pulse():
	if hint_tween:
		hint_tween.kill()
		hint_tween = null
	
	if pulsing_button:
		pulsing_button.modulate = Color.WHITE
		pulsing_button.scale = Vector2(1.0, 1.0)
		pulsing_button = null

func _on_gathering_btn_pressed(): switch_to("gathering")
func _on_processing_btn_pressed(): switch_to("processing")
func _on_infrastructure_btn_pressed(): switch_to("infrastructure")
func _on_shipyard_btn_pressed(): switch_to("shipyard")
func _on_research_btn_pressed(): switch_to("research")
func _on_combat_btn_pressed(): switch_to("combat")
func _on_mission_btn_pressed(): switch_to("mission")
func _on_designer_btn_pressed(): switch_to("designer")
func _on_inventory_btn_pressed(): switch_to("inventory")
func _on_atlas_btn_pressed():
	switch_to("atlas")

func _on_warp_btn_pressed():
	switch_to("warp")
func _on_options_btn_pressed(): switch_to("options")
func _on_fleet_btn_pressed(): switch_to("fleet")

func _on_game_resetted():
	switch_to("mission")
