extends PanelContainer

var rid: String
var recipe: Dictionary
var manager: RefCounted
var parent_ui: Node

@onready var name_lbl = $MarginContainer/VBoxContainer/NameLabel
@onready var lvl_lbl = $MarginContainer/VBoxContainer/LevelLabel
@onready var in_lbl = $MarginContainer/VBoxContainer/InputLabel
@onready var out_lbl = $MarginContainer/VBoxContainer/OutputLabel
@onready var btn = $MarginContainer/VBoxContainer/Button
@onready var prog_bar = $MarginContainer/VBoxContainer/ProgressBar
@onready var time_lbl = $MarginContainer/VBoxContainer/TimeLabel

# P1 Mastery — compact readout under the output block: caption row +
# thin progress bar. Built once in setup(), refreshed in update_state().
var _mastery_left_lbl: Label
var _mastery_right_lbl: Label
var _mastery_bar: ProgressBar

func setup(p_rid: String, p_data: Dictionary, p_manager, p_parent):
	rid = p_rid
	recipe = p_data
	manager = p_manager
	parent_ui = p_parent
	
	name_lbl.text = recipe["name"]
	name_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["engineering"])
	lvl_lbl.text = "Lvl %d" % recipe.get("level_req", 1)
	
	UITheme.apply_card_style(self, "engineering")
	UITheme.apply_premium_button_style(btn, "engineering")
	prog_bar.accent = UITheme.CATEGORY_COLORS["engineering"]

	# Input text is handled dynamically in update_state for coloring
	in_lbl.text = ""

	# Output text is handled dynamically in update_state for multipliers
	out_lbl.text = ""

	# Themed "work order" card: crucible-motif backdrop + icon header, with a
	# clear input -> (transform) -> output flow. Inputs recede, output pops.
	var glyph = load("res://assets/cursors/pages/processing.svg") as Texture2D
	UITheme.inject_activity_header(self, "engineering", glyph)
	UITheme.wrap_in_io_panel(in_lbl, "engineering", "input")
	var out_panel = UITheme.wrap_in_io_panel(out_lbl, "engineering", "output")
	# Gap sits above REFINE: INPUTS anchors under the header, while
	# REFINE / OUTPUT / footer stay bottom-aligned across cards.
	UITheme.pin_card_footer(self, "ArrowLabel")

	var arrow = $MarginContainer/VBoxContainer.get_node_or_null("ArrowLabel")
	if arrow:
		arrow.text = "▼ REFINE ▼"
		arrow.add_theme_font_size_override("font_size", 9)
		arrow.add_theme_color_override("font_color",
			UITheme.CATEGORY_COLORS["engineering"].lightened(0.2))

	# Mastery panel sits directly under the OUTPUT panel.
	var card_vbox = $MarginContainer/VBoxContainer
	var after_idx = (out_panel.get_index() + 1) if out_panel else card_vbox.get_child_count()
	var mp = UITheme.build_mastery_panel(card_vbox, after_idx, "engineering")
	_mastery_left_lbl = mp["left"]
	_mastery_right_lbl = mp["right"]
	_mastery_bar = mp["bar"]

func _on_button_pressed():
	if GameState.combat_manager and GameState.combat_manager.in_combat:
		return
	if manager.is_active and manager.current_recipe_id == rid:
		manager.stop_action()
	else:
		GameState.set_active_manager(manager)
		manager.start_action(rid)
	parent_ui.update_ui()

func _refresh_mastery():
	if not _mastery_bar or not manager:
		return
	var level = manager.get_mastery_level(rid)
	var prog = manager.get_mastery_progress(rid)
	var in_lvl = int(prog["in_level"])
	var needed = int(prog["needed"])
	if needed < 1:
		needed = 1
	var pct = float(in_lvl) / float(needed) * 100.0
	if pct < 0.0: pct = 0.0
	if pct > 100.0: pct = 100.0

	var col_dim = Color(0.48, 0.45, 0.41)
	var col_mid = Color(0.72, 0.65, 0.45)
	var col_bright = Color(0.83, 0.69, 0.22)
	var col_gold = Color(1.0, 0.84, 0.20)

	if level >= 100:
		_mastery_left_lbl.text = "★ GOLD MASTERY"
		_mastery_right_lbl.text = "LV 100"
		_mastery_left_lbl.add_theme_color_override("font_color", col_gold)
		_mastery_right_lbl.add_theme_color_override("font_color", col_gold)
		_mastery_bar.value = 100.0
		name_lbl.add_theme_color_override("font_color", col_gold)
	elif level >= 50:
		_mastery_left_lbl.text = "✦ MASTERY  LV %d" % level
		_mastery_right_lbl.text = "%d / %d" % [in_lvl, needed]
		_mastery_left_lbl.add_theme_color_override("font_color", col_bright)
		_mastery_right_lbl.add_theme_color_override("font_color", col_bright)
		_mastery_bar.value = pct
	elif level > 0:
		_mastery_left_lbl.text = "MASTERY  LV %d" % level
		_mastery_right_lbl.text = "%d / %d" % [in_lvl, needed]
		_mastery_left_lbl.add_theme_color_override("font_color", col_mid)
		_mastery_right_lbl.add_theme_color_override("font_color", col_mid)
		_mastery_bar.value = pct
	else:
		_mastery_left_lbl.text = "MASTERY  LV 0"
		_mastery_right_lbl.text = "%d / %d" % [in_lvl, needed]
		_mastery_left_lbl.add_theme_color_override("font_color", col_dim)
		_mastery_right_lbl.add_theme_color_override("font_color", col_dim)
		_mastery_bar.value = pct

func update_state():
	var is_this_active = (manager.is_active and manager.current_recipe_id == rid)
	_refresh_mastery()
	var has_ingredients = true # Will be re-evaluated per item
	
	# Rebuild Ingredient String with Colors
	# We do this every update to reflect real-time amounts
	var in_str = "[center]"
	var inputs = recipe.get("input", {})
	var missing_any = false
	
	if inputs.is_empty():
		in_str += "None\n"
	else:
		for item in inputs:
			var req_qty = inputs[item]
			var avail_qty = GameState.resources.get_element_amount(item)
			var color = "gray" 
			
			if avail_qty >= req_qty:
				color = "lime"
			else:
				missing_any = true
				
			in_str += "[color=%s]%s %s[/color]\n" % [color, FormatUtils.format_number(req_qty), ElementDB.get_display_name(item)]
	
	in_str += "[/center]"
	in_lbl.text = in_str
	
	has_ingredients = not missing_any
	
	# Rebuild Output String with Multipliers
	var out_str = "[center]"
	var rates = manager.get_current_rate() if is_this_active else {}
	
	var eff_mult = 1.0
	if GameState.research_manager:
		eff_mult = GameState.research_manager.get_efficiency_multiplier()
		
	if "output" in recipe:
		for item in recipe["output"]:
			var display_name = ElementDB.get_display_name(item)
			var qty = recipe["output"][item]
			
			# BBCode url structure to catch hovers (similar to research smart links)
			var meta_json = JSON.stringify({"id": item, "type": "item"})
			var link_text = "[url=%s][color=#ffce5c][u]%s[/u][/color][/url]" % [meta_json, display_name]
			
			# Apply Efficiency Multiplier to displayed output
			var line = "%s %s" % [FormatUtils.format_number(qty * eff_mult), link_text]
			
			if item in rates:
				out_str += "%s [color=#55ff55](%s/m)[/color]\n" % [line, FormatUtils.format_number(rates[item])]
			else:
				out_str += "%s\n" % line
	out_str += "[/center]"
	out_lbl.bbcode_enabled = true
	out_lbl.text = out_str.strip_edges()
	
	var lvl_req = recipe.get("level_req", 1)
	var has_level = manager.get_level() >= lvl_req
	
	# Research Check
	var has_research = true
	if "research_req" in recipe:
		if GameState.research_manager:
			has_research = GameState.research_manager.is_tech_unlocked(recipe["research_req"])
	
	if is_this_active:
		UITheme.apply_locked_overlay(self, recipe["name"], "", false)
		btn.text = "Stop"
		btn.disabled = false
		modulate = Color(1.2, 1, 1)
		
		var speed_mult = manager.get_recipe_speed_multiplier(rid)
		var effective_duration = recipe["duration"] / speed_mult
		var prog = (manager.action_progress / effective_duration) * 100.0
		prog_bar.active = true
		prog_bar.value = prog
		time_lbl.text = "%s / %s" % [FormatUtils.format_time(manager.action_progress), FormatUtils.format_time(effective_duration)]
	else:
		prog_bar.active = false
		prog_bar.value = 0
		time_lbl.text = "0.0s / %s" % (FormatUtils.format_time(recipe["duration"] / manager.get_recipe_speed_multiplier(rid)))
		modulate = Color(1, 1, 1)
		
		if not has_research:
			var tech_name = GameState.research_manager.tech_tree.get(recipe["research_req"], {}).get("name", "Unknown Tech")
			UITheme.apply_locked_overlay(self, recipe["name"], "RESEARCH: %s" % tech_name, true, recipe["research_req"], "engineering")
			btn.text = "Research Required"
			btn.disabled = true
		elif not has_level:
			UITheme.apply_locked_overlay(self, recipe["name"], "LEVEL %d REQUIRED" % recipe["level_req"], true, "", "engineering")
			btn.text = "Requires Lv %d" % lvl_req
			btn.disabled = true
		elif not has_ingredients:
			UITheme.apply_locked_overlay(self, recipe["name"], "", false)
			btn.text = "Missing Materials"
			btn.disabled = true
		elif GameState.combat_manager and GameState.combat_manager.in_combat:
			UITheme.apply_locked_overlay(self, recipe["name"], "", false)
			btn.text = "IN COMBAT"
			btn.disabled = true
			btn.modulate = Color(1.0, 0.35, 0.35, 0.8)
			modulate = Color(0.85, 0.85, 0.85)
		else:
			UITheme.apply_locked_overlay(self, recipe["name"], "", false)
			btn.text = "Start"
			btn.disabled = false

# ────────────────────────────────────────────────────────────
# META HOVER (Info Card Tooltip)
# ────────────────────────────────────────────────────────────

var _active_info_card = null
var info_card_scene = preload("res://scenes/ui/info_card.tscn")

func _ready():
	out_lbl.meta_hover_started.connect(_on_meta_hover)
	out_lbl.meta_hover_ended.connect(_on_meta_exit)

func _on_meta_hover(meta):
	if _active_info_card: _active_info_card.queue_free()
	
	var m_data = JSON.parse_string(str(meta))
	if not m_data: return
	
	var card = info_card_scene.instantiate()
	
	# Add to ModalLayer to avoid container stretching
	var main = get_tree().current_scene
	var modal_layer = main.get_node_or_null("ModalLayer")
	if modal_layer:
		modal_layer.add_child(card)
	else:
		main.add_child(card)
		
	card.setup(m_data["id"], m_data["type"])
	_active_info_card = card
	
	var mpos = get_global_mouse_position()
	card.global_position = mpos + Vector2(20, 20)
	
	# Keep on screen bounds
	var viewport = get_viewport_rect().size
	var card_size = Vector2(220, 100)
	if card.size.x > 0: card_size = card.size
	
	if card.global_position.x + card_size.x > viewport.x:
		card.global_position.x = mpos.x - card_size.x - 20
	if card.global_position.y + card_size.y > viewport.y:
		card.global_position.y = mpos.y - card_size.y - 20

func _on_meta_exit(meta):
	if _active_info_card:
		_active_info_card.queue_free()
		_active_info_card = null
