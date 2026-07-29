extends Node
# ============================================================================
# ANDROID LIFECYCLE CHECK — the pause/resume contract an idle game lives on.
#
#  1) PlatformInfo reports desktop correctly and hands back ZERO safe-area
#     insets off-handheld (a non-zero inset here would pad the desktop shell)
#  2) _process delta CLAMP: a resumed app hands _process the whole absence.
#     Unclamped, managers would pay that out at full active rates on top of
#     the offline payout for the same window. One frame must never bill more
#     than MAX_FRAME_DELTA.
#  3) resume credits the away window as OFFLINE progress (the boot path can't
#     — a pause/resume never re-boots), consumes _bg_unix_time, and announces
#     itself so the offline modal can re-show on a live scene tree
#  4) resume respects the same 24h cap (x warp-tree multiplier) as load_game
#  5) resume below the 10s threshold is a no-op — no modal for a glance at
#     the notification shade
#  6) the playtime clock is re-anchored on resume: get_ticks_msec keeps
#     counting while the OS has us suspended, so without this the absence
#     gets billed as active play time
#
#   Godot --headless --path <root> res://scenes/android_lifecycle_check.tscn
# ============================================================================

func _ready() -> void:
	GameState.set_process(false)
	GameState.hard_reset()
	var fails := 0
	print("[ANDROID] ============ lifecycle check ============")

	# ── 1) PlatformInfo on the desktop path ──
	var handheld: bool = PlatformInfo.is_handheld()
	var insets: Vector4 = PlatformInfo.safe_area_insets(get_viewport())
	var p_ok: bool = (not handheld) and insets == Vector4.ZERO
	print("[ANDROID] 1) platform: handheld=%s insets=%s -> %s"
		% [handheld, insets, "PASS" if p_ok else "FAIL"])
	if not p_ok: fails += 1

	# Insets must also survive a null viewport (called before the tree is up).
	var null_ok: bool = PlatformInfo.safe_area_insets(null) == Vector4.ZERO
	print("[ANDROID] 1b) null-viewport insets -> %s" % ["PASS" if null_ok else "FAIL"])
	if not null_ok: fails += 1

	# ── 2) frame-delta clamp ──
	# occupancy accrues raw `delta` in _process, so it reads back exactly what
	# the clamp let through.
	var occ: Dictionary = GameState.telemetry["occupancy"]
	var before: float = _occ_total(occ)
	GameState._process(3600.0)
	var billed: float = _occ_total(occ) - before
	var ceiling: float = GameState.MAX_FRAME_DELTA * maxf(Engine.time_scale, 1.0)
	var clamp_ok: bool = billed <= ceiling + 0.001
	print("[ANDROID] 2) 3600s frame billed %.3fs (ceiling %.3fs) -> %s"
		% [billed, ceiling, "PASS" if clamp_ok else "FAIL"])
	if not clamp_ok: fails += 1

	# A normal frame must pass through untouched — the clamp is for stalls.
	before = _occ_total(occ)
	GameState._process(0.016)
	var normal: float = _occ_total(occ) - before
	var normal_ok: bool = absf(normal - 0.016) < 0.0001
	print("[ANDROID] 2b) 16ms frame billed %.4fs -> %s"
		% [normal, "PASS" if normal_ok else "FAIL"])
	if not normal_ok: fails += 1

	# ── 3) resume credits the away window ──
	var fired := [false]
	GameState.offline_progress_applied.connect(func(): fired[0] = true)

	GameState.offline_away_sec = 0.0
	GameState._bg_unix_time = Time.get_unix_time_from_system() - 3600.0
	GameState._resume_from_background()
	var away: float = GameState.offline_away_sec
	var resume_ok: bool = absf(away - 3600.0) < 5.0 \
		and fired[0] \
		and GameState._bg_unix_time < 0.0 \
		and not GameState.offline_capped
	print("[ANDROID] 3) 1h resume: away=%.1fs signal=%s consumed=%s -> %s"
		% [away, fired[0], GameState._bg_unix_time < 0.0, "PASS" if resume_ok else "FAIL"])
	if not resume_ok: fails += 1

	# ── 4) resume honours the offline cap ──
	var cap_mult: float = GameState.warp_manager.get_tree_offline_cap_mult()
	var eff_cap: float = GameState.OFFLINE_DELTA_CAP_SECONDS * cap_mult
	GameState.offline_away_sec = 0.0
	GameState.offline_capped = false
	GameState._bg_unix_time = Time.get_unix_time_from_system() - (eff_cap * 3.0)
	GameState._resume_from_background()
	var cap_ok: bool = absf(GameState.offline_away_sec - eff_cap) < 5.0 and GameState.offline_capped
	print("[ANDROID] 4) 3x-cap resume: away=%.0fs (cap %.0fs) capped=%s -> %s"
		% [GameState.offline_away_sec, eff_cap, GameState.offline_capped,
		   "PASS" if cap_ok else "FAIL"])
	if not cap_ok: fails += 1

	# ── 5) a short glance away is a no-op ──
	GameState.offline_away_sec = 0.0
	fired[0] = false
	GameState._bg_unix_time = Time.get_unix_time_from_system() - 5.0
	GameState._resume_from_background()
	var short_ok: bool = GameState.offline_away_sec == 0.0 and not fired[0]
	print("[ANDROID] 5) 5s resume is a no-op -> %s" % ["PASS" if short_ok else "FAIL"])
	if not short_ok: fails += 1

	# Resume with nothing recorded must also do nothing (desktop never pauses).
	fired[0] = false
	GameState._bg_unix_time = -1.0
	GameState._resume_from_background()
	var idle_ok: bool = not fired[0]
	print("[ANDROID] 5b) resume without a recorded pause -> %s" % ["PASS" if idle_ok else "FAIL"])
	if not idle_ok: fails += 1

	# ── 6) playtime clock re-anchored across the absence ──
	GameState.total_playtime = 0.0
	GameState._pt_last_msec = Time.get_ticks_msec() - 3_600_000  # "an hour of ticks"
	GameState._bg_unix_time = Time.get_unix_time_from_system() - 3600.0
	GameState._resume_from_background()
	GameState._process(0.016)
	var pt: float = GameState.total_playtime
	var pt_ok: bool = pt < 60.0
	print("[ANDROID] 6) playtime after 1h suspend: %.1fs (must be ~0) -> %s"
		% [pt, "PASS" if pt_ok else "FAIL"])
	if not pt_ok: fails += 1

	print("[ANDROID] ============ %s ============"
		% ["ALL PASS" if fails == 0 else "%d FAIL" % fails])
	get_tree().quit(0 if fails == 0 else 1)


func _occ_total(occ: Dictionary) -> float:
	var t := 0.0
	for k in occ:
		t += float(occ[k])
	return t
