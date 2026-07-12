extends Control

@onready var hp_lbl = $VBoxContainer/StatsPanel/HBoxContainer/HPLabel
@onready var atk_lbl = $VBoxContainer/StatsPanel/HBoxContainer/AtkLabel
@onready var def_lbl = $VBoxContainer/StatsPanel/HBoxContainer/DefLabel
@onready var eva_lbl = $VBoxContainer/StatsPanel/HBoxContainer/EvaLabel
@onready var energy_lbl = $VBoxContainer/StatsPanel/HBoxContainer/EnergyLabel
@onready var rack_container = $VBoxContainer/ScrollContainer/RackContainer

var manager: RefCounted
var hull_widget_scene = preload("res://scenes/ui/hull_widget.tscn")
var module_widget_scene = preload("res://scenes/ui/module_widget.tscn")
var widgets = []
var racks = {} # {category_id: GridContainer/HBoxContainer}
var _collection_rows := {}  # v135a: {set_id: Label} for the neutral Unique-Set collection panel

# v116: category tabs (matches processing/infra + armory filter bar). The 4
# weapon racks merge into one "Weapons" tab (their headers act as sub-headers);
# the rest are single-category tabs. Only the active tab's racks are shown.
var _tab_strip: HFlowContainer
var _tab_buttons := {}       # {tab_id: Button}
var _rack_vboxes := {}       # {category_id: rack VBoxContainer}
var _active_tab: String = ""
var TAB_DEFS := [
	{"id": "hulls",   "label": "Hulls",        "color": Color(0.40, 0.90, 0.60), "cats": ["hulls"]},
	{"id": "weapons", "label": "Weapons",      "color": Color(1.00, 0.40, 0.35), "cats": ["kinetic", "explosive", "energy", "cryo"]},
	{"id": "shield",  "label": "Shields",      "color": Color(0.40, 0.60, 1.00), "cats": ["shield"]},
	{"id": "armor",   "label": "Armor",        "color": Color(0.65, 0.65, 0.65), "cats": ["armor"]},
	{"id": "engine",  "label": "Engines",      "color": Color(0.80, 1.00, 0.20), "cats": ["engine"]},
	{"id": "battery", "label": "Power Cores",  "color": Color(1.00, 1.00, 0.20), "cats": ["battery"]},
	{"id": "cooling", "label": "Cooling",      "color": Color(0.20, 0.65, 1.00), "cats": ["cooling"]},
	{"id": "sensor",  "label": "Sensors",      "color": Color(0.60, 0.20, 1.00), "cats": ["sensor"]},
	{"id": "ammo",    "label": "Ordnance",     "color": Color(1.00, 0.60, 0.30), "cats": ["ammo"]},
	{"id": "gem",     "label": "Matrix Cores", "color": Color(0.80, 0.30, 0.80), "cats": ["gem"]},
]

func _ready():
	manager = GameState.shipyard_manager
	
	# Mission & Resource Integration
	GameState.mission_manager.mission_updated.connect(_on_mission_updated)
	if GameState.resources:
		if not GameState.resources.element_added.is_connected(_on_resource_changed):
			GameState.resources.element_added.connect(_on_resource_changed)
		if not GameState.resources.currency_added.is_connected(_on_resource_changed):
			GameState.resources.currency_added.connect(_on_resource_changed)
		if not GameState.resources.element_removed.is_connected(_on_resource_changed):
			GameState.resources.element_removed.connect(_on_resource_changed)
		if not GameState.resources.currency_removed.is_connected(_on_resource_changed):
			GameState.resources.currency_removed.connect(_on_resource_changed)
	if manager and not manager.inventory_updated.is_connected(_on_inventory_updated):
		manager.inventory_updated.connect(_on_inventory_updated)
	# v113: refresh craft cards the instant ANY research completes. A tech unlock
	# may fire no resource event (debug/free unlock, or research paid on another
	# screen), so a "RESEARCH:" lock could otherwise linger until the next resource
	# tick. Listen to tech_unlocked directly so the card clears immediately.
	if GameState.research_manager and not GameState.research_manager.tech_unlocked.is_connected(_on_tech_unlocked):
		GameState.research_manager.tech_unlocked.connect(_on_tech_unlocked)
	
	# UI Robustness: Ensure parent containers don't block mouse events
	$VBoxContainer/StatsPanel.mouse_filter = Control.MOUSE_FILTER_PASS
	$VBoxContainer/StatsPanel/HBoxContainer.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# v124: the live ship stat strip (HP/Atk/Shield/Eva/Energy) is removed from the
	# Shipyard — it duplicates Combat/Designer readouts and only crowds the craft
	# list. Hidden (not freed) so the @onready label refs stay valid.
	$VBoxContainer/StatsPanel.visible = false
	_setup_tabs()
	_build_collection_panel()
	call_deferred("refresh_list")

func get_coach_anchor(key: String) -> Control:
	match key:
		"first_item":
			# Anchor to a VISIBLE item in the active tab, not a hidden rack.
			for cat in _cats_of_tab(_active_tab):
				var sid = String(cat)
				if racks.has(sid) and racks[sid].get_child_count() > 0:
					return racks[sid].get_child(0)
			return widgets[0] if not widgets.is_empty() else null
		"stats":
			return $VBoxContainer/StatsPanel
		"matrix_synth":
			# v131: the Matrix Synthesis craft widget (coach anchor). Null when not
			# on-screen — the coach overlay falls back to a centered card.
			for w in widgets:
				if is_instance_valid(w) and str(w.get("mid")) == "matrix_synthesis" and w.is_visible_in_tree():
					return w
			return null
	return null

func _style_stats_panel():
	UITheme.apply_card_style($VBoxContainer/StatsPanel, "shipyard")
	for child in $VBoxContainer/StatsPanel/HBoxContainer.get_children():
		if child is Label:
			child.add_theme_font_size_override("font_size", 13)

func _process(_delta):
	_update_stats_display()

func _on_mission_updated():
	pass # No tab alerts needed with blade architecture

func _on_resource_changed(_a=null, _b=null):
	for w in widgets:
		if w.has_method("update_state"):
			w.update_state()

# ── Unique-Set collection panel (neutral state — v135a) ─────────────────────
# A passive "trophy cabinet": how many pieces of each boss's 3-piece Unique set you
# OWN (X/3). Pure collection state — no zone/weakness hints, no "go farm" nudge.
func _build_collection_panel() -> void:
	if not GameState.combat_manager:
		return
	var panel := PanelContainer.new()
	panel.name = "CollectionPanel"
	UITheme.apply_card_style(panel, "shipyard")
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	panel.add_child(vb)
	var hdr := Label.new()
	hdr.text = "◈ UNIQUE SETS"
	hdr.add_theme_font_size_override("font_size", 12)
	UITheme.apply_segmented_font(hdr, UITheme.COLORS["accent"])
	hdr.add_theme_color_override("font_color", UITheme.COLORS["accent"])
	vb.add_child(hdr)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 2)
	vb.add_child(grid)
	_collection_rows = {}
	for sid in GameState.combat_manager.TRINITY_SET_BONUSES:
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 11)
		grid.add_child(lbl)
		_collection_rows[sid] = lbl
	var vbox := $VBoxContainer
	vbox.add_child(panel)
	vbox.move_child(panel, $VBoxContainer/ScrollContainer.get_index())  # above the rack scroll
	_refresh_collection()

func _refresh_collection() -> void:
	if _collection_rows.is_empty() or not GameState.shipyard_manager or not GameState.combat_manager:
		return
	var counts: Dictionary = GameState.shipyard_manager.get_owned_set_counts()
	var defs = GameState.combat_manager.TRINITY_SET_BONUSES
	for sid in _collection_rows:
		var n := int(counts.get(sid, 0))
		var lbl: Label = _collection_rows[sid]
		if not is_instance_valid(lbl):
			continue
		lbl.text = "%s  %d/3" % [String(defs.get(sid, {}).get("name", sid)), n]
		if n >= 3:
			lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))       # complete — gold
		elif n > 0:
			lbl.add_theme_color_override("font_color", UITheme.COLORS["text_main"])
		else:
			lbl.add_theme_color_override("font_color", UITheme.COLORS["text_dim"])   # not started — dim

func _on_inventory_updated():
	_on_resource_changed()
	_refresh_collection()

func _on_tech_unlocked(_tech_id = null):
	_on_resource_changed()  # re-evaluate every craft card's research lock

func _update_stats_display():
	if not $VBoxContainer/StatsPanel.visible:
		return   # stat strip removed from the Shipyard — nothing to refresh
	if hp_lbl:
		hp_lbl.text = "HP: %d / %d" % [manager.current_hp, manager.max_hp]
	if atk_lbl:
		atk_lbl.text = "Atk: %s" % UITheme.format_num(manager.attack)
	if def_lbl:
		def_lbl.text = "Shield: %s" % UITheme.format_num(manager.max_shield)
	if eva_lbl:
		eva_lbl.text = "Eva: %.1f%%" % manager.evasion
	if energy_lbl:
		var e_max = manager.energy_capacity  # v110: ship's own field
		var e_used = manager.energy_used
		energy_lbl.text = "Energy: %d/%d" % [e_used, e_max]
		energy_lbl.modulate = Color(1, 0.3, 0.3) if e_used > e_max else Color.WHITE

# v124: _on_repair_pressed / repair button removed — repair is now done by using
# repair-kit consumables (combat HUD), no Liras. shipyard_manager.repair_hull()
# remains (kit-based) for any programmatic callers.


func refresh_list():
	# Clear previous racks
	for child in rack_container.get_children():
		child.queue_free()
	widgets.clear()
	racks.clear()
	
	# Create racks - Hulls now use GridContainer for consistency
	_create_rack("hulls", "Capital Hulls", Color(0.4, 0.9, 0.6, 0.5), rack_container, false)
	_create_rack("kinetic", "Kinetic Weapons", Color(1.0, 0.32, 0.32, 0.5), rack_container)
	_create_rack("explosive", "Explosive Weapons", Color(1.0, 0.5, 0.0, 0.5), rack_container) # Added
	_create_rack("energy", "Energy Weapons", Color(0.0, 0.9, 1.0, 0.5), rack_container)
	_create_rack("cryo", "Special Weapons", Color(0.72, 0.55, 1.0, 0.5), rack_container)  # v113: exotic-element weapons (Cryo + Corrosion + future tiers) share this rack
	_create_rack("shield", "Shield Generators", Color(0.4, 0.6, 1.0, 0.5), rack_container)
	_create_rack("armor", "Hull Armor", Color(0.6, 0.6, 0.6, 0.5), rack_container)
	_create_rack("engine", "Engine Systems", Color(0.8, 1.0, 0.2, 0.5), rack_container)
	_create_rack("battery", "Power Cores", Color(1.0, 1.0, 0.2, 0.5), rack_container)
	_create_rack("cooling", "Cooling Systems", Color(0.0, 0.5, 1.0, 0.5), rack_container)
	_create_rack("sensor", "Sensor & EW Suites", Color(0.6, 0.2, 1.0, 0.5), rack_container)
	_create_rack("ammo", "Ordnance", Color(1.0, 0.6, 0.3, 0.5), rack_container)
	_create_rack("gem", "Matrix Cores (Sockets)", Color(0.8, 0.3, 0.8, 0.5), rack_container)
	
	# Hulls
	var sorted_hulls = manager.hulls.keys()
	sorted_hulls.sort_custom(func(a,b): return manager.hulls[a]["cost"].get("credits",0) < manager.hulls[b]["cost"].get("credits",0))
	
	for hid in sorted_hulls:
		var w = hull_widget_scene.instantiate()
		racks["hulls"].add_child(w)
		w.setup(hid, manager.hulls[hid], manager, self)
		widgets.append(w)
		
	# Modules Categorization & Sorting (Audit v70.0)
	var sorted_mods = manager.modules.keys()
	
	# Custom Sort: Sort by "Power Score" (Tier) ascending
	sorted_mods.sort_custom(func(a, b):
		return _get_module_power_score(a, manager.modules[a]) < _get_module_power_score(b, manager.modules[b])
	)
	
	for mid in sorted_mods:
		var data = manager.modules[mid]
		# Audit v80.1: Skip dropped loot and Unique (Drop-only) modules in Shipyard Crafting
		if data.get("is_custom", false) or data.get("is_unique", false):
			continue
		# v110: grant/drop-only modules have no cost (e.g. the Warp-granted
		# Cryo-Lance) — never show them in the craft list.
		if data.get("cost", {}).is_empty():
			continue

		var type = data.get("slot_type", "weapon")
		var cat = "kinetic"
		
		# Category Logic
		match type:
			"weapon":
				var stats = data.get("stats", {})
				if stats.get("atk_cryo", 0) > 0:
					cat = "cryo"
				elif stats.get("atk_explosive", 0) > 0:
					cat = "explosive"
				elif stats.get("atk_kinetic", 0) > stats.get("atk_energy", 0):
					cat = "kinetic"
				else:
					cat = "energy"
			"shield": cat = "shield"
			"armor": cat = "armor" # Added armor mapping
			"engine": cat = "engine"
			"battery": cat = "battery"
			"cooling": cat = "cooling"
			"sensor": cat = "sensor"
			"ammo", "slug": cat = "ammo"
			"gem", "gem_synth": cat = "gem"
			_: cat = "energy" # Default
		
		if cat not in racks: continue
		
		var w = module_widget_scene.instantiate()
		racks[cat].add_child(w)
		w.setup(mid, data, manager, self)
		w.update_state()
		widgets.append(w)

	# v116: tab visibility supersedes the old per-rack empty-hiding — _show_tab
	# reveals only the active tab's non-empty racks.
	_build_tabs()

func _get_module_power_score(id: String, data: Dictionary) -> int:
	# Tier Heuristic: Calculate a "Power Score" based on primary stat or cost
	# Used for sorting modules from Weakest -> Strongest
	
	var score = 0
	var stats = data.get("stats", {})
	
	# 1. Base Score from Cost (Expensive = Better)
	# Logarithmic scale prevents late game items from dwarfing everything
	var cost = data.get("cost", {})
	var credits = cost.get("credits", 0)
	if credits > 0:
		score += int(log(credits) * 10)
	else:
		# Battery T1/T2 have 0 credits cost, check material rarity manually
		if "BatteryT1" in cost: score += 10
		elif "BatteryT2" in cost: score += 20
		elif "BatteryT3" in cost: score += 30
		else: score += 5 # Fallback
		
	# 2. Stat Bonus
	# Add raw stats to differentiate items with verify similar costs
	if stats.get("atk_kinetic", 0) > 0: score += stats["atk_kinetic"]
	if stats.get("atk_energy", 0) > 0: score += stats["atk_energy"]
	if stats.get("atk_explosive", 0) > 0: score += stats["atk_explosive"]
	if stats.get("max_shield", 0) > 0: score += stats["max_shield"] / 5
	if stats.get("hp", 0) > 0: score += stats["hp"] / 10
	if stats.get("energy_capacity", 0) > 0: score += stats["energy_capacity"]
	if stats.get("eva", 0) > 0: score += stats["eva"] * 2
	if stats.get("atk_speed_bonus", 0) > 0: score += int(stats["atk_speed_bonus"] * 100)
	
	# v80.3: Removed dead sort-score overrides (mining_laser_mk1, mk2, railgun_mk1 no longer exist)
	
	return score

func _create_rack(id: String, title: String, color: Color, parent: Node, horizontal: bool = false):
	var rack_vbox = VBoxContainer.new()
	rack_vbox.name = id + "_rack"
	rack_vbox.add_theme_constant_override("separation", 10)
	parent.add_child(rack_vbox)
	
	var header = Label.new()
	header.name = "Header"   # so the tab system can hide it on single-category tabs
	header.text = "[ %s ]" % title.to_upper()
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", color)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rack_vbox.add_child(header)
	
	var rack_grid: Control
	if horizontal:
		# Create a horizontal scroll for hulls
		var scroll = ScrollContainer.new()
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size.y = 145  # Reduced 20% from 180
		rack_vbox.add_child(scroll)
		
		rack_grid = HBoxContainer.new()
		rack_grid.add_theme_constant_override("separation", 20)
		scroll.add_child(rack_grid)
	else:
		rack_grid = GridContainer.new()
		rack_grid.columns = 4
		rack_grid.add_theme_constant_override("h_separation", 10)
		rack_grid.add_theme_constant_override("v_separation", 10)
		rack_vbox.add_child(rack_grid)
	
	var sep = HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.1)
	rack_vbox.add_child(sep)

	racks[id] = rack_grid
	_rack_vboxes[id] = rack_vbox

func get_module_widget(module_id: String) -> Control:
	for w in widgets:
		if w.get("mid") == module_id:
			return w
	return null

func get_hull_widget(hull_id: String) -> Control:
	for w in widgets:
		if w.get("hid") == hull_id:
			return w
	return null

var _last_focus_mid: String = ""

func on_page_enter():
	# Re-arm scroll-to so re-entering the page during a mission re-centers
	# the relevant module card.
	_last_focus_mid = ""

func focus_module_tab(module_id: String):
	# Scroll the mission-relevant module card into view (called every frame by
	# the nav-hint system, so only act when the target actually changes).
	if module_id == "" or module_id == _last_focus_mid:
		return
	var w = get_module_widget(module_id)
	if not w:
		return
	_last_focus_mid = module_id
	var tab_id = _tab_for_cat(_cat_of_widget(w))
	if tab_id != "" and _active_tab != tab_id:
		_show_tab(tab_id)
	var sc = $VBoxContainer/ScrollContainer
	if sc is ScrollContainer:
		_scroll_card_to_top(sc, w)

# v134: same fix as processing_page — ensure_control_visible scrolls minimally,
# so a module card taller than the viewport ended BOTTOM-aligned with its header
# clipped offscreen when a mission pulse focused it. Top-align instead, one
# frame later so the tab-switch relayout has settled.
func _scroll_card_to_top(sc: ScrollContainer, w: Control) -> void:
	await get_tree().process_frame
	if not is_instance_valid(sc) or not is_instance_valid(w) or not w.is_visible_in_tree():
		return
	var top: float = w.global_position.y - sc.get_global_rect().position.y + float(sc.scroll_vertical)
	sc.scroll_vertical = int(maxf(0.0, top - 10.0))


# ─── Category tabs ───────────────────────────────────────────────────────────
func _setup_tabs():
	_tab_strip = HFlowContainer.new()
	_tab_strip.add_theme_constant_override("h_separation", 6)
	_tab_strip.add_theme_constant_override("v_separation", 6)
	var vb = $VBoxContainer
	vb.add_child(_tab_strip)
	vb.move_child(_tab_strip, $VBoxContainer/ScrollContainer.get_index())


func _build_tabs():
	if not _tab_strip:
		return
	# Hide headers on single-category tabs (the tab labels the section); keep
	# them on merged tabs (Weapons) where they act as sub-headers.
	for cat_id in _rack_vboxes:
		var hdr = _rack_vboxes[cat_id].get_node_or_null("Header")
		if hdr:
			hdr.visible = _cats_of_tab(_tab_for_cat(cat_id)).size() > 1

	_tab_buttons.clear()
	for c in _tab_strip.get_children():
		c.queue_free()

	var first_tab := ""
	for t in TAB_DEFS:
		var tab_id: String = String(t["id"])
		if _tab_item_count(t["cats"]) == 0:
			continue
		if first_tab == "":
			first_tab = tab_id
		var btn = Button.new()
		btn.text = String(t["label"])
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(_show_tab.bind(tab_id))
		_tab_strip.add_child(btn)
		_tab_buttons[tab_id] = btn

	var keep: bool = _active_tab != "" and _tab_buttons.has(_active_tab)
	_show_tab(_active_tab if keep else first_tab)


func _show_tab(tab_id: String) -> void:
	if tab_id == "":
		return
	_active_tab = tab_id
	var active_cats = _cats_of_tab(tab_id)
	for cat_id in _rack_vboxes:
		var show_it: bool = (cat_id in active_cats) and racks.has(cat_id) and racks[cat_id].get_child_count() > 0
		_rack_vboxes[cat_id].visible = show_it
	for id in _tab_buttons:
		_style_tab_button(_tab_buttons[id], id == tab_id, _tab_color(id))
	var sc = $VBoxContainer/ScrollContainer
	if sc is ScrollContainer:
		sc.scroll_vertical = 0


func _tab_item_count(cats: Array) -> int:
	var n := 0
	for cat in cats:
		var sid := String(cat)
		if racks.has(sid):
			n += racks[sid].get_child_count()
	return n


func _cats_of_tab(tab_id: String) -> Array:
	for t in TAB_DEFS:
		if String(t["id"]) == tab_id:
			return t["cats"]
	return []


func _tab_for_cat(cat: String) -> String:
	for t in TAB_DEFS:
		if cat in t["cats"]:
			return String(t["id"])
	return ""


func _tab_color(tab_id: String) -> Color:
	for t in TAB_DEFS:
		if String(t["id"]) == tab_id:
			return t["color"]
	return Color.WHITE


func _cat_of_widget(w) -> String:
	var p = w.get_parent()
	for cat_id in racks:
		if racks[cat_id] == p:
			return cat_id
	return ""


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
