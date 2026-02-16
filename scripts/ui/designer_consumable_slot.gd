extends PanelContainer

signal equip_requested(slot_type, item_id)
signal unequip_requested(slot_type)

@onready var icon = $Margin/HBox/Icon
@onready var name_lbl = $Margin/HBox/VBox/NameLabel
@onready var type_lbl = $Margin/HBox/VBox/TypeLabel
@onready var eject_btn = $Margin/HBox/EjectBtn
@onready var select_btn = $SelectBtn 

var slot_type: String = "" # "hull" or "shield"
var current_item: String = ""
var manager: RefCounted
var parent_page: Control

func setup(_type: String, _page: Control, _manager: RefCounted):
	slot_type = _type
	parent_page = _page
	manager = _manager
	
	type_lbl.text = "HULL REPAIR" if slot_type == "hull" else "SHIELD REPAIR"
	
	refresh()

func refresh():
	current_item = manager.get_consumable(slot_type)
	
	if current_item != "":
		var data = ElementDB.get_consumable_data(current_item)
		var dname = data.get("name", current_item)
		var qty = GameState.resources.get_element_amount(current_item)
		
		name_lbl.text = "%s (x%d)" % [dname, qty]
		name_lbl.modulate = Color(1, 1, 1, 1)
		eject_btn.visible = true
		icon.modulate = Color(1, 1, 1, 1)
	else:
		name_lbl.text = "EMPTY SLOT"
		name_lbl.modulate = Color(1, 1, 1, 0.5)
		eject_btn.visible = false
		icon.modulate = Color(1, 1, 1, 0.2)

func _on_select_btn_pressed():
	# Show popup of available consumables
	var popup = PopupMenu.new()
	popup.position = get_screen_position() + Vector2(0, size.y)
	
	popup.add_item("None (Unequip)", 0)
	popup.set_item_metadata(0, "")
	
	var items = ElementDB.get_elements_in_category("consumables")
	var idx = 1
	for id in items:
		var data = ElementDB.get_consumable_data(id)
		if data.get("type") == slot_type:
			var qty = GameState.resources.get_element_amount(id)
			if qty > 0 or id == current_item:
				popup.add_item("%s (x%d)" % [data.get("name", id), qty], idx)
				popup.set_item_metadata(idx, id)
				idx += 1
				
	add_child(popup)
	popup.popup()
	popup.index_pressed.connect(_on_popup_selected.bind(popup))

func _on_popup_selected(index: int, popup: PopupMenu):
	var id = popup.get_item_metadata(index)
	if id == "":
		manager.unequip_consumable(slot_type)
	else:
		manager.equip_consumable(slot_type, id)
	
	popup.queue_free()
	parent_page.trigger_refresh() # Refresh full page to update slots

func _on_eject_btn_pressed():
	manager.unequip_consumable(slot_type)
	parent_page.trigger_refresh()

# ─────────────────────────────────────────────────
# DRAG & DROP
# ─────────────────────────────────────────────────

func _can_drop_data(_at_position, data):
	if typeof(data) != TYPE_DICTIONARY: return false
	if data.get("type") != "consumable": return false
	
	var incoming_type = data.get("consumable_type", "")
	# Only accept if the consumable's sub-type matches this slot
	return incoming_type == slot_type

func _drop_data(_at_position, data):
	var item_id = data.get("mid", "")
	if item_id != "":
		manager.equip_consumable(slot_type, item_id)
		UITheme.trigger_circuit_surge(self)
		parent_page.trigger_refresh()

func _get_drag_data(_at_position):
	if current_item == "": return null
	
	var drag_data = {
		"type": "unequip_consumable",
		"slot_type": slot_type,
		"mid": current_item,
	}
	
	# Visual preview
	var preview = Label.new()
	var c_data = ElementDB.get_consumable_data(current_item)
	preview.text = c_data.get("name", current_item)
	preview.modulate = Color(1, 0.5, 0.5, 0.8)
	set_drag_preview(preview)
	return drag_data

func _gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if current_item != "":
				manager.unequip_consumable(slot_type)
				parent_page.trigger_refresh()
