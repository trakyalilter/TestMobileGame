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

@onready var storage_grid: GridContainer = $VBoxContainer/MainLayout/RightPanel/Margin/VBox/Scroll/GutterMargin/UnifiedStorageGrid
const SpatialInventory = preload("res://scripts/ui/spatial_inventory.gd")
# v111.17 Phase 1: PoE-style spatial Armory. storage_grid (GridContainer) is
# repurposed to hold a single SpatialInventory canvas that footprint-packs the
# tiles (modules 2x2, cores/ammo/consumables 1x1).
var _spatial: Control = null
# v111.18 Phase 2b: page navigation for the paginated spatial Armory.
var _page_nav: HBoxContainer = null
var _page_prev_btn: Button = null
var _page_next_btn: Button = null
var _page_lbl: Label = null
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
var bulk_actions_container: HFlowContainer
var is_selection_mode: bool = false

var focused_slot_idx: int = -1
var focused_slot_type: String = ""
var focused_slot_equipped_mid: String = ""
# P1 Onboarding: coach-driven filter that dims non-matching Armory modules
# while an equip mission is active. Separate from focused_slot_type so the
# user's manual slot click always wins over the coach hint.
var _equip_focus_filter_type: String = ""
var all_slot_widgets: Array = []
var armory_sort_mode: int = 0  # 0=Power, 1=Zone, 2=Rarity
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

# v111.15: full-word labels (no more WPN/SHD/ARM abbreviations) and the old
# combined "ordnance" filter split into separate AMMO + CONSUMABLES tabs.
const FILTER_ORDER := ["all", "weapon", "shield", "armor", "engine", "battery", "utility", "ammo", "consumables", "matrix"]
const FILTER_LABELS := {
	"all": "ALL",
	"weapon": "WEAPONS",
	"shield": "SHIELDS",
	"armor": "ARMOR",
	"engine": "ENGINES",
	"battery": "BATTERIES",
	"utility": "UTILITY",
	"ammo": "AMMO",
	"consumables": "CONSUMABLES",
	"matrix": "MATRIX",
}
const FILTER_TOOLTIPS := {
	"all": "Show all modules, ammo, and consumables.",
	"weapon": "Weapon modules.",
	"shield": "Shield modules.",
	"armor": "Armor modules.",
	"engine": "Engine modules.",
	"battery": "Battery modules.",
	"utility": "Sensors, reactors, cooling, and other utility modules.",
	"ammo": "Ammunition for weapons.",
	"consumables": "Hull and shield consumables.",
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
	# Reuse the existing scene "OrdnanceTab" node for AMMO; ConsumablesTab is
	# created dynamically by _setup_filter_tabs (not in the .tscn).
	"ammo": {"node": "OrdnanceTab", "accent": Color(0.93, 0.64, 0.42)},
	"consumables": {"node": "ConsumablesTab", "accent": Color(0.55, 0.85, 0.55)},
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

	# P1 Onboarding: persistent drag-drop hint banner — auto-dismisses on the
	# player's first successful equip. Hooked here so it appears on first
	# Designer visit and never re-appears once dismissed.
	_build_drag_hint_banner_if_needed()
	if manager and not manager.inventory_updated.is_connected(_check_drag_hint_dismissal):
		manager.inventory_updated.connect(_check_drag_hint_dismissal)

	trigger_refresh()

# --- P1 Onboarding: equip-mission Armory filter ---
# Coach calls these when an equip mission is active so the just-crafted
# module visually pops vs the rest of the inventory. Guarded — calling with
# the same value is a no-op so per-frame calls from the coach refresh stay
# cheap.
func set_equip_focus_filter(slot_type: String) -> void:
	if _equip_focus_filter_type == slot_type:
		return
	_equip_focus_filter_type = slot_type
	rebuild_storage()

func clear_equip_focus_filter() -> void:
	if _equip_focus_filter_type == "":
		return
	_equip_focus_filter_type = ""
	rebuild_storage()

# --- P1 Onboarding: drag-drop hint banner ---
var _drag_hint_banner: Control = null

func _build_drag_hint_banner_if_needed() -> void:
	if GameState.game_settings.get("designer_drag_hint_seen", false):
		return
	var banner = PanelContainer.new()
	banner.name = "DragHintBanner"
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.13, 0.08, 0.92)
	sb.border_color = Color(0.95, 0.86, 0.55, 0.70)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	banner.add_theme_stylebox_override("panel", sb)
	var lbl = Label.new()
	lbl.text = "💡  Drag modules from your Armory (right panel) onto ship slots to equip them. This hint disappears after your first equip."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.86, 0.55))
	banner.add_child(lbl)
	var vbox = $VBoxContainer
	vbox.add_child(banner)
	# Slot just below the title (index 0). Banner ends up above InfoPanel.
	vbox.move_child(banner, 1)
	_drag_hint_banner = banner

func _check_drag_hint_dismissal() -> void:
	if not _drag_hint_banner:
		return
	if GameState.game_settings.get("designer_drag_hint_seen", false):
		return
	if not manager:
		return
	var has_any: bool = false
	for slot_mid in manager.loadout.values():
		if slot_mid != null and slot_mid != "":
			has_any = true
			break
	if has_any:
		GameState.game_settings["designer_drag_hint_seen"] = true
		GameState.save_game()
		_drag_hint_banner.queue_free()
		_drag_hint_banner = null

var _consumable_blade: Control = null
var _consumable_hull_slot: Control = null
var _consumable_shield_slot: Control = null
var _last_focus_slot: String = ""

func get_coach_anchor(key: String) -> Control:
	match key:
		"schematic":
			return schematic_area
		"power":
			return power_bar
		"consumables":
			return _consumable_blade if _consumable_blade else schematic_area
	return null

func on_page_enter():
	# Re-arm scroll-to so re-entering during an equip mission re-centres.
	_last_focus_slot = ""

# Return the slot widget an equip mission should point at: the first EMPTY
# slot of the given type (weapon/shield/armor/...), or the dedicated
# consumable slot. Falls back to the first slot of that type.
func get_slot_widget(slot_type: String) -> Control:
	if slot_type == "consumable_hull":
		return _consumable_hull_slot
	if slot_type == "consumable_shield":
		return _consumable_shield_slot
	var fallback: Control = null
	for w in all_slot_widgets:
		if not is_instance_valid(w): continue
		if w.slot_type != slot_type: continue
		if fallback == null: fallback = w
		var eq = ""
		if manager: eq = manager.loadout.get(w.slot_idx, "")
		if eq == null or eq == "":
			return w
	return fallback

# Scroll the relevant slot into view. Called every frame by the nav-hint
# system, so only act when the target slot type actually changes.
func focus_slot(slot_type: String) -> void:
	if slot_type == "" or slot_type == _last_focus_slot:
		return
	var w = get_slot_widget(slot_type)
	if not w:
		return
	_last_focus_slot = slot_type
	var sc = get_node_or_null("VBoxContainer/MainLayout/SchematicArea/LayoutSplit/SlotListPanel/SlotScroll")
	if sc is ScrollContainer:
		sc.call_deferred("ensure_control_visible", w)

func _apply_designer_styles():
	title_lbl.add_theme_color_override("font_color", TITLE_GOLD)
	title_lbl.add_theme_font_size_override("font_size", 24)

	ship_name_lbl.add_theme_color_override("font_color", TITLE_GOLD)
	ship_name_lbl.add_theme_font_size_override("font_size", 22)
	power_lbl.add_theme_color_override("font_color", TEXT_MAIN)

	# Standalone ARMORY title folded into the toolbar row (chrome diet) so
	# it no longer eats a full strip above the grid.
	bay_lbl.visible = false

	_apply_frame_style(info_panel, FRAME_BG, FRAME_EDGE)
	_apply_frame_style(schematic_area, Color(0.08, 0.06, 0.05, 0.96), Color(0.37, 0.27, 0.19, 0.92))
	_apply_frame_style(right_panel, Color(0.08, 0.06, 0.05, 0.96), Color(0.47, 0.32, 0.19, 0.92))
	# Themed CardChrome on the three big container panels (like the main
	# menu). _apply_frame_style sets no content_margin and these are
	# PanelContainers with nested-container content, so the chrome spans the
	# true panel edges with no inset. Gold tint matches the page identity.
	UITheme._attach_chrome(info_panel, TITLE_GOLD)
	UITheme._attach_chrome(schematic_area, TITLE_GOLD)
	UITheme._attach_chrome(right_panel, TITLE_GOLD)
	_apply_tab_frame_style()
	_apply_power_bar_style()
	_refresh_filter_button_styles()
	
	# v111.17 Phase 1: the GridContainer now just hosts the spatial canvas, which
	# footprint-packs the tiles itself. One column, no separation = pure host.
	storage_grid.columns = 1
	storage_grid.add_theme_constant_override("h_separation", 0)
	storage_grid.add_theme_constant_override("v_separation", 0)
	_spatial = SpatialInventory.new()
	_spatial.name = "SpatialInventory"
	# Fill the column width (no side margins); cells size to the available width.
	_spatial.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spatial.cell_clicked.connect(_on_grid_cell_clicked)
	_spatial.pages_changed.connect(_on_pages_changed)
	storage_grid.add_child(_spatial)
	_setup_page_nav()


func _setup_filter_tabs():
	tab_buttons.clear()
	for filter_id in FILTER_ORDER:
		var node_name = FILTER_CONFIG[filter_id]["node"]
		var button = tab_strip.get_node_or_null(node_name)
		if button and button is Button:
			tab_buttons[filter_id] = button
			(button as Button).pressed.connect(_on_filter_pressed.bind(filter_id))
			(button as Button).tooltip_text = FILTER_TOOLTIPS.get(filter_id, "")
		elif tab_strip.get_child_count() > 0:
			# v111.15: dynamically create any tab missing from the .tscn
			# (matrix, consumables). Duplicates the first tab button for
			# consistent styling, then wires it.
			var first_btn = tab_strip.get_child(0)
			var new_btn = first_btn.duplicate()
			new_btn.name = FILTER_CONFIG[filter_id]["node"]
			tab_strip.add_child(new_btn)
			tab_buttons[filter_id] = new_btn
			new_btn.pressed.connect(_on_filter_pressed.bind(filter_id))
			new_btn.tooltip_text = FILTER_TOOLTIPS.get(filter_id, "")
	_refresh_tab_labels()

func _setup_bulk_actions():
	# v111.16: HFlowContainer (not HBox) so the action buttons WRAP within the
	# Armory's fixed-width column instead of forcing it wider. Previously, toggling
	# selection mode added "DEMOLISH SELECTED" + "CLEAR" to a non-wrapping HBox,
	# whose min width (~700px) inflated RightPanel and stretched every grid cell.
	# Wrapping keeps the panel at its 336px design width in every state.
	bulk_actions_container = HFlowContainer.new()
	bulk_actions_container.alignment = FlowContainer.ALIGNMENT_END
	bulk_actions_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bulk_actions_container.add_theme_constant_override("h_separation", 10)
	bulk_actions_container.add_theme_constant_override("v_separation", 6)
	
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

	# v111.7: storage_grid now lives inside a GutterMargin (reserves space for
	# the v-scrollbar so cells don't run under it). Hop one extra .get_parent()
	# to reach the Scroll and the surrounding VBox.
	var scroll = storage_grid.get_parent().get_parent()
	var v_box = scroll.get_parent()

	# v111.16: "Equipping for: … | Currently: …" context banner removed — the
	# focused-slot highlight plus the slot's own tooltip already communicate
	# which slot is being equipped, so the extra header row was redundant clutter.

	# Sort mode buttons
	var sort_row = HBoxContainer.new()
	sort_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sort_row.add_theme_constant_override("separation", 6)
	# Superseded by the toolbar's Sort dropdown -- hide the whole row so it
	# doesn't reserve a separation gap above the grid.
	sort_row.visible = false
	v_box.add_child(sort_row)
	v_box.move_child(sort_row, scroll.get_index())

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
	_setup_loadout_preset_row(v_box, sort_row.get_index())

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

	# Inline title (replaces the standalone ARMORY strip).
	var title = Label.new()
	title.text = "ARMORY"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.95, 0.80, 0.30))
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toolbar.add_child(title)

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
	normal.set_corner_radius_all(4)
	normal.set_border_width_all(1)
	var n_edge: Color = accent
	n_edge.a = 0.32
	normal.border_color = n_edge
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5

	var hover := normal.duplicate()
	hover.bg_color = accent.lerp(Color.BLACK, 0.74)
	var h_edge: Color = accent
	h_edge.a = 0.6
	hover.border_color = h_edge

	var pressed := normal.duplicate()
	pressed.bg_color = accent.lerp(Color.BLACK, 0.55)
	pressed.border_color = accent
	pressed.border_width_top = 2
	pressed.shadow_color = Color(accent.r, accent.g, accent.b, 0.28)
	pressed.shadow_size = 5

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
	normal.set_corner_radius_all(4)
	normal.set_border_width_all(1)
	normal.border_color = TAB_EDGE
	normal.content_margin_left = 9
	normal.content_margin_right = 9
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5

	var focus := normal.duplicate()
	focus.border_color = Color(0.95, 0.78, 0.45, 0.95)
	focus.border_width_bottom = 2
	focus.shadow_color = Color(0.85, 0.70, 0.45, 0.18)
	focus.shadow_size = 4

	le.add_theme_stylebox_override("normal", normal)
	le.add_theme_stylebox_override("focus", focus)
	le.add_theme_color_override("font_color", TEXT_MAIN)
	le.add_theme_color_override("font_placeholder_color", TEXT_DIM)
	le.add_theme_color_override("caret_color", Color(0.85, 0.70, 0.45))

func _setup_loadout_preset_row(parent: Node, insert_idx: int):
	var preset_row = HBoxContainer.new()
	preset_row.alignment = BoxContainer.ALIGNMENT_CENTER
	preset_row.add_theme_constant_override("separation", 7)

	var label = Label.new()
	label.text = "LOADOUTS"
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", TEXT_DIM)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preset_row.add_child(label)

	# v111.16: 3 click-to-LOAD chips (1/2/3) + a single SAVE ▾ dropdown,
	# replacing the old 6-button SAVE/LOAD grid. Click a numbered chip to load
	# that preset; use SAVE ▾ to write the current build to a slot.
	_preset_load_buttons = []
	for i in [1, 2, 3]:
		var load_btn = Button.new()
		load_btn.text = "%d" % i
		load_btn.tooltip_text = "Load Preset %d" % i
		load_btn.custom_minimum_size = Vector2(34, 0)
		load_btn.pressed.connect(_on_preset_load.bind(i))
		load_btn.add_theme_font_size_override("font_size", 11)
		_apply_filter_button_style(load_btn, false, Color(0.95, 0.80, 0.30))
		preset_row.add_child(load_btn)
		_preset_load_buttons.append(load_btn)

	var save_menu = MenuButton.new()
	save_menu.text = "SAVE ▾"
	save_menu.tooltip_text = "Save the current ship build to a preset slot."
	save_menu.add_theme_font_size_override("font_size", 10)
	save_menu.flat = false
	_apply_filter_button_style(save_menu, false, Color(0.55, 0.85, 0.95))
	var save_popup = save_menu.get_popup()
	for i in [1, 2, 3]:
		save_popup.add_item("Save to Preset %d" % i, i)
	save_popup.id_pressed.connect(_on_preset_save)
	preset_row.add_child(save_menu)

	parent.add_child(preset_row)
	parent.move_child(preset_row, insert_idx)

	# v111.16: thin divider above the loadout row separates the filter band
	# (tabs) from the tools band (loadouts / sort / manage) so the toolbar
	# reads as two grouped zones instead of one undifferentiated stack.
	var divider = HSeparator.new()
	var dsb := StyleBoxLine.new()
	dsb.color = Color(0.45, 0.38, 0.30, 0.35)
	dsb.thickness = 1
	divider.add_theme_stylebox_override("separator", dsb)
	parent.add_child(divider)
	parent.move_child(divider, insert_idx)   # lands just above the preset row

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
	dlg.dialog_text = "Demolish %d non-equipped module(s)?\n\nYou will receive Liras, Spare Parts, and zone salvage." % count
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
	# v111.14.1: mutually exclusive with module-arm — focusing a slot clears
	# any armed module so the two highlight systems never show at once.
	if _armed_mid != "":
		_armed_mid = ""
		_clear_slot_highlights()
	for w in all_slot_widgets:
		if is_instance_valid(w): w.set_focus_highlight(false)
	focused_slot_idx = slot_idx
	focused_slot_type = s_type
	focused_slot_equipped_mid = equipped_mid
	for w in all_slot_widgets:
		if is_instance_valid(w) and w.slot_idx == slot_idx:
			w.set_focus_highlight(true)
			break
	# v111.15: removed auto-filter on slot focus — it yanked the armory to a
	# different tab on every slot click, which the player found disorienting.
	# The slot still highlights; the armory stays on whatever tab the player
	# chose. Clicking any compatible module still equips into the focused slot.

func _slot_type_to_filter(s_type: String) -> String:
	match s_type:
		"weapon": return "weapon"
		"shield": return "shield"
		"armor": return "armor"
		"engine": return "engine"
		"battery": return "battery"
		"reactor", "sensor", "cooling": return "utility"
		_: return s_type

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
	# v111.16: stronger active/inactive contrast so the active filter pops and
	# the other 9 recede instead of forming a same-weight wall.
	# Inactive = near-transparent ghost, very faint edge, dim text.
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.08, 0.07, 0.22)   # ghost (was 0.92)
	normal.set_corner_radius_all(4)
	normal.set_border_width_all(1)
	var dim_edge: Color = accent
	dim_edge.a = 0.16                                  # very faint (was 0.30)
	normal.border_color = dim_edge
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5

	var hover = normal.duplicate()
	hover.bg_color = accent.lerp(Color.BLACK, 0.70)
	var hb: Color = accent
	hb.a = 0.55
	hover.border_color = hb

	# Active: bright filled accent plate, lit top edge, strong accent halo —
	# unmistakably "this is the current filter".
	var selected = normal.duplicate()
	selected.bg_color = accent.lerp(Color.BLACK, 0.40)   # more accent (was 0.55)
	selected.bg_color.a = 1.0
	selected.border_color = accent
	selected.set_border_width_all(1)
	selected.border_width_top = 2
	selected.shadow_color = Color(accent.r, accent.g, accent.b, 0.45)
	selected.shadow_size = 7

	var disabled = normal.duplicate()
	disabled.bg_color = Color(0.09, 0.07, 0.06, 0.18)
	disabled.border_color = Color(0.25, 0.20, 0.18, 0.30)

	button.add_theme_stylebox_override("normal", selected if is_active else normal)
	button.add_theme_stylebox_override("hover", selected if is_active else hover)
	button.add_theme_stylebox_override("pressed", selected)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled", disabled)

	# Active text bright white-accent; inactive text deeply dimmed so it reads
	# as a quiet option, not a competing label.
	button.add_theme_color_override("font_color",
		accent.lerp(Color.WHITE, 0.88) if is_active else accent.lerp(TEXT_DIM, 0.72))
	button.add_theme_color_override("font_hover_color", accent.lerp(Color.WHITE, 0.65))
	button.add_theme_color_override("font_pressed_color", accent.lerp(Color.WHITE, 0.9))
	button.add_theme_color_override("font_disabled_color", Color(0.40, 0.36, 0.33))
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
	# v110: ship energy capacity is the shipyard's own field now.
	var e_cap = float(manager.energy_capacity)
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
	lbl.text = "GRID"
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
		margin_prefix = "MARGIN +%d" % int(margin)
	else:
		fill_color = Color(0.84, 0.70, 0.45)
		margin_color = Color(0.80, 0.95, 0.55)
		margin_prefix = "MARGIN +%d" % int(margin)

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

		var line = _SetTooltip.new()
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

		# Feed the custom rich tooltip (styled, LOCKED/ACTIVE state, pips).
		var blines: Array = []
		for bk in info["bonus"]:
			var bv = info["bonus"][bk]
			var bn: String = bk.replace("_pct", "").replace("_flat", "").replace("_", " ").capitalize()
			var bv_str: String = "%d%%" % bv if ("_pct" in bk or "crit" in bk) else "%d" % bv
			blines.append([bn, bv_str])
		line.tip_title = info["name"]
		line.accent = Color(1.0, 0.85, 0.30) if active else Color(0.20, 0.84, 0.90)
		line.have = have
		line.total = total
		line.is_active = active
		line.bonus_lines = blines
		line.mouse_filter = Control.MOUSE_FILTER_STOP
		# No tooltip_text on purpose: _SetTooltip shows its own styled hover
		# popup, so Godot's default (boxed) tooltip never fires.

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
	_consumable_blade = blade_panel  # coach/nav-hint anchor for Combat Triage

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
	_consumable_hull_slot = hull_slot

	var shield_slot = slot_widget_scene.instantiate()
	flow.add_child(shield_slot)
	shield_slot.setup(-1, "consumable_shield", self, manager)
	_consumable_shield_slot = shield_slot

func rebuild_ammo_slots():
	pass

var _storage_rebuild_pending := false

func _rebuild_storage_after_drag() -> void:
	# Wait out the drag, then do the deferred rebuild exactly once.
	while is_inside_tree() and get_viewport().gui_is_dragging():
		await get_tree().create_timer(0.15).timeout
	if is_inside_tree():
		_storage_rebuild_pending = false
		rebuild_storage()
	else:
		_storage_rebuild_pending = false

func rebuild_storage():
	if not is_inside_tree():
		return
	# v111.17: spatial canvas is created in _apply_designer_styles(); bail if a
	# signal fires a rebuild before that runs.
	if _spatial == null:
		return
	# CRASH FIX: never free/rebuild armory cards while a drag is in progress.
	# inventory_updated (combat loot, craft, equip, etc.) can fire mid-drag;
	# rebuilding here queue_free()s the very node being dragged, which Godot's
	# drag machinery then dereferences -> intermittent crash. Defer instead.
	if get_viewport().gui_is_dragging():
		if not _storage_rebuild_pending:
			_storage_rebuild_pending = true
			_rebuild_storage_after_drag()
		return
	_storage_rebuild_pending = false

	var slot_count = 0
	# v111.17 Phase 1: clear the spatial canvas (NOT storage_grid, whose only
	# child is the canvas itself).
	_spatial.begin()

	var inv = manager.module_inventory
	# v111.17: never show currently-equipped modules in the Armory. Build the set
	# of equipped module ids from the loadout and skip them below.
	var equipped_ids := {}
	for _s in manager.loadout:
		var _eq = manager.loadout[_s]
		if _eq != null and _eq != "":
			equipped_ids[_eq] = true
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
		if module_id in equipped_ids:
			continue   # equipped modules are hidden from the Armory
		var module_count = inv[module_id]
		if module_count > 0 and module_id in manager.modules:
			var module_data = manager.modules[module_id]
			if _is_module_visible_for_filter(module_data) and _module_matches_search(module_id, module_data):
				var item = draggable_icon_scene.instantiate()
				_spatial.add_item(item, 2, 2, manager.get_armory_pos(module_id))   # gear modules: 2x2
				var module_slot_type = module_data.get("slot_type", "")
				var type_matches_focus = focused_slot_type != "" and module_slot_type == _slot_type_to_filter(focused_slot_type)
				# Set selection + comparison baseline BEFORE setup() so the
				# first _update_ui() draws the ▲/▼/= chevron. (Previously these
				# were set after setup() with no redraw, so the chevron only
				# appeared on newly-dropped cards that got a second _update_ui()
				# on hover.) Only same-type modules compare against the focused
				# slot's equipped module so the indicator stays meaningful.
				# v111.14: drag fully retired (crash-prone). Cards are never
				# draggable now; equip happens via click-to-arm. The armed
				# module reuses the is_selected highlight so the player sees
				# which one is picked up.
				item.is_selected = (module_id in selected_mids) or (module_id == _armed_mid)
				item.is_draggable = false
				if "compare_equipped_mid" in item:
					item.compare_equipped_mid = focused_slot_equipped_mid if type_matches_focus else ""
				item.setup(module_id, module_data, module_count)
				item.clicked.connect(_on_card_clicked)
				# Dim non-matching modules. User-click focus wins (focused_slot_type);
				# otherwise the coach-driven equip-mission filter applies, so the
				# just-crafted module stands out vs the rest of the Armory.
				if focused_slot_type != "" and not type_matches_focus:
					item.modulate = Color(1, 1, 1, 0.35)
				elif focused_slot_type == "" and _equip_focus_filter_type != "" \
						and module_slot_type != _equip_focus_filter_type:
					item.modulate = Color(1, 1, 1, 0.35)
				slot_count += 1

	# v111.15: ammo now its own filter (split from the combined ordnance tab).
	if active_filter in ["all", "ammo"]:
		for ammo_id in ORDNANCE_AMMO_IDS:
			var qty = GameState.resources.get_element_amount(ammo_id)
			if qty > 0:
				var display_name = ElementDB.get_display_name(ammo_id)
				var fake_data = {"name": display_name, "slot_type": "ammo", "stats": {}}
				if not _module_matches_search(ammo_id, fake_data):
					continue
				var ammo_card = draggable_icon_scene.instantiate()
				_spatial.add_item(ammo_card, 1, 1, manager.get_armory_pos(ammo_id))
				ammo_card.setup(ammo_id, fake_data, qty)
				ammo_card.is_selected = ammo_id in selected_mids
				ammo_card.clicked.connect(_on_card_clicked)
				slot_count += 1

	# v111.15: consumables now their own filter (split from ordnance).
	if active_filter in ["all", "consumables"]:
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
				_spatial.add_item(consumable_card, 1, 1, manager.get_armory_pos(consumable_id))
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
				_spatial.add_item(core_card, 1, 1, manager.get_armory_pos(core_id))   # Matrix Core: 1x1
				var display_name = ElementDB.get_display_name(core_id)
				var fake_data = {
					"name": display_name,
					"slot_type": "gem", # Treating as gem for socketing
					"rarity": 3 if "Stable" in display_name else (4 if "Pristine" in display_name else 2),
					"stats": {},
					"desc": ElementDB.get_element_description(core_id)
				}
				# v111.16: cores are click-to-arm like modules (drag retired).
				# Clicking arms the core → an equipped module's empty matrix socket
				# (which glows) then accepts it on click.
				core_card.is_draggable = false
				core_card.is_selected = (core_id == _armed_mid)
				core_card.clicked.connect(_on_card_clicked)
				core_card.setup(core_id, fake_data, qty)
				slot_count += 1
	
	# Boss cores (Lunar, Asteroid, …) are research/crafting materials, NOT
	# equippable modules — they are shown in the Inventory page ("Other"),
	# not the Armory. Matrix cores above stay: those socket into gear.

	# v111.17 Phase 1: no more empty-slot filler tiles — the spatial canvas draws
	# its own empty cell-grid background. Lay everything out now.
	_spatial.commit()

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
		"ammo", "consumables", "ordnance", "ord":
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
	# Mirror rebuild_storage: equipped modules are hidden, so don't count them.
	var equipped_ids := {}
	for _s in manager.loadout:
		var _eq = manager.loadout[_s]
		if _eq != null and _eq != "":
			equipped_ids[_eq] = true
	for module_id in inv.keys():
		if module_id in equipped_ids:
			continue
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

	# v111.15: ammo + consumables counted separately for their own tabs.
	var ammo_count = 0
	for ammo_id in ORDNANCE_AMMO_IDS:
		if GameState.resources.get_element_amount(ammo_id) > 0:
			ammo_count += 1
	counts["ammo"] = ammo_count

	var consumable_count = 0
	var consumables = ElementDB.get_elements_in_category("consumables")
	for consumable_id in consumables:
		if GameState.resources.get_element_amount(consumable_id) > 0:
			consumable_count += 1
	counts["consumables"] = consumable_count

	# v83.9: Matrix Core Counts
	var core_count = 0
	var matrix_cores = ElementDB.get_elements_in_category("matrix_cores")
	for core_id in matrix_cores:
		if GameState.resources.get_element_amount(core_id) > 0:
			core_count += 1
	counts["matrix"] = core_count

	# Boss cores excluded from the Armory (they're Inventory materials).
	counts["all"] += ammo_count + consumable_count + core_count
	return counts

func _normalize_filter_id(filter_id: String) -> String:
	match filter_id:
		"wpn":
			return "weapon"
		"sys":
			return "systems"
		"ord", "ordnance":
			return "ammo"   # v111.15: legacy alias → new AMMO tab
		_:
			if filter_id in FILTER_ORDER:
				return filter_id
			if filter_id in ["systems", "explosive", "armor"]:
				return filter_id
			return "all"

func get_module_widget(module_id: String) -> Control:
	# v111.17: tiles now live under the spatial canvas, not storage_grid directly.
	var host: Node = _spatial if _spatial else storage_grid
	for child in host.get_children():
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
	# Demolish multi-select mode keeps its existing toggle behaviour.
	if is_selection_mode:
		if p_mid in selected_mids:
			selected_mids.erase(p_mid)
		else:
			selected_mids.append(p_mid)
		_update_bulk_ui()
		rebuild_storage()
		return

	# v111.14.1: bidirectional, mutually-exclusive equip.
	# SLOT-FIRST: if a slot is already focused (player clicked a slot, armory
	# filtered to compatible modules), clicking a module equips it straight
	# into that focused slot.
	if focused_slot_idx >= 0:
		_equip_to_focused_slot(p_mid)
		return
	# MODULE-FIRST: otherwise arm the module (compatible slots glow); click
	# again to cancel.
	if p_mid == _armed_mid:
		_disarm_module()
	else:
		_arm_module(p_mid)

# Slot-first path: equip the clicked module into the currently-focused slot.
func _equip_to_focused_slot(mid: String) -> void:
	for w in all_slot_widgets:
		if is_instance_valid(w) and w.slot_idx == focused_slot_idx:
			if w.has_method("equip_id") and w.equip_id(mid):
				UITheme.trigger_ui_thud(self, 1.0)
				# trigger_refresh already fired inside equip; keep slot focused
				# so the player can keep swapping modules into it rapidly.
				rebuild_storage()
			else:
				UITheme.show_notification("Can't equip there.", Color(1, 0.5, 0.4))
			return

# ── v111.14 click-to-equip armed-module state ─────────────────────────
var _armed_mid: String = ""

func is_module_armed() -> bool:
	return _armed_mid != ""

func get_armed_mid() -> String:
	return _armed_mid

func _arm_module(mid: String) -> void:
	# Mutually exclusive with slot-focus: arming a module clears any focused
	# slot so only one highlight system is ever active on screen.
	_clear_focused_slot()
	_armed_mid = mid
	_highlight_compatible_slots()
	rebuild_storage()      # re-render so the armed card shows its highlight

# Clears slot-focus state (highlight + filter banner) without re-rendering
# the armory. Safe to call when nothing is focused.
func _clear_focused_slot() -> void:
	if focused_slot_idx < 0 and focused_slot_type == "":
		return
	focused_slot_idx = -1
	focused_slot_type = ""
	focused_slot_equipped_mid = ""
	for w in all_slot_widgets:
		if is_instance_valid(w) and w.has_method("set_focus_highlight"):
			w.set_focus_highlight(false)

func _disarm_module() -> void:
	if _armed_mid == "":
		return
	_armed_mid = ""
	_clear_slot_highlights()
	rebuild_storage()

# v111.18 Phase 2: clicking an empty grid cell while an item is "picked up"
# (armed) relocates it there, on the CURRENTLY VIEWED page. Footprint: gear
# modules 2x2, everything else 1x1. The canvas re-packs unpinned items around it.
func _on_grid_cell_clicked(gx: int, gy: int) -> void:
	if _armed_mid == "" or _spatial == null:
		return
	var fp := 2 if manager.modules.has(_armed_mid) else 1
	if gx < 0 or gy < 0 or gx + fp > _spatial.cols or gy + fp > _spatial.page_rows:
		return
	manager.set_armory_pos(_armed_mid, _spatial.current_page, gx, gy)
	GameState.save_game()
	_disarm_module()   # clears the pick-up + rebuilds; the item now sits there

# v111.18 Phase 2b: compact "‹ Page i / N ›" nav row directly under the grid.
# Hidden while there is a single page; pages auto-increment as the grid fills.
func _setup_page_nav() -> void:
	var scroll = storage_grid.get_parent().get_parent()   # GutterMargin -> Scroll
	var v_box = scroll.get_parent()

	_page_nav = HBoxContainer.new()
	_page_nav.alignment = BoxContainer.ALIGNMENT_CENTER
	_page_nav.add_theme_constant_override("separation", 10)
	_page_nav.visible = false

	_page_prev_btn = Button.new()
	_page_prev_btn.text = "‹"
	_page_prev_btn.custom_minimum_size = Vector2(34, 26)
	_apply_filter_button_style(_page_prev_btn, false, Color(0.65, 0.60, 0.82))
	_page_prev_btn.pressed.connect(_on_page_prev)
	_page_nav.add_child(_page_prev_btn)

	_page_lbl = Label.new()
	_page_lbl.add_theme_font_size_override("font_size", 11)
	_page_lbl.add_theme_color_override("font_color", Color(0.78, 0.80, 0.88))
	_page_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_nav.add_child(_page_lbl)

	_page_next_btn = Button.new()
	_page_next_btn.text = "›"
	_page_next_btn.custom_minimum_size = Vector2(34, 26)
	_apply_filter_button_style(_page_next_btn, false, Color(0.65, 0.60, 0.82))
	_page_next_btn.pressed.connect(_on_page_next)
	_page_nav.add_child(_page_next_btn)

	v_box.add_child(_page_nav)
	v_box.move_child(_page_nav, scroll.get_index() + 1)   # directly under the grid

func _on_page_prev() -> void:
	if _spatial:
		_spatial.set_page(_spatial.current_page - 1)

func _on_page_next() -> void:
	if _spatial:
		_spatial.set_page(_spatial.current_page + 1)

func _on_pages_changed(count: int, current: int) -> void:
	if not is_instance_valid(_page_lbl):
		return
	_page_lbl.text = "Page %d / %d" % [current + 1, count]
	_page_prev_btn.disabled = current <= 0
	_page_next_btn.disabled = current >= count - 1
	_page_nav.visible = count > 1

# Called by a slot widget after it successfully equips the armed module.
func notify_equipped() -> void:
	_armed_mid = ""
	_clear_slot_highlights()
	rebuild_storage()

func _highlight_compatible_slots() -> void:
	for w in all_slot_widgets:
		if is_instance_valid(w) and w.has_method("set_equip_highlight") and w.has_method("can_accept_module"):
			w.set_equip_highlight(w.can_accept_module(_armed_mid))

func _clear_slot_highlights() -> void:
	for w in all_slot_widgets:
		if is_instance_valid(w) and w.has_method("set_equip_highlight"):
			w.set_equip_highlight(false)

func _unhandled_input(event: InputEvent) -> void:
	# Esc cancels whichever equip state is active (mutually exclusive).
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _armed_mid != "":
			_disarm_module()
			get_viewport().set_input_as_handled()
		elif focused_slot_idx >= 0:
			_clear_focused_slot()
			_on_filter_changed("all")    # restore the unfiltered armory
			get_viewport().set_input_as_handled()

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


# Rich, styled hover card for an equipped set — replaces the primitive
# default text tooltip. Shows progress pips and a clear LOCKED→ACTIVE state
# so the set reads as a collection goal, not a stat dump.
class _SetTooltip extends HBoxContainer:
	var tip_title: String = ""
	var accent: Color = Color(0.20, 0.84, 0.90)
	var have: int = 0
	var total: int = 3
	var is_active: bool = false
	var bonus_lines: Array = []  # [[name, value_str], ...]

	# Manual hover popup (NOT Godot's _make_custom_tooltip — that wraps the
	# control in the theme's TooltipPanel, which drew a translucent black box
	# behind our card). We render our own panel into ModalLayer instead.
	var _popup: PanelContainer = null

	func _ready() -> void:
		mouse_entered.connect(_show_tip)
		mouse_exited.connect(_hide_tip)
		tree_exiting.connect(_hide_tip)

	func _hide_tip() -> void:
		if is_instance_valid(_popup):
			_popup.queue_free()
		_popup = null

	func _show_tip() -> void:
		_hide_tip()
		_popup = _build_panel()
		var root := get_tree().current_scene
		var host: Node = null
		if root:
			host = root.get_node_or_null("ModalLayer")
			if host == null:
				host = root
		else:
			host = get_tree().root
		host.add_child(_popup)
		_popup.call_deferred("set", "position", _clamped_pos())

	func _clamped_pos() -> Vector2:
		var vp := get_viewport_rect().size
		var sz := _popup.size if is_instance_valid(_popup) else Vector2(280, 140)
		var p := get_global_mouse_position() + Vector2(18, 16)
		if p.x + sz.x > vp.x - 8: p.x = get_global_mouse_position().x - sz.x - 18
		if p.y + sz.y > vp.y - 8: p.y = vp.y - sz.y - 8
		p.x = max(8.0, p.x)
		p.y = max(8.0, p.y)
		return p

	func _build_panel() -> PanelContainer:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.08, 0.12, 0.98)
		sb.set_border_width_all(1)
		sb.border_width_top = 3
		sb.border_color = accent
		sb.set_corner_radius_all(5)
		sb.shadow_color = Color(0, 0, 0, 0.55)
		sb.shadow_size = 14
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		panel.add_theme_stylebox_override("panel", sb)

		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.scroll_active = false
		rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rt.custom_minimum_size = Vector2(264, 0)
		rt.add_theme_font_size_override("normal_font_size", 12)

		var hex := accent.to_html(false)
		var pips := ""
		for i in range(total):
			pips += "◆" if i < have else "◇"

		var s := "[b][color=#%s]%s[/color][/b]\n" % [hex, tip_title]
		s += "[color=#%s]%s[/color]  [color=#7a8190]%d / %d pieces[/color]\n" % [hex, pips, have, total]
		s += "[color=#2b3140]————————————————————[/color]\n"
		if is_active:
			s += "[b][color=#4FE08C]◆ SET BONUS ACTIVE[/color][/b]\n"
		else:
			var rem := total - have
			s += "[b][color=#FFB13D]◇ LOCKED[/color][/b]  [color=#9aa0ad]equip %d more piece%s[/color]\n" % [rem, ("s" if rem > 1 else "")]
		var line_col := "#cfe8d8" if is_active else "#6c7280"
		for bl in bonus_lines:
			s += "[color=%s]   +%s  %s[/color]\n" % [line_col, str(bl[1]), str(bl[0])]

		rt.text = s.strip_edges()
		panel.add_child(rt)
		return panel
