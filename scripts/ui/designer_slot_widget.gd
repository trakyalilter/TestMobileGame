extends PanelContainer

var slot_idx: int
var slot_type: String
var parent_ui: Node
var manager: RefCounted
var is_occupied: bool = false
var pulse_tween: Tween

@onready var type_lbl = $MarginContainer/VBoxContainer/TypeLabel
@onready var rarity_badge = $MarginContainer/VBoxContainer/RarityBadge
@onready var name_lbl = $MarginContainer/VBoxContainer/NameLabel
@onready var stats_lbl = $MarginContainer/VBoxContainer/StatsLabel
@onready var socket_anchor = $MarginContainer/VBoxContainer/SocketAnchor
@onready var option_btn = $MarginContainer/VBoxContainer/OptionButton

func setup(idx: int, s_type: String, p_ui, p_manager):
	slot_idx = idx
	slot_type = s_type
	parent_ui = p_ui
	manager = p_manager
	
	if is_node_ready():
		refresh_state()

func _ready():
	_apply_base_style()
	option_btn.visible = false
	refresh_state()

func _apply_base_style():
	var frame = StyleBoxFlat.new()
	frame.bg_color = Color(0.11, 0.09, 0.08, 0.96)
	frame.set_corner_radius_all(3)
	frame.set_border_width_all(2)
	frame.border_width_top = 5
	frame.border_color = Color(0.35, 0.35, 0.35, 0.5)
	frame.content_margin_left = 6
	frame.content_margin_top = 5
	frame.content_margin_right = 6
	frame.content_margin_bottom = 5
	add_theme_stylebox_override("panel", frame)

func refresh_state():
	if not is_node_ready(): return
	if not manager: manager = GameState.shipyard_manager
	if not manager: return
	
	# Clear old sockets
	for child in socket_anchor.get_children():
		child.queue_free()

	_stop_pulse()

	# CONSUMABLE LOGIC
	if slot_type.begins_with("consumable_"):
		_refresh_consumable_state()
		return

	type_lbl.text = "SLOT %d: %s" % [slot_idx + 1, slot_type.to_upper()]
	type_lbl.add_theme_color_override("font_color", _get_slot_color(slot_type))
	
	option_btn.clear()
	option_btn.add_item("Change...", 0)
	option_btn.set_item_metadata(0, null)
	
	var equipped_id = manager.loadout.get(slot_idx)
	is_occupied = equipped_id != null
	
	if equipped_id:
		var m_data = manager.modules.get(equipped_id)
		if not m_data:
			name_lbl.text = "INVALID ID"
			stats_lbl.text = "?"
			rarity_badge.visible = false
			tooltip_text = "Module data not found for ID: %s" % equipped_id
			option_btn.add_item("Unequip (Invalid)", 1)
			option_btn.set_item_metadata(1, "unequip")
			return

		var clean_name = _get_clean_name(m_data.get("name", "Unknown"))
		name_lbl.text = clean_name.to_upper()
		
		var rarity = manager.get_module_rarity(equipped_id)
		var rarity_color = manager.RARITY_COLORS.get(rarity, Color(0.7, 0.7, 0.7))
		
		name_lbl.add_theme_color_override("font_color", rarity_color.lerp(Color.WHITE, 0.18))
		
		var r_label = manager.RARITY_LABELS.get(rarity, "")
		rarity_badge.visible = r_label != ""
		rarity_badge.text = "[ %s ]" % r_label.to_upper()
		rarity_badge.add_theme_color_override("font_color", rarity_color)

		stats_lbl.text = _build_card_stats(m_data.get("stats", {}))

		_apply_card_style(rarity, rarity_color)
		_apply_pulse(rarity)
		
		tooltip_text = _build_module_tooltip(m_data)

		# Make physical sockets in the SocketAnchor
		if m_data.has("sockets"):
			option_btn.add_separator("--- Matrix Cores ---")
			var h_box = HBoxContainer.new()
			h_box.alignment = BoxContainer.ALIGNMENT_CENTER
			h_box.add_theme_constant_override("separation", 8)
			
			for i in range(m_data["sockets"].size()):
				var gem = m_data["sockets"][i]
				var item_idx = option_btn.item_count
				# Draw actual Physical Socket Visual!
				var sock_bg = Panel.new()
				sock_bg.custom_minimum_size = Vector2(12, 12)
				var sb = StyleBoxFlat.new()
				sb.bg_color = Color(0.01, 0.01, 0.01, 0.9)
				sb.border_width_left = 1; sb.border_width_top = 1; sb.border_width_right = 1; sb.border_width_bottom = 1;
				sb.border_color = Color(0.4, 0.4, 0.4, 0.8)
				
				if gem:
					var gem_name = ElementDB.get_display_name(gem)
					option_btn.add_item("Socket: Remove " + gem_name, item_idx)
					option_btn.set_item_metadata(item_idx, {"action": "remove_gem", "socket_idx": i})
					
					var g_color = Color("#ff4444") if "Crimson" in gem_name else (Color("#44ccff") if "Cobalt" in gem_name else (Color("#ffcc00") if "Topaz" in gem_name else Color("#aa44ff")))
					sb.bg_color = g_color
					sb.border_color = g_color.lightened(0.6)
					sb.shadow_color = g_color * Color(1, 1, 1, 0.4)
					sb.shadow_size = 6
				else:
					option_btn.add_item("Socket: [Empty]", item_idx)
					option_btn.set_item_disabled(item_idx, true)
				
				sock_bg.add_theme_stylebox_override("panel", sb)
				sock_bg.pivot_offset = Vector2(6, 6)
				sock_bg.rotation_degrees = 45 # Diamond layout
				
				var sock_wrap = Control.new()
				sock_wrap.custom_minimum_size = Vector2(20, 20)
				sock_bg.position = Vector2(4, 4)
				sock_wrap.add_child(sock_bg)
				h_box.add_child(sock_wrap)
				
			socket_anchor.add_child(h_box)
			option_btn.add_separator("---------------------")
		
		option_btn.add_item("Unequip", option_btn.item_count)
		option_btn.set_item_metadata(option_btn.item_count - 1, "unequip")
	else:
		name_lbl.text = "EMPTY"
		name_lbl.add_theme_color_override("font_color", Color(0.33, 0.33, 0.33))
		stats_lbl.text = "--"
		rarity_badge.visible = false
		_apply_base_style()
		tooltip_text = "Empty %s Slot\nDrag a module here to equip" % slot_type.capitalize()

	# Populate Inventory Options
	var inv = manager.module_inventory
	var idx_counter = option_btn.item_count
	for mid in inv:
		var count = inv[mid]
		if count > 0 and mid in manager.modules:
			var m_data = manager.modules[mid]
			if m_data["slot_type"] == slot_type:
				var item_idx = option_btn.item_count
				var m_rarity = manager.get_module_rarity(mid)
				var r_label = manager.RARITY_LABELS.get(m_rarity, "COMMON").to_upper()
				
				var status = manager.can_equip_module(mid)
				var lock_icon = "[LOCK] " if not status["can_equip"] else ""
				
				var display_name = "%s[%s] %s (x%d)" % [lock_icon, r_label, m_data["name"], count]
				if m_rarity == manager.Rarity.COMMON:
					display_name = "%s%s (x%d)" % [lock_icon, m_data["name"], count]
					
				option_btn.add_item(display_name, idx_counter)
				option_btn.set_item_metadata(item_idx, mid)
				idx_counter += 1

func _refresh_consumable_state():
	_apply_base_style()
	var c_type = "hull" if slot_type == "consumable_hull" else "shield"
	
	type_lbl.text = "HULL REPAIR" if c_type == "hull" else "SHIELD REPAIR"
	type_lbl.add_theme_color_override("font_color", Color(0.74, 0.74, 0.86))
	rarity_badge.visible = false
	
	option_btn.clear()
	option_btn.add_item("Change...", 0)
	
	var equipped_id = manager.get_consumable(c_type)
	if equipped_id != "":
		var data = ElementDB.get_consumable_data(equipped_id)
		var dname = data.get("name", equipped_id)
		var qty = GameState.resources.get_element_amount(equipped_id)
		var heal_pct = int(round(data.get("stats", {}).get("heal_pct", 0.0) * 100.0))
		
		name_lbl.text = "%s (x%d)" % [dname, qty]
		name_lbl.add_theme_color_override("font_color", Color(0.74, 0.74, 0.86))
		
		stats_lbl.text = "Restores %d%% %s" % [heal_pct, c_type.capitalize()]
		
		tooltip_text = "%s\nRestores %d%% %s" % [dname, heal_pct, c_type.capitalize()]
		
		option_btn.add_item("Unequip", 1)
		option_btn.set_item_metadata(1, "unequip")
	else:
		name_lbl.text = "EMPTY SLOT"
		name_lbl.add_theme_color_override("font_color", Color(0.33, 0.33, 0.33))
		stats_lbl.text = "--"
		tooltip_text = "Drag a Consumable here"

	var items = ElementDB.get_elements_in_category("consumables")
	var idx = 2
	for id in items:
		var data = ElementDB.get_consumable_data(id)
		if data.get("type") == c_type:
			var qty = GameState.resources.get_element_amount(id)
			if qty > 0:
				option_btn.add_item("%s (x%d)" % [data.get("name", id), qty], idx)
				option_btn.set_item_metadata(idx, id)
				idx += 1

func _get_clean_name(raw_name: String) -> String:
	var title = raw_name
	for suffix in [" (Common)", " (Uncommon)", " (Rare)", " (Legendary)", " (Unique)"]:
		title = title.replace(suffix, "")
	return title

func _get_slot_color(s_type: String) -> Color:
	match s_type:
		"weapon": return Color(0.92, 0.48, 0.32)
		"shield": return Color(0.50, 0.72, 0.95)
		"armor": return Color(0.78, 0.73, 0.66)
		"engine", "reactor", "battery": return Color(0.84, 0.79, 0.43)
		"ammo": return Color(0.88, 0.60, 0.34)
		"consumable": return Color(0.74, 0.74, 0.86)
		_: return Color(0.65, 0.58, 0.47)

func _get_rarity_background(rarity: int) -> Color:
	if rarity == manager.Rarity.UNCOMMON: return Color(0.08, 0.11, 0.08, 0.96)
	if rarity == manager.Rarity.RARE: return Color(0.07, 0.10, 0.14, 0.96)
	if rarity == manager.Rarity.LEGENDARY: return Color(0.15, 0.10, 0.06, 0.98)
	if rarity == manager.Rarity.UNIQUE: return Color(0.16, 0.08, 0.14, 0.98)
	return Color(0.11, 0.09, 0.08, 0.96)

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

	if rarity == manager.Rarity.LEGENDARY or rarity == manager.Rarity.UNIQUE:
		frame.set_border_width_all(3)
		frame.border_width_top = 6
		frame.shadow_size = 12

	if rarity == manager.Rarity.UNIQUE:
		frame.border_color = Color(0.85, 0.65, 0.25, 1.0) # Antique Legendary Gold

	add_theme_stylebox_override("panel", frame)

func _apply_pulse(rarity: int):
	_stop_pulse()
	if rarity == manager.Rarity.LEGENDARY:
		pulse_tween = create_tween().set_loops()
		pulse_tween.tween_property(self, "modulate", Color(1.08, 1.03, 0.94), 0.9).set_trans(Tween.TRANS_SINE)
		pulse_tween.tween_property(self, "modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
	elif rarity == manager.Rarity.UNIQUE:
		pulse_tween = create_tween().set_loops()
		pulse_tween.tween_property(self, "modulate", Color(1.10, 0.97, 1.08), 0.9).set_trans(Tween.TRANS_SINE)
		pulse_tween.tween_property(self, "modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)

func _stop_pulse():
	if pulse_tween and is_instance_valid(pulse_tween):
		pulse_tween.kill()
	pulse_tween = null
	modulate = Color.WHITE

func _build_card_stats(stats: Dictionary) -> String:
	var lines: Array[String] = []

	if slot_type == "weapon":
		var dmg = stats.get("atk_kinetic", 0) + stats.get("atk_energy", 0) + stats.get("atk_explosive", 0)
		var interval = max(0.01, float(stats.get("atk_interval", 2.5)))
		lines.append("DPS: %.1f" % (float(dmg) / interval))

	var keys = stats.keys()
	keys.sort()
	for key in keys:
		if key == "atk_interval": continue
		var val = stats[key]
		if key == "energy_load" and val == 0: continue
		if slot_type == "weapon" and key in ["atk_kinetic", "atk_energy", "atk_explosive"]: continue
		
		var label = FormatUtils.format_stat_label(key)
		lines.append("%s: %s" % [label, FormatUtils.format_stat_value(key, val)])
		if lines.size() >= 3: break

	if lines.is_empty():
		return "No combat modifiers"
	return "\n".join(lines)


func _get_drag_data(at_position):
	if slot_type.begins_with("consumable_"):
		var c_type = "hull" if slot_type == "consumable_hull" else "shield"
		var equipped_id = manager.get_consumable(c_type)
		if equipped_id == "": return null
		
		return {
			"type": "unequip_consumable",
			"slot_type": c_type,
			"id": equipped_id
		}
	
	var equipped_id = manager.loadout.get(slot_idx)
	if not equipped_id: return null
	
	var drag_data = {
		"type": "unequip_module",
		"slot_idx": slot_idx,
		"mid": equipped_id,
		"slot_type": slot_type
	}
	
	var preview = load("res://scenes/ui/designer_slot_widget.tscn").instantiate()
	preview.setup(slot_idx, slot_type, parent_ui, manager)
	
	var preview_container = Control.new()
	preview_container.add_child(preview)
	
	preview.scale = Vector2(1.05, 1.05)
	preview.modulate = Color(1.0, 0.7, 0.7, 0.95)
	
	var shadow = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.45)
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 12)
	shadow.add_theme_stylebox_override("panel", style)
	shadow.custom_minimum_size = Vector2(144, 224)
	
	preview_container.add_child(shadow)
	preview_container.move_child(shadow, 0)
	
	preview.position = Vector2(-70, -110)
	shadow.position = Vector2(-70, -110)
	
	set_drag_preview(preview_container)
	return drag_data

func _can_drop_data(at_position, data):
	if typeof(data) != TYPE_DICTIONARY: return false
	
	if slot_type.begins_with("consumable_"):
		var c_type = "hull" if slot_type == "consumable_hull" else "shield"
		if data.get("type") == "consumable":
			return data.get("consumable_type") == c_type
		return false
		
	if data.get("type") == "module":
		if data.get("slot_type") == "gem":
			var equipped_id = manager.loadout.get(slot_idx)
			if equipped_id:
				var m_data = manager.modules.get(equipped_id)
				if m_data and m_data.has("sockets"):
					return true
			return false
		return data.get("slot_type") == slot_type
	return false

func _drop_data(at_position, data):
	if slot_type.begins_with("consumable_"):
		var c_type = "hull" if slot_type == "consumable_hull" else "shield"
		var item_id = data.get("mid", "")
		if data.get("type") == "consumable":
			manager.equip_consumable(c_type, item_id)
			UITheme.trigger_circuit_surge(self)
			parent_ui.trigger_refresh()
		return

	var mid = data.get("mid")
	
	if data.get("type") == "module" and data.get("slot_type") == "gem":
		var equipped_id = manager.loadout.get(slot_idx)
		if equipped_id:
			var m_data = manager.modules.get(equipped_id)
			if m_data and m_data.has("sockets"):
				var socket_idx = -1
				for i in range(m_data["sockets"].size()):
					if m_data["sockets"][i] == null:
						socket_idx = i
						break
				
				if socket_idx >= 0:
					if manager.insert_gem(equipped_id, socket_idx, mid):
						UITheme.trigger_circuit_surge(self)
						parent_ui.trigger_refresh()
					else:
						UITheme.show_notification("Failed to insert core.", Color.RED)
				else:
					UITheme.show_notification("No empty sockets available.", Color.RED)
		return

	if manager.equip_module(slot_idx, mid):
		UITheme.trigger_circuit_surge(self)
		parent_ui.trigger_refresh()

func _on_option_button_item_selected(index):
	var data = option_btn.get_item_metadata(index)
	
	if slot_type.begins_with("consumable_"):
		var c_type = "hull" if slot_type == "consumable_hull" else "shield"
		if data == "unequip":
			manager.unequip_consumable(c_type)
		elif data:
			manager.equip_consumable(c_type, data)
		parent_ui.trigger_refresh()
		option_btn.select(0)
		return

	if data == "unequip":
		manager.unequip_slot(slot_idx)
		parent_ui.trigger_refresh()
	elif typeof(data) == TYPE_DICTIONARY and data.get("action") == "remove_gem":
		if manager.remove_gem(manager.loadout.get(slot_idx), data["socket_idx"]):
			UITheme.trigger_circuit_surge(self)
			parent_ui.trigger_refresh()
	elif typeof(data) == TYPE_STRING:
		if manager.equip_module(slot_idx, data):
			UITheme.trigger_circuit_surge(self)
			parent_ui.trigger_refresh()
	
	option_btn.select(0)

func _gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if slot_type.begins_with("consumable_"):
				var c_type = "hull" if slot_type == "consumable_hull" else "shield"
				manager.unequip_consumable(c_type)
			else:
				manager.unequip_slot(slot_idx)
			parent_ui.trigger_refresh()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if parent_ui and parent_ui.has_method("_on_filter_changed"):
				var target_filter = "all"
				if slot_type == "weapon": target_filter = "weapon"
				elif slot_type == "shield": target_filter = "shield"
				elif slot_type == "armor": target_filter = "armor"
				elif slot_type == "engine": target_filter = "engine"
				elif slot_type == "battery": target_filter = "battery"
				elif slot_type in ["reactor", "sensor", "cooling"]: target_filter = "utility"
				elif slot_type.begins_with("consumable_"): target_filter = "ordnance"
				
				parent_ui._on_filter_changed(target_filter)
				UITheme.trigger_ui_thud(self, 1.0)

# TOOLTIP

func _make_custom_tooltip(_for_text: String) -> Control:
	var equipped_id = manager.loadout.get(slot_idx)
	if not equipped_id: return null
	var m_data = manager.modules.get(equipped_id)
	if not m_data: return null

	var panel = PanelContainer.new()
	var rarity = manager.get_module_rarity(equipped_id)
	var r_color = manager.RARITY_COLORS.get(rarity, Color(0.2, 0.2, 0.2))

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.03, 0.98)
	style.border_color = r_color
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

	rtl.text = _build_module_tooltip(m_data)
	panel.add_child(rtl)

	return panel

func _build_module_tooltip(m_data: Dictionary) -> String:
	var equipped_id = manager.loadout.get(slot_idx)
	var rarity = manager.get_module_rarity(equipped_id)
	var rarity_label = manager.RARITY_LABELS.get(rarity, "Common")
	if rarity == manager.Rarity.COMMON:
		rarity_label = "Common"

	var rarity_color_hex = manager.RARITY_COLORS.get(rarity, Color.GRAY).to_html(false)
	var s_type = m_data.get("slot_type", "weapon")
	var div = "[color=#3d3d3d]───────────────────────────────[/color]\n"

	var tt = ""

	var display_name = _get_clean_name(m_data.get("name", "Item")).to_upper()
	tt += "[b][color=#%s]%s[/color][/b]\n" % [rarity_color_hex, display_name]
	tt += "[font_size=10][color=gray]%s %s[/color][/font_size]\n" % [rarity_label, s_type.capitalize()]
	tt += div

	var stats = m_data.get("stats", {})

	if s_type == "weapon":
		var dmg = stats.get("atk_kinetic", 0) + stats.get("atk_energy", 0) + stats.get("atk_explosive", 0)
		var interval = max(0.01, float(stats.get("atk_interval", 2.5)))
		var dps = float(dmg) / interval
		tt += "[font_size=20][b]%.1f DPS[/b][/font_size]\n" % dps
		tt += "[font_size=9][color=gray]%s total damage, %.2f hits/s[/color][/font_size]\n" % [UITheme.format_num(dmg), 1.0 / interval]
		tt += div
	elif s_type == "shield":
		var m_shield = stats.get("max_shield", 0)
		tt += "[font_size=20][b]%s[/b][/font_size] [font_size=10][color=gray]Shield Capacity[/color][/font_size]\n" % UITheme.format_num(m_shield)
		tt += div
	elif s_type == "armor":
		var hp_val = stats.get("hp", 0)
		tt += "[font_size=20][b]%s[/b][/font_size] [font_size=10][color=gray]Integrity Reinforcement[/color][/font_size]\n" % UITheme.format_num(hp_val)
		tt += div

	var keys = stats.keys()
	keys.sort()
	for key in keys:
		if key == "atk_interval": continue
		if s_type == "weapon" and key in ["atk_kinetic", "atk_energy", "atk_explosive"]: continue
		if s_type == "shield" and key == "max_shield": continue
		if s_type == "armor" and key == "hp": continue
		
		var label = FormatUtils.format_stat_label(key)
		var val = stats[key]
		var val_str = FormatUtils.format_stat_value(key, val)
		
		# v76.0: Display Roll Range for base stats
		var range_info = ""
		var base_id = m_data.get("base_module", "")
		var item_rarity_val = m_data.get("rarity", manager.Rarity.COMMON)
		if base_id != "" and base_id in manager.modules and key in manager.BOOSTABLE_STATS:
			var base_val = manager.modules[base_id].get("stats", {}).get(key, 0)
			if base_val > 0:
				var s_range = manager.RARITY_STAT_RANGE.get(item_rarity_val, [0, 0])
				if s_range[1] > 0:
					var r_min = base_val * (1.0 + s_range[0])
					var r_max = base_val * (1.0 + s_range[1])
					range_info = " [color=gray][font_size=9][%s-%s][/font_size][/color]" % [
						FormatUtils.format_stat_value(key, r_min),
						FormatUtils.format_stat_value(key, r_max)
					]

		tt += "%s: %s%s\n" % [label, val_str, range_info]

	var affixes = m_data.get("affixes", {})
	if affixes.size() > 0:
		tt += div
		for aid in affixes:
			if aid in manager.AFFIX_DB:
				var cfg = manager.AFFIX_DB[aid]
				var val = int(affixes[aid] * 100)
				var r_min = int(cfg["range"][0] * 100)
				var r_max = int(cfg["range"][1] * 100)
				
				var item_rarity = m_data.get("rarity", manager.Rarity.COMMON)
				var icon = "⋄"
				if item_rarity == manager.Rarity.LEGENDARY: icon = "★"
				elif item_rarity == manager.Rarity.UNIQUE: icon = "✦"
				
				tt += "[color=#8fc5ff]%s %s[/color] [color=gray][font_size=9][%d-%d]%%[/font_size][/color]\n" % [icon, (cfg["desc"] % val), r_min, r_max]

	if m_data.has("sockets"):
		tt += div
		for gem in m_data["sockets"]:
			if gem:
				var g_name = ElementDB.get_display_name(gem)
				tt += "[color=#b548b5]⋄ %s[/color]\n" % g_name
			else:
				tt += "[color=#444444]⋄ Empty Socket[/color]\n"

	tt += div
	tt += "[center][font_size=10][color=gray][Right-click to unequip][/color][/font_size][/center]"
	return tt
