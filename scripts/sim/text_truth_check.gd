extends Node
# PLAYER-FACING TEXT TRUTH GUARD.
#
# Every string here described a mechanic that had been deleted or never shipped.
# None of them errored, nothing failed a test, and they survived multiple balance
# passes — a description is only wrong if someone reads it against the code.
#
#   - SlugT1S advertised "+5% damage on its channel" after v155 set its
#     AMMO_TIER_MULT to 1.00, in the vocabulary of the removed channel system.
#   - Cryo weapon tooltips carried "Weak: Conventional enemies resist" while no
#     enemy anywhere has a positive resist_cryo.
#   - Nine Z2-Z10 modules called themselves "missile-channel" armaments; their
#     stat is atk_explosive and every live surface says EXPLOSIVE.
#
#   Godot --headless --path <root> res://scenes/text_truth_check.tscn

const REMOVED_VOCAB := ["missile-channel", "energy-channel", "kinetic-channel",
	"on its channel", "hits the hull", "penetrates armor"]

var fails: int = 0

func _ready() -> void:
	await get_tree().process_frame
	var sm = GameState.shipyard_manager

	# ---- 1. no module description may use removed-system vocabulary ---------
	for mid in sm.modules:
		var d: String = String(sm.modules[mid].get("desc", ""))
		for bad in REMOVED_VOCAB:
			if bad in d:
				_fail("module %s desc says '%s': \"%s\"" % [mid, bad, d.substr(0, 60)])

	# ---- 2. nor may any element description ---------------------------------
	for e in GameState.elements_db:
		var d2: String = String((e as Dictionary).get("description", ""))
		for bad in REMOVED_VOCAB:
			if bad in d2:
				_fail("element %s desc says '%s'" % [String((e as Dictionary).get("symbol", "?")), bad])

	# ---- 3. an ammo that claims a bonus must actually have one --------------
	# ElementDB.AMMO_TIER_MULT is the only thing that grants an ammo damage edge.
	for e in GameState.elements_db:
		var ed: Dictionary = e
		# AMMO only — a matrix core's "+60% Crit Dmg" comes from its gem stats, not
		# from AMMO_TIER_MULT, and reading it here was a false positive.
		if String(ed.get("category", "")) != "Ammo":
			continue
		var sym: String = String(ed.get("symbol", ""))
		var desc: String = String(ed.get("description", ""))
		if not ("%" in desc and ("damage" in desc.to_lower() or "dmg" in desc.to_lower())):
			continue
		var mult: float = _ammo_mult(sym)
		if mult <= 1.0:
			_fail("%s advertises a damage bonus but AMMO_TIER_MULT is %.2f: \"%s\"" % [sym, mult, desc])

	# ---- 4. a tooltip may not claim a resistance nothing carries ------------
	# Guards the reinstatement of the cryo "conventional enemies resist" line.
	var any_positive_cryo_resist: bool = false
	for eid in GameState.combat_manager.enemy_db:
		if float(GameState.combat_manager.enemy_db[eid].get("resist_cryo", 0.0)) > 0.0:
			any_positive_cryo_resist = true
			break
	var claims: int = 0
	for f in ["res://scripts/ui/designer_slot_widget.gd", "res://scripts/ui/module_card.gd"]:
		var fh := FileAccess.open(f, FileAccess.READ)
		if fh == null:
			continue
		if 'tr("Weak: Conventional enemies resist")' in fh.get_as_text():
			claims += 1
		fh.close()
	print("[TXT] cryo-resist tooltip claims=%d, enemies with positive resist_cryo=%s" % [
		claims, str(any_positive_cryo_resist)])
	if claims > 0 and not any_positive_cryo_resist:
		_fail("%d tooltip(s) say conventional enemies resist Cryo, but no enemy has a positive resist_cryo" % claims)

	print("[TXT] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _ammo_mult(sym: String) -> float:
	for suffix in ElementDB.AMMO_TIER_MULT:
		if sym.ends_with(String(suffix)):
			return float(ElementDB.AMMO_TIER_MULT[suffix])
	return 1.0


func _fail(msg: String) -> void:
	print("[TXT] FAIL: %s" % msg)
	fails += 1
