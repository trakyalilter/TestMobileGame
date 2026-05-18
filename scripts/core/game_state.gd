extends Node

# Core Systems
var resources : Node

signal game_resetted
signal game_loaded

# Managers
var gathering_manager : RefCounted
var processing_manager : RefCounted
var infrastructure_manager : RefCounted
var shipyard_manager : RefCounted
var research_manager : RefCounted
var combat_manager : RefCounted
var mission_manager : RefCounted
var warp_manager : RefCounted
var bounty_manager : RefCounted
var quest_manager : RefCounted
# var processing_manager
# var mission_manager
# var combat_manager
# var infrastructure_manager
# var shipyard_manager

var active_manager : RefCounted = null
var was_resetted: bool = false

var offline_report: String = ""
var elements_db: Array = []

# v52.1: Game Settings (opt-in features)
var game_settings: Dictionary = {
	"offline_combat": false  # Disabled by default
}

# Auto-save
var time_since_save: float = 0.0
const PROD_SAVE_INTERVAL: float = 60.0

# P2.7: Global offline cap. Generous (24h) but finite — gathering/processing/
# infrastructure offline accrual was previously unbounded, both an economy
# exploit and a startup-stall risk (AUDIT_LOG AUD-P0-004). Tune here.
const OFFLINE_DELTA_CAP_SECONDS: float = 86400.0

# Total active play time: real wall-clock seconds the game has been open.
# Measured off the system clock so Engine.time_scale (game-speed) can't
# inflate it. Persisted across sessions; reset only on a full New Game.
var total_playtime: float = 0.0
var _pt_last_msec: int = 0

func _ready():
	# Initialize Resources
	var res_script = load("res://scripts/core/resources.gd")
	resources = res_script.new()
	add_child(resources)
	
	load_elements_db()
	
	# Initialize Managers
	gathering_manager = load("res://scripts/managers/gathering_manager.gd").new()
	processing_manager = load("res://scripts/managers/processing_manager.gd").new()
	infrastructure_manager = load("res://scripts/managers/infrastructure_manager.gd").new()
	shipyard_manager = load("res://scripts/managers/shipyard_manager.gd").new()
	research_manager = load("res://scripts/managers/research_manager.gd").new()
	combat_manager = load("res://scripts/managers/combat_manager.gd").new()
	mission_manager = load("res://scripts/managers/mission_manager.gd").new()
	warp_manager = load("res://scripts/managers/warp_manager.gd").new()
	bounty_manager = load("res://scripts/managers/bounty_manager.gd").new()
	quest_manager = load("res://scripts/managers/quest_manager.gd").new()

	mission_manager.connect_signals()
	bounty_manager.connect_signals()
	quest_manager.connect_signals()
	
	load_game()

func _process(delta):
	# 0. Total play time (real clock — immune to game-speed scaling)
	var now_ms := Time.get_ticks_msec()
	if _pt_last_msec == 0:
		_pt_last_msec = now_ms
	total_playtime += float(now_ms - _pt_last_msec) / 1000.0
	_pt_last_msec = now_ms

	# 1. Background Automation (Infrastructure)
	if infrastructure_manager: infrastructure_manager.process_tick(delta)
	if bounty_manager: bounty_manager.process_tick(delta)
	
	# 2. Active Foreground Task
	# In Python it was one active manager. 
	# In Godot we can stick to that or allow parallel.
	# Sticking to single active manager for now as per Python logic
	if active_manager:
		active_manager.process_tick(delta)
		
	# Auto-save
	time_since_save += delta
	if time_since_save >= PROD_SAVE_INTERVAL:
		save_game()
		time_since_save = 0.0

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		save_game()

func _task_label(m) -> String:
	if m == gathering_manager: return "Mining"
	if m == processing_manager: return "Engineering"
	if m == research_manager: return "Research"
	if m == combat_manager: return "Combat"
	return "Task"

func set_active_manager(manager):
	if active_manager and active_manager != manager:
		active_manager.stop_action()
		# Only one foreground task runs at a time — make the swap visible so
		# the player isn't left wondering why their last task "stopped".
		UITheme.show_notification("%s paused — now %s" % [_task_label(active_manager), _task_label(manager)], Color(1.0, 0.82, 0.35))
	active_manager = manager

func save_game():
	var save_data = {
		"version": 1, # Audit v1.0: Added versioning
		"resources": resources.get_save_data(),
		"gathering": gathering_manager.get_save_data_manager(),
		"processing": processing_manager.get_save_data_manager(),
		"infrastructure": infrastructure_manager.get_save_data_manager(),
		"shipyard": shipyard_manager.get_save_data_manager(),
		"research": research_manager.get_save_data_manager(),
		"combat": combat_manager.get_save_data_manager(),
		"mission": mission_manager.get_save_data_manager(),
		"prestige": warp_manager.get_save_data_manager(),
		"bounty": bounty_manager.get_save_data_manager(),
		"quest": quest_manager.get_save_data_manager(),
		"game_settings": game_settings,  # v52.1
		"total_playtime": total_playtime,
		"last_save_time": Time.get_unix_time_from_system()
	}
	
	# P0 Fix: Atomic Save Pattern
	var path_final = "user://savegame.json"
	var path_temp = "user://savegame.tmp"
	var path_bak = "user://savegame.bak"
	
	var file = FileAccess.open(path_temp, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close() # Ensure flush
		
		# Verify temp file exists
		if FileAccess.file_exists(path_temp):
			# Backup existing save
			if FileAccess.file_exists(path_final):
				var err = DirAccess.copy_absolute(path_final, path_bak)
				if err != OK: print("Warning: Backup failed.")
			
			# Atomic Rename
			var err = DirAccess.rename_absolute(path_temp, path_final)
			if err == OK:
				print("Game Saved Atomically.")
			else:
				print("CRITICAL: Failed to rename temp save file. Error: ", err)
		else:
			print("CRITICAL: Temp save file creation failed.")
	else:
		print("Failed to open temp save file.")

func migrate_save(data: Dictionary, from_version: int) -> Dictionary:
	print("Migrating save from v%d..." % from_version)
	# v0 -> v1 (Initial Versioning)
	data["version"] = 1
	return data

func load_game():
	if not FileAccess.file_exists("user://savegame.json"):
		return
		
	var file = FileAccess.open("user://savegame.json", FileAccess.READ)
	var content = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(content)
	
	if error == OK:
		var data = json.data
		
		# Version Check & Migration
		var ver = data.get("version", 0)
		if ver < 1:
			data = migrate_save(data, ver)
			
		resources.load_save_data(data.get("resources", {}))
		gathering_manager.load_save_data_manager(data.get("gathering", {}))
		infrastructure_manager.load_save_data_manager(data.get("infrastructure", {}))
		research_manager.load_save_data_manager(data.get("research", {}))
		processing_manager.load_save_data_manager(data.get("processing", {}))
		
		# Shipyard depends on research and processing for capacity scaling!
		shipyard_manager.load_save_data_manager(data.get("shipyard", {}))
		
		combat_manager.load_save_data_manager(data.get("combat", {}))
		mission_manager.load_save_data_manager(data.get("mission", {}))
		warp_manager.load_save_data_manager(data.get("prestige", {}))
		bounty_manager.load_save_data_manager(data.get("bounty", {}))
		quest_manager.load_save_data_manager(data.get("quest", {}))
		
		# v52.1: Load game settings
		var saved_settings = data.get("game_settings", {})
		for key in saved_settings:
			game_settings[key] = saved_settings[key]

		# Restore lifetime play time (defaults to 0 for pre-existing saves).
		# Re-anchor the clock so the load gap isn't counted as play time.
		total_playtime = float(data.get("total_playtime", 0.0))
		_pt_last_msec = Time.get_ticks_msec()
		
		# Restore Active Manager
		var offline_combat_enabled = game_settings.get("offline_combat", false)
		
		if gathering_manager.is_active:
			set_active_manager(gathering_manager)
		elif processing_manager.is_active:
			set_active_manager(processing_manager)
		elif research_manager.is_active:
			set_active_manager(research_manager)
		elif combat_manager.in_combat:
			if offline_combat_enabled:
				set_active_manager(combat_manager)
			else:
				# If offline combat is disabled, stop combat upon offline load.
				combat_manager.stop_action()
			
		# Offline Progress
		var last_time = data.get("last_save_time", Time.get_unix_time_from_system())
		var current_time = Time.get_unix_time_from_system()
		var delta = current_time - last_time
		
		if delta > 10:
			var capped_delta = min(delta, OFFLINE_DELTA_CAP_SECONDS)
			process_offline_progress(capped_delta)
			# Transparency: never silently swallow time — tell the returning
			# player their earnings were capped so it doesn't feel like a bug.
			if delta > OFFLINE_DELTA_CAP_SECONDS and offline_report != "":
				var cap_hrs = int(OFFLINE_DELTA_CAP_SECONDS / 3600.0)
				offline_report = "Offline earnings are capped at %d hours.\n\n%s" % [cap_hrs, offline_report]
	else:
		print("JSON Parse Error: ", json.get_error_message())
	
	game_loaded.emit()

func process_offline_progress(delta: float):
	print("Processing offline progress for ", delta, " seconds.")
	var reports = []
	
	var g_report = gathering_manager.calculate_offline(delta)
	if g_report: reports.append(g_report)
	
	var p_report = processing_manager.calculate_offline(delta)
	if p_report: reports.append(p_report)

	var i_report = infrastructure_manager.calculate_offline(delta)
	if i_report: reports.append(i_report)
	
	var r_report = research_manager.calculate_offline(delta)
	if r_report: reports.append(r_report)
	
	# v52.1: Optional offline combat
	if game_settings.get("offline_combat", false):
		var c_report = combat_manager.calculate_offline(delta)
		if c_report: reports.append(c_report)
	elif combat_manager.in_combat:
		# Player left mid-fight with offline combat off — explain the silence
		# instead of letting them think combat is broken.
		reports.append("Combat was paused while you were away. Turn on Offline Combat in Options to keep fighting offline.")
	
	if not reports.is_empty():
		offline_report = "\n\n".join(reports)
	else:
		offline_report = ""

func hard_reset():
	resources.reset()
	gathering_manager.reset()
	processing_manager.reset()
	infrastructure_manager.reset()
	shipyard_manager.reset()
	research_manager.reset()
	combat_manager.reset()
	mission_manager.reset()
	if quest_manager: quest_manager.reset()
	# ... others

	# Re-show first-visit page tours on a fresh playthrough
	game_settings["coach_seen"] = {}

	# New Game = brand new lifetime clock (Warp prestige does NOT reset this)
	total_playtime = 0.0
	_pt_last_msec = Time.get_ticks_msec()

	was_resetted = true
	game_resetted.emit()
	
	if FileAccess.file_exists("user://savegame.json"):
		DirAccess.remove_absolute("user://savegame.json")

func load_elements_db():
	var file = FileAccess.open("res://assets/elements.json", FileAccess.READ)
	if file:
		var content = file.get_as_text()
		var json = JSON.new()
		var error = json.parse(content)
		if error == OK:
			elements_db = json.data
			print("Loaded elements_db: ", elements_db.size(), " entries.")
		else:
			print("Failed to parse elements.json: ", json.get_error_message())
	else:
		print("Failed to open res://assets/elements.json")

func get_element_data(symbol: String) -> Dictionary:
	for element in elements_db:
		if element.get("symbol") == symbol:
			return element
	return {}
