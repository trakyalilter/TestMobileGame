extends PanelContainer

# v111.10: Targeting-Data datasheet redesign.
#
# Replaces the flat "Name / pipe-separated stats / CSV drops / mismatched
# buttons" layout with a structured datasheet that sells the encounter:
#
#   [ Enemy Name ............. T<N> ]   <- header + tier badge
#   ♥ HP   ⚔ ATK <TYPE>   ⛨ DEF       <- glanceable stat row
#   [⛨ KIN]  [▼ EXP]                  <- inline resist/weak chips
#   LOOT  drop1 ·drop2 · 4× T1 Module <- structured drop preview
#   +N XP  ·  +M ₺                    <- predicted yield (decision driver)
#   [ INFO ] [          ENGAGE     ] <- parallel actions, ENGAGE primary

var eid
var data
var parent_ui

@onready var vb: VBoxContainer = $MarginContainer/VBoxContainer


func setup(p_eid, p_data, p_parent):
	eid = p_eid
	data = p_data
	parent_ui = p_parent

	# v111.10.2: drop apply_card_style + inject_diegetic_header. Outer
	# Targeting Data panel already provides the framing — adding another
	# bordered card per row produced the nested-panels "double frame"
	# crowding the player called out. Cards now style as RECESSED ROWS
	# (subtle bg + bottom hairline) which read as list items, not cards.
	_apply_row_style()

	# The .tscn carries legacy NameLabel / StatsLabel / LootLabel / Actions
	# nodes. Clear them so the datasheet rebuilds with a clean slate; nothing
	# downstream references those node names anymore.
	for c in vb.get_children():
		c.queue_free()
	# Tighter VBox so rows pack closer.
	vb.add_theme_constant_override("separation", 3)

	_build_header()
	_build_combined_stats_row()    # stats + affinity merged onto one line
	_build_loot_inline()           # loot trimmed to a single line
	_build_yield_row()
	_build_actions_row()


# Row-style background: faint dark tint with a 1px combat-accent bottom
# hairline that doubles as the separator to the next card.
func _apply_row_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.078, 0.07, 0.55)
	sb.border_color = Color(1.0, 0.392, 0.451, 0.32)
	sb.border_width_bottom = 1
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	add_theme_stylebox_override("panel", sb)


# ─── Header: name + tier badge ───────────────────────────────────────
func _build_header() -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)

	var name_lbl := Label.new()
	name_lbl.text = str(data["name"])
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.894, 0.961, 0.933))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(name_lbl)

	# v111.10.3: T1/T2/T3 tier chip removed per design direction — engineer-
	# speak that the player doesn't speak. HP/ATK numbers + the section's
	# combat-red palette convey threat directly; explicit tier scaffolding
	# adds noise without information the player can act on.


# ─── Stats + affinity combined onto a single line ───────────────────
func _build_combined_stats_row() -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)

	var hp := int(data["stats"]["hp"])
	var atk := int(data["stats"]["atk"])
	var def := int(data["stats"]["def"])

	_add_stat_cell(hb, "hp", "♥", UITheme.format_num(hp), Color(1.0, 0.392, 0.451))

	var dmg_tag := "KIN"
	var dmg_col := Color(0.439, 0.533, 0.949)
	match data.get("dmg_type", "kinetic"):
		"energy":
			dmg_tag = "NRG"
			dmg_col = Color(0.373, 0.878, 0.784)
		"explosive":
			dmg_tag = "EXP"
			dmg_col = Color(1.0, 0.761, 0.302)
	_add_stat_cell(hb, "atk", "⚔", "%s %s" % [UITheme.format_num(atk), dmg_tag], dmg_col)

	_add_stat_cell(hb, "def", "⛨", str(def), Color(0.439, 0.533, 0.949))

	# Right-align affinity chips on the same row, separator dot in between.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)

	# v120: tier-hardening removed — the pre-fight "⚠ HARDENED" chip is gone (the soft
	# numeric gate has no binary hardened state). Warp-Hardened (Z11) chip below stays.

	# v111: Warp-Hardened (Z11+) nullify conventional damage; only Cryo bites.
	if data.get("warp_hardened", false):
		hb.add_child(_make_chip("❄CRYO-ONLY", Color(0.373, 0.878, 0.784), 8))

	for entry in [
		[float(data.get("resist_k", 0.0)), "KIN"],
		[float(data.get("resist_e", 0.0)), "NRG"],
		[float(data.get("resist_x", 0.0)), "EXP"],
		[float(data.get("resist_cryo", 0.0)), "CRY"],
	]:
		var val: float = entry[0]
		var tag: String = entry[1]
		if val > 0.05:
			hb.add_child(_make_chip("⛨%s" % tag, Color(1.0, 0.392, 0.451), 8))
		elif val < -0.05:
			hb.add_child(_make_chip("▼%s" % tag, Color(0.275, 0.878, 0.627), 8))


func _add_stat_cell(parent: Node, icon_key: String, fallback_glyph: String, value: String, accent: Color) -> void:
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", 4)
	parent.add_child(cell)

	# v115: custom SVG stat glyph — HP heart / ATK target-reticle (no more
	# melee crossed-swords in a ship-combat game) / DEF shield. White art tinted
	# per-stat via modulate. Falls back to the unicode glyph until the editor
	# reimports the new SVGs (load() returns null until then) — no broken state.
	var tex := _stat_icon(icon_key)
	if tex:
		var ir := TextureRect.new()
		ir.texture = tex
		ir.modulate = accent
		# EXPAND_IGNORE_SIZE: don't let the 64px source texture dictate the min
		# size (the default KEEP_SIZE made the icons render huge). Pin to 15px.
		ir.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ir.custom_minimum_size = Vector2(15, 15)
		ir.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ir.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ir.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(ir)
	else:
		var g := Label.new()
		g.text = fallback_glyph
		g.add_theme_font_size_override("font_size", 11)
		g.add_theme_color_override("font_color", accent)
		cell.add_child(g)

	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", 11)
	v.add_theme_color_override("font_color", Color(0.894, 0.961, 0.933))
	cell.add_child(v)


# Loads a stat glyph SVG, or null if it isn't imported yet (→ glyph fallback).
# ResourceLoader.exists guards against console error-spam pre-reimport.
func _stat_icon(key: String) -> Texture2D:
	var path := "res://assets/icons/glyphs/%s.svg" % key
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


# ─── Loot inline: single line with a small caption prefix ──────────
func _build_loot_inline() -> void:
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.scroll_active = false
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("normal_font_size", 10)
	lbl.add_theme_color_override("default_color", Color(0.78, 0.88, 0.85))

	# v111.10.3: drop the "×" multiplication sign — reads as a math operator
	# (Iron ×2-4 = "Iron times two minus four"?), not as a quantity. Plain
	# space is cleaner ("Iron 2–4"). Same notation as "+5 XP" in the yield
	# row below — no operator, just number-then-unit.
	var parts: Array = []
	for entry in data.get("loot", []):
		var item_id: String = str(entry[0])
		if item_id == "credits":
			continue        # surfaced in the yield row instead
		var display: String = ElementDB.get_display_name(item_id)
		var lo: int = int(entry[1])
		var hi: int = int(entry[2])
		parts.append("%s %d–%d" % [display, lo, hi] if lo != hi else "%s %d" % [display, lo])

	# v111.10.3: module pool surfaced as just "Module" — no count (was
	# misleading: pool of 4 != 4 drops per kill), no T1/T2/T3 (engineer
	# jargon), no zone name (the player already knows what zone they're in).
	# Honest signal: "this enemy can drop a module," nothing more.
	# v120: front-half (e1/e2) of Z2-Z10 drops materials ONLY — its def still carries a
	# module_drop_pool, but the loot roll is suppressed, so don't tease "Module" on the
	# card. Keyed to the browsed zone (current_zone isn't set yet). Always-on routing.
	var m_pool: Array = data.get("module_drop_pool", [])
	var _drops_modules: bool = m_pool.size() > 0
	if _drops_modules and parent_ui and parent_ui.manager:
		if parent_ui.manager.enemy_is_front_salvage(eid, str(parent_ui.last_refreshed_zone)):
			_drops_modules = false
	if _drops_modules:
		parts.append("Module")

	lbl.text = "[color=#9a7c52]LOOT[/color]  " + "  ·  ".join(parts) if not parts.is_empty() \
		else "[color=#9a7c52]LOOT[/color]  —"
	vb.add_child(lbl)


# ─── Yield row: predicted XP + Lira average ─────────────────────────
func _build_yield_row() -> void:
	var xp := int(data.get("xp", 0))
	var credit_min := 0
	var credit_max := 0
	for entry in data.get("loot", []):
		if str(entry[0]) == "credits":
			credit_min = int(entry[1])
			credit_max = int(entry[2])
			break

	var parts: Array = []
	if xp > 0:
		parts.append("+%d XP" % xp)
	if credit_max > 0:
		var avg: int = int((credit_min + credit_max) / 2.0)
		parts.append("+%d %s" % [avg, UITheme.LIRA_ICON_BB])

	if parts.is_empty():
		return

	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.scroll_active = false
	lbl.add_theme_font_size_override("normal_font_size", 10)
	lbl.add_theme_color_override("default_color", Color(0.275, 0.878, 0.627))
	lbl.text = "  ·  ".join(parts)
	vb.add_child(lbl)


# ─── Action row: parallel buttons, ENGAGE primary ───────────────────
func _build_actions_row() -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)

	var info_btn := Button.new()
	info_btn.text = "INFO"
	info_btn.custom_minimum_size = Vector2(50, 24)
	info_btn.add_theme_font_size_override("font_size", 10)
	info_btn.add_theme_color_override("font_color", Color(0.498, 0.639, 0.612))
	info_btn.flat = true
	info_btn.pressed.connect(_on_info_btn_pressed)
	hb.add_child(info_btn)

	var fight_btn := Button.new()
	fight_btn.text = "ENGAGE"
	fight_btn.custom_minimum_size = Vector2(0, 24)
	fight_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fight_btn.add_theme_font_size_override("font_size", 11)
	fight_btn.pressed.connect(_on_fight_btn_pressed)
	UITheme.apply_premium_button_style(fight_btn, "combat")
	hb.add_child(fight_btn)


# ─── Helpers ─────────────────────────────────────────────────────────
func _make_chip(text: String, color: Color, font_size: int) -> Control:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)

	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.bg_color.a = 0.15
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	var border := color
	border.a = 0.45
	sb.border_color = border
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1

	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", sb)
	chip.add_child(lbl)
	return chip


func _on_fight_btn_pressed():
	parent_ui.request_fight(eid)


func _on_info_btn_pressed():
	parent_ui.show_enemy_info(data)
