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

# v134: mission_updated fires on EVERY progress tick (each gather action, each
# kill), and this used to rebuild all cards each time — resetting the scroll
# position every ~3s while a gather mission ran, and freeing widgets mid-hover.
# Only rebuild when the SET of active missions changes (claim/reveal/new-game);
# per-card values self-update in mission_widget._process.
var _built_ids: Array = []

func refresh_list():
	if not manager: return
	manager.sync_progress()
	if not grid: return

	var ids: Array = manager.active_missions.duplicate()
	var unchanged: bool = (ids == _built_ids)
	if unchanged and not widgets.is_empty():
		var w0 = widgets[0]
		# New game re-inits the missions dict with the same id list — the old
		# widgets would keep polling ORPHANED dicts. is_same = reference identity.
		if not is_instance_valid(w0) or not is_same(w0.data, manager.missions.get(w0.mid)):
			unchanged = false
	if unchanged:
		return
	_built_ids = ids

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
