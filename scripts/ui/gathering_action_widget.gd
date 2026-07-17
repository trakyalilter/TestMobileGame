extends PanelContainer

var aid: String
var data: Dictionary
var manager: RefCounted
var parent_ui: Node

# v109: fallback duration when an action's data has no "duration" key.
# Mirrors GatheringManager.start_action() line 386 (`action.get("duration", 4.0)`).
# Previously the widget fell back to manager.action_duration, which is mutated
# to the CURRENTLY-RUNNING action's value — so an idle Pump Water widget would
# bleed in Excavate Soil's 3.0s while Soil was running, then "jump" to 4.0s
# when the player switched to Pump Water. Idle vs running now agree.
const _DEFAULT_DURATION: float = 4.0

@onready var name_lbl = $MarginContainer/VBoxContainer/NameLabel
@onready var lvl_lbl = $MarginContainer/VBoxContainer/LevelLabel
@onready var loot_lbl = $MarginContainer/VBoxContainer/LootLabel
@onready var btn = $MarginContainer/VBoxContainer/Button
@onready var status_lbl = $MarginContainer/VBoxContainer/StatusLabel
@onready var time_lbl = $MarginContainer/VBoxContainer/TimeLabel
@onready var prog_bar = $MarginContainer/VBoxContainer/ProgressBar

# P1 Mastery — compact readout under the loot block: caption row +
# thin progress bar. Built once in setup(), refreshed in update_state().
var _mastery_left_lbl: RichTextLabel    # v109: now bbcode-capable so the
										# MASTERY keyword can be underlined.
var _mastery_right_lbl: Label
var _mastery_bar: ProgressBar
# v107: hover-popup info card. Created on mouse_entered, freed on _exited
# or tree_exiting (handles widget destroy mid-hover so no orphan stays).
var _mastery_info_card: Control = null

# v122 PERF: update_state() runs every frame (page _process). Only the progress
# bar + time vary frame-to-frame; the loot BBCode, mastery RichText and locked
# overlay change rarely. These signatures skip those expensive rebuilds (esp.
# the RichTextLabel re-parse) unless their inputs actually changed — the
# per-frame re-parse was the source of the progress-bar stutter.
var _loot_sig: String = ""
var _mastery_sig: String = ""
var _state_sig: String = ""

func setup(p_aid: String, p_data: Dictionary, p_manager, p_parent):
	aid = p_aid
	data = p_data
	manager = p_manager
	parent_ui = p_parent

	name_lbl.text = data["name"]
	name_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["ops"])
	var req = data.get("level_req", 1)
	lvl_lbl.text = tr("Lvl %d") % req

	UITheme.apply_card_style(self, "ops")
	UITheme.apply_premium_button_style(btn, "ops")
	prog_bar.accent = UITheme.CATEGORY_COLORS["ops"]

	# Themed "work order" card: drill-motif backdrop + icon header, with the
	# yield framed as the payoff. Loot text still compiled in update_state().
	var glyph = load("res://assets/icons/glyphs/gathering.svg") as Texture2D
	UITheme.inject_activity_header(self, "ops", glyph)
	var loot_panel = UITheme.wrap_in_io_panel(loot_lbl, "ops", "yield")
	UITheme.pin_card_footer(self)

	# Mastery panel sits directly under the YIELD panel (wrap_in_io_panel
	# returns the wrapper, which lives in this VBox at the label's old index).
	var card_vbox = $MarginContainer/VBoxContainer
	var after_idx = (loot_panel.get_index() + 1) if loot_panel else card_vbox.get_child_count()
	var mp = UITheme.build_mastery_panel(card_vbox, after_idx, "ops")
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

	# v137: click a loot material name → deep-link to its Atlas page.
	loot_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	loot_lbl.meta_clicked.connect(func(meta): UITheme.request_atlas_from_meta(meta))

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
	if manager.is_active and manager.current_action_id == aid:
		manager.stop_action()
	else:
		GameState.set_active_manager(manager)
		manager.start_action(aid)

	parent_ui.update_ui()

func _refresh_mastery():
	if not _mastery_bar or not manager:
		return
	var level: int = manager.get_mastery_level(aid)
	var prog: Dictionary = manager.get_mastery_progress(aid)
	var in_lvl: int = int(prog["in_level"])
	var needed: int = int(prog["needed"])
	if needed < 1:
		needed = 1
	var pct: float = clamp(float(in_lvl) / float(needed) * 100.0, 0.0, 100.0)

	# v107: Current cumulative bonus + next-milestone teaser, so the system
	# explains itself at a glance instead of being a silent progress bar.
	var bonus_pct: int = int(round((1.0 - manager.get_mastery_duration_mult(aid)) * 100.0))
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

	# v109: wrap the MASTERY keyword in [u]...[/u] so it reads as a hoverable
	# affordance. RichTextLabel uses default_color (not font_color) for the
	# baseline tint; the [u] tag inherits that colour for the underline.
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
	var is_this_active = (manager.is_active and manager.current_action_id == aid)
	var in_combat: bool = GameState.combat_manager != null and GameState.combat_manager.in_combat
	_refresh_mastery()

	var lvl = manager.get_level()
	var req = data.get("level_req", 1)

	var eff_mult = 1.0
	if GameState.research_manager:
		eff_mult = GameState.research_manager.get_efficiency_multiplier()
	var rates = manager.get_current_rate() if is_this_active else {}

	# --- LOOT (expensive BBCode re-parse) — rebuild only when it would change.
	# While active the rates are constant, so this builds once on activation. ---
	var loot_sig := "%s|%.4f|%s" % [is_this_active, eff_mult, str(rates)]
	if loot_sig != _loot_sig:
		_loot_sig = loot_sig
		var loot_text = "[center]"
		for entry in data["loot_table"]:
			var symbol = entry[0]
			var display_name = ElementDB.get_display_name(symbol)
			var icon_bb = ElementDB.material_icon_bbcode(symbol, 16)
			# v112: deterministic yield — show the single fixed value.
			var name_link = "[url=atlasmat:%s]%s[/url]" % [symbol, display_name]
			var base_loot = "%s%s: %s" % [icon_bb, name_link, FormatUtils.format_number(float(entry[3]) * eff_mult)]
			if symbol in rates:
				loot_text += "%s [color=#55ff55](%s/m)[/color]\n" % [base_loot, FormatUtils.format_number(rates[symbol])]
			else:
				loot_text += "%s\n" % base_loot
		loot_text += "[/center]"
		loot_lbl.text = loot_text.strip_edges()

	# --- unlocked + status (cheap) ---
	var unlocked = true
	var status_msg = ""
	if lvl < req:
		unlocked = false
		status_msg = tr("LEVEL %d REQUIRED") % req
	if "research_req" in data and data["research_req"]:
		if GameState.research_manager and not GameState.research_manager.is_tech_unlocked(data["research_req"]):
			unlocked = false
			var tech_name = GameState.research_manager.tech_tree.get(data["research_req"], {}).get("name", "Unknown Tech")
			status_msg = tr("RESEARCH: %s") % tr(tech_name).to_upper()

	# --- STATE: locked overlay + button + card tint — only on transition. ---
	var state_sig := "%s|%s|%s|%s" % [unlocked, status_msg, is_this_active, in_combat]
	if state_sig != _state_sig:
		_state_sig = state_sig
		if unlocked:
			UITheme.apply_locked_overlay(self, data["name"], "", false)
			status_lbl.text = ""
			btn.disabled = false
			if is_this_active:
				btn.text = tr("Stop")
				btn.modulate = Color(1.0, 0.4, 0.4) # Red-ish
				modulate = Color(1.2, 1, 1) # Highlight
			elif in_combat:
				btn.text = tr("IN COMBAT")
				btn.disabled = true
				btn.modulate = Color(1.0, 0.35, 0.35, 0.8)
				modulate = Color(0.85, 0.85, 0.85)
			else:
				btn.text = tr("Start")
				btn.modulate = Color(1, 1, 1)
				modulate = Color(1, 1, 1)
		else:
			var tech_id = data.get("research_req", "") if "RESEARCH" in status_msg else ""
			UITheme.apply_locked_overlay(self, data["name"], status_msg, true, tech_id, "ops")
			if "RESEARCH" in status_msg:
				btn.text = tr("RESEARCH REQUIRED")
			elif "LEVEL" in status_msg:
				btn.text = tr("LEVEL %d REQUIRED") % req
			else:
				btn.text = tr("LOCKED")
			btn.disabled = true
			status_lbl.text = status_msg
			modulate = Color(0.7, 0.7, 0.7)

	# --- PROGRESS — cheap, EVERY frame, so the fill stays smooth. ---
	if unlocked and is_this_active:
		var speed_mult = manager.get_action_speed_multiplier(aid)
		var effective_duration = float(data.get("duration", _DEFAULT_DURATION)) / speed_mult
		# v108: Clamp — a single big delta (frame stutter / tab refocus) can push
		# action_progress past required_time for one frame; never show "3.8s/2.9s".
		var safe_progress: float = clamp(manager.action_progress, 0.0, effective_duration)
		prog_bar.active = true
		prog_bar.value = (safe_progress / effective_duration) * 100.0 if effective_duration > 0.0 else 0.0
		time_lbl.text = tr("%s / %s") % [FormatUtils.format_time(safe_progress), FormatUtils.format_time(effective_duration)]
	else:
		prog_bar.active = false
		prog_bar.value = 0
		if unlocked:
			var speed_mult = manager.get_action_speed_multiplier(aid)
			time_lbl.text = tr("0.0s / %s") % FormatUtils.format_time(float(data.get("duration", _DEFAULT_DURATION)) / speed_mult)
		else:
			time_lbl.text = "- / -"
