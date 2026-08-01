extends Control
## Procedural "Matrix Core" icon — a faceted cut GEMSTONE (not an energy core).
##
## A solid, top-lit faceted gem: shaded crown facets, a polished table, crisp
## cut-edge hairlines and a specular glint. Reads as a mineral stone, not
## plasma. Colour is supplied per gem; the facet light/shadow are white/black
## lerps on that base colour, so any colour works from one routine.
##
## Tier drives cut quality (Cracked / Stable / Pristine), so the stone visibly
## refines as it upgrades:
##   0 CRACKED  — muted facets, internal inclusions, a fracture, a chipped point
##   1 STABLE   — a clean cut (default)
##   2 PRISTINE — finer 12-facet brilliant cut, double rim, dual glints, shimmer
##
## Geometry is authored in a 64×64 "comp space" and mapped to whatever rect the
## node is given, so the big armory tile and the tiny equipped socket match.
##
## Hardware-cursor-friendly: pure _draw(), no per-frame work — repaints only on
## resize or when set_core() changes the colour/tier.

const TIER_CRACKED := 0
const TIER_STABLE := 1
const TIER_PRISTINE := 2
const TIER_RESONANT := 3   # v135a: CMB_4 tier — renders at Pristine quality + an extra halo/glint

# v147: THE socket-row geometry, shared by every surface that draws sockets
# (equipped slot panel + armory tile). They had drifted apart — the armory drew
# flat 45° Panel diamonds at 7px/3px in a straight line while the equipped slot
# drew these faceted icons at 16px/12px on an arc, so the same module looked like
# two different items. Both now read these constants and socket_offset().
const SOCKET_D := 16.0        # icon size (px)
const SOCKET_GAP := 12.0      # gap between sockets (px)
const SOCKET_ARC := 8.0       # parabola depth: outer sockets ride high, centre dips

# Row width for n sockets, so a caller can centre the row.
static func socket_row_width(n: int) -> float:
	if n <= 0:
		return 0.0
	return float(n) * SOCKET_D + float(n - 1) * SOCKET_GAP

# Position of socket i within the row. Bowl ∪ (classic y=x²): the outer sockets
# ride high near the icon and the centre dips, so 3 sockets cradle under it.
# A lone socket sits flat at mid-band (a single point can't show a curve).
static func socket_offset(i: int, n: int) -> Vector2:
	var ci: float = float(n - 1) / 2.0
	var t: float = 0.0 if n <= 1 else (float(i) - ci) / maxf(1.0, ci)
	var y: float = (SOCKET_ARC * 0.5) if n <= 1 else (SOCKET_ARC * (1.0 - t * t))
	return Vector2(float(i) * (SOCKET_D + SOCKET_GAP), y)

# Single source for gem colour (was duplicated verbatim in module_card and
# designer_slot_widget, which is how the two socket looks drifted).
static func gem_color(gem_name: String) -> Color:
	if "Crimson" in gem_name: return Color("#ff4444")
	if "Cobalt" in gem_name: return Color("#44ccff")
	if "Topaz" in gem_name: return Color("#FFC24D")
	if "Amethyst" in gem_name: return Color("#aa44ff")
	return Color("#b548b5") # Default purple

# Colour used for an EMPTY socket (hollow recessed outline).
const EMPTY_SOCKET_COLOR := Color(0.42, 0.47, 0.58)

var core_color: Color = Color(0.45, 0.80, 1.0)
var hollow: bool = false   # empty socket → faint recessed outline only
var tier: int = TIER_STABLE

# Socket-plate colour, used to fake the "removed material" of a chipped corner.
const _SOCKET_BG := Color(0.03, 0.045, 0.07)
const _WHITE := Color(1, 1, 1)
const _BLACK := Color(0, 0, 0)
# Per-crown-facet light (+white / −black) under a single up-left light source.
const _FL := [0.16, -0.10, -0.30, -0.20, 0.22, 0.38]


func set_core(color: Color, is_hollow: bool = false, p_tier: int = TIER_STABLE) -> void:
	core_color = color
	hollow = is_hollow
	tier = p_tier
	queue_redraw()


# Cracked* / Stable* / Pristine* / Resonant* gem-name → tier. Default Stable.
static func tier_from_name(n: String) -> int:
	if "Resonant" in n:
		return TIER_RESONANT
	if "Pristine" in n:
		return TIER_PRISTINE
	if "Cracked" in n:
		return TIER_CRACKED
	return TIER_STABLE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)


# Map a point from 64×64 comp space into the live rect.
func _mp(x: float, y: float, c: Vector2, r: float) -> Vector2:
	return c + Vector2((x - 32.0) * r / 32.0, (y - 32.0) * r / 32.0)

func _map(comp_pts: Array, c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in comp_pts:
		out.append(_mp(p.x, p.y, c, r))
	return out

func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var cl := PackedVector2Array(pts)
	cl.append(pts[0])
	return cl


func _draw() -> void:
	var s := size
	if s.x <= 1.0 or s.y <= 1.0:
		return
	var c := s * 0.5
	var r := minf(s.x, s.y) * 0.5
	var u := r / 32.0     # comp-space → px width scale

	# Point-top hexagon (comp space) + 0.42 inner table.
	var vc := [Vector2(32, 10), Vector2(47.6, 21), Vector2(47.6, 43),
		Vector2(32, 54), Vector2(16.4, 43), Vector2(16.4, 21)]
	var tc := []
	for p in vc:
		tc.append(Vector2(32, 32) + (p - Vector2(32, 32)) * 0.42)
	var v := _map(vc, c, r)
	var t := _map(tc, c, r)

	# Empty socket: faint recessed silhouette only.
	if hollow:
		var dim := Color(core_color.r, core_color.g, core_color.b, 0.32)
		draw_polyline(_closed(v), dim, maxf(1.0, 1.4 * u), true)
		draw_circle(c, r * 0.10, Color(core_color.r, core_color.g, core_color.b, 0.18))
		return

	var mute: float = 0.5 if tier == TIER_CRACKED else 1.0

	# Pristine/Resonant grade-shimmer behind the stone (subtle, NOT a plasma disc).
	if tier >= TIER_PRISTINE:
		var halo := Color(core_color.r, core_color.g, core_color.b, 0.16)
		# v135a: Resonant adds a wider, brighter outer ring so it out-shines Pristine.
		if tier >= TIER_RESONANT:
			draw_colored_polygon(_scaled(v, c, 1.22), Color(core_color.r, core_color.g, core_color.b, 0.13))
		draw_colored_polygon(_scaled(v, c, 1.14), halo)
		halo.a = 0.22
		draw_colored_polygon(_scaled(v, c, 1.07), halo)

	# Base body + shaded crown facets.
	draw_colored_polygon(v, core_color)
	for i in range(6):
		var j := (i + 1) % 6
		var facet := PackedVector2Array([v[i], v[j], t[j], t[i]])
		var l: float = float(_FL[i]) * mute
		var fcol: Color = core_color.lerp(_WHITE, l) if l >= 0.0 else core_color.lerp(_BLACK, -l)
		draw_colored_polygon(facet, fcol)

	# Polished table.
	var table_light: float = 0.18 if tier == TIER_CRACKED else 0.40
	draw_colored_polygon(t, core_color.lerp(_WHITE, table_light))

	# Cut-edge hairlines (vertex → table).
	var hair := Color(0, 0, 0, 0.22 * (0.55 if tier == TIER_CRACKED else 1.0))
	for i in range(6):
		draw_line(v[i], t[i], hair, maxf(0.8, 1.0 * u), true)

	# Pristine+: 12-facet brilliant ridges (facet-centre → table-centre).
	if tier >= TIER_PRISTINE:
		var ridge := Color(1, 1, 1, 0.40)
		for i in range(6):
			var j := (i + 1) % 6
			draw_line((v[i] + v[j]) * 0.5, (t[i] + t[j]) * 0.5, ridge, maxf(0.7, 0.9 * u), true)

	if tier == TIER_CRACKED:
		_draw_cracked(c, r, u, v)
		return

	# Rim (Stable + Pristine + Resonant).
	var rim_a: float = (1.0 if tier >= TIER_RESONANT else 0.8) if tier >= TIER_PRISTINE else 0.5
	draw_polyline(_closed(v), Color(1, 1, 1, rim_a), maxf(1.0, 1.7 * u), true)
	if tier >= TIER_PRISTINE:
		draw_polyline(_closed(_scaled(v, c, 0.9)), Color(1, 1, 1, 0.28), maxf(0.7, 0.8 * u), true)

	# Specular glint(s).
	draw_line(_mp(22, 20, c, r), _mp(27.5, 14.5, c, r), Color(1, 1, 1, 0.9), maxf(1.2, 2.4 * u), true)
	if tier >= TIER_PRISTINE:
		draw_line(_mp(40, 40, c, r), _mp(44, 36, c, r), Color(1, 1, 1, 0.8), maxf(1.0, 1.8 * u), true)
	# v135a: Resonant gets a third micro-glint for a richer sparkle.
	if tier >= TIER_RESONANT:
		draw_line(_mp(30, 46, c, r), _mp(33, 43, c, r), Color(1, 1, 1, 0.7), maxf(0.9, 1.5 * u), true)


# Cracked-tier overlays: dull wash, inclusions, fracture, chipped point, broken rim.
func _draw_cracked(c: Vector2, r: float, u: float, v: PackedVector2Array) -> void:
	# Dull wash.
	draw_colored_polygon(v, Color(0, 0, 0, 0.20))
	# Internal inclusions (mineral flecks).
	draw_circle(_mp(27, 35, c, r), maxf(1.0, 2.1 * u), Color(0, 0, 0, 0.30))
	draw_circle(_mp(37, 29, c, r), maxf(0.8, 1.4 * u), Color(0, 0, 0, 0.24))
	# Fracture — dark depth + a lit edge beside it + a short branch.
	var frac := _map([Vector2(45.5, 24), Vector2(36, 33), Vector2(30, 43)], c, r)
	draw_polyline(frac, Color(0, 0, 0, 0.55), maxf(1.0, 1.6 * u), true)
	var frac_lit := _map([Vector2(46.2, 24.6), Vector2(36.8, 33.6), Vector2(30.8, 43.4)], c, r)
	draw_polyline(frac_lit, Color(1, 1, 1, 0.18), maxf(0.6, 0.7 * u), true)
	draw_line(_mp(36, 33, c, r), _mp(31, 30, c, r), Color(0, 0, 0, 0.45), maxf(0.8, 1.2 * u), true)
	# Chipped point at the upper-right vertex: a sliver of socket shows + a
	# frosty fresh-break edge that catches light.
	draw_colored_polygon(_map([Vector2(44.6, 17.4), Vector2(47.6, 21), Vector2(45.4, 24.4)], c, r), _SOCKET_BG)
	draw_line(_mp(44.6, 17.4, c, r), _mp(45.4, 24.4, c, r), Color(1, 1, 1, 0.32), maxf(0.7, 1.0 * u), true)
	# Dim rim, broken around the chip (skips the v0→v1 segment).
	var broken := _map([Vector2(47.6, 21), Vector2(47.6, 43), Vector2(32, 54),
		Vector2(16.4, 43), Vector2(16.4, 21), Vector2(32, 10), Vector2(44.6, 17.4)], c, r)
	draw_polyline(broken, Color(1, 1, 1, 0.24), maxf(0.9, 1.3 * u), true)
	# Faint glint only (damaged stones barely sparkle).
	draw_line(_mp(23, 19, c, r), _mp(26, 16, c, r), Color(1, 1, 1, 0.30), maxf(0.8, 1.6 * u), true)


# Scale a mapped polygon about centre c.
func _scaled(pts: PackedVector2Array, c: Vector2, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + (p - c) * k)
	return out
