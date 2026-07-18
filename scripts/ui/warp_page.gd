extends Control

# Warp Core page — a scrollable, sectioned prestige screen for SPENDING and
# MONITORING only. The dominant readout is EXOTIC SHARDS + progress-to-next-shard
# (the actual climb); the Mastery Tree sits at the bottom in a single coherent
# panel. v138: the warp itself is DIEGETIC — the player enters the SINGULARITY on
# the Sector Chart (torn open by a Zone-3+ boss kill). No execute button here;
# a passive status line reports whether a rift is open this run.
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
# v135a: gains-forward preview — leads the page with what you GET (shards, standing
# multipliers, starter package) instead of the loss ledger. Neutral state, never a nag.
var _gains_panel: PanelContainer
var _gains_shards_lbl: Label
var _gains_mult_lbl: Label
var _gains_starter_lbl: Label
var _col: VBoxContainer

# Header
var _cycle_lbl: Label
var _shards_big_lbl: Label
var _progress_bar: ProgressBar
var _progress_lbl: Label
var _first_warp_panel: PanelContainer

# v124c: command-band stat chips. _gain_big_lbl is the POTENTIAL chip's value and
# stays a coach anchor.
var _gain_big_lbl: Label
var _tier_val: Label
var _reso_val: Label

# v134h: Feed-the-Core manual charge panel.
var _feed_panel: PanelContainer
var _feed_picker: OptionButton
var _feed_spin: SpinBox
var _feed_preview: Label
var _feed_btn: Button
var _feed_syms: Array = []   # picker index -> material symbol

# Buttons
var _rift_status_lbl: Label   # v138: passive Singularity state (replaces the execute button)
var _back_btn: Button

# Tree (procedural, tabbed — one branch shown at a time in a grid so the whole
# page fits the viewport without scrolling).
var _tree_panel: PanelContainer
var _avail_label: Label
var _active_branch: String = "engineering"
var _branch_tabs: Dictionary = {}      # {branch_id: tab Button}
var _branch_grids: Dictionary = {}     # {branch_id: GridContainer}
var _lock_msg: Label
var _node_widgets: Dictionary = {}     # {node_id: {root, style, btn, dot, chip_*, title}}


# ─── Lifecycle ────────────────────────────────────────────────────────────
func _ready():
	_wm = GameState.warp_manager
	_build_ui()
	_wm.warped.connect(_on_warped)
	_wm.tree_node_purchased.connect(_on_node_purchased)
	# v138: warp is triggered from the Sector Chart's singularity (star_map_overlay),
	# not this page. The old ConfirmationDialog confirm-warp hook (_on_confirm_warp) was
	# removed with that refactor — this dangling connect was left behind and broke the
	# whole Warp scene with a parse error. Do not re-add it.
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
			return _rift_status_lbl   # v138: the old execute-button step points at the rift status
		"tree":
			return _tree_panel
		"feed":
			return _feed_panel
	return null


# ─── Layout scaffold ──────────────────────────────────────────────────────
func _build_ui():
	# v124b: fit-to-viewport — NO page scroll. _col fills the screen; the mastery
	# tree section (the tall part) is tabbed + laid in a grid and EXPANDs into the
	# remaining height, so the whole page fits 1280×720 without scrolling.
	var pad = MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + s, 16)
	add_child(pad)

	_col = VBoxContainer.new()
	_col.name = "WarpColumn"
	_col.add_theme_constant_override("separation", 10)
	pad.add_child(_col)

	_build_command_band()   # cycle + shards + vital chips + progress + actions, all in one compact band
	_build_gains_preview()  # v135a: lead with the reward (shards + bonuses + starter), not the loss
	_build_first_warp_block()
	_build_feed_core_section()  # v134h: manual "Feed the Core" charge sink
	_build_tree_section()    # the dominant zone — fills the rest of the viewport


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


# ─── Modular component builders ─────────────────────────────────────────────

# Per-branch identity colour — the only categorical signal the tree exposes
# (no per-node icons exist). Drives node dots + branch column accents.
func _branch_accent(branch_id: String) -> Color:
	match branch_id:
		"engineering": return Color(0.40, 0.85, 0.55)
		"combat":      return Color(1.00, 0.45, 0.45)
		"recursion":   return Color(0.78, 0.55, 1.00)
		_:             return COLOR_GOLD


# Compact prestige-vital chip: "CAPTION  value" on ONE line. Value clips (never
# wraps) so the command band can't grow and steal the tree's height. Returns the
# value label ref for live updates.
func _make_stat_chip(caption: String, accent: Color) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.14, 0.85)
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	var edge := accent
	edge.a = 0.32
	sb.border_color = edge
	sb.border_width_left = 3
	sb.content_margin_left = 11
	sb.content_margin_right = 11
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	panel.add_child(h)

	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 9)
	cap.add_theme_color_override("font_color", Color(0.55, 0.58, 0.66))
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(cap)

	var val := Label.new()
	val.add_theme_font_size_override("font_size", 14)
	val.add_theme_color_override("font_color", accent)
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.clip_text = true   # EXPAND_FILL + clip (NOT shrink) → fills its share, truncates overflow
	val.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(val)

	return {"panel": panel, "value": val}


# Compact pill button (used for BUY / UP in node cards).
func _style_pill_button(btn: Button, color: Color) -> void:
	for st in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		var bg := color
		if st == "normal":
			bg.a = 0.18
		elif st == "hover":
			bg.a = 0.32
		else:
			bg.a = 0.48
		s.bg_color = bg
		s.set_corner_radius_all(3)
		s.set_border_width_all(1)
		var bd := color
		bd.a = 0.7
		s.border_color = bd
		s.content_margin_left = 8
		s.content_margin_right = 8
		s.content_margin_top = 2
		s.content_margin_bottom = 2
		btn.add_theme_stylebox_override(st, s)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", color.lightened(0.35))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)


# Retint + show a node card's status chip (and hide its buy button).
func _set_chip(w: Dictionary, text: String, color: Color) -> void:
	w["btn"].visible = false
	w["chip_panel"].visible = true
	var lbl: Label = w["chip_lbl"]
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	var csb: StyleBoxFlat = w["chip_sb"]
	var bg := color
	bg.a = 0.15
	csb.bg_color = bg
	var bd := color
	bd.a = 0.45
	csb.border_color = bd


# ─── COMMAND BAND: cycle + shards + vital chips + progress + actions ─────────
# One compact console band — was three stacked panels (header + readiness +
# buttons). The big KEEPS/RESETS panels are GONE: that ledger is shown in full,
# colour-coded, in the Singularity's entry-confirm modal on the Sector Chart
# (v138), so here it's just a one-line reminder. Collapsing the summary frees the
# lower ~480px of the viewport for the Mastery Tree (the actual interaction).
func _build_command_band():
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_FILL
	panel.size_flags_vertical = Control.SIZE_FILL   # sizes to content; the tree owns all vertical slack
	_col.add_child(panel)

	var mc = MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 20)
	mc.add_theme_constant_override("margin_right", 20)
	mc.add_theme_constant_override("margin_top", 10)
	mc.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(mc)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	mc.add_child(v)

	# Row A: cycle (left) ····· big shard readout (right).
	var row_a = HBoxContainer.new()
	row_a.add_theme_constant_override("separation", 12)
	v.add_child(row_a)
	_cycle_lbl = Label.new()
	_cycle_lbl.add_theme_font_size_override("font_size", 12)
	_cycle_lbl.add_theme_color_override("font_color", COLOR_DIM)
	_cycle_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row_a.add_child(_cycle_lbl)
	var sp_a = Control.new()
	sp_a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_a.add_child(sp_a)
	_shards_big_lbl = Label.new()
	_shards_big_lbl.add_theme_font_size_override("font_size", 24)
	_shards_big_lbl.add_theme_color_override("font_color", COLOR_SHARD)
	_shards_big_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row_a.add_child(_shards_big_lbl)

	# Row B: the three prestige vitals as inline chips.
	var chips = HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(chips)
	var c_tier = _make_stat_chip(tr("TIER"), COLOR_SHARD)
	_tier_val = c_tier["value"]; chips.add_child(c_tier["panel"])
	var c_reso = _make_stat_chip(tr("RESONANCE"), COLOR_SHARD)
	_reso_val = c_reso["value"]; chips.add_child(c_reso["panel"])
	var c_pot = _make_stat_chip(tr("POTENTIAL"), COLOR_SHARD)
	_gain_big_lbl = c_pot["value"]; chips.add_child(c_pot["panel"])

	# Row C: progress-to-next-shard bar + caption (one row).
	var row_c = HBoxContainer.new()
	row_c.add_theme_constant_override("separation", 10)
	v.add_child(row_c)
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 10)
	_progress_bar.show_percentage = false
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.apply_progress_bar_style(_progress_bar, "research")
	row_c.add_child(_progress_bar)
	_progress_lbl = Label.new()
	_progress_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_progress_lbl.add_theme_font_size_override("font_size", 10)
	_progress_lbl.add_theme_color_override("font_color", COLOR_DIM)
	_progress_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row_c.add_child(_progress_lbl)

	# One-line keeps/resets reminder (full colour-coded ledger lives in the modal).
	var kr = Label.new()
	kr.text = tr("KEEPS  Research · Ships · Exotic Matter · Mastery          RESETS  Liras · Buildings · Resources · Skill levels (30% XP)")
	kr.add_theme_font_size_override("font_size", 9)
	kr.add_theme_color_override("font_color", Color(0.52, 0.55, 0.62))
	kr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kr.clip_text = true
	kr.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(kr)

	# Row D: Return (quiet) + the Singularity status line (v138 — the warp itself
	# happens on the Sector Chart; this row only REPORTS whether a rift is open).
	var row_d = HBoxContainer.new()
	row_d.alignment = BoxContainer.ALIGNMENT_CENTER
	row_d.add_theme_constant_override("separation", 14)
	v.add_child(row_d)
	_back_btn = Button.new()
	_back_btn.text = tr("← Return")
	_back_btn.custom_minimum_size = Vector2(120, 40)
	UITheme.apply_premium_button_style(_back_btn, "engineering")
	_back_btn.add_theme_font_size_override("font_size", 12)
	_back_btn.pressed.connect(_on_back_btn_pressed)
	row_d.add_child(_back_btn)
	_rift_status_lbl = Label.new()
	_rift_status_lbl.text = tr("NO SINGULARITY DETECTED THIS RUN")
	_rift_status_lbl.custom_minimum_size = Vector2(340, 44)
	_rift_status_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rift_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rift_status_lbl.add_theme_font_size_override("font_size", 13)
	_rift_status_lbl.add_theme_color_override("font_color", Color(0.55, 0.58, 0.68))
	row_d.add_child(_rift_status_lbl)

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
	title.text = tr("FIRST WARP — WHAT YOU'LL UNLOCK")
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["mission"])
	v.add_child(title)

	var bullets = Label.new()
	bullets.text = tr("• Prestige multipliers (Production / Combat / Gathering / XP)\n• Warp Tier scaling (doubles every 5 warps)\n• Starting resource package on each future warp")
	bullets.add_theme_font_size_override("font_size", 11)
	bullets.add_theme_color_override("font_color", Color(0.78, 0.86, 0.82))
	v.add_child(bullets)

	_apply_flat_panel(_first_warp_panel, UITheme.CATEGORY_COLORS["mission"])


# ─── TREE: tabbed branches + grid — fits the viewport, no page scroll ────────
func _build_tree_section():
	_tree_panel = PanelContainer.new()
	_tree_panel.size_flags_horizontal = Control.SIZE_FILL
	_tree_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL   # fills the remaining height
	_col.add_child(_tree_panel)

	var outer = MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer.add_theme_constant_override(k, 12)
	_tree_panel.add_child(outer)

	var c = VBoxContainer.new()
	c.add_theme_constant_override("separation", 8)
	outer.add_child(c)

	# Title + AVAILABLE/SPENT/EARNED on ONE row to save vertical space.
	var head_row = HBoxContainer.new()
	c.add_child(head_row)
	var title = Label.new()
	title.text = tr("[ WARP MASTERY TREE ]")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	head_row.add_child(title)
	_avail_label = Label.new()
	_avail_label.add_theme_font_size_override("font_size", 12)
	_avail_label.add_theme_color_override("font_color", Color.WHITE)
	_avail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head_row.add_child(_avail_label)

	# Branch tab bar (segmented) — show one branch at a time.
	var tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_child(tabs)
	tabs.add_child(_make_tab_button("engineering", tr("ENGINEERING")))
	tabs.add_child(_make_tab_button("combat", tr("COMBAT")))
	tabs.add_child(_make_tab_button("recursion", tr("RECURSION")))

	# Contained node area: the PAGE never scrolls. Each branch's nodes lay in a
	# 2-column grid (so e.g. Recursion's ~13 nodes are ~7 rows, not 13). Only the
	# densest branch might scroll a little — and only inside this box.
	var node_scroll = ScrollContainer.new()
	node_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	node_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.add_child(node_scroll)

	var stack = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node_scroll.add_child(stack)

	for branch_id in ["engineering", "combat", "recursion"]:
		stack.add_child(_build_branch_grid(branch_id))

	_lock_msg = Label.new()
	_lock_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lock_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lock_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lock_msg.custom_minimum_size = Vector2(0, 90)
	_lock_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lock_msg.add_theme_font_size_override("font_size", 14)
	_lock_msg.add_theme_color_override("font_color", COLOR_LOCKED)
	_lock_msg.visible = false
	stack.add_child(_lock_msg)

	UITheme.apply_card_style(_tree_panel, "research")
	_show_branch("engineering")


# Segmented branch tab — active state uses the toggle "pressed" stylebox.
func _make_tab_button(branch_id: String, label: String) -> Button:
	var accent: Color = _branch_accent(branch_id)
	var b = Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 13)
	b.text = label
	for st in ["normal", "hover", "pressed"]:
		var s = StyleBoxFlat.new()
		var bg := accent
		if st == "normal":
			bg.a = 0.0
		elif st == "hover":
			bg.a = 0.16
		else:
			bg.a = 0.28
		s.bg_color = bg
		s.set_corner_radius_all(3)
		s.set_border_width_all(1)
		var bd := accent
		bd.a = 0.25 if st == "normal" else 0.65
		s.border_color = bd
		s.content_margin_top = 9
		s.content_margin_bottom = 9
		s.content_margin_left = 8
		s.content_margin_right = 8
		b.add_theme_stylebox_override(st, s)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", COLOR_DIM)
	b.add_theme_color_override("font_pressed_color", accent.lightened(0.3))
	b.add_theme_color_override("font_hover_color", accent.lightened(0.2))
	b.pressed.connect(func(): _show_branch(branch_id))
	_branch_tabs[branch_id] = b
	return b


func _build_branch_grid(branch_id: String) -> Control:
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for node_id in _wm.TREE_NODES:
		if str(_wm.TREE_NODES[node_id].get("branch", "")) != branch_id:
			continue
		grid.add_child(_build_node_card(node_id))
	_branch_grids[branch_id] = grid
	return grid


# Switch the visible branch. A locked (not-yet-revealed) branch hides its grid
# and shows the lock message instead.
func _show_branch(branch_id: String) -> void:
	_active_branch = branch_id
	var revealed: bool = _wm.is_branch_revealed(branch_id)
	for b in _branch_grids:
		_branch_grids[b].visible = (b == branch_id and revealed)
	if _lock_msg != null:
		_lock_msg.visible = not revealed
		if not revealed:
			_lock_msg.text = tr("[ LOCKED ]   This branch unlocks at Warp #%d") % int(_wm.BRANCH_REVEAL_WARP.get(branch_id, 1))
	for b in _branch_tabs:
		_branch_tabs[b].button_pressed = (b == branch_id)


func _build_node_card(node_id: String) -> Control:
	var node_data = _wm.TREE_NODES[node_id]
	var accent: Color = _branch_accent(str(node_data.get("branch", "")))

	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.16, 0.95)
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.border_color = COLOR_LOCKED
	sb.border_width_left = 4            # branch-accent stripe set per-state in refresh
	sb.content_margin_left = 11
	sb.content_margin_right = 11
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", sb)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	card.add_child(v)

	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)

	# Branch-accent node dot — the only categorical signal available (no per-node
	# icons exist), so it colour-codes which branch a card belongs to at a glance.
	var dot = ColorRect.new()
	dot.color = accent
	dot.custom_minimum_size = Vector2(7, 7)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)

	var t = Label.new()
	t.text = tr(str(node_data.get("name", "")))   # player-facing name only (no internal ENG_1/CMB_2 id)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("font_size", 14)
	t.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(t)

	# Buy/Up button (shown only when affordable) — compact gold pill.
	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 12)
	_style_pill_button(btn, COLOR_AFFORD)
	btn.pressed.connect(func(): _on_buy_pressed(node_id))
	row.add_child(btn)

	# Status chip (shown otherwise) — a recolourable pill: ✓ ACQUIRED / SOON /
	# Need n / MAX, etc. Stylebox + label stored so _refresh_node can retint it.
	var chip_panel = PanelContainer.new()
	chip_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	chip_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var chip_sb = StyleBoxFlat.new()
	chip_sb.set_corner_radius_all(3)
	chip_sb.set_border_width_all(1)
	chip_sb.content_margin_left = 6
	chip_sb.content_margin_right = 6
	chip_sb.content_margin_top = 2
	chip_sb.content_margin_bottom = 2
	chip_panel.add_theme_stylebox_override("panel", chip_sb)
	var chip_lbl = Label.new()
	chip_lbl.add_theme_font_size_override("font_size", 11)
	chip_panel.add_child(chip_lbl)
	row.add_child(chip_panel)

	var desc = Label.new()
	desc.text = tr(str(node_data.get("desc", "")))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.72, 0.75, 0.82))
	v.add_child(desc)

	_node_widgets[node_id] = {
		"root": card, "style": sb, "btn": btn, "title": t, "dot": dot,
		"chip_panel": chip_panel, "chip_sb": chip_sb, "chip_lbl": chip_lbl,
	}
	return card


# ─── Refresh / update ─────────────────────────────────────────────────────
func _update_all():
	_refresh_header()
	_refresh_first_warp_visibility()
	_refresh_readiness()
	_refresh_gains_preview()
	_refresh_tree()
	if _feed_picker != null:
		_populate_feed_picker()   # v134h: refresh feedable-material owned counts


func _refresh_header():
	var n = int(_wm.total_warps)
	_cycle_lbl.text = tr("WARP CYCLE   #%d   ▸   #%d") % [n, n + 1]
	_shards_big_lbl.text = tr("◈   %.1f   EXOTIC SHARDS") % _wm.warp_shards
	var tier = 0
	if _wm.has_method("get_warp_tier"):
		tier = int(_wm.get_warp_tier())
	var prod_pct = (_wm.get_production_multiplier() - 1.0) * 100.0
	_tier_val.text = tr("×%d  ·  +%.0f%% prod") % [int(pow(2, tier)), prod_pct]


func _refresh_first_warp_visibility():
	_first_warp_panel.visible = (int(_wm.total_warps) == 0)


func _refresh_readiness():
	var gains = int(_wm.calculate_warp_gains())
	# POTENTIAL chip.
	if gains > 0:
		_gain_big_lbl.text = tr("+%d %s · READY") % [gains, _shard_label(gains)]
		_gain_big_lbl.add_theme_color_override("font_color", COLOR_SHARD.lightened(0.1))
	else:
		_gain_big_lbl.text = tr("— not ready")
		_gain_big_lbl.add_theme_color_override("font_color", Color(0.78, 0.62, 0.62))

	# RESONANCE chip: charge you've fed into the Core + the bonus shards it's worth.
	# v134h: no more passive "~/s draw rate" — charge only accrues from manual feeding.
	if _wm != null and _reso_val != null:
		var bonus := int(_wm.get_charge_bonus_shards(gains))
		_reso_val.text = tr("%s  +%d◈") % [FormatUtils.format_number(_wm.warp_charge), bonus]


# v135a: gains-forward preview — the reward, shown before the loss ledger. Pure
# neutral state (shards, standing multipliers, starter package). No "warp now" nag.
func _build_gains_preview():
	_gains_panel = PanelContainer.new()
	_gains_panel.name = "GainsPreview"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.13, 0.12, 0.55)
	sb.border_color = COLOR_SHARD
	sb.border_color.a = 0.35
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	_gains_panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	_gains_panel.add_child(vb)
	var hdr := Label.new()
	hdr.text = tr("◈ WARP REWARDS")
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", COLOR_SHARD)
	vb.add_child(hdr)
	_gains_shards_lbl = Label.new()
	_gains_shards_lbl.add_theme_font_size_override("font_size", 15)
	_gains_shards_lbl.add_theme_color_override("font_color", COLOR_KEEPS)
	vb.add_child(_gains_shards_lbl)
	_gains_mult_lbl = Label.new()
	_gains_mult_lbl.add_theme_font_size_override("font_size", 11)
	_gains_mult_lbl.add_theme_color_override("font_color", UITheme.COLORS.get("text_main", Color(0.85, 0.9, 0.95)))
	vb.add_child(_gains_mult_lbl)
	_gains_starter_lbl = Label.new()
	_gains_starter_lbl.add_theme_font_size_override("font_size", 10)
	_gains_starter_lbl.add_theme_color_override("font_color", COLOR_DIM)
	vb.add_child(_gains_starter_lbl)
	_col.add_child(_gains_panel)
	_refresh_gains_preview()

func _refresh_gains_preview():
	if _gains_shards_lbl == null or _wm == null:
		return
	var base := int(_wm.calculate_warp_gains())
	var bonus := int(_wm.get_charge_bonus_shards(base))
	var total := base + bonus
	if total > 0:
		var extra := (tr("   (%d + %d Resonance)") % [base, bonus]) if bonus > 0 else ""
		_gains_shards_lbl.text = tr("+%d %s%s") % [total, _shard_label(total), extra]
		_gains_shards_lbl.add_theme_color_override("font_color", COLOR_KEEPS)
	else:
		_gains_shards_lbl.text = tr("— not ready yet")
		_gains_shards_lbl.add_theme_color_override("font_color", Color(0.78, 0.62, 0.62))
	# v135b: the warp-manager multiplier getters are untyped (return Variant), so
	# ":=" infers Variant and the project's warnings-as-errors rejects it — the
	# whole warp_page failed to load. Explicit float typing (the documented gotcha).
	var prod: float = (_wm.get_production_multiplier() - 1.0) * 100.0
	var comb: float = (_wm.get_combat_multiplier() - 1.0) * 100.0
	var gath: float = (_wm.get_gathering_multiplier() - 1.0) * 100.0
	var xpm: float = (_wm.get_xp_multiplier() - 1.0) * 100.0
	_gains_mult_lbl.text = tr("Standing bonuses  +%.0f%% Prod · +%.0f%% Combat · +%.0f%% Gather · +%.0f%% XP") % [prod, comb, gath, xpm]
	var starter_mult := 1.0
	if _wm.has_method("get_tree_starter_mult"):
		starter_mult = _wm.get_tree_starter_mult()
	var proj_shards: float = _wm.warp_shards + float(total)
	_gains_starter_lbl.text = tr("Starter package on reset: %s credits + Fe / Si / Wood / Water") % FormatUtils.format_number(int(proj_shards * 5000.0 * starter_mult))

# Per-frame live values: progress bar + Singularity status line.
func _update_dynamic():
	if _rift_status_lbl == null: return
	var gains = int(_wm.calculate_warp_gains())
	# v138: passive rift state — the warp happens on the Sector Chart, this reports it.
	if _wm.rift_open and gains > 0:
		var s = "" if gains == 1 else "s"
		_rift_status_lbl.text = tr("◈  SINGULARITY OPEN — enter it on the Sector Chart  (+%d shard%s)") % [gains, s]
		_rift_status_lbl.add_theme_color_override("font_color", Color(0.78, 0.55, 1.0))
	else:
		_rift_status_lbl.text = tr("NO SINGULARITY DETECTED THIS RUN")
		_rift_status_lbl.add_theme_color_override("font_color", Color(0.55, 0.58, 0.68))

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
	_progress_lbl.text = tr("%s / %s   (toward +%d %s)") % [
		FormatUtils.format_number(score),
		FormatUtils.format_number(next_thr),
		gains + 1,
		tr("shard") if gains + 1 == 1 else tr("shards")
	]
	# Refresh readiness label too (gains can change live).
	_refresh_readiness()
	_refresh_gains_preview()


# Mirrors warp_manager.calculate_warp_gains() score computation exactly.
func _compute_progress_score() -> float:
	var total_credits = GameState.resources.lifetime_credits - _wm.credits_at_warp_start
	var building_count = 0
	for bid in GameState.infrastructure_manager.buildings:
		building_count += GameState.infrastructure_manager.buildings[bid]
	return float(total_credits) + float(building_count) * 1000.0


# ─── v134h: Feed the Core (manual charge deposit) ──────────────────────────
# Replaces the removed always-on auto-drain. The player deliberately deposits
# surplus feedable materials here for warp_charge → bonus shards at the next warp.
func _build_feed_core_section():
	var panel := PanelContainer.new()
	_feed_panel = panel
	_apply_flat_panel(panel, COLOR_SHARD)
	_col.add_child(panel)

	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 18)
	mc.add_theme_constant_override("margin_right", 18)
	mc.add_theme_constant_override("margin_top", 12)
	mc.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(mc)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	mc.add_child(vb)

	var title := Label.new()
	title.text = tr("FEED THE CORE")
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", COLOR_SHARD)
	vb.add_child(title)

	var sub := Label.new()
	sub.text = tr("Pour surplus materials into the Core — accrues Resonance, redeemed as bonus shards at your next Warp. Your stockpiles are never touched unless you feed them.")
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", COLOR_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sub)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)

	_feed_picker = OptionButton.new()
	_feed_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feed_picker.item_selected.connect(_on_feed_picker_changed)
	row.add_child(_feed_picker)

	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(30, 30)
	_style_pill_button(minus, COLOR_SHARD)
	minus.pressed.connect(func(): if _feed_spin: _feed_spin.value = max(0.0, _feed_spin.value - _feed_step()))
	row.add_child(minus)

	_feed_spin = SpinBox.new()
	_feed_spin.min_value = 0
	_feed_spin.max_value = 1e15
	_feed_spin.step = 1
	_feed_spin.custom_minimum_size = Vector2(96, 30)
	if UITheme.has_method("apply_input_style"):
		UITheme.apply_input_style(_feed_spin.get_line_edit(), "research")
	_feed_spin.value_changed.connect(_on_feed_amount_changed)
	row.add_child(_feed_spin)

	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(30, 30)
	_style_pill_button(plus, COLOR_SHARD)
	plus.pressed.connect(func(): if _feed_spin: _feed_spin.value = min(_feed_owned(), _feed_spin.value + _feed_step()))
	row.add_child(plus)

	var maxb := Button.new()
	maxb.text = tr("MAX")
	maxb.custom_minimum_size = Vector2(46, 30)
	_style_pill_button(maxb, COLOR_SHARD)
	maxb.pressed.connect(func(): if _feed_spin: _feed_spin.value = _feed_owned())
	row.add_child(maxb)

	_feed_preview = Label.new()
	_feed_preview.add_theme_font_size_override("font_size", 11)
	_feed_preview.add_theme_color_override("font_color", COLOR_SHARD)
	_feed_preview.custom_minimum_size = Vector2(96, 0)
	_feed_preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_feed_preview)

	_feed_btn = Button.new()
	_feed_btn.text = tr("FEED")
	_feed_btn.custom_minimum_size = Vector2(62, 30)
	_style_pill_button(_feed_btn, COLOR_SHARD)
	_feed_btn.pressed.connect(_on_feed_pressed)
	row.add_child(_feed_btn)

	_populate_feed_picker()


# Rebuild the material dropdown from CHARGE_WEIGHT, showing only owned mats.
func _populate_feed_picker():
	if _feed_picker == null: return
	var prev_sym := _feed_sym()
	_feed_syms.clear()
	_feed_picker.clear()
	for sym in _wm.CHARGE_WEIGHT:
		var owned: float = GameState.resources.get_element_amount(sym)
		if owned <= 0.0: continue
		var w: float = float(_wm.CHARGE_WEIGHT[sym])
		_feed_picker.add_item("%s  ×%s  (%s◈/u)" % [
			ElementDB.get_display_name(sym),
			FormatUtils.format_number(owned),
			FormatUtils.format_number(w)])
		_feed_syms.append(sym)
	if _feed_syms.is_empty():
		_feed_picker.add_item("— no surplus to feed —")
		_feed_picker.disabled = true
		if _feed_btn: _feed_btn.disabled = true
	else:
		_feed_picker.disabled = false
		if _feed_btn: _feed_btn.disabled = false
		var idx := _feed_syms.find(prev_sym)
		if idx >= 0: _feed_picker.selected = idx
	_refresh_feed_preview()


func _feed_sym() -> String:
	if _feed_picker == null or _feed_syms.is_empty(): return ""
	var i := _feed_picker.selected
	if i < 0 or i >= _feed_syms.size(): return ""
	return str(_feed_syms[i])


func _feed_owned() -> float:
	var s := _feed_sym()
	if s == "": return 0.0
	return GameState.resources.get_element_amount(s)


func _feed_step() -> float:
	return max(1.0, floor(_feed_owned() * 0.1))


func _on_feed_picker_changed(_idx: int):
	if _feed_spin: _feed_spin.value = 0
	_refresh_feed_preview()


func _on_feed_amount_changed(v: float):
	var owned := _feed_owned()
	if v > owned and _feed_spin:
		_feed_spin.value = owned   # clamp (re-enters with clamped value)
		return
	_refresh_feed_preview()


func _refresh_feed_preview():
	if _feed_preview == null: return
	var s := _feed_sym()
	var amt: float = (_feed_spin.value if _feed_spin else 0.0)
	if s == "" or amt <= 0.0:
		_feed_preview.text = ""
		return
	_feed_preview.text = tr("= +%s◈") % FormatUtils.format_number(_wm.charge_value(s, amt))


func _on_feed_pressed():
	var s := _feed_sym()
	if s == "": return
	var amt: float = (_feed_spin.value if _feed_spin else 0.0)
	if amt <= 0.0: return
	var gained: float = _wm.feed_core(s, amt)
	if gained > 0.0:
		if _feed_spin: _feed_spin.value = 0
		_update_all()   # refreshes picker counts + RESONANCE chip


# ─── Tree refresh (4-state cascade preserved) ─────────────────────────────
func _refresh_tree():
	if _tree_panel == null: return
	var avail_n = int(_wm.get_available_shards())
	_avail_label.text = tr("AVAILABLE %d %s  ·  SPENT %d  ·  EARNED %d") % [
		avail_n, _shard_label(avail_n),
		int(_wm.warp_shards_spent),
		int(_wm.warp_shards),
	]

	# Per-branch owned/total → tab labels (locked branches show no count).
	var owned_by_branch: Dictionary = {}
	var total_by_branch: Dictionary = {}
	for node_id in _wm.TREE_NODES:
		var b: String = str(_wm.TREE_NODES[node_id].get("branch", ""))
		total_by_branch[b] = int(total_by_branch.get(b, 0)) + 1
		if _wm.is_node_purchased(node_id):
			owned_by_branch[b] = int(owned_by_branch.get(b, 0)) + 1
	for branch_id in _branch_tabs:
		var tab = _branch_tabs[branch_id]
		var base: String = branch_id.to_upper()
		if _wm.is_branch_revealed(branch_id):
			tab.text = tr("%s  %d/%d") % [base, int(owned_by_branch.get(branch_id, 0)), int(total_by_branch.get(branch_id, 0))]
		else:
			tab.text = tr("%s  ·  LOCKED") % base

	# Re-apply the active branch's reveal/visibility (a warp may have just
	# revealed it), then repaint every node.
	_show_branch(_active_branch)
	for node_id in _node_widgets:
		_refresh_node(node_id)


func _refresh_node(node_id: String):
	var w = _node_widgets[node_id]
	var sb = w["style"]
	var btn = w["btn"]
	var dot = w["dot"]
	var node_data = _wm.TREE_NODES[node_id]
	var accent: Color = _branch_accent(str(node_data.get("branch", "")))
	var is_rep: bool = _wm._is_repeatable(node_id)
	var lvl: int = _wm.get_node_level(node_id)
	var cost: int = int(_wm.get_node_cost(node_id))   # v122: next-level cost for repeatables

	# Title shows the current level on repeatable spines.
	var nm: String = str(node_data.get("name", ""))
	w["title"].text = ("%s  ·  Lv %d" % [nm, lvl]) if (is_rep and lvl > 0) else nm

	# Border = STATE colour; dot = BRANCH colour (lit only when the node is live).
	dot.color = COLOR_LOCKED

	# Unimplemented stub.
	if not _wm.is_node_implemented(node_id):
		sb.border_color = COLOR_LOCKED
		sb.bg_color = Color(0.09, 0.10, 0.13, 0.90)
		btn.visible = false
		_set_chip(w, "SOON · %d ◈" % cost, COLOR_LOCKED)
		return

	# Affordable (next level for repeatables, or first buy for finite).
	if _wm.can_purchase_node(node_id):
		sb.border_color = COLOR_AFFORD
		sb.bg_color = Color(0.13, 0.11, 0.06, 0.95)
		dot.color = accent
		btn.visible = true
		btn.disabled = false
		btn.text = ("UP · %d ◈" % cost) if is_rep else ("BUY · %d ◈" % cost)
		w["chip_panel"].visible = false
		return

	# Not purchasable now: fully owned/maxed, or gated, or unaffordable.
	btn.visible = false
	var at_cap: bool = false
	if is_rep:
		var cap: int = int(node_data.get("cap", 0))
		at_cap = cap > 0 and lvl >= cap
	if (not is_rep and _wm.is_node_purchased(node_id)) or at_cap:
		sb.border_color = COLOR_PURCHASED
		sb.bg_color = Color(0.08, 0.16, 0.10, 0.95)
		dot.color = accent
		_set_chip(w, ("MAX · Lv %d" % lvl) if is_rep else "ACQUIRED", COLOR_PURCHASED)
	else:
		sb.border_color = COLOR_LOCKED
		sb.bg_color = Color(0.10, 0.11, 0.16, 0.95)
		var avail: int = int(_wm.get_available_shards())
		if avail < cost:
			_set_chip(w, "Need %d ◈" % (cost - avail), COLOR_LOCKED)
		else:
			_set_chip(w, tr("Locked"), COLOR_LOCKED)   # prereq / branch gate


func _shard_label(n: int) -> String:
	return "Shard" if abs(n) == 1 else "Shards"


# ─── Actions ──────────────────────────────────────────────────────────────
# (v138: the execute-warp button + confirm moved to the Sector Chart — entering
# the Singularity is the warp. This page only spends shards and monitors.)

func _on_back_btn_pressed():
	if get_tree().current_scene.has_method("switch_to"):
		get_tree().current_scene.switch_to("mission")


func _on_warped(gains):
	_update_all()
	UITheme.trigger_circuit_surge(_shards_big_lbl)
	# Brief celebratory text on the readiness panel so the dopamine moment lands.
	var s = "" if gains == 1 else "s"
	_gain_big_lbl.text = tr("WARP COMPLETE · +%d SHARD%s") % [gains, s]
	_gain_big_lbl.add_theme_color_override("font_color", COLOR_PURCHASED)


func _on_node_purchased(_node_id: String):
	_refresh_tree()


func _on_buy_pressed(node_id: String):
	if _wm.purchase_node(node_id):
		UITheme.trigger_circuit_surge(_avail_label)
