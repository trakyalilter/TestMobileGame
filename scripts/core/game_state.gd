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
var fleet_manager : RefCounted
var warp_manager : RefCounted
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
	fleet_manager = load("res://scripts/managers/fleet_manager.gd").new()
	warp_manager = load("res://scripts/managers/warp_manager.gd").new()
	
	mission_manager.connect_signals()
	
	load_game()

func _process(delta):
	# 1. Background Automation (Infrastructure & Fleet)
	if infrastructure_manager: infrastructure_manager.process_tick(delta)
	if fleet_manager: fleet_manager.process_tick(delta)
	
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

func set_active_manager(manager):
	if active_manager and active_manager != manager:
		active_manager.stop_action()
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
		"fleet": fleet_manager.get_save_data_manager(),
		"prestige": warp_manager.get_save_data_manager(),
		"game_settings": game_settings,  # v52.1
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
		fleet_manager.load_save_data_manager(data.get("fleet", {}))
		warp_manager.load_save_data_manager(data.get("prestige", {}))
		
		# v52.1: Load game settings
		var saved_settings = data.get("game_settings", {})
		for key in saved_settings:
			game_settings[key] = saved_settings[key]
		
		# Restore Active Manager
		if gathering_manager.is_active:
			set_active_manager(gathering_manager)
		elif processing_manager.is_active:
			set_active_manager(processing_manager)
		elif research_manager.is_active:
			set_active_manager(research_manager)
		elif combat_manager.in_combat:
			set_active_manager(combat_manager)
			
		# Offline Progress
		var last_time = data.get("last_save_time", Time.get_unix_time_from_system())
		var current_time = Time.get_unix_time_from_system()
		var delta = current_time - last_time
		
		if delta > 10:
			process_offline_progress(delta)
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
	
	var fl_report = fleet_manager.calculate_offline(delta)
	if fl_report: reports.append(fl_report)
	
	# v52.1: Optional offline combat
	if game_settings.get("offline_combat", false):
		var c_report = combat_manager.calculate_offline(delta)
		if c_report: reports.append(c_report)
	
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
	fleet_manager.reset()
	# ... others
	
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
