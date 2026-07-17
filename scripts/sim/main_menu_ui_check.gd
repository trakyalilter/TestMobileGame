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

	print("[MM] checkbox synced to: %s (expect true)" % mm.chk_offline_combat.button_pressed)
	print("[MM] offline_combat still: %s" % GameState.game_settings.get("offline_combat"))
	print("[MM] tree node count  before=%d  after=%d  (delta %d)" % [before, after, after - before])
	print("[MM] SPURIOUS DIALOG ON OPEN: %s" % ("YES — BUG" if after > before else "no — fixed"))
	print("[MM] done")
	get_tree().quit(0)
