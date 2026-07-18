extends Control

var manager: RefCounted
var card_scene = preload("res://scenes/ui/quest_card.tscn")
var cards: Array = []
var _last_board_ids: Array = []

@onready var grid = $Margin/VBox/Scroll/QuestGrid
@onready var stats_lbl = $Margin/VBox/HeaderHBox/StatsLabel
@onready var reroll_btn = $Margin/VBox/ControlsHBox/RerollBtn
@onready var claim_all_btn = $Margin/VBox/ControlsHBox/ClaimAllBtn

func _ready():
	manager = GameState.quest_manager
	if manager:
		manager.quest_updated.connect(_on_quest_updated)
		reroll_btn.pressed.connect(_on_reroll_pressed)
		claim_all_btn.pressed.connect(_on_claim_all_pressed)
	UITheme.apply_premium_button_style(reroll_btn, "infrastructure")
	UITheme.apply_premium_button_style(claim_all_btn, "mission")
	_rebuild()

func get_coach_anchor(key: String) -> Control:
	match key:
		"grid":
			return grid
		"claim_all":
			return claim_all_btn
	return null

func _on_claim_all_pressed():
	if not manager: return
	var n = manager.claim_all_completed()
	if n > 0:
		UITheme.show_notification(tr("Claimed %d quest reward(s)") % n, Color(1.0, 0.85, 0.30))

func _on_reroll_pressed():
	if manager:
		manager.reroll_board()

func _on_quest_updated():
	# Only rebuild when the board roster actually changes (claim/reroll).
	# Progress updates are handled per-frame in _process via refresh_state().
	if not manager: return
	var ids = []
	for q in manager.board:
		ids.append(q["id"])
	if ids != _last_board_ids:
		_rebuild()
	else:
		# Just refresh stats/reroll cost
		if stats_lbl:
			stats_lbl.text = tr("Completed: %d") % manager.total_completed

func _rebuild():
	if not manager: return
	if not is_inside_tree(): return

	for c in grid.get_children():
		c.queue_free()
	cards.clear()
	_last_board_ids.clear()

	for q in manager.board:
		var card = card_scene.instantiate()
		grid.add_child(card)
		card.setup(q, self)
		cards.append(card)
		_last_board_ids.append(q["id"])

	if stats_lbl:
		stats_lbl.text = tr("Completed: %d") % manager.total_completed
	if reroll_btn:
		reroll_btn.text = tr("REROLL BOARD (%s CR)") % UITheme.format_num(manager.get_reroll_cost())

func _process(_delta):
	# Light per-frame refresh for progress bar values (signal only refires on full rebuild)
	if not manager: return
	if not visible: return
	for card in cards:
		if is_instance_valid(card) and card.has_method("refresh_state"):
			card.refresh_state()
	# Keep CLAIM ALL count current as quests tick into completion
	if claim_all_btn:
		var n = manager.count_claimable()
		claim_all_btn.text = tr("CLAIM ALL (%d)") % n
		claim_all_btn.disabled = (n == 0)

func on_claim(quest_id: String):
	if manager:
		manager.claim_quest(quest_id)
