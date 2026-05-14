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
