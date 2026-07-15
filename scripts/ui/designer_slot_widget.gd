extends PanelContainer

var slot_idx: int
var slot_type: String
var parent_ui: Node
var manager: RefCounted
var is_occupied: bool = false
var pulse_tween: Tween

var _active_gem_card = null
var _info_card_scene = preload("res://scenes/ui/info_card.tscn")
const MatrixCoreIcon = preload("res://scripts/ui/matrix_core_icon.gd")
const ModuleCard = preload("res://scripts/ui/module_card.gd")   # v136: shared compare-pin state + bbcode factory
var _is_focused: bool = false
var _card_target: bool = false   # v127: a Hack Card is in hand and this slot is a valid target
var _card_socket_overlay: Control = null   # v127.1: top-most insert-socket overlay child
var _card_socket_tween: Tween = null

@onready var type_lbl = $MarginContainer/VBoxContainer/TypeLabel
@onready var rarity_badge = $MarginContainer/VBoxContainer/RarityBadge
@onready var name_lbl = $MarginContainer/VBoxContainer/NameLabel
@onready var stats_lbl = $MarginContainer/VBoxContainer/StatsLabel
@onready var socket_anchor = $MarginContainer/VBoxContainer/SocketAnchor
@onready var option_btn = $MarginContainer/VBoxContainer/OptionButton

func setup(idx: int, s_type: String, p_ui, p_manager):
	slot_idx = idx
	slot_type = s_type
	parent_ui = p_ui
	manager = p_manager
	
	if is_node_ready():
		refresh_state()

func _ready():
	_apply_base_style()
	# Uniform fixed slot size: the square module layout overflows the scene's 124²
	# base by a content-dependent amount (the icon + 24px socket band + unequip),
	# so every filled slot grew a little differently. Pin a fixed size and let the
	# icon's EXPAND_FILL absorb the slack — empty and filled slots are now identical.
	# v131b: SQUARE 124x124 so every equipment slot is a uniform square matching
	# the armory tiles (card language: icon=type, border=rarity, emblem=tier). The
	# scene's SHRINK_CENTER flag holds this exact size, so slots don't stretch to
	# fill the blade — they form a clean square grid like the armory.
	custom_minimum_size = Vector2(124, 124)
	option_btn.visible = false
	# v111.20: slot-level hover → rarity-framed module tooltip (manual popup),
	# replacing the generic cyan _make_custom_tooltip.
	if not mouse_entered.is_connected(_on_slot_hover):
		mouse_entered.connect(_on_slot_hover)
		mouse_exited.connect(_on_slot_unhover)
		tree_exiting.connect(_on_slot_unhover)
	# Only refresh if setup() already ran; otherwise the empty slot_type falls
	# through to the module-render path and bleeds set labels into consumable slots.
	if slot_type != "":
		refresh_state()

func _apply_base_style():
	var frame = StyleBoxFlat.new()
	frame.bg_color = Color(0.08, 0.08, 0.1, 0.9)
	frame.set_corner_radius_all(2)
	frame.set_border_width_all(1)
	frame.border_color = Color(0.2, 0.2, 0.25, 1.0)
	
	# Top accent bar instead of just border
	frame.border_width_top = 4
	frame.border_color = Color(0.3, 0.3, 0.4, 0.8)
	
	frame.content_margin_left = 8
	frame.content_margin_top = 6
	frame.content_margin_right = 8
	frame.content_margin_bottom = 6
	
	# Inner shadow for depth
	frame.shadow_color = Color(0, 0, 0, 0.5)
	frame.shadow_size = 4

	if _is_focused:
		frame.border_width_top = 5
		frame.border_color = Color(0.4, 0.82, 1.0, 0.9)
		frame.shadow_color = Color(0.4, 0.82, 1.0, 0.35)
		frame.shadow_size = 10

	add_theme_stylebox_override("panel", frame)
	if _card_target:
		_apply_card_socket_frame()

func _get_type_number() -> int:
	if not parent_ui or not "all_slot_widgets" in parent_ui: return slot_idx + 1
	var n = 1
	for w in parent_ui.all_slot_widgets:
		if w == self: break
		if is_instance_valid(w) and w.slot_type == slot_type: n += 1
	return n

func _ensure_footer_spacer() -> void:
	# Expanding gap so the Unequip/Repair/Change footer sinks to the bottom;
	# with the fixed slot height this aligns headers (top) and footers
	# (bottom) across side-by-side slots regardless of content length.
	var v = $MarginContainer/VBoxContainer
	var sp = v.get_node_or_null("FooterSpacer")
	if not sp:
		sp = Control.new()
		sp.name = "FooterSpacer"
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sp.custom_minimum_size = Vector2(0, 2)
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(sp)
	v.move_child(sp, option_btn.get_index())

func _ensure_type_icon() -> TextureRect:
	var v = $MarginContainer/VBoxContainer
	var ic = v.get_node_or_null("TypeIcon")
	if not ic:
		ic = TextureRect.new()
		ic.name = "TypeIcon"
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(0, 30)
		ic.size_flags_horizontal = Control.SIZE_FILL
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(ic)
		v.move_child(ic, 0)
	return ic

# Draws the sector emblem BIG in the top-right corner — clear of the centred icon
# and the lower matrix-core sockets — on a faint plate so it reads on any rarity bg.
class _ZoneBadge extends Control:
	var tex: Texture2D = null
	var tint: Color = Color(1, 1, 1, 1)
	func _draw() -> void:
		if tex == null:
			return
		var s := 30.0
		var pad := 4.0
		var r := Rect2(Vector2(size.x - s - pad, pad), Vector2(s, s))
		draw_texture_rect(tex, r, false, tint)

# Corner zone-provenance badge node (created once, kept on top so it reads as a
# stamp). The emblem itself is drawn by the _ZoneBadge inner class above.
func _ensure_zone_badge() -> _ZoneBadge:
	var b = get_node_or_null("ZoneBadge")
	if not b:
		b = _ZoneBadge.new()
		b.name = "ZoneBadge"
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(b)
	move_child(b, get_child_count() - 1)
	return b

# Square equipped-module layout: Name (top) → Icon (centre) → Matrix-Core
# Sockets (lower) → Unequip (bottom). Only sizes + positions change — the
# rarity frame, name tint, type icon and socket visuals are the existing
# design, just rearranged. Rarity reads from the frame, so the type label,
# rarity-badge text and the stats/durability line come off the face.
func _arrange_module_square() -> void:
	var v = $MarginContainer/VBoxContainer
	# No name on the face — it's in the hover info card. Everything except
	# Icon → Sockets → Unequip comes off, so the square holds fixed content.
	type_lbl.visible = false
	rarity_badge.visible = false
	stats_lbl.visible = false
	name_lbl.visible = false
	option_btn.visible = false
	for n in ["SetLabel", "FooterSpacer", "QuickRepairBtn"]:
		var node = v.get_node_or_null(n)
		if node: node.visible = false

	# Top balancer (≈ the bottom socket+unequip band) so the EXPAND icon's
	# region is symmetric and the icon sits in the card CENTRE, not the top.
	var topbal = v.get_node_or_null("TopBalance")
	if not topbal:
		topbal = Control.new()
		topbal.name = "TopBalance"
		topbal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(topbal)
	topbal.visible = true
	topbal.custom_minimum_size = Vector2(0, 32)

	var ic = v.get_node_or_null("TypeIcon")
	if ic:
		ic.visible = true
		# Small min so the fixed 140px slot height always binds (occupied content min
		# stays UNDER it instead of overflowing); EXPAND_FILL then grows the icon back
		# to fill the centre. This is what locks every equipped slot to one size.
		ic.custom_minimum_size = Vector2(0, 16)
		ic.size_flags_vertical = Control.SIZE_EXPAND_FILL  # fills/centres the middle
	# Reserve the socket band so the centred icon is the SAME size whether the
	# module has 0, 1 or 3 sockets.
	socket_anchor.custom_minimum_size = Vector2(0, 22)

	# Order: TopBalance → Icon (centre) → Sockets (arc) → Unequip (bottom).
	var uneq = v.get_node_or_null("QuickUnequipBtn")
	var order := [topbal, ic, socket_anchor, uneq]
	var i := 0
	for n in order:
		if is_instance_valid(n):
			v.move_child(n, i)
			i += 1

func set_focus_highlight(on: bool):
	_is_focused = on
	if is_occupied and not slot_type.begins_with("consumable_") and manager:
		var equipped_id = manager.loadout.get(slot_idx, "")
		if equipped_id != "" and equipped_id in manager.modules:
			var rarity = manager.get_module_rarity(equipped_id)
			var rarity_color = manager.RARITY_COLORS.get(rarity, Color(0.7, 0.7, 0.7))
			_apply_card_style(rarity, rarity_color)
			return
	_apply_base_style()

# v127: mark this equipped slot as a valid Hack Card target while a card is in hand.
# Sets a flag and re-runs the slot's OWN styler, which stamps a blue socket frame on
# top when the flag is set — so a rarity restyle / legendary pulse can't wipe it.
func set_card_socket(active: bool) -> void:
	if manager == null:
		manager = GameState.shipyard_manager
	# Check the loadout directly (is_occupied can be stale when this fires on arm).
	var eqv = null if manager == null else manager.loadout.get(slot_idx, "")
	var eq: String = "" if eqv == null else str(eqv)
	var new_target: bool = active and eq != "" and not slot_type.begins_with("consumable_")
	if new_target == _card_target:
		return
	_card_target = new_target
	# Redraw the frame via the slot's normal stylers (they honour _card_target now).
	if new_target and manager and str(eq) in manager.modules:
		var rarity: int = manager.get_module_rarity(eq)
		var rc: Color = manager.RARITY_COLORS.get(rarity, Color(0.7, 0.7, 0.7))
		_apply_card_style(rarity, rc)
	else:
		_apply_base_style()
	# v127.1: the root-panel frame above is occluded on an OCCUPIED slot (it draws
	# BEHIND the module content + the full-rect RarityFX child, and clip_contents
	# eats its outward glow) — so the socket was invisible on equipped modules. Add
	# a dedicated TOP-MOST overlay child (same visual as the armory tile) so it
	# actually shows.
	_apply_card_socket_overlay(new_target)

# v127.1: insert-socket overlay as a top-most child (mirrors the armory tile in
# module_card.gd). Painted ABOVE the module content + RarityFX, unlike the root
# panel stylebox. Idempotent: tears down any prior overlay first.
func _apply_card_socket_overlay(active: bool) -> void:
	if _card_socket_tween and is_instance_valid(_card_socket_tween):
		_card_socket_tween.kill()
	_card_socket_tween = null
	if is_instance_valid(_card_socket_overlay):
		_card_socket_overlay.queue_free()
	_card_socket_overlay = null
	if not active:
		return
	var acc := Color(0.40, 0.60, 1.0)
	var insert_frame := Panel.new()
	insert_frame.name = "CardSocketOverlay"
	insert_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	insert_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(acc.r, acc.g, acc.b, 0.08)
	fsb.set_corner_radius_all(4)
	fsb.set_border_width_all(2)
	fsb.border_color = Color(acc.r, acc.g, acc.b, 0.85)
	insert_frame.add_theme_stylebox_override("panel", fsb)
	# Centred card bay (blue mount + near-black slot the card seats into).
	var housing := Panel.new()
	housing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	housing.anchor_left = 0.5
	housing.anchor_top = 0.5
	housing.anchor_right = 0.5
	housing.anchor_bottom = 0.5
	housing.offset_left = -12
	housing.offset_right = 12
	housing.offset_top = -32
	housing.offset_bottom = 32
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(acc.r, acc.g, acc.b, 0.95)
	hsb.set_corner_radius_all(3)
	housing.add_theme_stylebox_override("panel", hsb)
	insert_frame.add_child(housing)
	var bay := Panel.new()
	bay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bay.offset_left = 3
	bay.offset_top = 4
	bay.offset_right = -3
	bay.offset_bottom = -4
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.02, 0.03, 0.05, 1.0)
	bsb.set_corner_radius_all(2)
	bay.add_theme_stylebox_override("panel", bsb)
	housing.add_child(bay)
	add_child(insert_frame)
	move_child(insert_frame, get_child_count() - 1)   # guarantee above RarityFX
	_card_socket_overlay = insert_frame
	if is_inside_tree():
		_card_socket_tween = create_tween().set_loops()
		_card_socket_tween.tween_property(insert_frame, "modulate:a", 0.45, 0.55).set_trans(Tween.TRANS_SINE)
		_card_socket_tween.tween_property(insert_frame, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE)

# v127: blue "insert socket" frame stamped over the slot's normal frame while a Hack
# Card is in hand (called from _apply_base_style / _apply_card_style).
func _apply_card_socket_frame() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.11, 0.20, 0.96)
	sb.set_corner_radius_all(2)
	sb.set_border_width_all(2)
	sb.border_width_top = 5
	sb.border_color = Color(0.45, 0.70, 1.0, 1.0)
	sb.shadow_color = Color(0.45, 0.70, 1.0, 0.6)
	sb.shadow_size = 12
	sb.content_margin_left = 8
	sb.content_margin_top = 6
	sb.content_margin_right = 8
	sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)

func refresh_state():
	if not is_node_ready(): return
	if not manager: manager = GameState.shipyard_manager
	if not manager: return
	
	# Clear old sockets
	for child in socket_anchor.get_children():
		child.queue_free()

	var old_uneq = $MarginContainer/VBoxContainer.get_node_or_null("QuickUnequipBtn")
	if is_instance_valid(old_uneq): old_uneq.free()

	var old_repair = $MarginContainer/VBoxContainer.get_node_or_null("QuickRepairBtn")
	if is_instance_valid(old_repair): old_repair.free()

	_stop_pulse()
	_ensure_footer_spacer()

	# Reset the face each refresh (visibility + default order) so a slot that
	# was equipped doesn't bleed its square-layout overrides into the empty or
	# consumable state. The equipped path re-applies its overrides via _arrange.
	type_lbl.visible = true
	stats_lbl.visible = true
	rarity_badge.visible = true
	name_lbl.visible = true
	var _vb = $MarginContainer/VBoxContainer
	_vb.move_child(type_lbl, 0)
	_vb.move_child(name_lbl, 1)
	_vb.move_child(rarity_badge, 2)
	_vb.move_child(stats_lbl, 3)
	_vb.move_child(socket_anchor, 4)
	# The square-layout top balancer + reserved socket band are equipped-only;
	# strip them so empty/consumable slots don't show a phantom gap. _arrange
	# re-creates/re-shows them for the equipped state.
	var _tb = _vb.get_node_or_null("TopBalance")
	if _tb: _tb.visible = false
	socket_anchor.custom_minimum_size = Vector2(0, 0)

	# CONSUMABLE LOGIC
	if slot_type.begins_with("consumable_"):
		_refresh_consumable_state()
		return

	# v135a: the CMB_3 aux slot is a singleton that accepts any type — label it as
	# such rather than "AUX 1", so its any-type nature reads at a glance.
	if slot_type == "aux":
		type_lbl.text = "AUX · ANY"
	else:
		type_lbl.text = "%s %d" % [slot_type.to_upper(), _get_type_number()]
	type_lbl.add_theme_color_override("font_color", _get_slot_color(slot_type))
	
	option_btn.clear()
	option_btn.add_item("EQUIP ▼", 0)
	option_btn.set_item_metadata(0, null)

	var equipped_id = manager.loadout.get(slot_idx)
	is_occupied = equipped_id != null
	
	if equipped_id:
		var m_data = manager.modules.get(equipped_id)
		if not m_data:
			name_lbl.text = "INVALID ID"
			stats_lbl.text = "?"
			rarity_badge.visible = false
			tooltip_text = "Module data not found for ID: %s" % equipped_id
			option_btn.add_item("Unequip (Invalid)", 1)
			option_btn.set_item_metadata(1, "unequip")
			return

		var clean_name = _get_clean_name(m_data.get("name", "Unknown"))
		# Cap the on-face name to ~2 lines so a long affixed name can't grow the
		# square; the full name stays in the hover tooltip.
		if clean_name.length() > 34:
			clean_name = clean_name.substr(0, 33).strip_edges() + "…"
		name_lbl.text = clean_name.to_upper()
		
		# v83.9: Set Name Display for equipped slots
		var sid = m_data.get("set_id", "")
		if sid == "" and m_data.get("is_custom") and m_data.has("base_module"):
			var base_id = m_data["base_module"]
			sid = manager.modules.get(base_id, {}).get("set_id", "")
		
		var v_box = $MarginContainer/VBoxContainer
		var set_lbl = v_box.get_node_or_null("SetLabel")
		if not set_lbl:
			set_lbl = Label.new()
			set_lbl.name = "SetLabel"
			set_lbl.add_theme_font_size_override("font_size", 8)
			set_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			set_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v_box.add_child(set_lbl)
			v_box.move_child(set_lbl, name_lbl.get_index() + 1)
		
		if sid != "" and GameState.combat_manager and "TRINITY_SET_BONUSES" in GameState.combat_manager:
			var s_db = GameState.combat_manager.TRINITY_SET_BONUSES
			if s_db.has(sid):
				var set_name = s_db[sid]["name"]
				set_lbl.text = "[ %s ]" % set_name.to_upper()
				set_lbl.add_theme_color_override("font_color", Color(0.0, 0.8, 0.8)) # Cyan
				set_lbl.visible = true
			else: set_lbl.visible = false
		else: set_lbl.visible = false
		
		var rarity = manager.get_module_rarity(equipped_id)
		var rarity_color = manager.RARITY_COLORS.get(rarity, Color(0.7, 0.7, 0.7))
		
		name_lbl.add_theme_color_override("font_color", rarity_color.lerp(Color.WHITE, 0.18))
		
		var r_label = manager.RARITY_LABELS.get(rarity, "")
		rarity_badge.visible = r_label != ""
		rarity_badge.text = "[ %s ]" % r_label.to_upper()
		rarity_badge.add_theme_color_override("font_color", rarity_color)

		# Cohesion with the armory tiles: type icon + damage-family accent.
		var stats = m_data.get("stats", {})
		var accent = UITheme.weapon_family_color(stats) if slot_type == "weapon" else _get_slot_color(slot_type)
		type_lbl.add_theme_color_override("font_color", accent)
		var ic = _ensure_type_icon()
		ic.texture = UITheme.module_type_icon(slot_type, stats)
		ic.modulate = accent.lerp(Color.WHITE, 0.85)
		ic.visible = true

		# Source-sector badge: the zone emblem drawn BIG in the top-right corner —
		# clear of the centred icon and the lower matrix-core sockets — so the drop's
		# sector reads at a glance. The tooltip carries the sector NAME.
		var zb := _ensure_zone_badge()
		var zz := int(m_data.get("zone", m_data.get("zone_difficulty", 0)))
		var zbtex: Texture2D = ElementDB.get_material_icon("Z%d_Core" % clampi(zz, 1, 10)) if zz >= 1 else null
		if zbtex:
			zb.tex = zbtex
			zb.tint = ElementDB.get_material_tint("Z%d_Core" % clampi(zz, 1, 10))
			zb.visible = true
			zb.queue_redraw()
		else:
			zb.visible = false

		stats_lbl.text = _build_card_stats(stats, equipped_id)
		if slot_type == "weapon":
			stats_lbl.text = "%s · %s" % [UITheme.weapon_family_tag(stats), stats_lbl.text]

		var durability = int(m_data.get("durability", 100))
		stats_lbl.text += "\nDUR %d%%" % durability

		var uneq_btn = Button.new()
		uneq_btn.name = "QuickUnequipBtn"
		uneq_btn.text = "× Unequip"
		uneq_btn.flat = true
		uneq_btn.add_theme_font_size_override("font_size", 9)
		uneq_btn.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
		uneq_btn.pressed.connect(func():
			manager.unequip_slot(slot_idx)
			if parent_ui: parent_ui.trigger_refresh()
		)
		$MarginContainer/VBoxContainer.add_child(uneq_btn)
		$MarginContainer/VBoxContainer.move_child(uneq_btn, option_btn.get_index())

		# Per-module repair affordance (replaces global repair-mode discovery problem).
		# Shown when the equipped module is a custom drop and below full durability.
		if equipped_id.begins_with("custom_") and durability < 100:
			var repair_btn = Button.new()
			repair_btn.name = "QuickRepairBtn"
			repair_btn.text = "🔧 Repair  %d%%" % durability
			repair_btn.flat = true
			repair_btn.add_theme_font_size_override("font_size", 9)
			var dur_col := Color(0.95, 0.85, 0.30)
			if durability <= 25: dur_col = Color(0.95, 0.40, 0.30)
			elif durability <= 50: dur_col = Color(0.95, 0.65, 0.25)
			repair_btn.add_theme_color_override("font_color", dur_col)
			repair_btn.tooltip_text = "Repair this module without entering global Repair Mode."
			repair_btn.pressed.connect(_try_repair)
			$MarginContainer/VBoxContainer.add_child(repair_btn)
			$MarginContainer/VBoxContainer.move_child(repair_btn, uneq_btn.get_index() + 1)

		_apply_card_style(rarity, rarity_color)
		_apply_pulse(rarity)
		# v111.19: rare+ equipped modules shimmer like the armory tiles.
		UITheme.attach_rarity_fx(self, rarity, rarity_color)
		# v111.20: tooltip is now a rarity-framed manual popup (see _on_slot_hover).

		# Make physical sockets in the SocketAnchor
		if m_data.has("sockets"):
			option_btn.add_separator("--- Matrix Cores ---")
			# v112: lay the sockets on a parabolic arc (centre highest, nearest
			# the icon; outer sockets splay down) instead of a flat row, so a
			# 3-socket module reads as a curved cradle under the icon. h_box is a
			# plain Control now (manual positioning), not an HBoxContainer.
			var n_sock: int = m_data["sockets"].size()
			var sd := 16.0
			var sgap := 12.0
			var arc_depth := 8.0
			var h_box = Control.new()
			h_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h_box.custom_minimum_size = Vector2(
				float(n_sock) * sd + float(maxi(0, n_sock - 1)) * sgap, sd + arc_depth)

			for i in range(m_data["sockets"].size()):
				var gem = m_data["sockets"][i]
				var item_idx = option_btn.item_count
				# v111.16: faceted crystal core visual (was a flat rotated square).
				# The option_btn entries below still drive the right-click remove
				# menu and must be kept exactly as-is.
				var core := MatrixCoreIcon.new()
				core.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				core.mouse_filter = Control.MOUSE_FILTER_IGNORE

				if gem:
					var gem_name = ElementDB.get_display_name(gem)
					option_btn.add_item("Socket: Remove " + gem_name, item_idx)
					option_btn.set_item_metadata(item_idx, {"action": "remove_gem", "socket_idx": i})
					core.set_core(_get_gem_color(gem_name), false, MatrixCoreIcon.tier_from_name(gem))
				else:
					option_btn.add_item("Socket: [Empty]", item_idx)
					option_btn.set_item_disabled(item_idx, true)
					core.set_core(Color(0.42, 0.47, 0.58), true)  # hollow empty socket

				var sock_wrap = Control.new()
				sock_wrap.custom_minimum_size = Vector2(sd, sd)
				sock_wrap.size = Vector2(sd, sd)
				sock_wrap.add_child(core)
				# Arc placement: x sequential, y a parabola. Bowl ∪ (classic
				# y=x²): outer sockets ride high near the icon, centre dips —
				# so 3 sockets cradle under the icon. A lone socket sits flat
				# at mid-band (a single point can't show a curve).
				# Explicit float types — this codebase chokes on `:=` inference
				# through ternaries (see CLAUDE.md gotchas).
				var _ci: float = float(n_sock - 1) / 2.0
				var _t: float = 0.0 if n_sock <= 1 else (float(i) - _ci) / maxf(1.0, _ci)
				var _y: float = (arc_depth * 0.5) if n_sock <= 1 else (arc_depth * (1.0 - _t * _t))
				sock_wrap.position = Vector2(float(i) * (sd + sgap), _y)

				# v111.16: sockets are click-driven now (drag retired).
				#   filled socket → click (or right-click) removes the core
				#   empty socket  → click sockets the Matrix Core armed in the armory
				sock_wrap.mouse_filter = Control.MOUSE_FILTER_STOP
				var sock_i := i
				if gem:
					var _facet_txt: String = manager.get_gem_facet_text(gem, slot_type)
					sock_wrap.tooltip_text = "Matrix Core: %s\n%s  (active in this %s slot)\n[Click to remove]" % [ElementDB.get_display_name(gem), _facet_txt, slot_type.capitalize()]
					var captured_gem = gem
					sock_wrap.mouse_entered.connect(func():
						# v111.13 CRASH FIX: a queued mouse_entered can fire after
						# this slot has been detached (drop completes → slot
						# rebuild frees us). get_global_mouse_position() /
						# get_viewport() on a node with a null viewport hard-
						# crashes the engine. Bail if we're no longer in the tree.
						if not is_inside_tree(): return
						if _active_gem_card: _active_gem_card.queue_free()
						var card = _info_card_scene.instantiate()
						var main = get_tree().current_scene
						var modal = main.get_node_or_null("ModalLayer")
						if modal: modal.add_child(card)
						else: main.add_child(card)
						card.setup(captured_gem, "gem", slot_type)
						var mpos = get_global_mouse_position()
						var vp = get_viewport().get_visible_rect().size
						card.global_position = mpos + Vector2(20, -20)
						await get_tree().process_frame
						if is_instance_valid(card):
							if card.global_position.x + card.size.x > vp.x:
								card.global_position.x = mpos.x - card.size.x - 20
							if card.global_position.y + card.size.y > vp.y:
								card.global_position.y = mpos.y - card.size.y - 20
						_active_gem_card = card
					)
					sock_wrap.mouse_exited.connect(func():
						if _active_gem_card:
							_active_gem_card.queue_free()
							_active_gem_card = null
					)
					sock_wrap.gui_input.connect(func(event):
						if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
							if _active_gem_card:
								_active_gem_card.queue_free()
								_active_gem_card = null
							if manager.remove_gem(equipped_id, sock_i):
								UITheme.trigger_circuit_surge(self)
								parent_ui.trigger_refresh()
					)
				else:
					sock_wrap.tooltip_text = "Empty Matrix Socket — a core here gives its %s-slot bonus\n[Click a Matrix Core, then click here to socket it]" % slot_type.capitalize()
					sock_wrap.gui_input.connect(func(event):
						if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
							_socket_armed_core(equipped_id, sock_i)
					)

				h_box.add_child(sock_wrap)
				
			socket_anchor.add_child(h_box)
			option_btn.add_separator("---------------------")
		
		option_btn.add_item("Unequip", option_btn.item_count)
		option_btn.set_item_metadata(option_btn.item_count - 1, "unequip")

		# Square face: Name → Icon → Sockets → Unequip (size + position only).
		_arrange_module_square()
	else:
		name_lbl.text = ""
		name_lbl.visible = false   # empty slot leads with the type label
		stats_lbl.text = "--"
		rarity_badge.visible = false
		_ensure_type_icon().visible = false
		var ezb = get_node_or_null("ZoneBadge")
		if ezb: ezb.visible = false
		_apply_base_style()
		UITheme.attach_rarity_fx(self, 0, Color.WHITE)   # clear any prior shimmer
		tooltip_text = "Empty %s Slot\nDrag a matching module here (or click a module, then click here)" % slot_type.capitalize()

	# Populate Inventory Options
	var inv = manager.module_inventory
	var idx_counter = option_btn.item_count
	for mid in inv:
		var count = inv[mid]
		if count > 0 and mid in manager.modules:
			var m_data = manager.modules[mid]
			# v135a: the aux slot lists every standard module type (not gems/consumables).
			if m_data["slot_type"] == slot_type or (slot_type == "aux" and not m_data["slot_type"] in ["gem", "consumable"]):
				var item_idx = option_btn.item_count
				var m_rarity = manager.get_module_rarity(mid)
				var r_label = manager.RARITY_LABELS.get(m_rarity, "COMMON").to_upper()
				
				var status = manager.can_equip_module(mid)
				var lock_icon = "[LOCK] " if not status["can_equip"] else ""
				
				var display_name = "%s[%s] %s (x%d)" % [lock_icon, r_label, m_data["name"], count]
				if m_rarity == manager.Rarity.COMMON:
					display_name = "%s%s (x%d)" % [lock_icon, m_data["name"], count]
					
				option_btn.add_item(display_name, idx_counter)
				option_btn.set_item_metadata(item_idx, mid)
				idx_counter += 1

func _refresh_consumable_state():
	_apply_base_style()
	var c_type = "hull" if slot_type == "consumable_hull" else "shield"

	type_lbl.text = "HULL REPAIR" if c_type == "hull" else "SHIELD REPAIR"
	type_lbl.add_theme_color_override("font_color", Color(0.74, 0.74, 0.86))
	rarity_badge.visible = false
	_ensure_type_icon().visible = false

	# Belt-and-suspenders: hide any SetLabel that an early refresh may have left here.
	# Consumables are not part of Trinity sets, so this label should never appear.
	var stale_set_lbl = $MarginContainer/VBoxContainer.get_node_or_null("SetLabel")
	if stale_set_lbl: stale_set_lbl.visible = false
	
	option_btn.clear()
	option_btn.add_item("EQUIP ▼", 0)

	var equipped_id = manager.get_consumable(c_type)
	if equipped_id != "":
		var data = ElementDB.get_consumable_data(equipped_id)
		var dname = data.get("name", equipped_id)
		var qty = GameState.resources.get_element_amount(equipped_id)
		var heal_pct = int(round(data.get("heal_pct", data.get("stats", {}).get("heal_pct", 0.0)) * 100.0))
		
		name_lbl.text = "%s (x%d)" % [dname, qty]
		name_lbl.add_theme_color_override("font_color", Color(0.74, 0.74, 0.86))
		
		stats_lbl.text = "Restores %d%% %s" % [heal_pct, c_type.capitalize()]
		
		tooltip_text = "%s\nRestores %d%% %s" % [dname, heal_pct, c_type.capitalize()]
		
		option_btn.add_item("Unequip", 1)
		option_btn.set_item_metadata(1, "unequip")
	else:
		name_lbl.text = ""
		stats_lbl.text = "--"
		tooltip_text = "Drag a consumable here (or click one, then click here)"

	var items = ElementDB.get_elements_in_category("consumables")
	var idx = 2
	for id in items:
		var data = ElementDB.get_consumable_data(id)
		if data.get("type") == c_type:
			var qty = GameState.resources.get_element_amount(id)
			if qty > 0:
				option_btn.add_item("%s (x%d)" % [data.get("name", id), qty], idx)
				option_btn.set_item_metadata(option_btn.get_item_count() - 1, id)
				idx += 1

func _get_clean_name(raw_name: String) -> String:
	var title = raw_name
	for suffix in [" (Common)", " (Uncommon)", " (Rare)", " (Legendary)", " (Unique)"]:
		title = title.replace(suffix, "")
	return title

func _get_slot_color(s_type: String) -> Color:
	match s_type:
		"weapon": return Color(0.92, 0.48, 0.32)
		"shield": return Color(0.50, 0.72, 0.95)
		"armor": return Color(0.78, 0.73, 0.66)
		"engine", "reactor", "battery": return Color(0.84, 0.79, 0.43)
		"ammo": return Color(0.88, 0.60, 0.34)
		"consumable": return Color(0.74, 0.74, 0.86)
		"aux": return Color(0.78, 0.55, 1.0)  # v135a: warp-purple — CMB_3 any-type slot
		_: return Color(0.65, 0.58, 0.47)

func _get_gem_color(gem_name: String) -> Color:
	if "Crimson" in gem_name: return Color("#ff4444")
	if "Cobalt" in gem_name: return Color("#44ccff")
	if "Topaz" in gem_name: return Color("#FFC24D")
	if "Amethyst" in gem_name: return Color("#aa44ff")
	return Color("#b548b5") # Default purple

func _get_rarity_background(rarity: int) -> Color:
	if rarity == manager.Rarity.UNCOMMON: return Color(0.08, 0.11, 0.08, 0.96)
	if rarity == manager.Rarity.RARE: return Color(0.07, 0.10, 0.14, 0.96)
	if rarity == manager.Rarity.LEGENDARY: return Color(0.15, 0.10, 0.06, 0.98)
	if rarity == manager.Rarity.UNIQUE: return Color(0.16, 0.08, 0.14, 0.98)
	return Color(0.11, 0.09, 0.08, 0.96)

func _apply_card_style(rarity: int, rarity_color: Color):
	var frame = StyleBoxFlat.new()
	frame.bg_color = _get_rarity_background(rarity)
	frame.set_corner_radius_all(2)
	frame.set_border_width_all(1)
	frame.border_color = rarity_color.lerp(Color.WHITE, 0.3)
	frame.border_color.a = 0.5
	
	# Top accent bar
	frame.border_width_top = 5
	frame.border_color = rarity_color
	
	frame.content_margin_left = 8
	frame.content_margin_top = 6
	frame.content_margin_right = 8
	frame.content_margin_bottom = 6
	
	# Premium outer glow for rarity
	frame.shadow_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.3)
	frame.shadow_size = 10
	
	if rarity >= manager.Rarity.RARE:
		frame.shadow_size = 15
		frame.set_border_width_all(2)
		
	if rarity >= manager.Rarity.LEGENDARY:
		frame.border_color.a = 0.9
		frame.shadow_size = 20
		frame.shadow_color.a = 0.5

	if _is_focused:
		frame.border_color = Color(0.4, 0.82, 1.0)
		frame.border_width_top = 6
		frame.shadow_color = Color(0.4, 0.82, 1.0, 0.5)
		frame.shadow_size = 16

	add_theme_stylebox_override("panel", frame)
	if _card_target:
		_apply_card_socket_frame()

func _apply_pulse(rarity: int):
	_stop_pulse()
	if rarity == manager.Rarity.LEGENDARY:
		pulse_tween = create_tween().set_loops()
		pulse_tween.tween_property(self, "modulate", Color(1.08, 1.03, 0.94), 0.9).set_trans(Tween.TRANS_SINE)
		pulse_tween.tween_property(self, "modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
	elif rarity == manager.Rarity.UNIQUE:
		pulse_tween = create_tween().set_loops()
		pulse_tween.tween_property(self, "modulate", Color(1.10, 0.97, 1.08), 0.9).set_trans(Tween.TRANS_SINE)
		pulse_tween.tween_property(self, "modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)

func _stop_pulse():
	if pulse_tween and is_instance_valid(pulse_tween):
		pulse_tween.kill()
	pulse_tween = null
	modulate = Color.WHITE

func _build_card_stats(stats: Dictionary, mid: String = "") -> String:
	var lines: Array[String] = []

	if slot_type == "weapon":
		var dmg = stats.get("atk_kinetic", 0) + stats.get("atk_energy", 0) + stats.get("atk_explosive", 0) + stats.get("atk_cryo", 0)
		var interval = max(0.01, float(stats.get("atk_interval", 2.5)))
		lines.append("DPS %.1f" % (float(dmg) / interval))

	# v110: derived power (tier-based), replacing the stale energy_load stat.
	if mid != "" and manager:
		if slot_type in ["weapon", "shield", "armor", "engine", "sensor"]:
			var draw = manager.get_module_energy_load(mid)
			if draw > 0: lines.append("POWER DRAW %d" % draw)
		elif slot_type == "battery":
			var supply = manager.get_module_energy_capacity(mid)
			if supply > 0: lines.append("POWER +%d" % supply)

	var keys = stats.keys()
	keys.sort()
	for key in keys:
		if key == "atk_interval": continue
		var val = stats[key]
		if key == "energy_load" or key == "energy_capacity": continue
		if slot_type == "weapon" and key in ["atk_kinetic", "atk_energy", "atk_explosive", "atk_cryo"]: continue

		var label = FormatUtils.format_stat_label(key)
		lines.append("%s %s" % [label, FormatUtils.format_stat_value(key, val)])
		if lines.size() >= 2: break

	if lines.is_empty():
		return "No combat modifiers"
	return "\n".join(lines)


@warning_ignore("unreachable_code")
func _get_drag_data(at_position: Vector2) -> Variant:
	# v111.14: drag-to-unequip retired alongside drag-to-equip — the drag
	# machinery (preview node + detached-node mouse calls) was the crash
	# source. Right-click on a slot already unequips, so the gesture is
	# covered. Returning null disables all slot dragging. (Body kept below
	# for reference but is intentionally unreachable.)
	return null
	if slot_type.begins_with("consumable_"):
		var c_type = "hull" if slot_type == "consumable_hull" else "shield"
		var equipped_id = manager.get_consumable(c_type)
		if equipped_id == "": return null
		
		return {
			"type": "unequip_consumable",
			"slot_type": c_type,
			"id": equipped_id
		}
	
	var equipped_id = manager.loadout.get(slot_idx)
	if not equipped_id: return null
	
	var drag_data = {
		"type": "unequip_module",
		"slot_idx": slot_idx,
		"mid": equipped_id,
		"slot_type": slot_type
	}
	
	var preview = load("res://scenes/ui/designer_slot_widget.tscn").instantiate()
	preview.setup(slot_idx, slot_type, parent_ui, manager)
	
	var preview_container = Control.new()
	preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_container.add_child(preview)
	
	preview.scale = Vector2(1.05, 1.05)
	preview.modulate = Color(1.0, 0.7, 0.7, 0.95)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shadow = Panel.new()
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.45)
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 12)
	shadow.add_theme_stylebox_override("panel", style)
	shadow.custom_minimum_size = Vector2(144, 224)
	
	preview_container.add_child(shadow)
	preview_container.move_child(shadow, 0)
	
	preview.position = Vector2(-70, -110)
	shadow.position = Vector2(-70, -110)
	
	var queue = [preview_container]
	while queue.size() > 0:
		var n = queue.pop_front()
		if n is Control:
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue.append_array(n.get_children())

	set_drag_preview(preview_container)
	return drag_data

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY: return false
	
	if slot_type.begins_with("consumable_"):
		var c_type = "hull" if slot_type == "consumable_hull" else "shield"
		if data.get("type") == "consumable":
			return data.get("consumable_type") == c_type
		return false
		
	if data.get("type") == "module":
		if data.get("slot_type") == "gem":
			var equipped_id = manager.loadout.get(slot_idx)
			if equipped_id:
				var m_data = manager.modules.get(equipped_id)
				if m_data and m_data.has("sockets"):
					# Only accept (and highlight) when there is a free socket.
					for g in m_data["sockets"]:
						if g == null:
							return true
			return false
		# v135a: the CMB_3 aux slot accepts any dragged module except socket gems /
		# consumables (gems are routed to sockets by the branch above).
		if slot_type == "aux":
			return not data.get("slot_type") in ["gem", "consumable"]
		return data.get("slot_type") == slot_type
	return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	# Legacy drag path — now just routes through the shared equip logic.
	_equip_payload(data)

# v111.14: shared equip routing used by BOTH the legacy drag _drop_data and
# the new click-to-equip path (try_equip_armed). Returns true on success.
func _equip_payload(data: Variant) -> bool:
	if slot_type.begins_with("consumable_"):
		var c_type = "hull" if slot_type == "consumable_hull" else "shield"
		var item_id = data.get("mid", "")
		if data.get("type") == "consumable":
			manager.equip_consumable(c_type, item_id)
			UITheme.trigger_circuit_surge(self)
			parent_ui.trigger_refresh()
			return true
		return false

	var mid = data.get("mid")

	if data.get("type") == "module" and data.get("slot_type") == "gem":
		var equipped_id = manager.loadout.get(slot_idx)
		if equipped_id:
			var m_data = manager.modules.get(equipped_id)
			if m_data and m_data.has("sockets"):
				var socket_idx = -1
				for i in range(m_data["sockets"].size()):
					if m_data["sockets"][i] == null:
						socket_idx = i
						break

				if socket_idx >= 0:
					if manager.insert_gem(equipped_id, socket_idx, mid):
						UITheme.trigger_circuit_surge(self)
						parent_ui.trigger_refresh()
						return true
					else:
						UITheme.show_notification("Failed to insert core.", Color.RED)
				else:
					UITheme.show_notification("No empty sockets available.", Color.RED)
		return false

	if manager.equip_module(slot_idx, mid):
		UITheme.trigger_circuit_surge(self)
		parent_ui.trigger_refresh()
		return true
	return false

# v111.14: build a drop-style payload from a module/consumable id.
func _payload_for(mid: String) -> Dictionary:
	if mid == "": return {}
	var m_data = manager.modules.get(mid, {})
	if not m_data.is_empty():
		return {"type": "module", "mid": mid, "slot_type": m_data.get("slot_type", "")}
	# v111.16: Matrix Cores are inventory ELEMENTS, not modules. Present one as a
	# gem payload so the shared equip routing sockets it into this slot's module
	# (enables click-core → click-module, mirroring the module equip flow).
	if _is_matrix_core(mid):
		return {"type": "module", "mid": mid, "slot_type": "gem"}
	var c_data = ElementDB.get_consumable_data(mid)
	if not c_data.is_empty():
		return {"type": "consumable", "mid": mid, "consumable_type": c_data.get("type", "hull")}
	return {}

func _is_matrix_core(mid: String) -> bool:
	return mid != "" and ElementDB.get_elements_in_category("matrix_cores").has(mid)

# Socket the armory's currently-armed Matrix Core into a SPECIFIC socket of the
# module in this slot. Used by the per-socket pip click (precise targeting).
func _socket_armed_core(module_id: String, socket_idx: int) -> void:
	if not parent_ui or not parent_ui.has_method("get_armed_mid"):
		return
	var core_id: String = parent_ui.get_armed_mid()
	if not _is_matrix_core(core_id):
		UITheme.show_notification("Click a Matrix Core first, then a socket.", Color(1, 0.82, 0.4))
		return
	if manager.insert_gem(module_id, socket_idx, core_id):
		UITheme.trigger_circuit_surge(self)
		if parent_ui.has_method("notify_equipped"):
			parent_ui.notify_equipped()       # clears the armed core + armory
		# Rebuild the equipped slots LAST so the seated core shows (this frees &
		# recreates this widget; queue_free defers, so the call is safe).
		parent_ui.trigger_refresh()
	else:
		UITheme.show_notification("Couldn't socket that core.", Color(1, 0.5, 0.4))

# True if this slot would accept the given module/consumable id (click-equip).
func can_accept_module(mid: String) -> bool:
	var data := _payload_for(mid)
	if data.is_empty(): return false
	return _can_drop_data(Vector2.ZERO, data)

# Equip a specific module/consumable id into this slot. Returns success.
# Used by both the armed-module path (module-first) and the focused-slot
# path (slot-first: armory click equips into the focused slot).
func equip_id(mid: String) -> bool:
	var data := _payload_for(mid)
	if data.is_empty() or not _can_drop_data(Vector2.ZERO, data):
		return false
	return _equip_payload(data)

# Equip the parent UI's currently-armed module into this slot. Returns success.
func try_equip_armed() -> bool:
	if not parent_ui or not parent_ui.has_method("get_armed_mid"):
		return false
	return equip_id(parent_ui.get_armed_mid())

# Glow this slot while a compatible module is armed for equipping.
func set_equip_highlight(on: bool) -> void:
	modulate = Color(1.3, 1.3, 1.05) if on else Color(1, 1, 1)

func _on_option_button_item_selected(index):
	var data = option_btn.get_item_metadata(index)
	
	if slot_type.begins_with("consumable_"):
		var c_type = "hull" if slot_type == "consumable_hull" else "shield"
		if data == "unequip":
			manager.unequip_consumable(c_type)
		elif data:
			manager.equip_consumable(c_type, data)
		parent_ui.trigger_refresh()
		option_btn.select(0)
		return

	if data == "unequip":
		manager.unequip_slot(slot_idx)
		parent_ui.trigger_refresh()
	elif typeof(data) == TYPE_DICTIONARY and data.get("action") == "remove_gem":
		if manager.remove_gem(manager.loadout.get(slot_idx), data["socket_idx"]):
			UITheme.trigger_circuit_surge(self)
			parent_ui.trigger_refresh()
	elif typeof(data) == TYPE_STRING:
		if manager.equip_module(slot_idx, data):
			UITheme.trigger_circuit_surge(self)
			parent_ui.trigger_refresh()
	
	option_btn.select(0)

func _gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		if parent_ui and "is_repair_mode" in parent_ui and parent_ui.is_repair_mode:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if is_occupied and not slot_type.begins_with("consumable_"):
					_try_repair()
				return
				
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if slot_type.begins_with("consumable_"):
				var c_type = "hull" if slot_type == "consumable_hull" else "shield"
				manager.unequip_consumable(c_type)
			else:
				manager.unequip_slot(slot_idx)
			parent_ui.trigger_refresh()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			# v136: Shift-click an equipped module to pin it as the compare baseline (same
			# gesture as the Armory). Handled before equip/hack routing so it never fires an equip.
			if event.shift_pressed and is_occupied and not slot_type.begins_with("consumable_"):
				var pin_mid = manager.loadout.get(slot_idx, "")
				if pin_mid != null and str(pin_mid) != "" and parent_ui and parent_ui.has_method("_on_module_pin_toggled"):
					parent_ui._on_module_pin_toggled(str(pin_mid))
				return
			# v127: a Hack Card in hand applies to THIS equipped module.
			if is_occupied and not slot_type.begins_with("consumable_") and parent_ui and parent_ui.has_method("try_apply_armed_card"):
				var eq_mid = manager.loadout.get(slot_idx, "")
				if eq_mid == null: eq_mid = ""
				if str(eq_mid) != "" and parent_ui.try_apply_armed_card(str(eq_mid), self):
					return
			# v111.14: armed-module equip takes priority. If the player has
			# clicked a module in the armory (armed it), a left-click here
			# equips it into this slot via the shared equip routing.
			if parent_ui and parent_ui.has_method("is_module_armed") and parent_ui.is_module_armed():
				if try_equip_armed():
					UITheme.trigger_ui_thud(self, 1.0)
					parent_ui.notify_equipped()
				else:
					UITheme.show_notification("Can't equip there.", Color(1, 0.5, 0.4))
				return
			if slot_type.begins_with("consumable_"):
				# v111.15: no auto-filter on slot click (disorienting). Equip a
				# consumable by clicking the consumable card to arm it, then
				# clicking this slot (handled by the armed-check above).
				UITheme.trigger_ui_thud(self, 1.0)
			elif parent_ui and parent_ui.has_method("set_focused_slot"):
				# Dict.get() returns the default ONLY when the key is missing; a stored
				# null value comes through as null. Coerce to "" so the typed param holds.
				var equipped_mid = manager.loadout.get(slot_idx, "")
				if equipped_mid == null: equipped_mid = ""
				parent_ui.set_focused_slot(slot_idx, slot_type, equipped_mid)
				UITheme.trigger_ui_thud(self, 1.0)

func _try_repair():
	var equipped_id = manager.loadout.get(slot_idx)
	if not equipped_id or not equipped_id.begins_with("custom_"):
		UITheme.show_notification("Cannot repair this module", Color.RED)
		return
		
	var m_data = manager.modules.get(equipped_id)
	var cur_dur = m_data.get("durability", 100)
	if cur_dur >= 100:
		UITheme.show_notification("Module is at maximum durability", Color.GREEN)
		return
		
	var missing = 100 - cur_dur
	var chunks = ceili(missing / 10.0)
	var rarity = manager.get_module_rarity(equipped_id)
	
	# v125: cost is Spare Parts only (no Liras).
	var parts_cost = manager.RARITY_SPARE_PARTS.get(rarity, 1) * chunks

	_spawn_custom_repair_modal(m_data, cur_dur, parts_cost)

func _spawn_custom_repair_modal(m_data: Dictionary, cur_dur: int, parts_cost: int):
	# v124: rebuilt on the shared themed modal (UITheme.show_confirm) instead of a
	# hand-built primitive Window — chrome-framed panel, bbcode body, on-brand
	# confirm/cancel, backdrop-cancel + Enter-confirms. Confirm is locked (not just
	# greyed text) when the player can't afford the Spare Parts.
	var have: int = int(GameState.resources.get_element_amount("SparePart"))
	var affordable: bool = have >= parts_cost
	var nm: String = str(m_data.get("name", "Module")).to_upper()
	var warn_hex: String = UITheme.COLORS["warning"].to_html(false)
	var pos_hex: String = UITheme.COLORS["positive"].to_html(false)
	var dim_hex: String = UITheme.COLORS["text_dim"].to_html(false)
	var neg_hex: String = UITheme.COLORS["negative"].to_html(false)
	var have_hex: String = pos_hex if affordable else neg_hex

	var body := "[center]Restore  [b]%s[/b]\n" % nm
	body += "from [color=#%s]%d%%[/color]   →   [color=#%s]100%%[/color] durability.\n\n" % [warn_hex, cur_dur, pos_hex]
	body += "[color=#%s]COST[/color]     [b][color=#%s]%d[/color][/b]  Spare Parts\n" % [dim_hex, warn_hex, parts_cost]
	body += "[color=#%s]IN STOCK[/color]     [b][color=#%s]%d[/color][/b]" % [dim_hex, have_hex, have]
	if not affordable:
		body += "\n\n[color=#%s][b]NOT ENOUGH SPARE PARTS[/b][/color]" % neg_hex
	body += "[/center]"

	# Capture into locals — the slot widget may be rebuilt by trigger_refresh.
	var mgr = manager
	var s_idx := slot_idx
	var p_cost := parts_cost
	var pui = parent_ui
	var on_ok := func():
		if mgr.repair_module(s_idx, p_cost):
			UITheme.show_notification("Module repaired", UITheme.COLORS["positive"])
			if is_instance_valid(pui) and pui.has_method("trigger_refresh"):
				pui.trigger_refresh()
		else:
			UITheme.show_notification("Not enough Spare Parts", UITheme.COLORS["negative"])

	UITheme.show_confirm({
		"title": "Repair Module",
		"body": body,
		"confirm_text": "Repair",
		"cancel_text": "Cancel",
		"accent": UITheme.COLORS["warning"],
		"confirm_disabled": not affordable,
		"on_confirm": on_ok,
	})

func _style_repair_button(btn: Button, hover_color: Color):
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.10, 0.09, 0.95)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.4, 0.3, 0.2, 0.8)
	normal.set_corner_radius_all(3)
	
	var hover = normal.duplicate()
	hover.bg_color = hover_color
	hover.border_color = Color.WHITE
	
	var pressed = hover.duplicate()
	pressed.bg_color = hover_color.darkened(0.2)
	
	var disabled = normal.duplicate()
	disabled.bg_color = Color(0.05, 0.05, 0.05, 0.8)
	disabled.border_color = Color(0.2, 0.2, 0.2, 0.5)
	
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("disabled", disabled)

# TOOLTIP

# v111.20: equipped-module hover → shared rarity-framed tooltip (manual popup).
# Consumable slots fall through to their plain tooltip_text; empty slots show
# nothing here.
func _on_slot_hover() -> void:
	if not is_inside_tree() or slot_type.begins_with("consumable_"):
		return
	if get_viewport().gui_is_dragging():
		return
	var equipped_id = manager.loadout.get(slot_idx)
	if not equipped_id:
		return
	var m_data = manager.modules.get(equipped_id)
	if not m_data:
		return
	var _wz := int(m_data.get("zone", m_data.get("zone_difficulty", 0)))
	var _wm: Texture2D = ElementDB.get_material_icon("Z%d_Core" % clampi(_wz, 1, 10)) if _wz >= 1 else null
	# v136: with a compare pin live, hovering an equipped module shows the pinned baseline
	# and this module side by side — both built by module_card's factory, so an equipped
	# compare looks identical to an Armory compare. Otherwise show the normal tooltip plus
	# the POE-style shortcut footer.
	var eqid := str(equipped_id)
	var pin_mid: String = ModuleCard.compare_pin_mid
	if pin_mid != "" and pin_mid != eqid and pin_mid in manager.modules and eqid in manager.modules:
		var bb_a: String = ModuleCard.build_module_bbcode(pin_mid, "", true)
		var bb_b: String = ModuleCard.build_module_bbcode(eqid, pin_mid, false)
		var a_wz := int(manager.modules[pin_mid].get("zone", manager.modules[pin_mid].get("zone_difficulty", 0)))
		var a_wm: Texture2D = ElementDB.get_material_icon("Z%d_Core" % clampi(a_wz, 1, 10)) if a_wz >= 1 else null
		UITheme.show_compare_tooltip(self, bb_a, bb_b, a_wm, _wm)
	else:
		var _tt := _build_module_tooltip(m_data)
		var _hint := "Shift-click: unpin  ·  Esc: clear compare" if pin_mid == eqid else "Shift-click to pin & compare two modules"
		_tt += "\n[color=#1E3B38]──────────────────────────────[/color]\n[font_size=9][color=#5E7C77]%s[/color][/font_size]" % _hint
		UITheme.show_item_tooltip(self, _tt, _wm)

func _on_slot_unhover() -> void:
	UITheme.hide_item_tooltip(self)

func _build_module_tooltip(m_data: Dictionary) -> String:
	var equipped_id = manager.loadout.get(slot_idx)
	var rarity = manager.get_module_rarity(equipped_id)
	var rarity_label = manager.RARITY_LABELS.get(rarity, "Common")
	if rarity == manager.Rarity.COMMON:
		rarity_label = "Common"

	var rarity_color_hex = manager.RARITY_COLORS.get(rarity, Color.GRAY).to_html(false)
	var s_type = m_data.get("slot_type", "weapon")
	var div = "[color=#1E3B38]──────────────────────────────[/color]\n"

	var tt = ""

	var display_name = _get_clean_name(m_data.get("name", "Item")).to_upper()
	tt += "[font_size=16][b][color=#%s]%s[/color][/b][/font_size]\n" % [rarity_color_hex, display_name]
	tt += "[font_size=10][color=#7FA39C]%s %s[/color][/font_size]\n" % [rarity_label, s_type.capitalize()]
	
	var durability = int(m_data.get("durability", 100))
	var dur_col = "#46E0A0"
	if durability <= 25: dur_col = "#FF6473"
	elif durability <= 50: dur_col = "#FFC24D"
	elif durability <= 75: dur_col = "#D7B842"
	tt += "[font_size=10][color=#7FA39C]Durability:[/color] [color=%s]%d/100[/color][/font_size]\n" % [dur_col, durability]
	
	tt += div

	var stats = m_data.get("stats", {})

	if s_type == "weapon":
		var dmg = stats.get("atk_kinetic", 0) + stats.get("atk_energy", 0) + stats.get("atk_explosive", 0) + stats.get("atk_cryo", 0)
		var interval = max(0.01, float(stats.get("atk_interval", 2.5)))
		var dps = float(dmg) / interval
		tt += "[font_size=24][b]%.1f DPS[/b][/font_size]\n" % dps
		tt += "[font_size=9][color=#7FA39C]%s total damage, %.2f hits/s[/color][/font_size]\n" % [UITheme.format_num(dmg), 1.0 / interval]

		# v87.0 parity: show the damage type + matchup on the EQUIPPED slot too
		if stats.get("atk_kinetic", 0) > 0:
			tt += "[img=15 color=#7088F2]res://assets/icons/modules/weapon_kinetic.svg[/img] [color=#7088F2][b]KINETIC[/b][/color]\n"
			tt += "[img=11 color=#46E0A0]res://assets/icons/ui/chevron_up.svg[/img] [color=#46E0A0]Strong: Hull (+20%)[/color]\n"
			tt += "[img=11 color=#FF6473]res://assets/icons/ui/chevron_down.svg[/img] [color=#FF6473]Weak: Shield (-50%)[/color]\n"
		if stats.get("atk_energy", 0) > 0:
			tt += "[img=15 color=#5FE0C8]res://assets/icons/modules/weapon_energy.svg[/img] [color=#5FE0C8][b]ENERGY[/b][/color]\n"
			tt += "[img=11 color=#46E0A0]res://assets/icons/ui/chevron_up.svg[/img] [color=#46E0A0]Strong: Shield (+50%), Armor Bypass[/color]\n"
			tt += "[img=11 color=#FF6473]res://assets/icons/ui/chevron_down.svg[/img] [color=#FF6473]Weak: Hull (-10%)[/color]\n"
		if stats.get("atk_explosive", 0) > 0:
			tt += "[img=15 color=#FFC24D]res://assets/icons/modules/weapon_explosive.svg[/img] [color=#FFC24D][b]EXPLOSIVE[/b][/color]\n"
			tt += "[img=11 color=#46E0A0]res://assets/icons/ui/chevron_up.svg[/img] [color=#46E0A0]Strong: Armor Bypass (80% pen)[/color]\n"
			tt += "[img=11 color=#FF6473]res://assets/icons/ui/chevron_down.svg[/img] [color=#FF6473]Weak: Slower fire rate[/color]\n"
		if stats.get("atk_cryo", 0) > 0:
			tt += "[img=15 color=#39A6E0]res://assets/icons/modules/weapon_cryo.svg[/img] [color=#39A6E0][b]CRYOGENIC[/b][/color]\n"
			tt += "[img=11 color=#46E0A0]res://assets/icons/ui/chevron_up.svg[/img] [color=#46E0A0]Breaches Warp-Hardened hulls[/color]\n"
			tt += "[img=11 color=#46E0A0]res://assets/icons/ui/chevron_up.svg[/img] [color=#46E0A0]Self-charging — no ammo[/color]\n"
			tt += "[img=11 color=#FF6473]res://assets/icons/ui/chevron_down.svg[/img] [color=#FF6473]Weak: Conventional enemies resist[/color]\n"
		tt += div
	elif s_type == "shield":
		var m_shield = stats.get("max_shield", 0)
		tt += "[font_size=24][b]%s[/b][/font_size] [font_size=10][color=#7FA39C]Shield Capacity[/color][/font_size]\n" % UITheme.format_num(m_shield)
		tt += div
	elif s_type == "armor":
		var hp_val = stats.get("hp", 0)
		tt += "[font_size=24][b]%s[/b][/font_size] [font_size=10][color=#7FA39C]Integrity Reinforcement[/color][/font_size]\n" % UITheme.format_num(hp_val)
		tt += div

	# v110: derived power (tier-based) — replaces the stale energy_load stat.
	if manager:
		if s_type in ["weapon", "shield", "armor", "engine", "sensor"]:
			var draw = manager.get_def_energy_load(m_data)
			if draw > 0:
				tt += "[color=#FFC24D]POWER DRAW: %d[/color]\n" % draw
				tt += div
		elif s_type == "battery":
			var supply = manager.get_def_energy_capacity(m_data)
			if supply > 0:
				tt += "[color=#46E0A0]POWER SUPPLY: +%d[/color]\n" % supply
				tt += div

	var keys = stats.keys()
	keys.sort()
	for key in keys:
		if key == "atk_interval": continue
		if key == "energy_load" or key == "energy_capacity": continue  # v110: derived
		if s_type == "weapon" and key in ["atk_kinetic", "atk_energy", "atk_explosive", "atk_cryo"]: continue
		if s_type == "shield" and key == "max_shield": continue
		if s_type == "armor" and key == "hp": continue
		
		var label = FormatUtils.format_stat_label(key)
		var val = stats[key]
		var val_str = FormatUtils.format_stat_value(key, val)
		
		# v76.0: Display Roll Range for base stats
		var range_info = ""
		var base_id = m_data.get("base_module", "")
		var item_rarity_val = int(m_data.get("rarity", manager.Rarity.COMMON))
		if base_id != "" and base_id in manager.modules and key in manager.BOOSTABLE_STATS:
			var base_val = manager.modules[base_id].get("stats", {}).get(key, 0)
			if base_val > 0:
				var s_range = manager.RARITY_STAT_RANGE.get(item_rarity_val, [0, 0])
				if s_range[1] > 0:
					var r_min = 0.0
					var r_max = 0.0
					var zone_mult = 1.0
					if key in manager.ZONE_SCALABLE_STATS and m_data.has("zone_difficulty"):
						zone_mult = manager.get_module_zone_multiplier(int(m_data.get("zone_difficulty", 1)))
					
					if key == "atk_interval":
						# Better = Lower. Range is [Slowest - Fastest]
						var scaled_base = max(0.25, float(base_val) / zone_mult)
						r_min = max(scaled_base / (1.0 + (s_range[1] * 0.4)), 0.25) # Best (fastest)
						r_max = max(scaled_base / (1.0 + (s_range[0] * 0.4)), 0.25) # Worst (slowest)
					else:
						# Better = Higher. Range is [Lowest - Highest]
						var scaled_base = base_val * zone_mult
						r_min = scaled_base * (1.0 + s_range[0])
						r_max = scaled_base * (1.0 + s_range[1])
						
					range_info = " [color=#7FA39C][font_size=9][%s-%s][/font_size][/color]" % [
						FormatUtils.format_stat_value(key, r_min),
						FormatUtils.format_stat_value(key, r_max)
					]

		tt += "%s: %s%s\n" % [label, val_str, range_info]

	var affixes = m_data.get("affixes", {})
	if affixes.size() > 0:
		tt += div
		var zone_diff = int(m_data.get("zone_difficulty", 1))
		for aid in affixes:
			if aid in manager.AFFIX_DB:
				var cfg = manager.AFFIX_DB[aid]
				var val_raw = affixes[aid]
				var scaling = cfg.get("scaling", "percent")
				
				# v80.1 Fix: Use scaled ranges for display
				var s_range = manager.get_affix_scaled_range(aid, zone_diff)
				var val_str = ""
				var range_str = ""
				
				if scaling == "flat" or scaling == "linear_tier":
					val_str = str(int(val_raw))
					range_str = " [color=#7FA39C][font_size=9][%d-%d][/font_size][/color]" % [int(s_range[0]), int(s_range[1])]
				else:
					val_str = "%d%%" % int(val_raw * 100)
					range_str = " [color=#7FA39C][font_size=9][%d-%d]%%[/font_size][/color]" % [int(s_range[0] * 100), int(s_range[1] * 100)]
				
				var item_rarity_val = int(m_data.get("rarity", manager.Rarity.COMMON))
				var icon = ""
				
				var desc = cfg["desc"] % [int(val_raw) if (scaling == "flat" or scaling == "linear_tier") else int(val_raw * 100)]
				tt += "[img=11 color=#5FE0C8]res://assets/icons/ui/affix_node.svg[/img] [color=#5FE0C8]%s[/color]\n" % desc

	if m_data.has("sockets"):
		tt += div
		for gem in m_data["sockets"]:
			if gem:
				var g_name = ElementDB.get_display_name(gem)
				var g_desc = ElementDB.get_element_description(gem)
				var g_hex = _get_gem_color(g_name).to_html(false)
				if g_desc != "":
					tt += "[color=#%s]%s: %s[/color]\n" % [g_hex, g_name, g_desc]
				else:
					tt += "[color=#%s]%s[/color]\n" % [g_hex, g_name]
			else:
				tt += "[img=11 color=#7FA39C]res://assets/icons/ui/socket_empty.svg[/img] [color=#7FA39C]Empty Socket[/color]\n"

	# v83.9: Set Bonus Tooltip Section
	var sid = m_data.get("set_id", "")
	if sid == "" and m_data.get("is_custom") and m_data.has("base_module"):
		var base_id = m_data["base_module"]
		sid = manager.modules.get(base_id, {}).get("set_id", "")
		
	if sid != "" and GameState.combat_manager and "TRINITY_SET_BONUSES" in GameState.combat_manager:
		var s_db = GameState.combat_manager.TRINITY_SET_BONUSES
		if s_db.has(sid):
			tt += div
			var set_info = s_db[sid]
			var count = GameState.combat_manager.get_set_piece_count(sid)
			var total = set_info["pieces"]
			var active = count >= total
			
			tt += "[b][color=#7088F2]SET: %s[/color][/b]\n" % set_info["name"].to_upper()
			tt += "[font_size=10][color=#7FA39C]%d / %d pieces equipped[/color][/font_size]\n" % [count, total]
			
			for bonus_key in set_info["bonus"]:
				var val = set_info["bonus"][bonus_key]
				var b_name = bonus_key.replace("_pct", "").replace("_flat", "").replace("_", " ").to_upper()
				var val_str = "+%d%%" % val if ("_pct" in bonus_key or "crit" in bonus_key) else "+%d" % val
				
				var col = "#ffffff" if active else "#666666"
				tt += "[color=%s]%s: %s[/color]\n" % [col, b_name, val_str]

	tt += div
	tt += "[center][font_size=10][color=#7FA39C][Right-click to unequip][/color][/font_size][/center]"
	return tt
