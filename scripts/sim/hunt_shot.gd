extends Node
# Renders the real game, opens the Hunt Log, saves a PNG. Ground truth for
# "what does the page actually look like". Mirrors designer_shot.
#   HSHOT_OUT=<path> Godot --path . res://scenes/hunt_shot.tscn
func _ready() -> void:
	var m: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(m)
	for _i in range(40):
		await get_tree().process_frame
	get_tree().current_scene = m
	var cs: Dictionary = GameState.game_settings.get("coach_seen", {})
	cs["hunt"] = true
	GameState.game_settings["coach_seen"] = cs
	if "offline_modal" in m and m.offline_modal != null and is_instance_valid(m.offline_modal):
		m.offline_modal.visible = false
	# Seed a spread of ranks so the shot shows earned + unearned stars together.
	var cm = GameState.combat_manager
	cm.enemy_kills["z1_lunar_drone"] = 640
	cm.enemy_kills["z1_boss_architect"] = 30
	m.switch_to("hunt")
	for _i in range(60):
		await get_tree().process_frame
	if "offline_modal" in m and m.offline_modal != null and is_instance_valid(m.offline_modal):
		m.offline_modal.visible = false
	for _i in range(20):
		await get_tree().process_frame
	var out := OS.get_environment("HSHOT_OUT")
	if out == "":
		out = "user://hunt_page.png"
	var img: Image = get_viewport().get_texture().get_image()
	print("[HSHOT] saved=", out, " err=", img.save_png(out))
	get_tree().quit(0)
