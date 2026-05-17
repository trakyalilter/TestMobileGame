class_name DrillProgressBar
extends Control

## Diegetic mining progress bar. A drawn steel auger (assets/drill_bit.svg)
## rides the fill edge, boring left -> right; the filled portion is the freshly
## excavated, heat-glowing tunnel. While the action runs the bit vibrates,
## throws an arcing rock-debris stream and the cut face glows. Drop-in for a
## ProgressBar -- exposes `value` (0..100) so `prog_bar.value = pct` keeps
## working. No inline % readout: the card's time label already shows progress.

@export var value: float = 0.0: set = set_value
@export var active: bool = false: set = set_active
@export var accent: Color = Color(1.0, 0.6, 0.2): set = set_accent

const ROCK := Color(0.42, 0.34, 0.28)
# Tip sits at x=250/256 of the sprite, centred vertically (y=60/120).
const TIP_U := 0.9766

var _phase: float = 0.0
var _tex: Texture2D
var _bg_style: StyleBoxFlat
var _fill_style: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = max(custom_minimum_size.y, 16.0)
	_tex = load("res://assets/drill_bit.svg") as Texture2D
	_rebuild_styles()

func set_value(v: float) -> void:
	v = clampf(v, 0.0, 100.0)
	if is_equal_approx(v, value):
		return
	value = v
	# update_state() pushes value every frame while a job runs, so this is
	# also the animation pump -- no _process needed (and no stale-process
	# freeze when the action loops past 100% back to 0).
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
	_bg_style.bg_color = Color(0.05, 0.04, 0.035, 0.97)
	_bg_style.set_border_width_all(1)
	var edge: Color = accent.darkened(0.55)
	edge.a = 0.55
	_bg_style.border_color = edge
	_bg_style.set_corner_radius_all(3)

	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = accent.lerp(Color(0.30, 0.14, 0.05), 0.30)
	_fill_style.set_corner_radius_all(2)

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 6.0 or h <= 6.0:
		return

	_phase = Time.get_ticks_msec() / 1000.0
	var pct: float = clampf(value / 100.0, 0.0, 1.0)
	var drilling: bool = active and pct < 1.0
	var mid: float = h * 0.5

	# --- Channel (unmined rock) -----------------------------------------
	draw_style_box(_bg_style, Rect2(Vector2.ZERO, size))
	var seam := Color(0, 0, 0, 0.22)
	var sx: float = 7.0
	while sx < w - 2.0:
		draw_line(Vector2(sx, 3.0), Vector2(sx - 2.0, h - 3.0), seam, 1.0)
		sx += 8.0

	# --- Excavated tunnel (3D bored hole) -------------------------------
	var bit_x: float = clampf(pct * w, 0.0, w)
	if bit_x > 2.0:
		draw_style_box(_fill_style, Rect2(Vector2.ZERO, Vector2(bit_x, h)))
		draw_rect(Rect2(0, 1, bit_x, maxf(h * 0.22, 2.0)), Color(1, 1, 1, 0.12))
		draw_rect(Rect2(0, h - maxf(h * 0.28, 3.0), bit_x, maxf(h * 0.28, 3.0)),
			Color(0, 0, 0, 0.28))

	# The drill is the "actively mining" signal. Idle cards show a quiet
	# "READY" channel (faint accent hatch) instead of a black void.
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

	# Jitter the whole bit a hair while cutting.
	var jx: float = sin(_phase * 41.0) * 0.8 if drilling else 0.0
	var jy: float = cos(_phase * 53.0) * 0.9 if drilling else 0.0
	var tip := Vector2(clampf(bit_x + jx, 1.0, w), mid + jy)

	# Friction heat behind the cut face.
	if drilling:
		var pulse: float = 0.55 + 0.45 * sin(_phase * 22.0)
		var glow := accent.lerp(Color(1, 0.95, 0.7), 0.5)
		glow.a = 0.16 * pulse
		draw_circle(tip, h * 0.9, glow)
		var face := Color(1.0, 0.93, 0.72, 0.7 * pulse)
		draw_rect(Rect2(maxf(tip.x - 2.0, 0.0), 2.0, 3.0, h - 4.0), face)

	# --- The drill (drawn asset) ----------------------------------------
	if _tex:
		var dh: float = h * 1.05
		var dw: float = dh * (float(_tex.get_width()) / float(_tex.get_height()))
		var rect := Rect2(tip.x - dw * TIP_U, tip.y - dh * 0.5, dw, dh)
		var mod := Color(1, 1, 1)
		if drilling:
			var b: float = 1.0 + 0.06 * sin(_phase * 26.0)
			mod = Color(b, b, b * 0.98)
		draw_texture_rect(_tex, rect, false, mod)
	else:
		# Fallback so the bar is never empty if the asset failed to import.
		var r: float = h * 0.42
		draw_colored_polygon(PackedVector2Array([
			Vector2(tip.x - h, tip.y - r), tip, Vector2(tip.x - h, tip.y + r)
		]), Color(0.55, 0.6, 0.68))

	# White-hot spark at the contact point.
	if drilling:
		var tw: float = 0.55 + 0.45 * sin(_phase * 33.0)
		draw_circle(tip, h * 0.20 * tw, Color(1.0, 0.92, 0.7, 0.55))
		draw_circle(tip, h * 0.11, Color(1.0, 0.98, 0.88, 0.95))

	# --- Rock debris ----------------------------------------------------
	# Chunky shards launched up the tunnel on a gravity arc. Deterministic
	# per-shard seeds + the global phase -> a steady stream, zero nodes.
	if drilling:
		for i in range(4):
			var s1: float = fposmod(sin(float(i) * 12.9898) * 43758.5, 1.0)
			var s2: float = fposmod(sin(float(i) * 78.233) * 12345.6, 1.0)
			var life: float = fposmod(_phase * 1.7 + s1, 1.0)
			var vx: float = -(0.6 + s2) * (h * 1.6 + 6.0)
			var vy: float = -(0.7 + s1) * h * 1.4
			var px: float = tip.x + vx * life
			var py: float = tip.y + vy * life + (h * 3.2) * life * life
			if px <= 1.0 or py >= h - 0.5:
				continue
			var col := ROCK.lerp(accent, 0.25)
			col.a = clampf(1.0 - life, 0.0, 1.0) * 0.85
			var ssz: float = (2.6 - life * 1.4) + s2 * 1.2
			var rot: float = life * 9.0 + s1 * 6.28
			var ca: float = cos(rot)
			var sn: float = sin(rot)
			var c := Vector2(px, py)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(ca, sn) * ssz,
				c + Vector2(-sn, ca) * ssz * 0.7,
				c + Vector2(-ca, -sn) * ssz,
			]), col)

		# Crunch burst: shattered rock spalling radially off the cutting
		# face -- fast, short-lived chips expanding out then fading. Reads
		# as the bit chewing/cracking rock rather than a tidy stream.
		for k in range(7):
			var k1: float = fposmod(sin(float(k) * 91.17) * 7654.32, 1.0)
			var clife: float = fposmod(_phase * 3.1 + k1, 1.0)
			var ang: float = (float(k) / 7.0) * TAU + k1 * 1.3
			var dist: float = clife * h * (0.9 + k1 * 0.7)
			var cp := tip + Vector2(cos(ang), sin(ang) * 0.7) * dist
			if cp.x <= 1.0 or cp.x >= w or cp.y <= 0.5 or cp.y >= h - 0.5:
				continue
			var cc := ROCK.lerp(Color(0.7, 0.62, 0.5), k1)
			cc.a = clampf(1.0 - clife, 0.0, 1.0) * 0.8
			var csz: float = (1.8 - clife) + k1 * 1.0
			draw_rect(Rect2(cp.x - csz * 0.5, cp.y - csz * 0.5, csz, csz), cc)
