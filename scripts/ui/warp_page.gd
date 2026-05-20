extends Control

@onready var shard_count = $VBox/Header/ShardCount
@onready var shard_desc = $VBox/Header/ShardDesc
@onready var gain_label = $VBox/WarpCore/Status/PotentialGain
@onready var warp_btn = $HBox/ExecuteBtn
@onready var back_btn = $HBox/BackBtn

# v107: Warp Mastery Tree UI ----------------------------------------------
const SHARD_TEXT := "Shards"  # inline shard label — swap to "[img]…[/img]" bbcode later if/when a shard icon SVG is added
const ACCENT_GOLD := Color(1.0, 0.82, 0.30)         # matches lira icon / header gold
const ACCENT_PURPLE := Color(0.72, 0.45, 1.0)       # matches Exotic Matter shard color
const COLOR_PURCHASED := Color(0.30, 0.95, 0.45)    # green checkmark state
const COLOR_LOCKED := Color(0.55, 0.55, 0.62)       # greyed out
const COLOR_AFFORD := Color(1.0, 0.82, 0.30)        # gold accent — affordable
const COLOR_BRANCH_LOCK_BG := Color(0.08, 0.08, 0.10, 0.85)

var _tree_panel: PanelContainer = null
var _avail_label: Label = null
var _branch_columns: Dictionary = {}   # {branch_id: {column_vbox, lock_overlay}}
var _node_widgets: Dictionary = {}     # {node_id: {root, status_lbl, buy_btn}}

func _ready():
	_update_ui()
	GameState.warp_manager.warped.connect(_on_warped)
	GameState.warp_manager.tree_node_purchased.connect(_on_node_purchased)
	_build_tree_section()
	_refresh_tree()

func get_coach_anchor(key: String) -> Control:
	match key:
		"gain":
			return gain_label
		"warp_btn":
			return warp_btn
	return null

func _process(_delta):
	_update_dynamic_values()

func _update_ui():
	var wm = GameState.warp_manager
	shard_count.text = "EXOTIC MATTER: %.1f Shards" % wm.warp_shards

	if wm.total_warps == 0:
		shard_desc.text = "FIRST WARP — Permanently unlocks:\n• Prestige multipliers (Production / Combat / Gathering / XP)\n• Warp Tier scaling (doubles every 5 warps)\n• Starting resource package on each future warp"
		shard_desc.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
	else:
		var tier = wm.warp_tier if "warp_tier" in wm else int(wm.total_warps / 5)
		shard_desc.text = "Warp %d  |  Tier %d  |  ×%.0f multiplier scale\n+%.0f%% Production | +%.0f%% Combat | +%.0f%% Gathering | +%.0f%% XP" % [
			wm.total_warps,
			tier,
			pow(2, tier),
			(wm.get_production_multiplier() - 1.0) * 100.0,
			(wm.get_combat_multiplier() - 1.0) * 100.0,
			(wm.get_gathering_multiplier() - 1.0) * 100.0,
			(wm.get_xp_multiplier() - 1.0) * 100.0
		]
		shard_desc.add_theme_color_override("font_color", Color.WHITE)

func _update_dynamic_values():
	var gains = GameState.warp_manager.calculate_warp_gains()
	gain_label.text = "Potential Gains: +%d Shards" % gains
	warp_btn.disabled = gains <= 0

func _on_execute_btn_pressed():
	# Confirmation logic
	_show_confirmation()

func _show_confirmation():
	var gains = GameState.warp_manager.calculate_warp_gains()
	var msg = "WARP CORE RESONANCE DETECTED.\n\nExecuting this command will reset your Liras, Industrial Infrastructure, and Standard Materials.\n\nYou will gain %d EXOTIC MATTER SHARDS.\n\nPROCEED WITH SYSTEM RESTART?" % gains
	
	# For now, just execute if confirmed via prompt or simple button check
	# In a real game we'd use a Modal.
	GameState.warp_manager.execute_warp()

func _on_warped(gains):
	_update_ui()
	UITheme.trigger_circuit_surge(shard_count)
	var wm = GameState.warp_manager
	gain_label.text = "WARP COMPLETE — +%d Shards gained  |  Total: %.1f  |  Next tier in %d warps" % [
		gains,
		wm.warp_shards,
		5 - (wm.total_warps % 5)
	]
	gain_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7))
	# v107: Repaint Mastery Tree so newly-revealed branches uncover, and any
	# new shards immediately show as spendable.
	_refresh_tree()

func _on_back_btn_pressed():
	if get_tree().current_scene.has_method("switch_to"):
		get_tree().current_scene.switch_to("mission")


# === v107: Warp Mastery Tree UI ============================================

func _build_tree_section():
	# Widen + grow the parent VBox to accommodate the two-column tree.
	var vb := $VBox
	vb.offset_left = -400.0
	vb.offset_right = 400.0
	vb.offset_top = -340.0
	vb.offset_bottom = 340.0

	# v107: Reparent the existing Return/Execute button row INTO the VBox
	# between WarpCore and the new tree, instead of letting it float as a
	# bottom-anchored sibling that overlaps the tree cards. The HBox keeps
	# its children (Return + Execute) but follows the natural VBox flow now.
	var hbox = $HBox
	if hbox and hbox.get_parent() != vb:
		hbox.get_parent().remove_child(hbox)
		# Reset anchors — VBox flow takes over horizontal positioning
		hbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_child(hbox)

	var wm = GameState.warp_manager

	_tree_panel = PanelContainer.new()
	_tree_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_panel.custom_minimum_size = Vector2(760, 340)
	UITheme.apply_card_style(_tree_panel, "shipyard")
	vb.add_child(_tree_panel)

	var outer := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer.add_theme_constant_override(k, 12)
	_tree_panel.add_child(outer)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	outer.add_child(col)

	var title := Label.new()
	title.text = "[ WARP MASTERY TREE ]"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", ACCENT_GOLD)
	col.add_child(title)

	_avail_label = Label.new()
	_avail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avail_label.add_theme_font_size_override("font_size", 13)
	_avail_label.add_theme_color_override("font_color", Color.WHITE)
	col.add_child(_avail_label)

	# v107: Wrap the two-column section in a ScrollContainer so the lower
	# nodes (E4/E5/C4/C5) are reachable when the viewport doesn't have
	# enough vertical room. Horizontal scroll is disabled — only vertical
	# overflow scrolls. The header + warp-readiness + execute button row
	# above stay anchored, so the EXECUTE WARP action is never hidden.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.custom_minimum_size = Vector2(0, 240)
	col.add_child(scroll)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # let HBox grow to fit cards; scroll handles overflow
	scroll.add_child(hb)

	hb.add_child(_build_branch_column("engineering", "ENGINEERING"))
	hb.add_child(_build_branch_column("combat", "COMBAT"))


func _build_branch_column(branch_id: String, title: String) -> Control:
	var wm = GameState.warp_manager

	# Stack: branch column (nodes) + lock overlay on top
	var col_panel := PanelContainer.new()
	col_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col_style := StyleBoxFlat.new()
	col_style.bg_color = Color(0.10, 0.10, 0.13, 0.85)
	col_style.set_border_width_all(1)
	col_style.border_color = ACCENT_GOLD
	col_style.border_color.a = 0.25
	col_style.set_corner_radius_all(2)
	col_panel.add_theme_stylebox_override("panel", col_style)

	var stack := Control.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col_panel.add_child(stack)

	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(k, 8)
	stack.add_child(mc)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	mc.add_child(col)

	var hdr := Label.new()
	hdr.text = title
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", 14)
	hdr.add_theme_color_override("font_color", ACCENT_GOLD)
	col.add_child(hdr)

	for node_id in wm.TREE_NODES:
		var node_data: Dictionary = wm.TREE_NODES[node_id]
		if node_data.get("branch", "") != branch_id:
			continue
		col.add_child(_build_node_card(node_id))

	# Branch lock overlay (covers the column when branch not yet revealed)
	var lock := Panel.new()
	lock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lock.mouse_filter = Control.MOUSE_FILTER_STOP
	var lock_sb := StyleBoxFlat.new()
	lock_sb.bg_color = COLOR_BRANCH_LOCK_BG
	lock_sb.set_corner_radius_all(2)
	lock.add_theme_stylebox_override("panel", lock_sb)
	stack.add_child(lock)

	var lock_label := Label.new()
	lock_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock_label.add_theme_font_size_override("font_size", 14)
	lock_label.add_theme_color_override("font_color", COLOR_LOCKED)
	var reveal_at: int = int(wm.BRANCH_REVEAL_WARP.get(branch_id, 1))
	lock_label.text = "🔒 UNLOCKS AT WARP #%d" % reveal_at
	lock.add_child(lock_label)

	_branch_columns[branch_id] = {"column": col, "lock": lock}
	return col_panel


func _build_node_card(node_id: String) -> Control:
	var wm = GameState.warp_manager
	var node_data: Dictionary = wm.TREE_NODES[node_id]

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.13, 0.17, 0.95)
	sb.set_border_width_all(1)
	sb.border_color = COLOR_LOCKED
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)

	# Title row: name (expand) + state-driven action element (right-aligned).
	# We instantiate BOTH a Button and a Label and toggle visibility in
	# _refresh_node — keeps the card layout stable across state transitions.
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)

	var t := Label.new()
	t.text = "%s — %s" % [node_id, node_data.get("name", "")]
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("font_size", 12)
	t.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(t)

	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(func(): _on_buy_pressed(node_id))
	row.add_child(btn)

	var status_lbl := Label.new()
	status_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
	status_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(status_lbl)

	# Description below the title row, full width.
	var desc := Label.new()
	desc.text = str(node_data.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", Color(0.72, 0.75, 0.82))
	v.add_child(desc)

	_node_widgets[node_id] = {"root": card, "style": sb, "btn": btn, "status": status_lbl}
	return card


func _refresh_tree():
	if _tree_panel == null:
		return
	var wm = GameState.warp_manager
	var avail_n: int = int(wm.get_available_shards())
	_avail_label.text = "AVAILABLE: %d %s   |   SPENT: %d   |   EARNED: %d" % [
		avail_n, _shard_label(avail_n),
		int(wm.warp_shards_spent),
		int(wm.warp_shards)
	]
	for branch_id in _branch_columns:
		var lock: Control = _branch_columns[branch_id]["lock"]
		lock.visible = not wm.is_branch_revealed(branch_id)
	for node_id in _node_widgets:
		_refresh_node(node_id)


func _refresh_node(node_id: String):
	var wm = GameState.warp_manager
	var w: Dictionary = _node_widgets[node_id]
	var sb: StyleBoxFlat = w["style"]
	var btn: Button = w["btn"]
	var status: Label = w["status"]
	var cost: int = int(wm.TREE_NODES[node_id].get("cost", 0))

	# Single source of truth for the right-hand element: button is for the
	# affordable state only; every other state shows inline status text.
	if wm.is_node_purchased(node_id):
		sb.border_color = COLOR_PURCHASED
		btn.visible = false
		status.visible = true
		status.text = "✓ Acquired"
		status.add_theme_color_override("font_color", COLOR_PURCHASED)
	elif not wm.is_node_implemented(node_id):
		# Mechanic-unlock node whose code path hasn't shipped yet — no
		# shards at risk, distinct visual from "can't afford".
		sb.border_color = COLOR_LOCKED
		btn.visible = false
		status.visible = true
		status.text = "Coming Soon · %d %s" % [cost, _shard_label(cost)]
		status.add_theme_color_override("font_color", COLOR_LOCKED)
	elif wm.can_purchase_node(node_id):
		sb.border_color = COLOR_AFFORD
		btn.visible = true
		status.visible = false
		btn.text = "Buy · %d %s" % [cost, _shard_label(cost)]
		btn.disabled = false
	else:
		sb.border_color = COLOR_LOCKED
		btn.visible = false
		status.visible = true
		var avail: int = int(wm.get_available_shards())
		var need: int = max(0, cost - avail)
		status.text = "Need %d more %s" % [need, _shard_label(need)]
		status.add_theme_color_override("font_color", COLOR_LOCKED)


func _shard_label(n: int) -> String:
	# v107: singular vs plural so "1 Shard" reads naturally instead of "1 Shards".
	return "Shard" if abs(n) == 1 else "Shards"


func _on_buy_pressed(node_id: String):
	var wm = GameState.warp_manager
	if wm.purchase_node(node_id):
		UITheme.trigger_circuit_surge(_avail_label)


func _on_node_purchased(_node_id: String):
	_refresh_tree()
