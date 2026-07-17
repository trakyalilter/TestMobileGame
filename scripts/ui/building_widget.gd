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
var _mastery_lbl: Label
# v130: Boost-Card overclock UI (repurposed OverclockContainer scene node)
var _oc_container: Control
var _oc_label: Label
var _oc_btn: Button
# v131: throttle slider refs — kept so installing a card raises the cap to 200% live.
var _throttle_slider: HSlider
var _throttle_val_lbl: Label

func setup(p_bid: String, p_data: Dictionary, p_manager, p_parent):
	bid = p_bid
	data = p_data
	manager = p_manager
	parent_ui = p_parent
	
	custom_minimum_size = Vector2(0, 240)
	
	name_lbl.text = tr(data["name"])
	name_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["infrastructure"])
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	desc_lbl.text = tr(data["description"])
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Grow to fit ALL cost lines (4-cost buildings clipped the last line,
	# hiding gating mats like Drone Core).
	cost_lbl.fit_content = true
	
	UITheme.apply_card_style(self, "infrastructure")
	UITheme.apply_premium_button_style(buy_btn, "infrastructure")
	
	# v130: the old slider-overclock container is repurposed for the Boost-Card
	# overclock — label shows installed cards, a button installs one from cargo.
	# Hidden until relevant (owned building + a card in cargo or already installed).
	if has_node("MarginContainer/VBoxContainer/OverclockContainer"):
		_oc_container = get_node("MarginContainer/VBoxContainer/OverclockContainer")
		_oc_label = _oc_container.get_node("OCLabel")
		# v131: no overclock STATUS text — the Efficiency slider's 200% cap is the
		# indicator. The label node stays permanently hidden; the container is only
		# ever an unlock prompt (the UNLOCK button).
		_oc_label.visible = false
		_oc_container.get_node("OCSlider").hide()
		_oc_btn = Button.new()
		_oc_btn.text = tr("INSTALL BOOST CARD")
		_oc_btn.custom_minimum_size = Vector2(0, 28)
		_oc_btn.clip_text = true  # v131: never let a long label widen the card
		_oc_btn.add_theme_font_size_override("font_size", 10)
		UITheme.apply_premium_button_style(_oc_btn, "infrastructure")
		# v130: the Boost Card material icon, tinted its signature amber (same
		# id-keyed glyph the inventory/recipes show). Degrades to text-only if
		# the icon file is ever absent (get_material_icon returns null).
		var _oc_tex: Texture2D = ElementDB.get_material_icon("BoostCard")
		if _oc_tex:
			_oc_btn.icon = _oc_tex
			_oc_btn.add_theme_constant_override("icon_max_width", 18)
			var _oc_tint: Color = ElementDB.get_material_tint("BoostCard")
			for _st in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
				_oc_btn.add_theme_color_override(_st, _oc_tint)
			_oc_btn.add_theme_color_override("icon_disabled_color", Color(_oc_tint.r, _oc_tint.g, _oc_tint.b, 0.45))
		_oc_btn.pressed.connect(_on_overclock_pressed)
		_oc_container.add_child(_oc_btn)
		_oc_container.hide()
	
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
	throttle_title.text = tr("Efficiency")
	throttle_title.add_theme_font_size_override("font_size", 10)
	throttle_header.add_child(throttle_title)
	
	var throttle_val_lbl = Label.new()
	var current_throttle = manager.get_building_throttle(bid)
	throttle_val_lbl.text = tr("%d%%") % (current_throttle * 100)
	throttle_val_lbl.add_theme_font_size_override("font_size", 10)
	throttle_val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	throttle_val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	throttle_header.add_child(throttle_val_lbl)
	_throttle_val_lbl = throttle_val_lbl

	var slider = HSlider.new()
	slider.min_value = 0
	# v131: Boost-Card overclock raises the cap to 200% (else 100%). update_state()
	# keeps this in sync so installing a card lifts the ceiling live.
	slider.max_value = 200 if (manager.has_method("get_overclock") and manager.get_overclock(bid) >= 1) else 100
	slider.step = 5
	slider.value = current_throttle * 100
	throttle_container.add_child(slider)
	_throttle_slider = slider

	slider.value_changed.connect(func(val):
		manager.set_building_throttle(bid, val / 100.0)
		throttle_val_lbl.text = tr("%d%%") % val
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

	# Infra↔Mastery readout — populated by update_state(), hidden when unlinked.
	_mastery_lbl = Label.new()
	_mastery_lbl.add_theme_font_size_override("font_size", 10)
	_mastery_lbl.add_theme_color_override("font_color", Color(1.0, 0.84, 0.4))
	_mastery_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mastery_lbl.visible = false
	$MarginContainer/VBoxContainer.add_child(_mastery_lbl)
	$MarginContainer/VBoxContainer.move_child(_mastery_lbl, stats_lbl.get_index() + 1)

	var cost_str = ""
	for res in data["cost"]:
		var display_name = UITheme.LIRA_ICON_BB if res == "credits" else ElementDB.get_display_name(res)
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
		count_lbl.text = tr("Owned: %d / %d") % [count, max_count]
	else:
		count_lbl.text = tr("Owned: %d") % count
	
	# Infra↔Mastery: linked Mastery level + the output bonus it grants (count>0).
	_update_mastery_readout(count)

	# v131: Boost-Card overclock. A card is a ONE-TIME unlock that raises this
	# building type's Efficiency cap 100%→200%. NO status text — the slider's 200%
	# cap IS the indicator. The container shows ONLY as an unlock prompt: a card is
	# in cargo AND this type isn't overclocked yet. Once unlocked it disappears.
	if _oc_container:
		var oc: int = manager.get_overclock(bid) if manager.has_method("get_overclock") else 0
		var cards: float = GameState.resources.get_element_amount("BoostCard")
		var unlocked: bool = oc >= 1
		var show_oc: bool = count > 0 and not unlocked and cards >= 1
		_oc_container.visible = show_oc
		if show_oc:
			_oc_btn.visible = true
			_oc_btn.disabled = false
			_oc_btn.text = tr("UNLOCK 200% (1 Card)")
		# Keep the slider ceiling synced — install lifts it to 200% live.
		if _throttle_slider:
			_throttle_slider.max_value = 200 if unlocked else 100

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
		
		var is_cr: bool = (res == "credits")
		# cost_lbl is BBCode RichText -> Lira icon; the disabled Build button
		# is a plain Button -> the word "Liras" (can't embed an image there).
		var display_name: String = UITheme.LIRA_ICON_BB if is_cr else ElementDB.get_display_name(res)
		var res_str = "%s %s" % [FormatUtils.format_number(needed), display_name]

		if owned >= needed:
			cost_str += "[color=#00ff00]%s[/color]\n" % res_str
		else:
			cost_str += "[color=#ff6666]%s[/color]\n" % res_str
			can_afford_all = false
			if missing == "":
				var missing_name: String = "Liras" if is_cr else ElementDB.get_display_name(res)
				missing = "%s %s" % [FormatUtils.format_number(needed - owned), missing_name]
			
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
		var lock_msg = tr("RESEARCH: %s") % tr(tech_name)
		UITheme.apply_locked_overlay(self, data["name"], lock_msg, true, req_id, "infrastructure")
		buy_btn.text = tr("RESEARCH REQUIRED") # All Caps for emphasis
		buy_btn.disabled = true
		return
	elif not has_level:
		UITheme.apply_locked_overlay(self, data["name"], tr("LEVEL %d REQUIRED") % lvl_req, true, "", "infrastructure")
		buy_btn.text = tr("Requires Lv %d") % lvl_req
		buy_btn.disabled = true
		return
	else:
		UITheme.apply_locked_overlay(self, data["name"], "", false)

	if data.has("max") and count >= max_count:
		buy_btn.text = tr("Maxed")
		buy_btn.disabled = true
		_stop_pulse()
	elif can_afford_all:
		var mult = manager.buy_multiplier
		buy_btn.text = tr("Build x%d") % mult if mult > 1 else "Build"
		buy_btn.disabled = false
		buy_btn.tooltip_text = ""
		_start_pulse()
	else:
		# Name the blocking resource so a clipped/long cost list can't hide
		# WHY Build is disabled (the Drone Core / Salvage Data class).
		buy_btn.text = tr("Need %s") % missing
		buy_btn.disabled = true
		buy_btn.tooltip_text = tr("Missing: %s") % missing
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
	else:
		# v137: build() was SILENT on failure. The cost display is throttled (~200ms), so
		# a card can still read "affordable" green for a moment after a resource drops
		# below cost — the player clicks, can_afford fails, and nothing visibly happens.
		# Tell them exactly what's short, then re-sync THIS card so the stale green corrects.
		UITheme.show_notification(_build_block_reason(), UITheme.COLORS["negative"])
		update_state()

# Why can't this be built right now? Names the first shortfall for the failure toast.
func _build_block_reason() -> String:
	var costs = manager.get_building_cost(bid)
	for res in costs:
		var need := float(costs[res])
		var have := 0.0
		if res == "credits":
			have = float(GameState.resources.get_currency("credits"))
		else:
			have = GameState.resources.get_element_amount(res)
		if have < need:
			var nm: String = "Liras" if res == "credits" else ElementDB.get_display_name(res)
			return "Need %s more %s" % [FormatUtils.format_number(need - have), nm]
	var d: Dictionary = manager.building_db.get(bid, {})
	if d.get("research_req") and GameState.research_manager and not GameState.research_manager.is_tech_unlocked(d["research_req"]):
		return "Research required to build this"
	if d.has("max"):
		return "Maximum reached"
	return "Cannot build right now"

func _update_mastery_readout(count: int) -> void:
	if not _mastery_lbl: return
	if count <= 0:
		_mastery_lbl.visible = false
		return
	var info: Dictionary = manager.get_building_mastery_info(bid)
	if not info.get("linked", false):
		_mastery_lbl.visible = false
		return
	var disp: String = ElementDB.get_display_name(info.get("symbol", ""))
	_mastery_lbl.text = tr("%s Mastery  Lv %d  (+%d%% output)") % [disp, int(info.get("level", 0)), int(round(info.get("bonus_pct", 0.0)))]
	_mastery_lbl.visible = true

# v130: install one Boost Card from cargo onto this building type (consumed —
# a permanent overclock; the manager clamps the effect to owned units).
func _on_overclock_pressed() -> void:
	var r: Dictionary = manager.install_boost_card(bid)
	var ok: bool = bool(r.get("ok", false))
	UITheme.show_notification(str(r.get("msg", "")), UITheme.COLORS["positive"] if ok else UITheme.COLORS["negative"])
	if ok:
		UITheme.trigger_ui_thud(self, 4.0)
	update_state()
	if parent_ui and parent_ui.has_method("update_ui"):
		parent_ui.update_ui()
