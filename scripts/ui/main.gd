extends Control
## Mobile-first shell: top resource HUD, swappable content pages, bottom tab bar.
## UI is built entirely in code and refreshed from GameState signals.

const TABS := [
	{"id": "gather", "label": "Gather"},
	{"id": "craft",  "label": "Craft"},
	{"id": "tech",   "label": "Tech"},
	{"id": "stats",  "label": "More"},
]

# Palette
const C_BG := "0b1220"
const C_PANEL := "111c2e"
const C_CARD := "16243a"
const C_BORDER := "2a3a55"
const C_ACCENT := "5ad1e0"
const C_TEXT := "e6ebf2"
const C_DIM := "8a93a5"
const C_MUTED := "5a6478"
const C_WARN := "c08457"

var content: Control
var pages := {}            # id -> ScrollContainer
var tab_buttons := {}      # id -> Button
var current := ""
var res_bar: HBoxContainer
var active_label: Label
var _active_bar: ProgressBar = null
var _reset_armed := false

func _ready() -> void:
	# Lock to portrait on mobile (project setting isn't always honored on-device).
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
	_build()
	GameState.resources_changed.connect(_on_resources)
	GameState.skills_changed.connect(_refresh_current)
	GameState.tech_changed.connect(_refresh_all)
	GameState.action_changed.connect(_refresh_current)
	_refresh_top()
	_show("gather")
	if GameState.pending_offline != "":
		_show_offline(GameState.pending_offline)
		GameState.pending_offline = ""

func _process(_delta: float) -> void:
	if is_instance_valid(_active_bar) and GameState.active_type != "":
		var dur := GameState.current_duration()
		if dur > 0.0:
			_active_bar.value = clampf(GameState.progress / dur * 100.0, 0.0, 100.0)
	if active_label:
		active_label.text = _active_text()

func _on_resources() -> void:
	_refresh_top()
	_refresh_current()

# ============================================================ BUILD
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color.html(C_BG)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# --- Top HUD ---
	var top := PanelContainer.new()
	_style_panel(top, C_PANEL)
	root.add_child(top)
	var topv := VBoxContainer.new()
	topv.add_theme_constant_override("separation", 4)
	top.add_child(topv)

	var title := Label.new()
	title.text = "✦ STELLAR FORGE"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color.html(C_ACCENT))
	topv.add_child(title)

	active_label = Label.new()
	active_label.add_theme_font_size_override("font_size", 12)
	active_label.add_theme_color_override("font_color", Color.html(C_DIM))
	topv.add_child(active_label)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 26)
	topv.add_child(scroll)
	res_bar = HBoxContainer.new()
	res_bar.add_theme_constant_override("separation", 16)
	scroll.add_child(res_bar)

	# --- Content (pages) ---
	content = Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(content)
	for t in TABS:
		var page := _make_page()
		page.visible = false
		content.add_child(page)
		pages[t.id] = page

	# --- Bottom tab bar ---
	var bottom := PanelContainer.new()
	_style_panel(bottom, C_PANEL)
	root.add_child(bottom)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	bottom.add_child(tabs)
	for t in TABS:
		var b := Button.new()
		b.text = t.label
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 44)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_show.bind(t.id))
		tabs.add_child(b)
		tab_buttons[t.id] = b

func _make_page() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 12)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(m)
	var v := VBoxContainer.new()
	v.name = "List"
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(v)
	return sc

# ============================================================ NAV
func _show(id: String) -> void:
	current = id
	_reset_armed = false
	for pid in pages:
		pages[pid].visible = (pid == id)
	for bid in tab_buttons:
		_style_tab(tab_buttons[bid], bid == id)
	_refresh_current()

func _refresh_all() -> void:
	_refresh_top()
	_refresh_current()

func _refresh_current() -> void:
	match current:
		"gather": _build_gather()
		"craft":  _build_craft()
		"tech":   _build_tech()
		"stats":  _build_stats()

func _clear(id: String) -> VBoxContainer:
	var v: VBoxContainer = pages[id].find_child("List", true, false)
	for c in v.get_children():
		v.remove_child(c)
		c.queue_free()
	return v

# ============================================================ PAGES
func _build_gather() -> void:
	_active_bar = null
	var v := _clear("gather")
	_header(v, "PLANETARY HARVESTING", "Lv %d" % GameState.level_of("harvesting"))
	for id in GameData.GATHER:
		var a: Dictionary = GameData.GATHER[id]
		var ok := GameState.meets_requirements(a, "harvesting")
		v.add_child(_action_card("gather", id, a["name"], _gather_sub(a), ok, _req_text(a, "harvesting")))

func _build_craft() -> void:
	_active_bar = null
	var v := _clear("craft")
	_header(v, "FABRICATION BAY", "Lv %d" % GameState.level_of("fabrication"))
	for id in GameData.CRAFT:
		var r: Dictionary = GameData.CRAFT[id]
		var ok := GameState.meets_requirements(r, "fabrication")
		v.add_child(_action_card("craft", id, r["name"], _craft_sub(r), ok, _req_text(r, "fabrication")))

func _build_tech() -> void:
	_active_bar = null
	var v := _clear("tech")
	_header(v, "RESEARCH LAB", "")
	for id in GameData.TECH:
		var t: Dictionary = GameData.TECH[id]
		var panel := PanelContainer.new()
		_style_panel(panel, C_CARD, true)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		panel.add_child(row)
		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.add_theme_constant_override("separation", 2)
		row.add_child(left)
		_lbl(left, t["name"], 15, C_TEXT)
		_lbl(left, t["desc"], 11, C_DIM)
		_lbl(left, "Cost: " + _cost_str(t.get("cost", {})), 11, C_ACCENT)

		if GameState.is_unlocked(id):
			_lbl(row, "✓", 20, "6ad36a")
		else:
			var b := Button.new()
			b.text = "Research"
			b.custom_minimum_size = Vector2(92, 40)
			b.focus_mode = Control.FOCUS_NONE
			b.disabled = not GameState.can_unlock(id)
			b.pressed.connect(func() -> void: GameState.unlock_tech(id))
			row.add_child(b)
		v.add_child(panel)

func _build_stats() -> void:
	_active_bar = null
	var v := _clear("stats")

	_header(v, "OPERATIONS", "")
	for sk in ["harvesting", "fabrication"]:
		var lvl := GameState.level_of(sk)
		var cur := int(GameState.skills[sk])
		var base := GameState.xp_for_level(lvl)
		var next := GameState.xp_for_level(lvl + 1)
		var pct: float = 0.0 if next <= base else float(cur - base) / float(next - base) * 100.0
		var panel := PanelContainer.new()
		_style_panel(panel, C_CARD, true)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		panel.add_child(col)
		_lbl(col, "%s — Lv %d" % [sk.capitalize(), lvl], 15, C_TEXT)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 8)
		bar.show_percentage = false
		bar.max_value = 100
		bar.value = pct
		_style_bar(bar)
		col.add_child(bar)
		_lbl(col, "%d / %d XP" % [cur, next], 10, C_MUTED)
		v.add_child(panel)

	_header(v, "STORAGE", "")
	for sym in GameData.RESOURCES:
		var row := HBoxContainer.new()
		var n := Label.new()
		n.text = GameData.res_name(sym)
		n.add_theme_color_override("font_color", GameData.color_for(sym))
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		var amt := Label.new()
		amt.text = GameData.fmt(GameState.amount(sym))
		amt.add_theme_color_override("font_color", Color.html(C_TEXT))
		row.add_child(amt)
		v.add_child(row)

	_header(v, "SYSTEM", "")
	var save_btn := Button.new()
	save_btn.text = "Save Now"
	save_btn.custom_minimum_size = Vector2(0, 42)
	save_btn.focus_mode = Control.FOCUS_NONE
	save_btn.pressed.connect(func() -> void: GameState.save_game())
	v.add_child(save_btn)

	var reset_btn := Button.new()
	reset_btn.text = "Reset Game"
	reset_btn.custom_minimum_size = Vector2(0, 42)
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.add_theme_color_override("font_color", Color.html(C_WARN))
	reset_btn.pressed.connect(func() -> void:
		if _reset_armed:
			GameState.hard_reset()
			_show("gather")
		else:
			_reset_armed = true
			reset_btn.text = "⚠ Tap again to wipe save"
	)
	v.add_child(reset_btn)

# ============================================================ WIDGETS
func _action_card(type: String, id: String, title: String, subtitle: String, unlocked: bool, lock_text: String) -> Control:
	var panel := PanelContainer.new()
	_style_panel(panel, C_CARD, true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 3)
	row.add_child(left)
	_lbl(left, title, 15, C_TEXT if unlocked else C_MUTED)
	_lbl(left, subtitle if unlocked else lock_text, 11, C_DIM if unlocked else C_WARN)

	var is_active := (GameState.active_type == type and GameState.active_id == id)
	if is_active:
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 6)
		bar.show_percentage = false
		bar.max_value = 100
		bar.value = clampf(GameState.progress / maxf(0.01, GameState.current_duration()) * 100.0, 0, 100)
		_style_bar(bar)
		left.add_child(bar)
		_active_bar = bar

	if unlocked:
		var b := Button.new()
		b.text = "Stop" if is_active else "Start"
		b.custom_minimum_size = Vector2(74, 42)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: GameState.start_task(type, id))
		row.add_child(b)
	else:
		_lbl(row, "🔒", 18, C_MUTED)
	return panel

func _header(v: VBoxContainer, title: String, right: String) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color.html(C_MUTED))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	if right != "":
		var r := Label.new()
		r.text = right
		r.add_theme_font_size_override("font_size", 12)
		r.add_theme_color_override("font_color", Color.html(C_ACCENT))
		h.add_child(r)
	v.add_child(h)

func _lbl(parent: Node, text: String, size: int, color: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.html(color))
	parent.add_child(l)
	return l

func _refresh_top() -> void:
	if res_bar == null:
		return
	for c in res_bar.get_children():
		res_bar.remove_child(c)
		c.queue_free()
	for sym in GameData.RESOURCES:
		var l := Label.new()
		l.text = "%s %s" % [GameData.res_name(sym), GameData.fmt(GameState.amount(sym))]
		l.add_theme_color_override("font_color", GameData.color_for(sym))
		l.add_theme_font_size_override("font_size", 13)
		res_bar.add_child(l)

# ============================================================ MODAL
func _show_offline(text: String) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	_style_panel(panel, C_CARD, true)
	panel.custom_minimum_size = Vector2(300, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	_lbl(v, "◷ Welcome Back, Commander", 16, C_ACCENT)
	_lbl(v, text, 13, C_TEXT)
	var ok := Button.new()
	ok.text = "Collect"
	ok.custom_minimum_size = Vector2(0, 42)
	ok.focus_mode = Control.FOCUS_NONE
	ok.pressed.connect(func() -> void: overlay.queue_free())
	v.add_child(ok)

# ============================================================ TEXT HELPERS
func _active_text() -> String:
	if GameState.active_type == "gather":
		return "▶ Harvesting: " + GameData.GATHER[GameState.active_id]["name"]
	elif GameState.active_type == "craft":
		return "▶ Crafting: " + GameData.CRAFT[GameState.active_id]["name"]
	return "Idle — tap an action to begin"

func _gather_sub(a: Dictionary) -> String:
	return "+%d-%d %s  ·  %.1fs  ·  +%d xp" % [
		int(a["min"]), int(a["max"]), GameData.res_name(a["resource"]),
		float(a["duration"]), int(a.get("xp", 0))]

func _craft_sub(r: Dictionary) -> String:
	var parts := []
	for sym in r["inputs"]:
		parts.append("%d %s" % [int(r["inputs"][sym]), GameData.res_name(sym)])
	return "%s → %d %s  ·  +%d xp" % [
		" + ".join(parts), int(r.get("amount", 1)), GameData.res_name(r["output"]), int(r.get("xp", 0))]

func _req_text(def: Dictionary, skill: String) -> String:
	var parts := []
	if int(def.get("level_req", 1)) > 1:
		parts.append("Lv %d %s" % [int(def["level_req"]), skill.capitalize()])
	var tr: String = def.get("tech_req", "")
	if tr != "":
		parts.append("Research: " + GameData.TECH.get(tr, {}).get("name", tr))
	if parts.is_empty():
		return "🔒 Locked"
	return "🔒 Requires " + ", ".join(parts)

func _cost_str(cost: Dictionary) -> String:
	var parts := []
	for sym in cost:
		parts.append("%d %s" % [int(cost[sym]), GameData.res_name(sym)])
	return ", ".join(parts) if not parts.is_empty() else "Free"

# ============================================================ STYLE
func _style_panel(p: Control, hex: String, border: bool = false) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color.html(hex)
	s.set_corner_radius_all(10)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	if border:
		s.set_border_width_all(1)
		s.border_color = Color.html(C_BORDER)
	p.add_theme_stylebox_override("panel", s)

func _style_tab(b: Button, active: bool) -> void:
	b.add_theme_color_override("font_color", Color.html(C_ACCENT if active else C_MUTED))
	b.add_theme_color_override("font_color_hover", Color.html(C_ACCENT if active else C_DIM))
	b.add_theme_color_override("font_color_pressed", Color.html(C_ACCENT))
	b.add_theme_font_size_override("font_size", 13)
	var bgc := "16273f" if active else "00000000"
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.html(bgc)
		sb.set_corner_radius_all(8)
		b.add_theme_stylebox_override(state, sb)

func _style_bar(b: ProgressBar) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color.html("0c1626")
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color.html(C_ACCENT)
	fg.set_corner_radius_all(3)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
