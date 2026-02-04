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
	UITheme.apply_progress_bar_style(prog_bar, "engineering")
	
	# Input text is handled dynamically in update_state for coloring
	in_lbl.text = ""
	
	var out_str = "[center]"
	var rates = manager.get_current_rate() if manager.is_active and manager.current_recipe_id == rid else {}
	
	if "output" in recipe:
		for item in recipe["output"]:
			var display_name = ElementDB.get_display_name(item)
			var qty = recipe["output"][item]
			var line = "%s %s" % [FormatUtils.format_number(qty), display_name]
			
			if item in rates:
				out_str += "%s [color=#55ff55](%s/m)[/color]\n" % [line, FormatUtils.format_number(rates[item])]
			else:
				out_str += "%s\n" % line
				
	out_str += "[/center]"
	out_lbl.text = out_str.strip_edges()

func _on_button_pressed():
	if manager.is_active and manager.current_recipe_id == rid:
		manager.stop_action()
	else:
		GameState.set_active_manager(manager)
		manager.start_action(rid)
	parent_ui.update_ui()

func update_state():
	var is_this_active = (manager.is_active and manager.current_recipe_id == rid)
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
		prog_bar.value = prog
		time_lbl.text = "%s / %s" % [FormatUtils.format_time(manager.action_progress), FormatUtils.format_time(effective_duration)]
	else:
		prog_bar.value = 0
		time_lbl.text = "0.0s / %s" % (FormatUtils.format_time(recipe["duration"] / manager.get_recipe_speed_multiplier(rid)))
		modulate = Color(1, 1, 1)
		
		if not has_research:
			var tech_name = GameState.research_manager.tech_tree.get(recipe["research_req"], {}).get("name", "Unknown Tech")
			UITheme.apply_locked_overlay(self, recipe["name"], "RESEARCH: %s" % tech_name, true)
			btn.text = "Research Required"
			btn.disabled = true
		elif not has_level:
			UITheme.apply_locked_overlay(self, recipe["name"], "LEVEL %d REQUIRED" % lvl_req, true)
			btn.text = "Requires Lv %d" % lvl_req
			btn.disabled = true
		elif not has_ingredients:
			UITheme.apply_locked_overlay(self, recipe["name"], "", false)
			btn.text = "Missing Materials"
			btn.disabled = true
		else:
			UITheme.apply_locked_overlay(self, recipe["name"], "", false)
			btn.text = "Start"
			btn.disabled = false
