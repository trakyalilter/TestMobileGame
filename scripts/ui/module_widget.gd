extends PanelContainer

var mid: String
var data: Dictionary
var manager: RefCounted
var parent_ui: Node
var target_slot_idx: int = -1

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
	
	_update_stats_text()
	
	cost_lbl.text = ""
	research_lbl.hide()
	
	# Comparison tooltip on hover
	mouse_entered.connect(_on_hover_enter)
	mouse_exited.connect(_on_hover_exit)

func _update_stats_text():
	var s_txt = ""
	var stats = data.get("stats", {})
	for k in stats:
		var label = FormatUtils.format_stat_label(k)
		var val = stats[k]
		s_txt += "%s: %s\n" % [label, FormatUtils.format_stat_value(k, val)]
	stats_lbl.text = s_txt.strip_edges()



func update_state():
	var owned = manager.module_inventory.get(mid, 0)
	owned_lbl.text = "In Storage: %d" % owned
	
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
	if target_slot_idx >= 0:
		# Equip to specific slot
		if manager.module_inventory.get(mid, 0) > 0:
			if manager.equip_module(target_slot_idx, mid):
				UITheme.trigger_ui_thud(self, 10.0)
				if parent_ui.has_method("_build_slot_grid"):
					parent_ui._build_slot_grid()
		target_slot_idx = -1
		_reset_highlight()
	else:
		# Craft module
		if manager.craft_module(mid):
			UITheme.trigger_ui_thud(self, 8.0)

# ─────────────────────────────────────────────────
# SLOT HIGHLIGHTING
# ─────────────────────────────────────────────────

func highlight_for_slot(slot_idx: int, req_type: String):
	var my_type = data.get("slot_type", "")
	if my_type == req_type and manager.module_inventory.get(mid, 0) > 0:
		target_slot_idx = slot_idx
		modulate = Color(0.5, 1.0, 0.5, 1.0)  # Green highlight
		btn.text = "EQUIP"
	else:
		_reset_highlight()

func _reset_highlight():
	target_slot_idx = -1
	modulate = Color.WHITE
	btn.text = "Craft"

# ─────────────────────────────────────────────────
# COMPARISON TOOLTIP
# ─────────────────────────────────────────────────

func _on_hover_enter():
	tooltip_text = _build_comparison_tooltip()

func _on_hover_exit():
	pass

func _build_comparison_tooltip() -> String:
	var tt = data["name"] + "\n"
	tt += "─────────────────\n"
	
	var my_stats = data.get("stats", {})
	var slot_type = data.get("slot_type", "weapon")
	
	# Find currently equipped module of same type for comparison
	var equipped_mid = null
	for idx in manager.loadout:
		var m = manager.loadout[idx]
		if m and m in manager.modules:
			var m_data = manager.modules[m]
			if m_data.get("slot_type") == slot_type:
				equipped_mid = m
				break
	
	for k in my_stats:
		var label = FormatUtils.format_stat_label(k)
		var val = my_stats[k]
		var delta_str = ""
		
		if equipped_mid and equipped_mid != mid:
			var eq_stats = manager.modules[equipped_mid].get("stats", {})
			var eq_val = eq_stats.get(k, 0)
			var diff = val - eq_val
			if diff > 0:
				delta_str = " [color=lime](+%s ↑)[/color]" % FormatUtils.format_stat_value(k, diff)
			elif diff < 0:
				delta_str = " [color=red](%s ↓)[/color]" % FormatUtils.format_stat_value(k, diff)
		
		tt += "%s: %s%s\n" % [label, FormatUtils.format_stat_value(k, val), delta_str]
	
	if equipped_mid and equipped_mid != mid:
		tt += "─────────────────\n"
		tt += "Compared to: %s" % manager.modules[equipped_mid]["name"]
	
	if data.has("desc"):
		tt += "\n─────────────────\n"
		tt += data["desc"]
	
	return tt
