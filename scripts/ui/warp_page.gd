extends Control

# Warp Core page — rebuilt as a scrollable, sectioned prestige screen.
# Hierarchy is reversed from the old layout: the dominant readout is now
# EXOTIC SHARDS + progress-to-next-shard (the actual climb), the warp
# readiness panel commits to keeps-green / resets-red, EXECUTE WARP is a
# heavy primary CTA (with confirmation) and RETURN is a small secondary,
# the Mastery Tree sits at the bottom in a single coherent panel.
#
# First-warp teaching block auto-hides after total_warps >= 1 so it doesn't
# eat the hero zone on every visit forever.

# ─── Palette ──────────────────────────────────────────────────────────────
const COLOR_KEEPS := Color(0.45, 0.95, 0.55)
const COLOR_RESETS := Color(0.95, 0.40, 0.40)
const COLOR_SHARD := Color(0.78, 0.55, 1.0)        # Exotic Matter purple
const COLOR_GOLD := Color(1.0, 0.82, 0.30)
const COLOR_PURCHASED := Color(0.30, 0.95, 0.45)
const COLOR_LOCKED := Color(0.55, 0.55, 0.62)
const COLOR_AFFORD := Color(1.0, 0.82, 0.30)
const COLOR_DIM := Color(0.62, 0.66, 0.76)
const COLOR_BRANCH_LOCK_BG := Color(0.05, 0.06, 0.10, 0.92)

# Mirror of warp_manager.calculate_warp_gains() — kept in sync.
const FIRST_SHARD_THRESHOLD := 500000.0

# ─── State ────────────────────────────────────────────────────────────────
var _wm  # GameState.warp_manager
var _col: VBoxContainer

# Header
var _cycle_lbl: Label
var _shards_big_lbl: Label
var _shards_sub_lbl: Label
var _progress_bar: ProgressBar
var _progress_lbl: Label
var _first_warp_panel: PanelContainer

# Readiness
var _gain_big_lbl: Label

# Buttons
var _warp_btn: Button
var _back_btn: Button

# Tree (procedural)
var _tree_panel: PanelContainer
var _avail_label: Label
var _branch_columns: Dictionary = {}   # {branch_id: {column, lock}}
var _node_widgets: Dictionary = {}     # {node_id: {root, style, btn, status}}


# ─── Lifecycle ────────────────────────────────────────────────────────────
func _ready():
	_wm = GameState.warp_manager
	_build_ui()
	_wm.warped.connect(_on_warped)
	_wm.tree_node_purchased.connect(_on_node_purchased)
	$ConfirmationDialog.confirmed.connect(_on_confirm_warp)
	_update_all()


func _process(_delta):
	if not visible: return
	_update_dynamic()


# Tutorial coach anchors — preserved from the old API so the coach overlay
# still knows where to point.
func get_coach_anchor(key: String) -> Control:
	match key:
		"gain":
			return _gain_big_lbl
		"warp_btn":
			return _warp_btn
	return null


# ─── Layout scaffold ──────────────────────────────────────────────────────
func _build_ui():
	var pad = MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + s, 20)
	add_child(pad)

	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_FILL
	scroll.size_flags_vertical = Control.SIZE_FILL
	pad.add_child(scroll)

	var center = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	_col = VBoxContainer.new()
	_col.name = "WarpColumn"
	_col.custom_minimum_size = Vector2(740, 0)
	_col.add_theme_constant_override("separation", 16)
	center.add_child(_col)

	_build_header()
	_build_first_warp_block()
	_build_readiness()
	_build_buttons()
	_build_tree_section()


# Quiet supporting-panel style: subtle filled card with a thin left accent
# stripe, NO corner-bracket CardChrome. Reserving the heavy bracketed chrome
# for the two anchor sections (hero + tree) — instead of stamping it on every
# panel — removes the rainbow-of-frames clutter and builds a real hierarchy.
func _apply_flat_panel(panel: Control, accent: Color) -> void:
	if not panel: return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.085, 0.095, 0.135, 0.92)
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	var edge := accent
	edge.a = 0.30
	sb.border_color = edge
	sb.border_width_left = 3            # accent stripe = quiet semantic cue
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", sb)


# ─── HEADER: cycle + big shard readout + progress-to-next-shard bar ──────
func _build_header():
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_FILL
	_col.add_child(panel)

	var mc = MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 22)
	mc.add_theme_constant_override("margin_right", 22)
	mc.add_theme_constant_override("margin_top", 16)
	mc.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(mc)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	mc.add_child(v)

	_cycle_lbl = Label.new()
	_cycle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cycle_lbl.add_theme_font_size_override("font_size", 13)
	_cycle_lbl.add_theme_color_override("font_color", COLOR_DIM)
	v.add_child(_cycle_lbl)

	_shards_big_lbl = Label.new()
	_shards_big_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shards_big_lbl.add_theme_font_size_override("font_size", 34)
	_shards_big_lbl.add_theme_color_override("font_color", COLOR_SHARD)
	v.add_child(_shards_big_lbl)

	_shards_sub_lbl = Label.new()
	_shards_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shards_sub_lbl.add_theme_font_size_override("font_size", 11)
	_shards_sub_lbl.add_theme_color_override("font_color", COLOR_DIM)
	v.add_child(_shards_sub_lbl)

	# Faint rule cleanly separates the identity readout (shards / tier) above
	# from the climb-to-next-shard below — sharper internal hierarchy than a
	# blank gap.
	var sp_top = Control.new()
	sp_top.custom_minimum_size = Vector2(0, 6)
	v.add_child(sp_top)
	var hero_rule = ColorRect.new()
	hero_rule.color = Color(1, 1, 1, 0.07)
	hero_rule.custom_minimum_size = Vector2(0, 1)
	v.add_child(hero_rule)
	var sp_bot = Control.new()
	sp_bot.custom_minimum_size = Vector2(0, 6)
	v.add_child(sp_bot)

	var cap = Label.new()
	cap.text = "PROGRESS TO NEXT SHARD"
	cap.add_theme_font_size_override("font_size", 10)
	cap.add_theme_color_override("font_color", Color(0.55, 0.58, 0.66))
	v.add_child(cap)

	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 12)
	_progress_bar.show_percentage = false
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	UITheme.apply_progress_bar_style(_progress_bar, "research")
	v.add_child(_progress_bar)

	_progress_lbl = Label.new()
	_progress_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_progress_lbl.add_theme_font_size_override("font_size", 10)
	_progress_lbl.add_theme_color_override("font_color", COLOR_DIM)
	v.add_child(_progress_lbl)

	UITheme.apply_card_style(panel, "research")


# ─── FIRST WARP teaching (auto-hidden once total_warps >= 1) ─────────────
func _build_first_warp_block():
	_first_warp_panel = PanelContainer.new()
	_first_warp_panel.size_flags_horizontal = Control.SIZE_FILL
	_col.add_child(_first_warp_panel)

	var mc = MarginContainer.new()
	for s in ["left", "right"]:
		mc.add_theme_constant_override("margin_" + s, 18)
	mc.add_theme_constant_override("margin_top", 12)
	mc.add_theme_constant_override("margin_bottom", 14)
	_first_warp_panel.add_child(mc)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	mc.add_child(v)

	var title = Label.new()
	title.text = "FIRST WARP — WHAT YOU'LL UNLOCK"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["mission"])
	v.add_child(title)

	var bullets = Label.new()
	bullets.text = "• Prestige multipliers (Production / Combat / Gathering / XP)\n• Warp Tier scaling (doubles every 5 warps)\n• Starting resource package on each future warp"
	bullets.add_theme_font_size_override("font_size", 11)
	bullets.add_theme_color_override("font_color", Color(0.78, 0.86, 0.82))
	v.add_child(bullets)

	_apply_flat_panel(_first_warp_panel, UITheme.CATEGORY_COLORS["mission"])


# ─── READINESS: gains big + keeps/resets ──────────────────────────────────
func _build_readiness():
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_FILL
	_col.add_child(panel)

	var mc = MarginContainer.new()
	for s in ["left", "right"]:
		mc.add_theme_constant_override("margin_" + s, 22)
	mc.add_theme_constant_override("margin_top", 14)
	mc.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(mc)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	mc.add_child(v)

	var title_row = HBoxContainer.new()
	v.add_child(title_row)

	var ttl = Label.new()
	ttl.text = "WARP READINESS"
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ttl.add_theme_font_size_override("font_size", 13)
	ttl.add_theme_color_override("font_color", COLOR_DIM)
	title_row.add_child(ttl)

	_gain_big_lbl = Label.new()
	_gain_big_lbl.add_theme_font_size_override("font_size", 14)
	_gain_big_lbl.add_theme_color_override("font_color", COLOR_SHARD)
	title_row.add_child(_gain_big_lbl)

	var rule = ColorRect.new()
	rule.color = Color(1, 1, 1, 0.08)
	rule.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule)

	var keeps = Label.new()
	keeps.text = "  ✓  KEEPS    Research · Ships · Exotic Matter · Warp Mastery"
	keeps.add_theme_font_size_override("font_size", 11)
	keeps.add_theme_color_override("font_color", COLOR_KEEPS)
	v.add_child(keeps)

	var resets = Label.new()
	resets.text = "  ✗  RESETS   Liras · Buildings · Standard Resources · Skill levels (keep 30% XP)"
	resets.add_theme_font_size_override("font_size", 11)
	resets.add_theme_color_override("font_color", COLOR_RESETS)
	v.add_child(resets)

	_apply_flat_panel(panel, UITheme.CATEGORY_COLORS["ops"])


# ─── BUTTONS: small return + heavy execute (purple primary CTA) ──────────
func _build_buttons():
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	_col.add_child(row)

	_back_btn = Button.new()
	_back_btn.text = "← Return"
	_back_btn.custom_minimum_size = Vector2(130, 44)
	UITheme.apply_premium_button_style(_back_btn, "engineering")
	_back_btn.add_theme_font_size_override("font_size", 12)
	_back_btn.pressed.connect(_on_back_btn_pressed)
	row.add_child(_back_btn)

	_warp_btn = Button.new()
	_warp_btn.text = "◈   EXECUTE WARP"
	_warp_btn.custom_minimum_size = Vector2(380, 56)
	UITheme.apply_premium_button_style(_warp_btn, "research")
	_warp_btn.add_theme_font_size_override("font_size", 16)
	_warp_btn.pressed.connect(_on_execute_btn_pressed)
	row.add_child(_warp_btn)


# ─── TREE: existing 4-state logic, restructured into the new column ──────
func _build_tree_section():
	_tree_panel = PanelContainer.new()
	_tree_panel.size_flags_horizontal = Control.SIZE_FILL
	_col.add_child(_tree_panel)

	var outer = MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer.add_theme_constant_override(k, 14)
	_tree_panel.add_child(outer)

	var c = VBoxContainer.new()
	c.add_theme_constant_override("separation", 8)
	outer.add_child(c)

	var title = Label.new()
	title.text = "[ WARP MASTERY TREE ]"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	c.add_child(title)

	_avail_label = Label.new()
	_avail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avail_label.add_theme_font_size_override("font_size", 12)
	_avail_label.add_theme_color_override("font_color", Color.WHITE)
	c.add_child(_avail_label)

	var hb = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_child(hb)

	hb.add_child(_build_branch_column("engineering", "ENGINEERING"))
	hb.add_child(_build_branch_column("combat", "COMBAT"))

	# Unified to the warp-purple accent (was "shipyard" blue) so the two heavy
	# bracketed anchors — hero + tree — share one cohesive prestige identity
	# instead of being two different colours.
	UITheme.apply_card_style(_tree_panel, "research")


func _build_branch_column(branch_id: String, title_text: String) -> Control:
	var col_panel = PanelContainer.new()
	col_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col_style = StyleBoxFlat.new()
	col_style.bg_color = Color(0.08, 0.09, 0.13, 0.85)
	col_style.set_border_width_all(1)
	col_style.border_color = Color(COLOR_GOLD.r, COLOR_GOLD.g, COLOR_GOLD.b, 0.22)
	col_panel.add_theme_stylebox_override("panel", col_style)
	# Safety net: a column must never paint past its own frame again.
	col_panel.clip_contents = true

	# v111.16 OVERFLOW FIX: parent the content MarginContainer and the lock
	# overlay DIRECTLY to the PanelContainer. A PanelContainer fits every child
	# to its full content rect (so they overlap) and sizes itself to the largest
	# child's minimum size — which is exactly the overlay behaviour we want. The
	# old code wrapped both in a plain Control, whose minimum size is always
	# (0,0); that collapsed the column to zero height and its node/lock text
	# spilled outside the panel. Lock is added LAST so it paints on top.
	var mc = MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(k, 8)
	col_panel.add_child(mc)

	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	mc.add_child(col)

	var hdr = Label.new()
	hdr.text = title_text
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", 13)
	hdr.add_theme_color_override("font_color", COLOR_GOLD)
	col.add_child(hdr)

	for node_id in _wm.TREE_NODES:
		var node_data = _wm.TREE_NODES[node_id]
		if node_data.get("branch", "") != branch_id:
			continue
		col.add_child(_build_node_card(node_id))

	# Branch lock overlay — covers the column when the branch isn't yet
	# revealed by warp count. Added last so it always paints on top of content.
	var lock = Panel.new()
	lock.mouse_filter = Control.MOUSE_FILTER_STOP
	var lock_sb = StyleBoxFlat.new()
	lock_sb.bg_color = COLOR_BRANCH_LOCK_BG
	lock.add_theme_stylebox_override("panel", lock_sb)
	col_panel.add_child(lock)

	var lock_label = Label.new()
	# FILL the lock panel and center text inside it. The old PRESET_CENTER sized
	# the label to its un-wrapped text width and pinned it at the panel centre,
	# so the banner ran off the right edge of the column (now visibly clipped).
	# Full-rect + centered + word-wrap keeps it inside the column at any width.
	lock_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lock_label.offset_left = 8
	lock_label.offset_right = -8
	lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lock_label.add_theme_font_size_override("font_size", 14)
	lock_label.add_theme_color_override("font_color", COLOR_LOCKED)
	var reveal_at = int(_wm.BRANCH_REVEAL_WARP.get(branch_id, 1))
	lock_label.text = "[ LOCKED ]   UNLOCKS AT WARP #%d" % reveal_at
	lock.add_child(lock_label)

	_branch_columns[branch_id] = {"column": col, "lock": lock}
	return col_panel


func _build_node_card(node_id: String) -> Control:
	var node_data = _wm.TREE_NODES[node_id]

	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.16, 0.95)
	sb.set_border_width_all(1)
	sb.border_color = COLOR_LOCKED
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	card.add_theme_stylebox_override("panel", sb)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	card.add_child(v)

	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)

	var t = Label.new()
	t.text = "%s · %s" % [node_id, node_data.get("name", "")]
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("font_size", 12)
	t.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(t)

	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(func(): _on_buy_pressed(node_id))
	row.add_child(btn)

	var status_lbl = Label.new()
	status_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
	status_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(status_lbl)

	var desc = Label.new()
	desc.text = str(node_data.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", Color(0.72, 0.75, 0.82))
	v.add_child(desc)

	_node_widgets[node_id] = {"root": card, "style": sb, "btn": btn, "status": status_lbl}
	return card


# ─── Refresh / update ─────────────────────────────────────────────────────
func _update_all():
	_refresh_header()
	_refresh_first_warp_visibility()
	_refresh_readiness()
	_refresh_tree()


func _refresh_header():
	var n = int(_wm.total_warps)
	_cycle_lbl.text = "WARP CYCLE   #%d   ▸   #%d" % [n, n + 1]
	_shards_big_lbl.text = "◈   %.1f   EXOTIC SHARDS" % _wm.warp_shards
	var tier = 0
	if _wm.has_method("get_warp_tier"):
		tier = int(_wm.get_warp_tier())
	var prod_pct = (_wm.get_production_multiplier() - 1.0) * 100.0
	_shards_sub_lbl.text = "Warp Tier  ×%d   ·   +%.0f%% production scale" % [int(pow(2, tier)), prod_pct]


func _refresh_first_warp_visibility():
	_first_warp_panel.visible = (int(_wm.total_warps) == 0)


func _refresh_readiness():
	var gains = int(_wm.calculate_warp_gains())
	if gains > 0:
		_gain_big_lbl.text = "POTENTIAL  +%d %s" % [gains, "SHARD" if gains == 1 else "SHARDS"]
		_gain_big_lbl.add_theme_color_override("font_color", COLOR_SHARD.lightened(0.1))
	else:
		_gain_big_lbl.text = "NOT READY"
		_gain_big_lbl.add_theme_color_override("font_color", Color(0.65, 0.55, 0.55))


# Per-frame live values: progress bar + button enable state.
func _update_dynamic():
	if _warp_btn == null: return
	var gains = int(_wm.calculate_warp_gains())
	_warp_btn.disabled = (gains <= 0)

	var score = _compute_progress_score()
	var prev_thr = 0.0
	if gains > 0:
		prev_thr = FIRST_SHARD_THRESHOLD * pow(2.0, float(gains - 1))
	var next_thr = FIRST_SHARD_THRESHOLD * pow(2.0, float(gains))
	var span = next_thr - prev_thr
	if span < 1.0: span = 1.0
	var into = score - prev_thr
	if into < 0.0: into = 0.0
	if into > span: into = span
	_progress_bar.value = (into / span) * 100.0
	_progress_lbl.text = "%s / %s   (toward +%d %s)" % [
		FormatUtils.format_number(score),
		FormatUtils.format_number(next_thr),
		gains + 1,
		"shard" if gains + 1 == 1 else "shards"
	]
	# Refresh readiness label too (gains can change live).
	_refresh_readiness()


# Mirrors warp_manager.calculate_warp_gains() score computation exactly.
func _compute_progress_score() -> float:
	var total_credits = GameState.resources.lifetime_credits - _wm.credits_at_warp_start
	var building_count = 0
	for bid in GameState.infrastructure_manager.buildings:
		building_count += GameState.infrastructure_manager.buildings[bid]
	return float(total_credits) + float(building_count) * 1000.0


# ─── Tree refresh (4-state cascade preserved) ─────────────────────────────
func _refresh_tree():
	if _tree_panel == null: return
	var avail_n = int(_wm.get_available_shards())
	_avail_label.text = "AVAILABLE  %d %s     SPENT  %d     EARNED  %d" % [
		avail_n, _shard_label(avail_n),
		int(_wm.warp_shards_spent),
		int(_wm.warp_shards),
	]
	for branch_id in _branch_columns:
		var lock = _branch_columns[branch_id]["lock"]
		lock.visible = not _wm.is_branch_revealed(branch_id)
	for node_id in _node_widgets:
		_refresh_node(node_id)


func _refresh_node(node_id: String):
	var w = _node_widgets[node_id]
	var sb = w["style"]
	var btn = w["btn"]
	var status = w["status"]
	var cost = int(_wm.TREE_NODES[node_id].get("cost", 0))

	if _wm.is_node_purchased(node_id):
		sb.border_color = COLOR_PURCHASED
		sb.bg_color = Color(0.08, 0.16, 0.10, 0.95)
		btn.visible = false
		status.visible = true
		status.text = "✓ Acquired"
		status.add_theme_color_override("font_color", COLOR_PURCHASED)
	elif not _wm.is_node_implemented(node_id):
		sb.border_color = COLOR_LOCKED
		sb.bg_color = Color(0.09, 0.10, 0.13, 0.90)
		btn.visible = false
		status.visible = true
		status.text = "Soon · %d %s" % [cost, _shard_label(cost)]
		status.add_theme_color_override("font_color", COLOR_LOCKED)
	elif _wm.can_purchase_node(node_id):
		sb.border_color = COLOR_AFFORD
		sb.bg_color = Color(0.13, 0.11, 0.06, 0.95)
		btn.visible = true
		status.visible = false
		btn.text = "BUY · %d %s" % [cost, _shard_label(cost)]
		btn.disabled = false
	else:
		sb.border_color = COLOR_LOCKED
		sb.bg_color = Color(0.10, 0.11, 0.16, 0.95)
		btn.visible = false
		status.visible = true
		var avail = int(_wm.get_available_shards())
		var need = cost - avail
		if need < 0: need = 0
		status.text = "Need %d more %s" % [need, _shard_label(need)]
		status.add_theme_color_override("font_color", COLOR_LOCKED)


func _shard_label(n: int) -> String:
	return "Shard" if abs(n) == 1 else "Shards"


# ─── Actions ──────────────────────────────────────────────────────────────
func _on_execute_btn_pressed():
	var gains = int(_wm.calculate_warp_gains())
	if gains <= 0: return
	var s = "" if gains == 1 else "s"
	$ConfirmationDialog.dialog_text = "Execute Warp will:\n\n+ Grant %d Exotic Shard%s\n\nReset: Liras, Buildings, Standard Resources, Skill levels (keep 30%% XP)\nKeep: Research, Ships, Exotic Matter, Warp Mastery purchases\n\nThis cannot be undone." % [gains, s]
	$ConfirmationDialog.popup_centered()


func _on_confirm_warp():
	_wm.execute_warp()


func _on_back_btn_pressed():
	if get_tree().current_scene.has_method("switch_to"):
		get_tree().current_scene.switch_to("mission")


func _on_warped(gains):
	_update_all()
	UITheme.trigger_circuit_surge(_shards_big_lbl)
	# Brief celebratory text on the readiness panel so the dopamine moment lands.
	var s = "" if gains == 1 else "s"
	_gain_big_lbl.text = "WARP COMPLETE · +%d SHARD%s" % [gains, s]
	_gain_big_lbl.add_theme_color_override("font_color", COLOR_PURCHASED)


func _on_node_purchased(_node_id: String):
	_refresh_tree()


func _on_buy_pressed(node_id: String):
	if _wm.purchase_node(node_id):
		UITheme.trigger_circuit_surge(_avail_label)
