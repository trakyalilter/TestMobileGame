extends Control

# First-visit page tour. Dims the screen, spotlights the anchored widget, and
# shows an explanatory card with Skip / Next controls. Driven by main.gd:
#   start(page_name, steps, anchor_provider)
# Emits `finished(page_name)` when the player skips or completes the tour so
# main.gd can persist the "seen" flag.
#
# Implemented as a plain Control parented under ModalLayer (same proven pattern
# as the other modals in this project).

signal finished(page_name: String)

const DIM := Color(0, 0, 0, 0.62)
const PAD := 8.0          # spotlight padding around the target
const CARD_W := 380.0
const GAP := 18.0         # gap between target and card

var _page_name: String = ""
var _steps: Array = []
var _idx: int = 0
var _provider: Node = null
var _active: bool = false
var _built: bool = false

var _dim := []            # 4 ColorRects forming the cutout frame
var _highlight: Panel
var _card: PanelContainer
var _title_lbl: Label
var _body_lbl: Label
var _step_lbl: Label
var _next_btn: Button
var _skip_btn: Button
var _hl_tween: Tween

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func is_active() -> bool:
	return _active

func _build_ui() -> void:
	if _built: return
	_built = true

	for i in range(4):
		var d := ColorRect.new()
		d.color = DIM
		d.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(d)
		_dim.append(d)

	_highlight = Panel.new()
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0, 0, 0, 0)
	hs.set_border_width_all(2)
	hs.border_color = Color(1.0, 0.82, 0.25)
	hs.set_corner_radius_all(4)
	_highlight.add_theme_stylebox_override("panel", hs)
	add_child(_highlight)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(CARD_W, 0)
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.07, 0.08, 0.12, 0.98)
	cs.set_border_width_all(1)
	cs.border_width_top = 3
	cs.border_color = Color(0.42, 0.84, 1.0, 0.85)
	cs.set_corner_radius_all(6)
	cs.shadow_color = Color(0, 0, 0, 0.6)
	cs.shadow_size = 18
	cs.content_margin_left = 22
	cs.content_margin_right = 22
	cs.content_margin_top = 18
	cs.content_margin_bottom = 16
	_card.add_theme_stylebox_override("panel", cs)
	add_child(_card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_card.add_child(vb)

	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 18)
	_title_lbl.add_theme_color_override("font_color", Color(0.42, 0.84, 1.0))
	vb.add_child(_title_lbl)

	_body_lbl = Label.new()
	_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_lbl.custom_minimum_size = Vector2(CARD_W - 44, 0)
	_body_lbl.add_theme_font_size_override("font_size", 13)
	_body_lbl.add_theme_color_override("font_color", Color(0.86, 0.88, 0.92))
	vb.add_child(_body_lbl)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	vb.add_child(footer)

	_step_lbl = Label.new()
	_step_lbl.add_theme_font_size_override("font_size", 11)
	_step_lbl.add_theme_color_override("font_color", Color(0.55, 0.58, 0.66))
	_step_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(_step_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	_skip_btn = Button.new()
	_skip_btn.text = "Skip"
	_skip_btn.add_theme_font_size_override("font_size", 12)
	_skip_btn.pressed.connect(_on_skip)
	footer.add_child(_skip_btn)

	_next_btn = Button.new()
	_next_btn.add_theme_font_size_override("font_size", 12)
	_next_btn.pressed.connect(_on_next)
	footer.add_child(_next_btn)

func start(page_name: String, steps: Array, anchor_provider: Node) -> void:
	if steps.is_empty():
		finished.emit(page_name)
		return
	_build_ui()
	_page_name = page_name
	_steps = steps
	_provider = anchor_provider
	_idx = 0
	_active = true
	visible = true
	# Pages build their widgets via call_deferred; wait so anchors can be measured.
	await get_tree().process_frame
	await get_tree().process_frame
	if _active:
		_render()

func _resolve_anchor(key: String) -> Control:
	if _provider and _provider.has_method("get_coach_anchor"):
		var c = _provider.get_coach_anchor(key)
		if c is Control and is_instance_valid(c):
			return c
	return null

func _render() -> void:
	if _steps.is_empty() or _idx < 0 or _idx >= _steps.size():
		_finish()
		return
	var step: Dictionary = _steps[_idx]
	_title_lbl.text = str(step.get("title", ""))
	_body_lbl.text = str(step.get("body", ""))
	_step_lbl.text = "%d / %d" % [_idx + 1, _steps.size()]
	_next_btn.text = "Got it" if _idx == _steps.size() - 1 else "Next  >"

	var anchor_key := str(step.get("anchor", ""))
	var vp := get_viewport_rect().size

	var hole := _measure(anchor_key, vp)
	# Heavy pages build their widgets a few frames after becoming visible.
	# If the spotlight target isn't measurable yet, wait briefly and retry once.
	if hole.size.x <= 1.0 and anchor_key != "":
		await get_tree().process_frame
		await get_tree().process_frame
		# Bail if the tour ended or the player advanced during the wait.
		if not _active or _idx >= _steps.size() or str(_steps[_idx].get("anchor", "")) != anchor_key:
			return
		hole = _measure(anchor_key, vp)

	if hole.size.x > 1.0 and hole.size.y > 1.0:
		_apply_cutout(hole, vp)
		_highlight.visible = true
		_highlight.position = hole.position
		_highlight.size = hole.size
		_pulse_highlight()
	else:
		_apply_cutout(Rect2(0, 0, 0, 0), vp)  # full dim, no hole
		_highlight.visible = false
		if _hl_tween: _hl_tween.kill()

	# Position the card once its size is known.
	await get_tree().process_frame
	if not _active: return
	_place_card(vp)

func _measure(anchor_key: String, vp: Vector2) -> Rect2:
	var target := _resolve_anchor(anchor_key)
	if target and target.is_visible_in_tree() and target.size.x > 1.0 and target.size.y > 1.0:
		var gr := target.get_global_rect()
		var h := Rect2(gr.position - Vector2(PAD, PAD), gr.size + Vector2(PAD, PAD) * 2.0)
		return h.intersection(Rect2(Vector2.ZERO, vp))
	return Rect2(0, 0, 0, 0)

func _apply_cutout(hole: Rect2, vp: Vector2) -> void:
	if hole.size.x <= 0.0 or hole.size.y <= 0.0:
		_dim[0].position = Vector2.ZERO
		_dim[0].size = vp
		for i in range(1, 4):
			_dim[i].size = Vector2.ZERO
		return
	# Top
	_dim[0].position = Vector2.ZERO
	_dim[0].size = Vector2(vp.x, hole.position.y)
	# Bottom
	_dim[1].position = Vector2(0, hole.end.y)
	_dim[1].size = Vector2(vp.x, max(0.0, vp.y - hole.end.y))
	# Left
	_dim[2].position = Vector2(0, hole.position.y)
	_dim[2].size = Vector2(hole.position.x, hole.size.y)
	# Right
	_dim[3].position = Vector2(hole.end.x, hole.position.y)
	_dim[3].size = Vector2(max(0.0, vp.x - hole.end.x), hole.size.y)

func _place_card(vp: Vector2) -> void:
	var cs := _card.size
	var pos: Vector2

	if _highlight.visible:
		var hr := Rect2(_highlight.position, _highlight.size)
		var cx: float = clamp(hr.position.x + hr.size.x / 2.0 - cs.x / 2.0, 16.0, max(16.0, vp.x - cs.x - 16.0))
		if hr.end.y + GAP + cs.y <= vp.y - 16.0:
			pos = Vector2(cx, hr.end.y + GAP)              # below target
		elif hr.position.y - GAP - cs.y >= 16.0:
			pos = Vector2(cx, hr.position.y - GAP - cs.y)  # above target
		else:
			pos = Vector2(                                 # beside target
				clamp(hr.end.x + GAP, 16.0, max(16.0, vp.x - cs.x - 16.0)),
				clamp(vp.y / 2.0 - cs.y / 2.0, 16.0, max(16.0, vp.y - cs.y - 16.0)))
	else:
		pos = (vp - cs) / 2.0  # no anchor: dead center

	_card.position = pos

func _pulse_highlight() -> void:
	if _hl_tween: _hl_tween.kill()
	_highlight.modulate = Color.WHITE
	_hl_tween = create_tween().set_loops()
	_hl_tween.tween_property(_highlight, "modulate", Color(1.4, 1.2, 0.5), 0.6).set_trans(Tween.TRANS_SINE)
	_hl_tween.tween_property(_highlight, "modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE)

func _on_next() -> void:
	if _idx >= _steps.size() - 1:
		_finish()
	else:
		_idx += 1
		_render()

func _on_skip() -> void:
	_finish()

func _finish() -> void:
	if not _active: return
	_active = false
	visible = false
	if _hl_tween:
		_hl_tween.kill()
		_hl_tween = null
	finished.emit(_page_name)
