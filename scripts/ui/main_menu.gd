extends Control

@onready var btn_continue = $MenuVBox/BtnContinue
@onready var btn_new_game = $MenuVBox/BtnNewGame
@onready var btn_options = $MenuVBox/BtnOptions
@onready var btn_exit = $MenuVBox/BtnExit

@onready var menu_vbox = $MenuVBox
@onready var options_panel = $OptionsPanel
@onready var chk_offline_combat = $OptionsPanel/HBox/BtnOfflineCombat
@onready var btn_back = $OptionsPanel/BtnBack

@onready var background = $Background

func _ready():
	_apply_styles()
	
	btn_continue.pressed.connect(_on_continue_pressed)
	btn_new_game.pressed.connect(_on_new_game_pressed)
	btn_options.pressed.connect(_on_options_pressed)
	btn_exit.pressed.connect(_on_exit_pressed)
	
	btn_back.pressed.connect(_on_back_pressed)
	chk_offline_combat.toggled.connect(_on_offline_combat_toggled)
	
	var has_save = FileAccess.file_exists("user://savegame.json")
	btn_continue.disabled = not has_save
	if not has_save:
		btn_continue.text = "Continue (No Save Data)"

func _apply_styles():
	UITheme.apply_premium_button_style(btn_continue, "generic")
	UITheme.apply_premium_button_style(btn_new_game, "generic")
	UITheme.apply_premium_button_style(btn_options, "generic")
	UITheme.apply_premium_button_style(btn_exit, "combat")
	UITheme.apply_premium_button_style(btn_back, "generic")
	
	background.color = UITheme.COLORS["background"]

func _on_continue_pressed():
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_new_game_pressed():
	# Wait for GameState to be ready just in case, though it is an Autoload
	GameState.hard_reset()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_options_pressed():
	menu_vbox.hide()
	options_panel.show()
	chk_offline_combat.button_pressed = GameState.game_settings.get("offline_combat", false)

func _on_back_pressed():
	options_panel.hide()
	menu_vbox.show()

func _on_offline_combat_toggled(pressed: bool):
	GameState.game_settings["offline_combat"] = pressed
	GameState.save_game()

func _on_exit_pressed():
	get_tree().quit()
