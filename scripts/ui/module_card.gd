extends PanelContainer

var mid: String
var data: Dictionary

@onready var name_lbl = $Margin/VBox/HBox/NameLabel
@onready var stats_lbl = $Margin/VBox/StatsLabel
@onready var count_lbl = $Margin/VBox/HBox/CountLabel

var count: int = 0

func setup(p_mid: String, p_data: Dictionary, p_count: int):
	mid = p_mid
	data = p_data
	count = p_count
	_update_ui()
	
func _update_ui():
	if not data or not is_inside_tree(): return
	if not name_lbl or not stats_lbl or not count_lbl: return
	
	name_lbl.text = data.get("name", "Unknown")
	name_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS.get("shipyard", Color.WHITE))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_lbl.text = "x%d" % count
	
	UITheme.apply_card_style(self, "shipyard")
	
	var s_txt = ""
	var stats = data.get("stats", {})
	for k in stats:
		var label = FormatUtils.format_stat_label(k)
		var val = stats[k]
		s_txt += "%s: %s\n" % [label, FormatUtils.format_stat_value(k, val)]
			
	stats_lbl.text = s_txt.strip_edges()
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _ready():
	_update_ui()

# ─────────────────────────────────────────────────
# CUSTOM RICH TOOLTIP with BBCode colors (PHASE 22)
# ─────────────────────────────────────────────────

func _make_custom_tooltip(for_text: String) -> Control:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style.border_color = Color(0, 0.7, 0.9, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	
	var rtl = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.custom_minimum_size = Vector2(280, 0)
	rtl.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	rtl.add_theme_font_size_override("normal_font_size", 12)
	
	rtl.text = _build_comparison_tooltip_bbcode()
	panel.add_child(rtl)
	
	return panel

func _build_comparison_tooltip_bbcode() -> String:
	if not data: return ""
	
	var tt = "[b][color=cyan]%s[/color][/b]\n" % data.get("name", "Item")
	tt += "[color=gray]─────────────────[/color]\n"
	
	var my_stats = data.get("stats", {})
	var slot_type = data.get("slot_type", "weapon")
	var sm = GameState.shipyard_manager
	
	# Find currently equipped module of same slot_type for comparison
	var equipped_mid = null
	var equipped_stats = {}
	for idx in sm.loadout:
		var m = sm.loadout[idx]
		if m and m in sm.modules:
			var m_data = sm.modules[m]
			if m_data.get("slot_type") == slot_type:
				equipped_mid = m
				equipped_stats = m_data.get("stats", {})
				break
	
	# Show stats with colored delta comparison
	for k in my_stats:
		var label = FormatUtils.format_stat_label(k)
		var val = my_stats[k]
		var delta_str = ""
		
		if equipped_mid and equipped_mid != mid:
			var eq_val = equipped_stats.get(k, 0)
			var diff = val - eq_val
			if diff > 0:
				delta_str = " [color=lime](+%s ↑)[/color]" % FormatUtils.format_stat_value(k, diff)
			elif diff < 0:
				delta_str = " [color=red](%s ↓)[/color]" % FormatUtils.format_stat_value(k, diff)
		
		tt += "%s: %s%s\n" % [label, FormatUtils.format_stat_value(k, val), delta_str]
	
	# Add DPS if it's a weapon
	if slot_type == "weapon":
		var dmg = my_stats.get("atk_kinetic", 0) + my_stats.get("atk_energy", 0) + my_stats.get("atk_explosive", 0)
		var interval = my_stats.get("atk_interval", 2.5)
		if interval > 0:
			var dps = float(dmg) / interval
			tt += "[color=gray]─────────────────[/color]\n"
			tt += "[b]DPS: %.1f[/b]" % dps
			
			# Compare DPS
			if equipped_mid and equipped_mid != mid:
				var eq_dmg = equipped_stats.get("atk_kinetic", 0) + equipped_stats.get("atk_energy", 0) + equipped_stats.get("atk_explosive", 0)
				var eq_int = equipped_stats.get("atk_interval", 2.5)
				if eq_int > 0:
					var eq_dps = float(eq_dmg) / eq_int
					var dps_diff = dps - eq_dps
					if dps_diff > 0:
						tt += " [color=lime](+%.1f ↑)[/color]" % dps_diff
					elif dps_diff < 0:
						tt += " [color=red](%.1f ↓)[/color]" % dps_diff
			tt += "\n"
	
	# Show comparison target
	if equipped_mid and equipped_mid != mid:
		tt += "[color=gray]─────────────────[/color]\n"
		tt += "[color=yellow]vs: %s[/color]" % sm.modules[equipped_mid]["name"]
	elif not equipped_mid:
		tt += "[color=gray]─────────────────[/color]\n"
		tt += "[color=gray](No %s equipped)[/color]" % slot_type.capitalize()
	
	# Description if available
	if data.has("desc"):
		tt += "\n[color=gray]─────────────────[/color]\n"
		tt += "[color=silver]%s[/color]" % data["desc"]
	
	tt += "\n[color=gray][Drag to slot to equip][/color]"
	return tt

func _get_drag_data(_at_position):
	if not data or not mid: return null
	
	var drag_data = {
		"type": "ammo" if data.get("slot_type") == "ammo" else "module",
		"mid": mid,
		"ammo_id": mid, # For ease of use in drop
		"slot_type": data.get("slot_type", "")
	}
	
	# Visual Preview: Use a real card instance
	var preview = load("res://scenes/ui/module_card.tscn").instantiate()
	preview.setup(mid, data, count)
	# Scale down slightly and make semi-transparent
	preview.modulate.a = 0.7
	preview.custom_minimum_size = Vector2(100, 100)
	
	set_drag_preview(preview)
	return drag_data
