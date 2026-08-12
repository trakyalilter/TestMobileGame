extends Control

# --- Colors (palette-aware: defaults are the Bloom literals; _apply_theme()
#     repoints them to the active UITheme palette tokens at _ready()) ---
var BG_COLOR      := Color(0.030, 0.030, 0.058, 1.0)
var ACCENT_CYAN   := Color(0.42,  0.84,  1.00)
var ACCENT_AMBER  := Color(0.92,  0.70,  0.30)
var TEXT_MAIN     := Color(0.90,  0.87,  0.80)
var TEXT_DIM      := Color(0.48,  0.46,  0.42)
var PANEL_BG      := Color(0.055, 0.055, 0.095, 0.97)
var PANEL_BORDER  := Color(0.32,  0.42,  0.58,  0.75)

# Repoint local colour vars to the active palette tokens. MUST run before any
# UI is built. Vars (not consts) so they can hold runtime UITheme values.
func _apply_theme() -> void:
	BG_COLOR     = UITheme.COLORS["background"]
	PANEL_BG     = Color(UITheme.COLORS["panel_bg"], 0.97)
	PANEL_BORDER = Color(UITheme.COLORS["accent"], 0.75)
	ACCENT_CYAN  = UITheme.COLORS["accent_bright"]
	ACCENT_AMBER = UITheme.COLORS["warning"]
	TEXT_MAIN    = UITheme.COLORS["text_main"]
	TEXT_DIM     = UITheme.COLORS["text_dim"]

# --- UI references ---
var _center_panel: PanelContainer
var _menu_root: Control
var _options_root: Control
var _howto_root: Control
var btn_continue: Button
var btn_new_game: Button
var btn_howto: Button
var btn_exit: Button
var pill_offline_combat: Control
var has_save: bool = false
var _stars: Array = []
# VFX: parallax drift + occasional shooting star.
const _LAYER_SPEEDS := [5.0, 12.0, 24.0]   # px/sec, per depth layer
var _drift_dir := Vector2.ZERO              # set in _ready
var _shoot_t := 6.0                          # seconds until next shooting star

func _ready():
	# Cold-launch entry scene — apply the saved palette before anything else
	# builds, then repoint our local colour vars to the active tokens.
	UITheme.apply_palette(UITheme.get_ui_palette())
	_apply_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# v134c: a crash between the atomic save's backup-copy and rename can leave a
	# .bak-ONLY save (load_game now recovers it) — so Continue must appear for that
	# state too, or the player sees "New Game" only and thinks their save is gone.
	has_save = FileAccess.file_exists("user://savegame.json") or FileAccess.file_exists("user://savegame.bak")

	_build_background()
	_build_starfield()
	_build_corner_chrome()
	_build_center_panel()
	_build_footer()

	_animate_entrance()
	_start_star_twinkle()
	_drift_dir = Vector2(0.55, 0.85).normalized()
	set_process(true)

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
		star.set_meta("layer", i % 3)
		add_child(star)
		_stars.append(star)

func _build_corner_chrome():
	var vp = get_viewport().get_visible_rect().size
	var chrome_col = Color(UITheme.COLORS["accent"], 0.55)

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
	_build_howto_screen(vbox)

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
	h_lbl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	h_lbl.text = "HORIZON"
	h_lbl.add_theme_font_size_override("font_size", 54)
	h_lbl.add_theme_color_override("font_color", ACCENT_CYAN)
	h_lbl.add_theme_color_override("font_shadow_color", Color(0, 0.6, 1.0, 0.4))
	h_lbl.add_theme_constant_override("shadow_offset_x", 0)
	h_lbl.add_theme_constant_override("shadow_offset_y", 0)
	h_lbl.add_theme_constant_override("shadow_outline_size", 8)
	row.add_child(h_lbl)

	var i_lbl = Label.new()
	i_lbl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	i_lbl.text = "IDLE"
	i_lbl.add_theme_font_size_override("font_size", 34)
	i_lbl.add_theme_color_override("font_color", ACCENT_AMBER)
	i_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	row.add_child(i_lbl)

	var sub = Label.new()
	sub.text = tr("DEEP SPACE OPERATIONS SYSTEM")
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
	btn_continue = _make_btn(tr("CONTINUE"), 20, "continue")
	btn_continue.custom_minimum_size = Vector2(0, 58)
	btn_continue.disabled = not has_save
	vbox.add_child(btn_continue)

	# Save preview / hint
	var preview = Label.new()
	preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview.add_theme_font_size_override("font_size", 10)
	if has_save:
		preview.text = _load_save_summary()
		preview.add_theme_color_override("font_color", Color(UITheme.COLORS["positive"], 0.85))
	else:
		preview.text = tr("No save data — start a new game")
		preview.add_theme_color_override("font_color", Color(UITheme.COLORS["text_dim"], 0.75))
	vbox.add_child(preview)

	_add_spacer(vbox, 4)

	# New Game
	btn_new_game = _make_btn("+  " + tr("NEW GAME"), 18, "new_game")
	btn_new_game.custom_minimum_size = Vector2(0, 50)
	vbox.add_child(btn_new_game)

	# How to Play — the game teaches its systems in-run via coach marks, but a
	# returning or curious player had nowhere to read the loop as a whole. Sits
	# under New Game (a first-timer's natural next glance) and above the
	# settings/exit row so it never competes with CONTINUE.
	btn_howto = _make_btn(tr("HOW TO PLAY"), 15, "howto")
	btn_howto.custom_minimum_size = Vector2(0, 40)
	btn_howto.pressed.connect(_on_howto_pressed)
	vbox.add_child(btn_howto)

	_add_sep(vbox, 14, 12)

	# Exit row
	var bottom = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	vbox.add_child(bottom)

	# Settings — opens the SYSTEM CONFIGURATION screen (offline-combat toggle +
	# language). This button was previously missing, so _on_options_pressed() was
	# orphaned and the whole options screen was unreachable from the menu.
	var btn_settings = _make_btn(tr("SETTINGS"), 14, "settings_open")
	btn_settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_settings.custom_minimum_size = Vector2(0, 44)
	btn_settings.pressed.connect(_on_options_pressed)
	bottom.add_child(btn_settings)

	btn_exit = _make_btn(tr("EXIT"), 14, "exit")
	btn_exit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_exit.custom_minimum_size = Vector2(0, 44)
	bottom.add_child(btn_exit)

	btn_continue.pressed.connect(_on_continue_pressed)
	btn_new_game.pressed.connect(_on_new_game_pressed)
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
	title.text = tr("SYSTEM CONFIGURATION")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", ACCENT_CYAN)
	vbox.add_child(title)

	_add_sep(vbox, 2, 6)

	# v161: the settings list outgrew the panel once the INTERFACE group landed
	# (title clipped off the top, last palette off the bottom). Everything below
	# the heading scrolls; the RETURN button stays pinned outside it.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	content.add_child(row)

	var lbl = Label.new()
	lbl.text = tr("Enable Offline Combat")
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", TEXT_MAIN)
	row.add_child(lbl)

	# v161: segmented Off|On pill (UITheme.make_segmented_pill) — the same control
	# the in-game Sys Config uses. Was a raw Godot CheckBox: a bare outlined square
	# that matched nothing else in the game and read as a web form field.
	pill_offline_combat = UITheme.make_segmented_pill(
		[[tr("Off"), false], [tr("On"), true]],
		GameState.game_settings.get("offline_combat", false),
		func(v): _on_offline_combat_toggled(bool(v)))
	row.add_child(pill_offline_combat)

	_add_sep(content, 8, 4)

	# Language selector (Phase-0 loc). Names shown in their own language; selecting
	# one persists the locale and reloads the scene so every tr() re-reads under it.
	var lang_row = HBoxContainer.new()
	lang_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lang_row.add_theme_constant_override("separation", 10)
	content.add_child(lang_row)
	var lang_lbl = Label.new()
	lang_lbl.text = tr("Language") + ":"
	lang_lbl.add_theme_font_size_override("font_size", 16)
	lang_lbl.add_theme_color_override("font_color", TEXT_MAIN)
	lang_row.add_child(lang_lbl)
	# v161: same segmented pill as the toggle above. Two loose boxed buttons never
	# showed WHICH language was active; the pill fills the current one.
	lang_row.add_child(UITheme.make_segmented_pill(
		[["English", "en"], ["Türkçe", "tr"]],
		TranslationServer.get_locale().substr(0, 2),
		func(v): _on_language_selected(str(v))))

	_add_sep(content, 10, 8)

	# ── INTERFACE ──────────────────────────────────────────────────────────
	# v161: the same look-and-feel settings the in-game Sys Config exposes.
	# They were reachable only AFTER starting a run, so a player who wanted a
	# bigger cursor or a different palette had to load a save to get at them.
	var iface_title = Label.new()
	iface_title.text = tr("INTERFACE")
	iface_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	iface_title.add_theme_font_size_override("font_size", 11)
	iface_title.add_theme_color_override("font_color", Color(TEXT_DIM, 0.9))
	content.add_child(iface_title)

	_add_sep(content, 6, 4)

	_menu_setting_row(content, tr("Cursor Size"),
		[[tr("Small"), CursorManager.SIZE_SMALL],
		 [tr("Medium"), CursorManager.SIZE_MEDIUM],
		 [tr("Large"), CursorManager.SIZE_LARGE]],
		CursorManager.get_size(),
		func(v):
			GameState.game_settings["cursor_size"] = int(v)
			CursorManager.apply_size(int(v))
			_persist_pref())

	_menu_setting_row(content, tr("Card Frame"),
		[[tr("Industrial"), UITheme.CHROME_INDUSTRIAL],
		 [tr("Precursor"), UITheme.CHROME_PRECURSOR]],
		UITheme.get_card_chrome(),
		func(v):
			GameState.game_settings["card_chrome"] = int(v)
			UITheme.chrome_changed.emit()
			_persist_pref())

	_add_sep(content, 6, 4)

	# Palette: 7 options, too many for a pill — wrapping row of buttons each
	# tinted with its own signature accent, matching the in-game picker.
	var pal_lbl = Label.new()
	pal_lbl.text = tr("Color Palette")
	pal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pal_lbl.add_theme_font_size_override("font_size", 13)
	pal_lbl.add_theme_color_override("font_color", TEXT_MAIN)
	content.add_child(pal_lbl)

	var flow = HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	content.add_child(flow)
	var cur_pal := UITheme.get_ui_palette()
	for id in UITheme.PALETTE_ORDER:
		var pal: Dictionary = UITheme.UI_PALETTES[id]
		var pb = _make_btn(str(pal["name"]), 11, "settings")
		pb.custom_minimum_size = Vector2(126, 32)
		pb.add_theme_color_override("font_color",
			Color.WHITE if id == cur_pal else Color.html(str(pal["colors"]["accent"])))
		pb.pressed.connect(_on_menu_palette_pressed.bind(str(id)))
		flow.add_child(pb)

	_add_sep(content, 8, 4)

	var btn_back = _make_btn(tr("RETURN TO MENU"), 14, "settings")
	btn_back.custom_minimum_size = Vector2(0, 46)
	btn_back.pressed.connect(_on_back_pressed)
	vbox.add_child(btn_back)

# Label-left, segmented-pill-right settings row (menu flavour of the in-game
# Sys Config row).
func _menu_setting_row(parent: VBoxContainer, label_text: String, opts: Array,
		current, on_pick: Callable) -> void:
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var l = Label.new()
	l.text = label_text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", TEXT_MAIN)
	row.add_child(l)
	row.add_child(UITheme.make_segmented_pill(opts, current, on_pick))

# Preferences live in GameState.game_settings, which only reaches disk through
# save_game(). Writing one from the MENU when no save exists would mint a save
# file for a player who never started a run — Continue would light up on a fresh
# install. So only persist over an existing save; otherwise the choice applies
# live now and is written with the player's first real save.
func _persist_pref() -> void:
	if has_save:
		GameState.save_game()

func _on_menu_palette_pressed(id: String) -> void:
	GameState.game_settings["ui_palette"] = id
	UITheme.apply_palette(id)
	_persist_pref()
	# Every stylebox on this screen was built against the old tokens; rebuild
	# the menu so the new palette actually shows.
	get_tree().reload_current_scene()

func _on_language_selected(code: String) -> void:
	Localization.set_locale(code)
	# Rebuild the whole menu under the new locale — simplest reliable refresh.
	get_tree().reload_current_scene()

# ─────────────────────────────────────────────
#  FOOTER
# ─────────────────────────────────────────────
func _build_footer():
	var vp = get_viewport().get_visible_rect().size

	var ver = Label.new()
	# The DEMO label belongs to the demo build only. 046790d set it here back when
	# main WAS the demo build; the demo has had its own repo since, where the footer
	# is DemoGate-driven, so main labelling itself DEMO is now simply wrong.
	ver.text = tr("HORIZON IDLE  ·  PROTOTYPE")
	ver.position = Vector2(24, vp.y - 34)
	ver.add_theme_font_size_override("font_size", 10)
	ver.add_theme_color_override("font_color", Color(UITheme.COLORS["text_dim"], 0.75))
	add_child(ver)

	var status = Label.new()
	status.text = tr("SYSTEM READY  ◆")
	status.add_theme_font_size_override("font_size", 10)
	status.add_theme_color_override("font_color", Color(UITheme.COLORS["positive"], 0.80))
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

func _process(delta: float) -> void:
	if _stars.is_empty(): return
	var vp := get_viewport().get_visible_rect().size
	# Parallax drift — three depth layers move at different speeds along
	# the same diagonal. Stars wrap to the opposite edge.
	for star in _stars:
		var layer: int = star.get_meta("layer", 0)
		star.position += _drift_dir * _LAYER_SPEEDS[layer] * delta
		if star.position.x > vp.x: star.position.x -= vp.x
		if star.position.y > vp.y: star.position.y -= vp.y
		if star.position.x < -4.0: star.position.x += vp.x
		if star.position.y < -4.0: star.position.y += vp.y
	# Occasional shooting star.
	_shoot_t -= delta
	if _shoot_t <= 0.0:
		_spawn_shooting_star()
		_shoot_t = randf_range(10.0, 22.0)

func _spawn_shooting_star() -> void:
	var vp := get_viewport().get_visible_rect().size
	var streak := Line2D.new()
	streak.width = 1.6
	streak.default_color = Color(0.92, 0.96, 1.0, 0.9)
	streak.add_point(Vector2.ZERO)        # head (motion direction)
	streak.add_point(Vector2(-46, -34))   # tail (opposite of motion)
	var start := Vector2(
		randf_range(-30.0, vp.x * 0.50),
		randf_range(-30.0, vp.y * 0.25))
	streak.position = start
	add_child(streak)
	# Draw behind the centre panel: insert just before it in the child order.
	if _center_panel and is_instance_valid(_center_panel):
		move_child(streak, _center_panel.get_index())
	var travel := Vector2(vp.x * 0.95, vp.y * 0.70)
	var dur := randf_range(0.95, 1.40)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(streak, "position", start + travel, dur) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(streak, "modulate:a", 0.0, dur) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(streak.queue_free)

# ─────────────────────────────────────────────
#  HELPERS
# ─────────────────────────────────────────────
# ── HOW TO PLAY ───────────────────────────────────────────────────────────
# A briefing, not a manual: eight short sections that name the loop, the trap
# each system hides, and where to look when stuck. Everything here is teachable
# in one screen — the in-run coach marks handle the step-by-step.
const HOWTO_SECTIONS := [
	["ONE TASK AT A TIME",
		"Mining, Engineering, Research and Combat share a single active slot — starting one pauses the last. Pick the operation worth your next hour, then walk away; it keeps running."],
	["GATHER, REFINE, BUILD",
		"Mine raw materials, refine them in Engineering, spend the results in the Shipyard and on Infrastructure. Later tiers do not want more raw ore — they want the things ore becomes."],
	["RESEARCH OPENS THE GAME",
		"The Research Lab gates actions, recipes, buildings and sectors. If something looks missing or a recipe is greyed out, it is almost always a research node — look there first."],
	["YOUR SHIP IS YOUR BUILD",
		"Craft modules in the Shipyard, slot them in the Ship Designer. Batteries supply power and everything else draws it, so keep the grid margin positive. Save loadouts as presets and swap them per fight."],
	["FIGHT SMART, NOT HARD",
		"Every enemy resists one damage type and is weak to another — matching the weakness matters more than raw numbers. Sector bosses are deliberate gear checks: if one wall you, farm its sector for drops, then return."],
	["WEAR AND REPAIR",
		"Losing a fight wears every equipped module to 50%, and worn gear can be destroyed outright on the next loss. Recycle surplus modules into Spare Parts and repair with the hammer tool in the Ship Designer."],
	["INCOME THAT NEVER SLEEPS",
		"Infrastructure buildings and Bounty contracts run in the background no matter which task is active. Missions and Orders pay you for things you were doing anyway — claim them."],
	["YOU ARE MEANT TO LEAVE",
		"Progress accrues while the game is closed, up to a generous cap, and a report greets you on return. Offline combat is opt-in: it earns loot but risks module durability while unattended."],
]

func _build_howto_screen(parent: VBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.visible = false
	parent.add_child(vbox)
	_howto_root = vbox

	var title := Label.new()
	title.text = tr("HOW TO PLAY")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", ACCENT_CYAN)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = tr("DEEP SPACE OPERATIONS BRIEFING")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 9)
	sub.add_theme_color_override("font_color", Color(TEXT_DIM, 0.85))
	vbox.add_child(sub)

	_add_sep(vbox, 12, 10)

	# Scrolls: the briefing is taller than the menu panel. Height is budgeted
	# against the 720p base viewport — the panel is centred and grows both ways,
	# so anything over ~300 here pushes the title and BACK off screen.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 296)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for i in range(HOWTO_SECTIONS.size()):
		var sec: Array = HOWTO_SECTIONS[i]
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(row)

		var head := Label.new()
		# Numbered so the briefing reads as an ordered path, not a pile of tips.
		head.text = "%02d   %s" % [i + 1, tr(str(sec[0]))]
		head.add_theme_font_size_override("font_size", 13)
		head.add_theme_color_override("font_color", ACCENT_CYAN)
		row.add_child(head)

		var body := Label.new()
		body.text = tr(str(sec[1]))
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_font_size_override("font_size", 12)
		body.add_theme_color_override("font_color", Color(TEXT_MAIN, 0.82))
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(body)

	_add_sep(vbox, 12, 10)

	var back := _make_btn(tr("BACK"), 14, "settings_back")
	back.custom_minimum_size = Vector2(0, 42)
	back.pressed.connect(_on_howto_back_pressed)
	vbox.add_child(back)

func _on_howto_pressed() -> void:
	_menu_root.hide()
	_howto_root.show()

func _on_howto_back_pressed() -> void:
	_howto_root.hide()
	_menu_root.show()

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
			accent  = UITheme.CATEGORY_COLORS["inventory"]
			bg_base = Color(0.11, 0.09, 0.05, 0.95)
		"new_game":
			accent  = UITheme.COLORS["positive"]
			bg_base = Color(0.05, 0.10, 0.06, 0.95)
		"exit":
			accent  = UITheme.COLORS["negative"]
			bg_base = Color(0.10, 0.05, 0.05, 0.95)
		"howto":
			# Aqua "ops" identity — informational, distinct from the green
			# commit action above it and the indigo settings row below.
			accent  = UITheme.CATEGORY_COLORS["ops"]
			bg_base = Color(0.05, 0.10, 0.10, 0.95)
		_:  # settings / back
			accent  = UITheme.CATEGORY_COLORS["shipyard"]
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
	# v134c: mirror load_game's fallback so a .bak-only save still previews its
	# stats instead of the generic placeholder.
	var f = FileAccess.open("user://savegame.json", FileAccess.READ)
	if not f: f = FileAccess.open("user://savegame.bak", FileAccess.READ)
	if not f: return tr("Save data found")
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not data is Dictionary: return tr("Save data found")

	# v139 (owner request): the save-slot subtitle shows ONLY total play time — the
	# Zone + Liras it used to also carry were redundant with the in-game header.
	# format_playtime covers every range (0s → Nd Nh), so no <60s guard is needed.
	var pt := float(data.get("total_playtime", 0.0))
	return tr("%s played") % FormatUtils.format_playtime(pt)

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

	for b in [btn_continue, btn_new_game, btn_exit]:
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
	h.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	h.text = "HORIZON"
	h.add_theme_font_size_override("font_size", 30)
	h.add_theme_color_override("font_color", ACCENT_CYAN)
	brand.add_child(h)
	var i := Label.new()
	i.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	i.text = "IDLE"
	i.add_theme_font_size_override("font_size", 20)
	i.add_theme_color_override("font_color", ACCENT_AMBER)
	i.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	brand.add_child(i)

	_load_lbl = Label.new()
	_load_lbl.text = tr("INITIALIZING SYSTEMS")
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
	if _load_pct: _load_pct.text = tr("%d%%") % int(shown)

func _enter_finalizing() -> void:
	if _load_lbl: _load_lbl.text = tr("ENTERING SECTOR")
	if _load_pct: _load_pct.text = tr("FINALIZING")
	if _load_bar: _load_bar.value = 100
	if _load_shimmer:
		_load_shimmer.visible = true
		var tw := _load_shimmer.create_tween().set_loops()
		tw.tween_property(_load_shimmer, "position:x", 360.0, 0.7).from(-80.0).set_trans(Tween.TRANS_SINE)

func _on_options_pressed():
	_menu_root.hide()
	_options_root.show()
	# Visual-only sync: set_pill_value restyles without invoking on_pick, so
	# opening Settings can't spuriously fire the consent-dialog handler.
	UITheme.set_pill_value(pill_offline_combat, bool(GameState.game_settings.get("offline_combat", false)))

func _on_back_pressed():
	_options_root.hide()
	_menu_root.show()

func _on_offline_combat_toggled(pressed: bool):
	# v125: gate the first enable behind the durability-risk consent prompt.
	# Decline reverts the checkbox without re-firing this handler.
	if pressed and not GameState.game_settings.get("offline_combat_warned", false):
		UITheme.show_offline_combat_warning(
			Callable(self, "_on_offline_combat_consent"),
			Callable(self, "_on_offline_combat_decline"))
		return
	GameState.game_settings["offline_combat"] = pressed
	GameState.save_game()


func _on_offline_combat_consent() -> void:
	GameState.game_settings["offline_combat"] = true
	GameState.game_settings["offline_combat_warned"] = true
	UITheme.set_pill_value(pill_offline_combat, true)
	GameState.save_game()


func _on_offline_combat_decline() -> void:
	GameState.game_settings["offline_combat"] = false
	UITheme.set_pill_value(pill_offline_combat, false)
	GameState.save_game()

func _on_exit_pressed():
	get_tree().quit()
