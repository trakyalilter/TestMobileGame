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
	_build_nebula()
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

func _build_nebula():
	var vp = get_viewport().get_visible_rect().size
	var blobs = [
		[Vector2(vp.x * 0.12, vp.y * 0.18), Vector2(320, 220), Color(0.18, 0.28, 0.60, 0.030)],
		[Vector2(vp.x * 0.72, vp.y * 0.62), Vector2(380, 260), Color(0.38, 0.10, 0.52, 0.025)],
		[Vector2(vp.x * 0.80, vp.y * 0.08), Vector2(240, 190), Color(0.10, 0.32, 0.55, 0.035)],
	]
	for b in blobs:
		var blob = ColorRect.new()
		blob.size = b[1]
		blob.position = b[0] - b[1] * 0.5
		blob.color = b[2]
		add_child(blob)

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
	style.content_margin_left   = 44
	style.content_margin_right  = 44
	style.content_margin_top    = 38
	style.content_margin_bottom = 44
	_center_panel.add_theme_stylebox_override("panel", style)
	add_child(_center_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	_center_panel.add_child(vbox)

	_build_title(vbox)
	_add_sep(vbox, 22, 18)
	_build_main_menu(vbox)
	_build_options_menu(vbox)

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
		cr_str = "%.1fM Cr" % (credits / 1_000_000.0)
	elif credits >= 1_000.0:
		cr_str = "%.1fK Cr" % (credits / 1_000.0)
	else:
		cr_str = "%d Cr" % int(credits)

	return "Zone %d  ·  %s" % [max_zone, cr_str]

# ─────────────────────────────────────────────
#  BUTTON HANDLERS
# ─────────────────────────────────────────────
func _on_continue_pressed():
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_new_game_pressed():
	GameState.hard_reset()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

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
