extends PanelContainer

var parent_ui: Node
var manager: RefCounted
var slot_idx: int = -1

@onready var type_lbl = $MarginContainer/VBoxContainer/TypeLabel
@onready var name_lbl = $MarginContainer/VBoxContainer/NameLabel
@onready var status_lbl = $MarginContainer/VBoxContainer/StatusLabel

func setup(p_slot_idx, p_ui, p_manager):
	slot_idx = p_slot_idx
	parent_ui = p_ui
	manager = p_manager

	if is_node_ready():
		refresh_state()

func _ready():
	_apply_base_style()
	refresh_state()

func _apply_base_style():
	var frame = StyleBoxFlat.new()
	frame.bg_color = Color(0.11, 0.09, 0.08, 0.96)
	frame.set_corner_radius_all(3)
	frame.set_border_width_all(2)
	frame.border_width_top = 5
	frame.border_color = Color(0.35, 0.35, 0.35, 0.5)
	frame.content_margin_left = 6
	frame.content_margin_top = 5
	frame.content_margin_right = 6
	frame.content_margin_bottom = 5
	add_theme_stylebox_override("panel", frame)

# v137: the ammo card had no icon. Lazily add a TextureRect at the top (matching the
# equipped-module / consumable slots) and fill it with the ammo's own material icon.
func _ensure_icon() -> TextureRect:
	var v = $MarginContainer/VBoxContainer
	var ic = v.get_node_or_null("AmmoIcon")
	if not ic:
		ic = TextureRect.new()
		ic.name = "AmmoIcon"
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(0, 46)   # v139c: icon-forward — bigger icon, no text stack
		ic.size_flags_horizontal = Control.SIZE_FILL
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(ic)
		v.move_child(ic, 0)
	return ic

func refresh_state():
	if not is_node_ready():
		return
	if not manager:
		manager = GameState.shipyard_manager
	if not manager:
		return

	var active_ammo = manager.ammo_loadout.get(slot_idx, "")
	# v139c: ICON-FORWARD (owner: "i only wanted icons"). The slot number + ammo
	# NAME are redundant with the icon (and both live in the hover tooltip) — hide
	# them and lead with the icon; keep only the terse count, the one functional
	# number. Empty slots still read as EMPTY.
	type_lbl.visible = false

	var ic = _ensure_icon()
	if active_ammo != "":
		var qty = GameState.resources.get_element_amount(active_ammo)
		name_lbl.visible = false
		status_lbl.text = "×%d" % qty
		status_lbl.add_theme_color_override("font_color", Color(0.373, 0.878, 0.784) if qty > 0 else Color(0.8, 0.3, 0.3))
		status_lbl.visible = true
		var atex = ElementDB.get_material_icon(active_ammo)
		if atex:
			ic.texture = atex
			ic.modulate = ElementDB.get_material_tint(active_ammo)
			ic.visible = true
		else:
			ic.visible = false
	else:
		name_lbl.visible = true
		name_lbl.text = tr("EMPTY")
		name_lbl.add_theme_color_override("font_color", Color(0.33, 0.33, 0.33))
		status_lbl.visible = false
		ic.visible = false


func _get_drag_data(_at_position: Vector2) -> Variant:
	var active_ammo = manager.ammo_loadout.get(slot_idx, "")
	if active_ammo == "":
		return null

	var drag_data = {
		"type": "unequip_ammo",
		"slot_idx": slot_idx,
		"ammo_id": active_ammo
	}

	var preview = load("res://scenes/ui/designer_ammo_slot_widget.tscn").instantiate()
	preview.setup(slot_idx, parent_ui, manager)
	preview.modulate = Color(1, 0.5, 0.5, 0.8)
	preview.custom_minimum_size = Vector2(124, 124)  # v131b: square, matches equipment slots
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var queue = [preview]
	while queue.size() > 0:
		var n = queue.pop_front()
		if n is Control:
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue.append_array(n.get_children())

	set_drag_preview(preview)
	return drag_data

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or data.get("type") != "ammo":
		return false
	
	var ammo_id = data.get("ammo_id")
	var mid = manager.loadout.get(slot_idx)
	if mid and mid in manager.modules:
		var m_stats = manager.modules[mid].get("stats", {})
		var w_type = "kinetic"
		if m_stats.get("atk_energy", 0) > 0: w_type = "energy"
		elif m_stats.get("atk_explosive", 0) > 0: w_type = "explosive"
		
		return manager.is_ammo_compatible(w_type, ammo_id)
	return false

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var ammo_id = data.get("ammo_id")
	manager.set_slot_ammo(slot_idx, ammo_id)
	parent_ui.trigger_refresh()

func _gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			manager.set_slot_ammo(slot_idx, "")
			parent_ui.trigger_refresh()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if parent_ui and parent_ui.has_method("_on_filter_changed"):
				parent_ui._on_filter_changed("ordnance")

func _make_custom_tooltip(_for_text: String) -> Control:
	var active_ammo = manager.ammo_loadout.get(slot_idx, "")
	if active_ammo == "":
		return null

	# v111.15 FRAME-IN-FRAME FIX: return a frameless RichTextLabel so the theme's
	# `TooltipPanel` wrapper is the single frame (returning our own bordered
	# PanelContainer nested two frames).
	var rtl = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.custom_minimum_size = Vector2(320, 0)
	rtl.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))

	var ammo_name = ElementDB.get_display_name(active_ammo).to_upper()
	var tt = "[center][b][font_size=16][color=#aaaaaa]%s[/color][/font_size][/b]\n" % ammo_name
	tt += "[i][font_size=10][color=#7FA39C]" + tr("Common Ammo") + "[/color][/font_size][/i][/center]\n"
	# v139c: count now lives here (the tile is icon-only) so hover still shows stock.
	tt += "[center][font_size=11][color=#5FE0C8]" + (tr("Stock: %d") % int(GameState.resources.get_element_amount(active_ammo))) + "[/color][/font_size][/center]\n"
	tt += "[color=#1E3B38]──────────────────────────────[/color]\n"

	# v144: percentage ladder, shared with combat (ElementDB.AMMO_TIER_MULT).
	var channel := ElementDB.get_ammo_channel(String(active_ammo))
	var type_label = "Damage"
	var color_label = "white"

	match channel:
		"kinetic":
			type_label = tr("Kinetic Damage")
			color_label = "red"
		"energy":
			type_label = tr("Energy Damage")
			color_label = "cyan"
		"explosive":
			type_label = tr("Explosive Damage")
			color_label = "orange"

	# v143: suppress at 0 — T1 is the x1.00 baseline (see info_card note).
	if channel != "" and ElementDB.get_ammo_damage_pct(String(active_ammo)) > 0:
		# v137: was a broken concat — `%` binds tighter than `+`, so the args formatted the
		# trailing fragment (no specifiers) and left "+%.1f" literal. Build the label, format once.
		var bonus_label: String = tr("%s Bonus") % type_label
		var pct: int = ElementDB.get_ammo_damage_pct(String(active_ammo))
		tt += "[center][font_size=20][b][color=%s]+%d%%[/color][/b][/font_size] [font_size=10][color=#7FA39C]%s[/color][/font_size][/center]\n" % [color_label, pct, bonus_label]
		tt += "[color=#1E3B38]──────────────────────────────[/color]\n"

	tt += "[center][font_size=10][color=#7FA39C][Right-click to unequip][/color][/font_size][/center]"

	rtl.text = tt
	return rtl
