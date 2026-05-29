extends PanelContainer

# Empty Armory grid cell. Reads as the SAME socket plate that sits behind
# every filled module tile (module_card.gd `sock_sb`) so filled and empty
# cells share one piece of hardware — only the seated inner plate differs.
# Without this, the .tscn's StyleBoxFlat was being clobbered by a fainter
# `_ready()` override (alpha 0.2), which gave each cell visually mismatched
# corners/borders and made the grid look "broken-shape".

const _BG: Color   = Color(0.03, 0.045, 0.07, 0.92)   # match module socket bg
const _BD: Color   = Color(0.22, 0.32, 0.44, 0.55)    # softer than filled, but visible
const _DOT: Color  = Color(0.32, 0.42, 0.55, 0.28)    # subtle "empty here" marker

func _ready() -> void:
	# Match module_card.gd line 73: every grid cell wants to expand. Without
	# this, only filled cells (which DO have EXPAND_FILL) claim the extra
	# horizontal space in their column, blowing one column wide and leaving
	# the rest crammed at the empty-slot 100px minimum.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_FILL

	# v111.7: keep cells square — same trick as module_card.gd. When the grid
	# stretches us wider than our min, push min height up to match so the
	# cell renders as a square. Caller (designer_page) sets the initial min
	# size; this runs after layout and bumps height up to actual width.
	if not resized.is_connected(_keep_square):
		resized.connect(_keep_square)

	var frame := StyleBoxFlat.new()
	frame.bg_color = _BG
	frame.set_border_width_all(1)
	frame.border_color = _BD
	frame.border_blend = false
	frame.set_corner_radius_all(5)                    # match filled-cell socket
	frame.shadow_color = Color(0, 0, 0, 0.40)
	frame.shadow_size = 2
	frame.shadow_offset = Vector2(0, 1)
	add_theme_stylebox_override("panel", frame)

	# Tiny centre dot — same trick equipped-slot widgets use to mark a vacant
	# socket. Without it the cell reads as dead background; with it, the
	# player understands "this is a slot, just empty".
	var dot := Panel.new()
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.custom_minimum_size = Vector2(4, 4)
	dot.size = Vector2(4, 4)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = _DOT
	dsb.set_corner_radius_all(2)
	dot.add_theme_stylebox_override("panel", dsb)
	add_child(dot)

# v111.7: hooked from _ready. Mirrors module_card._keep_square — when the
# grid stretches us wider than our current min, bump min height to match
# so the cell renders square. Guard prevents loops (bumping min.y doesn't
# change size.x in a GridContainer).
func _keep_square() -> void:
	if size.x > custom_minimum_size.y:
		custom_minimum_size.y = size.x
