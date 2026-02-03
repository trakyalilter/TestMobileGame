extends PanelContainer

@onready var credits_lbl = $MarginContainer/HBoxContainer/CreditsLabel
@onready var mission_lbl = $MarginContainer/HBoxContainer/MissionLabel
@onready var task_lbl = $MarginContainer/HBoxContainer/TaskLabel

var stability_lbl: Label # Added dynamically in _ready if not in scene

@onready var infra_led = $MarginContainer/HBoxContainer/StatusCluster/InfraLed
@onready var fleet_led = $MarginContainer/HBoxContainer/StatusCluster/FleetLed
@onready var research_led = $MarginContainer/HBoxContainer/StatusCluster/ResearchLed

func _ready():
	UITheme.apply_panel_style(self)
	
	# Premium Glassmorphism Feel
	self.modulate.a = 0.9
	UITheme.add_hover_scale(task_lbl, 1.02)
	UITheme.apply_segmented_font(credits_lbl, UITheme.COLORS["warning"])
	UITheme.apply_segmented_font(mission_lbl, Color(0.2, 0.8, 1.0)) # Cyan
	UITheme.apply_segmented_font(task_lbl, UITheme.COLORS["text_main"])
	
	# Add Stability Label dynamically to avoid tscn surgery
	stability_lbl = Label.new()
	stability_lbl.name = "StabilityLabel"
	stability_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stability_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stability_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stability_lbl.clip_text = true
	stability_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	$MarginContainer/HBoxContainer.add_child(stability_lbl)
	$MarginContainer/HBoxContainer.move_child(stability_lbl, 3) # After TaskLabel
	UITheme.apply_segmented_font(stability_lbl, Color.WHITE)
	
	# Prevent layout expansion from text
	for lbl in [credits_lbl, mission_lbl, task_lbl]:
		lbl.clip_text = true
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	
	UITheme.packet_landed.connect(_on_packet_landed)
	
	# Initial LED setup
	_setup_leds()
	
	# Initial sync
	update_hud()
	
	# Connect signals for real-time updates and activity blips
	if GameState.resources:
		GameState.resources.currency_added.connect(func(t, a): update_credits())
		GameState.resources.currency_removed.connect(func(t, a): update_credits())
	
	if GameState.mission_manager:
		GameState.mission_manager.mission_updated.connect(_update_mission_display)
		_update_mission_display()
	
	if GameState.infrastructure_manager:
		GameState.infrastructure_manager.activity_occurred.connect(func(): flash_led(infra_led, UITheme.CATEGORY_COLORS["infrastructure"]))
	if GameState.fleet_manager:
		GameState.fleet_manager.activity_occurred.connect(func(): flash_led(fleet_led, UITheme.CATEGORY_COLORS["mission"]))
	if GameState.research_manager:
		GameState.research_manager.activity_occurred.connect(func(): flash_led(research_led, UITheme.CATEGORY_COLORS["research"]))

var last_mission_id: String = ""
var last_completed_state: bool = false

func _update_mission_display():
	if not GameState.mission_manager: return
	
	var mm = GameState.mission_manager
	if mm.active_missions.is_empty():
		mission_lbl.text = "MISSION: NONE"
		return
		
	var mid = mm.active_missions[0]
	var m = mm.missions[mid]
	var prog_pct = (m["current_qty"] / float(max(1, m["target_qty"]))) * 100.0
	
	# Compact representation for the header
	mission_lbl.text = "OBJ: %s (%d%%)" % [m["name"].to_upper(), int(prog_pct)]
	
	# SENSORY FEEDBACK LOGIC (Audit v13.0)
	# Case 1: Mission Completed (Transition from Incomplete -> Complete)
	if m["completed"] and not last_completed_state:
		# TACTILE: Heavy thud to signify job done
		UITheme.trigger_ui_thud(mission_lbl, 6.0) 
		# VISUAL: Gold Pulse
		UITheme.add_pulse_glow(mission_lbl, "inventory") # Gold color
		
	# Case 2: New Mission Started (ID changed)
	if mid != last_mission_id:
		# VISUAL: Circuit Surge (New orders received)
		UITheme.trigger_circuit_surge(mission_lbl, Color(0.2, 0.8, 1.0))
		
	last_mission_id = mid
	last_completed_state = m["completed"]
	
	if m["completed"]:
		mission_lbl.add_theme_color_override("font_color", Color.GOLD)
		mission_lbl.text = "OBJ: [ %s READY ]" % m["name"].to_upper()
	else:
		mission_lbl.add_theme_color_override("font_color", Color(0.2, 0.8, 1.0))

func _setup_leds():
	# Make them circular (or rounded squares for mechanical look)
	for led in [infra_led, fleet_led, research_led]:
		led.custom_minimum_size = Vector2(6, 6)
		led.color = Color(0.1, 0.1, 0.1)

func flash_led(led: ColorRect, color: Color):
	var tween = create_tween()
	tween.tween_property(led, "color", color.lightened(0.5), 0.1)
	tween.tween_property(led, "color", Color(0.1, 0.1, 0.1), 0.5).set_delay(0.1)

func _process(_delta):
	# Poll for task status
	update_task_status()
	update_stability()

func update_stability():
	if not GameState.infrastructure_manager: return
	
	var stability = GameState.infrastructure_manager.energy_efficiency * 100.0
	stability_lbl.text = "STABILITY: %d%%" % int(stability)
	
	if stability < 100.0:
		stability_lbl.add_theme_color_override("font_color", UITheme.COLORS["negative"])
		# Visual flicker if stability is critical
		if stability < 50.0 and Engine.get_frames_drawn() % 30 < 10:
			stability_lbl.modulate.a = 0.3
		else:
			stability_lbl.modulate.a = 1.0
	else:
		stability_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4)) # Green
		stability_lbl.modulate.a = 1.0

func update_hud():
	update_credits()

func update_credits():
	var cr = GameState.resources.get_currency("credits")
	credits_lbl.text = "Credits: %s" % UITheme.format_num(cr)

# Removed _on_energy_changed as it's no longer displayed in the header

func update_task_status():
	var status_text = "Idle"
	
	if GameState.gathering_manager and GameState.gathering_manager.is_active:
		var gm = GameState.gathering_manager
		var action_name = gm.current_action.get("name", "Gathering")
		var speed_mult = gm.get_action_speed_multiplier(gm.current_action_id)
		var prog = (gm.action_progress / (gm.action_duration / speed_mult)) * 100.0
		status_text = "Gathering: %s (%d%%)" % [action_name, int(prog)]
		
	elif GameState.processing_manager and GameState.processing_manager.is_active:
		var pm = GameState.processing_manager
		var recipe_name = pm.current_recipe.get("name", "Processing")
		var speed_mult = pm.get_recipe_speed_multiplier(pm.current_recipe_id)
		var prog = (pm.action_progress / (pm.current_recipe["duration"] / speed_mult)) * 100.0
		status_text = "Engineering: %s (%d%%)" % [recipe_name, int(prog)]
		
	elif GameState.combat_manager and GameState.combat_manager.in_combat:
		var cm = GameState.combat_manager
		status_text = "Combat: %s" % cm.current_enemy.get("name", "Unknown")
		
	elif GameState.research_manager and GameState.research_manager.is_active:
		var rm = GameState.research_manager
		var tech_name = rm.tech_tree[rm.active_tech_id]["name"]
		var prog = (rm.action_progress / rm.calculate_effective_duration(rm.active_tech_id)) * 100.0
		status_text = "Researching: %s (%d%%)" % [tech_name, int(prog)]
	
	task_lbl.text = "System Action: %s" % status_text
	if status_text == "Idle":
		task_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	else:
		task_lbl.add_theme_color_override("font_color", Color.WHITE)

func _on_packet_landed(_color: Color):
	# TACTILE: Subtle thud on arrival
	UITheme.trigger_ui_thud(credits_lbl, 1.5)
	
	# Visual "Overheat" pulse
	var tween = create_tween()
	credits_lbl.modulate = Color(2, 1.5, 1) # White-ish orange flash
	tween.tween_property(credits_lbl, "modulate", Color.WHITE.lightened(0.3), 0.2)
