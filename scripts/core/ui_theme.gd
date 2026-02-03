extends Node

signal packet_landed(color)

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
	"ops": Color(1.0, 0.6, 0.2),         # Orange
	"engineering": Color(0.2, 0.8, 1.0),   # Cyan
	"infrastructure": Color(0.4, 0.9, 0.4),# Green
	"combat": Color(1.0, 0.3, 0.3),        # Red
	"inventory": Color(1.0, 0.8, 0.2),     # Gold
	"research": Color(0.9, 0.4, 1.0),      # Pink/Purple
	"shipyard": Color(0.3, 0.5, 1.0),      # Blue
	"mission": Color(0.2, 1.0, 0.6)        # Teal/Emerald
}

func setup_page_background(page: Control):
	pass

func apply_card_style(panel: Control, category: String = "ops") -> StyleBoxFlat:
	if not panel: return null
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	var style = StyleBoxFlat.new()
	style.bg_color = COLORS["panel_bg"]
	style.bg_color.a = 0.85 # Slight transparency for glass feel
	style.draw_center = true
	
	# THEMATIC: No even borders. Left and Right are thin, Top is accented.
	style.set_border_width_all(1)
	style.border_width_left = 2
	style.border_width_top = 4 # Heavy top bar
	style.border_color = accent.lerp(Color.BLACK, 0.4)
	
	# Corner Braces Simulation (using border_blend and colors)
	style.border_blend = true
	style.border_color = accent
	
	# Rounded but sharp (Mechanical feel)
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 0
	style.corner_radius_bottom_left = 4
	
	# Shadow for depth
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 8
	style.shadow_offset = Vector2(4, 4)
	
	# Subtle Skew for "Screen" feel
	# style.skew = Vector2(0.02, 0) # Removed as it can cause layout issues in deep sub-panels
	
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

func apply_premium_button_style(button: Button, category: String = "ops"):
	if not button: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = accent.lerp(Color.BLACK, 0.6)
	style_normal.set_border_width_all(1)
	style_normal.border_color = accent
	style_normal.corner_radius_top_left = 4
	style_normal.corner_radius_top_right = 4
	style_normal.corner_radius_bottom_right = 4
	style_normal.corner_radius_bottom_left = 4
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = accent.lerp(Color.BLACK, 0.4)
	style_hover.border_color = accent.lightened(0.2)
	style_hover.shadow_color = accent.lerp(Color.BLACK, 0.5)
	style_hover.shadow_size = 2
	
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = accent
	
	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.2, 0.2, 0.2)
	button.add_theme_stylebox_override("disabled", style_disabled)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 13)

func apply_progress_bar_style(pb: ProgressBar, category: String = "ops"):
	if not pb: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	var style_bg = StyleBoxFlat.new()
	style_bg.bg_color = COLORS["background"].lightened(0.05)
	style_bg.corner_radius_top_left = 2
	style_bg.corner_radius_top_right = 2
	style_bg.corner_radius_bottom_right = 2
	style_bg.corner_radius_bottom_left = 2
	style_bg.set_border_width_all(1)
	style_bg.border_color = Color(0,0,0,0.5)
	
	var style_fill = StyleBoxFlat.new()
	style_fill.bg_color = accent
	# Subtle Glossy Gradient
	style_fill.bg_color = accent.lerp(Color.WHITE, 0.1)
	style_fill.border_width_top = 1
	style_fill.border_color = Color(1, 1, 1, 0.3) # Highlight
	
	style_fill.corner_radius_top_left = 2
	style_fill.corner_radius_top_right = 2
	style_fill.corner_radius_bottom_right = 2
	style_fill.corner_radius_bottom_left = 2
	
	pb.add_theme_stylebox_override("background", style_bg)
	pb.add_theme_stylebox_override("fill", style_fill)

static func format_num(val: float) -> String:
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
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = COLORS["sidebar"] if not is_active else COLORS["accent"]
	style_normal.draw_center = true
	style_normal.set_border_width_all(1)
	style_normal.border_color = COLORS["accent"] if is_active else Color.TRANSPARENT
	style_normal.content_margin_left = 15
	
	button.add_theme_stylebox_override("normal", style_normal)
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = COLORS["accent"].lerp(Color.BLACK, 0.5)
	button.add_theme_stylebox_override("hover", style_hover)
	
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = COLORS["accent"]
	button.add_theme_stylebox_override("pressed", style_pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	if is_active:
		button.add_theme_color_override("font_color", Color.WHITE)
	else:
		button.add_theme_color_override("font_color", COLORS["text_dim"])

func apply_modal_style(panel: PanelContainer):
	if not panel: return
	var style = StyleBoxFlat.new()
	style.bg_color = COLORS["background"].lightened(0.02)
	style.set_border_width_all(2)
	style.border_color = COLORS["accent"]
	style.border_blend = true
	
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	
	# Heavy Shadow for depth
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 20
	style.shadow_offset = Vector2(0, 10)
	
	panel.add_theme_stylebox_override("panel", style)

func apply_tab_style(tabs: TabContainer, category: String = "ops"):
	if not tabs: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	# Tab Selected (Matches panel background)
	var style_selected = StyleBoxFlat.new()
	style_selected.bg_color = COLORS["panel_bg"]
	style_selected.set_border_width_all(1)
	style_selected.border_color = COLORS["panel_bg"] # Seamless
	style_selected.border_width_top = 2
	style_selected.border_color = accent
	style_selected.corner_radius_top_left = 4
	style_selected.corner_radius_top_right = 4
	style_selected.content_margin_left = 12
	style_selected.content_margin_right = 12
	
	# Tab Unselected
	var style_unselected = StyleBoxFlat.new()
	style_unselected.bg_color = COLORS["sidebar"].lerp(Color.BLACK, 0.2)
	style_unselected.set_border_width_all(1)
	style_unselected.border_color = Color.TRANSPARENT
	style_unselected.corner_radius_top_left = 4
	style_unselected.corner_radius_top_right = 4
	style_unselected.content_margin_left = 10
	style_unselected.content_margin_right = 10
	
	# Tab Hover - Enhanced Tactile Glow
	var style_hover = style_unselected.duplicate()
	style_hover.bg_color = COLORS["sidebar"].lightened(0.05)
	style_hover.border_width_top = 2
	style_hover.border_color = accent.lerp(Color.WHITE, 0.3)
	style_hover.border_blend = true
	
	# Tab Focus/Disabled (Safety)
	var style_focus = style_selected.duplicate()
	style_focus.draw_center = false # No double-center
	
	# Content Panel (The dashboard background)
	var style_panel = StyleBoxFlat.new()
	style_panel.bg_color = COLORS["panel_bg"]
	style_panel.set_border_width_all(1)
	style_panel.border_color = accent.lerp(Color.BLACK, 0.5)
	style_panel.border_width_top = 2
	style_panel.border_color = accent
	style_panel.border_blend = true
	style_panel.shadow_color = Color(0, 0, 0, 0.3)
	style_panel.shadow_size = 10
	style_panel.shadow_offset = Vector2(0, 4)
	
	tabs.add_theme_stylebox_override("tab_selected", style_selected)
	tabs.add_theme_stylebox_override("tab_unselected", style_unselected)
	tabs.add_theme_stylebox_override("tab_hovered", style_hover)
	tabs.add_theme_stylebox_override("tab_focus", style_focus)
	tabs.add_theme_stylebox_override("tab_disabled", style_unselected)
	tabs.add_theme_stylebox_override("panel", style_panel)
	
	tabs.add_theme_color_override("font_selected_color", Color.WHITE)
	tabs.add_theme_color_override("font_hovered_color", Color.WHITE)
	tabs.add_theme_color_override("font_unselected_color", Color(0.7, 0.7, 0.7))
	
	# Tab Sizing
	tabs.add_theme_constant_override("side_margin", 10)
	tabs.add_theme_color_override("font_unselected_color", COLORS["text_dim"])
	tabs.add_theme_font_size_override("font_size", 13)

func apply_sharp_button_style(button: Button, category: String = "ops"):
	if not button: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = accent.lerp(Color.BLACK, 0.7)
	style_normal.set_border_width_all(1)
	style_normal.border_color = accent.lerp(Color.BLACK, 0.3)
	style_normal.corner_radius_top_left = 0
	style_normal.corner_radius_top_right = 0
	style_normal.corner_radius_bottom_right = 0
	style_normal.corner_radius_bottom_left = 0
	
	# Added Padding to increase size
	style_normal.content_margin_left = 16
	style_normal.content_margin_right = 16
	style_normal.content_margin_top = 8
	style_normal.content_margin_bottom = 8
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = accent.lerp(Color.BLACK, 0.5)
	style_hover.border_color = accent
	
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = accent
	style_pressed.border_color = Color.WHITE
	
	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.1, 0.1, 0.1)
	style_disabled.border_color = Color(0.2, 0.2, 0.2)
	
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
		label.add_theme_font_size_override("font_size", 16)
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

func _process(delta):
	# Global UI animations or packet handling can go here
	pass
