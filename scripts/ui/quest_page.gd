extends Control

# v162: STATION PROCUREMENT tabs (Demand Engine S1 — docs/design/DEMAND_ENGINE.md).
# The page now fronts two systems sharing one card widget:
#  - STANDING ORDERS: the legacy stockpile board (reroll + claim-all live here).
#  - One tab per procurement family: 3 never-expiring rate-based orders + the
#    family's demand-pool meter. Tab strip is programmatic (bounty_page pattern,
#    no .tscn surgery) and hidden entirely until the first factory family is
#    online — day-one UX is unchanged.

var manager: RefCounted
var card_scene = preload("res://scenes/ui/quest_card.tscn")
var cards: Array = []
var _last_board_sig: Array = []

@onready var grid = $Margin/VBox/Scroll/QuestGrid
@onready var stats_lbl = $Margin/VBox/HeaderHBox/StatsLabel
@onready var reroll_btn = $Margin/VBox/ControlsHBox/RerollBtn
@onready var claim_all_btn = $Margin/VBox/ControlsHBox/ClaimAllBtn

const LEGACY_TAB := "standing"
# Family display strings live in the loc CSV as literal EN keys.
const FAMILY_LABELS := {
	"refining": "REFINING", "chemical": "CHEMICAL", "structural": "STRUCTURAL",
	"electronics": "ELECTRONICS", "ordnance": "ORDNANCE",
	"fabrication": "FABRICATION", "capital": "CAPITAL",
}

var _tab_scroll: ScrollContainer = null
var _tab_box: HBoxContainer = null
var _tab_ids: Array = []
var _active_tab: String = LEGACY_TAB
var _pool_panel: PanelContainer = null
var _pool_label: Label = null
var _pool_bar: ProgressBar = null

func _ready():
	manager = GameState.quest_manager
	if manager:
		manager.quest_updated.connect(_on_quest_updated)
		reroll_btn.pressed.connect(_on_reroll_pressed)
		claim_all_btn.pressed.connect(_on_claim_all_pressed)
	UITheme.apply_premium_button_style(reroll_btn, "infrastructure")
	UITheme.apply_premium_button_style(claim_all_btn, "mission")
	_build_tab_strip()
	_build_pool_header()
	_rebuild()

func get_coach_anchor(key: String) -> Control:
	match key:
		"grid":
			return grid
		"claim_all":
			return claim_all_btn
	return null

# ── v162: tab strip + pool header (programmatic) ──

func _build_tab_strip():
	var vbox = $Margin/VBox
	_tab_scroll = ScrollContainer.new()
	_tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tab_scroll.custom_minimum_size = Vector2(0, 36)
	_tab_box = HBoxContainer.new()
	_tab_box.add_theme_constant_override("separation", 4)
	_tab_scroll.add_child(_tab_box)
	vbox.add_child(_tab_scroll)
	vbox.move_child(_tab_scroll, 1)  # right under the header
	_rebuild_tabs()

func _build_pool_header():
	var vbox = $Margin/VBox
	_pool_panel = PanelContainer.new()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	_pool_label = Label.new()
	_pool_label.add_theme_font_size_override("font_size", 12)
	_pool_bar = ProgressBar.new()
	_pool_bar.custom_minimum_size = Vector2(160, 14)
	_pool_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pool_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pool_bar.show_percentage = false
	hb.add_child(_pool_label)
	hb.add_child(_pool_bar)
	_pool_panel.add_child(hb)
	UITheme.apply_progress_bar_style(_pool_bar, "infrastructure")
	vbox.add_child(_pool_panel)
	vbox.move_child(_pool_panel, 2)  # under the tab strip
	_pool_panel.visible = false

func _rebuild_tabs():
	if not manager or _tab_box == null: return
	var unlocked: bool = manager.is_procurement_unlocked()
	_tab_scroll.visible = unlocked
	if not unlocked:
		if _active_tab != LEGACY_TAB:
			_active_tab = LEGACY_TAB
		return
	var ids: Array = [LEGACY_TAB]
	for fam in ElementDB.PROCUREMENT_FAMILY_ORDER:
		ids.append(String(fam))
	if ids == _tab_ids and _tab_box.get_child_count() > 0:
		_restyle_tabs()
		return
	_tab_ids = ids
	for c in _tab_box.get_children():
		c.queue_free()
	var online: Array = manager.get_online_families()
	for tid in ids:
		var btn = Button.new()
		var tid_s: String = String(tid)
		if tid_s == LEGACY_TAB:
			btn.text = tr("STANDING ORDERS")
		else:
			btn.text = tr(FAMILY_LABELS.get(tid_s, tid_s))
			if not online.has(tid_s):
				# Dormant family: tab stays visible (demand advertised before
				# supply) but dimmed.
				btn.modulate = Color(1, 1, 1, 0.45)
				btn.tooltip_text = tr("No operating line yet — build one to open this market.")
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(_on_tab_pressed.bind(tid_s))
		_tab_box.add_child(btn)
	_restyle_tabs()

func _restyle_tabs():
	for i in range(_tab_box.get_child_count()):
		var btn = _tab_box.get_child(i)
		if btn is Button and i < _tab_ids.size():
			UITheme.apply_sidebar_button_style(btn, String(_tab_ids[i]) == _active_tab)

func _on_tab_pressed(tab_id: String):
	_active_tab = tab_id
	_rebuild()

# ── board rendering ──

func _on_claim_all_pressed():
	if not manager: return
	var n = manager.claim_all_completed()
	if n > 0:
		UITheme.show_notification(tr("Claimed %d quest reward(s)") % n, Color(1.0, 0.85, 0.30))

func _on_reroll_pressed():
	if manager:
		manager.reroll_board()

func _current_cards() -> Array:
	if _active_tab == LEGACY_TAB:
		return manager.board
	return manager.get_procurement_board(_active_tab)

func _board_sig() -> Array:
	var sig: Array = [_active_tab]
	for q in _current_cards():
		sig.append(q["id"])
	return sig

func _on_quest_updated():
	# Only rebuild when the visible roster actually changes (claim/reroll/tab
	# data); progress updates are handled per-frame via refresh_state().
	if not manager: return
	_rebuild_tabs()
	if _board_sig() != _last_board_sig:
		_rebuild()
	else:
		if stats_lbl:
			stats_lbl.text = tr("Completed: %d") % manager.total_completed

func _rebuild():
	if not manager: return
	if not is_inside_tree(): return

	_rebuild_tabs()

	for c in grid.get_children():
		c.queue_free()
	cards.clear()

	var on_family: bool = (_active_tab != LEGACY_TAB)
	reroll_btn.visible = not on_family
	claim_all_btn.visible = not on_family
	if _pool_panel:
		_pool_panel.visible = on_family and manager.is_family_online(_active_tab)

	for q in _current_cards():
		var card = card_scene.instantiate()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # v140: fill the single-column width
		grid.add_child(card)
		card.setup(q, self)
		cards.append(card)

	# Dormant family: no line yet -> one explanatory label instead of cards.
	if on_family and _current_cards().is_empty():
		var lbl = Label.new()
		lbl.text = tr("No operating line in this family yet.\nBuild its factory and the station's orders open up.")
		lbl.add_theme_color_override("font_color", UITheme.COLORS["text_dim"])
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(lbl)

	_last_board_sig = _board_sig()

	if stats_lbl:
		stats_lbl.text = tr("Completed: %d") % manager.total_completed
	if reroll_btn:
		reroll_btn.text = tr("REROLL BOARD (%s CR)") % UITheme.format_num(manager.get_reroll_cost())
	_refresh_pool_meter()

func _refresh_pool_meter():
	if not _pool_panel or not _pool_panel.visible: return
	var v: float = manager.get_pool_value(_active_tab)
	var cap: float = manager.get_pool_cap(_active_tab)
	if _pool_bar:
		_pool_bar.max_value = maxf(cap, 1.0)
		_pool_bar.value = v
	if _pool_label:
		_pool_label.text = tr("STATION DEMAND: %s / %s Liras — refills continuously") % [UITheme.format_num(v), UITheme.format_num(cap)]

func _process(_delta):
	# Light per-frame refresh for progress bar values (signal only refires on full rebuild)
	if not manager: return
	if not visible: return
	for card in cards:
		if is_instance_valid(card) and card.has_method("refresh_state"):
			card.refresh_state()
	_refresh_pool_meter()
	# Keep CLAIM ALL count current as quests tick into completion
	if claim_all_btn and claim_all_btn.visible:
		var n = manager.count_claimable()
		claim_all_btn.text = tr("CLAIM ALL (%d)") % n
		claim_all_btn.disabled = (n == 0)

func on_claim(quest_id: String):
	if not manager: return
	# Legacy board ids route to claim_quest; everything else is procurement.
	for q in manager.board:
		if q["id"] == quest_id:
			manager.claim_quest(quest_id)
			return
	manager.claim_procurement(quest_id)
