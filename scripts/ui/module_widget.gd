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
	
	# v74.0: Display Affixes
	if data.get("affixes", {}).size() > 0:
		var a_txt = "\n"
		var sm = GameState.shipyard_manager
		var affixes = data["affixes"]
		for aid in affixes:
			if aid in sm.AFFIX_DB:
				var cfg = sm.AFFIX_DB[aid]
				var val = int(affixes[aid] * 100)
				var a_desc = cfg["desc"] % val
				a_txt += "\n[ %s ]\n" % a_desc
		stats_lbl.text += a_txt



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
	
	if data.get("is_custom", false):
		cost_lbl.text = "[center][color=orange]Drop-only module[/color][/center]"
		btn.text = "DROP ONLY"
		btn.disabled = true
		return

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
				UITheme.trigger_ui_thud(btn, 6.0)
				update_state()
				if parent_ui.has_method("_build_slot_grid"):
					parent_ui._build_slot_grid()
		target_slot_idx = -1
		_reset_highlight()
	else:
		# Craft module
		if manager.craft_module(mid):
			UITheme.trigger_ui_thud(btn, 5.0)
			update_state()

# ─────────────────────────────────────────────────
# SLOT HIGHLIGHTING
# ─────────────────────────────────────────────────

func highlight_for_slot(slot_idx: int, req_type: String):
	var my_type = data.get("slot_type", "")
	if my_type == req_type and manager.module_inventory.get(mid, 0) > 0:
		target_slot_idx = slot_idx
		modulate = Color(0.5, 1.0, 0.5, 1.0)  # Green highlight
		btn.text = "EQUIP"
		btn.disabled = false
	else:
		_reset_highlight()

func _reset_highlight():
	target_slot_idx = -1
	modulate = Color.WHITE
	if data.get("is_custom", false):
		btn.text = "DROP ONLY"
		btn.disabled = true
	else:
		btn.text = "Craft"

# ─────────────────────────────────────────────────
# COMPARISON TOOLTIP
# ─────────────────────────────────────────────────

func _on_hover_enter():
	tooltip_text = _build_comparison_tooltip()

func _on_hover_exit():
	pass

func _make_custom_tooltip(_for_text: String) -> Control:
	var panel = PanelContainer.new()
	var sm = GameState.shipyard_manager
	var rarity = data.get("rarity", sm.Rarity.COMMON)
	var r_color = sm.RARITY_COLORS.get(rarity, Color(0.2, 0.2, 0.2))
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.98)
	style.border_color = r_color
	style.border_color.a = 0.8
	style.set_border_width_all(1)
	style.border_width_top = 4
	style.set_corner_radius_all(2)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	
	var rtl = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.custom_minimum_size = Vector2(320, 0)
	rtl.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	
	rtl.text = _build_comparison_tooltip()
	panel.add_child(rtl)
	
	return panel

func _build_comparison_tooltip() -> String:
	if not data: return ""
	
	var sm = GameState.shipyard_manager
	var rarity = data.get("rarity", sm.Rarity.COMMON)
	var rarity_label = sm.RARITY_LABELS.get(rarity, "Common")
	if rarity == sm.Rarity.COMMON: rarity_label = "Common"
	
	var rarity_color_hex = sm.RARITY_COLORS.get(rarity, Color.GRAY).to_html(false)
	var slot_type = data.get("slot_type", "weapon")
	
	var tt = ""
	
	# 1. HEADER
	var display_name = data.get("name", "Item").to_upper()
	for suffix in [" (COMMON)", " (UNCOMMON)", " (RARE)", " (LEGENDARY)"]:
		display_name = display_name.replace(suffix, "")
		
	tt += "[center][b][font_size=16][color=#%s]%s[/color][/font_size][/b]\n" % [rarity_color_hex, display_name]
	tt += "[i][font_size=10][color=gray]%s %s[/color][/font_size][/i][/center]\n" % [rarity_label, slot_type.capitalize()]
	tt += "[color=gray]──────────────────────────────────[/color]\n"
	
	var my_stats = data.get("stats", {})
	
	# 2. PRIMARY STAT
	if slot_type == "weapon":
		var dmg = my_stats.get("atk_kinetic", 0) + my_stats.get("atk_energy", 0) + my_stats.get("atk_explosive", 0)
		var interval = my_stats.get("atk_interval", 2.5)
		if interval > 0:
			var dps = float(dmg) / interval
			tt += "[center][font_size=20][b]%.1f[/b][/font_size] [font_size=10][color=gray]Damage Per Second[/color][/font_size][/center]\n" % dps
			tt += "[center][font_size=10][color=silver]• %s Damage  • %.2f Attacks per Second[/color][/font_size][/center]\n" % [UITheme.format_num(dmg), 1.0/interval]
			tt += "[color=gray]──────────────────────────────────[/color]\n"
	elif slot_type == "shield":
		var m_shield = my_stats.get("max_shield", 0)
		tt += "[center][font_size=20][b]%s[/b][/font_size] [font_size=10][color=gray]Shield Capacity[/color][/font_size][/center]\n" % UITheme.format_num(m_shield)
		tt += "[color=gray]──────────────────────────────────[/color]\n"
	elif slot_type == "armor":
		var hp_val = my_stats.get("hp", 0)
		tt += "[center][font_size=20][b]%s[/b][/font_size] [font_size=10][color=gray]Integrity Reinforcement[/color][/font_size][/center]\n" % UITheme.format_num(hp_val)
		tt += "[color=gray]──────────────────────────────────[/color]\n"

	# 3. STAT COMPARISON
	var equipped_mid = null
	var equipped_stats = {}
	for idx in manager.loadout:
		var m = manager.loadout[idx]
		if m and m in manager.modules:
			var m_data = manager.modules[m]
			if m_data.get("slot_type") == slot_type:
				equipped_mid = m
				equipped_stats = m_data.get("stats", {})
				break
	
	for k in my_stats:
		# Filter out structural and redundant stats
		if k == "energy_load" or k == "atk_interval": continue
		if slot_type == "weapon" and (k == "atk_kinetic" or k == "atk_energy" or k == "atk_explosive"): continue
		if slot_type == "shield" and k == "max_shield": continue
		if slot_type == "armor" and k == "hp": continue
		
		var label = FormatUtils.format_stat_label(k)
		var val = my_stats[k]
		var delta_str = ""
		
		if equipped_mid and equipped_mid != mid:
			var eq_val = equipped_stats.get(k, 0)
			var diff = val - eq_val
			if diff > 0:
				delta_str = " [color=lime][font_size=9](+%s ↑)[/font_size][/color]" % FormatUtils.format_stat_value(k, diff)
			elif diff < 0:
				delta_str = " [color=red][font_size=9](%s ↓)[/font_size][/color]" % FormatUtils.format_stat_value(k, diff)
		
		tt += "[color=silver]⋄ %s: [color=white]%s[/color][/color]%s\n" % [label, FormatUtils.format_stat_value(k, val), delta_str]
	
	# 4. RANDOM AFFIXES
	var affixes = data.get("affixes", {})
	if affixes.size() > 0:
		tt += "[color=gray]──────────────────────────────────[/color]\n"
		for aid in affixes:
			if aid in sm.AFFIX_DB:
				var cfg = sm.AFFIX_DB[aid]
				var val = int(affixes[aid] * 100)
				if rarity == sm.Rarity.LEGENDARY:
					tt += "[color=orange]★ [b]%s[/b][/color]\n" % (cfg["desc"] % val)
				else:
					tt += "[color=cyan]⋄ %s[/color]\n" % (cfg["desc"] % val)

	# 5. FOOTER
	tt += "[color=gray]──────────────────────────────────[/color]\n"
	if equipped_mid and equipped_mid != mid:
		tt += "[font_size=9][color=yellow]Comparing with: %s[/color][/font_size]" % manager.modules[equipped_mid]["name"]
	else:
		tt += "[font_size=9][color=gray](Currently equipped module)[/color][/font_size]" if equipped_mid == mid else ""

	return tt
