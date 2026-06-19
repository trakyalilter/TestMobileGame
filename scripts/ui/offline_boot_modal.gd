extends Control
# v112: "Tactical Telemetry" offline welcome-back screen (design dir. B).
# Diegetic station console: radial elapsed-time gauge, status-LED activity
# channels, monospace telemetry stat blocks, scanline + corner-bracket FX, and
# a SCROLLABLE cargo ledger (built to absorb the future parallel-infra material
# explosion without overflowing the screen). Driven entirely by the structured
# GameState.offline_report_data — see any manager's calculate_offline().

@onready var bg: ColorRect = $ColorRect

# ── palette ───────────────────────────────────────────────────────────────
const CYAN  := Color(0.20, 0.84, 1.00)
const GREEN := Color(0.40, 0.90, 0.60)
const GOLD  := Color(1.00, 0.82, 0.30)
const RED   := Color(1.00, 0.54, 0.48)
const TEXT  := Color(0.90, 0.92, 0.97)
const DIM   := Color(0.60, 0.62, 0.74)
const FAINT := Color(0.42, 0.45, 0.56)
const IDLE  := Color(0.22, 0.27, 0.38)

const CAP_SECONDS := 86400.0

# ── consumed report data ────────────────────────────────────────────────────
var _data: Array = []
var _away_sec: float = 0.0
var _capped: bool = false

# ── built nodes we animate / fill ───────────────────────────────────────────
var _boot_log: Label
var _content: VBoxContainer
var _gauge: RingGauge
var _gauge_target: float = 0.0
var _continue_btn: Button
var _mono_font: SystemFont


func _ready():
	visible = false
	if bg: bg.color = Color(0, 0, 0, 1)


func debug_preview():
	# Debug-only (Options → "Offline Welcome"): representative 15h report with a
	# long material list so the scrollable cargo ledger is visibly exercised.
	_data = [
		{
			"category": "gathering", "title": "Off-World Operations", "action": "Excavate Soil",
			"time_sec": 54660, "actions": 13675, "xp": 109400,
			"gains": {"Dirt": 218800, "Water": 9200, "Fe": 1400},
			"drains": {}, "notes": [], "status": "active",
		},
		{
			"category": "processing", "title": "Engineering", "action": "Smelt Iron",
			"time_sec": 7200, "actions": 1440, "xp": 24000,
			"gains": {"Fe": 4200, "Si": 600, "credits": 18400},
			"drains": {}, "notes": [], "status": "active",
		},
		{
			"category": "infrastructure", "title": "Infrastructure Grid", "action": "",
			"time_sec": 54660, "actions": 0, "xp": 0,
			"gains": {"Si": 9500, "Al": 6100, "Cu": 4200, "Mn": 3050, "Ti": 1875, "Ni": 980, "credits": 12400},
			"drains": {"Water": 3200, "Dirt": 1800},
			"notes": ["Throttled to 82% — upkeep ran short."], "status": "active",
		},
		{
			"category": "combat", "title": "Combat Sweep", "action": "",
			"time_sec": 54660, "actions": 0, "xp": 0,
			"gains": {}, "drains": {}, "status": "standby",
			"notes": ["Paused — enable Offline Combat in Options to keep fighting while away."],
		},
	]
	_away_sec = 54660.0
	_capped = false
	_build_ui()
	_play_boot_sequence()


func check_and_show():
	if GameState.offline_report_data == null or GameState.offline_report_data.is_empty():
		return
	_data = GameState.offline_report_data.duplicate(true)
	_away_sec = GameState.offline_away_sec
	_capped = GameState.offline_capped
	# Consume so a later scene reload doesn't replay it.
	GameState.offline_report_data = []
	GameState.offline_away_sec = 0.0
	GameState.offline_capped = false
	_build_ui()
	_play_boot_sequence()


# ════════════════════════════════════════════════════════════════════════════
#  UI BUILD
# ════════════════════════════════════════════════════════════════════════════
func _build_ui():
	# Clear any prior build (defensive — the modal shows once per session).
	for c in get_children():
		if c != bg:
			c.queue_free()

	_mono_font = SystemFont.new()
	_mono_font.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New", "monospace"])

	# Scanlines + corner brackets behind the content.
	var fx := TelemetryBG.new()
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 46)
	add_child(margin)

	var center := CenterContainer.new()
	margin.add_child(center)

	var root_vb := VBoxContainer.new()
	root_vb.custom_minimum_size = Vector2(680, 0)
	root_vb.add_theme_constant_override("separation", 16)
	center.add_child(root_vb)

	# Boot log (streams first, stays dim at the top).
	_boot_log = _mk_mono(" ", 11, FAINT)
	_boot_log.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vb.add_child(_boot_log)

	# Everything below is revealed (faded in) after the boot sequence.
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 15)
	_content.modulate.a = 0.0
	root_vb.add_child(_content)

	var title := _mk_label("OFFLINE TELEMETRY   //   STATION LOG", 12, CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(title)

	# ── mid row: elapsed gauge + activity channels ──
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 28)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(mid)

	_gauge = RingGauge.new()
	_gauge.custom_minimum_size = Vector2(134, 134)
	_gauge.ring_color = CYAN
	_gauge_target = clampf(_away_sec / CAP_SECONDS, 0.0, 1.0)
	var gc := CenterContainer.new()
	gc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge.add_child(gc)
	var gvb := VBoxContainer.new()
	gvb.add_theme_constant_override("separation", 1)
	gc.add_child(gvb)
	var away_lbl := _mk_mono(_fmt_time(_away_sec), 19, Color.WHITE)
	away_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gvb.add_child(away_lbl)
	var elapsed := _mk_label("ELAPSED", 8, CYAN)
	elapsed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gvb.add_child(elapsed)
	mid.add_child(_gauge)

	var channels := VBoxContainer.new()
	channels.custom_minimum_size = Vector2(320, 0)
	channels.add_theme_constant_override("separation", 5)
	for b in _data:
		channels.add_child(_mk_channel(b))
	mid.add_child(channels)

	# ── aggregate stat blocks ──
	var agg := _aggregate()
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_child(_mk_stat("XP ACCRUED", FormatUtils.format_number(agg["xp"])))
	stats.add_child(_mk_stat("UNITS HAULED", FormatUtils.format_number(agg["units"])))
	stats.add_child(_mk_stat("ACTIONS", FormatUtils.format_number(agg["actions"])))
	_content.add_child(stats)

	# ── cargo ledger (header + SCROLLABLE rows) ──
	_content.add_child(_mk_label("CARGO LEDGER", 9, CYAN))

	var rows := _sorted_ledger(agg["ledger"])
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 132)   # capped height → scrolls past ~7 rows
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var ledger_vb := VBoxContainer.new()
	ledger_vb.custom_minimum_size = Vector2(542, 0)
	ledger_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ledger_vb.add_theme_constant_override("separation", 4)
	if rows.is_empty():
		ledger_vb.add_child(_mk_mono("  no cargo recovered", 11, FAINT))
	else:
		for r in rows:
			ledger_vb.add_child(_mk_ledger_row(r))
	scroll.add_child(ledger_vb)
	_content.add_child(scroll)

	# ── notes (cap / throttle / paused / biosphere) ──
	for n in _collect_notes():
		var hot: bool = ("throttle" in n.to_lower()) or ("paused" in n.to_lower()) or ("capped" in n.to_lower())
		var nl := _mk_label("› " + n, 10, GOLD if hot else DIM)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(nl)

	# ── footer + contextual continue button ──
	var footer := _mk_label("ALL SYSTEMS NOMINAL   //   WELCOME BACK, COMMANDER", 9, FAINT)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(footer)

	var resume := _describe_active_task()
	_continue_btn = Button.new()
	_continue_btn.text = resume["button"]
	_continue_btn.custom_minimum_size = Vector2(230, 44)
	_continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UITheme.apply_premium_button_style(_continue_btn, "engineering")  # cyan family
	_continue_btn.pressed.connect(_on_continue_pressed)
	_continue_btn.modulate.a = 0.0   # revealed last
	_content.add_child(_continue_btn)


# ════════════════════════════════════════════════════════════════════════════
#  REVEAL SEQUENCE
# ════════════════════════════════════════════════════════════════════════════
func _play_boot_sequence():
	visible = true
	modulate.a = 1.0
	_boot_log.text = ""
	_content.modulate.a = 0.0
	_gauge.fill = 0.0

	var tw := create_tween()
	tw.tween_callback(_blog.bind("> CORE REACTOR ONLINE"))
	tw.tween_interval(0.45)
	tw.tween_callback(func(): UITheme.trigger_ui_thud(self, 12.0))
	tw.tween_callback(_blog.bind("> AUX POWER  [ OK ]"))
	tw.tween_interval(0.4)
	tw.tween_callback(_blog.bind("> SYNCHRONIZING SECTOR LOGISTICS..."))
	tw.tween_interval(0.55)
	tw.tween_callback(_blog.bind("> DATA INTEGRITY  100%"))
	tw.tween_interval(0.35)
	# Reveal: fade the console in while the gauge sweeps up to its fill.
	tw.tween_property(_content, "modulate:a", 1.0, 0.5)
	tw.parallel().tween_property(_gauge, "fill", _gauge_target, 1.0).from(0.0)
	tw.tween_interval(0.35)
	tw.tween_property(_continue_btn, "modulate:a", 1.0, 0.4)


func _blog(msg: String):
	_boot_log.text += (msg if _boot_log.text == "" else "\n" + msg)
	UITheme.trigger_ui_thud(_boot_log, 1.0)


func _on_continue_pressed():
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.45)
	t.tween_callback(func(): visible = false; modulate.a = 1.0)


# ════════════════════════════════════════════════════════════════════════════
#  AGGREGATION
# ════════════════════════════════════════════════════════════════════════════
func _aggregate() -> Dictionary:
	var total_xp := 0
	var total_actions := 0
	var units := 0.0
	var ledger := {}   # display-key → {amt, drain, res?}
	for b in _data:
		total_xp += int(b.get("xp", 0))
		total_actions += int(b.get("actions", 0))
		for k in b.get("gains", {}):
			var amt := float(b["gains"][k])
			if str(k) != "credits":
				units += amt
			var prev: float = float(ledger.get(k, {}).get("amt", 0.0))
			ledger[k] = {"amt": prev + amt, "drain": false}
		for k in b.get("drains", {}):
			var dkey := "-" + str(k)
			var amt2 := float(b["drains"][k])
			var prev2: float = float(ledger.get(dkey, {}).get("amt", 0.0))
			ledger[dkey] = {"amt": prev2 + amt2, "drain": true, "res": k}
	return {"xp": total_xp, "actions": total_actions, "units": units, "ledger": ledger}


# Returns a sorted Array of {key, amt, drain, ratio}: gains (desc) then drains.
func _sorted_ledger(ledger: Dictionary) -> Array:
	var gains: Array = []
	var drains: Array = []
	for k in ledger:
		var e: Dictionary = ledger[k]
		var item := {
			"key": str(e.get("res", k)),
			"amt": float(e["amt"]),
			"drain": bool(e.get("drain", false)),
		}
		if item["drain"]:
			drains.append(item)
		else:
			gains.append(item)
	gains.sort_custom(func(a, b): return a["amt"] > b["amt"])
	drains.sort_custom(func(a, b): return a["amt"] > b["amt"])
	var maxamt := 1.0
	for g in gains:
		maxamt = maxf(maxamt, g["amt"])
	var out: Array = []
	for g in gains:
		g["ratio"] = clampf(g["amt"] / maxamt, 0.03, 1.0)
		out.append(g)
	for d in drains:
		d["ratio"] = clampf(d["amt"] / maxamt, 0.03, 1.0)
		out.append(d)
	return out


func _collect_notes() -> Array:
	# Per-activity notes (throttle %, combat-paused nag, biosphere buff) are
	# deliberately omitted — the channel LEDs/status already convey "ran / idle",
	# and this screen is the dopamine beat, not a caveats list. Only the offline
	# cap survives: forfeited earnings are material, not noise.
	var out: Array = []
	if _capped:
		out.append("Earnings capped at %dh — you were away longer." % int(CAP_SECONDS / 3600.0))
	return out


# ════════════════════════════════════════════════════════════════════════════
#  WIDGET FACTORIES
# ════════════════════════════════════════════════════════════════════════════
func _mk_label(txt: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	return l


func _mk_mono(txt: String, fsize: int, col: Color) -> Label:
	var l := _mk_label(txt, fsize, col)
	if _mono_font:
		l.add_theme_font_override("font", _mono_font)
	return l


func _mk_channel(b: Dictionary) -> Control:
	var active: bool = str(b.get("status", "active")) == "active"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var dot := _Dot.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.dot_color = GREEN if active else IDLE
	dot.glow = active
	row.add_child(dot)

	var title := _mk_mono(str(b.get("title", "")).to_upper(), 11, TEXT if active else FAINT)
	title.custom_minimum_size = Vector2(156, 0)
	row.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var val := _mk_mono(_channel_value(b), 11, CYAN if active else FAINT)
	row.add_child(val)

	var st := _mk_mono("ACTIVE" if active else "STANDBY", 9, GREEN if active else FAINT)
	st.custom_minimum_size = Vector2(60, 0)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(st)
	return row


func _channel_value(b: Dictionary) -> String:
	var cat := str(b.get("category", ""))
	if cat == "infrastructure":
		return "AUTO"
	if cat == "combat":
		var k := int(b.get("actions", 0))
		return ("%d kills" % k) if k > 0 else "—"
	return _fmt_time(float(b.get("time_sec", 0)))


func _mk_stat(cap: String, val: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(170, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.05)
	sb.set_border_width_all(1)
	sb.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.30)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 13
	sb.content_margin_right = 13
	sb.content_margin_top = 8
	sb.content_margin_bottom = 9
	p.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	p.add_child(vb)
	vb.add_child(_mk_label(cap, 8, CYAN))
	vb.add_child(_mk_mono(val, 20, Color.WHITE))
	return p


func _mk_ledger_row(r: Dictionary) -> Control:
	var col: Color = RED if r["drain"] else _key_color(r["key"])
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 9)

	var tick := ColorRect.new()
	tick.color = col
	tick.custom_minimum_size = Vector2(3, 14)
	hb.add_child(tick)

	var sym := _mk_mono(_disp_name(r["key"]).to_upper(), 11, RED if r["drain"] else TEXT)
	sym.custom_minimum_size = Vector2(118, 0)
	hb.add_child(sym)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = float(r["ratio"]) * 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 9)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bbg := StyleBoxFlat.new()
	bbg.bg_color = Color(1, 1, 1, 0.06)
	bbg.set_corner_radius_all(2)
	var bfg := StyleBoxFlat.new()
	bfg.bg_color = col
	bfg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bbg)
	bar.add_theme_stylebox_override("fill", bfg)
	hb.add_child(bar)

	var amt := _mk_mono(("−" if r["drain"] else "+") + FormatUtils.format_number(r["amt"]), 11, col)
	amt.custom_minimum_size = Vector2(84, 0)
	amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(amt)
	return hb


# ════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ════════════════════════════════════════════════════════════════════════════
func _disp_name(key: String) -> String:
	if key == "credits":
		return "Liras"
	# ElementDB is an autoload; call it directly like the rest of the codebase.
	var n = ElementDB.get_display_name(key)
	if n != null and str(n) != "":
		return str(n)
	return key.replace("_", " ")


func _key_color(key: String) -> Color:
	if key == "credits":
		return GOLD
	return UITheme.element_accent(key)


func _fmt_time(sec: float) -> String:
	# FormatUtils is a static class_name utility — call directly (NOT via
	# has_method: that's an instance method and parse-errors on a class ref).
	return FormatUtils.format_playtime(sec)


# Short description of the active task → contextual Continue-button label so the
# player knows exactly where they'll land. (Reads live manager state.)
func _describe_active_task() -> Dictionary:
	var default := {"label": "", "button": "BRIDGE CONTROL"}
	if not GameState:
		return default

	if GameState.combat_manager and GameState.combat_manager.in_combat:
		return {"label": "", "button": "RETURN TO BATTLE"}
	if GameState.gathering_manager and GameState.gathering_manager.is_active:
		return {"label": "", "button": "CONTINUE GATHERING"}
	if GameState.processing_manager and GameState.processing_manager.is_active:
		return {"label": "", "button": "CONTINUE PROCESSING"}
	if GameState.research_manager and GameState.research_manager.is_active:
		return {"label": "", "button": "CONTINUE RESEARCH"}
	return {"label": "", "button": "BRIDGE CONTROL"}


# ════════════════════════════════════════════════════════════════════════════
#  INNER DRAWN WIDGETS
# ════════════════════════════════════════════════════════════════════════════
class RingGauge extends Control:
	var ring_color: Color = Color(0.2, 0.84, 1.0)
	var fill: float = 0.0:
		set(value):
			fill = value
			queue_redraw()

	func _draw():
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 5.0
		var track := Color(ring_color.r, ring_color.g, ring_color.b, 0.14)
		draw_arc(c, r, 0.0, TAU, 72, track, 6.0, true)
		if fill > 0.001:
			var start := -PI / 2.0
			draw_arc(c, r, start, start + TAU * clampf(fill, 0.0, 1.0), 72, ring_color, 6.0, true)


class _Dot extends Control:
	var dot_color: Color = Color.WHITE
	var glow: bool = false

	func _draw():
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		if glow:
			draw_circle(c, r + 2.5, Color(dot_color.r, dot_color.g, dot_color.b, 0.25))
		draw_circle(c, r, dot_color)


class TelemetryBG extends Control:
	var line_color := Color(0.20, 0.84, 1.0, 0.028)
	var bracket := Color(0.20, 0.84, 1.0, 0.5)

	func _ready():
		resized.connect(queue_redraw)

	func _draw():
		var y := 0.0
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), line_color, 1.0)
			y += 4.0
		var L := 22.0
		var m := 16.0
		var w := size.x
		var h := size.y
		# 4 corner brackets
		draw_line(Vector2(m, m), Vector2(m + L, m), bracket, 1.0)
		draw_line(Vector2(m, m), Vector2(m, m + L), bracket, 1.0)
		draw_line(Vector2(w - m, m), Vector2(w - m - L, m), bracket, 1.0)
		draw_line(Vector2(w - m, m), Vector2(w - m, m + L), bracket, 1.0)
		draw_line(Vector2(m, h - m), Vector2(m + L, h - m), bracket, 1.0)
		draw_line(Vector2(m, h - m), Vector2(m, h - m - L), bracket, 1.0)
		draw_line(Vector2(w - m, h - m), Vector2(w - m - L, h - m), bracket, 1.0)
		draw_line(Vector2(w - m, h - m), Vector2(w - m, h - m - L), bracket, 1.0)
