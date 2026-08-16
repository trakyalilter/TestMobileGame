extends Control
# HUNT LOG — per-enemy kill ranks (v177, owner feature).
#
# Zone tabs (unlocked zones only, appearing as zones unlock — same disclosure
# rule the Bounty board uses) over a grid of enemy cards. Each card shows a
# 5-star rank earned by lifetime kills, and every star is +10% damage against
# THAT enemy.
#
#   25 / 100 / 250 / 500 / 1000 kills  ->  1..5 stars  ->  +10% each
#
# Code-built like fleet_page/warp_page: the sidebar page container instantiates
# the script directly, so there is no .tscn to keep in sync.
#
# Structure is rebuilt on zone change / page enter; the per-card numbers refresh
# on a light poll so a kill landing while the page is open ticks the bar without
# rebuilding the grid (a rebuild under the cursor kills hover state).

const STAR_ON := Color(1.0, 0.82, 0.30)     # Lira gold — earned
const STAR_OFF := Color(0.28, 0.32, 0.40)   # unearned, still visible as a pip
const ACCENT := Color(1.0, 0.392, 0.451)    # CATEGORY_COLORS.combat — this is a combat log

var _cm
var _zone_id: String = ""
var _tab_row: HBoxContainer
var _grid: GridContainer
var _cards: Array = []       # [{eid, stars: Array[Panel], kills_lbl, bonus_lbl, bar}]
var _tabs: Dictionary = {}   # {zone_id: Button}
var _poll: float = 0.0
var _known_zones: Array = []


func _ready() -> void:
	_cm = GameState.combat_manager
	_build_ui()
	_rebuild_tabs()


func on_page_enter() -> void:
	_rebuild_tabs()


func _process(delta: float) -> void:
	if not visible:
		return
	_poll += delta
	if _poll < 0.5:
		return
	_poll = 0.0
	# A zone unlocked while the page was open? Re-tab (cheap: id list compare).
	if _unlocked_zone_ids() != _known_zones:
		_rebuild_tabs()
	else:
		_refresh_cards()


# ── Zones ──────────────────────────────────────────────────────────────────
# Combat zones only. get_available_zones() also returns HAZARD entries, which
# are gauntlet runs with a synthesised enemy pool rather than a sector roster —
# they have no place in a per-enemy hunting record.
func _unlocked_zone_ids() -> Array:
	var out: Array = []
	if _cm == null:
		return out
	for z in _cm.get_available_zones():
		if bool(z.get("is_hazard", false)):
			continue
		out.append(str(z["id"]))
	return out


func _zone_name(zid: String) -> String:
	return str((_cm.zones.get(zid, {}) as Dictionary).get("name", zid))


# ── Layout ─────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + s, 24)
	for s2 in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s2, 20)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var title := Label.new()
	title.text = tr("HUNT LOG")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", ACCENT)
	col.add_child(title)

	# v177 (owner): NO explainer paragraph here. The house rule is that advice and
	# tutorial text live in opt-in surfaces (hover cards, modals); an auto surface
	# carries short facts only — and the cards below already state the rank, the
	# kills, the distance to the next star and the exact bonus. A sentence
	# re-describing the ladder was just noise above them.
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 6)
	col.add_child(_tab_row)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)


func _rebuild_tabs() -> void:
	if _cm == null or not is_instance_valid(_tab_row):
		return
	_known_zones = _unlocked_zone_ids()
	for c in _tab_row.get_children():
		c.queue_free()
	_tabs.clear()
	if _known_zones.is_empty():
		_zone_id = ""
		_rebuild_cards()
		return
	# Keep the player's tab across a rebuild; fall back to the first zone.
	if not _zone_id in _known_zones:
		_zone_id = str(_known_zones[0])
	for zid in _known_zones:
		var b := Button.new()
		b.text = _zone_name(str(zid))
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		var this_zid := str(zid)
		b.pressed.connect(func():
			_zone_id = this_zid
			_rebuild_cards()
			_style_tabs())
		_tab_row.add_child(b)
		_tabs[this_zid] = b
	_style_tabs()
	_rebuild_cards()


func _style_tabs() -> void:
	for zid in _tabs:
		var b: Button = _tabs[zid]
		if not is_instance_valid(b):
			continue
		var on: bool = (str(zid) == _zone_id)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.10, 0.13, 0.18, 0.95) if on else Color(0.06, 0.07, 0.10, 0.9)
		sb.set_corner_radius_all(3)
		sb.set_border_width_all(1)
		sb.border_color = ACCENT if on else Color(0.22, 0.25, 0.32)
		sb.border_width_bottom = 3 if on else 1
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_color_override("font_color", Color.WHITE if on else Color(0.62, 0.66, 0.76))


# ── Cards ──────────────────────────────────────────────────────────────────
func _rebuild_cards() -> void:
	if not is_instance_valid(_grid):
		return
	_cards.clear()
	for c in _grid.get_children():
		c.queue_free()
	if _zone_id == "":
		return
	for eid in (_cm.zones.get(_zone_id, {}) as Dictionary).get("enemies", []):
		var e: Dictionary = _cm.enemy_db.get(str(eid), {})
		if e.is_empty():
			continue
		_grid.add_child(_make_card(str(eid), e))
	_refresh_cards()


func _make_card(eid: String, e: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.085, 0.115, 0.94)
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.20, 0.23, 0.30)
	sb.border_width_left = 3
	var is_boss: bool = bool(e.get("is_boss", false))
	sb.border_color = ACCENT if is_boss else Color(0.20, 0.23, 0.30)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	# Stars ride the TOP of the card, as specified.
	var star_row := HBoxContainer.new()
	star_row.add_theme_constant_override("separation", 4)
	v.add_child(star_row)
	var stars: Array = []
	for i in range(_cm.HUNT_STAR_THRESHOLDS.size()):
		var pip := _make_star()
		star_row.add_child(pip)
		stars.append(pip)

	var name_lbl := Label.new()
	name_lbl.text = tr(str(e.get("name", eid)))
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", ACCENT if is_boss else Color.WHITE)
	v.add_child(name_lbl)

	var kills_lbl := Label.new()
	kills_lbl.add_theme_font_size_override("font_size", 11)
	kills_lbl.add_theme_color_override("font_color", Color(0.62, 0.66, 0.76))
	v.add_child(kills_lbl)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 6)
	bar.show_percentage = false
	bar.max_value = 1.0
	v.add_child(bar)

	var bonus_lbl := Label.new()
	bonus_lbl.add_theme_font_size_override("font_size", 12)
	v.add_child(bonus_lbl)

	_cards.append({"eid": eid, "stars": stars, "kills": kills_lbl,
		"bonus": bonus_lbl, "bar": bar})
	return panel


# A real five-pointed STAR, drawn as vector art. It has to be drawn rather than
# typed: the owner's no-pictograph rule bars the literal star glyph from any
# player-facing string, but that rule is about TEXT — drawn geometry is how this
# codebase already renders its matrix-core hexagons and sector emblems.
# (v177 first cut used a rounded Panel, which read as an orb, not a star.)
class _StarPip extends Control:
	var earned: bool = false
	var col_on: Color = Color(1.0, 0.82, 0.30)
	var col_off: Color = Color(0.28, 0.32, 0.40)

	func _points() -> PackedVector2Array:
		var c := size * 0.5
		var outer := minf(size.x, size.y) * 0.5
		var inner := outer * 0.42     # classic 5-point silhouette
		var pts := PackedVector2Array()
		for i in range(10):
			# Start at -90 deg so the star sits POINT-UP.
			var ang := -PI * 0.5 + PI * float(i) / 5.0
			var rad := outer if (i % 2 == 0) else inner
			pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
		return pts

	func _draw() -> void:
		if size.x <= 2.0 or size.y <= 2.0:
			return
		var pts := _points()
		var outline := pts.duplicate()
		outline.append(pts[0])
		var col: Color = col_on if earned else col_off
		# EMPTY AND FILLED MUST BE THE SAME SIZE. Both states draw the identical
		# outline stroke, at the same width, from the same _points(); `earned`
		# only adds a fill INSIDE it. The first cut instead gave the filled star
		# an extra dark seam stroke and the empty star a different width, so the
		# filled silhouette sat a pixel proud of the hollow one and the row read
		# as mismatched sizes.
		if earned:
			draw_colored_polygon(pts, col_on)
		draw_polyline(outline, col, 1.3, true)


func _make_star() -> Control:
	var p := _StarPip.new()
	p.custom_minimum_size = Vector2(17, 17)
	p.col_on = STAR_ON
	p.col_off = STAR_OFF
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


# Fraction -> percent string, one decimal only when it earns one: 0.025 -> "2.5",
# 0.25 -> "25". Keeps the whole-number ranks clean while the 2.5% rank stays honest.
func _pct_str(frac: float) -> String:
	var v: float = frac * 100.0
	if absf(v - round(v)) < 0.01:
		return str(int(round(v)))
	return String.num(v, 1)


func _refresh_cards() -> void:
	if _cm == null:
		return
	for c in _cards:
		var card: Dictionary = c
		var eid := str(card["eid"])
		var prog: Dictionary = _cm.get_hunt_progress(eid)
		var st := int(prog["stars"])
		var pips: Array = card["stars"]
		for i in range(pips.size()):
			var pip = pips[i]
			if not is_instance_valid(pip):
				continue
			var want: bool = (i < st)
			if pip.earned != want:
				pip.earned = want
				pip.queue_redraw()
		var kills := int(prog["kills"])
		var lbl: Label = card["kills"]
		var bar: ProgressBar = card["bar"]
		if int(prog["next"]) > 0:
			# The ladder is NOT uniform (2.5/5/10/15/25), so "what does the next
			# star actually pay" is a real question the card should answer — it is
			# a short fact, not an explainer.
			lbl.text = tr("%s kills   ·   %s to next star (+%s%%)") % [
				FormatUtils.format_number(kills), FormatUtils.format_number(int(prog["remaining"])),
				_pct_str(_cm.get_hunt_star_bonus(st + 1))]
			# Progress WITHIN the current band, so the bar restarts at each star
			# instead of creeping asymptotically toward 1000.
			var lo: float = 0.0 if st == 0 else float(_cm.HUNT_STAR_THRESHOLDS[st - 1])
			var hi: float = float(prog["next"])
			bar.value = clampf((float(kills) - lo) / maxf(1.0, hi - lo), 0.0, 1.0)
			bar.visible = true
		else:
			lbl.text = tr("%s kills   ·   fully hunted") % FormatUtils.format_number(kills)
			bar.visible = false
		var bonus: Label = card["bonus"]
		# Read the rank's bonus from the table, NOT back out of the multiplier:
		# (1.025 - 1.0) * 100 lands on 2.4999… in float, which rounded to "+2%"
		# and quietly understated the first star.
		var frac: float = _cm.get_hunt_star_bonus(st)
		if frac > 0.0:
			bonus.text = tr("+%s%% damage vs this enemy") % _pct_str(frac)
			bonus.add_theme_color_override("font_color", STAR_ON)
		else:
			bonus.text = tr("No bonus yet — %d kills for the first star") % int(_cm.HUNT_STAR_THRESHOLDS[0])
			bonus.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
