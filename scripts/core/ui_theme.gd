extends Node

signal packet_landed(color)
signal notification_requested(text: String, color: Color) # Feature v66.1
signal research_navigation_requested(tech_id: String)

func show_notification(text: Variant, color: Color = Color.WHITE):
	notification_requested.emit(text, color)

func format_number(value: float) -> String:
	if not is_finite(value): return "!!!" 
	if value <= 0: return "0"
	
	if value < 1000:
		return str(int(value))
	elif value < 1000000:
		return "%.1fK" % (value / 1000.0)
	elif value < 1000000000:
		return "%.1fM" % (value / 1000000.0)
	elif value < 1000000000000:
		return "%.1fB" % (value / 1000000000.0)
	else:
		return "%.1fT" % (value / 1000000000000.0)

# Color Palette
const COLORS = {
	"background": Color(0.08, 0.08, 0.12),
	"sidebar": Color(0.12, 0.12, 0.18),
	"panel_bg": Color(0.15, 0.15, 0.22),
	"accent": Color(0.2, 0.4, 0.8),
	"accent_bright": Color(0.3, 0.6, 1.0),
	"text_main": Color(0.9, 0.9, 0.95),
	"text_dim": Color(0.6, 0.6, 0.7),
	"text_accent": Color(0.0, 0.8, 1.0),
	"positive": Color(0.3, 0.7, 0.3),
	"negative": Color(0.8, 0.3, 0.3),
	"warning": Color(1.0, 0.8, 0.2)
}

const CATEGORY_COLORS = {
	"ops": Color(1.0, 0.6, 0.2), # Orange
	"engineering": Color(0.2, 0.8, 1.0), # Cyan
	"infrastructure": Color(0.4, 0.9, 0.4), # Green
	"combat": Color(1.0, 0.3, 0.3), # Red
	"inventory": Color(1.0, 0.8, 0.2), # Gold
	"research": Color(0.9, 0.4, 1.0), # Pink/Purple
	"shipyard": Color(0.3, 0.5, 1.0), # Blue
	"mission": Color(0.2, 1.0, 0.6) # Teal/Emerald
}

func setup_page_background(page: Control):
	pass

func apply_card_style(panel: Control, category: String = "ops") -> StyleBoxFlat:
	if not panel: return null
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	var style = StyleBoxFlat.new()
	# Blend 5% of accent into the panel background
	style.bg_color = COLORS["panel_bg"].lerp(accent, 0.05)
	style.bg_color.a = 0.90
	style.draw_center = true
	
	# Uniform 1px crisp border
	style.set_border_width_all(1)
	var border_col = accent
	border_col.a = 0.3 # Subtle 30% alpha
	style.border_color = border_col
	style.border_blend = false
	
	# Uniform modern rounded corners
	style.set_corner_radius_all(6)
	
	# Softer, diffused shadow
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 4)
	
	panel.add_theme_stylebox_override("panel", style)
	return style

func apply_diegetic_header(panel: Control, category: String = "ops"):
	if not panel: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	var style = StyleBoxFlat.new()
	style.bg_color = accent.lerp(Color.BLACK, 0.8)
	style.border_width_bottom = 2
	style.border_color = accent
	panel.add_theme_stylebox_override("panel", style)

func inject_diegetic_header(card: PanelContainer, category: String) -> PanelContainer:
	var margin_cont = card.get_node_or_null("MarginContainer")
	if not margin_cont: return null
	
	var vbox = margin_cont.get_node_or_null("VBoxContainer")
	if not vbox: return null
	
	var name_lbl = vbox.get_node_or_null("NameLabel")
	if not name_lbl: return null
	
	# 1. Adjust Main Layout to support header (flush top)
	margin_cont.add_theme_constant_override("margin_top", 0)
	margin_cont.add_theme_constant_override("margin_left", 2)
	margin_cont.add_theme_constant_override("margin_right", 2)
	margin_cont.add_theme_constant_override("margin_bottom", 6)
	vbox.add_theme_constant_override("separation", 8)
	
	# 2. Create Header
	var header_panel = PanelContainer.new()
	header_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(header_panel)
	vbox.move_child(header_panel, 0)
	
	# 3. Reparent NameLabel
	name_lbl.get_parent().remove_child(name_lbl)
	
	var header_margin = MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 8)
	header_margin.add_theme_constant_override("margin_top", 6)
	header_margin.add_theme_constant_override("margin_right", 8)
	header_margin.add_theme_constant_override("margin_bottom", 6)
	header_margin.mouse_filter = Control.MOUSE_FILTER_PASS
	header_panel.add_child(header_margin)
	
	header_margin.add_child(name_lbl)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_font_size_override("font_size", 13)
	
	# 4. Apply Styling
	apply_diegetic_header(header_panel, category)
	return header_panel

func apply_premium_button_style(button: Button, category: String = "ops"):
	if not button: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = COLORS["sidebar"].lerp(accent, 0.05)
	style_normal.set_border_width_all(1)
	var normal_border = accent
	normal_border.a = 0.4
	style_normal.border_color = normal_border
	style_normal.set_corner_radius_all(4)
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = accent.lerp(Color.BLACK, 0.3)
	style_hover.border_color = accent
	style_hover.shadow_color = Color(0, 0, 0, 0.2)
	style_hover.shadow_size = 4
	style_hover.shadow_offset = Vector2(0, 2)
	
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = accent
	style_pressed.border_color = Color.WHITE
	
	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.15, 0.15, 0.15, 0.8)
	style_disabled.border_color = Color(0.3, 0.3, 0.3, 0.5)
	button.add_theme_stylebox_override("disabled", style_disabled)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 13)

func apply_progress_bar_style(pb: ProgressBar, category: String = "ops"):
	if not pb: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	var style_bg = StyleBoxFlat.new()
	style_bg.bg_color = Color(0, 0, 0, 0.4)
	style_bg.set_border_width_all(1)
	style_bg.border_color = Color(0.2, 0.2, 0.2, 0.5)
	
	var style_fill = StyleBoxFlat.new()
	style_fill.bg_color = accent
	style_fill.border_width_right = 2
	style_fill.border_color = Color.WHITE
	style_fill.border_color.a = 0.5
	
	pb.add_theme_stylebox_override("background", style_bg)
	pb.add_theme_stylebox_override("fill", style_fill)

## apply_segmented_bar_style: Creates a high-tech "Digital Gauge" look
func apply_segmented_bar_style(pb: ProgressBar, category: String = "ops"):
	if not pb: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	var style_bg = StyleBoxFlat.new()
	style_bg.bg_color = Color(0.08, 0.08, 0.1, 0.9)
	style_bg.set_border_width_all(1)
	style_bg.border_color = accent.lerp(Color.BLACK, 0.6)
	
	var style_fill = StyleBoxFlat.new()
	style_fill.bg_color = accent
	style_fill.border_width_top = 2
	style_fill.border_color = Color.WHITE
	style_fill.border_color.a = 0.2
	
	pb.add_theme_stylebox_override("background", style_bg)
	pb.add_theme_stylebox_override("fill", style_fill)
	
	# REMOVED: Procedural overlays that cause phantom artifacts

## trigger_damage_flash: Visual "White-Out" for bars when taking hits
func trigger_damage_flash(node: Control):
	if not node: return
	var tween = node.create_tween()
	var original_mod = node.modulate
	
	node.modulate = Color(3, 3, 3, 1) # Overexposure
	tween.tween_property(node, "modulate", original_mod, 0.2).set_trans(Tween.TRANS_QUINT)
	
	# Add a bite-sized shake
	# Assuming trigger_ui_thud exists elsewhere or is a placeholder
	# trigger_ui_thud(node, 3.0)

func format_num(val: float) -> String:
	return FormatUtils.format_number(val)

func apply_panel_style(panel: PanelContainer):
	if not panel: return
	var style = StyleBoxFlat.new()
	style.bg_color = COLORS["panel_bg"]
	style.set_border_width_all(1)
	style.border_color = COLORS["accent"].lerp(Color.BLACK, 0.3)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	panel.add_theme_stylebox_override("panel", style)

func apply_sidebar_button_style(button: Button, is_active: bool):
	if not button: return

	var accent     := Color(0.38, 0.78, 1.00)
	var bg_active  := Color(0.10, 0.135, 0.215, 0.88)
	var bg_hover   := Color(0.08, 0.100, 0.165, 0.65)

	var style_n := StyleBoxFlat.new()
	style_n.draw_center = is_active
	style_n.bg_color = bg_active if is_active else Color(0, 0, 0, 0)
	style_n.set_border_width_all(0)
	if is_active:
		style_n.border_width_left = 3
		style_n.border_color = accent
	style_n.content_margin_left   = 14
	style_n.content_margin_right  = 8
	style_n.content_margin_top    = 6
	style_n.content_margin_bottom = 6

	var style_h := StyleBoxFlat.new()
	style_h.draw_center = true
	style_h.bg_color = bg_hover
	style_h.set_border_width_all(0)
	style_h.border_width_left = 2
	style_h.border_color = accent.darkened(0.35)
	style_h.content_margin_left   = 14
	style_h.content_margin_right  = 8
	style_h.content_margin_top    = 6
	style_h.content_margin_bottom = 6

	var style_p := style_h.duplicate()
	style_p.bg_color = bg_active
	style_p.border_width_left = 3
	style_p.border_color = accent

	button.add_theme_stylebox_override("normal",  style_n)
	button.add_theme_stylebox_override("hover",   style_h)
	button.add_theme_stylebox_override("pressed", style_p)
	button.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())

	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color",
		Color(0.90, 0.95, 1.00) if is_active else Color(0.50, 0.55, 0.68))
	button.add_theme_color_override("font_hover_color",   Color(0.78, 0.90, 1.00))
	button.add_theme_color_override("font_pressed_color", Color(1.00, 1.00, 1.00))

func apply_modal_style(panel: PanelContainer):
	if not panel: return
	var style = StyleBoxFlat.new()
	# Softer background
	style.bg_color = COLORS["background"].lightened(0.02).lerp(COLORS["accent"], 0.05)
	
	# Crisp thin border
	style.set_border_width_all(1)
	var modal_border = COLORS["accent"]
	modal_border.a = 0.4
	style.border_color = modal_border
	
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	
	# Large soft diffused shadow
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 24
	style.shadow_offset = Vector2(0, 10)
	
	panel.add_theme_stylebox_override("panel", style)

func apply_input_style(input: Control, category: String = "ops"):
	if not input: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = COLORS["panel_bg"].darkened(0.3)
	style_normal.bg_color.a = 0.8
	style_normal.set_border_width_all(1)
	style_normal.border_color = style_normal.bg_color # Hidden border natively
	style_normal.set_corner_radius_all(4)
	
	var style_focus = style_normal.duplicate()
	style_focus.border_color = accent
	style_focus.bg_color = COLORS["panel_bg"].darkened(0.2)
	
	input.add_theme_stylebox_override("normal", style_normal)
	input.add_theme_stylebox_override("focus", style_focus)

func apply_tab_style(tabs: TabContainer, category: String = "ops"):
	if not tabs: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	# Content Panel (Matches new apply_card_style)
	var style_panel = StyleBoxFlat.new()
	style_panel.bg_color = COLORS["panel_bg"].lerp(accent, 0.05)
	style_panel.bg_color.a = 0.90
	style_panel.set_border_width_all(1)
	var border_col = accent
	border_col.a = 0.3
	style_panel.border_color = border_col
	style_panel.set_corner_radius_all(6)
	style_panel.shadow_color = Color(0, 0, 0, 0.25)
	style_panel.shadow_size = 12
	style_panel.shadow_offset = Vector2(0, 4)
	
	# Tab Selected (Matches panel background to look seamless)
	var style_selected = StyleBoxFlat.new()
	style_selected.bg_color = style_panel.bg_color
	style_selected.set_border_width_all(1)
	style_selected.border_color = style_selected.bg_color # Seamless blend
	style_selected.border_width_top = 2
	style_selected.border_color = accent
	style_selected.corner_radius_top_left = 4
	style_selected.corner_radius_top_right = 4
	style_selected.content_margin_left = 16
	style_selected.content_margin_right = 16
	
	# Tab Unselected
	var style_unselected = StyleBoxFlat.new()
	style_unselected.bg_color = COLORS["sidebar"].darkened(0.1)
	style_unselected.set_border_width_all(0)
	style_unselected.corner_radius_top_left = 4
	style_unselected.corner_radius_top_right = 4
	style_unselected.content_margin_left = 12
	style_unselected.content_margin_right = 12
	
	# Tab Hover
	var style_hover = style_unselected.duplicate()
	style_hover.bg_color = COLORS["sidebar"].lightened(0.05)
	style_hover.border_width_top = 2
	style_hover.border_color = accent.lightened(0.3)
	
	# Tab Focus/Disabled (Safety)
	var style_focus = style_selected.duplicate()
	style_focus.draw_center = false
	
	tabs.add_theme_stylebox_override("tab_selected", style_selected)
	tabs.add_theme_stylebox_override("tab_unselected", style_unselected)
	tabs.add_theme_stylebox_override("tab_hovered", style_hover)
	tabs.add_theme_stylebox_override("tab_focus", style_focus)
	tabs.add_theme_stylebox_override("tab_disabled", style_unselected)
	tabs.add_theme_stylebox_override("panel", style_panel)
	
	tabs.add_theme_color_override("font_selected_color", Color.WHITE)
	tabs.add_theme_color_override("font_hovered_color", Color.WHITE)
	tabs.add_theme_color_override("font_unselected_color", COLORS["text_dim"])
	
	# Tab Sizing
	tabs.add_theme_constant_override("side_margin", 10)
	tabs.add_theme_font_size_override("font_size", 13)

func apply_sharp_button_style(button: Button, category: String = "ops"):
	if not button: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = COLORS["sidebar"].lerp(accent, 0.05)
	style_normal.set_border_width_all(1)
	var normal_border = accent
	normal_border.a = 0.4
	style_normal.border_color = normal_border
	style_normal.set_corner_radius_all(0) # Keep it sharp!
	
	# Added Padding to increase size
	style_normal.content_margin_left = 16
	style_normal.content_margin_right = 16
	style_normal.content_margin_top = 8
	style_normal.content_margin_bottom = 8
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = accent.lerp(Color.BLACK, 0.3)
	style_hover.border_color = accent
	
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = accent
	style_pressed.border_color = Color.WHITE
	
	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.15, 0.15, 0.15, 0.8)
	style_disabled.border_color = Color(0.3, 0.3, 0.3, 0.5)
	
	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	button.add_theme_stylebox_override("disabled", style_disabled)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 12)

# --- ANIMATION HELPERS (Iter8 Rich Aesthetics) ---

func add_hover_scale(control: Control, scale_amount: float = 1.05):
	if not control: return
	control.pivot_offset = control.size / 2
	
	control.mouse_entered.connect(func():
		var tween = control.create_tween()
		tween.tween_property(control, "scale", Vector2(scale_amount, scale_amount), 0.15).set_trans(Tween.TRANS_SINE)
	)
	control.mouse_exited.connect(func():
		var tween = control.create_tween()
		tween.tween_property(control, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_SINE)
	)

func add_pulse_glow(control: Control, category: String = "ops"):
	if not control: return
	var color = CATEGORY_COLORS.get(category, COLORS["accent_bright"])
	
	var tween = control.create_tween().set_loops()
	tween.tween_property(control, "modulate", color.lightened(0.2), 0.8).set_trans(Tween.TRANS_SINE)
	tween.tween_property(control, "modulate", Color.WHITE, 0.8).set_trans(Tween.TRANS_SINE)
	return tween

# --- PHASE 28: TACTILE INSTRUMENT HELPERS ---

## trigger_ui_thud: Localized screen shake for physical weight
func trigger_ui_thud(node: Control, intensity: float = 4.0):
	if not node: return
	var original_pos = node.position
	var tween = node.create_tween()
	
	# High-frequency decay shake
	for i in range(4):
		var offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		tween.tween_property(node, "position", original_pos + offset, 0.03)
		intensity *= 0.5
	
	tween.tween_property(node, "position", original_pos, 0.05)

## apply_instrument_style: Styles buttons as physical mechanical toggles
func apply_instrument_style(button: Button, category: String = "ops"):
	if not button: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.1, 0.1, 0.15)
	style_normal.set_border_width_all(1)
	style_normal.border_color = Color(0.3, 0.3, 0.4)
	
	# Physical "Bevel" effect
	style_normal.border_width_left = 3
	style_normal.border_color = accent.lerp(Color.WHITE, 0.2)
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = accent.lerp(Color.BLACK, 0.7)
	style_hover.border_width_left = 5
	style_hover.border_color = accent
	
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = accent
	style_pressed.border_width_left = 8
	style_pressed.border_color = Color.WHITE
	
	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	# Monospace for "Terminal" look
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color(0.8, 0.8, 1.0))

## apply_segmented_font: Makes labels look like LED readouts
func apply_segmented_font(label: Control, color: Color = Color.CYAN):
	if label is Label or label is RichTextLabel:
		label.add_theme_color_override("font_color", color)
		label.add_theme_font_size_override("font_size", 10)
		# Simulating glow via modulate/shadow
		label.modulate = color.lightened(0.3)
		
		if label is Label:
			label.uppercase = true

# --- PHASE 29: FLOW & ENTROPY HELPERS ---

## spawn_data_packet: Visualizes production flow to the HUD
func spawn_data_packet(start_node: Control, target_pos: Vector2, color: Color = Color.CYAN):
	if not start_node: return
	
	var packet = ColorRect.new()
	packet.custom_minimum_size = Vector2(4, 4)
	packet.color = color
	packet.modulate.a = 0.8
	
	# Add to the main scene to ensure it stays on top of all UI
	var root = start_node.get_tree().root.get_child(0)
	root.add_child(packet)
	
	packet.global_position = start_node.global_position + (start_node.size / 2.0)
	
	var tween = packet.create_tween()
	# High-velocity "pop" out then quintic ease toward target
	var mid_offset = Vector2(randf_range(-50, 50), randf_range(-50, 50))
	tween.tween_property(packet, "global_position", packet.global_position + mid_offset, 0.1).set_trans(Tween.TRANS_QUINT)
	tween.tween_property(packet, "global_position", target_pos, 0.6).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(packet, "scale", Vector2(0.2, 0.2), 0.6)
	tween.tween_callback(func():
		packet_landed.emit(color)
		packet.queue_free()
	)

## trigger_mechanical_bash: Heavy, low-frequency shake for industrial events
func trigger_mechanical_bash(node: Control, intensity: float = 12.0):
	if not node: return
	var original_pos = node.position
	var tween = node.create_tween()
	
	# Deep, reverberating thud
	for i in range(5):
		var offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		tween.tween_property(node, "position", original_pos + offset, 0.05).set_trans(Tween.TRANS_SINE)
		intensity *= 0.6
	
	tween.tween_property(node, "position", original_pos, 0.1)

# --- PHASE 30: TACTICAL DECK HELPERS ---

## trigger_circuit_surge: Visual pulse when snapping modules
func trigger_circuit_surge(node: Control, color: Color = Color.CYAN):
	if not node: return
	
	var tween = node.create_tween()
	node.modulate = color.lightened(0.5)
	node.scale = Vector2(1.1, 1.1)
	
	tween.tween_property(node, "modulate", Color.WHITE, 0.2).set_trans(Tween.TRANS_QUINT)
	tween.parallel().tween_property(node, "scale", Vector2(1.0, 1.0), 0.2)

## trigger_system_glitch: Visceral feedback for combat damage
func trigger_system_glitch(node: Control, intensity: float = 8.0):
	if not node: return
	var original_pos = node.position
	var tween = node.create_tween()
	
	# High-frequency jitter + Color flickering
	for i in range(6):
		var offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		tween.tween_property(node, "position", original_pos + offset, 0.02)
		
		# Alternating red-tint flicker
		if i % 2 == 0:
			tween.parallel().tween_property(node, "modulate", Color(1.5, 0.5, 0.5), 0.02)
		else:
			tween.parallel().tween_property(node, "modulate", Color.WHITE, 0.02)
		
		intensity *= 0.8
	
	tween.tween_property(node, "position", original_pos, 0.05)
	tween.parallel().tween_property(node, "modulate", Color.WHITE, 0.05)

## trigger_tab_alert: Rhythmic pulse + Visual marker for navigation headers
func trigger_tab_alert(tabs: TabContainer, tab_idx: int, active: bool = true, color: Color = Color.CYAN):
	if not tabs or tab_idx < 0 or tab_idx >= tabs.get_tab_count(): return
	
	var title = tabs.get_tab_title(tab_idx)
	var marker = "(!) "
	
	# Handle Title Prefixing (Audit v16.4: Clean text marker)
	if active:
		if not title.begins_with(marker):
			tabs.set_tab_title(tab_idx, marker + title)
	else:
		if title.begins_with(marker):
			tabs.set_tab_title(tab_idx, title.replace(marker, ""))
	
	# 1. Manage Active Alerts List
	var active_alerts = tabs.get_meta("active_tab_alerts", [])
	if active:
		if not tab_idx in active_alerts:
			active_alerts.append(tab_idx)
	else:
		active_alerts.erase(tab_idx)
	tabs.set_meta("active_tab_alerts", active_alerts)
	
	# 2. Global Pulse Disabled (Audit v16.4: Reduced noise)
	var bar = tabs.get_tab_bar()
	bar.modulate = Color.WHITE
	# Removed pulse_key / tween logic entirely
# --- PHASE 47: DIEGETIC & HOLOGRAPHIC HELPERS ---

## apply_holographic_projection: Minimalist border-only HUD style
func apply_holographic_projection(panel: Control, category: String = "ops"):
	if not panel: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0) # FULL TRANSPARENCY
	style.draw_center = false
	
	# THEMATIC: Glowing minimalist borders
	style.set_border_width_all(1)
	style.border_color = accent
	# High-frequency "Energy" glow via border blend
	style.border_blend = true
	
	# Slightly rounded for modern sci-fi
	style.set_corner_radius_all(2)
	
	# Shadow behaves more like a "Halo" in 0% opacity backgrounds
	style.shadow_color = Color(accent, 0.2)
	style.shadow_size = 4
	
	panel.add_theme_stylebox_override("panel", style)
	return style

## apply_locked_overlay: Creates and manages a visual "LOCKED" state for Cards
func apply_locked_overlay(card: Control, item_name: String, message: String, is_locked: bool, tech_id: String = "", category: String = "ops"):
	if not card: return
	
	var overlay_name = "LockedOverlay"
	var overlay = card.get_node_or_null(overlay_name)
	
	if not is_locked:
		if overlay: overlay.hide()
		return
	
	if not overlay:
		# 1. Create Transparent Shadow Panel
		overlay = ColorRect.new()
		overlay.name = overlay_name
		overlay.color = Color(0, 0, 0, 1.0) # Full dark overlay
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_STOP # Block clicks
		card.add_child(overlay)
		
		# 2. Add Centered Containers
		var center = CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.add_child(center)
		
		var vbox = VBoxContainer.new()
		vbox.name = "VBox"
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.custom_minimum_size.x = card.custom_minimum_size.x - 8
		center.add_child(vbox)
		
		var name_lbl = Label.new()
		name_lbl.name = "ItemNameLabel"
		name_lbl.text = item_name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 12) # Reduced for better fit
		
		var title_col = CATEGORY_COLORS.get(category, Color(0.1, 0.8, 1.0))
		name_lbl.add_theme_color_override("font_color", title_col)
		
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD # Standard word wrap only
		vbox.add_child(name_lbl)
		
		var lock_lbl = Label.new()
		lock_lbl.name = "LockHeading"
		lock_lbl.text = "LOCKED"
		lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_lbl.add_theme_font_size_override("font_size", 14) # Reduced from 18
		lock_lbl.add_theme_color_override("font_color", Color.WHITE)
		vbox.add_child(lock_lbl)
		
		var req_lbl = RichTextLabel.new()
		req_lbl.name = "ReqLabel"
		req_lbl.bbcode_enabled = true
		req_lbl.fit_content = true
		req_lbl.scroll_active = false
		req_lbl.mouse_filter = Control.MOUSE_FILTER_STOP 
		req_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		req_lbl.add_theme_font_size_override("normal_font_size", 9) 
		req_lbl.add_theme_color_override("default_color", Color(1.0, 0.4, 0.4))
		req_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		req_lbl.add_theme_constant_override("line_separation", 2)
		vbox.add_child(req_lbl)
		
		req_lbl.meta_clicked.connect(func(meta):
			if str(meta).begins_with("research:"):
				var tid = str(meta).replace("research:", "")
				research_navigation_requested.emit(tid)
		)
		
		_update_locked_message(req_lbl, message, tech_id)
	else:
		overlay.show()
		var name_lbl = overlay.find_child("ItemNameLabel", true, false)
		if name_lbl: 
			name_lbl.text = item_name
			var title_col = CATEGORY_COLORS.get(category, Color(0.1, 0.8, 1.0))
			name_lbl.add_theme_color_override("font_color", title_col)
		
		var req_lbl = overlay.find_child("ReqLabel", true, false)
		if req_lbl: 
			_update_locked_message(req_lbl, message, tech_id)

func _update_locked_message(lbl: RichTextLabel, message: String, tech_id: String):
	if message.to_upper().begins_with("RESEARCH:") and tech_id != "":
		# Handle both "RESEARCH: Name" and "RESEARCH: NAME"
		var tech_name = message.substr(9).strip_edges() # Skip "RESEARCH:"
		lbl.text = "[center]RESEARCH:\n[url=research:%s][color=#ffdd22][u]%s[/u][/color][/url][/center]" % [tech_id, tech_name]
	else:
		lbl.text = "[center]%s[/center]" % message

func _process(delta):
	# Global UI animations or packet handling can go here
	pass
