extends PanelContainer

var mid: String
var data: Dictionary

@onready var name_lbl = $Margin/VBox/NameLabel
@onready var stats_lbl = $Margin/VBox/StatsLabel

var count: int = 0

func setup(p_mid: String, p_data: Dictionary, p_count: int):
	mid = p_mid
	data = p_data
	count = p_count
	_update_ui()
	
func _update_ui():
	if not is_inside_tree() or not name_lbl: return
	var title = data.get("name", "Unknown")
	# Strip redundant rarity suffix since the badge handles it
	for suffix in ["(Common)", "(Uncommon)", "(Rare)", "(Legendary)"]:
		title = title.replace(" " + suffix, "")
	if count > 1:
		name_lbl.text = "%s (x%d)" % [title, count]
	else:
		name_lbl.text = title
	
	# v71.0: Rarity-based styling
	var sm = GameState.shipyard_manager
	var rarity = sm.get_module_rarity(mid)
	var rarity_color = sm.RARITY_COLORS.get(rarity, Color(0.69, 0.69, 0.69))
	
	# v71.3: Rarity Tier Badge
	var rarity_vbox = $Margin/VBox
	var rarity_badge = rarity_vbox.get_node_or_null("RarityBadge")
	if not rarity_badge:
		rarity_badge = Label.new()
		rarity_badge.name = "RarityBadge"
		rarity_vbox.add_child(rarity_badge)
		rarity_vbox.move_child(rarity_badge, 0)
		rarity_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	var r_label = sm.RARITY_LABELS.get(rarity, "COMMON").to_upper()
	rarity_badge.text = "[ %s ]" % r_label
	rarity_badge.add_theme_color_override("font_color", rarity_color)
	rarity_badge.add_theme_font_size_override("font_size", 9)
	rarity_badge.visible = rarity > sm.Rarity.COMMON
	
	name_lbl.add_theme_color_override("font_color", rarity_color)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	# v71.5: Equipment Prerequisite Unlock Check
	var status = sm.can_equip_module(mid)
	UITheme.apply_locked_overlay(self, title, status["reason"], not status["can_equip"])
	
	# Apply rarity-styled card with left accent bar
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	card_style.set_corner_radius_all(4)
	card_style.set_content_margin_all(6)
	if rarity >= sm.Rarity.UNCOMMON:
		# Vivid left accent bar + matching top border
		card_style.border_width_left = 8
		card_style.border_width_top = 4
		card_style.border_width_right = 1
		card_style.border_width_bottom = 1
		card_style.border_color = rarity_color
	else:
		card_style.border_color = Color(0.25, 0.25, 0.3, 0.5)
		card_style.set_border_width_all(1)
	add_theme_stylebox_override("panel", card_style)
	
	var s_txt = ""
	var stats = data.get("stats", {})
	for k in stats:
		var label = FormatUtils.format_stat_label(k)
		var val = stats[k]
		s_txt += "%s: %s\n" % [label, FormatUtils.format_stat_value(k, val)]
			
	stats_lbl.text = s_txt.strip_edges()
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	# Legendary pulse effect
	if rarity == sm.Rarity.LEGENDARY:
		_start_legendary_pulse()

func _ready():
	_update_ui()
	mouse_filter = Control.MOUSE_FILTER_STOP

# v71.2: Right-click to sell
func _gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_show_sell_menu()

func _show_sell_menu():
	var sm = GameState.shipyard_manager
	# Check if this module is exclusively equipped (no spares in inventory)
	var in_storage = sm.module_inventory.get(mid, 0)
	if in_storage <= 0:
		UITheme.show_notification("Cannot sell equipped module", Color.RED)
		return
	
	var price = sm.get_sell_price(mid)
	var popup = PopupMenu.new()
	popup.add_item("Sell for %s credits" % UITheme.format_num(price), 0)
	popup.add_separator()
	popup.add_item("Cancel", 1)
	add_child(popup)
	
	popup.id_pressed.connect(func(id):
		if id == 0:
			if sm.sell_module(mid):
				var rarity_color = sm.RARITY_COLORS.get(data.get("rarity", sm.Rarity.COMMON), Color.WHITE)
				UITheme.show_notification("Sold for %s ¢" % UITheme.format_num(price), rarity_color)
		popup.queue_free()
	)
	popup.popup(Rect2i(get_global_mouse_position(), Vector2i(1, 1)))

# v71.0: Legendary golden pulse animation
func _start_legendary_pulse():
	var tween = create_tween().set_loops()
	tween.tween_property(self, "modulate", Color(1.15, 1.05, 0.85), 1.0).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0), 1.0).set_trans(Tween.TRANS_SINE)

# ─────────────────────────────────────────────────
# CUSTOM RICH TOOLTIP with BBCode colors (PHASE 22)
# ─────────────────────────────────────────────────

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
	style.border_width_top = 4 # Thick top border for rarity identity
	style.set_corner_radius_all(2)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	
	var rtl = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.custom_minimum_size = Vector2(320, 0)
	rtl.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	
	rtl.text = _build_comparison_tooltip_bbcode()
	panel.add_child(rtl)
	
	return panel

func _build_comparison_tooltip_bbcode() -> String:
	if not data: return ""
	
	var sm = GameState.shipyard_manager
	var rarity = data.get("rarity", sm.Rarity.COMMON)
	var rarity_label = sm.RARITY_LABELS.get(rarity, "Common")
	if rarity == sm.Rarity.COMMON: rarity_label = "Common"
	
	var rarity_color_hex = sm.RARITY_COLORS.get(rarity, Color.GRAY).to_html(false)
	var slot_type = data.get("slot_type", "weapon")
	
	var tt = ""
	
	# 1. HEADER (Structured)
	var display_name = data.get("name", "Item").to_upper()
	for suffix in [" (COMMON)", " (UNCOMMON)", " (RARE)", " (LEGENDARY)"]:
		display_name = display_name.replace(suffix, "")
		
	tt += "[center][b][font_size=16][color=#%s]%s[/color][/font_size][/b]\n" % [rarity_color_hex, display_name]
	tt += "[i][font_size=10][color=gray]%s %s[/color][/font_size][/i][/center]\n" % [rarity_label, slot_type.capitalize()]
	tt += "[color=gray]──────────────────────────────────[/color]\n"
	
	var my_stats = data.get("stats", {})
	
	# 2. PRIMARY STAT (Large Type)
	if slot_type == "weapon":
		var dmg = my_stats.get("atk_kinetic", 0) + my_stats.get("atk_energy", 0) + my_stats.get("atk_explosive", 0)
		var interval = my_stats.get("atk_interval", 2.5)
		if interval > 0:
			var dps = float(dmg) / interval
			tt += "[center][font_size=20][b]%.1f[/b][/font_size] [font_size=10][color=gray]Damage Per Second[/color][/font_size][/center]\n" % dps
			
			# Indented weapon details
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
	elif slot_type == "ammo":
		var bonus = 0.0
		var type_label = "Damage"
		var color_label = "white"
		
		# Parse ammo damage from ID (matching combat_manager.gd logic)
		if mid.begins_with("Slug"):
			bonus = 5.0
			if "T1S" in mid: bonus = 10.0
			elif "T2" in mid: bonus = 15.0
			elif "T3" in mid: bonus = 30.0
			elif "T4" in mid: bonus = 60.0
			type_label = "Kinetic Damage"
			color_label = "red"
		elif mid.begins_with("Cell"):
			bonus = 5.0
			if "T2" in mid: bonus = 15.0
			elif "T3" in mid: bonus = 30.0
			elif "T4" in mid: bonus = 60.0
			type_label = "Energy Damage"
			color_label = "cyan"
		elif "Missile" in mid or "Torpedo" in mid:
			bonus = 10.0
			if "Seeker" in mid: bonus = 25.0
			elif "Torpedo" in mid: bonus = 60.0
			type_label = "Explosive Damage"
			color_label = "orange"
			
		if bonus > 0:
			tt += "[center][font_size=20][b][color=%s]+%.1f[/color][/b][/font_size] [font_size=10][color=gray]%s Bonus[/color][/font_size][/center]\n" % [color_label, bonus, type_label]
			tt += "[color=gray]──────────────────────────────────[/color]\n"

	# 3. STATS & AFFIXES (Diablo Style)
	# Find comparison target
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
	
	for k in my_stats:
		# Filter out stats already shown in Primary Stat section
		if k == "atk_interval": continue
		if k == "energy_load" and my_stats[k] == 0: continue
		if slot_type == "weapon" and (k == "atk_kinetic" or k == "atk_energy" or k == "atk_explosive"): continue
		if slot_type == "shield" and k == "max_shield": continue
		if slot_type == "armor" and k == "hp": continue
		
		var label = FormatUtils.format_stat_label(k)
		var val = my_stats[k]
		var delta_str = ""
		
		# Comparison deltas
		if equipped_mid and equipped_mid != mid and k != "energy_load":
			var eq_val = equipped_stats.get(k, 0)
			var diff = val - eq_val
			if diff > 0:
				delta_str = " [color=lime][font_size=9](+%s ↑)[/font_size][/color]" % FormatUtils.format_stat_value(k, diff)
			elif diff < 0:
				delta_str = " [color=red][font_size=9](%s ↓)[/font_size][/color]" % FormatUtils.format_stat_value(k, diff)
		
		tt += "[color=silver]⋄ %s: [color=white]%s[/color][/color]%s\n" % [label, FormatUtils.format_stat_value(k, val), delta_str]
	
	# 4. RANDOM AFFIXES (with Ranges)
	var affixes = data.get("affixes", {})
	if affixes.size() > 0:
		tt += "[color=gray]──────────────────────────────────[/color]\n"
		for aid in affixes:
			if aid in sm.AFFIX_DB:
				var cfg = sm.AFFIX_DB[aid]
				var val = int(affixes[aid] * 100)
				
				# Legendary coloring
				if rarity == sm.Rarity.LEGENDARY:
					tt += "[color=orange]★ [b]%s[/b][/color]\n" % (cfg["desc"] % val)
				else:
					tt += "[color=cyan]⋄ %s[/color]\n" % (cfg["desc"] % val)
	
	# 5. FOOTER
	tt += "[color=gray]──────────────────────────────────[/color]\n"
	var sell_price = sm.get_sell_price(mid)
	tt += "[font_size=10][color=gray]Sell Value:[/color] [color=gold]%s ¢[/color][/font_size]" % UITheme.format_num(sell_price)
	
	if equipped_mid and equipped_mid != mid:
		tt += "\n[font_size=9][color=yellow]Comparing with: %s[/color][/font_size]" % sm.modules[equipped_mid]["name"]
	
	return tt

func _get_drag_data(_at_position):
	if not data or not mid: return null
	
	var st = data.get("slot_type", "")
	var dtype = "module"
	if st == "ammo": dtype = "ammo"
	elif st == "consumable": dtype = "consumable"
	
	var drag_data = {
		"type": dtype,
		"mid": mid,
		"ammo_id": mid, # For ease of use in drop
		"slot_type": st,
		"consumable_type": data.get("consumable_type", ""), # hull or shield
	}
	
	# Visual Preview: Use a real card instance
	var preview = load("res://scenes/ui/module_card.tscn").instantiate()
	preview.setup(mid, data, count)
	
	# "Physical space item" look:
	# Keep size consistent, scale it slightly up to feel like it popped out of the slot,
	# give it a solid shadow and a slight tilt or crispness.
	var preview_container = Control.new()
	preview_container.add_child(preview)
	
	# Scale it up slightly to feel picked up
	preview.scale = Vector2(1.05, 1.05)
	preview.modulate.a = 0.95 # Mostly solid, not transparent
	
	# Add a physical shadow explicitly (if the theme doesn't handle drag contexts)
	var shadow = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 15
	style.shadow_offset = Vector2(0, 10)
	shadow.add_theme_stylebox_override("panel", style)
	shadow.custom_minimum_size = Vector2(100, 100)
	
	# Put shadow behind it
	preview_container.add_child(shadow)
	preview_container.move_child(shadow, 0)
	
	# Offset the preview so the mouse holds the center of the card
	preview.position = Vector2(-50, -50)
	shadow.position = Vector2(-45, -45)
	
	set_drag_preview(preview_container)
	return drag_data
