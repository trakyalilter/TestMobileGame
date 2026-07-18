extends PanelContainer

const MatrixCoreIcon = preload("res://scripts/ui/matrix_core_icon.gd")

var mid: String
var data: Dictionary
var count: int = 0
var pulse_tween: Tween
var is_selected: bool = false
# v111.14: default OFF. Drag-and-drop equip is retired (it was the source of
# the intermittent detached-node crash); equipping now uses click-to-arm →
# click-slot. Left as a var so any legacy caller can still opt in, but no
# armory/ammo/consumable card enables it anymore.
var is_draggable: bool = false
var compare_equipped_mid: String = ""
# v134g: coach "equip THIS" glow. Set by the designer on the armory card(s) that
# satisfy an active equip mission (e.g. the just-crafted Thruster during m007b) —
# the mission already pulses the target SLOT; this pulses the matching MODULE in
# the Armory so the player knows what to drag, not just where. Overrides the
# subtle rarity shimmer while active.
var coach_pulse: bool = false
# v127: when a Hack Card is armed in the Armory, module tiles show an insert
# socket (accent frame + card bay) so the player sees a valid drop target.
var show_card_socket: bool = false
var _card_socket_node: Panel = null
# v127: while a Hack Card is armed, suppress hover info-cards on every module tile
# (set by the designer page). Static so all tiles share one flag.
static var suppress_info_card: bool = false
# v136: "pin two items to compare". Shift-click a module (Armory OR an equipped slot) to
# PIN it as the comparison baseline. While a pin is live, hovering any OTHER module shows
# BOTH full cards side by side (pinned baseline + hovered) and every armory card shows a
# ▲/▼ chevron vs the pin. compare_pin_mid is shared by all tiles; _bbcode_factory is a
# lazily-built offscreen card that renders the tooltip bbcode for ANY mid, so the baseline
# works even when the pinned/hovered item is equipped and has no armory tile.
static var compare_pin_mid: String = ""
static var _bbcode_factory = null

# Render the comparison-tooltip bbcode for an arbitrary module id, independent of any
# on-screen tile. Reuses one offscreen module_card (never in the tree; its @onready nodes
# stay null but the bbcode builder never touches them).
static func build_module_bbcode(p_mid: String, compare_vs: String = "", no_compare: bool = false) -> String:
	var sm = GameState.shipyard_manager
	if not sm or not p_mid in sm.modules:
		return ""
	if _bbcode_factory == null or not is_instance_valid(_bbcode_factory):
		_bbcode_factory = load("res://scripts/ui/module_card.gd").new()
	_bbcode_factory.mid = p_mid
	_bbcode_factory.data = sm.modules[p_mid]
	_bbcode_factory.count = int(sm.module_inventory.get(p_mid, 0))
	_bbcode_factory.compare_equipped_mid = compare_vs
	return _bbcode_factory._build_comparison_tooltip_bbcode(false, "", no_compare)

signal clicked(p_mid: String)
signal stone_dropped(stone_id: String, target_mid: String)   # v127: Hack Stone dragged onto this module
signal pin_toggled(p_mid: String)   # v136: shift-click → toggle compare baseline

@onready var type_lbl: Label = $Margin/VBox/Header/TypeLabel
@onready var rarity_badge: Label = $Margin/VBox/Header/RarityBadge
@onready var name_lbl: Label = $Margin/VBox/NameLabel
@onready var stats_lbl: Label = $Margin/VBox/StatsLabel
@onready var footer_lbl: Label = $Margin/VBox/FooterLabel

func setup(p_mid: String, p_data: Dictionary, p_count: int):
	mid = p_mid
	data = p_data
	count = p_count
	_update_ui()

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_enter)
	# v111.20: rarity-framed hover tooltip (manual ModalLayer popup) replaces the
	# generic cyan _make_custom_tooltip so the info card frame matches the rarity.
	mouse_exited.connect(func(): UITheme.hide_item_tooltip(self))
	tree_exiting.connect(func(): UITheme.hide_item_tooltip(self))
	_update_ui()

func _zone_watermark(d: Dictionary) -> Texture2D:
	var _wz := int(d.get("zone", d.get("zone_difficulty", 0)))
	return ElementDB.get_material_icon("Z%d_Core" % clampi(_wz, 1, 10)) if _wz >= 1 else null

func _on_mouse_enter():
	# v134g CRASH FIX: never rebuild this card while a drag is in flight. Clearing
	# the "unseen" badge calls _update_ui() → _draw_tile_visual(), which FREES and
	# rebuilds the tile (see its `child.free()`). Doing that to the card the cursor
	# is hovering DURING a drag frees nodes the viewport's drag machinery is still
	# touching → crash (repro: drag a module over a freshly-looted, still-"unseen"
	# tile). The badge clear is cosmetic — defer it past the drag. The tooltip below
	# was already drag-guarded for the same reason; share the one check.
	var _dragging: bool = is_inside_tree() and get_viewport().gui_is_dragging()
	var sm = GameState.shipyard_manager
	if not _dragging and sm and sm.get("unseen_modules") != null and sm.unseen_modules.get(mid, false):
		sm.unseen_modules.erase(mid)
		_update_ui()
	# While holding a Hack Card, don't pop module info-cards (the player is aiming
	# at a socket, not inspecting the module).
	if suppress_info_card:
		return
	# Don't pop info cards on other tiles while a drag is in progress.
	if not data.is_empty() and not _dragging:
		var _wm: Texture2D = _zone_watermark(data)
		# v136: with a compare pin live, hovering any OTHER module shows the pinned
		# baseline and this module as two full cards side by side — this one carries the
		# ▲/▼ deltas vs the pin; the baseline is shown on its own (no delta column). Both
		# sides must be real modules (never ammo/consumable/core vs a module).
		if compare_pin_mid != "" and compare_pin_mid != mid and sm and compare_pin_mid in sm.modules and mid in sm.modules:
			var bb_a: String = build_module_bbcode(compare_pin_mid, "", true)
			var bb_b: String = build_module_bbcode(mid, compare_pin_mid, false)
			UITheme.show_compare_tooltip(self, bb_a, bb_b, _zone_watermark(sm.modules[compare_pin_mid]), _wm)
		else:
			UITheme.show_item_tooltip(self, _build_comparison_tooltip_bbcode(), _wm)

# v131e: self-heal. If a card's setup() ran while its host was momentarily
# detached, the old `not is_inside_tree()` guard below skipped the ENTIRE visual
# build — leaving the raw scene (visible portrait $Margin/VBox + the silver
# default panel), which then relayouts as a portrait card instead of a square
# tile. Rebuild once the node is actually in the tree.
func _enter_tree() -> void:
	if not data.is_empty():
		_update_ui()

func _update_ui():
	# Guard only on missing data — the visual build is tree-safe (local $ lookups,
	# no @onready). The cosmetic pulse/glow tweens self-gate on is_inside_tree().
	if data.is_empty():
		return

	var sm = GameState.shipyard_manager
	var slot_type = data.get("slot_type", "module")
	var rarity = _get_module_rarity_safe(sm)
	var rarity_color = _get_rarity_color_safe(sm, rarity)
	var clean_name = _get_clean_name(data.get("name", "Unknown"))
	
	if slot_type == "gem" or slot_type == "gem_synth":
		_draw_gem_visual(clean_name, rarity_color)
		return

	# DYNAMIC COMPACT VISUAL REDESIGN
	_draw_tile_visual(clean_name, slot_type, rarity, rarity_color, data)
	return

func _draw_tile_visual(item_name: String, slot_type: String, rarity: int, rarity_color: Color, m_data: Dictionary):
	var margin_vbox = $Margin/VBox
	margin_vbox.visible = false

	for child in get_children():
		if child.name == "TileVisual":
			child.free()

	var sm = GameState.shipyard_manager
	var TS := 64.0
	var hi = rarity >= GameState.shipyard_manager.Rarity.RARE
	var top_rarity = rarity >= GameState.shipyard_manager.Rarity.LEGENDARY
	var slot_col = _get_slot_color(slot_type)
	# Weapons read by DAMAGE FAMILY, not the generic weapon colour, so
	# kinetic / energy / explosive are distinguishable at a glance.
	if slot_type == "weapon":
		slot_col = _weapon_dmg_color(m_data.get("stats", {}))
	# v131d: ammo shares ONE icon, so a generic orange chip made every round look
	# identical. Colour it by DAMAGE TYPE (matching the weapon it feeds) + a tier
	# stamp below, so KIN/NRG/EXP and T1..T4 read at a glance.
	elif slot_type == "ammo":
		slot_col = _ammo_dmg_color(_ammo_type(mid))

	# Expand to fill the grid column; height stays fixed via min size.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, TS)
	# v111.7: keep cells square. EXPAND_FILL stretches us wider than TS in
	# the grid (good — looks full), but the original code left height fixed
	# at TS, producing 2:1 rectangles. Track our rendered width via the
	# resized signal and bump min height to match so we render as a square.
	if not resized.is_connected(_keep_square):
		resized.connect(_keep_square)
	var tile_container = Control.new()
	tile_container.name = "TileVisual"
	tile_container.custom_minimum_size = Vector2(0, TS)
	tile_container.mouse_filter = Control.MOUSE_FILTER_PASS

	# --- Socket backplate: matches the empty-slot filler so a filled cell
	# reads as "module seated in a slot", consistent with the empty cells
	# and the equipped-slot panel. ---
	var socket = Panel.new()
	socket.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	socket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sock_sb = StyleBoxFlat.new()
	if slot_type == "hack_stone":
		# v127: Hack Stones show ONLY the hexagon shard — no square socket/chip wrap.
		sock_sb.bg_color = Color(0, 0, 0, 0)
	else:
		sock_sb.bg_color = Color(0.03, 0.045, 0.07, 0.92)
		sock_sb.set_corner_radius_all(5)
		sock_sb.set_border_width_all(1)
		sock_sb.border_color = Color(0.24, 0.36, 0.48, 0.85)
		sock_sb.shadow_color = Color(0, 0, 0, 0.55)
		sock_sb.shadow_size = 3
	socket.add_theme_stylebox_override("panel", sock_sb)
	tile_container.add_child(socket)

	# --- Frame: rarity plate seated inside the socket (rim shows around) ---
	# Hack stones render as a bare shard: skip the rarity plate entirely so no
	# rounded-square border wraps the hexagon (socket/emblem/root cleared too).
	if slot_type != "hack_stone":
		var bg_panel = Panel.new()
		bg_panel.anchor_right = 1.0
		bg_panel.anchor_bottom = 1.0
		bg_panel.offset_left = 5
		bg_panel.offset_top = 5
		bg_panel.offset_right = -5
		bg_panel.offset_bottom = -5
		bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb = StyleBoxFlat.new()
		sb.bg_color = _get_rarity_background(rarity)
		sb.set_corner_radius_all(4)
		sb.set_border_width_all(2 if not top_rarity else 3)
		sb.border_color = rarity_color
		sb.shadow_color = Color(rarity_color.r, rarity_color.g, rarity_color.b,
			0.0 if rarity == sm.Rarity.COMMON else (0.32 if hi else 0.16))
		sb.shadow_size = (9 if top_rarity else (6 if hi else 0))
		bg_panel.add_theme_stylebox_override("panel", sb)
		tile_container.add_child(bg_panel)

	# --- Zone/tier EMBLEM: a top-right CORNER STAMP (v131c — was a faint full-tile
	# watermark), matching the equipped-slot _ZoneBadge: the emblem texture drawn
	# directly, NO background plate. The compare chevron is relocated to the bottom
	# to free this corner. ---
	var zsrc := int(m_data.get("zone", m_data.get("zone_difficulty", 0)))
	if zsrc >= 1:
		var zid := "Z%d_Core" % clampi(zsrc, 1, 10)
		var ztex := ElementDB.get_material_icon(zid)
		if ztex:
			var bs := 26.0
			var pad := 4.0
			var zmark := TextureRect.new()
			zmark.texture = ztex
			zmark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			zmark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			zmark.anchor_left = 1.0; zmark.anchor_right = 1.0
			zmark.offset_left = -(bs + pad); zmark.offset_right = -pad
			zmark.offset_top = pad; zmark.offset_bottom = pad + bs
			var zt: Color = ElementDB.get_material_tint(zid)
			zt.a = 0.95
			zmark.modulate = zt
			zmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tile_container.add_child(zmark)

	# (No top colour band -- it read as a durability/progress meter. Category
	# is already carried by the emblem chip + icon tint.)

	# --- Centre emblem: slot-coloured chip + bold type letter ---
	# v127: Hack Stones skip the chip entirely — the big hexagon shard IS the visual.
	# v131c: chip 0.5 -> 0.58 of the tile — paired with the de-watermarked module
	# glyphs (fill 0.16->0.34, strokes 0.55->0.92) so the icon is the scan cue again.
	var em := TS * 0.58
	var is_stone: bool = (slot_type == "hack_stone")
	var icon_parent: Control = tile_container
	if not is_stone:
		var emblem = Panel.new()
		emblem.anchor_left = 0.5; emblem.anchor_right = 0.5
		emblem.anchor_top = 0.5; emblem.anchor_bottom = 0.5
		emblem.offset_left = -em * 0.5; emblem.offset_right = em * 0.5
		emblem.offset_top = -em * 0.5 - 1.0; emblem.offset_bottom = em * 0.5 - 1.0
		emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var esb = StyleBoxFlat.new()
		# Chip fill is near-neutral so RARITY (the frame) and SLOT (icon + chip rim)
		# read on separate channels — no more gold-chip-on-gold-frame confusion.
		esb.bg_color = slot_col.lerp(Color(0.05, 0.09, 0.10), 0.84)
		esb.set_corner_radius_all(5)
		esb.set_border_width_all(1)
		esb.border_color = slot_col.lerp(Color.WHITE, 0.1)
		emblem.add_theme_stylebox_override("panel", esb)
		tile_container.add_child(emblem)
		icon_parent = emblem

	var icon_tex = _get_module_icon(slot_type, m_data.get("stats", {}), m_data)
	if icon_tex:
		var icon = TextureRect.new()
		icon.texture = icon_tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if is_stone:
			# Big centred shard filling ~72% of the cell — the hexagon reads as the
			# item itself; tint by its material colour (distinct coloured crystal).
			icon.anchor_left = 0.14; icon.anchor_top = 0.14
			icon.anchor_right = 0.86; icon.anchor_bottom = 0.86
			icon.modulate = ElementDB.get_material_tint(mid).lerp(Color.WHITE, 0.18)
		else:
			icon.anchor_right = 1.0; icon.anchor_bottom = 1.0
			icon.offset_left = 5; icon.offset_top = 5
			icon.offset_right = -5; icon.offset_bottom = -5
			icon.modulate = slot_col.lerp(Color.WHITE, 0.85)
		icon_parent.add_child(icon)
	else:
		var letter_lbl = Label.new()
		letter_lbl.text = _get_type_char(slot_type)
		letter_lbl.add_theme_font_size_override("font_size", 20)
		letter_lbl.add_theme_color_override("font_color", slot_col.lerp(Color.WHITE, 0.75))
		letter_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter_lbl.anchor_right = 1.0; letter_lbl.anchor_bottom = 1.0
		letter_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_parent.add_child(letter_lbl)

	# --- Socket pips: show matrix-core slots (filled = gem colour, empty =
	# hollow), top-centre, mirroring the equipped-slot panel's diamonds ---
	if m_data.has("sockets") and m_data["sockets"].size() > 0:
		var socks = m_data["sockets"]
		var n: int = socks.size()
		var d := 7.0
		var gap := 3.0
		var total: float = n * d + (n - 1) * gap
		var row = Control.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.anchor_left = 0.5; row.anchor_right = 0.5
		row.offset_left = -total * 0.5; row.offset_right = total * 0.5
		row.offset_top = 3; row.offset_bottom = 3 + d
		tile_container.add_child(row)
		for i in range(n):
			var dia = Panel.new()
			dia.size = Vector2(d, d)
			dia.position = Vector2(i * (d + gap), 0)
			dia.pivot_offset = Vector2(d * 0.5, d * 0.5)
			dia.rotation_degrees = 45
			dia.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var dsb = StyleBoxFlat.new()
			dsb.set_border_width_all(1)
			var gem = socks[i]
			if gem:
				var gc = _get_gem_color(ElementDB.get_display_name(gem))
				dsb.bg_color = gc
				dsb.border_color = gc.lerp(Color.WHITE, 0.5)
			else:
				dsb.bg_color = Color(0, 0, 0, 0.45)
				dsb.border_color = Color(0.55, 0.60, 0.68, 0.85)
			dia.add_theme_stylebox_override("panel", dsb)
			row.add_child(dia)

	# --- Compare chevron: upgrade/downgrade scan cue, top-right ---
	var cmp = _compute_compare_summary()
	if cmp != "":
		var cmp_lbl = Label.new()
		cmp_lbl.text = cmp
		cmp_lbl.add_theme_font_size_override("font_size", 14)
		cmp_lbl.add_theme_color_override("font_color",
			Color(0.40, 1.0, 0.55) if cmp == "▲" else (Color(1.0, 0.40, 0.40) if cmp == "▼" else Color(0.80, 0.80, 0.80)))
		# v131c: moved top-right → bottom-right (the top-right corner now holds the
		# zone/tier emblem stamp). Sits just above the equipped underline.
		cmp_lbl.anchor_left = 1.0; cmp_lbl.anchor_right = 1.0
		cmp_lbl.anchor_top = 1.0; cmp_lbl.anchor_bottom = 1.0
		cmp_lbl.offset_left = -19; cmp_lbl.offset_right = -2
		cmp_lbl.offset_top = -26; cmp_lbl.offset_bottom = -8
		cmp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cmp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile_container.add_child(cmp_lbl)

	# --- v127: ammo tile shows NO corner stamp — the damage-type colour is the only
	# cue (dropped the old T1..T4 tier stamp and the +ATK bonus stamp per feedback). ---

	# --- Count chip, top-left ---
	if count > 1:
		var count_badge = _make_count_chip(count)
		count_badge.position = Vector2(6, 5)
		tile_container.add_child(count_badge)
		tile_container.move_child(count_badge, tile_container.get_child_count() - 1)  # paint on top

	# Power/tier readout is intentionally NOT drawn on the tile — every module's
	# full info is available on hover (the rarity-framed tooltip). Keeps the armory
	# grid clean; the icon + rarity frame + zone watermark carry the glance identity.
	# (Sort·Power still works — it computes its key from stats, not from this label.)

	# --- Equipped marker: bright slot-colour underline ---
	if sm and mid in sm.loadout.values():
		var eq = ColorRect.new()
		eq.color = Color(0.45, 1.0, 0.6, 0.95)
		eq.anchor_top = 1.0; eq.anchor_right = 1.0; eq.anchor_bottom = 1.0
		eq.offset_left = 7; eq.offset_right = -7
		eq.offset_top = -8; eq.offset_bottom = -5
		eq.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile_container.add_child(eq)

	# --- Unseen indicator (yellow orb) ---
	if sm and sm.get("unseen_modules") != null and sm.unseen_modules.get(mid, false):
		var orb = Panel.new()
		orb.size = Vector2(8, 8)
		orb.position = Vector2(-2, -2)
		orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var osb = StyleBoxFlat.new()
		osb.bg_color = Color(1.0, 0.9, 0.1)
		osb.set_corner_radius_all(4)
		osb.shadow_color = Color(1.0, 0.9, 0.1, 0.6)
		osb.shadow_size = 4
		orb.add_theme_stylebox_override("panel", osb)
		tile_container.add_child(orb)

	# --- Selection highlight (cyan glow) ---
	if is_selected:
		var selection_panel = Panel.new()
		selection_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		selection_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ssb = StyleBoxFlat.new()
		ssb.bg_color = Color(0, 0, 0, 0)
		ssb.set_border_width_all(3)
		ssb.border_color = Color(0, 1.0, 1.0, 0.85)
		ssb.set_corner_radius_all(4)
		ssb.shadow_color = Color(0, 1.0, 1.0, 0.4)
		ssb.shadow_size = 6
		selection_panel.add_theme_stylebox_override("panel", ssb)
		tile_container.add_child(selection_panel)

	# --- v127: Hack-card insert socket. Shown on module tiles while a Hack Card
	# is armed in the Armory: an accent frame (valid target) + a centred card bay
	# the card animates into. Only the designer's module cards set the flag. ---
	_card_socket_node = null
	if show_card_socket:
		var insert_acc := Color(0.40, 0.60, 1.0)
		# Faint valid-target frame on the whole tile.
		var insert_frame := Panel.new()
		insert_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		insert_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var insert_frame_sb := StyleBoxFlat.new()
		insert_frame_sb.bg_color = Color(insert_acc.r, insert_acc.g, insert_acc.b, 0.08)
		insert_frame_sb.set_corner_radius_all(4)
		insert_frame_sb.set_border_width_all(2)
		insert_frame_sb.border_color = Color(insert_acc.r, insert_acc.g, insert_acc.b, 0.85)
		insert_frame_sb.shadow_color = Color(insert_acc.r, insert_acc.g, insert_acc.b, 0.35)
		insert_frame_sb.shadow_size = 5
		insert_frame.add_theme_stylebox_override("panel", insert_frame_sb)
		tile_container.add_child(insert_frame)
		# Socket housing (blue mount) — a thin vertical slot the width of the card's
		# edge, with a near-black slot the card slides edge-first into.
		var housing := Panel.new()
		housing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		housing.anchor_left = 0.5; housing.anchor_top = 0.5
		housing.anchor_right = 0.5; housing.anchor_bottom = 0.5
		housing.offset_left = -12; housing.offset_right = 12
		housing.offset_top = -32; housing.offset_bottom = 32
		var housing_sb := StyleBoxFlat.new()
		housing_sb.bg_color = Color(insert_acc.r, insert_acc.g, insert_acc.b, 0.95)
		housing_sb.set_corner_radius_all(3)
		housing.add_theme_stylebox_override("panel", housing_sb)
		insert_frame.add_child(housing)
		var slot := Panel.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		slot.offset_left = 3; slot.offset_top = 4
		slot.offset_right = -3; slot.offset_bottom = -4
		var slot_sb := StyleBoxFlat.new()
		slot_sb.bg_color = Color(0.02, 0.03, 0.05, 1.0)
		slot_sb.set_corner_radius_all(2)
		slot_sb.shadow_color = Color(0, 0, 0, 0.6)
		slot_sb.shadow_size = 3
		slot.add_theme_stylebox_override("panel", slot_sb)
		housing.add_child(slot)
		_card_socket_node = insert_frame

	# Self panel is just a transparent host; the tile draws its own frame.
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_apply_pulse(rarity)

	UITheme.attach_rarity_fx(tile_container, rarity, rarity_color)
	add_child(tile_container)
	# Pulse the insert socket (tweens require in-tree; skip cleanly when detached).
	if show_card_socket and is_instance_valid(_card_socket_node) and is_inside_tree():
		var pt := create_tween()
		if pt:
			pt.set_loops()
			pt.tween_property(_card_socket_node, "modulate:a", 0.45, 0.55).set_trans(Tween.TRANS_SINE)
			pt.tween_property(_card_socket_node, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE)
	# v127: Hack Stones show ONLY the shard — clear the root PanelContainer frame
	# too (the transparent socket would otherwise reveal the default panel behind it).
	if slot_type == "hack_stone":
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	# Armory tiles are tiny — request the translucent dim variant so the
	# rarity frame + slot icon underneath still read instead of the card
	# going fully black.
	if sm and mid in sm.modules:
		var status = sm.can_equip_module(mid)
		UITheme.apply_locked_overlay(self, item_name, status["reason"], not status["can_equip"], "", "ops", true)
	else:
		UITheme.apply_locked_overlay(self, item_name, "", false, "", "ops", true)

## Compact power readout — the key behind Sort·Power. No longer drawn on the tile
## (module info lives in the hover tooltip); kept as the sort/compare value source.
func _get_power_readout(slot_type: String, stats: Dictionary) -> String:
	match slot_type:
		"weapon":
			return "%s" % FormatUtils.format_number(_weapon_dps(stats))
		"shield":
			return FormatUtils.format_number(float(stats.get("max_shield", 0)))
		"armor":
			return FormatUtils.format_number(float(stats.get("hp", 0)))
		"ammo", "consumable", "gem", "gem_synth":
			return ""
	var sc := _stat_score(stats)
	return "" if sc == 0.0 else FormatUtils.format_number(sc)

func _get_type_char(s_type: String) -> String:
	match s_type:
		"weapon": return "W"
		"shield": return "S"
		"armor": return "A"
		"engine": return "E"
		"battery": return "B"
		"reactor": return "R"
		"sensor": return "V"
		"cooling": return "C"
		"ammo": return "O"
		"consumable": return "H"
		"gem", "gem_synth": return "G"
	return "M"

# Drawn type icon (weapons split by damage family). Loaded once per key and
# cached across every card instance.
static var _icon_cache: Dictionary = {}

func _get_module_icon(slot_type: String, stats: Dictionary, m_data: Dictionary = {}) -> Texture2D:
	# v127: Hack Stones are ITEMS, not modules — each has its own material icon
	# (a distinct data-shard sigil). Keying off slot_type made every stone load the
	# one generic modules/module.svg, so they all looked identical. Use the per-item
	# icon; fall through to the generic module tile only if its SVG isn't imported.
	if slot_type == "hack_stone":
		var htex = ElementDB.get_material_icon(mid)
		if htex:
			return htex
	var key = slot_type
	if slot_type == "weapon":
		key = "weapon_" + _weapon_type(stats)
		# Corrosion rides the cryo channel (atk_cryo) but is tagged exotic — give
		# it its own ship-turret icon instead of falling back to the cryo one.
		if str(stats.get("exotic_element", "")) == "corrosion":
			key = "weapon_corrosion"
	# v111.9: split consumables into hull-patch and shield-booster icons.
	# Was using a single `consumable.svg` (the medieval-potion placeholder)
	# for every consumable, so the player couldn't distinguish a +10% Hull
	# patch from a +10% Shield booster at a glance. Now the icon silhouette
	# itself carries the type — hex plate = hull, capacitor = shield.
	if slot_type == "consumable":
		var ctype: String = str(m_data.get("consumable_type", ""))
		if ctype == "hull":
			key = "consumable_hull"
		elif ctype == "shield":
			key = "consumable_shield"
		# else: fall through to plain "consumable" (any unknown type)
	var valid = ["weapon_kinetic", "weapon_energy", "weapon_explosive", "weapon_cryo", "weapon_corrosion",
		"shield", "armor", "engine", "battery", "reactor", "sensor",
		"cooling", "ammo", "consumable", "consumable_hull", "consumable_shield"]
	if not (key in valid):
		key = "module"
	if key in _icon_cache:
		return _icon_cache[key]
	var tex = load("res://assets/icons/modules/%s.svg" % key) as Texture2D
	_icon_cache[key] = tex
	return tex

# Damage-family identity for weapons (colour is the primary scan cue,
# the tag is the unambiguous backup).
func _weapon_dmg_color(stats: Dictionary) -> Color:
	match _weapon_type(stats):
		"cryo": return Color(0.70, 0.95, 1.0)  # v109: pale ice (distinct from energy cyan)
		"energy": return Color(0.32, 0.80, 1.0)
		"explosive": return Color(1.0, 0.45, 0.30)
		_: return Color(0.92, 0.66, 0.32)

func _weapon_dmg_tag(stats: Dictionary) -> String:
	match _weapon_type(stats):
		"cryo": return "CRY"  # v109
		"energy": return "NRG"
		"explosive": return "EXP"
		_: return "KIN"

# v131d: ammo identity from its id. Slug* = kinetic, Cell* = energy, Missile* =
# explosive; tier is the digit after "T" (SlugT2 -> T2). Colours mirror
# _weapon_dmg_color so a round matches the weapon family it feeds.
func _ammo_type(id: String) -> String:
	if id.begins_with("Slug"): return "kinetic"
	if id.begins_with("Cell"): return "energy"
	if id.begins_with("Missile"): return "explosive"
	return "kinetic"

func _ammo_tier(id: String) -> String:
	var ti := id.find("T")
	while ti >= 0:
		var c := id.substr(ti + 1, 1)
		if c.is_valid_int():
			return "T" + c
		ti = id.find("T", ti + 1)
	return ""

func _ammo_dmg_color(atype: String) -> Color:
	match atype:
		"energy": return Color(0.32, 0.80, 1.0)
		"explosive": return Color(1.0, 0.45, 0.30)
		_: return Color(0.92, 0.66, 0.32)

func _compute_compare_summary() -> String:
	# At-a-glance upgrade indicator vs the focused-slot's equipped module.
	# Returns "▲" / "▼" / "=" / "" (empty = nothing to compare against).
	if compare_equipped_mid == "" or compare_equipped_mid == mid:
		return ""
	var sm = GameState.shipyard_manager
	if not sm or not compare_equipped_mid in sm.modules:
		return ""
	if not mid in sm.modules:
		return ""
	var my_stats = data.get("stats", {})
	var eq_stats = sm.modules[compare_equipped_mid].get("stats", {})

	# Weapons: only compare within the SAME damage type. A DPS chevron
	# between e.g. KINETIC and EXPLOSIVE is misleading — they're situational
	# (explosive bypasses armor, energy melts shields), so a raw "better/
	# worse" is wrong advice. Different type => no arrow at all.
	if data.get("slot_type", "") == "weapon":
		if _weapon_type(my_stats) != _weapon_type(eq_stats):
			return ""
		var my_dps := _weapon_dps(my_stats)
		var eq_dps := _weapon_dps(eq_stats)
		if abs(my_dps - eq_dps) < 0.05:
			return "="
		return "▲" if my_dps > eq_dps else "▼"
	# Sum every stat the module carries (not a hardcoded list) so each slot
	# type compares on its own profile: engine -> eva, battery ->
	# energy_capacity, sensor -> accuracy, weapon -> atk_*, etc. Comparisons
	# are always same-slot-type (designer_page only sets compare_equipped_mid
	# for matching types), so a raw sum is valid here. Lower-is-better stats
	# are subtracted.
	var my_score = _stat_score(my_stats)
	var eq_score = _stat_score(eq_stats)
	if abs(my_score - eq_score) < 0.5:
		return "="
	return "▲" if my_score > eq_score else "▼"

# Stats where a lower value is the upgrade (faster fire = shorter interval).
const _COMPARE_INVERSE_STATS := ["atk_interval"]

func _stat_score(stats: Dictionary) -> float:
	var s := 0.0
	for k in stats:
		var v = stats[k]
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			continue
		if k in _COMPARE_INVERSE_STATS:
			s -= float(v)
		else:
			s += float(v)
	return s

func _weapon_dps(stats: Dictionary) -> float:
	var dmg := float(stats.get("atk_kinetic", 0)) + float(stats.get("atk_energy", 0)) + float(stats.get("atk_explosive", 0)) + float(stats.get("atk_cryo", 0))
	var interval := maxf(0.01, float(stats.get("atk_interval", 2.5)))
	return dmg / interval

# Mirrors combat_manager's weapon-type rule so the compare chevron only
# appears between like-for-like damage types.
func _weapon_type(stats: Dictionary) -> String:
	if float(stats.get("atk_cryo", 0)) > 0.0:  # v109: 4th type
		return "cryo"
	if float(stats.get("atk_energy", 0)) > 0.0:
		return "energy"
	if float(stats.get("atk_explosive", 0)) > 0.0:
		return "explosive"
	return "kinetic"

func _get_item_tier(item_name: String, m_data: Dictionary) -> String:
	if m_data.has("tier"):
		return str(m_data["tier"])
	
	if "Mk." in item_name:
		var parts = item_name.split("Mk.")
		if parts.size() > 1:
			var roman = parts[1].strip_edges().split(" ")[0]
			if roman == "I": return "1"
			if roman == "II": return "2"
			if roman == "III": return "3"
			if roman == "IV": return "4"
			if roman == "V": return "5"
			if roman == "VI": return "6"
			return roman
			
	if "T1" in item_name: return "1"
	if "T2" in item_name: return "2"
	if "T3" in item_name: return "3"
	if "T4" in item_name: return "4"
	if "T5" in item_name: return "5"
	
	return "1"

func _draw_gem_visual(gem_name: String, rarity_color: Color):
	var margin_vbox = $Margin/VBox
	margin_vbox.visible = false
	
	for child in get_children():
		if child.name == "GemVisual":
			child.free()
			
	# v111.16: match the empty-slot / module-tile cell so cores SIT IN a slot
	# (expanding square cell, seated on the same dark socket plate) instead of
	# floating at a fixed 40px size.
	var TS := 64.0
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_FILL
	custom_minimum_size = Vector2(0, TS)
	if not resized.is_connected(_keep_square):
		resized.connect(_keep_square)

	var gem_container = Control.new()
	gem_container.name = "GemVisual"
	gem_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gem_container.mouse_filter = Control.MOUSE_FILTER_PASS

	# Socket backplate — identical to module tiles / empty slots, so a filled
	# core cell reads as "core seated in a slot", flush with the empty cells.
	var socket = Panel.new()
	socket.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	socket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sock_sb = StyleBoxFlat.new()
	sock_sb.bg_color = Color(0.03, 0.045, 0.07, 0.92)
	sock_sb.set_corner_radius_all(5)
	sock_sb.set_border_width_all(1)
	sock_sb.border_color = Color(0.24, 0.36, 0.48, 0.85)
	sock_sb.shadow_color = Color(0, 0, 0, 0.55)
	sock_sb.shadow_size = 3
	socket.add_theme_stylebox_override("panel", sock_sb)
	gem_container.add_child(socket)

	# Faceted crystal core, seated INSIDE the socket with the same 5px inset the
	# module tiles use for their rarity plate. Added above the plate; the count
	# badge / unseen orb / selection ring still paint on top of it.
	var core := MatrixCoreIcon.new()
	core.name = "Core"
	core.anchor_right = 1.0
	core.anchor_bottom = 1.0
	core.offset_left = 5
	core.offset_top = 5
	core.offset_right = -5
	core.offset_bottom = -5
	core.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Tier from the element key (mid, e.g. "CrackedCrimsonCore") — robust even if
	# the display name drops the tier word.
	core.set_core(_get_gem_color(gem_name), false, MatrixCoreIcon.tier_from_name(mid))
	gem_container.add_child(core)

	if count > 1:
		var count_badge = _make_count_chip(count)
		count_badge.position = Vector2(6, 5)
		gem_container.add_child(count_badge)
		gem_container.move_child(count_badge, gem_container.get_child_count() - 1)  # paint on top

	# Unseen indicator (Yellow Orb)
	var sm2 = GameState.shipyard_manager
	if sm2 and sm2.get("unseen_modules") != null and sm2.unseen_modules.get(mid, false):
		var orb = Panel.new()
		orb.custom_minimum_size = Vector2(8, 8)
		orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var osb = StyleBoxFlat.new()
		osb.bg_color = Color(1.0, 0.9, 0.1) # Bright yellow
		osb.set_corner_radius_all(4)
		osb.shadow_color = Color(1.0, 0.9, 0.1, 0.6)
		osb.shadow_size = 4
		orb.add_theme_stylebox_override("panel", osb)
		orb.position = Vector2(-2, -2)
		gem_container.add_child(orb)

	# Selection Highlight (Cyan Glow for Gems)
	if is_selected:
		var selection_panel = Panel.new()
		selection_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		selection_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ssb = StyleBoxFlat.new()
		ssb.bg_color = Color(0, 0, 0, 0)
		ssb.set_border_width_all(3)
		ssb.border_color = Color(0, 1.0, 1.0, 0.8) # Cyan
		ssb.set_corner_radius_all(3)
		ssb.shadow_color = Color(0, 1.0, 1.0, 0.4)
		ssb.shadow_size = 6
		selection_panel.add_theme_stylebox_override("panel", ssb)
		gem_container.add_child(selection_panel)
		
	var sm = GameState.shipyard_manager
	var rarity = _get_module_rarity_safe(sm)
	_apply_card_style(rarity, rarity_color, "gem")
	_apply_pulse(rarity)

	# Cores carry their tier in data ("rarity": 2/3/4 for Cracked/Stable/Pristine),
	# so use that for the shimmer rather than the modules-only lookup.
	UITheme.attach_rarity_fx(gem_container, int(data.get("rarity", rarity)), rarity_color)
	add_child(gem_container)
	
	# Small glow tween to make the core feel alive (tweens require in-tree).
	if is_inside_tree():
		var glow_tween = create_tween().set_loops()
		glow_tween.tween_property(core, "modulate", Color(1.2, 1.2, 1.2), 1.5).set_trans(Tween.TRANS_SINE)
		glow_tween.tween_property(core, "modulate", Color(0.9, 0.9, 0.9), 1.5).set_trans(Tween.TRANS_SINE)


func _get_module_rarity_safe(sm) -> int:
	if not sm:
		return 0
	if mid in sm.modules:
		return sm.get_module_rarity(mid)
	return sm.Rarity.COMMON

func _get_rarity_color_safe(sm, rarity: int) -> Color:
	if not sm:
		return Color(0.7, 0.7, 0.7)
	return sm.RARITY_COLORS.get(rarity, Color(0.7, 0.7, 0.7))

func _get_rarity_label_safe(sm, rarity: int) -> String:
	if not sm or rarity == sm.Rarity.COMMON:
		return ""
	return sm.RARITY_LABELS.get(rarity, "")

func _get_clean_name(raw_name: String) -> String:
	var title = raw_name
	for suffix in [" (Common)", " (Uncommon)", " (Rare)", " (Legendary)", " (Unique)"]:
		title = title.replace(suffix, "")
	return title

func _build_card_stats(slot_type: String, stats: Dictionary) -> String:
	if slot_type == "ammo":
		return _build_ammo_card_stats()

	if slot_type == "consumable":
		var heal_pct = int(round(data.get("heal_pct", data.get("stats", {}).get("heal_pct", 0.0)) * 100.0))
		var target = data.get("consumable_type", "hull").capitalize()
		return "Restores %d%% %s" % [heal_pct, target]

	var lines: Array[String] = []

	if slot_type == "weapon":
		var dmg = stats.get("atk_kinetic", 0) + stats.get("atk_energy", 0) + stats.get("atk_explosive", 0) + stats.get("atk_cryo", 0)
		var interval = max(0.01, float(stats.get("atk_interval", 2.5)))
		lines.append("DPS: %.1f" % (float(dmg) / interval))

		# v87.0: Damage Type Strong/Weak (Condensed)
		if stats.get("atk_kinetic", 0) > 0: lines.append(tr("KIN - Strong vs Hull, Weak vs Shield"))
		if stats.get("atk_energy", 0) > 0: lines.append(tr("NRG - Strong vs Shield, Bypasses Armor"))
		if stats.get("atk_explosive", 0) > 0: lines.append(tr("EXP - Bypasses Armor, Slower Fire"))
		if stats.get("atk_cryo", 0) > 0: lines.append(tr("CRY - Breaches Warp-Hardened, Weak vs Conventional"))

	# v110: derived power (tier-based) — replaces the stale energy_load stat.
	var sm = GameState.shipyard_manager
	if sm:
		if slot_type in ["weapon", "shield", "armor", "engine", "sensor"]:
			var draw = sm.get_module_energy_load(mid)
			if draw > 0: lines.append("POWER DRAW: %d" % draw)
		elif slot_type == "battery":
			var supply = sm.get_module_energy_capacity(mid)
			if supply > 0: lines.append("POWER: +%d" % supply)

	var keys = stats.keys()
	keys.sort()

	var ga_list = data.get("greater_affixes", [])

	for key in keys:
		if key == "atk_interval":
			continue
		var val = stats[key]
		if key == "energy_load" or key == "energy_capacity":
			continue
		var label = FormatUtils.format_stat_label(key)
		var ga_prefix = "[color=#FFC24D]+[/color] " if key in ga_list else ""
		lines.append("%s%s: %s" % [ga_prefix, label, FormatUtils.format_stat_value(key, val)])
		if lines.size() >= 5: # Increased limit slightly
			break

	if lines.is_empty():
		if slot_type == "gem":
			return data.get("desc", tr("No combat modifiers"))
		return tr("No combat modifiers")
	return "\n".join(lines)

func _build_ammo_card_stats() -> String:
	var bonus = 0.0
	var type_label = "Damage"

	if mid.begins_with("Slug"):
		bonus = 5.0
		if "T1S" in mid:
			bonus = 10.0
		elif "T2" in mid:
			bonus = 15.0
		elif "T3" in mid:
			bonus = 30.0
		elif "T4" in mid:
			bonus = 60.0
		type_label = "Kinetic"
	elif mid.begins_with("Cell"):
		bonus = 5.0
		if "T2" in mid:
			bonus = 15.0
		elif "T3" in mid:
			bonus = 30.0
		elif "T4" in mid:
			bonus = 60.0
		type_label = "Energy"
	elif "Missile" in mid or "Torpedo" in mid:
		bonus = 10.0
		if "Seeker" in mid:
			bonus = 25.0
		elif "Torpedo" in mid:
			bonus = 60.0
		type_label = "Explosive"

	if bonus <= 0.0:
		return "Ammunition"
	return "+%.1f %s Damage" % [bonus, type_label]

func _build_footer_text(slot_type: String, rarity_label: String) -> String:
	var parts: Array[String] = []
	if rarity_label != "":
		parts.append(rarity_label.to_upper())
	if slot_type != "":
		parts.append(slot_type.to_upper())
	if count > 1:
		parts.append("x%d" % count)
	if parts.is_empty():
		return ""
	return " | ".join(parts)

# Stack-count chip — a dark rounded badge with cyan ×N text, shared by the module
# tile and the matrix-core tile so the corner tally reads as an intentional chip
# instead of raw text crammed against the corner bracket. format_num keeps big
# counts compact (e.g. ×12.0K) so the chip never overruns the cell.
func _make_count_chip(n: int) -> Control:
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.08, 0.85)
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.45, 0.85, 1.0, 0.45)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = tr("×%s") % UITheme.format_num(n)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.80, 1.0, 1.0))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(lbl)
	return badge


func _apply_card_style(rarity: int, rarity_color: Color, slot_type: String = "module"):
	var frame = StyleBoxFlat.new()
	frame.bg_color = _get_rarity_background(rarity)
	frame.set_corner_radius_all(3)
	
	if slot_type == "gem" or slot_type == "gem_synth":
		frame.bg_color = Color(0, 0, 0, 0.0) # Transparent background
		frame.set_border_width_all(0)
		frame.shadow_size = 0
		add_theme_stylebox_override("panel", frame)
		return
		
	frame.set_border_width_all(2)
	frame.border_width_top = 5
	frame.border_color = rarity_color.lerp(Color(0.55, 0.45, 0.34), 0.35)
	frame.content_margin_left = 6
	frame.content_margin_top = 5
	frame.content_margin_right = 6
	frame.content_margin_bottom = 5
	frame.shadow_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.2)
	frame.shadow_size = 8
	frame.shadow_offset = Vector2(0, 2)

	var sm = GameState.shipyard_manager
	if sm and (rarity == sm.Rarity.LEGENDARY or rarity == sm.Rarity.UNIQUE):
		frame.set_border_width_all(3)
		frame.border_width_top = 6
		frame.shadow_size = 12

	add_theme_stylebox_override("panel", frame)

func _get_rarity_background(rarity: int) -> Color:
	var sm = GameState.shipyard_manager
	if not sm:
		return Color(0.11, 0.09, 0.08, 0.96)

	if rarity == sm.Rarity.UNCOMMON:
		return Color(0.08, 0.11, 0.08, 0.96)
	if rarity == sm.Rarity.RARE:
		return Color(0.07, 0.10, 0.14, 0.96)
	if rarity == sm.Rarity.LEGENDARY:
		return Color(0.15, 0.10, 0.06, 0.98)
	if rarity == sm.Rarity.UNIQUE:
		return Color(0.16, 0.08, 0.14, 0.98)
	return Color(0.11, 0.09, 0.08, 0.96)

func _get_slot_color(slot_type: String) -> Color:
	match slot_type:
		"weapon":
			return Color(0.92, 0.48, 0.32)
		"shield":
			return Color(0.50, 0.72, 0.95)
		"armor":
			return Color(0.78, 0.73, 0.66)
		"engine", "reactor", "battery":
			return Color(0.84, 0.79, 0.43)
		"ammo":
			return Color(0.88, 0.60, 0.34)
		"consumable":
			return Color(0.74, 0.74, 0.86)
		_:
			return Color(0.65, 0.58, 0.47)

func _get_gem_color(gem_name: String) -> Color:
	if "Crimson" in gem_name: return Color("#ff4444")
	if "Cobalt" in gem_name: return Color("#44ccff")
	if "Topaz" in gem_name: return Color("#FFC24D")
	if "Amethyst" in gem_name: return Color("#aa44ff")
	return Color("#b548b5") # Default purple

func _apply_pulse(rarity: int):
	_stop_pulse()
	if not is_inside_tree():
		return   # pulse tweens require in-tree; restart on the next in-tree _update_ui
	# v134g: coach equip-target glow takes priority over the rarity shimmer — a
	# faster, brighter cyan pulse that reads as "grab THIS one" (mirrors the slot
	# pulse the mission drives on the designer side).
	if coach_pulse:
		pulse_tween = create_tween().set_loops()
		pulse_tween.tween_property(self, "modulate", Color(1.35, 1.55, 1.75), 0.5).set_trans(Tween.TRANS_SINE)
		pulse_tween.tween_property(self, "modulate", Color.WHITE, 0.5).set_trans(Tween.TRANS_SINE)
		return
	var sm = GameState.shipyard_manager
	if not sm:
		return
	if rarity == sm.Rarity.LEGENDARY:
		pulse_tween = create_tween().set_loops()
		pulse_tween.tween_property(self, "modulate", Color(1.08, 1.03, 0.94), 0.9).set_trans(Tween.TRANS_SINE)
		pulse_tween.tween_property(self, "modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
	elif rarity == sm.Rarity.UNIQUE:
		pulse_tween = create_tween().set_loops()
		pulse_tween.tween_property(self, "modulate", Color(1.10, 0.97, 1.08), 0.9).set_trans(Tween.TRANS_SINE)
		pulse_tween.tween_property(self, "modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)

func _stop_pulse():
	if pulse_tween and is_instance_valid(pulse_tween):
		pulse_tween.kill()
	pulse_tween = null
	modulate = Color.WHITE

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_show_demolish_menu()
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			# v136: Shift-click pins/unpins this module as the compare baseline. A plain
			# click still arms the module for click-to-equip (kept intact for touch /
			# no-drag play), so the two gestures never collide.
			if event.shift_pressed:
				pin_toggled.emit(mid)
			else:
				clicked.emit(mid)

func _show_demolish_menu():
	var sm = GameState.shipyard_manager
	if not sm or mid not in sm.modules:
		return

	var in_storage = sm.module_inventory.get(mid, 0)
	if in_storage <= 0:
		UITheme.show_notification(tr("Cannot recycle an equipped module"), Color.RED)
		return

	var price = sm.get_sell_price(mid)
	var parts = sm.get_demolish_parts(mid)
	
	# v124: themed confirm modal (UITheme.show_confirm) instead of the raw Godot
	# PopupMenu — chrome-framed, shows the salvage refund, red "destructive" accent.
	# Centered, so it no longer needs the old get_global_mouse_position crash-guard.
	var mname: String = str(sm.modules.get(mid, {}).get("name", mid)).to_upper()
	var rarity = sm.get_module_rarity(mid)
	var rarity_color: Color = sm.RARITY_COLORS.get(rarity, Color.WHITE)

	var warn_hex: String = UITheme.COLORS["warning"].to_html(false)
	var pos_hex: String = UITheme.COLORS["positive"].to_html(false)
	var dim_hex: String = UITheme.COLORS["text_dim"].to_html(false)

	var body := tr("[center]Recycle [b]%s[/b] for parts?\n\n") % mname
	body += tr("[color=#%s]YOU RECEIVE[/color]\n") % dim_hex
	body += tr("[b][color=#%s]%s[/color][/b] %s      [b][color=#%s]%s[/color][/b] Spare Parts\n\n") % [warn_hex, UITheme.format_num(price), UITheme.LIRA_ICON_BB, pos_hex, str(parts)]
	body += tr("[color=#%s]This permanently destroys the module.[/color][/center]") % dim_hex

	var on_ok := func():
		if sm.demolish_module(mid):
			UITheme.show_notification(tr("Recycled for %s Liras & %s parts") % [UITheme.format_num(price), parts], rarity_color)

	UITheme.show_confirm({
		"title": tr("Recycle Module"),
		"body": body,
		"confirm_text": tr("Recycle"),
		"cancel_text": tr("Cancel"),
		"accent": UITheme.COLORS["negative"],
		"danger": true,
		"on_confirm": on_ok,
	})


# v137: true when this exact module instance is fitted to a ship slot (loadout is
# {slot_idx: module_id}). Used to badge the card in a side-by-side compare, where the
# equipped item and an armory item otherwise look identical.
func _is_equipped(sm, module_id: String) -> bool:
	if not sm or module_id == "":
		return false
	var lo = sm.get("loadout")
	if lo == null:
		return false
	return module_id in lo.values()

func _build_comparison_tooltip_bbcode(anchor_select: bool = false, hover_affix: String = "", no_compare: bool = false) -> String:
	if data.is_empty():
		return ""

	var sm = GameState.shipyard_manager
	var slot_type = data.get("slot_type", "module")
	var rarity = _get_module_rarity_safe(sm)
	var rarity_label = _get_rarity_label_safe(sm, rarity)
	if rarity_label == "":
		rarity_label = "Common"
	var rarity_color_hex = _get_rarity_color_safe(sm, rarity).to_html(false)
	var display_name = _get_clean_name(data.get("name", "Item")).to_upper()

	var tt = ""
	var div = "[color=#1E3B38]──────────────────────────────[/color]\n"

	tt += "[font_size=16][b][color=#%s]%s[/color][/b][/font_size]\n" % [rarity_color_hex, display_name]

	# v127: Hack Stones are crafting currency — show what the stone DOES; the module
	# boilerplate (rarity / durability / stats) is meaningless for them.
	if slot_type == "hack_stone":
		tt += "[font_size=10][color=#7FA39C]HACK CARD · Module Crafting[/color][/font_size]\n"
		tt += div
		var eff: String = "Applies a crafting effect to a module."
		if sm:
			eff = str(sm.HACK_STONE_DESC.get(mid, eff))
		tt += "[font_size=12][color=#CBD5D0]%s[/color][/font_size]\n" % eff
		tt += "\n[font_size=9][color=#7FA39C]Click to arm, then click a module to apply.[/color][/font_size]"
		return tt

	# v137: flag the module currently fitted to the ship — essential in a side-by-side
	# compare, where the equipped card and an armory card are otherwise indistinguishable.
	var eq_tag := ""
	if _is_equipped(sm, mid):
		eq_tag = "  [color=#4DD8C0][b](EQUIPPED)[/b][/color]"
	tt += "[font_size=10][color=#7FA39C]%s %s[/color]%s[/font_size]\n" % [tr(rarity_label), tr(slot_type.capitalize()), eq_tag]

	var durability = int(data.get("durability", 100))
	var dur_col = "#46E0A0"
	if durability <= 25: dur_col = "#FF6473"
	elif durability <= 50: dur_col = "#FFC24D"
	elif durability <= 75: dur_col = "#D7B842"
	tt += "[font_size=10][color=#7FA39C]%s[/color] [color=%s]%d/100[/color][/font_size]\n" % [tr("Durability:"), dur_col, durability]
		
	tt += div

	var my_stats = data.get("stats", {})
	if slot_type == "weapon":
		var dmg = my_stats.get("atk_kinetic", 0) + my_stats.get("atk_energy", 0) + my_stats.get("atk_explosive", 0) + my_stats.get("atk_cryo", 0)
		var interval = max(0.01, float(my_stats.get("atk_interval", 2.5)))
		var dps = float(dmg) / interval
		tt += "[font_size=24][b]%.1f DPS[/b][/font_size]\n" % dps
		tt += "[font_size=9][color=#7FA39C]" + (tr("%s total damage, %.2f hits/s") % [UITheme.format_num(dmg), 1.0 / interval]) + "[/color][/font_size]\n"

		# v87.0: Damage Type Strong/Weak (Rich BBCode)
		if my_stats.get("atk_kinetic", 0) > 0:
			tt += "[img=15 color=#7088F2]res://assets/icons/modules/weapon_kinetic.svg[/img] [color=#7088F2][b]" + tr("KINETIC") + "[/b][/color]\n"
			tt += "[img=11 color=#46E0A0]res://assets/icons/ui/chevron_up.svg[/img] [color=#46E0A0]" + tr("Strong: Hull (+20%)") + "[/color]\n"
			tt += "[img=11 color=#FF6473]res://assets/icons/ui/chevron_down.svg[/img] [color=#FF6473]" + tr("Weak: Shield (-50%)") + "[/color]\n"
		if my_stats.get("atk_energy", 0) > 0:
			tt += "[img=15 color=#5FE0C8]res://assets/icons/modules/weapon_energy.svg[/img] [color=#5FE0C8][b]" + tr("ENERGY") + "[/b][/color]\n"
			tt += "[img=11 color=#46E0A0]res://assets/icons/ui/chevron_up.svg[/img] [color=#46E0A0]" + tr("Strong: Shield (+50%), Armor Bypass") + "[/color]\n"
			tt += "[img=11 color=#FF6473]res://assets/icons/ui/chevron_down.svg[/img] [color=#FF6473]" + tr("Weak: Hull (-10%)") + "[/color]\n"
		if my_stats.get("atk_explosive", 0) > 0:
			tt += "[img=15 color=#FFC24D]res://assets/icons/modules/weapon_explosive.svg[/img] [color=#FFC24D][b]" + tr("EXPLOSIVE") + "[/b][/color]\n"
			tt += "[img=11 color=#46E0A0]res://assets/icons/ui/chevron_up.svg[/img] [color=#46E0A0]" + tr("Strong: Armor Bypass (80% pen)") + "[/color]\n"
			tt += "[img=11 color=#FF6473]res://assets/icons/ui/chevron_down.svg[/img] [color=#FF6473]" + tr("Weak: Slower fire rate") + "[/color]\n"
		if my_stats.get("atk_cryo", 0) > 0:
			tt += "[img=15 color=#39A6E0]res://assets/icons/modules/weapon_cryo.svg[/img] [color=#39A6E0][b]" + tr("CRYOGENIC") + "[/b][/color]\n"
			tt += "[img=11 color=#46E0A0]res://assets/icons/ui/chevron_up.svg[/img] [color=#46E0A0]" + tr("Breaches Warp-Hardened hulls") + "[/color]\n"
			tt += "[img=11 color=#46E0A0]res://assets/icons/ui/chevron_up.svg[/img] [color=#46E0A0]" + tr("Self-charging — no ammo") + "[/color]\n"
			tt += "[img=11 color=#FF6473]res://assets/icons/ui/chevron_down.svg[/img] [color=#FF6473]" + tr("Weak: Conventional enemies resist") + "[/color]\n"

		tt += div
	elif slot_type == "ammo":
		tt += "[font_size=14][b]%s[/b][/font_size]\n" % _build_ammo_card_stats()
		tt += div
	elif slot_type == "consumable":
		var heal_pct = int(round(data.get("heal_pct", data.get("stats", {}).get("heal_pct", 0.0)) * 100.0))
		var target = data.get("consumable_type", "hull")
		tt += "[font_size=16][b]%s[/b][/font_size]\n" % (tr("Restores %d%% %s") % [heal_pct, tr(target.capitalize())])
		tt += div
	elif slot_type == "shield":
		var val = my_stats.get("max_shield", 0)
		tt += "[font_size=24][b]%s[/b][/font_size] [font_size=10][color=#7FA39C]%s[/color][/font_size]\n" % [UITheme.format_num(val), tr("Shield Capacity")]
		tt += div
	elif slot_type == "armor":
		var val = my_stats.get("hp", 0)
		tt += "[font_size=24][b]%s[/b][/font_size] [font_size=10][color=#7FA39C]%s[/color][/font_size]\n" % [UITheme.format_num(val), tr("Integrity Reinforcement")]
		tt += div
	elif slot_type == "gem":
		var gem_desc = data.get("desc", ElementDB.get_element_description(mid))
		tt += "[font_size=14][b]%s[/b][/font_size]\n" % gem_desc
		# Per-slot-type breakdown (mirrors the equipped-socket inspect card) so the
		# armory hover shows what the core gives in each host type, not just flavour.
		if sm:
			var _cat_slot = {"Weapon": "weapon", "Armor/Shield": "armor", "Engine/Sensor": "engine"}
			for _cl in ["Weapon", "Armor/Shield", "Engine/Sensor"]:
				var _ft: String = sm.get_gem_facet_text(mid, _cat_slot[_cl])
				if _ft != "":
					tt += "[color=#7FA39C][lb]%s][/color]  [color=#46E0A0]%s[/color]\n" % [_cl, _ft]
		tt += div

	# v110: power is tier-DERIVED now (not the stale energy_load stat). Show the
	# real draw for consumers / real supply for batteries.
	if sm:
		if slot_type in ["weapon", "shield", "armor", "engine", "sensor"]:
			var draw = sm.get_module_energy_load(mid)
			if draw > 0:
				tt += "[color=#FFC24D]%s[/color]\n" % (tr("POWER DRAW: %d") % draw)
				tt += div
		elif slot_type == "battery":
			var supply = sm.get_module_energy_capacity(mid)
			if supply > 0:
				tt += "[color=#46E0A0]%s[/color]\n" % (tr("POWER SUPPLY: +%d") % supply)
				tt += div

	var equipped_mid = ""
	var equipped_stats = {}
	# v136: no_compare (the pinned baseline card in a side-by-side compare) shows its
	# OWN stats with no delta column — skip the equipped-vs lookup entirely.
	if not no_compare:
		if compare_equipped_mid != "" and sm and compare_equipped_mid in sm.modules:
			equipped_mid = compare_equipped_mid
			equipped_stats = sm.modules[compare_equipped_mid].get("stats", {})
		elif sm and slot_type in ["weapon", "shield", "armor", "engine", "battery", "reactor", "sensor", "cooling"]:
			for idx in sm.loadout:
				var equipped = sm.loadout[idx]
				if equipped and equipped in sm.modules:
					var equipped_data = sm.modules[equipped]
					if equipped_data.get("slot_type", "") == slot_type:
						equipped_mid = equipped
						equipped_stats = equipped_data.get("stats", {})
						break

	var keys = my_stats.keys()
	keys.sort()
	for key in keys:
		if key == "atk_interval":
			continue
		var val = my_stats[key]
		# v110: energy is shown via the derived POWER DRAW/SUPPLY line above;
		# suppress the stale per-module energy stats here.
		if key == "energy_load" or key == "energy_capacity":
			continue
		if slot_type == "weapon" and key in ["atk_kinetic", "atk_energy", "atk_explosive", "atk_cryo"]:
			continue
		if slot_type == "shield" and key == "max_shield":
			continue
		if slot_type == "armor" and key == "hp":
			continue

		var label = FormatUtils.format_stat_label(key)
		var val_str = FormatUtils.format_stat_value(key, val)
		
		# v76.0: Display Roll Range for base stats
		var range_info = ""
		var base_id = data.get("base_module", "")
		if base_id != "" and base_id in sm.modules and key in sm.BOOSTABLE_STATS:
			var base_val = sm.modules[base_id].get("stats", {}).get(key, 0)
			if base_val > 0:
				var s_range = sm.RARITY_STAT_RANGE.get(rarity, [0, 0])
				if s_range[1] > 0:
					var zone_mult = 1.0
					if key in sm.ZONE_SCALABLE_STATS and data.has("zone_difficulty"):
						zone_mult = sm.get_module_zone_multiplier(int(data.get("zone_difficulty", 1)))
					var scaled_base = base_val * zone_mult
					var r_min = scaled_base * (1.0 + s_range[0])
					var r_max = scaled_base * (1.0 + s_range[1])
					range_info = " [color=#7FA39C][font_size=9][%s-%s][/font_size][/color]" % [
						FormatUtils.format_stat_value(key, r_min),
						FormatUtils.format_stat_value(key, r_max)
					]

		var line = "%s: %s%s" % [label, val_str, range_info]
		# v135a: only diff stats present on BOTH items — an affix-only stat (on the
		# hovered item but not equipped) would otherwise show a false +full-value.
		if equipped_mid != "" and equipped_mid != mid and key != "energy_load" and equipped_stats.has(key):
			var diff = val - equipped_stats.get(key, 0)
			if diff > 0:
				line += " [color=#46E0A0](+%s)[/color]" % FormatUtils.format_stat_value(key, diff)
			elif diff < 0:
				line += " [color=#FF6473](%s)[/color]" % FormatUtils.format_stat_value(key, diff)
		tt += "%s\n" % line

	var affixes = data.get("affixes", {})
	var ga_list = data.get("greater_affixes", [])
	
	if sm and affixes.size() > 0:
		tt += div
		if anchor_select:
			tt += "[font_size=11][color=#5FE0C8][b]ANCHOR BOLT[/b] — click an affix to lock it:[/color][/font_size]\n"
		var zone_difficulty = int(data.get("zone_difficulty", 1))
		for aid in affixes:
			if aid in sm.AFFIX_DB:
				var cfg = sm.AFFIX_DB[aid]
				var val_raw = affixes[aid]
				var scaling = cfg.get("scaling", "percent")
				var is_ga = aid in ga_list
				
				# v80.1 Fix: Use scaled ranges for display
				var s_range = sm.get_affix_scaled_range(aid, zone_difficulty)
				var val_str = ""
				var range_str = ""
				
				if scaling == "flat" or scaling == "linear_tier":
					val_str = str(int(val_raw))
					range_str = " [color=#7FA39C][font_size=9][%d-%d][/font_size][/color]" % [int(s_range[0]), int(s_range[1])]
				else:
					val_str = "%d%%" % int(val_raw * 100)
					range_str = " [color=#7FA39C][font_size=9][%d-%d]%%[/font_size][/color]" % [int(s_range[0] * 100), int(s_range[1] * 100)]
				
				var desc_val = 0
				if scaling == "flat" or scaling == "linear_tier":
					desc_val = int(val_raw)
				else:
					desc_val = int(val_raw * 100)

				var desc = tr(cfg["desc"]) % desc_val
				# v137: wrap jargon in glossary [url]s for the sticky hover — but NOT in
				# anchor-select mode, where the whole row is already a [url=affix:*] (no nesting).
				if not anchor_select:
					desc = UITheme.linkify_glossary(desc)

				var affix_body := ""
				if is_ga:
					affix_body = "[img=13 color=#FFC24D]res://assets/icons/ui/affix_greater.svg[/img] [color=#FFC24D][b]%s[/b][/color]  [color=#FFD98A][font_size=9]%s[/font_size][/color]" % [desc, tr("GREATER")]
				else:
					affix_body = "[img=11 color=#5FE0C8]res://assets/icons/ui/affix_node.svg[/img] [color=#5FE0C8]%s[/color]" % desc
				if anchor_select:
					# Clickable to lock; a lock icon marks the already-anchored affix;
					# the hovered affix gets a background highlight (no underline).
					var lock_bb := ""
					# v128: 2-lock support — check the array field + the legacy single field.
					var _anch_list: Array = data.get("anchored_affixes", [])
					if str(aid) == str(data.get("anchored_affix", "")) or (str(aid) in _anch_list):
						lock_bb = "[img=12 color=#FFD14C]res://assets/icons/ui/lock.svg[/img] "
					var shown := affix_body
					if hover_affix != "" and str(aid) == hover_affix:
						shown = "[bgcolor=#2E6E64]%s[/bgcolor]" % affix_body
					tt += "%s[url=affix:%s]%s[/url]\n" % [lock_bb, str(aid), shown]
				else:
					tt += "%s\n" % affix_body

	if data.has("sockets"):
		tt += div
		for gem in data["sockets"]:
			if gem:
				var g_name = ElementDB.get_display_name(gem)
				# Show the bonus this core actually grants IN THIS module's slot type
				# (its slot-matched facet) — not the generic "socket into…" flavour.
				var g_desc = sm.get_gem_facet_text(gem, slot_type) if sm else ""
				if g_desc == "":
					g_desc = ElementDB.get_element_description(gem)
				var g_hex = _get_gem_color(g_name).to_html(false)
				if g_desc != "":
					tt += "[color=#%s]%s: %s[/color]\n" % [g_hex, g_name, g_desc]
				else:
					tt += "[color=#%s]%s[/color]\n" % [g_hex, g_name]
			else:
				tt += "[img=11 color=#7FA39C]res://assets/icons/ui/socket_empty.svg[/img] [color=#7FA39C]%s[/color]\n" % tr("Empty Socket")

	# Provenance: the sector this module dropped from (zone emblem + sector number).
	var prov_zone := int(data.get("zone", data.get("zone_difficulty", 0)))
	if prov_zone >= 1:
		tt += div
		var prov_bb := ElementDB.material_icon_bbcode("Z%d_Core" % clampi(prov_zone, 1, 10), 14)
		var prov_name := "Sector %d" % prov_zone
		if GameState.combat_manager:
			prov_name = GameState.combat_manager.get_zone_name(prov_zone)
		tt += "[font_size=10][color=#9fb3a8]%s%s[/color][/font_size]\n" % [prov_bb, prov_name.to_upper()]

	if sm and mid in sm.modules:
		tt += div
		tt += "[font_size=10][color=#7FA39C]Sell Value:[/color] [color=#D7B842]%s %s[/color][/font_size]" % [UITheme.format_num(sm.get_sell_price(mid)), UITheme.LIRA_ICON_BB]

	# v83.9: Set Bonus Tooltip Section
	var sid = data.get("set_id", "")
	if sid == "" and data.get("is_custom") and data.has("base_module"):
		var base_id = data["base_module"]
		sid = sm.modules.get(base_id, {}).get("set_id", "")
	if sid != "" and GameState.combat_manager and "TRINITY_SET_BONUSES" in GameState.combat_manager:
		var s_db = GameState.combat_manager.TRINITY_SET_BONUSES
		if s_db.has(sid):
			tt += div
			var set_info = s_db[sid]
			var count = GameState.combat_manager.get_set_piece_count(sid)
			var total = set_info["pieces"]
			var active = count >= total
			
			tt += "[b][color=#7088F2]%s[/color][/b]\n" % (tr("SET: %s") % UITheme.tr_upper(tr(set_info["name"])))
			tt += "[font_size=10][color=#7FA39C]%s[/color][/font_size]\n" % (tr("%d / %d pieces equipped") % [count, total])
			
			for bonus_key in set_info["bonus"]:
				var val = set_info["bonus"][bonus_key]
				var b_name = bonus_key.replace("_pct", "").replace("_flat", "").replace("_", " ").to_upper()
				var val_str = "+%d%%" % val if ("_pct" in bonus_key or "crit" in bonus_key) else "+%d" % val
				
				var col = "#ffffff" if active else "#666666"
				tt += "[color=%s]%s: %s[/color]\n" % [col, b_name, val_str]

	# v136/v137: POE-style action-hint footer. Shift-click compares; right-click recycles.
	# The compare line is skipped on the pinned baseline card in side-by-side view and on
	# ammo/consumables/cores (not in sm.modules). The recycle line only shows when a copy is
	# in storage — the recycle action rejects equipped-only modules.
	var hint_lines: Array = []
	if not no_compare and sm and mid in sm.modules:
		if compare_pin_mid == mid:
			hint_lines.append("Shift-click: unpin  ·  Esc: clear compare")
		elif compare_pin_mid != "":
			hint_lines.append("Shift-click: pin this instead  ·  Esc: clear compare")
		else:
			hint_lines.append("Shift-click to pin & compare two modules")
	if sm and mid in sm.modules and sm.module_inventory.get(mid, 0) > 0:
		hint_lines.append("Right-click to recycle for parts")
	if not hint_lines.is_empty():
		tt += div
		var hint_txt := ""
		for i in range(hint_lines.size()):
			if i > 0: hint_txt += "\n"
			hint_txt += str(hint_lines[i])
		tt += "[font_size=9][color=#5E7C77]%s[/color][/font_size]" % hint_txt

	return tt

func _get_drag_data(_at_position: Vector2) -> Variant:
	if not is_draggable or data.is_empty() or mid == "":
		return null
	UITheme.hide_item_tooltip()   # clear the hover info card as the drag begins

	var slot_type = data.get("slot_type", "")
	var dtype = "module"
	if slot_type == "ammo":
		dtype = "ammo"
	elif slot_type == "consumable":
		dtype = "consumable"
	elif slot_type == "hack_stone":
		dtype = "hack_stone"   # v127: drag a stone onto a module to apply

	var drag_data = {
		"type": dtype,
		"mid": mid,
		"ammo_id": mid,
		"slot_type": slot_type,
		"consumable_type": data.get("consumable_type", ""),
	}

	# v112: LIGHTWEIGHT preview — a plain rarity-bordered name chip. The old
	# path re-instantiated the full module_card.tscn and ran setup()/_update_ui()
	# on a detached node; those detached-node calls were the drag crash source.
	# A scriptless Panel+Label has no _ready/_process/mouse calls to misfire.
	set_drag_preview(_make_drag_preview())
	return drag_data

# Builds the drag preview as a faithful, STATIC replica of the module's tile
# (socket plate + rarity frame + slot emblem + icon) — or the faceted crystal
# for Matrix Cores. Pure scriptless nodes with explicit sizes: no module_card
# re-instantiation, no _ready/_update_ui/tweens/mouse calls (the crash source).
# The colour/icon helpers are pure computation, so they're safe to call here.
func _make_drag_preview() -> Control:
	var sm = GameState.shipyard_manager
	var slot_type = data.get("slot_type", "module")
	var rarity = _get_module_rarity_safe(sm)
	var rarity_color = _get_rarity_color_safe(sm, rarity)

	var TS := 84.0
	# Root rides at the cursor; the tile is offset so the cursor sits at its
	# centre (matches the feel of "picking the tile up").
	var root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tile = Control.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.position = Vector2(-TS * 0.5, -TS * 0.5)
	tile.size = Vector2(TS, TS)
	tile.modulate.a = 0.95
	root.add_child(tile)

	# Socket backplate — identical recipe to the real tile / empty cell.
	var socket = Panel.new()
	socket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	socket.size = Vector2(TS, TS)
	var sock_sb = StyleBoxFlat.new()
	sock_sb.bg_color = Color(0.03, 0.045, 0.07, 0.92)
	sock_sb.set_corner_radius_all(5)
	sock_sb.set_border_width_all(1)
	sock_sb.border_color = Color(0.24, 0.36, 0.48, 0.85)
	sock_sb.shadow_color = Color(0, 0, 0, 0.55)
	sock_sb.shadow_size = 8
	socket.add_theme_stylebox_override("panel", sock_sb)
	tile.add_child(socket)

	# Matrix Cores draw a faceted crystal; everything else uses the tile look.
	if slot_type == "gem" or slot_type == "gem_synth":
		var core := MatrixCoreIcon.new()
		core.mouse_filter = Control.MOUSE_FILTER_IGNORE
		core.position = Vector2(5, 5)
		core.size = Vector2(TS - 10, TS - 10)
		core.set_core(_get_gem_color(str(data.get("name", ""))), false, MatrixCoreIcon.tier_from_name(mid))
		tile.add_child(core)
		return root

	var top_rarity: bool = sm != null and rarity >= sm.Rarity.LEGENDARY
	var slot_col = _get_slot_color(slot_type)
	if slot_type == "weapon":
		slot_col = _weapon_dmg_color(data.get("stats", {}))

	# Rarity plate seated inside the socket (rim shows around).
	var plate = Panel.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.position = Vector2(5, 5)
	plate.size = Vector2(TS - 10, TS - 10)
	var sb = StyleBoxFlat.new()
	sb.bg_color = _get_rarity_background(rarity)
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(3 if top_rarity else 2)
	sb.border_color = rarity_color
	sb.shadow_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.4)
	sb.shadow_size = 10
	plate.add_theme_stylebox_override("panel", sb)
	tile.add_child(plate)

	# Centre emblem chip + icon (or type-letter fallback).
	var em := TS * 0.5
	var emblem = Panel.new()
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem.position = Vector2((TS - em) * 0.5, (TS - em) * 0.5)
	emblem.size = Vector2(em, em)
	var esb = StyleBoxFlat.new()
	# Chip fill is near-neutral so RARITY (the frame) and SLOT (icon + chip rim)
	# read on separate channels — no more gold-chip-on-gold-frame confusion.
	esb.bg_color = slot_col.lerp(Color(0.05, 0.09, 0.10), 0.84)
	esb.set_corner_radius_all(5)
	esb.set_border_width_all(1)
	esb.border_color = slot_col.lerp(Color.WHITE, 0.1)
	emblem.add_theme_stylebox_override("panel", esb)
	tile.add_child(emblem)

	var icon_tex = _get_module_icon(slot_type, data.get("stats", {}), data)
	if icon_tex:
		var icon = TextureRect.new()
		icon.texture = icon_tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(5, 5)
		icon.size = Vector2(em - 10, em - 10)
		icon.modulate = slot_col.lerp(Color.WHITE, 0.85)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		emblem.add_child(icon)
	else:
		var letter = Label.new()
		letter.text = _get_type_char(slot_type)
		letter.add_theme_font_size_override("font_size", 22)
		letter.add_theme_color_override("font_color", slot_col.lerp(Color.WHITE, 0.75))
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.size = Vector2(em, em)
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		emblem.add_child(letter)

	return root

# v112: steady armory cards are NEVER drop targets. Only empty grid cells (the
# spatial canvas) and ship slots accept drops. Returning false here means a
# dragged card hovering/dropping over another card is a clean no-op — severing
# the dragged-item-vs-standing-item interaction that caused the crash.
func _can_drop_data(_at_position: Vector2, p_data: Variant) -> bool:
	# v127: accept a dragged Hack Stone onto a real MODULE (not another stone, ammo,
	# consumable, or matrix core — those aren't craftable). The backend still
	# validates (e.g. a raw Common needs a Splice Chip first) and toasts on refusal.
	if p_data is Dictionary and str(p_data.get("type", "")) == "hack_stone":
		var st := str(data.get("slot_type", ""))
		return mid != "" and not (st in ["hack_stone", "ammo", "consumable", "gem", "gem_synth"])
	return false

func _drop_data(_at_position: Vector2, p_data: Variant) -> void:
	if p_data is Dictionary and str(p_data.get("type", "")) == "hack_stone":
		stone_dropped.emit(str(p_data.get("mid", "")), mid)

# v111.7: hooked from _build_card_visual via resized.connect. Match min height to
# the cell WIDTH so every tile renders square — GROW for the 2x2 module cells
# (width > base min 64) AND SHRINK for the 1x1 ammo/consumable/gem cells (width <
# base min), which previously stayed taller-than-wide. The abs>0.5 guard means the
# next resized fire on the same width sees min.y == size.x and exits (no loop;
# setting min.y doesn't change size.x in the grid).
func _keep_square() -> void:
	if size.x > 0.0 and absf(custom_minimum_size.y - size.x) > 0.5:
		custom_minimum_size.y = size.x
		# We're a PanelContainer that sizes to its content, so the fixed-height
		# content node ("TileVisual", min height = TS) is what actually pins the
		# height. Square it too, or narrow 1x1 cells stay taller-than-wide.
		var tv := get_node_or_null("TileVisual")
		if tv:
			tv.custom_minimum_size.y = size.x
