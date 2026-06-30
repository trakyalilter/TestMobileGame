extends Control

var manager: RefCounted
var card_scene = preload("res://scenes/ui/bounty_contract_card.tscn")

@onready var available_container = $Dashboard/HBox/AvailablePanel/VBox/Scroll/AvailableList
@onready var active_container = $Dashboard/HBox/ActivePanel/VBox/Scroll/ActiveList
@onready var timer_lbl = $Dashboard/HBox/AvailablePanel/VBox/RefreshHBox/TimerLabel
@onready var refresh_btn = $Dashboard/HBox/AvailablePanel/VBox/RefreshHBox/RefreshBtn
@onready var stats_lbl = $Dashboard/HBox/ActivePanel/VBox/StatsLabel

func _ready():
	manager = GameState.bounty_manager
	if manager:
		manager.bounty_updated.connect(_refresh_ui)
		refresh_btn.pressed.connect(_on_refresh_pressed)
	_refresh_ui()

func get_coach_anchor(key: String) -> Control:
	match key:
		"available":
			return available_container
		"active":
			return active_container
	return null

func _on_refresh_pressed():
	if manager:
		manager.force_refresh()

func _refresh_ui():
	if not manager: return
	if not is_inside_tree(): return
	
	# Clear
	for c in available_container.get_children():
		c.queue_free()
	for c in active_container.get_children():
		c.queue_free()
	
	# Available Contracts
	for contract in manager.available_contracts:
		var card = card_scene.instantiate()
		available_container.add_child(card)
		card.setup(contract, self, "available")
	
	if manager.available_contracts.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No contracts available.\nWait for refresh..."
		empty_lbl.add_theme_color_override("font_color", UITheme.COLORS["text_dim"])
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		available_container.add_child(empty_lbl)
	
	# Active Contracts
	for contract in manager.active_contracts:
		var card = card_scene.instantiate()
		active_container.add_child(card)
		card.setup(contract, self, "active")
	
	if manager.active_contracts.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No active contracts.\nAccept contracts from the board."
		empty_lbl.add_theme_color_override("font_color", UITheme.COLORS["text_dim"])
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		active_container.add_child(empty_lbl)
	
	# Stats
	if stats_lbl:
		stats_lbl.text = "Completed: %d | Slots: %d/%d" % [
			manager.total_completed,
			manager.active_contracts.size(),
			manager.MAX_ACTIVE
		]
	
	if refresh_btn and manager:
		refresh_btn.text = "REFRESH (%s CR)" % UITheme.format_num(manager.get_refresh_cost())

func _process(_delta):
	if not manager: return
	# Update timer display
	if timer_lbl and manager.refresh_timer > 0:
		var hours = int(manager.refresh_timer / 3600)
		var mins = int(fmod(manager.refresh_timer, 3600) / 60)
		timer_lbl.text = "Refresh in: %dh %dm" % [hours, mins]
	elif timer_lbl:
		timer_lbl.text = "Refreshing..."

# ─── Card Callbacks ───

func _on_contract_accepted(contract_id: String):
	manager.accept_contract(contract_id)

func _on_contract_claimed(contract_id: String):
	manager.claim_contract(contract_id)

func _on_contract_abandoned(contract_id: String):
	manager.abandon_contract(contract_id)
