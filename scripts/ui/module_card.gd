extends PanelContainer

var mid: String
var data: Dictionary
var count: int = 0
var pulse_tween: Tween
var is_selected: bool = false
var is_draggable: bool = true
var compare_equipped_mid: String = ""

signal clicked(p_mid: String)

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
	_update_ui()

func _on_mouse_enter():
	var sm = GameState.shipyard_manager
	if sm and sm.get("unseen_modules") != null and sm.unseen_modules.get(mid, false):
		sm.unseen_modules.erase(mid)
		_update_ui()

func _update_ui():
	if not is_inside_tree() or data.is_empty():
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
			
	var tile_container = Control.new()
	tile_container.name = "TileVisual"
	var size = 40 # Increased by 25% (32 -> 40)
	custom_minimum_size = Vector2(size, size)
	tile_container.custom_minimum_size = Vector2(size, size)
	tile_container.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var bg_panel = Panel.new()
	bg_panel.custom_minimum_size = Vector2(size, size)


	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.08, 0.95)
	
	# The jagged/glowing highlight based on rarity from user mockup
	if rarity == GameState.shipyard_manager.Rarity.LEGENDARY:
		sb.border_color = Color(0.95, 0.85, 0.2, 1.0)
		sb.shadow_color = Color(0.95, 0.85, 0.2, 0.2) # Lower alpha
	elif rarity == GameState.shipyard_manager.Rarity.RARE:
		sb.border_color = Color(0.2, 0.5, 0.95, 1.0)
		sb.shadow_color = Color(0.2, 0.5, 0.95, 0.2)
	elif rarity == GameState.shipyard_manager.Rarity.UNIQUE:
		sb.border_color = Color(0.8, 0.2, 0.8, 1.0)
		sb.shadow_color = Color(0.8, 0.2, 0.8, 0.2)
	elif rarity == GameState.shipyard_manager.Rarity.UNCOMMON:
		sb.border_color = Color(0.2, 0.8, 0.2, 1.0)
		sb.shadow_color = Color(0.2, 0.8, 0.2, 0.1)
	else:
		sb.border_color = Color(0.4, 0.4, 0.4, 1.0)
		sb.shadow_color = Color(0, 0, 0, 0.0)
		
	# Make it look like a highlighted border
	sb.border_width_left = 2; sb.border_width_top = 2; sb.border_width_right = 2; sb.border_width_bottom = 2;
	sb.set_corner_radius_all(3)
	sb.shadow_size = 5 if rarity >= GameState.shipyard_manager.Rarity.RARE else 0

	
	bg_panel.add_theme_stylebox_override("panel", sb)
	tile_container.add_child(bg_panel)
	
	# Center Letter (W, S, A, etc.)
	var type_char = _get_type_char(slot_type)
	var letter_lbl = Label.new()
	letter_lbl.text = type_char
	letter_lbl.add_theme_font_size_override("font_size", 18) # Was 14
	letter_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	letter_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter_lbl.custom_minimum_size = Vector2(size, size)
	tile_container.add_child(letter_lbl)
	
	# Bottom Right Tier badge — PoE-style iLvl indicator with colored pill background
	var tier_val = _get_item_tier(item_name, m_data)
	if tier_val != "":
		var tier_panel = PanelContainer.new()
		tier_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tier_style = StyleBoxFlat.new()
		tier_style.bg_color = rarity_color.lerp(Color.BLACK, 0.45)
		tier_style.set_corner_radius_all(3)
		tier_style.border_color = rarity_color.lerp(Color.WHITE, 0.15)
		tier_style.set_border_width_all(1)
		tier_style.content_margin_left = 3
		tier_style.content_margin_right = 3
		tier_style.content_margin_top = 0
		tier_style.content_margin_bottom = 0
		tier_panel.add_theme_stylebox_override("panel", tier_style)

		var tier_lbl = Label.new()
		tier_lbl.text = tier_val
		tier_lbl.add_theme_font_size_override("font_size", 9)
		tier_lbl.add_theme_color_override("font_color", rarity_color.lerp(Color.WHITE, 0.55))
		tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tier_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tier_panel.add_child(tier_lbl)

		var tier_margin = MarginContainer.new()
		tier_margin.add_theme_constant_override("margin_right", 2)
		tier_margin.add_theme_constant_override("margin_bottom", 2)
		tier_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tier_margin.custom_minimum_size = Vector2(size, size)

		# Anchor the badge to bottom-right via a container that aligns its child
		var anchor = HBoxContainer.new()
		anchor.alignment = BoxContainer.ALIGNMENT_END
		anchor.custom_minimum_size = Vector2(size, 0)
		anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		anchor.add_child(tier_panel)

		var v_anchor = VBoxContainer.new()
		v_anchor.alignment = BoxContainer.ALIGNMENT_END
		v_anchor.custom_minimum_size = Vector2(size, size)
		v_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v_anchor.add_child(anchor)
		tile_container.add_child(v_anchor)

	# Top Right comparison chevron — surfaces upgrade/downgrade at a glance
	# (Detailed deltas are still in the tooltip; this is the scan-mode cue.)
	var cmp = _compute_compare_summary()
	if cmp != "":
		var cmp_lbl = Label.new()
		cmp_lbl.text = cmp
		cmp_lbl.add_theme_font_size_override("font_size", 12)
		var cmp_color = Color(0.45, 1.00, 0.55) if cmp == "▲" else (Color(1.00, 0.40, 0.40) if cmp == "▼" else Color(0.85, 0.85, 0.85))
		cmp_lbl.add_theme_color_override("font_color", cmp_color)
		cmp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var cmp_margin = MarginContainer.new()
		cmp_margin.add_theme_constant_override("margin_right", 2)
		cmp_margin.add_theme_constant_override("margin_top", -2)
		cmp_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var cmp_anchor = HBoxContainer.new()
		cmp_anchor.alignment = BoxContainer.ALIGNMENT_END
		cmp_anchor.custom_minimum_size = Vector2(size, 0)
		cmp_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cmp_anchor.add_child(cmp_lbl)

		var cmp_v = VBoxContainer.new()
		cmp_v.alignment = BoxContainer.ALIGNMENT_BEGIN
		cmp_v.custom_minimum_size = Vector2(size, size)
		cmp_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cmp_v.add_child(cmp_anchor)
		tile_container.add_child(cmp_v)



	
	# Count badge if Stacked (Top Left Corner Badge)
	if count > 1:
		var badge_bg = ColorRect.new()
		badge_bg.color = Color(0, 0, 0, 0.6)
		badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		var count_lbl = Label.new()
		count_lbl.text = str(count)
		count_lbl.add_theme_font_size_override("font_size", 8) # Was 6
		count_lbl.add_theme_color_override("font_color", Color(0.7, 1.0, 1.0))
		
		var text_size = count_lbl.get_theme_font("font").get_string_size(count_lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
		badge_bg.custom_minimum_size = Vector2(text_size.x + 4, 12)
		badge_bg.position = Vector2(2, 2)
		
		count_lbl.position = Vector2(2, -1)
		badge_bg.add_child(count_lbl)
		tile_container.add_child(badge_bg)

	# Unseen indicator (Yellow Orb)
	var sm = GameState.shipyard_manager
	if sm and sm.get("unseen_modules") != null and sm.unseen_modules.get(mid, false):
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
		tile_container.add_child(orb)

	# Selection Highlight (Cyan Glow)
	if is_selected:
		var selection_panel = Panel.new()
		selection_panel.custom_minimum_size = Vector2(size, size)
		selection_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ssb = StyleBoxFlat.new()
		ssb.bg_color = Color(0, 0, 0, 0)
		ssb.set_border_width_all(3)
		ssb.border_color = Color(0, 1.0, 1.0, 0.8) # Cyan
		ssb.set_corner_radius_all(3)
		ssb.shadow_color = Color(0, 1.0, 1.0, 0.4)
		ssb.shadow_size = 6
		selection_panel.add_theme_stylebox_override("panel", ssb)
		tile_container.add_child(selection_panel)

	# Overrides to original card layout
	var empty_style = StyleBoxEmpty.new()
	add_theme_stylebox_override("panel", empty_style)
	_apply_pulse(rarity)
	
	add_child(tile_container)
	if sm and mid in sm.modules:
		var status = sm.can_equip_module(mid)
		UITheme.apply_locked_overlay(self, item_name, status["reason"], not status["can_equip"])
	else:
		UITheme.apply_locked_overlay(self, item_name, "", false)

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
	var dmg := float(stats.get("atk_kinetic", 0)) + float(stats.get("atk_energy", 0)) + float(stats.get("atk_explosive", 0))
	var interval := maxf(0.01, float(stats.get("atk_interval", 2.5)))
	return dmg / interval

# Mirrors combat_manager's weapon-type rule so the compare chevron only
# appears between like-for-like damage types.
func _weapon_type(stats: Dictionary) -> String:
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
			
	var gem_container = Control.new()
	gem_container.name = "GemVisual"
	var grid_size = 40 # Match the module tile size for grid alignment
	var visual_size = 25 # The specific size requested for the core visual
	custom_minimum_size = Vector2(grid_size, grid_size)
	gem_container.custom_minimum_size = Vector2(grid_size, grid_size)
	gem_container.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var sock_bg = Panel.new()
	var size = 15 # Diamond size
	sock_bg.custom_minimum_size = Vector2(size, size)
	sock_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb = StyleBoxFlat.new()
	var g_color = _get_gem_color(gem_name)

	
	sb.bg_color = g_color
	sb.border_width_left = 1; sb.border_width_top = 1; sb.border_width_right = 1; sb.border_width_bottom = 1;
	sb.border_color = g_color.lightened(0.5)
	sb.shadow_color = g_color * Color(1, 1, 1, 0.45)
	sb.shadow_size = 4
	
	sock_bg.add_theme_stylebox_override("panel", sb)
	sock_bg.pivot_offset = Vector2(size / 2.0, size / 2.0)
	sock_bg.rotation_degrees = 45
	
	# Center the diamond within the 40x40 grid cell
	sock_bg.position = Vector2((grid_size - size) / 2.0, (grid_size - size) / 2.0)
	
	if count > 1:
		var badge_bg = ColorRect.new()
		badge_bg.color = Color(0, 0, 0, 0.6)
		# Position badge relative to the visual_size or just top-left of the 40x40
		badge_bg.position = Vector2(6, 6) 
		
		var count_lbl = Label.new()
		count_lbl.text = str(count)
		count_lbl.add_theme_font_size_override("font_size", 8)
		count_lbl.add_theme_color_override("font_color", Color(0.7, 1.0, 1.0))
		
		var text_size = count_lbl.get_theme_font("font").get_string_size(count_lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
		badge_bg.custom_minimum_size = Vector2(text_size.x + 2, 10)
		count_lbl.position = Vector2(1, -1)
		
		badge_bg.add_child(count_lbl)
		gem_container.add_child(badge_bg)

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
		selection_panel.custom_minimum_size = Vector2(grid_size, grid_size)
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
	
	gem_container.add_child(sock_bg)
	add_child(gem_container)
	
	# Small glow tween to make the core feel alive
	var glow_tween = create_tween().set_loops()
	glow_tween.tween_property(sock_bg, "modulate", Color(1.2, 1.2, 1.2), 1.5).set_trans(Tween.TRANS_SINE)
	glow_tween.tween_property(sock_bg, "modulate", Color(0.9, 0.9, 0.9), 1.5).set_trans(Tween.TRANS_SINE)


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
		var dmg = stats.get("atk_kinetic", 0) + stats.get("atk_energy", 0) + stats.get("atk_explosive", 0)
		var interval = max(0.01, float(stats.get("atk_interval", 2.5)))
		lines.append("DPS: %.1f" % (float(dmg) / interval))
		
		# v87.0: Damage Type Strong/Weak (Condensed)
		if stats.get("atk_kinetic", 0) > 0: lines.append("KIN - Strong vs Hull, Weak vs Shield")
		if stats.get("atk_energy", 0) > 0: lines.append("NRG - Strong vs Shield, Bypasses Armor")
		if stats.get("atk_explosive", 0) > 0: lines.append("EXP - Bypasses Armor, Slower Fire")

	var keys = stats.keys()
	keys.sort()
	
	var ga_list = data.get("greater_affixes", [])
	
	for key in keys:
		if key == "atk_interval":
			continue
		var val = stats[key]
		if key == "energy_load" and val == 0:
			continue
		var label = FormatUtils.format_stat_label(key)
		var ga_prefix = "[color=#ffcc00]★[/color] " if key in ga_list else ""
		lines.append("%s%s: %s" % [ga_prefix, label, FormatUtils.format_stat_value(key, val)])
		if lines.size() >= 5: # Increased limit slightly
			break

	if lines.is_empty():
		if slot_type == "gem":
			return data.get("desc", "No combat modifiers")
		return "No combat modifiers"
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
	if "Topaz" in gem_name: return Color("#ffcc00")
	if "Amethyst" in gem_name: return Color("#aa44ff")
	return Color("#b548b5") # Default purple

func _apply_pulse(rarity: int):
	_stop_pulse()
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
			clicked.emit(mid)

func _show_demolish_menu():
	var sm = GameState.shipyard_manager
	if not sm or mid not in sm.modules:
		return

	var in_storage = sm.module_inventory.get(mid, 0)
	if in_storage <= 0:
		UITheme.show_notification("Cannot demolish equipped module", Color.RED)
		return

	var price = sm.get_sell_price(mid)
	var parts = sm.get_demolish_parts(mid)
	
	var popup = PopupMenu.new()
	popup.add_item("Demolish (%s credits, %s parts)" % [UITheme.format_num(price), parts], 0)
	popup.add_separator()
	popup.add_item("Cancel", 1)
	add_child(popup)

	popup.id_pressed.connect(func(id):
		if id == 0 and sm.demolish_module(mid):
			var rarity = sm.get_module_rarity(mid)
			var rarity_color = sm.RARITY_COLORS.get(rarity, Color.WHITE)
			UITheme.show_notification("Demolished for %s credits & %s parts" % [UITheme.format_num(price), parts], rarity_color)
		popup.queue_free()
	)
	popup.popup(Rect2i(get_global_mouse_position(), Vector2i(1, 1)))

func _make_custom_tooltip(_for_text: String) -> Control:
	if data.is_empty():
		return null

	var sm = GameState.shipyard_manager
	var rarity = _get_module_rarity_safe(sm)
	var rarity_color = _get_rarity_color_safe(sm, rarity)

	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.03, 0.98)
	style.border_color = rarity_color
	style.border_color.a = 0.85
	style.set_border_width_all(2)
	style.border_width_top = 5
	style.set_corner_radius_all(3)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)

	var rtl = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.custom_minimum_size = Vector2(340, 0)
	rtl.add_theme_color_override("default_color", Color(0.92, 0.90, 0.86))
	rtl.text = _build_comparison_tooltip_bbcode()
	panel.add_child(rtl)
	return panel

func _build_comparison_tooltip_bbcode() -> String:
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
	var div = "[color=#3d3d3d]-------------------------------[/color]\n"

	tt += "[b][color=#%s]%s[/color][/b]\n" % [rarity_color_hex, display_name]
	tt += "[font_size=10][color=gray]%s %s[/color][/font_size]\n" % [rarity_label, slot_type.capitalize()]
	
	var durability = int(data.get("durability", 100))
	var dur_col = "green"
	if durability <= 25: dur_col = "red"
	elif durability <= 50: dur_col = "orange"
	elif durability <= 75: dur_col = "yellow"
	tt += "[font_size=10][color=gray]Durability:[/color] [color=%s]%d/100[/color][/font_size]\n" % [dur_col, durability]
		
	tt += div

	var my_stats = data.get("stats", {})
	if slot_type == "weapon":
		var dmg = my_stats.get("atk_kinetic", 0) + my_stats.get("atk_energy", 0) + my_stats.get("atk_explosive", 0)
		var interval = max(0.01, float(my_stats.get("atk_interval", 2.5)))
		var dps = float(dmg) / interval
		tt += "[font_size=20][b]%.1f DPS[/b][/font_size]\n" % dps
		tt += "[font_size=9][color=gray]%s total damage, %.2f hits/s[/color][/font_size]\n" % [UITheme.format_num(dmg), 1.0 / interval]
		
		# v87.0: Damage Type Strong/Weak (Rich BBCode)
		if my_stats.get("atk_kinetic", 0) > 0: 
			tt += "[color=#99ccff][b]KINETIC[/b][/color]\n"
			tt += "[color=green]  + Strong: Hull (+20%)[/color]\n"
			tt += "[color=red]  - Weak: Shield (-50%)[/color]\n"
		if my_stats.get("atk_energy", 0) > 0:
			tt += "[color=#ffe64d][b]ENERGY[/b][/color]\n"
			tt += "[color=green]  + Strong: Shield (+50%), Armor Bypass[/color]\n"
			tt += "[color=red]  - Weak: Hull (-10%)[/color]\n"
		if my_stats.get("atk_explosive", 0) > 0:
			tt += "[color=#ff804d][b]EXPLOSIVE[/b][/color]\n"
			tt += "[color=green]  + Strong: Armor Bypass (80% pen)[/color]\n"
			tt += "[color=red]  - Weak: Slower fire rate[/color]\n"
			
		tt += div
	elif slot_type == "ammo":
		tt += "[font_size=14][b]%s[/b][/font_size]\n" % _build_ammo_card_stats()
		tt += div
	elif slot_type == "consumable":
		var heal_pct = int(round(data.get("heal_pct", data.get("stats", {}).get("heal_pct", 0.0)) * 100.0))
		var target = data.get("consumable_type", "hull")
		tt += "[font_size=16][b]Restores %d%% %s[/b][/font_size]\n" % [heal_pct, target.capitalize()]
		tt += div
	elif slot_type == "shield":
		var val = my_stats.get("max_shield", 0)
		tt += "[font_size=20][b]%s[/b][/font_size] [font_size=10][color=gray]Shield Capacity[/color][/font_size]\n" % UITheme.format_num(val)
		tt += div
	elif slot_type == "armor":
		var val = my_stats.get("hp", 0)
		tt += "[font_size=20][b]%s[/b][/font_size] [font_size=10][color=gray]Integrity Reinforcement[/color][/font_size]\n" % UITheme.format_num(val)
		tt += div
	elif slot_type == "gem":
		var gem_desc = data.get("desc", ElementDB.get_element_description(mid))
		tt += "[font_size=14][b]%s[/b][/font_size]\n" % gem_desc
		tt += div

	var equipped_mid = ""
	var equipped_stats = {}
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
		if key == "energy_load" and val == 0:
			continue
		if slot_type == "weapon" and key in ["atk_kinetic", "atk_energy", "atk_explosive"]:
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
					range_info = " [color=gray][font_size=9][%s-%s][/font_size][/color]" % [
						FormatUtils.format_stat_value(key, r_min),
						FormatUtils.format_stat_value(key, r_max)
					]

		var line = "%s: %s%s" % [label, val_str, range_info]
		if equipped_mid != "" and equipped_mid != mid and key != "energy_load":
			var diff = val - equipped_stats.get(key, 0)
			if diff > 0:
				line += " [color=lime](+%s)[/color]" % FormatUtils.format_stat_value(key, diff)
			elif diff < 0:
				line += " [color=red](%s)[/color]" % FormatUtils.format_stat_value(key, diff)
		tt += "%s\n" % line

	var affixes = data.get("affixes", {})
	var ga_list = data.get("greater_affixes", [])
	
	if sm and affixes.size() > 0:
		tt += div
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
					range_str = " [color=gray][font_size=9][%d-%d][/font_size][/color]" % [int(s_range[0]), int(s_range[1])]
				else:
					val_str = "%d%%" % int(val_raw * 100)
					range_str = " [color=gray][font_size=9][%d-%d]%%[/font_size][/color]" % [int(s_range[0] * 100), int(s_range[1] * 100)]
				
				var desc_val = 0
				if scaling == "flat" or scaling == "linear_tier":
					desc_val = int(val_raw)
				else:
					desc_val = int(val_raw * 100)

				var desc = cfg["desc"] % desc_val

				if is_ga:
					tt += "[color=#ffcc00][b] GREATER[/b][/color]  [color=#ffdd44][b]%s[/b][/color]%s\n" % [desc, range_str]
				else:
					tt += "[color=#8fc5ff]◆ %s[/color]%s\n" % [desc, range_str]

	if data.has("sockets"):
		tt += div
		for gem in data["sockets"]:
			if gem:
				var g_name = ElementDB.get_display_name(gem)
				var g_desc = ElementDB.get_element_description(gem)
				var g_hex = _get_gem_color(g_name).to_html(false)
				if g_desc != "":
					tt += "[color=#%s]%s: %s[/color]\n" % [g_hex, g_name, g_desc]
				else:
					tt += "[color=#%s]%s[/color]\n" % [g_hex, g_name]
			else:
				tt += "[color=#444444]Empty Socket[/color]\n"

	if sm and mid in sm.modules:
		tt += div
		tt += "[font_size=10][color=gray]Sell Value:[/color] [color=#e0b150]%s credits[/color][/font_size]" % UITheme.format_num(sm.get_sell_price(mid))

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
			
			tt += "[b][color=#00ffff]SET: %s[/color][/b]\n" % set_info["name"].to_upper()
			tt += "[font_size=10][color=gray]%d / %d pieces equipped[/color][/font_size]\n" % [count, total]
			
			for bonus_key in set_info["bonus"]:
				var val = set_info["bonus"][bonus_key]
				var b_name = bonus_key.replace("_pct", "").replace("_flat", "").replace("_", " ").to_upper()
				var val_str = "+%d%%" % val if ("_pct" in bonus_key or "crit" in bonus_key) else "+%d" % val
				
				var col = "#ffffff" if active else "#666666"
				tt += "[color=%s]%s: %s[/color]\n" % [col, b_name, val_str]

	return tt

func _get_drag_data(_at_position: Vector2) -> Variant:
	if not is_draggable or data.is_empty() or mid == "":
		return null

	var slot_type = data.get("slot_type", "")
	var dtype = "module"
	if slot_type == "ammo":
		dtype = "ammo"
	elif slot_type == "consumable":
		dtype = "consumable"

	var drag_data = {
		"type": dtype,
		"mid": mid,
		"ammo_id": mid,
		"slot_type": slot_type,
		"consumable_type": data.get("consumable_type", ""),
	}

	var preview = load("res://scenes/ui/module_card.tscn").instantiate()
	preview.setup(mid, data, count)

	var preview_container = Control.new()
	preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_container.add_child(preview)
	
	preview.scale = Vector2(1.0, 1.0)
	preview.modulate.a = 0.96
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shadow = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.45)
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 8)
	shadow.add_theme_stylebox_override("panel", style)
	
	var p_size = custom_minimum_size
	shadow.custom_minimum_size = p_size

	preview_container.add_child(shadow)
	preview_container.move_child(shadow, 0)
	
	preview.position = -p_size / 2.0
	shadow.position = -p_size / 2.0

	var queue = [preview_container]
	while queue.size() > 0:
		var n = queue.pop_front()
		if n is Control:
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue.append_array(n.get_children())

	set_drag_preview(preview_container)

	return drag_data

func _can_drop_data(at_position: Vector2, p_data: Variant) -> bool:
	var p = get_parent()
	if p and p.has_method("_can_drop_data"):
		return p._can_drop_data(at_position, p_data)
	return false

func _drop_data(at_position: Vector2, p_data: Variant) -> void:
	var p = get_parent()
	if p and p.has_method("_drop_data"):
		p._drop_data(at_position, p_data)
