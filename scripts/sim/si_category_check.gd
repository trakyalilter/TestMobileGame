extends Node
# v139l: Silicon showed a GREEN gain-toast frame but a BLUE-GREY inventory glyph.
# Root: "Si" was missing from CATEGORIES.basic_metals, so get_category("Si")="other"
# and element_accent fell to the green default, while the card used the explicit
# MATERIAL_TINT["Si"]. Asserts Si now categorizes + its accent is no longer the default.
# NOTE: no hard_reset / no save writes. Run with --user-dir <scratch> anyway.
func _ready() -> void:
	var fails := 0
	var cat: String = ElementDB.get_category("Si")
	var acc: Color = UITheme.element_accent("Si")
	var default_green := Color(0.40, 0.90, 0.60)
	var basic := UITheme.element_accent("Fe")   # a known basic_metal, for parity
	var c1: bool = cat == "basic_metals"
	var c2: bool = not acc.is_equal_approx(default_green)
	var c3: bool = acc.is_equal_approx(basic)
	if not c1: fails += 1
	if not c2: fails += 1
	if not c3: fails += 1
	print("[SICAT] get_category(Si) = %s  %s" % [cat, "OK" if c1 else "*** FAIL"])
	print("[SICAT] accent != green default   %s (accent=%s)" % ["OK" if c2 else "*** FAIL", str(acc)])
	print("[SICAT] accent == Fe (basic_metal) %s" % ["OK" if c3 else "*** FAIL"])
	print("[SICAT] %s" % ("ALL PASS" if fails == 0 else "*** %d FAIL" % fails))
	get_tree().quit(1 if fails > 0 else 0)
