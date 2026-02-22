extends PanelContainer

var slot_idx: int
var slot_type: String
var parent_ui: Node
var manager: RefCounted
var is_occupied: bool = false

@onready var type_lbl = $MarginContainer/VBoxContainer/TypeLabel
@onready var name_lbl = $MarginContainer/VBoxContainer/NameLabel
@onready var icon_lbl = $MarginContainer/VBoxContainer/IconLabel
@onready var option_btn = $MarginContainer/VBoxContainer/OptionButton

func setup(idx: int, s_type: String, p_ui, p_manager):
	slot_idx = idx
	slot_type = s_type
	parent_ui = p_ui
	manager = p_manager
	
	if is_node_ready():
		refresh_state()

func _ready():
	UITheme.apply_card_style(self, "shipyard")
	# We'll hide the option button in setup to favor Drag & Drop
	option_btn.visible = false
	refresh_state()

func refresh_state():
	if not is_node_ready(): return
	if not manager: manager = GameState.shipyard_manager
	if not manager: return
	
	# Reset style to base shipyard theme during refresh
	UITheme.apply_card_style(self, "shipyard")

	# CONSUMABLE LOGIC
	if slot_type.begins_with("consumable_"):
		_refresh_consumable_state()
		return

	type_lbl.text = "SLOT %d: %s" % [slot_idx + 1, slot_type.to_upper()]
	type_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["shipyard"])
	
	option_btn.clear()
	option_btn.add_item("Change...", 0)
	option_btn.set_item_metadata(0, null)
	
	var equipped_id = manager.loadout.get(slot_idx)
	is_occupied = equipped_id != null
	
	# Current Item Display
	if equipped_id:
		var m_data = manager.modules.get(equipped_id)
		if not m_data:
			# Safety: Module ID exists in loadout but not in database (removed/deprecated)
			name_lbl.text = "INVALID ID"
			icon_lbl.text = "?"
			tooltip_text = "Module data not found for ID: %s" % equipped_id
			option_btn.add_item("Unequip (Invalid)", 1)
			option_btn.set_item_metadata(1, "unequip")
			return

		var en_load = m_data["stats"].get("energy_load", 0)
		if en_load > 0:
			name_lbl.text = "%s (-%d En)" % [m_data["name"], en_load]
		else:
			name_lbl.text = m_data["name"]
		
		# v71.0: Use rarity color for equipped modules
		var rarity = manager.get_module_rarity(equipped_id)
		var rarity_color = manager.RARITY_COLORS.get(rarity, Color(0, 0.73, 0.83))
		name_lbl.modulate = rarity_color
		icon_lbl.text = "▣"
		icon_lbl.modulate = rarity_color
		
		# v71.2: Left accent bar for rarity on equipped slots
		if rarity >= manager.Rarity.UNCOMMON:
			var slot_style = StyleBoxFlat.new()
			slot_style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
			slot_style.border_width_left = 8
			slot_style.border_width_top = 4
			slot_style.border_width_right = 1
			slot_style.border_width_bottom = 1
			slot_style.border_color = rarity_color
			slot_style.set_corner_radius_all(4)
			slot_style.set_content_margin_all(6)
			add_theme_stylebox_override("panel", slot_style)
		
		# Build tooltip with module stats
		tooltip_text = _build_module_tooltip(m_data)
		
		# Option to Unequip
		option_btn.add_item("Unequip", 1)
		option_btn.set_item_metadata(1, "unequip")
	else:
		name_lbl.text = "EMPTY"
		name_lbl.modulate = Color(0.33, 0.33, 0.33) # Dark Gray
		icon_lbl.text = "⛝"
		icon_lbl.modulate = Color(0.33, 0.33, 0.33)
		tooltip_text = "Empty %s Slot\nDrag a module here to equip" % slot_type.capitalize()

	# Populate Inventory Options
	var inv = manager.module_inventory
	var idx_counter = 2
	for mid in inv:
		var count = inv[mid]
		if count > 0 and mid in manager.modules:
			var m_data = manager.modules[mid]
			if m_data["slot_type"] == slot_type:
				var item_idx = option_btn.item_count
				var m_rarity = manager.get_module_rarity(mid)
				var r_label = manager.RARITY_LABELS.get(m_rarity, "COMMON").to_upper()
				
				# v71.5: Identify locked modules with a lock prefix
				var status = manager.can_equip_module(mid)
				var lock_icon = "🔒 " if not status["can_equip"] else ""
				
				# v71.3: Use rarity prefix instead of color function to avoid crashes
				var display_name = "%s[%s] %s (x%d)" % [lock_icon, r_label, m_data["name"], count]
				if m_rarity == manager.Rarity.COMMON:
					display_name = "%s%s (x%d)" % [lock_icon, m_data["name"], count]
					
				option_btn.add_item(display_name, idx_counter)
				option_btn.set_item_metadata(item_idx, mid)
				idx_counter += 1

func _refresh_consumable_state():
	UITheme.apply_card_style(self, "shipyard")
	var c_type = "hull" if slot_type == "consumable_hull" else "shield"
	var label_txt = "HULL REPAIR" if c_type == "hull" else "SHIELD REPAIR"
	
	type_lbl.text = label_txt
	type_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["shipyard"])
	
	option_btn.clear()
	option_btn.add_item("Change...", 0)
	
	var equipped_id = manager.get_consumable(c_type)
	if equipped_id != "":
		var data = ElementDB.get_consumable_data(equipped_id)
		var dname = data.get("name", equipped_id)
		var qty = GameState.resources.get_element_amount(equipped_id)
		
		name_lbl.text = "%s (x%d)" % [dname, qty]
		name_lbl.modulate = Color(0, 0.73, 0.83) # Cyan
		icon_lbl.text = "💊"
		icon_lbl.modulate = Color(0, 0.73, 0.83)
		
		tooltip_text = "%s\nRestores %d%% %s" % [dname, int(data.get("heal_pct", 0) * 100), c_type.capitalize()]
		
		option_btn.add_item("Unequip", 1)
		option_btn.set_item_metadata(1, "unequip")
	else:
		name_lbl.text = "EMPTY SLOT"
		name_lbl.modulate = Color(0.33, 0.33, 0.33)
		icon_lbl.text = "⛝"
		icon_lbl.modulate = Color(0.33, 0.33, 0.33)
		tooltip_text = "Drag a Consumable here"

	# Inventory Options
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
	
	var data = manager.modules.get(equipped_id)
	
	var drag_data = {
		"type": "unequip_module",
		"slot_idx": slot_idx,
		"mid": equipped_id,
		"slot_type": slot_type
	}
	
	# Visual Preview: Use a real slot instance
	var preview = load("res://scenes/ui/designer_slot_widget.tscn").instantiate()
	preview.setup(slot_idx, slot_type, parent_ui, manager)
	
	var preview_container = Control.new()
	preview_container.add_child(preview)
	
	preview.scale = Vector2(1.05, 1.05)
	preview.modulate = Color(1.0, 0.7, 0.7, 0.95) # Reddish tint but mostly solid
	
	var shadow = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 15
	style.shadow_offset = Vector2(0, 10)
	shadow.add_theme_stylebox_override("panel", style)
	shadow.custom_minimum_size = Vector2(120, 120)
	
	preview_container.add_child(shadow)
	preview_container.move_child(shadow, 0)
	
	preview.position = Vector2(-60, -60)
	shadow.position = Vector2(-55, -55)
	
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
		return data.get("slot_type") == slot_type
	return false

func _drop_data(at_position, data):
	if slot_type.begins_with("consumable_"):
		var c_type = "hull" if slot_type == "consumable_hull" else "shield"
		var item_id = data.get("mid", "") # Consumable ID from card
		
		# If coming from another slot (unequip_consumable?) - usually we drag FROM inventory
		if data.get("type") == "consumable":
			# From inventory card
			manager.equip_consumable(c_type, item_id)
			UITheme.trigger_circuit_surge(self)
			parent_ui.trigger_refresh()
		return

	var mid = data.get("mid")
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
	elif data:
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
			# Smart Filter mapping
			if parent_ui and parent_ui.has_method("_on_filter_changed"):
				var target_filter = "all"
				if slot_type == "weapon": target_filter = "wpn"
				elif slot_type in ["engine", "reactor", "battery", "shield"]: target_filter = "sys"
				elif slot_type == "armor": target_filter = "armor"
				elif slot_type.begins_with("consumable_"): target_filter = "ord"
				
				parent_ui._on_filter_changed(target_filter)
				
				# Tactile feedback
				UITheme.trigger_ui_thud(self, 1.0)

# ─────────────────────────────────────────────────
# MODULE TOOLTIP (PHASE 22)
# ─────────────────────────────────────────────────

func _build_module_tooltip(m_data: Dictionary) -> String:
	var tt = m_data["name"] + "\n"
	tt += "─────────────────\n"
	
	var stats = m_data.get("stats", {})
	for k in stats:
		var label = FormatUtils.format_stat_label(k)
		var val = stats[k]
		tt += "%s: %s\n" % [label, FormatUtils.format_stat_value(k, val)]
	
	# Add DPS if it's a weapon
	if m_data.get("slot_type") == "weapon":
		var dmg = stats.get("atk_kinetic", 0) + stats.get("atk_energy", 0) + stats.get("atk_explosive", 0)
		var interval = stats.get("atk_interval", 2.5)
		if interval > 0:
			var dps = float(dmg) / interval
			tt += "─────────────────\n"
			tt += "DPS: %.1f\n" % dps
	
	if m_data.has("desc"):
		tt += "─────────────────\n"
		tt += m_data["desc"]
	
	tt += "\n[Right-click to unequip]"
	return tt
