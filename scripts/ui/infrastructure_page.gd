extends Control

@onready var net_lbl = $VBoxContainer/Header/NetLabel
@onready var gen_lbl = $VBoxContainer/Header/StatsVBox/GenLabel
@onready var cons_lbl = $VBoxContainer/Header/StatsVBox/ConsLabel

@onready var energy_grid = $VBoxContainer/ScrollContainer/BladeContainer/EnergyRack/Grid
@onready var mining_grid = $VBoxContainer/ScrollContainer/BladeContainer/MiningRack/Grid
@onready var production_grid = $VBoxContainer/ScrollContainer/BladeContainer/ProductionRack/Grid

@onready var blade_container = $VBoxContainer/ScrollContainer/BladeContainer

var manager: RefCounted
var building_widget_scene = preload("res://scenes/ui/building_widget.tscn")
var widgets = []

var logistics_rack: VBoxContainer
var logistics_grid: GridContainer

# v116: category tabs (matches the processing page + armory filter bar). One
# rack visible at a time, toggled by a wrapping tab strip.
var _tab_strip: HFlowContainer
var _tab_buttons := {}      # {tab_id: Button}
var _tab_racks := {}        # {tab_id: rack VBoxContainer}
var _active_tab: String = ""
var TAB_DEFS := [
	{"id": "power",      "label": "Power",       "color": Color(1.00, 0.80, 0.20)},
	{"id": "extraction", "label": "Extraction",  "color": Color(1.00, 0.60, 0.20)},
	{"id": "industry",   "label": "Fabrication", "color": Color(0.20, 0.80, 1.00)},
	{"id": "logistics",  "label": "Logistics",   "color": Color(0.60, 0.40, 1.00)},
]

func _ready():
	manager = GameState.infrastructure_manager
	$VBoxContainer/ScrollContainer.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_setup_logistics_rack()
	_setup_tabs()
	_setup_multi_buy_toggles()
	_connect_signals()
	call_deferred("refresh_list")

var refresh_timer: SceneTreeTimer
var is_dirty: bool = false

func _connect_signals():
	GameState.resources.element_added.connect(_on_resources_changed)
	GameState.resources.element_removed.connect(_on_resources_changed)
	GameState.resources.currency_added.connect(_on_resources_changed)
	GameState.resources.currency_removed.connect(_on_resources_changed)
	GameState.resources.energy_changed.connect(_on_resources_changed)
	if manager.has_signal("building_constructed"):
		manager.building_constructed.connect(_on_resources_changed)
	# v137: refresh when the page is re-shown. While hidden, resource changes on other
	# pages schedule a refresh that _do_refresh drops (page not visible), so returning to
	# Infrastructure could show a stale "affordable" green on a now-unbuildable card.
	visibility_changed.connect(_on_visibility_shown)

func _on_visibility_shown() -> void:
	if is_visible_in_tree():
		queue_refresh()

func _on_resources_changed(_a=null, _b=null):
	queue_refresh()

func get_coach_anchor(key: String) -> Control:
	match key:
		"first_building":
			# Anchor to a VISIBLE building (active tab's first), not a hidden one.
			var g = _grid_for_tab(_active_tab)
			if g and g.get_child_count() > 0:
				return g.get_child(0)
			return widgets[0] if not widgets.is_empty() else null
		"energy":
			return net_lbl
	return null

func queue_refresh():
	if is_dirty: return
	# v134: resources_* are AUTOLOAD signals that keep firing even while this page is
	# OUT of the scene tree (e.g. warp charge removes an element every _process frame
	# while the player is on another page). get_tree() is null when detached — guard
	# BEFORE setting is_dirty, or a re-attached page stays permanently un-refreshable.
	if not is_inside_tree(): return
	is_dirty = true
	# Throttle: Max 5 updates per second (200ms)
	get_tree().create_timer(0.2).timeout.connect(_do_refresh)

func _do_refresh():
	is_dirty = false
	# is_visible_in_tree() (not bare `visible`) so a detached/hidden page never runs
	# update_ui() — which reaches into get_tree()/live nodes.
	if is_visible_in_tree():
		update_ui()

var btn_x1: Button
var btn_x10: Button
var btn_x100: Button

func _setup_multi_buy_toggles():
	var header = $VBoxContainer/Header
	var toggle_box = HBoxContainer.new()
	toggle_box.add_theme_constant_override("separation", 10)
	toggle_box.alignment = BoxContainer.ALIGNMENT_CENTER
	# Insert below StatsVBox
	header.add_child(toggle_box)
	
	btn_x1 = Button.new()
	btn_x1.text = tr("BUILD x1")
	btn_x1.toggle_mode = true
	btn_x1.button_pressed = true
	
	btn_x10 = Button.new()
	btn_x10.text = tr("BUILD x10")
	btn_x10.toggle_mode = true
	
	btn_x100 = Button.new()
	btn_x100.text = tr("BUILD x100")
	btn_x100.toggle_mode = true
	
	toggle_box.add_child(btn_x1)
	toggle_box.add_child(btn_x10)
	toggle_box.add_child(btn_x100)
	
	UITheme.apply_sharp_button_style(btn_x1, "infrastructure")
	UITheme.apply_sharp_button_style(btn_x10, "infrastructure")
	UITheme.apply_sharp_button_style(btn_x100, "infrastructure")
	
	btn_x1.pressed.connect(func(): _set_multiplier(1))
	btn_x10.pressed.connect(func(): _set_multiplier(10))
	btn_x100.pressed.connect(func(): _set_multiplier(100))

func _set_multiplier(mult: int):
	manager.set_buy_multiplier(mult)
	btn_x1.button_pressed = (mult == 1)
	btn_x10.button_pressed = (mult == 10)
	btn_x100.button_pressed = (mult == 100)
	
	# Force refresh cost labels immediately
	for w in widgets:
		w.update_state()

func _setup_logistics_rack():
	# Create a new rack for Command/Logistics since it was dynamically added
	logistics_rack = VBoxContainer.new()
	logistics_rack.name = "LogisticsRack"
	logistics_rack.add_theme_constant_override("separation", 10)
	
	var header = Label.new()
	header.name = "Header"   # so _setup_tabs can hide it (the tab labels the section)
	header.text = tr("[ COMMAND & LOGISTICS ]")
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.6, 0.4, 1.0, 0.5))
	logistics_rack.add_child(header)
	
	logistics_grid = GridContainer.new()
	logistics_grid.columns = 4
	logistics_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	logistics_grid.add_theme_constant_override("h_separation", 10)
	logistics_grid.add_theme_constant_override("v_separation", 10)
	logistics_rack.add_child(logistics_grid)
	
	# Cleaner look (no separator)
	blade_container.add_child(logistics_rack)

func refresh_list():
	for grid in [energy_grid, mining_grid, production_grid, logistics_grid]:
		if not grid: continue
		for child in grid.get_children():
			child.queue_free()
	widgets.clear()
	
	# v136: order cards early→late WITHIN each category by RESEARCH-UNLOCK tier
	# (the real progression gate), with build-credits cost as the within-tier
	# tiebreaker. Raw credits alone lied — e.g. the Uranium Centrifuge is cheap
	# (50K) but gated behind a tier-2 tech, so a cost-only sort floated a
	# late-game plant to the top. Tier-first keeps each card near when it unlocks.
	var bids: Array = manager.building_db.keys()
	bids.sort_custom(_by_progression)

	for bid in bids:
		var data = manager.building_db[bid]
		var w = building_widget_scene.instantiate()

		var cat = data.get("category", "industry")
		var target_grid = production_grid
		
		match cat:
			"power": target_grid = energy_grid
			"extraction": target_grid = mining_grid
			"industry": target_grid = production_grid
			"logistics": target_grid = logistics_grid
		
		if target_grid:
			target_grid.add_child(w)
			w.setup(bid, data, manager, self)
			widgets.append(w)

	_build_tabs()

# Early→late ordering: primary key = research-unlock tier (when the building
# actually becomes available), secondary = build-credits cost (affordability
# within the same tier). Buildings share a grid per category, so this orders
# each tab's cards by real progression, not raw price.
func _by_progression(a: String, b: String) -> bool:
	var ta: int = _unlock_tier(a)
	var tb: int = _unlock_tier(b)
	if ta != tb:
		return ta < tb
	return _build_credits(a) < _build_credits(b)

func _build_credits(bid: String) -> float:
	return float(manager.building_db[bid].get("cost", {}).get("credits", 0.0))

# Research tier that gates this building. No-research buildings are tier 0
# (buildable from the start). Falls back to 0 if the tech id is unknown.
func _unlock_tier(bid: String) -> int:
	var rm = GameState.research_manager
	var key: String = str(manager.building_db[bid].get("research_req", ""))
	if key == "" or key == "-" or rm == null or not rm.tech_tree.has(key):
		return 0
	return int(rm.tech_tree[key].get("tier", 0))

# Removed _process derived updates - using signals + throttled refreshes now

func update_ui():
	if not manager: return
	
	manager.recalc_energy()
	
	var net = manager.net_energy
	var gen = manager.generation
	var cons = manager.consumption
	
	if net_lbl:
		var eff = manager.energy_efficiency
		if net >= 0:
			net_lbl.text = tr("NET: +%.1f kW") % net
			net_lbl.add_theme_color_override("font_color", Color.CYAN)
		elif eff <= 0.5:
			net_lbl.text = tr("NET: %.1f kW  GRID COLLAPSING") % net
			net_lbl.add_theme_color_override("font_color", Color.RED)
		else:
			net_lbl.text = tr("NET: %.1f kW  POWER DEFICIT") % net
			net_lbl.add_theme_color_override("font_color", Color.ORANGE_RED)

	if gen_lbl:
		gen_lbl.text = tr("GEN: %.1f kW") % gen

	if cons_lbl:
		var eff = manager.energy_efficiency
		if eff < 0.5:
			cons_lbl.text = tr("CONS: %.1f kW  [THROTTLED TO %d%% — BUILD MORE POWER]") % [cons, int(eff * 100)]
			cons_lbl.add_theme_color_override("font_color", Color.RED)
		elif eff < 1.0:
			cons_lbl.text = tr("CONS: %.1f kW  (Grid Stalled: %d%%)") % [cons, int(eff * 100)]
			cons_lbl.add_theme_color_override("font_color", Color.ORANGE)
		else:
			cons_lbl.text = tr("CONS: %.1f kW") % cons
			cons_lbl.add_theme_color_override("font_color", Color.WHITE)

	for w in widgets:
		w.update_state()

func get_building_widget(building_id: String) -> Control:
	for w in widgets:
		if w.bid == building_id:
			return w
	return null


# ─── Category tabs ───────────────────────────────────────────────────────────
func _setup_tabs():
	# Map each tab to its rack VBox and hide the in-rack header (the tab labels
	# the section now), matching the processing page.
	_tab_racks = {
		"power":      $VBoxContainer/ScrollContainer/BladeContainer/EnergyRack,
		"extraction": $VBoxContainer/ScrollContainer/BladeContainer/MiningRack,
		"industry":   $VBoxContainer/ScrollContainer/BladeContainer/ProductionRack,
		"logistics":  logistics_rack,
	}
	for tab_id in _tab_racks:
		var rack = _tab_racks[tab_id]
		var hdr = rack.get_node_or_null("Header")
		if hdr:
			hdr.visible = false

	_tab_strip = HFlowContainer.new()
	_tab_strip.add_theme_constant_override("h_separation", 6)
	_tab_strip.add_theme_constant_override("v_separation", 6)
	var vb = $VBoxContainer
	vb.add_child(_tab_strip)
	vb.move_child(_tab_strip, $VBoxContainer/ScrollContainer.get_index())


func _build_tabs():
	if not _tab_strip:
		return
	_tab_buttons.clear()
	for c in _tab_strip.get_children():
		c.queue_free()

	var first_tab := ""
	for t in TAB_DEFS:
		var tab_id: String = String(t["id"])
		var grid = _grid_for_tab(tab_id)
		if not grid or grid.get_child_count() == 0:
			continue
		if first_tab == "":
			first_tab = tab_id
		var btn = Button.new()
		btn.text = tr(String(t["label"]))
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(_show_tab.bind(tab_id))
		_tab_strip.add_child(btn)
		_tab_buttons[tab_id] = btn

	var keep: bool = _active_tab != "" and _tab_buttons.has(_active_tab)
	_show_tab(_active_tab if keep else first_tab)


func _show_tab(tab_id: String) -> void:
	if tab_id == "" or not _tab_racks.has(tab_id):
		return
	_active_tab = tab_id
	for id in _tab_racks:
		_tab_racks[id].visible = (id == tab_id)
	for id in _tab_buttons:
		_style_tab_button(_tab_buttons[id], id == tab_id, _tab_color(id))
	var sc = $VBoxContainer/ScrollContainer
	if sc is ScrollContainer:
		sc.scroll_vertical = 0


func _grid_for_tab(tab_id: String) -> GridContainer:
	match tab_id:
		"power": return energy_grid
		"extraction": return mining_grid
		"industry": return production_grid
		"logistics": return logistics_grid
	return null


func _tab_color(tab_id: String) -> Color:
	for t in TAB_DEFS:
		if String(t["id"]) == tab_id:
			return t["color"]
	return Color.WHITE


# Mirrors the armory filter-bar style: inactive = ghost; active = filled accent.
func _style_tab_button(button: Button, is_active: bool, accent: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.08, 0.07, 0.22)
	normal.set_corner_radius_all(4)
	normal.set_border_width_all(1)
	var dim_edge: Color = accent
	dim_edge.a = 0.16
	normal.border_color = dim_edge
	normal.content_margin_left = 11
	normal.content_margin_right = 11
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5

	var hover := normal.duplicate()
	hover.bg_color = accent.lerp(Color.BLACK, 0.70)
	var hb: Color = accent
	hb.a = 0.55
	hover.border_color = hb

	var selected := normal.duplicate()
	selected.bg_color = accent.lerp(Color.BLACK, 0.40)
	selected.bg_color.a = 1.0
	selected.border_color = accent
	selected.border_width_top = 2
	selected.shadow_color = Color(accent.r, accent.g, accent.b, 0.45)
	selected.shadow_size = 7

	button.add_theme_stylebox_override("normal", selected if is_active else normal)
	button.add_theme_stylebox_override("hover", selected if is_active else hover)
	button.add_theme_stylebox_override("pressed", selected)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", Color.WHITE if is_active else Color(0.70, 0.70, 0.75))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
