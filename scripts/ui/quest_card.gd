extends PanelContainer

var quest: Dictionary
var parent_ui: Node

@onready var title_lbl = $Margin/VBox/HeaderHBox/TitleLabel
@onready var tier_lbl = $Margin/VBox/HeaderHBox/TierLabel
@onready var desc_lbl = $Margin/VBox/DescLabel
@onready var progress_lbl = $Margin/VBox/ProgressLabel
@onready var progress_bar = $Margin/VBox/ProgressBar
@onready var reward_lbl = $Margin/VBox/RewardLabel
@onready var claim_btn = $Margin/VBox/ClaimBtn

func setup(p_quest: Dictionary, p_parent: Node):
	quest = p_quest
	parent_ui = p_parent

	var category = "combat" if quest["type"] == "hunt" else "mission"
	UITheme.apply_card_style(self, category)
	UITheme.apply_premium_button_style(claim_btn, category)
	UITheme.apply_progress_bar_style(progress_bar, category)

	title_lbl.text = quest["title"]
	desc_lbl.text = quest["desc"]
	tier_lbl.text = "T%d" % int(quest.get("difficulty", 1))

	# Reward summary
	var reward_text = "+%s Cr" % UITheme.format_num(quest["reward_credits"])
	var mat = quest.get("reward_material", {})
	if mat and mat.size() > 0:
		var d_name = ElementDB.get_display_name(mat["id"])
		reward_text += "   +%d %s" % [mat["qty"], d_name]
	reward_lbl.text = reward_text

	claim_btn.pressed.connect(_on_claim_pressed)

	refresh_state()

func refresh_state():
	if not is_inside_tree(): return
	var cur = quest["current_qty"]
	var tot = quest["target_qty"]
	progress_bar.max_value = tot
	progress_bar.value = cur
	progress_lbl.text = "%s / %s" % [UITheme.format_num(cur), UITheme.format_num(tot)]

	if quest["claimed"]:
		claim_btn.text = "CLAIMED"
		claim_btn.disabled = true
		modulate = Color(0.5, 0.5, 0.5)
	elif quest["completed"]:
		claim_btn.text = "CLAIM REWARD"
		claim_btn.disabled = false
		modulate = Color(1.0, 1.05, 0.9)
	else:
		claim_btn.text = "IN PROGRESS"
		claim_btn.disabled = true
		modulate = Color.WHITE

func _on_claim_pressed():
	if parent_ui and parent_ui.has_method("on_claim"):
		parent_ui.on_claim(quest["id"])
