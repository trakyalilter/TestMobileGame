extends PanelContainer

var mid: String
var data: Dictionary
var count: int = 0
var pulse_tween: Tween

@onready var type_lbl: Label = $Margin/VBox/Header/TypeLabel
@onready var rarity_badge: Label = $Margin/VBox/Header/RarityBadge
@onready var name_lbl: Label = $Margin/VBox/NameLabel
@onready var stats_lbl: Label = $Margin/VBox/StatsLabel
@onready var footer_lbl: Label = $Margin/VBox/FooterLabel

func setup(p_mid: String, p_data: Dictionary, p_count: int):
	mid = p_mid
	data = p_data
	count = p_count
	_update_ui()

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_ui()

func _update_ui():
	if not is_inside_tree() or data.is_empty():
		return

	var sm = GameState.shipyard_manager
	var slot_type = data.get("slot_type", "module")
	var rarity = _get_module_rarity_safe(sm)
	var rarity_color = _get_rarity_color_safe(sm, rarity)
	var clean_name = _get_clean_name(data.get("name", "Unknown"))

	type_lbl.text = slot_type.to_upper()
	type_lbl.add_theme_color_override("font_color", _get_slot_color(slot_type))

	var rarity_label = _get_rarity_label_safe(sm, rarity)
	rarity_badge.visible = rarity_label != ""
	rarity_badge.text = rarity_label.to_upper()
	rarity_badge.add_theme_color_override("font_color", rarity_color)

	name_lbl.text = clean_name.to_upper()
	name_lbl.add_theme_color_override("font_color", rarity_color.lerp(Color.WHITE, 0.18))
	stats_lbl.text = _build_card_stats(slot_type, data.get("stats", {}))
	footer_lbl.text = _build_footer_text(slot_type, rarity_label)

	# v83.9: Set Name Display
	var sid = data.get("set_id", "")
	if sid == "" and data.get("is_custom") and data.has("base_module"):
		var base_id = data["base_module"]
		sid = sm.modules.get(base_id, {}).get("set_id", "")
	var margin_vbox = $Margin/VBox
	var set_lbl = margin_vbox.get_node_or_null("SetLabel")
	if not set_lbl:
		set_lbl = Label.new()
		set_lbl.name = "SetLabel"
		set_lbl.add_theme_font_size_override("font_size", 8)
		set_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		set_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		margin_vbox.add_child(set_lbl)
		margin_vbox.move_child(set_lbl, name_lbl.get_index() + 1)
	
	if sid != "" and GameState.combat_manager and "TRINITY_SET_BONUSES" in GameState.combat_manager:
		var s_db = GameState.combat_manager.TRINITY_SET_BONUSES
		if s_db.has(sid):
			var set_name = s_db[sid]["name"]
			set_lbl.text = "[ %s ]" % set_name.to_upper()
			set_lbl.add_theme_color_override("font_color", Color(0.0, 0.8, 0.8)) # Cyan for set
			set_lbl.visible = true
		else:
			set_lbl.visible = false
	else:
		set_lbl.visible = false

	# Socket rendering logic
	for child in margin_vbox.get_children():
		if child.name == "SocketContainer":
			child.free()
	
	if data.has("sockets") and data["sockets"].size() > 0:
		var h_box = HBoxContainer.new()
		h_box.name = "SocketContainer"
		h_box.alignment = BoxContainer.ALIGNMENT_CENTER
		h_box.add_theme_constant_override("separation", 12)
		h_box.custom_minimum_size = Vector2(0, 20)
		
		for gem in data["sockets"]:
			var sock_bg = Panel.new()
			sock_bg.custom_minimum_size = Vector2(10, 10)
			var sb = StyleBoxFlat.new()
			sb.bg_color = Color(0.01, 0.01, 0.01, 0.9)
			sb.border_width_left = 1; sb.border_width_top = 1; sb.border_width_right = 1; sb.border_width_bottom = 1;
			sb.border_color = Color(0.4, 0.4, 0.4, 0.8)
			
			if gem:
				var gem_name = ElementDB.get_display_name(gem)
				var g_color = _get_gem_color(gem_name)
				sb.bg_color = g_color
				sb.border_color = g_color.lightened(0.6)
				sb.shadow_color = g_color * Color(1, 1, 1, 0.4)
				sb.shadow_size = 4
			
			sock_bg.add_theme_stylebox_override("panel", sb)
			sock_bg.pivot_offset = Vector2(5, 5)
			sock_bg.rotation_degrees = 45 # Diamond layout
			
			var sock_wrap = Control.new()
			sock_wrap.custom_minimum_size = Vector2(16, 16)
			sock_bg.position = Vector2(3, 3)
			sock_wrap.add_child(sock_bg)
			h_box.add_child(sock_wrap)
			
		margin_vbox.add_child(h_box)
		margin_vbox.move_child(h_box, footer_lbl.get_index()) # Put right above footer!

	_apply_card_style(rarity, rarity_color)
	_apply_pulse(rarity)

	if sm and mid in sm.modules:
		var status = sm.can_equip_module(mid)
		UITheme.apply_locked_overlay(self, clean_name, status["reason"], not status["can_equip"])
	else:
		UITheme.apply_locked_overlay(self, clean_name, "", false)

func _get_module_rarity_safe(sm) -> int:
	if not sm:
		return 0
	if mid in sm.modules:
		return sm.get_module_rarity(mid)
	return sm.Rarity.COMMON

func _get_rarity_color_safe(sm, rarity: int) -> Color:
	if not sm:
		return Color(0.7, 0.7, 0.7)
	return sm.RARITY_COLORS.get(rarity, Color(0.7, 0.7, 0.7))

func _get_rarity_label_safe(sm, rarity: int) -> String:
	if not sm or rarity == sm.Rarity.COMMON:
		return ""
	return sm.RARITY_LABELS.get(rarity, "")

func _get_clean_name(raw_name: String) -> String:
	var title = raw_name
	for suffix in [" (Common)", " (Uncommon)", " (Rare)", " (Legendary)", " (Unique)"]:
		title = title.replace(suffix, "")
	return title

func _build_card_stats(slot_type: String, stats: Dictionary) -> String:
	if slot_type == "ammo":
		return _build_ammo_card_stats()

	if slot_type == "consumable":
		var heal_pct = int(round(data.get("heal_pct", data.get("stats", {}).get("heal_pct", 0.0)) * 100.0))
		var target = data.get("consumable_type", "hull").capitalize()
		return "Restores %d%% %s" % [heal_pct, target]

	var lines: Array[String] = []

	if slot_type == "weapon":
		var dmg = stats.get("atk_kinetic", 0) + stats.get("atk_energy", 0) + stats.get("atk_explosive", 0)
		var interval = max(0.01, float(stats.get("atk_interval", 2.5)))
		lines.append("DPS: %.1f" % (float(dmg) / interval))

	var keys = stats.keys()
	keys.sort()
	for key in keys:
		if key == "atk_interval":
			continue
		var val = stats[key]
		if key == "energy_load" and val == 0:
			continue
		var label = FormatUtils.format_stat_label(key)
		lines.append("%s: %s" % [label, FormatUtils.format_stat_value(key, val)])
		if lines.size() >= 4:
			break

	if lines.is_empty():
		if slot_type == "gem":
			return data.get("desc", "No combat modifiers")
		return "No combat modifiers"
	return "\n".join(lines)

func _build_ammo_card_stats() -> String:
	var bonus = 0.0
	var type_label = "Damage"

	if mid.begins_with("Slug"):
		bonus = 5.0
		if "T1S" in mid:
			bonus = 10.0
		elif "T2" in mid:
			bonus = 15.0
		elif "T3" in mid:
			bonus = 30.0
		elif "T4" in mid:
			bonus = 60.0
		type_label = "Kinetic"
	elif mid.begins_with("Cell"):
		bonus = 5.0
		if "T2" in mid:
			bonus = 15.0
		elif "T3" in mid:
			bonus = 30.0
		elif "T4" in mid:
			bonus = 60.0
		type_label = "Energy"
	elif "Missile" in mid or "Torpedo" in mid:
		bonus = 10.0
		if "Seeker" in mid:
			bonus = 25.0
		elif "Torpedo" in mid:
			bonus = 60.0
		type_label = "Explosive"

	if bonus <= 0.0:
		return "Ammunition"
	return "+%.1f %s Damage" % [bonus, type_label]

func _build_footer_text(slot_type: String, rarity_label: String) -> String:
	var parts: Array[String] = []
	if rarity_label != "":
		parts.append(rarity_label.to_upper())
	if slot_type != "":
		parts.append(slot_type.to_upper())
	if count > 1:
		parts.append("x%d" % count)
	if parts.is_empty():
		return ""
	return " | ".join(parts)

func _apply_card_style(rarity: int, rarity_color: Color):
	var frame = StyleBoxFlat.new()
	frame.bg_color = _get_rarity_background(rarity)
	frame.set_corner_radius_all(3)
	frame.set_border_width_all(2)
	frame.border_width_top = 5
	frame.border_color = rarity_color.lerp(Color(0.55, 0.45, 0.34), 0.35)
	frame.content_margin_left = 6
	frame.content_margin_top = 5
	frame.content_margin_right = 6
	frame.content_margin_bottom = 5
	frame.shadow_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.2)
	frame.shadow_size = 8
	frame.shadow_offset = Vector2(0, 2)

	var sm = GameState.shipyard_manager
	if sm and (rarity == sm.Rarity.LEGENDARY or rarity == sm.Rarity.UNIQUE):
		frame.set_border_width_all(3)
		frame.border_width_top = 6
		frame.shadow_size = 12

	add_theme_stylebox_override("panel", frame)

func _get_rarity_background(rarity: int) -> Color:
	var sm = GameState.shipyard_manager
	if not sm:
		return Color(0.11, 0.09, 0.08, 0.96)

	if rarity == sm.Rarity.UNCOMMON:
		return Color(0.08, 0.11, 0.08, 0.96)
	if rarity == sm.Rarity.RARE:
		return Color(0.07, 0.10, 0.14, 0.96)
	if rarity == sm.Rarity.LEGENDARY:
		return Color(0.15, 0.10, 0.06, 0.98)
	if rarity == sm.Rarity.UNIQUE:
		return Color(0.16, 0.08, 0.14, 0.98)
	return Color(0.11, 0.09, 0.08, 0.96)

func _get_slot_color(slot_type: String) -> Color:
	match slot_type:
		"weapon":
			return Color(0.92, 0.48, 0.32)
		"shield":
			return Color(0.50, 0.72, 0.95)
		"armor":
			return Color(0.78, 0.73, 0.66)
		"engine", "reactor", "battery":
			return Color(0.84, 0.79, 0.43)
		"ammo":
			return Color(0.88, 0.60, 0.34)
		"consumable":
			return Color(0.74, 0.74, 0.86)
		_:
			return Color(0.65, 0.58, 0.47)

func _get_gem_color(gem_name: String) -> Color:
	if "Crimson" in gem_name: return Color("#ff4444")
	if "Cobalt" in gem_name: return Color("#44ccff")
	if "Topaz" in gem_name: return Color("#ffcc00")
	if "Amethyst" in gem_name: return Color("#aa44ff")
	return Color("#b548b5") # Default purple

func _apply_pulse(rarity: int):
	_stop_pulse()
	var sm = GameState.shipyard_manager
	if not sm:
		return
	if rarity == sm.Rarity.LEGENDARY:
		pulse_tween = create_tween().set_loops()
		pulse_tween.tween_property(self, "modulate", Color(1.08, 1.03, 0.94), 0.9).set_trans(Tween.TRANS_SINE)
		pulse_tween.tween_property(self, "modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
	elif rarity == sm.Rarity.UNIQUE:
		pulse_tween = create_tween().set_loops()
		pulse_tween.tween_property(self, "modulate", Color(1.10, 0.97, 1.08), 0.9).set_trans(Tween.TRANS_SINE)
		pulse_tween.tween_property(self, "modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)

func _stop_pulse():
	if pulse_tween and is_instance_valid(pulse_tween):
		pulse_tween.kill()
	pulse_tween = null
	modulate = Color.WHITE

func _gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_show_sell_menu()

func _show_sell_menu():
	var sm = GameState.shipyard_manager
	if not sm or mid not in sm.modules:
		return

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
		if id == 0 and sm.sell_module(mid):
			var rarity = sm.get_module_rarity(mid)
			var rarity_color = sm.RARITY_COLORS.get(rarity, Color.WHITE)
			UITheme.show_notification("Sold for %s credits" % UITheme.format_num(price), rarity_color)
		popup.queue_free()
	)
	popup.popup(Rect2i(get_global_mouse_position(), Vector2i(1, 1)))

func _make_custom_tooltip(_for_text: String) -> Control:
	if data.is_empty():
		return null

	var sm = GameState.shipyard_manager
	var rarity = _get_module_rarity_safe(sm)
	var rarity_color = _get_rarity_color_safe(sm, rarity)

	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.03, 0.98)
	style.border_color = rarity_color
	style.border_color.a = 0.85
	style.set_border_width_all(2)
	style.border_width_top = 5
	style.set_corner_radius_all(3)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)

	var rtl = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.custom_minimum_size = Vector2(340, 0)
	rtl.add_theme_color_override("default_color", Color(0.92, 0.90, 0.86))
	rtl.text = _build_comparison_tooltip_bbcode()
	panel.add_child(rtl)
	return panel

func _build_comparison_tooltip_bbcode() -> String:
	if data.is_empty():
		return ""

	var sm = GameState.shipyard_manager
	var slot_type = data.get("slot_type", "module")
	var rarity = _get_module_rarity_safe(sm)
	var rarity_label = _get_rarity_label_safe(sm, rarity)
	if rarity_label == "":
		rarity_label = "Common"
	var rarity_color_hex = _get_rarity_color_safe(sm, rarity).to_html(false)
	var display_name = _get_clean_name(data.get("name", "Item")).to_upper()

	var tt = ""
	var div = "[color=#3d3d3d]-------------------------------[/color]\n"

	tt += "[b][color=#%s]%s[/color][/b]\n" % [rarity_color_hex, display_name]
	tt += "[font_size=10][color=gray]%s %s[/color][/font_size]\n" % [rarity_label, slot_type.capitalize()]
	tt += div

	var my_stats = data.get("stats", {})
	if slot_type == "weapon":
		var dmg = my_stats.get("atk_kinetic", 0) + my_stats.get("atk_energy", 0) + my_stats.get("atk_explosive", 0)
		var interval = max(0.01, float(my_stats.get("atk_interval", 2.5)))
		var dps = float(dmg) / interval
		tt += "[font_size=20][b]%.1f DPS[/b][/font_size]\n" % dps
		tt += "[font_size=9][color=gray]%s total damage, %.2f hits/s[/color][/font_size]\n" % [UITheme.format_num(dmg), 1.0 / interval]
		tt += div
	elif slot_type == "ammo":
		tt += "[font_size=14][b]%s[/b][/font_size]\n" % _build_ammo_card_stats()
		tt += div
	elif slot_type == "consumable":
		var heal_pct = int(round(data.get("heal_pct", data.get("stats", {}).get("heal_pct", 0.0)) * 100.0))
		var target = data.get("consumable_type", "hull")
		tt += "[font_size=16][b]Restores %d%% %s[/b][/font_size]\n" % [heal_pct, target.capitalize()]
		tt += div
	elif slot_type == "shield":
		var val = my_stats.get("max_shield", 0)
		tt += "[font_size=20][b]%s[/b][/font_size] [font_size=10][color=gray]Shield Capacity[/color][/font_size]\n" % UITheme.format_num(val)
		tt += div
	elif slot_type == "armor":
		var val = my_stats.get("hp", 0)
		tt += "[font_size=20][b]%s[/b][/font_size] [font_size=10][color=gray]Integrity Reinforcement[/color][/font_size]\n" % UITheme.format_num(val)
		tt += div
	elif slot_type == "gem":
		var gem_desc = data.get("desc", ElementDB.get_element_description(mid))
		tt += "[font_size=14][b]%s[/b][/font_size]\n" % gem_desc
		tt += div

	var equipped_mid = ""
	var equipped_stats = {}
	if sm and slot_type in ["weapon", "shield", "armor", "engine", "battery", "reactor", "sensor", "cooling"]:
		for idx in sm.loadout:
			var equipped = sm.loadout[idx]
			if equipped and equipped in sm.modules:
				var equipped_data = sm.modules[equipped]
				if equipped_data.get("slot_type", "") == slot_type:
					equipped_mid = equipped
					equipped_stats = equipped_data.get("stats", {})
					break

	var keys = my_stats.keys()
	keys.sort()
	for key in keys:
		if key == "atk_interval":
			continue
		var val = my_stats[key]
		if key == "energy_load" and val == 0:
			continue
		if slot_type == "weapon" and key in ["atk_kinetic", "atk_energy", "atk_explosive"]:
			continue
		if slot_type == "shield" and key == "max_shield":
			continue
		if slot_type == "armor" and key == "hp":
			continue

		var label = FormatUtils.format_stat_label(key)
		var val_str = FormatUtils.format_stat_value(key, val)
		
		# v76.0: Display Roll Range for base stats
		var range_info = ""
		var base_id = data.get("base_module", "")
		if base_id != "" and base_id in sm.modules and key in sm.BOOSTABLE_STATS:
			var base_val = sm.modules[base_id].get("stats", {}).get(key, 0)
			if base_val > 0:
				var s_range = sm.RARITY_STAT_RANGE.get(rarity, [0, 0])
				if s_range[1] > 0:
					var zone_mult = 1.0
					if key in sm.ZONE_SCALABLE_STATS and data.has("zone_difficulty"):
						zone_mult = sm.get_module_zone_multiplier(int(data.get("zone_difficulty", 1)))
					var scaled_base = base_val * zone_mult
					var r_min = scaled_base * (1.0 + s_range[0])
					var r_max = scaled_base * (1.0 + s_range[1])
					range_info = " [color=gray][font_size=9][%s-%s][/font_size][/color]" % [
						FormatUtils.format_stat_value(key, r_min),
						FormatUtils.format_stat_value(key, r_max)
					]

		var line = "%s: %s%s" % [label, val_str, range_info]
		if equipped_mid != "" and equipped_mid != mid and key != "energy_load":
			var diff = val - equipped_stats.get(key, 0)
			if diff > 0:
				line += " [color=lime](+%s)[/color]" % FormatUtils.format_stat_value(key, diff)
			elif diff < 0:
				line += " [color=red](%s)[/color]" % FormatUtils.format_stat_value(key, diff)
		tt += "%s\n" % line

	var affixes = data.get("affixes", {})
	if sm and affixes.size() > 0:
		tt += div
		var zone_difficulty = int(data.get("zone_difficulty", 1))
		for aid in affixes:
			if aid in sm.AFFIX_DB:
				var cfg = sm.AFFIX_DB[aid]
				var val_raw = affixes[aid]
				var scaling = cfg.get("scaling", "percent")
				
				# v80.1 Fix: Use scaled ranges for display
				var s_range = sm.get_affix_scaled_range(aid, zone_difficulty)
				var val_str = ""
				var range_str = ""
				
				if scaling == "flat":
					val_str = str(int(val_raw))
					range_str = " [color=gray][font_size=9][%d-%d][/font_size][/color]" % [int(s_range[0]), int(s_range[1])]
				else:
					val_str = "%d%%" % int(val_raw * 100)
					range_str = " [color=gray][font_size=9][%d-%d]%%[/font_size][/color]" % [int(s_range[0] * 100), int(s_range[1] * 100)]
				
				var icon = ""
				
				var desc = cfg["desc"] % [int(val_raw) if scaling == "flat" else int(val_raw * 100)]
				tt += "[color=#8fc5ff]%s %s[/color]%s\n" % [icon, desc, range_str]

	if data.has("sockets"):
		tt += div
		for gem in data["sockets"]:
			if gem:
				var g_name = ElementDB.get_display_name(gem)
				var g_desc = ElementDB.get_element_description(gem)
				var g_hex = _get_gem_color(g_name).to_html(false)
				if g_desc != "":
					tt += "[color=#%s]%s: %s[/color]\n" % [g_hex, g_name, g_desc]
				else:
					tt += "[color=#%s]%s[/color]\n" % [g_hex, g_name]
			else:
				tt += "[color=#444444]Empty Socket[/color]\n"

	if sm and mid in sm.modules:
		tt += div
		tt += "[font_size=10][color=gray]Sell Value:[/color] [color=#e0b150]%s credits[/color][/font_size]" % UITheme.format_num(sm.get_sell_price(mid))

	# v83.9: Set Bonus Tooltip Section
	var sid = data.get("set_id", "")
	if sid == "" and data.get("is_custom") and data.has("base_module"):
		var base_id = data["base_module"]
		sid = sm.modules.get(base_id, {}).get("set_id", "")
	if sid != "" and GameState.combat_manager and "TRINITY_SET_BONUSES" in GameState.combat_manager:
		var s_db = GameState.combat_manager.TRINITY_SET_BONUSES
		if s_db.has(sid):
			tt += div
			var set_info = s_db[sid]
			var count = GameState.combat_manager.get_set_piece_count(sid)
			var total = set_info["pieces"]
			var active = count >= total
			
			tt += "[b][color=#00ffff]SET: %s[/color][/b]\n" % set_info["name"].to_upper()
			tt += "[font_size=10][color=gray]%d / %d pieces equipped[/color][/font_size]\n" % [count, total]
			
			for bonus_key in set_info["bonus"]:
				var val = set_info["bonus"][bonus_key]
				var b_name = bonus_key.replace("_pct", "").replace("_flat", "").replace("_", " ").to_upper()
				var val_str = "+%d%%" % val if ("_pct" in bonus_key or "crit" in bonus_key) else "+%d" % val
				
				var col = "#ffffff" if active else "#666666"
				tt += "[color=%s]%s: %s[/color]\n" % [col, b_name, val_str]

	return tt

func _get_drag_data(_at_position):
	if data.is_empty() or mid == "":
		return null

	var slot_type = data.get("slot_type", "")
	var dtype = "module"
	if slot_type == "ammo":
		dtype = "ammo"
	elif slot_type == "consumable":
		dtype = "consumable"

	var drag_data = {
		"type": dtype,
		"mid": mid,
		"ammo_id": mid,
		"slot_type": slot_type,
		"consumable_type": data.get("consumable_type", ""),
	}

	var preview = load("res://scenes/ui/module_card.tscn").instantiate()
	preview.setup(mid, data, count)

	var preview_container = Control.new()
	preview_container.add_child(preview)
	preview.scale = Vector2(1.05, 1.05)
	preview.modulate.a = 0.96

	var shadow = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.45)
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 12)
	shadow.add_theme_stylebox_override("panel", style)
	shadow.custom_minimum_size = Vector2(124, 138)

	preview_container.add_child(shadow)
	preview_container.move_child(shadow, 0)
	preview.position = Vector2(-62, -70)
	shadow.position = Vector2(-58, -66)

	set_drag_preview(preview_container)
	return drag_data
