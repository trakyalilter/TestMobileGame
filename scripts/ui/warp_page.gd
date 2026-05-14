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

	if wm.total_warps == 0:
		shard_desc.text = "FIRST WARP — Permanently unlocks:\n• Prestige multipliers (Production / Combat / Gathering / XP)\n• Warp Tier scaling (doubles every 5 warps)\n• Starting resource package on each future warp"
		shard_desc.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
	else:
		var tier = wm.warp_tier if "warp_tier" in wm else int(wm.total_warps / 5)
		shard_desc.text = "Warp %d  |  Tier %d  |  ×%.0f multiplier scale\n+%.0f%% Production | +%.0f%% Combat | +%.0f%% Gathering | +%.0f%% XP" % [
			wm.total_warps,
			tier,
			pow(2, tier),
			(wm.get_production_multiplier() - 1.0) * 100.0,
			(wm.get_combat_multiplier() - 1.0) * 100.0,
			(wm.get_gathering_multiplier() - 1.0) * 100.0,
			(wm.get_xp_multiplier() - 1.0) * 100.0
		]
		shard_desc.add_theme_color_override("font_color", Color.WHITE)

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

func _on_warped(gains):
	_update_ui()
	UITheme.trigger_circuit_surge(shard_count)
	var wm = GameState.warp_manager
	gain_label.text = "WARP COMPLETE — +%d Shards gained  |  Total: %.1f  |  Next tier in %d warps" % [
		gains,
		wm.warp_shards,
		5 - (wm.total_warps % 5)
	]
	gain_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7))

func _on_back_btn_pressed():
	if get_tree().current_scene.has_method("switch_to"):
		get_tree().current_scene.switch_to("mission")
