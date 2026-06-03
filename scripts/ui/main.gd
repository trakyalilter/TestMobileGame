extends Control
## Mobile shell for the ported horizonidle content: grid cards with category
## sub-tabs (gather/craft/combat) and a credit-funded research tree.

# Bottom bar = primary loops; secondary systems live under "More".
const BOTTOM := [
	{"id": "gather",   "label": "Gather"},
	{"id": "craft",    "label": "Craft"},
	{"id": "combat",   "label": "Combat"},
	{"id": "research", "label": "Research"},
	{"id": "more",     "label": "More"},
]
const PAGE_IDS := ["gather", "craft", "combat", "research", "more", "build", "ship", "bounty", "warp", "missions", "stats"]
const MORE_MENU := [
	{"id": "missions", "label": "✦  Missions"},
	{"id": "build",  "label": "⌂  Infrastructure"},
	{"id": "ship",   "label": "⛭  Ship Designer"},
	{"id": "bounty", "label": "◆  Bounty Board"},
	{"id": "warp",   "label": "✦  Warp Core"},
	{"id": "stats",  "label": "≡  Storage & Crew"},
]

# ---- Design system tokens ----
const BG_TOP := "0d1426"      # app background gradient
const BG_BOT := "060912"
const SURFACE := "172238"     # card surface
const SURFACE_HI := "1f2c48"  # raised chips / segmented
const INSET := "0c1322"       # recessed wells
const LINE := "2b374f"        # hairline borders / dividers
const C_TEXT := "eef2fb"
const C_DIM := "9aa7c2"
const C_MUTED := "5d6b88"
const C_WARN := "ecb44a"
const GOLD := "ecb44a"
const CYAN := "55d3e6"
const GREEN := "5fd585"
const RED := "ef6a52"
const PURP := "b78ae8"
const BUILD := "ef9a54"
const C_BG := "0b1220"        # legacy refs
const C_PANEL := "111c2e"
const DOMAIN := {"gather": GOLD, "craft": CYAN, "combat": RED, "research": PURP, "more": CYAN}
const NAV_ICON := {"gather": "↑", "craft": "⚙", "combat": "◎", "research": "✦", "more": "≡"}

# Global text scale — bumps every font size for phone readability without
# touching individual call sites. Tune this one number to rescale the whole UI.
const FONT_SCALE := 1.28
func _fs(n: int) -> int:
	return int(round(n * FONT_SCALE))

var content: Control
var pages := {}
var nav_items := {}
var current := ""
var gather_cat := "terrestrial"
var craft_cat := "basics"
var combat_zone := 0
var build_cat := "power"
var ship_view := "loadout"
var ship_mod_slot := "weapon"
var res_bar: HBoxContainer
var safe_margin: MarginContainer
var active_banner: PanelContainer
var _banner_chip: PanelContainer
var _banner_icon: Label
var _banner_kind: Label
var _banner_name: Label
var _banner_time: Label
var _banner_bar: ProgressBar
var _active_bar: ProgressBar = null
var _active_timer: Label = null
var _combat_hp_bar: ProgressBar = null
var _combat_hp_label: Label = null
var _enemy_hp_bar: ProgressBar = null
var _enemy_hp_label: Label = null
var _enemy_shield_bar: ProgressBar = null
var _player_shield_bar: ProgressBar = null
var _player_heat_bar: ProgressBar = null
var _enemy_anchor: Control = null
var _player_anchor: Control = null
var _seen_events := 0
var _reset_armed := false
var _warp_armed := false

func _ready() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
	_apply_theme()
	_build()
	GameState.resources_changed.connect(_on_resources)
	GameState.skills_changed.connect(_refresh_current)
	GameState.research_changed.connect(_refresh_all)
	GameState.action_changed.connect(_refresh_current)
	GameState.action_changed.connect(_refresh_banner)
	GameState.bounty_changed.connect(_refresh_current)
	GameState.missions_changed.connect(_refresh_current)
	get_viewport().size_changed.connect(_update_safe_area)
	call_deferred("_update_safe_area")
	_refresh_top()
	_refresh_banner()
	_show("gather")
	if GameState.pending_offline != "":
		_show_offline(GameState.pending_offline)
		GameState.pending_offline = ""

## Branded display font (Rajdhani) with Noto symbol fallbacks so glyph icons
## render on devices whose system font lacks them.
func _apply_theme() -> void:
	var f = load("res://assets/fonts/Rajdhani-Medium.ttf")
	if f is FontFile:
		var fb: Array = []
		var s2 = load("res://assets/fonts/NotoSansSymbols2-Regular.ttf")
		var s1 = load("res://assets/fonts/NotoSansSymbols-VF.ttf")
		if s2: fb.append(s2)
		if s1: fb.append(s1)
		f.fallbacks = fb
		var th := Theme.new()
		th.default_font = f
		th.default_font_size = _fs(14)
		theme = th

## Pads the UI clear of the status bar / notch / gesture bar.
func _update_safe_area() -> void:
	if safe_margin == null:
		return
	var safe := DisplayServer.get_display_safe_area()
	var ws := DisplayServer.window_get_size()
	if ws.x <= 0 or ws.y <= 0:
		return
	var vp := get_viewport().get_visible_rect().size
	var top := int(safe.position.y * vp.y / ws.y)
	var bottom := int((ws.y - safe.position.y - safe.size.y) * vp.y / ws.y)
	safe_margin.add_theme_constant_override("margin_top", maxi(top, 0))
	safe_margin.add_theme_constant_override("margin_bottom", maxi(bottom, 0))

func _process(_delta: float) -> void:
	if GameState.active_type != "":
		var dur := GameState.current_duration()
		if dur > 0.0:
			var pct := clampf(GameState.progress / dur * 100.0, 0.0, 100.0)
			if is_instance_valid(_active_bar):
				_active_bar.value = pct
			if is_instance_valid(_active_timer):
				_active_timer.text = "%.1fs / %.1fs" % [GameState.progress, dur]
			if is_instance_valid(_banner_bar):
				_banner_bar.value = pct
			if is_instance_valid(_banner_time):
				_banner_time.text = "%.1fs" % maxf(0.0, dur - GameState.progress)
	if is_instance_valid(_combat_hp_bar):
		var mx := GameState.combat_max_hp()
		_combat_hp_bar.max_value = mx
		_combat_hp_bar.value = GameState.combat_hp
		if is_instance_valid(_combat_hp_label):
			_combat_hp_label.text = "%d / %d" % [int(GameState.combat_hp), int(mx)]
	if current == "combat" and GameState.active_type == "combat" and not GameState.enemy_inst.is_empty():
		var e: Dictionary = GameState.enemy_inst
		if is_instance_valid(_enemy_hp_bar):
			_enemy_hp_bar.max_value = e["max_hp"]
			_enemy_hp_bar.value = e["hp"]
			if is_instance_valid(_enemy_hp_label):
				_enemy_hp_label.text = "%d / %d" % [int(e["hp"]), int(e["max_hp"])]
		if is_instance_valid(_enemy_shield_bar):
			_enemy_shield_bar.max_value = maxf(1.0, e["max_shield"])
			_enemy_shield_bar.value = e["shield"]
		if is_instance_valid(_player_shield_bar):
			_player_shield_bar.max_value = maxf(1.0, GameState.player_max_shield())
			_player_shield_bar.value = GameState.player_shield
		if is_instance_valid(_player_heat_bar):
			_player_heat_bar.max_value = GameState.MAX_HEAT
			_player_heat_bar.value = GameState.player_heat
		_drain_combat_events()

func _on_resources() -> void:
	_refresh_top()
	_refresh_current()

# ============================================================ SHELL
func _build() -> void:
	var bg := TextureRect.new()
	bg.texture = _grad_tex(BG_TOP, BG_BOT)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	safe_margin = MarginContainer.new()
	safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(safe_margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	safe_margin.add_child(root)

	# ---- Top HUD ----
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _hud_style())
	root.add_child(top)
	var topv := VBoxContainer.new()
	topv.add_theme_constant_override("separation", 8)
	top.add_child(topv)
	var title := Label.new()
	title.text = "✦  STELLAR FORGE"
	title.add_theme_font_size_override("font_size", _fs(15))
	title.add_theme_color_override("font_color", Color.html(CYAN))
	topv.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 38)
	topv.add_child(scroll)
	res_bar = HBoxContainer.new()
	res_bar.add_theme_constant_override("separation", 6)
	scroll.add_child(res_bar)
	active_banner = _build_active_banner()
	topv.add_child(active_banner)

	# ---- Content ----
	content = Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(content)
	for pid in PAGE_IDS:
		var page := _make_page()
		page.visible = false
		content.add_child(page)
		pages[pid] = page

	# ---- Bottom nav ----
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", _nav_style())
	root.add_child(bottom)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	bottom.add_child(tabs)
	for t in BOTTOM:
		tabs.add_child(_make_nav_item(t.id, t.label))

func _make_nav_item(id: String, label: String) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 78)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, empty)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(vb)
	var icon := Label.new()
	icon.text = NAV_ICON.get(id, "•")
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", _fs(21))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(icon)
	var lab := Label.new()
	lab.text = label
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", _fs(11))
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(lab)
	var dc := CenterContainer.new()
	dc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(16, 3)
	dc.add_child(dot)
	vb.add_child(dc)
	btn.pressed.connect(_show.bind(id))
	nav_items[id] = {"icon": icon, "label": lab, "dot": dot}
	return btn

func _make_page() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 10)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(m)
	var v := VBoxContainer.new()
	v.name = "List"
	v.add_theme_constant_override("separation", 9)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(v)
	return sc

# ============================================================ NAV
func _show(id: String) -> void:
	current = id
	_reset_armed = false
	_warp_armed = false
	for pid in pages:
		pages[pid].visible = (pid == id)
	var hl: String = id if nav_items.has(id) else "more"
	for bid in nav_items:
		_style_nav(bid, bid == hl)
	_refresh_current()

func _refresh_all() -> void:
	_refresh_top()
	_refresh_current()

func _refresh_current() -> void:
	_active_bar = null
	_active_timer = null
	_combat_hp_bar = null
	_combat_hp_label = null
	_enemy_hp_bar = null
	_enemy_hp_label = null
	_enemy_shield_bar = null
	_player_shield_bar = null
	_player_heat_bar = null
	_enemy_anchor = null
	_player_anchor = null
	match current:
		"gather":   _build_gather()
		"craft":    _build_craft()
		"combat":   _build_combat()
		"build":    _build_infra()
		"ship":     _build_ship()
		"bounty":   _build_bounty()
		"warp":     _build_warp()
		"missions": _build_missions()
		"research": _build_research()
		"more":     _build_more()
		"stats":    _build_stats()
	# Let touch drags fall through cards to the page's ScrollContainer so the
	# whole content surface scrolls (not just the dark background gaps). Panels
	# and containers default to MOUSE_FILTER_STOP, which eats the drag.
	if pages.has(current):
		_scroll_passthrough(pages[current])

# Recursively switch non-interactive controls from STOP to PASS so the parent
# ScrollContainer still receives touch-drag events. Buttons/sliders/inputs keep
# STOP so taps and drags on them keep working.
func _scroll_passthrough(node: Node) -> void:
	for c in node.get_children():
		if c is Control and not (c is BaseButton or c is Slider or c is LineEdit or c is TextEdit or c is ScrollContainer):
			if c.mouse_filter == Control.MOUSE_FILTER_STOP:
				c.mouse_filter = Control.MOUSE_FILTER_PASS
		_scroll_passthrough(c)

func _clear(id: String) -> VBoxContainer:
	var v: VBoxContainer = pages[id].find_child("List", true, false)
	for c in v.get_children():
		v.remove_child(c)
		c.queue_free()
	return v

# ============================================================ GATHER
func _build_gather() -> void:
	var v := _clear("gather")
	_skill_banner(v, "PLANETARY HARVESTING", "harvesting", GOLD)
	_subtabs(v, GameData.GATHER_CATS, gather_cat, GOLD, func(id: String) -> void:
		gather_cat = id
		_build_gather())
	var g := _grid(v)
	var any := false
	for id in GameData.GATHER:
		var a: Dictionary = GameData.GATHER[id]
		if a.get("category", "terrestrial") != gather_cat:
			continue
		any = true
		g.add_child(_gather_card(id, a))
	if not any:
		_empty(v, "No operations here yet.")

func _gather_card(id: String, a: Dictionary) -> Control:
	var unlocked := GameState.meets_requirements(a, "harvesting")
	var active := (GameState.active_type == "gather" and GameState.active_id == id)
	var v := _card(GOLD, unlocked or active, 196)
	_card_head(v, "↑", a["name"], "Lv %d" % int(a.get("level_req", 1)), GOLD, unlocked)
	if unlocked:
		_inset(v, "YIELD", _loot_lines(a.get("loot", [])), GOLD)
		_action_controls(v, "gather", id, active, GOLD)
	else:
		_locked(v, a, "harvesting")
	return v.get_parent()

# ============================================================ CRAFT
func _build_craft() -> void:
	var v := _clear("craft")
	_skill_banner(v, "ENGINEERING", "fabrication", CYAN)
	_subtabs(v, GameData.CRAFT_CATS, craft_cat, CYAN, func(id: String) -> void:
		craft_cat = id
		_build_craft())
	var g := _grid(v)
	var any := false
	for id in GameData.CRAFT:
		var r: Dictionary = GameData.CRAFT[id]
		if r.get("category", "misc") != craft_cat:
			continue
		any = true
		g.add_child(_craft_card(id, r))
	if not any:
		_empty(v, "No recipes in this category.")

func _craft_card(id: String, r: Dictionary) -> Control:
	var unlocked := GameState.meets_requirements(r, "fabrication")
	var active := (GameState.active_type == "craft" and GameState.active_id == id)
	var affordable := GameState.can_afford(r.get("inputs", {}))
	var v := _card(CYAN, unlocked or active, 248)
	_card_head(v, "⚙", r["name"], "Lv %d" % int(r.get("level_req", 1)), CYAN, unlocked)
	if unlocked:
		var in_lines := []
		for sym in r.get("inputs", {}):
			in_lines.append(_line("%d %s" % [int(r["inputs"][sym]), GameData.res_name(sym)], _hex(GameData.color_for(sym))))
		_inset(v, "INPUTS", in_lines, CYAN)
		var d := Label.new()
		d.text = "▼"
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.add_theme_font_size_override("font_size", _fs(9))
		d.add_theme_color_override("font_color", Color.html(CYAN))
		v.add_child(d)
		var out_lines := []
		for sym in r.get("outputs", {}):
			out_lines.append(_line("%d %s" % [int(r["outputs"][sym]), GameData.res_name(sym)], C_TEXT))
		for row in r.get("bonus", []):
			out_lines.append(_line("+%d%% %s" % [int(float(row[1]) * 100.0), GameData.res_name(row[0])], _hex(GameData.color_for(row[0]))))
		_inset(v, "OUTPUT", out_lines, CYAN, true)
		if active or affordable:
			_action_controls(v, "craft", id, active, CYAN)
		else:
			v.add_child(_card_button("Missing Materials", C_MUTED, false))
			_progress(v, false, CYAN)
	else:
		_locked(v, r, "fabrication")
	return v.get_parent()

# ============================================================ COMBAT
func _build_combat() -> void:
	var v := _clear("combat")
	if GameState.active_type == "combat" and not GameState.enemy_inst.is_empty():
		_build_battle(v)
	else:
		_build_targets(v)

func _build_targets(v: VBoxContainer) -> void:
	_skill_banner(v, "BATTLE STATION", "combat", RED)
	# Hull status + repair (no passive regen)
	var hp := GameState.combat_hp
	var mhp := GameState.combat_max_hp()
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	var hl := Label.new()
	hl.text = "Hull  %d / %d" % [int(hp), int(mhp)]
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hl.add_theme_font_size_override("font_size", _fs(12))
	hl.add_theme_color_override("font_color", Color.html(GREEN if hp >= mhp else C_WARN))
	hrow.add_child(hl)
	if hp < mhp:
		var cost := GameState.repair_cost()
		var rb := _card_button("Repair ₡%s" % GameData.fmt(cost), GREEN, GameState.credits >= cost)
		rb.custom_minimum_size = Vector2(140, 34)
		if GameState.credits >= cost:
			rb.pressed.connect(func() -> void: GameState.repair_hull())
		hrow.add_child(rb)
	v.add_child(hrow)
	var zone_items := []
	for z in GameData.ZONES:
		zone_items.append({"id": z["id"], "label": z["name"]})
	combat_zone = clampi(combat_zone, 0, GameData.ZONES.size() - 1)
	var cur_zone_id: String = GameData.ZONES[combat_zone]["id"]
	_subtabs(v, zone_items, cur_zone_id, RED, func(id: String) -> void:
		for i in GameData.ZONES.size():
			if GameData.ZONES[i]["id"] == id:
				combat_zone = i
		_build_combat())
	var zone: Dictionary = GameData.ZONES[combat_zone]
	_section(v, zone.get("desc", ""), RED)
	var g := _grid(v)
	for eid in zone.get("enemies", []):
		if GameData.ENEMIES.has(eid):
			g.add_child(_enemy_card(eid, GameData.ENEMIES[eid]))

func _enemy_card(id: String, e: Dictionary) -> Control:
	var v := _card(RED, true)
	_card_head(v, "◎", e["name"], "", RED, true)
	var stats := [
		_line("HP %s" % GameData.fmt(e["hp"]), C_TEXT),
		_line("ATK %d / %.1fs" % [int(e.get("atk", 0)), float(e.get("interval", 2.0))], C_WARN),
		_line("DEF %d" % int(e.get("def", 0)), C_DIM),
	]
	if int(e.get("max_shield", 0)) > 0:
		stats.insert(1, _line("Shield %s" % GameData.fmt(e["max_shield"]), CYAN))
	_inset(v, "TARGET", stats, RED)
	_inset(v, "SALVAGE", _loot_lines(e.get("loot", [])), RED)
	var b := _card_button("Engage", RED, true)
	b.pressed.connect(func() -> void: GameState.start_task("combat", id))
	v.add_child(b)
	return v.get_parent()

# ---- Live battle view ----
func _build_battle(v: VBoxContainer) -> void:
	var e: Dictionary = GameState.enemy_inst
	_skill_banner(v, "BATTLE STATION", "combat", RED)

	# Enemy combatant
	var ep := _card(RED, true)
	_card_head(ep, "◎", e["name"], "", RED, true)
	var er := HBoxContainer.new()
	var ehl := Label.new()
	ehl.text = "ENEMY HULL"
	ehl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ehl.add_theme_font_size_override("font_size", _fs(9))
	ehl.add_theme_color_override("font_color", Color.html(RED))
	er.add_child(ehl)
	_enemy_hp_label = Label.new()
	_enemy_hp_label.add_theme_font_size_override("font_size", _fs(9))
	_enemy_hp_label.add_theme_color_override("font_color", Color.html(C_DIM))
	er.add_child(_enemy_hp_label)
	ep.add_child(er)
	_enemy_hp_bar = _mk_bar(ep, RED, 9)
	if float(e["max_shield"]) > 0.0:
		_enemy_shield_bar = _mk_bar(ep, CYAN, 5)
	_enemy_anchor = _add_anchor(ep)
	v.add_child(ep.get_parent())

	# Player combatant
	var pp := _card(CYAN, true)
	var hull: Dictionary = GameData.HULLS.get(GameState.active_hull, {})
	_card_head(pp, "◇", hull.get("name", "Ship"), "%d guns" % GameState.ship_weapons().size(), CYAN, true)
	var pr := HBoxContainer.new()
	var phl := Label.new()
	phl.text = "HULL"
	phl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phl.add_theme_font_size_override("font_size", _fs(9))
	phl.add_theme_color_override("font_color", Color.html(CYAN))
	pr.add_child(phl)
	_combat_hp_label = Label.new()
	_combat_hp_label.add_theme_font_size_override("font_size", _fs(9))
	_combat_hp_label.add_theme_color_override("font_color", Color.html(C_DIM))
	pr.add_child(_combat_hp_label)
	pp.add_child(pr)
	_combat_hp_bar = _mk_bar(pp, GREEN, 9)
	if GameState.player_max_shield() > 0.0:
		_player_shield_bar = _mk_bar(pp, CYAN, 5)
	var heatl := Label.new()
	heatl.text = "HEAT"
	heatl.add_theme_font_size_override("font_size", _fs(9))
	heatl.add_theme_color_override("font_color", Color.html(BUILD))
	pp.add_child(heatl)
	_player_heat_bar = _mk_bar(pp, BUILD, 5)
	_player_anchor = _add_anchor(pp)
	v.add_child(pp.get_parent())

	var rb := _card_button("⛒ Retreat", RED, true)
	rb.custom_minimum_size = Vector2(0, 42)
	rb.pressed.connect(func() -> void: GameState.stop_task())
	v.add_child(rb)
	_seen_events = GameState._event_seq   # only show events from here on

func _drain_combat_events() -> void:
	for ev in GameState.combat_events:
		if int(ev.get("seq", -1)) >= _seen_events:
			_seen_events = int(ev["seq"]) + 1
			_spawn_popup(ev)

func _spawn_popup(ev: Dictionary) -> void:
	var anchor: Control = _enemy_anchor if ev.get("side", "enemy") == "enemy" else _player_anchor
	if not is_instance_valid(anchor) or anchor.size.x < 20.0:
		return
	var l := Label.new()
	l.text = ev["text"]
	l.add_theme_font_size_override("font_size", _fs(16))
	l.add_theme_color_override("font_color", Color.html(ev["color"]))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(clampf(randf_range(16.0, anchor.size.x - 80.0), 8.0, maxf(8.0, anchor.size.x - 70.0)), anchor.size.y * 0.35)
	anchor.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 32.0, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tw.set_parallel(false)
	tw.tween_callback(l.queue_free)

func _mk_bar(parent: VBoxContainer, accent: String, h: int) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(0, h)
	b.show_percentage = false
	b.max_value = 100
	b.value = 100
	_style_bar(b, accent)
	parent.add_child(b)
	return b

func _add_anchor(vbox: VBoxContainer) -> Control:
	var a := Control.new()
	a.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.clip_contents = false
	vbox.get_parent().add_child(a)
	return a

# ============================================================ INFRASTRUCTURE
func _build_infra() -> void:
	var v := _clear("build")
	_back_header(v)
	_skill_banner(v, "INFRASTRUCTURE", "infrastructure", BUILD)
	var p := GameState.infra_power()
	var e := Label.new()
	e.text = "⚡ %d kW gen  ·  %d kW use  ·  Grid %d%%" % [int(p["gen"]), int(p["cons"]), int(float(p["eff"]) * 100.0)]
	e.add_theme_font_size_override("font_size", _fs(11))
	e.add_theme_color_override("font_color", Color.html(BUILD if float(p["eff"]) >= 1.0 else C_WARN))
	v.add_child(e)
	_subtabs(v, GameData.BUILDING_CATS, build_cat, BUILD, func(id: String) -> void:
		build_cat = id
		_build_infra())
	var g := _grid(v)
	var any := false
	for bid in GameData.BUILDINGS:
		var d: Dictionary = GameData.BUILDINGS[bid]
		if d.get("category", "industry") != build_cat:
			continue
		any = true
		g.add_child(_building_card(bid, d))
	if not any:
		_empty(v, "Nothing here.")

func _building_card(bid: String, d: Dictionary) -> Control:
	var unlocked := GameState.building_unlocked(bid)
	var count := GameState.building_count(bid)
	var v := _card(BUILD, unlocked or count > 0)
	_card_head(v, "⌂", d["name"], "x%d" % count, BUILD, unlocked)
	if not unlocked:
		_locked(v, d, "infrastructure")
		return v.get_parent()
	if d.get("desc", "") != "":
		_clbl(v, d["desc"], 10, C_DIM)
	# effect (per building) lines
	var eff_lines := []
	for sym in d.get("yield", {}):
		var nm := "Credits" if sym == "credits" else GameData.res_name(sym)
		eff_lines.append(_line("+%s %s" % [str(d["yield"][sym]), nm], GREEN))
	for sym in d.get("input", {}):
		eff_lines.append(_line("-%d %s" % [int(d["input"][sym]), GameData.res_name(sym)], C_WARN))
	if float(d.get("energy_gen", 0.0)) > 0.0:
		eff_lines.append(_line("+%d kW" % int(d["energy_gen"]), CYAN))
	if float(d.get("energy_cons", 0.0)) > 0.0:
		eff_lines.append(_line("-%d kW" % int(d["energy_cons"]), C_WARN))
	if not eff_lines.is_empty():
		_inset(v, "PER UNIT / %.0fs" % float(d.get("interval", 1.0)), eff_lines, BUILD)
	# Throttle (any owned building — scales production and energy)
	if count > 0:
		var th := GameState.get_throttle(bid)
		var trow := HBoxContainer.new()
		trow.add_theme_constant_override("separation", 6)
		var minus := _card_button("−", BUILD, th > 0.0)
		minus.custom_minimum_size = Vector2(40, 30)
		minus.pressed.connect(func() -> void: GameState.set_throttle(bid, th - 0.25))
		trow.add_child(minus)
		var tl := Label.new()
		tl.text = "Throttle %d%%" % int(th * 100.0)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.add_theme_font_size_override("font_size", _fs(11))
		tl.add_theme_color_override("font_color", Color.html(C_DIM))
		trow.add_child(tl)
		var plus := _card_button("+", BUILD, th < 1.0)
		plus.custom_minimum_size = Vector2(40, 30)
		plus.pressed.connect(func() -> void: GameState.set_throttle(bid, th + 0.25))
		trow.add_child(plus)
		v.add_child(trow)
	# cost
	var maxed := d.has("max") and count >= int(d["max"])
	if maxed:
		v.add_child(_card_button("MAX BUILT", C_MUTED, false))
	else:
		var cost := GameState.building_cost(bid)
		var cost_lines := []
		for sym in cost:
			var have: bool = GameState.credits >= int(cost[sym]) if sym == "credits" else GameState.amount(sym) >= int(cost[sym])
			var label := "₡%s" % GameData.fmt(cost[sym]) if sym == "credits" else "%s %s" % [GameData.fmt(cost[sym]), GameData.res_name(sym)]
			cost_lines.append(_line(label, GOLD if have else C_WARN))
		_inset(v, "COST", cost_lines, BUILD)
		var can := GameState.building_can_afford(bid)
		var b := _card_button("Build", BUILD, can)
		if can:
			b.pressed.connect(func() -> void: GameState.build_building(bid))
		v.add_child(b)
	return v.get_parent()

# ============================================================ MORE MENU
func _build_more() -> void:
	var v := _clear("more")
	var t := Label.new()
	t.text = "SYSTEMS"
	t.add_theme_font_size_override("font_size", _fs(16))
	t.add_theme_color_override("font_color", Color.html(CYAN))
	v.add_child(t)
	for it in MORE_MENU:
		var b := Button.new()
		b.text = it["label"]
		b.custom_minimum_size = Vector2(0, 54)
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", _fs(15))
		b.add_theme_color_override("font_color", Color.html(C_TEXT))
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, _bordered("16243a", "2a3a55", 1, 8))
		var pid: String = it["id"]
		b.pressed.connect(func() -> void: _show(pid))
		v.add_child(b)
	_empty(v, "Fleet · Bounty · Warp coming next.")

# ============================================================ BOUNTY BOARD
func _build_bounty() -> void:
	var v := _clear("bounty")
	_back_header(v)
	var t := Label.new()
	t.text = "◆ BOUNTY BOARD"
	t.add_theme_font_size_override("font_size", _fs(16))
	t.add_theme_color_override("font_color", Color.html(GOLD))
	v.add_child(t)

	var rr := HBoxContainer.new()
	var rt := Label.new()
	var secs := int(GameState.bounty_refresh_timer)
	rt.text = "Auto-refresh in %dh %dm" % [secs / 3600, (secs % 3600) / 60]
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("font_size", _fs(11))
	rt.add_theme_color_override("font_color", Color.html(C_DIM))
	rr.add_child(rt)
	var cost := GameState.bounty_refresh_cost()
	var rb := _card_button("Refresh ₡%s" % GameData.fmt(cost), GOLD, GameState.credits >= cost)
	rb.custom_minimum_size = Vector2(150, 32)
	if GameState.credits >= cost:
		rb.pressed.connect(func() -> void: GameState.force_refresh_bounty())
	rr.add_child(rb)
	v.add_child(rr)

	_section(v, "ACTIVE  (%d/%d)" % [GameState.bounty_active.size(), GameState.BOUNTY_MAX_ACTIVE], GOLD)
	if GameState.bounty_active.is_empty():
		_empty(v, "No active contracts — accept some below.")
	for c in GameState.bounty_active:
		v.add_child(_bounty_card(c, true))

	_section(v, "AVAILABLE", GOLD)
	if GameState.bounty_available.is_empty():
		_empty(v, "Board is empty.")
	for c in GameState.bounty_available:
		v.add_child(_bounty_card(c, false))

func _bounty_card(c: Dictionary, active: bool) -> Control:
	var elite: bool = c.get("is_elite", false)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bordered("16243a", GOLD if elite else "2a3a55", 2 if elite else 1))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	_lbl_wrap(vb, c.get("title", ""), 14, GOLD if elite else C_TEXT)
	_lbl_wrap(vb, c.get("desc", ""), 10, C_DIM)
	var reward := Label.new()
	reward.text = "Reward: ₡%s" % GameData.fmt(c.get("reward_credits", 0))
	reward.add_theme_font_size_override("font_size", _fs(11))
	reward.add_theme_color_override("font_color", Color.html(GOLD))
	vb.add_child(reward)

	var cid: String = c["id"]
	if active:
		if c["type"] == "hunt":
			var pg := Label.new()
			pg.text = "Progress: %d / %d" % [int(c["current_qty"]), int(c["target_qty"])]
			pg.add_theme_font_size_override("font_size", _fs(11))
			pg.add_theme_color_override("font_color", Color.html(GREEN if c["completed"] else C_DIM))
			vb.add_child(pg)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		if c["completed"]:
			var claim := _card_button("Claim", GREEN, true)
			claim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			claim.pressed.connect(func() -> void: GameState.claim_contract(cid))
			row.add_child(claim)
		var ab := _card_button("Abandon", C_WARN, true)
		ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ab.pressed.connect(func() -> void: GameState.abandon_contract(cid))
		row.add_child(ab)
		vb.add_child(row)
	else:
		var can := GameState.bounty_active.size() < GameState.BOUNTY_MAX_ACTIVE
		if c["type"] == "delivery":
			var need := int(c["target_qty"])
			var have := GameState.amount(c["target"])
			var nl := Label.new()
			nl.text = "You have %s / %s" % [GameData.fmt(have), GameData.fmt(need)]
			nl.add_theme_font_size_override("font_size", _fs(10))
			nl.add_theme_color_override("font_color", Color.html(GREEN if have >= need else C_WARN))
			vb.add_child(nl)
			can = can and have >= need
		var acc := _card_button("Accept" if can else ("Slots Full" if GameState.bounty_active.size() >= GameState.BOUNTY_MAX_ACTIVE else "Need Materials"), GOLD, can)
		if can:
			acc.pressed.connect(func() -> void: GameState.accept_contract(cid))
		vb.add_child(acc)
	return panel

func _lbl_wrap(parent: Node, text: String, size: int, color: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", _fs(size))
	l.add_theme_color_override("font_color", Color.html(color))
	parent.add_child(l)

# ============================================================ WARP CORE
func _build_missions() -> void:
	var v := _clear("missions")
	_back_header(v)
	var t := Label.new()
	t.text = "✦ MISSIONS"
	t.add_theme_font_size_override("font_size", _fs(16))
	t.add_theme_color_override("font_color", Color.html(PURP))
	v.add_child(t)
	_lbl_wrap(v, "%d completed" % GameState.missions_claimed.size(), 11, C_DIM)
	_section(v, "Active Objectives", PURP)
	if GameState.missions_active.is_empty():
		_empty(v, "All missions complete. Well done, Commander.")
	for mid in GameState.missions_active:
		v.add_child(_mission_card(mid))

func _mission_card(mid: String) -> Control:
	var m: Dictionary = GameData.MISSIONS[mid]
	var done := GameState.mission_completed(mid)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _card_style(SURFACE, GREEN if done else LINE, 1, done))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	_lbl_wrap(vb, m.get("name", mid), 14, GREEN if done else C_TEXT)
	_lbl_wrap(vb, m.get("desc", ""), 10, C_DIM)
	var cur := int(GameState.missions_progress.get(mid, 0))
	var qty := int(m.get("qty", 1))
	if qty > 1:
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 7)
		bar.show_percentage = false
		bar.max_value = qty
		bar.value = cur
		_style_bar(bar, GREEN if done else PURP)
		vb.add_child(bar)
		_lbl_wrap(vb, "%s / %s" % [GameData.fmt(cur), GameData.fmt(qty)], 9, C_MUTED)
	var rl := Label.new()
	rl.text = "Reward: ₡%s" % GameData.fmt(m.get("cr", 0))
	rl.add_theme_font_size_override("font_size", _fs(11))
	rl.add_theme_color_override("font_color", Color.html(GOLD))
	vb.add_child(rl)
	if done:
		var b := _card_button("Claim Reward", GREEN, true)
		b.pressed.connect(func() -> void: GameState.claim_mission(mid))
		vb.add_child(b)
	return panel

func _build_warp() -> void:
	var v := _clear("warp")
	_back_header(v)
	var t := Label.new()
	t.text = "✦ WARP CORE"
	t.add_theme_font_size_override("font_size", _fs(16))
	t.add_theme_color_override("font_color", Color.html(PURP))
	v.add_child(t)
	_lbl_wrap(v, "Collapse your empire into a Warp Core for permanent Warp Shards. Skills keep 30%% XP, buildings/ship reset — but researched tech stays unlocked.", 10, C_DIM)

	var sh := Label.new()
	sh.text = "Warp Shards: %s   ·   Warps: %d   ·   Tier %d" % [GameData.fmt(int(GameState.warp_shards)), GameState.total_warps, GameState.warp_tier()]
	sh.add_theme_font_size_override("font_size", _fs(13))
	sh.add_theme_color_override("font_color", Color.html(PURP))
	v.add_child(sh)

	_section(v, "PERMANENT BONUSES", PURP)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bordered("241f3e", "453c6b", 1, 6))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	_clbl(box, "Gathering  +%d%%" % int((GameState.warp_gathering_mult() - 1.0) * 100.0), 12, GREEN)
	_clbl(box, "All XP  +%d%%" % int((GameState.warp_xp_mult() - 1.0) * 100.0), 12, GREEN)
	_clbl(box, "Production  +%d%%" % int((GameState.warp_production_mult() - 1.0) * 100.0), 12, GREEN)
	_clbl(box, "Combat  +%d%%" % int((GameState.warp_combat_mult() - 1.0) * 100.0), 12, GREEN)
	v.add_child(panel)

	# Prestige preview
	var earned: int = GameState.lifetime_credits - GameState.credits_at_warp_start
	var bcount := 0
	for bid in GameState.buildings:
		bcount += int(GameState.buildings[bid])
	var score: int = earned + bcount * 1000
	var gain := GameState.warp_gain_preview()
	_section(v, "WARP READOUT", PURP)
	_lbl_wrap(v, "Progress score: ₡%s  (lifetime credits since last warp + buildings)" % GameData.fmt(score), 11, C_TEXT)
	if gain <= 0:
		_lbl_wrap(v, "Reach a score of ₡500K to earn your first Warp Shard.", 11, C_WARN)
	else:
		_lbl_wrap(v, "Warping now grants %d Warp Shard%s." % [gain, "s" if gain != 1 else ""], 12, GREEN)

	var wb := _card_button(("⚠ Tap again to WARP (+%d)" % gain) if _warp_armed else ("WARP for %d Shards" % gain), PURP, gain > 0)
	wb.custom_minimum_size = Vector2(0, 46)
	if gain > 0:
		wb.pressed.connect(func() -> void:
			if _warp_armed:
				GameState.execute_warp()
				_show("warp")
			else:
				_warp_armed = true
				_build_warp())
	v.add_child(wb)

func _back_header(v: VBoxContainer) -> void:
	var b := Button.new()
	b.text = "‹  More"
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", _fs(13))
	b.add_theme_color_override("font_color", Color.html(C_DIM))
	b.pressed.connect(func() -> void: _show("more"))
	v.add_child(b)

# ============================================================ SHIPYARD
func _build_ship() -> void:
	var v := _clear("ship")
	_back_header(v)
	var eyebrow := Label.new()
	eyebrow.text = "⛭ SHIP DESIGNER"
	eyebrow.add_theme_font_size_override("font_size", _fs(16))
	eyebrow.add_theme_color_override("font_color", Color.html(CYAN))
	v.add_child(eyebrow)
	var h: Dictionary = GameData.HULLS.get(GameState.active_hull, {})
	var nm := Label.new()
	nm.text = h.get("name", "No Ship")
	nm.add_theme_font_size_override("font_size", _fs(12))
	nm.add_theme_color_override("font_color", Color.html(C_DIM))
	v.add_child(nm)
	var s := GameState.ship_stats()
	if not s.is_empty():
		var st := Label.new()
		st.text = "ATK %.0f  ·  HP %.0f  ·  DEF %.0f  ·  Shield %.0f" % [s["atk"], s["hp"], s["def"], s["shield"]]
		st.add_theme_font_size_override("font_size", _fs(11))
		st.add_theme_color_override("font_color", Color.html(C_TEXT))
		v.add_child(st)
		var en := Label.new()
		var over: bool = s["energy_load"] > s["energy_cap"] and s["energy_cap"] > 0.0
		en.text = "Energy %d / %d kW%s" % [int(s["energy_load"]), int(s["energy_cap"]), "  ⚠ brownout" if over else ""]
		en.add_theme_font_size_override("font_size", _fs(10))
		en.add_theme_color_override("font_color", Color.html(C_WARN if over else C_DIM))
		v.add_child(en)
	_subtabs(v, [{"id": "loadout", "label": "Loadout"}, {"id": "modules", "label": "Modules"}, {"id": "fittings", "label": "Fittings"}, {"id": "hulls", "label": "Hulls"}], ship_view, CYAN, func(id: String) -> void:
		ship_view = id
		_build_ship())
	match ship_view:
		"loadout": _ship_loadout(v, h)
		"modules": _ship_modules(v)
		"fittings": _ship_fittings(v, h)
		"hulls": _ship_hulls(v)

func _ship_fittings(v: VBoxContainer, h: Dictionary) -> void:
	_section(v, "Auto-Consumables  (trigger at 50%)", CYAN)
	_consumable_picker(v, "hull", "Hull Repair Kit", GameState.consumable_hull_slot)
	_consumable_picker(v, "shield", "Shield Booster", GameState.consumable_shield_slot)
	_section(v, "Weapon Ammo  (consumed per shot, +damage)", CYAN)
	var slots: Array = h.get("slots", [])
	var any := false
	for i in slots.size():
		if slots[i] == "weapon" and GameState.loadout.has(str(i)):
			any = true
			_ammo_picker(v, str(i), GameData.MODULES.get(GameState.loadout[str(i)], {}))
	if not any:
		_empty(v, "Equip weapons (Loadout) to load ammo.")

func _consumable_picker(v: VBoxContainer, kind: String, title: String, current: String) -> void:
	var c := _card(CYAN, true)
	_card_head(c, "✦", title, "", CYAN, true)
	_pick_button(c, kind == "hull" and current == "" or kind == "shield" and current == "", "None", current == "", func() -> void: GameState.set_consumable(kind, ""))
	for cid in GameData.CONSUMABLES:
		var d: Dictionary = GameData.CONSUMABLES[cid]
		if d.get("type", "") != kind:
			continue
		var owned := GameState.amount(cid)
		if owned <= 0 and cid != current:
			continue
		var label := "%s  x%d  (+%d%%)" % [d.get("name", cid), owned, int(float(d.get("heal_pct", 0)) * 100.0)]
		_pick_button(c, cid == current, label, cid == current, func() -> void: GameState.set_consumable(kind, cid))
	v.add_child(c.get_parent())

func _ammo_picker(v: VBoxContainer, slot: String, m: Dictionary) -> void:
	var st: Dictionary = m.get("stats", {})
	var letter := "k"
	if float(st.get("atk_energy", 0)) > 0: letter = "e"
	elif float(st.get("atk_explosive", 0)) > 0: letter = "x"
	var current: String = GameState.ammo_loadout.get(slot, "")
	var c := _card(CYAN, true)
	_card_head(c, "◆", m.get("name", "Weapon"), "", CYAN, true)
	_pick_button(c, current == "", "No Ammo (base damage)", current == "", func() -> void: GameState.set_ammo(slot, ""))
	for sym in GameData.RESOURCES:
		var ab := GameState.ammo_bonus(sym)
		if ab[0] != letter:
			continue
		var owned := GameState.amount(sym)
		if owned <= 0 and sym != current:
			continue
		_pick_button(c, sym == current, "%s  x%s  (+%d dmg)" % [GameData.res_name(sym), GameData.fmt(owned), int(ab[1])], sym == current, func() -> void: GameState.set_ammo(slot, sym))
	v.add_child(c.get_parent())

func _pick_button(parent: VBoxContainer, _ignored: bool, label: String, active: bool, cb: Callable) -> void:
	var b := _card_button(label, CYAN if active else C_MUTED, true)
	b.add_theme_font_size_override("font_size", _fs(12))
	b.pressed.connect(cb)
	parent.add_child(b)

func _ship_loadout(v: VBoxContainer, h: Dictionary) -> void:
	var slots: Array = h.get("slots", [])
	if slots.is_empty():
		_empty(v, "No ship.")
		return
	var counts := GameState.equipped_set_counts()
	if not counts.is_empty():
		_section(v, "Set Bonuses", PURP)
		for sn in counts:
			var sd: Dictionary = GameData.SETS.get(sn, {})
			var active: bool = counts[sn] >= 3
			var txt := "%s — %d/3" % [sn, counts[sn]]
			if active and sd.get("bonus_desc", "") != "":
				txt += "  ✓ " + sd["bonus_desc"]
			_clbl(v, txt, 11, GOLD if active else C_DIM)
	_section(v, "LOADOUT — tap Remove to unequip", CYAN)
	var g := _grid(v)
	for i in slots.size():
		var stype: String = slots[i]
		var key := str(i)
		var equipped: String = GameState.loadout.get(key, "")
		var c := _card(CYAN, equipped != "")
		_card_head(c, "▢", GameData.SLOT_LABELS.get(stype, stype), "", CYAN, true)
		if equipped != "":
			var md: Dictionary = GameState.module_def(equipped)
			var rcol: String = GameState.RARITY_COLOR.get(int(md.get("rarity", 0)), C_TEXT)
			_clbl(c, md.get("name", equipped), 12, rcol)
			for aid in md.get("affixes", {}):
				_clbl(c, _affix_text(aid, md["affixes"][aid]), 9, GameState.RARITY_COLOR.get(3, GOLD))
			var b := _card_button("Remove", CYAN, true)
			b.pressed.connect(func() -> void: GameState.unequip_slot(key))
			c.add_child(b)
		else:
			_clbl(c, "— empty —", 11, C_MUTED)
		g.add_child(c.get_parent())

func _ship_modules(v: VBoxContainer) -> void:
	var slot_items := []
	for st in ["weapon", "shield", "armor", "battery", "engine", "sensor", "cooling"]:
		slot_items.append({"id": st, "label": GameData.SLOT_LABELS.get(st, st)})
	_subtabs(v, slot_items, ship_mod_slot, CYAN, func(id: String) -> void:
		ship_mod_slot = id
		_build_ship())
	# Owned rolled gear (rarity + affixes) for this slot
	var owned_custom := []
	for cid in GameState.custom_modules:
		if GameState.custom_modules[cid].get("slot", "") == ship_mod_slot and int(GameState.module_inventory.get(cid, 0)) > 0:
			owned_custom.append(cid)
	if not owned_custom.is_empty():
		_section(v, "Your Salvaged Gear", PURP)
		var ig := _grid(v)
		for cid in owned_custom:
			ig.add_child(_custom_module_card(cid))
	_section(v, "Module Shop", CYAN)
	var g := _grid(v)
	var any := false
	for mid in GameData.MODULES:
		var m: Dictionary = GameData.MODULES[mid]
		if m.get("slot", "") != ship_mod_slot:
			continue
		any = true
		g.add_child(_module_card(mid, m))
	if not any:
		_empty(v, "No modules of this type.")

func _custom_module_card(cid: String) -> Control:
	var md: Dictionary = GameState.custom_modules[cid]
	var rcol: String = GameState.RARITY_COLOR.get(int(md.get("rarity", 0)), C_TEXT)
	var owned := int(GameState.module_inventory.get(cid, 0))
	var c := _card(rcol, true)
	_card_head(c, "◆", md.get("name", cid), ("x%d" % owned) if owned > 1 else "", rcol, true)
	_inset(c, "STATS", _module_stat_lines(md.get("stats", {})), rcol)
	if not md.get("affixes", {}).is_empty():
		var alines := []
		for aid in md["affixes"]:
			alines.append(_line(_affix_text(aid, md["affixes"][aid]), rcol))
		_inset(c, "AFFIXES", alines, rcol, true)
	# Gem sockets
	var sockets: Array = md.get("sockets", [])
	if sockets.size() > 0:
		var slines := []
		var has_empty := false
		for i in sockets.size():
			var gid = sockets[i]
			if gid != null and gid != "":
				slines.append(_line("◆ " + GameData.GEMS.get(gid, {}).get("name", gid), "3a9fff"))
			else:
				slines.append(_line("◇ empty socket", C_MUTED))
				has_empty = true
		_inset(c, "SOCKETS", slines, "3a9fff")
		if has_empty:
			for gem in GameData.GEMS:
				if GameState.amount(gem) > 0:
					var gb := _card_button("Socket %s x%d" % [GameData.GEMS[gem]["name"], GameState.amount(gem)], "3a9fff", true)
					gb.add_theme_font_size_override("font_size", _fs(11))
					gb.pressed.connect(func() -> void: GameState.socket_gem(cid, gem))
					c.add_child(gb)
		for i in sockets.size():
			var gid2 = sockets[i]
			if gid2 != null and gid2 != "":
				var idx := i
				var rb := _card_button("Remove " + GameData.GEMS.get(gid2, {}).get("name", gid2), C_MUTED, true)
				rb.add_theme_font_size_override("font_size", _fs(11))
				rb.pressed.connect(func() -> void: GameState.unsocket_gem(cid, idx))
				c.add_child(rb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var eq := _card_button("Equip", CYAN, true)
	eq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eq.pressed.connect(func() -> void: GameState.equip_module(cid))
	row.add_child(eq)
	var sell := _card_button("Sell ₡%s" % GameData.fmt(GameState.RARITY_SELL.get(int(md.get("rarity", 0)), 100)), GOLD, true)
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell.pressed.connect(func() -> void: GameState.sell_module(cid))
	row.add_child(sell)
	c.add_child(row)
	return c.get_parent()

func _affix_text(aid: String, val: float) -> String:
	var cfg: Dictionary = GameState.AFFIX_DB.get(aid, {})
	var d: String = cfg.get("desc", aid)
	if "%d%%" in d:
		return "◆ " + (d % int(round(val * 100.0)))
	return "◆ " + cfg.get("name", aid)

func _module_card(mid: String, m: Dictionary) -> Control:
	var unlocked := GameState.module_unlocked(mid)
	var owned := int(GameState.module_inventory.get(mid, 0))
	var c := _card(CYAN, unlocked)
	_card_head(c, "▣", m.get("name", mid), ("x%d" % owned) if owned > 0 else "", CYAN, unlocked)
	if not unlocked:
		_locked(c, m, "combat")
		return c.get_parent()
	_inset(c, "STATS", _module_stat_lines(m.get("stats", {})), CYAN)
	var cost_lines := []
	for sym in m.get("cost", {}):
		var have: bool = GameState.credits >= int(m["cost"][sym]) if sym == "credits" else GameState.amount(sym) >= int(m["cost"][sym])
		var label := "₡%s" % GameData.fmt(m["cost"][sym]) if sym == "credits" else "%s %s" % [GameData.fmt(m["cost"][sym]), GameData.res_name(sym)]
		cost_lines.append(_line(label, GOLD if have else C_WARN))
	_inset(c, "COST", cost_lines, CYAN)
	if owned > 0:
		var eq := _card_button("Equip", CYAN, true)
		eq.pressed.connect(func() -> void:
			if not GameState.equip_module(mid):
				pass)
		c.add_child(eq)
	var buy := _card_button("Buy", GOLD, GameState.module_can_buy(mid))
	if GameState.module_can_buy(mid):
		buy.pressed.connect(func() -> void: GameState.buy_module(mid))
	c.add_child(buy)
	return c.get_parent()

func _ship_hulls(v: VBoxContainer) -> void:
	_section(v, "HULLS", CYAN)
	var g := _grid(v)
	for hid in GameData.HULLS:
		g.add_child(_hull_card(hid, GameData.HULLS[hid]))

func _hull_card(hid: String, h: Dictionary) -> Control:
	var unlocked := GameState.hull_unlocked(hid)
	var owned := GameState.hull_owned(hid)
	var active: bool = GameState.active_hull == hid
	var c := _card(CYAN, unlocked or owned)
	_card_head(c, "⛭", h.get("name", hid), "T%d" % int(h.get("tier", 0)), CYAN, unlocked)
	if not unlocked:
		_locked(c, h, "combat")
		return c.get_parent()
	_inset(c, "HULL", [
		_line("HP %s" % GameData.fmt(h.get("hp", 0)), C_TEXT),
		_line("ATK %d" % int(h.get("atk", 0)), C_WARN),
		_line("%d slots" % (h.get("slots", []) as Array).size(), C_DIM),
	], CYAN)
	if active:
		c.add_child(_card_button("ACTIVE", C_MUTED, false))
	elif owned:
		var sw := _card_button("Switch", CYAN, true)
		sw.pressed.connect(func() -> void: GameState.select_hull(hid))
		c.add_child(sw)
	else:
		var cost_lines := []
		for sym in h.get("cost", {}):
			var have: bool = GameState.credits >= int(h["cost"][sym]) if sym == "credits" else GameState.amount(sym) >= int(h["cost"][sym])
			var label := "₡%s" % GameData.fmt(h["cost"][sym]) if sym == "credits" else "%s %s" % [GameData.fmt(h["cost"][sym]), GameData.res_name(sym)]
			cost_lines.append(_line(label, GOLD if have else C_WARN))
		if not cost_lines.is_empty():
			_inset(c, "COST", cost_lines, CYAN)
		var b := _card_button("Build", GOLD, GameState.hull_can_get(hid))
		if GameState.hull_can_get(hid):
			b.pressed.connect(func() -> void: GameState.select_hull(hid))
		c.add_child(b)
	return c.get_parent()

func _module_stat_lines(stats: Dictionary) -> Array:
	var labels := {
		"atk_energy": "Energy Dmg", "atk_kinetic": "Kinetic Dmg", "atk_explosive": "Explosive Dmg",
		"atk_interval": "Interval", "energy_load": "Energy Use", "energy_capacity": "Energy Cap",
		"hp": "Hull HP", "def": "Armor", "max_shield": "Shield", "shield_regen": "Shield Regen",
		"shield_regen_mult": "Regen x", "atk_speed_bonus": "Fire Rate +", "atk_speed_mult": "Fire Rate x",
		"accuracy": "Accuracy", "crit_chance": "Crit", "eva": "Evasion", "jamming_strength": "Jamming",
	}
	var lines := []
	for k in stats:
		var v = stats[k]
		var txt: String
		if k == "atk_interval":
			txt = "%s %.1fs" % [labels.get(k, k), float(v)]
		elif k in ["atk_speed_bonus", "crit_chance", "eva"]:
			txt = "%s %d%%" % [labels.get(k, k), int(float(v) * 100.0)]
		else:
			txt = "%s %s" % [labels.get(k, k), str(v)]
		lines.append(_line(txt, C_TEXT))
	return lines

# ============================================================ RESEARCH
func _build_research() -> void:
	var v := _clear("research")
	var title := Label.new()
	title.text = "RESEARCH NETWORK"
	title.add_theme_font_size_override("font_size", _fs(16))
	title.add_theme_color_override("font_color", Color.html(PURP))
	v.add_child(title)
	var cr := Label.new()
	cr.text = "Credits: ₡%s   ·   sell materials in More" % GameData.fmt(GameState.credits)
	cr.add_theme_font_size_override("font_size", _fs(11))
	cr.add_theme_color_override("font_color", Color.html(GOLD))
	v.add_child(cr)

	# Progressive reveal: show researched, available, and frontier nodes; group by depth.
	var tiers := {}
	for id in GameData.RESEARCH:
		if not _research_visible(id):
			continue
		var d := _research_depth(id)
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
			row.add_child(_research_node(id))

func _research_visible(id: String) -> bool:
	if GameState.is_research_unlocked(id):
		return true
	var p: String = GameData.RESEARCH[id].get("parent", "")
	return p == "" or GameState.is_research_unlocked(p)

func _research_depth(id: String) -> int:
	var p: String = GameData.RESEARCH[id].get("parent", "")
	if p == "" or not GameData.RESEARCH.has(p):
		return 0
	return _research_depth(p) + 1

func _research_node(id: String) -> Control:
	var t: Dictionary = GameData.RESEARCH[id]
	var researched := GameState.is_research_unlocked(id)
	var available := GameState.research_available(id)
	var border := GREEN if researched else (PURP if available else "453c6b")
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bordered("241f3e", border, 2 if (available or researched) else 1))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	_clbl(v, t.get("name", id), 13, C_TEXT if (available or researched) else C_MUTED)
	if researched:
		_clbl(v, "✓ Researched", 10, GREEN)
	else:
		var cred := int(t.get("credits", 0))
		var have_cr := GameState.credits >= cred
		_clbl(v, "₡%s" % GameData.fmt(cred), 11, GOLD if have_cr else C_WARN)
		for sym in t.get("items", {}):
			var have := GameState.amount(sym) >= int(t["items"][sym])
			_clbl(v, "%d %s" % [int(t["items"][sym]), GameData.res_name(sym)], 10, GOLD if have else C_WARN)
		var overlay := Button.new()
		overlay.flat = true
		overlay.focus_mode = Control.FOCUS_NONE
		overlay.disabled = not available
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.pressed.connect(func() -> void: GameState.unlock_research(id))
		panel.add_child(overlay)
	return panel

# ============================================================ STATS / STORAGE
func _build_stats() -> void:
	var v := _clear("stats")
	_back_header(v)
	# Credits banner
	var cpanel := PanelContainer.new()
	cpanel.add_theme_stylebox_override("panel", _card_style(_mix(GOLD, SURFACE, 0.86), _mix(GOLD, LINE, 0.4), 1, false))
	var crow := HBoxContainer.new()
	cpanel.add_child(crow)
	var cl := Label.new()
	cl.text = "CREDITS"
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cl.add_theme_font_size_override("font_size", _fs(12))
	cl.add_theme_color_override("font_color", Color.html(C_DIM))
	crow.add_child(cl)
	var cv := Label.new()
	cv.text = "₡%s" % GameData.fmt(GameState.credits)
	cv.add_theme_font_size_override("font_size", _fs(18))
	cv.add_theme_color_override("font_color", Color.html(GOLD))
	crow.add_child(cv)
	v.add_child(cpanel)

	_section(v, "CREW", CYAN)
	for sk in ["harvesting", "fabrication", "combat", "infrastructure"]:
		_skill_banner(v, sk.capitalize(), sk, CYAN)

	_section(v, "Storage — tap Sell for credits", GOLD)
	var any := false
	for sym in GameData.RESOURCES:
		var amt := GameState.amount(sym)
		if amt <= 0:
			continue
		any = true
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _bordered(SURFACE, LINE, 1, 10))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		panel.add_child(row)
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var ds := StyleBoxFlat.new()
		ds.bg_color = GameData.color_for(sym)
		ds.set_corner_radius_all(4)
		dot.add_theme_stylebox_override("panel", ds)
		row.add_child(dot)
		var n := Label.new()
		n.text = GameData.res_name(sym)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		n.add_theme_color_override("font_color", Color.html(C_TEXT))
		row.add_child(n)
		var a := Label.new()
		a.text = GameData.fmt(amt)
		a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		a.add_theme_color_override("font_color", Color.html(C_DIM))
		row.add_child(a)
		var val := maxi(1, GameData.value_of(sym))
		var sell := _card_button("Sell ₡%s" % GameData.fmt(amt * val), GOLD, true)
		sell.custom_minimum_size = Vector2(96, 32)
		sell.add_theme_font_size_override("font_size", _fs(12))
		sell.pressed.connect(func() -> void: GameState.sell_all(sym))
		row.add_child(sell)
		v.add_child(panel)
	if not any:
		_empty(v, "Storage empty — go gather something.")

	_section(v, "System", CYAN)
	var save_btn := _card_button("Save Now", CYAN, true)
	save_btn.custom_minimum_size = Vector2(0, 44)
	save_btn.pressed.connect(func() -> void: GameState.save_game())
	v.add_child(save_btn)
	var reset_btn := _card_button("⚠ Tap again to wipe save" if _reset_armed else "Reset Game", RED, true)
	reset_btn.custom_minimum_size = Vector2(0, 44)
	reset_btn.pressed.connect(func() -> void:
		if _reset_armed:
			GameState.hard_reset()
			_show("gather")
		else:
			_reset_armed = true
			_build_stats())
	v.add_child(reset_btn)

# ============================================================ SHARED CARD PIECES
func _action_controls(v: VBoxContainer, type: String, id: String, active: bool, accent: String, start_label := "Start", stop_label := "Stop") -> void:
	var b := _card_button(stop_label if active else start_label, accent, true)
	b.pressed.connect(func() -> void: GameState.start_task(type, id))
	v.add_child(b)
	var t := Label.new()
	t.text = "%.1fs / %.1fs" % [GameState.progress if active else 0.0, GameState.effective_duration(type, id)]
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", _fs(10))
	t.add_theme_color_override("font_color", Color.html(C_MUTED))
	v.add_child(t)
	if active:
		_active_timer = t
	_progress(v, active, accent)

func _locked(v: VBoxContainer, def: Dictionary, skill: String) -> void:
	var top := Control.new()
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(top)
	_clbl(v, "LOCKED", 13, C_WARN)
	var r := Label.new()
	r.text = _req_text(def, skill)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_theme_font_size_override("font_size", _fs(10))
	r.add_theme_color_override("font_color", Color.html(C_MUTED))
	v.add_child(r)
	var bot := Control.new()
	bot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(bot)

func _loot_lines(loot: Array) -> Array:
	var lines := []
	for row in loot:
		var is_credits: bool = row[0] == "credits"
		var label := "Credits" if is_credits else GameData.res_name(row[0])
		var txt := "%s%s %d-%d" % ["₡ " if is_credits else "", label, int(row[2]), int(row[3])]
		if float(row[1]) < 1.0:
			txt += " (%d%%)" % int(float(row[1]) * 100.0)
		lines.append(_line(txt, GOLD if is_credits else _hex(GameData.color_for(row[0]))))
	return lines

func _empty(v: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color.html(C_MUTED))
	l.add_theme_font_size_override("font_size", _fs(12))
	v.add_child(l)

# ============================================================ WIDGET HELPERS
func _grid(v: VBoxContainer) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(g)
	return g

func _subtabs(v: VBoxContainer, items: Array, current_id: String, accent: String, on_select: Callable) -> void:
	var sc := ScrollContainer.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, 38)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 7)
	sc.add_child(hb)
	for it in items:
		var on: bool = it["id"] == current_id
		var b := Button.new()
		b.text = it["label"]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 32)
		b.add_theme_font_size_override("font_size", _fs(12))
		var fill := accent if on else SURFACE_HI
		var txt := _ideal_text(accent) if on else C_DIM
		b.add_theme_color_override("font_color", Color.html(txt))
		b.add_theme_color_override("font_color_hover", Color.html(txt))
		b.add_theme_color_override("font_color_pressed", Color.html(txt))
		var sb := _bordered(fill, accent if on else LINE, 1, 16)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, sb)
		var sel_id: String = it["id"]
		b.pressed.connect(func() -> void: on_select.call(sel_id))
		hb.add_child(b)
	v.add_child(sc)

func _style_nav(id: String, active: bool) -> void:
	var item: Dictionary = nav_items[id]
	var col: String = DOMAIN.get(id, CYAN) if active else C_MUTED
	item["icon"].add_theme_color_override("font_color", Color.html(col))
	item["label"].add_theme_color_override("font_color", Color.html(col))
	var dot: Panel = item["dot"]
	dot.visible = active
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color.html(DOMAIN.get(id, CYAN))
	ds.set_corner_radius_all(2)
	dot.add_theme_stylebox_override("panel", ds)

func _card(accent: String, lit: bool, min_h: int = 0) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _card_style(SURFACE, accent if lit else LINE, 1, lit))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if min_h > 0:
		# Uniform card height via a minimum size (NOT SIZE_FILL, which breaks
		# the parent ScrollContainer's scroll range).
		panel.custom_minimum_size = Vector2(0, min_h)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	return v

func _card_head(v: VBoxContainer, icon: String, name: String, badge: String, accent: String, lit: bool) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 7)
	if icon != "":
		var chip := PanelContainer.new()
		chip.custom_minimum_size = Vector2(26, 26)
		chip.add_theme_stylebox_override("panel", _bordered(_mix(accent, INSET, 0.82) if lit else INSET, _mix(accent, LINE, 0.5) if lit else LINE, 1, 7))
		var cc := CenterContainer.new()
		chip.add_child(cc)
		var ic := Label.new()
		ic.text = icon
		ic.add_theme_font_size_override("font_size", _fs(13))
		ic.add_theme_color_override("font_color", Color.html(accent if lit else C_MUTED))
		cc.add_child(ic)
		hb.add_child(chip)
	var nm := Label.new()
	nm.text = name
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.add_theme_font_size_override("font_size", _fs(13))
	nm.add_theme_color_override("font_color", Color.html(C_TEXT if lit else C_MUTED))
	hb.add_child(nm)
	if badge != "":
		var bd := PanelContainer.new()
		bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bsb := _bordered(_mix(accent, INSET, 0.8) if lit else INSET, accent if lit else LINE, 1, 8)
		bsb.content_margin_left = 7
		bsb.content_margin_right = 7
		bsb.content_margin_top = 2
		bsb.content_margin_bottom = 2
		bd.add_theme_stylebox_override("panel", bsb)
		var bl := Label.new()
		bl.text = badge
		bl.add_theme_font_size_override("font_size", _fs(9))
		bl.add_theme_color_override("font_color", Color.html(accent if lit else C_MUTED))
		bd.add_child(bl)
		hb.add_child(bd)
	v.add_child(hb)

func _inset(v: VBoxContainer, title: String, lines: Array, accent: String, highlight := false) -> void:
	var panel := PanelContainer.new()
	var sb := _bordered(INSET, accent if highlight else LINE, 1, 8)
	if highlight:
		sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", _fs(8))
	t.add_theme_color_override("font_color", Color.html(accent if highlight else C_MUTED))
	box.add_child(t)
	for ln in lines:
		_clbl(box, ln["text"], 12, ln["color"])
	v.add_child(panel)

func _clbl(parent: Node, text: String, size: int, color: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", _fs(size))
	l.add_theme_color_override("font_color", Color.html(color))
	parent.add_child(l)

func _line(text: String, color: String) -> Dictionary:
	return {"text": text, "color": color}

func _card_button(text: String, accent: String, enabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 36)
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	# Filled accent CTA with elevation; pressed state inset; disabled muted.
	var normal := _bordered(accent if enabled else "232f48", _mix(accent, "ffffff", 0.75) if enabled else LINE, 1, 9)
	if enabled:
		normal.shadow_color = Color(0, 0, 0, 0.35)
		normal.shadow_size = 4
		normal.shadow_offset = Vector2(0, 2)
	var pressed := _bordered(_mix(accent, "000000", 0.78) if enabled else "232f48", accent if enabled else LINE, 1, 9)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", _bordered("232f48", LINE, 1, 9))
	var tc := _ideal_text(accent) if enabled else C_MUTED
	b.add_theme_color_override("font_color", Color.html(tc))
	b.add_theme_color_override("font_color_hover", Color.html(tc))
	b.add_theme_color_override("font_color_pressed", Color.html(tc))
	b.add_theme_color_override("font_color_disabled", Color.html(C_MUTED))
	b.add_theme_font_size_override("font_size", _fs(13))
	return b

func _progress(v: VBoxContainer, active: bool, accent: String) -> void:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0, 8)
	var bar := ProgressBar.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = 0
	_style_bar(bar, accent)
	wrap.add_child(bar)
	if not active:
		var lbl := Label.new()
		lbl.text = "READY"
		lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", _fs(7))
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
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _card_style(_mix(accent, SURFACE, 0.88), _mix(accent, LINE, 0.4), 1, false))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	var hb := HBoxContainer.new()
	var t := Label.new()
	t.text = title
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("font_size", _fs(14))
	t.add_theme_color_override("font_color", Color.html(accent))
	hb.add_child(t)
	var lv := Label.new()
	lv.text = "Lv %d" % lvl
	lv.add_theme_font_size_override("font_size", _fs(14))
	lv.add_theme_color_override("font_color", Color.html(C_TEXT))
	hb.add_child(lv)
	box.add_child(hb)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = pct
	_style_bar(bar, accent)
	box.add_child(bar)
	var xpl := Label.new()
	xpl.text = "%s / %s XP" % [GameData.fmt(cur - base), GameData.fmt(next - base)]
	xpl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	xpl.add_theme_font_size_override("font_size", _fs(9))
	xpl.add_theme_color_override("font_color", Color.html(C_MUTED))
	box.add_child(xpl)
	v.add_child(panel)

func _section(v: VBoxContainer, text: String, accent: String) -> void:
	if text == "":
		return
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 7)
	var tick := Panel.new()
	tick.custom_minimum_size = Vector2(3, 12)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color.html(accent)
	ts.set_corner_radius_all(2)
	tick.add_theme_stylebox_override("panel", ts)
	hb.add_child(tick)
	var l := Label.new()
	l.text = text.to_upper()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", _fs(11))
	l.add_theme_color_override("font_color", Color.html(C_DIM))
	hb.add_child(l)
	v.add_child(hb)

func _connector(v: VBoxContainer) -> void:
	var c := CenterContainer.new()
	var line := ColorRect.new()
	line.color = Color.html(PURP)
	line.custom_minimum_size = Vector2(3, 14)
	c.add_child(line)
	v.add_child(c)

func _refresh_top() -> void:
	if res_bar == null:
		return
	for c in res_bar.get_children():
		res_bar.remove_child(c)
		c.queue_free()
	res_bar.add_child(_chip("₡", GameData.fmt(GameState.credits), GOLD, true))
	for sym in GameData.RESOURCES:
		var amt := GameState.amount(sym)
		if amt <= 0:
			continue
		res_bar.add_child(_chip(GameData.res_name(sym), GameData.fmt(amt), _hex(GameData.color_for(sym)), false))

## A rounded resource pill: colored dot + name + value.
func _chip(name: String, value: String, accent: String, strong: bool) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bordered(_mix(accent, SURFACE_HI, 0.85) if strong else SURFACE_HI, _mix(accent, LINE, 0.6) if strong else LINE, 1, 14))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 5)
	panel.add_child(hb)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(7, 7)
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color.html(accent)
	ds.set_corner_radius_all(4)
	dot.add_theme_stylebox_override("panel", ds)
	var dw := CenterContainer.new()
	dw.add_child(dot)
	hb.add_child(dw)
	var nm := Label.new()
	nm.text = name
	nm.add_theme_font_size_override("font_size", _fs(11))
	nm.add_theme_color_override("font_color", Color.html(C_DIM))
	hb.add_child(nm)
	var vl := Label.new()
	vl.text = value
	vl.add_theme_font_size_override("font_size", _fs(12))
	vl.add_theme_color_override("font_color", Color.html(accent if strong else C_TEXT))
	hb.add_child(vl)
	return panel

func _build_active_banner() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bordered(INSET, LINE, 1, 12))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	panel.add_child(hb)
	_banner_chip = PanelContainer.new()
	_banner_chip.custom_minimum_size = Vector2(40, 40)
	_banner_chip.add_theme_stylebox_override("panel", _bordered(SURFACE_HI, LINE, 1, 10))
	var cc := CenterContainer.new()
	_banner_chip.add_child(cc)
	_banner_icon = Label.new()
	_banner_icon.add_theme_font_size_override("font_size", _fs(19))
	cc.add_child(_banner_icon)
	hb.add_child(_banner_chip)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vb.add_theme_constant_override("separation", 3)
	hb.add_child(vb)
	_banner_kind = Label.new()
	_banner_kind.add_theme_font_size_override("font_size", _fs(9))
	vb.add_child(_banner_kind)
	_banner_name = Label.new()
	_banner_name.add_theme_font_size_override("font_size", _fs(14))
	_banner_name.add_theme_color_override("font_color", Color.html(C_TEXT))
	vb.add_child(_banner_name)
	_banner_bar = ProgressBar.new()
	_banner_bar.custom_minimum_size = Vector2(0, 5)
	_banner_bar.show_percentage = false
	_banner_bar.max_value = 100
	vb.add_child(_banner_bar)
	_banner_time = Label.new()
	_banner_time.custom_minimum_size = Vector2(46, 0)
	_banner_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_banner_time.add_theme_font_size_override("font_size", _fs(14))
	_banner_time.add_theme_color_override("font_color", Color.html(C_DIM))
	hb.add_child(_banner_time)
	return panel

func _refresh_banner() -> void:
	if _banner_icon == null:
		return
	var t := GameState.active_type
	var accent := C_MUTED
	var icon := "✦"
	var kind := "IDLE"
	var nm := "Tap an action to begin"
	if t == "gather":
		accent = GOLD; icon = "↑"; kind = "HARVESTING"; nm = GameData.GATHER[GameState.active_id]["name"]
	elif t == "craft":
		accent = CYAN; icon = "⚙"; kind = "ENGINEERING"; nm = GameData.CRAFT[GameState.active_id]["name"]
	elif t == "combat":
		accent = RED; icon = "◎"; kind = "IN COMBAT"; nm = GameData.ENEMIES[GameState.active_id]["name"]
	_banner_icon.text = icon
	_banner_icon.add_theme_color_override("font_color", Color.html(accent))
	_banner_chip.add_theme_stylebox_override("panel", _bordered(_mix(accent, INSET, 0.8), accent, 1, 10))
	_banner_kind.text = kind
	_banner_kind.add_theme_color_override("font_color", Color.html(accent))
	_banner_name.text = nm
	_banner_bar.modulate.a = 1.0 if t != "" else 0.0
	_style_bar(_banner_bar, accent)
	if t == "":
		_banner_time.text = ""
		_banner_bar.value = 0.0

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
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	_clbl(v, "◷ Welcome Back, Commander", 16, CYAN)
	var body := Label.new()
	body.text = text
	body.add_theme_color_override("font_color", Color.html(C_TEXT))
	v.add_child(body)
	var ok := Button.new()
	ok.text = "Collect"
	ok.custom_minimum_size = Vector2(0, 40)
	ok.focus_mode = Control.FOCUS_NONE
	ok.pressed.connect(func() -> void: overlay.queue_free())
	v.add_child(ok)

# ============================================================ TEXT
func _active_text() -> String:
	if GameState.active_type == "gather":
		return "▶ Harvesting: " + GameData.GATHER[GameState.active_id]["name"]
	elif GameState.active_type == "craft":
		return "▶ Crafting: " + GameData.CRAFT[GameState.active_id]["name"]
	elif GameState.active_type == "combat":
		return "▶ Engaging: " + GameData.ENEMIES[GameState.active_id]["name"]
	return "Idle — tap an action to begin"

func _req_text(def: Dictionary, skill: String) -> String:
	var parts := []
	if int(def.get("level_req", 1)) > 1:
		parts.append("Lv %d %s" % [int(def["level_req"]), skill.capitalize()])
	var rr: String = def.get("research_req", "")
	if rr != "":
		parts.append("Research: " + GameData.RESEARCH.get(rr, {}).get("name", rr))
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
	b.add_theme_font_size_override("font_size", _fs(12))
	var bgc := "16273f" if active else "00000000"
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.html(bgc)
		sb.set_corner_radius_all(8)
		b.add_theme_stylebox_override(state, sb)

func _style_bar(b: ProgressBar, accent: String) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color.html("0a1120")
	bg.set_corner_radius_all(6)
	bg.set_border_width_all(1)
	bg.border_color = Color.html(LINE)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color.html(accent)
	fg.set_corner_radius_all(6)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)

# ---- Design helpers ----
func _card_style(bg: String, border: String, width := 1, elevated := false) -> StyleBoxFlat:
	var s := _bordered(bg, border, width, 14)
	s.content_margin_left = 11
	s.content_margin_right = 11
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	if elevated:
		s.shadow_color = Color(0, 0, 0, 0.40)
		s.shadow_size = 7
		s.shadow_offset = Vector2(0, 3)
	return s

func _hud_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color.html("0f1830")
	s.border_width_bottom = 1
	s.border_color = Color.html(LINE)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 2)
	return s

func _nav_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color.html("0f1830")
	s.border_width_top = 1
	s.border_color = Color.html(LINE)
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _grad_tex(top: String, bot: String) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color.html(top))
	g.set_color(1, Color.html(bot))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 8
	tex.height = 256
	return tex

func _mix(a: String, b: String, t: float) -> String:
	return Color.html(a).lerp(Color.html(b), t).to_html(false)

## Dark text on bright accents, light text on dark ones — keeps CTAs legible.
func _ideal_text(accent: String) -> String:
	var c := Color.html(accent)
	var lum := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
	return "0b1220" if lum > 0.55 else "f4f7fc"
