class_name Skill
extends RefCounted

var skill_name: String
var xp: float = 0.0
var level: int = 1
# v107: Cap raised 99 → 100 to give a clean round-number capstone and a
# dedicated milestone (gold-card cosmetic in P1 Mastery layer). XP table
# already runs to 120 so no curve change is needed — just the cap.
var max_level: int = 100
var xp_table: Dictionary = {}

# Signals for UI updates can be added here or in the manager
signal level_up(new_level)
signal xp_gained(amount)
signal milestone_unlocked(milestone_level)

var unlocked_milestones: Array[int] = []

func _init(p_name: String = "Skill"):
	skill_name = p_name
	xp_table = _generate_xp_table()

func _generate_xp_table() -> Dictionary:
	var table = {}
	var total_xp: float = 0.0
	# RuneScape XP Formula - Adjusted for steeper early game
	# Original diff / 4.0 was too fast for 1-hour loops.
	# Standardizing to require more actions for early milestones.
	for lvl in range(1, 121):
		table[lvl] = int(total_xp)
		if lvl < 120:
			# Steeper early game by adding a flat difficulty constant for first 20 levels
			var boost = 200.0 if lvl < 20 else 0.0
			var diff = int(floor(lvl + boost + 300.0 * pow(2.0, float(lvl) / 7.0)))
			total_xp += diff / 4.0
	return table

func get_xp_for_level(lvl: int) -> int:
	if lvl in xp_table:
		return xp_table[lvl]
	return 0

func get_level() -> int:
	return level

func add_xp(amount: float):
	# Audit v2.0 P1-9: Apply prestige XP multiplier
	var xp_mult = 1.0
	if GameState and GameState.warp_manager:
		xp_mult *= GameState.warp_manager.get_xp_multiplier()
	
	xp += amount * xp_mult
	xp_gained.emit(amount * xp_mult)
	check_level_up()

func check_level_up():
	var next_level = level + 1
	if next_level in xp_table:
		var req_xp = xp_table[next_level]
		while xp >= req_xp:
			level += 1
			next_level += 1
			level_up.emit(level)
			_check_milestones(level)
			if next_level > max_level:
				break
			if next_level in xp_table:
				req_xp = xp_table[next_level]

func _check_milestones(new_lvl: int):
	# v107: 100 added as the capstone milestone — P1 Mastery hooks this to
	# award the gold-card cosmetic (Hearthstone-style golden header treatment
	# on the maxed skill's card).
	for m in [10, 25, 50, 75, 100]:
		if new_lvl >= m and not m in unlocked_milestones:
			unlocked_milestones.append(m)
			milestone_unlocked.emit(m)

func is_milestone_unlocked(m_lvl: int) -> bool:
	return m_lvl in unlocked_milestones

func get_progress_to_next_level() -> float:
	if level >= max_level:
		return 100.0
	
	var current_level_xp = xp_table[level]
	var next_level_xp = xp_table[level + 1]
	
	var needed = next_level_xp - current_level_xp
	var current = xp - current_level_xp
	
	if needed <= 0: return 100.0 # Should not happen based on formula
	
	return (current / float(needed)) * 100.0

func get_save_data() -> Dictionary:
	return {
		"xp": xp
	}

func load_save_data(data: Dictionary):
	if data.is_empty(): return
	xp = float(data.get("xp", 0.0))
	check_level_up()

func reset(decay_factor: float = 1.0) -> void:
	xp *= (1.0 - decay_factor)
	# Level will be recalculated by check_level_up
	level = 1
	check_level_up()
