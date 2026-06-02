extends Control
## Mobile shell for the ported horizonidle content: grid cards with category
## sub-tabs (gather/craft/combat) and a credit-funded research tree.

const TABS := [
	{"id": "gather",   "label": "Gather"},
	{"id": "craft",    "label": "Craft"},
	{"id": "combat",   "label": "Combat"},
	{"id": "build",    "label": "Build"},
	{"id": "research", "label": "Research"},
	{"id": "stats",    "label": "More"},
]

const C_BG := "0b1220"
const C_PANEL := "111c2e"
const C_TEXT := "e6ebf2"
const C_DIM := "8a93a5"
const C_MUTED := "5a6478"
const C_WARN := "d9a441"
const GOLD := "d9b24c"
const CYAN := "4fd2e0"
const GREEN := "5ad17a"
const RED := "e0654f"
const PURP := "9a7ad6"
const BUILD := "e0944f"

var content: Control
var pages := {}
var tab_buttons := {}
var current := ""
var gather_cat := "terrestrial"
var craft_cat := "basics"
var combat_zone := 0
var build_cat := "power"
var res_bar: HBoxContainer
var active_label: Label
var _active_bar: ProgressBar = null
var _active_timer: Label = null
var _combat_hp_bar: ProgressBar = null
var _combat_hp_label: Label = null
var _reset_armed := false

func _ready() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
	_build()
	GameState.resources_changed.connect(_on_resources)
	GameState.skills_changed.connect(_refresh_current)
	GameState.research_changed.connect(_refresh_all)
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
	if is_instance_valid(_combat_hp_bar):
		var mx := GameState.combat_max_hp()
		_combat_hp_bar.max_value = mx
		_combat_hp_bar.value = GameState.combat_hp
		if is_instance_valid(_combat_hp_label):
			_combat_hp_label.text = "%d / %d HP" % [int(GameState.combat_hp), int(mx)]
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
	title.add_theme_font_size_override("font_size", 17)
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
	res_bar.add_theme_constant_override("separation", 14)
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
	tabs.add_theme_constant_override("separation", 2)
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
	for pid in pages:
		pages[pid].visible = (pid == id)
	for bid in tab_buttons:
		_style_tab(tab_buttons[bid], bid == id)
	_refresh_current()

func _refresh_all() -> void:
	_refresh_top()
	_refresh_current()

func _refresh_current() -> void:
	_active_bar = null
	_active_timer = null
	_combat_hp_bar = null
	_combat_hp_label = null
	match current:
		"gather":   _build_gather()
		"craft":    _build_craft()
		"combat":   _build_combat()
		"build":    _build_infra()
		"research": _build_research()
		"stats":    _build_stats()

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
	var v := _card(GOLD, unlocked or active)
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
	var v := _card(CYAN, unlocked or active)
	_card_head(v, "⚙", r["name"], "Lv %d" % int(r.get("level_req", 1)), CYAN, unlocked)
	if unlocked:
		var in_lines := []
		for sym in r.get("inputs", {}):
			in_lines.append(_line("%d %s" % [int(r["inputs"][sym]), GameData.res_name(sym)], _hex(GameData.color_for(sym))))
		_inset(v, "INPUTS", in_lines, CYAN)
		var d := Label.new()
		d.text = "▼"
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.add_theme_font_size_override("font_size", 9)
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
	_skill_banner(v, "BATTLE STATION", "combat", RED)
	# hull bar
	var hb := HBoxContainer.new()
	var hl := Label.new()
	hl.text = "HULL"
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hl.add_theme_font_size_override("font_size", 11)
	hl.add_theme_color_override("font_color", Color.html(RED))
	hb.add_child(hl)
	_combat_hp_label = Label.new()
	_combat_hp_label.text = "%d / %d HP" % [int(GameState.combat_hp), int(GameState.combat_max_hp())]
	_combat_hp_label.add_theme_font_size_override("font_size", 10)
	_combat_hp_label.add_theme_color_override("font_color", Color.html(C_DIM))
	hb.add_child(_combat_hp_label)
	v.add_child(hb)
	_combat_hp_bar = ProgressBar.new()
	_combat_hp_bar.custom_minimum_size = Vector2(0, 9)
	_combat_hp_bar.show_percentage = false
	_combat_hp_bar.max_value = GameState.combat_max_hp()
	_combat_hp_bar.value = GameState.combat_hp
	_style_bar(_combat_hp_bar, RED)
	v.add_child(_combat_hp_bar)
	var st := Label.new()
	st.text = "Attack %.0f   ·   Regen %.0f/s" % [GameState.combat_attack(), GameState.combat_max_hp() * GameState.HP_REGEN]
	st.add_theme_font_size_override("font_size", 10)
	st.add_theme_color_override("font_color", Color.html(C_DIM))
	v.add_child(st)

	# zone sub-tabs
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
	var active := (GameState.active_type == "combat" and GameState.active_id == id)
	var v := _card(RED, true)
	_card_head(v, "◎", e["name"], "", RED, true)
	_inset(v, "TARGET", [
		_line("HP %d" % int(e["hp"]), C_TEXT),
		_line("ATK %d / %.1fs" % [int(e.get("atk", 0)), float(e.get("interval", 2.0))], C_WARN),
		_line("DEF %d" % int(e.get("def", 0)), C_DIM),
	], RED)
	_inset(v, "SALVAGE", _loot_lines(e.get("loot", [])), RED)
	_action_controls(v, "combat", id, active, RED, "Engage", "Retreat")
	return v.get_parent()

# ============================================================ INFRASTRUCTURE
func _build_infra() -> void:
	var v := _clear("build")
	_skill_banner(v, "INFRASTRUCTURE", "infrastructure", BUILD)
	var p := GameState.infra_power()
	var e := Label.new()
	e.text = "⚡ %d kW gen  ·  %d kW use  ·  Grid %d%%" % [int(p["gen"]), int(p["cons"]), int(float(p["eff"]) * 100.0)]
	e.add_theme_font_size_override("font_size", 11)
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

# ============================================================ RESEARCH
func _build_research() -> void:
	var v := _clear("research")
	var title := Label.new()
	title.text = "RESEARCH NETWORK"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color.html(PURP))
	v.add_child(title)
	var cr := Label.new()
	cr.text = "Credits: ₡%s   ·   sell materials in More" % GameData.fmt(GameState.credits)
	cr.add_theme_font_size_override("font_size", 11)
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
	_section(v, "CREW", CYAN)
	for sk in ["harvesting", "fabrication", "combat", "infrastructure"]:
		_skill_banner(v, sk.to_upper(), sk, CYAN)
	var crl := Label.new()
	crl.text = "Credits: ₡%s" % GameData.fmt(GameState.credits)
	crl.add_theme_color_override("font_color", Color.html(GOLD))
	v.add_child(crl)

	_section(v, "STORAGE  (tap Sell for credits)", CYAN)
	var any := false
	for sym in GameData.RESOURCES:
		var amt := GameState.amount(sym)
		if amt <= 0:
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var n := Label.new()
		n.text = GameData.res_name(sym)
		n.add_theme_color_override("font_color", GameData.color_for(sym))
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		var a := Label.new()
		a.text = GameData.fmt(amt)
		a.add_theme_color_override("font_color", Color.html(C_TEXT))
		row.add_child(a)
		var val := maxi(1, GameData.value_of(sym))
		var sell := Button.new()
		sell.text = "Sell ₡%s" % GameData.fmt(amt * val)
		sell.focus_mode = Control.FOCUS_NONE
		sell.add_theme_font_size_override("font_size", 11)
		sell.pressed.connect(func() -> void: GameState.sell_all(sym))
		row.add_child(sell)
		v.add_child(row)
	if not any:
		_empty(v, "Storage empty — go gather something.")

	_section(v, "SYSTEM", CYAN)
	var save_btn := Button.new()
	save_btn.text = "Save Now"
	save_btn.custom_minimum_size = Vector2(0, 40)
	save_btn.focus_mode = Control.FOCUS_NONE
	save_btn.pressed.connect(func() -> void: GameState.save_game())
	v.add_child(save_btn)
	var reset_btn := Button.new()
	reset_btn.text = "Reset Game"
	reset_btn.custom_minimum_size = Vector2(0, 40)
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.add_theme_color_override("font_color", Color.html(C_WARN))
	reset_btn.pressed.connect(func() -> void:
		if _reset_armed:
			GameState.hard_reset()
			_show("gather")
		else:
			_reset_armed = true
			reset_btn.text = "⚠ Tap again to wipe save")
	v.add_child(reset_btn)

# ============================================================ SHARED CARD PIECES
func _action_controls(v: VBoxContainer, type: String, id: String, active: bool, accent: String, start_label := "Start", stop_label := "Stop") -> void:
	var b := _card_button(stop_label if active else start_label, accent, true)
	b.pressed.connect(func() -> void: GameState.start_task(type, id))
	v.add_child(b)
	var t := Label.new()
	t.text = "%.1fs / %.1fs" % [GameState.progress if active else 0.0, GameState.effective_duration(type, id)]
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 10)
	t.add_theme_color_override("font_color", Color.html(C_MUTED))
	v.add_child(t)
	if active:
		_active_timer = t
	_progress(v, active, accent)

func _locked(v: VBoxContainer, def: Dictionary, skill: String) -> void:
	_clbl(v, "LOCKED", 13, C_WARN)
	var r := Label.new()
	r.text = _req_text(def, skill)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_theme_font_size_override("font_size", 10)
	r.add_theme_color_override("font_color", Color.html(C_MUTED))
	v.add_child(r)

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
	l.add_theme_font_size_override("font_size", 12)
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
	sc.custom_minimum_size = Vector2(0, 36)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	sc.add_child(hb)
	for it in items:
		var b := Button.new()
		b.text = it["label"]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 30)
		b.add_theme_font_size_override("font_size", 12)
		var on: bool = it["id"] == current_id
		b.add_theme_color_override("font_color", Color.html(accent if on else C_DIM))
		b.add_theme_color_override("font_color_hover", Color.html(accent))
		b.add_theme_color_override("font_color_pressed", Color.html(accent))
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, _bordered("1c2740" if on else "141d2e", accent if on else "2a3550", 1, 6))
		var sel_id: String = it["id"]
		b.pressed.connect(func() -> void: on_select.call(sel_id))
		hb.add_child(b)
	v.add_child(sc)

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
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.add_theme_font_size_override("font_size", 13)
	nm.add_theme_color_override("font_color", Color.html(C_TEXT if lit else C_MUTED))
	hb.add_child(nm)
	if badge != "":
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
		_clbl(box, ln["text"], 12, ln["color"])
	v.add_child(panel)

func _clbl(parent: Node, text: String, size: int, color: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.html(color))
	parent.add_child(l)

func _line(text: String, color: String) -> Dictionary:
	return {"text": text, "color": color}

func _card_button(text: String, accent: String, enabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 32)
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	for state in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, _bordered("12192a", accent if enabled else "2a3550", 1, 5))
	b.add_theme_color_override("font_color", Color.html(accent if enabled else C_MUTED))
	b.add_theme_color_override("font_color_disabled", Color.html(C_MUTED))
	b.add_theme_color_override("font_color_hover", Color.html(accent))
	b.add_theme_color_override("font_color_pressed", Color.html(C_TEXT))
	return b

func _progress(v: VBoxContainer, active: bool, accent: String) -> void:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0, 13)
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
	box.add_theme_constant_override("separation", 2)
	var t := Label.new()
	t.text = "%s — Lv %d" % [title, lvl]
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", Color.html(accent))
	box.add_child(t)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 7)
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = pct
	_style_bar(bar, accent)
	box.add_child(bar)
	v.add_child(box)

func _section(v: VBoxContainer, text: String, accent: String) -> void:
	if text == "":
		return
	var l := Label.new()
	l.text = "[ %s ]" % text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color.html(accent))
	v.add_child(l)

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
	var cr := Label.new()
	cr.text = "₡ %s" % GameData.fmt(GameState.credits)
	cr.add_theme_color_override("font_color", Color.html(GOLD))
	cr.add_theme_font_size_override("font_size", 13)
	res_bar.add_child(cr)
	for sym in GameData.RESOURCES:
		var amt := GameState.amount(sym)
		if amt <= 0:
			continue
		var l := Label.new()
		l.text = "%s %s" % [GameData.res_name(sym), GameData.fmt(amt)]
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
	b.add_theme_font_size_override("font_size", 12)
	var bgc := "16273f" if active else "00000000"
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.html(bgc)
		sb.set_corner_radius_all(8)
		b.add_theme_stylebox_override(state, sb)

func _style_bar(b: ProgressBar, accent: String) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color.html("0c1626")
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color.html(accent)
	fg.set_corner_radius_all(3)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
