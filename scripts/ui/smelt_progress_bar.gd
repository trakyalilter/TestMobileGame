class_name SmeltProgressBar
extends Control

## Minimal-premium processing progress bar (v111.8 redesign).
##
## Shares the chassis of DrillProgressBar (same three layers, same flash,
## same idle breath) but swaps the leading-edge motif from a drill tip to
## a pulsing heat ember — the "the charge is getting hot" cue that's
## immediately legible without needing to know the crucible metaphor.
##
## Why one shared design across both skills: progress bars are the most
## viewed UI surface in the game. Visual consistency lets the player parse
## state at a glance regardless of which skill is active; the leading-edge
## motif + accent colour carry the skill identity.
##
## API unchanged: exposes `value` (0..100), `active`, `accent`.

@export var value: float = 0.0: set = set_value
@export var active: bool = false: set = set_active
@export var accent: Color = Color(0.2, 0.8, 1.0): set = set_accent

const _MIN_H: float = 14.0
const _FLASH_S: float = 0.12               # 120ms completion flash
const _IDLE_BREATH_PERIOD: float = 3.0      # idle accent breath cycle
const _EMBER_PULSE_PERIOD: float = 0.55     # ember "live" pulse while smelting

var _last_value: float = 0.0
var _flash_t: float = 0.0
var _phase_t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = max(custom_minimum_size.y, _MIN_H)
	set_process(true)


func set_value(v: float) -> void:
	v = clampf(v, 0.0, 100.0)
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
	# v111.8.2: redraw only when there's something animating — flash decay
	# or the idle accent breath. Active fill is value-driven so set_value()
	# triggers the redraw, no need to pump frames here.
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
	var track_col: Color = Color(0.04, 0.05, 0.06, 0.95)
	if not active:
		var breath: float = (sin(_phase_t * TAU / _IDLE_BREATH_PERIOD) + 1.0) * 0.5
		var idle_tint: Color = Color(accent.r, accent.g, accent.b, 0.05 + breath * 0.05)
		track_col = track_col.blend(idle_tint)
	draw_rect(rect_full, track_col)

	# 1px dim-accent border.
	var border: Color = accent.darkened(0.6)
	border.a = 0.45
	draw_rect(rect_full, border, false, 1.0)

	# --- 2. Fill (active only) ---
	# v111.8.2: leading-edge ember removed per UX call — the heat halo + core
	# was reading as noise rather than informative. Fill + top stripe is
	# enough; the cycle completion flash supplies the satisfying tick.
	if active and pct > 0.0:
		var fill_w: float = pct * w
		draw_rect(Rect2(0, 0, fill_w, h), accent)

		# Premium top stripe.
		var top_stripe: Color = accent.lerp(Color.WHITE, 0.45)
		top_stripe.a = 0.85
		draw_rect(Rect2(0, 0, fill_w, 1), top_stripe)

	# --- 4. Completion flash ---
	if _flash_t > 0.0:
		var t: float = _flash_t / _FLASH_S
		var flash_col: Color = Color.WHITE.lerp(accent, 1.0 - t)
		flash_col.a = t * 0.85
		draw_rect(rect_full, flash_col)
