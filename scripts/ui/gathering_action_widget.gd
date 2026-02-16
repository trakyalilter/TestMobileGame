extends PanelContainer

var aid: String
var data: Dictionary
var manager: RefCounted
var parent_ui: Node

@onready var name_lbl = $MarginContainer/VBoxContainer/NameLabel
@onready var lvl_lbl = $MarginContainer/VBoxContainer/LevelLabel
@onready var loot_lbl = $MarginContainer/VBoxContainer/LootLabel
@onready var btn = $MarginContainer/VBoxContainer/Button
@onready var status_lbl = $MarginContainer/VBoxContainer/StatusLabel
@onready var time_lbl = $MarginContainer/VBoxContainer/TimeLabel
@onready var prog_bar = $MarginContainer/VBoxContainer/ProgressBar

func setup(p_aid: String, p_data: Dictionary, p_manager, p_parent):
	aid = p_aid
	data = p_data
	manager = p_manager
	parent_ui = p_parent
	
	name_lbl.text = data["name"]
	name_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["ops"])
	var req = data.get("level_req", 1)
	lvl_lbl.text = "Lvl %d" % req
	
	UITheme.apply_card_style(self, "ops")
	UITheme.apply_premium_button_style(btn, "ops")
	UITheme.apply_progress_bar_style(prog_bar, "ops")
	
	var loot_text = "[center]"
	var rates = manager.get_current_rate() if manager.is_active and manager.current_action_id == aid else {}
	
	for entry in data["loot_table"]:
		var symbol = entry[0]
		var display_name = ElementDB.get_display_name(symbol)
		var base_loot = "%s: %d-%d" % [display_name, entry[2], entry[3]]
		
		if symbol in rates:
			loot_text += "%s [color=#55ff55](%s/m)[/color]\n" % [base_loot, FormatUtils.format_number(rates[symbol])]
		else:
			loot_text += "%s\n" % base_loot
			
	loot_text += "[/center]"
	loot_lbl.text = loot_text.strip_edges()

func _on_button_pressed():
	if manager.is_active and manager.current_action_id == aid:
		manager.stop_action()
	else:
		GameState.set_active_manager(manager)
		manager.start_action(aid)
	
	parent_ui.update_ui()

func update_state():
	var is_this_active = (manager.is_active and manager.current_action_id == aid)
	
	var lvl = manager.get_level()
	var req = data.get("level_req", 1)
	
	var unlocked = true
	var status_msg = ""
	
	if lvl < req:
		unlocked = false
		status_msg = "Level Locked"
	
	# Research Check
	if "research_req" in data and data["research_req"]:
		if GameState.research_manager and not GameState.research_manager.is_tech_unlocked(data["research_req"]):
			unlocked = false
			var tech_name = GameState.research_manager.tech_tree.get(data["research_req"], {}).get("name", "Unknown Tech")
			status_msg = "RESEARCH: %s" % tech_name.to_upper()
	
	if unlocked:
		UITheme.apply_locked_overlay(self, data["name"], "", false)
		status_lbl.text = ""
		btn.disabled = false
		if is_this_active:
			btn.text = "Stop"
			btn.modulate = Color(1.0, 0.4, 0.4) # Red-ish
			modulate = Color(1.2, 1, 1) # Highlight
			
			var speed_mult = manager.get_action_speed_multiplier(aid)
			var effective_duration = manager.action_duration / speed_mult
			var prog = (manager.action_progress / effective_duration) * 100.0
			prog_bar.value = prog
			time_lbl.text = "%s / %s" % [FormatUtils.format_time(manager.action_progress), FormatUtils.format_time(effective_duration)]
		else:
			btn.text = "Start"
			btn.modulate = Color(1, 1, 1)
			modulate = Color(1, 1, 1)
			prog_bar.value = 0
			var speed_mult = manager.get_action_speed_multiplier(aid)
			time_lbl.text = "0.0s / %s" % FormatUtils.format_time(manager.action_duration / speed_mult)
	else:
		UITheme.apply_locked_overlay(self, data["name"], status_msg, true)
		
		# Context-sensitive Button Text
		if "RESEARCH:" in status_msg:
			btn.text = "RESEARCH REQUIRED"
		elif "Level" in status_msg:
			btn.text = "LEVEL %d REQUIRED" % req
		else:
			btn.text = "LOCKED"
			
		btn.disabled = true
		status_lbl.text = status_msg
		modulate = Color(0.7, 0.7, 0.7)
		prog_bar.value = 0
		time_lbl.text = "- / -"
