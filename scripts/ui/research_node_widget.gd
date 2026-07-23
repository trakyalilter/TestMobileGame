extends PanelContainer

# v111: Display-only research node.
#
# Previous behaviour was hover-tooltip (show structured info) + click-to-unlock.
# That mixed an "informational" gesture with a "commit-resources" gesture on
# the same control, which led to accidental unlocks.
#
# New behaviour:
#   click  →  open research_detail_modal.gd (full-screen dim + centered card
#             with EFFECTS / UNLOCKS / REQUIRES / FLAVOR + RESEARCH button)
#   player explicitly commits by pressing RESEARCH in the modal.
#
# All tooltip rendering, smart-linking, and effect formatting now live in
# research_detail_modal.gd. This widget is just a clickable card face that
# shows name + cost and a state-tinted background.

var nid: String
var data: Dictionary
var manager: RefCounted
var parent_graph: Node

@onready var name_lbl = $MarginContainer/VBoxContainer/NameLabel
@onready var cost_lbl = $MarginContainer/VBoxContainer/CostLabel
@onready var desc_tip = $TooltipPanel              # kept for scene compat, hidden in setup
@onready var desc_lbl = $TooltipPanel/MarginContainer/Label

# Colors
const COL_LOCKED = Color(0.12, 0.12, 0.12)
const COL_AVAILABLE = Color(0.18, 0.18, 0.22)
const COL_UNLOCKED = Color(0.1, 0.25, 0.15)
const BORDER_LOCKED = Color(0.3, 0.3, 0.3)
const BORDER_AVAILABLE = Color(1.0, 0.8, 0.2)
const BORDER_UNLOCKED = Color(0.2, 1.0, 0.5)

const _MODAL_SCRIPT := preload("res://scripts/ui/research_detail_modal.gd")

var _header_panel: PanelContainer
var _pulse_tween: Tween


func setup(p_nid: String, p_data: Dictionary, p_manager, p_parent):
	nid = p_nid
	data = p_data
	manager = p_manager
	parent_graph = p_parent

	name_lbl.text = data["name"]
	cost_lbl.text = tr("%d %s") % [data.get("cost", 0), UITheme.LIRA_ICON_BB]

	# v111: hover-tooltip retired. Hide the legacy TooltipPanel so the scene
	# graph stays untouched but the player never sees it.
	if desc_tip:
		desc_tip.visible = false
		desc_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# v111.3: child Labels / RichTextLabels default to MOUSE_FILTER_STOP and
	# were swallowing clicks before they reached the PanelContainer's
	# gui_input — the player could only click the diegetic header (whose
	# children DON'T absorb input). Switch every child to PASS so the whole
	# card face is a hit target, then let gui_input fire on the root panel.
	name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	cost_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	var mc := get_node_or_null("MarginContainer")
	if mc:
		mc.mouse_filter = Control.MOUSE_FILTER_PASS
		var vb := mc.get_node_or_null("VBoxContainer")
		if vb:
			vb.mouse_filter = Control.MOUSE_FILTER_PASS

	scale = Vector2(1, 1)
	update_state()


func _ready():
	_ensure_header()


func _ensure_header():
	if _header_panel: return
	_header_panel = UITheme.inject_diegetic_header(self, "research")

	# Hide original spacing Control if it exists
	var vbox = get_node("MarginContainer/VBoxContainer")
	var spacer = vbox.get_node_or_null("Control")
	if spacer: spacer.hide()


func _cleanup_pulse():
	if _pulse_tween:
		_pulse_tween.kill()
		_pulse_tween = null
	# Reset border to standard
	var style = get_theme_stylebox("panel").duplicate()
	style.shadow_size = 0
	add_theme_stylebox_override("panel", style)


func update_state():
	var is_repeatable = manager.repeatable_tech_db.has(nid)
	var is_unlocked = manager.is_tech_unlocked(nid) if not is_repeatable else false
	var can_unlock = manager.can_unlock(nid) if not is_repeatable else manager.can_unlock_repeatable(nid)

	if is_repeatable:
		var lvl = manager.get_repeatable_level(nid)
		name_lbl.text = manager.repeatable_tech_db[nid]["name"] + " (Lvl %d)" % lvl
		var costs = manager.get_repeatable_cost(nid)
		var cost_parts = []
		for res in costs:
			var req_qty = costs[res]
			var inv_qty = GameState.resources.get_currency("credits") if res == "credits" else GameState.resources.get_element_amount(res)
			var color = "lime" if inv_qty >= req_qty else "gray"
			var display_name = UITheme.LIRA_ICON_BB if res == "credits" else ElementDB.get_display_name(res)
			cost_parts.append("[color=%s]%s %s[/color]" % [color, FormatUtils.format_number(req_qty), display_name])
		cost_lbl.text = "[center]" + "\n".join(cost_parts) + "[/center]"

	name_lbl.add_theme_color_override("font_color", Color.WHITE) # Header handled color
	var style = UITheme.apply_card_style(self, "research")
	_ensure_header()
	_cleanup_pulse()

	if is_unlocked:
		style.bg_color = COL_UNLOCKED
		style.border_color = BORDER_UNLOCKED
		style.shadow_color = Color(BORDER_UNLOCKED, 0.4)
		style.shadow_size = 8
		cost_lbl.text = tr("[center][b][color=SPRING_GREEN]RESEARCHED[/color][/b][/center]")
	else:
		# Build cost string with met/unmet color coding
		var cost_parts = []
		var total_credits = GameState.resources.get_currency("credits")
		var raw_credit_cost = data.get("cost", 0)
		var credit_cost = int(raw_credit_cost * manager.COST_MULTIPLIER)

		# Credits check
		if credit_cost > 0:
			var color = "#00ff00" if total_credits >= credit_cost else "#888888"
			cost_parts.append("[color=%s]%s %s[/color]" % [color, FormatUtils.format_number(credit_cost), UITheme.LIRA_ICON_BB])

		# Items check
		if "cost_items" in data:
			for item in data["cost_items"]:
				var raw_qty = data["cost_items"][item]
				# v141: manager owns this formula — boss cores are exempt from
				# MATERIAL_MULTIPLIER, so multiplying here showed 2x the real cost.
				var req_qty = int(manager._effective_item_requirement(String(item), int(raw_qty)))
				var inv_qty = GameState.resources.get_element_amount(item)
				var color = "#00ff00" if inv_qty >= req_qty else "#888888"
				var display_name = ElementDB.get_display_name(item)
				cost_parts.append("[color=%s]%s %s[/color]" % [color, FormatUtils.format_number(req_qty), display_name])

		cost_lbl.text = "[center]" + "\n".join(cost_parts) + "[/center]"

		if can_unlock:
			style.bg_color = COL_AVAILABLE
			style.border_color = BORDER_AVAILABLE
			# Pulse cue: "this one is researchable right now"
			_start_pulse(style)
		else:
			style.bg_color = COL_LOCKED
			style.border_color = BORDER_LOCKED

	add_theme_stylebox_override("panel", style)


func _start_pulse(style: StyleBoxFlat):
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(style, "border_color", Color(1.0, 1.0, 0.5), 0.8).set_trans(Tween.TRANS_SINE)
	_pulse_tween.parallel().tween_property(style, "shadow_size", 8, 0.8).set_trans(Tween.TRANS_SINE)
	_pulse_tween.parallel().tween_property(style, "shadow_color", Color(1.0, 0.8, 0.0, 0.5), 0.8)

	_pulse_tween.tween_property(style, "border_color", BORDER_AVAILABLE, 0.8).set_trans(Tween.TRANS_SINE)
	_pulse_tween.parallel().tween_property(style, "shadow_size", 2, 0.8).set_trans(Tween.TRANS_SINE)
	_pulse_tween.parallel().tween_property(style, "shadow_color", Color(1.0, 0.8, 0.0, 0.1), 0.8)


# ─────────────────────────────────────────────────────────────────────
# Click handling — drag-vs-click discrimination so panning the tree
# doesn't accidentally open a modal on release.
# ─────────────────────────────────────────────────────────────────────
var _pressed_pos: Vector2 = Vector2.ZERO
var _is_pressed: bool = false
const DRAG_THRESHOLD = 5.0


func _on_gui_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_pressed = true
			_pressed_pos = event.global_position
			# v111.1: tactile press cue — squeeze the node a touch the moment
			# the mouse goes down, so the player knows the click landed even
			# before the modal fades in (~120ms later).
			_play_press_feedback()
		else:
			if _is_pressed:
				var dist = event.global_position.distance_to(_pressed_pos)
				_is_pressed = false
				if dist < DRAG_THRESHOLD:
					_open_detail_modal()


# v111.1: A small scale + tint pulse triggered on mouse-down, decoupled from
# the modal opening so the user sees something happen instantly even if the
# modal takes a frame or two to construct.
func _play_press_feedback() -> void:
	pivot_offset = size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.94, 0.94), 0.06).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "modulate", Color(1.25, 1.20, 0.90), 0.06).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_property(self, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(self, "modulate", Color(1, 1, 1), 0.12)


# v111: click no longer unlocks directly. Opens a modal where the player
# reviews the structured info + cost, then commits via a RESEARCH button.
func _open_detail_modal() -> void:
	# If a modal is already open in the ModalLayer for ANY node, free it
	# first so we don't stack overlapping cards.
	var modal_layer: Node = get_tree().current_scene.get_node_or_null("ModalLayer") \
		if get_tree().current_scene else null
	if modal_layer:
		var existing := modal_layer.get_node_or_null("_ResearchDetailModal")
		if existing:
			existing.queue_free()

	var modal: Control = _MODAL_SCRIPT.new()
	modal.name = "_ResearchDetailModal"
	var parent_node: Node = modal_layer if modal_layer else get_tree().current_scene
	parent_node.add_child(modal)
	modal.start(nid, data, manager, parent_graph)
