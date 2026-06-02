extends Control
## Mobile-first shell: top resource HUD, swappable content pages, bottom tab bar.
## Grid-card layout (gather/craft) + tabbed research trees, styled after the desktop build.

const TABS := [
	{"id": "gather", "label": "Gather"},
	{"id": "craft",  "label": "Craft"},
	{"id": "tech",   "label": "Tech"},
	{"id": "stats",  "label": "More"},
]

# Palette
const C_BG := "0b1220"
const C_PANEL := "111c2e"
const C_TEXT := "e6ebf2"
const C_DIM := "8a93a5"
const C_MUTED := "5a6478"
const C_WARN := "d9a441"
# Per-page accents
const GOLD := "d9b24c"
const CYAN := "4fd2e0"
const GREEN := "5ad17a"
const PURPLE := "2e2750"

var content: Control
var pages := {}
var tab_buttons := {}
var current := ""
var tech_cat := "operations"
var res_bar: HBoxContainer
var active_label: Label
var _active_bar: ProgressBar = null
var _active_timer: Label = null
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
	if GameState.active_type != "":
		var dur := GameState.current_duration()
		if dur > 0.0:
			if is_instance_valid(_active_bar):
				_active_bar.value = clampf(GameState.progress / dur * 100.0, 0.0, 100.0)
			if is_instance_valid(_active_timer):
				_active_timer.text = "%.1fs / %.1fs" % [GameState.progress, dur]
	if active_label:
		active_label.text = _active_text()

func _on_resources() -> void:
	_refresh_top()
	_refresh_current()

# ============================================================ SHELL
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

	var top := PanelContainer.new()
	_style_panel(top, C_PANEL)
	root.add_child(top)
	var topv := VBoxContainer.new()
	topv.add_theme_constant_override("separation", 4)
	top.add_child(topv)
	var title := Label.new()
	title.text = "✦ STELLAR FORGE"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color.html(CYAN))
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

	content = Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(content)
	for t in TABS:
		var page := _make_page()
		page.visible = false
		content.add_child(page)
		pages[t.id] = page

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
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
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

# ============================================================ GATHER / CRAFT PAGES
func _build_gather() -> void:
	_active_bar = null
	_active_timer = null
	var v := _clear("gather")
	_skill_banner(v, "PLANETARY HARVESTING", "harvesting", GOLD)
	_section(v, "TERRESTRIAL OPERATIONS", GOLD)
	var g := _grid(v)
	for id in GameData.GATHER:
		g.add_child(_gather_card(id, GameData.GATHER[id]))

func _build_craft() -> void:
	_active_bar = null
	_active_timer = null
	var v := _clear("craft")
	_skill_banner(v, "ENGINEERING", "fabrication", CYAN)
	_section(v, "BASIC OPERATIONS", CYAN)
	var g := _grid(v)
	for id in GameData.CRAFT:
		g.add_child(_craft_card(id, GameData.CRAFT[id]))

func _gather_card(id: String, a: Dictionary) -> Control:
	var unlocked := GameState.meets_requirements(a, "harvesting")
	var active := (GameState.active_type == "gather" and GameState.active_id == id)
	var v := _card(GOLD, unlocked or active)

	_card_head(v, "↑", a["name"], "Lv %d" % int(a.get("level_req", 1)), GOLD, unlocked)
	if unlocked:
		_inset(v, "YIELD", [_line("%s: %d-%d" % [GameData.res_name(a["resource"]), int(a["min"]), int(a["max"])], C_TEXT)], GOLD)
		_action_controls(v, "gather", id, active, GOLD)
	else:
		_locked(v, a, "harvesting")
	return v.get_parent()

func _craft_card(id: String, r: Dictionary) -> Control:
	var unlocked := GameState.meets_requirements(r, "fabrication")
	var active := (GameState.active_type == "craft" and GameState.active_id == id)
	var affordable := GameState.can_afford(r.get("inputs", {}))
	var v := _card(CYAN, unlocked or active)

	_card_head(v, "⚙", r["name"], "Lv %d" % int(r.get("level_req", 1)), CYAN, unlocked)
	if unlocked:
		var in_lines := []
		for sym in r["inputs"]:
			in_lines.append(_line("%d %s" % [int(r["inputs"][sym]), GameData.res_name(sym)], _hex(GameData.color_for(sym))))
		_inset(v, "INPUTS", in_lines, CYAN)
		var d := Label.new()
		d.text = "▼ REFINE ▼"
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.add_theme_font_size_override("font_size", 9)
		d.add_theme_color_override("font_color", Color.html(CYAN))
		v.add_child(d)
		_inset(v, "OUTPUT", [_line("%d %s" % [int(r.get("amount", 1)), GameData.res_name(r["output"])], C_TEXT)], CYAN, true)
		if active or affordable:
			_action_controls(v, "craft", id, active, CYAN)
		else:
			var b := _card_button("Missing Materials", C_MUTED, false)
			v.add_child(b)
			_progress(v, false, CYAN)
	else:
		_locked(v, r, "fabrication")
	return v.get_parent()

func _action_controls(v: VBoxContainer, type: String, id: String, active: bool, accent: String) -> void:
	var b := _card_button("Stop" if active else "Start", accent, true)
	b.pressed.connect(func() -> void: GameState.start_task(type, id))
	v.add_child(b)
	var t := Label.new()
	var dur := GameState.effective_duration(type, id)
	t.text = "%.1fs / %.1fs" % [GameState.progress if active else 0.0, dur]
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 10)
	t.add_theme_color_override("font_color", Color.html(C_MUTED))
	v.add_child(t)
	if active:
		_active_timer = t
	_progress(v, active, accent)

func _locked(v: VBoxContainer, def: Dictionary, skill: String) -> void:
	var l := Label.new()
	l.text = "LOCKED"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color.html(C_WARN))
	v.add_child(l)
	var r := Label.new()
	r.text = _req_text(def, skill)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_theme_font_size_override("font_size", 10)
	r.add_theme_color_override("font_color", Color.html(C_MUTED))
	v.add_child(r)

# ============================================================ TECH TREES
func _build_tech() -> void:
	_active_bar = null
	_active_timer = null
	var v := _clear("tech")
	var title := Label.new()
	title.text = "RESEARCH NETWORK"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color.html(CYAN))
	v.add_child(title)

	# Category sub-tabs
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	v.add_child(tabs)
	for cat in GameData.TECH_CATS:
		var b := Button.new()
		b.text = cat.label
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 34)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_subtab(b, cat.id == tech_cat)
		b.pressed.connect(func() -> void:
			tech_cat = cat.id
			_build_tech()
		)
		tabs.add_child(b)

	# Build the tree for the active category, grouped into tiers by depth.
	var tiers := {}
	for id in GameData.TECH:
		if GameData.TECH[id].get("cat", "") == tech_cat:
			var d := _depth(id)
			if not tiers.has(d):
				tiers[d] = []
			tiers[d].append(id)
	var depths := tiers.keys()
	depths.sort()
	var first := true
	for d in depths:
		if not first:
			_connector(v)
		first = false
		var row := GridContainer.new()
		row.columns = 2
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 8)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(row)
		for id in tiers[d]:
			row.add_child(_tech_node(id))

func _depth(id: String) -> int:
	var reqs: Array = GameData.TECH[id].get("req", [])
	if reqs.is_empty():
		return 0
	var m := 0
	for r in reqs:
		if GameData.TECH.has(r):
			m = maxi(m, _depth(r) + 1)
	return m

func _tech_node(id: String) -> Control:
	var t: Dictionary = GameData.TECH[id]
	var researched := GameState.is_unlocked(id)
	var available := GameState.can_unlock(id)
	var border := GREEN if researched else (GOLD if available else "453c6b")

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bordered("241f3e", border, 2 if (available or researched) else 1))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	panel.add_child(v)

	var name_l := Label.new()
	name_l.text = t["name"]
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.add_theme_font_size_override("font_size", 13)
	name_l.add_theme_color_override("font_color", Color.html(C_TEXT if (available or researched) else C_MUTED))
	v.add_child(name_l)

	if researched:
		var ok := Label.new()
		ok.text = "✓ Researched"
		ok.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ok.add_theme_font_size_override("font_size", 10)
		ok.add_theme_color_override("font_color", Color.html(GREEN))
		v.add_child(ok)
	else:
		var desc := Label.new()
		desc.text = t.get("desc", "")
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 9)
		desc.add_theme_color_override("font_color", Color.html(C_DIM))
		v.add_child(desc)
		for sym in t.get("cost", {}):
			var c := Label.new()
			c.text = "%d %s" % [int(t["cost"][sym]), GameData.res_name(sym)]
			c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			c.add_theme_font_size_override("font_size", 10)
			var have := GameState.amount(sym) >= int(t["cost"][sym])
			c.add_theme_color_override("font_color", Color.html(GOLD if have else C_WARN))
			v.add_child(c)
		# Whole-card tap target
		var overlay := Button.new()
		overlay.flat = true
		overlay.focus_mode = Control.FOCUS_NONE
		overlay.disabled = not available
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.pressed.connect(func() -> void: GameState.unlock_tech(id))
		panel.add_child(overlay)
	return panel

func _connector(v: VBoxContainer) -> void:
	var c := CenterContainer.new()
	var line := ColorRect.new()
	line.color = Color.html(CYAN)
	line.custom_minimum_size = Vector2(3, 16)
	c.add_child(line)
	v.add_child(c)

# ============================================================ STATS PAGE
func _build_stats() -> void:
	_active_bar = null
	_active_timer = null
	var v := _clear("stats")
	_section(v, "OPERATIONS", CYAN)
	for sk in ["harvesting", "fabrication"]:
		_skill_banner(v, sk.to_upper(), sk, CYAN if sk == "fabrication" else GOLD)

	_section(v, "STORAGE", CYAN)
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

	_section(v, "SYSTEM", CYAN)
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

# ============================================================ REUSABLE PIECES
func _grid(v: VBoxContainer) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(g)
	return g

## Creates a bordered card panel, adds it to nothing yet; returns the inner VBox.
## Caller does `card.get_parent()` to retrieve the panel for placement.
func _card(accent: String, lit: bool) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bordered("1a2336", accent if lit else "2a3550", 2 if lit else 1))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	return v

func _card_head(v: VBoxContainer, icon: String, name: String, badge: String, accent: String, lit: bool) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 5)
	var ic := Label.new()
	ic.text = icon
	ic.add_theme_font_size_override("font_size", 13)
	ic.add_theme_color_override("font_color", Color.html(accent if lit else C_MUTED))
	hb.add_child(ic)
	var nm := Label.new()
	nm.text = name
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.add_theme_font_size_override("font_size", 13)
	nm.add_theme_color_override("font_color", Color.html(C_TEXT if lit else C_MUTED))
	hb.add_child(nm)
	var bd := PanelContainer.new()
	bd.add_theme_stylebox_override("panel", _bordered("12192a", accent if lit else "2a3550", 1, 4))
	var bl := Label.new()
	bl.text = badge
	bl.add_theme_font_size_override("font_size", 9)
	bl.add_theme_color_override("font_color", Color.html(accent if lit else C_MUTED))
	bd.add_child(bl)
	hb.add_child(bd)
	v.add_child(hb)

func _inset(v: VBoxContainer, title: String, lines: Array, accent: String, highlight := false) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bordered("12192a", accent if highlight else "2a3550", 2 if highlight else 1, 5))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	panel.add_child(box)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 8)
	t.add_theme_color_override("font_color", Color.html(C_MUTED))
	box.add_child(t)
	for ln in lines:
		var l := Label.new()
		l.text = ln["text"]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color.html(ln["color"]))
		box.add_child(l)
	v.add_child(panel)

func _line(text: String, color: String) -> Dictionary:
	return {"text": text, "color": color}

func _card_button(text: String, accent: String, enabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 34)
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := _bordered("12192a", accent if enabled else "2a3550", 1, 5)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color.html(accent if enabled else C_MUTED))
	b.add_theme_color_override("font_color_disabled", Color.html(C_MUTED))
	b.add_theme_color_override("font_color_hover", Color.html(accent))
	b.add_theme_color_override("font_color_pressed", Color.html(C_TEXT))
	return b

func _progress(v: VBoxContainer, active: bool, accent: String) -> void:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0, 14)
	var bar := ProgressBar.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = 0
	_style_bar(bar, accent)
	wrap.add_child(bar)
	var lbl := Label.new()
	lbl.text = "" if active else "READY"
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", Color.html(C_MUTED))
	wrap.add_child(lbl)
	v.add_child(wrap)
	if active:
		_active_bar = bar

func _skill_banner(v: VBoxContainer, title: String, skill_id: String, accent: String) -> void:
	var lvl := GameState.level_of(skill_id)
	var cur := int(GameState.skills.get(skill_id, 0))
	var base := GameState.xp_for_level(lvl)
	var next := GameState.xp_for_level(lvl + 1)
	var pct: float = 100.0 if next <= base else float(cur - base) / float(next - base) * 100.0
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 16)
	t.add_theme_color_override("font_color", Color.html(accent))
	box.add_child(t)
	var hb := HBoxContainer.new()
	var lv := Label.new()
	lv.text = "Level %d" % lvl
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_theme_font_size_override("font_size", 12)
	lv.add_theme_color_override("font_color", Color.html(C_TEXT))
	hb.add_child(lv)
	var xp := Label.new()
	xp.text = "%d / %d XP" % [cur, next]
	xp.add_theme_font_size_override("font_size", 10)
	xp.add_theme_color_override("font_color", Color.html(C_DIM))
	hb.add_child(xp)
	box.add_child(hb)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = pct
	_style_bar(bar, accent)
	box.add_child(bar)
	v.add_child(box)

func _section(v: VBoxContainer, text: String, accent: String) -> void:
	var l := Label.new()
	l.text = "[ %s ]" % text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color.html(accent))
	v.add_child(l)

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
	panel.add_theme_stylebox_override("panel", _bordered("1a2336", CYAN, 2))
	panel.custom_minimum_size = Vector2(300, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var t := Label.new()
	t.text = "◷ Welcome Back, Commander"
	t.add_theme_font_size_override("font_size", 16)
	t.add_theme_color_override("font_color", Color.html(CYAN))
	v.add_child(t)
	var body := Label.new()
	body.text = text
	body.add_theme_color_override("font_color", Color.html(C_TEXT))
	v.add_child(body)
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

func _req_text(def: Dictionary, skill: String) -> String:
	var parts := []
	if int(def.get("level_req", 1)) > 1:
		parts.append("Lv %d %s" % [int(def["level_req"]), skill.capitalize()])
	var tr: String = def.get("tech_req", "")
	if tr != "":
		parts.append("Research: " + GameData.TECH.get(tr, {}).get("name", tr))
	if parts.is_empty():
		return "Locked"
	return "Requires " + ", ".join(parts)

func _hex(c: Color) -> String:
	return c.to_html(false)

# ============================================================ STYLE
func _bordered(bg: String, border: String, width := 2, radius := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color.html(bg)
	s.set_corner_radius_all(radius)
	s.set_border_width_all(width)
	s.border_color = Color.html(border)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _style_panel(p: Control, hex: String) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color.html(hex)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", s)

func _style_tab(b: Button, active: bool) -> void:
	b.add_theme_color_override("font_color", Color.html(CYAN if active else C_MUTED))
	b.add_theme_color_override("font_color_hover", Color.html(CYAN if active else C_DIM))
	b.add_theme_color_override("font_color_pressed", Color.html(CYAN))
	b.add_theme_font_size_override("font_size", 13)
	var bgc := "16273f" if active else "00000000"
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.html(bgc)
		sb.set_corner_radius_all(8)
		b.add_theme_stylebox_override(state, sb)

func _style_subtab(b: Button, active: bool) -> void:
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", Color.html(CYAN if active else C_DIM))
	b.add_theme_color_override("font_color_hover", Color.html(CYAN))
	b.add_theme_color_override("font_color_pressed", Color.html(CYAN))
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, _bordered("241f3e" if active else "171326", CYAN if active else "453c6b", 1, 6))

func _style_bar(b: ProgressBar, accent: String) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color.html("0c1626")
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color.html(accent)
	fg.set_corner_radius_all(3)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
