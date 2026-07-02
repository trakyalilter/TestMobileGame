extends Control
# v113: "Tactical Telemetry" offline welcome-back screen (design dir. B).
# Diegetic station console: radial elapsed-time gauge, status-LED activity
# channels, monospace telemetry stat blocks, scanline + corner-bracket FX, and
# a SCROLLABLE cargo ledger (built to absorb the future parallel-infra material
# explosion without overflowing the screen). Driven entirely by the structured
# GameState.offline_report_data — see any manager's calculate_offline().
# v113 refinement (currency-first dopamine pass): the stat row LEADS with Liras
# earned (gold), values count UP on the reveal, the cargo ledger colours amounts
# by semantic (jade gained / coral lost / amber Liras), the boot log is tightened
# and the "systems online" thud now lands on the reward beat, and the Continue
# button is the one solid (jade) fill on screen.

@onready var bg: ColorRect = $ColorRect

# ── palette ───────────────────────────────────────────────────────────────
const CYAN  := Color(0.373, 0.878, 0.784)  # Precursor Bloom aqua accent
const GREEN := Color(0.275, 0.878, 0.627)  # jade positive
const GOLD  := Color(1.0, 0.761, 0.302)    # amber currency / hot
const RED   := Color(1.0, 0.392, 0.451)    # coral negative
const TEXT  := Color(0.894, 0.961, 0.933)
const DIM   := Color(0.498, 0.639, 0.612)
const FAINT := Color(0.36, 0.45, 0.43)
const IDLE  := Color(0.18, 0.29, 0.27)

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
var _stat_rolls: Array = []   # {label, target, prefix} — rolled up on reveal by _tick_stats


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
			"drains": {}, "notes": [], "status": "active",
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
	_stat_rolls.clear()

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

	# ── aggregate stat blocks (currency-first; values count up on reveal) ──
	var agg := _aggregate()
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	# Lead slot: the soft currency the player actually spends. If they banked no
	# Liras (e.g. a pure raw-gathering run), celebrate their single biggest haul
	# instead so the hero stat is never an empty "+0".
	var credits_total: float = float(agg.get("credits", 0.0))
	if credits_total > 0.0:
		stats.add_child(_mk_stat("LIRAS", credits_total, GOLD, "+"))
	else:
		var top_key := ""
		var top_amt := 0.0
		for k in agg["ledger"]:
			var e: Dictionary = agg["ledger"][k]
			if not bool(e.get("drain", false)) and float(e["amt"]) > top_amt:
				top_amt = float(e["amt"])
				top_key = str(e.get("res", k))
		if top_key != "":
			stats.add_child(_mk_stat(_disp_name(top_key).to_upper(), top_amt, _key_color(top_key), "+"))
		else:
			stats.add_child(_mk_stat("LIRAS", 0.0, GOLD, "+"))
	stats.add_child(_mk_stat("XP ACCRUED", float(agg["xp"]), Color.WHITE, "+"))
	stats.add_child(_mk_stat("ACTIONS", float(agg["actions"]), Color.WHITE, ""))
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

	# ── notes (cap / throttle / paused) ──
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
	UITheme.apply_premium_button_style(_continue_btn, "engineering")
	# Make the CTA the ONE saturated fill on the screen — a solid jade "go" block
	# with a dark label, inverted from the light-on-dark console so it unmistakably
	# reads as THE action that ends the reveal.
	var btn_dark := Color(0.039, 0.086, 0.078)
	for st in ["normal", "hover", "pressed", "focus"]:
		var fb := StyleBoxFlat.new()
		fb.bg_color = GREEN
		if st == "hover":
			fb.bg_color = Color(0.40, 0.95, 0.72)
		elif st == "pressed":
			fb.bg_color = Color(0.22, 0.74, 0.52)
		fb.set_corner_radius_all(4)
		fb.content_margin_left = 18
		fb.content_margin_right = 18
		fb.content_margin_top = 10
		fb.content_margin_bottom = 10
		_continue_btn.add_theme_stylebox_override(st, fb)
	for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_continue_btn.add_theme_color_override(fc, btn_dark)
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
	# Boot log: tightened pacing so the reward lands ~0.6s sooner every return —
	# the terminal flavor sets the table, it isn't the meal.
	tw.tween_callback(_blog.bind("> CORE REACTOR ONLINE"))
	tw.tween_interval(0.30)
	tw.tween_callback(_blog.bind("> AUX POWER  [ OK ]"))
	tw.tween_interval(0.28)
	tw.tween_callback(_blog.bind("> SYNCHRONIZING SECTOR LOGISTICS..."))
	tw.tween_interval(0.30)
	tw.tween_callback(_blog.bind("> DATA INTEGRITY  100%"))
	tw.tween_interval(0.24)
	# Reveal beat — the climax: a heavy "systems online" slam lands exactly as the
	# console fades in, the gauge sweeps, and the reward numbers roll up to total.
	tw.tween_callback(func(): UITheme.trigger_ui_thud(self, 14.0))
	tw.tween_property(_content, "modulate:a", 1.0, 0.5)
	tw.parallel().tween_property(_gauge, "fill", _gauge_target, 1.0).from(0.0)
	tw.parallel().tween_method(_tick_stats, 0.0, 1.0, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.30)
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
	var credits := 0.0
	var ledger := {}   # display-key → {amt, drain, res?}
	for b in _data:
		total_xp += int(b.get("xp", 0))
		total_actions += int(b.get("actions", 0))
		for k in b.get("gains", {}):
			var amt := float(b["gains"][k])
			if str(k) != "credits":
				units += amt
			else:
				credits += amt
			var prev: float = float(ledger.get(k, {}).get("amt", 0.0))
			ledger[k] = {"amt": prev + amt, "drain": false}
		for k in b.get("drains", {}):
			var dkey := "-" + str(k)
			var amt2 := float(b["drains"][k])
			var prev2: float = float(ledger.get(dkey, {}).get("amt", 0.0))
			ledger[dkey] = {"amt": prev2 + amt2, "drain": true, "res": k}
	return {"xp": total_xp, "actions": total_actions, "units": units, "credits": credits, "ledger": ledger}


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
	# Per-activity notes (throttle %, combat-paused nag) are
	# deliberately omitted — the channel LEDs/status already convey "ran / idle",
	# and this screen is the dopamine beat, not a caveats list. Only the offline
	# cap survives: forfeited earnings are material, not noise.
	var out: Array = []
	if _capped:
		out.append("Reached the %dh offline cap — log in sooner to bank it all." % int(CAP_SECONDS / 3600.0))
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


func _mk_stat(cap: String, target: float, val_col: Color = Color.WHITE, prefix: String = "") -> PanelContainer:
	# Each stat carries its own accent (gold Liras, aqua XP/actions, element tint
	# for a top-haul fallback). The value starts at 0 and is rolled up to `target`
	# by _tick_stats() during the reveal — see _play_boot_sequence().
	var accent: Color = val_col if val_col != Color.WHITE else CYAN
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.r, accent.g, accent.b, 0.05)
	sb.set_border_width_all(1)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.30)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 13
	sb.content_margin_right = 13
	sb.content_margin_top = 8
	sb.content_margin_bottom = 9
	p.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	p.add_child(vb)
	vb.add_child(_mk_label(cap, 8, accent))
	var val_lbl := _mk_mono(prefix + "0", 20, val_col)
	vb.add_child(val_lbl)
	_stat_rolls.append({"label": val_lbl, "target": target, "prefix": prefix})
	return p


# Odometer roll for the stat values, driven 0→1 during the reveal sweep so the
# numbers the player came back for animate up instead of hard-appearing.
func _tick_stats(t: float) -> void:
	for s in _stat_rolls:
		var lbl: Label = s["label"]
		if is_instance_valid(lbl):
			lbl.text = str(s["prefix"]) + FormatUtils.format_number(float(s["target"]) * t)


func _mk_ledger_row(r: Dictionary) -> Control:
	var col: Color = RED if r["drain"] else _key_color(r["key"])
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 9)

	var tick := ColorRect.new()
	tick.color = col
	tick.custom_minimum_size = Vector2(3, 14)
	hb.add_child(tick)

	# Tinted material glyph in a fixed-width slot. The slot is kept even when a
	# row has no icon (e.g. Liras/credits) so every name column stays aligned.
	hb.add_child(_mk_ledger_icon(r["key"], r["drain"]))

	var sym := _mk_mono(_disp_name(r["key"]).to_upper(), 11, RED if r["drain"] else TEXT)
	sym.custom_minimum_size = Vector2(112, 0)
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

	# Amount reads by SEMANTIC colour (jade gained / coral lost / amber Liras) so a
	# fat haul and a trickle differ at a glance; the tick + bar keep the material tint.
	var amt_col: Color = RED if r["drain"] else (GOLD if r["key"] == "credits" else GREEN)
	var amt := _mk_mono(("−" if r["drain"] else "+") + FormatUtils.format_number(r["amt"]), 11, amt_col)
	amt.custom_minimum_size = Vector2(84, 0)
	amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(amt)
	return hb


# Fixed-width icon slot for a ledger row. Returns a 20px-wide centered TextureRect
# carrying the material's tinted glyph; if the key has no icon (credits, or any
# un-iconned material) the slot stays empty so name columns remain aligned.
func _mk_ledger_icon(key: String, drain: bool) -> Control:
	var slot := CenterContainer.new()
	slot.custom_minimum_size = Vector2(20, 16)
	var tex: Texture2D = null
	if key != "credits":
		tex = ElementDB.get_material_icon(key)
	if tex == null:
		return slot
	var ico := TextureRect.new()
	ico.texture = tex
	ico.custom_minimum_size = Vector2(16, 16)
	ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Drains tint red to read as a loss; gains keep the material's signature tint.
	ico.modulate = RED if drain else ElementDB.get_material_tint(key)
	slot.add_child(ico)
	return slot


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
	var ring_color: Color = Color(0.373, 0.878, 0.784)
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
	var line_color := Color(0.373, 0.878, 0.784, 0.028)
	var bracket := Color(0.373, 0.878, 0.784, 0.5)

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
