extends Control

@onready var level_label = $VBoxContainer/Header/LevelLabel
@onready var xp_label = $VBoxContainer/Header/XPLabel
@onready var xp_bar = $VBoxContainer/XPBar
@onready var rack_container = $VBoxContainer/ScrollContainer/RackContainer

var manager: RefCounted
var action_widget_scene = preload("res://scenes/ui/gathering_action_widget.tscn")
var widgets = []

var racks = {} # {category_name: GridContainer}

func _ready():
	manager = GameState.gathering_manager
	$VBoxContainer/ScrollContainer.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	call_deferred("refresh_actions")

func refresh_actions():
	# Clear previous racks
	for child in rack_container.get_children():
		child.queue_free()
	
	widgets.clear()
	racks.clear()

	_create_rack("terrestrial", "Terrestrial Operations", Color(0.4, 0.9, 0.6, 0.5), rack_container)
	_create_rack("orbital", "Orbital Harvesting", Color(0.4, 0.6, 1.0, 0.5), rack_container)
	_create_rack("void", "Void Transmutation", Color(0.8, 0.4, 1.0, 0.5), rack_container)

	var sorted_keys = manager.actions.keys()
	sorted_keys.sort_custom(func(a, b): return manager.actions[a]["level_req"] < manager.actions[b]["level_req"])
	
	for aid in sorted_keys:
		var data = manager.actions[aid]
		var cat = data.get("category", "terrestrial")
		
		if cat in racks:
			var w = action_widget_scene.instantiate()
			racks[cat].add_child(w)
			w.setup(aid, data, manager, self)
			widgets.append(w)

func _create_rack(id: String, title: String, color: Color, parent: Node):
	var rack_vbox = VBoxContainer.new()
	rack_vbox.name = id + "_rack"
	rack_vbox.add_theme_constant_override("separation", 10)
	parent.add_child(rack_vbox)
	
	var header = Label.new()
	header.text = "[ %s ]" % title.to_upper()
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", color)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rack_vbox.add_child(header)
	
	var rack_grid = GridContainer.new()
	rack_grid.columns = 4
	rack_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rack_grid.add_theme_constant_override("h_separation", 10)
	rack_grid.add_theme_constant_override("v_separation", 10)
	rack_vbox.add_child(rack_grid)
	
	var sep = HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.1)
	rack_vbox.add_child(sep)
	
	racks[id] = rack_grid


func get_widget_by_aid(target_aid: String) -> Control:
	for w in widgets:
		if w.aid == target_aid:
			return w
	return null

func get_coach_anchor(key: String) -> Control:
	match key:
		"first_action":
			return widgets[0] if not widgets.is_empty() else null
		"xp_bar":
			return xp_bar
	return null

func _process(delta):
	update_ui()

func update_ui():
	if not manager: return
	
	var lvl = manager.get_level()
	var xp = manager.xp
	
	level_label.text = "Level: %d" % lvl
	xp_label.text = "XP: %d" % int(xp)
	
	xp_bar.value = manager.get_progress_to_next_level()
	
	for w in widgets:
		w.update_state()
		
	# Cargo Manifest reward popups for gather yields + XP.
	while not manager.events.is_empty():
		var ev = manager.events.pop_front() # [type, data, target_id]
		var type = ev[0]
		var data = ev[1]
		var target_id = ev[2]

		# Only surface a popup when its source action is on this visible page.
		var target_w = null
		for w in widgets:
			if w.aid == target_id:
				target_w = w
				break
		if not target_w or not is_visible_in_tree():
			continue

		if type == "xp":
			UITheme.show_reward({
				"kind": "xp", "key": "xp:gather", "name": "Gathering XP",
				"amount": UITheme.parse_xp_amount(data),
				"total_text": "Lvl %d" % manager.get_level(),
				"accent": Color(1.0, 0.8, 0.15),
			})
		elif data is Dictionary:
			var symbol = data.get("symbol", "item")
			var amount = int(data.get("amount", 0))
			var total = GameState.resources.get_element_amount(symbol)
			UITheme.show_reward({
				"kind": "loot", "key": symbol, "symbol": symbol,
				"name": ElementDB.get_display_name(symbol),
				"amount": amount,
				"total_text": UITheme.format_number(total),
				"accent": UITheme.element_accent(symbol),
			})
