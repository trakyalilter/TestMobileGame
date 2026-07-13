extends Node

# ============================================================================
# RARITY DROP SPIKE — measures the live roll_rarity() distribution + the
# expected kills-to-tier at representative drop_chances, for a clean A/B when
# rebalancing. Samples the REAL shipyard_manager.roll_rarity so it always
# reflects whatever is currently in code.
#
# Run: tools/run_sim.ps1 -Scene "res://scenes/rarity_drop_spike.tscn"
# ============================================================================

const N := 300000

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	GameState.set_process(false)
	GameState.hard_reset()
	seed(4242)
	var sm = GameState.shipyard_manager

	print("[RD] === roll_rarity distribution (%d samples each) ===" % N)
	print("[RD] (TRASH Common = EMPTY roll: no module drops)")
	_measure(sm, false, "TRASH")
	_measure(sm, true,  "BOSS ")

	print("[RD] === expected KILLS to first drop of each tier (trash) ===")
	_kills(sm, 0.10, "e3/e4  dc=0.10       ")
	_kills(sm, 0.25, "e5     dc=0.25       ")
	_kills(sm, 0.3125, "e5+Xeno dc=0.31      ")

	print("[RD] === boss: guaranteed 4-10 module rolls/kill (avg 7) ===")
	_boss_per_kill(sm)

	print("[RD] done")
	get_tree().quit(0)

func _measure(sm, is_boss: bool, label: String) -> void:
	var t := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
	for _i in range(N):
		var r: int = sm.roll_rarity(is_boss)
		t[r] = t[r] + 1
	print("[RD] %s | Common %5.1f%% | Uncommon %5.1f%% | Rare %5.1f%% | Legendary %5.2f%% | Unique %5.2f%%" % [
		label, 100.0 * t[0] / N, 100.0 * t[1] / N, 100.0 * t[2] / N, 100.0 * t[3] / N, 100.0 * t[4] / N])

func _kills(sm, dc: float, label: String) -> void:
	# Per kill: a drop-roll fires with prob dc; if it rolls Common it's EMPTY
	# (no module). Only Uncommon+ is a real drop.
	var cnt := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
	var real_drops := 0
	for _i in range(N):
		if randf() < dc:
			var r: int = sm.roll_rarity(false)
			cnt[r] = cnt[r] + 1
			if r != 0:  # Common = empty
				real_drops += 1
	var any_k: float = float(N) / float(max(1, real_drops))
	var rare_k: float = _kills_for(cnt[2], N)
	var leg_k: float = _kills_for(cnt[3], N)
	print("[RD] %s | real module ~%4.0f kills | Rare ~%s kills | Legendary ~%s kills" % [
		label, any_k, _fmt_k(rare_k), _fmt_k(leg_k)])

func _kills_for(hits: int, total: int) -> float:
	if hits <= 0:
		return -1.0
	return float(total) / float(hits)

func _fmt_k(k: float) -> String:
	return "%.0f" % k if k > 0.0 else "never"

func _boss_per_kill(sm) -> void:
	var kills := int(N / 7)
	var t := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
	for _k in range(kills):
		for _r in range(7):
			var r: int = sm.roll_rarity(true)
			t[r] = t[r] + 1
	print("[RD] avg modules/boss-kill | Rare %.2f | Legendary %.2f | Unique %.3f  (7 rolls/kill)" % [
		float(t[2]) / kills, float(t[3]) / kills, float(t[4]) / kills])
