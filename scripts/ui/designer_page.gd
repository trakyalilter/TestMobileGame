extends Control

@onready var title_lbl: Label = $VBoxContainer/Label

@onready var info_panel: PanelContainer = $VBoxContainer/InfoPanel
@onready var schematic_area: PanelContainer = $VBoxContainer/MainLayout/SchematicArea
@onready var right_panel: PanelContainer = $VBoxContainer/MainLayout/RightPanel
@onready var bay_lbl: Label = $VBoxContainer/MainLayout/RightPanel/Margin/VBox/Label

@onready var ship_name_lbl: Label = $VBoxContainer/InfoPanel/MarginContainer/InfoHBox/ShipSpecs/ShipNameLabel
@onready var power_bar: ProgressBar = $VBoxContainer/InfoPanel/MarginContainer/InfoHBox/ShipSpecs/SystemLoad/PowerBar
@onready var power_lbl: Label = $VBoxContainer/InfoPanel/MarginContainer/InfoHBox/ShipSpecs/SystemLoad/PowerLabel
@onready var stats_grid: GridContainer = $VBoxContainer/InfoPanel/MarginContainer/InfoHBox/StatsGrid
@onready var btn_repair_mode: Button = $VBoxContainer/InfoPanel/MarginContainer/InfoHBox/BtnRepairMode

@onready var storage_grid: GridContainer = $VBoxContainer/MainLayout/RightPanel/Margin/VBox/Scroll/UnifiedStorageGrid
@onready var tab_frame: PanelContainer = $VBoxContainer/MainLayout/RightPanel/Margin/VBox/TabStripFrame
@onready var tab_strip: HFlowContainer = $VBoxContainer/MainLayout/RightPanel/Margin/VBox/TabStripFrame/TabMargin/TabStrip

var manager: RefCounted
var active_filter := "all"
var is_repair_mode := false
var tab_buttons: Dictionary = {}
var slot_widget_scene = preload("res://scenes/ui/designer_slot_widget.tscn")
var ammo_slot_scene = preload("res://scenes/ui/designer_ammo_slot_widget.tscn")
var draggable_icon_scene = preload("res://scenes/ui/module_card.tscn")
var empty_slot_scene = preload("res://scenes/ui/empty_slot.tscn")

# v87.1: Multi-select demolish
var is_select_mode := false
var selected_modules: Dictionary = {} # {module_id: true}
var _select_btn: Button = null
var _action_bar: HBoxContainer = null
var _demolish_btn: Button = null
var _select_all_btn: Button = null
var _deselect_all_btn: Button = null

const FRAME_BG := Color(0.09, 0.07, 0.06, 0.96)
const FRAME_EDGE := Color(0.42, 0.30, 0.21, 0.95)
const TITLE_GOLD := Color(0.84, 0.70, 0.45)
const TEXT_MAIN := Color(0.90, 0.86, 0.78)
const TEXT_DIM := Color(0.62, 0.57, 0.50)
const TAB_BASE := Color(0.16, 0.11, 0.08)
const TAB_EDGE := Color(0.44, 0.31, 0.21)

const FILTER_ORDER := ["all", "weapon", "shield", "armor", "engine", "battery", "utility", "ordnance", "matrix"]
const FILTER_LABELS := {
	"all": "ALL",
	"weapon": "WPN",
	"shield": "SHD",
	"armor": "ARM",
	"engine": "ENG",
	"battery": "BAT",
	"utility": "UTL",
	"ordnance": "ORD",
	"matrix": "CORE",
}
const FILTER_TOOLTIPS := {
	"all": "Show all modules, ammo, and consumables.",
	"weapon": "Weapon modules.",
	"shield": "Shield modules.",
	"armor": "Armor modules.",
	"engine": "Engine modules.",
	"battery": "Battery modules.",
	"utility": "Sensors, reactors, cooling, and other utility modules.",
	"ordnance": "Ammo and consumables.",
	"matrix": "Matrix Cores for sockets.",
}
const ORDNANCE_AMMO_IDS := [
	"SlugT1",
	"SlugT1S",
	"SlugT2",
	"SlugT3",
	"SlugT4",
	"CellT1",
	"CellT2",
	"CellT3",
	"CellT4",
	"Photon_Torpedo"
]
const FILTER_CONFIG := {
	"all": {"node": "AllTab", "accent": Color(0.80, 0.73, 0.62)},
	"weapon": {"node": "WeaponTab", "accent": Color(0.92, 0.50, 0.35)},
	"shield": {"node": "ShieldTab", "accent": Color(0.56, 0.76, 0.96)},
	"armor": {"node": "ArmorTab", "accent": Color(0.78, 0.71, 0.62)},
	"engine": {"node": "EngineTab", "accent": Color(0.85, 0.79, 0.50)},
	"battery": {"node": "BatteryTab", "accent": Color(0.80, 0.86, 0.56)},
	"utility": {"node": "UtilityTab", "accent": Color(0.73, 0.67, 0.88)},
	"ordnance": {"node": "OrdnanceTab", "accent": Color(0.93, 0.64, 0.42)},
	"matrix": {"node": "MatrixTab", "accent": Color(0.85, 0.45, 0.85)},
}

func _ready():
	manager = GameState.shipyard_manager
	visibility_changed.connect(_on_visibility_changed)
	GameState.game_loaded.connect(trigger_refresh)
	
	if btn_repair_mode:
		btn_repair_mode.toggled.connect(func(toggled_on):
			is_repair_mode = toggled_on
			if is_repair_mode:
				Input.set_default_cursor_shape(Input.CURSOR_CROSS)
			else:
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		)
	if GameState.warp_manager:
		GameState.warp_manager.warped.connect(_on_warp_refresh)
	manager.inventory_updated.connect(_on_inventory_updated)

	_apply_designer_styles()
	_setup_filter_tabs()

	trigger_refresh()

func _apply_designer_styles():
	title_lbl.add_theme_color_override("font_color", TITLE_GOLD)
	title_lbl.add_theme_font_size_override("font_size", 24)

	ship_name_lbl.add_theme_color_override("font_color", TITLE_GOLD)
	ship_name_lbl.add_theme_font_size_override("font_size", 22)
	power_lbl.add_theme_color_override("font_color", TEXT_MAIN)

	bay_lbl.add_theme_color_override("font_color", TITLE_GOLD)
	bay_lbl.add_theme_font_size_override("font_size", 15)

	_apply_frame_style(info_panel, FRAME_BG, FRAME_EDGE)
	_apply_frame_style(schematic_area, Color(0.08, 0.06, 0.05, 0.96), Color(0.37, 0.27, 0.19, 0.92))
	_apply_frame_style(right_panel, Color(0.08, 0.06, 0.05, 0.96), Color(0.47, 0.32, 0.19, 0.92))
	_apply_tab_frame_style()
	_apply_power_bar_style()
	_refresh_filter_button_styles()
	
	# v84.0: Increased columns for compact tiles
	storage_grid.columns = 6
	storage_grid.add_theme_constant_override("h_separation", 6)
	storage_grid.add_theme_constant_override("v_separation", 6)


func _setup_filter_tabs():
	tab_buttons.clear()
	for filter_id in FILTER_ORDER:
		var node_name = FILTER_CONFIG[filter_id]["node"]
		var button = tab_strip.get_node_or_null(node_name)
		if button and button is Button:
			tab_buttons[filter_id] = button
			(button as Button).pressed.connect(_on_filter_pressed.bind(filter_id))
			(button as Button).tooltip_text = FILTER_TOOLTIPS.get(filter_id, "")
		elif filter_id == "matrix" and tab_strip.get_child_count() > 0:
			# v83.9: Dynamically create Matrix tab if missing from scene
			var first_btn = tab_strip.get_child(0)
			var new_btn = first_btn.duplicate()
			new_btn.name = "MatrixTab"
			tab_strip.add_child(new_btn)
			tab_buttons[filter_id] = new_btn
			new_btn.pressed.connect(_on_filter_pressed.bind(filter_id))
			new_btn.tooltip_text = FILTER_TOOLTIPS.get(filter_id, "")
	
	# v87.1: Add SELECT toggle button
	if tab_strip.get_child_count() > 0:
		var first_btn = tab_strip.get_child(0)
		_select_btn = first_btn.duplicate()
		_select_btn.name = "SelectModeBtn"
		_select_btn.text = "SELECT"
		_select_btn.tooltip_text = "Toggle selection mode to demolish multiple modules at once."
		tab_strip.add_child(_select_btn)
		_select_btn.pressed.connect(_on_select_mode_pressed)
		_apply_select_button_style()
	
	# v87.1: Create action bar (hidden by default)
	_create_action_bar()
	
	_refresh_tab_labels()

func _on_filter_pressed(filter_id: String):
	_on_filter_changed(filter_id)

func _apply_frame_style(panel: PanelContainer, bg: Color, border: Color):
	var style = StyleBoxFlat.new()
	style.bg_color = bg
	style.set_border_width_all(2)
	style.border_width_top = 4
	style.border_color = border
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0, 0, 0, 0.30)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", style)

func _apply_tab_frame_style():
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.05, 0.04, 0.94)
	style.set_border_width_all(1)
	style.border_color = Color(0.35, 0.24, 0.17, 0.85)
	style.set_corner_radius_all(3)
	style.content_margin_left = 2
	style.content_margin_top = 2
	style.content_margin_right = 2
	style.content_margin_bottom = 2
	tab_frame.add_theme_stylebox_override("panel", style)

func _apply_power_bar_style():
	var track = StyleBoxFlat.new()
	track.bg_color = Color(0.07, 0.05, 0.04, 0.95)
	track.set_border_width_all(1)
	track.border_color = Color(0.35, 0.24, 0.16, 0.85)
	track.set_corner_radius_all(2)

	var fill = StyleBoxFlat.new()
	fill.bg_color = Color(0.79, 0.62, 0.27, 0.95)
	fill.set_corner_radius_all(2)

	power_bar.add_theme_stylebox_override("background", track)
	power_bar.add_theme_stylebox_override("fill", fill)

func _refresh_filter_button_styles():
	var visual_filter = active_filter
	if visual_filter == "systems":
		visual_filter = "utility"
	elif visual_filter == "explosive":
		visual_filter = "weapon"

	for filter_id in FILTER_ORDER:
		if not tab_buttons.has(filter_id):
			continue
		var button: Button = tab_buttons[filter_id]
		var accent: Color = FILTER_CONFIG[filter_id]["accent"]
		_apply_filter_button_style(button, visual_filter == filter_id, accent)

func _apply_filter_button_style(button: Button, is_active: bool, accent: Color):
	var normal = StyleBoxFlat.new()
	normal.bg_color = TAB_BASE
	normal.set_border_width_all(1)
	normal.border_color = TAB_EDGE
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6

	var hover = normal.duplicate()
	hover.bg_color = TAB_BASE.lerp(accent, 0.24)
	hover.border_color = accent.lerp(Color.WHITE, 0.15)

	var pressed = normal.duplicate()
	pressed.bg_color = TAB_BASE.lerp(accent, 0.44)
	pressed.border_color = accent.lerp(Color.WHITE, 0.28)
	pressed.border_width_top = 3

	var disabled = normal.duplicate()
	disabled.bg_color = Color(0.10, 0.08, 0.07, 0.70)
	disabled.border_color = Color(0.25, 0.20, 0.18, 0.70)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled", disabled)

	button.add_theme_color_override("font_color", accent.lerp(Color(0.86, 0.80, 0.70), 0.55))
	button.add_theme_color_override("font_hover_color", accent.lerp(Color.WHITE, 0.25))
	button.add_theme_color_override("font_pressed_color", Color(0.17, 0.11, 0.06))
	button.add_theme_font_size_override("font_size", 10)
	button.button_pressed = is_active

func _on_visibility_changed():
	if visible:
		trigger_refresh()
	else:
		if is_repair_mode:
			btn_repair_mode.button_pressed = false

func _on_inventory_updated():
	if visible:
		# v87.1: Prune stale selections
		if is_select_mode:
			for mid in selected_modules.keys():
				if not manager.module_inventory.has(mid) or manager.module_inventory[mid] <= 0:
					selected_modules.erase(mid)
			_refresh_action_bar()
		rebuild_storage()
		_refresh_tab_labels()
		update_header()

func _on_warp_refresh(_gains):
	trigger_refresh()

func trigger_refresh():
	update_header()
	rebuild_slots()
	rebuild_ammo_slots()
	rebuild_storage()
	_refresh_tab_labels()
	_refresh_filter_button_styles()

func update_header():
	if manager.active_hull and manager.active_hull in manager.hulls:
		var hull_data = manager.hulls[manager.active_hull]
		ship_name_lbl.text = hull_data["name"].to_upper()

		var e_cap = 100.0
		if GameState.resources:
			e_cap = GameState.resources.max_energy
		var e_used = manager.energy_used

		power_bar.max_value = e_cap
		power_bar.value = e_used
		power_lbl.text = "%d / %d" % [int(round(e_used)), int(round(e_cap))]

		if e_used > e_cap:
			power_bar.modulate = Color(1.0, 0.38, 0.34)
			power_lbl.add_theme_color_override("font_color", Color(1.0, 0.47, 0.42))
		elif e_used > e_cap * 0.8:
			power_bar.modulate = Color(1.0, 0.74, 0.31)
			power_lbl.add_theme_color_override("font_color", Color(1.0, 0.78, 0.45))
		else:
			power_bar.modulate = Color(0.84, 0.70, 0.45)
			power_lbl.add_theme_color_override("font_color", TEXT_MAIN)

		var total_dps = _calculate_total_dps()
		var combat_manager = GameState.combat_manager
		var milestone_eva = combat_manager.get_milestone_evasion_bonus() if combat_manager else 0.0
		var milestone_crit = combat_manager.get_milestone_crit_bonus() if combat_manager else 0.0

		var total_eva = manager.evasion + milestone_eva
		var total_crit = (manager.crit_chance + milestone_crit) * 100.0

		var stats = [
			{"label": "HP", "val": str(manager.max_hp), "color": Color(0.73, 0.86, 0.56)},
			{"label": "SHIELD", "val": UITheme.format_num(manager.max_shield), "color": Color(0.56, 0.76, 0.96)},
			{"label": "ATK", "val": UITheme.format_num(manager.attack), "color": Color(0.95, 0.57, 0.38)},
			{"label": "DEF", "val": UITheme.format_num(manager.defense), "color": Color(0.79, 0.74, 0.66)},
			{"label": "ACC", "val": str(manager.accuracy), "color": Color(0.85, 0.81, 0.74)},
			{"label": "CRIT", "val": "%.0f%%" % total_crit, "color": Color(0.93, 0.47, 0.38)},
			{"label": "EVA", "val": "%.0f" % total_eva, "color": Color(0.86, 0.84, 0.47)},
			{"label": "DPS", "val": UITheme.format_num(total_dps), "color": Color(0.94, 0.80, 0.44)}
		]

		for child in stats_grid.get_children():
			child.queue_free()

		for stat_data in stats:
			var tile = PanelContainer.new()
			tile.custom_minimum_size = Vector2(96, 40)
			tile.add_theme_stylebox_override("panel", _make_stat_tile_style(stat_data["color"]))

			var margin = MarginContainer.new()
			margin.add_theme_constant_override("margin_left", 6)
			margin.add_theme_constant_override("margin_top", 4)
			margin.add_theme_constant_override("margin_right", 6)
			margin.add_theme_constant_override("margin_bottom", 4)
			tile.add_child(margin)

			var box = VBoxContainer.new()
			box.add_theme_constant_override("separation", 1)
			margin.add_child(box)

			var key_lbl = Label.new()
			key_lbl.text = stat_data["label"]
			key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			key_lbl.add_theme_font_size_override("font_size", 9)
			key_lbl.add_theme_color_override("font_color", TEXT_DIM)

			var value_lbl = Label.new()
			value_lbl.text = stat_data["val"]
			value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			value_lbl.add_theme_font_size_override("font_size", 12)
			value_lbl.add_theme_color_override("font_color", stat_data["color"])

			box.add_child(key_lbl)
			box.add_child(value_lbl)
			stats_grid.add_child(tile)
	else:
		ship_name_lbl.text = "NO HULL SELECTED"
		power_lbl.text = "0 / 0"
		for child in stats_grid.get_children():
			child.queue_free()

func _make_stat_tile_style(accent: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.08, 0.07, 0.94)
	style.set_border_width_all(1)
	style.border_color = accent.lerp(Color(0.43, 0.33, 0.24), 0.55)
	style.set_corner_radius_all(2)
	style.content_margin_left = 2
	style.content_margin_top = 2
	style.content_margin_right = 2
	style.content_margin_bottom = 2
	return style

func _calculate_total_dps() -> float:
	var total = 0.0

	var has_plasma_overcharger = false
	for slot_idx in manager.loadout:
		if manager.loadout[slot_idx] == "plasma_overcharger":
			has_plasma_overcharger = true
			break

	for slot_idx in manager.loadout:
		var module_id = manager.loadout[slot_idx]
		if module_id and module_id in manager.modules:
			var module_data = manager.modules[module_id]
			if module_data.get("slot_type") == "weapon":
				var stats = module_data.get("stats", {})
				var energy_damage = stats.get("atk_energy", 0)
				if has_plasma_overcharger:
					energy_damage *= 2.0

				var damage = stats.get("atk_kinetic", 0) + energy_damage + stats.get("atk_explosive", 0)
				var interval = stats.get("atk_interval", 2.5)
				if interval > 0:
					total += float(damage) / interval
	return total

func rebuild_slots():
	var slot_container = $VBoxContainer/MainLayout/SchematicArea/LayoutSplit/SlotListPanel/SlotScroll/SchematicContainer
	if slot_container:
		for child in slot_container.get_children():
			child.queue_free()

	if not manager.active_hull in manager.hulls:
		return

	var hull_data = manager.hulls[manager.active_hull]
	var slots = hull_data["slots"]

	var blades = {
		"Weapons": [],
		"Ammunition": [],
		"Defense": [],
		"Armor": [],
		"Systems": [],
		"Utility": []
	}

	for i in range(slots.size()):
		var slot_type = slots[i]
		if slot_type == "weapon":
			blades["Weapons"].append({"idx": i, "type": slot_type})
			blades["Ammunition"].append({"idx": i, "type": "ammo"})
		elif slot_type == "shield":
			blades["Defense"].append({"idx": i, "type": slot_type})
		elif slot_type == "armor":
			blades["Armor"].append({"idx": i, "type": slot_type})
		elif slot_type in ["engine", "reactor", "battery"]:
			blades["Systems"].append({"idx": i, "type": slot_type})
		else:
			blades["Utility"].append({"idx": i, "type": slot_type})

	_create_blade("Weapons", blades["Weapons"], slot_container, Color(0.90, 0.44, 0.31))
	_create_blade("Ammunition", blades["Ammunition"], slot_container, Color(0.90, 0.58, 0.36), true)
	_create_blade("Defense", blades["Defense"], slot_container, Color(0.58, 0.73, 0.92))
	_create_blade("Armor", blades["Armor"], slot_container, Color(0.76, 0.70, 0.62))
	_create_blade("Systems", blades["Systems"], slot_container, Color(0.83, 0.78, 0.45))
	_create_blade("Utility", blades["Utility"], slot_container, Color(0.72, 0.63, 0.56))
	_create_consumable_blade(slot_container)

func _create_blade(title: String, slot_list: Array, parent: Node, color: Color = Color.WHITE, is_ammo: bool = false):
	if slot_list.is_empty():
		return

	var blade_panel = PanelContainer.new()
	blade_panel.add_theme_stylebox_override("panel", _make_blade_style(color))
	parent.add_child(blade_panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	blade_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var label = Label.new()
	label.text = "%s" % title.to_upper()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	vbox.add_child(label)

	var flow = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	vbox.add_child(flow)

	for slot_data in slot_list:
		var widget
		if is_ammo:
			widget = ammo_slot_scene.instantiate()
			flow.add_child(widget)
			widget.setup(slot_data["idx"], self, manager)
		else:
			widget = slot_widget_scene.instantiate()
			flow.add_child(widget)
			widget.setup(slot_data["idx"], slot_data["type"], self, manager)

func _make_blade_style(accent: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.05, 0.05, 0.88)
	style.set_border_width_all(1)
	style.border_color = accent.lerp(Color(0.38, 0.28, 0.20), 0.55)
	style.set_corner_radius_all(2)
	style.shadow_color = Color(0, 0, 0, 0.18)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 2)
	return style

func _create_consumable_blade(parent: Node):
	var blade_panel = PanelContainer.new()
	blade_panel.add_theme_stylebox_override("panel", _make_blade_style(Color(0.78, 0.65, 0.82)))
	parent.add_child(blade_panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	blade_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var label = Label.new()
	label.text = "CONSUMABLES"
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.78, 0.65, 0.82))
	vbox.add_child(label)

	var flow = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	vbox.add_child(flow)

	var hull_slot = slot_widget_scene.instantiate()
	flow.add_child(hull_slot)
	hull_slot.setup(-1, "consumable_hull", self, manager)

	var shield_slot = slot_widget_scene.instantiate()
	flow.add_child(shield_slot)
	shield_slot.setup(-1, "consumable_shield", self, manager)

func rebuild_ammo_slots():
	pass

func rebuild_storage():
	var slot_count = 0
	for child in storage_grid.get_children():
		child.queue_free()

	var inv = manager.module_inventory
	var sorted_mids = inv.keys()
	sorted_mids.sort_custom(func(a, b):
		var data_a = manager.modules.get(a, {})
		var data_b = manager.modules.get(b, {})
		return _get_module_power_score(a, data_a) < _get_module_power_score(b, data_b)
	)

	for module_id in sorted_mids:
		var module_count = inv[module_id]
		if module_count > 0 and module_id in manager.modules:
			var module_data = manager.modules[module_id]
			if _is_module_visible_for_filter(module_data):
				var item = draggable_icon_scene.instantiate()
				storage_grid.add_child(item)
				item.setup(module_id, module_data, module_count)
				# v87.1: Wire selection mode
				item.select_mode_active = is_select_mode
				if is_select_mode and selected_modules.has(module_id):
					item.set_selected(true)
				item.on_selection_toggled = _on_card_selection_toggled
				slot_count += 1

	if active_filter in ["all", "ordnance", "ord"]:
		for ammo_id in ORDNANCE_AMMO_IDS:
			var qty = GameState.resources.get_element_amount(ammo_id)
			if qty > 0:
				var ammo_card = draggable_icon_scene.instantiate()
				storage_grid.add_child(ammo_card)
				var display_name = ElementDB.get_display_name(ammo_id)
				var fake_data = {"name": display_name, "slot_type": "ammo", "stats": {}}
				ammo_card.setup(ammo_id, fake_data, qty)
				slot_count += 1

	if active_filter in ["all", "ordnance", "ord"]:
		var consumables = ElementDB.get_elements_in_category("consumables")
		for consumable_id in consumables:
			var qty = GameState.resources.get_element_amount(consumable_id)
			if qty > 0:
				var consumable_card = draggable_icon_scene.instantiate()
				storage_grid.add_child(consumable_card)
				var consumable_data = ElementDB.get_consumable_data(consumable_id)
				var display_name = consumable_data.get("name", consumable_id)
				var consumable_type = consumable_data.get("type", "hull")
				var fake_data = {
					"name": display_name,
					"slot_type": "consumable",
					"consumable_type": consumable_type,
					"stats": {"heal_pct": consumable_data.get("heal_pct", 0)}
				}
				consumable_card.setup(consumable_id, fake_data, qty)
				slot_count += 1

	# v83.9: Matrix Cores (Cracked, Stable, Pristine)
	if active_filter in ["all", "matrix"]:
		var cores = ElementDB.get_elements_in_category("matrix_cores")
		for core_id in cores:
			var qty = GameState.resources.get_element_amount(core_id)
			if qty > 0:
				var core_card = draggable_icon_scene.instantiate()
				storage_grid.add_child(core_card)
				var display_name = ElementDB.get_display_name(core_id)
				var fake_data = {
					"name": display_name,
					"slot_type": "gem", # Treating as gem for socketing
					"rarity": 3 if "Stable" in display_name else (4 if "Pristine" in display_name else 2),
					"stats": {},
					"desc": ElementDB.get_element_description(core_id)
				}
				core_card.setup(core_id, fake_data, qty)
				slot_count += 1
	
	# v83.9.5: Boss Cores (Lunar, Asteroid, etc.) - Only in "ALL"
	if active_filter == "all":
		var boss_cores = ElementDB.get_elements_in_category("boss_cores")
		for core_id in boss_cores:
			var qty = GameState.resources.get_element_amount(core_id)
			if qty > 0:
				var core_card = draggable_icon_scene.instantiate()
				storage_grid.add_child(core_card)
				var display_name = ElementDB.get_display_name(core_id)
				var fake_data = {
					"name": display_name,
					"slot_type": "resource",
					"rarity": 4, # Unique
					"stats": {},
					"desc": "Rare boss component."
				}
				core_card.setup(core_id, fake_data, qty)
				slot_count += 1

	# v84.1: Fill remaining with Empty Slots (Premium Grid Look)
	var min_slots = 42 # 6 columns * 7 rows
	var needed = max(0, min_slots - slot_count)
	for i in range(needed):
		var empty = empty_slot_scene.instantiate()
		storage_grid.add_child(empty)
		# Match compact tile sizing
		empty.custom_minimum_size = Vector2(40, 40)

func _is_module_visible_for_filter(module_data: Dictionary) -> bool:
	var module_type = module_data.get("slot_type", "weapon")
	match active_filter:
		"all":
			return true
		"weapon":
			return module_type == "weapon"
		"shield":
			return module_type == "shield"
		"armor":
			return module_type == "armor"
		"engine":
			return module_type == "engine"
		"battery":
			return module_type == "battery"
		"utility":
			var core_types = ["weapon", "shield", "armor", "engine", "battery"]
			return module_type in ["sensor", "cooling", "reactor"] or module_type not in core_types
		"systems", "sys":
			return module_type in ["shield", "engine", "battery", "sensor", "cooling", "reactor"]
		"explosive":
			return module_type == "weapon" and module_data.get("stats", {}).get("atk_explosive", 0) > 0
		"ordnance", "ord":
			return false
		"matrix":
			return module_type in ["gem", "gem_synth"]
		_:
			return true

func rebuild_ammo_storage():
	pass

func _on_filter_changed(filter_id: String):
	active_filter = _normalize_filter_id(filter_id)
	_refresh_filter_button_styles()
	_refresh_tab_labels()
	rebuild_storage()

func _refresh_tab_labels():
	if not manager:
		return

	var counts = _build_filter_counts()
	for filter_id in FILTER_ORDER:
		if not tab_buttons.has(filter_id):
			continue
		var button: Button = tab_buttons[filter_id]
		var label = FILTER_LABELS.get(filter_id, filter_id.to_upper())
		var value = int(counts.get(filter_id, 0))
		button.text = "%s %d" % [label, value]

func _build_filter_counts() -> Dictionary:
	var counts := {}
	for filter_id in FILTER_ORDER:
		counts[filter_id] = 0

	if not manager:
		return counts

	var inv = manager.module_inventory
	for module_id in inv.keys():
		var qty = int(inv[module_id])
		if qty <= 0 or not manager.modules.has(module_id):
			continue

		counts["all"] += 1
		var module_type = manager.modules[module_id].get("slot_type", "weapon")
		match module_type:
			"weapon":
				counts["weapon"] += 1
			"shield":
				counts["shield"] += 1
			"armor":
				counts["armor"] += 1
			"engine":
				counts["engine"] += 1
			"battery":
				counts["battery"] += 1
			"reactor", "sensor", "cooling":
				counts["utility"] += 1
			_:
				counts["utility"] += 1

	if not GameState.resources:
		return counts

	var ordnance_count = 0
	for ammo_id in ORDNANCE_AMMO_IDS:
		if GameState.resources.get_element_amount(ammo_id) > 0:
			ordnance_count += 1

	var consumables = ElementDB.get_elements_in_category("consumables")
	for consumable_id in consumables:
		if GameState.resources.get_element_amount(consumable_id) > 0:
			ordnance_count += 1

	counts["ordnance"] = ordnance_count
	
	# v83.9: Matrix Core Counts
	var core_count = 0
	var matrix_cores = ElementDB.get_elements_in_category("matrix_cores")
	for core_id in matrix_cores:
		if GameState.resources.get_element_amount(core_id) > 0:
			core_count += 1
	counts["matrix"] = core_count
	
	# Boss Cores added to "ALL"
	var boss_core_count = 0
	var boss_cores = ElementDB.get_elements_in_category("boss_cores")
	for core_id in boss_cores:
		if GameState.resources.get_element_amount(core_id) > 0:
			boss_core_count += 1
			
	counts["all"] += ordnance_count + core_count + boss_core_count
	return counts

func _normalize_filter_id(filter_id: String) -> String:
	match filter_id:
		"wpn":
			return "weapon"
		"sys":
			return "systems"
		"ord":
			return "ordnance"
		_:
			if filter_id in FILTER_ORDER:
				return filter_id
			if filter_id in ["systems", "explosive", "armor"]:
				return filter_id
			return "all"

func get_module_widget(module_id: String) -> Control:
	for child in storage_grid.get_children():
		if child.get("mid") == module_id:
			return child
	return null

func _get_module_power_score(id: String, data: Dictionary) -> int:
	var score = 0
	var stats = data.get("stats", {})

	var cost = data.get("cost", {})
	var credits = cost.get("credits", 0)
	if credits > 0:
		score += int(log(credits) * 10)
	else:
		if "BatteryT1" in cost:
			score += 10
		elif "BatteryT2" in cost:
			score += 20
		elif "BatteryT3" in cost:
			score += 30
		else:
			score += 5

	if stats.get("atk_kinetic", 0) > 0:
		score += stats["atk_kinetic"]
	if stats.get("atk_energy", 0) > 0:
		score += stats["atk_energy"]
	if stats.get("atk_explosive", 0) > 0:
		score += stats["atk_explosive"]
	if stats.get("max_shield", 0) > 0:
		score += stats["max_shield"] / 5
	if stats.get("hp", 0) > 0:
		score += stats["hp"] / 10
	if stats.get("energy_capacity", 0) > 0:
		score += stats["energy_capacity"]
	if stats.get("eva", 0) > 0:
		score += stats["eva"] * 2
	if stats.get("atk_speed_bonus", 0) > 0:
		score += int(stats["atk_speed_bonus"] * 100)

	# v80.3: Removed dead sort-score overrides (mining_laser_mk1, mk2, railgun_mk1 no longer exist)

	return score

# ──────────────────────────────────────────────
# v87.1: Multi-Select Demolish System
# ──────────────────────────────────────────────

func _create_action_bar():
	_action_bar = HBoxContainer.new()
	_action_bar.name = "SelectActionBar"
	_action_bar.add_theme_constant_override("separation", 6)
	_action_bar.visible = false
	
	# Insert into the right panel's VBox, after tab strip frame
	var parent_vbox = tab_frame.get_parent()
	if parent_vbox:
		parent_vbox.add_child(_action_bar)
		parent_vbox.move_child(_action_bar, tab_frame.get_index() + 1)
	
	# SELECT ALL button
	_select_all_btn = Button.new()
	_select_all_btn.text = "ALL"
	_select_all_btn.tooltip_text = "Select all visible modules"
	_select_all_btn.custom_minimum_size = Vector2(50, 28)
	_select_all_btn.pressed.connect(_on_select_all)
	_action_bar.add_child(_select_all_btn)
	_apply_action_button_style(_select_all_btn, Color(0.7, 0.7, 0.6))
	
	# DESELECT ALL button
	_deselect_all_btn = Button.new()
	_deselect_all_btn.text = "NONE"
	_deselect_all_btn.tooltip_text = "Deselect all modules"
	_deselect_all_btn.custom_minimum_size = Vector2(50, 28)
	_deselect_all_btn.pressed.connect(_on_deselect_all)
	_action_bar.add_child(_deselect_all_btn)
	_apply_action_button_style(_deselect_all_btn, Color(0.7, 0.7, 0.6))
	
	# Spacer
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_bar.add_child(spacer)
	
	# DEMOLISH button
	_demolish_btn = Button.new()
	_demolish_btn.text = "DEMOLISH (0)"
	_demolish_btn.tooltip_text = "Demolish all selected modules"
	_demolish_btn.custom_minimum_size = Vector2(140, 28)
	_demolish_btn.pressed.connect(_on_demolish_selected)
	_action_bar.add_child(_demolish_btn)
	_apply_action_button_style(_demolish_btn, Color(0.95, 0.35, 0.25))

func _apply_select_button_style():
	if not _select_btn: return
	var accent = Color(0.95, 0.65, 0.25) if not is_select_mode else Color(0.3, 0.9, 0.4)
	_apply_filter_button_style(_select_btn, is_select_mode, accent)
	_select_btn.text = "DONE" if is_select_mode else "SELECT"

func _apply_action_button_style(btn: Button, accent: Color):
	var normal = StyleBoxFlat.new()
	normal.bg_color = TAB_BASE
	normal.set_border_width_all(1)
	normal.border_color = accent.lerp(TAB_EDGE, 0.5)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	
	var hover = normal.duplicate()
	hover.bg_color = TAB_BASE.lerp(accent, 0.25)
	hover.border_color = accent
	
	var pressed = normal.duplicate()
	pressed.bg_color = TAB_BASE.lerp(accent, 0.4)
	
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.3))
	btn.add_theme_color_override("font_hover_color", accent.lerp(Color.WHITE, 0.5))
	btn.add_theme_font_size_override("font_size", 10)

func _on_select_mode_pressed():
	is_select_mode = !is_select_mode
	if is_select_mode:
		_enter_select_mode()
	else:
		_exit_select_mode()

func _enter_select_mode():
	is_select_mode = true
	selected_modules.clear()
	_apply_select_button_style()
	_action_bar.visible = true
	_refresh_action_bar()
	rebuild_storage()

func _exit_select_mode():
	is_select_mode = false
	selected_modules.clear()
	_apply_select_button_style()
	_action_bar.visible = false
	rebuild_storage()

func _on_card_selection_toggled(module_id: String, is_sel: bool):
	if is_sel:
		selected_modules[module_id] = true
	else:
		selected_modules.erase(module_id)
	_refresh_action_bar()

func _on_select_all():
	# Select all visible module cards (not ammo/consumables)
	for child in storage_grid.get_children():
		if child.has_method("set_selected") and child.get("mid") != null:
			var slot_type = child.data.get("slot_type", "")
			if slot_type not in ["ammo", "consumable", "gem"]:
				child.set_selected(true)
				selected_modules[child.mid] = true
	_refresh_action_bar()

func _on_deselect_all():
	selected_modules.clear()
	for child in storage_grid.get_children():
		if child.has_method("set_selected"):
			child.set_selected(false)
	_refresh_action_bar()

func _refresh_action_bar():
	if not _demolish_btn: return
	var count = selected_modules.size()
	if count == 0:
		_demolish_btn.text = "DEMOLISH (0)"
		_demolish_btn.disabled = true
		_demolish_btn.modulate = Color(1, 1, 1, 0.4)
	else:
		var summary = manager.get_batch_demolish_summary(selected_modules.keys())
		_demolish_btn.text = "DEMOLISH %d > %s cr + %s pts" % [
			summary["count"],
			UITheme.format_num(summary["credits"]),
			summary["parts"]
		]
		_demolish_btn.disabled = false
		_demolish_btn.modulate = Color.WHITE

func _on_demolish_selected():
	var count = selected_modules.size()
	if count == 0: return
	
	var summary = manager.get_batch_demolish_summary(selected_modules.keys())
	
	# Confirmation dialog
	var dlg = ConfirmationDialog.new()
	dlg.title = "Confirm Batch Demolish"
	dlg.dialog_text = "Demolish %d modules?\n\nYou will receive:\n  %s Credits\n  %d Spare Parts" % [
		summary["count"],
		UITheme.format_num(summary["credits"]),
		summary["parts"]
	]
	dlg.ok_button_text = "DEMOLISH"
	dlg.cancel_button_text = "Cancel"
	add_child(dlg)
	
	dlg.confirmed.connect(func():
		var ids = selected_modules.keys().duplicate()
		var result = manager.demolish_modules_batch(ids)
		UITheme.show_notification(
			"Demolished %d modules: +%s credits, +%d parts" % [
				result["count"],
				UITheme.format_num(result["credits"]),
				result["parts"]
			],
			Color(0.3, 0.9, 0.4)
		)
		_exit_select_mode()
		dlg.queue_free()
	)
	dlg.canceled.connect(func():
		dlg.queue_free()
	)
	dlg.popup_centered()
