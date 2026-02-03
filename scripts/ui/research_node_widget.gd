extends PanelContainer

var nid: String
var data: Dictionary
var manager: RefCounted
var parent_graph: Node

@onready var name_lbl = $MarginContainer/VBoxContainer/NameLabel
@onready var cost_lbl = $MarginContainer/VBoxContainer/CostLabel
@onready var desc_tip = $TooltipPanel
@onready var desc_lbl = $TooltipPanel/MarginContainer/Label

# Colors
const COL_LOCKED = Color(0.2, 0.2, 0.2)
const COL_AVAILABLE = Color(0.3, 0.3, 0.3)
const COL_UNLOCKED = Color(0.1, 0.4, 0.2)
const BORDER_LOCKED = Color(0.4, 0.4, 0.4)
const BORDER_AVAILABLE = Color(1.0, 0.8, 0.2)
const BORDER_UNLOCKED = Color(0.0, 0.8, 0.4)

func setup(p_nid: String, p_data: Dictionary, p_manager, p_parent):
	nid = p_nid
	data = p_data
	manager = p_manager
	parent_graph = p_parent
	
	name_lbl.text = data["name"]
	cost_lbl.text = "%d Cr" % data.get("cost", 0)
	desc_lbl.text = data["description"]
	
	desc_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$TooltipPanel/MarginContainer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	scale = Vector2(1,1) # Reset logic
	
	update_state()

func update_state():
	var is_repeatable = manager.repeatable_tech_db.has(nid)
	var is_unlocked = manager.is_tech_unlocked(nid) if not is_repeatable else false
	var can_unlock = manager.can_unlock(nid) if not is_repeatable else manager.can_unlock_repeatable(nid)
	
	if is_repeatable:
		var lvl = manager.get_repeatable_level(nid)
		name_lbl.text = manager.repeatable_tech_db[nid]["name"] + " (Lvl %d)" % lvl
		var costs = manager.get_repeatable_cost(nid)
		var cost_parts = []
		for res in costs:
			var req_qty = costs[res]
			var inv_qty = GameState.resources.get_currency("credits") if res == "credits" else GameState.resources.get_element_amount(res)
			var color = "lime" if inv_qty >= req_qty else "gray"
			var display_name = "Cr" if res == "credits" else ElementDB.get_display_name(res)
			cost_parts.append("[color=%s]%s %s[/color]" % [color, FormatUtils.format_number(req_qty), display_name])
		cost_lbl.text = "[center]" + "\n".join(cost_parts) + "[/center]"
	
	name_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["research"])
	var style = UITheme.apply_card_style(self, "research")
	
	if is_unlocked:
		style.bg_color = COL_UNLOCKED
		style.border_color = BORDER_UNLOCKED
		cost_lbl.text = "[center][color=LIME]RESEARCHED[/color][/center]"
	else:
		# Build cost string with met/unmet color coding
		var cost_parts = []
		var total_credits = GameState.resources.get_currency("credits")
		var credit_cost = data.get("cost", 0)
		
		# Credits check
		if credit_cost > 0:
			var color = "lime" if total_credits >= credit_cost else "gray"
			cost_parts.append("[color=%s]%s Cr[/color]" % [color, FormatUtils.format_number(credit_cost)])
		
		# Items check
		if "cost_items" in data:
			for item in data["cost_items"]:
				var req_qty = data["cost_items"][item]
				var inv_qty = GameState.resources.get_element_amount(item)
				var color = "lime" if inv_qty >= req_qty else "gray"
				var display_name = ElementDB.get_display_name(item)
				cost_parts.append("[color=%s]%s %s[/color]" % [color, FormatUtils.format_number(req_qty), display_name])
		
		cost_lbl.text = "[center]" + "\n".join(cost_parts) + "[/center]"
		
		if can_unlock:
			style.bg_color = COL_AVAILABLE
			style.border_color = BORDER_AVAILABLE
		else:
			style.bg_color = COL_LOCKED
			style.border_color = BORDER_LOCKED
		
	add_theme_stylebox_override("panel", style)

func _on_gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var is_repeatable = manager.repeatable_tech_db.has(nid)
		if is_repeatable:
			if manager.unlock_repeatable_tech(nid):
				update_state()
				# Local effect
				UITheme.trigger_circuit_surge(self, Color.LIME)
		elif not manager.is_tech_unlocked(nid):
			if manager.unlock_tech(nid):
				parent_graph.refresh_all()

func _on_mouse_entered():
	desc_tip.visible = true
	_update_tooltip_position()
	# move to front
	z_index = 10

func _update_tooltip_position():
	# Force the container to recalculate its size based on the new text
	desc_tip.reset_size()
	
	# Default offset
	desc_tip.position = Vector2(120, 0)
	
	# Use combined_minimum_size for the most accurate calculation before a frame pass
	var t_size = desc_tip.get_combined_minimum_size()
	var global_scale = get_global_transform().get_scale()
	var scaled_size = t_size * global_scale
	
	var global_pos = get_global_position() + desc_tip.position * global_scale
	var screen_size = get_viewport_rect().size
	
	# Adjust X: if it goes off right, flip to left side of node
	if global_pos.x + scaled_size.x > screen_size.x:
		desc_tip.position.x = - (t_size.x + 20)
		
	# Re-calculate global_pos.y after X potential shift (though Y check is independent)
	# Check Y: if it goes off bottom, shift it up
	if global_pos.y + scaled_size.y > screen_size.y:
		var overflow = (global_pos.y + scaled_size.y) - screen_size.y
		# Convert global overflow back to local coordinates
		desc_tip.position.y -= overflow / global_scale.y
		
	# FINAL SAFETY: Ensure it doesn't go off top of screen
	var final_global_y = get_global_position().y + desc_tip.position.y * global_scale.y
	if final_global_y < 0:
		desc_tip.position.y = -get_global_position().y / global_scale.y

func _on_mouse_exited():
	desc_tip.visible = false
	z_index = 0
