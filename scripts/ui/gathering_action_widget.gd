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

# P1 Mastery — compact readout under the loot block: caption row +
# thin progress bar. Built once in setup(), refreshed in update_state().
var _mastery_left_lbl: Label
var _mastery_right_lbl: Label
var _mastery_bar: ProgressBar

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
	prog_bar.accent = UITheme.CATEGORY_COLORS["ops"]

	# Themed "work order" card: drill-motif backdrop + icon header, with the
	# yield framed as the payoff. Loot text still compiled in update_state().
	var glyph = load("res://assets/cursors/pages/gathering.svg") as Texture2D
	UITheme.inject_activity_header(self, "ops", glyph)
	var loot_panel = UITheme.wrap_in_io_panel(loot_lbl, "ops", "yield")
	UITheme.pin_card_footer(self)

	# Mastery panel sits directly under the YIELD panel (wrap_in_io_panel
	# returns the wrapper, which lives in this VBox at the label's old index).
	var card_vbox = $MarginContainer/VBoxContainer
	var after_idx = (loot_panel.get_index() + 1) if loot_panel else card_vbox.get_child_count()
	var mp = UITheme.build_mastery_panel(card_vbox, after_idx, "ops")
	_mastery_left_lbl = mp["left"]
	_mastery_right_lbl = mp["right"]
	_mastery_bar = mp["bar"]

func _on_button_pressed():
	if GameState.combat_manager and GameState.combat_manager.in_combat:
		return
	if manager.is_active and manager.current_action_id == aid:
		manager.stop_action()
	else:
		GameState.set_active_manager(manager)
		manager.start_action(aid)

	parent_ui.update_ui()

func _refresh_mastery():
	if not _mastery_bar or not manager:
		return
	var level = manager.get_mastery_level(aid)
	var prog = manager.get_mastery_progress(aid)
	var in_lvl = int(prog["in_level"])
	var needed = int(prog["needed"])
	if needed < 1:
		needed = 1
	var pct = float(in_lvl) / float(needed) * 100.0
	if pct < 0.0: pct = 0.0
	if pct > 100.0: pct = 100.0

	var col_dim = Color(0.48, 0.45, 0.41)
	var col_mid = Color(0.72, 0.65, 0.45)
	var col_bright = Color(0.83, 0.69, 0.22)
	var col_gold = Color(1.0, 0.84, 0.20)

	if level >= 100:
		_mastery_left_lbl.text = "★ GOLD MASTERY"
		_mastery_right_lbl.text = "LV 100"
		_mastery_left_lbl.add_theme_color_override("font_color", col_gold)
		_mastery_right_lbl.add_theme_color_override("font_color", col_gold)
		_mastery_bar.value = 100.0
		name_lbl.add_theme_color_override("font_color", col_gold)
	elif level >= 50:
		_mastery_left_lbl.text = "✦ MASTERY  LV %d" % level
		_mastery_right_lbl.text = "%d / %d" % [in_lvl, needed]
		_mastery_left_lbl.add_theme_color_override("font_color", col_bright)
		_mastery_right_lbl.add_theme_color_override("font_color", col_bright)
		_mastery_bar.value = pct
	elif level > 0:
		_mastery_left_lbl.text = "MASTERY  LV %d" % level
		_mastery_right_lbl.text = "%d / %d" % [in_lvl, needed]
		_mastery_left_lbl.add_theme_color_override("font_color", col_mid)
		_mastery_right_lbl.add_theme_color_override("font_color", col_mid)
		_mastery_bar.value = pct
	else:
		_mastery_left_lbl.text = "MASTERY  LV 0"
		_mastery_right_lbl.text = "%d / %d" % [in_lvl, needed]
		_mastery_left_lbl.add_theme_color_override("font_color", col_dim)
		_mastery_right_lbl.add_theme_color_override("font_color", col_dim)
		_mastery_bar.value = pct

func update_state():
	var is_this_active = (manager.is_active and manager.current_action_id == aid)
	_refresh_mastery()
	
	var lvl = manager.get_level()
	var req = data.get("level_req", 1)
	
	# Rebuild Loot String with Colors & Multipliers dynamically
	var loot_text = "[center]"
	var rates = manager.get_current_rate() if is_this_active else {}
	
	var eff_mult = 1.0
	if GameState.research_manager:
		eff_mult = GameState.research_manager.get_efficiency_multiplier()
		
	for entry in data["loot_table"]:
		var symbol = entry[0]
		var display_name = ElementDB.get_display_name(symbol)
		var base_loot = "%s: %s-%s" % [
			display_name, 
			FormatUtils.format_number(float(entry[2]) * eff_mult), 
			FormatUtils.format_number(float(entry[3]) * eff_mult)
		]
		
		if symbol in rates:
			loot_text += "%s [color=#55ff55](%s/m)[/color]\n" % [base_loot, FormatUtils.format_number(rates[symbol])]
		else:
			loot_text += "%s\n" % base_loot
			
	loot_text += "[/center]"
	loot_lbl.text = loot_text.strip_edges()
	
	var unlocked = true
	var status_msg = ""
	
	if lvl < req:
		unlocked = false
		status_msg = "LEVEL %d REQUIRED" % req
	
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
			prog_bar.active = true
			prog_bar.value = prog
			time_lbl.text = "%s / %s" % [FormatUtils.format_time(manager.action_progress), FormatUtils.format_time(effective_duration)]
		elif GameState.combat_manager and GameState.combat_manager.in_combat:
			btn.text = "IN COMBAT"
			btn.disabled = true
			btn.modulate = Color(1.0, 0.35, 0.35, 0.8)
			modulate = Color(0.85, 0.85, 0.85)
			prog_bar.active = false
			prog_bar.value = 0
			var speed_mult = manager.get_action_speed_multiplier(aid)
			time_lbl.text = "0.0s / %s" % FormatUtils.format_time(manager.action_duration / speed_mult)
		else:
			btn.text = "Start"
			btn.modulate = Color(1, 1, 1)
			modulate = Color(1, 1, 1)
			prog_bar.active = false
			prog_bar.value = 0
			var speed_mult = manager.get_action_speed_multiplier(aid)
			time_lbl.text = "0.0s / %s" % FormatUtils.format_time(manager.action_duration / speed_mult)
	else:
		var tech_id = data.get("research_req", "") if "RESEARCH:" in status_msg else ""
		UITheme.apply_locked_overlay(self, data["name"], status_msg, true, tech_id, "ops")
		
		# Context-sensitive Button Text
		if "RESEARCH:" in status_msg:
			btn.text = "RESEARCH REQUIRED"
		elif "LEVEL" in status_msg:
			btn.text = "LEVEL %d REQUIRED" % req
		else:
			btn.text = "LOCKED"
			
		btn.disabled = true
		status_lbl.text = status_msg
		modulate = Color(0.7, 0.7, 0.7)
		prog_bar.active = false
		prog_bar.value = 0
		time_lbl.text = "- / -"
