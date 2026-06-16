extends Control
# Fleet page — P1 scaffold (roster + build sink). See docs/FLEET_SIEGE_GATES.md.
# UI is code-built (mirrors warp_page). Structure (which hulls/ships exist) is
# rebuilt on fleet_changed / page-enter; per-frame state (affordability) is a
# light poll so Build buttons unlock as materials accrue — no list rebuild, no
# flicker.

var _mgr
var _cap_lbl: Label
var _power_lbl: Label
var _build_rows: Array = []   # [{hid, btn, cost_lbl}]
var _build_list: VBoxContainer
var _roster_list: VBoxContainer
var _poll: float = 0.0

func _ready() -> void:
	_mgr = GameState.fleet_manager
	_build_ui()
	if _mgr and not _mgr.fleet_changed.is_connected(_on_fleet_changed):
		_mgr.fleet_changed.connect(_on_fleet_changed)
	_rebuild()

func on_page_enter() -> void:
	_rebuild()

func _process(delta: float) -> void:
	if not visible: return
	_poll += delta
	if _poll >= 0.5:
		_poll = 0.0
		_update_states()

func _on_fleet_changed() -> void:
	_rebuild()

# ── UI construction ─────────────────────────────────────────────────────────
func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_FILL
	scroll.size_flags_vertical = Control.SIZE_FILL
	margin.add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Concrete min width — without it the autowrap labels collapse the column to
	# zero width inside the ScrollContainer and the whole page renders empty
	# (matches the warp_page scaffold).
	col.custom_minimum_size = Vector2(720, 0)
	col.add_theme_constant_override("separation", 12)
	scroll.add_child(col)

	var title := Label.new()
	title.text = "FLEET COMMAND"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	col.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Forge your material surplus into a battle-fleet. Capacity grows with every Warp. Each ship adds +25% of your ship's damage in combat (up to +100%)."
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(subtitle)

	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 28)
	col.add_child(status)
	_cap_lbl = Label.new()
	_cap_lbl.add_theme_font_size_override("font_size", 16)
	status.add_child(_cap_lbl)
	_power_lbl = Label.new()
	_power_lbl.add_theme_font_size_override("font_size", 16)
	_power_lbl.add_theme_color_override("font_color", Color(1.0, 0.84, 0.4))
	status.add_child(_power_lbl)

	var build_hdr := Label.new()
	build_hdr.text = "BUILD  (consumes your surplus)"
	build_hdr.add_theme_font_size_override("font_size", 13)
	build_hdr.add_theme_color_override("font_color", Color(0.5, 0.7, 0.95))
	col.add_child(build_hdr)
	_build_list = VBoxContainer.new()
	_build_list.add_theme_constant_override("separation", 6)
	col.add_child(_build_list)

	var roster_hdr := Label.new()
	roster_hdr.text = "ROSTER"
	roster_hdr.add_theme_font_size_override("font_size", 13)
	roster_hdr.add_theme_color_override("font_color", Color(0.5, 0.7, 0.95))
	col.add_child(roster_hdr)
	_roster_list = VBoxContainer.new()
	_roster_list.add_theme_constant_override("separation", 4)
	col.add_child(_roster_list)

# ── Structure (rebuild on change) ───────────────────────────────────────────
func _rebuild() -> void:
	if not _mgr or not is_instance_valid(_build_list): return
	_build_rows.clear()
	for c in _build_list.get_children(): c.queue_free()
	for hid in _mgr.get_buildable_hulls():
		_build_list.add_child(_make_build_row(String(hid)))
	_rebuild_roster()
	_update_states()

func _make_build_row(hid: String) -> Control:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var name_lbl := Label.new()
	name_lbl.text = "%s   ·   Power %s" % [_mgr.get_hull_name(hid), FormatUtils.format_number(_mgr.get_hull_power(hid))]
	name_lbl.add_theme_font_size_override("font_size", 14)
	info.add_child(name_lbl)

	var cost_lbl := Label.new()
	cost_lbl.add_theme_font_size_override("font_size", 11)
	cost_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(cost_lbl)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(120, 0)
	btn.pressed.connect(func():
		if _mgr.build_ship(hid):
			_rebuild()
	)
	row.add_child(btn)

	_build_rows.append({"hid": hid, "btn": btn, "cost_lbl": cost_lbl})
	return panel

func _rebuild_roster() -> void:
	for c in _roster_list.get_children(): c.queue_free()
	if _mgr.get_fleet_count() == 0:
		var empty := Label.new()
		empty.text = "No ships yet — build your first hull above."
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
		_roster_list.add_child(empty)
		return
	var idx := 0
	for s in _mgr.ships:
		_roster_list.add_child(_make_roster_row(idx, String(s.get("hull_id", ""))))
		idx += 1

func _make_roster_row(index: int, hid: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lbl := Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.text = "   ⟢  %s   (Power %s)" % [_mgr.get_hull_name(hid), FormatUtils.format_number(_mgr.get_hull_power(hid))]
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)
	var scrap := Button.new()
	scrap.text = "Scrap"
	scrap.add_theme_font_size_override("font_size", 10)
	scrap.pressed.connect(func():
		if _mgr.scrap_ship(index):
			_rebuild()
	)
	row.add_child(scrap)
	return row

# ── State (light poll: affordability only, no rebuild) ──────────────────────
func _update_states() -> void:
	if not _mgr or not is_instance_valid(_cap_lbl): return
	var count: int = _mgr.get_fleet_count()
	var cap: int = _mgr.get_fleet_capacity()
	_cap_lbl.text = "Fleet:  %d / %d" % [count, cap]
	_cap_lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0) if count < cap else Color(1.0, 0.6, 0.4))
	# v112 P2: fleet now contributes to combat — show the live +X% damage bonus.
	var bonus_pct: int = _mgr.get_combat_bonus_pct() if _mgr.has_method("get_combat_bonus_pct") else 0
	if bonus_pct > 0:
		_power_lbl.text = "Fleet Strength:  %s  ·  +%d%% ship damage in combat" % [FormatUtils.format_number(_mgr.get_fleet_power()), bonus_pct]
	else:
		_power_lbl.text = "Fleet Strength:  %s  ·  build ships to add combat damage" % FormatUtils.format_number(_mgr.get_fleet_power())
	var full: bool = count >= cap
	for r in _build_rows:
		var btn: Button = r["btn"]
		if not is_instance_valid(btn): continue
		btn.text = "Cap Full" if full else "Build"
		btn.disabled = not _mgr.can_build(r["hid"])
		r["cost_lbl"].text = _format_cost(r["hid"])

# First-visit coach tour anchors (see CoachMarks.STEPS["fleet"]).
func get_coach_anchor(key: String) -> Control:
	match key:
		"build": return _build_list
		"power": return _power_lbl
		"capacity": return _cap_lbl
	return null

func _format_cost(hid: String) -> String:
	var parts: Array = []
	var cost: Dictionary = _mgr.get_hull_cost(hid)
	for res in cost:
		var have: float = GameState.resources.get_element_amount(res)
		var need := float(cost[res])
		var tag := "%s %s" % [FormatUtils.format_number(need), ElementDB.get_display_name(res)]
		parts.append(tag if have >= need else "✗ " + tag)
	return "   ".join(parts)
