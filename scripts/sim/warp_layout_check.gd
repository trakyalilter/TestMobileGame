extends Node
# ============================================================================
# WARP PAGE LAYOUT CHECK (v140) — geometry regression guard for the two-column
# Warp Core page. The v124b single-stack layout starved the Mastery Tree: four
# stacked panels ate the viewport and the tree's node area was left ~187px, so
# every branch scrolled and card rows clipped mid-text. v140 moved the tree into
# a full-height right column beside a fixed-width status rail.
#
# This asserts SIZES, not logic — it catches "a panel grew and squeezed the tree
# again" on the next balance/UI pass.
#
# NOTE ON LOCALE: Localization is english-as-key and every label resolves tr() at
# BUILD time, so flipping TranslationServer after the page exists does NOT re-flow
# text. Each locale therefore gets a FRESH page instance. Turkish runs ~25% longer
# than English and the rail is the tight axis, so EN passing is not evidence TR does.
#   Godot --headless --path <root> res://scenes/warp_layout_check.tscn
# ============================================================================

const PAGE_H := 688.0   # 720 viewport - 16px top/bottom page padding

var fails := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond: fails += 1
	print("[WARPUI] %-44s %s %s" % [name, "OK" if cond else "*** FAIL", detail])


func _find(n: Node, cls: String, want_name: String = "") -> Node:
	if n.get_class() == cls and (want_name == "" or n.name == want_name):
		return n
	for c in n.get_children():
		var r = _find(c, cls, want_name)
		if r != null:
			return r
	return null


# Fresh page under a given locale + warp state. Locale must be set BEFORE the
# instance is built (see NOTE ON LOCALE above).
func _build_page(locale: String, warps: int) -> Control:
	TranslationServer.set_locale(locale)
	var wm = GameState.warp_manager
	wm.total_warps = warps
	wm.warp_shards = 13.0 if warps > 0 else 0.0

	var root := Control.new()
	root.size = Vector2(1280, 720)
	add_child(root)
	var page = preload("res://scenes/ui/warp_page.tscn").instantiate()
	root.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	await get_tree().process_frame
	return page


func _ready() -> void:
	GameState.set_process(false)
	GameState.hard_reset()

	print("[WARPUI] ============ warp page layout (1280x720) ============")

	# ── A. Structure + the dominant-zone claim (post-warp EN) ──
	var page: Control = await _build_page("en", 3)
	var shell := _find(page, "HBoxContainer", "WarpShell") as Control
	var rail := _find(page, "VBoxContainer", "WarpRail") as Control
	_ok("shell exists", shell != null)
	_ok("rail exists", rail != null)
	if shell == null or rail == null:
		get_tree().quit(1)
		return
	var tree_panel: Control = page._tree_panel
	_ok("tree panel exists", tree_panel != null)
	print("[WARPUI]   rail = %s   tree = %s" % [str(rail.size), str(tree_panel.size)])
	_ok("tree taller than 600px", tree_panel.size.y > 600.0, "y=%.0f" % tree_panel.size.y)
	_ok("tree wider than rail", tree_panel.size.x > rail.size.x, "%.0f vs %.0f" % [tree_panel.size.x, rail.size.x])
	_ok("tree >= 60% of page width", tree_panel.size.x >= 1248.0 * 0.60, "%.0f" % tree_panel.size.x)

	var scroll := _find(tree_panel, "ScrollContainer") as ScrollContainer
	_ok("node scroll exists", scroll != null)
	if scroll != null:
		print("[WARPUI]   node viewport height = %.0f  (was ~187 pre-v140)" % scroll.size.y)
		_ok("node viewport > 500px", scroll.size.y > 500.0, "y=%.0f" % scroll.size.y)

	# ── B. Per locale: no rail overflow, no branch scroll, cards stay readable ──
	# Both warp states matter: the FIRST WARP teaching panel is only in the rail
	# while total_warps == 0, which is the taller (tighter) configuration.
	for loc in ["en", "tr"]:
		for warps in [0, 3]:
			var p: Control = await _build_page(loc, warps)
			var r := _find(p, "VBoxContainer", "WarpRail") as Control
			var tp: Control = p._tree_panel
			var sc := _find(tp, "ScrollContainer") as ScrollContainer
			var tag := "%s/warps=%d" % [loc, warps]

			# Rail has no scrollbar — its content MUST fit the page height.
			var need: float = r.get_combined_minimum_size().y
			print("[WARPUI]   [%s] rail need %.0f / %.0f" % [tag, need, PAGE_H])
			_ok("rail fits [%s]" % tag, need <= PAGE_H, "needs %.0f / has %.0f" % [need, PAGE_H])
			# The rail has no scrollbar: overflow CLIPS silently rather than scrolling.
			# The fresh-player state runs close to the ceiling, so shout before a future
			# copy edit (one more wrapped line ~= 13px) pushes it over the edge.
			if need <= PAGE_H and PAGE_H - need < 24.0:
				print("[WARPUI]   !! TIGHT [%s]: only %.0fpx rail headroom — adding a line here will clip" % [tag, PAGE_H - need])

			# No rail child may exceed the rail width (horizontal overflow clips).
			for child in r.get_children():
				var c := child as Control
				if c == null or not c.visible:
					continue
				_ok("rail child fits [%s] %s" % [tag, c.name], c.size.x <= r.size.x + 1.0,
					"%.0f <= %.0f" % [c.size.x, r.size.x])

			# THE REGRESSION THIS GUARDS: every branch fits without scrolling.
			# Only REVEALED branches are measurable — an unrevealed branch hides its
			# grid and shows the lock message, and a hidden Control is never laid out
			# (its combined_minimum_size reports unwrapped garbage, not real geometry).
			var wm2 = GameState.warp_manager
			var measured := 0
			for branch_id in ["engineering", "combat", "recursion"]:
				if not wm2.is_branch_revealed(branch_id):
					continue
				p._show_branch(branch_id)
				await get_tree().process_frame
				await get_tree().process_frame
				var grid: Control = p._branch_grids[branch_id]
				var gneed: float = grid.get_combined_minimum_size().y
				_ok("%s unscrolled [%s]" % [branch_id, tag], gneed <= sc.size.y,
					"needs %.0f / has %.0f" % [gneed, sc.size.y])
				measured += 1

			if measured == 0:
				# Fresh player: nothing revealed, so the tree must show the lock copy.
				_ok("lock message shown [%s]" % tag, p._lock_msg != null and p._lock_msg.visible)
				continue

			# Cards must stay wide enough that a desc doesn't shred into 3+ lines.
			p._show_branch("engineering")
			await get_tree().process_frame
			await get_tree().process_frame
			for nid in p._node_widgets:
				var w: Control = p._node_widgets[nid]["root"]
				if w.visible and w.size.x > 0.0:
					_ok("card >= 380px [%s]" % tag, w.size.x >= 380.0, "%.0f" % w.size.x)
					break

	TranslationServer.set_locale("en")
	print("[WARPUI] ============ %s ============" % ("ALL PASS" if fails == 0 else "%d FAIL(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
