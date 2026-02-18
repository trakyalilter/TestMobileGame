extends PanelContainer

@onready var title_lbl = $MarginContainer/VBoxContainer/Header/TitleLabel
@onready var type_lbl = $MarginContainer/VBoxContainer/Header/TypeLabel
@onready var desc_lbl = $MarginContainer/VBoxContainer/DescLabel
@onready var stats_container = $MarginContainer/VBoxContainer/StatsContainer
@onready var cost_lbl = $MarginContainer/VBoxContainer/CostLabel

func setup(id: String, type: String):
	
	# Force reset size
	custom_minimum_size = Vector2(220, 0)
	size = Vector2(220, 0)
	
	# Reset content
	for child in stats_container.get_children():
		child.queue_free()
	cost_lbl.text = ""
	
	match type:
		"item": _setup_item(id)
		"ship": _setup_ship(id)
		"module": _setup_module(id)
		"building": _setup_building(id)
		_:
			title_lbl.text = "Unknown Entity"
			desc_lbl.text = "No data found for %s" % id

func _setup_item(id: String):
	title_lbl.text = ElementDB.get_display_name(id)
	type_lbl.text = "RESOURCE"
	type_lbl.modulate = Color(0.7, 0.7, 0.7)
	
	# Try to find description or category
	var cat = ElementDB.get_category(id)
	desc_lbl.text = "Category: %s" % cat.capitalize()
	
	# Value
	var val = ElementDB.get_element_value(id)
	_add_stat("Base Value", "%d Cr" % val)

func _setup_ship(id: String):
	var sm = GameState.shipyard_manager
	if not id in sm.hulls: return
	
	var data = sm.hulls[id]
	title_lbl.text = data["name"]
	type_lbl.text = "SHIP HULL"
	type_lbl.modulate = Color(0.2, 0.6, 1.0)
	
	desc_lbl.text = "Class Tier: %d" % data.get("tier", 0)
	
	var stats = data["stats"]
	_add_stat("Hull Points", str(stats["hp"]))
	_add_stat("Base Attack", str(stats["atk"]))
	_add_stat("Capacity", str(stats["energy_capacity"]))
	_add_stat("Slots", str(data["slots"].size()))
	
	_set_cost(data["cost"])

func _setup_module(id: String):
	var sm = GameState.shipyard_manager
	if not id in sm.modules: return
	
	z_index = 100 # Ensure on top of Research Node
	
	var data = sm.modules[id]
	title_lbl.text = data["name"]
	title_lbl.modulate = Color.WHITE # Force strict white

	
	var s_type = data.get("slot_type", "module").to_upper()
	type_lbl.text = "SHIP MODULE (%s)" % s_type
	type_lbl.modulate = Color(1.0, 0.5, 0.2)
	
	desc_lbl.text = data.get("desc", "")
	desc_lbl.modulate = Color(0.8, 0.8, 0.8, 1) # Force strict grey

	
	var stats = data.get("stats", {})
	for k in stats:
		var key_name = k.capitalize().replace("_", " ")
		var val_str = str(stats[k])
		if "bonus" in k or "chance" in k:
			val_str = "+%.0f%%" % (stats[k] * 100.0)
		_add_stat(key_name, val_str)
		
	_set_cost(data["cost"])

func _setup_building(id: String):
	# Infrastructure data
	# We need access to InfrastructureManager's building_db.
	# Assuming GameState.infrastructure_manager is available or we load reference
	var im = GameState.infrastructure_manager
	if not im or not id in im.building_db: return
	
	var data = im.building_db[id]
	title_lbl.text = data["name"]
	type_lbl.text = "INFRASTRUCTURE"
	type_lbl.modulate = Color(0.4, 0.8, 0.4)
	
	desc_lbl.text = data["description"]
	
	if "energy_gen" in data and data["energy_gen"] > 0:
		_add_stat("Energy Gen", "+%.1f kW" % data["energy_gen"])
	if "energy_cons" in data and data["energy_cons"] > 0:
		_add_stat("Energy Use", "-%.1f kW" % data["energy_cons"])
		
	_set_cost(data["cost"])

func _add_stat(label: String, value: String):
	var box = HBoxContainer.new()
	var l = Label.new()
	l.text = label + ":"
	l.modulate = Color(0.6, 0.6, 0.6)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v = Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	
	box.add_child(l)
	box.add_child(v)
	stats_container.add_child(box)

func _set_cost(cost_data: Dictionary):
	var parts = []
	for res in cost_data:
		var qty = cost_data[res]
		var n = "Cr" if res == "credits" else res
		parts.append("%s %s" % [FormatUtils.format_number(qty), n])
	cost_lbl.text = "Cost: " + ", ".join(parts)
