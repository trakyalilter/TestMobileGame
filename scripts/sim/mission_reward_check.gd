extends Node
# MISSION REWARDS: LIRAS, NEVER SKILL XP (owner ruling, 2026-08-09).
#
# v134 wired reward_xp onto "the skill the mission exercised". The routing sent
# research / craft / build / visit_page beats to Engineering, so m002
# "Foundational Research" paid 200 Engineering XP and put a brand-new player at
# Engineering level 2 having crafted nothing — level 2 needs 133. A level is
# supposed to mean you did the thing.
#
# Two ways that can come back, both checked:
#   1. the grant is re-wired (measured by actually claiming a mission and
#      watching every skill's XP, not by reading the code);
#   2. a mission ends up paying NOTHING — which is what happens if XP is removed
#      from a mission that only ever paid XP.
#
#   Godot --headless --path <root> res://scenes/mission_reward_check.tscn

var fails: int = 0

func _ready() -> void:
	await get_tree().process_frame
	if not GameState.sim_mode:
		print("[MREW] ABORT: sim_mode false")
		get_tree().quit(1)
		return
	GameState.set_process(false)
	var mm = GameState.mission_manager

	# ---- 1. claiming a mission must move no skill's XP ---------------------
	# The old defect was research -> Engineering, so claim a RESEARCH beat: the
	# exact shape that used to leak.
	var skills := {
		"Mining": GameState.gathering_manager,
		"Engineering": GameState.processing_manager,
		"Combat": GameState.combat_manager,
		"Research": GameState.research_manager,
		"Infrastructure": GameState.infrastructure_manager,
	}
	var target := ""
	for mid in mm.missions:
		var m: Dictionary = mm.missions[mid]
		if String(m.get("type", "")) == "research" and float(m.get("reward_xp", 0)) > 0.0:
			target = String(mid)
			break
	if target == "":
		print("[MREW] no research mission carries reward_xp — nothing to leak")
	else:
		var before := {}
		for k in skills:
			before[k] = float(skills[k].xp)
		var m2: Dictionary = mm.missions[target]
		m2["completed"] = true
		m2["claimed"] = false
		if not target in mm.active_missions:
			mm.active_missions.append(target)
		mm.claim_reward(target)
		var moved: Array = []
		for k2 in skills:
			var d: float = float(skills[k2].xp) - float(before[k2])
			if absf(d) > 0.001:
				moved.append("%s +%.0f" % [k2, d])
		print("[MREW] claimed %s (research, reward_xp=%d) -> skill xp moved: %s" % [
			target, int(m2.get("reward_xp", 0)), ", ".join(moved) if moved.size() > 0 else "none"])
		if moved.size() > 0:
			_fail("claiming a mission paid skill XP: %s" % ", ".join(moved))

	# ---- 2. no mission may pay nothing at all -----------------------------
	# Removing XP from a mission that only paid XP leaves an empty reward.
	var empty: Array = []
	for mid3 in mm.missions:
		var m3: Dictionary = mm.missions[mid3]
		if float(m3.get("reward_cr", 0)) <= 0.0:
			empty.append(String(mid3))
	if empty.size() > 0:
		_fail("%d mission(s) pay no Liras and XP is no longer granted, so they pay NOTHING: %s" % [
			empty.size(), ", ".join(empty)])

	print("[MREW] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _fail(msg: String) -> void:
	print("[MREW] FAIL: %s" % msg)
	fails += 1
