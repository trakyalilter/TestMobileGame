extends Control
## Phase 2 spatial Armory grid — PAGINATED Path-of-Exile-style footprints.
##
## Modules occupy 2x2, Matrix Cores / ammo / consumables 1x1. Each PAGE is a
## fixed cols x PAGE_ROWS cell grid; when items overflow the current page the
## packer spills onto the next, creating pages on demand ("pages that
## increment"). Saved positions are (page, x, y) and persist; unpinned items
## auto-pack first-fit.

## Left-click over an empty cell of the CURRENT page. (gx,gy are cell coords on
## the current page; designer_page combines with current_page to pin an item.)
signal cell_clicked(gx: int, gy: int)
## Page set changed (count and/or current). designer_page updates its nav row.
signal pages_changed(page_count: int, current_page: int)

const GAP := 4.0          # gap between cells (px)

var cols := 4
var page_rows := 6        # cells tall per page (page capacity = cols * page_rows)

var current_page := 0
var _page_count := 1
var _items: Array = []     # [{node, w, h, pin:Vector3i(page,x,y)}]
var _placed: Array = []    # [{node, page, gx, gy, w, h}]


func _ready() -> void:
	if not resized.is_connected(_relayout):
		resized.connect(_relayout)


func begin() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_items.clear()
	_placed.clear()


# pin = Vector3i(page, gx, gy); page<0 (or any coord<0) means "auto-pack".
func add_item(node: Control, w: int, h: int, pin: Vector3i = Vector3i(-1, -1, -1)) -> void:
	add_child(node)
	_items.append({"node": node, "w": maxi(1, w), "h": maxi(1, h), "pin": pin})


func get_page_count() -> int:
	return _page_count


func set_page(i: int) -> void:
	var np := clampi(i, 0, _page_count - 1)
	if np == current_page:
		return
	current_page = np
	_relayout()
	queue_redraw()
	pages_changed.emit(_page_count, current_page)


# Pack every queued tile: pinned positions first (kept if in-bounds and free),
# then auto-pack the rest first-fit across pages, creating pages as needed.
func commit() -> void:
	_placed.clear()
	var occ := {}          # page(int) -> Array[page_rows] of Array[cols] bool
	var deferred: Array = []
	for it in _items:
		var w: int = it["w"]
		var h: int = it["h"]
		var pin: Vector3i = it.get("pin", Vector3i(-1, -1, -1))
		if pin.x >= 0 and pin.y >= 0 and pin.z >= 0 and _fits(occ, pin.x, pin.y, pin.z, w, h):
			_mark(occ, pin.x, pin.y, pin.z, w, h)
			_placed.append({"node": it["node"], "page": pin.x, "gx": pin.y, "gy": pin.z, "w": w, "h": h})
		else:
			deferred.append(it)
	for it in deferred:
		var w: int = it["w"]
		var h: int = it["h"]
		var spot := _first_fit(occ, w, h)
		_mark(occ, spot.x, spot.y, spot.z, w, h)
		_placed.append({"node": it["node"], "page": spot.x, "gx": spot.y, "gy": spot.z, "w": w, "h": h})

	_page_count = 1
	for p in _placed:
		_page_count = maxi(_page_count, int(p["page"]) + 1)
	current_page = clampi(current_page, 0, _page_count - 1)
	_relayout()
	pages_changed.emit(_page_count, current_page)


# Cell pixel size derived from live width so the grid fills edge-to-edge.
func _cell_size() -> float:
	var avail := size.x
	if avail <= 1.0:
		avail = custom_minimum_size.x
	return maxf(8.0, (avail - float(cols - 1) * GAP) / float(cols))


func _relayout() -> void:
	var cell := _cell_size()
	for p in _placed:
		var node: Control = p["node"]
		if not is_instance_valid(node):
			continue
		if int(p["page"]) != current_page:
			node.visible = false
			continue
		node.visible = true
		var w: int = p["w"]
		var h: int = p["h"]
		var sw := float(w) * cell + float(w - 1) * GAP
		var sh := float(h) * cell + float(h - 1) * GAP
		node.position = Vector2(p["gx"] * (cell + GAP), p["gy"] * (cell + GAP))
		node.custom_minimum_size = Vector2(sw, sh)
		node.size = Vector2(sw, sh)
	# Fixed page height (pages replace scrolling). Width stays 0 so we fill.
	var want_h := page_rows * (cell + GAP) - GAP
	if absf(want_h - custom_minimum_size.y) > 0.5:
		custom_minimum_size = Vector2(0, want_h)
	queue_redraw()


func _page_grid(occ: Dictionary, page: int) -> Array:
	if not occ.has(page):
		var g: Array = []
		for _r in range(page_rows):
			var row: Array = []
			for _c in range(cols):
				row.append(false)
			g.append(row)
		occ[page] = g
	return occ[page]


func _fits(occ: Dictionary, page: int, x: int, y: int, w: int, h: int) -> bool:
	if page < 0 or x < 0 or y < 0 or x + w > cols or y + h > page_rows:
		return false
	var g := _page_grid(occ, page)
	for dy in range(h):
		for dx in range(w):
			if g[y + dy][x + dx]:
				return false
	return true


func _mark(occ: Dictionary, page: int, x: int, y: int, w: int, h: int) -> void:
	var g := _page_grid(occ, page)
	for dy in range(h):
		for dx in range(w):
			g[y + dy][x + dx] = true


func _first_fit(occ: Dictionary, w: int, h: int) -> Vector3i:
	var page := 0
	while page < 1000:
		for y in range(page_rows - h + 1):
			for x in range(cols - w + 1):
				if _fits(occ, page, x, y, w, h):
					return Vector3i(page, x, y)
		page += 1
	return Vector3i(0, 0, 0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var step := _cell_size() + GAP
		if step <= 0.0:
			return
		var gx := clampi(int(event.position.x / step), 0, cols - 1)
		var gy := clampi(int(event.position.y / step), 0, page_rows - 1)
		cell_clicked.emit(gx, gy)


func _draw() -> void:
	var cell := _cell_size()
	var fill := Color(0.05, 0.065, 0.10, 0.55)
	var border := Color(0.20, 0.30, 0.42, 0.30)
	for gy in range(page_rows):
		for gx in range(cols):
			var r := Rect2(gx * (cell + GAP), gy * (cell + GAP), cell, cell)
			draw_rect(r, fill, true)
			draw_rect(r, border, false, 1.0)
