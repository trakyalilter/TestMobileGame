class_name DrillProgressBar
extends Control

## Minimal-premium gathering progress bar (v111.8 redesign).
##
## Three visual layers only — track, fill, leading-edge tip — instead of the
## previous six (track + seam stripes + tinted fill + top highlight + bottom
## shadow + drill sprite + idle hatch). At 16px tall the eye reads the FILL
## EDGE in one glance, no sprite competing for attention.
##
## • Track:    recessed dark rect with a 1px dim-accent border.
## • Fill:     strong skill-color block with a 1px lighter top stripe.
## • Edge:     small triangular drill tip at the leading edge + soft halo.
## • Idle:     quiet dim track with a 3-second accent breath.
## • Complete: 120ms white→accent flash overlay on each cycle reset, which
##             is the dopamine tick idle players come back for.
##
## API unchanged: exposes `value` (0..100), `active`, `accent`.

@export var value: float = 0.0: set = set_value
@export var active: bool = false: set = set_active
@export var accent: Color = Color(0.18, 0.91, 0.769): set = set_accent

const _MIN_H: float = 14.0
const _FLASH_S: float = 0.12              # 120ms completion flash
const _IDLE_BREATH_PERIOD: float = 3.0     # one breath every 3s when idle

var _last_value: float = 0.0
var _flash_t: float = 0.0
var _phase_t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = max(custom_minimum_size.y, _MIN_H)
	set_process(true)


func set_value(v: float) -> void:
	v = clampf(v, 0.0, 100.0)
	# Detect cycle completion: big drop from high % back near zero.
	# Trigger the celebration flash on the snap-back.
	if _last_value > 75.0 and v < 5.0:
		_flash_t = _FLASH_S
	_last_value = v
	if is_equal_approx(v, value):
		return
	value = v
	queue_redraw()


func set_active(a: bool) -> void:
	if a == active:
		return
	active = a
	_phase_t = 0.0
	queue_redraw()


func set_accent(c: Color) -> void:
	accent = c
	queue_redraw()


func _process(delta: float) -> void:
	var need_redraw: bool = false
	if _flash_t > 0.0:
		_flash_t = max(0.0, _flash_t - delta)
		need_redraw = true
	# Both states animate (idle breath / completion fade), so we tick
	# regardless and let _draw decide what to paint.
	_phase_t += delta
	if not active or _flash_t > 0.0:
		need_redraw = true
	if need_redraw:
		queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w < 4.0 or h < 4.0:
		return

	var pct: float = clampf(value / 100.0, 0.0, 1.0)
	var rect_full: Rect2 = Rect2(Vector2.ZERO, size)

	# --- 1. Track ---
	var track_col: Color = Color(0.05, 0.05, 0.07, 0.95)
	if not active:
		# Idle breath: subtle accent tint that gently pulses.
		var breath: float = (sin(_phase_t * TAU / _IDLE_BREATH_PERIOD) + 1.0) * 0.5
		var idle_tint: Color = Color(accent.r, accent.g, accent.b, 0.05 + breath * 0.05)
		track_col = track_col.blend(idle_tint)
	draw_rect(rect_full, track_col)

	# Subtle 1px border (dim accent so the bar reads as a card element).
	var border: Color = accent.darkened(0.6)
	border.a = 0.45
	draw_rect(rect_full, border, false, 1.0)

	# --- 2. Fill (active only) ---
	# v111.8.2: leading-edge drill tip removed per UX call — fill + top stripe
	# carries enough progress signal at this scale, and the tip was reading
	# as visual noise. Completion flash (below) still provides the dopamine.
	if active and pct > 0.0:
		var fill_w: float = pct * w
		draw_rect(Rect2(0, 0, fill_w, h), accent)

		# 1px lighter top stripe for premium "lit edge" feel.
		var top_stripe: Color = accent.lerp(Color.WHITE, 0.45)
		top_stripe.a = 0.85
		draw_rect(Rect2(0, 0, fill_w, 1), top_stripe)

	# --- 4. Completion flash (top layer, fades out) ---
	if _flash_t > 0.0:
		var t: float = _flash_t / _FLASH_S        # 1.0 → 0.0
		# Start white, fade toward accent as t decreases.
		var flash_col: Color = Color.WHITE.lerp(accent, 1.0 - t)
		flash_col.a = t * 0.85
		draw_rect(rect_full, flash_col)
