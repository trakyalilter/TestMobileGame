extends Node
# SECTOR-MAP OBJECTIVE MARKER.
#
# The map marks the enemy an active kill mission names, so the player locks the
# RIGHT hostile instead of any of them. get_active_defeat_targets() fed that, and
# it matched type "defeat" ONLY — missing "defeat_retreat", which is the type of
# m017, the first kill the tutorial ever asks for. The Lunar Drone therefore sat
# unmarked during the one mission that names it, and the coach arrow could not
# help either: get_enemy_card() returns null while the chart is open, by design,
# on the assumption that the chart marks the target itself.
#
#   Godot --headless --path <root> res://scenes/objective_marker_check.tscn

var fails: int = 0

func _ready() -> void:
	await get_tree().process_frame
	GameState.set_process(false)
	var mm = GameState.mission_manager

	# Every active kill mission must contribute its target, whatever the type.
	var kill_types := ["defeat", "defeat_retreat"]
	var missing: Array = []
	var covered: Array = []
	for mid in mm.missions:
		var m: Dictionary = mm.missions[mid]
		if not (str(m.get("type", "")) in kill_types):
			continue
		var tgt := str(m.get("target", ""))
		if tgt == "":
			continue
		# activate it in isolation and ask what the map would mark
		for other in mm.active_missions.duplicate():
			mm.active_missions.erase(other)
		m["completed"] = false
		m["claimed"] = false
		mm.active_missions.append(str(mid))
		var marked: Array = mm.get_active_defeat_targets()
		if marked.has(tgt):
			covered.append(str(mid))
		else:
			missing.append("%s (%s -> %s)" % [str(mid), str(m.get("type", "")), tgt])

	print("[OBJ] kill missions marked: %d, unmarked: %d" % [covered.size(), missing.size()])
	for x in missing:
		_fail("no objective marker for %s" % x)

	print("[OBJ] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _fail(msg: String) -> void:
	print("[OBJ] FAIL: %s" % msg)
	fails += 1
