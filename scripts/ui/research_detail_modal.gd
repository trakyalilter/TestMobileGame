extends Control
class_name ResearchDetailModal

# v111: Replaces hover-tooltip + click-to-unlock with a deliberate
# review-then-commit modal. Click a node → background dims, a centered card
# shows the structured EFFECTS / UNLOCKS / REQUIRES / FLAVOR breakdown plus
# colour-coded cost and a single RESEARCH button. Player commits explicitly.
#
# Self-contained: parents itself under ModalLayer (or current_scene as a
# fallback), tears down via queue_free on dismiss. All text rendering
# (tooltip builder, effect formatter, smart-linker) was moved here from
# research_node_widget.gd — the widget is now display-only.

signal closed

const PANEL_W: float = 440.0
const DIM_COLOR: Color = Color(0, 0, 0, 0.72)
const HDR_COL: String = "#FFC24D"
const HINT_COL: String = "#7FA39C"

var _nid: String = ""
var _data: Dictionary = {}
var _manager: RefCounted = null
var _parent_page: Node = null
var _is_repeatable: bool = false

var _action_btn: Button
var _card: PanelContainer
var _body_rt: RichTextLabel
var _cost_rt: RichTextLabel

# Smart-link popup state — mirrors the research_node_widget's old behaviour
# so terms inside the modal body still open click-popups for ships / items /
# modules / buildings.
var _active_info_card: Control = null
var _info_card_scene: PackedScene = preload("res://scenes/ui/info_card.tscn")


func _ready() -> void:
	# v111.2: set_anchors_AND_offsets_preset — the plain `set_anchors_preset`
	# only sets anchors and leaves offsets at whatever stale values the Control
	# was born with, so the rect never actually fills the viewport. Critical
	# here because ModalLayer is a CanvasLayer (not a Control), so the Control
	# uses the viewport as its anchor reference but ONLY if its rect spans it.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


# ─────────────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────────────
func start(nid: String, data: Dictionary, manager: RefCounted, parent_page: Node) -> void:
	_nid = nid
	_data = data
	_manager = manager
	_parent_page = parent_page
	_is_repeatable = manager and manager.repeatable_tech_db.has(nid)

	if not is_inside_tree():
		await tree_entered
	_build_ui()
	_refresh_state()
	# v111.1: 120ms fade-in so the player gets clear "something happened"
	# feedback between clicking the node and the card being fully readable.
	modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.12).set_trans(Tween.TRANS_QUAD)


# ─────────────────────────────────────────────────────────────────────
# UI construction
# ─────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	# Dim backdrop — captures clicks so the tree behind doesn't see them,
	# and dismisses the modal on click-outside-card.
	var dim := ColorRect.new()
	dim.color = DIM_COLOR
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	# v111.1: Use a full-rect CenterContainer to centre the card. The earlier
	# PRESET_CENTER on the card alone put the card's TOP-LEFT at the screen
	# centre — not the card's centre. CenterContainer auto-aligns its only
	# child's centre to its own centre, and mouse_filter=IGNORE lets clicks
	# pass through to the dim backdrop (so outside-card click still closes).
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(PANEL_W, 0)
	# Click-on-card should NOT dismiss → swallow events at the card.
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_card)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.039, 0.086, 0.078, 0.98)
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.border_color = Color(0.690, 0.420, 0.949, 0.90)     # research-branch violet
	sb.set_corner_radius_all(6)
	sb.shadow_color = Color(0, 0, 0, 0.70)
	sb.shadow_size = 22
	sb.shadow_offset = Vector2(0, 6)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	_card.add_theme_stylebox_override("panel", sb)
	# v111.13: removed a duplicate add_child(_card) here — the card is already
	# parented to `center` (CenterContainer) on line 97. The leftover direct
	# add_child triggered "already has a parent" and aborted modal build.

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_card.add_child(vb)

	# Header row: title + explicit close button
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	vb.add_child(hdr)

	var title := Label.new()
	title.text = str(_data.get("name", _nid))
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(0.690, 0.420, 0.949))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)

	# v111.1: Explicit ✕ close button. Click-outside-card and Escape still
	# work but a visible affordance is what the player expects to find.
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.add_theme_color_override("font_color", Color(0.498, 0.639, 0.612))
	close_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.392, 0.451))
	close_btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.30, 0.36))
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(_close)
	hdr.add_child(close_btn)

	# Category + tier sub-line (only if both present)
	var cat: String = str(_data.get("category", ""))
	var tier_val = _data.get("tier", null)
	if cat != "" or tier_val != null:
		var sub := Label.new()
		var parts: Array = []
		if tier_val != null:
			parts.append("T%s" % str(tier_val))
		if cat != "":
			parts.append(UITheme.tr_upper(tr(cat.capitalize())))
		sub.text = "  ·  ".join(parts)
		sub.add_theme_font_size_override("font_size", 10)
		sub.add_theme_color_override("font_color", Color(0.498, 0.639, 0.612))
		vb.add_child(sub)

	# Gold rule under the header
	var rule := ColorRect.new()
	rule.color = Color(0.690, 0.420, 0.949, 0.40)
	rule.custom_minimum_size = Vector2(0, 1)
	vb.add_child(rule)

	# Body — structured tooltip text (EFFECTS / UNLOCKS / REQUIRES / FLAVOR)
	_body_rt = RichTextLabel.new()
	_body_rt.bbcode_enabled = true
	_body_rt.fit_content = true
	_body_rt.scroll_active = false
	_body_rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_rt.custom_minimum_size = Vector2(PANEL_W - 44, 0)
	_body_rt.add_theme_font_size_override("normal_font_size", 12)
	_body_rt.add_theme_font_size_override("bold_font_size", 12)
	_body_rt.add_theme_font_size_override("italics_font_size", 12)
	_body_rt.add_theme_font_size_override("bold_italics_font_size", 12)
	_body_rt.add_theme_color_override("default_color", Color(0.894, 0.961, 0.933))
	_body_rt.text = _apply_smart_linking(_build_tooltip_text(_data))
	_body_rt.meta_hover_started.connect(_on_meta_hover)
	_body_rt.meta_hover_ended.connect(_on_meta_exit)
	vb.add_child(_body_rt)

	# Cost section (separate so colour-coded affordability is obvious)
	_cost_rt = RichTextLabel.new()
	_cost_rt.bbcode_enabled = true
	_cost_rt.fit_content = true
	_cost_rt.scroll_active = false
	_cost_rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cost_rt.custom_minimum_size = Vector2(PANEL_W - 44, 0)
	_cost_rt.add_theme_font_size_override("normal_font_size", 12)
	_cost_rt.add_theme_font_size_override("bold_font_size", 12)
	_cost_rt.add_theme_color_override("default_color", Color(0.894, 0.961, 0.933))
	_cost_rt.text = _build_cost_text()
	vb.add_child(_cost_rt)

	# Action button (RESEARCH / RESEARCHED / locked-state text)
	_action_btn = Button.new()
	_action_btn.add_theme_font_size_override("font_size", 14)
	_action_btn.custom_minimum_size = Vector2(0, 36)
	_action_btn.pressed.connect(_on_research_pressed)
	vb.add_child(_action_btn)


# ─────────────────────────────────────────────────────────────────────
# Tooltip text builder (moved here from research_node_widget.gd v110)
# ─────────────────────────────────────────────────────────────────────
func _build_tooltip_text(d: Dictionary) -> String:
	var has_structured := d.has("effects") or d.has("unlocks") or d.has("flavor")
	if not has_structured:
		return str(d.get("description", ""))

	var sections: Array = []

	# EFFECTS
	var fx: Array = d.get("effects", [])
	if not fx.is_empty():
		var lines: Array = ["[color=%s]%s[/color]" % [HDR_COL, tr("EFFECTS")]]
		for e in fx:
			lines.append("• " + _format_effect(e))
		sections.append("\n".join(lines))

	# UNLOCKS
	var unl: Array = d.get("unlocks", [])
	if not unl.is_empty():
		var lines2: Array = ["[color=%s]%s[/color]" % [HDR_COL, tr("UNLOCKS")]]
		for u in unl:
			lines2.append("• " + tr(str(u)))
		sections.append("\n".join(lines2))

	# REQUIRES — derived from parent + req_tech
	var req_lines: Array = []
	var parent_id: String = str(d.get("parent", ""))
	if parent_id != "" and _manager and _manager.tech_tree.has(parent_id):
		req_lines.append("• " + tr(str(_manager.tech_tree[parent_id].get("name", parent_id))))
	var rt_id: String = str(d.get("req_tech", ""))
	if rt_id != "" and _manager and _manager.tech_tree.has(rt_id):
		req_lines.append("• " + tr(str(_manager.tech_tree[rt_id].get("name", rt_id)))
			+ "  [color=%s]%s[/color]" % [HINT_COL, tr("(cross-branch)")])
	if not req_lines.is_empty():
		sections.append("[color=%s]%s[/color]\n" % [HDR_COL, tr("REQUIRES")] + "\n".join(req_lines))

	# FLAVOR
	var flav: String = str(d.get("flavor", ""))
	if flav != "":
		sections.append("[color=%s][i]%s[/i][/color]" % [HINT_COL, tr(flav)])

	return "\n\n".join(sections)


func _format_effect(e: Dictionary) -> String:
	var t: String = str(e.get("type", ""))
	match t:
		"action_speed":
			var pct: int = int(round(float(e.get("bonus", 0.0)) * 100.0))
			var name: String = _resolve_action_name(str(e.get("id", "")))
			var chain: Array = e.get("stack_chain", [])
			var stack_str: String = ""
			if not chain.is_empty():
				stack_str = tr("  [color=%s](stacks with %s)[/color]") % [HINT_COL, ", ".join(chain)]
			elif bool(e.get("stacks", false)):
				stack_str = tr("  [color=%s](stacks)[/color]") % HINT_COL
			return tr("+%d%% %s speed%s") % [pct, name, stack_str]
		"chance_drop":
			var item: String = str(e.get("id", ""))
			var ctx: String = str(e.get("context", ""))
			var item_name: String = ElementDB.get_display_name(item) if item != "" else item
			return tr("Chance: %s from %s") % [item_name, tr(ctx)]
		"bonus_yield":
			var pct: int = int(round(float(e.get("bonus", 0.0)) * 100.0))
			var what: String = str(e.get("what", "yield"))
			return "+%d%% %s" % [pct, tr(what)]
		"yield_multiplier":
			var factor: float = float(e.get("factor", 1.0))
			var what: String = str(e.get("what", "Output"))
			var factor_str: String = str(int(factor)) if factor == floor(factor) else str(factor)
			return "×%s %s" % [factor_str, tr(what)]
		"flat_bonus":
			var amt: float = float(e.get("amount", 0.0))
			var what: String = str(e.get("what", ""))
			var sign: String = "+" if amt >= 0 else ""
			var amt_str: String = str(int(amt)) if amt == floor(amt) else str(amt)
			return "%s%s %s" % [sign, amt_str, tr(what)]
		"threshold":
			var pct: int = int(round(float(e.get("at_pct", 0.0)) * 100.0))
			var what: String = str(e.get("what", ""))
			return tr("Triggers at ≤%d%% %s") % [pct, what]
		_:
			return str(e)


func _resolve_action_name(action_id: String) -> String:
	if GameState.gathering_manager and GameState.gathering_manager.actions.has(action_id):
		return str(GameState.gathering_manager.actions[action_id].get("name", action_id))
	if GameState.processing_manager and GameState.processing_manager.recipes.has(action_id):
		return str(GameState.processing_manager.recipes[action_id].get("name", action_id))
	return action_id


# ─────────────────────────────────────────────────────────────────────
# Cost panel — colour-coded affordability per resource
# ─────────────────────────────────────────────────────────────────────
func _build_cost_text() -> String:
	if _is_repeatable:
		return _build_repeatable_cost_text()

	var raw_credits: float = float(_data.get("cost", 0))
	var credits: int = int(raw_credits * float(_manager.COST_MULTIPLIER))
	var lines: Array = ["[color=%s]%s[/color]" % [HDR_COL, tr("COST")]]

	if credits > 0:
		var have_c: int = int(GameState.resources.get_currency("credits"))
		var col: String = "#7fff7f" if have_c >= credits else "#ff8080"
		lines.append("[color=%s]%s %s[/color]  [color=%s](%s)[/color]" % [
			col,
			FormatUtils.format_number(credits),
			UITheme.LIRA_ICON_BB,
			HINT_COL,
			FormatUtils.format_number(have_c)
		])

	var items: Dictionary = _data.get("cost_items", {})
	for item in items:
		var raw_qty: float = float(items[item])
		var req_qty: int = int(raw_qty * float(_manager.MATERIAL_MULTIPLIER))
		var have_q: int = int(GameState.resources.get_element_amount(item))
		var col2: String = "#7fff7f" if have_q >= req_qty else "#ff8080"
		var display: String = ElementDB.get_display_name(item)
		lines.append("[color=%s]%s %s[/color]  [color=%s](%s)[/color]" % [
			col2,
			FormatUtils.format_number(req_qty),
			display,
			HINT_COL,
			FormatUtils.format_number(have_q)
		])

	return "\n".join(lines)


func _build_repeatable_cost_text() -> String:
	var costs: Dictionary = _manager.get_repeatable_cost(_nid)
	var lines: Array = ["[color=%s]%s[/color]" % [HDR_COL, tr("NEXT LEVEL COST")]]
	for res in costs:
		var req_qty: float = float(costs[res])
		var have_q: float
		var display: String
		if res == "credits":
			have_q = float(GameState.resources.get_currency("credits"))
			display = UITheme.LIRA_ICON_BB
		else:
			have_q = float(GameState.resources.get_element_amount(res))
			display = ElementDB.get_display_name(res)
		var col: String = "#7fff7f" if have_q >= req_qty else "#ff8080"
		lines.append("[color=%s]%s %s[/color]  [color=%s](%s)[/color]" % [
			col,
			FormatUtils.format_number(req_qty),
			display,
			HINT_COL,
			FormatUtils.format_number(have_q)
		])
	return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────
# Action button state
# ─────────────────────────────────────────────────────────────────────
func _refresh_state() -> void:
	if _is_repeatable:
		var lvl: int = _manager.get_repeatable_level(_nid)
		var can_r: bool = _manager.can_unlock_repeatable(_nid)
		_action_btn.text = tr("RESEARCH  ·  Lvl %d → %d") % [lvl, lvl + 1]
		_action_btn.disabled = not can_r
		_apply_btn_style(can_r)
		return

	var is_unlocked: bool = _manager.is_tech_unlocked(_nid)
	if is_unlocked:
		_action_btn.text = tr("RESEARCHED")
		_action_btn.disabled = true
		_apply_btn_style(false, true)
		return

	var can_u: bool = _manager.can_unlock(_nid)
	if can_u:
		_action_btn.text = tr("RESEARCH")
		_action_btn.disabled = false
		_apply_btn_style(true)
	else:
		# Distinguish warp-gate / missing-prereq / insufficient-resources.
		var parent_id: String = str(_data.get("parent", ""))
		var rt_id: String = str(_data.get("req_tech", ""))
		var locked_by_parent: bool = parent_id != "" and not _manager.is_tech_unlocked(parent_id)
		var locked_by_rt: bool = rt_id != "" and not _manager.is_tech_unlocked(rt_id)
		# v111: warp-gated techs read as a prestige reward, not a resource wall.
		var locked_by_warp: bool = _data.get("requires_warp", false) and not GameState.game_settings.get("cryo_unlocked", false)
		if locked_by_warp:
			_action_btn.text = tr("REQUIRES WARP CORE ACTIVATION")
		elif locked_by_parent or locked_by_rt:
			_action_btn.text = tr("LOCKED  ·  unlock prerequisites first")
		else:
			_action_btn.text = tr("INSUFFICIENT RESOURCES")
		_action_btn.disabled = true
		_apply_btn_style(false)

	# Also re-render the cost text so colour-coded affordability stays fresh
	# if state has shifted (e.g., after a repeatable purchase).
	if _cost_rt:
		_cost_rt.text = _build_cost_text()


func _apply_btn_style(active: bool, success: bool = false) -> void:
	# Light/quick visual differentiation. Falls back to default Button look
	# if UITheme can't reach in — we just tint modulate.
	if success:
		_action_btn.modulate = Color(0.55, 1.0, 0.65)
	elif active:
		_action_btn.modulate = Color(1.0, 0.95, 0.55)
	else:
		_action_btn.modulate = Color(0.65, 0.65, 0.70)


# ─────────────────────────────────────────────────────────────────────
# Actions
# ─────────────────────────────────────────────────────────────────────
func _on_research_pressed() -> void:
	if _is_repeatable:
		if _manager.unlock_repeatable_tech(_nid):
			if _parent_page and _parent_page.has_method("refresh_all"):
				_parent_page.refresh_all()
			UITheme.trigger_circuit_surge(self, Color.LIME)
			# Repeatables stay open — player can grind multiple levels in a row.
			_refresh_state()
	else:
		if _manager.unlock_tech(_nid):
			if _parent_page and _parent_page.has_method("refresh_all"):
				_parent_page.refresh_all()
			_close()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	if _active_info_card and is_instance_valid(_active_info_card):
		_active_info_card.queue_free()
	closed.emit()
	queue_free()


# ─────────────────────────────────────────────────────────────────────
# Smart-link handling — keep clickable item / hull / module popups inside
# the modal's body, identical to the old research-node-widget behaviour.
# ─────────────────────────────────────────────────────────────────────
func _apply_smart_linking(text: String) -> String:
	if text.contains("[url"): return text

	var terms: Array = []
	for symbol in ElementDB.ELEMENT_NAMES:
		terms.append({"name": ElementDB.ELEMENT_NAMES[symbol], "id": symbol, "type": "item"})
	if GameState.shipyard_manager:
		for hid in GameState.shipyard_manager.hulls:
			terms.append({"name": GameState.shipyard_manager.hulls[hid]["name"], "id": hid, "type": "ship"})
		for mid in GameState.shipyard_manager.modules:
			terms.append({"name": GameState.shipyard_manager.modules[mid]["name"], "id": mid, "type": "module"})
	if GameState.infrastructure_manager:
		for bid in GameState.infrastructure_manager.building_db:
			terms.append({"name": GameState.infrastructure_manager.building_db[bid]["name"], "id": bid, "type": "building"})

	terms.sort_custom(func(a, b): return a["name"].length() > b["name"].length())

	var processed: String = text
	var replacements: Dictionary = {}
	var token_id: int = 0
	for t in terms:
		if not (t["name"] in processed):
			continue
		if "[url" in processed and t["name"] + "[/url]" in processed:
			continue
		var token: String = "{{LINK_%d}}" % token_id
		var meta: String = JSON.stringify({"id": t["id"], "type": t["type"]})
		var link_bbcode: String = "[url=%s][color=#44aaff]%s[/color][/url]" % [meta, t["name"]]
		processed = processed.replace(t["name"], token)
		replacements[token] = link_bbcode
		token_id += 1
	for tok in replacements:
		processed = processed.replace(tok, replacements[tok])
	return processed


func _on_meta_hover(meta) -> void:
	if _active_info_card and is_instance_valid(_active_info_card):
		_active_info_card.queue_free()
	var d = JSON.parse_string(str(meta))
	if not d: return
	var card: Control = _info_card_scene.instantiate()
	add_child(card)
	card.setup(d["id"], d["type"])
	_active_info_card = card
	var mpos: Vector2 = get_global_mouse_position()
	card.global_position = mpos + Vector2(20, 20)
	# Keep on screen
	var vp: Vector2 = get_viewport_rect().size
	var cs: Vector2 = card.size if card.size.x > 0 else Vector2(220, 100)
	if card.global_position.x + cs.x > vp.x:
		card.global_position.x = mpos.x - cs.x - 20
	if card.global_position.y + cs.y > vp.y:
		card.global_position.y = mpos.y - cs.y - 20


func _on_meta_exit(_meta) -> void:
	if _active_info_card and is_instance_valid(_active_info_card):
		_active_info_card.queue_free()
		_active_info_card = null
