extends PanelContainer

@onready var credits_lbl = $MarginContainer/HBoxContainer/CreditsLabel
@onready var task_lbl = $MarginContainer/HBoxContainer/TaskLabel

# P-onboard: emitted when the player taps the Current-Objective chip → main switches
# to the Missions page.
signal objective_pressed
var objective_btn: Button
# P-cargo: emitted when the player taps the header slot meter → main switches to
# the Inventory page.
signal inventory_pressed

var credits_led: ColorRect

# Header cargo-slot meter (used/max): amber near-full, red + pulse when full,
# tap → Inventory. The persistent counterpart to the transient full toast.
var slot_btn: Button
var _slot_pulse: Tween
var _slot_sig: String = ""
var _slot_was_full: bool = false

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

	# 2. Add Status LEDs & Enhanced Labels
	_setup_leds()
	_setup_objective_chip()
	_setup_slot_meter()

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

	# Prevent layout expansion from text
	for lbl in [credits_lbl, task_lbl]:
		lbl.clip_text = true
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	# Initial sync
	update_credits()
	
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


# ── Cargo-slot meter ────────────────────────────────────────────────────────
func _setup_slot_meter() -> void:
	slot_btn = Button.new()
	slot_btn.name = "SlotMeter"
	slot_btn.flat = true
	slot_btn.focus_mode = Control.FOCUS_NONE
	slot_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slot_btn.icon = load("res://assets/icons/nav/inventory.svg")
	slot_btn.add_theme_constant_override("icon_max_width", 15)
	slot_btn.add_theme_constant_override("h_separation", 5)
	slot_btn.add_theme_font_size_override("font_size", 13)
	slot_btn.tooltip_text = "Cargo slots — sell or expand storage when full."
	slot_btn.pressed.connect(func(): inventory_pressed.emit())

	var hbox = $MarginContainer/HBoxContainer
	hbox.add_child(slot_btn)
	hbox.move_child(slot_btn, credits_lbl.get_index() + 1)
	# Liras hugs its value so the meter sits right beside it; the task label
	# keeps the expand and centres in the remaining width. Both trim flags MUST be
	# off here — _setup_leds set clip_text=true AND text_overrun=TRIM_ELLIPSIS
	# (harmless while the label EXPAND-filled). Godot's Label.get_minimum_size()
	# pins width to 1px if EITHER flag is set, so under SHRINK_BEGIN the label
	# collapses and the amount vanishes — clearing clip_text alone is not enough.
	# The Lira value is always FormatUtils-compact, so no overflow risk.
	credits_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	credits_lbl.clip_text = false
	credits_lbl.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	update_slots()

func update_slots() -> void:
	if not is_instance_valid(slot_btn) or not GameState.resources:
		return
	var used: int = GameState.resources.get_used_slots()
	var maxs: int = GameState.resources.get_max_slots()
	var sig := "%d/%d" % [used, maxs]
	if sig == _slot_sig:
		return   # unchanged — skip the per-frame work
	_slot_sig = sig
	slot_btn.text = sig

	var full: bool = used >= maxs
	var near: bool = used >= maxs - 2
	var col: Color
	if full:
		col = Color(1.0, 0.42, 0.35)      # red — drops are being wasted
	elif near:
		col = Color(1.0, 0.72, 0.30)      # amber — almost out of room
	else:
		col = Color(0.62, 0.66, 0.78)     # neutral
	slot_btn.add_theme_color_override("font_color", col)
	slot_btn.add_theme_color_override("font_hover_color", col.lightened(0.25))
	slot_btn.add_theme_color_override("icon_normal_color", col)

	if full and not _slot_was_full:
		_start_slot_pulse()
	elif not full and _slot_was_full:
		_stop_slot_pulse()
	_slot_was_full = full

func _start_slot_pulse() -> void:
	_stop_slot_pulse()
	if not is_instance_valid(slot_btn):
		return
	_slot_pulse = create_tween().set_loops()
	_slot_pulse.tween_property(slot_btn, "modulate", Color(1.0, 0.55, 0.55), 0.55).set_trans(Tween.TRANS_SINE)
	_slot_pulse.tween_property(slot_btn, "modulate", Color.WHITE, 0.55).set_trans(Tween.TRANS_SINE)

func _stop_slot_pulse() -> void:
	if _slot_pulse and _slot_pulse.is_valid():
		_slot_pulse.kill()
	_slot_pulse = null
	if is_instance_valid(slot_btn):
		slot_btn.modulate = Color.WHITE




func flash_led(led: ColorRect, color: Color):
	var tween = create_tween()
	tween.tween_property(led, "color", color.lightened(0.5), 0.1)
	tween.tween_property(led, "color", Color(0.1, 0.1, 0.1), 0.5).set_delay(0.1)

func _process(_delta):
	# Poll for task status
	update_task_status()
	update_objective()
	update_slots()

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
		status_text = "Gathering: %s" % action_name

	elif GameState.processing_manager and GameState.processing_manager.is_active:
		var pm = GameState.processing_manager
		var recipe_name = pm.current_recipe.get("name", "Processing")
		status_text = "Engineering: %s" % recipe_name

	elif GameState.combat_manager and GameState.combat_manager.in_combat:
		var cm = GameState.combat_manager
		var enemy_name = "Unknown"
		if cm.current_enemy:
			enemy_name = cm.current_enemy.get("name", "Unknown")
		status_text = "Combat: %s" % enemy_name
		
	elif GameState.research_manager and GameState.research_manager.is_active:
		var rm = GameState.research_manager
		var tech_name = rm.tech_tree[rm.active_tech_id]["name"]
		status_text = "Researching: %s" % tech_name
	
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
