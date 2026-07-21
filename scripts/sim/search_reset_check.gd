extends Node
# ============================================================================
# ENGINEERING SEARCH-RESET CHECK (v139i) — owner request: typing in the
# Engineering (processing) page's output search, then switching pages, must
# reset the search. switch_to() toggles page.visible, so the page clears its
# search on visibility_changed(hide). Asserts the real page end-to-end:
#   - a search filters the recipe list (tab strip hidden)
#   - hiding the page (page switch) clears the text AND restores the tab view
#   - showing it again leaves it clear (no re-filter)
#   Godot --headless --path <root> res://scenes/search_reset_check.tscn
# ============================================================================

var fails := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond: fails += 1
	print("[SEARCHRST] %-44s %s %s" % [name, "OK" if cond else "*** FAIL", detail])

func _ready() -> void:
	print("[SEARCHRST] ===== engineering search-reset check =====")
	GameState.set_process(false)

	var page = load("res://scenes/ui/processing_page.tscn").instantiate()
	add_child(page)                       # triggers _ready (builds tabs + search bar)
	await get_tree().process_frame
	await get_tree().process_frame

	_ok("search bar built", page._search_bar != null)

	# Type a query and apply it (mirrors the text_changed -> _apply_search path).
	page._search_bar.text = "Steel"
	page._apply_search("Steel")
	_ok("search filters (tab strip hidden)", page._search_bar.text == "Steel" and not page._tab_strip.visible)

	# Switch away: switch_to() sets page.visible = false -> visibility_changed(hide).
	page.visible = false
	await get_tree().process_frame
	_ok("text cleared on page switch", page._search_bar.text == "")
	_ok("tab view restored (strip visible)", page._tab_strip.visible)

	# Come back: still clear, not re-filtered.
	page.visible = true
	await get_tree().process_frame
	_ok("still clear after returning", page._search_bar.text == "")

	# Leaving with an EMPTY search must be a safe no-op.
	page.visible = false
	await get_tree().process_frame
	_ok("empty-search hide is a no-op", page._search_bar.text == "")

	print("[SEARCHRST] %s" % ("ALL PASS" if fails == 0 else "*** %d FAILURE(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
