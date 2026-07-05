extends Control
# v134h: procedural star-chart emblem for the combat page's Star Chart button.
# A north-star glyph over a faint constellation (dots + link lines). Asset-free
# so it needs no texture import; tint via `col`.

@export var col: Color = Color(0.18, 0.91, 0.77)   # ops teal (matches the Nav card)

func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = min(size.x, size.y) * 0.30
	if r <= 0.0:
		return
	# Constellation: a few dots joined by faint links, sitting behind the star.
	var dots := [Vector2(-0.85, -0.5), Vector2(0.9, -0.72), Vector2(0.7, 0.78), Vector2(-0.62, 0.86)]
	var prev: Vector2 = c + dots[dots.size() - 1] * r
	for d in dots:
		var p: Vector2 = c + d * r
		draw_line(prev, p, Color(col.r, col.g, col.b, 0.20), 1.0)
		prev = p
	for d in dots:
		draw_circle(c + d * r, maxf(1.5, r * 0.10), Color(col.r, col.g, col.b, 0.55))
	# 4-point north star.
	var pts := PackedVector2Array()
	for i in range(8):
		var ang: float = PI * float(i) / 4.0 - PI * 0.5
		var rad: float = r if i % 2 == 0 else r * 0.32
		pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
	draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.95))
