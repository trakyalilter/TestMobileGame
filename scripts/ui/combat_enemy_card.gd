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
	stats_lbl.text = "HP: %d | ATK: %d | DEF: %d" % [data["stats"]["hp"], data["stats"]["atk"], data["stats"]["def"]]
	
	UITheme.apply_card_style(self, "combat")
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
