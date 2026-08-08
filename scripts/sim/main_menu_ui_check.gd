extends Node

# Reproduces the "opening Settings pops the offline-combat dialog" bug and confirms
# the fix. Simulates a save with offline combat ENABLED but not yet warned — the exact
# state where _on_options_pressed()'s checkbox-sync spuriously fires the toggle handler.
# Run: tools/run_sim.ps1 -Scene "res://scenes/main_menu_ui_check.tscn"

func _ready() -> void:
	call_deferred("_boot")

func _count_windows(n: Node, arr: Array) -> void:
	if n is Window and not (n is Viewport):
		arr.append(n)
	for c in n.get_children():
		_count_windows(c, arr)

func _boot() -> void:
	GameState.game_settings["offline_combat"] = true
	GameState.game_settings["offline_combat_warned"] = false

	var mm = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)
	await get_tree().process_frame
	await get_tree().process_frame

	# Count ALL nodes (the warning is a Control modal on ModalLayer, not a Window),
	# so any node-count increase from opening Settings = a spurious dialog spawned.
	var before: int = get_tree().get_node_count()
	mm._on_options_pressed()   # open Settings
	await get_tree().process_frame
	var after: int = get_tree().get_node_count()

	# v174: this read mm.chk_offline_combat, the CheckBox that v161 replaced with a
	# segmented pill. The property access errored before the quit below, so the
	# scene hung to timeout and BOTH assertions stopped being checked -- the probe
	# looked like a failing guard while the thing it guards was fine.
	var shown = UITheme.get_pill_value(mm.pill_offline_combat)
	var setting: bool = bool(GameState.game_settings.get("offline_combat", false))
	var fails: int = 0

	print("[MM] pill shows: %s   setting: %s" % [str(shown), str(setting)])
	if shown != setting:
		print("[MM] FAIL: opening Settings left the pill out of sync with offline_combat")
		fails += 1

	# The bug this scene exists for: the sync used to invoke the toggle handler,
	# which fired the consent dialog just for OPENING Settings. Count all nodes --
	# the warning is a Control on ModalLayer, not a Window.
	print("[MM] tree node count  before=%d  after=%d  (delta %d)" % [before, after, after - before])
	if after > before:
		print("[MM] FAIL: spurious dialog spawned on opening Settings (delta %d)" % (after - before))
		fails += 1

	# offline_combat_warned must still be false: nothing consented on our behalf.
	if bool(GameState.game_settings.get("offline_combat_warned", false)):
		print("[MM] FAIL: offline_combat_warned got set by merely opening Settings")
		fails += 1

	print("[MM] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
