extends Node
# Faithful repro without the probe destroying itself: add main under root AND
# assign it as current_scene (change_scene_to_file would free this node while it
# is still awaiting, which produces its own "deleted while awaiting" flood).
func _ready() -> void:
	print("[DOC] display=", DisplayServer.get_name())
	var m: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.call_deferred("add_child", m)
	for _i in range(40):
		await get_tree().process_frame
	get_tree().current_scene = m
	if OS.get_cmdline_user_args().has("--nocoach"):
		var cs: Dictionary = GameState.game_settings.get("coach_seen", {})
		cs["designer"] = true
		GameState.game_settings["coach_seen"] = cs
		print("[DOC] coach suppressed")
	print("[DOC] current_scene=", get_tree().current_scene.name, " pages=", m.pages.size())
	print("[DOC] making designer visible WITHOUT switch_to...")
	m.pages["designer"].visible = true
	for _i in range(60):
		await get_tree().process_frame
	print("[DOC] SURVIVED raw visible=true")
	for target in ["designer","shipyard","designer","inventory","designer","atlas","combat","designer"]:
		print("[DOC] --- switch_to(%s) ---" % target)
		m.switch_to(target)
		for _i in range(60):
			await get_tree().process_frame
		print("[DOC] survived %s" % target)
	print("[DOC] ALL SURVIVED")
	get_tree().quit(0)
