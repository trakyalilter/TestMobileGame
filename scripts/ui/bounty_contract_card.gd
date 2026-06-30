extends PanelContainer

var contract_data: Dictionary = {}
var parent_ui = null

@onready var title_lbl = $Margin/VBox/TitleLabel
@onready var desc_lbl = $Margin/VBox/DescLabel
@onready var progress_bar = $Margin/VBox/ProgressBar
@onready var reward_lbl = $Margin/VBox/RewardLabel
@onready var action_btn = $Margin/VBox/ActionBtn

func setup(data: Dictionary, p_parent, mode: String = "available"):
	contract_data = data
	parent_ui = p_parent
	
	title_lbl.text = data["title"]
	desc_lbl.text = data["desc"]
	
	# Progress
	progress_bar.max_value = data["target_qty"]
	progress_bar.value = data["current_qty"]
	progress_bar.visible = (mode == "active")
	
	# Reward preview
	var sm = GameState.shipyard_manager
	var negotiation = sm.affix_bonuses.get("contract_negotiation", 0.0)
	var final_reward = int(data["reward_credits"] * (1.0 + negotiation))
	
	var reward_txt = "Reward: %s CR" % UITheme.format_num(final_reward)
	if negotiation > 0:
		reward_txt += " (+%d%%)" % int(negotiation * 100)
		
	if data.get("reward_module_pool", []).size() > 0:
		reward_txt += " + Module Drop"
	reward_lbl.text = reward_txt
	
	# v74.0: Logistician's Edge UI
	if data["type"] == "delivery" and mode == "available":
		var logi_edge = sm.affix_bonuses.get("logistician_edge", 0.0)
		if logi_edge > 0:
			var eff_qty = int(data["target_qty"] * (1.0 - logi_edge))
			var d_name = ElementDB.get_display_name(data["target"])
			desc_lbl.text = "Deliver %d %s (Discounted: -%d%%)" % [eff_qty, d_name, int(logi_edge * 100)]
	
	# Action button
	match mode:
		"available":
			action_btn.text = "ACCEPT"
			action_btn.pressed.connect(_on_accept)
		"active":
			if data["completed"]:
				action_btn.text = "CLAIM ✓"
				action_btn.pressed.connect(_on_claim)
			else:
				action_btn.text = "ABANDON"
				action_btn.pressed.connect(_on_abandon)
	
	# Styling
	_apply_style(data, mode)

func _apply_style(data: Dictionary, mode: String):
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.10, 0.95)
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	
	if data.get("completed", false) and mode == "active":
		style.border_color = Color.GOLD
		UITheme.apply_premium_button_style(action_btn, "combat")
	elif mode == "available":
		style.border_color = Color(UITheme.COLORS["accent"], 0.6)
		UITheme.apply_premium_button_style(action_btn, "combat") # Standardized to Combat
	else:
		style.border_color = Color(UITheme.COLORS["text_dim"], 0.4)
		action_btn.modulate = Color(UITheme.COLORS["negative"], 0.7)

	add_theme_stylebox_override("panel", style)
	
	# Type icon
	var type_icon = "⚔" if data["type"] == "hunt" else "📦"
	title_lbl.text = "%s %s" % [type_icon, data["title"]]
	
	# Color the title by difficulty
	var diff = data.get("difficulty", 1)
	if diff >= 8:
		title_lbl.add_theme_color_override("font_color", UITheme.COLORS["negative"]) # Red
	elif diff >= 5:
		title_lbl.add_theme_color_override("font_color", UITheme.COLORS["warning"]) # amber (high diff)
	elif diff >= 3:
		title_lbl.add_theme_color_override("font_color", UITheme.COLORS["text_accent"]) # aqua (mid diff)
	else:
		title_lbl.add_theme_color_override("font_color", UITheme.COLORS["positive"]) # Light green

func _on_accept():
	if parent_ui and parent_ui.has_method("_on_contract_accepted"):
		parent_ui._on_contract_accepted(contract_data["id"])

func _on_claim():
	if parent_ui and parent_ui.has_method("_on_contract_claimed"):
		parent_ui._on_contract_claimed(contract_data["id"])

func _on_abandon():
	if parent_ui and parent_ui.has_method("_on_contract_abandoned"):
		parent_ui._on_contract_abandoned(contract_data["id"])
