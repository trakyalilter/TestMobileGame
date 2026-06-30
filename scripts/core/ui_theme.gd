extends Node

signal packet_landed(color)
signal notification_requested(text: String, color: Color) # Feature v66.1
signal research_navigation_requested(tech_id: String)
# Emitted when the player switches card frame style in Sys Config so every
# live CardChrome overlay repaints without a page rebuild.
signal chrome_changed
# Emitted when the UI colour palette changes (Sys Config). The live re-theme is
# done by rebuilding the scene; this signal is for any future live listeners.
signal palette_changed
# Structured gain feed ("Cargo Manifest" popups) — distinct from the plain
# notification_requested toast. main.gd renders these as icon-chip + name +
# delta + dim total pills, coalescing repeats of the same key. See show_reward.
signal reward_requested(info: Dictionary)

# v111.19: animated rarity-frame shader, shared by armory tiles + equipped slots.
const RARITY_FRAME_SHADER = preload("res://assets/shaders/rarity_frame.gdshader")

# Card frame / "soul" chrome styles, selectable in Sys Config.
# Default is INDUSTRIAL (matches the diegetic engineering-console copy).
const CHROME_INDUSTRIAL := 0
const CHROME_HOLOGRAPHIC := 1
const CHROME_PRECURSOR := 2

func get_card_chrome() -> int:
	return int(GameState.game_settings.get("card_chrome", CHROME_INDUSTRIAL))

# Inline Lira currency icon for BBCode/RichText contexts ONLY (plain Labels
# and Buttons can't embed images — those use the word "Liras"). Single source
# of truth: tweak size/path/tint here. 14px ≈ inline body text height.
const LIRA_ICON_BB := "[img=14 color=#ffd14c]res://assets/icons/lira.svg[/img]"

func show_notification(text: Variant, color: Color = Color.WHITE):
	notification_requested.emit(text, color)

# Fire a "Cargo Manifest" gain popup. `info` keys:
#   kind        "loot" | "xp"
#   key         coalesce key (same key ticks up instead of stacking)
#   symbol      element symbol for the chip (loot)
#   name        display name / label line ("Iron", "Gathering XP")
#   amount      numeric delta (drives coalescing accumulation + the +N readout)
#   total_text  pre-formatted dim secondary ("115", "Lvl 12")
#   accent      base accent Color
#   hot         optional bool — crit/jackpot punch (brighter flash)
#   tag         optional String — "CRIT" / "JACKPOT" suffix on the name line
func show_reward(info: Dictionary) -> void:
	reward_requested.emit(info)

# XP gain events arrive pre-formatted as "+N XP"; recover the integer for the
# manifest delta / coalescing. Tolerates a raw number too.
func parse_xp_amount(data) -> int:
	if data is int or data is float:
		return int(data)
	var s := str(data).replace("+", "").replace("XP", "").strip_edges()
	return int(s) if s.is_valid_int() else 0

# Accent hue for an element/material by ElementDB category, so the manifest
# popup (and any future per-element tint) reads by colour at a glance:
# metals steel-blue, ores bronze, components cyan, ammo orange, exotics purple,
# everything else the loot green. Currency = lira gold.
func element_accent(symbol: String) -> Color:
	if symbol == "credits":
		return Color(1.0, 0.82, 0.30)
	match ElementDB.get_category(symbol):
		"ores": return Color(0.80, 0.64, 0.42)
		"basic_metals": return Color(0.56, 0.72, 0.90)
		"advanced_metals": return Color(0.40, 0.85, 0.95)
		"rare_metals": return Color(0.95, 0.82, 0.48)
		"alloys": return Color(0.74, 0.80, 0.88)
		"components": return Color(0.35, 0.80, 1.0)
		"batteries": return Color(0.85, 0.95, 0.38)
		"ammo": return Color(1.0, 0.62, 0.28)
		"special", "endgame", "boss_cores": return Color(0.78, 0.55, 1.0)
		"matrix_cores": return Color(0.95, 0.48, 0.58)
		_: return Color(0.40, 0.90, 0.60)

func format_number(value: float) -> String:
	if not is_finite(value): return "!!!" 
	if value <= 0: return "0"
	
	if value < 1000:
		return str(int(value))
	elif value < 1000000:
		return "%.1fK" % (value / 1000.0)
	elif value < 1000000000:
		return "%.1fM" % (value / 1000000.0)
	elif value < 1000000000000:
		return "%.1fB" % (value / 1000000000.0)
	else:
		return "%.1fT" % (value / 1000000000000.0)

# Color Palette
# Palette: "Precursor Bloom" — abyssal teal-black backgrounds with bioluminescent
# accents. ONE blue-green undertone unifies the whole UI (even the backgrounds are
# teal-shifted, never navy); accents are luminous but held in a disciplined chroma
# band so the set reads as one curated light source, not eight crayon primaries.
# v123: runtime palette (was const). apply_palette() rewrites these in place when
# the player picks a UI palette in Sys Config; every UITheme.COLORS[...] read is
# unaffected. The literal below is the "Default" (Precursor Bloom) palette.
var COLORS := {
	"background": Color(0.039, 0.086, 0.078),   # #0A1614 abyssal teal-black
	"sidebar": Color(0.055, 0.122, 0.114),      # #0E1F1D
	"panel_bg": Color(0.078, 0.169, 0.161),     # #142B29
	"accent": Color(0.216, 0.788, 0.690),       # #37C9B0 teal
	"accent_bright": Color(0.427, 0.941, 0.847),# #6DF0D8 aqua glow
	"text_main": Color(0.894, 0.961, 0.933),    # #E4F5EE
	"text_dim": Color(0.498, 0.639, 0.612),     # #7FA39C
	"text_accent": Color(0.373, 0.878, 0.784),  # #5FE0C8
	"positive": Color(0.275, 0.878, 0.627),     # #46E0A0 jade
	"negative": Color(1.0, 0.392, 0.451),       # #FF6473 coral (the one heat pop)
	"warning": Color(1.0, 0.761, 0.302)         # #FFC24D amber
}

var CATEGORY_COLORS := {
	"ops": Color(0.180, 0.910, 0.769),          # #2EE8C4 aqua
	"engineering": Color(0.224, 0.651, 0.878),  # #39A6E0 sky-cyan
	"infrastructure": Color(0.455, 0.831, 0.373),# #74D45F leaf-green
	"combat": Color(1.0, 0.392, 0.451),         # #FF6473 coral
	"inventory": Color(0.843, 0.722, 0.259),    # #D7B842 amber-gold
	"research": Color(0.690, 0.420, 0.949),     # #B06BF2 violet
	"shipyard": Color(0.439, 0.533, 0.949),     # #7088F2 periwinkle-indigo
	"mission": Color(0.075, 0.627, 0.455)       # #13A074 deep jade
}

# v123: selectable sci-fi UI palettes (Sys Config). Each fills the same token
# set as COLORS + CATEGORY_COLORS above. "default" == the current Precursor Bloom.
# Order here drives the picker order. Hex strings → parsed via Color.html().
const UI_PALETTES := {
	"default": { "name": "Default (Bloom)",
		"colors": {"background":"#0A1614","sidebar":"#0E1F1D","panel_bg":"#142B29","accent":"#37C9B0","accent_bright":"#6DF0D8","text_main":"#E4F5EE","text_dim":"#7FA39C","text_accent":"#5FE0C8","positive":"#46E0A0","negative":"#FF6473","warning":"#FFC24D"},
		"category": {"ops":"#2EE8C4","engineering":"#39A6E0","infrastructure":"#74D45F","combat":"#FF6473","inventory":"#D7B842","research":"#B06BF2","shipyard":"#7088F2","mission":"#13A074"} },
	"phosphor": { "name": "Phosphor Terminal",
		"colors": {"background":"#070b07","sidebar":"#0c130c","panel_bg":"#111a12","accent":"#33ff66","accent_bright":"#5cff8c","text_main":"#d6f5d8","text_dim":"#7fa888","text_accent":"#5cff8c","positive":"#33ff66","negative":"#ff5c47","warning":"#ffb347"},
		"category": {"ops":"#ffb347","engineering":"#3BF0D6","infrastructure":"#5cff8c","combat":"#ff5c47","inventory":"#ffd24c","research":"#e065ff","shipyard":"#52c2ff","mission":"#33ffb0"} },
	"derelict": { "name": "Derelict Salvage",
		"colors": {"background":"#15100C","sidebar":"#1C160F","panel_bg":"#241B13","accent":"#D97A2B","accent_bright":"#FF9D42","text_main":"#F0E3D2","text_dim":"#A08B72","text_accent":"#FFB866","positive":"#8FB54A","negative":"#D9512E","warning":"#E8A627"},
		"category": {"ops":"#E08A2E","engineering":"#3FA89A","infrastructure":"#7AA83F","combat":"#F0613F","inventory":"#E0B341","research":"#C07FE8","shipyard":"#C97F3A","mission":"#3FB88A"} },
	"precursor": { "name": "Precursor Crystalline",
		"colors": {"background":"#0c0a18","sidebar":"#120e22","panel_bg":"#1a1530","accent":"#2fe0d4","accent_bright":"#62f6ec","text_main":"#ece7ff","text_dim":"#9c95c6","text_accent":"#46ecff","positive":"#3fe0a3","negative":"#ff5f6e","warning":"#ffcf5c"},
		"category": {"ops":"#ffae57","engineering":"#46d7ff","infrastructure":"#5fe0a0","combat":"#ff5a68","inventory":"#ffd166","research":"#c66bff","shipyard":"#6c8cff","mission":"#34f0c4"} },
	"aurora": { "name": "Aurora Deep-Space",
		"colors": {"background":"#0A1320","sidebar":"#0E1A2B","panel_bg":"#152233","accent":"#3DD68C","accent_bright":"#7CF0B8","text_main":"#E9F2FF","text_dim":"#8FA6C4","text_accent":"#5FF0C0","positive":"#48E0A0","negative":"#FF6E7A","warning":"#FFC861"},
		"category": {"ops":"#46E0C2","engineering":"#4FB6E8","infrastructure":"#5FD982","combat":"#FF6E7A","inventory":"#F2C45A","research":"#B27AF0","shipyard":"#6E92F0","mission":"#3FE0A6"} },
	"bridge": { "name": "Cold Tactical Bridge",
		"colors": {"background":"#0A0F1A","sidebar":"#101725","panel_bg":"#172234","accent":"#3D7FE0","accent_bright":"#5FC4FF","text_main":"#E8F0FB","text_dim":"#8A9BB8","text_accent":"#8FD8FF","positive":"#46D98A","negative":"#FF5E63","warning":"#FFC24D"},
		"category": {"ops":"#5FB0E8","engineering":"#3FD0E0","infrastructure":"#52C98E","combat":"#FF5E63","inventory":"#E8B84A","research":"#B589F2","shipyard":"#7AA0FF","mission":"#36D6B0"} },
	"neon": { "name": "Neon Cyber-Deck",
		"colors": {"background":"#05050a","sidebar":"#0c0a16","panel_bg":"#14101f","accent":"#ff2fe6","accent_bright":"#ff5cf2","text_main":"#eef0ff","text_dim":"#948cbd","text_accent":"#26f5ff","positive":"#3dffae","negative":"#ff3366","warning":"#ffd23d"},
		"category": {"ops":"#ff8a3d","engineering":"#36d8ff","infrastructure":"#34f5a0","combat":"#ff476f","inventory":"#ffc94d","research":"#cf57ff","shipyard":"#5f8cff","mission":"#2af0cf"} },
}

const PALETTE_ORDER := ["default", "phosphor", "derelict", "precursor", "aurora", "bridge", "neon"]

func get_ui_palette() -> String:
	if GameState and GameState.game_settings != null:
		return str(GameState.game_settings.get("ui_palette", "default"))
	return "default"

# Rewrite COLORS + CATEGORY_COLORS in place from the chosen palette. The live
# re-theme of already-built UI is done by the caller via a scene reload (every
# stylebox is rebuilt against the new tokens); at boot this runs before pages
# build, so they pick up the palette directly.
func apply_palette(id: String) -> void:
	var p = UI_PALETTES.get(id)
	if p == null:
		id = "default"
		p = UI_PALETTES["default"]
	var c: Dictionary = p["colors"]
	for k in c:
		COLORS[k] = Color.html(c[k])
	var cat: Dictionary = p["category"]
	for k in cat:
		CATEGORY_COLORS[k] = Color.html(cat[k])
	if GameState and GameState.game_settings != null:
		GameState.game_settings["ui_palette"] = id
	palette_changed.emit()

func setup_page_background(page: Control):
	pass

func apply_card_style(panel: Control, category: String = "ops") -> StyleBoxFlat:
	if not panel: return null
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	var style = StyleBoxFlat.new()
	# Solid console panel, faintly accent-tinted (reads less "translucent
	# overlay", more "physical module" — matches the recessed bar track).
	style.bg_color = COLORS["panel_bg"].lerp(accent, 0.06)
	style.bg_color.a = 0.96
	style.draw_center = true

	# Faint uniform 1px hairline only. The CardChrome overlay now owns the
	# lit-edge / frame motif, so a thicker StyleBox top border just stacks
	# behind it and reads as one over-thick accent band.
	style.set_border_width_all(1)
	var border_col: Color = accent
	border_col.a = 0.22
	style.border_color = border_col
	style.border_blend = false

	# Square corners: the CardChrome overlay (always on) draws sharp corner
	# hardware / a chamfered octagon / etched frames — a rounded StyleBox
	# corner would poke out behind those and read as a defect.
	style.set_corner_radius_all(0)

	# Depth shadow so cards separate cleanly in the grid.
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 3)

	panel.add_theme_stylebox_override("panel", style)

	# Procedural "soul" chrome layer (corner hardware / holo frame / etched
	# filigree) painted over the flat StyleBox. One overlay per card, tinted
	# by the same accent — switches live with the Sys Config setting.
	_attach_chrome(panel, accent)
	return style

# v111.19: animated rarity-frame overlay (shimmer + orbiting highlight + soft
# twinkles) for rare+ cards. Shared by armory tiles (module_card) AND equipped
# slots (designer_slot_widget) so both shine identically. Idempotent: removes any
# prior overlay first, and a sub-RARE call simply clears it (use that to wipe the
# fx when a slot empties). Each tier glows in its own rarity colour — no rainbow.
func attach_rarity_fx(host: Control, rarity: int, rarity_color: Color) -> void:
	if not is_instance_valid(host):
		return
	var existing := host.get_node_or_null("RarityFX")
	if existing:
		host.remove_child(existing)   # detach now so re-add can't collide on name
		existing.queue_free()
	var sm = GameState.shipyard_manager
	var rare_tier: int = int(sm.Rarity.RARE) if sm else 2
	var legendary_tier: int = int(sm.Rarity.LEGENDARY) if sm else 3
	if rarity < rare_tier:
		return

	var fx := ColorRect.new()
	fx.name = "RarityFX"
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.color = Color.WHITE   # ignored; the shader writes COLOR directly

	var mat := ShaderMaterial.new()
	mat.shader = RARITY_FRAME_SHADER
	mat.set_shader_parameter("rarity_color", rarity_color)
	mat.set_shader_parameter("rainbow", 0.0)   # rarity-coloured, not a rainbow
	if rarity == rare_tier:
		mat.set_shader_parameter("intensity", 0.70)
		mat.set_shader_parameter("speed", 0.8)
		mat.set_shader_parameter("sparkle", 0.0)
		mat.set_shader_parameter("border", 0.12)
	elif rarity == legendary_tier:
		mat.set_shader_parameter("intensity", 1.0)
		mat.set_shader_parameter("speed", 1.25)
		mat.set_shader_parameter("sparkle", 1.0)
		mat.set_shader_parameter("border", 0.13)
	else:  # UNIQUE (and any higher tier)
		mat.set_shader_parameter("intensity", 1.25)
		mat.set_shader_parameter("speed", 1.6)
		mat.set_shader_parameter("sparkle", 1.0)
		mat.set_shader_parameter("border", 0.14)
	fx.material = mat

	# Feed the live pixel size so the border stays uniform on non-square cards.
	fx.resized.connect(func():
		if is_instance_valid(fx) and fx.size.x > 0.0 and fx.size.y > 0.0:
			mat.set_shader_parameter("rect_px", fx.size))
	host.add_child(fx)

# ── v111.20: shared rarity-framed item tooltip ─────────────────────────────
# A single hover tooltip shown via a manual ModalLayer popup (NOT Godot's generic
# cyan TooltipPanel), so the frame is rarity-coloured + shimmers like the cards.
# One global instance; anchor-tracked so a fast A->B hover never clears B's card
# when A's late mouse_exited fires.
var _item_tooltip: Control = null
var _item_tooltip_anchor: Control = null

func show_item_tooltip(anchor: Control, bbcode: String, watermark: Texture2D = null) -> void:
	_free_item_tooltip()
	if not is_instance_valid(anchor) or not anchor.is_inside_tree() or bbcode == "":
		return
	var modal := anchor.get_tree().root.find_child("ModalLayer", true, false)
	var parent: Node = modal if modal else anchor.get_tree().current_scene
	if parent == null:
		return

	var card := PanelContainer.new()
	card.name = "ItemTooltip"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never steals the hover

	# ONE consistent premium template (Precursor Bloom). Deep teal-black glass, a
	# teal frame with a heavier lit top edge, rounded corners, soft shadow. Rarity
	# still reads from the title colour; the SOUL comes from the faint slot-emblem
	# watermark ghosted behind the text + the corner-bracket chrome layered on top.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.039, 0.086, 0.078, 0.965)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.border_color = Color(0.216, 0.788, 0.690, 0.5)
	sb.content_margin_left = 15
	sb.content_margin_right = 15
	sb.content_margin_top = 13
	sb.content_margin_bottom = 13
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 4)
	card.add_theme_stylebox_override("panel", sb)

	# Faint zone emblem ghosted into the BOTTOM-RIGHT corner (index 0 = furthest
	# back). Drawn small + cornered so it reads as a maker's mark — never a slab
	# scaled up behind the dense title/stat text.
	if watermark != null:
		var wm := _TooltipWatermark.new()
		wm.tex = watermark
		wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(wm)

	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.custom_minimum_size = Vector2(328, 0)
	rtl.add_theme_color_override("default_color", Color(0.894, 0.961, 0.933))
	# Comfortable baseline sizes + line spacing (inline [font_size] tags in the
	# body still win where set).
	rtl.add_theme_font_size_override("normal_font_size", 12)
	rtl.add_theme_font_size_override("bold_font_size", 12)
	rtl.add_theme_constant_override("line_separation", 3)
	rtl.text = bbcode
	card.add_child(rtl)

	# Tech corner-bracket chrome on top — drawn in the panel margin, never on text.
	var chrome := _TooltipChrome.new()
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(chrome)

	parent.add_child(card)

	# Position near the mouse, flipped away from the viewport edges.
	var mpos := anchor.get_global_mouse_position()
	var vp := anchor.get_viewport().get_visible_rect().size
	var est := card.size if card.size.x > 1.0 else Vector2(360.0, 240.0)
	var px := mpos.x + 18.0
	var py := mpos.y + 18.0
	if px + est.x > vp.x - 8.0:
		px = mpos.x - est.x - 18.0
	if py + est.y > vp.y - 8.0:
		py = mpos.y - est.y - 18.0
	card.position = Vector2(maxf(8.0, px), maxf(8.0, py))

	_item_tooltip = card
	_item_tooltip_anchor = anchor


# Faint zone-emblem watermark — drawn small in the BOTTOM-RIGHT corner of the card
# so it reads as a maker's mark, never a slab behind the text. Child index 0 (back).
class _TooltipWatermark extends Control:
	var tex: Texture2D = null
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		if tex == null:
			return
		var s := minf(120.0, minf(size.x, size.y) - 8.0)
		if s < 24.0:
			return
		var pad := 6.0
		var r := Rect2(size.x - s - pad, size.y - s - pad, s, s)
		draw_texture_rect(tex, r, false, Color(0.373, 0.878, 0.784, 0.07))


# Tech corner-bracket overlay for the item tooltip — four L-brackets + small
# square nodes in accent teal, painted in the panel margin so they never cross the
# text. Fills the panel (PanelContainer), redraws when the card resizes to its text.
class _TooltipChrome extends Control:
	var accent := Color(0.373, 0.878, 0.784, 0.85)
	var node_col := Color(0.216, 0.788, 0.690, 0.95)
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 12.0 or h < 12.0:
			return
		# This Control is fit INSIDE the panel's content margins, but the brackets
		# must sit in the MARGIN — outside the inset text — or they overlap the
		# title. PanelContainer doesn't clip, so draw past our own rect by
		# (content_margin − 5px edge inset) to land them ~5px from the true edge.
		var ox := 10.0   # left/right content_margin (15) − 5
		var oy := 8.0    # top/bottom content_margin (13) − 5
		var L := 9.0
		var t := 1.5
		var corners := [Vector2(-ox, -oy), Vector2(w + ox, -oy), Vector2(-ox, h + oy), Vector2(w + ox, h + oy)]
		var dirs := [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
		for i in 4:
			var c: Vector2 = corners[i]
			var d: Vector2 = dirs[i]
			draw_line(c, c + Vector2(L * d.x, 0.0), accent, t)
			draw_line(c, c + Vector2(0.0, L * d.y), accent, t)
			draw_rect(Rect2(c - Vector2(1.5, 1.5), Vector2(3, 3)), node_col, true)


func hide_item_tooltip(anchor: Control = null) -> void:
	# Only the owner (or a forced null) may clear it.
	if anchor != null and anchor != _item_tooltip_anchor:
		return
	_free_item_tooltip()

func _free_item_tooltip() -> void:
	if is_instance_valid(_item_tooltip):
		_item_tooltip.queue_free()
	_item_tooltip = null
	_item_tooltip_anchor = null

# Adds (or refreshes) the CardChrome overlay on a styled card. Idempotent:
# re-applying a style on the same panel just updates the accent.
func _attach_chrome(panel: Control, accent: Color) -> void:
	var existing := panel.get_node_or_null("_CardChrome")
	if existing:
		existing.accent = accent
		existing.queue_redraw()
		return
	var chrome := CardChrome.new()
	chrome.name = "_CardChrome"
	chrome.accent = accent
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(chrome)
	# Stay the last sibling so the ornament paints above card content.
	panel.move_child(chrome, panel.get_child_count() - 1)

func apply_diegetic_header(panel: Control, category: String = "ops"):
	if not panel: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	var style = StyleBoxFlat.new()
	# Dark accent-tinted title bar with a crisp accent underline — a
	# "command bar" that caps the card. Square top corners to match the
	# square (chrome-framed) panel so the header sits perfectly flush.
	style.bg_color = accent.lerp(Color.BLACK, 0.82)
	style.border_width_bottom = 2
	style.border_color = accent
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	panel.add_theme_stylebox_override("panel", style)

func inject_diegetic_header(card: PanelContainer, category: String) -> PanelContainer:
	var margin_cont = card.get_node_or_null("MarginContainer")
	if not margin_cont: return null
	
	var vbox = margin_cont.get_node_or_null("VBoxContainer")
	if not vbox: return null
	
	var name_lbl = vbox.get_node_or_null("NameLabel")
	if not name_lbl: return null
	
	# 1. Adjust Main Layout to support header (flush top). Left/right = 10 (was 2):
	# at 2px the body content sat at x≈3, LEFT of the CardChrome inner frame (x=4),
	# so left-aligned rows (costs, the efficiency label) visibly overflowed the
	# inner border. 10 clears the frame + tucks the header tidily inside the corner
	# brackets (the chrome's own design assumes a ~10–15px content inset).
	margin_cont.add_theme_constant_override("margin_top", 0)
	margin_cont.add_theme_constant_override("margin_left", 10)
	margin_cont.add_theme_constant_override("margin_right", 10)
	margin_cont.add_theme_constant_override("margin_bottom", 6)
	vbox.add_theme_constant_override("separation", 8)
	
	# 2. Create Header
	var header_panel = PanelContainer.new()
	header_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(header_panel)
	vbox.move_child(header_panel, 0)
	
	# 3. Reparent NameLabel
	name_lbl.get_parent().remove_child(name_lbl)
	
	var header_margin = MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 8)
	header_margin.add_theme_constant_override("margin_top", 6)
	header_margin.add_theme_constant_override("margin_right", 8)
	header_margin.add_theme_constant_override("margin_bottom", 6)
	header_margin.mouse_filter = Control.MOUSE_FILTER_PASS
	header_panel.add_child(header_margin)
	
	header_margin.add_child(name_lbl)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_font_size_override("font_size", 13)
	
	# 4. Apply Styling
	apply_diegetic_header(header_panel, category)
	return header_panel

func apply_premium_button_style(button: Button, category: String = "ops"):
	if not button: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	# Recessed control with a lit accent top edge — same vocabulary as the
	# card frame and the bar fill, so the whole card reads as one system.
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = COLORS["sidebar"].lerp(accent, 0.06)
	style_normal.set_border_width_all(1)
	style_normal.border_width_top = 2
	var normal_border: Color = accent
	normal_border.a = 0.45
	style_normal.border_color = normal_border
	style_normal.set_corner_radius_all(4)

	# Hover lights the frame and adds a soft ACCENT halo (not a black
	# drop-shadow) — the bar's glow language.
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = accent.lerp(Color.BLACK, 0.32)
	style_hover.border_color = accent
	style_hover.shadow_color = Color(accent.r, accent.g, accent.b, 0.35)
	style_hover.shadow_size = 5
	style_hover.shadow_offset = Vector2(0, 0)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = accent
	style_pressed.border_color = Color.WHITE

	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.12, 0.13, 0.16, 0.85)
	style_disabled.border_color = Color(0.3, 0.3, 0.34, 0.45)
	button.add_theme_stylebox_override("disabled", style_disabled)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	# Bright accents (cyan/gold) wash out white text when pressed — use a
	# near-black label so the pressed state stays readable.
	button.add_theme_color_override("font_pressed_color", Color(0.05, 0.06, 0.08))
	button.add_theme_color_override("font_disabled_color", Color(0.45, 0.46, 0.5))
	button.add_theme_font_size_override("font_size", 13)

func apply_progress_bar_style(pb: ProgressBar, category: String = "ops"):
	if not pb: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])

	# Recessed "channel": near-black, faint accent-tinted edge, inner pad so
	# the fill nests cleanly inside the border instead of overdrawing it.
	var style_bg = StyleBoxFlat.new()
	style_bg.bg_color = Color(0.03, 0.04, 0.07, 0.95)
	style_bg.set_border_width_all(1)
	var edge: Color = accent.darkened(0.55)
	edge.a = 0.55
	style_bg.border_color = edge
	style_bg.set_corner_radius_all(3)
	style_bg.content_margin_left = 2
	style_bg.content_margin_right = 2
	style_bg.content_margin_top = 2
	style_bg.content_margin_bottom = 2

	# Solid accent fill with a lit top/leading edge (fakes a light source)
	# and a soft accent halo — the flat-glow look used across the UI.
	var style_fill = StyleBoxFlat.new()
	style_fill.bg_color = accent
	style_fill.set_corner_radius_all(2)
	style_fill.border_width_top = 1
	style_fill.border_width_right = 2
	var lit: Color = accent.lightened(0.5)
	lit.a = 0.9
	style_fill.border_color = lit
	style_fill.shadow_color = Color(accent.r, accent.g, accent.b, 0.4)
	style_fill.shadow_size = 5

	pb.add_theme_stylebox_override("background", style_bg)
	pb.add_theme_stylebox_override("fill", style_fill)

	# Percentage readout: smaller, accent-tinted, with a dark outline so it
	# stays legible whether it sits over the fill or the empty channel.
	pb.add_theme_color_override("font_color", accent.lightened(0.6))
	pb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	pb.add_theme_constant_override("outline_size", 3)
	pb.add_theme_font_size_override("font_size", 10)

# Builds the compact mastery readout used by gathering / processing cards:
# a tiny caption row ("MASTERY  LV N"  ⋯  "X / Y") above a thin progress
# bar. Returns the refs the caller needs to update each tick.
# Pass after_index = -1 to leave the panel at the end of `parent`.
# v107: Mastery info-card body text — used by show_info_card on hover of the
# "MASTERY" keyword on action/recipe cards. Single source of truth so the
# wording stays consistent across gathering + processing widgets.
func get_mastery_tooltip() -> String:
	# v108: 5 milestone rows (cap is implicit at Lv 100). Body is rendered by
	# show_info_card via RichTextLabel with bold/italics font-size overrides
	# so [b]...[/b] doesn't blow the line height up to default bold size.
	# v109: alt-recipe unlock retired; Lv 50 is now a big-step milestone with
	# +10% instead of +5% (replacing the dead alt-recipe promise with raw
	# speed). Cap moved to −30% to keep Lv 75/100 worth chasing. The actual
	# mastery info card builds a structured grid via _build_mastery_body —
	# this BBCode string is only the fallback for generic show_info_card use.
	# v110: bare schedule — no "+1 XP / run" intro, no per-row tail text. Row
	# colour alone signals Lv 50 leap (warm) + Lv 100 cap (gold). This BBCode
	# string is the fallback path; the structured grid in _build_mastery_body
	# is what the actual MASTERY tooltip renders.
	return ("[color=#C8E0D8][b]Lv 10[/b]    −5%  duration[/color][br]"
		+ "[color=#C8E0D8][b]Lv 25[/b]    −10% duration[/color][br]"
		+ "[color=#FFC24D][b]Lv 50[/b]    −20% duration[/color][br]"
		+ "[color=#C8E0D8][b]Lv 75[/b]    −25% duration[/color][br]"
		+ "[color=#FFD98A][b]Lv 100[/b]  −30% duration[/color]")

# v107: Lightweight styled info card. Caller passes an anchor Control; the
# popup parents itself under ModalLayer (or current_scene as fallback) and
# positions just above the anchor. Caller owns lifecycle — queue_free on
# mouse_exited / tree_exiting. Returns the popup Control.
func show_info_card(anchor: Control, title: String, body: String) -> Control:
	var root: Node = anchor.get_tree().current_scene
	var modal_layer: Node = anchor.get_tree().root.find_child("ModalLayer", true, false)
	var parent: Node = modal_layer if modal_layer else root

	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.039, 0.086, 0.078, 0.965)    # teal-black Precursor Bloom
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.216, 0.788, 0.690, 0.5)  # teal frame
	sb.border_width_top = 3                             # lit top accent
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 4)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(260, 0)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	card.add_child(vb)

	# Slim uppercase caption + thin gold rule (replaces the heavy HSeparator).
	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.uppercase = true
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", Color(0.373, 0.878, 0.784))
	vb.add_child(title_lbl)
	var rule := ColorRect.new()
	rule.color = Color(0.216, 0.788, 0.690, 0.4)
	rule.custom_minimum_size = Vector2(0, 1)
	vb.add_child(rule)

	# v109: For MASTERY tooltips, build a structured aligned layout (intro +
	# small caption + 3-col grid) instead of a free-text RichTextLabel. Three
	# wins: columns actually align across rows, redundant "duration" word
	# becomes a single section caption, and Lv 100 stands out as gold.
	if title.to_upper() == "MASTERY":
		_build_mastery_body(vb)
	else:
		# Generic fallback for any other info card.
		var body_rt := RichTextLabel.new()
		body_rt.bbcode_enabled = true
		body_rt.fit_content = true
		body_rt.scroll_active = false
		body_rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_rt.custom_minimum_size = Vector2(237, 0)
		body_rt.size_flags_horizontal = Control.SIZE_FILL
		body_rt.add_theme_font_size_override("normal_font_size", 11)
		body_rt.add_theme_font_size_override("bold_font_size", 11)
		body_rt.add_theme_font_size_override("italics_font_size", 11)
		body_rt.add_theme_font_size_override("bold_italics_font_size", 11)
		body_rt.add_theme_font_size_override("mono_font_size", 11)
		body_rt.add_theme_constant_override("line_separation", -2)
		body_rt.add_theme_color_override("default_color", Color(0.894, 0.961, 0.933))
		body_rt.text = body
		vb.add_child(body_rt)

	# Same tech corner-bracket chrome as the item card, for one consistent look.
	var chrome := _TooltipChrome.new()
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(chrome)

	parent.add_child(card)

	# v108.3: Position near the mouse cursor, NOT by anchor rect. Same proven
	# pattern as scripts/ui/research_node_widget.gd `_on_meta_hover` — which has
	# been working in-game for ages. Sidesteps every prior failure mode:
	#   - no `await` (fit_content settle race)
	#   - no anchor.get_global_rect() (broken when anchor lives inside a parent
	#     with a transform / ScrollContainer / SubViewport)
	#   - no `card.size.y` dependency at placement time (RichTextLabel measures
	#     over several frames)
	# Fallback size guards against card.size being (0,0) on the same frame.
	var mpos: Vector2 = anchor.get_global_mouse_position()
	var vp_size: Vector2 = anchor.get_viewport().get_visible_rect().size
	var est_size: Vector2 = card.size if card.size.x > 1.0 else Vector2(260, 180)
	var px: float = mpos.x + 20.0
	var py: float = mpos.y + 20.0
	if px + est_size.x > vp_size.x - 8.0:
		px = mpos.x - est_size.x - 20.0
	if py + est_size.y > vp_size.y - 8.0:
		py = mpos.y - est_size.y - 20.0
	card.position = Vector2(max(8.0, px), max(8.0, py))
	return card

# ─── Themed modal confirm / alert dialog ────────────────────────────────────
# v125: one-time consent prompt for enabling Offline Combat. Offline combat is
# unattended, so equipped modules already worn to <=50% durability can be
# destroyed while away (shipyard_manager.apply_offline_durability_risk).
# Centralized here so every entry point (Options + main-menu settings) shows the
# identical warning. on_confirm fires on accept; on_cancel when they back out
# (the caller reverts the toggle).
func show_offline_combat_warning(on_confirm: Callable, on_cancel: Callable = Callable()) -> Control:
	var body := "Offline Combat keeps your ship fighting while you're away — but unattended.\n\n"
	body += "[color=#ffb454]Any equipped module already at [b]50% durability or lower[/b] can be [b]destroyed[/b] during offline combat.[/color] Modules above 50% are safe.\n\n"
	body += "Repair worn modules with Spare Parts before logging off to carry [b]zero[/b] risk.\n\nEnable Offline Combat?"
	return show_confirm({
		"title": "Enable Offline Combat?",
		"body": body,
		"confirm_text": "Enable — I Accept the Risk",
		"cancel_text": "Cancel",
		"accent": Color(0.95, 0.65, 0.25),
		"danger": true,
		"on_confirm": on_confirm,
		"on_cancel": on_cancel,
	})


# Drop-in replacement for Godot's primitive Window-based ConfirmationDialog /
# AcceptDialog. Builds a chrome-framed in-scene modal on the ModalLayer: a
# dimmed click-blocking backdrop, a diegetic command-bar title, a BBCode body,
# and premium Confirm/Cancel buttons. Backdrop-click and the Cancel button both
# dismiss (and fire on_cancel). Enter confirms (Confirm grabs focus).
#
#   opts = {
#     title:        String,              # header (rendered uppercase)
#     body:         String,              # BBCode
#     confirm_text: String  = "Confirm",
#     cancel_text:  String  = "Cancel",  # "" → single-button alert mode
#     accent:       Color   = warp purple,
#     danger:       bool    = false,     # Confirm reads destructive (red)
#     on_confirm:   Callable,            # invoked after dismiss
#     on_cancel:    Callable,            # optional
#   }
# Returns the overlay Control (it self-frees on either choice).
func show_confirm(opts: Dictionary) -> Control:
	var tree := get_tree()
	if not tree: return null
	var scene: Node = tree.current_scene
	var modal_layer: Node = tree.root.find_child("ModalLayer", true, false)
	var parent: Node = modal_layer if modal_layer else scene
	if not parent: return null

	var accent: Color = opts.get("accent", Color(0.78, 0.55, 1.0))   # warp purple
	var is_danger: bool = bool(opts.get("danger", false))
	var cancel_text: String = String(opts.get("cancel_text", "Cancel"))

	# Full-rect overlay; the dim ColorRect swallows clicks behind the dialog.
	var overlay := Control.new()
	overlay.name = "ConfirmModal"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	# Chrome-framed panel (square corners + faint accent border, like the cards).
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.11, 0.985)
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(1)
	var bcol: Color = accent
	bcol.a = 0.55
	sb.border_color = bcol
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 26
	sb.shadow_offset = Vector2(0, 10)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	panel.add_child(vb)

	# Title bar — dark accent-tinted command bar with a crisp accent underline.
	var header := PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = accent.lerp(Color.BLACK, 0.80)
	hsb.border_width_bottom = 2
	hsb.border_color = accent
	hsb.content_margin_left = 16
	hsb.content_margin_right = 16
	hsb.content_margin_top = 11
	hsb.content_margin_bottom = 11
	header.add_theme_stylebox_override("panel", hsb)
	vb.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = String(opts.get("title", "CONFIRM"))
	title_lbl.uppercase = true
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	header.add_child(title_lbl)

	# Body.
	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 20)
	body_margin.add_theme_constant_override("margin_right", 20)
	body_margin.add_theme_constant_override("margin_top", 16)
	body_margin.add_theme_constant_override("margin_bottom", 18)
	vb.add_child(body_margin)

	var body_rt := RichTextLabel.new()
	body_rt.bbcode_enabled = true
	body_rt.fit_content = true
	body_rt.scroll_active = false
	body_rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_rt.custom_minimum_size = Vector2(400, 0)
	body_rt.add_theme_font_size_override("normal_font_size", 13)
	body_rt.add_theme_font_size_override("bold_font_size", 13)
	body_rt.add_theme_color_override("default_color", Color(0.86, 0.88, 0.92))
	body_rt.text = String(opts.get("body", ""))
	body_margin.add_child(body_rt)

	# Button row.
	var btn_margin := MarginContainer.new()
	btn_margin.add_theme_constant_override("margin_left", 16)
	btn_margin.add_theme_constant_override("margin_right", 16)
	btn_margin.add_theme_constant_override("margin_bottom", 16)
	vb.add_child(btn_margin)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_margin.add_child(btn_row)

	# Shared cancel path (Cancel button + backdrop click).
	var do_cancel := func():
		if not is_instance_valid(overlay): return
		overlay.queue_free()
		var cc = opts.get("on_cancel", null)
		if cc is Callable and (cc as Callable).is_valid(): (cc as Callable).call()

	if cancel_text != "":
		var cancel_btn := Button.new()
		cancel_btn.text = cancel_text
		cancel_btn.custom_minimum_size = Vector2(140, 42)
		cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_dialog_button(cancel_btn, Color(0.55, 0.57, 0.66), false)
		cancel_btn.pressed.connect(do_cancel)
		btn_row.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = String(opts.get("confirm_text", "Confirm"))
	confirm_btn.custom_minimum_size = Vector2(140, 42)
	confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var confirm_accent: Color = Color(0.95, 0.40, 0.40) if is_danger else accent
	_style_dialog_button(confirm_btn, confirm_accent, true)
	confirm_btn.pressed.connect(func():
		if not is_instance_valid(overlay): return
		overlay.queue_free()
		var cb = opts.get("on_confirm", null)
		if cb is Callable and (cb as Callable).is_valid(): (cb as Callable).call()
	)
	btn_row.add_child(confirm_btn)
	# Optional: present the choice but block confirm (e.g. can't afford the cost).
	if bool(opts.get("confirm_disabled", false)):
		confirm_btn.disabled = true

	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			do_cancel.call()
	)

	parent.add_child(overlay)
	_attach_chrome(panel, accent)        # L-bracket corner ornament, on-brand
	if not confirm_btn.disabled:
		confirm_btn.grab_focus()         # Enter confirms (skip when blocked)
	return overlay

# Color-parameterised dialog button (sibling to the category-keyed
# apply_premium_button_style). prominent → filled primary; else subdued outline.
func _style_dialog_button(button: Button, accent: Color, prominent: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(4)
	normal.set_border_width_all(1)
	normal.border_width_top = 2
	if prominent:
		normal.bg_color = accent.lerp(Color(0.04, 0.04, 0.07), 0.45)
		normal.border_color = accent
	else:
		normal.bg_color = COLORS["sidebar"].lerp(accent, 0.05)
		var b: Color = accent
		b.a = 0.5
		normal.border_color = b
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6

	var hover := normal.duplicate()
	hover.bg_color = accent.lerp(Color.BLACK, 0.28) if prominent else accent.lerp(Color.BLACK, 0.45)
	hover.border_color = accent
	hover.shadow_color = Color(accent.r, accent.g, accent.b, 0.35)
	hover.shadow_size = 6

	var pressed := normal.duplicate()
	pressed.bg_color = accent
	pressed.border_color = Color.WHITE

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color(0.05, 0.06, 0.08))
	button.add_theme_font_size_override("font_size", 14)

# v109: structured body builder for the MASTERY info card. Intro + small gold
# caption + 3-column grid (Lv key | duration cut | unlock note). Grid keeps
# the % values vertically aligned and lets us drop the repeated "duration"
# word — it's now stated once in the caption.
func _build_mastery_body(parent: VBoxContainer) -> void:
	# v110: "Show don't tell." Everything explanatory is gone — no "+1 XP per
	# run" intro (the bar fills visibly), no "kept across Warps" promise (the
	# player discovers persistence by Warping), no per-row "big step / Gold
	# (cap)" suffix. Only the caption + numbers remain. Colour shift at Lv 50
	# (warm bright) and Lv 100 (gold) is the silent reward signal.
	var col_text := Color(0.894, 0.961, 0.933)
	var col_mid_step := Color(1.0, 0.761, 0.302)    # amber — Lv 50 leap
	var col_gold := Color(1.0, 0.761, 0.302)        # cap reward

	# Section caption — only piece of "telling" we keep, because raw "−5%"
	# is ambiguous (yield? damage? duration?). One word disambiguates 5 rows.
	var caption := Label.new()
	caption.text = "DURATION BONUS"
	caption.uppercase = true
	caption.add_theme_font_size_override("font_size", 9)
	caption.add_theme_color_override("font_color", Color(0.498, 0.639, 0.612))
	parent.add_child(caption)

	# 2-col grid: Lv key (bold) | % cut. Row colour carries the milestone
	# tier; no third "explainer" column.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	parent.add_child(grid)

	# rows: [key, pct, row_color]
	var rows: Array = [
		["Lv 10",  "−5%",   col_text],
		["Lv 25",  "−10%",  col_text],
		["Lv 50",  "−20%",  col_mid_step],   # warm bright cue — leap
		["Lv 75",  "−25%",  col_text],
		["Lv 100", "−30%",  col_gold],       # gold cue — cap
	]
	for r in rows:
		var key_lbl := RichTextLabel.new()
		key_lbl.bbcode_enabled = true
		key_lbl.fit_content = true
		key_lbl.scroll_active = false
		key_lbl.add_theme_font_size_override("normal_font_size", 11)
		key_lbl.add_theme_font_size_override("bold_font_size", 11)
		key_lbl.add_theme_color_override("default_color", r[2])
		key_lbl.text = "[b]%s[/b]" % r[0]
		key_lbl.custom_minimum_size = Vector2(48, 0)   # fits "Lv 100" bold
		grid.add_child(key_lbl)

		var pct_lbl := Label.new()
		pct_lbl.text = r[1]
		pct_lbl.add_theme_font_size_override("font_size", 11)
		pct_lbl.add_theme_color_override("font_color", r[2])
		pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pct_lbl.custom_minimum_size = Vector2(40, 0)
		grid.add_child(pct_lbl)

func build_mastery_panel(parent: VBoxContainer, after_index: int, category: String) -> Dictionary:
	var box := VBoxContainer.new()
	box.name = "MasteryPanel"
	box.add_theme_constant_override("separation", 2)
	parent.add_child(box)
	if after_index >= 0 and after_index < parent.get_child_count():
		parent.move_child(box, after_index)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 6)
	hdr.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(hdr)

	# v109: LEFT mastery slot is a RichTextLabel so callers can wrap the
	# "MASTERY" keyword in [u]...[/u] — that's the player's visual cue that
	# the word is hoverable for the milestone schedule popup.
	var left := RichTextLabel.new()
	left.bbcode_enabled = true
	left.fit_content = true
	left.scroll_active = false
	left.shortcut_keys_enabled = false
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.mouse_filter = Control.MOUSE_FILTER_PASS
	left.add_theme_font_size_override("normal_font_size", 9)
	left.add_theme_font_size_override("bold_font_size", 9)
	left.add_theme_font_size_override("italics_font_size", 9)
	left.add_theme_font_size_override("bold_italics_font_size", 9)
	hdr.add_child(left)

	var right := Label.new()
	right.add_theme_font_size_override("font_size", 9)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hdr.add_child(right)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 5)
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	apply_progress_bar_style(bar, category)
	box.add_child(bar)

	return {"box": box, "left": left, "right": right, "bar": bar}


## apply_segmented_bar_style: Creates a high-tech "Digital Gauge" look
func apply_segmented_bar_style(pb: ProgressBar, category: String = "ops"):
	if not pb: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	var style_bg = StyleBoxFlat.new()
	style_bg.bg_color = Color(0.08, 0.08, 0.1, 0.9)
	style_bg.set_border_width_all(1)
	style_bg.border_color = accent.lerp(Color.BLACK, 0.6)
	
	var style_fill = StyleBoxFlat.new()
	style_fill.bg_color = accent
	style_fill.border_width_top = 2
	style_fill.border_color = Color.WHITE
	style_fill.border_color.a = 0.2
	
	pb.add_theme_stylebox_override("background", style_bg)
	pb.add_theme_stylebox_override("fill", style_fill)
	
	# REMOVED: Procedural overlays that cause phantom artifacts

## trigger_damage_flash: Visual "White-Out" for bars when taking hits
func trigger_damage_flash(node: Control):
	if not node: return
	var tween = node.create_tween()
	var original_mod = node.modulate
	
	node.modulate = Color(3, 3, 3, 1) # Overexposure
	tween.tween_property(node, "modulate", original_mod, 0.2).set_trans(Tween.TRANS_QUINT)
	
	# Add a bite-sized shake
	# Assuming trigger_ui_thud exists elsewhere or is a placeholder
	# trigger_ui_thud(node, 3.0)

func format_num(val: float) -> String:
	return FormatUtils.format_number(val)

func apply_panel_style(panel: PanelContainer):
	if not panel: return
	var style = StyleBoxFlat.new()
	style.bg_color = COLORS["panel_bg"]
	style.set_border_width_all(1)
	style.border_color = COLORS["accent"].lerp(Color.BLACK, 0.3)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	panel.add_theme_stylebox_override("panel", style)

func apply_sidebar_button_style(button: Button, is_active: bool, accent_override = null):
	if not button: return

	var accent     := Color(0.38, 0.78, 1.00)
	var bg_active  := Color(0.10, 0.135, 0.215, 0.88)
	var bg_hover   := Color(0.08, 0.100, 0.165, 0.65)
	# accent_override gives a nav button its own identity colour (e.g. the purple
	# Warp Core) using the EXACT sidebar shape/rhythm — left-bar accent + a faintly
	# accent-tinted active fill — instead of a clashing default boxed button.
	var has_identity := false
	if accent_override != null:
		accent = accent_override
		has_identity = true
		bg_active = accent.darkened(0.80)
		bg_active.a = 0.85
		bg_hover = accent.darkened(0.86)
		bg_hover.a = 0.55

	var style_n := StyleBoxFlat.new()
	style_n.draw_center = is_active
	style_n.bg_color = bg_active if is_active else Color(0, 0, 0, 0)
	style_n.set_border_width_all(0)
	if is_active:
		style_n.border_width_left = 3
		style_n.border_color = accent
	style_n.content_margin_left   = 14
	style_n.content_margin_right  = 8
	style_n.content_margin_top    = 6
	style_n.content_margin_bottom = 6

	var style_h := StyleBoxFlat.new()
	style_h.draw_center = true
	style_h.bg_color = bg_hover
	style_h.set_border_width_all(0)
	style_h.border_width_left = 2
	style_h.border_color = accent.darkened(0.35)
	style_h.content_margin_left   = 14
	style_h.content_margin_right  = 8
	style_h.content_margin_top    = 6
	style_h.content_margin_bottom = 6

	var style_p := style_h.duplicate()
	style_p.bg_color = bg_active
	style_p.border_width_left = 3
	style_p.border_color = accent

	button.add_theme_stylebox_override("normal",  style_n)
	button.add_theme_stylebox_override("hover",   style_h)
	button.add_theme_stylebox_override("pressed", style_p)
	button.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())

	# Resting/active label+icon colours. With an identity accent the button carries
	# its colour in every state (dimmer when inactive, brighter when active).
	var col_off := Color(0.50, 0.55, 0.68)
	var col_on := Color(0.90, 0.95, 1.00)
	var col_hover := Color(0.78, 0.90, 1.00)
	if has_identity:
		col_off = accent.darkened(0.05)
		col_on = accent.lightened(0.28)
		col_hover = accent.lightened(0.28)
	var col_main: Color = col_on if is_active else col_off

	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", col_main)
	button.add_theme_color_override("font_hover_color",   col_hover)
	button.add_theme_color_override("font_pressed_color", Color(1.00, 1.00, 1.00))
	# v111.21: tint the white SVG nav icon in lockstep with the label, and keep a
	# consistent icon size + icon↔label gap.
	button.add_theme_color_override("icon_normal_color", col_main)
	button.add_theme_color_override("icon_hover_color",   col_hover)
	button.add_theme_color_override("icon_pressed_color", Color(1.00, 1.00, 1.00))
	button.add_theme_constant_override("icon_max_width", 18)
	button.add_theme_constant_override("h_separation", 10)

func apply_modal_style(panel: PanelContainer):
	if not panel: return
	var style = StyleBoxFlat.new()
	# Softer background
	style.bg_color = COLORS["background"].lightened(0.02).lerp(COLORS["accent"], 0.05)
	
	# Crisp thin border
	style.set_border_width_all(1)
	var modal_border = COLORS["accent"]
	modal_border.a = 0.4
	style.border_color = modal_border
	
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	
	# Large soft diffused shadow
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 24
	style.shadow_offset = Vector2(0, 10)
	
	panel.add_theme_stylebox_override("panel", style)

func apply_input_style(input: Control, category: String = "ops"):
	if not input: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = COLORS["panel_bg"].darkened(0.3)
	style_normal.bg_color.a = 0.8
	style_normal.set_border_width_all(1)
	style_normal.border_color = style_normal.bg_color # Hidden border natively
	style_normal.set_corner_radius_all(4)
	
	var style_focus = style_normal.duplicate()
	style_focus.border_color = accent
	style_focus.bg_color = COLORS["panel_bg"].darkened(0.2)
	
	input.add_theme_stylebox_override("normal", style_normal)
	input.add_theme_stylebox_override("focus", style_focus)

func apply_tab_style(tabs: TabContainer, category: String = "ops"):
	if not tabs: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	# Content Panel (Matches new apply_card_style)
	var style_panel = StyleBoxFlat.new()
	style_panel.bg_color = COLORS["panel_bg"].lerp(accent, 0.05)
	style_panel.bg_color.a = 0.90
	style_panel.set_border_width_all(1)
	var border_col = accent
	border_col.a = 0.3
	style_panel.border_color = border_col
	style_panel.set_corner_radius_all(6)
	style_panel.shadow_color = Color(0, 0, 0, 0.25)
	style_panel.shadow_size = 12
	style_panel.shadow_offset = Vector2(0, 4)
	
	# Tab Selected (Matches panel background to look seamless)
	var style_selected = StyleBoxFlat.new()
	style_selected.bg_color = style_panel.bg_color
	style_selected.set_border_width_all(1)
	style_selected.border_color = style_selected.bg_color # Seamless blend
	style_selected.border_width_top = 2
	style_selected.border_color = accent
	style_selected.corner_radius_top_left = 4
	style_selected.corner_radius_top_right = 4
	style_selected.content_margin_left = 16
	style_selected.content_margin_right = 16
	
	# Tab Unselected
	var style_unselected = StyleBoxFlat.new()
	style_unselected.bg_color = COLORS["sidebar"].darkened(0.1)
	style_unselected.set_border_width_all(0)
	style_unselected.corner_radius_top_left = 4
	style_unselected.corner_radius_top_right = 4
	style_unselected.content_margin_left = 12
	style_unselected.content_margin_right = 12
	
	# Tab Hover
	var style_hover = style_unselected.duplicate()
	style_hover.bg_color = COLORS["sidebar"].lightened(0.05)
	style_hover.border_width_top = 2
	style_hover.border_color = accent.lightened(0.3)
	
	# Tab Focus/Disabled (Safety)
	var style_focus = style_selected.duplicate()
	style_focus.draw_center = false
	
	tabs.add_theme_stylebox_override("tab_selected", style_selected)
	tabs.add_theme_stylebox_override("tab_unselected", style_unselected)
	tabs.add_theme_stylebox_override("tab_hovered", style_hover)
	tabs.add_theme_stylebox_override("tab_focus", style_focus)
	tabs.add_theme_stylebox_override("tab_disabled", style_unselected)
	tabs.add_theme_stylebox_override("panel", style_panel)
	
	tabs.add_theme_color_override("font_selected_color", Color.WHITE)
	tabs.add_theme_color_override("font_hovered_color", Color.WHITE)
	tabs.add_theme_color_override("font_unselected_color", COLORS["text_dim"])
	
	# Tab Sizing
	tabs.add_theme_constant_override("side_margin", 10)
	tabs.add_theme_font_size_override("font_size", 13)

func apply_sharp_button_style(button: Button, category: String = "ops"):
	if not button: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = COLORS["sidebar"].lerp(accent, 0.05)
	style_normal.set_border_width_all(1)
	var normal_border = accent
	normal_border.a = 0.4
	style_normal.border_color = normal_border
	style_normal.set_corner_radius_all(0) # Keep it sharp!
	
	# Added Padding to increase size
	style_normal.content_margin_left = 16
	style_normal.content_margin_right = 16
	style_normal.content_margin_top = 8
	style_normal.content_margin_bottom = 8
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = accent.lerp(Color.BLACK, 0.3)
	style_hover.border_color = accent
	
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = accent
	style_pressed.border_color = Color.WHITE
	
	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.15, 0.15, 0.15, 0.8)
	style_disabled.border_color = Color(0.3, 0.3, 0.3, 0.5)
	
	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	button.add_theme_stylebox_override("disabled", style_disabled)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 12)

# --- ANIMATION HELPERS (Iter8 Rich Aesthetics) ---

func add_hover_scale(control: Control, scale_amount: float = 1.05):
	if not control: return
	control.pivot_offset = control.size / 2
	
	control.mouse_entered.connect(func():
		var tween = control.create_tween()
		tween.tween_property(control, "scale", Vector2(scale_amount, scale_amount), 0.15).set_trans(Tween.TRANS_SINE)
	)
	control.mouse_exited.connect(func():
		var tween = control.create_tween()
		tween.tween_property(control, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_SINE)
	)

func add_pulse_glow(control: Control, category: String = "ops"):
	if not control: return
	var color = CATEGORY_COLORS.get(category, COLORS["accent_bright"])
	
	var tween = control.create_tween().set_loops()
	tween.tween_property(control, "modulate", color.lightened(0.2), 0.8).set_trans(Tween.TRANS_SINE)
	tween.tween_property(control, "modulate", Color.WHITE, 0.8).set_trans(Tween.TRANS_SINE)
	return tween

# --- PHASE 28: TACTILE INSTRUMENT HELPERS ---

## trigger_ui_thud: Localized screen shake for physical weight
func trigger_ui_thud(node: Control, intensity: float = 4.0):
	if not node: return
	var original_pos = node.position
	var tween = node.create_tween()
	
	# High-frequency decay shake
	for i in range(4):
		var offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		tween.tween_property(node, "position", original_pos + offset, 0.03)
		intensity *= 0.5
	
	tween.tween_property(node, "position", original_pos, 0.05)

## apply_instrument_style: Styles buttons as physical mechanical toggles
func apply_instrument_style(button: Button, category: String = "ops"):
	if not button: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.1, 0.1, 0.15)
	style_normal.set_border_width_all(1)
	style_normal.border_color = Color(0.3, 0.3, 0.4)

	# v111.12: Left "bevel" accent. Border width is now CONSTANT (3px) across
	# normal/hover/pressed — previously it grew 3→5→8, which shrank the button's
	# content area on hover, re-wrapping the label text and resizing the whole
	# consumables card. State feedback comes from bg + border COLOUR only, so
	# the content area (and therefore text wrap + button size) never changes.
	style_normal.border_width_left = 3
	style_normal.border_color = accent.lerp(Color.WHITE, 0.2)

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = accent.lerp(Color.BLACK, 0.7)
	style_hover.border_color = accent

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = accent
	style_pressed.border_color = Color.WHITE
	
	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	# Monospace for "Terminal" look
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color(0.8, 0.8, 1.0))

## apply_segmented_font: Makes labels look like LED readouts
func apply_segmented_font(label: Control, color: Color = Color.CYAN):
	if label is Label or label is RichTextLabel:
		label.add_theme_color_override("font_color", color)
		label.add_theme_font_size_override("font_size", 10)
		# Simulating glow via modulate/shadow
		label.modulate = color.lightened(0.3)
		
		if label is Label:
			label.uppercase = true

# --- PHASE 29: FLOW & ENTROPY HELPERS ---

## spawn_data_packet: Visualizes production flow to the HUD
func spawn_data_packet(start_node: Control, target_pos: Vector2, color: Color = Color.CYAN):
	if not start_node: return
	
	var packet = ColorRect.new()
	packet.custom_minimum_size = Vector2(4, 4)
	packet.color = color
	packet.modulate.a = 0.8
	
	# Add to the main scene to ensure it stays on top of all UI
	var root = start_node.get_tree().root.get_child(0)
	root.add_child(packet)
	
	packet.global_position = start_node.global_position + (start_node.size / 2.0)
	
	var tween = packet.create_tween()
	# High-velocity "pop" out then quintic ease toward target
	var mid_offset = Vector2(randf_range(-50, 50), randf_range(-50, 50))
	tween.tween_property(packet, "global_position", packet.global_position + mid_offset, 0.1).set_trans(Tween.TRANS_QUINT)
	tween.tween_property(packet, "global_position", target_pos, 0.6).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(packet, "scale", Vector2(0.2, 0.2), 0.6)
	tween.tween_callback(func():
		packet_landed.emit(color)
		packet.queue_free()
	)

## trigger_mechanical_bash: Heavy, low-frequency shake for industrial events
func trigger_mechanical_bash(node: Control, intensity: float = 12.0):
	if not node: return
	var original_pos = node.position
	var tween = node.create_tween()
	
	# Deep, reverberating thud
	for i in range(5):
		var offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		tween.tween_property(node, "position", original_pos + offset, 0.05).set_trans(Tween.TRANS_SINE)
		intensity *= 0.6
	
	tween.tween_property(node, "position", original_pos, 0.1)

# --- PHASE 30: TACTICAL DECK HELPERS ---

## trigger_circuit_surge: Visual pulse when snapping modules
func trigger_circuit_surge(node: Control, color: Color = Color.CYAN):
	if not node: return
	
	var tween = node.create_tween()
	node.modulate = color.lightened(0.5)
	node.scale = Vector2(1.1, 1.1)
	
	tween.tween_property(node, "modulate", Color.WHITE, 0.2).set_trans(Tween.TRANS_QUINT)
	tween.parallel().tween_property(node, "scale", Vector2(1.0, 1.0), 0.2)

## trigger_system_glitch: Visceral feedback for combat damage
func trigger_system_glitch(node: Control, intensity: float = 8.0):
	if not node: return
	var original_pos = node.position
	var tween = node.create_tween()
	
	# High-frequency jitter + Color flickering
	for i in range(6):
		var offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		tween.tween_property(node, "position", original_pos + offset, 0.02)
		
		# Alternating red-tint flicker
		if i % 2 == 0:
			tween.parallel().tween_property(node, "modulate", Color(1.5, 0.5, 0.5), 0.02)
		else:
			tween.parallel().tween_property(node, "modulate", Color.WHITE, 0.02)
		
		intensity *= 0.8
	
	tween.tween_property(node, "position", original_pos, 0.05)
	tween.parallel().tween_property(node, "modulate", Color.WHITE, 0.05)

## trigger_tab_alert: Rhythmic pulse + Visual marker for navigation headers
func trigger_tab_alert(tabs: TabContainer, tab_idx: int, active: bool = true, color: Color = Color.CYAN):
	if not tabs or tab_idx < 0 or tab_idx >= tabs.get_tab_count(): return
	
	var title = tabs.get_tab_title(tab_idx)
	var marker = "(!) "
	
	# Handle Title Prefixing (Audit v16.4: Clean text marker)
	if active:
		if not title.begins_with(marker):
			tabs.set_tab_title(tab_idx, marker + title)
	else:
		if title.begins_with(marker):
			tabs.set_tab_title(tab_idx, title.replace(marker, ""))
	
	# 1. Manage Active Alerts List
	var active_alerts = tabs.get_meta("active_tab_alerts", [])
	if active:
		if not tab_idx in active_alerts:
			active_alerts.append(tab_idx)
	else:
		active_alerts.erase(tab_idx)
	tabs.set_meta("active_tab_alerts", active_alerts)
	
	# 2. Global Pulse Disabled (Audit v16.4: Reduced noise)
	var bar = tabs.get_tab_bar()
	bar.modulate = Color.WHITE
	# Removed pulse_key / tween logic entirely
# --- PHASE 47: DIEGETIC & HOLOGRAPHIC HELPERS ---

## apply_holographic_projection: Minimalist border-only HUD style
func apply_holographic_projection(panel: Control, category: String = "ops"):
	if not panel: return
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0) # FULL TRANSPARENCY
	style.draw_center = false
	
	# THEMATIC: Glowing minimalist borders
	style.set_border_width_all(1)
	style.border_color = accent
	# High-frequency "Energy" glow via border blend
	style.border_blend = true
	
	# Slightly rounded for modern sci-fi
	style.set_corner_radius_all(2)
	
	# Shadow behaves more like a "Halo" in 0% opacity backgrounds
	style.shadow_color = Color(accent, 0.2)
	style.shadow_size = 4
	
	panel.add_theme_stylebox_override("panel", style)
	return style

## apply_locked_overlay: Creates and manages a visual "LOCKED" state for Cards
func apply_locked_overlay(card: Control, item_name: String, message: String, is_locked: bool, tech_id: String = "", category: String = "ops", dim_only: bool = false):
	if not card: return
	
	var overlay_name = "LockedOverlay"
	var overlay = card.get_node_or_null(overlay_name)
	
	if not is_locked:
		if overlay: overlay.hide()
		return
	
	if not overlay:
		# Two modes:
		#  · default (block)  — fully opaque black; big cards (gather/process/
		#    recipes) have their own dense content that would clash if it
		#    bled through.
		#  · dim_only — translucent dark so the rarity-styled tile underneath
		#    still reads (used by module_card, where the rarity frame + slot
		#    icon are the only identity cues on a small ~64px tile).
		overlay = ColorRect.new()
		overlay.name = overlay_name
		overlay.color = Color(0.02, 0.03, 0.05, 0.62) if dim_only else Color(0, 0, 0, 1.0)
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_STOP # Block clicks
		card.add_child(overlay)
		# Stay the last sibling so the overlay paints above any child visuals
		# the caller adds after this function runs.
		card.move_child(overlay, card.get_child_count() - 1)
		
		# 2. Full-width padded container. A CenterContainer shrinks to its
		#    content, so long research names ("Lightweight Alloys") had no
		#    width to wrap against and overflowed/clipped the card. A
		#    MarginContainer forces the text block to the real card width.
		var pad = MarginContainer.new()
		pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pad.add_theme_constant_override("margin_left", 6)
		pad.add_theme_constant_override("margin_right", 6)
		pad.add_theme_constant_override("margin_top", 4)
		pad.add_theme_constant_override("margin_bottom", 4)
		overlay.add_child(pad)

		var vbox = VBoxContainer.new()
		vbox.name = "VBox"
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER  # vertical centering
		pad.add_child(vbox)

		var name_lbl = Label.new()
		name_lbl.name = "ItemNameLabel"
		name_lbl.text = item_name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title_col = CATEGORY_COLORS.get(category, Color(0.216, 0.788, 0.69))
		name_lbl.add_theme_color_override("font_color", title_col)
		if dim_only:
			# Compact single-line, clipped — leaves room for the rarity tile
			# to read through the translucent overlay.
			name_lbl.add_theme_font_size_override("font_size", 10)
			name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
			name_lbl.clip_text = true
			name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			name_lbl.add_theme_constant_override("outline_size", 3)
			name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		else:
			name_lbl.add_theme_font_size_override("font_size", 12)
			name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(name_lbl)

		var lock_lbl = Label.new()
		lock_lbl.name = "LockHeading"
		lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if dim_only:
			lock_lbl.text = "[ LOCKED ]"
			lock_lbl.add_theme_font_size_override("font_size", 11)
			lock_lbl.add_theme_color_override("font_color", CATEGORY_COLORS["combat"].lightened(0.1))
			lock_lbl.add_theme_constant_override("outline_size", 3)
			lock_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		else:
			lock_lbl.text = "LOCKED"
			lock_lbl.add_theme_font_size_override("font_size", 14)
			lock_lbl.add_theme_color_override("font_color", Color.WHITE)
		vbox.add_child(lock_lbl)

		var req_lbl = RichTextLabel.new()
		req_lbl.name = "ReqLabel"
		req_lbl.bbcode_enabled = true
		req_lbl.fit_content = true       # height-to-content; width from parent
		req_lbl.scroll_active = false
		req_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		req_lbl.add_theme_font_size_override("normal_font_size", 9)
		req_lbl.add_theme_color_override("default_color", Color(1.0, 0.4, 0.4))
		req_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		req_lbl.add_theme_constant_override("line_separation", 2)
		req_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(req_lbl)
		
		req_lbl.meta_clicked.connect(func(meta):
			if str(meta).begins_with("research:"):
				var tid = str(meta).replace("research:", "")
				research_navigation_requested.emit(tid)
		)
		
		_update_locked_message(req_lbl, message, tech_id)
	else:
		overlay.show()
		var name_lbl = overlay.find_child("ItemNameLabel", true, false)
		if name_lbl: 
			name_lbl.text = item_name
			var title_col = CATEGORY_COLORS.get(category, Color(0.216, 0.788, 0.69))
			name_lbl.add_theme_color_override("font_color", title_col)
		
		var req_lbl = overlay.find_child("ReqLabel", true, false)
		if req_lbl: 
			_update_locked_message(req_lbl, message, tech_id)

func _update_locked_message(lbl: RichTextLabel, message: String, tech_id: String):
	if message.to_upper().begins_with("RESEARCH:") and tech_id != "":
		# Handle both "RESEARCH: Name" and "RESEARCH: NAME"
		var tech_name = message.substr(9).strip_edges() # Skip "RESEARCH:"
		lbl.text = "[center]RESEARCH:\n[url=research:%s][color=#ffdd22][u]%s[/u][/color][/url][/center]" % [tech_id, tech_name]
	else:
		lbl.text = "[center]%s[/center]" % message

# --- ACTIVITY CARD OVERHAUL (additive; used only by the gathering /
# processing widgets -- does NOT touch the shared inject_diegetic_header /
# apply_card_style paths the other 15 card types rely on) ---

## inject_activity_header: one compact command row -- [icon | name | Lv badge]
## -- replacing the name + separate centred level line. Reparents the
## existing NameLabel + LevelLabel so update_state() keeps driving them.
func inject_activity_header(card: PanelContainer, category: String, icon_tex: Texture2D) -> PanelContainer:
	var margin_cont = card.get_node_or_null("MarginContainer")
	if not margin_cont: return null
	var vbox = margin_cont.get_node_or_null("VBoxContainer")
	if not vbox: return null
	var name_lbl = vbox.get_node_or_null("NameLabel")
	var lvl_lbl = vbox.get_node_or_null("LevelLabel")
	if not name_lbl: return null

	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])

	# Uniform side inset so header / IO panels / button / bar share one
	# aligned column. Top stays 0 so the header band sits flush to the card.
	margin_cont.add_theme_constant_override("margin_top", 0)
	margin_cont.add_theme_constant_override("margin_left", 8)
	margin_cont.add_theme_constant_override("margin_right", 8)
	margin_cont.add_theme_constant_override("margin_bottom", 8)
	vbox.add_theme_constant_override("separation", 7)

	var header_panel = PanelContainer.new()
	header_panel.name = "ActivityHeader"
	header_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(header_panel)
	vbox.move_child(header_panel, 0)

	var hmargin = MarginContainer.new()
	hmargin.add_theme_constant_override("margin_left", 8)
	hmargin.add_theme_constant_override("margin_right", 8)
	hmargin.add_theme_constant_override("margin_top", 5)
	hmargin.add_theme_constant_override("margin_bottom", 5)
	hmargin.mouse_filter = Control.MOUSE_FILTER_PASS
	header_panel.add_child(hmargin)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	hmargin.add_child(row)

	if icon_tex:
		var icon = TextureRect.new()
		icon.texture = icon_tex
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)

	name_lbl.get_parent().remove_child(name_lbl)
	row.add_child(name_lbl)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.clip_text = true
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_font_size_override("font_size", 13)

	if lvl_lbl:
		lvl_lbl.get_parent().remove_child(lvl_lbl)
		var badge = PanelContainer.new()
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bm = MarginContainer.new()
		bm.add_theme_constant_override("margin_left", 6)
		bm.add_theme_constant_override("margin_right", 6)
		bm.add_theme_constant_override("margin_top", 1)
		bm.add_theme_constant_override("margin_bottom", 1)
		badge.add_child(bm)
		bm.add_child(lvl_lbl)
		lvl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lvl_lbl.add_theme_font_size_override("font_size", 10)
		lvl_lbl.add_theme_color_override("font_color", accent.lightened(0.4))
		var bstyle = StyleBoxFlat.new()
		bstyle.bg_color = accent.lerp(Color.BLACK, 0.78)
		bstyle.set_corner_radius_all(3)
		bstyle.set_border_width_all(1)
		var bcol: Color = accent
		bcol.a = 0.5
		bstyle.border_color = bcol
		badge.add_theme_stylebox_override("panel", bstyle)
		row.add_child(badge)

	apply_diegetic_header(header_panel, category)
	return header_panel

## wrap_in_io_panel: pull a label into a captioned compartment. kind is one
## of "yield" / "output" (the payoff -- reads as the hero) or "input" (recedes).
## The caption turns a floating text box into a labelled instrument readout.
func wrap_in_io_panel(label: Control, category: String, kind: String) -> PanelContainer:
	if not label: return null
	var parent = label.get_parent()
	if not parent: return null
	var accent = CATEGORY_COLORS.get(category, COLORS["accent"])
	var idx = label.get_index()
	var emphasis: bool = kind != "input"

	var panel = PanelContainer.new()
	panel.name = label.name + "Panel"
	panel.size_flags_horizontal = Control.SIZE_FILL
	# Size to content -- a forced vexpand is what hollowed the sparse cards.
	parent.add_child(panel)
	parent.move_child(panel, idx)

	var m = MarginContainer.new()
	m.add_theme_constant_override("margin_left", 9)
	m.add_theme_constant_override("margin_right", 9)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(m)

	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	m.add_child(col)

	var cap = Label.new()
	cap.text = ({"yield": "YIELD", "output": "OUTPUT", "input": "INPUTS"}).get(kind, kind.to_upper())
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 8)
	cap.add_theme_constant_override("outline_size", 0)
	if emphasis:
		var cc: Color = accent.lightened(0.35)
		cc.a = 0.75
		cap.add_theme_color_override("font_color", cc)
	else:
		cap.add_theme_color_override("font_color", Color(0.52, 0.54, 0.60))
	col.add_child(cap)

	label.get_parent().remove_child(label)
	col.add_child(label)
	if label is RichTextLabel:
		label.add_theme_font_size_override("normal_font_size", 14 if emphasis else 11)
		label.add_theme_color_override("default_color",
			Color(0.96, 0.97, 1.0) if emphasis else Color(0.66, 0.68, 0.74))

	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(4)
	if emphasis:
		style.bg_color = accent.lerp(Color.BLACK, 0.82)
		style.set_border_width_all(1)
		style.border_width_left = 3
		var bc: Color = accent
		bc.a = 0.9
		style.border_color = bc
		style.shadow_color = Color(accent.r, accent.g, accent.b, 0.16)
		style.shadow_size = 6
	else:
		style.bg_color = Color(0.0, 0.0, 0.0, 0.22)
		style.set_border_width_all(1)
		style.border_color = Color(1, 1, 1, 0.05)
	panel.add_theme_stylebox_override("panel", style)
	return panel

## pin_card_footer: make every card in a grid row the same height and put the
## flexible gap just before `before_node_name`, so everything from that node
## down is bottom-aligned across cards regardless of how tall the region above
## it grows. Pass the REFINE divider for processing (so INPUTS floats, but
## REFINE/OUTPUT/footer all line up) or the Button for the simple cards.
func pin_card_footer(card: PanelContainer, before_node_name: String = "Button") -> void:
	if not card: return
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox = card.get_node_or_null("MarginContainer/VBoxContainer")
	if not vbox: return
	var pivot = vbox.get_node_or_null(before_node_name)
	if not pivot:
		pivot = vbox.get_node_or_null("Button")
	if not pivot: return
	if vbox.get_node_or_null("FooterSpacer"): return
	var spacer = Control.new()
	spacer.name = "FooterSpacer"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(0, 2)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)
	vbox.move_child(spacer, pivot.get_index())

# --- MODULE TYPE ICON / DAMAGE-FAMILY (shared by the armory tiles and the
# equipped-slot widgets so they read with one visual language) ---

var _module_icon_cache: Dictionary = {}

func weapon_family(stats: Dictionary) -> String:
	if float(stats.get("atk_cryo", 0)) > 0.0:
		return "cryo"
	if float(stats.get("atk_energy", 0)) > 0.0:
		return "energy"
	if float(stats.get("atk_explosive", 0)) > 0.0:
		return "explosive"
	return "kinetic"

func weapon_family_color(stats: Dictionary) -> Color:
	match weapon_family(stats):
		"cryo": return Color(0.70, 0.95, 1.0)
		"energy": return Color(0.32, 0.80, 1.0)
		"explosive": return Color(1.0, 0.45, 0.30)
		_: return Color(0.92, 0.66, 0.32)

func weapon_family_tag(stats: Dictionary) -> String:
	match weapon_family(stats):
		"cryo": return "CRY"
		"energy": return "NRG"
		"explosive": return "EXP"
		_: return "KIN"

func module_type_icon(slot_type: String, stats: Dictionary) -> Texture2D:
	var key = slot_type
	if slot_type == "weapon":
		key = "weapon_" + weapon_family(stats)
		# Corrosion uses the cryo channel but is tagged exotic — own turret icon.
		if str(stats.get("exotic_element", "")) == "corrosion":
			key = "weapon_corrosion"
	var valid = ["weapon_kinetic", "weapon_energy", "weapon_explosive", "weapon_cryo", "weapon_corrosion",
		"shield", "armor", "engine", "battery", "reactor", "sensor",
		"cooling", "ammo", "consumable"]
	if not (key in valid):
		key = "module"
	if key in _module_icon_cache:
		return _module_icon_cache[key]
	var tex = load("res://assets/icons/modules/%s.svg" % key) as Texture2D
	_module_icon_cache[key] = tex
	return tex

func _process(delta):
	# Global UI animations or packet handling can go here
	pass

# ---------------------------------------------------------------------------
# CardChrome — procedural card "soul" overlay.
#
# A mouse-transparent Control that paints sci-fi panel hardware over the flat
# StyleBox of every card built through apply_card_style(). The motif is chosen
# globally in Sys Config (GameState.game_settings.card_chrome); the accent is
# inherited per-card so all 8 category colours stay coherent. Fully static —
# repaints only on resize or when the player switches styles.
# ---------------------------------------------------------------------------
class CardChrome extends Control:
	var accent: Color = Color(0.216, 0.788, 0.690)
	# Page background, used to mask the holographic octagon corner cuts.
	const _PAGE_BG := Color(0.039, 0.086, 0.078)

	func _ready() -> void:
		UITheme.chrome_changed.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 8.0 or h < 8.0:
			return
		match UITheme.get_card_chrome():
			UITheme.CHROME_HOLOGRAPHIC:
				_draw_holographic(w, h)
			UITheme.CHROME_PRECURSOR:
				_draw_precursor(w, h)
			_:
				_draw_industrial(w, h)

	# --- small shared primitives ------------------------------------------
	func _diamond(c: Vector2, r: float, col: Color) -> void:
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -r), c + Vector2(r, 0),
			c + Vector2(0, r), c + Vector2(-r, 0)]), col)

	func _diamond_outline(c: Vector2, r: float, col: Color, wd: float) -> void:
		draw_polyline(PackedVector2Array([
			c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r),
			c + Vector2(-r, 0), c + Vector2(0, -r)]), col, wd, true)

	# Eight-point octagon tracing a chamfer of size `c`.
	func _octagon(w: float, h: float, c: float) -> PackedVector2Array:
		return PackedVector2Array([
			Vector2(c, 0), Vector2(w - c, 0), Vector2(w, c), Vector2(w, h - c),
			Vector2(w - c, h), Vector2(c, h), Vector2(0, h - c), Vector2(0, c),
			Vector2(c, 0)])

	# --- 01 · Industrial command console ----------------------------------
	func _draw_industrial(w: float, h: float) -> void:
		var a := accent
		# CRT scanline surface — one batched call, very low alpha.
		var scan := PackedVector2Array()
		var sy := 7.0
		while sy < h - 5.0:
			scan.append(Vector2(5, sy))
			scan.append(Vector2(w - 5, sy))
			sy += 4.0
		if not scan.is_empty():
			draw_multiline(scan, Color(1, 1, 1, 0.022), 1.0)

		# Recessed inner hairline frame only (thin — matches the comp).
		var fr := a
		fr.a = 0.18
		draw_rect(Rect2(4, 4, w - 8, h - 8), fr, false, 1.0)

		# Machined L brackets, scaled to the panel so big containers (Storage,
		# Item Details, menu/loading panels) carry the theme as visibly as the
		# small cards. Clamp floor = the original 18px so small cards are
		# unchanged.
		var bl := clampf(min(w, h) * 0.07, 18.0, 44.0)
		_bracket(Vector2(2, 2), 1.0, 1.0, a, bl)
		_bracket(Vector2(w - 2, 2), -1.0, 1.0, a, bl)
		_bracket(Vector2(2, h - 2), 1.0, -1.0, a, bl)
		_bracket(Vector2(w - 2, h - 2), -1.0, -1.0, a, bl)

		# Recessed rivets near the lower corners.
		_rivet(Vector2(13, h - 12))
		_rivet(Vector2(w - 13, h - 12))

	func _bracket(o: Vector2, sx: float, sy: float, col: Color, L: float = 18.0) -> void:
		var f := L / 18.0           # scale factor vs the original 18px unit
		var mw := clampf(2.0 * f, 2.0, 4.0)
		draw_polyline(PackedVector2Array([
			o + Vector2(0, L * sy), o, o + Vector2(L * sx, 0)]), col, mw, true)
		var inner := col
		inner.a *= 0.5
		draw_polyline(PackedVector2Array([
			o + Vector2(5 * f * sx, 13 * f * sy), o + Vector2(5 * f * sx, 5 * f * sy),
			o + Vector2(13 * f * sx, 5 * f * sy)]), inner, clampf(f, 1.0, 2.0), true)

	func _rivet(c: Vector2) -> void:
		draw_circle(c, 3.0, Color(0, 0, 0, 0.5))
		draw_circle(c, 1.6, Color(1, 1, 1, 0.22))

	# --- 02 · Holographic projection --------------------------------------
	func _draw_holographic(w: float, h: float) -> void:
		var a := accent
		var ch := 16.0

		# Cut all four corners with page bg → a true octagon silhouette.
		# Triangles bleed ~3px past the overlay so they also mask the panel's
		# rounded StyleBox corner (radius 5) that sits just outside this rect.
		var b := 3.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(-b, -b), Vector2(ch, -b), Vector2(-b, ch)]), _PAGE_BG)
		draw_colored_polygon(PackedVector2Array([
			Vector2(w - ch, -b), Vector2(w + b, -b), Vector2(w + b, ch)]), _PAGE_BG)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-b, h - ch), Vector2(ch, h + b), Vector2(-b, h + b)]), _PAGE_BG)
		draw_colored_polygon(PackedVector2Array([
			Vector2(w + b, h - ch), Vector2(w + b, h + b), Vector2(w - ch, h + b)]), _PAGE_BG)

		# Outer bloom — stacked octagon strokes following the shape.
		var gg := a
		gg.a = 0.06
		for i in range(1, 4):
			var d := float(i) * 2.0
			# Bloom octagon, expanded outward by d on every side.
			var ring := PackedVector2Array()
			for p in _octagon(w + d * 2.0, h + d * 2.0, ch + d):
				ring.append(p - Vector2(d, d))
			draw_polyline(ring, gg, 2.0, true)

		# Faint dot-mesh fill (one batched call).
		var dm := a
		dm.a = 0.06
		var mesh := PackedVector2Array()
		var my := 18.0
		while my < h - 12.0:
			var mx := 18.0
			while mx < w - 12.0:
				mesh.append(Vector2(mx - 1.5, my))
				mesh.append(Vector2(mx + 1.5, my))
				mesh.append(Vector2(mx, my - 1.5))
				mesh.append(Vector2(mx, my + 1.5))
				mx += 16.0
			my += 16.0
		if not mesh.is_empty():
			draw_multiline(mesh, dm, 1.0)

		# Static "scan band" — soft bright band, reads as a frozen sweep.
		var by := h * 0.40
		for k in range(6):
			var t := float(k)
			var band := a
			band.a = 0.05 * (1.0 - t / 6.0)
			draw_rect(Rect2(ch, by - t * 3.0, w - ch * 2.0, 3.0), band, true)
			draw_rect(Rect2(ch, by + t * 3.0, w - ch * 2.0, 3.0), band, true)

		# Faint inner octagon, inset 4px on every side.
		var g2 := a
		g2.a = 0.2
		var inner := PackedVector2Array()
		for p in _octagon(w - 8, h - 8, ch - 4):
			inner.append(p + Vector2(4, 4))
		draw_polyline(inner, g2, 1.0, true)

		# Outer frame drawn edge-by-edge: dim straight runs, BRIGHT thick
		# chamfer cuts. One clean stroke per edge — the "lit bevel" is the
		# frame itself, so nothing overlaps or wedges at the corners.
		var v0 := Vector2(ch, 0)
		var v1 := Vector2(w - ch, 0)
		var v2 := Vector2(w, ch)
		var v3 := Vector2(w, h - ch)
		var v4 := Vector2(w - ch, h)
		var v5 := Vector2(ch, h)
		var v6 := Vector2(0, h - ch)
		var v7 := Vector2(0, ch)
		var edge := a
		edge.a = 0.45
		var cut := a
		cut.a = 0.95
		draw_line(v0, v1, edge, 1.2)   # straight runs
		draw_line(v2, v3, edge, 1.2)
		draw_line(v4, v5, edge, 1.2)
		draw_line(v6, v7, edge, 1.2)
		draw_line(v7, v0, cut, 2.5)    # lit chamfer cuts
		draw_line(v1, v2, cut, 2.5)
		draw_line(v3, v4, cut, 2.5)
		draw_line(v5, v6, cut, 2.5)

	# --- 03 · Precursor-etched --------------------------------------------
	func _filigree(o: Vector2, sx: float, sy: float, col: Color) -> void:
		# Main chamfered L bracket.
		draw_polyline(PackedVector2Array([
			o + Vector2(2 * sx, 36 * sy), o + Vector2(2 * sx, 14 * sy),
			o + Vector2(14 * sx, 2 * sy), o + Vector2(36 * sx, 2 * sy)]), col, 1.8)
		# Parallel inner groove (lighter — fakes an engraved bevel).
		var groove := col
		groove.a *= 0.45
		draw_polyline(PackedVector2Array([
			o + Vector2(6 * sx, 30 * sy), o + Vector2(6 * sx, 16 * sy),
			o + Vector2(16 * sx, 6 * sy), o + Vector2(30 * sx, 6 * sy)]), groove, 1.2)
		# Hooked flourish + an inlaid node at the elbow.
		draw_polyline(PackedVector2Array([
			o + Vector2(2 * sx, 24 * sy), o + Vector2(11 * sx, 24 * sy),
			o + Vector2(16 * sx, 19 * sy)]), col, 1.4)
		_diamond(o + Vector2(9 * sx, 9 * sy), 2.5, col)

	func _draw_precursor(w: float, h: float) -> void:
		var a := accent
		# Engraved double inner stroke (outer line + lighter offset groove).
		var e1 := a
		e1.a = 0.5
		var e2 := a
		e2.a = 0.2
		draw_rect(Rect2(6, 6, w - 12, h - 12), e1, false, 1.0)
		draw_rect(Rect2(9, 9, w - 18, h - 18), e2, false, 1.0)

		# Angular filigree at all four corners.
		var fc := a
		fc.a = 0.85
		_filigree(Vector2(0, 0), 1.0, 1.0, fc)
		_filigree(Vector2(w, 0), -1.0, 1.0, fc)
		_filigree(Vector2(0, h), 1.0, -1.0, fc)
		_filigree(Vector2(w, h), -1.0, -1.0, fc)

		# Embroidery stitch ticks down both inner side edges.
		var st := a
		st.a = 0.3
		var stitch := PackedVector2Array()
		var ys := 48.0
		while ys < h - 48.0:
			stitch.append(Vector2(12, ys))
			stitch.append(Vector2(16, ys))
			stitch.append(Vector2(w - 12, ys))
			stitch.append(Vector2(w - 16, ys))
			ys += 11.0
		# Skip when the card is too short to fit any stitch ticks — an empty
		# point array makes draw_multiline error out (renderer assert).
		if not stitch.is_empty():
			draw_multiline(stitch, st, 1.0)

		# Inlaid node diamonds (with a ring) at the mid-point of each edge.
		for p in [Vector2(w * 0.5, 4), Vector2(w * 0.5, h - 4),
				Vector2(4, h * 0.5), Vector2(w - 4, h * 0.5)]:
			_diamond(p, 4.0, a)
			_diamond_outline(p, 7.0, e2, 1.0)

		# Etched glyph row along the bottom inner edge: diamond · chevron.
		var gl := a
		gl.a = 0.45
		var gx := 46.0
		var idx := 0
		while gx < w - 46.0:
			if idx % 2 == 0:
				_diamond(Vector2(gx, h - 11), 2.5, gl)
			else:
				draw_polyline(PackedVector2Array([
					Vector2(gx - 3, h - 9), Vector2(gx, h - 13),
					Vector2(gx + 3, h - 9)]), gl, 1.2)
			gx += 15.0
			idx += 1
