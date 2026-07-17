extends Control

var manager: RefCounted
var card_scene = preload("res://scenes/ui/bounty_contract_card.tscn")

@onready var available_container = $Dashboard/HBox/AvailablePanel/VBox/Scroll/AvailableList
@onready var active_container = $Dashboard/HBox/ActivePanel/VBox/Scroll/ActiveList
@onready var timer_lbl = $Dashboard/HBox/AvailablePanel/VBox/RefreshHBox/TimerLabel
@onready var refresh_btn = $Dashboard/HBox/AvailablePanel/VBox/RefreshHBox/RefreshBtn
@onready var stats_lbl = $Dashboard/HBox/ActivePanel/VBox/StatsLabel

# v139: per-zone boards — a tab strip of unlocked zones filters the available list.
# Built programmatically (no .tscn surgery); locked zones simply have no tab.
var _tab_scroll: ScrollContainer = null
var _zone_tabs: HBoxContainer = null
var _tab_zone_ids: Array = []
var _active_zone: String = ""

func _ready():
	manager = GameState.bounty_manager
	if manager:
		manager.bounty_updated.connect(_refresh_ui)
		refresh_btn.pressed.connect(_on_refresh_pressed)
	_build_zone_tabs()
	_refresh_ui()

func get_coach_anchor(key: String) -> Control:
	match key:
		"available":
			return available_container
		"active":
			return active_container
	return null

func _build_zone_tabs():
	var vbox = $Dashboard/HBox/AvailablePanel/VBox
	_tab_scroll = ScrollContainer.new()
	_tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tab_scroll.custom_minimum_size = Vector2(0, 36)
	_zone_tabs = HBoxContainer.new()
	_zone_tabs.add_theme_constant_override("separation", 4)
	_tab_scroll.add_child(_zone_tabs)
	vbox.add_child(_tab_scroll)
	vbox.move_child(_tab_scroll, 1)  # right under the BOUNTY BOARD header
	_rebuild_zone_tabs()

func _rebuild_zone_tabs():
	if not manager or _zone_tabs == null: return
	var zones: Array = manager.get_unlocked_zones()
	var ids: Array = []
	for z in zones:
		ids.append(z["id"])
	# Roster unchanged → just keep the active-tab highlight fresh.
	if ids == _tab_zone_ids and _zone_tabs.get_child_count() > 0:
		_restyle_tabs()
		return
	_tab_zone_ids = ids
	for c in _zone_tabs.get_children():
		c.queue_free()
	# Default to the frontier (highest difficulty) — that's where the player lives.
	if _active_zone == "" or not ids.has(_active_zone):
		_active_zone = ids.back() if ids.size() > 0 else ""
	for z in zones:
		var btn = Button.new()
		btn.text = z["name"]
		btn.tooltip_text = tr("Sector difficulty %d") % z["difficulty"]
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(_on_zone_tab_pressed.bind(z["id"]))
		_zone_tabs.add_child(btn)
	_restyle_tabs()

func _restyle_tabs():
	for i in range(_zone_tabs.get_child_count()):
		var btn = _zone_tabs.get_child(i)
		if btn is Button and i < _tab_zone_ids.size():
			UITheme.apply_sidebar_button_style(btn, _tab_zone_ids[i] == _active_zone)

func _on_zone_tab_pressed(zone_id: String):
	_active_zone = zone_id
	_refresh_ui()

func _on_refresh_pressed():
	if manager and _active_zone != "":
		manager.force_refresh(_active_zone)

func _refresh_ui():
	if not manager: return
	if not is_inside_tree(): return
	_rebuild_zone_tabs()

	# Clear
	for c in available_container.get_children():
		c.queue_free()
	for c in active_container.get_children():
		c.queue_free()

	# Available Contracts — the active zone's board
	var pool: Array = []
	if _active_zone != "":
		pool = manager.get_zone_contracts(_active_zone)
	for contract in pool:
		var card = card_scene.instantiate()
		available_container.add_child(card)
		card.setup(contract, self, "available")

	if pool.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = tr("No contracts in this sector.\nWait for refresh...")
		empty_lbl.add_theme_color_override("font_color", UITheme.COLORS["text_dim"])
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		available_container.add_child(empty_lbl)

	# Active Contracts (global — all zones share the 3 slots)
	for contract in manager.active_contracts:
		var card = card_scene.instantiate()
		active_container.add_child(card)
		card.setup(contract, self, "active")

	if manager.active_contracts.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = tr("No active contracts.\nAccept contracts from the board.")
		empty_lbl.add_theme_color_override("font_color", UITheme.COLORS["text_dim"])
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		active_container.add_child(empty_lbl)

	# Stats
	if stats_lbl:
		stats_lbl.text = tr("Completed: %d | Slots: %d/%d") % [
			manager.total_completed,
			manager.active_contracts.size(),
			manager.MAX_ACTIVE
		]

	if refresh_btn and _active_zone != "":
		refresh_btn.text = tr("REFRESH ZONE (%s CR)") % UITheme.format_num(manager.get_refresh_cost(_active_zone))

func _process(_delta):
	if not manager: return
	# Update timer display (global — the natural refresh re-rolls EVERY zone board)
	if timer_lbl and manager.refresh_timer > 0:
		var hours = int(manager.refresh_timer / 3600)
		var mins = int(fmod(manager.refresh_timer, 3600) / 60)
		timer_lbl.text = tr("All boards refresh in: %dh %dm") % [hours, mins]
	elif timer_lbl:
		timer_lbl.text = tr("Refreshing...")

# ─── Card Callbacks ───

func _on_contract_accepted(contract_id: String):
	manager.accept_contract(contract_id)

func _on_contract_claimed(contract_id: String):
	manager.claim_contract(contract_id)

func _on_contract_abandoned(contract_id: String):
	manager.abandon_contract(contract_id)
