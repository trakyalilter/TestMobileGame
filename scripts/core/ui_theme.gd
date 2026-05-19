extends Node

signal packet_landed(color)
signal notification_requested(text: String, color: Color) # Feature v66.1
signal research_navigation_requested(tech_id: String)
# Emitted when the player switches card frame style in Sys Config so every
# live CardChrome overlay repaints without a page rebuild.
signal chrome_changed

# Card frame / "soul" chrome styles, selectable in Sys Config.
# Default is INDUSTRIAL (matches the diegetic engineering-console copy).
const CHROME_INDUSTRIAL := 0
const CHROME_HOLOGRAPHIC := 1
const CHROME_PRECURSOR := 2

func get_card_chrome() -> int:
	return int(GameState.game_settings.get("card_chrome", CHROME_INDUSTRIAL))

# Inline Lira currency icon for BBCode/RichText contexts ONLY (plain Labels
# and Buttons can't embed images — those use the word "Liras"). Single source
# of truth: tweak size/path/tint here. 14px ≈ inline body text height.
const LIRA_ICON_BB := "[img=14 color=#ffd14c]res://assets/icons/lira.svg[/img]"

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
	# Solid console panel, faintly accent-tinted (reads less "translucent
	# overlay", more "physical module" — matches the recessed bar track).
	style.bg_color = COLORS["panel_bg"].lerp(accent, 0.06)
	style.bg_color.a = 0.96
	style.draw_center = true

	# Faint uniform 1px hairline only. The CardChrome overlay now owns the
	# lit-edge / frame motif, so a thicker StyleBox top border just stacks
	# behind it and reads as one over-thick accent band.
	style.set_border_width_all(1)
	var border_col: Color = accent
	border_col.a = 0.22
	style.border_color = border_col
	style.border_blend = false

	# Square corners: the CardChrome overlay (always on) draws sharp corner
	# hardware / a chamfered octagon / etched frames — a rounded StyleBox
	# corner would poke out behind those and read as a defect.
	style.set_corner_radius_all(0)

	# Depth shadow so cards separate cleanly in the grid.
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 3)

	panel.add_theme_stylebox_override("panel", style)

	# Procedural "soul" chrome layer (corner hardware / holo frame / etched
	# filigree) painted over the flat StyleBox. One overlay per card, tinted
	# by the same accent — switches live with the Sys Config setting.
	_attach_chrome(panel, accent)
	return style

# Adds (or refreshes) the CardChrome overlay on a styled card. Idempotent:
# re-applying a style on the same panel just updates the accent.
func _attach_chrome(panel: Control, accent: Color) -> void:
	var existing := panel.get_node_or_null("_CardChrome")
	if existing:
		existing.accent = accent
		existing.queue_redraw()
		return
	var chrome := CardChrome.new()
	chrome.name = "_CardChrome"
	chrome.accent = accent
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(chrome)
	# Stay the last sibling so the ornament paints above card content.
	panel.move_child(chrome, panel.get_child_count() - 1)

func apply_diegetic_header(panel: Control, category: String = "ops"):
	if not panel: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	var style = StyleBoxFlat.new()
	# Dark accent-tinted title bar with a crisp accent underline — a
	# "command bar" that caps the card. Square top corners to match the
	# square (chrome-framed) panel so the header sits perfectly flush.
	style.bg_color = accent.lerp(Color.BLACK, 0.82)
	style.border_width_bottom = 2
	style.border_color = accent
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
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
	
	# Recessed control with a lit accent top edge — same vocabulary as the
	# card frame and the bar fill, so the whole card reads as one system.
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = COLORS["sidebar"].lerp(accent, 0.06)
	style_normal.set_border_width_all(1)
	style_normal.border_width_top = 2
	var normal_border: Color = accent
	normal_border.a = 0.45
	style_normal.border_color = normal_border
	style_normal.set_corner_radius_all(4)

	# Hover lights the frame and adds a soft ACCENT halo (not a black
	# drop-shadow) — the bar's glow language.
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = accent.lerp(Color.BLACK, 0.32)
	style_hover.border_color = accent
	style_hover.shadow_color = Color(accent.r, accent.g, accent.b, 0.35)
	style_hover.shadow_size = 5
	style_hover.shadow_offset = Vector2(0, 0)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = accent
	style_pressed.border_color = Color.WHITE

	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.12, 0.13, 0.16, 0.85)
	style_disabled.border_color = Color(0.3, 0.3, 0.34, 0.45)
	button.add_theme_stylebox_override("disabled", style_disabled)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	# Bright accents (cyan/gold) wash out white text when pressed — use a
	# near-black label so the pressed state stays readable.
	button.add_theme_color_override("font_pressed_color", Color(0.05, 0.06, 0.08))
	button.add_theme_color_override("font_disabled_color", Color(0.45, 0.46, 0.5))
	button.add_theme_font_size_override("font_size", 13)

func apply_progress_bar_style(pb: ProgressBar, category: String = "ops"):
	if not pb: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])

	# Recessed "channel": near-black, faint accent-tinted edge, inner pad so
	# the fill nests cleanly inside the border instead of overdrawing it.
	var style_bg = StyleBoxFlat.new()
	style_bg.bg_color = Color(0.03, 0.04, 0.07, 0.95)
	style_bg.set_border_width_all(1)
	var edge: Color = accent.darkened(0.55)
	edge.a = 0.55
	style_bg.border_color = edge
	style_bg.set_corner_radius_all(3)
	style_bg.content_margin_left = 2
	style_bg.content_margin_right = 2
	style_bg.content_margin_top = 2
	style_bg.content_margin_bottom = 2

	# Solid accent fill with a lit top/leading edge (fakes a light source)
	# and a soft accent halo — the flat-glow look used across the UI.
	var style_fill = StyleBoxFlat.new()
	style_fill.bg_color = accent
	style_fill.set_corner_radius_all(2)
	style_fill.border_width_top = 1
	style_fill.border_width_right = 2
	var lit: Color = accent.lightened(0.5)
	lit.a = 0.9
	style_fill.border_color = lit
	style_fill.shadow_color = Color(accent.r, accent.g, accent.b, 0.4)
	style_fill.shadow_size = 5

	pb.add_theme_stylebox_override("background", style_bg)
	pb.add_theme_stylebox_override("fill", style_fill)

	# Percentage readout: smaller, accent-tinted, with a dark outline so it
	# stays legible whether it sits over the fill or the empty channel.
	pb.add_theme_color_override("font_color", accent.lightened(0.6))
	pb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	pb.add_theme_constant_override("outline_size", 3)
	pb.add_theme_font_size_override("font_size", 10)

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
		
		# 2. Full-width padded container. A CenterContainer shrinks to its
		#    content, so long research names ("Lightweight Alloys") had no
		#    width to wrap against and overflowed/clipped the card. A
		#    MarginContainer forces the text block to the real card width.
		var pad = MarginContainer.new()
		pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pad.add_theme_constant_override("margin_left", 6)
		pad.add_theme_constant_override("margin_right", 6)
		pad.add_theme_constant_override("margin_top", 4)
		pad.add_theme_constant_override("margin_bottom", 4)
		overlay.add_child(pad)

		var vbox = VBoxContainer.new()
		vbox.name = "VBox"
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER  # vertical centering
		pad.add_child(vbox)

		var name_lbl = Label.new()
		name_lbl.name = "ItemNameLabel"
		name_lbl.text = item_name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 12) # Reduced for better fit
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var title_col = CATEGORY_COLORS.get(category, Color(0.1, 0.8, 1.0))
		name_lbl.add_theme_color_override("font_color", title_col)

		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(name_lbl)

		var lock_lbl = Label.new()
		lock_lbl.name = "LockHeading"
		lock_lbl.text = "LOCKED"
		lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_lbl.add_theme_font_size_override("font_size", 14) # Reduced from 18
		lock_lbl.add_theme_color_override("font_color", Color.WHITE)
		lock_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(lock_lbl)

		var req_lbl = RichTextLabel.new()
		req_lbl.name = "ReqLabel"
		req_lbl.bbcode_enabled = true
		req_lbl.fit_content = true       # height-to-content; width from parent
		req_lbl.scroll_active = false
		req_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		req_lbl.add_theme_font_size_override("normal_font_size", 9)
		req_lbl.add_theme_color_override("default_color", Color(1.0, 0.4, 0.4))
		req_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		req_lbl.add_theme_constant_override("line_separation", 2)
		req_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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

# --- ACTIVITY CARD OVERHAUL (additive; used only by the gathering /
# processing widgets -- does NOT touch the shared inject_diegetic_header /
# apply_card_style paths the other 15 card types rely on) ---

## inject_activity_header: one compact command row -- [icon | name | Lv badge]
## -- replacing the name + separate centred level line. Reparents the
## existing NameLabel + LevelLabel so update_state() keeps driving them.
func inject_activity_header(card: PanelContainer, category: String, icon_tex: Texture2D) -> PanelContainer:
	var margin_cont = card.get_node_or_null("MarginContainer")
	if not margin_cont: return null
	var vbox = margin_cont.get_node_or_null("VBoxContainer")
	if not vbox: return null
	var name_lbl = vbox.get_node_or_null("NameLabel")
	var lvl_lbl = vbox.get_node_or_null("LevelLabel")
	if not name_lbl: return null

	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])

	# Uniform side inset so header / IO panels / button / bar share one
	# aligned column. Top stays 0 so the header band sits flush to the card.
	margin_cont.add_theme_constant_override("margin_top", 0)
	margin_cont.add_theme_constant_override("margin_left", 8)
	margin_cont.add_theme_constant_override("margin_right", 8)
	margin_cont.add_theme_constant_override("margin_bottom", 8)
	vbox.add_theme_constant_override("separation", 7)

	var header_panel = PanelContainer.new()
	header_panel.name = "ActivityHeader"
	header_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(header_panel)
	vbox.move_child(header_panel, 0)

	var hmargin = MarginContainer.new()
	hmargin.add_theme_constant_override("margin_left", 8)
	hmargin.add_theme_constant_override("margin_right", 8)
	hmargin.add_theme_constant_override("margin_top", 5)
	hmargin.add_theme_constant_override("margin_bottom", 5)
	hmargin.mouse_filter = Control.MOUSE_FILTER_PASS
	header_panel.add_child(hmargin)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	hmargin.add_child(row)

	if icon_tex:
		var icon = TextureRect.new()
		icon.texture = icon_tex
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)

	name_lbl.get_parent().remove_child(name_lbl)
	row.add_child(name_lbl)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.clip_text = true
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_font_size_override("font_size", 13)

	if lvl_lbl:
		lvl_lbl.get_parent().remove_child(lvl_lbl)
		var badge = PanelContainer.new()
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bm = MarginContainer.new()
		bm.add_theme_constant_override("margin_left", 6)
		bm.add_theme_constant_override("margin_right", 6)
		bm.add_theme_constant_override("margin_top", 1)
		bm.add_theme_constant_override("margin_bottom", 1)
		badge.add_child(bm)
		bm.add_child(lvl_lbl)
		lvl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lvl_lbl.add_theme_font_size_override("font_size", 10)
		lvl_lbl.add_theme_color_override("font_color", accent.lightened(0.4))
		var bstyle = StyleBoxFlat.new()
		bstyle.bg_color = accent.lerp(Color.BLACK, 0.78)
		bstyle.set_corner_radius_all(3)
		bstyle.set_border_width_all(1)
		var bcol: Color = accent
		bcol.a = 0.5
		bstyle.border_color = bcol
		badge.add_theme_stylebox_override("panel", bstyle)
		row.add_child(badge)

	apply_diegetic_header(header_panel, category)
	return header_panel

## wrap_in_io_panel: pull a label into a captioned compartment. kind is one
## of "yield" / "output" (the payoff -- reads as the hero) or "input" (recedes).
## The caption turns a floating text box into a labelled instrument readout.
func wrap_in_io_panel(label: Control, category: String, kind: String) -> PanelContainer:
	if not label: return null
	var parent = label.get_parent()
	if not parent: return null
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	var idx = label.get_index()
	var emphasis: bool = kind != "input"

	var panel = PanelContainer.new()
	panel.name = label.name + "Panel"
	panel.size_flags_horizontal = Control.SIZE_FILL
	# Size to content -- a forced vexpand is what hollowed the sparse cards.
	parent.add_child(panel)
	parent.move_child(panel, idx)

	var m = MarginContainer.new()
	m.add_theme_constant_override("margin_left", 9)
	m.add_theme_constant_override("margin_right", 9)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(m)

	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	m.add_child(col)

	var cap = Label.new()
	cap.text = ({"yield": "YIELD", "output": "OUTPUT", "input": "INPUTS"}).get(kind, kind.to_upper())
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 8)
	cap.add_theme_constant_override("outline_size", 0)
	if emphasis:
		var cc: Color = accent.lightened(0.35)
		cc.a = 0.75
		cap.add_theme_color_override("font_color", cc)
	else:
		cap.add_theme_color_override("font_color", Color(0.52, 0.54, 0.60))
	col.add_child(cap)

	label.get_parent().remove_child(label)
	col.add_child(label)
	if label is RichTextLabel:
		label.add_theme_font_size_override("normal_font_size", 14 if emphasis else 11)
		label.add_theme_color_override("default_color",
			Color(0.96, 0.97, 1.0) if emphasis else Color(0.66, 0.68, 0.74))

	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(4)
	if emphasis:
		style.bg_color = accent.lerp(Color.BLACK, 0.82)
		style.set_border_width_all(1)
		style.border_width_left = 3
		var bc: Color = accent
		bc.a = 0.9
		style.border_color = bc
		style.shadow_color = Color(accent.r, accent.g, accent.b, 0.16)
		style.shadow_size = 6
	else:
		style.bg_color = Color(0.0, 0.0, 0.0, 0.22)
		style.set_border_width_all(1)
		style.border_color = Color(1, 1, 1, 0.05)
	panel.add_theme_stylebox_override("panel", style)
	return panel

## pin_card_footer: make every card in a grid row the same height and put the
## flexible gap just before `before_node_name`, so everything from that node
## down is bottom-aligned across cards regardless of how tall the region above
## it grows. Pass the REFINE divider for processing (so INPUTS floats, but
## REFINE/OUTPUT/footer all line up) or the Button for the simple cards.
func pin_card_footer(card: PanelContainer, before_node_name: String = "Button") -> void:
	if not card: return
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox = card.get_node_or_null("MarginContainer/VBoxContainer")
	if not vbox: return
	var pivot = vbox.get_node_or_null(before_node_name)
	if not pivot:
		pivot = vbox.get_node_or_null("Button")
	if not pivot: return
	if vbox.get_node_or_null("FooterSpacer"): return
	var spacer = Control.new()
	spacer.name = "FooterSpacer"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(0, 2)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)
	vbox.move_child(spacer, pivot.get_index())

# --- MODULE TYPE ICON / DAMAGE-FAMILY (shared by the armory tiles and the
# equipped-slot widgets so they read with one visual language) ---

var _module_icon_cache: Dictionary = {}

func weapon_family(stats: Dictionary) -> String:
	if float(stats.get("atk_energy", 0)) > 0.0:
		return "energy"
	if float(stats.get("atk_explosive", 0)) > 0.0:
		return "explosive"
	return "kinetic"

func weapon_family_color(stats: Dictionary) -> Color:
	match weapon_family(stats):
		"energy": return Color(0.32, 0.80, 1.0)
		"explosive": return Color(1.0, 0.45, 0.30)
		_: return Color(0.92, 0.66, 0.32)

func weapon_family_tag(stats: Dictionary) -> String:
	match weapon_family(stats):
		"energy": return "NRG"
		"explosive": return "EXP"
		_: return "KIN"

func module_type_icon(slot_type: String, stats: Dictionary) -> Texture2D:
	var key = slot_type
	if slot_type == "weapon":
		key = "weapon_" + weapon_family(stats)
	var valid = ["weapon_kinetic", "weapon_energy", "weapon_explosive",
		"shield", "armor", "engine", "battery", "reactor", "sensor",
		"cooling", "ammo", "consumable"]
	if not (key in valid):
		key = "module"
	if key in _module_icon_cache:
		return _module_icon_cache[key]
	var tex = load("res://assets/icons/modules/%s.svg" % key) as Texture2D
	_module_icon_cache[key] = tex
	return tex

func _process(delta):
	# Global UI animations or packet handling can go here
	pass

# ---------------------------------------------------------------------------
# CardChrome — procedural card "soul" overlay.
#
# A mouse-transparent Control that paints sci-fi panel hardware over the flat
# StyleBox of every card built through apply_card_style(). The motif is chosen
# globally in Sys Config (GameState.game_settings.card_chrome); the accent is
# inherited per-card so all 8 category colours stay coherent. Fully static —
# repaints only on resize or when the player switches styles.
# ---------------------------------------------------------------------------
class CardChrome extends Control:
	var accent: Color = Color(1.0, 0.6, 0.2)
	# Page background, used to mask the holographic octagon corner cuts.
	const _PAGE_BG := Color(0.08, 0.08, 0.12)

	func _ready() -> void:
		UITheme.chrome_changed.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 8.0 or h < 8.0:
			return
		match UITheme.get_card_chrome():
			UITheme.CHROME_HOLOGRAPHIC:
				_draw_holographic(w, h)
			UITheme.CHROME_PRECURSOR:
				_draw_precursor(w, h)
			_:
				_draw_industrial(w, h)

	# --- small shared primitives ------------------------------------------
	func _diamond(c: Vector2, r: float, col: Color) -> void:
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -r), c + Vector2(r, 0),
			c + Vector2(0, r), c + Vector2(-r, 0)]), col)

	func _diamond_outline(c: Vector2, r: float, col: Color, wd: float) -> void:
		draw_polyline(PackedVector2Array([
			c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r),
			c + Vector2(-r, 0), c + Vector2(0, -r)]), col, wd, true)

	# Eight-point octagon tracing a chamfer of size `c`.
	func _octagon(w: float, h: float, c: float) -> PackedVector2Array:
		return PackedVector2Array([
			Vector2(c, 0), Vector2(w - c, 0), Vector2(w, c), Vector2(w, h - c),
			Vector2(w - c, h), Vector2(c, h), Vector2(0, h - c), Vector2(0, c),
			Vector2(c, 0)])

	# --- 01 · Industrial command console ----------------------------------
	func _draw_industrial(w: float, h: float) -> void:
		var a := accent
		# CRT scanline surface — one batched call, very low alpha.
		var scan := PackedVector2Array()
		var sy := 7.0
		while sy < h - 5.0:
			scan.append(Vector2(5, sy))
			scan.append(Vector2(w - 5, sy))
			sy += 4.0
		draw_multiline(scan, Color(1, 1, 1, 0.022), 1.0)

		# Recessed inner hairline frame only (thin — matches the comp).
		var fr := a
		fr.a = 0.18
		draw_rect(Rect2(4, 4, w - 8, h - 8), fr, false, 1.0)

		# Machined L brackets, scaled to the panel so big containers (Storage,
		# Item Details, menu/loading panels) carry the theme as visibly as the
		# small cards. Clamp floor = the original 18px so small cards are
		# unchanged.
		var bl := clampf(min(w, h) * 0.07, 18.0, 44.0)
		_bracket(Vector2(2, 2), 1.0, 1.0, a, bl)
		_bracket(Vector2(w - 2, 2), -1.0, 1.0, a, bl)
		_bracket(Vector2(2, h - 2), 1.0, -1.0, a, bl)
		_bracket(Vector2(w - 2, h - 2), -1.0, -1.0, a, bl)

		# Recessed rivets near the lower corners.
		_rivet(Vector2(13, h - 12))
		_rivet(Vector2(w - 13, h - 12))

	func _bracket(o: Vector2, sx: float, sy: float, col: Color, L: float = 18.0) -> void:
		var f := L / 18.0           # scale factor vs the original 18px unit
		var mw := clampf(2.0 * f, 2.0, 4.0)
		draw_polyline(PackedVector2Array([
			o + Vector2(0, L * sy), o, o + Vector2(L * sx, 0)]), col, mw, true)
		var inner := col
		inner.a *= 0.5
		draw_polyline(PackedVector2Array([
			o + Vector2(5 * f * sx, 13 * f * sy), o + Vector2(5 * f * sx, 5 * f * sy),
			o + Vector2(13 * f * sx, 5 * f * sy)]), inner, clampf(f, 1.0, 2.0), true)

	func _rivet(c: Vector2) -> void:
		draw_circle(c, 3.0, Color(0, 0, 0, 0.5))
		draw_circle(c, 1.6, Color(1, 1, 1, 0.22))

	# --- 02 · Holographic projection --------------------------------------
	func _draw_holographic(w: float, h: float) -> void:
		var a := accent
		var ch := 16.0

		# Cut all four corners with page bg → a true octagon silhouette.
		# Triangles bleed ~3px past the overlay so they also mask the panel's
		# rounded StyleBox corner (radius 5) that sits just outside this rect.
		var b := 3.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(-b, -b), Vector2(ch, -b), Vector2(-b, ch)]), _PAGE_BG)
		draw_colored_polygon(PackedVector2Array([
			Vector2(w - ch, -b), Vector2(w + b, -b), Vector2(w + b, ch)]), _PAGE_BG)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-b, h - ch), Vector2(ch, h + b), Vector2(-b, h + b)]), _PAGE_BG)
		draw_colored_polygon(PackedVector2Array([
			Vector2(w + b, h - ch), Vector2(w + b, h + b), Vector2(w - ch, h + b)]), _PAGE_BG)

		# Outer bloom — stacked octagon strokes following the shape.
		var gg := a
		gg.a = 0.06
		for i in range(1, 4):
			var d := float(i) * 2.0
			# Bloom octagon, expanded outward by d on every side.
			var ring := PackedVector2Array()
			for p in _octagon(w + d * 2.0, h + d * 2.0, ch + d):
				ring.append(p - Vector2(d, d))
			draw_polyline(ring, gg, 2.0, true)

		# Faint dot-mesh fill (one batched call).
		var dm := a
		dm.a = 0.06
		var mesh := PackedVector2Array()
		var my := 18.0
		while my < h - 12.0:
			var mx := 18.0
			while mx < w - 12.0:
				mesh.append(Vector2(mx - 1.5, my))
				mesh.append(Vector2(mx + 1.5, my))
				mesh.append(Vector2(mx, my - 1.5))
				mesh.append(Vector2(mx, my + 1.5))
				mx += 16.0
			my += 16.0
		draw_multiline(mesh, dm, 1.0)

		# Static "scan band" — soft bright band, reads as a frozen sweep.
		var by := h * 0.40
		for k in range(6):
			var t := float(k)
			var band := a
			band.a = 0.05 * (1.0 - t / 6.0)
			draw_rect(Rect2(ch, by - t * 3.0, w - ch * 2.0, 3.0), band, true)
			draw_rect(Rect2(ch, by + t * 3.0, w - ch * 2.0, 3.0), band, true)

		# Faint inner octagon, inset 4px on every side.
		var g2 := a
		g2.a = 0.2
		var inner := PackedVector2Array()
		for p in _octagon(w - 8, h - 8, ch - 4):
			inner.append(p + Vector2(4, 4))
		draw_polyline(inner, g2, 1.0, true)

		# Outer frame drawn edge-by-edge: dim straight runs, BRIGHT thick
		# chamfer cuts. One clean stroke per edge — the "lit bevel" is the
		# frame itself, so nothing overlaps or wedges at the corners.
		var v0 := Vector2(ch, 0)
		var v1 := Vector2(w - ch, 0)
		var v2 := Vector2(w, ch)
		var v3 := Vector2(w, h - ch)
		var v4 := Vector2(w - ch, h)
		var v5 := Vector2(ch, h)
		var v6 := Vector2(0, h - ch)
		var v7 := Vector2(0, ch)
		var edge := a
		edge.a = 0.45
		var cut := a
		cut.a = 0.95
		draw_line(v0, v1, edge, 1.2)   # straight runs
		draw_line(v2, v3, edge, 1.2)
		draw_line(v4, v5, edge, 1.2)
		draw_line(v6, v7, edge, 1.2)
		draw_line(v7, v0, cut, 2.5)    # lit chamfer cuts
		draw_line(v1, v2, cut, 2.5)
		draw_line(v3, v4, cut, 2.5)
		draw_line(v5, v6, cut, 2.5)

	# --- 03 · Precursor-etched --------------------------------------------
	func _filigree(o: Vector2, sx: float, sy: float, col: Color) -> void:
		# Main chamfered L bracket.
		draw_polyline(PackedVector2Array([
			o + Vector2(2 * sx, 36 * sy), o + Vector2(2 * sx, 14 * sy),
			o + Vector2(14 * sx, 2 * sy), o + Vector2(36 * sx, 2 * sy)]), col, 1.8)
		# Parallel inner groove (lighter — fakes an engraved bevel).
		var groove := col
		groove.a *= 0.45
		draw_polyline(PackedVector2Array([
			o + Vector2(6 * sx, 30 * sy), o + Vector2(6 * sx, 16 * sy),
			o + Vector2(16 * sx, 6 * sy), o + Vector2(30 * sx, 6 * sy)]), groove, 1.2)
		# Hooked flourish + an inlaid node at the elbow.
		draw_polyline(PackedVector2Array([
			o + Vector2(2 * sx, 24 * sy), o + Vector2(11 * sx, 24 * sy),
			o + Vector2(16 * sx, 19 * sy)]), col, 1.4)
		_diamond(o + Vector2(9 * sx, 9 * sy), 2.5, col)

	func _draw_precursor(w: float, h: float) -> void:
		var a := accent
		# Engraved double inner stroke (outer line + lighter offset groove).
		var e1 := a
		e1.a = 0.5
		var e2 := a
		e2.a = 0.2
		draw_rect(Rect2(6, 6, w - 12, h - 12), e1, false, 1.0)
		draw_rect(Rect2(9, 9, w - 18, h - 18), e2, false, 1.0)

		# Angular filigree at all four corners.
		var fc := a
		fc.a = 0.85
		_filigree(Vector2(0, 0), 1.0, 1.0, fc)
		_filigree(Vector2(w, 0), -1.0, 1.0, fc)
		_filigree(Vector2(0, h), 1.0, -1.0, fc)
		_filigree(Vector2(w, h), -1.0, -1.0, fc)

		# Embroidery stitch ticks down both inner side edges.
		var st := a
		st.a = 0.3
		var stitch := PackedVector2Array()
		var ys := 48.0
		while ys < h - 48.0:
			stitch.append(Vector2(12, ys))
			stitch.append(Vector2(16, ys))
			stitch.append(Vector2(w - 12, ys))
			stitch.append(Vector2(w - 16, ys))
			ys += 11.0
		draw_multiline(stitch, st, 1.0)

		# Inlaid node diamonds (with a ring) at the mid-point of each edge.
		for p in [Vector2(w * 0.5, 4), Vector2(w * 0.5, h - 4),
				Vector2(4, h * 0.5), Vector2(w - 4, h * 0.5)]:
			_diamond(p, 4.0, a)
			_diamond_outline(p, 7.0, e2, 1.0)

		# Etched glyph row along the bottom inner edge: diamond · chevron.
		var gl := a
		gl.a = 0.45
		var gx := 46.0
		var idx := 0
		while gx < w - 46.0:
			if idx % 2 == 0:
				_diamond(Vector2(gx, h - 11), 2.5, gl)
			else:
				draw_polyline(PackedVector2Array([
					Vector2(gx - 3, h - 9), Vector2(gx, h - 13),
					Vector2(gx + 3, h - 9)]), gl, 1.2)
			gx += 15.0
			idx += 1
