extends Control

@onready var reset_btn = $CenterContainer/VBoxContainer/ResetBtn
@onready var save_btn = $CenterContainer/VBoxContainer/SaveBtn
@onready var offline_combat_check = $CenterContainer/VBoxContainer/OfflineCombatCheck
@onready var speed_container = $CenterContainer/VBoxContainer/SpeedContainer

const SPEED_OPTIONS = [1.0, 2.0, 4.0, 8.0, 16.0]

func _ready():
	# v52.1: Sync checkbox with game settings
	if offline_combat_check:
		offline_combat_check.button_pressed = GameState.game_settings.get("offline_combat", false)
		offline_combat_check.toggled.connect(_on_offline_combat_toggled)
	_setup_speed_buttons()
	_add_replay_tutorials_btn()
	_add_cursor_size_row()
	_add_playtime_label()
	_add_telemetry_readout()

var _cursor_btns: Array = []

func _add_cursor_size_row():
	var vb = $CenterContainer/VBoxContainer
	if not vb: return

	var label = Label.new()
	label.text = "Cursor Size"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.7, 0.74, 0.82))
	vb.add_child(label)

	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)

	var opts = [
		["Small", CursorManager.SIZE_SMALL],
		["Medium", CursorManager.SIZE_MEDIUM],
		["Large", CursorManager.SIZE_LARGE],
	]
	for o in opts:
		var b = Button.new()
		b.text = o[0]
		b.set_meta("px", o[1])
		b.pressed.connect(_on_cursor_size_pressed.bind(o[1]))
		row.add_child(b)
		_cursor_btns.append(b)

	# Place the label+row just under the speed selector.
	if speed_container:
		var base = speed_container.get_index() + 1
		vb.move_child(label, base)
		vb.move_child(row, base + 1)

	_update_cursor_buttons()

func _on_cursor_size_pressed(px: int):
	GameState.game_settings["cursor_size"] = px
	CursorManager.apply_size(px)
	GameState.save_game()
	_update_cursor_buttons()

func _update_cursor_buttons():
	var cur = CursorManager.get_size()
	for b in _cursor_btns:
		b.modulate = Color(0.4, 1.0, 0.4) if int(b.get_meta("px")) == cur else Color(1, 1, 1)

var _pt_label: Label
var _pt_refresh: float = 0.0

func _add_playtime_label():
	var vb = $CenterContainer/VBoxContainer
	if not vb: return
	_pt_label = Label.new()
	_pt_label.name = "PlayTimeLabel"
	_pt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pt_label.add_theme_color_override("font_color", Color(0.55, 0.78, 0.95))
	vb.add_child(_pt_label)
	vb.move_child(_pt_label, 0)  # top of the system panel
	_refresh_playtime()

func _refresh_playtime():
	if _pt_label:
		_pt_label.text = "Total Play Time:  %s" % FormatUtils.format_playtime(GameState.total_playtime)

# P3.10: read-only balance instrumentation readout.
var _tele_label: Label

func _add_telemetry_readout():
	var vb = $CenterContainer/VBoxContainer
	if not vb: return
	vb.add_child(HSeparator.new())
	var header = Label.new()
	header.text = "Balance Telemetry (debug)"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", Color(0.7, 0.74, 0.82))
	vb.add_child(header)
	_tele_label = Label.new()
	_tele_label.name = "TelemetryLabel"
	_tele_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tele_label.add_theme_color_override("font_color", Color(0.6, 0.85, 0.7))
	vb.add_child(_tele_label)
	_refresh_telemetry()

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

func _refresh_telemetry():
	if not _tele_label: return
	var t = GameState.telemetry
	_tele_label.text = "Active slot — %s\nProduction — %s" % [_pct_line(t["occupancy"]), _pct_line(t["production"])]

func _process(delta):
	if not visible:
		return
	_pt_refresh += delta
	if _pt_refresh >= 1.0:
		_pt_refresh = 0.0
		_refresh_playtime()
		_refresh_telemetry()

func _add_replay_tutorials_btn():
	var vb = $CenterContainer/VBoxContainer
	if not vb: return
	var btn = Button.new()
	btn.name = "ReplayTutorialsBtn"
	btn.text = "Replay Tutorials"
	btn.pressed.connect(_on_replay_tutorials_pressed)
	vb.add_child(btn)
	# Sit it just under the offline-combat checkbox if possible.
	if offline_combat_check:
		vb.move_child(btn, offline_combat_check.get_index() + 1)

func _on_replay_tutorials_pressed():
	GameState.game_settings["coach_seen"] = {}
	GameState.save_game()
	UITheme.show_notification("Tutorials reset — page tips will reappear as you visit each screen", Color(0.42, 0.84, 1.0))

func _on_offline_combat_toggled(pressed: bool):
	GameState.game_settings["offline_combat"] = pressed
	print("[Options] Offline Combat: ", pressed)

func _on_reset_btn_pressed():
	# Confirmation Dialog? 
	# For simplicity in Godot prototype, just do it or show simple confirmation.
	# Using OS.alert for a quick confirm is not standard, let's use a visibility toggle panel or just do it.
	# Let's create a confirmation popup in scene.
	
	$ConfirmationDialog.visible = true
	$ConfirmationDialog.popup_centered()

func _on_save_btn_pressed():
	GameState.save_game()
	# Maybe show a toast/label saying "Game Saved"?
	# For now just print or maybe small popup
	var confirm = $ConfirmationDialog
	confirm.title = "Game Saved"
	confirm.dialog_text = "Progress has been saved successfully."
	confirm.get_ok_button().text = "OK"
	confirm.ok_button_text = "OK" # Property
	
	# Disconnect any old signal
	if confirm.confirmed.is_connected(_on_confirmation_dialog_confirmed):
		confirm.confirmed.disconnect(_on_confirmation_dialog_confirmed)
	
	confirm.popup_centered()

func _on_confirmation_dialog_confirmed():
	GameState.hard_reset()
	# Maybe reload scene to ensure clean state?
	get_tree().reload_current_scene()

func _setup_speed_buttons():
	for i in speed_container.get_child_count():
		var btn = speed_container.get_child(i)
		var speed = SPEED_OPTIONS[i]
		btn.pressed.connect(func(): _set_game_speed(speed))
	_update_speed_buttons()

func _set_game_speed(speed: float):
	Engine.time_scale = speed
	_update_speed_buttons()

func _update_speed_buttons():
	for i in speed_container.get_child_count():
		var btn = speed_container.get_child(i)
		if SPEED_OPTIONS[i] == Engine.time_scale:
			btn.modulate = Color(0.4, 1.0, 0.4)
		else:
			btn.modulate = Color(1, 1, 1)

func update_ui():
	# v52.1: Refresh checkbox state
	if offline_combat_check:
		offline_combat_check.button_pressed = GameState.game_settings.get("offline_combat", false)
	_update_speed_buttons()
