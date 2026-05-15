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
var selected_mids: Array[String] = []
var btn_demolish_selected: Button
var btn_clear: Button
var btn_selection_toggle: Button
var bulk_actions_container: HBoxContainer
var is_selection_mode: bool = false

var focused_slot_idx: int = -1
var focused_slot_type: String = ""
var focused_slot_equipped_mid: String = ""
var all_slot_widgets: Array = []
var armory_sort_mode: int = 0  # 0=Power, 1=Zone, 2=Rarity
var _armory_banner: Label = null
var _sort_buttons: Array = []
var _preset_load_buttons: Array = []

# Consolidated armory toolbar (search + sort dropdown + manage toggle).
var armory_search: LineEdit
var armory_sort_dropdown: OptionButton
var armory_manage_btn: Button
var armory_search_text: String = ""

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
	"SlugT1", "SlugT1S", "SlugT2", "SlugT3", "SlugT4",
	"CellT1", "CellT2", "CellT3", "CellT4",
	"MissileT1", "MissileT2", "MissileT3", "MissileT4"
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
		_apply_toolbar_button_style(btn_repair_mode, Color(0.95, 0.78, 0.30))
		btn_repair_mode.toggled.connect(func(toggled_on):
			is_repair_mode = toggled_on
			# Re-apply style so the "pressed" edge actually persists while toggled on
			_apply_toolbar_button_style(btn_repair_mode, Color(0.95, 0.78, 0.30))
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
	_setup_bulk_actions()

	# Title is clickable — rename active build (preset name)
	if ship_name_lbl:
		ship_name_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		ship_name_lbl.gui_input.connect(_on_ship_title_input)
		ship_name_lbl.mouse_entered.connect(func():
			if _get_active_build_name() != "":
				Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND))
		ship_name_lbl.mouse_exited.connect(func():
			if not is_repair_mode:
				Input.set_default_cursor_shape(Input.CURSOR_ARROW))

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
	_refresh_tab_labels()

func _setup_bulk_actions():
	bulk_actions_container = HBoxContainer.new()
	bulk_actions_container.alignment = BoxContainer.ALIGNMENT_END
	bulk_actions_container.add_theme_constant_override("separation", 10)
	
	btn_selection_toggle = Button.new()
	btn_selection_toggle.text = "SELECT MODULES"
	btn_selection_toggle.toggle_mode = true
	btn_selection_toggle.toggled.connect(_on_selection_mode_toggled)
	_apply_filter_button_style(btn_selection_toggle, false, Color(0.3, 0.8, 0.9))
	bulk_actions_container.add_child(btn_selection_toggle)

	btn_demolish_selected = Button.new()
	btn_demolish_selected.text = "DEMOLISH SELECTED (0)"
	btn_demolish_selected.disabled = true
	btn_demolish_selected.visible = false
	btn_demolish_selected.pressed.connect(_on_demolish_selected_pressed)
	_apply_filter_button_style(btn_demolish_selected, false, Color(0.9, 0.3, 0.3))
	bulk_actions_container.add_child(btn_demolish_selected)
	
	btn_clear = Button.new()
	btn_clear.text = "CLEAR"
	btn_clear.visible = false
	btn_clear.pressed.connect(func():
		selected_mids.clear()
		_update_bulk_ui()
		rebuild_storage()
	)
	_apply_filter_button_style(btn_clear, false, Color(0.7, 0.7, 0.7))
	bulk_actions_container.add_child(btn_clear)

	# Scrap-by-rarity quick actions
	var btn_scrap_common = Button.new()
	btn_scrap_common.text = "SCRAP COMMONS"
	btn_scrap_common.tooltip_text = "Demolish every non-equipped Common module."
	btn_scrap_common.pressed.connect(_on_scrap_by_rarity.bind(0))
	_apply_filter_button_style(btn_scrap_common, false, Color(0.70, 0.70, 0.70))
	bulk_actions_container.add_child(btn_scrap_common)

	var btn_scrap_junk = Button.new()
	btn_scrap_junk.text = "SCRAP JUNK"
	btn_scrap_junk.tooltip_text = "Demolish every non-equipped Common + Uncommon module."
	btn_scrap_junk.pressed.connect(_on_scrap_by_rarity.bind(1))
	_apply_filter_button_style(btn_scrap_junk, false, Color(0.30, 0.85, 0.40))
	bulk_actions_container.add_child(btn_scrap_junk)

	var scroll = storage_grid.get_parent()
	var v_box = scroll.get_parent()

	# Armory context banner
	_armory_banner = Label.new()
	_armory_banner.add_theme_font_size_override("font_size", 11)
	_armory_banner.add_theme_color_override("font_color", Color(0.55, 0.80, 1.0))
	_armory_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_armory_banner.text = ""
	v_box.add_child(_armory_banner)
	v_box.move_child(_armory_banner, scroll.get_index())

	# Sort mode buttons
	var sort_row = HBoxContainer.new()
	sort_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sort_row.add_theme_constant_override("separation", 6)
	v_box.add_child(sort_row)
	v_box.move_child(sort_row, _armory_banner.get_index() + 1)

	_sort_buttons.clear()
	for i in range(3):
		var btn = Button.new()
		btn.text = ["Power", "Zone", "Rarity"][i]
		var mode_idx = i
		btn.pressed.connect(func():
			armory_sort_mode = mode_idx
			_update_sort_button_styles()
			rebuild_storage()
		)
		_apply_filter_button_style(btn, i == 0, Color(0.65, 0.60, 0.82))
		sort_row.add_child(btn)
		_sort_buttons.append(btn)

	v_box.add_child(bulk_actions_container)
	v_box.move_child(bulk_actions_container, scroll.get_index())
	# Bulk actions are hidden by default; Manage toggle reveals them.
	bulk_actions_container.visible = false

	# Loadout Preset row (above sort buttons)
	_setup_loadout_preset_row(v_box, _armory_banner.get_index())

	# Consolidated toolbar: SEARCH + SORT dropdown + MANAGE toggle.
	# Hides the now-redundant sort button row.
	_setup_armory_toolbar(v_box, scroll)
	for btn in _sort_buttons:
		if is_instance_valid(btn): btn.visible = false

func _setup_armory_toolbar(v_box: Node, scroll_node: Node):
	var toolbar = HBoxContainer.new()
	toolbar.name = "ArmoryToolbar"
	toolbar.add_theme_constant_override("separation", 6)
	toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Search — primary filter, takes most width
	armory_search = LineEdit.new()
	armory_search.placeholder_text = "🔍  Search    tier:3   set:architect   slot:weapon"
	armory_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	armory_search.clear_button_enabled = true
	armory_search.add_theme_font_size_override("font_size", 11)
	_apply_search_field_style(armory_search)
	armory_search.text_changed.connect(func(t):
		armory_search_text = t
		rebuild_storage())
	toolbar.add_child(armory_search)

	# Sort dropdown — consolidates the 3 sort buttons
	armory_sort_dropdown = OptionButton.new()
	armory_sort_dropdown.add_item("Sort · Power",  0)
	armory_sort_dropdown.add_item("Sort · Zone",   1)
	armory_sort_dropdown.add_item("Sort · Rarity", 2)
	armory_sort_dropdown.selected = armory_sort_mode
	armory_sort_dropdown.add_theme_font_size_override("font_size", 11)
	_apply_dropdown_style(armory_sort_dropdown)
	armory_sort_dropdown.item_selected.connect(func(idx):
		armory_sort_mode = idx
		_update_sort_button_styles()
		rebuild_storage())
	toolbar.add_child(armory_sort_dropdown)

	# Manage toggle — reveals/hides bulk action controls on demand
	armory_manage_btn = Button.new()
	armory_manage_btn.text = "⚙ Manage"
	armory_manage_btn.toggle_mode = true
	armory_manage_btn.tooltip_text = "Reveal bulk actions (select / demolish / scrap)."
	armory_manage_btn.add_theme_font_size_override("font_size", 11)
	_apply_toolbar_button_style(armory_manage_btn, Color(0.55, 0.85, 0.95))
	armory_manage_btn.toggled.connect(func(on):
		if bulk_actions_container:
			bulk_actions_container.visible = on
		_apply_toolbar_button_style(armory_manage_btn, Color(0.55, 0.85, 0.95)))
	toolbar.add_child(armory_manage_btn)

	v_box.add_child(toolbar)
	v_box.move_child(toolbar, scroll_node.get_index())

# ── Toolbar styling helpers (match the parchment/brass theme used elsewhere) ──

func _apply_toolbar_button_style(button: Button, accent: Color):
	# Toggle-aware: pressed state shows a lit accent edge so on/off is obvious.
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.07, 0.05, 0.95)
	normal.set_corner_radius_all(2)
	normal.set_border_width_all(1)
	normal.border_color = TAB_EDGE
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4

	var hover := normal.duplicate()
	hover.bg_color = Color(0.14, 0.10, 0.07, 1.0)
	hover.border_color = accent.lerp(TAB_EDGE, 0.45)

	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.18, 0.13, 0.08, 1.0)
	pressed.border_color = accent
	pressed.border_width_left = 3

	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.08, 0.06, 0.05, 0.70)
	disabled.border_color = Color(0.22, 0.18, 0.15, 0.70)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# If the button is toggle-pressed, also show the lit edge in the normal state
	if button.toggle_mode and button.button_pressed:
		button.add_theme_stylebox_override("normal", pressed.duplicate())

	button.add_theme_color_override("font_color", accent.lerp(TEXT_MAIN, 0.55))
	button.add_theme_color_override("font_hover_color", accent.lerp(Color.WHITE, 0.25))
	button.add_theme_color_override("font_pressed_color", accent.lerp(Color.WHITE, 0.45))
	button.add_theme_color_override("font_focus_color", accent.lerp(TEXT_MAIN, 0.55))

func _apply_dropdown_style(opt: OptionButton):
	# Style the OptionButton itself like a toolbar button…
	_apply_toolbar_button_style(opt, Color(0.85, 0.70, 0.45))
	opt.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# …and style its popup list to match the brass/parchment palette.
	var popup := opt.get_popup()
	if popup == null: return
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.05, 0.04, 0.98)
	panel.set_corner_radius_all(3)
	panel.set_border_width_all(1)
	panel.border_color = Color(0.85, 0.70, 0.45, 0.65)
	panel.content_margin_left = 4
	panel.content_margin_right = 4
	panel.content_margin_top = 4
	panel.content_margin_bottom = 4
	panel.shadow_color = Color(0, 0, 0, 0.6)
	panel.shadow_size = 6
	popup.add_theme_stylebox_override("panel", panel)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.18, 0.13, 0.08, 1.0)
	hover.border_width_left = 2
	hover.border_color = Color(0.85, 0.70, 0.45, 0.95)
	hover.set_corner_radius_all(2)
	hover.content_margin_left = 8
	hover.content_margin_right = 8
	hover.content_margin_top = 3
	hover.content_margin_bottom = 3
	popup.add_theme_stylebox_override("hover", hover)

	popup.add_theme_color_override("font_color", TEXT_MAIN)
	popup.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.55))
	popup.add_theme_color_override("font_separator_color", TAB_EDGE)
	popup.add_theme_font_size_override("font_size", 11)

func _apply_search_field_style(le: LineEdit):
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.04, 0.03, 0.98)
	normal.set_corner_radius_all(2)
	normal.set_border_width_all(1)
	normal.border_color = TAB_EDGE
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4

	var focus := normal.duplicate()
	focus.border_color = Color(0.85, 0.70, 0.45, 0.95)
	focus.border_width_left = 2

	le.add_theme_stylebox_override("normal", normal)
	le.add_theme_stylebox_override("focus", focus)
	le.add_theme_color_override("font_color", TEXT_MAIN)
	le.add_theme_color_override("font_placeholder_color", TEXT_DIM)
	le.add_theme_color_override("caret_color", Color(0.85, 0.70, 0.45))

func _setup_loadout_preset_row(parent: Node, insert_idx: int):
	var preset_row = HBoxContainer.new()
	preset_row.alignment = BoxContainer.ALIGNMENT_CENTER
	preset_row.add_theme_constant_override("separation", 12)

	var label = Label.new()
	label.text = "LOADOUTS:"
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.55, 0.60, 0.72))
	preset_row.add_child(label)

	_preset_load_buttons = []
	for i in [1, 2, 3]:
		var preset_box = HBoxContainer.new()
		preset_box.add_theme_constant_override("separation", 2)

		var save_btn = Button.new()
		save_btn.text = "💾 %d" % i
		save_btn.tooltip_text = "Save current ship setup to Preset %d" % i
		save_btn.pressed.connect(_on_preset_save.bind(i))
		save_btn.add_theme_font_size_override("font_size", 11)
		_apply_filter_button_style(save_btn, false, Color(0.65, 0.85, 0.95))
		preset_box.add_child(save_btn)

		var load_btn = Button.new()
		load_btn.text = "LOAD %d" % i
		load_btn.tooltip_text = "Apply Preset %d to ship" % i
		load_btn.pressed.connect(_on_preset_load.bind(i))
		load_btn.add_theme_font_size_override("font_size", 11)
		_apply_filter_button_style(load_btn, false, Color(0.95, 0.80, 0.30))
		preset_box.add_child(load_btn)

		preset_row.add_child(preset_box)
		_preset_load_buttons.append(load_btn)

	parent.add_child(preset_row)
	parent.move_child(preset_row, insert_idx)
	_refresh_preset_buttons()

func _refresh_preset_buttons():
	if not manager: return
	for i in range(3):
		var idx = i + 1
		var btn = _preset_load_buttons[i]
		var empty = manager.is_loadout_preset_empty(idx)
		btn.disabled = empty
		if empty:
			btn.tooltip_text = "Preset %d is empty. Save a build first." % idx
		else:
			btn.tooltip_text = "Apply Preset %d to ship." % idx

func _on_preset_save(idx: int):
	if not manager: return
	if manager.save_loadout_preset(idx):
		UITheme.show_notification("Loadout saved to Preset %d" % idx, Color(0.50, 0.95, 1.0))
		_refresh_preset_buttons()

func _on_preset_load(idx: int):
	if not manager: return
	var result = manager.load_loadout_preset(idx)
	if result["loaded"] == 0 and result["skipped"] == 0:
		UITheme.show_notification("Preset %d is empty." % idx, Color.RED)
		return
	var msg = "Loaded Preset %d  —  %d slot(s) restored" % [idx, result["loaded"]]
	if result["skipped"] > 0:
		msg += "  |  %d missing" % result["skipped"]
	UITheme.show_notification(msg, Color(0.95, 0.80, 0.30))
	# Force full UI refresh — slots & armory both depend on loadout
	trigger_refresh()

func _on_scrap_by_rarity(max_rarity: int):
	if not manager: return
	var count = manager.count_demolish_candidates_by_rarity(max_rarity)
	if count <= 0:
		var name = "Common" if max_rarity == 0 else "Junk"
		UITheme.show_notification("No %s modules to scrap." % name, Color(0.7, 0.7, 0.7))
		return
	# Confirmation dialog
	var dlg = ConfirmationDialog.new()
	dlg.title = "Bulk Demolish"
	dlg.dialog_text = "Demolish %d non-equipped module(s)?\n\nYou will receive credits, Spare Parts, and zone salvage." % count
	dlg.confirmed.connect(func():
		var scrapped = manager.bulk_demolish_by_rarity(max_rarity)
		UITheme.show_notification("Demolished %d module(s)" % scrapped, Color(0.95, 0.55, 0.25))
		trigger_refresh()
	)
	add_child(dlg)
	dlg.popup_centered()

func _on_selection_mode_toggled(toggled_on: bool):
	is_selection_mode = toggled_on
	if not toggled_on:
		selected_mids.clear()
	
	btn_selection_toggle.text = "EXIT SELECTION" if toggled_on else "SELECT MODULES"
	btn_demolish_selected.visible = toggled_on
	btn_clear.visible = toggled_on
	
	_update_bulk_ui()
	rebuild_storage()

func set_focused_slot(slot_idx: int, s_type: String, equipped_mid: String):
	for w in all_slot_widgets:
		if is_instance_valid(w): w.set_focus_highlight(false)
	focused_slot_idx = slot_idx
	focused_slot_type = s_type
	focused_slot_equipped_mid = equipped_mid
	for w in all_slot_widgets:
		if is_instance_valid(w) and w.slot_idx == slot_idx:
			w.set_focus_highlight(true)
			break
	_on_filter_changed(_slot_type_to_filter(s_type))
	_update_armory_banner()

func _slot_type_to_filter(s_type: String) -> String:
	match s_type:
		"weapon": return "weapon"
		"shield": return "shield"
		"armor": return "armor"
		"engine": return "engine"
		"battery": return "battery"
		"reactor", "sensor", "cooling": return "utility"
		_: return s_type

func _update_armory_banner():
	if not _armory_banner: return
	if focused_slot_type == "":
		_armory_banner.text = ""
		return
	if focused_slot_idx >= 0 and manager:
		var eq = manager.loadout.get(focused_slot_idx, "")
		focused_slot_equipped_mid = eq if eq else ""
	var slot_num = _get_focused_slot_number()
	var slot_label = "%s %d" % [focused_slot_type.to_upper(), slot_num]
	if focused_slot_equipped_mid != "" and focused_slot_equipped_mid in manager.modules:
		var eq_name = manager.modules[focused_slot_equipped_mid].get("name", "Unknown")
		for suffix in [" (Common)", " (Uncommon)", " (Rare)", " (Legendary)", " (Unique)"]:
			eq_name = eq_name.replace(suffix, "")
		_armory_banner.text = "Equipping for: %s  |  Currently: %s" % [slot_label, eq_name.to_upper()]
	else:
		_armory_banner.text = "Equipping for: %s  |  Slot is empty" % slot_label

func _get_focused_slot_number() -> int:
	var n = 1
	for w in all_slot_widgets:
		if is_instance_valid(w) and w.slot_type == focused_slot_type:
			if w.slot_idx == focused_slot_idx: break
			n += 1
	return n

func _update_sort_button_styles():
	var accent = Color(0.65, 0.60, 0.82)
	for i in range(_sort_buttons.size()):
		if i < _sort_buttons.size() and is_instance_valid(_sort_buttons[i]):
			_apply_filter_button_style(_sort_buttons[i], i == armory_sort_mode, accent)

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
		focused_slot_type = ""
		focused_slot_idx = -1
		focused_slot_equipped_mid = ""
		if _armory_banner: _armory_banner.text = ""

func _on_inventory_updated():
	if visible:
		# v85.0: Clean up selected_mids that are no longer in inventory
		var inv = manager.module_inventory
		var new_selected: Array[String] = []
		for mid in selected_mids:
			if inv.has(mid) and inv[mid] > 0:
				new_selected.append(mid)
			elif mid in ORDNANCE_AMMO_IDS: # Also check resources for ammo
				if GameState.resources.get_element_amount(mid) > 0:
					new_selected.append(mid)
		selected_mids = new_selected
		_update_bulk_ui()
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
	_update_armory_banner()
	_refresh_preset_buttons()

func update_header():
	if not (manager.active_hull and manager.active_hull in manager.hulls):
		ship_name_lbl.text = "NO HULL SELECTED"
		power_lbl.text = "0 / 0"
		for child in stats_grid.get_children():
			child.queue_free()
		return

	var hull_data = manager.hulls[manager.active_hull]

	# Build name in title: shows active loadout preset name when one matches the current loadout.
	var build_name = _get_active_build_name()
	if build_name != "":
		ship_name_lbl.text = "%s  ·  %s  ✎" % [hull_data["name"].to_upper(), build_name.to_upper()]
		ship_name_lbl.tooltip_text = "Click to rename this build."
	else:
		ship_name_lbl.text = hull_data["name"].to_upper()
		ship_name_lbl.tooltip_text = ""

	# Power-grid math (used by both old ShipSpecs bar and new GRID line)
	var e_cap = 100.0
	if GameState.resources:
		e_cap = GameState.resources.max_energy
	var e_used = manager.energy_used
	var grid_margin = e_cap - e_used

	# Keep the legacy ShipSpecs power bar updated but hide it — the new GRID line replaces it.
	power_bar.visible = false
	power_lbl.visible = false
	power_bar.max_value = e_cap
	power_bar.value = e_used
	power_lbl.text = "%d / %d" % [int(round(e_used)), int(round(e_cap))]
	var ship_specs_power_label = power_bar.get_parent().get_node_or_null("Label")
	if ship_specs_power_label: ship_specs_power_label.visible = false

	var total_dps = _calculate_total_dps()
	var combat_manager = GameState.combat_manager
	var milestone_eva = combat_manager.get_milestone_evasion_bonus() if combat_manager else 0.0
	var milestone_crit = combat_manager.get_milestone_crit_bonus() if combat_manager else 0.0
	var total_eva = manager.evasion + milestone_eva
	var total_crit = (manager.crit_chance + milestone_crit) * 100.0

	# Re-render the stat hierarchy
	for child in stats_grid.get_children():
		child.queue_free()
	stats_grid.columns = 1

	var stack = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 3)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_child(stack)

	# 1. HERO DPS — the question every player is actually asking
	stack.add_child(_build_hero_dps_panel(total_dps))

	# 2. HP / SHIELD as proper bars (the two things that get you killed)
	stack.add_child(_build_resource_bar("HULL",   manager.current_hp, manager.max_hp,
		Color(0.85, 0.40, 0.30), Color(0.30, 0.12, 0.10)))
	stack.add_child(_build_resource_bar("SHIELD", manager.max_shield, manager.max_shield,
		Color(0.45, 0.80, 1.00), Color(0.10, 0.20, 0.32)))

	# 3. POWER GRID with margin (the thing that gates equipping — promoted to first-class)
	stack.add_child(_build_grid_bar(e_used, e_cap, grid_margin))

	# 4. Supporting stats — single dense row, lower visual weight than HP/Shield/DPS
	stack.add_child(_build_supporting_stats_row(manager.attack, manager.defense, manager.accuracy, total_crit, total_eva))

	# 5. Sets Active panel — surfaces partial set progress
	var sets_panel = _build_sets_active_panel()
	if sets_panel: stack.add_child(sets_panel)

# ── Stat Hierarchy Builders ──

func _build_hero_dps_panel(dps: float) -> Control:
	var panel = PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.05, 0.04, 0.95)
	bg.set_border_width_all(1)
	bg.border_color = Color(0.84, 0.70, 0.45, 0.60)
	bg.set_corner_radius_all(3)
	bg.border_width_left = 4
	bg.content_margin_left = 12
	bg.content_margin_right = 12
	bg.content_margin_top = 3
	bg.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", bg)

	var hbox = HBoxContainer.new()
	panel.add_child(hbox)

	var key = Label.new()
	key.text = "DPS"
	key.add_theme_font_size_override("font_size", 11)
	key.add_theme_color_override("font_color", TEXT_DIM)
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(key)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var value = Label.new()
	value.text = UITheme.format_num(dps)
	value.add_theme_font_size_override("font_size", 22)
	value.add_theme_color_override("font_color", Color(0.95, 0.82, 0.42))
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(value)
	return panel

func _build_resource_bar(label: String, value: float, max_value: float, fill: Color, track: Color) -> Control:
	var outer = HBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)

	var lbl = Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(54, 0)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", TEXT_DIM)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	outer.add_child(lbl)

	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.max_value = max(1.0, max_value)
	bar.value = clamp(value, 0.0, max_value)

	var bar_bg = StyleBoxFlat.new()
	bar_bg.bg_color = track
	bar_bg.set_corner_radius_all(2)
	bar_bg.set_border_width_all(1)
	bar_bg.border_color = fill.lerp(Color.BLACK, 0.6)
	var bar_fill = StyleBoxFlat.new()
	bar_fill.bg_color = fill
	bar_fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bar_bg)
	bar.add_theme_stylebox_override("fill", bar_fill)
	outer.add_child(bar)

	var v_lbl = Label.new()
	v_lbl.text = "%s / %s" % [UITheme.format_num(value), UITheme.format_num(max_value)]
	v_lbl.custom_minimum_size = Vector2(110, 0)
	v_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v_lbl.add_theme_font_size_override("font_size", 11)
	v_lbl.add_theme_color_override("font_color", fill.lerp(Color.WHITE, 0.35))
	outer.add_child(v_lbl)
	return outer

func _build_grid_bar(used: float, cap: float, margin: float) -> Control:
	var outer = HBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)

	var lbl = Label.new()
	lbl.text = "⚡ GRID"
	lbl.custom_minimum_size = Vector2(54, 0)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", TEXT_DIM)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	outer.add_child(lbl)

	# Overload/warning/normal coloring drives both the bar and the margin readout.
	var fill_color: Color
	var margin_color: Color
	var margin_prefix: String
	if margin < 0:
		fill_color = Color(1.0, 0.38, 0.34)
		margin_color = Color(1.0, 0.45, 0.38)
		margin_prefix = "OVERLOAD"
	elif used > cap * 0.8:
		fill_color = Color(1.0, 0.74, 0.31)
		margin_color = Color(1.0, 0.80, 0.42)
		margin_prefix = "MARGIN +%d kW" % int(margin)
	else:
		fill_color = Color(0.84, 0.70, 0.45)
		margin_color = Color(0.80, 0.95, 0.55)
		margin_prefix = "MARGIN +%d kW" % int(margin)

	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.max_value = max(1.0, cap)
	bar.value = clamp(used, 0.0, cap)
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.08, 0.06, 1.0)
	bg.set_corner_radius_all(2)
	bg.set_border_width_all(1)
	bg.border_color = fill_color.lerp(Color.BLACK, 0.6)
	var fill = StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	outer.add_child(bar)

	var margin_lbl = Label.new()
	# Merge the used/cap readout into the margin line so the GRID bar fits in a single row.
	if margin >= 0:
		margin_lbl.text = "%d / %d  ·  %s" % [int(used), int(cap), margin_prefix]
	else:
		margin_lbl.text = "%d / %d  ·  %s" % [int(used), int(cap), margin_prefix]
	margin_lbl.custom_minimum_size = Vector2(160, 0)
	margin_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	margin_lbl.add_theme_font_size_override("font_size", 10)
	margin_lbl.add_theme_color_override("font_color", margin_color)
	outer.add_child(margin_lbl)
	return outer

func _build_supporting_stats_row(atk: float, def: float, acc: float, crit_pct: float, eva: float) -> Control:
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", 14)

	var chips = [
		{"k": "ATK",  "v": UITheme.format_num(atk),       "col": Color(0.95, 0.57, 0.38)},
		{"k": "DEF",  "v": UITheme.format_num(def),       "col": Color(0.79, 0.74, 0.66)},
		{"k": "ACC",  "v": str(int(acc)),                  "col": Color(0.85, 0.81, 0.74)},
		{"k": "CRIT", "v": "%.0f%%" % crit_pct,            "col": Color(0.93, 0.47, 0.38)},
		{"k": "EVA",  "v": "%.0f" % eva,                   "col": Color(0.86, 0.84, 0.47)}
	]
	for c in chips:
		var chip = HBoxContainer.new()
		chip.add_theme_constant_override("separation", 4)

		var k = Label.new()
		k.text = c["k"]
		k.add_theme_font_size_override("font_size", 9)
		k.add_theme_color_override("font_color", TEXT_DIM)
		k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(k)

		var v = Label.new()
		v.text = c["v"]
		v.add_theme_font_size_override("font_size", 12)
		v.add_theme_color_override("font_color", c["col"])
		v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(v)

		row.add_child(chip)
	return row

func _build_sets_active_panel() -> Control:
	# Walk currently-equipped modules and group by set_id.
	var counts: Dictionary = {}
	for slot in manager.loadout:
		var mid = manager.loadout[slot]
		if not mid: continue
		var data = manager.modules.get(mid, {})
		var sid = data.get("set_id", "")
		if sid == "" and data.get("is_custom") and data.has("base_module"):
			sid = manager.modules.get(data["base_module"], {}).get("set_id", "")
		if sid == "": continue
		counts[sid] = counts.get(sid, 0) + 1

	if counts.is_empty(): return null
	if not GameState.combat_manager or not "TRINITY_SET_BONUSES" in GameState.combat_manager:
		return null
	var s_db = GameState.combat_manager.TRINITY_SET_BONUSES

	# Compact single-line-per-set panel. Bonus details moved to per-line tooltips.
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.10, 0.85)
	style.set_corner_radius_all(2)
	style.border_width_left = 2
	style.border_color = Color(0.0, 0.80, 0.85, 0.55)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	panel.add_child(vbox)

	var sids = counts.keys()
	sids.sort_custom(func(a, b):
		var pa = s_db.get(a, {}).get("pieces", 99)
		var pb = s_db.get(b, {}).get("pieces", 99)
		var active_a = counts[a] >= pa
		var active_b = counts[b] >= pb
		if active_a != active_b: return active_a
		return counts[a] > counts[b])

	for sid in sids:
		if not s_db.has(sid): continue
		var info = s_db[sid]
		var have = counts[sid]
		var total = info["pieces"]
		var active = have >= total

		var line = HBoxContainer.new()
		line.add_theme_constant_override("separation", 5)
		vbox.add_child(line)

		var pips = ""
		for i in range(total):
			pips += ("◆" if i < have else "◇")
		var pip_lbl = Label.new()
		pip_lbl.text = pips
		pip_lbl.add_theme_font_size_override("font_size", 10)
		pip_lbl.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.30) if active else Color(0.65, 0.65, 0.70))
		line.add_child(pip_lbl)

		var name_lbl = Label.new()
		name_lbl.text = info["name"]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color",
			Color(1.0, 0.92, 0.55) if active else Color(0.78, 0.78, 0.86))
		line.add_child(name_lbl)

		var status_lbl = Label.new()
		if active:
			status_lbl.text = "ACTIVE"
			status_lbl.add_theme_color_override("font_color", Color(0.45, 1.00, 0.55))
		else:
			status_lbl.text = "%d/%d" % [have, total]
			status_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70))
		status_lbl.add_theme_font_size_override("font_size", 9)
		line.add_child(status_lbl)

		# Build a rich tooltip for hover instead of inflating the page with sub-lines.
		var tt := "%s   %d / %d pieces\n" % [info["name"], have, total]
		for bk in info["bonus"]:
			var bv = info["bonus"][bk]
			var bn = bk.replace("_pct", "").replace("_flat", "").replace("_", " ")
			var bv_str = "+%d%%" % bv if ("_pct" in bk or "crit" in bk) else "+%d" % bv
			tt += "  • %s  %s\n" % [bn, bv_str]
		if not active:
			tt += "(%d more piece%s to activate)" % [total - have, "s" if (total - have) > 1 else ""]
		else:
			tt += "ACTIVE"
		line.mouse_filter = Control.MOUSE_FILTER_STOP
		line.tooltip_text = tt

	return panel

func _on_ship_title_input(event: InputEvent):
	if not (event is InputEventMouseButton): return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	var build_name = _get_active_build_name()
	if build_name == "": return  # Nothing to rename — save a preset first
	_open_build_rename_dialog(build_name)

func _open_build_rename_dialog(current_name: String):
	var dlg = AcceptDialog.new()
	dlg.title = "Rename Build"
	dlg.min_size = Vector2(320, 0)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	var hint = Label.new()
	hint.text = "Rename the active loadout preset:"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", TEXT_DIM)
	box.add_child(hint)

	var input = LineEdit.new()
	input.text = current_name
	input.placeholder_text = "Build name…"
	input.custom_minimum_size = Vector2(240, 0)
	input.select_all_on_focus = true
	box.add_child(input)

	dlg.add_child(box)
	dlg.confirmed.connect(func():
		var new_name = input.text.strip_edges()
		if new_name == "": return
		for idx in manager.loadout_presets:
			var p = manager.loadout_presets[idx]
			if _loadout_matches_preset(p):
				p["name"] = new_name
				break
		manager.inventory_updated.emit()
		trigger_refresh())
	dlg.tree_exited.connect(func(): dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()
	input.grab_focus()

func _get_active_build_name() -> String:
	# Returns the preset name if the current loadout exactly matches one of the saved presets.
	if not manager or not "loadout_presets" in manager: return ""
	for idx in manager.loadout_presets:
		var preset = manager.loadout_presets[idx]
		if _loadout_matches_preset(preset):
			return preset.get("name", "")
	return ""

func _loadout_matches_preset(preset: Dictionary) -> bool:
	var preset_load = preset.get("loadout", {})
	# Empty preset can never match
	var preset_has_content = false
	for k in preset_load:
		var v = preset_load[k]
		if v != null and v != "":
			preset_has_content = true
			break
	if not preset_has_content: return false

	# Build normalized maps of slot_idx → mid (skipping null/empty)
	var cur := {}
	for s in manager.loadout:
		var m = manager.loadout[s]
		if m: cur[int(s)] = m
	var psh := {}
	for s in preset_load:
		var m = preset_load[s]
		if m: psh[int(s)] = m
	if cur.size() != psh.size(): return false
	for k in cur:
		if not psh.has(k) or psh[k] != cur[k]: return false
	return true

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
	all_slot_widgets.clear()
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
			all_slot_widgets.append(widget)

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
		match armory_sort_mode:
			1:  # Zone
				var za = data_a.get("zone", data_a.get("zone_difficulty", 0))
				var zb = data_b.get("zone", data_b.get("zone_difficulty", 0))
				if za != zb: return za > zb
			2:  # Rarity
				var ra = data_a.get("rarity", 0)
				var rb = data_b.get("rarity", 0)
				if ra != rb: return ra > rb
		return _get_module_power_score(a, data_a) > _get_module_power_score(b, data_b)
	)

	for module_id in sorted_mids:
		var module_count = inv[module_id]
		if module_count > 0 and module_id in manager.modules:
			var module_data = manager.modules[module_id]
			if _is_module_visible_for_filter(module_data) and _module_matches_search(module_id, module_data):
				var item = draggable_icon_scene.instantiate()
				storage_grid.add_child(item)
				var module_slot_type = module_data.get("slot_type", "")
				var type_matches_focus = focused_slot_type != "" and module_slot_type == _slot_type_to_filter(focused_slot_type)
				# Set selection + comparison baseline BEFORE setup() so the
				# first _update_ui() draws the ▲/▼/= chevron. (Previously these
				# were set after setup() with no redraw, so the chevron only
				# appeared on newly-dropped cards that got a second _update_ui()
				# on hover.) Only same-type modules compare against the focused
				# slot's equipped module so the indicator stays meaningful.
				item.is_selected = module_id in selected_mids
				item.is_draggable = not is_selection_mode
				if "compare_equipped_mid" in item:
					item.compare_equipped_mid = focused_slot_equipped_mid if type_matches_focus else ""
				item.setup(module_id, module_data, module_count)
				item.clicked.connect(_on_card_clicked)
				if focused_slot_type != "" and not type_matches_focus:
					item.modulate = Color(1, 1, 1, 0.35)
				slot_count += 1

	if active_filter in ["all", "ordnance", "ord"]:
		for ammo_id in ORDNANCE_AMMO_IDS:
			var qty = GameState.resources.get_element_amount(ammo_id)
			if qty > 0:
				var display_name = ElementDB.get_display_name(ammo_id)
				var fake_data = {"name": display_name, "slot_type": "ammo", "stats": {}}
				if not _module_matches_search(ammo_id, fake_data):
					continue
				var ammo_card = draggable_icon_scene.instantiate()
				storage_grid.add_child(ammo_card)
				ammo_card.setup(ammo_id, fake_data, qty)
				ammo_card.is_selected = ammo_id in selected_mids
				ammo_card.clicked.connect(_on_card_clicked)
				slot_count += 1

	if active_filter in ["all", "ordnance", "ord"]:
		var consumables = ElementDB.get_elements_in_category("consumables")
		for consumable_id in consumables:
			var qty = GameState.resources.get_element_amount(consumable_id)
			if qty > 0:
				var consumable_data = ElementDB.get_consumable_data(consumable_id)
				var display_name = consumable_data.get("name", consumable_id)
				var consumable_type = consumable_data.get("type", "hull")
				var fake_data = {
					"name": display_name,
					"slot_type": "consumable",
					"consumable_type": consumable_type,
					"stats": {"heal_pct": consumable_data.get("heal_pct", 0)}
				}
				if not _module_matches_search(consumable_id, fake_data):
					continue
				var consumable_card = draggable_icon_scene.instantiate()
				storage_grid.add_child(consumable_card)
				consumable_card.setup(consumable_id, fake_data, qty)
				consumable_card.is_selected = consumable_id in selected_mids
				consumable_card.clicked.connect(_on_card_clicked)
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

func _module_matches_search(mid: String, module_data: Dictionary) -> bool:
	# Empty search shows everything.
	var raw = armory_search_text.strip_edges().to_lower()
	if raw == "": return true
	# Whitespace-split tokens are AND-combined. Operator tokens look like "tier:3".
	for term in raw.split(" ", false):
		var t = term.strip_edges()
		if t == "": continue
		if not _module_matches_term(mid, module_data, t):
			return false
	return true

func _module_matches_term(mid: String, module_data: Dictionary, term: String) -> bool:
	# Operators: tier:N / set:X / slot:Y / rarity:Z
	if ":" in term:
		var parts = term.split(":", true, 1)
		if parts.size() == 2:
			var op = parts[0]
			var val = parts[1]
			match op:
				"tier", "zone":
					var z = int(module_data.get("zone", module_data.get("zone_difficulty", 0)))
					return z == int(val) if val.is_valid_int() else false
				"set":
					var sid = str(module_data.get("set_id", ""))
					if sid == "" and module_data.get("is_custom") and module_data.has("base_module"):
						var base = manager.modules.get(module_data["base_module"], {})
						sid = str(base.get("set_id", ""))
					return val in sid.to_lower()
				"slot", "type":
					return val == str(module_data.get("slot_type", "")).to_lower()
				"rarity":
					var rname = ""
					match int(module_data.get("rarity", 0)):
						0: rname = "common"
						1: rname = "uncommon"
						2: rname = "rare"
						3: rname = "legendary"
						4: rname = "unique"
					return val in rname
	# Plain text: match module display name (and module id as fallback).
	var name = str(module_data.get("name", mid)).to_lower()
	if term in name: return true
	if term in mid.to_lower(): return true
	return false

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
func _on_card_clicked(p_mid: String):
	if not is_selection_mode:
		return
		
	if p_mid in selected_mids:
		selected_mids.erase(p_mid)
	else:
		selected_mids.append(p_mid)
	_update_bulk_ui()
	rebuild_storage()

func _update_bulk_ui():
	if btn_demolish_selected:
		btn_demolish_selected.text = "DEMOLISH SELECTED (%d)" % selected_mids.size()
		btn_demolish_selected.disabled = selected_mids.is_empty()

func _on_demolish_selected_pressed():
	if selected_mids.is_empty(): return
	
	# v85.0: Copy to avoid mutation issues
	var to_demolish = selected_mids.duplicate()
	for mid in to_demolish:
		manager.demolish_module(mid)
	
	selected_mids.clear()
	_update_bulk_ui()
	rebuild_storage()
