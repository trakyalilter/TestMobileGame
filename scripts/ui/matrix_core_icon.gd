extends Control
## Procedural "Matrix Core" icon.
##
## Replaces the old flat rotated-square gem (which read as a plain rectangle)
## with a charming cut-crystal energy core: an outer energy glow, a faceted
## crystal body shaded by a single up-left light, a glowing white-hot nucleus,
## a bright rim and a specular spark. Colour is supplied per gem/element and it
## scales to whatever rect it is given, so the same node works in the big
## armory tile and the tiny equipped socket.
##
## Hardware-cursor-friendly: pure _draw(), no per-frame work — it only repaints
## on resize or when set_core() changes the colour.

var core_color: Color = Color(0.45, 0.80, 1.0)
var hollow: bool = false   # empty socket → faint recessed outline only


func set_core(color: Color, is_hollow: bool = false) -> void:
	core_color = color
	hollow = is_hollow
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Repaint after the container settles our size (first _draw can run at 0,0).
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)


func _draw() -> void:
	var s := size
	if s.x <= 1.0 or s.y <= 1.0:
		return
	var c := s * 0.5
	var r := minf(s.x, s.y) * 0.5    # half-extent to the cell edge
	var gr := r * 0.66               # crystal body radius (leaves room for glow)
	var rx := gr * 0.82              # slightly narrower than tall → crystal feel
	var ry := gr

	# Point-top hexagon: [0]=top, 1=upper-right, 2=lower-right, 3=bottom,
	# 4=lower-left, 5=upper-left.
	var v := PackedVector2Array()
	for i in range(6):
		var a := deg_to_rad(-90.0 + i * 60.0)
		v.append(c + Vector2(cos(a) * rx, sin(a) * ry))

	# Empty socket: just a faint recessed silhouette + dim centre marker.
	if hollow:
		var dim := Color(core_color.r, core_color.g, core_color.b, 0.34)
		_outline(v, dim, maxf(1.0, gr * 0.10))
		draw_circle(c, gr * 0.16, Color(core_color.r, core_color.g, core_color.b, 0.20))
		return

	# 1) Outer energy glow — soft concentric discs, kept inside the cell.
	for g in range(3):
		var grad := r * (0.96 - g * 0.20)
		var ga := 0.05 + g * 0.05
		draw_circle(c, grad, Color(core_color.r, core_color.g, core_color.b, ga))

	# 2) Dark crystal body.
	var base := core_color.darkened(0.5)
	draw_colored_polygon(v, base)

	# Inner "table" facet ring.
	var table := PackedVector2Array()
	for i in range(6):
		table.append(c + (v[i] - c) * 0.42)

	# 3) Crown facets — each shaded by a single up-left light so the cut reads 3D.
	var light := Vector2(-0.5, -0.86)
	var bright := core_color.lightened(0.32)
	for i in range(6):
		var j := (i + 1) % 6
		var facet := PackedVector2Array([v[i], v[j], table[j], table[i]])
		var n := ((v[i] + v[j]) * 0.5 - c).normalized()
		var lit := 0.5 + 0.5 * clampf(n.dot(light), -1.0, 1.0)
		draw_colored_polygon(facet, base.lerp(bright, lit))

	# 4) Lit table + white-hot nucleus halo.
	draw_colored_polygon(table, core_color.lightened(0.40))
	var halo := core_color.lightened(0.7)
	halo.a = 0.45
	draw_circle(c, gr * 0.30, halo)
	draw_circle(c, gr * 0.15, Color(1, 1, 1, 0.92))

	# 5) Crisp rim highlight.
	_outline(v, core_color.lightened(0.55), maxf(1.0, gr * 0.10))

	# 6) Specular spark on the upper-left facet.
	var sp := ((v[5] + v[0]) * 0.5).lerp(c, 0.22)
	var sw := maxf(1.0, gr * 0.09)
	draw_line(sp + Vector2(-gr * 0.18, -gr * 0.18), sp + Vector2(gr * 0.22, gr * 0.22), Color(1, 1, 1, 0.9), sw)


func _outline(pts: PackedVector2Array, col: Color, w: float) -> void:
	var closed := PackedVector2Array(pts)
	closed.append(pts[0])
	draw_polyline(closed, col, w, true)
