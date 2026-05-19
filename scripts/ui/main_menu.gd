extends Control

# --- Colors ---
const BG_COLOR      := Color(0.030, 0.030, 0.058, 1.0)
const ACCENT_CYAN   := Color(0.42,  0.84,  1.00)
const ACCENT_AMBER  := Color(0.92,  0.70,  0.30)
const TEXT_MAIN     := Color(0.90,  0.87,  0.80)
const TEXT_DIM      := Color(0.48,  0.46,  0.42)
const PANEL_BG      := Color(0.055, 0.055, 0.095, 0.97)
const PANEL_BORDER  := Color(0.32,  0.42,  0.58,  0.75)

# --- UI references ---
var _center_panel: PanelContainer
var _menu_root: Control
var _options_root: Control
var btn_continue: Button
var btn_new_game: Button
var btn_options: Button
var btn_exit: Button
var chk_offline_combat: CheckBox
var has_save: bool = false
var _stars: Array = []

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	has_save = FileAccess.file_exists("user://savegame.json")

	_build_background()
	_build_starfield()
	_build_corner_chrome()
	_build_center_panel()
	_build_footer()

	_animate_entrance()
	_start_star_twinkle()

# ─────────────────────────────────────────────
#  BACKGROUND
# ─────────────────────────────────────────────
func _build_background():
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG_COLOR
	add_child(bg)

func _build_starfield():
	var rng = RandomNumberGenerator.new()
	rng.seed = 7391
	var vp = get_viewport().get_visible_rect().size
	for i in range(90):
		var star = ColorRect.new()
		var sz = rng.randf_range(1.0, 2.6)
		star.size = Vector2(sz, sz)
		star.position = Vector2(rng.randf() * vp.x, rng.randf() * vp.y)
		var b = rng.randf_range(0.45, 1.0)
		star.color = Color(b * 0.88, b * 0.92, b, rng.randf_range(0.20, 0.80))
		add_child(star)
		_stars.append(star)

func _build_corner_chrome():
	var vp = get_viewport().get_visible_rect().size
	var chrome_col = Color(0.28, 0.44, 0.62, 0.55)

	# Thin horizontal accent lines
	for y_pos in [38.0, vp.y - 42.0]:
		var line = ColorRect.new()
		line.size = Vector2(vp.x, 1)
		line.position = Vector2(0, y_pos)
		line.color = Color(chrome_col.r, chrome_col.g, chrome_col.b, 0.30)
		add_child(line)

	# Corner bracket glyphs
	var corners = [
		[Vector2(18, 16),              "┌"],
		[Vector2(vp.x - 34, 16),      "┐"],
		[Vector2(18, vp.y - 42),      "└"],
		[Vector2(vp.x - 34, vp.y-42), "┘"],
	]
	for c in corners:
		var lbl = Label.new()
		lbl.text = c[1]
		lbl.position = c[0]
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.add_theme_color_override("font_color", chrome_col)
		add_child(lbl)

# ─────────────────────────────────────────────
#  CENTER PANEL
# ─────────────────────────────────────────────
func _build_center_panel():
	_center_panel = PanelContainer.new()
	_center_panel.custom_minimum_size = Vector2(480, 0)
	_center_panel.set_anchors_preset(Control.PRESET_CENTER)
	_center_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH

	var style = StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_border_width_all(1)
	style.border_width_top = 3
	style.border_color = PANEL_BORDER
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0, 0, 0, 0.70)
	style.shadow_size = 28
	style.shadow_offset = Vector2(0, 10)
	# Padding moved to an inner MarginContainer (not stylebox content_margin)
	# so the themed CardChrome overlay can span the full panel edges.
	_center_panel.add_theme_stylebox_override("panel", style)
	add_child(_center_panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 44)
	pad.add_theme_constant_override("margin_right", 44)
	pad.add_theme_constant_override("margin_top", 38)
	pad.add_theme_constant_override("margin_bottom", 44)
	_center_panel.add_child(pad)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	pad.add_child(vbox)

	_build_title(vbox)
	_add_sep(vbox, 22, 18)
	_build_main_menu(vbox)
	_build_options_menu(vbox)

	# Same selectable card-soul chrome as gameplay cards (Sys Config).
	UITheme._attach_chrome(_center_panel, ACCENT_CYAN)

func _build_title(parent: VBoxContainer):
	var title_box = VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 4)
	parent.add_child(title_box)

	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	title_box.add_child(row)

	var h_lbl = Label.new()
	h_lbl.text = "HORIZON"
	h_lbl.add_theme_font_size_override("font_size", 54)
	h_lbl.add_theme_color_override("font_color", ACCENT_CYAN)
	h_lbl.add_theme_color_override("font_shadow_color", Color(0, 0.6, 1.0, 0.4))
	h_lbl.add_theme_constant_override("shadow_offset_x", 0)
	h_lbl.add_theme_constant_override("shadow_offset_y", 0)
	h_lbl.add_theme_constant_override("shadow_outline_size", 8)
	row.add_child(h_lbl)

	var i_lbl = Label.new()
	i_lbl.text = "IDLE"
	i_lbl.add_theme_font_size_override("font_size", 34)
	i_lbl.add_theme_color_override("font_color", ACCENT_AMBER)
	i_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	row.add_child(i_lbl)

	var sub = Label.new()
	sub.text = "DEEP SPACE OPERATIONS SYSTEM"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", TEXT_DIM)
	title_box.add_child(sub)

func _build_main_menu(parent: VBoxContainer):
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	parent.add_child(vbox)
	_menu_root = vbox

	# Continue
	btn_continue = _make_btn("▶  CONTINUE", 20, "continue")
	btn_continue.custom_minimum_size = Vector2(0, 58)
	btn_continue.disabled = not has_save
	vbox.add_child(btn_continue)

	# Save preview / hint
	var preview = Label.new()
	preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview.add_theme_font_size_override("font_size", 10)
	if has_save:
		preview.text = _load_save_summary()
		preview.add_theme_color_override("font_color", Color(0.50, 0.72, 0.50, 0.85))
	else:
		preview.text = "No save data — start a new game"
		preview.add_theme_color_override("font_color", Color(0.55, 0.45, 0.40, 0.75))
	vbox.add_child(preview)

	_add_spacer(vbox, 4)

	# New Game
	btn_new_game = _make_btn("+  NEW GAME", 18, "new_game")
	btn_new_game.custom_minimum_size = Vector2(0, 50)
	vbox.add_child(btn_new_game)

	_add_sep(vbox, 14, 12)

	# Settings + Exit row
	var bottom = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	vbox.add_child(bottom)

	btn_options = _make_btn("⚙  SETTINGS", 14, "settings")
	btn_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_options.custom_minimum_size = Vector2(0, 44)
	bottom.add_child(btn_options)

	btn_exit = _make_btn("✕  EXIT", 14, "exit")
	btn_exit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_exit.custom_minimum_size = Vector2(0, 44)
	bottom.add_child(btn_exit)

	btn_continue.pressed.connect(_on_continue_pressed)
	btn_new_game.pressed.connect(_on_new_game_pressed)
	btn_options.pressed.connect(_on_options_pressed)
	btn_exit.pressed.connect(_on_exit_pressed)

	if has_save:
		var tween = create_tween().set_loops()
		tween.tween_property(btn_continue, "modulate", Color(1.06, 1.03, 0.95), 1.4).set_trans(Tween.TRANS_SINE)
		tween.tween_property(btn_continue, "modulate", Color.WHITE, 1.4).set_trans(Tween.TRANS_SINE)

func _build_options_menu(parent: VBoxContainer):
	var vbox = VBoxContainer.new()
	vbox.visible = false
	vbox.add_theme_constant_override("separation", 14)
	parent.add_child(vbox)
	_options_root = vbox

	var title = Label.new()
	title.text = "SYSTEM CONFIGURATION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", ACCENT_CYAN)
	vbox.add_child(title)

	_add_sep(vbox, 2, 6)

	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	vbox.add_child(row)

	var lbl = Label.new()
	lbl.text = "Enable Offline Combat"
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", TEXT_MAIN)
	row.add_child(lbl)

	chk_offline_combat = CheckBox.new()
	chk_offline_combat.custom_minimum_size = Vector2(40, 40)
	chk_offline_combat.toggled.connect(_on_offline_combat_toggled)
	row.add_child(chk_offline_combat)

	_add_sep(vbox, 8, 4)

	var btn_back = _make_btn("◀  RETURN TO MENU", 14, "settings")
	btn_back.custom_minimum_size = Vector2(0, 46)
	btn_back.pressed.connect(_on_back_pressed)
	vbox.add_child(btn_back)

# ─────────────────────────────────────────────
#  FOOTER
# ─────────────────────────────────────────────
func _build_footer():
	var vp = get_viewport().get_visible_rect().size

	var ver = Label.new()
	ver.text = "HORIZON IDLE  ·  v0.1 PROTOTYPE"
	ver.position = Vector2(24, vp.y - 34)
	ver.add_theme_font_size_override("font_size", 10)
	ver.add_theme_color_override("font_color", Color(0.38, 0.38, 0.50, 0.75))
	add_child(ver)

	var status = Label.new()
	status.text = "SYSTEM READY  ◆"
	status.add_theme_font_size_override("font_size", 10)
	status.add_theme_color_override("font_color", Color(0.28, 0.68, 0.38, 0.80))
	status.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	status.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	status.offset_left  = -200
	status.offset_top   = -38
	status.offset_right = -24
	status.offset_bottom = -20
	add_child(status)

# ─────────────────────────────────────────────
#  ANIMATIONS
# ─────────────────────────────────────────────
func _animate_entrance():
	if not _center_panel: return
	_center_panel.modulate.a = 0.0
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_center_panel, "modulate:a", 1.0, 0.55)

func _start_star_twinkle():
	var rng = RandomNumberGenerator.new()
	rng.seed = 9901
	for star in _stars:
		var base_a = star.color.a
		var dur = rng.randf_range(1.8, 5.0)
		var delay = rng.randf_range(0.0, 4.0)
		var tween = create_tween().set_loops()
		tween.tween_interval(delay)
		tween.tween_property(star, "color:a", base_a * 0.12, dur).set_trans(Tween.TRANS_SINE)
		tween.tween_property(star, "color:a", base_a, dur * 0.65).set_trans(Tween.TRANS_SINE)

# ─────────────────────────────────────────────
#  HELPERS
# ─────────────────────────────────────────────
func _make_btn(label: String, font_size: int, style: String) -> Button:
	var btn = Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", font_size)
	_apply_btn_style(btn, style)
	return btn

func _apply_btn_style(btn: Button, style_type: String):
	var accent: Color
	var bg_base: Color
	match style_type:
		"continue":
			accent  = Color(0.88, 0.72, 0.28)
			bg_base = Color(0.11, 0.09, 0.05, 0.95)
		"new_game":
			accent  = Color(0.38, 0.76, 0.44)
			bg_base = Color(0.05, 0.10, 0.06, 0.95)
		"exit":
			accent  = Color(0.80, 0.28, 0.28)
			bg_base = Color(0.10, 0.05, 0.05, 0.95)
		_:  # settings / back
			accent  = Color(0.52, 0.54, 0.72)
			bg_base = Color(0.07, 0.07, 0.11, 0.95)

	var normal = StyleBoxFlat.new()
	normal.bg_color = bg_base
	normal.set_border_width_all(1)
	normal.border_width_top = 2
	normal.border_color = accent.lerp(Color(0.5, 0.5, 0.6), 0.45)
	normal.set_corner_radius_all(3)
	normal.content_margin_left   = 16
	normal.content_margin_right  = 16
	normal.content_margin_top    = 6
	normal.content_margin_bottom = 6

	var hover = normal.duplicate()
	hover.bg_color = bg_base.lerp(accent, 0.20)
	hover.border_color = accent.lerp(Color.WHITE, 0.35)
	hover.shadow_color = Color(accent.r, accent.g, accent.b, 0.28)
	hover.shadow_size  = 10

	var pressed = normal.duplicate()
	pressed.bg_color    = bg_base.lerp(accent, 0.38)
	pressed.border_color = accent.lerp(Color.WHITE, 0.55)
	pressed.border_width_top = 3

	var disabled = normal.duplicate()
	disabled.bg_color    = Color(0.07, 0.07, 0.09, 0.65)
	disabled.border_color = Color(0.22, 0.22, 0.26, 0.45)

	btn.add_theme_stylebox_override("normal",   normal)
	btn.add_theme_stylebox_override("hover",    hover)
	btn.add_theme_stylebox_override("pressed",  pressed)
	btn.add_theme_stylebox_override("focus",    StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.add_theme_color_override("font_color",          accent.lerp(TEXT_MAIN, 0.38))
	btn.add_theme_color_override("font_hover_color",    Color.WHITE.lerp(accent, 0.22))
	btn.add_theme_color_override("font_pressed_color",  Color(0.14, 0.10, 0.06))
	btn.add_theme_color_override("font_disabled_color", Color(0.32, 0.32, 0.36))

func _add_sep(parent: Node, margin_top: int = 12, margin_bottom: int = 12):
	_add_spacer(parent, margin_top)
	var sep = HSeparator.new()
	var ss = StyleBoxFlat.new()
	ss.bg_color = Color(PANEL_BORDER.r, PANEL_BORDER.g, PANEL_BORDER.b, 0.55)
	ss.content_margin_top = 0
	sep.add_theme_stylebox_override("separator", ss)
	sep.add_theme_constant_override("separation", 0)
	parent.add_child(sep)
	_add_spacer(parent, margin_bottom)

func _add_spacer(parent: Node, height: int):
	var s = Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)

func _load_save_summary() -> String:
	var f = FileAccess.open("user://savegame.json", FileAccess.READ)
	if not f: return "Save data found"
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not data is Dictionary: return "Save data found"

	# Credits stored as float under resources.currencies.credits
	var credits: float = 0.0
	var res_dict = data.get("resources", {})
	if res_dict is Dictionary:
		var cur_dict = res_dict.get("currencies", {})
		if cur_dict is Dictionary:
			credits = float(cur_dict.get("credits", 0.0))

	# Highest accessible zone from research unlocks (zone_2_access → zone 2)
	var max_zone: int = 1
	var research_dict = data.get("research", {})
	if research_dict is Dictionary:
		var unlocked = research_dict.get("unlocked_techs", [])
		if unlocked is Array:
			for tech in unlocked:
				if tech is String and tech.begins_with("zone_") and tech.ends_with("_access"):
					var parts = tech.split("_")
					if parts.size() >= 2:
						var n = int(parts[1])
						if n > max_zone: max_zone = n

	var cr_str: String
	if credits >= 1_000_000.0:
		cr_str = "%.1fM Liras" % (credits / 1_000_000.0)
	elif credits >= 1_000.0:
		cr_str = "%.1fK Liras" % (credits / 1_000.0)
	else:
		cr_str = "%d Liras" % int(credits)

	var summary := "Zone %d  ·  %s" % [max_zone, cr_str]

	var pt := float(data.get("total_playtime", 0.0))
	if pt >= 60.0:
		summary += "  ·  %s played" % FormatUtils.format_playtime(pt)

	return summary

# ─────────────────────────────────────────────
#  BUTTON HANDLERS
# ─────────────────────────────────────────────
const _MAIN_SCENE := "res://scenes/main.tscn"
var _loading := false
var _load_lbl: Label = null
var _load_bar: ProgressBar = null
var _load_pct: Label = null
var _load_shimmer: ColorRect = null

func _on_continue_pressed():
	_begin_load(false)

func _on_new_game_pressed():
	_begin_load(true)

# Smooth boot: paint a loading screen FIRST, thread-load the scene resource,
# then swap. The unavoidable page-build still happens on the main thread, but
# now it happens behind a loading screen the player expects to wait on —
# instead of a frozen Continue button.
func _begin_load(is_new_game: bool) -> void:
	if _loading: return
	_loading = true

	for b in [btn_continue, btn_new_game, btn_options, btn_exit]:
		if is_instance_valid(b): b.disabled = true

	_show_loading_overlay()
	CursorManager.set_state(CursorManager.State.WAIT)

	# Two frames so the overlay actually renders before any heavy work.
	await get_tree().process_frame
	await get_tree().process_frame

	if is_new_game:
		GameState.hard_reset()

	ResourceLoader.load_threaded_request(_MAIN_SCENE)
	while true:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(_MAIN_SCENE, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			CursorManager.set_state(CursorManager.State.DEFAULT)
			get_tree().change_scene_to_file(_MAIN_SCENE)  # blocking fallback
			return
		if progress.size() > 0:
			_set_load_progress(progress[0])
		await get_tree().process_frame

	var packed: PackedScene = ResourceLoader.load_threaded_get(_MAIN_SCENE)
	# Resource load is done, but the scene still has to instantiate on the
	# main thread (unmeasurable). Switch to an indeterminate "finalizing"
	# state so the held frame reads as working, never "stuck at 100%".
	_enter_finalizing()
	CursorManager.set_state(CursorManager.State.DEFAULT)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_packed(packed)

func _show_loading_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG_COLOR
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks while loading
	layer.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	var ps := StyleBoxFlat.new()
	ps.bg_color = PANEL_BG
	ps.set_border_width_all(1)
	ps.border_width_top = 3
	ps.border_color = PANEL_BORDER
	ps.set_corner_radius_all(4)
	ps.shadow_color = Color(0, 0, 0, 0.6)
	ps.shadow_size = 24
	# Padding via inner MarginContainer so the CardChrome spans full edges.
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 40)
	pad.add_theme_constant_override("margin_right", 40)
	pad.add_theme_constant_override("margin_top", 32)
	pad.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(pad)
	# Same selectable card-soul chrome as gameplay cards (Sys Config).
	UITheme._attach_chrome(panel, ACCENT_CYAN)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	pad.add_child(vb)

	# Brand line — keeps the boot screen on-identity, not a bare bar.
	var brand := HBoxContainer.new()
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	brand.add_theme_constant_override("separation", 8)
	vb.add_child(brand)
	var h := Label.new()
	h.text = "HORIZON"
	h.add_theme_font_size_override("font_size", 30)
	h.add_theme_color_override("font_color", ACCENT_CYAN)
	brand.add_child(h)
	var i := Label.new()
	i.text = "IDLE"
	i.add_theme_font_size_override("font_size", 20)
	i.add_theme_color_override("font_color", ACCENT_AMBER)
	i.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	brand.add_child(i)

	_load_lbl = Label.new()
	_load_lbl.text = "INITIALIZING SYSTEMS"
	_load_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_load_lbl.add_theme_font_size_override("font_size", 12)
	_load_lbl.add_theme_color_override("font_color", TEXT_DIM)
	vb.add_child(_load_lbl)

	# Progress bar with a shimmer overlay used during the finalizing phase.
	var bar_wrap := Control.new()
	bar_wrap.custom_minimum_size = Vector2(360, 16)
	bar_wrap.clip_contents = true
	vb.add_child(bar_wrap)

	_load_bar = ProgressBar.new()
	_load_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_bar.min_value = 0
	_load_bar.max_value = 100
	_load_bar.value = 0
	_load_bar.show_percentage = false
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.04, 0.05, 0.09, 1.0)
	track.set_border_width_all(1)
	track.border_color = PANEL_BORDER
	track.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT_CYAN
	fill.set_corner_radius_all(3)
	fill.shadow_color = Color(ACCENT_CYAN.r, ACCENT_CYAN.g, ACCENT_CYAN.b, 0.35)
	fill.shadow_size = 6
	_load_bar.add_theme_stylebox_override("background", track)
	_load_bar.add_theme_stylebox_override("fill", fill)
	bar_wrap.add_child(_load_bar)

	_load_shimmer = ColorRect.new()
	_load_shimmer.color = Color(1, 1, 1, 0.12)
	_load_shimmer.size = Vector2(70, 16)
	_load_shimmer.position = Vector2(-80, 0)
	_load_shimmer.visible = false
	_load_shimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(_load_shimmer)

	_load_pct = Label.new()
	_load_pct.text = "0%"
	_load_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_load_pct.add_theme_font_size_override("font_size", 11)
	_load_pct.add_theme_color_override("font_color", ACCENT_CYAN)
	vb.add_child(_load_pct)

func _set_load_progress(p: float) -> void:
	# Reserve the top 10% for the unmeasurable instantiation phase so the
	# bar never sits full-but-frozen.
	var shown: float = clamp(p, 0.0, 1.0) * 90.0
	if _load_bar: _load_bar.value = shown
	if _load_pct: _load_pct.text = "%d%%" % int(shown)

func _enter_finalizing() -> void:
	if _load_lbl: _load_lbl.text = "ENTERING SECTOR"
	if _load_pct: _load_pct.text = "FINALIZING"
	if _load_bar: _load_bar.value = 100
	if _load_shimmer:
		_load_shimmer.visible = true
		var tw := _load_shimmer.create_tween().set_loops()
		tw.tween_property(_load_shimmer, "position:x", 360.0, 0.7).from(-80.0).set_trans(Tween.TRANS_SINE)

func _on_options_pressed():
	_menu_root.hide()
	_options_root.show()
	chk_offline_combat.button_pressed = GameState.game_settings.get("offline_combat", false)

func _on_back_pressed():
	_options_root.hide()
	_menu_root.show()

func _on_offline_combat_toggled(pressed: bool):
	GameState.game_settings["offline_combat"] = pressed
	GameState.save_game()

func _on_exit_pressed():
	get_tree().quit()
