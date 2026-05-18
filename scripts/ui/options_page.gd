extends Control

# Sys Config — rebuilt as a scrollable, sectioned settings screen.
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
var _tele_label: Label             # balance telemetry readout
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
	_build_testing_section()

	var foot := Label.new()
	foot.text = "Horizon Idle · prototype build · changes save automatically"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_theme_font_size_override("font_size", 11)
	foot.add_theme_color_override("font_color", Color(0.45, 0.47, 0.55))
	col.add_child(foot)

	_refresh_all()


# --------------------------------------------------------------------------
# Sections
# --------------------------------------------------------------------------
func _build_header() -> void:
	var body := _section("System Config", HEADER_CAT)
	var sub := Label.new()
	sub.text = "Save, gameplay and interface options."
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

	var save_btn := _primary_button("SAVE GAME", FRAME_CAT)
	save_btn.pressed.connect(_on_save_btn_pressed)
	body.add_child(save_btn)

	var warn := Label.new()
	warn.text = "Hard reset wipes your save permanently — this cannot be undone."
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
		 ["Holographic", UITheme.CHROME_HOLOGRAPHIC],
		 ["Precursor", UITheme.CHROME_PRECURSOR]],
		func(): return UITheme.get_card_chrome(),
		func(v): _on_card_frame_pressed(v))


func _build_testing_section() -> void:
	var body := _section("Testing", "research")

	var speed_opts := []
	for s in SPEED_OPTIONS:
		speed_opts.append(["%d×" % int(s), s])
	_add_choice_row(body, "Game Speed",
		speed_opts,
		func(): return Engine.time_scale,
		func(v): _set_game_speed(v))

	body.add_child(HSeparator.new())

	var tele_title := Label.new()
	tele_title.text = "Balance Telemetry (debug)"
	tele_title.add_theme_font_size_override("font_size", 12)
	tele_title.add_theme_color_override("font_color", Color(0.66, 0.7, 0.8))
	body.add_child(tele_title)

	_tele_label = Label.new()
	_tele_label.add_theme_font_size_override("font_size", 11)
	_tele_label.add_theme_color_override("font_color", Color(0.6, 0.85, 0.7))
	body.add_child(_tele_label)
	_refresh_telemetry()


# --------------------------------------------------------------------------
# Builders
# --------------------------------------------------------------------------
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
	rule.color = UITheme.CATEGORY_COLORS.get(category, Color(0.3, 0.6, 1.0))
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
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.66, 0.7, 0.8))
	parent.add_child(lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var btns: Array = []
	for o in opts:
		var b := Button.new()
		b.text = str(o[0])
		b.custom_minimum_size = Vector2(0, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.apply_premium_button_style(b, FRAME_CAT)
		b.add_theme_font_size_override("font_size", 14)
		var val = o[1]
		b.pressed.connect(func():
			on_pick.call(val)
			_refresh_all())
		row.add_child(b)
		btns.append([b, val])

	_refreshers.append(func():
		var cur = get_cur.call()
		for pair in btns:
			pair[0].modulate = SEL if pair[1] == cur else UNSEL)


func _refresh_all() -> void:
	for r in _refreshers:
		r.call()


# --------------------------------------------------------------------------
# Behaviour
# --------------------------------------------------------------------------
func _on_offline_combat_toggled(pressed: bool) -> void:
	GameState.game_settings["offline_combat"] = pressed
	print("[Options] Offline Combat: ", pressed)


func _on_cursor_size_pressed(px: int) -> void:
	GameState.game_settings["cursor_size"] = px
	CursorManager.apply_size(px)
	GameState.save_game()


func _on_card_frame_pressed(mode: int) -> void:
	GameState.game_settings["card_chrome"] = mode
	GameState.save_game()
	UITheme.chrome_changed.emit()  # live-repaint every visible card


func _set_game_speed(speed: float) -> void:
	Engine.time_scale = speed


func _on_save_btn_pressed() -> void:
	GameState.save_game()
	UITheme.show_notification("Game saved", Color(0.45, 0.9, 0.55))


func _on_reset_btn_pressed() -> void:
	$ConfirmationDialog.popup_centered()


func _on_confirmation_dialog_confirmed() -> void:
	GameState.hard_reset()
	get_tree().reload_current_scene()


func _on_replay_tutorials_pressed() -> void:
	GameState.game_settings["coach_seen"] = {}
	GameState.save_game()
	UITheme.show_notification("Tutorials reset — page tips will reappear as you visit each screen", Color(0.42, 0.84, 1.0))


# --------------------------------------------------------------------------
# Live readouts
# --------------------------------------------------------------------------
func _refresh_playtime() -> void:
	if _pt_label:
		_pt_label.text = "Total Play Time:  %s" % FormatUtils.format_playtime(GameState.total_playtime)


func _pct_line(d: Dictionary) -> String:
	var total := 0.0
	for k in d:
		total += float(d[k])
	if total <= 0.0:
		return "no data yet"
	var parts := []
	for k in d:
		var p := float(d[k]) / total * 100.0
		if p >= 0.5:
			parts.append("%s %d%%" % [k, int(round(p))])
	return ", ".join(parts) if not parts.is_empty() else "no data yet"


func _mat_line(ms: Dictionary) -> String:
	if ms.is_empty():
		return "no data yet"
	var parts := []
	for mat in ms:
		var c := float(ms[mat].get("combat", 0.0))
		var k := float(ms[mat].get("craft", 0.0))
		var tot := c + k
		if tot <= 0.0:
			continue
		parts.append("%s %d%% farmed" % [mat, int(round(c / tot * 100.0))])
	return ", ".join(parts) if not parts.is_empty() else "no data yet"


func _refresh_telemetry() -> void:
	if not _tele_label:
		return
	var t = GameState.telemetry
	_tele_label.text = "Active slot — %s\nProduction — %s\nMaterials — %s" % [
		_pct_line(t["occupancy"]), _pct_line(t["production"]), _mat_line(t.get("mat_source", {}))]


func _process(delta: float) -> void:
	if not visible:
		return
	_pt_refresh += delta
	if _pt_refresh >= 1.0:
		_pt_refresh = 0.0
		_refresh_playtime()
		_refresh_telemetry()


# Kept for external callers (e.g. page navigation) — re-sync selected states.
func update_ui() -> void:
	_refresh_all()
