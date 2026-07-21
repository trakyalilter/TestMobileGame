extends Node
# ============================================================================
# ATLAS BYPRODUCT-SOURCE CHECK (v139k) — owner-reported: Silver (Ag) shows
# "No known source" in the Atlas yet feeds Advanced Circuits + Silver Catalyst.
# Root cause: build_material_database scanned recipe["output"] + ["input"] but
# NEVER recipe["output_table"], so byproduct-only materials read as unsourced.
# Ag is a DETERMINISTIC byproduct of Zinc Reduction (made mandatory for m029b),
# Co/Pd/PathogenCore are probabilistic byproducts. Asserts they now resolve.
#   Godot --headless --path <root> res://scenes/matrix_mission_check.tscn ...
#   (this file: res://scenes/... see atlas_source_check.tscn)
# ============================================================================

var fails := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond: fails += 1
	print("[ATLASSRC] %-42s %s %s" % [name, "OK" if cond else "*** FAIL", detail])

func _src_count(atlas, sym: String) -> int:
	return atlas.material_db.get(sym, {}).get("sources", []).size()

func _sourced_from(atlas, sym: String, needle: String) -> bool:
	for s in atlas.material_db.get(sym, {}).get("sources", []):
		if needle.to_lower() in str(s.get("name", "")).to_lower():
			return true
	return false

func _ready() -> void:
	print("[ATLASSRC] ===== atlas byproduct-source check =====")
	GameState.set_process(false)
	GameState.hard_reset()

	# build_material_database is pure data (no @onready node access), so a bare .new()
	# instance can rebuild the DB without the full scene.
	var atlas = load("res://scripts/ui/atlas_page.gd").new()
	atlas.build_material_database()

	# The reported case: Ag is byproduct-ONLY (Zinc Reduction), so 0 -> >=1 proves the fix.
	_ok("Ag has a source now", _src_count(atlas, "Ag") >= 1, "count=%d" % _src_count(atlas, "Ag"))
	_ok("Ag sourced from Zinc Reduction", _sourced_from(atlas, "Ag", "Zinc"))
	# Ag still lists its USES (regression guard — the input scan must be untouched).
	var ag_uses: int = atlas.material_db.get("Ag", {}).get("uses", []).size()
	_ok("Ag still lists uses (>=2)", ag_uses >= 2, "uses=%d" % ag_uses)

	# Other byproducts surfaced by the same fix.
	_ok("Co has a source", _src_count(atlas, "Co") >= 1)
	_ok("Pd has a source", _src_count(atlas, "Pd") >= 1)
	_ok("PathogenCore has a source", _src_count(atlas, "PathogenCore") >= 1)

	atlas.free()
	print("[ATLASSRC] %s" % ("ALL PASS" if fails == 0 else "*** %d FAILURE(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
