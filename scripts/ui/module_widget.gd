extends PanelContainer

var mid: String
var data: Dictionary
var manager: RefCounted
var parent_ui: Node

@onready var name_lbl = $MarginContainer/VBoxContainer/NameLabel
@onready var stats_lbl = $MarginContainer/VBoxContainer/StatsLabel
@onready var cost_lbl = $MarginContainer/VBoxContainer/CostLabel
@onready var owned_lbl = $MarginContainer/VBoxContainer/OwnedLabel
@onready var research_lbl = $MarginContainer/VBoxContainer/ResearchLabel
@onready var btn = $MarginContainer/VBoxContainer/Button

func setup(p_mid: String, p_data: Dictionary, p_manager, p_parent):
	mid = p_mid
	data = p_data
	manager = p_manager
	parent_ui = p_parent
	
	name_lbl.text = data["name"]
	name_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["shipyard"])
	
	UITheme.apply_card_style(self, "shipyard")
	UITheme.apply_premium_button_style(btn, "shipyard")
	
	var s_txt = ""
	var stats = data.get("stats", {})
	for k in stats:
		var label = FormatUtils.format_stat_label(k)
		var val = stats[k]
		s_txt += "%s: %s\n" % [label, FormatUtils.format_stat_value(k, val)]
	stats_lbl.text = s_txt.strip_edges()
	
	# Cost text handled dynamically in update_state
	cost_lbl.text = ""
	research_lbl.hide()

func _process(delta):
	update_state()

func update_state():
	var owned = manager.module_inventory.get(mid, 0)
	owned_lbl.text = "In Storage: %d" % owned
	
	# Check Research Requirements
	var req_id = data.get("research_req")
	var tech_unlocked = GameState.research_manager.is_tech_unlocked(req_id)
	
	if not tech_unlocked:
		var tech_name = GameState.research_manager.tech_tree.get(req_id, {}).get("name", req_id)
		UITheme.apply_locked_overlay(self, data["name"], "RESEARCH: %s" % tech_name, true)
		research_lbl.text = "Req: %s" % tech_name
		research_lbl.show()
		btn.disabled = true
		cost_lbl.hide()
		return
	else:
		UITheme.apply_locked_overlay(self, data["name"], "", false)
		research_lbl.hide()
		cost_lbl.show()

	var affordable = true
	var cost_str = "[center]"
	
	for res in data["cost"]:
		var qty = data["cost"][res]
		var can_afford = false
		var color = "gray" 
		
		if res == "credits":
			if GameState.resources.get_currency("credits") >= qty: 
				can_afford = true
				color = "lime"
		else:
			if GameState.resources.get_element_amount(res) >= qty: 
				can_afford = true
				color = "lime"
		
		if not can_afford:
			affordable = false
			
		cost_str += "[color=%s]%s %s[/color]\n" % [color, FormatUtils.format_number(qty), ElementDB.get_display_name(res)]
	
	cost_str += "[/center]"
	cost_lbl.text = cost_str
	
	btn.disabled = not affordable

func _on_button_pressed():
	if manager.craft_module(mid):
		UITheme.trigger_ui_thud(self, 8.0) # Manufacturing Thud
