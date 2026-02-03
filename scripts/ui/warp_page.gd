extends Control

@onready var shard_count = $VBox/Header/ShardCount
@onready var shard_desc = $VBox/Header/ShardDesc
@onready var gain_label = $VBox/WarpCore/Status/PotentialGain
@onready var warp_btn = $HBox/ExecuteBtn
@onready var back_btn = $HBox/BackBtn

func _ready():
	_update_ui()
	GameState.warp_manager.warped.connect(_on_warped)

func _process(_delta):
	_update_dynamic_values()

func _update_ui():
	var wm = GameState.warp_manager
	shard_count.text = "EXOTIC MATTER: %.1f Shards" % wm.warp_shards
	# Audit v3.0: Show all 4 prestige multipliers
	shard_desc.text = "+%.0f%% Production | +%.0f%% Combat | +%.0f%% Gathering | +%.0f%% XP" % [
		(wm.get_production_multiplier() - 1.0) * 100.0,
		(wm.get_combat_multiplier() - 1.0) * 100.0,
		(wm.get_gathering_multiplier() - 1.0) * 100.0,
		(wm.get_xp_multiplier() - 1.0) * 100.0
	]

func _update_dynamic_values():
	var gains = GameState.warp_manager.calculate_warp_gains()
	gain_label.text = "Potential Gains: +%d Shards" % gains
	warp_btn.disabled = gains <= 0

func _on_execute_btn_pressed():
	# Confirmation logic
	_show_confirmation()

func _show_confirmation():
	var gains = GameState.warp_manager.calculate_warp_gains()
	var msg = "WARP CORE RESONANCE DETECTED.\n\nExecuting this command will reset your Credits, Industrial Infrastructure, and Standard Materials.\n\nYou will gain %d EXOTIC MATTER SHARDS.\n\nPROCEED WITH SYSTEM RESTART?" % gains
	
	# For now, just execute if confirmed via prompt or simple button check
	# In a real game we'd use a Modal.
	GameState.warp_manager.execute_warp()

func _on_warped(_gains):
	_update_ui()
	UITheme.trigger_circuit_surge(shard_count)
	# Switch to mission page or similar handled by GameState signal

func _on_back_btn_pressed():
	if get_tree().current_scene.has_method("switch_to"):
		get_tree().current_scene.switch_to("mission")
