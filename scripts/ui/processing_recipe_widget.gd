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
var _mastery_left_lbl: RichTextLabel    # v109: bbcode so the MASTERY keyword
										# can be underlined as the hover hint.
var _mastery_right_lbl: Label
var _mastery_bar: ProgressBar
# v107: hover-popup info card. Created on mouse_entered, freed on _exited
# or tree_exiting (handles widget destroy mid-hover so no orphan stays).
var _mastery_info_card: Control = null

# v122 PERF: update_state() runs every frame (page _process). Guard the
# expensive per-frame RichTextLabel rebuilds (inputs / outputs / mastery) and
# the locked overlay so they only run when their inputs change; the progress
# bar + time still update every frame. Kills the BBCode-reparse stutter.
var _in_sig: String = ""
var _out_sig: String = ""
var _mastery_sig: String = ""
var _state_sig: String = ""

func setup(p_rid: String, p_data: Dictionary, p_manager, p_parent):
	rid = p_rid
	recipe = p_data
	manager = p_manager
	parent_ui = p_parent
	
	name_lbl.text = recipe["name"]
	name_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["engineering"])
	lvl_lbl.text = tr("Lvl %d") % recipe.get("level_req", 1)
	
	UITheme.apply_card_style(self, "engineering")
	UITheme.apply_premium_button_style(btn, "engineering")
	prog_bar.accent = UITheme.CATEGORY_COLORS["engineering"]

	# Input text is handled dynamically in update_state for coloring
	in_lbl.text = ""

	# Output text is handled dynamically in update_state for multipliers
	out_lbl.text = ""

	# Themed "work order" card: crucible-motif backdrop + icon header, with a
	# clear input -> (transform) -> output flow. Inputs recede, output pops.
	var glyph = load("res://assets/icons/glyphs/processing.svg") as Texture2D
	UITheme.inject_activity_header(self, "engineering", glyph)
	UITheme.wrap_in_io_panel(in_lbl, "engineering", "input")
	var out_panel = UITheme.wrap_in_io_panel(out_lbl, "engineering", "output")
	# Gap sits above REFINE: INPUTS anchors under the header, while
	# REFINE / OUTPUT / footer stay bottom-aligned across cards.
	UITheme.pin_card_footer(self, "ArrowLabel")

	var arrow = $MarginContainer/VBoxContainer.get_node_or_null("ArrowLabel")
	if arrow:
		arrow.text = tr("▼ REFINE ▼")
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
	# v107: Hovering the "MASTERY" keyword (LEFT label) opens a styled info
	# card via UITheme.show_info_card. Bar + RIGHT label stay non-interactive
	# so the keyword IS the affordance. Lifecycle: freed on mouse_exited
	# and on widget tree_exiting (handles destroy-while-hovering).
	# Godot 4 quirk: Label.mouse_filter defaults to IGNORE → no hover events
	# fire. Set to PASS so the label captures hover but clicks still go
	# through to the underlying card / button.
	_mastery_left_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	_mastery_left_lbl.mouse_entered.connect(_on_mastery_hover_enter)
	_mastery_left_lbl.mouse_exited.connect(_on_mastery_hover_exit)
	tree_exiting.connect(_free_mastery_info_card)

func _on_mastery_hover_enter() -> void:
	if _mastery_info_card and is_instance_valid(_mastery_info_card):
		return
	_mastery_info_card = UITheme.show_info_card(_mastery_left_lbl, "MASTERY", UITheme.get_mastery_tooltip())

func _on_mastery_hover_exit() -> void:
	_free_mastery_info_card()

func _free_mastery_info_card() -> void:
	if _mastery_info_card and is_instance_valid(_mastery_info_card):
		_mastery_info_card.queue_free()
	_mastery_info_card = null

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
	var level: int = manager.get_mastery_level(rid)
	var prog: Dictionary = manager.get_mastery_progress(rid)
	var in_lvl: int = int(prog["in_level"])
	var needed: int = int(prog["needed"])
	if needed < 1:
		needed = 1
	var pct: float = clamp(float(in_lvl) / float(needed) * 100.0, 0.0, 100.0)

	# v107: Current cumulative bonus + next-milestone teaser, so the system
	# explains itself at a glance instead of being a silent progress bar.
	var bonus_pct: int = int(round((1.0 - manager.get_mastery_duration_mult(rid)) * 100.0))
	# v122 PERF: skip the RichText/colour rebuild unless the readout changed.
	var m_sig := "%d|%d|%d|%d" % [level, in_lvl, needed, bonus_pct]
	if m_sig == _mastery_sig:
		return
	_mastery_sig = m_sig
	var bonus_suffix: String = (" · −%d%%" % bonus_pct) if bonus_pct > 0 else ""
	var next_m: int = 0
	for m in manager.MASTERY_MILESTONES:
		if level < m:
			next_m = m
			break

	var col_dim := Color(0.48, 0.45, 0.41)
	var col_mid := Color(0.72, 0.65, 0.45)
	var col_bright := Color(0.83, 0.69, 0.22)
	var col_gold := Color(1.0, 0.84, 0.20)

	# v109: wrap MASTERY keyword in [u]...[/u] so the underline visually
	# signals "hoverable" — same affordance as a hyperlink in the research
	# tree's tooltip pattern.
	if level >= 100:
		_mastery_left_lbl.text = tr("GOLD [u]MASTERY[/u]%s") % bonus_suffix
		_mastery_right_lbl.text = tr("LV 100  MAX")
		_mastery_left_lbl.add_theme_color_override("default_color", col_gold)
		_mastery_right_lbl.add_theme_color_override("font_color", col_gold)
		_mastery_bar.value = 100.0
		name_lbl.add_theme_color_override("font_color", col_gold)
	elif level >= 50:
		# v109: alt-recipe unlock retired; Lv 50 is now a "big-step" milestone
		# (+10% duration in one shot). Brighter colour still distinguishes
		# 50-99 from 1-49 so the leap feels like a state change, not just a
		# bigger number.
		_mastery_left_lbl.text = tr("[u]MASTERY[/u]  LV %d%s") % [level, bonus_suffix]
		_mastery_right_lbl.text = tr("%d / %d  ▸  LV %d") % [in_lvl, needed, next_m]
		_mastery_left_lbl.add_theme_color_override("default_color", col_bright)
		_mastery_right_lbl.add_theme_color_override("font_color", col_bright)
		_mastery_bar.value = pct
	elif level > 0:
		_mastery_left_lbl.text = tr("[u]MASTERY[/u]  LV %d%s") % [level, bonus_suffix]
		_mastery_right_lbl.text = tr("%d / %d  ▸  LV %d") % [in_lvl, needed, next_m]
		_mastery_left_lbl.add_theme_color_override("default_color", col_mid)
		_mastery_right_lbl.add_theme_color_override("font_color", col_mid)
		_mastery_bar.value = pct
	else:
		_mastery_left_lbl.text = tr("[u]MASTERY[/u]  LV 0")
		_mastery_right_lbl.text = tr("%d / %d  ▸  LV %d") % [in_lvl, needed, next_m]
		_mastery_left_lbl.add_theme_color_override("default_color", col_dim)
		_mastery_right_lbl.add_theme_color_override("font_color", col_dim)
		_mastery_bar.value = pct

func update_state():
	# v122 PERF: every page's _process runs even while hidden, so without this
	# every skill page rebuilds its cards every frame. Skip off-screen widgets
	# (hidden page OR hidden tab); they refresh when shown again.
	if not is_visible_in_tree():
		return
	var is_this_active = (manager.is_active and manager.current_recipe_id == rid)
	var in_combat: bool = GameState.combat_manager != null and GameState.combat_manager.in_combat
	_refresh_mastery()

	# --- INPUTS: real-time availability colouring. The satisfied-state is cheap
	# to compute every frame (dict reads); rebuild the BBCode only when it flips.
	var inputs = recipe.get("input", {})
	var pm = GameState.processing_manager   # ENG_3 reduces effective input cost; show what's actually consumed
	var missing_any = false
	var in_sig := str(inputs.size())
	for item in inputs:
		var need: int = pm.effective_input_qty(inputs[item]) if pm else int(inputs[item])
		var ok: bool = GameState.resources.get_element_amount(item) >= need
		if not ok:
			missing_any = true
		in_sig += ("1" if ok else "0") + str(need)   # fold effective need in so the card rebuilds when ENG_3 changes it
	var has_ingredients = not missing_any
	if in_sig != _in_sig:
		_in_sig = in_sig
		var in_str = "[center]"
		if inputs.is_empty():
			in_str += "None\n"
		else:
			for item in inputs:
				var req_qty: int = pm.effective_input_qty(inputs[item]) if pm else int(inputs[item])
				var avail_qty = GameState.resources.get_element_amount(item)
				var color = "lime" if avail_qty >= req_qty else "gray"
				var in_icon = ElementDB.material_icon_bbcode(item, 16)
				var in_link = "[url=atlasmat:%s]%s[/url]" % [item, ElementDB.get_display_name(item)]
				in_str += "%s[color=%s]%s %s[/color]\n" % [in_icon, color, FormatUtils.format_number(req_qty), in_link]
		in_str += "[/center]"
		in_lbl.text = in_str

	# --- OUTPUTS: rebuild only when (active, eff_mult, rates) change. ---
	var eff_mult = 1.0
	if GameState.research_manager:
		eff_mult = GameState.research_manager.get_efficiency_multiplier()
	var rates = manager.get_current_rate() if is_this_active else {}
	var out_sig := "%s|%.4f|%s" % [is_this_active, eff_mult, str(rates)]
	if out_sig != _out_sig:
		_out_sig = out_sig
		var out_str = "[center]"
		if "output" in recipe:
			for item in recipe["output"]:
				var display_name = ElementDB.get_display_name(item)
				var qty = recipe["output"][item]
				# BBCode url to catch hovers (info-card links).
				var meta_json = JSON.stringify({"id": item, "type": "item"})
				var link_text = "[url=%s][color=#ffce5c][u]%s[/u][/color][/url]" % [meta_json, display_name]
				var out_icon = ElementDB.material_icon_bbcode(item, 16)
				var line = "%s%s %s" % [out_icon, FormatUtils.format_number(qty * eff_mult), link_text]
				if item in rates:
					out_str += "%s [color=#55ff55](%s%s)[/color]\n" % [line, FormatUtils.format_number(rates[item]), tr("/m")]
				else:
					out_str += "%s\n" % line
		out_str += "[/center]"
		out_lbl.bbcode_enabled = true
		out_lbl.text = out_str.strip_edges()

	# --- gates (cheap) ---
	var lvl_req = recipe.get("level_req", 1)
	var has_level = manager.get_level() >= lvl_req
	var has_research = true
	if "research_req" in recipe and GameState.research_manager:
		has_research = GameState.research_manager.is_tech_unlocked(recipe["research_req"])

	# --- STATE: locked overlay + button + card tint — only on transition. ---
	var state_sig := "%s|%s|%s|%s|%s" % [is_this_active, has_research, has_level, has_ingredients, in_combat]
	if state_sig != _state_sig:
		_state_sig = state_sig
		if is_this_active:
			UITheme.apply_locked_overlay(self, recipe["name"], "", false)
			btn.text = tr("Stop")
			btn.disabled = false
			btn.modulate = Color(1, 1, 1)   # v137: clear any stale IN-COMBAT red tint
			modulate = Color(1.2, 1, 1)
		else:
			modulate = Color(1, 1, 1)
			# v137: reset here so every non-combat state is default — the in_combat branch
			# below reddens the button but nothing used to clear it, so it stayed red-ish
			# after combat ("Start" on a red button).
			btn.modulate = Color(1, 1, 1)
			if not has_research:
				var tech_name = GameState.research_manager.tech_tree.get(recipe["research_req"], {}).get("name", "Unknown Tech")
				UITheme.apply_locked_overlay(self, recipe["name"], tr("RESEARCH: %s") % tr(tech_name), true, recipe["research_req"], "engineering")
				btn.text = tr("Research Required")
				btn.disabled = true
			elif not has_level:
				UITheme.apply_locked_overlay(self, recipe["name"], "LEVEL %d REQUIRED" % recipe["level_req"], true, "", "engineering")
				btn.text = tr("Requires Lv %d") % lvl_req
				btn.disabled = true
			elif not has_ingredients:
				UITheme.apply_locked_overlay(self, recipe["name"], "", false)
				btn.text = tr("Missing Materials")
				btn.disabled = true
			elif in_combat:
				UITheme.apply_locked_overlay(self, recipe["name"], "", false)
				btn.text = tr("IN COMBAT")
				btn.disabled = true
				btn.modulate = Color(1.0, 0.35, 0.35, 0.8)
				modulate = Color(0.85, 0.85, 0.85)
			else:
				UITheme.apply_locked_overlay(self, recipe["name"], "", false)
				btn.text = tr("Start")
				btn.disabled = false

	# --- PROGRESS — cheap, EVERY frame, so the fill stays smooth. ---
	if is_this_active:
		var speed_mult = manager.get_recipe_speed_multiplier(rid)
		var effective_duration = float(recipe["duration"]) / speed_mult
		# v108: Clamp — a single big delta can briefly exceed required_time.
		var safe_progress: float = clamp(manager.action_progress, 0.0, effective_duration)
		prog_bar.active = true
		prog_bar.value = (safe_progress / effective_duration) * 100.0 if effective_duration > 0.0 else 0.0
		time_lbl.text = tr("%s / %s") % [FormatUtils.format_time(safe_progress), FormatUtils.format_time(effective_duration)]
	else:
		prog_bar.active = false
		prog_bar.value = 0
		time_lbl.text = tr("0.0s / %s") % FormatUtils.format_time(recipe["duration"] / manager.get_recipe_speed_multiplier(rid))

# ────────────────────────────────────────────────────────────
# META HOVER (Info Card Tooltip)
# ────────────────────────────────────────────────────────────

var _active_info_card = null
var info_card_scene = preload("res://scenes/ui/info_card.tscn")

func _ready():
	out_lbl.meta_hover_started.connect(_on_meta_hover)
	out_lbl.meta_hover_ended.connect(_on_meta_exit)
	# v137: click an input/output material name → deep-link to its Atlas page.
	in_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	out_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	in_lbl.meta_clicked.connect(func(meta): UITheme.request_atlas_from_meta(meta))
	out_lbl.meta_clicked.connect(func(meta):
		_on_meta_exit(meta)   # dismiss the hover info-card before switching pages
		UITheme.request_atlas_from_meta(meta)
	)

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
