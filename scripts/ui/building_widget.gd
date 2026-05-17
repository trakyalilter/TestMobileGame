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

var production_timer: float = 0.0
var production_interval: float = 1.0

func setup(p_bid: String, p_data: Dictionary, p_manager, p_parent):
	bid = p_bid
	data = p_data
	manager = p_manager
	parent_ui = p_parent
	
	custom_minimum_size = Vector2(0, 240)
	
	name_lbl.text = data["name"]
	name_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["infrastructure"])
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	desc_lbl.text = data["description"]
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Grow to fit ALL cost lines (4-cost buildings clipped the last line,
	# hiding gating mats like Drone Core).
	cost_lbl.fit_content = true
	
	UITheme.apply_card_style(self, "infrastructure")
	UITheme.apply_premium_button_style(buy_btn, "infrastructure")
	
	# Hide unused overclocking UI
	if has_node("MarginContainer/VBoxContainer/OverclockContainer"):
		get_node("MarginContainer/VBoxContainer/OverclockContainer").hide()
	
	production_interval = data.get("interval", 2.0)
	
	_ensure_header()
	update_state()

var _header_panel: PanelContainer
func _ensure_header():
	if _header_panel: return
	_header_panel = UITheme.inject_diegetic_header(self, "infrastructure")
	
	# Efficiency Slider (Throttle)
	var throttle_container = VBoxContainer.new()
	$MarginContainer/VBoxContainer.add_child(throttle_container)
	# Move slider above Buy Button
	$MarginContainer/VBoxContainer.move_child(throttle_container, buy_btn.get_index())
	
	var throttle_header = HBoxContainer.new()
	throttle_container.add_child(throttle_header)
	
	var throttle_title = Label.new()
	throttle_title.text = "Efficiency"
	throttle_title.add_theme_font_size_override("font_size", 10)
	throttle_header.add_child(throttle_title)
	
	var throttle_val_lbl = Label.new()
	var current_throttle = manager.get_building_throttle(bid)
	throttle_val_lbl.text = "%d%%" % (current_throttle * 100)
	throttle_val_lbl.add_theme_font_size_override("font_size", 10)
	throttle_val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	throttle_val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	throttle_header.add_child(throttle_val_lbl)
	
	var slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = current_throttle * 100
	throttle_container.add_child(slider)
	
	slider.value_changed.connect(func(val):
		manager.set_building_throttle(bid, val / 100.0)
		throttle_val_lbl.text = "%d%%" % val
	)
	
	var gen = data.get("energy_gen", 0.0)
	var cons = data.get("energy_cons", 0.0)
	var stats_text = ""
	
	# Forensic 3: Real-time Rate Display (Show adjusted yield/output)
	var rates = manager.get_building_adjusted_rate(bid)
	var yield_text = ""
	if not rates["yield"].is_empty():
		for res in rates["yield"]:
			yield_text += "+%.1f %s/m " % [rates["yield"][res], res]
	
	if gen > 0: 
		stats_text = "+%.1f kW" % gen
		stats_lbl.add_theme_color_override("font_color", Color.YELLOW)
	elif cons > 0:
		stats_text = "-%.1f kW %s" % [cons, yield_text]
		stats_lbl.add_theme_color_override("font_color", Color.TOMATO)
	stats_lbl.text = stats_text
	
	var cost_str = ""
	for res in data["cost"]:
		var display_name = ElementDB.get_display_name(res)
		cost_str += "%d %s\n" % [data["cost"][res], display_name]
	cost_lbl.text = cost_str.strip_edges()

func _process(delta):
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
	var missing := ""  # first unmet cost — surfaced on the disabled button

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
			if missing == "":
				missing = "%s %s" % [FormatUtils.format_number(needed - owned), display_name]
			
	cost_lbl.text = cost_str.strip_edges()
	
	# Check Requirements (Locked State)
	var has_research = true
	var req_id = data.get("research_req")
	if req_id:
		has_research = GameState.research_manager.is_tech_unlocked(req_id)
		
	var lvl_req = data.get("level_req", 1)
	var has_level = manager.get_level() >= lvl_req
	
	if not has_research:
		var tech_data = GameState.research_manager.tech_tree.get(req_id, {})
		var tech_name = tech_data.get("name", "Unknown Tech")
		# Force strict formatting
		var lock_msg = "RESEARCH: %s" % tech_name
		UITheme.apply_locked_overlay(self, data["name"], lock_msg, true, req_id, "infrastructure")
		buy_btn.text = "RESEARCH REQUIRED" # All Caps for emphasis
		buy_btn.disabled = true
		return
	elif not has_level:
		UITheme.apply_locked_overlay(self, data["name"], "LEVEL %d REQUIRED" % lvl_req, true, "", "infrastructure")
		buy_btn.text = "Requires Lv %d" % lvl_req
		buy_btn.disabled = true
		return
	else:
		UITheme.apply_locked_overlay(self, data["name"], "", false)

	if data.has("max") and count >= max_count:
		buy_btn.text = "Maxed"
		buy_btn.disabled = true
		_stop_pulse()
	elif can_afford_all:
		var mult = manager.buy_multiplier
		buy_btn.text = "Build x%d" % mult if mult > 1 else "Build"
		buy_btn.disabled = false
		buy_btn.tooltip_text = ""
		_start_pulse()
	else:
		# Name the blocking resource so a clipped/long cost list can't hide
		# WHY Build is disabled (the Drone Core / Salvage Data class).
		buy_btn.text = "Need %s" % missing
		buy_btn.disabled = true
		buy_btn.tooltip_text = "Missing: %s" % missing
		_stop_pulse()

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
