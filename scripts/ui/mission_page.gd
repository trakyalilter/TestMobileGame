extends Control

@onready var grid = $VBoxContainer/ScrollContainer/GridContainer

var manager: RefCounted
var widget_scene = preload("res://scenes/ui/mission_widget.tscn")
var widgets = []

func _ready():
	manager = GameState.mission_manager
	if manager:
		manager.mission_updated.connect(refresh_list)
	call_deferred("refresh_list")

func refresh_list():
	if not manager: return
	manager.sync_progress()
	if not grid: return
	for child in grid.get_children():
		child.queue_free()
	widgets.clear()
	
	for mid in manager.active_missions:
		var w = widget_scene.instantiate()
		grid.add_child(w)
		var m_data = manager.missions[mid]
		w.setup(mid, m_data, manager, self)
		widgets.append(w)

func get_coach_anchor(key: String) -> Control:
	if widgets.is_empty():
		return null
	var first = widgets[0]
	match key:
		"first_mission":
			return first
		"claim":
			var cb = first.get("claim_btn")
			return cb if cb is Control else first
	return null

func _process(delta):
	# Widgets update themselves in their _process
	pass
