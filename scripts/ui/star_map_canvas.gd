extends Control
# ──────────────────────────────────────────────────────────────────────────
# Star-map canvas — pure presentation. Draws the Sector Chart (nebula heat
# bands, curved warp lanes, system nodes, starfield) and handles pointer
# hit-testing. It knows NOTHING about the combat manager: the overlay feeds it
# a flat list of zone "models" (id / name / difficulty / state / flags) and it
# reports clicks/hovers back by id. Keep simulation out of here.
#
# A model is a Dictionary:
#   { id, name, difficulty:int, state:"cleared"|"current"|"available"|"locked",
#     is_boss:bool, is_hazard:bool }
# ──────────────────────────────────────────────────────────────────────────

signal zone_clicked(zone_id)
signal zone_hovered(zone_id)
signal enemy_clicked(enemy_id)   # a hostile cluster / boss picked in sector view

# Two-level view: "galaxy" (sector chart) drills into "sector" (close-up of one
# system, hostiles spread as clickable clusters + boss). A fade-through transition
# with a slight reveal-zoom sells the "push in close" feel.
# Sector enemy model (fed by the overlay, pre-formatted — canvas stays dumb):
#   { eid, name, is_boss:bool, color:Color, hp_txt:String, tag:String }

# Organic system layout, normalised 0..1 within the canvas (hand-placed so the
# route spirals from home space up into the deep void rather than marching in a
# line). Hazards hang off their parent system on a spur.
const LAYOUT := {
	"lunar_orbit":    Vector2(0.088, 0.880),
	"asteroid_belt":  Vector2(0.203, 0.744),
	"mars_debris":    Vector2(0.304, 0.843),
	"cryofield":      Vector2(0.372, 0.611),
	"sector_alpha":   Vector2(0.507, 0.676),
	"sector_beta":    Vector2(0.601, 0.467),
	"sector_gamma":   Vector2(0.723, 0.541),
	"sector_delta":   Vector2(0.777, 0.333),
	"sector_zeta":    Vector2(0.885, 0.411),
	"sector_epsilon": Vector2(0.939, 0.204),
	"the_threshold":  Vector2(0.905, 0.670),
	"the_rift":       Vector2(0.845, 0.880),
	"emp_nexus":      Vector2(0.380, 0.985),
	# v138: the Singularity — apart from the lane network, in the top-left void.
	# It is not a destination on the route; it's a hole OUT of the run.
	"warp_rift":      Vector2(0.140, 0.220),
}
# Which system a hazard spur branches from.
const SPUR_PARENT := {"emp_nexus": "mars_debris"}

# Precursor Bloom palette.
const C_JADE        := Color(0.274, 0.878, 0.627)
const C_AQUA        := Color(0.427, 0.878, 0.784)
const C_AQUA_BRIGHT := Color(0.427, 0.941, 0.847)
const C_TEAL        := Color(0.216, 0.788, 0.690)
const C_AMBER       := Color(1.000, 0.761, 0.302)
const C_CORAL       := Color(1.000, 0.392, 0.451)
const C_DIM         := Color(0.498, 0.639, 0.612)
const C_TEXT        := Color(0.894, 0.961, 0.933)
const C_LOCK        := Color(0.360, 0.480, 0.455)

const MARGIN := 50.0
const HIT_RADIUS := 24.0

var models: Array = []
var selected_id: String = ""
var hovered_id: String = ""

var _stars: Array = []
var _phase: float = 0.0
var _shake_id: String = ""
var _shake_t: float = 0.0
var _font: Font
var _by_diff: Array = []   # main-chain models sorted by difficulty (no hazards)

# sector drill-in state
var view_mode: String = "galaxy"        # "galaxy" | "sector"
var selected_enemy_id: String = ""
var _hovered_enemy_id: String = ""
var _enemies: Array = []                # current sector-view enemy models (+pos)
var _focus_zone: Dictionary = {}        # the zone model we drilled into
var _fade: float = 0.0                  # 0 clear .. 1 fully black (transition scrim)
var _fade_dir: float = 0.0              # +1 covering, -1 revealing, 0 idle
var _pending_mode: String = ""
var _pending_enemies: Array = []
var _pending_zone: Dictionary = {}

# enemy cluster slots (normalised), assigned weakest→strongest; boss sits apart.
const ENEMY_SLOTS := [Vector2(0.24, 0.47), Vector2(0.76, 0.47), Vector2(0.34, 0.74), Vector2(0.66, 0.74)]
const BOSS_SLOT := Vector2(0.50, 0.24)
const ENEMY_HIT := 40.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font()
	_gen_stars()
	set_process(true)

func set_models(m: Array) -> void:
	models = m
	_by_diff = []
	for mod in models:
		# v138: the Singularity sits OFF the warp-lane network (no lane connects it).
		if not mod.get("is_hazard", false) and not mod.get("is_rift", false):
			_by_diff.append(mod)
	_by_diff.sort_custom(func(a, b): return int(a["difficulty"]) < int(b["difficulty"]))
	queue_redraw()

func set_selected(id: String) -> void:
	selected_id = id
	queue_redraw()

func shake(id: String) -> void:
	_shake_id = id
	_shake_t = 0.45
	queue_redraw()

# Drill into a sector: fade out, swap to the close-up view, fade back in. The
# overlay supplies pre-formatted enemy models; we assign cluster slots here
# (boss apart, the rest in weakest→strongest order as given).
func enter_sector(zone_model: Dictionary, enemies: Array) -> void:
	_pending_zone = zone_model
	var arr: Array = []
	var ci := 0
	for e in enemies:
		var em: Dictionary = e.duplicate()
		if e.get("is_boss", false):
			em["pos"] = BOSS_SLOT
		else:
			em["pos"] = ENEMY_SLOTS[ci % ENEMY_SLOTS.size()]
			ci += 1
		arr.append(em)
	_pending_enemies = arr
	_pending_mode = "sector"
	_fade_dir = 1.0

func exit_sector() -> void:
	_pending_mode = "galaxy"
	_fade_dir = 1.0

# Hard reset to the galaxy view (no transition) — used when the chart (re)opens.
func reset_galaxy() -> void:
	view_mode = "galaxy"
	_enemies = []
	_focus_zone = {}
	selected_enemy_id = ""
	_hovered_enemy_id = ""
	_fade = 0.0
	_fade_dir = 0.0
	queue_redraw()

func is_in_sector() -> bool:
	return view_mode == "sector" or _pending_mode == "sector"

func set_selected_enemy(eid: String) -> void:
	selected_enemy_id = eid
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return  # don't burn frames animating while the chart is closed
	_phase += delta
	if _shake_t > 0.0:
		_shake_t = maxf(0.0, _shake_t - delta)
	if _fade_dir != 0.0:
		_fade = clampf(_fade + delta / 0.16 * _fade_dir, 0.0, 1.0)
		if _fade_dir > 0.0 and _fade >= 1.0:
			# fully covered — swap the view, then reveal
			view_mode = _pending_mode
			if view_mode == "sector":
				_enemies = _pending_enemies
				_focus_zone = _pending_zone
			else:
				_enemies = []
				_focus_zone = {}
			selected_enemy_id = ""
			_hovered_enemy_id = ""
			_fade_dir = -1.0
		elif _fade_dir < 0.0 and _fade <= 0.0:
			_fade_dir = 0.0
	queue_redraw()

# ── geometry ──────────────────────────────────────────────────────────────
func _norm_of(m: Dictionary) -> Vector2:
	if LAYOUT.has(m["id"]):
		return LAYOUT[m["id"]]
	# Fallback for any zone without an authored slot: spread by difficulty.
	return Vector2(0.10 + 0.072 * float(m.get("difficulty", 1)), 0.5)

func _node_px(m: Dictionary) -> Vector2:
	var n: Vector2 = _norm_of(m)
	var p := Vector2(MARGIN + n.x * (size.x - 2.0 * MARGIN), MARGIN + n.y * (size.y - 2.0 * MARGIN))
	if m["id"] == _shake_id and _shake_t > 0.0:
		p.x += sin(_shake_t * 70.0) * 6.0 * (_shake_t / 0.45)
	return p

# ── drawing ─────────────────────────────────────────────────────────────-─
func _draw() -> void:
	# view_mode only flips once the scrim fully covers (see _process), so the
	# galaxy→sector swap is never visible; we just draw the current mode + scrim.
	if view_mode == "galaxy":
		_draw_galaxy()
	else:
		_draw_sector()
	if _fade > 0.001:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.019, 0.043, 0.039, _fade))

func _draw_galaxy() -> void:
	if models.is_empty():
		return
	# 1. nebula heat bands (soft blobs, no shader/blur — stacked alpha circles)
	_soft_blob(Vector2(size.x * 0.20, size.y * 0.80), size.x * 0.44, C_TEAL, 0.34)
	_soft_blob(Vector2(size.x * 0.55, size.y * 0.46), size.x * 0.42, C_AMBER, 0.26)
	_soft_blob(Vector2(size.x * 0.85, size.y * 0.40), size.x * 0.42, C_CORAL, 0.30)

	# 2. starfield (deterministic positions, gentle twinkle)
	for s in _stars:
		var sp: Vector2 = Vector2(s["n"].x * size.x, s["n"].y * size.y)
		var a: float = s["a"] * (0.55 + 0.45 * sin(_phase * 1.4 + s["tw"]))
		draw_circle(sp, s["r"], Color(0.81, 0.937, 0.902, a))

	# 3. warp lanes (main chain + hazard spurs)
	for i in range(_by_diff.size() - 1):
		_draw_lane(_by_diff[i], _by_diff[i + 1], i)
	for m in models:
		if m.get("is_hazard", false) and SPUR_PARENT.has(m["id"]):
			var parent := _model_by_id(SPUR_PARENT[m["id"]])
			if not parent.is_empty():
				_draw_spur(parent, m)

	# 4. systems
	for m in models:
		_draw_node(m)

func _soft_blob(c: Vector2, radius: float, col: Color, peak: float) -> void:
	# Stacked translucent discs approximating a radial glow (GL-compat, no
	# shader/blur). Each disc has a hard edge; for a BIG blob, 14 discs leave
	# ~40px gaps that read as concentric rings. Scale the disc count with the
	# radius so the edges stay <~12px apart (smooth), and normalise per-disc
	# alpha by the count so total brightness is unchanged. Small blobs keep n=14
	# and look identical to before.
	var n := clampi(int(radius / 12.0), 14, 60)
	var norm := 14.0 / float(n)
	for i in range(n):
		var f := float(i) / float(n - 1)        # 0 outer .. 1 inner
		var r := radius * (1.0 - 0.92 * f)
		draw_circle(c, r, Color(col.r, col.g, col.b, peak * f * f * 0.16 * norm))

func _bezier(p1: Vector2, p2: Vector2, sign: float) -> PackedVector2Array:
	var mid := (p1 + p2) * 0.5
	var d := p2 - p1
	var perp := Vector2(-d.y, d.x).normalized()
	var ctrl := mid + perp * d.length() * 0.16 * sign
	var pts := PackedVector2Array()
	for i in range(17):
		var t := float(i) / 16.0
		pts.append(p1.lerp(ctrl, t).lerp(ctrl.lerp(p2, t), t))
	return pts

func _draw_lane(a: Dictionary, b: Dictionary, idx: int) -> void:
	var p1 := _node_px(a)
	var p2 := _node_px(b)
	var sign := 1.0 if (idx % 2 == 0) else -1.0
	var pts := _bezier(p1, p2, sign)
	var sa := str(a["state"])
	var sb := str(b["state"])
	var reachable_a := sa == "cleared" or sa == "current" or sa == "available"
	match sb:
		"cleared":
			draw_polyline(pts, Color(C_JADE.r, C_JADE.g, C_JADE.b, 0.16), 7.0, true)  # underglow
			draw_polyline(pts, Color(C_JADE.r, C_JADE.g, C_JADE.b, 0.85), 2.6, true)
		"current":
			draw_polyline(pts, Color(C_AQUA.r, C_AQUA.g, C_AQUA.b, 0.18), 8.0, true)
			draw_polyline(pts, C_AQUA_BRIGHT, 3.0, true)
		"available":
			# the actionable frontier hop — glowing, marching dashes
			draw_polyline(pts, Color(C_TEAL.r, C_TEAL.g, C_TEAL.b, 0.14), 7.0, true)
			_dashed(pts, Color(0.45, 0.95, 0.85, 1.0), 3.0, 10.0, 6.0, _phase * 42.0)
		_:
			if reachable_a:
				# the push-lane from your frontier into the unknown — points the way
				_dashed(pts, Color(C_TEAL.r, C_TEAL.g, C_TEAL.b, 0.5), 2.0, 7.0, 7.0, _phase * 26.0)
			else:
				_dashed(pts, Color(C_LOCK.r, C_LOCK.g, C_LOCK.b, 0.38), 1.4, 3.0, 8.0, 0.0)

func _draw_spur(parent: Dictionary, hz: Dictionary) -> void:
	var pts := _bezier(_node_px(parent), _node_px(hz), 1.0)
	var col := C_AMBER if str(hz["state"]) != "locked" else C_LOCK
	_dashed(pts, Color(col.r, col.g, col.b, 0.55), 1.6, 3.0, 6.0, _phase * 20.0)

func _dashed(pts: PackedVector2Array, color: Color, width: float, dash: float, gap: float, offset: float) -> void:
	var period := dash + gap
	var carry := fposmod(-offset, period)
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.001:
			continue
		var dir := (b - a) / seg
		var t := 0.0
		while t < seg:
			var local := fposmod(carry + t, period)
			var on := local < dash
			var step := (dash - local) if on else (period - local)
			step = minf(step, seg - t)
			if step <= 0.0:
				break
			if on:
				draw_line(a + dir * t, a + dir * (t + step), color, width, true)
			t += step
		carry += seg

func _draw_node(m: Dictionary) -> void:
	var p := _node_px(m)
	# v138: the Singularity gets its own draw path (black hole, not a system node).
	if m.get("is_rift", false):
		_draw_rift_node(m, p)
		return
	var diff := int(m.get("difficulty", 1))
	var heat := _heat(diff)
	var st := str(m["state"])
	var label_col := C_DIM
	var label_y := 26.0   # gap below the node for the name

	match st:
		"cleared":
			_soft_blob(p, 26.0, C_JADE, 0.55)
			draw_circle(p, 9.0, Color(C_JADE.r, C_JADE.g, C_JADE.b, 0.30))
			draw_circle(p, 6.5, C_JADE)
			draw_circle(p, 2.6, Color(0.86, 1.0, 0.93))
			label_col = Color(C_JADE.r, C_JADE.g, C_JADE.b, 0.85)
		"current":
			_soft_blob(p, 46.0, C_AQUA, 0.95)
			var pr := 22.0 + 7.0 * sin(_phase * 2.3)
			draw_arc(p, pr, 0.0, TAU, 48, Color(C_AQUA.r, C_AQUA.g, C_AQUA.b, 0.35), 1.2, true)
			draw_arc(p, 17.0, 0.0, TAU, 48, C_AQUA_BRIGHT, 1.6, true)
			draw_circle(p, 9.5, C_AQUA_BRIGHT)
			draw_circle(p, 4.0, Color(0.94, 1.0, 0.99))
			_chevron(p + Vector2(0.0, -31.0))
			label_col = C_AQUA_BRIGHT
			label_y = 30.0
		"available":
			_soft_blob(p, 30.0, heat, 0.70)
			draw_circle(p, 11.0, Color(heat.r, heat.g, heat.b, 0.22))
			draw_circle(p, 7.5, heat)
			draw_circle(p, 3.0, Color(1, 1, 1, 0.92))
			label_col = C_TEXT
		_: # locked — recessive but heat-tinted: hollow ring previews the threat
			# gradient ahead, no halo/fill so it never competes with reachable nodes
			draw_circle(p, 6.5, Color(0.071, 0.137, 0.129))
			draw_arc(p, 6.5, 0.0, TAU, 24, Color(heat.r, heat.g, heat.b, 0.38), 1.3, true)
			draw_circle(p, 1.7, Color(heat.r, heat.g, heat.b, 0.45))
			label_col = Color(C_LOCK.r, C_LOCK.g, C_LOCK.b, 0.78)

	# Boss tag — a small coral pip offset to the upper-right, ONLY on reachable
	# uncleared bosses (the "objective" cue). Not a ring around every node, and
	# not on locked nodes (they stay mysterious). The current node owns the
	# chevron, so it skips the pip.
	if m.get("is_boss", false) and (st == "available"):
		var bp := p + Vector2(9.0, -9.0)
		draw_circle(bp, 3.4, Color(0.05, 0.10, 0.10, 0.9))
		draw_circle(bp, 2.6, C_CORAL)

	# selection reticle (rotating dashed ring + crosshair ticks)
	if m["id"] == selected_id:
		for k in range(8):
			var a0 := _phase * 1.3 + float(k) * TAU / 8.0
			draw_arc(p, 19.0, a0, a0 + TAU / 18.0, 4, C_TEAL, 1.8, true)
		for d in [Vector2(0, -19), Vector2(0, 19), Vector2(-19, 0), Vector2(19, 0)]:
			draw_line(p + d * 1.0, p + d * 1.25, C_TEAL, 1.4, true)
	elif m["id"] == hovered_id:
		draw_arc(p, 16.0, 0.0, TAU, 28, Color(C_TEAL.r, C_TEAL.g, C_TEAL.b, 0.6), 1.3, true)

	# label + state caption
	var nm := str(m["name"]).replace("HAZARD: ", "")
	_ctext(Vector2(p.x, p.y + label_y), tr(nm), label_col, 11)
	if st == "current":
		_ctext(Vector2(p.x, p.y + label_y + 11.0), tr("YOU ARE HERE"), Color(C_AQUA.r, C_AQUA.g, C_AQUA.b, 0.85), 8)
	elif m["id"] == selected_id and st == "available":
		# v174: was "READY TO WARP". On this map "warp" meant TRAVEL to the sector,
		# but Warp is the prestige reset everywhere else in the game — so Zone 1 read
		# as "you can prestige now" to a player twenty minutes in. Same collision as
		# the two Basic Batteries: one word, two mechanics.
		_ctext(Vector2(p.x, p.y + label_y + 11.0), tr("SET COURSE"), C_TEAL, 8)
	elif st == "locked" and m["id"] == selected_id:
		_ctext(Vector2(p.x, p.y + label_y + 11.0), tr("LOCKED"), C_CORAL, 8)

# v138: the SINGULARITY — a black hole, not a system: void core + white-hot photon
# ring + counter-rotating accretion arcs + a breathing gravitational-lensing halo.
# Pure draw primitives (GL-compat, no shader), animated off _phase like the rest.
func _draw_rift_node(m: Dictionary, p: Vector2) -> void:
	var cw := Color(0.78, 0.55, 1.0)   # prestige purple
	var breathe := 1.0 + 0.06 * sin(_phase * 2.6)
	# lensing halo — wider + brighter than any system glow so it reads as MASS
	_soft_blob(p, 44.0 * breathe, cw, 0.85)
	# accretion disc: three bright arcs swirling clockwise…
	for k in range(3):
		var a0 := _phase * 1.8 + float(k) * TAU / 3.0
		draw_arc(p, 15.0, a0, a0 + TAU * 0.24, 16, Color(cw.r, cw.g, cw.b, 0.9), 2.4, true)
	# …and two fainter counter-rotating outer wisps (the shear reads as spin)
	for k in range(2):
		var a1 := -_phase * 1.1 + float(k) * TAU / 2.0
		draw_arc(p, 19.5, a1, a1 + TAU * 0.16, 12, Color(0.95, 0.88, 1.0, 0.5), 1.3, true)
	# photon ring (white-hot rim) around the event horizon (true void)
	draw_circle(p, 11.0 * breathe, Color(0.94, 0.90, 1.0, 0.95))
	draw_circle(p, 9.0 * breathe, Color(0.02, 0.01, 0.05))
	# selection reticle / hover ring (same language as systems, in purple)
	if m["id"] == selected_id:
		for k in range(8):
			var a2 := _phase * 1.3 + float(k) * TAU / 8.0
			draw_arc(p, 25.0, a2, a2 + TAU / 18.0, 4, cw, 1.8, true)
		for d in [Vector2(0, -25), Vector2(0, 25), Vector2(-25, 0), Vector2(25, 0)]:
			draw_line(p + d * 1.0, p + d * 1.2, cw, 1.4, true)
	elif m["id"] == hovered_id:
		draw_arc(p, 22.0, 0.0, TAU, 32, Color(cw.r, cw.g, cw.b, 0.6), 1.3, true)
	# label + state caption
	_ctext(Vector2(p.x, p.y + 32.0), tr("SINGULARITY"), Color(0.90, 0.78, 1.0), 11)
	if m["id"] == selected_id:
		_ctext(Vector2(p.x, p.y + 43.0), tr("ENTER TO WARP"), cw, 8)

func _chevron(p: Vector2) -> void:
	var pts := PackedVector2Array([
		p + Vector2(0, -7), p + Vector2(6, 4), p + Vector2(0, 1), p + Vector2(-6, 4)])
	draw_colored_polygon(pts, Color(0.92, 1.0, 0.98))

func _ctext(pos: Vector2, txt: String, col: Color, fs: int, w: float = 150.0) -> void:
	if _font == null:
		return
	draw_string(_font, Vector2(pos.x - w * 0.5, pos.y), txt, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)

func _heat(diff: int) -> Color:
	if diff <= 4:
		return C_TEAL
	elif diff <= 8:
		return C_AMBER
	return C_CORAL

func _gen_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260630
	_stars.clear()
	for i in range(72):
		_stars.append({
			"n": Vector2(rng.randf(), rng.randf()),
			"r": rng.randf_range(0.6, 1.8),
			"a": rng.randf_range(0.22, 0.78),
			"tw": rng.randf() * TAU,
		})

func _model_by_id(id: String) -> Dictionary:
	for m in models:
		if m["id"] == id:
			return m
	return {}

# ── sector close-up view ────────────────────────────────────────────────────
func _npx(n: Vector2) -> Vector2:
	return Vector2(MARGIN + n.x * (size.x - 2.0 * MARGIN), MARGIN + n.y * (size.y - 2.0 * MARGIN))

# position with the reveal-zoom applied (content eases out from centre as the
# scrim lifts), so drilling in feels like pushing close.
func _spx(n: Vector2, reveal: float) -> Vector2:
	var p := _npx(n)
	if reveal < 0.999:
		var c := size * 0.5
		p = c + (p - c) * reveal
	return p

func _draw_sector() -> void:
	var reveal := lerpf(0.90, 1.0, 1.0 - _fade)
	var diff := int(_focus_zone.get("difficulty", 1))
	var heat := _heat(diff)

	# close-up atmosphere: one big heat nebula + starfield (no planet-limb arc —
	# a thin stroke across the whole view just read as a stray line).
	_soft_blob(size * 0.5, size.x * 0.58, heat, 0.30)
	for s in _stars:
		var sp: Vector2 = Vector2(s["n"].x * size.x, s["n"].y * size.y)
		var a: float = s["a"] * (0.55 + 0.45 * sin(_phase * 1.4 + s["tw"]))
		draw_circle(sp, s["r"], Color(0.81, 0.937, 0.902, a))

	# header + back affordance
	_ctext(Vector2(size.x * 0.5, 38.0), UITheme.tr_upper(tr(str(_focus_zone.get("name", "")).replace("HAZARD: ", ""))), C_TEXT, 16, size.x)
	_ctext(Vector2(size.x * 0.5, 56.0), tr("SELECT A TARGET"), heat, 9, size.x)
	var bx := Vector2(30.0, 28.0)
	draw_colored_polygon(PackedVector2Array([bx + Vector2(0, -4), bx + Vector2(0, 4), bx + Vector2(-6, 0)]), C_DIM)
	_ctext(Vector2(bx.x + 44.0, bx.y + 4.0), tr("STAR MAP"), C_DIM, 10, 90)

	for e in _enemies:
		if e.get("is_boss", false):
			_draw_boss(e, reveal)
		else:
			_draw_cluster(e, reveal)

func _draw_cluster(e: Dictionary, reveal: float) -> void:
	var p := _spx(e["pos"], reveal)
	var col: Color = e.get("color", C_TEXT)
	var sel: bool = e["eid"] == selected_enemy_id
	var hov: bool = e["eid"] == _hovered_enemy_id
	_soft_blob(p, 36.0, col, 0.55 if (sel or hov) else 0.32)
	# a little swarm of ships drifting around the cluster centre
	var offs := [Vector2(0, -7), Vector2(-11, 3), Vector2(11, 4), Vector2(-5, 9), Vector2(6, -2)]
	var bob := 1.5 * sin(_phase * 2.0)
	for i in range(offs.size()):
		_ship_glyph(p + offs[i] * 1.25 + Vector2(0, bob if i % 2 == 0 else -bob), col, 5.0)
	if sel:
		_reticle(p, 30.0)
	elif hov:
		draw_arc(p, 28.0, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.6), 1.3, true)
	if e.get("objective", false):
		_draw_objective_marker(p, 33.0)
	_ctext(Vector2(p.x, p.y + 44.0), tr(str(e.get("name", "Hostile"))), C_TEXT if (sel or hov) else C_DIM, 11)
	_ctext(Vector2(p.x, p.y + 56.0), tr("%s · %s HP") % [str(e.get("tag", "")), str(e.get("hp_txt", "?"))], col, 8)

func _draw_boss(e: Dictionary, reveal: float) -> void:
	var p := _spx(e["pos"], reveal)
	var sel: bool = e["eid"] == selected_enemy_id
	var hov: bool = e["eid"] == _hovered_enemy_id
	# v161: the boss used to be a pulsing RING plus four free-floating radial
	# ticks around a centred diamond — which is the exact vocabulary of
	# _reticle(), the SELECTION marker. Every boss therefore read as "already
	# targeted / locked on" while sitting idle. Rings and floating ticks are now
	# reserved strictly for hover/selection; the boss is drawn as a HOSTILE
	# STRUCTURE: a heavy armoured hull whose buttresses are attached to the
	# silhouette (structure reads as a thing, detached ticks read as a crosshair),
	# slowly rotating so it still feels alive and menacing.
	_soft_blob(p, 52.0, C_CORAL, 0.75)
	var spin := _phase * 0.22
	var breathe := 1.0 + 0.035 * sin(_phase * 2.0)
	var hull_r := 17.0 * breathe
	# Mid-tone, not near-black: against the dark starfield an almost-black
	# buttress reads as a smudge instead of structure.
	var dark := Color(C_CORAL.r * 0.72, C_CORAL.g * 0.34, C_CORAL.b * 0.40, 1.0)

	# Six armoured buttresses, welded to the hull edge (not floating).
	for k in range(6):
		var a0: float = spin + float(k) * TAU / 6.0
		var dir := Vector2(cos(a0), sin(a0))
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([
			p + dir * (hull_r - 1.0) + side * 5.2,
			p + dir * (hull_r + 8.5) + side * 2.6,
			p + dir * (hull_r + 8.5) - side * 2.6,
			p + dir * (hull_r - 1.0) - side * 5.2,
		]), dark)

	# Hexagonal hull + inner plating + hot core.
	var hull := PackedVector2Array()
	var plate := PackedVector2Array()
	for k in range(6):
		var a1: float = spin + float(k) * TAU / 6.0 + PI / 6.0
		var d1 := Vector2(cos(a1), sin(a1))
		hull.append(p + d1 * hull_r)
		plate.append(p + d1 * (hull_r * 0.62))
	draw_colored_polygon(hull, C_CORAL)
	draw_colored_polygon(plate, Color(0.30, 0.09, 0.13, 1.0))
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(0, -6.0), p + Vector2(6.0, 0), p + Vector2(0, 6.0), p + Vector2(-6.0, 0),
	]), Color(1.0, 0.80, 0.84))
	if sel:
		_reticle(p, 34.0)
	elif hov:
		draw_arc(p, 32.0, 0.0, TAU, 36, Color(C_CORAL.r, C_CORAL.g, C_CORAL.b, 0.6), 1.4, true)
	if e.get("objective", false):
		_draw_objective_marker(p, 40.0)
	_ctext(Vector2(p.x, p.y + 52.0), tr(str(e.get("name", "Boss"))), Color(1.0, 0.62, 0.67) if (sel or hov) else C_CORAL, 12)
	_ctext(Vector2(p.x, p.y + 65.0), tr("SECTOR BOSS · %s HP") % str(e.get("hp_txt", "?")), Color(C_CORAL.r, C_CORAL.g, C_CORAL.b, 0.85), 8)

func _ship_glyph(p: Vector2, col: Color, s: float) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.8, s * 0.8), p + Vector2(-s * 0.8, s * 0.8)]), col)

func _reticle(p: Vector2, r: float) -> void:
	for k in range(8):
		var a0 := _phase * 1.3 + float(k) * TAU / 8.0
		draw_arc(p, r, a0, a0 + TAU / 18.0, 4, C_TEAL, 1.8, true)
	for d in [Vector2(0, -r), Vector2(0, r), Vector2(-r, 0), Vector2(r, 0)]:
		draw_line(p + d.normalized() * (r - 4.0), p + d.normalized() * (r + 4.0), C_TEAL, 1.4, true)

# v133: gold quest marker on an enemy tied to an active "defeat" mission — a pulsing
# ring + a bobbing chevron + label so the player locks the RIGHT target.
func _draw_objective_marker(p: Vector2, r: float) -> void:
	var oc := Color(1.0, 0.82, 0.35)
	var rr := r + 3.0 * sin(_phase * 3.0)
	draw_arc(p, rr + 5.0, 0.0, TAU, 44, Color(oc.r, oc.g, oc.b, 0.28), 5.0, true)
	draw_arc(p, rr, 0.0, TAU, 44, Color(oc.r, oc.g, oc.b, 0.9), 2.4, true)
	var my := p.y - (r + 14.0) - 3.0 * sin(_phase * 3.0)
	draw_colored_polygon(PackedVector2Array([Vector2(p.x - 5.5, my - 6.0), Vector2(p.x + 5.5, my - 6.0), Vector2(p.x, my)]), oc)
	_ctext(Vector2(p.x, my - 15.0), tr("OBJECTIVE"), oc, 9)

func _enemy_by_id(eid: String) -> Dictionary:
	for e in _enemies:
		if e["eid"] == eid:
			return e
	return {}

func _nearest_enemy(local_pos: Vector2) -> Dictionary:
	var best := {}
	var best_d := ENEMY_HIT
	for e in _enemies:
		var d := _spx(e["pos"], 1.0).distance_to(local_pos)
		if d < best_d:
			best_d = d
			best = e
	return best

# ── interaction ─────────────────────────────────────────────────────────-─
func _nearest(local_pos: Vector2) -> Dictionary:
	var best := {}
	var best_d := HIT_RADIUS
	for m in models:
		var d := _node_px(m).distance_to(local_pos)
		if d < best_d:
			best_d = d
			best = m
	return best

func _gui_input(event: InputEvent) -> void:
	# Ignore input mid-transition.
	if _fade_dir != 0.0:
		return
	if view_mode == "sector":
		_sector_input(event)
		return
	if event is InputEventMouseMotion:
		var hit := _nearest(event.position)
		var hid: String = str(hit["id"]) if not hit.is_empty() else ""
		if hid != hovered_id:
			hovered_id = hid
			emit_signal("zone_hovered", hid)
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var hit := _nearest(event.position)
		if not hit.is_empty():
			emit_signal("zone_clicked", str(hit["id"]))
			accept_event()

func _sector_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hit := _nearest_enemy(event.position)
		var hid: String = str(hit["eid"]) if not hit.is_empty() else ""
		if hid != _hovered_enemy_id:
			_hovered_enemy_id = hid
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var hit := _nearest_enemy(event.position)
		if not hit.is_empty():
			selected_enemy_id = str(hit["eid"])
			emit_signal("enemy_clicked", selected_enemy_id)
			accept_event()
			queue_redraw()
