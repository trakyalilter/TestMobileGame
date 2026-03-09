extends Control

var panel: PanelContainer
var rarity_column: VBoxContainer
var type_column: VBoxContainer
var btn_close: Button

func _ready():
	# Build layout from code
	custom_minimum_size = Vector2(550, 400)
	anchors_preset = Control.PRESET_CENTER
	
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(550, 400)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(panel)
	
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	var title = Label.new()
	title.text = "LOOT FILTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)
	
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 20)
	scroll.add_child(hbox)
	
	rarity_column = VBoxContainer.new()
	rarity_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(rarity_column)
	
	var v_sep = VSeparator.new()
	hbox.add_child(v_sep)
	
	type_column = VBoxContainer.new()
	type_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(type_column)
	
	btn_close = Button.new()
	btn_close.text = "CLOSE"
	btn_close.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(btn_close)
	
	UITheme.apply_modal_style(panel)
	UITheme.apply_premium_button_style(btn_close, "combat")
	btn_close.pressed.connect(close)
	
	_build_filter_sections()

func _build_filter_sections():
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	if not sm or not cm: return
	
	# --- SECTION: RARITY ---
	_add_section_header("RARITY FILTER", rarity_column)
	for rarity_val in sm.Rarity.values():
		var rarity_name = sm.RARITY_LABELS.get(rarity_val, "Common")
		if rarity_name == "": rarity_name = "Common"
		
		var cb = CheckBox.new()
		cb.text = rarity_name
		cb.button_pressed = cm.loot_filter.get(rarity_val, true)
		cb.add_theme_color_override("font_color", sm.RARITY_COLORS.get(rarity_val, Color.WHITE))
		cb.toggled.connect(_on_rarity_toggled.bind(rarity_val))
		rarity_column.add_child(cb)

	# --- SECTION: TYPE ---
	_add_section_header("TYPE FILTER", type_column)
	var types = ["weapon", "armor", "shield", "engine", "battery", "sensor"]
	for t in types:
		var cb = CheckBox.new()
		cb.text = t.capitalize()
		cb.button_pressed = cm.loot_type_filter.get(t, true)
		cb.toggled.connect(_on_type_toggled.bind(t))
		type_column.add_child(cb)

func _add_section_header(text: String, container: Control):
	var l = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	l.add_theme_font_size_override("font_size", 12)
	container.add_child(l)

func _on_rarity_toggled(is_pressed: bool, rarity_val: int):
	GameState.combat_manager.loot_filter[rarity_val] = is_pressed
	UITheme.show_notification("Rarity: " + GameState.shipyard_manager.RARITY_LABELS.get(rarity_val, "Common") + (" ON" if is_pressed else " OFF"), Color.AQUA)

func _on_type_toggled(is_pressed: bool, type_name: String):
	GameState.combat_manager.loot_type_filter[type_name] = is_pressed
	UITheme.show_notification("Type: " + type_name.capitalize() + (" ON" if is_pressed else " OFF"), Color.AQUA)

func close():
	queue_free()
