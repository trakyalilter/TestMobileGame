extends PanelContainer

var slot_idx: int
var slot_type: String
var parent_ui: Node
var manager: RefCounted
var is_occupied: bool = false
var pulse_tween: Tween

var _active_gem_card = null
var _info_card_scene = preload("res://scenes/ui/info_card.tscn")
var _is_focused: bool = false

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
	# Only refresh if setup() already ran; otherwise the empty slot_type falls
	# through to the module-render path and bleeds set labels into consumable slots.
	if slot_type != "":
		refresh_state()

func _apply_base_style():
	var frame = StyleBoxFlat.new()
	frame.bg_color = Color(0.08, 0.08, 0.1, 0.9)
	frame.set_corner_radius_all(2)
	frame.set_border_width_all(1)
	frame.border_color = Color(0.2, 0.2, 0.25, 1.0)
	
	# Top accent bar instead of just border
	frame.border_width_top = 4
	frame.border_color = Color(0.3, 0.3, 0.4, 0.8)
	
	frame.content_margin_left = 8
	frame.content_margin_top = 6
	frame.content_margin_right = 8
	frame.content_margin_bottom = 6
	
	# Inner shadow for depth
	frame.shadow_color = Color(0, 0, 0, 0.5)
	frame.shadow_size = 4

	if _is_focused:
		frame.border_width_top = 5
		frame.border_color = Color(0.4, 0.82, 1.0, 0.9)
		frame.shadow_color = Color(0.4, 0.82, 1.0, 0.35)
		frame.shadow_size = 10

	add_theme_stylebox_override("panel", frame)

func _get_type_number() -> int:
	if not parent_ui or not "all_slot_widgets" in parent_ui: return slot_idx + 1
	var n = 1
	for w in parent_ui.all_slot_widgets:
		if w == self: break
		if is_instance_valid(w) and w.slot_type == slot_type: n += 1
	return n

func set_focus_highlight(on: bool):
	_is_focused = on
	if is_occupied and not slot_type.begins_with("consumable_") and manager:
		var equipped_id = manager.loadout.get(slot_idx, "")
		if equipped_id != "" and equipped_id in manager.modules:
			var rarity = manager.get_module_rarity(equipped_id)
			var rarity_color = manager.RARITY_COLORS.get(rarity, Color(0.7, 0.7, 0.7))
			_apply_card_style(rarity, rarity_color)
			return
	_apply_base_style()

func refresh_state():
	if not is_node_ready(): return
	if not manager: manager = GameState.shipyard_manager
	if not manager: return
	
	# Clear old sockets
	for child in socket_anchor.get_children():
		child.queue_free()

	var old_uneq = $MarginContainer/VBoxContainer.get_node_or_null("QuickUnequipBtn")
	if is_instance_valid(old_uneq): old_uneq.free()

	var old_repair = $MarginContainer/VBoxContainer.get_node_or_null("QuickRepairBtn")
	if is_instance_valid(old_repair): old_repair.free()

	_stop_pulse()

	# CONSUMABLE LOGIC
	if slot_type.begins_with("consumable_"):
		_refresh_consumable_state()
		return

	type_lbl.text = "%s %d" % [slot_type.to_upper(), _get_type_number()]
	type_lbl.add_theme_color_override("font_color", _get_slot_color(slot_type))
	
	option_btn.clear()
	option_btn.add_item("EQUIP ▼", 0)
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
		
		# v83.9: Set Name Display for equipped slots
		var sid = m_data.get("set_id", "")
		if sid == "" and m_data.get("is_custom") and m_data.has("base_module"):
			var base_id = m_data["base_module"]
			sid = manager.modules.get(base_id, {}).get("set_id", "")
		
		var v_box = $MarginContainer/VBoxContainer
		var set_lbl = v_box.get_node_or_null("SetLabel")
		if not set_lbl:
			set_lbl = Label.new()
			set_lbl.name = "SetLabel"
			set_lbl.add_theme_font_size_override("font_size", 8)
			set_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			set_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v_box.add_child(set_lbl)
			v_box.move_child(set_lbl, name_lbl.get_index() + 1)
		
		if sid != "" and GameState.combat_manager and "TRINITY_SET_BONUSES" in GameState.combat_manager:
			var s_db = GameState.combat_manager.TRINITY_SET_BONUSES
			if s_db.has(sid):
				var set_name = s_db[sid]["name"]
				set_lbl.text = "[ %s ]" % set_name.to_upper()
				set_lbl.add_theme_color_override("font_color", Color(0.0, 0.8, 0.8)) # Cyan
				set_lbl.visible = true
			else: set_lbl.visible = false
		else: set_lbl.visible = false
		
		var rarity = manager.get_module_rarity(equipped_id)
		var rarity_color = manager.RARITY_COLORS.get(rarity, Color(0.7, 0.7, 0.7))
		
		name_lbl.add_theme_color_override("font_color", rarity_color.lerp(Color.WHITE, 0.18))
		
		var r_label = manager.RARITY_LABELS.get(rarity, "")
		rarity_badge.visible = r_label != ""
		rarity_badge.text = "[ %s ]" % r_label.to_upper()
		rarity_badge.add_theme_color_override("font_color", rarity_color)

		stats_lbl.text = _build_card_stats(m_data.get("stats", {}))
		
		var durability = int(m_data.get("durability", 100))
		stats_lbl.text += "\nDurability: %d/100" % durability

		var uneq_btn = Button.new()
		uneq_btn.name = "QuickUnequipBtn"
		uneq_btn.text = "× Unequip"
		uneq_btn.flat = true
		uneq_btn.add_theme_font_size_override("font_size", 9)
		uneq_btn.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
		uneq_btn.pressed.connect(func():
			manager.unequip_slot(slot_idx)
			if parent_ui: parent_ui.trigger_refresh()
		)
		$MarginContainer/VBoxContainer.add_child(uneq_btn)
		$MarginContainer/VBoxContainer.move_child(uneq_btn, option_btn.get_index())

		# Per-module repair affordance (replaces global repair-mode discovery problem).
		# Shown when the equipped module is a custom drop and below full durability.
		if equipped_id.begins_with("custom_") and durability < 100:
			var repair_btn = Button.new()
			repair_btn.name = "QuickRepairBtn"
			repair_btn.text = "🔧 Repair  %d%%" % durability
			repair_btn.flat = true
			repair_btn.add_theme_font_size_override("font_size", 9)
			var dur_col := Color(0.95, 0.85, 0.30)
			if durability <= 25: dur_col = Color(0.95, 0.40, 0.30)
			elif durability <= 50: dur_col = Color(0.95, 0.65, 0.25)
			repair_btn.add_theme_color_override("font_color", dur_col)
			repair_btn.tooltip_text = "Repair this module without entering global Repair Mode."
			repair_btn.pressed.connect(_try_repair)
			$MarginContainer/VBoxContainer.add_child(repair_btn)
			$MarginContainer/VBoxContainer.move_child(repair_btn, uneq_btn.get_index() + 1)

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
					
					var g_color = _get_gem_color(gem_name)
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
				
				# v83.9.1: Interactive Gem Removal
				if gem:
					sock_wrap.mouse_filter = Control.MOUSE_FILTER_STOP
					sock_wrap.tooltip_text = "Matrix Core: %s\n[Right-Click to remove]" % ElementDB.get_display_name(gem)
					var captured_gem = gem
					sock_wrap.mouse_entered.connect(func():
						if _active_gem_card: _active_gem_card.queue_free()
						var card = _info_card_scene.instantiate()
						var main = get_tree().current_scene
						var modal = main.get_node_or_null("ModalLayer")
						if modal: modal.add_child(card)
						else: main.add_child(card)
						card.setup(captured_gem, "gem")
						var mpos = get_global_mouse_position()
						var vp = get_viewport().get_visible_rect().size
						card.global_position = mpos + Vector2(20, -20)
						await get_tree().process_frame
						if is_instance_valid(card):
							if card.global_position.x + card.size.x > vp.x:
								card.global_position.x = mpos.x - card.size.x - 20
							if card.global_position.y + card.size.y > vp.y:
								card.global_position.y = mpos.y - card.size.y - 20
						_active_gem_card = card
					)
					sock_wrap.mouse_exited.connect(func():
						if _active_gem_card:
							_active_gem_card.queue_free()
							_active_gem_card = null
					)
					sock_wrap.gui_input.connect(func(event):
						if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
							if _active_gem_card:
								_active_gem_card.queue_free()
								_active_gem_card = null
							if manager.remove_gem(equipped_id, i):
								UITheme.trigger_circuit_surge(self)
								parent_ui.trigger_refresh()
					)
				
				h_box.add_child(sock_wrap)
				
			socket_anchor.add_child(h_box)
			option_btn.add_separator("---------------------")
		
		option_btn.add_item("Unequip", option_btn.item_count)
		option_btn.set_item_metadata(option_btn.item_count - 1, "unequip")
	else:
		name_lbl.text = ""
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

	# Belt-and-suspenders: hide any SetLabel that an early refresh may have left here.
	# Consumables are not part of Trinity sets, so this label should never appear.
	var stale_set_lbl = $MarginContainer/VBoxContainer.get_node_or_null("SetLabel")
	if stale_set_lbl: stale_set_lbl.visible = false
	
	option_btn.clear()
	option_btn.add_item("EQUIP ▼", 0)

	var equipped_id = manager.get_consumable(c_type)
	if equipped_id != "":
		var data = ElementDB.get_consumable_data(equipped_id)
		var dname = data.get("name", equipped_id)
		var qty = GameState.resources.get_element_amount(equipped_id)
		var heal_pct = int(round(data.get("heal_pct", data.get("stats", {}).get("heal_pct", 0.0)) * 100.0))
		
		name_lbl.text = "%s (x%d)" % [dname, qty]
		name_lbl.add_theme_color_override("font_color", Color(0.74, 0.74, 0.86))
		
		stats_lbl.text = "Restores %d%% %s" % [heal_pct, c_type.capitalize()]
		
		tooltip_text = "%s\nRestores %d%% %s" % [dname, heal_pct, c_type.capitalize()]
		
		option_btn.add_item("Unequip", 1)
		option_btn.set_item_metadata(1, "unequip")
	else:
		name_lbl.text = ""
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
				option_btn.set_item_metadata(option_btn.get_item_count() - 1, id)
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

func _get_gem_color(gem_name: String) -> Color:
	if "Crimson" in gem_name: return Color("#ff4444")
	if "Cobalt" in gem_name: return Color("#44ccff")
	if "Topaz" in gem_name: return Color("#ffcc00")
	if "Amethyst" in gem_name: return Color("#aa44ff")
	return Color("#b548b5") # Default purple

func _get_rarity_background(rarity: int) -> Color:
	if rarity == manager.Rarity.UNCOMMON: return Color(0.08, 0.11, 0.08, 0.96)
	if rarity == manager.Rarity.RARE: return Color(0.07, 0.10, 0.14, 0.96)
	if rarity == manager.Rarity.LEGENDARY: return Color(0.15, 0.10, 0.06, 0.98)
	if rarity == manager.Rarity.UNIQUE: return Color(0.16, 0.08, 0.14, 0.98)
	return Color(0.11, 0.09, 0.08, 0.96)

func _apply_card_style(rarity: int, rarity_color: Color):
	var frame = StyleBoxFlat.new()
	frame.bg_color = _get_rarity_background(rarity)
	frame.set_corner_radius_all(2)
	frame.set_border_width_all(1)
	frame.border_color = rarity_color.lerp(Color.WHITE, 0.3)
	frame.border_color.a = 0.5
	
	# Top accent bar
	frame.border_width_top = 5
	frame.border_color = rarity_color
	
	frame.content_margin_left = 8
	frame.content_margin_top = 6
	frame.content_margin_right = 8
	frame.content_margin_bottom = 6
	
	# Premium outer glow for rarity
	frame.shadow_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.3)
	frame.shadow_size = 10
	
	if rarity >= manager.Rarity.RARE:
		frame.shadow_size = 15
		frame.set_border_width_all(2)
		
	if rarity >= manager.Rarity.LEGENDARY:
		frame.border_color.a = 0.9
		frame.shadow_size = 20
		frame.shadow_color.a = 0.5

	if _is_focused:
		frame.border_color = Color(0.4, 0.82, 1.0)
		frame.border_width_top = 6
		frame.shadow_color = Color(0.4, 0.82, 1.0, 0.5)
		frame.shadow_size = 16

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


func _get_drag_data(at_position: Vector2) -> Variant:
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
	preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_container.add_child(preview)
	
	preview.scale = Vector2(1.05, 1.05)
	preview.modulate = Color(1.0, 0.7, 0.7, 0.95)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shadow = Panel.new()
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	
	var queue = [preview_container]
	while queue.size() > 0:
		var n = queue.pop_front()
		if n is Control:
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue.append_array(n.get_children())

	set_drag_preview(preview_container)
	return drag_data

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
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

func _drop_data(at_position: Vector2, data: Variant) -> void:
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
		if parent_ui and "is_repair_mode" in parent_ui and parent_ui.is_repair_mode:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if is_occupied and not slot_type.begins_with("consumable_"):
					_try_repair()
				return
				
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if slot_type.begins_with("consumable_"):
				var c_type = "hull" if slot_type == "consumable_hull" else "shield"
				manager.unequip_consumable(c_type)
			else:
				manager.unequip_slot(slot_idx)
			parent_ui.trigger_refresh()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if slot_type.begins_with("consumable_"):
				if parent_ui and parent_ui.has_method("_on_filter_changed"):
					parent_ui._on_filter_changed("ordnance")
					UITheme.trigger_ui_thud(self, 1.0)
			elif parent_ui and parent_ui.has_method("set_focused_slot"):
				var equipped_mid = manager.loadout.get(slot_idx, "")
				parent_ui.set_focused_slot(slot_idx, slot_type, equipped_mid)
				UITheme.trigger_ui_thud(self, 1.0)

func _try_repair():
	var equipped_id = manager.loadout.get(slot_idx)
	if not equipped_id or not equipped_id.begins_with("custom_"):
		UITheme.show_notification("Cannot repair this module", Color.RED)
		return
		
	var m_data = manager.modules.get(equipped_id)
	var cur_dur = m_data.get("durability", 100)
	if cur_dur >= 100:
		UITheme.show_notification("Module is at maximum durability", Color.GREEN)
		return
		
	var missing = 100 - cur_dur
	var chunks = ceili(missing / 10.0)
	var rarity = manager.get_module_rarity(equipped_id)
	
	# Cost calculation
	var parts_cost = manager.RARITY_SPARE_PARTS.get(rarity, 1) * chunks
	var credit_cost = max(50, int(manager.get_sell_price(equipped_id) * 0.2)) * chunks
	
	_spawn_custom_repair_modal(m_data, cur_dur, credit_cost, parts_cost)

func _spawn_custom_repair_modal(m_data: Dictionary, cur_dur: int, credit_cost: int, parts_cost: int):
	var layer = CanvasLayer.new()
	layer.layer = 100
	
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.07, 0.98)
	style.set_border_width_all(2)
	style.border_width_top = 4
	style.border_color = Color(0.8, 0.6, 0.2, 0.9)
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0, 0, 0, 0.8)
	style.shadow_size = 20
	panel.add_theme_stylebox_override("panel", style)
	
	panel.custom_minimum_size = Vector2(340, 0)
	center.add_child(panel)
	
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 20)
	marg.add_theme_constant_override("margin_top", 20)
	marg.add_theme_constant_override("margin_right", 20)
	marg.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(marg)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	marg.add_child(vbox)
	
	var title = Label.new()
	title.text = "REPAIR MODULE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	vbox.add_child(title)
	
	var desc = Label.new()
	desc.text = "Restore %s from %d%% back to maximum durability (100%%)?" % [m_data.get("name", "Unknown").to_upper(), cur_dur]
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(desc)
	
	var cost_box = VBoxContainer.new()
	cost_box.add_theme_constant_override("separation", 4)
	vbox.add_child(cost_box)
	
	var c_lbl = Label.new()
	c_lbl.text = "Cost: %s Credits" % UITheme.format_num(credit_cost)
	c_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c_lbl.add_theme_font_size_override("font_size", 14)
	c_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.4))
	cost_box.add_child(c_lbl)
	
	var p_lbl = Label.new()
	p_lbl.text = "Required: %d Spare Parts" % parts_cost
	p_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p_lbl.add_theme_font_size_override("font_size", 14)
	p_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	cost_box.add_child(p_lbl)
	
	var has_funds = GameState.resources.get_currency("credits") >= credit_cost and GameState.resources.get_element_amount("SparePart") >= parts_cost
	if not has_funds:
		var w_lbl = Label.new()
		w_lbl.text = "INSUFFICIENT RESOURCES"
		w_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		w_lbl.add_theme_font_size_override("font_size", 12)
		w_lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		cost_box.add_child(w_lbl)
	
	var btn_box = HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_box)
	
	var cancel = Button.new()
	cancel.text = " Cancel "
	cancel.custom_minimum_size = Vector2(100, 30)
	_style_repair_button(cancel, Color(0.6, 0.2, 0.2))
	btn_box.add_child(cancel)
	
	var confirm = Button.new()
	confirm.text = " Confirm "
	confirm.custom_minimum_size = Vector2(100, 30)
	confirm.disabled = not has_funds
	_style_repair_button(confirm, Color(0.2, 0.6, 0.2))
	if has_funds:
		confirm.add_theme_color_override("font_color", Color(0.6, 1.0, 0.5))
	btn_box.add_child(confirm)
	
	cancel.pressed.connect(layer.queue_free)
	confirm.pressed.connect(func():
		if manager.repair_module(slot_idx, credit_cost, parts_cost):
			UITheme.show_notification("Repaired Successfully!", Color.GREEN)
			parent_ui.trigger_refresh()
		else:
			UITheme.show_notification("Insufficient Resources", Color.RED)
		layer.queue_free()
	)
	
	parent_ui.add_child(layer)

func _style_repair_button(btn: Button, hover_color: Color):
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.10, 0.09, 0.95)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.4, 0.3, 0.2, 0.8)
	normal.set_corner_radius_all(3)
	
	var hover = normal.duplicate()
	hover.bg_color = hover_color
	hover.border_color = Color.WHITE
	
	var pressed = hover.duplicate()
	pressed.bg_color = hover_color.darkened(0.2)
	
	var disabled = normal.duplicate()
	disabled.bg_color = Color(0.05, 0.05, 0.05, 0.8)
	disabled.border_color = Color(0.2, 0.2, 0.2, 0.5)
	
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("disabled", disabled)

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
	var div = "[color=#3d3d3d]-------------------------------[/color]\n"

	var tt = ""

	var display_name = _get_clean_name(m_data.get("name", "Item")).to_upper()
	tt += "[b][color=#%s]%s[/color][/b]\n" % [rarity_color_hex, display_name]
	tt += "[font_size=10][color=gray]%s %s[/color][/font_size]\n" % [rarity_label, s_type.capitalize()]
	
	var durability = int(m_data.get("durability", 100))
	var dur_col = "green"
	if durability <= 25: dur_col = "red"
	elif durability <= 50: dur_col = "orange"
	elif durability <= 75: dur_col = "yellow"
	tt += "[font_size=10][color=gray]Durability:[/color] [color=%s]%d/100[/color][/font_size]\n" % [dur_col, durability]
	
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
		var item_rarity_val = int(m_data.get("rarity", manager.Rarity.COMMON))
		if base_id != "" and base_id in manager.modules and key in manager.BOOSTABLE_STATS:
			var base_val = manager.modules[base_id].get("stats", {}).get(key, 0)
			if base_val > 0:
				var s_range = manager.RARITY_STAT_RANGE.get(item_rarity_val, [0, 0])
				if s_range[1] > 0:
					var r_min = 0.0
					var r_max = 0.0
					var zone_mult = 1.0
					if key in manager.ZONE_SCALABLE_STATS and m_data.has("zone_difficulty"):
						zone_mult = manager.get_module_zone_multiplier(int(m_data.get("zone_difficulty", 1)))
					
					if key == "atk_interval":
						# Better = Lower. Range is [Slowest - Fastest]
						var scaled_base = max(0.25, float(base_val) / zone_mult)
						r_min = max(scaled_base / (1.0 + (s_range[1] * 0.4)), 0.25) # Best (fastest)
						r_max = max(scaled_base / (1.0 + (s_range[0] * 0.4)), 0.25) # Worst (slowest)
					else:
						# Better = Higher. Range is [Lowest - Highest]
						var scaled_base = base_val * zone_mult
						r_min = scaled_base * (1.0 + s_range[0])
						r_max = scaled_base * (1.0 + s_range[1])
						
					range_info = " [color=gray][font_size=9][%s-%s][/font_size][/color]" % [
						FormatUtils.format_stat_value(key, r_min),
						FormatUtils.format_stat_value(key, r_max)
					]

		tt += "%s: %s%s\n" % [label, val_str, range_info]

	var affixes = m_data.get("affixes", {})
	if affixes.size() > 0:
		tt += div
		var zone_diff = int(m_data.get("zone_difficulty", 1))
		for aid in affixes:
			if aid in manager.AFFIX_DB:
				var cfg = manager.AFFIX_DB[aid]
				var val_raw = affixes[aid]
				var scaling = cfg.get("scaling", "percent")
				
				# v80.1 Fix: Use scaled ranges for display
				var s_range = manager.get_affix_scaled_range(aid, zone_diff)
				var val_str = ""
				var range_str = ""
				
				if scaling == "flat" or scaling == "linear_tier":
					val_str = str(int(val_raw))
					range_str = " [color=gray][font_size=9][%d-%d][/font_size][/color]" % [int(s_range[0]), int(s_range[1])]
				else:
					val_str = "%d%%" % int(val_raw * 100)
					range_str = " [color=gray][font_size=9][%d-%d]%%[/font_size][/color]" % [int(s_range[0] * 100), int(s_range[1] * 100)]
				
				var item_rarity_val = int(m_data.get("rarity", manager.Rarity.COMMON))
				var icon = ""
				
				var desc = cfg["desc"] % [int(val_raw) if (scaling == "flat" or scaling == "linear_tier") else int(val_raw * 100)]
				tt += "[color=#8fc5ff]%s %s[/color]%s\n" % [icon, desc, range_str]

	if m_data.has("sockets"):
		tt += div
		for gem in m_data["sockets"]:
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

	# v83.9: Set Bonus Tooltip Section
	var sid = m_data.get("set_id", "")
	if sid == "" and m_data.get("is_custom") and m_data.has("base_module"):
		var base_id = m_data["base_module"]
		sid = manager.modules.get(base_id, {}).get("set_id", "")
		
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

	tt += div
	tt += "[center][font_size=10][color=gray][Right-click to unequip][/color][/font_size][/center]"
	return tt
