extends Node
# Renders the real game, opens the Ship Designer, saves a PNG of the frame.
# Ground truth for "what does the designer actually look like at design res".
# Run with a REAL renderer (not --headless) + backup/restore the save around it.
#   Godot --path . --resolution 1280x720 res://scenes/designer_shot.tscn
func _ready() -> void:
	var m: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.call_deferred("add_child", m)
	for _i in range(40):
		await get_tree().process_frame
	get_tree().current_scene = m
	# Suppress the coach tour so the shot shows the page, not the overlay.
	var cs: Dictionary = GameState.game_settings.get("coach_seen", {})
	cs["designer"] = true
	GameState.game_settings["coach_seen"] = cs
	m.switch_to("designer")
	for _i in range(90):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	var out := OS.get_environment("DSHOT_OUT")
	if out == "":
		out = "user://designer_shot.png"
	var err := img.save_png(out)
	print("[DSHOT] saved=", out, " err=", err, " size=", img.get_width(), "x", img.get_height())
	get_tree().quit(0)
