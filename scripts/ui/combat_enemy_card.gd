extends PanelContainer

var eid
var data
var parent_ui

@onready var name_lbl = $MarginContainer/VBoxContainer/NameLabel
@onready var stats_lbl = $MarginContainer/VBoxContainer/StatsLabel
@onready var loot_lbl = $MarginContainer/VBoxContainer/LootLabel

func setup(p_eid, p_data, p_parent):
	eid = p_eid
	data = p_data
	parent_ui = p_parent
	
	name_lbl.text = data["name"]
	name_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["combat"])
	
	# v87.0: Show damage type in compact stats
	var dmg_tag = "KIN"
	match data.get("dmg_type", "kinetic"):
		"energy": dmg_tag = "NRG"
		"explosive": dmg_tag = "EXP"
	stats_lbl.text = "HP: %s | ATK: %s %s | DEF: %d" % [UITheme.format_num(data["stats"]["hp"]), UITheme.format_num(data["stats"]["atk"]), dmg_tag, data["stats"]["def"]]

	# Resistance / vulnerability one-liner
	var rk = data.get("resist_k", 0.0)
	var re = data.get("resist_e", 0.0)
	var rx = data.get("resist_x", 0.0)
	var resist_parts = []
	var weak_parts = []
	if rk > 0.05:   resist_parts.append("KIN")
	elif rk < -0.05: weak_parts.append("KIN")
	if re > 0.05:   resist_parts.append("NRG")
	elif re < -0.05: weak_parts.append("NRG")
	if rx > 0.05:   resist_parts.append("EXP")
	elif rx < -0.05: weak_parts.append("EXP")

	var resist_line = ""
	if resist_parts.size() > 0:
		resist_line += "RESIST: " + ", ".join(resist_parts)
	if weak_parts.size() > 0:
		if resist_line != "": resist_line += "  "
		resist_line += "WEAK: " + ", ".join(weak_parts)

	if resist_line != "" and has_node("MarginContainer/VBoxContainer/ResistLabel"):
		$MarginContainer/VBoxContainer/ResistLabel.text = resist_line
	elif resist_line != "":
		var rl = Label.new()
		rl.name = "ResistLabel"
		rl.add_theme_font_size_override("font_size", 10)
		rl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 0.85))
		rl.text = resist_line
		$MarginContainer/VBoxContainer.add_child(rl)
		$MarginContainer/VBoxContainer.move_child(rl, stats_lbl.get_index() + 1)
	
	UITheme.apply_card_style(self, "combat")
	UITheme.inject_diegetic_header(self, "combat")
	
	if has_node("MarginContainer/VBoxContainer/Actions/FightBtn"):
		UITheme.apply_premium_button_style($MarginContainer/VBoxContainer/Actions/FightBtn, "combat")
	
	var loot_txt = "Drops: "
	for entry in data["loot"]:
		var d_name = ElementDB.get_display_name(entry[0])
		loot_txt += d_name + ", "
	
	# v71.4: Include modules in drop summary
	var m_pool = data.get("module_drop_pool", [])
	if m_pool.size() > 0:
		loot_txt = loot_txt.trim_suffix(", ") + "\n+ %d Ship Modules" % m_pool.size()
			
	loot_lbl.text = loot_txt.trim_suffix(", ")

func _on_fight_btn_pressed():
	parent_ui.request_fight(eid)

func _on_info_btn_pressed():
	parent_ui.show_enemy_info(data)
