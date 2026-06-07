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
const PAGE_IDS := ["gather", "craft", "combat", "research", "more", "build", "ship", "bounty", "warp", "missions", "atlas", "stats"]
const MORE_MENU := [
	{"id": "missions", "label": "✦  Missions"},
	{"id": "build",  "label": "⌂  Infrastructure"},
	{"id": "ship",   "label": "⛭  Ship Designer"},
	{"id": "bounty", "label": "◆  Bounty Board"},
	{"id": "warp",   "label": "✦  Warp Core"},
	{"id": "atlas",  "label": "❒  Atlas / Codex"},
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
const C_DIM := "b3c0db"      # secondary text — lifted for contrast
const C_MUTED := "8c9bbd"    # tertiary / locked text — lifted for contrast
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
# Hamburger drawer — every page reachable from one slide-out menu.
const NAV_ALL := [
	{"id": "gather",   "label": "Gather",         "icon": "↑"},
	{"id": "craft",    "label": "Craft",          "icon": "⚙"},
	{"id": "combat",   "label": "Combat",         "icon": "◎"},
	{"id": "research", "label": "Research",       "icon": "✦"},
	{"id": "missions", "label": "Missions",       "icon": "✦"},
	{"id": "build",    "label": "Infrastructure", "icon": "⌂"},
	{"id": "ship",     "label": "Ship Designer",  "icon": "⛭"},
	{"id": "bounty",   "label": "Bounty Board",   "icon": "◆"},
	{"id": "warp",     "label": "Warp Core",      "icon": "✦"},
	{"id": "atlas",    "label": "Atlas / Codex",  "icon": "❒"},
	{"id": "stats",    "label": "Storage & Crew", "icon": "≡"},
]
const DRAWER_W := 480.0

# Global text scale — bumps every font size for phone readability without
# touching individual call sites. Tune this one number to rescale the whole UI.
const FONT_SCALE := 1.28
func _fs(n: int) -> int:
	return int(round(n * FONT_SCALE))

var content: Control
var pages := {}
var nav_items := {}
var drawer: Control
var drawer_panel: PanelContainer
var drawer_scrim: ColorRect
var drawer_open := false
var _ham_badge: Panel
var _ham_btn: Button
var _hdr_credits: Label
var _coach_banner: PanelContainer
var _coach_obj: Label
var _coach_hint: Label
var _pulse_tween: Tween
var _pulse_target: Control
var _welcome: Control = null
var _welcome_done := false
var current := ""
var gather_cat := "terrestrial"
var craft_cat := "basics"
var combat_zone := 0
var research_tab := "Operations"
var atlas_mode := "materials"
var atlas_mat_cat := "gathered"
var _atlas_index := {}
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
	GameState.skills_changed.connect(_on_tick)
	GameState.research_changed.connect(_refresh_all)
	GameState.action_changed.connect(_on_tick)
	GameState.action_changed.connect(_refresh_banner)
	GameState.bounty_changed.connect(_on_tick)
	GameState.missions_changed.connect(_on_tick)
	GameState.offline_ready.connect(_on_offline_ready)
	GameState.action_reward.connect(_on_action_reward)
	get_viewport().size_changed.connect(_update_safe_area)
	call_deferred("_update_safe_area")
	_refresh_top()
	_refresh_banner()
	# New players start on the Missions tutorial (like the desktop game).
	_show("missions" if not GameState.has_mission_progress() else "gather")
	_update_badges()
	_update_coach()
	_show_welcome()

# ============================================================ COACHING
# Pulses the next thing to tap based on the active tutorial mission, and shows a
# directive banner — adapted from the desktop nav-hint system to the drawer UI.
const COACH_PAGE := {"gather": "gather", "gather_multi": "craft", "research": "research", "craft": "ship", "construct": "ship", "build": "build", "defeat": "combat", "loadout_check": "ship"}

func _page_label(id: String) -> String:
	for t in NAV_ALL:
		if t.id == id:
			return t.label
	return id.capitalize()

func _coach_active_mission() -> String:
	for mid in GameState.missions_active:
		return mid              # the tutorial chain has one active mission at a time
	return ""

func _gather_action_for(sym: String) -> String:
	var best := ""
	var best_lvl := 99999
	for gid in GameData.GATHER:
		for row in GameData.GATHER[gid].get("loot", []):
			if row[0] == sym:
				var lvl := int(GameData.GATHER[gid].get("level_req", 1))
				if lvl < best_lvl:
					best_lvl = lvl
					best = gid
	return best

func _update_coach() -> void:
	if _coach_banner == null:
		return
	var mid := _coach_active_mission()
	if mid == "" or not GameData.MISSIONS.has(mid):
		_coach_banner.visible = false
		_pulse_stop()
		return
	var m: Dictionary = GameData.MISSIONS[mid]
	_coach_banner.visible = true
	_coach_obj.text = "◆  OBJECTIVE: " + m.get("name", mid)
	var claim := GameState.mission_completed(mid)
	var page: String = COACH_PAGE.get(m.get("type", ""), "")
	var tgt = m.get("target", "")
	var card: String = tgt if tgt is String else ""   # gather_multi target is a Dictionary
	if m.get("type", "") == "gather":
		card = _gather_action_for(card)
	var pulse: Control = null
	if claim:
		_coach_hint.text = "✓ Reward ready — open ☰ → Missions and Claim."
		if current != "missions":
			pulse = _ham_btn
		if drawer_open and nav_items.has("missions"):
			pulse = nav_items["missions"]["btn"]
	elif page == "":
		_coach_hint.text = m.get("desc", "")
	elif drawer_open and page != current and nav_items.has(page):
		_coach_hint.text = "Open " + _page_label(page)
		pulse = nav_items[page]["btn"]
	elif page != current:
		_coach_hint.text = m.get("desc", "") + "   ·   tap ☰ → " + _page_label(page)
		pulse = _ham_btn
	else:
		_coach_hint.text = m.get("desc", "")
		pulse = _coach_find_card(card)
	_pulse_start(pulse)

func _coach_find_card(id: String) -> Control:
	if id == "" or not pages.has(current):
		return null
	var stack: Array = [pages[current]]
	while stack.size() > 0:
		var n = stack.pop_back()
		if n is Control and n.has_meta("coach_id") and String(n.get_meta("coach_id")) == id:
			return n
		for ch in n.get_children():
			stack.append(ch)
	return null

func _pulse_start(c: Control) -> void:
	if c == _pulse_target and _pulse_tween != null and _pulse_tween.is_valid():
		return
	_pulse_stop()
	if c == null or not is_instance_valid(c):
		return
	_pulse_target = c
	_pulse_tween = c.create_tween().set_loops()
	_pulse_tween.tween_property(c, "modulate", Color(1.45, 1.12, 0.5), 0.55).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(c, "modulate", Color.WHITE, 0.55).set_trans(Tween.TRANS_SINE)

func _pulse_stop() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	if is_instance_valid(_pulse_target):
		_pulse_target.modulate = Color.WHITE
	_pulse_target = null

# Branded intro splash shown on launch (tap or auto to continue); flows into the
# offline "welcome back" report afterward if there is one.
func _show_welcome() -> void:
	_welcome = Control.new()
	_welcome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_welcome.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_welcome)
	var bg := TextureRect.new()
	bg.texture = _grad_tex(BG_TOP, BG_BOT)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_welcome.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_welcome.add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)
	var emblem := _wlabel(col, "✦", 64, CYAN)
	var title := _wlabel(col, "STELLAR FORGE", 38, C_TEXT)
	var tag := _wlabel(col, "Mine · Craft · Conquer the Sectors", 14, GOLD)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 26)
	col.add_child(sp)
	var boot := ["◇  Igniting reactor core", "◇  Calibrating fabrication bays", "◇  Syncing sector network", "◇  All systems nominal"]
	var line_labels := []
	for s in boot:
		line_labels.append(_wlabel(col, s, 12, C_DIM))
	var prompt := _wlabel(col, "tap to begin", 13, CYAN)
	var tap := Button.new()
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var eb := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		tap.add_theme_stylebox_override(st, eb)
	tap.pressed.connect(_dismiss_welcome)
	_welcome.add_child(tap)
	# Animate everything in, then hold and auto-continue.
	for nd in [emblem, title, tag, prompt] + line_labels:
		nd.modulate.a = 0.0
	var tw := _welcome.create_tween()   # bound to the splash so an early skip kills it cleanly
	tw.tween_property(emblem, "modulate:a", 1.0, 0.4)
	tw.tween_property(title, "modulate:a", 1.0, 0.4)
	tw.tween_property(tag, "modulate:a", 1.0, 0.3)
	for l in line_labels:
		tw.tween_property(l, "modulate:a", 1.0, 0.18)
	tw.tween_property(prompt, "modulate:a", 1.0, 0.3)
	tw.tween_callback(func() -> void:
		var p := prompt.create_tween().set_loops()
		p.tween_property(prompt, "modulate:a", 0.35, 0.7)
		p.tween_property(prompt, "modulate:a", 1.0, 0.7))
	tw.tween_interval(2.2)
	tw.tween_callback(_dismiss_welcome)

func _wlabel(parent: Node, text: String, size: int, color: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", _fs(size))
	l.add_theme_color_override("font_color", Color.html(color))
	parent.add_child(l)
	return l

func _dismiss_welcome() -> void:
	if _welcome == null or _welcome_done:
		return
	_welcome_done = true
	var t := create_tween()
	t.tween_property(_welcome, "modulate:a", 0.0, 0.3)
	t.tween_callback(func() -> void:
		if is_instance_valid(_welcome):
			_welcome.queue_free()
		_welcome = null
		if GameState.pending_offline != "":
			_show_offline(GameState.pending_offline)
			GameState.pending_offline = "")

# Floating "+N" reward feedback on action completion (game-feel juice). Shown on
# the active loop pages so it doesn't distract when you're reading other screens.
func _on_action_reward(text: String, accent: String) -> void:
	if not (current in ["gather", "craft"]):
		return
	var holder := Control.new()
	holder.size = Vector2(get_viewport_rect().size.x, 28)
	holder.position = Vector2(0, 332)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var l := Label.new()
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text = text
	l.add_theme_font_size_override("font_size", _fs(16))
	l.add_theme_color_override("font_color", Color.html(accent))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(l)
	var tw := holder.create_tween()
	tw.set_parallel(true)
	tw.tween_property(holder, "position:y", 288.0, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "modulate:a", 0.0, 0.85).set_delay(0.12)
	tw.chain().tween_callback(holder.queue_free)

# Background-resume catch-up finished — show the same report modal as a cold launch.
func _on_offline_ready() -> void:
	if GameState.pending_offline != "":
		_show_offline(GameState.pending_offline)
		GameState.pending_offline = ""
	_refresh_top()
	_refresh_current()

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

# Pages whose content is static/expensive (positioned node-graph, big codex) and
# whose pan/scroll state must survive — don't rebuild them on passive ticks
# (gather/craft/infra loops fire resources_changed + skills_changed constantly).
const NO_TICK_REFRESH := ["research", "atlas"]

func _on_resources() -> void:
	_refresh_top()
	_update_badges()
	if current in NO_TICK_REFRESH:
		_update_coach()
		return
	_refresh_current()

# Guarded rebuild for frequent signals (skills/missions/bounty/action) — skips
# the graph/codex pages so their pan/scroll survives passive loops.
func _on_tick() -> void:
	_update_badges()
	if current in NO_TICK_REFRESH:
		_update_coach()
		return
	_refresh_current()

# Notification beads: a claimable mission lights the ☰ button and the Missions row.
func _update_badges() -> void:
	var claim := GameState.has_claimable_mission()
	if is_instance_valid(_ham_badge):
		_ham_badge.visible = claim
	var mi = nav_items.get("missions")
	if mi != null and is_instance_valid(mi.get("badge")):
		mi["badge"].visible = claim

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
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 10)
	var ham := Button.new()
	ham.text = "☰"
	ham.flat = true
	ham.focus_mode = Control.FOCUS_NONE
	ham.custom_minimum_size = Vector2(56, 50)
	ham.add_theme_font_size_override("font_size", _fs(28))
	ham.add_theme_color_override("font_color", Color.html(CYAN))
	ham.add_theme_color_override("font_color_hover", Color.html(CYAN))
	ham.add_theme_color_override("font_color_pressed", Color.html(GOLD))
	var empty_btn := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		ham.add_theme_stylebox_override(st, empty_btn)
	ham.pressed.connect(_toggle_drawer)
	_ham_btn = ham
	_ham_badge = _make_badge()
	_ham_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_ham_badge.offset_left = -16
	_ham_badge.offset_top = 6
	_ham_badge.offset_right = -4
	ham.add_child(_ham_badge)
	hdr.add_child(ham)
	var title := Label.new()
	title.text = "✦  STELLAR FORGE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.add_theme_font_size_override("font_size", _fs(15))
	title.add_theme_color_override("font_color", Color.html(CYAN))
	hdr.add_child(title)
	# Credits live in the header (primary currency, always visible) rather than
	# buried in the horizontally-scrolling resource bar.
	var cpill := PanelContainer.new()
	cpill.add_theme_stylebox_override("panel", _bordered(_mix(GOLD, INSET, 0.82), _mix(GOLD, LINE, 0.5), 1, 10))
	cpill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 4)
	cpill.add_child(ch)
	var cmark := Label.new()
	cmark.text = "₡"
	cmark.add_theme_font_size_override("font_size", _fs(15))
	cmark.add_theme_color_override("font_color", Color.html(GOLD))
	ch.add_child(cmark)
	_hdr_credits = Label.new()
	_hdr_credits.add_theme_font_size_override("font_size", _fs(15))
	_hdr_credits.add_theme_color_override("font_color", Color.html(GOLD))
	ch.add_child(_hdr_credits)
	hdr.add_child(cpill)
	topv.add_child(hdr)
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
	# Coaching banner (tutorial guidance) — shows the current objective + a directive.
	_coach_banner = PanelContainer.new()
	_coach_banner.add_theme_stylebox_override("panel", _card_style(_mix(GOLD, SURFACE, 0.84), _mix(GOLD, LINE, 0.4), 1, false))
	_coach_banner.visible = false
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 1)
	_coach_banner.add_child(cv)
	_coach_obj = Label.new()
	_coach_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_coach_obj.add_theme_font_size_override("font_size", _fs(12))
	_coach_obj.add_theme_color_override("font_color", Color.html(GOLD))
	cv.add_child(_coach_obj)
	_coach_hint = Label.new()
	_coach_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_coach_hint.add_theme_font_size_override("font_size", _fs(11))
	_coach_hint.add_theme_color_override("font_color", Color.html(CYAN))
	cv.add_child(_coach_hint)
	topv.add_child(_coach_banner)

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

	# ---- Slide-out navigation drawer (replaces the bottom nav) ----
	_build_drawer()

func _build_drawer() -> void:
	drawer = Control.new()
	drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	drawer.visible = false
	safe_margin.add_child(drawer)

	drawer_scrim = ColorRect.new()
	drawer_scrim.color = Color(0, 0, 0, 0.0)   # faded in on open
	drawer_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drawer_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	drawer_scrim.gui_input.connect(func(ev: InputEvent) -> void:
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			_close_drawer())
	drawer.add_child(drawer_scrim)

	drawer_panel = PanelContainer.new()
	drawer_panel.add_theme_stylebox_override("panel", _card_style(_mix(SURFACE, BG_BOT, 0.5), LINE, 1, true))
	drawer_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	drawer_panel.offset_top = 0
	drawer_panel.offset_bottom = 0
	drawer_panel.offset_left = -DRAWER_W
	drawer_panel.offset_right = 0
	drawer.add_child(drawer_panel)

	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	drawer_panel.add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	m.add_child(col)

	var dh := HBoxContainer.new()
	var dt := Label.new()
	dt.text = "✦  NAVIGATE"
	dt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dt.add_theme_font_size_override("font_size", _fs(15))
	dt.add_theme_color_override("font_color", Color.html(CYAN))
	dh.add_child(dt)
	var cx := Button.new()
	cx.text = "✕"
	cx.flat = true
	cx.focus_mode = Control.FOCUS_NONE
	cx.custom_minimum_size = Vector2(36, 36)
	cx.add_theme_font_size_override("font_size", _fs(16))
	cx.add_theme_color_override("font_color", Color.html(C_DIM))
	var eb := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		cx.add_theme_stylebox_override(st, eb)
	cx.pressed.connect(_close_drawer)
	dh.add_child(cx)
	col.add_child(dh)

	var sep := HSeparator.new()
	col.add_child(sep)

	var list_sc := ScrollContainer.new()
	list_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(list_sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_sc.add_child(list)
	for t in NAV_ALL:
		list.add_child(_make_drawer_item(t.id, t.label, t.icon))

func _make_drawer_item(id: String, label: String, icon: String) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 66)
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 14)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.offset_left = 12
	hb.offset_right = -12
	btn.add_child(hb)
	var bar := Panel.new()                       # left accent bar (active indicator)
	bar.custom_minimum_size = Vector2(5, 34)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(bar)
	var ic := Label.new()
	ic.text = icon
	ic.custom_minimum_size = Vector2(30, 0)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.add_theme_font_size_override("font_size", _fs(22))
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(ic)
	var lab := Label.new()
	lab.text = label
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lab.add_theme_font_size_override("font_size", _fs(17))
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(lab)
	var badge := _make_badge()
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(badge)
	btn.pressed.connect(_show.bind(id))
	nav_items[id] = {"btn": btn, "icon": ic, "label": lab, "bar": bar, "badge": badge}
	return btn

func _make_badge() -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(12, 12)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	var s := StyleBoxFlat.new()
	s.bg_color = Color.html(RED)
	s.set_corner_radius_all(6)
	s.set_border_width_all(2)
	s.border_color = Color.html(SURFACE)
	p.add_theme_stylebox_override("panel", s)
	return p

func _toggle_drawer() -> void:
	if drawer_open:
		_close_drawer()
	else:
		_open_drawer()

func _open_drawer() -> void:
	if drawer_open:
		return
	drawer_open = true
	drawer.visible = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(drawer_panel, "offset_left", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(drawer_panel, "offset_right", DRAWER_W, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(drawer_scrim, "color", Color(0, 0, 0, 0.55), 0.18)
	_update_coach()        # switch the pulse from the hamburger to the destination row

func _close_drawer() -> void:
	if not drawer_open:
		return
	drawer_open = false
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(drawer_panel, "offset_left", -DRAWER_W, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(drawer_panel, "offset_right", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(drawer_scrim, "color", Color(0, 0, 0, 0.0), 0.16)
	tw.chain().tween_callback(func() -> void: drawer.visible = false)
	_update_coach()

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
	GameState.equip_notice = ""        # transient; only shown right after a rejection
	for pid in pages:
		pages[pid].visible = (pid == id)
	for bid in nav_items:
		_style_nav(bid, bid == id)
	_close_drawer()
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
		"atlas":    _build_atlas()
		"research": _build_research()
		"more":     _build_more()
		"stats":    _build_stats()
	# Let touch drags fall through cards to the page's ScrollContainer so the
	# whole content surface scrolls (not just the dark background gaps). Panels
	# and containers default to MOUSE_FILTER_STOP, which eats the drag.
	if pages.has(current):
		_scroll_passthrough(pages[current])
	_update_coach()

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
		_refresh_current())
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
	var v := _card(GOLD, unlocked or active, 238)
	v.get_parent().set_meta("coach_id", id)
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
		_refresh_current())
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
	v.get_parent().set_meta("coach_id", id)
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
		# Locked zones (research-gated) get a padlock so progression reads clearly.
		var lbl: String = z["name"] if _zone_unlocked(z) else "🔒 " + z["name"]
		zone_items.append({"id": z["id"], "label": lbl})
	combat_zone = clampi(combat_zone, 0, GameData.ZONES.size() - 1)
	var cur_zone_id: String = GameData.ZONES[combat_zone]["id"]
	_subtabs(v, zone_items, cur_zone_id, RED, func(id: String) -> void:
		for i in GameData.ZONES.size():
			if GameData.ZONES[i]["id"] == id:
				combat_zone = i
		_refresh_current())
	var zone: Dictionary = GameData.ZONES[combat_zone]
	_section(v, zone.get("desc", ""), RED)
	if not _zone_unlocked(zone):
		# Sector access is research-gated, exactly as in the desktop game.
		var req: String = zone.get("research_req", "")
		var rname: String = GameData.RESEARCH.get(req, {}).get("name", req)
		var c := _card(RED, false)
		_card_head(c, "🔒", "SECTOR LOCKED", "", RED, false)
		var lr := Label.new()
		lr.text = "Requires research: %s" % rname
		lr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lr.add_theme_font_size_override("font_size", _fs(11))
		lr.add_theme_color_override("font_color", Color.html(C_WARN))
		c.add_child(lr)
		var gb := _card_button("Go to Research", PURP, true)
		gb.pressed.connect(func() -> void: _show("research"))
		c.add_child(gb)
		return
	var g := _grid(v)
	for eid in zone.get("enemies", []):
		if GameData.ENEMIES.has(eid):
			g.add_child(_enemy_card(eid, GameData.ENEMIES[eid]))

func _zone_unlocked(zone: Dictionary) -> bool:
	var req: String = zone.get("research_req", "")
	return req == "" or GameState.is_research_unlocked(req)

func _enemy_card(id: String, e: Dictionary) -> Control:
	var v := _card(RED, true)
	# Fill the grid row so both cards in a row match the taller one (enemies have
	# varying stat/loot line counts); a spacer pushes Engage to the bottom so the
	# buttons line up across the pair.
	var panel := v.get_parent()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.set_meta("coach_id", id)
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
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var b := _card_button("Engage", RED, true)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: GameState.start_task("combat", id))
	row.add_child(b)
	var intel := _card_button("ⓘ", CYAN, true)
	intel.custom_minimum_size = Vector2(46, 0)
	intel.pressed.connect(func() -> void: _show_enemy_intel(id))
	row.add_child(intel)
	v.add_child(row)
	return panel

## Enemy "Intel" modal — full stats, guaranteed/rare drops, and the module
## drop pool with lock states (ported from the desktop enemy_info_modal).
func _show_enemy_intel(eid: String) -> void:
	var e: Dictionary = GameData.ENEMIES.get(eid, {})
	if e.is_empty():
		return
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bordered("1a2336", RED, 2))
	panel.custom_minimum_size = Vector2(340, 0)
	center.add_child(panel)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 560)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(sc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	_clbl(v, "◎ Intel: " + e.get("name", eid), 16, RED)
	var stat_lines := [
		_line("HP %s" % GameData.fmt(e.get("hp", 0)), C_TEXT),
		_line("ATK %d / %.1fs" % [int(e.get("atk", 0)), float(e.get("interval", 2.0))], C_WARN),
		_line("DEF %d" % int(e.get("def", 0)), C_DIM),
		_line("Accuracy %d   ·   Evasion %d" % [int(e.get("accuracy", 0)), int(e.get("eva", 0))], C_DIM),
		_line("XP %d" % int(e.get("xp", 0)), GREEN),
	]
	if int(e.get("max_shield", 0)) > 0:
		stat_lines.insert(1, _line("Shield %s" % GameData.fmt(e["max_shield"]), CYAN))
	_inset(v, "COMBAT STATS", stat_lines, RED)
	var guaranteed := []
	var rare := []
	for row2 in e.get("loot", []):
		if float(row2[1]) >= 1.0:
			guaranteed.append(_line("%s %d-%d" % [GameData.res_name(row2[0]), int(row2[2]), int(row2[3])], _hex(GameData.color_for(row2[0]))))
		else:
			rare.append(_line("★ %s %d-%d  (%d%%)" % [GameData.res_name(row2[0]), int(row2[2]), int(row2[3]), int(float(row2[1]) * 100.0)], PURP))
	if not guaranteed.is_empty():
		_inset(v, "GUARANTEED DROPS", guaranteed, GOLD)
	if not rare.is_empty():
		_inset(v, "RARE DROPS", rare, PURP)
	var pool: Array = e.get("drop_pool", [])
	var chance := float(e.get("drop_chance", 0.0))
	if chance > 0.0 and not pool.is_empty():
		var mlines := []
		for mid in pool:
			var m: Dictionary = GameData.MODULES.get(mid, {})
			if m.is_empty():
				continue
			var unlocked := GameState.module_unlocked(mid)
			var nm: String = ("%s  [%s]" % [m.get("name", mid), GameData.SLOT_LABELS.get(m.get("slot", ""), "")])
			mlines.append(_line(("» " if unlocked else "🔒 ") + nm, CYAN if unlocked else C_MUTED))
		var head := "SUBSPACE SIGNAL — %d%% / kill" % int(round(chance * 100.0))
		_inset(v, head, mlines, CYAN)
	var ok := _card_button("Close", CYAN, true)
	ok.custom_minimum_size = Vector2(0, 42)
	ok.pressed.connect(func() -> void: overlay.queue_free())
	v.add_child(ok)

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
	var eff := int(float(p["eff"]) * 100.0)
	_stat_strip(v, [
		["⚡ GEN", "%d kW" % int(p["gen"]), GREEN],
		["USE", "%d kW" % int(p["cons"]), GOLD],
		["GRID", "%d%%" % eff, BUILD if float(p["eff"]) >= 1.0 else RED],
	])
	_subtabs(v, GameData.BUILDING_CATS, build_cat, BUILD, func(id: String) -> void:
		build_cat = id
		_refresh_current())
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
	v.get_parent().set_meta("coach_id", bid)
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
	var mtype: String = m.get("type", "")
	var cur := int(GameState.missions_progress.get(mid, 0))
	var qty := int(m.get("qty", 1))
	if mtype == "gather_multi":
		cur = GameState.multi_have(m)
		for s in m.get("target", {}):
			var need := int(m["target"][s])
			var have := mini(GameState.amount(s), need)
			_lbl_wrap(vb, "%s  %d / %d" % [GameData.res_name(s), have, need], 10, GREEN if have >= need else C_DIM)
	elif mtype == "loadout_check":
		cur = qty if done else 0
		_lbl_wrap(vb, ("✓ Weapon + Shield equipped" if done else "Equip a Weapon and a Shield"), 10, GREEN if done else C_WARN)
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
				_refresh_current())
	v.add_child(wb)

func _back_header(v: VBoxContainer) -> void:
	var b := Button.new()
	b.text = "☰  Menu"
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", _fs(13))
	b.add_theme_color_override("font_color", Color.html(C_DIM))
	b.pressed.connect(_open_drawer)
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
		_stat_strip(v, [
			["ATK", "%.0f" % s["atk"], RED],
			["HP", GameData.fmt(s["hp"]), GREEN],
			["DEF", "%.0f" % s["def"], CYAN],
			["SHIELD", GameData.fmt(s["shield"]), "3a9fff"],
		])
		var over: bool = s["energy_load"] > s["energy_cap"] and s["energy_cap"] > 0.0
		var erow := HBoxContainer.new()
		erow.add_theme_constant_override("separation", 8)
		var elab := Label.new()
		elab.text = "⚡ Energy"
		elab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		elab.add_theme_font_size_override("font_size", _fs(10))
		elab.add_theme_color_override("font_color", Color.html(C_DIM))
		erow.add_child(elab)
		var ebar := ProgressBar.new()
		ebar.custom_minimum_size = Vector2(0, 8)
		ebar.show_percentage = false
		ebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ebar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ebar.max_value = maxf(1.0, float(s["energy_cap"]))
		ebar.value = float(s["energy_load"])
		_style_bar(ebar, RED if over else CYAN)
		erow.add_child(ebar)
		var eval := Label.new()
		eval.text = "%d / %d kW%s" % [int(s["energy_load"]), int(s["energy_cap"]), "  ⚠" if over else ""]
		eval.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		eval.add_theme_font_size_override("font_size", _fs(10))
		eval.add_theme_color_override("font_color", Color.html(C_WARN if over else C_DIM))
		erow.add_child(eval)
		v.add_child(erow)
	_subtabs(v, [{"id": "loadout", "label": "Loadout"}, {"id": "modules", "label": "Modules"}, {"id": "fittings", "label": "Fittings"}, {"id": "hulls", "label": "Hulls"}], ship_view, CYAN, func(id: String) -> void:
		ship_view = id
		_refresh_current())
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

## A wrapping row of compact stat pills: each [label, value, accent_hex].
func _stat_strip(v: VBoxContainer, pairs: Array) -> void:
	var fc := HFlowContainer.new()
	fc.add_theme_constant_override("h_separation", 6)
	fc.add_theme_constant_override("v_separation", 6)
	for p in pairs:
		var pill := PanelContainer.new()
		var sb := _bordered(_mix(p[2], INSET, 0.86), _mix(p[2], LINE, 0.55), 1, 8)
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		pill.add_theme_stylebox_override("panel", sb)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 5)
		pill.add_child(hb)
		var l := Label.new()
		l.text = p[0]
		l.add_theme_font_size_override("font_size", _fs(9))
		l.add_theme_color_override("font_color", Color.html(C_DIM))
		hb.add_child(l)
		var val := Label.new()
		val.text = str(p[1])
		val.add_theme_font_size_override("font_size", _fs(12))
		val.add_theme_color_override("font_color", Color.html(p[2]))
		hb.add_child(val)
		fc.add_child(pill)
	v.add_child(fc)

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
	if GameState.equip_notice != "":
		var warn := Label.new()
		warn.text = "⚠ " + GameState.equip_notice
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_theme_font_size_override("font_size", _fs(11))
		warn.add_theme_color_override("font_color", Color.html(RED))
		v.add_child(warn)
	# Live energy grid readout (load / capacity).
	var ss := GameState.ship_stats()
	if not ss.is_empty():
		var grid := Label.new()
		var load := int(ss.get("energy_load", 0.0))
		var cap := int(ss.get("energy_cap", 0.0))
		grid.text = "⚡ Grid load %d / %d" % [load, cap]
		grid.add_theme_font_size_override("font_size", _fs(11))
		grid.add_theme_color_override("font_color", Color.html(RED if load > cap else C_DIM))
		v.add_child(grid)
	var slot_items := []
	for st in ["weapon", "shield", "armor", "battery", "engine", "sensor", "cooling"]:
		slot_items.append({"id": st, "label": GameData.SLOT_LABELS.get(st, st)})
	_subtabs(v, slot_items, ship_mod_slot, CYAN, func(id: String) -> void:
		ship_mod_slot = id
		_refresh_current())
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
	c.get_parent().set_meta("coach_id", mid)
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
	c.get_parent().set_meta("coach_id", hid)
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
# Faithful port of the desktop research_page graph: per-discipline tabs, each a
# 2D canvas of positioned nodes with parent→child branch lines drawn between them.
const RES_NODE_W := 154.0
const RES_NODE_H := 72.0
const RES_POS_SCALE := 1.42
const RES_PAD := 12.0

func _build_research() -> void:
	var v := _clear("research")
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "RESEARCH NETWORK"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.add_theme_font_size_override("font_size", _fs(16))
	title.add_theme_color_override("font_color", Color.html(PURP))
	head.add_child(title)
	var cr := Label.new()
	cr.text = "₡%s" % GameData.fmt(GameState.credits)
	cr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cr.add_theme_font_size_override("font_size", _fs(13))
	cr.add_theme_color_override("font_color", Color.html(GOLD))
	head.add_child(cr)
	v.add_child(head)

	var tabs: Array = GameData.RESEARCH_TABS.duplicate()
	tabs.append("Recursion")
	if not tabs.has(research_tab):
		research_tab = tabs[0]
	var tab_items := []
	for t in tabs:
		tab_items.append({"id": t, "label": t})
	_subtabs(v, tab_items, research_tab, PURP, func(id: String) -> void:
		research_tab = id
		_refresh_current())

	if research_tab == "Recursion":
		_build_recursion(v)
		return

	var graph: Dictionary = GameData.RESEARCH_GRAPHS[research_tab]
	var pos: Dictionary = graph["pos"]
	var nodes: Array = graph["nodes"]
	var maxx := 0.0
	var maxy := 0.0
	for nid in pos:
		var p: Vector2 = pos[nid]
		maxx = maxf(maxx, p.x)
		maxy = maxf(maxy, p.y)
	# Node names are capped to 2 lines (below), so RES_NODE_H bounds every node;
	# extra slack guarantees edge nodes pan fully into view.
	var cw: float = maxx * RES_POS_SCALE + RES_NODE_W + RES_PAD * 4.0
	var ch: float = maxy * RES_POS_SCALE + RES_NODE_H + RES_PAD * 4.0

	# One both-axis scroller pans the wide/tall tree in 2D (desktop parity). The
	# page's own vertical scroll is disabled for this page so the two scrollers
	# don't compete for the same drag — that was blocking all movement.
	pages["research"].vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var hs := ScrollContainer.new()
	hs.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Fill the page's content area (a disabled outer scroll sizes children to
	# their min, not the viewport, so set the height explicitly).
	var avail: float = pages["research"].size.y
	if avail < 200.0:
		avail = get_viewport_rect().size.y - 300.0
	hs.custom_minimum_size = Vector2(0, maxf(340.0, avail - 112.0))
	var canvas := Control.new()
	canvas.custom_minimum_size = Vector2(cw, ch)
	canvas.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	canvas.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	canvas.draw.connect(_draw_research_branches.bind(canvas, nodes, pos))
	for nid in nodes:
		if not GameData.RESEARCH.has(nid):
			continue
		var node := _research_node(nid)
		node.position = (pos[nid] as Vector2) * RES_POS_SCALE + Vector2(RES_PAD, RES_PAD)
		node.size = Vector2(RES_NODE_W, RES_NODE_H)
		canvas.add_child(node)
	hs.add_child(canvas)
	v.add_child(hs)

func _draw_research_branches(canvas: Control, nodes: Array, pos: Dictionary) -> void:
	for nid in nodes:
		if not GameData.RESEARCH.has(nid):
			continue
		var par: String = GameData.RESEARCH[nid].get("parent", "")
		# Cross-tab parents (not in this layout) are treated as roots — no line.
		if par == "" or not pos.has(par) or not pos.has(nid):
			continue
		var p1: Vector2 = (pos[par] as Vector2) * RES_POS_SCALE + Vector2(RES_PAD + RES_NODE_W, RES_PAD + RES_NODE_H * 0.5)
		var p2: Vector2 = (pos[nid] as Vector2) * RES_POS_SCALE + Vector2(RES_PAD, RES_PAD + RES_NODE_H * 0.5)
		var col := Color.html(GREEN) if GameState.is_research_unlocked(nid) else Color(0.42, 0.46, 0.62, 0.7)
		# Elbow connector (horizontal out of parent, vertical, into child) reads
		# cleaner on dense trees than a single diagonal.
		var midx := (p1.x + p2.x) * 0.5
		canvas.draw_line(p1, Vector2(midx, p1.y), col, 2.0)
		canvas.draw_line(Vector2(midx, p1.y), Vector2(midx, p2.y), col, 2.0)
		canvas.draw_line(Vector2(midx, p2.y), p2, col, 2.0)

func _research_node(id: String) -> Control:
	var t: Dictionary = GameData.RESEARCH[id]
	var researched := GameState.is_research_unlocked(id)
	var available := GameState.research_available(id)
	var border := GREEN if researched else (C_WARN if available else "39425e")
	var fill := _mix(GREEN, INSET, 0.82) if researched else (_mix(PURP, INSET, 0.86) if available else "151b2c")
	# Plain Panel (not PanelContainer) so the node keeps a fixed, uniform height
	# regardless of name length; overflow is clipped instead of growing the node
	# (which would push edge nodes past the canvas bounds).
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(RES_NODE_W, RES_NODE_H)
	panel.clip_contents = true
	panel.set_meta("coach_id", id)
	panel.add_theme_stylebox_override("panel", _bordered(fill, border, 2 if (available or researched) else 1, 8))
	panel.tooltip_text = t.get("desc", "")
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 6)
	panel.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.add_child(vb)
	var nm := Label.new()
	nm.text = t.get("name", id)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nm.add_theme_font_size_override("font_size", _fs(10))
	nm.add_theme_color_override("font_color", Color.html(C_TEXT if (available or researched) else C_MUTED))
	vb.add_child(nm)
	var status := Label.new()
	status.add_theme_font_size_override("font_size", _fs(10))
	if researched:
		status.text = "✓ Researched"
		status.add_theme_color_override("font_color", Color.html(GREEN))
	else:
		var cred := int(t.get("credits", 0))
		var extra: int = t.get("items", {}).size()
		status.text = "₡%s%s" % [GameData.fmt(cred), ("  +%d mat" % extra) if extra > 0 else ""]
		status.add_theme_color_override("font_color", Color.html(GOLD if GameState.credits >= cred else C_WARN))
	vb.add_child(status)
	if not researched:
		# Tap opens a detail modal with the full requirements (incl. material names)
		# — even when not yet affordable, so the player can see what's needed.
		var overlay := Button.new()
		overlay.flat = true
		overlay.focus_mode = Control.FOCUS_NONE
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.pressed.connect(func() -> void: _show_research_detail(id))
		panel.add_child(overlay)
	return panel

## Research node detail modal: name, description, full requirements (credits +
## each material with have/need), parent gate, and a Research button.
func _show_research_detail(id: String) -> void:
	var t: Dictionary = GameData.RESEARCH[id]
	var researched := GameState.is_research_unlocked(id)
	var available := GameState.research_available(id)
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bordered("1a2336", PURP, 2))
	panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	_clbl(v, "✦  " + t.get("name", id), 16, PURP)
	if t.get("desc", "") != "":
		var d := Label.new()
		d.text = t["desc"]
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.add_theme_font_size_override("font_size", _fs(11))
		d.add_theme_color_override("font_color", Color.html(C_DIM))
		v.add_child(d)
	var lines := []
	var cred := int(t.get("credits", 0))
	lines.append(_line("₡ Credits   %s / %s" % [GameData.fmt(GameState.credits), GameData.fmt(cred)], GOLD if GameState.credits >= cred else C_WARN))
	for sym in t.get("items", {}):
		var need := int(t["items"][sym])
		var have := GameState.amount(sym)
		lines.append(_line("%s   %s / %d" % [GameData.res_name(sym), GameData.fmt(have), need], GREEN if have >= need else C_WARN))
	_inset(v, "REQUIREMENTS", lines, PURP)
	var par: String = t.get("parent", "")
	if par != "" and not GameState.is_research_unlocked(par):
		_clbl(v, "🔒 First research: " + GameData.RESEARCH.get(par, {}).get("name", par), 11, C_WARN)
	if researched:
		_clbl(v, "✓ Researched", 13, GREEN)
	else:
		var rb := _card_button("Research", PURP, available)
		rb.custom_minimum_size = Vector2(0, 42)
		if available:
			rb.pressed.connect(func() -> void:
				GameState.unlock_research(id)
				overlay.queue_free())
		v.add_child(rb)
	var cx := _card_button("Close", C_MUTED, true)
	cx.custom_minimum_size = Vector2(0, 40)
	cx.pressed.connect(func() -> void: overlay.queue_free())
	v.add_child(cx)

# Recursion tab: infinite repeatable research (+5%/level sinks).
func _build_recursion(v: VBoxContainer) -> void:
	pages["research"].vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_section(v, "Recursion — infinite upgrades (+5% / level)", PURP)
	for rid in GameState.REPEATABLE_ORDER:
		var rd: Dictionary = GameState.REPEATABLE[rid]
		var lvl := GameState.repeatable_level(rid)
		var c := _card(PURP, true)
		_card_head(c, "∞", rd["name"], "Lv %d" % lvl, PURP, true)
		_clbl(c, "%s · %s" % [rd["field"], rd["desc"]], 11, C_DIM)
		_clbl(c, "Current bonus: +%d%%" % int(round(lvl * float(rd["bonus_value"]) * 100.0)), 11, GREEN)
		var cost: Dictionary = GameState.repeatable_cost(rid)
		var cost_lines := []
		for res in cost:
			var have: bool = (GameState.credits >= int(cost[res])) if res == "credits" else (GameState.amount(res) >= int(cost[res]))
			var lbl: String = ("₡%s" % GameData.fmt(cost[res])) if res == "credits" else ("%s %s" % [GameData.fmt(cost[res]), GameData.res_name(res)])
			cost_lines.append(_line(lbl, GOLD if have else C_WARN))
		_inset(c, "NEXT LEVEL COST", cost_lines, PURP)
		var can := GameState.can_unlock_repeatable(rid)
		var b := _card_button("Research Lv %d" % (lvl + 1), PURP, can)
		if can:
			b.pressed.connect(func() -> void: GameState.unlock_repeatable(rid))
		c.add_child(b)
		v.add_child(c.get_parent())     # attach the card panel to the page

# ============================================================ ATLAS / CODEX
func _build_atlas() -> void:
	var v := _clear("atlas")
	_back_header(v)
	_clbl(v, "ATLAS / CODEX", 16, CYAN)
	_subtabs(v, [{"id": "materials", "label": "Materials"}, {"id": "enemies", "label": "Enemies"}], atlas_mode, CYAN, func(id: String) -> void:
		atlas_mode = id
		_refresh_current())
	if atlas_mode == "materials":
		_atlas_materials(v)
	else:
		_atlas_enemies(v)

func _atlas_get_index() -> Dictionary:
	if not _atlas_index.is_empty():
		return _atlas_index
	var idx := {}
	for gid in GameData.GATHER:
		var a: Dictionary = GameData.GATHER[gid]
		for row in a.get("loot", []):
			_atlas_add(idx, row[0], "sources", "⛏ " + a.get("name", gid))
	for rid in GameData.CRAFT:
		var r: Dictionary = GameData.CRAFT[rid]
		for s in r.get("outputs", {}):
			_atlas_add(idx, s, "sources", "⚙ " + r.get("name", rid))
		for row in r.get("bonus", []):
			_atlas_add(idx, row[0], "sources", "⚙ " + r.get("name", rid))
		for s in r.get("inputs", {}):
			_atlas_add(idx, s, "uses", "⚙ " + r.get("name", rid))
	for eid in GameData.ENEMIES:
		var e: Dictionary = GameData.ENEMIES[eid]
		for row in e.get("loot", []):
			_atlas_add(idx, row[0], "sources", "◎ " + e.get("name", eid))
	for bid in GameData.BUILDINGS:
		var b: Dictionary = GameData.BUILDINGS[bid]
		for s in b.get("yield", {}):
			_atlas_add(idx, s, "sources", "⌂ " + b.get("name", bid))
		for s in b.get("input", {}):
			_atlas_add(idx, s, "uses", "⌂ " + b.get("name", bid))
		for s in b.get("cost", {}):
			if s != "credits":
				_atlas_add(idx, s, "uses", "⌂ " + b.get("name", bid))
	for hid in GameData.HULLS:
		for s in GameData.HULLS[hid].get("cost", {}):
			if s != "credits":
				_atlas_add(idx, s, "uses", "⛭ " + GameData.HULLS[hid].get("name", hid))
	for mid in GameData.MODULES:
		for s in GameData.MODULES[mid].get("cost", {}):
			if s != "credits":
				_atlas_add(idx, s, "uses", "▣ " + GameData.MODULES[mid].get("name", mid))
	for tid in GameData.RESEARCH:
		for s in GameData.RESEARCH[tid].get("items", {}):
			_atlas_add(idx, s, "uses", "✦ " + GameData.RESEARCH[tid].get("name", tid))
	_atlas_index = idx
	return idx

func _atlas_add(idx: Dictionary, sym: String, key: String, label: String) -> void:
	if not idx.has(sym):
		idx[sym] = {"sources": [], "uses": []}
	if not idx[sym][key].has(label):
		idx[sym][key].append(label)

const ATLAS_CATS := [
	{"id": "gathered", "label": "Gathered", "icon": "⛏"},
	{"id": "crafted",  "label": "Crafted",  "icon": "⚙"},
	{"id": "combat",   "label": "Combat",   "icon": "◎"},
	{"id": "built",    "label": "Built",    "icon": "⌂"},
	{"id": "other",    "label": "Other",    "icon": ""},
]

func _atlas_materials(v: VBoxContainer) -> void:
	var idx := _atlas_get_index()
	var cat_items := []
	for c in ATLAS_CATS:
		cat_items.append({"id": c.id, "label": c.label})
	_subtabs(v, cat_items, atlas_mat_cat, CYAN, func(id: String) -> void:
		atlas_mat_cat = id
		_refresh_current())
	var want_icon := ""
	for c in ATLAS_CATS:
		if c.id == atlas_mat_cat:
			want_icon = c.icon
	var n := 0
	# Lightweight rows, filtered by source category so each view stays small/fast.
	for sym in GameData.RESOURCES:
		var info = idx.get(sym, null)
		if info == null or (info["sources"].is_empty() and info["uses"].is_empty()):
			continue
		var match_cat := false
		if atlas_mat_cat == "other":
			match_cat = info["sources"].is_empty()
		else:
			for s in info["sources"]:
				if (s as String).begins_with(want_icon):
					match_cat = true
					break
		if not match_cat:
			continue
		n += 1
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _bordered(SURFACE, LINE, 1, 8))
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		panel.add_child(col)
		var nm := Label.new()
		nm.text = "%s   ₡%d" % [GameData.res_name(sym), GameData.value_of(sym)]
		nm.add_theme_font_size_override("font_size", _fs(13))
		nm.add_theme_color_override("font_color", GameData.color_for(sym))
		col.add_child(nm)
		if not info["sources"].is_empty():
			_atlas_line(col, "From: ", info["sources"], GREEN)
		if not info["uses"].is_empty():
			_atlas_line(col, "Used in: ", info["uses"], C_DIM)
		v.add_child(panel)
	if n == 0:
		_empty(v, "No materials catalogued.")

func _atlas_line(parent: Node, prefix: String, items: Array, color: String) -> void:
	var shown := items
	var more := 0
	if items.size() > 5:
		shown = items.slice(0, 5)
		more = items.size() - 5
	var l := Label.new()
	l.text = prefix + ", ".join(shown) + ("  +%d more" % more if more > 0 else "")
	# Single clipped line (no autowrap) — autowrap shaping on ~250 labels made the
	# Atlas page slow to open.
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_size_override("font_size", _fs(10))
	l.add_theme_color_override("font_color", Color.html(color))
	parent.add_child(l)

func _atlas_enemies(v: VBoxContainer) -> void:
	for z in GameData.ZONES:
		_section(v, "%s  (★%d)" % [z.get("name", ""), int(z.get("difficulty", 1))], RED)
		for eid in z.get("enemies", []):
			if not GameData.ENEMIES.has(eid):
				continue
			var e: Dictionary = GameData.ENEMIES[eid]
			var c := _card(RED, true)
			var badge := "DROPS" if (float(e.get("drop_chance", 0.0)) > 0.0 and not (e.get("drop_pool", []) as Array).is_empty()) else ""
			_card_head(c, "◎", e.get("name", eid), badge, RED, true)
			var stats := [
				_line("HP %s   DEF %d" % [GameData.fmt(e.get("hp", 0)), int(e.get("def", 0))], C_TEXT),
				_line("ATK %d / %.1fs" % [int(e.get("atk", 0)), float(e.get("interval", 2.0))], C_WARN),
			]
			if int(e.get("max_shield", 0)) > 0:
				stats.append(_line("Shield %s" % GameData.fmt(e["max_shield"]), CYAN))
			_inset(c, "STATS", stats, RED)
			var ib := _card_button("ⓘ Intel", CYAN, true)
			ib.pressed.connect(func() -> void: _show_enemy_intel(eid))
			c.add_child(ib)
			v.add_child(c.get_parent())

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

	var used := GameState.used_slots()
	var cap := GameState.max_slots()
	_section(v, "Storage  %d / %d slots — tap a slot to sell" % [used, cap], GOLD)
	# Slot-by-slot grid (like the desktop inventory): owned materials fill tiles
	# left-to-right, padded with empty slots up to the current capacity.
	var owned := []
	for sym in GameData.RESOURCES:
		if GameState.amount(sym) > 0:
			owned.append(sym)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 7)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(grid)
	for sym in owned:
		grid.add_child(_storage_tile(sym))
	var total: int = maxi(cap, int(ceil(owned.size() / 4.0)) * 4)
	for _i in range(total - owned.size()):
		grid.add_child(_storage_slot_empty())
	if owned.is_empty():
		_empty(v, "Storage empty — go gather something.")
	# Expand storage (credit sink): +1 slot at 1000·1.5^n.
	var up_cost := GameState.storage_upgrade_cost()
	var can_up := GameState.credits >= up_cost
	var up := _card_button("Expand Storage  +1 slot   ₡%s" % GameData.fmt(up_cost), GOLD, can_up)
	up.custom_minimum_size = Vector2(0, 42)
	if can_up:
		up.pressed.connect(func() -> void: GameState.upgrade_storage())
	v.add_child(up)

	_section(v, "System", CYAN)
	# Options: offline-combat toggle (off by default, like desktop).
	var oc := GameState.offline_combat
	var oc_btn := _card_button("Offline Combat: %s" % ("ON" if oc else "OFF"), GREEN if oc else C_MUTED, true)
	oc_btn.custom_minimum_size = Vector2(0, 44)
	oc_btn.pressed.connect(func() -> void:
		GameState.offline_combat = not GameState.offline_combat
		_refresh_current())
	v.add_child(oc_btn)
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
			_refresh_current())
	v.add_child(reset_btn)

func _storage_tile(sym: String) -> Control:
	var amt := GameState.amount(sym)
	var rcol := _hex(GameData.color_for(sym))
	var val: int = maxi(1, GameData.value_of(sym))
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 90)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _bordered(_mix(rcol, SURFACE, 0.9), rcol, 1, 8))
	panel.tooltip_text = "%s — tap to sell all for ₡%s" % [GameData.res_name(sym), GameData.fmt(amt * val)]
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 5)
	panel.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(vb)
	var nm := Label.new()
	nm.text = GameData.res_name(sym)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nm.add_theme_font_size_override("font_size", _fs(9))
	nm.add_theme_color_override("font_color", Color.html(rcol))
	vb.add_child(nm)
	var qty := Label.new()
	qty.text = GameData.fmt(amt)
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty.add_theme_font_size_override("font_size", _fs(14))
	qty.add_theme_color_override("font_color", Color.html(C_TEXT))
	vb.add_child(qty)
	var pv := Label.new()
	pv.text = "₡%s" % GameData.fmt(amt * val)
	pv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_theme_font_size_override("font_size", _fs(9))
	pv.add_theme_color_override("font_color", Color.html(GOLD))
	vb.add_child(pv)
	var overlay := Button.new()
	overlay.flat = true
	overlay.focus_mode = Control.FOCUS_NONE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.pressed.connect(func() -> void: GameState.sell_all(sym))
	panel.add_child(overlay)
	return panel

func _storage_slot_empty() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 90)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _bordered(INSET, LINE, 1, 8))
	var cc := CenterContainer.new()
	panel.add_child(cc)
	var dot := Label.new()
	dot.text = "·"
	dot.add_theme_font_size_override("font_size", _fs(16))
	dot.add_theme_color_override("font_color", Color.html(C_MUTED))
	cc.add_child(dot)
	return panel

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
		# PASS so a horizontal drag over a tab reaches the strip's ScrollContainer
		# (which then scrolls and cancels the tap); a clean tap still selects.
		b.mouse_filter = Control.MOUSE_FILTER_PASS
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
	var item = nav_items.get(id)
	if item == null:
		return
	var accent: String = DOMAIN.get(id, CYAN)
	item["icon"].add_theme_color_override("font_color", Color.html(accent if active else C_DIM))
	item["label"].add_theme_color_override("font_color", Color.html(C_TEXT if active else C_DIM))
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color.html(accent) if active else Color(0, 0, 0, 0)
	bs.set_corner_radius_all(2)
	item["bar"].add_theme_stylebox_override("panel", bs)
	var nbg := StyleBoxFlat.new()
	nbg.bg_color = Color.html(_mix(accent, SURFACE, 0.8)) if active else Color(0, 0, 0, 0)
	nbg.set_corner_radius_all(8)
	for st in ["normal", "hover", "pressed", "focus"]:
		item["btn"].add_theme_stylebox_override(st, nbg)

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
	if is_instance_valid(_hdr_credits):
		_hdr_credits.text = GameData.fmt(GameState.credits)
	if res_bar == null:
		return
	for c in res_bar.get_children():
		res_bar.remove_child(c)
		c.queue_free()
	var any := false
	for sym in GameData.RESOURCES:
		var amt := GameState.amount(sym)
		if amt <= 0:
			continue
		any = true
		res_bar.add_child(_chip(GameData.res_name(sym), GameData.fmt(amt), _hex(GameData.color_for(sym)), false))
	if not any:
		var hint := Label.new()
		hint.text = "No materials yet — gather to begin"
		hint.add_theme_font_size_override("font_size", _fs(10))
		hint.add_theme_color_override("font_color", Color.html(C_MUTED))
		res_bar.add_child(hint)

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
	_banner_name.add_theme_color_override("font_color", Color.html(C_TEXT if t != "" else C_DIM))
	_banner_bar.visible = t != ""        # collapse the bar's row when idle (tighter header)
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
