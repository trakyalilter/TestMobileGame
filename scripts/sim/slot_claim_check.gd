extends Node
# "EQUIP ONE PER <SLOT> SLOT" MUST MATCH THE HULL THE PLAYER IS FLYING (v175).
#
# Several refit beats tell the player to fabricate N of something and "equip one per
# weapon/armor/shield/battery slot". That sentence is a promise about the hull's slot
# table, and commit ca26034 redistributed those tables (+1 weapon every tier, the second
# slot alternating defence/battery) without revisiting the missions that quote them.
# Result: beats asking for 3 weapons on a 4-weapon hull, and one asking for 2 armour
# plates for a single armour slot — the second plate cost 7,260 Liras and 364 Steel and
# could never be equipped.
#
# Keyed on the CLAIM, not on the quantity. Asserting `target_qty == slot_count` for every
# craft beat would fire on beats that never promised one-per-slot (m017a asks for 2 Pulse
# Lasers and says nothing untrue), which is how the original audit finding picked up a
# false positive. Only beats whose DESCRIPTION contains "per <slot> slot" are judged.
#
# The hull is derived by walking the chain and remembering the last hull the player was
# told to construct, so this keeps working when the chain is reordered.
#
#   Godot --headless --path <root> res://scenes/slot_claim_check.tscn

const SLOT_WORDS := ["weapon", "armor", "shield", "battery", "engine", "sensor"]

var fails: int = 0

func _ready() -> void:
	await get_tree().process_frame
	GameState.set_process(false)
	var mm = GameState.mission_manager
	var sm = GameState.shipyard_manager

	# Corvette until the chain says otherwise — that is what a new game starts in.
	var hull := "corvette_hull"
	var checked := 0
	var cur := "m001"
	var steps := 0
	print("[SLOT] %-9s %-14s %-8s %5s %5s   %s" % [
		"mission", "hull", "slot", "asks", "slots", "verdict"])
	while cur != "" and steps < 200:
		var m: Dictionary = mm.missions.get(cur, {})
		if m.is_empty():
			break
		steps += 1
		# Track the hull the chain has put the player in.
		if str(m.get("type", "")) == "construct" and sm.hulls.has(str(m.get("target", ""))):
			hull = str(m.get("target", ""))
		var desc := str(m.get("description", ""))
		var low := desc.to_lower()
		for slot in SLOT_WORDS:
			var needle := "per %s slot" % slot
			if not (needle in low):
				continue
			checked += 1
			var have: int = _slot_count(sm, hull, slot)
			var asks: int = int(m.get("target_qty", 0))
			var ok: bool = (asks == have)
			print("[SLOT] %-9s %-14s %-8s %5d %5d   %s" % [
				cur, hull, slot, asks, have,
				"OK" if ok else "*** MISMATCH — text promises one per slot"])
			if not ok:
				_fail("%s says \"one per %s slot\" and asks for %d, but the %s has %d %s slot(s)" % [
					cur, slot, asks, str(sm.hulls.get(hull, {}).get("name", hull)), have, slot])
		cur = str(m.get("next_mission", ""))

	print("[SLOT] %d one-per-slot claim(s) checked across %d beats" % [checked, steps])
	if checked == 0:
		_fail("no beat matched \"per <slot> slot\" — the phrasing changed and this guard now checks nothing")

	print("[SLOT] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _slot_count(sm, hull: String, slot: String) -> int:
	var n := 0
	for s in (sm.hulls.get(hull, {}).get("slots", []) as Array):
		if str(s) == slot:
			n += 1
	return n


func _fail(msg: String) -> void:
	print("[SLOT] FAIL: %s" % msg)
	fails += 1
