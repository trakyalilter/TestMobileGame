extends CanvasLayer
## ClickFX — autoload. A subtle one-shot ring "pop" at the cursor when a
## button is pressed. Deliberately restrained: fires only on real button
## presses (not empty-space clicks), never animates the cursor itself, and
## costs nothing on the hardware-cursor path.
##
## Wiring is automatic — every BaseButton (current or created later) gets
## its `button_down` hooked. Disabled buttons don't emit it, so locked
## controls correctly produce no feedback.

const RING_COLOR := Color(0.373, 0.878, 0.784)  # Precursor Bloom aqua (matches UITheme)


func _ready() -> void:
	layer = 95  # above gameplay UI, below the scanline/vignette FX (100)
	get_tree().node_added.connect(_hook)
	_scan(get_tree().root)


func _scan(n: Node) -> void:
	_hook(n)
	for c in n.get_children():
		_scan(c)


func _hook(n: Node) -> void:
	if n is BaseButton and not n.button_down.is_connected(_on_button_down):
		n.button_down.connect(_on_button_down)


func _on_button_down() -> void:
	var ring := _Ring.new()
	ring.position = get_viewport().get_mouse_position()
	ring.tint = RING_COLOR
	add_child(ring)
	ring.play()


# Self-contained, self-freeing ring. One per click; clicks in an idle game
# are infrequent enough that pooling would be premature.
class _Ring extends Node2D:
	const _R0 := 9.0
	const _R1 := 34.0
	const _DUR := 0.22

	var tint: Color = Color.WHITE
	var _t: float = 0.0

	func play() -> void:
		var tw := create_tween()
		tw.tween_method(_step, 0.0, 1.0, _DUR).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_callback(queue_free)

	func _step(v: float) -> void:
		_t = v
		queue_redraw()

	func _draw() -> void:
		var r: float = lerp(_R0, _R1, _t)
		var c := tint
		c.a = (1.0 - _t) * 0.55
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, c, 2.0, true)
