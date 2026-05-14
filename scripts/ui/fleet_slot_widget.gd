extends PanelContainer

var slot_idx: int
var manager: RefCounted
var parent_ui: Node

@onready var status_lbl = $MarginContainer/VBoxContainer/Header/StatusLabel
@onready var mission_name = $MarginContainer/VBoxContainer/MissionLabel
@onready var ship_name = $MarginContainer/VBoxContainer/ShipLabel
@onready var progress_bar = $MarginContainer/VBoxContainer/ProgressBar
@onready var earnings_lbl = $MarginContainer/VBoxContainer/EarningsLabel
@onready var deploy_btn = $MarginContainer/VBoxContainer/ActionBox/DeployBtn
@onready var recall_btn = $MarginContainer/VBoxContainer/ActionBox/RecallBtn

func setup(p_idx: int, p_manager: RefCounted, p_parent: Node):
	slot_idx = p_idx
	manager = p_manager
	parent_ui = p_parent
	
	UITheme.apply_card_style(self, "mission")
	UITheme.apply_premium_button_style(deploy_btn, "mission")
	UITheme.apply_premium_button_style(recall_btn, "combat")
	UITheme.apply_progress_bar_style(progress_bar, "mission")
	
	UITheme.add_hover_scale(self)
	
	update_state()

func _process(delta):
	update_state()

func update_state():
	var active = manager.active_expeditions.get(slot_idx)
	
	if active:
		deploy_btn.visible = false
		recall_btn.visible = true
		progress_bar.visible = true
		
		var m_data = manager.missions[active["mission_id"]]
		var speed_bonus = GameState.research_manager.get_efficiency_bonus("fleet_speed") if GameState.research_manager else 0.0
		var effective_interval = m_data["interval"] / (1.0 + speed_bonus)
		
		mission_name.text = m_data["name"]
		ship_name.text = "Ship: " + active["hull_id"].capitalize()
		progress_bar.max_value = effective_interval
		progress_bar.value = active["progress"]

		var risk = m_data.get("risk", 0.0)
		if risk >= 0.30:
			status_lbl.text = "EXPEDITION ACTIVE  ⚠ EXTREME RISK"
			status_lbl.modulate = Color(1.0, 0.2, 0.2)
		elif risk >= 0.15:
			status_lbl.text = "EXPEDITION ACTIVE  ⚠ HIGH RISK"
			status_lbl.modulate = Color(1.0, 0.6, 0.1)
		else:
			status_lbl.text = "EXPEDITION ACTIVE"
			status_lbl.modulate = Color.CYAN
		
		# Earnings preview
		var earn_str = "Yielded: "
		if active["total_earned"].is_empty():
			earn_str += "Starting..."
		else:
			for res in active["total_earned"]:
				earn_str += "%s: %d, " % [res, active["total_earned"][res]]
		earnings_lbl.text = earn_str.strip_edges().trim_suffix(",")
	else:
		deploy_btn.visible = true
		recall_btn.visible = false
		progress_bar.visible = false
		mission_name.text = "Empty Fleet Slot"
		ship_name.text = "No Ship Assigned"
		status_lbl.text = "IDLE"
		status_lbl.modulate = Color.GRAY
		earnings_lbl.text = "Assign a hull to begin background scavenging."

func _on_deploy_btn_pressed():
	# For now, simplest deployment logic (Auto-pick available Corvette + Alpha Mission)
	# In a full UI, this would open a selection modal.
	var missions = manager.get_available_missions()
	if missions.is_empty(): return
	
	# Simple auto-picker for demonstration
	var preferred_hull = ""
	for h in GameState.shipyard_manager.hulls:
		if h != GameState.shipyard_manager.active_hull:
			preferred_hull = h
			break
			
	if preferred_hull != "":
		manager.deploy_fleet(slot_idx, missions[0], preferred_hull)

func _on_recall_btn_pressed():
	manager.recall_fleet(slot_idx)
