extends Control

# Settings — a scrollable, sectioned settings screen.
# The whole page is constructed in code so the layout isn't path-fragile and
# every section panel flows through UITheme.apply_card_style(), so it inherits
# the player's chosen card-frame "soul" just like every gameplay card.

const SPEED_OPTIONS := [1.0, 2.0, 4.0, 8.0, 16.0]

const FRAME_CAT := "engineering"   # neutral cyan for section frames
const DANGER_CAT := "combat"       # red for destructive actions
const HEADER_CAT := "ops"          # warm anchor for the page header

# Selected-state tint (matches the existing convention used for speed/cursor).
const SEL := Color(0.45, 1.0, 0.55)
const UNSEL := Color(1, 1, 1)

var _column: VBoxContainer
var _refreshers: Array = []        # Array[Callable] — repaint selected states
var _pt_label: Label               # total play-time readout
var _pt_refresh := 0.0


func _ready() -> void:
	_build_ui()
	$ConfirmationDialog.confirmed.connect(_on_confirmation_dialog_confirmed)


# --------------------------------------------------------------------------
# Layout scaffold
# --------------------------------------------------------------------------
func _build_ui() -> void:
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + s, 24)
	add_child(pad)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_FILL
	scroll.size_flags_vertical = Control.SIZE_FILL
	pad.add_child(scroll)

	# Centre a fixed-width column so controls stop stretching to full screen.
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.custom_minimum_size = Vector2(620, 0)
	col.add_theme_constant_override("separation", 16)
	center.add_child(col)
	_column = col

	_build_header()
	_build_save_section()
	_build_gameplay_section()
	_build_interface_section()

	var foot := Label.new()
	foot.text = tr("Horizon Idle · prototype build · changes save automatically")
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_theme_font_size_override("font_size", 11)
	foot.add_theme_color_override("font_color", Color(0.45, 0.47, 0.55))
	col.add_child(foot)

	_refresh_all()


# --------------------------------------------------------------------------
# Sections
# --------------------------------------------------------------------------
func _build_header() -> void:
	var body := _section("Settings", HEADER_CAT)
	var sub := Label.new()
	sub.text = tr("Save, gameplay and interface options.")
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.62, 0.66, 0.76))
	body.add_child(sub)

	_pt_label = Label.new()
	_pt_label.add_theme_font_size_override("font_size", 12)
	_pt_label.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS[HEADER_CAT].lightened(0.25))
	body.add_child(_pt_label)
	_refresh_playtime()


func _build_save_section() -> void:
	var body := _section("Save Data", FRAME_CAT)

	# No manual SAVE GAME button — the game autosaves every 60s and on exit, so a
	# manual save is redundant (and misreads as "progress is lost unless you press
	# this"). Only the Hard Reset control lives here.
	var warn := Label.new()
	warn.text = tr("Hard reset wipes your save permanently — this cannot be undone.")
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.add_theme_font_size_override("font_size", 11)
	warn.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS[DANGER_CAT].lightened(0.15))
	body.add_child(warn)

	var reset_btn := _primary_button("HARD RESET GAME", DANGER_CAT)
	reset_btn.custom_minimum_size = Vector2(0, 38)
	reset_btn.pressed.connect(_on_reset_btn_pressed)
	body.add_child(reset_btn)


func _build_gameplay_section() -> void:
	var body := _section("Gameplay", FRAME_CAT)
	_add_choice_row(body, "Offline Combat",
		[["Off", false], ["On", true]],
		func(): return GameState.game_settings.get("offline_combat", false),
		func(v): _on_offline_combat_toggled(v))

	var replay := _primary_button("Replay Tutorials", FRAME_CAT)
	replay.custom_minimum_size = Vector2(0, 38)
	replay.pressed.connect(_on_replay_tutorials_pressed)
	body.add_child(replay)


func _build_interface_section() -> void:
	var body := _section("Interface", FRAME_CAT)

	_add_choice_row(body, "Cursor Size",
		[["Small", CursorManager.SIZE_SMALL],
		 ["Medium", CursorManager.SIZE_MEDIUM],
		 ["Large", CursorManager.SIZE_LARGE]],
		func(): return CursorManager.get_size(),
		func(v): _on_cursor_size_pressed(v))

	_add_choice_row(body, "Card Frame",
		[["Industrial", UITheme.CHROME_INDUSTRIAL],
		 ["Precursor", UITheme.CHROME_PRECURSOR]],
		func(): return UITheme.get_card_chrome(),
		func(v): _on_card_frame_pressed(v))

	_build_palette_picker(body)


# v123: UI colour-palette picker — wrapping buttons, each tinted with its
# palette's signature accent (active one stays white). Selecting one applies +
# saves it and reloads the scene so every stylebox re-themes against the new
# tokens; the player lands back on this page (GameState.ui_return_page).
func _build_palette_picker(body: VBoxContainer) -> void:
	var lbl := Label.new()
	lbl.text = tr("Color Palette")
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.66, 0.7, 0.8))
	body.add_child(lbl)

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	body.add_child(flow)

	var cur := UITheme.get_ui_palette()
	for id in UITheme.PALETTE_ORDER:
		var pal: Dictionary = UITheme.UI_PALETTES[id]
		var b := Button.new()
		b.text = str(pal["name"])
		b.custom_minimum_size = Vector2(134, 36)
		b.add_theme_font_size_override("font_size", 12)
		UITheme.apply_premium_button_style(b, FRAME_CAT)
		var acc: String = pal["colors"]["accent"]
		b.add_theme_color_override("font_color", Color.WHITE if id == cur else Color.html(acc))
		if id == cur:
			b.tooltip_text = tr("Active palette")
		b.pressed.connect(_on_palette_pressed.bind(id))
		flow.add_child(b)


func _on_palette_pressed(id: String) -> void:
	if id == UITheme.get_ui_palette():
		return   # already active — skip the reload
	UITheme.apply_palette(id)
	GameState.save_game()
	GameState.ui_return_page = "options"   # land back here after the rebuild
	get_tree().reload_current_scene()


func _section(title: String, category: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_FILL
	_column.add_child(panel)

	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 20)
	mc.add_theme_constant_override("margin_right", 20)
	mc.add_theme_constant_override("margin_top", 16)
	mc.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(mc)

	# Style + chrome last, so the ornament overlay stays the top sibling
	# (paints above the section content, matching the gameplay-card pattern).
	UITheme.apply_card_style(panel, category)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 11)
	mc.add_child(vb)

	var t := Label.new()
	t.text = title.to_upper()
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", Color.WHITE)
	vb.add_child(t)

	var rule := ColorRect.new()
	rule.color = UITheme.CATEGORY_COLORS.get(category, Color(0.216, 0.788, 0.690))
	rule.color.a = 0.30
	rule.custom_minimum_size = Vector2(0, 2)
	vb.add_child(rule)

	return vb


func _primary_button(text: String, category: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_premium_button_style(b, category)
	b.add_theme_font_size_override("font_size", 15)
	return b


# label + a full-width segmented selector. `get_cur` returns the active value,
# `on_pick` is called with the chosen value. Highlight is driven by _refresh_all.
func _add_choice_row(parent: VBoxContainer, label_text: String,
		opts: Array, get_cur: Callable, on_pick: Callable) -> void:
	# v137: segmented pill — label left, options as segments inside a recessed track;
	# the active segment fills teal. One control for On/Off and multi-choice settings.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.72, 0.83, 0.80))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.039, 0.086, 0.078)
	track.set_border_width_all(1)
	track.border_color = Color(0.141, 0.251, 0.231)
	track.set_corner_radius_all(8)
	track.content_margin_left = 3
	track.content_margin_right = 3
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", track)
	row.add_child(pill)
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 3)
	pill.add_child(seg)

	var btns: Array = []
	for o in opts:
		var b := Button.new()
		b.text = str(o[0])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(50, 30)
		b.add_theme_font_size_override("font_size", 13)
		var val = o[1]
		b.pressed.connect(func():
			on_pick.call(val)
			_refresh_all())
		seg.add_child(b)
		btns.append([b, val])
		_style_segment(b, val == get_cur.call())

	_refreshers.append(func():
		var cur = get_cur.call()
		for pair in btns:
			_style_segment(pair[0], pair[1] == cur))

func _style_segment(b: Button, active: bool) -> void:
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(5)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	if active:
		box.bg_color = Color(0.216, 0.788, 0.690)   # teal fill
		b.add_theme_stylebox_override("normal", box)
		b.add_theme_stylebox_override("hover", box)
		b.add_theme_stylebox_override("pressed", box)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", Color(0.024, 0.137, 0.114))
		b.add_theme_color_override("font_hover_color", Color(0.024, 0.137, 0.114))
	else:
		box.bg_color = Color(0, 0, 0, 0)             # transparent
		var hov := box.duplicate()
		hov.bg_color = Color(0.216, 0.788, 0.690, 0.10)
		b.add_theme_stylebox_override("normal", box)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_stylebox_override("pressed", hov)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", Color(0.43, 0.55, 0.53))
		b.add_theme_color_override("font_hover_color", Color(0.6, 0.72, 0.68))


func _refresh_all() -> void:
	for r in _refreshers:
		r.call()


# --------------------------------------------------------------------------
# Behaviour
# --------------------------------------------------------------------------
func _on_offline_combat_toggled(pressed: bool) -> void:
	# v125: first time it's switched ON, require explicit consent — offline combat
	# can destroy modules already worn to <=50% durability. Decline keeps it off;
	# the choice row repaints from the (unchanged) setting either way.
	if pressed and not GameState.game_settings.get("offline_combat_warned", false):
		UITheme.show_offline_combat_warning(
			Callable(self, "_on_offline_combat_consent"),
			Callable(self, "_on_offline_combat_decline"))
		return
	GameState.game_settings["offline_combat"] = pressed
	print("[Options] Offline Combat: ", pressed)


func _on_offline_combat_consent() -> void:
	GameState.game_settings["offline_combat"] = true
	GameState.game_settings["offline_combat_warned"] = true
	_refresh_all()


func _on_offline_combat_decline() -> void:
	GameState.game_settings["offline_combat"] = false
	_refresh_all()


func _on_cursor_size_pressed(px: int) -> void:
	GameState.game_settings["cursor_size"] = px
	CursorManager.apply_size(px)
	GameState.save_game()


func _on_card_frame_pressed(mode: int) -> void:
	GameState.game_settings["card_chrome"] = mode
	GameState.save_game()
	UITheme.chrome_changed.emit()  # live-repaint every visible card


func _on_reset_btn_pressed() -> void:
	# v112: themed modal (was the primitive Window ConfirmationDialog).
	var body := tr("Delete your save and restart from scratch?\n\n")
	body += tr("[color=#f06b6b]Everything is wiped — Liras, ships, research, Warp Mastery, prestige.[/color]\n\n")
	body += tr("[color=#ffb454][b]This cannot be undone.[/b][/color]")
	UITheme.show_confirm({
		"title": tr("Confirm Hard Reset"),
		"body": body,
		"confirm_text": tr("Yes, Delete Everything"),
		"cancel_text": tr("Cancel"),
		"accent": Color(0.95, 0.40, 0.40),   # alarm red frame
		"danger": true,
		"on_confirm": Callable(self, "_on_confirmation_dialog_confirmed"),
	})


func _on_confirmation_dialog_confirmed() -> void:
	GameState.hard_reset()
	get_tree().reload_current_scene()


func _on_replay_tutorials_pressed() -> void:
	GameState.game_settings["coach_seen"] = {}
	GameState.save_game()
	UITheme.show_notification("Tutorials reset — page tips will reappear as you visit each screen", Color(0.373, 0.878, 0.784))


# --------------------------------------------------------------------------
# Live readouts
# --------------------------------------------------------------------------
func _refresh_playtime() -> void:
	if _pt_label:
		_pt_label.text = tr("Total Play Time:  %s") % FormatUtils.format_playtime(GameState.total_playtime)


func _process(delta: float) -> void:
	if not visible:
		return
	_pt_refresh += delta
	if _pt_refresh >= 1.0:
		_pt_refresh = 0.0
		_refresh_playtime()


# Kept for external callers (e.g. page navigation) — re-sync selected states.
func update_ui() -> void:
	_refresh_all()
