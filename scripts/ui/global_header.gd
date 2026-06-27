extends PanelContainer

@onready var credits_lbl = $MarginContainer/HBoxContainer/CreditsLabel
@onready var task_lbl = $MarginContainer/HBoxContainer/TaskLabel

# P-onboard: emitted when the player taps the Current-Objective chip → main switches
# to the Missions page.
signal objective_pressed
var objective_btn: Button

var stability_lbl: Label
var credits_led: ColorRect
var stability_led: ColorRect

func _ready():
	# 1. Glassmorphism Styling
	var glass = StyleBoxFlat.new()
	glass.bg_color = Color(0.06, 0.06, 0.08, 0.85) # Translucent dark glass
	glass.border_width_bottom = 2
	glass.border_color = UITheme.COLORS["accent"]
	glass.border_color.a = 0.6
	glass.shadow_color = Color(0, 0, 0, 0.4)
	glass.shadow_size = 8
	glass.set_content_margin_all(8)
	add_theme_stylebox_override("panel", glass)
	
	# ... (Add Stability Label as before)
	stability_lbl = Label.new()
	stability_lbl.name = "StabilityLabel"
	stability_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stability_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stability_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stability_lbl.clip_text = true
	stability_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	$MarginContainer/HBoxContainer.add_child(stability_lbl)
	$MarginContainer/HBoxContainer.move_child(stability_lbl, 2) # Position between Credits and Task
	UITheme.apply_segmented_font(stability_lbl, Color.WHITE)
	
	# 2. Add Status LEDs & Enhanced Labels (NOW AFTER LABELS EXIST)
	_setup_leds()
	_setup_objective_chip()

func _setup_leds():
	var hbox = $MarginContainer/HBoxContainer
	
	# Apply fonts first
	UITheme.apply_segmented_font(credits_lbl, Color.WHITE)
	UITheme.apply_segmented_font(task_lbl, UITheme.COLORS["text_main"])
	
	# Credits LED
	credits_led = ColorRect.new()
	credits_led.custom_minimum_size = Vector2(4, 12)
	credits_led.color = UITheme.COLORS["warning"]
	hbox.add_child(credits_led)
	hbox.move_child(credits_led, credits_lbl.get_index())

	# Lira currency symbol (replaces the "Liras:" text prefix)
	var lira_icon = TextureRect.new()
	lira_icon.name = "LiraIcon"
	lira_icon.texture = load("res://assets/icons/lira.svg")
	lira_icon.custom_minimum_size = Vector2(16, 16)
	lira_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lira_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lira_icon.modulate = Color(1.0, 0.82, 0.30)
	lira_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lira_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(lira_icon)
	hbox.move_child(lira_icon, credits_lbl.get_index())

	# Stability LED
	stability_led = ColorRect.new()
	stability_led.custom_minimum_size = Vector2(4, 12)
	stability_led.color = Color.GREEN
	hbox.add_child(stability_led)
	hbox.move_child(stability_led, stability_lbl.get_index())
	
	# Prevent layout expansion from text
	for lbl in [credits_lbl, task_lbl, stability_lbl]:
		lbl.clip_text = true
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	
	# Initial sync
	update_credits()
	update_stability()
	
	# Connect signals for real-time updates
	if GameState.resources:
		GameState.resources.currency_added.connect(func(t, a): update_credits())
		GameState.resources.currency_removed.connect(func(t, a): update_credits())
	
	


var last_mission_id: String = ""
var last_completed_state: bool = false

# P-onboard: persistent "Current Objective" chip. Surfaces the active mission as a
# one-line, tappable sentence so a player who never opens the Missions page still
# always knows the next step (and sees when one is ready to CLAIM).
func _setup_objective_chip() -> void:
	objective_btn = Button.new()
	objective_btn.name = "ObjectiveChip"
	objective_btn.flat = true
	objective_btn.focus_mode = Control.FOCUS_NONE
	objective_btn.clip_text = true
	objective_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	objective_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	objective_btn.add_theme_font_size_override("font_size", 12)
	objective_btn.tooltip_text = "Open Missions"
	objective_btn.pressed.connect(func(): objective_pressed.emit())
	$MarginContainer/HBoxContainer.add_child(objective_btn)
	update_objective()

func update_objective() -> void:
	if not is_instance_valid(objective_btn) or not GameState.mission_manager:
		return
	var obj: Dictionary = GameState.mission_manager.get_active_objective()
	if obj.is_empty():
		objective_btn.visible = false
		return
	objective_btn.visible = true
	var nm: String = str(obj.get("name", ""))
	var br := nm.find("] ")
	if br != -1:
		nm = nm.substr(br + 2)
	var is_ready: bool = obj.get("completed", false) and not obj.get("claimed", false)
	objective_btn.text = ("✓ CLAIM: " if is_ready else "▸ ") + nm
	objective_btn.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55) if is_ready else UITheme.COLORS["accent"])




func flash_led(led: ColorRect, color: Color):
	var tween = create_tween()
	tween.tween_property(led, "color", color.lightened(0.5), 0.1)
	tween.tween_property(led, "color", Color(0.1, 0.1, 0.1), 0.5).set_delay(0.1)

func _process(_delta):
	# Poll for task status
	update_task_status()
	update_stability()
	update_objective()

func update_stability():
	if not GameState.infrastructure_manager: return
	
	var stability = GameState.infrastructure_manager.energy_efficiency * 100.0
	stability_lbl.text = "STABILITY: %d%%" % int(stability)
	
	if stability < 100.0:
		stability_lbl.add_theme_color_override("font_color", UITheme.COLORS["negative"])
		stability_led.color = UITheme.COLORS["negative"]
		# Visual flicker if stability is critical
		if stability < 50.0 and Engine.get_frames_drawn() % 30 < 10:
			stability_lbl.modulate.a = 0.3
			stability_led.modulate.a = 0.3
		else:
			stability_lbl.modulate.a = 1.0
			stability_led.modulate.a = 1.0
	else:
		stability_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4)) # Green
		stability_led.color = Color(0.4, 1.0, 0.4)
		stability_lbl.modulate.a = 1.0
		stability_led.modulate.a = 1.0

func update_hud():
	update_credits()

func update_credits():
	var cr = GameState.resources.get_currency("credits")
	credits_lbl.text = " %s" % UITheme.format_num(cr)

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
		var enemy_name = "Unknown"
		if cm.current_enemy:
			enemy_name = cm.current_enemy.get("name", "Unknown")
		status_text = "Combat: %s" % enemy_name
		
	elif GameState.research_manager and GameState.research_manager.is_active:
		var rm = GameState.research_manager
		var tech_name = rm.tech_tree[rm.active_tech_id]["name"]
		var prog = (rm.action_progress / rm.calculate_effective_duration(rm.active_tech_id)) * 100.0
		status_text = "Researching: %s (%d%%)" % [tech_name, int(prog)]
	
	task_lbl.text = "%s" % status_text
	if status_text == "Idle":
		task_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	else:
		task_lbl.add_theme_color_override("font_color", Color.WHITE)

func _on_packet_landed(_color: Color):
	# TACTILE: Subtle thud on arrival
	UITheme.trigger_ui_thud(credits_lbl, 1.5)
	flash_led(credits_led, UITheme.COLORS["warning"])
	
	# Visual "Overheat" pulse
	var tween = create_tween()
	credits_lbl.modulate = Color(2, 1.5, 1) # White-ish orange flash
	tween.tween_property(credits_lbl, "modulate", Color.WHITE.lightened(0.3), 0.2)
