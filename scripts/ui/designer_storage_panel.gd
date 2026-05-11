extends GridContainer

# Handle drops for unequipping (dragging from ship slots back to storage)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY: return false
	var type = data.get("type", "")
	return type == "unequip_module" or type == "unequip_ammo" or type == "unequip_consumable"

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var type = data.get("type", "")
	var shipyard_manager = GameState.shipyard_manager
	var designer_page = get_viewport().get_node("Main/Content/PageContainer/DesignerPage") # Usual path
	
	if type == "unequip_module":
		var slot_idx = data.get("slot_idx", -1)
		if slot_idx != -1:
			shipyard_manager.unequip_slot(slot_idx)
			_refresh_designer()
			
	elif type == "unequip_ammo":
		var slot_idx = data.get("slot_idx", -1)
		if slot_idx != -1:
			shipyard_manager.set_slot_ammo(slot_idx, "")
			_refresh_designer()
	
	elif type == "unequip_consumable":
		var s_type = data.get("slot_type", "")
		if s_type != "":
			shipyard_manager.unequip_consumable(s_type)
			_refresh_designer()

func _refresh_designer():
	# Find designer page to trigger refresh
	# Try walking up first
	var p = get_parent()
	while p and not p.name == "DesignerPage":
		p = p.get_parent()
	
	if p:
		p.trigger_refresh()
	else:
		# Fallback to signal if needed, but designer triggers its own refresh usually
		pass
