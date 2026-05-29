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
@onready var menu_btn = $HBoxContainer/Sidebar/VBoxContainer/MenuBtn
@onready var bounty_btn = $HBoxContainer/Sidebar/VBoxContainer/BountyBtn
@onready var quest_btn = $HBoxContainer/Sidebar/VBoxContainer/QuestBtn
@onready var warp_btn = $HBoxContainer/Sidebar/VBoxContainer/WarpBtn
@onready var sidebar_list = $HBoxContainer/Sidebar/VBoxContainer
@onready var sidebar_panel = $HBoxContainer/Sidebar

@onready var modal_layer = $ModalLayer
var offline_modal

@onready var background = $Background

var pages = {}
var current_page_name = ""
var header_widget: Control

# First-visit coach-mark overlay (shown once per page)
var coach_overlay = null

# Claim badges — shown on Mission / Quest sidebar buttons when rewards are ready
var mission_claim_badge: Control = null
var quest_claim_badge: Control = null
var _claim_badge_tick: float = 0.0

func _ready():
	_init_pages()
	_apply_global_styles()
	_init_notifications() # Feature 66.1
	_init_claim_badges()
	_init_coach_overlay()

	# v71.1: Connect to shipyard alerts
	GameState.shipyard_manager.alert_changed.connect(_on_shipyard_alert_changed)

	GameState.game_resetted.connect(_on_game_resetted)
	
	if not GameState.mission_manager.has_progress():
		switch_to("mission")
	else:
		switch_to("gathering")
	
	# v84.2: Research Navigation QoL
	UITheme.research_navigation_requested.connect(_on_research_navigation_requested)

	# v107: P0 Prestige Discovery Fanfare — detect the moment the player
	# crosses the warp shard threshold for the first time. We listen on
	# every currency_added because credits feed the progress_score formula.
	GameState.resources.currency_added.connect(_on_currency_added_for_warp_reveal)

	# v109: Recursion discovery — the Recursion research tab is always visible
	# but easily missed, and is unusable until the player has Void Artifacts
	# (the shared gate item for every lane). Fire a one-shot pointer the first
	# time one is acquired.
	GameState.resources.element_added.connect(_on_element_added_for_recursion_reveal)

func _on_element_added_for_recursion_reveal(symbol: String, _amount: float) -> void:
	if symbol != "VoidArtifact":
		return
	if GameState.game_settings.get("recursion_revealed", false):
		return
	GameState.game_settings["recursion_revealed"] = true
	UITheme.show_notification(
		"⟨ RECURSION PROTOCOLS ONLINE ⟩  Spend Void Artifacts on the Research page's RECURSION tab for infinite, permanent global bonuses.",
		Color(0.55, 0.85, 1.0)
	)

func _on_currency_added_for_warp_reveal(currency_type: String, _amount: float) -> void:
	# Cheap fast-paths first — this fires on every credit gain.
	if currency_type != "credits":
		return
	if GameState.game_settings.get("warp_first_revealed", false):
		return
	if GameState.warp_manager.calculate_warp_gains() <= 0:
		return
	# First-time crossing of the prestige threshold — flip the flag,
	# reveal the Warp tab, and fire the fanfare.
	GameState.game_settings["warp_first_revealed"] = true
	_update_sidebar_styling()  # makes the Warp tab appear immediately
	_fire_warp_reveal_fanfare()

func _fire_warp_reveal_fanfare() -> void:
	# Tell the player something happened AND what to do — the pulsing tab
	# alone doesn't read as an instruction. One self-contained notification
	# beats two-stage messaging.
	UITheme.show_notification(
		"⟨ WARP CORE RESONANCE DETECTED ⟩  A new prestige system is online — open the WARP tab to spend Exotic Matter Shards.",
		Color(0.85, 0.5, 1.0)
	)
	if is_instance_valid(warp_btn):
		var tween := create_tween().set_loops(4)
		tween.tween_property(warp_btn, "modulate", Color(1.5, 1.0, 1.7), 0.5)
		tween.tween_property(warp_btn, "modulate", Color.WHITE, 0.5)

func _on_research_navigation_requested(tech_id: String):
	switch_to("research")
	var res_page = pages.get("research")
	if res_page and res_page.has_method("focus_on_tech"):
		res_page.focus_on_tech(tech_id)

func _apply_global_styles():
	background.color = UITheme.COLORS["background"]
	_style_sidebar_panel()
	_update_sidebar_styling()

func _style_sidebar_panel():
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.048, 0.052, 0.085, 1.0)
	style.set_border_width_all(0)
	style.border_width_right = 1
	style.border_color = Color(0.20, 0.26, 0.42, 0.50)
	sidebar_panel.add_theme_stylebox_override("panel", style)

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
	
	atlas_btn.text = "  📖  Atlas"

	
	var p_bounty = preload("res://scenes/ui/bounty_page.tscn").instantiate()
	page_container.add_child(p_bounty)
	p_bounty.visible = false
	pages["bounty"] = p_bounty

	var p_quest = preload("res://scenes/ui/quest_page.tscn").instantiate()
	page_container.add_child(p_quest)
	p_quest.visible = false
	pages["quest"] = p_quest
	
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

# Feature 66.1: Global Notification Stack (Melvor-style)
var notification_container: VBoxContainer

func _init_notifications():
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN # Grow leftwards
	margin.add_theme_constant_override("margin_right", 50)
	margin.add_theme_constant_override("margin_top", 100) # Below top HUD
	margin.add_theme_constant_override("margin_bottom", 50)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	notification_container = VBoxContainer.new()
	notification_container.alignment = BoxContainer.ALIGNMENT_END # Stack from bottom up
	notification_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(notification_container)
	
	$ModalLayer.add_child(margin)
	UITheme.notification_requested.connect(_spawn_notification)

func _spawn_notification(text: String, color: Color):
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = UITheme.COLORS["panel_bg"]
	style.bg_color.a = 0.95
	style.set_border_width_all(1)
	style.border_color = color.lerp(Color.WHITE, 0.4)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 4
	panel.add_theme_stylebox_override("panel", style)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(margin)
	
	var msg = Label.new()
	msg.text = text
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_color_override("font_color", color)
	msg.add_theme_font_size_override("font_size", 14)
	UITheme.apply_segmented_font(msg, color)
	margin.add_child(msg)
	# Right-align the notification to form a neat column
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	notification_container.add_child(panel)
	# Max 5 notifications visibly tracking
	var active_nodes = []
	for c in notification_container.get_children():
		if not c.is_queued_for_deletion():
			active_nodes.append(c)
	while active_nodes.size() > 5:
		var oldest = active_nodes.pop_front()
		oldest.queue_free()
	
	# Tween Flow: Fade In (0.2s) -> Hold (1.5s) -> Fade Out (0.3s)
	panel.modulate.a = 0.0
	var tween = panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE)
	tween.tween_interval(1.5)
	
	# Drift right while fading out
	tween.tween_property(panel, "modulate:a", 0.0, 0.3)
	tween.tween_callback(panel.queue_free)

# ── Claim Badges (Mission / Quest sidebar buttons) ──
func _init_claim_badges():
	mission_claim_badge = _build_claim_badge(Color(1.0, 0.40, 0.20))  # orange-red — story rewards
	mission_btn.add_child(mission_claim_badge)
	quest_claim_badge = _build_claim_badge(Color(1.0, 0.78, 0.22))   # gold — quest rewards
	quest_btn.add_child(quest_claim_badge)
	_update_claim_badges()

func _build_claim_badge(bg: Color) -> Control:
	# A right-edge circular pill carrying the claim count. Hidden when count == 0.
	var panel := PanelContainer.new()
	panel.name = "ClaimBadge"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	# Anchored to the right edge of the parent button, vertically centered.
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT, true)
	panel.position = Vector2(-32, -10)
	panel.custom_minimum_size = Vector2(22, 20)

	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(10)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	style.shadow_color = Color(bg.r, bg.g, bg.b, 0.45)
	style.shadow_size = 4
	panel.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.name = "CountLabel"
	lbl.text = "0"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)

	# Soft pulse to draw the eye without being obnoxious
	var tween := panel.create_tween().set_loops()
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 0.7), 0.9).set_trans(Tween.TRANS_SINE)
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 1.0), 0.9).set_trans(Tween.TRANS_SINE)

	return panel

func _update_claim_badges():
	var mm = GameState.mission_manager
	if mission_claim_badge and mm:
		var n = mm.count_claimable_missions()
		var lbl = mission_claim_badge.get_node_or_null("CountLabel")
		if lbl:
			lbl.text = str(n) if n < 99 else "99+"
		mission_claim_badge.visible = (n > 0)

	var qm = GameState.quest_manager
	if quest_claim_badge and qm:
		var n = qm.count_claimable()
		var lbl = quest_claim_badge.get_node_or_null("CountLabel")
		if lbl:
			lbl.text = str(n) if n < 99 else "99+"
		quest_claim_badge.visible = (n > 0) and quest_btn.visible

# ── First-visit Coach Marks ──
func _init_coach_overlay():
	if not GameState.game_settings.has("coach_seen"):
		GameState.game_settings["coach_seen"] = {}
	coach_overlay = preload("res://scenes/ui/coach_overlay.tscn").instantiate()
	if modal_layer:
		modal_layer.add_child(coach_overlay)
	else:
		add_child(coach_overlay)
	coach_overlay.finished.connect(_on_coach_finished)

func _coach_active() -> bool:
	return coach_overlay != null and coach_overlay.is_active()

func _maybe_show_coach(page_name: String):
	if coach_overlay == null or _coach_active():
		return
	var seen: Dictionary = GameState.game_settings.get("coach_seen", {})
	if seen.get(page_name, false):
		return
	# Don't stack on top of the offline-summary modal on first boot; the player
	# will navigate again and the tour will trigger then.
	if offline_modal and is_instance_valid(offline_modal) and offline_modal.visible:
		return
	var steps: Array = CoachMarks.get_steps(page_name)
	if steps.is_empty():
		return
	var page_node = pages.get(page_name)
	stop_hint_pulse()  # don't fight the tour with the nav pulse
	coach_overlay.start(page_name, steps, page_node)

func _on_coach_finished(page_name: String):
	var seen: Dictionary = GameState.game_settings.get("coach_seen", {})
	seen[page_name] = true
	GameState.game_settings["coach_seen"] = seen
	GameState.save_game()

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
		# P1 Onboarding hook: bump any active visit_page missions (e.g. m016c
		# "Combat Briefing") so the orientation step auto-completes the moment
		# the player navigates to the page it points at.
		if GameState.mission_manager:
			GameState.mission_manager._update_progress("visit_page", page_name, 1)
		_update_sidebar_styling()

		# Per-page idle cursor (inert until art exists for the page)
		CursorManager.set_page_cursor(page_name)

		# SMART NAVIGATION: Notify page it's been opened
		if pages[page_name].has_method("on_page_enter"):
			pages[page_name].on_page_enter()

		# v71.1: Clear shipyard alert when entering designer
		if page_name == "designer":
			GameState.shipyard_manager.new_drops_alert = false

		# First-visit onboarding tour for this page
		_maybe_show_coach(page_name)

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

		"bounty": return bounty_btn
		"quest": return quest_btn
		"warp": return warp_btn
	return null

func _on_shipyard_alert_changed(state: bool):
	if state and current_page_name != "designer":
		start_hint_pulse(designer_btn)
	elif not state:
		if pulsing_button == designer_btn:
			stop_hint_pulse()

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

	UITheme.apply_sidebar_button_style(bounty_btn, current_page_name == "bounty")
	UITheme.apply_sidebar_button_style(quest_btn, current_page_name == "quest")
	
	# THEMATIC: Progressive Disclosure (Early & Mid-Game Gates)
	var has_basic_eng = GameState.research_manager.is_tech_unlocked("applied_physics")
	var has_shipwright = GameState.research_manager.is_tech_unlocked("shipwright_1")
	
	# 1. Ship management & Combat become available at Applied Physics
	shipyard_btn.visible = has_basic_eng
	designer_btn.visible = has_basic_eng
	combat_btn.visible = has_basic_eng

	
	# v72.0: Bounty Board unlocks at Asteroid Clearance (first real combat sector)
	var has_asteroid_clearance = GameState.research_manager.is_tech_unlocked("asteroid_clearance")
	bounty_btn.visible = has_asteroid_clearance
	# Quests appear once the player has core gameplay loops available
	quest_btn.visible = has_basic_eng
	
	# 3. Late Game: Warp Core unlocks the first time the player crosses the
	# progress-score shard threshold. v107 moved this off the warp_drive
	# research gate — research-gating muffled the "Warp Core Resonance
	# Detected" surprise because the player chose to research it. Now the
	# tab simply appears when the player earns their first earnable shard.
	# Backward compat: existing saves where the player already had warp
	# activity OR warp_drive researched silently flip the flag so the tab
	# stays visible without re-firing the reveal.
	var revealed: bool = GameState.game_settings.get("warp_first_revealed", false)
	if not revealed:
		var wm_ref = GameState.warp_manager
		if wm_ref.total_warps > 0 or wm_ref.warp_shards > 0:
			revealed = true
		elif GameState.research_manager.is_tech_unlocked("warp_drive"):
			revealed = true
		if revealed:
			GameState.game_settings["warp_first_revealed"] = true
	warp_btn.visible = revealed
	


	

	
	# Style non-button sidebar elements
	for child in sidebar_list.get_children():
		if child is Label:
			if child.name == "LogoLabel":
				child.add_theme_font_size_override("font_size", 14)
				child.add_theme_color_override("font_color", Color(0.42, 0.84, 1.00))
				child.modulate = Color.WHITE
			else:
				child.add_theme_font_size_override("font_size", 9)
				child.add_theme_color_override("font_color", Color(0.28, 0.36, 0.52))
				child.modulate = Color.WHITE

	# Warp button keeps its purple accent
	if is_instance_valid(warp_btn) and warp_btn.visible:
		var wc := Color(0.78, 0.50, 1.00) if current_page_name != "warp" else Color(0.92, 0.72, 1.00)
		warp_btn.add_theme_color_override("font_color", wc)

func _process(delta):
	# 1. Navigation Logic & Disclosure Check (Once per second is enough)
	if Engine.get_frames_drawn() % 60 == 0:
		_update_sidebar_styling()

	# 2. Tutorial Navigation Guidance
	_update_navigation_hints()

	# 3. Claim badges (refresh ~4 Hz)
	_claim_badge_tick += delta
	if _claim_badge_tick >= 0.25:
		_claim_badge_tick = 0.0
		_update_claim_badges()

func _update_navigation_hints():
	# A page tour owns the spotlight while it's open — don't double up.
	if _coach_active():
		stop_hint_pulse()
		return
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
			page.focus_module_tab("z1_engine")
			target_to_pulse = page.get_module_widget("z1_engine")

	elif "m007b" in mm.active_missions:
		# Designer: pulse the empty engine slot so the just-crafted Thruster
		# closes its arc with a visible "equip me" target. Also dim non-engine
		# modules in the Armory so the Thruster pops visually.
		if current_page_name != "designer": target_to_pulse = designer_btn
		else:
			var dp = pages["designer"]
			if dp.has_method("set_equip_focus_filter"):
				dp.set_equip_focus_filter("engine")
			if dp.has_method("get_slot_widget"):
				dp.focus_slot("engine")
				target_to_pulse = dp.get_slot_widget("engine")
			elif dp.has_method("get_coach_anchor"):
				target_to_pulse = dp.get_coach_anchor("schematic")

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
			page.focus_module_tab("z1_kinetic")
			target_to_pulse = page.get_module_widget("z1_kinetic")

	elif "m015b" in mm.active_missions:
		# Designer: pulse the empty weapon slot + dim non-weapon Armory cards.
		if current_page_name != "designer": target_to_pulse = designer_btn
		else:
			var dp = pages["designer"]
			if dp.has_method("set_equip_focus_filter"):
				dp.set_equip_focus_filter("weapon")
			if dp.has_method("get_slot_widget"):
				dp.focus_slot("weapon")
				target_to_pulse = dp.get_slot_widget("weapon")
			elif dp.has_method("get_coach_anchor"):
				target_to_pulse = dp.get_coach_anchor("schematic")

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
			target_to_pulse = page.get_enemy_card("z1_lunar_drone")

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
			page.focus_module_tab("z1_battery")
			target_to_pulse = page.get_module_widget("z1_battery")

	elif "m022b" in mm.active_missions:
		# Designer: pulse the empty battery slot + dim non-battery Armory cards.
		if current_page_name != "designer": target_to_pulse = designer_btn
		else:
			var dp = pages["designer"]
			if dp.has_method("set_equip_focus_filter"):
				dp.set_equip_focus_filter("battery")
			if dp.has_method("get_slot_widget"):
				dp.focus_slot("battery")
				target_to_pulse = dp.get_slot_widget("battery")
			elif dp.has_method("get_coach_anchor"):
				target_to_pulse = dp.get_coach_anchor("schematic")

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
			page.focus_module_tab("z1_shield")
			target_to_pulse = page.get_module_widget("z1_shield")

	elif "m024c" in mm.active_missions:
		# Designer: pulse the empty shield slot + dim non-shield Armory cards.
		if current_page_name != "designer": target_to_pulse = designer_btn
		else:
			var dp = pages["designer"]
			if dp.has_method("set_equip_focus_filter"):
				dp.set_equip_focus_filter("shield")
			if dp.has_method("get_slot_widget"):
				dp.focus_slot("shield")
				target_to_pulse = dp.get_slot_widget("shield")
			elif dp.has_method("get_coach_anchor"):
				target_to_pulse = dp.get_coach_anchor("schematic")

	elif "m016c" in mm.active_missions:
		# Combat orientation — pulse the Combat tab until the player visits;
		# the visit_page hook in switch_to() auto-completes the mission.
		if current_page_name != "combat":
			target_to_pulse = combat_btn

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
		# Research: Asteroid Belt Authorization (zone_2_access)
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("zone_2_access")
			if widget: target_to_pulse = widget

	elif "m028" in mm.active_missions:
		# Gathering: Sector Alpha (Cassiterite)
		if current_page_name != "gathering": target_to_pulse = gathering_btn
		else:
			var widget = pages["gathering"].get_widget_by_aid("mine_cassiterite")
			if widget and not (GameState.gathering_manager.is_active and GameState.gathering_manager.current_action_id == "mine_cassiterite"):
				target_to_pulse = widget.btn

	elif "m029" in mm.active_missions:
		# Shipyard: Zone 2 Armor (Carbon Fiber Plate)
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			var page = pages["shipyard"]
			page.focus_module_tab("z2_armor")
			target_to_pulse = page.get_module_widget("z2_armor")

			target_to_pulse = page.get_module_widget("z2_armor")

	elif "m030" in mm.active_missions:
		# Research: Shipwright II (Audit v15.0)
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("shipwright_2")
			if widget: target_to_pulse = widget
			
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
		# Research: Sector Alpha Decryption
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("sector_alpha_decryption")
			if widget: target_to_pulse = widget
			
	elif "m032" in mm.active_missions:
		# Combat: Alpha Sector Dominance (Alien Frigate)
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("sector_alpha")
			target_to_pulse = page.get_enemy_card("z5_alien_frigate")

	elif "m033" in mm.active_missions:
		# Combat: Beta Sector Expansion (Ore Guardian)
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("sector_beta")
			target_to_pulse = page.get_enemy_card("z6_ore_guardian")

	elif "m034" in mm.active_missions:
		# Combat: Gamma Sector Control (Gamma Colossus)
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("sector_gamma")
			target_to_pulse = page.get_enemy_card("z6_boss_colossus")

	# ── Previously-undirected tutorial steps ──
	elif "m002b" in mm.active_missions:
		# Research: Applied Physics
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("applied_physics")
			if widget: target_to_pulse = widget

	elif "m013b" in mm.active_missions:
		# Gathering: Malachite Ore
		if current_page_name != "gathering": target_to_pulse = gathering_btn
		else:
			var widget = pages["gathering"].get_widget_by_aid("mine_malachite")
			if widget and not (GameState.gathering_manager.is_active and GameState.gathering_manager.current_action_id == "mine_malachite"):
				target_to_pulse = widget.btn

	elif "m013c" in mm.active_missions:
		# Processing: Refine Copper
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("smelt_copper")
			var widget = page.get_widget_by_aid("smelt_copper")
			if widget and not (pm.is_active and pm.current_recipe_id == "smelt_copper"):
				target_to_pulse = widget.btn

	elif "m016b" in mm.active_missions:
		# Designer: pulse the exact empty slot to fill next (weapon, then shield)
		if current_page_name != "designer": target_to_pulse = designer_btn
		else:
			var sm = GameState.shipyard_manager
			var has_w := false
			var has_s := false
			for mid_v in sm.loadout.values():
				if mid_v and mid_v in sm.modules:
					var st: String = sm.modules[mid_v].get("slot_type", "")
					if st == "weapon": has_w = true
					elif st == "shield": has_s = true
			var dp = pages["designer"]
			var want := "weapon" if not has_w else ("shield" if not has_s else "")
			if want != "" and dp.has_method("get_slot_widget"):
				dp.focus_slot(want)
				target_to_pulse = dp.get_slot_widget(want)
			elif dp.has_method("get_coach_anchor"):
				target_to_pulse = dp.get_coach_anchor("schematic")

	elif "m024b" in mm.active_missions:
		# Processing: craft repair kits (hull patches first, then shield boosters)
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			var need_hull = GameState.resources.get_element_amount("EmergencyPatch") < 5
			var rid = "craft_emergency_patch" if need_hull else "craft_basic_booster"
			page.focus_tab(rid)
			var widget = page.get_widget_by_aid(rid)
			if widget and not (pm.is_active and pm.current_recipe_id == rid):
				target_to_pulse = widget.btn

	elif "m024b2" in mm.active_missions:
		# Designer: pulse the exact empty consumable slot (hull, then shield)
		if current_page_name != "designer": target_to_pulse = designer_btn
		else:
			var sm = GameState.shipyard_manager
			var dp = pages["designer"]
			var want := "consumable_hull" if sm.consumable_hull_slot == "" else ("consumable_shield" if sm.consumable_shield_slot == "" else "")
			if want != "" and dp.has_method("get_slot_widget"):
				dp.focus_slot(want)
				target_to_pulse = dp.get_slot_widget(want)
			elif dp.has_method("get_coach_anchor"):
				target_to_pulse = dp.get_coach_anchor("consumables")

	elif "m025b" in mm.active_missions:
		# Processing: Smelt Steel
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("smelt_steel_basic")
			var widget = page.get_widget_by_aid("smelt_steel_basic")
			if widget and not (pm.is_active and pm.current_recipe_id == "smelt_steel_basic"):
				target_to_pulse = widget.btn

	elif "m026b" in mm.active_missions:
		# Shipyard: Construct Industrial Frigate
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			target_to_pulse = pages["shipyard"].get_hull_widget("frigate_hull")

	elif "m026c" in mm.active_missions:
		# Combat: Farm a RARE drop in Lunar Orbit
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("lunar_orbit")
			target_to_pulse = page.get_enemy_card("z1_lunar_drone")

	elif "m026d" in mm.active_missions:
		# Designer: pulse the weapon slot to swap in a RARE+ weapon
		if current_page_name != "designer": target_to_pulse = designer_btn
		else:
			var dp = pages["designer"]
			if dp.has_method("get_slot_widget"):
				dp.focus_slot("weapon")
				target_to_pulse = dp.get_slot_widget("weapon")
			elif dp.has_method("get_coach_anchor"):
				target_to_pulse = dp.get_coach_anchor("schematic")

	elif "m026e" in mm.active_missions:
		# Combat: Defeat Rogue Architect (Lunar Orbit boss)
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("lunar_orbit")
			target_to_pulse = page.get_enemy_card("z1_boss_architect")

	elif "m029b" in mm.active_missions:
		# Processing: Advanced Circuitry
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("craft_adv_circuit")
			var widget = page.get_widget_by_aid("craft_adv_circuit")
			if widget and not (pm.is_active and pm.current_recipe_id == "craft_adv_circuit"):
				target_to_pulse = widget.btn

	elif "m030e" in mm.active_missions:
		# Research: Mars Debris Clearance (zone_3_access)
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("zone_3_access")
			if widget: target_to_pulse = widget

	elif "m030f" in mm.active_missions:
		# Combat: Scavenger Mechs (Mars Debris)
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("mars_debris")
			target_to_pulse = page.get_enemy_card("z3_scavenger_mech")

	elif "m030g" in mm.active_missions:
		# Research: Cryofield Expedition (zone_4_access)
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("zone_4_access")
			if widget: target_to_pulse = widget

	elif "m030h" in mm.active_missions:
		# Combat: Ice Wraiths (Cryofield)
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("cryofield")
			target_to_pulse = page.get_enemy_card("z4_ice_wraith")

	elif "m032d" in mm.active_missions:
		# Combat: Void Artifacts from Sector Alpha ships
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("sector_alpha")
			target_to_pulse = page.get_enemy_card("z5_alien_frigate")

	# P1 Onboarding: clear the Designer's equip-mission Armory filter when
	# no equip mission is active. set_equip_focus_filter and
	# clear_equip_focus_filter are both idempotent so calling per-tick is cheap.
	var _any_equip_active: bool = (
		"m007b" in mm.active_missions
		or "m015b" in mm.active_missions
		or "m022b" in mm.active_missions
		or "m024c" in mm.active_missions
	)
	if not _any_equip_active and pages.has("designer"):
		var _dp = pages["designer"]
		if _dp.has_method("clear_equip_focus_filter"):
			_dp.clear_equip_focus_filter()

	# P1 Onboarding — Repair routing.
	# When no mission demands a pulse, the hull is damaged, the player is on
	# another page, and they are not mid-combat, pulse the Shipyard sidebar
	# button so they know where to go. Once on Shipyard, the existing red-
	# pulsing Repair button (shipyard_page._update_repair_button) takes over.
	# Mission pulses always win — this is a pure fallback.
	if target_to_pulse == null:
		var sm_ref = GameState.shipyard_manager
		var cm_ref = GameState.combat_manager
		if sm_ref and sm_ref.current_hp < sm_ref.max_hp \
				and current_page_name != "shipyard" \
				and not (cm_ref and cm_ref.in_combat):
			target_to_pulse = shipyard_btn

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
func _on_bounty_btn_pressed(): switch_to("bounty")
func _on_quest_btn_pressed(): switch_to("quest")

func _on_menu_btn_pressed():
	GameState.save_game()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_game_resetted():
	switch_to("mission")
