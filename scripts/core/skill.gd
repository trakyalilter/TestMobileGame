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

# v145: level_up / milestone_unlocked went from zero listeners repo-wide to
# driving player-facing toasts (main.gd::_on_skill_level_up). Three code paths
# REBUILD the level ladder from stored XP rather than earning it — load_save_data,
# reset() after a warp, and the Options debug level-setter — and each would
# machine-gun one toast per level. Silence the ladder while it is being restored;
# `unlocked_milestones` still fills so is_milestone_unlocked() stays correct.
var _silent_level_replay: bool = false

# Recompute `level` from `xp` WITHOUT firing the player-facing beats. Any caller
# that is restoring state rather than granting a level must use this.
#
# v174: `unlocked_milestones` is derived from xp exactly like `level` is (it is
# not saved -- load_save_data rebuilds it from xp alone), so it has to be rebuilt
# here too. _check_milestones only ever APPENDS, so leaving the old array in
# place meant a rebuild that LOWERED the level kept every milestone above it:
# after a warp (30% XP keep, ~12 levels down) processing kept its milestone-10
# and -25 speed multipliers and its milestone-50 double-output roll, and
# infrastructure kept its milestone-10 bonus, for the rest of the session. It
# also swallowed the toast on re-crossing, since the milestone was already in
# the array. Clearing first makes both correct, and costs one re-derive of an
# at-most-5-entry array on the three paths that call this.
# Both derived fields are rebuilt FROM SCRATCH here rather than trusting whatever
# the caller left behind. check_level_up() can only ratchet upward, so a rebuild
# that should LOWER the level (a warp, or loading a lower save over a live one)
# needs the floor reset first -- otherwise the while loop breaks immediately, the
# level stays where it was, and the cleared milestone array never refills.
func rebuild_level_silently() -> void:
	_silent_level_replay = true
	level = 1
	unlocked_milestones.clear()
	check_level_up()
	_silent_level_replay = false

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
	# v107a: clamp on max_level, NOT on xp_table size. The XP table runs to 120
	# while the cap is 100; the old loop keyed off "next_level in xp_table", so
	# once a skill hit 100 it kept ratcheting up to 120 (one level per add_xp).
	# Loop while strictly below the cap so level can never exceed max_level.
	while level < max_level:
		var next_level = level + 1
		if not next_level in xp_table:
			break
		if xp < xp_table[next_level]:
			break
		level += 1
		if not _silent_level_replay:
			level_up.emit(level)
		_check_milestones(level)

func _check_milestones(new_lvl: int):
	# v107: 100 added as the capstone milestone — P1 Mastery hooks this to
	# award the gold-card cosmetic (Hearthstone-style golden header treatment
	# on the maxed skill's card).
	for m in [10, 25, 50, 75, 100]:
		if new_lvl >= m and not m in unlocked_milestones:
			unlocked_milestones.append(m)
			if not _silent_level_replay:
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
	rebuild_level_silently()  # v145: restoring a save is not 60 level-ups

func reset(decay_factor: float = 1.0) -> void:
	xp *= (1.0 - decay_factor)
	# v145: a warp re-derives the retained level from decayed XP — the player did
	# not just re-earn every level, so the beats stay silent here too. v174: the
	# rebuild resets the level floor and the milestone array itself.
	rebuild_level_silently()
