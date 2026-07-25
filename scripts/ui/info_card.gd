extends PanelContainer

@onready var title_lbl = $MarginContainer/VBoxContainer/Header/TitleLabel
@onready var type_lbl = $MarginContainer/VBoxContainer/Header/TypeLabel
@onready var desc_lbl = $MarginContainer/VBoxContainer/DescLabel
@onready var stats_container = $MarginContainer/VBoxContainer/StatsContainer
@onready var cost_lbl = $MarginContainer/VBoxContainer/CostLabel

var _host_slot_ctx: String = ""

func setup(id: String, type: String, host_slot: String = ""):
	_host_slot_ctx = host_slot
	
	# Force reset size
	custom_minimum_size = Vector2(220, 0)
	size = Vector2(220, 0)
	
	# Reset content
	for child in stats_container.get_children():
		child.queue_free()
	cost_lbl.text = ""
	# Hide any prior material icon (only _setup_item re-shows it).
	var _mi = $MarginContainer/VBoxContainer/Header.get_node_or_null("MatIcon")
	if _mi:
		_mi.visible = false
	
	match type:
		"item": _setup_item(id)
		"ship": _setup_ship(id)
		"module": _setup_module(id)
		"building": _setup_building(id)
		"gem": _setup_gem(id)
		_:
			title_lbl.text = tr("Unknown Entity")
			desc_lbl.text = tr("No data found for %s") % id

func _setup_item(id: String):
	title_lbl.text = ElementDB.get_display_name(id)
	type_lbl.text = tr("RESOURCE")
	type_lbl.modulate = Color(0.498, 0.639, 0.612)
	_set_item_icon(id)
	
	# Try to find description or category
	var cat = ElementDB.get_category(id)
	desc_lbl.text = tr("Category: %s") % cat.capitalize()
	
	# Special Stats for Ammo
	if cat == "ammo":
		# v144: percentage ladder, shared with combat (ElementDB.AMMO_TIER_MULT).
		var channel := ElementDB.get_ammo_channel(id)
		var type_label = tr("Damage")
		match channel:
			"kinetic": type_label = tr("Kinetic Damage")
			"energy": type_label = tr("Energy Damage")
			"explosive": type_label = tr("Explosive Damage")
		# v143: suppress at 0. T1 is the baseline (x1.00) so its pct is 0, and T1 is the
		# free, automated, most-equipped ammo — a bold "+0%" reads as a broken stat.
		var _apct: int = ElementDB.get_ammo_damage_pct(id)
		if channel != "" and _apct > 0:
			_add_stat(type_label, "+%d%%" % _apct)
			
	# Special Stats for Consumables
	if cat == "consumables":
		var c_data = ElementDB.get_consumable_data(id)
		if c_data:
			var heal_pct = c_data.get("heal_pct", 0.0) * 100.0
			var c_type = c_data.get("type", "hull").capitalize()
			_add_stat(tr("%s Restoration") % c_type, "+%d%%" % heal_pct)
	
	# Value
	var val = ElementDB.get_element_value(id)
	_add_stat(tr("Base Value"), tr("%d Liras") % val)

func _setup_ship(id: String):
	var sm = GameState.shipyard_manager
	if not id in sm.hulls: return
	
	var data = sm.hulls[id]
	title_lbl.text = tr(data["name"])
	type_lbl.text = tr("SHIP HULL")
	type_lbl.modulate = Color(0.439, 0.533, 0.949)
	
	desc_lbl.text = tr("Class Tier: %d") % data.get("tier", 0)
	
	var stats = data["stats"]
	_add_stat(tr("Hull Points"), str(stats["hp"]))
	_add_stat(tr("Capacity"), str(stats["energy_capacity"]))
	_add_stat(tr("Slots"), str(data["slots"].size()))
	
	_set_cost(data["cost"])

func _setup_module(id: String):
	var sm = GameState.shipyard_manager
	if not id in sm.modules: return
	
	z_index = 100 # Ensure on top of Research Node
	
	var data = sm.modules[id]
	title_lbl.text = tr(data["name"])
	title_lbl.modulate = Color.WHITE # Force strict white

	var stats = data.get("stats", {})

	
	var s_type = data.get("slot_type", "module").to_upper()
	type_lbl.text = tr("SHIP MODULE (%s)") % s_type
	type_lbl.modulate = Color(0.373, 0.878, 0.784)
	
	var final_desc = tr(str(data.get("desc", "")))
	
	# v87.0: Damage Type Strong/Weak Tooltips
	if stats.has("atk_kinetic") and stats["atk_kinetic"] > 0:
		final_desc += "\n" + tr("[KINETIC]")
		final_desc += "\n" + tr("  + Strong: Hull Damage (+20%)")
		final_desc += "\n" + tr("  - Weak: Shield Damage (-50%)")
	if stats.has("atk_energy") and stats["atk_energy"] > 0:
		final_desc += "\n" + tr("[ENERGY]")
		final_desc += "\n" + tr("  + Strong: Shield Damage (+50%)")
		final_desc += "\n" + tr("  + Strong: Armor Bypass (70% pen)")
		final_desc += "\n" + tr("  - Weak: Hull Damage (-10%)")
	if stats.has("atk_explosive") and stats["atk_explosive"] > 0:
		final_desc += "\n" + tr("[EXPLOSIVE]")
		final_desc += "\n" + tr("  + Strong: Armor Bypass (80% pen!)")
		final_desc += "\n" + tr("  - Weak: Slower fire rate")
		
	desc_lbl.text = final_desc
	desc_lbl.modulate = Color(0.78, 0.88, 0.85, 1) # soft light teal-white

	
	
	
	for k in stats:
		var key_name = k.capitalize().replace("_", " ")
		var val_str = str(stats[k])
		if "bonus" in k or "chance" in k:
			val_str = "+%.0f%%" % (stats[k] * 100.0)
		_add_stat(key_name, val_str)
	
	# v87.0: Condensed type hint (replaces old v83.1 duplicate)
	if stats.has("atk_kinetic") and stats["atk_kinetic"] > 0:
		_add_stat(tr("TYPE"), tr("KINETIC"), Color(0.439, 0.533, 0.949))
	if stats.has("atk_energy") and stats["atk_energy"] > 0:
		_add_stat(tr("TYPE"), tr("ENERGY"), Color(0.373, 0.878, 0.784))
	if stats.has("atk_explosive") and stats["atk_explosive"] > 0:
		_add_stat(tr("TYPE"), tr("EXPLOSIVE"), Color(1.0, 0.761, 0.302))
		
	var durability = int(data.get("durability", 100))
	_add_stat(tr("Durability"), tr("%d/100") % durability, Color(1.0, 0.392, 0.451) if durability <= 20 else Color(0.894, 0.961, 0.933))
		
	_set_cost(data["cost"])

func _setup_building(id: String):
	# Infrastructure data
	# We need access to InfrastructureManager's building_db.
	# Assuming GameState.infrastructure_manager is available or we load reference
	var im = GameState.infrastructure_manager
	if not im or not id in im.building_db: return
	
	var data = im.building_db[id]
	title_lbl.text = tr(data["name"])
	type_lbl.text = tr("INFRASTRUCTURE")
	type_lbl.modulate = Color(0.455, 0.831, 0.373)
	
	desc_lbl.text = data["description"]
	
	if "energy_gen" in data and data["energy_gen"] > 0:
		_add_stat(tr("Energy Gen"), tr("+%.1f kW") % data["energy_gen"])
	if "energy_cons" in data and data["energy_cons"] > 0:
		_add_stat(tr("Energy Use"), tr("-%.1f kW") % data["energy_cons"])
		
	_set_cost(data["cost"])

func _setup_gem(id: String):
	var sm = GameState.shipyard_manager
	title_lbl.text = ElementDB.get_display_name(id)
	type_lbl.text = tr("MATRIX CORE")

	if "Crimson" in id:
		type_lbl.modulate = Color(1.0, 0.392, 0.451)
	elif "Cobalt" in id:
		type_lbl.modulate = Color(0.224, 0.651, 0.878)
	elif "Topaz" in id:
		type_lbl.modulate = Color(0.843, 0.722, 0.259)
	elif "Amethyst" in id:
		type_lbl.modulate = Color(0.690, 0.420, 0.949)
	else:
		type_lbl.modulate = Color(0.498, 0.639, 0.612)

	# v137: socketed → the active facet below IS the info; swap the generic "socket into…"
	# flavour for the remove hint (the native socket tooltip that used to say this was removed).
	desc_lbl.text = tr("[Click to remove]") if _host_slot_ctx != "" else ElementDB.get_element_description(id)

	# Matrix-core facets. A core gives a DIFFERENT bonus per host-slot category
	# (weapon / defense / utility). v136: when the core is socketed in a KNOWN slot,
	# show ONLY that slot's bonus — the other-slot facets are noise once it's placed,
	# and showing all three read as "general info". The armory inspect (no host slot)
	# still lists all three so the player can compare placements before socketing.
	var facets = sm.GEM_FACETS.get(id, {})
	var cat_name = {"weapon": tr("Weapon"), "defense": tr("Armor/Shield"), "utility": tr("Engine/Sensor")}
	var active_cat = sm._gem_slot_category(_host_slot_ctx) if _host_slot_ctx != "" else ""
	if active_cat != "":
		type_lbl.text = tr("MATRIX CORE · %s SLOT") % tr(_host_slot_ctx.to_upper())
	for cat in ["weapon", "defense", "utility"]:
		if active_cat != "" and cat != active_cat:
			continue   # socketed in a slot: show ONLY that slot's bonus, not the others
		var facet = facets.get(cat, {})
		for k in facet:
			var pretty = String(k).replace("_mult", "").replace("_flat", "").replace("_eff", "_efficiency").replace("_", " ").capitalize()
			var val_str = ("+%d" % int(facet[k])) if String(k).ends_with("_flat") else ("+%d%%" % int(round(float(facet[k]) * 100.0)))
			var label = pretty if active_cat != "" else "[%s] %s" % [cat_name[cat], pretty]
			_add_stat(label, val_str, Color(0.275, 0.878, 0.627))

# Batch-0: a tinted material glyph beside the resource title (when an icon
# exists). Created lazily; hidden again by setup() for non-item entities.
func _set_item_icon(id: String):
	var header = $MarginContainer/VBoxContainer/Header
	var mi = header.get_node_or_null("MatIcon")
	var tex = ElementDB.get_material_icon(id)
	if not tex:
		if mi:
			mi.visible = false
		return
	if not mi:
		mi = TextureRect.new()
		mi.name = "MatIcon"
		mi.custom_minimum_size = Vector2(26, 26)
		mi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(mi)
		header.move_child(mi, 0)
	mi.texture = tex
	mi.modulate = ElementDB.get_material_tint(id)
	mi.visible = true

func _add_stat(label: String, value: String, val_color: Color = Color.WHITE):
	var box = HBoxContainer.new()
	var l = Label.new()
	l.text = label + ":"
	l.modulate = Color(0.498, 0.639, 0.612) # dim teal-grey for labels
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v = Label.new()
	v.text = value
	v.modulate = val_color # Dynamic color for the value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	
	box.add_child(l)
	box.add_child(v)
	stats_container.add_child(box)

func _set_cost(cost_data: Dictionary):
	var parts = []
	for res in cost_data:
		var qty = cost_data[res]
		var n = tr("Liras") if res == "credits" else res
		parts.append("%s %s" % [FormatUtils.format_number(qty), n])
	cost_lbl.text = tr("Cost: ") + ", ".join(parts)
