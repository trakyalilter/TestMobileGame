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
	
	name_lbl.text = tr(data["name"])
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
		status_lbl.text = tr("COMPLETED")
		status_lbl.modulate = Color(0.3, 0.8, 0.3)
		claim_btn.text = tr("Claimed")
		claim_btn.disabled = true
		progress_bar.visible = false
		modulate.a = 0.6
	elif data["completed"]:
		status_lbl.text = tr("READY")
		status_lbl.modulate = Color(1.0, 0.8, 0.2)
		claim_btn.text = "Claim %s" % _reward_str()
		claim_btn.disabled = false
		progress_bar.visible = true
		modulate.a = 1.0
	else:
		status_lbl.text = tr("IN PROGRESS")
		status_lbl.modulate = Color(0.2, 0.7, 1.0)
		# v134: a disabled button reading just "8049 Liras" parsed as a COST to
		# new players. Name it as the reward.
		claim_btn.text = "Reward: %s" % _reward_str()
		claim_btn.disabled = true
		progress_bar.visible = true
		modulate.a = 1.0

# v134: claim_reward pays reward_cr x the warp production multiplier — show the
# amount that will ACTUALLY be paid (the raw base understated it after warping).
# reward_xp is granted too now, so surface it. format_number keeps late-game
# rewards readable (300K, 1.2M...). Goals like THE GREAT EXPEDITION pay XP only.
func _reward_str() -> String:
	var parts: Array = []
	var cr: float = float(data["reward_cr"])
	if cr > 0.0:
		if GameState.warp_manager:
			cr = cr * GameState.warp_manager.get_production_multiplier()
		parts.append("%s Liras" % FormatUtils.format_number(cr))
	var xp: float = float(data.get("reward_xp", 0))
	if xp > 0.0:
		parts.append("+%s XP" % FormatUtils.format_number(xp))
	if parts.is_empty():
		return "0 Liras"
	return "  ".join(parts)

func _on_claim_btn_pressed():
	if manager.claim_reward(mid):
		update_state()
