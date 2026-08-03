extends Node
# ============================================================================
# COACH ARROW ON ARMORY TILE (v141) — equip missions must point the GEAR to grab,
# not only the empty slot. The matching Armory module_card carries coach_pulse;
# this asserts that flag now also stamps a bobbing gold arrow (coach_arrow.svg,
# rotated to aim DOWN at the tile), and that clearing coach_pulse removes it.
#   Godot --headless --path <root> res://scenes/coach_arrow_check.tscn
# ============================================================================

var fails := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond: fails += 1
	print("[COACHARROW] %-44s %s %s" % [name, "OK" if cond else "*** FAIL", detail])


func _find_arrow(card: Node) -> TextureRect:
	for c in card.get_children():
		if c is TextureRect:
			return c
	return null


func _ready() -> void:
	GameState.set_process(false)
	print("[COACHARROW] ============ coach arrow on armory tile ============")

	var scene := load("res://scenes/ui/module_card.tscn")
	_ok("module_card scene loads", scene != null)
	if scene == null:
		get_tree().quit(1); return

	var card = scene.instantiate()
	add_child(card)
	card.size = Vector2(64, 64)
	await get_tree().process_frame

	# Arm the coach-pulse (what rebuild_storage sets on the matching tile) and run
	# the same pulse entry point the card uses (_apply_pulse).
	card.coach_pulse = true
	card._apply_pulse(0)   # rarity 0; coach branch returns before touching shipyard
	await get_tree().process_frame

	var arrow := _find_arrow(card)
	_ok("arrow spawned on coach_pulse", arrow != null)
	if arrow:
		_ok("arrow points DOWN (~90°)", absf(arrow.rotation - PI / 2.0) < 0.01,
			"rot=%.3f" % arrow.rotation)
		_ok("arrow is gold", arrow.modulate.r > 0.9 and arrow.modulate.b < 0.6,
			str(arrow.modulate))
		_ok("arrow ignores mouse", arrow.mouse_filter == Control.MOUSE_FILTER_IGNORE)
		_ok("arrow has a texture", arrow.texture != null)

	# Clearing coach_pulse must remove the arrow (mission advanced / tile rebuilt).
	card.coach_pulse = false
	card._apply_pulse(0)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("arrow removed when coach_pulse off", _find_arrow(card) == null)

	# ── v141: consumable equip focus matches hull/shield sub-type ──
	# The mission equips the hull kit first, then the shield kit; only the matching
	# kind should carry the arrow. _module_matches_equip_focus is pure logic, so a
	# script-only designer_page (no _ready, no armory build) exercises it cleanly.
	print("[COACHARROW] --- consumable hull/shield sub-filter ---")
	var dp = load("res://scripts/ui/designer_page.gd").new()
	var hull_kit := {"slot_type": "consumable", "consumable_type": "hull"}
	var shield_kit := {"slot_type": "consumable", "consumable_type": "shield"}
	var a_weapon := {"slot_type": "weapon", "stats": {"atk_kinetic": 5}}

	dp._equip_focus_filter_type = "consumable"
	dp._equip_focus_weapon_type = "hull"
	_ok("filter=consumable/hull: hull kit matches", dp._module_matches_equip_focus(hull_kit))
	_ok("filter=consumable/hull: shield kit EXCLUDED", not dp._module_matches_equip_focus(shield_kit))
	_ok("filter=consumable/hull: weapon EXCLUDED", not dp._module_matches_equip_focus(a_weapon))

	dp._equip_focus_weapon_type = "shield"
	_ok("filter=consumable/shield: shield kit matches", dp._module_matches_equip_focus(shield_kit))
	_ok("filter=consumable/shield: hull kit EXCLUDED", not dp._module_matches_equip_focus(hull_kit))

	# No focus → nothing matches (arrow off).
	dp._equip_focus_filter_type = ""
	dp._equip_focus_weapon_type = ""
	_ok("no focus: nothing matches", not dp._module_matches_equip_focus(hull_kit))
	dp.free()

	print("[COACHARROW] ============ %s ============" % ("ALL PASS" if fails == 0 else "%d FAIL(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
