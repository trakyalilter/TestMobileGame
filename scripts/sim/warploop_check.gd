extends Node
# ============================================================================
# WARP INFINITE-LOOP CHECK (v137) — verifies the credits_at_warp_start ordering
# fix. Before the fix, execute_warp snapshotted the prestige baseline BEFORE the
# starter package (shards*5000*mult) was added to lifetime_credits, so post-warp
# progress_score == the starter amount → once cumulative shards ≥ ~56 the starter
# alone cleared the 500k threshold, re-enabling Warp instantly (runaway loop).
# Fix: snapshot AFTER the starter → post-warp progress_score == 0 → gains == 0.
#   Godot --headless --path <root> res://scenes/warploop_check.tscn
# ============================================================================

func _ready() -> void:
	var wm = GameState.warp_manager
	var res = GameState.resources
	GameState.set_process(false)
	GameState.hard_reset()
	# Simulate a player DEEP into prestige — well past the ~56-shard trigger — with
	# enough lifetime credits that a legit warp is available right now.
	wm.credits_at_warp_start = 0.0
	wm.warp_shards = 100
	wm.warp_shards_spent = 0
	wm.total_warps = 6
	res.lifetime_credits = 5_000_000_000.0   # ~14 shards' worth of progress
	var gains_before: int = wm.calculate_warp_gains()
	print("[WARPLOOP] ============ warp infinite-loop check ============")
	print("[WARPLOOP] threshold = %.0f | pre-warp shards=100 lifetime=5B" % wm.get_tree_shard_threshold())
	print("[WARPLOOP] pre-warp gains = %d (expect >0: a legit warp is available)" % gains_before)
	wm.execute_warp()
	var score_after: float = wm.get_progress_score()
	var gains_after: int = wm.calculate_warp_gains()
	print("[WARPLOOP] post-warp: shards=%d total_warps=%d" % [wm.warp_shards, wm.total_warps])
	print("[WARPLOOP] post-warp progress_score = %.0f  (FIX: ~0, must be < threshold)" % score_after)
	print("[WARPLOOP] post-warp gains = %d  (FIX: 0 — Warp NOT instantly re-available)" % gains_after)
	if gains_after == 0:
		print("[WARPLOOP] PASS — infinite warp loop is closed")
	else:
		print("[WARPLOOP] *** FAIL — still re-warpable for %d shards with no play" % gains_after)
	get_tree().quit(0)
