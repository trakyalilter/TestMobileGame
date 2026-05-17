class_name SmeltProgressBar
extends Control

## Diegetic processing/smelting bar. The filled portion is the charge coming
## up to pour temperature -- a heat gradient from cold-dark through orange to a
## white-hot meniscus at the leading edge. A drawn crucible (assets/crucible.svg)
## rides that edge pouring molten metal; embers rise off the melt while the
## recipe runs. Drop-in for a ProgressBar -- exposes `value` (0..100) so
## `prog_bar.value = pct` keeps working. No inline % (the card's time label
## already shows progress). The crucible only renders while active, so idle
## cards stay a clean empty channel.

@export var value: float = 0.0: set = set_value
@export var active: bool = false: set = set_active
@export var accent: Color = Color(0.2, 0.8, 1.0): set = set_accent

# Molten ramp -- fixed (the heat reads as heat regardless of page accent).
const COLD := Color(0.30, 0.11, 0.04)
const MID := Color(1.0, 0.62, 0.20)
const HOT := Color(1.0, 0.95, 0.80)
# Pour-stream contact sits at x=32/200, y=98/120 of the sprite.
const TIP_U := 0.16
const TIP_V := 0.817

var _phase: float = 0.0
var _tex: Texture2D
var _bg_style: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = max(custom_minimum_size.y, 16.0)
	_tex = load("res://assets/crucible.svg") as Texture2D
	_rebuild_styles()

func set_value(v: float) -> void:
	v = clampf(v, 0.0, 100.0)
	if is_equal_approx(v, value):
		return
	value = v
	queue_redraw()

func set_active(a: bool) -> void:
	if a == active:
		return
	active = a
	queue_redraw()

func set_accent(c: Color) -> void:
	accent = c
	_rebuild_styles()
	queue_redraw()

func _rebuild_styles() -> void:
	_bg_style = StyleBoxFlat.new()
	_bg_style.bg_color = Color(0.04, 0.05, 0.06, 0.97)
	_bg_style.set_border_width_all(1)
	var edge: Color = accent.darkened(0.5)
	edge.a = 0.6
	_bg_style.border_color = edge
	_bg_style.set_corner_radius_all(3)

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 6.0 or h <= 6.0:
		return

	_phase = Time.get_ticks_msec() / 1000.0
	var pct: float = clampf(value / 100.0, 0.0, 1.0)
	var smelting: bool = active and pct < 1.0
	var mid: float = h * 0.5

	# --- Cold channel ---------------------------------------------------
	draw_style_box(_bg_style, Rect2(Vector2.ZERO, size))

	# --- Heated charge (gradient fill) ----------------------------------
	var edge_x: float = clampf(pct * w, 0.0, w)
	if edge_x > 2.0:
		# Cold base, then a brightening tail ramping to white at the front.
		draw_rect(Rect2(0, 0, edge_x, h), COLD)
		var tail: float = minf(edge_x, maxf(edge_x * 0.55, 14.0))
		var slices: int = 7
		for i in range(slices):
			var t0: float = float(i) / float(slices)
			var t1: float = float(i + 1) / float(slices)
			var sx: float = edge_x - tail + tail * t0
			var col := COLD.lerp(MID, t0) if t0 < 0.7 else MID.lerp(HOT, (t0 - 0.7) / 0.3)
			draw_rect(Rect2(sx, 0, tail * (t1 - t0) + 1.0, h), col)
		# White-hot pour line + 3D mould shading.
		draw_rect(Rect2(maxf(edge_x - 2.0, 0.0), 1.0, 2.5, h - 2.0),
			Color(1.0, 0.97, 0.85, 0.95))
		draw_rect(Rect2(0, 1, edge_x, maxf(h * 0.20, 2.0)), Color(1, 1, 1, 0.12))
		draw_rect(Rect2(0, h - maxf(h * 0.26, 3.0), edge_x, maxf(h * 0.26, 3.0)),
			Color(0, 0, 0, 0.26))

	# Crucible only renders while running. Idle cards show a quiet "READY"
	# channel (faint accent hatch) instead of a black void.
	if not active:
		var hatch := Color(accent.r, accent.g, accent.b, 0.09)
		var hx: float = -h
		while hx < w:
			# Clip each diagonal to the bar rect so the idle bar never
			# bleeds wider than the rest of the card column.
			var t0: float = clampf((0.0 - hx) / h, 0.0, 1.0)
			var t1: float = clampf((w - hx) / h, 0.0, 1.0)
			if t1 > t0:
				draw_line(
					Vector2(hx + t0 * h, (h - 2.0) + t0 * (4.0 - h)),
					Vector2(hx + t1 * h, (h - 2.0) + t1 * (4.0 - h)),
					hatch, 2.0)
			hx += 7.0
		var rf := ThemeDB.fallback_font
		if rf:
			var rt := "READY"
			var rs := rf.get_string_size(rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
			var rp := Vector2((w - rs.x) * 0.5, mid + rs.y * 0.30)
			draw_string(rf, rp + Vector2(1, 1), rt, HORIZONTAL_ALIGNMENT_LEFT,
				-1, 8, Color(0, 0, 0, 0.6))
			draw_string(rf, rp, rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
				Color(accent.r, accent.g, accent.b, 0.55))
		return

	var jx: float = sin(_phase * 33.0) * 0.6 if smelting else 0.0
	var jy: float = cos(_phase * 27.0) * 0.5 if smelting else 0.0
	var anchor := Vector2(clampf(edge_x + jx, 1.0, w), mid + jy)

	# Pour heat-bloom at the contact point.
	if smelting:
		var pulse: float = 0.55 + 0.45 * sin(_phase * 18.0)
		var bloom := Color(1.0, 0.78, 0.40, 0.20 * pulse)
		draw_circle(anchor, h * 0.95, bloom)

	# --- The crucible (drawn asset) -------------------------------------
	if _tex:
		var dh: float = h * 1.5
		var dw: float = dh * (float(_tex.get_width()) / float(_tex.get_height()))
		var mod := Color(1, 1, 1)
		if smelting:
			var b: float = 1.0 + 0.05 * sin(_phase * 21.0)
			mod = Color(b, b, b * 0.99)
		# Tilt the vessel into a pour, pivoting about the spout-contact point
		# so the stream stays locked to the melt front. The tip-angle deepens
		# with progress -- nearly upright at charge start, fully tipped over
		# as the pour finishes -- plus a slow wobble while running.
		var tilt: float = deg_to_rad(lerp(-7.0, -34.0, pct))
		if smelting:
			tilt += deg_to_rad(3.0) * sin(_phase * 3.4)
		draw_set_transform(anchor, tilt, Vector2.ONE)
		draw_texture_rect(_tex, Rect2(-dw * TIP_U, -dh * TIP_V, dw, dh),
			false, mod)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		# Fallback so the bar is never empty if the asset failed to import.
		draw_circle(anchor, h * 0.32, MID)

	# Bright pool right at the pour.
	if smelting:
		var fw: float = 0.55 + 0.45 * sin(_phase * 30.0)
		draw_circle(anchor, h * 0.18 * fw, Color(1.0, 0.85, 0.5, 0.55))
		draw_circle(anchor, h * 0.10, Color(1.0, 0.98, 0.88, 0.95))

	# --- Rising embers --------------------------------------------------
	# Sparks lift off the melt and cool as they climb. Deterministic
	# per-ember seed + global phase -> a steady drift, zero nodes.
	if smelting:
		for i in range(5):
			var s1: float = fposmod(sin(float(i) * 12.9898) * 43758.5, 1.0)
			var s2: float = fposmod(sin(float(i) * 78.233) * 12345.6, 1.0)
			var life: float = fposmod(_phase * 1.3 + s1, 1.0)
			var ex: float = anchor.x + (s2 - 0.5) * h * 1.6 + sin(life * 7.0 + s1 * 6.28) * 2.0
			var ey: float = anchor.y - life * h * 2.4
			if ey <= -2.0 or ex <= 1.0 or ex >= w:
				continue
			var a: float = clampf(1.0 - life, 0.0, 1.0) * 0.85
			var col := MID.lerp(HOT, life)
			col.a = a
			draw_circle(Vector2(ex, ey), (1.6 - life) + s2 * 0.6, col)
