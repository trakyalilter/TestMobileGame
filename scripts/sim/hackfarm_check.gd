extends Node
# ============================================================================
# HACK-CARD ANTI-FARM CHECK (v137) — verifies the progression-relative taper on
# _roll_hack_stone_drops kills the "strong player farms trivial low zones for
# enormous Hack Card yield" exploit, while leaving frontier content at full rate.
# Samples the SpliceChip roll (base 25%) at a spread of zones for a frontier-Z10
# player and compares empirical vs expected drop rate. Also confirms the
# firmware_hacking research gate still zeroes drops. Same path online + offline.
#   Godot --headless --path <root> res://scenes/hackfarm_check.tscn
# ============================================================================

const SAMPLES := 40000

func _ready() -> void:
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.set_process(false)
	GameState.hard_reset()
	# Unlock everything → frontier = highest regular zone (Z10; Z11/Z12 are flag-gated
	# and stay locked after hard_reset), firmware_hacking on so drops fire.
	for tid in rm.tech_tree:
		if not (tid in rm.unlocked_techs):
			rm.unlocked_techs.append(tid)
	var frontier: int = cm._player_frontier_zone()
	print("[HACKFARM] ============ Hack-Card anti-farm taper ============")
	print("[HACKFARM] frontier zone = %d (expect 10) | SpliceChip base = 25%%" % frontier)
	print("[HACKFARM] taper = clamp(1 - 0.30*(gap-2), 0.10, 1.0),  gap = frontier - zone")
	print("[HACKFARM] zone | gap | expected | empirical (n=%d)" % SAMPLES)
	for zone in [10, 9, 8, 6, 4, 2]:
		var gap: int = frontier - zone
		var relevance: float = clampf(1.0 - 0.30 * float(gap - 2), 0.10, 1.0)
		var expected: float = 0.25 * relevance
		var hits: int = 0
		for _i in range(SAMPLES):
			if cm._roll_hack_stone_drops(zone, false, false).has("SpliceChip"):
				hits += 1
		var emp: float = float(hits) / float(SAMPLES)
		var tag: String = "  <- the exploit" if zone == 2 else ""
		print("[HACKFARM] Z%-2d | gap %-2d | exp %5.2f%% | emp %5.2f%%%s" % [zone, gap, expected * 100.0, emp * 100.0, tag])
	# Gate: no firmware_hacking → zero drops (research gate intact).
	rm.unlocked_techs.erase("firmware_hacking")
	var gate_hits: int = 0
	for _i in range(2000):
		if not cm._roll_hack_stone_drops(10, false, false).is_empty():
			gate_hits += 1
	print("[HACKFARM] gate: firmware_hacking OFF -> %d/2000 drops (expect 0)" % gate_hits)
	print("[HACKFARM] ===================================================")
	get_tree().quit(0)
