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
	desc_lbl.bbcode_enabled = true
	desc_lbl.text = _apply_smart_linking(data["description"])
	
	desc_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$TooltipPanel/MarginContainer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_PASS # Allow hover
	
	scale = Vector2(1,1) # Reset logic
	
	update_state()

# Smart Linker Logic
var _link_cache: Dictionary = {}

func _apply_smart_linking(text: String) -> String:
	# Avoid re-processing if not needed
	if text.contains("[url"): return text
	
	var processed = text
	
	# Collect all potential global terms
	var terms = []
	
	# 1. Elements/Items
	for symbol in ElementDB.ELEMENT_NAMES:
		var ename = ElementDB.ELEMENT_NAMES[symbol]
		terms.append({"name": ename, "id": symbol, "type": "item"})
			
	# 2. Ships
	if GameState.shipyard_manager:
		for hid in GameState.shipyard_manager.hulls:
			var hname = GameState.shipyard_manager.hulls[hid]["name"]
			terms.append({"name": hname, "id": hid, "type": "ship"})
				
		# 3. Modules
		for mid in GameState.shipyard_manager.modules:
			var mname = GameState.shipyard_manager.modules[mid]["name"]
			terms.append({"name": mname, "id": mid, "type": "module"})
	
	# 4. Buildings
	if GameState.infrastructure_manager:
		for bid in GameState.infrastructure_manager.building_db:
			var bname = GameState.infrastructure_manager.building_db[bid]["name"]
			terms.append({"name": bname, "id": bid, "type": "building"})

	# SORT BY LENGTH DESCENDING (Greedy Fix)
	# This ensures "Osmium Armor" is matched before "Osmium"
	terms.sort_custom(func(a, b): return a["name"].length() > b["name"].length())
	
	# Placeholder Strategy:
	# Replace terms with unique tokens first to prevent partial matches inside existing links
	# e.g. "Osmium Armor" -> "{{LINK_0}}" -> "Osmium" won't find it inside
	var replacements = {}
	var token_id = 0
	
	for t in terms:
		if t["name"] in processed:
			# Check if already linked checks for [url, which is too broad
			# We trust the placeholder system to handle overlaps by length
			# New check: Only link if NOT ALREADY LINKED
			if not _is_linked(processed, t["name"]):
				var token = "{{LINK_%d}}" % token_id
				var link_bbcode = _make_link(t["name"], t["id"], t["type"])
				
				# Perform replacement with token
				# We must ensure we don't partial match inside other tokens, but tokens are unique
				# String.replace is safe because tokens don't contain other terms
				if processed.contains(t["name"]):
					processed = processed.replace(t["name"], token)
					replacements[token] = link_bbcode
					token_id += 1
	
	# Final Pass: Restore BBCodes
	for token in replacements:
		processed = processed.replace(token, replacements[token])
				
	return processed

func _is_linked(text: String, phrase: String) -> bool:
	return ("[url" in text and phrase + "[/url]" in text)

func _make_link(display: String, id: String, type: String) -> String:
	# Store type/id in url for the callback
	var meta = {"id": id, "type": type}
	var json = JSON.stringify(meta)
	return "[url=%s][color=#44aaff]%s[/color][/url]" % [json, display]

func _ready():
	desc_lbl.meta_hover_started.connect(_on_meta_hover)
	desc_lbl.meta_hover_ended.connect(_on_meta_exit)

var _active_info_card = null
var info_card_scene = preload("res://scenes/ui/info_card.tscn")

func _on_meta_hover(meta):
	if _active_info_card: _active_info_card.queue_free()
	
	var data = JSON.parse_string(str(meta))
	if not data: return
	
	var card = info_card_scene.instantiate()
	
	# Add to ModalLayer to avoid container stretching and ensure z-index
	var main = self.get_tree().current_scene
	var modal_layer = main.get_node_or_null("ModalLayer")
	if modal_layer:
		modal_layer.add_child(card)
	else:
		# Fallback
		main.add_child(card)
	
	# Call setup AFTER adding to tree so @onready vars work
	card.setup(data["id"], data["type"])
	_active_info_card = card
	
	# Position near mouse
	var mpos = get_global_mouse_position()
	card.global_position = mpos + Vector2(20, 20)
	
	# Keep on screen
	var viewport = get_viewport_rect().size
	var card_size = Vector2(220, 100) # Fallback size if not ready
	if card.size.x > 0: card_size = card.size
	
	if card.global_position.x + card_size.x > viewport.x:
		card.global_position.x = mpos.x - card_size.x - 20
	if card.global_position.y + card_size.y > viewport.y:
		card.global_position.y = mpos.y - card_size.y - 20

func _on_meta_exit(meta):
	if _active_info_card:
		_active_info_card.queue_free()
		_active_info_card = null

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
		var raw_credit_cost = data.get("cost", 0)
		# v61.0 Fix: Apply COST_MULTIPLIER to match research_manager.gd
		var credit_cost = int(raw_credit_cost * manager.COST_MULTIPLIER)
		
		# Credits check
		if credit_cost > 0:
			var color = "lime" if total_credits >= credit_cost else "gray"
			cost_parts.append("[color=%s]%s Cr[/color]" % [color, FormatUtils.format_number(credit_cost)])
		
		# Items check - apply MATERIAL_MULTIPLIER
		if "cost_items" in data:
			for item in data["cost_items"]:
				var raw_qty = data["cost_items"][item]
				# v61.0 Fix: Apply MATERIAL_MULTIPLIER to match research_manager.gd
				var req_qty = int(raw_qty * manager.MATERIAL_MULTIPLIER)
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

var _pressed_pos: Vector2 = Vector2.ZERO
var _is_pressed: bool = false
const DRAG_THRESHOLD = 5.0

func _on_gui_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_pressed = true
			_pressed_pos = event.global_position
		else:
			# Release
			if _is_pressed:
				var dist = event.global_position.distance_to(_pressed_pos)
				_is_pressed = false
				
				# Only trigger if NOT a drag
				if dist < DRAG_THRESHOLD:
					_handle_unlock()

func _handle_unlock():
	var is_repeatable = manager.repeatable_tech_db.has(nid)
	if is_repeatable:
		if manager.unlock_repeatable_tech(nid):
			update_state()
			parent_graph.refresh_all() # Fix Medium: Refresh others on repeatable
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
	# Note: desc_tip size might change if rich text wraps
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
