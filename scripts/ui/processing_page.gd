extends Control

@onready var level_label = $VBoxContainer/Header/LevelLabel
@onready var xp_label = $VBoxContainer/Header/XPLabel
@onready var xp_bar = $VBoxContainer/XPBar
@onready var rack_container = $VBoxContainer/ScrollContainer/RackContainer

var manager: RefCounted
var recipe_widget_scene = preload("res://scenes/ui/processing_recipe_widget.tscn")
var widgets = []
var racks = {} # {category_id: GridContainer}

# v116: category tabs replace the rack-by-rack stacked sections. One PAGE per
# tab (all but the active hidden), toggled by a wrapping tab strip styled like
# the armory filter bar. Munitions + Repair Kits each MERGE several sub-
# categories, shown as small sub-headers inside the single tab.
var _tab_strip: HFlowContainer
var _tab_buttons := {}     # {tab_id: Button}
var _tab_pages := {}       # {tab_id: VBoxContainer}
var _sub_headers := {}     # {sub_category_id: Label}  (merged-tab sub-headers)
var _active_tab: String = ""
var _search_bar: LineEdit   # v121: filter recipes by OUTPUT material

# Top-level tabs. `cats` are _get_recipe_category ids; a tab with >1 cat is a
# merged tab and gets sub-headers from SUB_DEFS.
var TAB_DEFS := [
	{"id": "basics",      "label": "Basics",      "color": Color(0.80, 0.80, 0.80), "cats": ["basics"]},
	{"id": "smelting",    "label": "Refining",    "color": Color(0.90, 0.50, 0.20), "cats": ["smelting"]},
	{"id": "alloys",      "label": "Alloys",      "color": Color(0.72, 0.72, 0.72), "cats": ["alloys"]},
	{"id": "materials",   "label": "Materials",   "color": Color(0.40, 0.85, 0.65), "cats": ["materials"]},
	{"id": "electronics", "label": "Electronics", "color": Color(0.25, 0.80, 1.00), "cats": ["electronics"]},
	{"id": "batteries",   "label": "Batteries",   "color": Color(1.00, 0.95, 0.35), "cats": ["batteries"]},
	{"id": "munitions",   "label": "Munitions",   "color": Color(0.95, 0.55, 0.25), "cats": ["munitions_kinetic", "munitions_energy", "munitions_explosive"]},
	{"id": "repair",      "label": "Repair Kits", "color": Color(0.30, 0.90, 0.60), "cats": ["consumables_hull", "consumables_shield"]},
	{"id": "research",    "label": "Research",    "color": Color(0.80, 0.45, 1.00), "cats": ["research"]},
]
# Sub-headers for merged tabs: sub_category_id → [label, accent].
var SUB_DEFS := {
	"munitions_kinetic":   ["Kinetic",   Color(0.95, 0.55, 0.25)],
	"munitions_energy":    ["Energy",    Color(0.35, 0.85, 1.00)],
	"munitions_explosive": ["Explosive", Color(1.00, 0.85, 0.35)],
	"consumables_hull":    ["Hull",      Color(0.30, 1.00, 0.55)],
	"consumables_shield":  ["Shield",    Color(0.30, 0.65, 1.00)],
}

func _ready():
	manager = GameState.processing_manager
	
	# Premium Styling
	UITheme.apply_progress_bar_style(xp_bar, "engineering")
	$VBoxContainer/ScrollContainer.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS

	# Category tab strip (wraps like the armory filter bar), inserted just above
	# the recipe scroll area.
	_tab_strip = HFlowContainer.new()
	_tab_strip.add_theme_constant_override("h_separation", 6)
	_tab_strip.add_theme_constant_override("v_separation", 6)
	var vb := $VBoxContainer
	vb.add_child(_tab_strip)
	vb.move_child(_tab_strip, $VBoxContainer/ScrollContainer.get_index())

	# v121: output search bar — type a material (e.g. "Steel", "Circuit") to filter
	# recipes to those that PRODUCE it, across every category tab. Sits above the tabs.
	_search_bar = LineEdit.new()
	_search_bar.placeholder_text = "🔍  Search by output  (e.g. Steel, Adv Circuit)…"
	_search_bar.clear_button_enabled = true
	_search_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_bar.custom_minimum_size = Vector2(0, 32)
	vb.add_child(_search_bar)
	vb.move_child(_search_bar, _tab_strip.get_index())
	_search_bar.text_changed.connect(_apply_search)

	# Mission & Resource Integration
	GameState.mission_manager.mission_updated.connect(_on_mission_updated)
	if GameState.resources:
		GameState.resources.element_added.connect(_on_resource_changed)
		GameState.resources.currency_added.connect(_on_resource_changed)
	
	call_deferred("refresh_recipes")
	call_deferred("_on_mission_updated")

func _on_mission_updated():
	pass # Tab alerts no longer needed with blade architecture

func _on_resource_changed(_a = null, _b = null):
	for w in widgets:
		if w.has_method("update_state"):
			w.update_state()

func get_coach_anchor(key: String) -> Control:
	match key:
		"first_recipe":
			# Anchor to a VISIBLE card (active tab's first grid with cards).
			if _active_tab != "" and _tab_pages.has(_active_tab):
				for node in _tab_pages[_active_tab].get_children():
					if node is GridContainer and node.get_child_count() > 0:
						return node.get_child(0)
			return widgets[0] if not widgets.is_empty() else null
		"xp_bar":
			return xp_bar
	return null

func refresh_recipes():
	# Clear previous grids
	for child in rack_container.get_children():
		child.queue_free()
	widgets.clear()
	racks.clear()

	_sub_headers.clear()
	_tab_pages.clear()

	# One hidden page per tab; inside, a 4-col grid per sub-category. Merged
	# tabs (>1 cat) get a small sub-header before each grid.
	for t in TAB_DEFS:
		var tab_id: String = String(t["id"])
		var cats: Array = t["cats"]
		var multi: bool = cats.size() > 1
		var page = VBoxContainer.new()
		page.name = tab_id + "_page"
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 10)
		page.visible = false
		rack_container.add_child(page)
		_tab_pages[tab_id] = page

		for sub in cats:
			var sub_id: String = String(sub)
			if multi and SUB_DEFS.has(sub_id):
				var sh = Label.new()
				sh.text = "[ %s ]" % String(SUB_DEFS[sub_id][0]).to_upper()
				sh.add_theme_font_size_override("font_size", 11)
				sh.add_theme_color_override("font_color", SUB_DEFS[sub_id][1])
				page.add_child(sh)
				_sub_headers[sub_id] = sh
			var grid = GridContainer.new()
			grid.name = sub_id + "_grid"
			grid.columns = 4
			grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_theme_constant_override("h_separation", 10)
			grid.add_theme_constant_override("v_separation", 10)
			page.add_child(grid)
			racks[sub_id] = grid

	var sorted_keys = manager.recipes.keys()
	sorted_keys.sort_custom(func(a, b):
		var ra = manager.recipes[a]
		var rb = manager.recipes[b]
		if ra["level_req"] != rb["level_req"]:
			return ra["level_req"] < rb["level_req"]
		return ra["name"] < rb["name"]
	)

	for rid in sorted_keys:
		var data = manager.recipes[rid]
		var w = recipe_widget_scene.instantiate()
		var cat = _get_recipe_category(rid, data)

		if cat in racks:
			racks[cat].add_child(w)
			w.setup(rid, data, manager, self)
			w.set_meta("rid", rid)   # v121: key for the output search filter
			widgets.append(w)

	# Hide empty sub-sections (header + grid) inside merged tabs so a tab with
	# no explosive ammo (etc.) doesn't show a dangling sub-header.
	for sub_id in _sub_headers:
		if racks[sub_id].get_child_count() == 0:
			_sub_headers[sub_id].visible = false
			racks[sub_id].visible = false

	_build_tabs()
	# v121: re-apply an active output search to the freshly-rebuilt widgets.
	if _search_bar and not _search_bar.text.strip_edges().is_empty():
		_apply_search(_search_bar.text)

# v121: output-material search — filter recipes to those PRODUCING the typed
# material, across all category tabs. Empty query restores the normal tab view.
func _apply_search(q_raw: String) -> void:
	var q := q_raw.strip_edges().to_lower()
	if q == "":
		for w in widgets:
			w.visible = true
		_restore_sections()
		_tab_strip.visible = true
		if _active_tab != "":
			_show_tab(_active_tab)
		return
	# Search mode: hide the tab strip, reveal every page, show only matches.
	_tab_strip.visible = false
	for id in _tab_pages:
		_tab_pages[id].visible = true
	for w in widgets:
		w.visible = _matches_output(str(w.get_meta("rid", "")), q)
	_prune_empty_sections()

func _matches_output(rid: String, q: String) -> bool:
	var data: Dictionary = manager.recipes.get(rid, {})
	if data.is_empty():
		return false
	for item in data.get("output", {}):
		if _item_matches(str(item), q):
			return true
	for entry in data.get("output_table", []):
		if entry is Array and entry.size() > 0 and _item_matches(str(entry[0]), q):
			return true
	# Also match the recipe's own name, so typing the recipe name works too.
	return q in str(data.get("name", "")).to_lower()

func _item_matches(item: String, q: String) -> bool:
	if q in item.to_lower():
		return true
	if ElementDB and ElementDB.has_method("get_display_name"):
		return q in str(ElementDB.get_display_name(item)).to_lower()
	return false

# Hide grids / sub-headers / pages with no VISIBLE recipe (search mode).
func _prune_empty_sections() -> void:
	for sid in racks:
		var grid = racks[sid]
		var any := false
		for c in grid.get_children():
			if c.visible:
				any = true
				break
		grid.visible = any
		if sid in _sub_headers:
			_sub_headers[sid].visible = any
	for tid in _tab_pages:
		var page = _tab_pages[tid]
		var any_p := false
		for node in page.get_children():
			if node is GridContainer and node.visible:
				any_p = true
				break
		page.visible = any_p

# Restore the permanent empty-section hiding (grids/headers with no recipes).
func _restore_sections() -> void:
	for sid in racks:
		var grid = racks[sid]
		var has: bool = grid.get_child_count() > 0
		grid.visible = has
		if sid in _sub_headers:
			_sub_headers[sid].visible = has


func _get_recipe_category(rid: String, data: Dictionary) -> String:
	# Priority: Explicit Category
	if data.get("category"):
		return data.get("category")

	# Munitions — split by damage type
	# Kinetic: slugs and rounds (Mass Driver / Railgun ammo)
	if "slug" in rid or "rounds" in rid:
		return "munitions_kinetic"
	# Energy: cells (Plasma / Laser / Vaporizer ammo)
	if "cell_t" in rid or "craft_cell" in rid:
		return "munitions_energy"
	# Explosive: missiles and warheads
	if "missile" in rid or "warhead" in rid:
		return "munitions_explosive"
	
	# Batteries - power storage
	if "battery" in rid:
		return "batteries"
	
	# Electronics - circuits, chips, semiconductors
	if "circuit" in rid or "chip" in rid or "semiconductor" in rid or "hydraulics" in rid:
		return "electronics"
	
	# Research/Artifacts - analysis, upgrading research fragments
	if "artifact" in rid or "res1" in rid or "res2" in rid or "res3" in rid or "nav_data" in rid or "decrypt" in rid:
		return "research"
	
	# Alloys - metal combinations
	if "bronze" in rid or "steel" in rid or "alloy" in rid or "galvanize" in rid or "stainless" in rid:
		return "alloys"
	
	# Ore Smelting - extracting pure elements from ores
	if "smelt" in rid or "refine" in rid or "extract" in rid or "centrifuge" in rid or "electrolysis" in rid or "leach" in rid or "process_" in rid or "panning" in rid:
		return "smelting"
	
	# Basics check (before materials fallback)
	if "sift" in rid or "charcoal" in rid or "burn" in rid or "wash" in rid:
		return "basics"
	
	# Advanced Materials - composites, polymers, fibers
	if "fiber" in rid or "polymer" in rid or "graphite" in rid or "nanoweave" in rid or "mesh" in rid or "sealant" in rid or "coolant" in rid or "charcoal" in rid or "carbon" in rid:
		return "materials"
	
	# Default to materials if no match
	return "materials"


func _build_tabs():
	_tab_buttons.clear()
	for c in _tab_strip.get_children():
		c.queue_free()

	var first_tab := ""
	for t in TAB_DEFS:
		var tab_id: String = String(t["id"])
		# Skip tabs whose sub-categories hold no recipes at all.
		if _tab_recipe_count(t["cats"]) == 0:
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

	# Keep the active tab across refreshes when it still exists; else first.
	var keep: bool = _active_tab != "" and _tab_buttons.has(_active_tab)
	_show_tab(_active_tab if keep else first_tab)


func _show_tab(tab_id: String) -> void:
	if tab_id == "" or not _tab_pages.has(tab_id):
		return
	_active_tab = tab_id
	for id in _tab_pages:
		_tab_pages[id].visible = (id == tab_id)
	for id in _tab_buttons:
		_style_tab_button(_tab_buttons[id], id == tab_id, _tab_color(id))
	# Reset scroll to top so a tall previous tab doesn't leave the new one
	# scrolled past its first row.
	var sc = $VBoxContainer/ScrollContainer
	if sc is ScrollContainer:
		sc.scroll_vertical = 0


func _tab_recipe_count(cats: Array) -> int:
	var n := 0
	for sub in cats:
		var sid := String(sub)
		if racks.has(sid):
			n += racks[sid].get_child_count()
	return n


func _tab_color(tab_id: String) -> Color:
	for t in TAB_DEFS:
		if String(t["id"]) == tab_id:
			return t["color"]
	return Color.WHITE


func _tab_for_cat(cat: String) -> String:
	for t in TAB_DEFS:
		if cat in t["cats"]:
			return String(t["id"])
	return ""


# Mirrors the armory filter-bar style (designer_page::_apply_filter_button_style):
# inactive = near-transparent ghost; active = filled accent plate + lit top edge.
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

func get_widget_by_aid(rid_in: String) -> Control:
	for w in widgets:
		if w.get("rid") == rid_in:
			return w
	return null

var _last_focus_rid: String = ""

func on_page_enter():
	_last_focus_rid = ""

func focus_tab(rid_in: String):
	# Switch to the mission-relevant recipe's category tab, then scroll it into
	# view (called every frame by the nav-hint system, so only act on change).
	if rid_in == "" or rid_in == _last_focus_rid:
		return
	var w = get_widget_by_aid(rid_in)
	if not w:
		return
	_last_focus_rid = rid_in
	var cat = _get_recipe_category(rid_in, manager.recipes.get(rid_in, {}))
	var tab_id = _tab_for_cat(cat)
	if tab_id != "" and _active_tab != tab_id:
		_show_tab(tab_id)
	var sc = $VBoxContainer/ScrollContainer
	if sc is ScrollContainer:
		sc.call_deferred("ensure_control_visible", w)

func _process(_delta):
	update_ui()

func update_ui():
	if not manager: return
	
	level_label.text = "Level: %d" % manager.get_level()
	xp_label.text = "XP: %d" % int(manager.xp)
	xp_bar.value = manager.get_progress_to_next_level()
	
	for w in widgets:
		w.update_state()
	
	while not manager.events.is_empty():
		var ev = manager.events.pop_front()
		var type = ev[0]
		var data = ev[1]
		var target_id = ev[2]

		# Only surface a popup when its source recipe is on this visible page.
		var target_w = null
		for w in widgets:
			if w.rid == target_id:
				target_w = w
				break
		if not target_w or not is_visible_in_tree():
			continue

		if type == "xp":
			UITheme.show_reward({
				"kind": "xp", "key": "xp:process", "name": "Processing XP",
				"amount": UITheme.parse_xp_amount(data),
				"total_text": "Lvl %d" % manager.get_level(),
				"accent": Color(1.0, 0.8, 0.15),
			})
		elif data is Dictionary:
			var symbol = data.get("symbol", "item")
			var amount = int(data.get("amount", 0))
			var total = 0
			if symbol == "credits":
				total = GameState.resources.get_currency("credits")
			else:
				total = GameState.resources.get_element_amount(symbol)
			var tag = ""
			if data.get("is_critical"): tag = "CRITICAL"
			elif data.get("is_jackpot"): tag = "JACKPOT"
			UITheme.show_reward({
				"kind": "loot", "key": symbol, "symbol": symbol,
				"name": ElementDB.get_display_name(symbol),
				"amount": amount,
				"total_text": UITheme.format_number(total),
				"accent": UITheme.element_accent(symbol),
				"hot": tag != "", "tag": tag,
			})
