extends PanelContainer

var bid: String
var data: Dictionary
var manager: RefCounted
var parent_ui: Node

@onready var name_lbl = $MarginContainer/VBoxContainer/NameLabel
@onready var stats_lbl = $MarginContainer/VBoxContainer/StatsLabel
@onready var desc_lbl = $MarginContainer/VBoxContainer/DescLabel
@onready var cost_lbl = $MarginContainer/VBoxContainer/CostLabel
@onready var count_lbl = $MarginContainer/VBoxContainer/CountLabel
@onready var buy_btn = $MarginContainer/VBoxContainer/BuyButton
@onready var oc_container = $MarginContainer/VBoxContainer/OverclockContainer
@onready var oc_lbl = $MarginContainer/VBoxContainer/OverclockContainer/OCLabel
@onready var oc_slider = $MarginContainer/VBoxContainer/OverclockContainer/OCSlider

var production_timer: float = 0.0
var production_interval: float = 1.0

func setup(p_bid: String, p_data: Dictionary, p_manager, p_parent):
	bid = p_bid
	data = p_data
	manager = p_manager
	parent_ui = p_parent
	
	name_lbl.text = data["name"]
	name_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["infrastructure"])
	desc_lbl.text = data["description"]
	
	UITheme.apply_card_style(self, "infrastructure")
	UITheme.apply_premium_button_style(buy_btn, "infrastructure")
	
	production_interval = data.get("interval", 2.0)
	
	var gen = data.get("energy_gen", 0.0)
	var cons = data.get("energy_cons", 0.0)
	var stats_text = ""
	if gen > 0: 
		stats_text = "+%.1f kW" % gen
		stats_lbl.add_theme_color_override("font_color", Color.YELLOW)
	elif cons > 0:
		stats_text = "-%.1f kW" % cons
		stats_lbl.add_theme_color_override("font_color", Color.TOMATO)
	stats_lbl.text = stats_text
	
	var cost_str = ""
	for res in data["cost"]:
		var display_name = ElementDB.get_display_name(res)
		cost_str += "%d %s\n" % [data["cost"][res], display_name]
	cost_lbl.text = cost_str.strip_edges()
	
	oc_slider.value = manager.get_overclock_level(bid)
	oc_lbl.text = "Overclock: %.1fx" % oc_slider.value
	oc_slider.value_changed.connect(_on_oc_slider_changed)

func _process(delta):
	# Refresh buildability
	update_state()
	
	# THEMATIC: Production Flow (Simulated for HUD satisfaction)
	var count = manager.get_building_count(bid)
	if count > 0 and production_interval > 0:
		production_timer += delta
		if production_timer >= production_interval:
			production_timer = 0
			_fire_production_packet()

func _fire_production_packet():
	# THEMATIC: Stagger suppression - don't pulse if we have too many buildings (performance/eye fatigue)
	var count = manager.get_building_count(bid)
	
	# Find the Credits Label in the Global Header as the target
	var header = get_tree().root.get_child(0).find_child("CreditsLabel", true, false)
	if header:
		UITheme.spawn_data_packet(self, header.global_position, UITheme.CATEGORY_COLORS["infrastructure"])
		
		# TACTILE: Grouped Floating Yield Text (Audit v3.0 Fix)
		var yield_data = data.get("yield", {})
		if not yield_data.is_empty():
			var yield_strings = []
			for res in yield_data:
				var amount = yield_data[res] * count
				yield_strings.append("+%s %s" % [FormatUtils.format_number(amount), res])
			_spawn_floating_yield(", ".join(yield_strings))
		
		# Visual "Kickback" pulse (Staggered or reduced for high counts)
		var pulse_intensity = 1.02 if count < 50 else 1.005
		var tween = create_tween()
		tween.tween_property(self, "scale", Vector2(pulse_intensity, pulse_intensity), 0.05)
		tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)

func _spawn_floating_yield(text: String):
	var float_lbl = Label.new()
	float_lbl.text = text
	float_lbl.add_theme_font_size_override("font_size", 9)
	float_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["infrastructure"])
	# Add to main scene tree root child 0 to float over all UI
	get_tree().root.get_child(0).add_child(float_lbl)
	
	float_lbl.global_position = global_position + Vector2(size.x * 0.7, 10)
	
	var tween = float_lbl.create_tween()
	tween.tween_property(float_lbl, "global_position:y", float_lbl.global_position.y - 40, 0.8).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(float_lbl, "modulate:a", 0.0, 0.8)
	tween.tween_callback(float_lbl.queue_free)

func update_state():
	var count = manager.get_building_count(bid)
	var max_count = data.get("max", 999)
	
	if data.has("max"):
		count_lbl.text = "Owned: %d / %d" % [count, max_count]
	else:
		count_lbl.text = "Owned: %d" % count
	
	# Refresh Cost Display (Iter8 Scaling)
	var current_costs = manager.get_building_cost(bid)
	var cost_str = ""
	var can_afford_all = true
	
	for res in current_costs:
		var needed = current_costs[res]
		var owned = 0.0
		if res == "credits":
			owned = GameState.resources.get_currency("credits")
		else:
			owned = GameState.resources.get_element_amount(res)
		
		var display_name = ElementDB.get_display_name(res)
		var res_str = "%s %s" % [FormatUtils.format_number(needed), display_name]
		
		if owned >= needed:
			cost_str += "[color=#00ff00]%s[/color]\n" % res_str
		else:
			cost_str += "[color=#ff6666]%s[/color]\n" % res_str
			can_afford_all = false
			
	cost_lbl.text = cost_str.strip_edges()
	
	if data.has("max") and count >= max_count:
		buy_btn.text = "Maxed"
		buy_btn.disabled = true
		_stop_pulse()
	else:
		buy_btn.text = "Build"
		buy_btn.disabled = not can_afford_all
		if can_afford_all:
			_start_pulse()
		else:
			_stop_pulse()
			
	# Update Overclock Visibility
	var oc_level = manager.get_overclock_level(bid)
	oc_lbl.text = "Overclock: %.1fx" % oc_level
	oc_slider.value = oc_level
	
	# Optional: Show warnings if efficiency is low
	if manager.energy_efficiency < 1.0:
		oc_lbl.add_theme_color_override("font_color", Color.YELLOW)
	else:
		oc_lbl.add_theme_color_override("font_color", Color.CYAN)

var pulse_tween: Tween
func _start_pulse():
	if pulse_tween: return
	pulse_tween = UITheme.add_pulse_glow(buy_btn, "infrastructure")

func _stop_pulse():
	if pulse_tween:
		pulse_tween.kill()
		pulse_tween = null
	buy_btn.modulate = Color.WHITE

func _on_buy_button_pressed():
	if GameState.infrastructure_manager.build(bid):
		# TACTILE: UI Thud on purchase
		UITheme.trigger_ui_thud(self, 6.0)
		
		# Visual feedback pop
		var tween = create_tween()
		tween.tween_property(self, "scale", Vector2(1.05, 1.05), 0.1)
		tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
		parent_ui.update_ui()

func _on_oc_slider_changed(value: float):
	manager.set_overclock_level(bid, value)
	oc_lbl.text = "Overclock: %.1fx" % value
	UITheme.trigger_ui_thud(self, 1.5)
