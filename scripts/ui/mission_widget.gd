extends PanelContainer

var mid: String
var data: Dictionary
var manager: RefCounted
var parent_page: Node

@onready var status_lbl = $MarginContainer/VBoxContainer/StatusLabel
@onready var name_lbl = $MarginContainer/VBoxContainer/NameLabel
@onready var desc_lbl = $MarginContainer/VBoxContainer/DescLabel
@onready var progress_bar = $MarginContainer/VBoxContainer/ProgressBar
@onready var claim_btn = $MarginContainer/VBoxContainer/ClaimBtn

func setup(p_mid: String, p_data: Dictionary, p_manager, p_parent):
	mid = p_mid
	data = p_data
	manager = p_manager
	parent_page = p_parent
	
	name_lbl.text = data["name"]
	name_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["mission"])
	desc_lbl.text = data["description"]
	progress_bar.max_value = data["target_qty"]
	
	UITheme.apply_card_style(self, "mission")
	UITheme.apply_premium_button_style(claim_btn, "mission")
	UITheme.apply_progress_bar_style(progress_bar, "mission")
	
	update_state()

func _process(delta):
	# Polling update for progress
	update_state()

func update_state():
	progress_bar.value = data["current_qty"]
	
	if data["claimed"]:
		status_lbl.text = "COMPLETED"
		status_lbl.modulate = Color(0.3, 0.8, 0.3)
		claim_btn.text = "Claimed"
		claim_btn.disabled = true
		progress_bar.visible = false
		modulate.a = 0.6
	elif data["completed"]:
		status_lbl.text = "READY"
		status_lbl.modulate = Color(1.0, 0.8, 0.2)
		claim_btn.text = "Claim %d Liras" % data["reward_cr"]
		claim_btn.disabled = false
		progress_bar.visible = true
		modulate.a = 1.0
	else:
		status_lbl.text = "IN PROGRESS"
		status_lbl.modulate = Color(0.2, 0.7, 1.0)
		claim_btn.text = "%d Liras" % data["reward_cr"]
		claim_btn.disabled = true
		progress_bar.visible = true
		modulate.a = 1.0

func _on_claim_btn_pressed():
	if manager.claim_reward(mid):
		update_state()
