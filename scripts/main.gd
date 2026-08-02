extends Control

@onready var page_container = $HBoxContainer/Content/PageContainer
# Sidebar Buttons
@onready var gathering_btn = $HBoxContainer/Sidebar/VBoxContainer/GatheringBtn
@onready var processing_btn = $HBoxContainer/Sidebar/VBoxContainer/ProcessingBtn
@onready var infrastructure_btn = $HBoxContainer/Sidebar/VBoxContainer/InfrastructureBtn
@onready var shipyard_btn = $HBoxContainer/Sidebar/VBoxContainer/ShipyardBtn
@onready var research_btn = $HBoxContainer/Sidebar/VBoxContainer/ResearchBtn
@onready var combat_btn = $HBoxContainer/Sidebar/VBoxContainer/CombatBtn
@onready var mission_btn = $HBoxContainer/Sidebar/VBoxContainer/MissionBtn
@onready var designer_btn = $HBoxContainer/Sidebar/VBoxContainer/DesignerBtn
@onready var inventory_btn = $HBoxContainer/Sidebar/VBoxContainer/InventoryBtn
@onready var atlas_btn = $HBoxContainer/Sidebar/VBoxContainer/AtlasBtn
@onready var options_btn = $HBoxContainer/Sidebar/VBoxContainer/OptionsBtn
@onready var menu_btn = $HBoxContainer/Sidebar/VBoxContainer/MenuBtn
@onready var bounty_btn = $HBoxContainer/Sidebar/VBoxContainer/BountyBtn
@onready var quest_btn = $HBoxContainer/Sidebar/VBoxContainer/QuestBtn
@onready var warp_btn = $HBoxContainer/Sidebar/VBoxContainer/WarpBtn
@onready var fleet_btn = $HBoxContainer/Sidebar/VBoxContainer/FleetBtn
@onready var sidebar_list = $HBoxContainer/Sidebar/VBoxContainer
@onready var sidebar_panel = $HBoxContainer/Sidebar

@onready var modal_layer = $ModalLayer
var offline_modal

@onready var background = $Background

var pages = {}
var current_page_name = ""
var header_widget: Control

# First-visit coach-mark overlay (shown once per page)
var coach_overlay = null

# Claim badges — shown on Mission / Quest sidebar buttons when rewards are ready
var mission_claim_badge: Control = null
var quest_claim_badge: Control = null
var warp_action_badge: Control = null  # v113 (NG+): "warp to breach Sector 11" nudge
var _claim_badge_tick: float = 0.0

func _ready():
	# v123: apply the saved UI palette BEFORE pages build so every card/button/bar
	# is styled against the chosen colours from the first frame.
	UITheme.apply_palette(UITheme.get_ui_palette())
	_init_pages()
	_apply_global_styles()
	_init_notifications() # Feature 66.1
	_init_claim_badges()
	_init_coach_overlay()

	# v71.1: Connect to shipyard alerts
	GameState.shipyard_manager.alert_changed.connect(_on_shipyard_alert_changed)

	GameState.game_resetted.connect(_on_game_resetted)
	
	if not GameState.mission_manager.has_progress():
		switch_to("mission")
	else:
		switch_to("gathering")

	# v123: a Sys Config palette change reloads the scene to re-theme everything;
	# land the player back on the page they came from (Options) rather than the
	# default landing page so they can keep A/B-testing palettes.
	if GameState.ui_return_page != "":
		var rp: String = GameState.ui_return_page
		GameState.ui_return_page = ""
		switch_to(rp)

	# v84.2: Research Navigation QoL
	UITheme.research_navigation_requested.connect(_on_research_navigation_requested)
	# v137: material deep-link — click a material in a recipe/inventory → open Atlas on it
	UITheme.atlas_navigation_requested.connect(_on_atlas_navigation_requested)

	# v107: P0 Prestige Discovery Fanfare — detect the moment the player
	# crosses the warp shard threshold for the first time. We listen on
	# every currency_added because credits feed the progress_score formula.
	# v110: Warp Core reveals when Zone 6 research completes (a content
	# milestone) rather than at an arbitrary credit threshold. tech_unlocked
	# v138: the prestige reveal is DIEGETIC now — the first Singularity (torn open by
	# a Zone-3+ boss kill) reveals the Warp system, not a research milestone.
	GameState.warp_manager.rift_opened.connect(_on_rift_opened_for_warp_reveal)

	# v128: one-shot durability warning on the first combat loss.
	if not GameState.combat_manager.combat_lost.is_connected(_maybe_show_combat_loss_coach):
		GameState.combat_manager.combat_lost.connect(_maybe_show_combat_loss_coach)

	# v145: make the level-up land (see _init_skill_level_feedback).
	_init_skill_level_feedback()

func _on_rift_opened_for_warp_reveal(first_reveal: bool) -> void:
	# v138: open_rift already set warp_first_revealed; here we surface the UI.
	_update_sidebar_styling()  # makes the Warp tab appear immediately
	if first_reveal:
		_fire_warp_reveal_fanfare()

func _fire_warp_reveal_fanfare() -> void:
	# Tell the player something happened AND where it is — the pulsing tab
	# alone doesn't read as an instruction. One self-contained notification
	# beats two-stage messaging.
	UITheme.show_notification(
		tr("⟨ SINGULARITY DETECTED ⟩  The boss's collapse tore a hole in spacetime — it is visible on the Sector Chart. The WARP tab is now online: Exotic Matter, mastery, monitoring."),
		Color(0.85, 0.5, 1.0)
	)
	if is_instance_valid(warp_btn):
		var tween := create_tween().set_loops(4)
		tween.tween_property(warp_btn, "modulate", Color(1.5, 1.0, 1.7), 0.5)
		tween.tween_property(warp_btn, "modulate", Color.WHITE, 0.5)

# ── v145: SKILL LEVEL-UP FEEDBACK ────────────────────────────────────────────
# Skill.level_up / Skill.milestone_unlocked were declared and emitted since the
# first build and had ZERO listeners repo-wide — in a skilling idle the level-up
# IS the core-loop payoff beat, and it was landing in total silence. They ride the
# existing UITheme.show_notification toast path (same chassis as every other
# system message); no second notification system is introduced.
#
# OWNER RULE — auto-appearing surfaces carry a SHORT FACT, never advice. These
# strings are "MINING LEVEL 42", never "you can now mine X, go to Y".
#
# Only Mining and Engineering are wired. combat_manager also extends Skill and
# still accrues XP, but v120 neutralised every combat-level bonus to 0 and no UI
# shows a combat level — toasting it would advertise a stat that does nothing,
# which is precisely what this session removed from the sensor slot.
# research_manager / infrastructure_manager extend Skill too but no code path
# ever calls add_xp on them, so they are permanently level 1. Both are logged as
# follow-ups rather than papered over here.
const _LEVEL_TOAST_COLOR := Color(0.42, 0.85, 1.00)      # cool scan-blue: routine progress
const _MILESTONE_TOAST_COLOR := Color(1.00, 0.79, 0.32)  # amber: this one is bigger
const _CAPSTONE_TOAST_COLOR := Color(1.00, 0.86, 0.45)   # gold: the level-100 cap

func _init_skill_level_feedback() -> void:
	# Label, skill, sidebar button to pulse on a milestone.
	var wired: Array = [
		["MINING", GameState.gathering_manager, gathering_btn],
		["ENGINEERING", GameState.processing_manager, processing_btn],
	]
	for entry in wired:
		var label: String = String(entry[0])
		var sk = entry[1]
		if sk == null:
			continue
		var lvl_cb := Callable(self, "_on_skill_level_up").bind(label)
		if not sk.level_up.is_connected(lvl_cb):
			sk.level_up.connect(lvl_cb)
		var ms_cb := Callable(self, "_on_skill_milestone").bind(label, entry[2])
		if not sk.milestone_unlocked.is_connected(ms_cb):
			sk.milestone_unlocked.connect(ms_cb)

# Pending highest level per skill, flushed once at end-of-frame. check_level_up()
# emits ONE level_up per level crossed inside a single call, so a fat offline
# return or a mission XP dump can cross a dozen levels at once — uncoalesced that
# machine-guns a dozen near-identical toasts. Collapsing to the highest level
# reached is also the more honest fact: "MINING LEVEL 25", not a countdown.
var _pending_skill_level: Dictionary = {}
var _skill_level_flush_queued: bool = false

func _on_skill_level_up(new_level: int, skill_label: String) -> void:
	# Milestone levels get their own, louder toast from _on_skill_milestone —
	# suppress the ordinary one so the beat isn't doubled on the same frame.
	if new_level in [10, 25, 50, 75, 100]:
		return
	_pending_skill_level[skill_label] = max(int(_pending_skill_level.get(skill_label, 0)), new_level)
	if not _skill_level_flush_queued:
		_skill_level_flush_queued = true
		_flush_skill_levels.call_deferred()

func _flush_skill_levels() -> void:
	_skill_level_flush_queued = false
	for skill_label in _pending_skill_level:
		UITheme.show_notification(
			tr("%s LEVEL %d") % [tr(String(skill_label)), int(_pending_skill_level[skill_label])],
			_LEVEL_TOAST_COLOR
		)
	_pending_skill_level.clear()

func _on_skill_milestone(milestone_level: int, skill_label: String, nav_btn: Control) -> void:
	# Milestones (10/25/50/75/100) must read as bigger than an ordinary level.
	# Three levers, all on the existing toast chassis: a warmer colour, a heavier
	# line, and a pulse on the skill's own sidebar tab so the eye is pulled to
	# where the reward lives. Still a short fact — no explainer.
	# A milestone toast IS this skill's level beat for the frame — drop any ordinary
	# level toast queued alongside it, or crossing 24->25 in one grant reads as
	# "MINING MILESTONE - LEVEL 25" immediately followed by "MINING LEVEL 24".
	_pending_skill_level.erase(skill_label)

	var is_capstone: bool = (milestone_level >= 100)
	var text: String = ""
	if is_capstone:
		text = tr("%s MASTERED — LEVEL %d") % [tr(skill_label), milestone_level]
	else:
		text = tr("%s MILESTONE — LEVEL %d") % [tr(skill_label), milestone_level]
	UITheme.show_notification(text, _CAPSTONE_TOAST_COLOR if is_capstone else _MILESTONE_TOAST_COLOR)

	if is_instance_valid(nav_btn):
		var punch: Color = Color(1.6, 1.4, 1.0) if is_capstone else Color(1.4, 1.25, 0.95)
		var tween := create_tween().set_loops(6 if is_capstone else 3)
		tween.tween_property(nav_btn, "modulate", punch, 0.28)
		tween.tween_property(nav_btn, "modulate", Color.WHITE, 0.28)

func _on_research_navigation_requested(tech_id: String):
	switch_to("research")
	var res_page = pages.get("research")
	if res_page and res_page.has_method("focus_on_tech"):
		res_page.focus_on_tech(tech_id)

# v137: open the Atlas focused on a material (from a recipe/inventory link).
func _on_atlas_navigation_requested(material_id: String):
	if material_id == "":
		return
	switch_to("atlas")
	var atlas_pg = pages.get("atlas")
	if atlas_pg and atlas_pg.has_method("focus_material"):
		atlas_pg.focus_material(material_id)

func _apply_global_styles():
	background.color = UITheme.COLORS["background"]
	_style_sidebar_panel()
	_apply_sidebar_icons()
	_update_sidebar_styling()

# v111.21: replace the emoji nav glyphs with crisp white SVG line-icons set as
# each button's `icon` (tinted per-state by apply_sidebar_button_style). Runs
# once; the icons live in res://assets/icons/nav/.
func _apply_sidebar_icons() -> void:
	_set_nav(mission_btn, "missions", "Missions")
	_set_nav(bounty_btn, "bounties", "Bounties")
	_set_nav(quest_btn, "quests", "Quests")
	_set_nav(gathering_btn, "mine", "Mine")
	_set_nav(processing_btn, "engineering", "Engineering")
	_set_nav(infrastructure_btn, "infrastructure", "Infrastructure")
	_set_nav(research_btn, "research", "Research Lab")
	_set_nav(shipyard_btn, "shipyard", "Shipyard")
	_set_nav(designer_btn, "designer", "Ship Designer")
	_set_nav(combat_btn, "combat", "Combat")
	_set_nav(warp_btn, "warp", "Warp Core")
	_set_nav(fleet_btn, "fleet", "Fleet")
	_set_nav(inventory_btn, "inventory", "Inventory")
	_set_nav(atlas_btn, "atlas", "Atlas")
	_set_nav(options_btn, "config", "Sys Config")
	_set_nav(menu_btn, "menu", "Main Menu")
	# Menu button isn't restyled per-page, so give its icon a fixed dim tint.
	if is_instance_valid(menu_btn):
		menu_btn.add_theme_color_override("icon_normal_color", Color(0.50, 0.55, 0.68))

func _set_nav(btn: Button, icon_name: String, label: String) -> void:
	if not is_instance_valid(btn):
		return
	var tex = load("res://assets/icons/nav/%s.svg" % icon_name)
	if tex:
		btn.icon = tex
	btn.text = label
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_constant_override("icon_max_width", 18)
	btn.add_theme_constant_override("h_separation", 10)

func _style_sidebar_panel():
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.048, 0.052, 0.085, 1.0)
	style.set_border_width_all(0)
	style.border_width_right = 1
	style.border_color = Color(0.20, 0.26, 0.42, 0.50)
	sidebar_panel.add_theme_stylebox_override("panel", style)

func _init_pages():
	# ... (same as before)
	var p_gathering = preload("res://scenes/ui/gathering_page.tscn").instantiate()
	page_container.add_child(p_gathering)
	p_gathering.visible = false
	pages["gathering"] = p_gathering
	
	var p_processing = preload("res://scenes/ui/processing_page.tscn").instantiate()
	page_container.add_child(p_processing)
	p_processing.visible = false
	pages["processing"] = p_processing
	
	var p_infrastructure = preload("res://scenes/ui/infrastructure_page.tscn").instantiate()
	page_container.add_child(p_infrastructure)
	p_infrastructure.visible = false
	pages["infrastructure"] = p_infrastructure
	
	var p_shipyard = preload("res://scenes/ui/shipyard_page.tscn").instantiate()
	page_container.add_child(p_shipyard)
	p_shipyard.visible = false
	pages["shipyard"] = p_shipyard
	
	var p_research = preload("res://scenes/ui/research_page.tscn").instantiate()
	page_container.add_child(p_research)
	p_research.visible = false
	pages["research"] = p_research
	
	var p_combat = preload("res://scenes/ui/combat_page.tscn").instantiate()
	page_container.add_child(p_combat)
	p_combat.visible = false
	pages["combat"] = p_combat
	
	var p_mission = preload("res://scenes/ui/mission_page.tscn").instantiate()
	page_container.add_child(p_mission)
	p_mission.visible = false
	pages["mission"] = p_mission
	
	var p_designer = preload("res://scenes/ui/designer_page.tscn").instantiate()
	page_container.add_child(p_designer)
	p_designer.visible = false
	pages["designer"] = p_designer
	
	var p_inventory = preload("res://scenes/ui/inventory_page.tscn").instantiate()
	page_container.add_child(p_inventory)
	p_inventory.visible = false
	pages["inventory"] = p_inventory
	
	var p_options = preload("res://scenes/ui/options_page.tscn").instantiate()
	page_container.add_child(p_options)
	p_options.visible = false
	pages["options"] = p_options

	var p_atlas = preload("res://scenes/ui/atlas_page.tscn").instantiate()
	page_container.add_child(p_atlas)
	p_atlas.visible = false
	pages["atlas"] = p_atlas
	
	atlas_btn.text = tr("  Atlas")

	
	var p_bounty = preload("res://scenes/ui/bounty_page.tscn").instantiate()
	page_container.add_child(p_bounty)
	p_bounty.visible = false
	pages["bounty"] = p_bounty

	var p_quest = preload("res://scenes/ui/quest_page.tscn").instantiate()
	page_container.add_child(p_quest)
	p_quest.visible = false
	pages["quest"] = p_quest
	
	var p_warp = preload("res://scenes/ui/warp_page.tscn").instantiate()
	page_container.add_child(p_warp)
	p_warp.visible = false
	pages["warp"] = p_warp

	# Built directly from the script (no .tscn): the page is 100% code-built, and
	# a hand-authored scene whose script ext_resource lacks an imported uid fails
	# to attach the script at load → the page renders as a script-less empty
	# Control. Instantiating the script (which `extends Control`) sidesteps that.
	var p_fleet = load("res://scripts/ui/fleet_page.gd").new()
	p_fleet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_container.add_child(p_fleet)
	p_fleet.visible = false
	pages["fleet"] = p_fleet

	if modal_layer:
		offline_modal = preload("res://scenes/ui/offline_boot_modal.tscn").instantiate()
		modal_layer.add_child(offline_modal)
		offline_modal.visible = false
		offline_modal.check_and_show()
		
	# 3. Create & Inject Global HUD
	header_widget = preload("res://scenes/ui/global_header.tscn").instantiate()
	$HBoxContainer/Content.add_child(header_widget)
	$HBoxContainer/Content.move_child(header_widget, 0) # Top of VBox
	# P-onboard: the header's Current-Objective chip taps through to the Missions page.
	if header_widget.has_signal("objective_pressed"):
		header_widget.objective_pressed.connect(func(): switch_to("mission"))
	# P-cargo: the header slot meter taps through to the Inventory page.
	if header_widget.has_signal("inventory_pressed"):
		header_widget.inventory_pressed.connect(func(): switch_to("inventory"))

# Feature 66.1: Global Notification Stack (Melvor-style)
var notification_container: VBoxContainer
# Cargo Manifest reward popups: live pills keyed for coalescing.
# {key: {panel, delta_lbl, total_lbl, accum:int, tween, accent:Color}}
var _reward_pills: Dictionary = {}

func _init_notifications():
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN # Grow leftwards
	margin.add_theme_constant_override("margin_right", 50)
	margin.add_theme_constant_override("margin_top", 100) # Below top HUD
	margin.add_theme_constant_override("margin_bottom", 50)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	notification_container = VBoxContainer.new()
	notification_container.alignment = BoxContainer.ALIGNMENT_END # Stack from bottom up
	notification_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(notification_container)
	
	$ModalLayer.add_child(margin)
	UITheme.notification_requested.connect(_spawn_notification)
	UITheme.reward_requested.connect(_spawn_reward)

# System / status toast — shares the Cargo Manifest pill chassis (dark bg,
# left accent stripe, soft shadow) so rewards and system messages read as one
# family in the shared feed. A leading status glyph (inferred from the intent
# colour) replaces the reward icon chip.
func _spawn_notification(text: String, color: Color):
	# v122: cleaner toast — dark rounded pill, left accent stripe, soft shadow,
	# and a small round status "LED" in the accent colour. Replaces the cryptic
	# !/i/✓ letter glyph (colour already carries the intent).
	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.12, 0.96)
	style.set_corner_radius_all(6)
	style.border_width_left = 3
	style.border_color = color
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	style.content_margin_left = 13
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	# Round status LED — clean colour-coded dot with a faint matching glow.
	var dot = Panel.new()
	dot.custom_minimum_size = Vector2(9, 9)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot_sb = StyleBoxFlat.new()
	dot_sb.bg_color = color
	dot_sb.set_corner_radius_all(5)
	dot_sb.shadow_color = Color(color.r, color.g, color.b, 0.5)
	dot_sb.shadow_size = 3
	dot.add_theme_stylebox_override("panel", dot_sb)
	row.add_child(dot)

	var msg = Label.new()
	msg.text = text
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.35))
	msg.add_theme_font_size_override("font_size", 13)
	msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(msg)

	notification_container.add_child(panel)
	_prune_feed()

	# Fade In (0.2s) -> Hold (1.6s) -> Fade Out (0.3s) -> free.
	panel.modulate.a = 0.0
	var tween = panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE)
	# Dwell scales with message length — long teaching toasts stay readable,
	# short status pings keep the old snappy feel. See UITheme.read_dwell.
	tween.tween_interval(UITheme.read_dwell(text))
	tween.tween_property(panel, "modulate:a", 0.0, 0.45)
	tween.tween_callback(panel.queue_free)

# ── Cargo Manifest reward popup ──
# Icon chip + NAME + big delta (accent) + dim total, on a dark pill with a
# left accent stripe. Repeats of the same `key` COALESCE: the live pill's
# delta ticks up and its lifetime resets, instead of spawning a fresh stack.
func _spawn_reward(info: Dictionary):
	var key: String = str(info.get("key", info.get("symbol", info.get("name", "?"))))
	var amount: int = int(info.get("amount", 0))
	var accent: Color = info.get("accent", Color(0.40, 0.90, 0.60))

	# Coalesce into an existing live pill for this key.
	if _reward_pills.has(key):
		var e = _reward_pills[key]
		if is_instance_valid(e["panel"]):
			e["accum"] = int(e["accum"]) + amount
			e["delta_lbl"].text = tr("+%s") % UITheme.format_number(e["accum"])
			e["total_lbl"].text = str(info.get("total_text", ""))
			_reward_restart_life(key)
			_reward_flash(e["delta_lbl"], bool(info.get("hot", false)))
			return
		_reward_pills.erase(key)

	var pill := _build_reward_pill(info, accent)
	notification_container.add_child(pill["panel"])
	_reward_pills[key] = pill
	_prune_feed()

	pill["panel"].modulate.a = 0.0
	_reward_restart_life(key)
	_reward_flash(pill["delta_lbl"], bool(info.get("hot", false)))

func _build_reward_pill(info: Dictionary, accent: Color) -> Dictionary:
	var is_xp: bool = str(info.get("kind", "loot")) == "xp"

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.065, 0.10, 0.95)
	if is_xp:
		# XP rows read warm-lit so progression is distinct from cargo.
		style.bg_color = Color(0.11, 0.085, 0.03, 0.95)
	style.set_corner_radius_all(5)
	style.border_width_left = 3
	style.border_color = accent
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", style)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(m)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)

	# Icon chip — symbol for loot, ★ for XP.
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(26, 26)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var chip_sb := StyleBoxFlat.new()
	chip_sb.bg_color = accent.lerp(Color.BLACK, 0.70) if not is_xp else Color(0, 0, 0, 0)
	chip_sb.set_corner_radius_all(6)
	if not is_xp:
		chip_sb.set_border_width_all(1)
		chip_sb.border_color = accent.lerp(Color.WHITE, 0.1)
	chip.add_theme_stylebox_override("panel", chip_sb)
	# Loot rows use the real material glyph (tinted) when we have one; XP keeps the
	# ★, and any material without an icon falls back to the 2-letter abbreviation.
	var mtex: Texture2D = null
	if not is_xp:
		mtex = ElementDB.get_material_icon(str(info.get("symbol", "")))
	if mtex:
		var mc := CenterContainer.new()
		mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ico := TextureRect.new()
		ico.texture = mtex
		ico.custom_minimum_size = Vector2(20, 20)
		ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ico.modulate = ElementDB.get_material_tint(str(info.get("symbol", "")))
		ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mc.add_child(ico)
		chip.add_child(mc)
	else:
		var chip_lbl := Label.new()
		chip_lbl.text = "XP" if is_xp else _chip_abbrev(str(info.get("symbol", "?")))
		chip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip_lbl.add_theme_font_size_override("font_size", 16 if is_xp else 11)
		chip_lbl.add_theme_color_override("font_color", accent if is_xp else accent.lerp(Color.WHITE, 0.7))
		chip.add_child(chip_lbl)
	row.add_child(chip)

	# Name + delta column.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	var name_lbl := Label.new()
	var name_txt: String = str(info.get("name", ""))
	var tag: String = str(info.get("tag", ""))
	if tag != "":
		name_txt = "%s · %s" % [name_txt, tag]
	name_lbl.text = name_txt.to_upper()
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", Color(0.62, 0.66, 0.76) if not info.get("hot", false) else Color(1.0, 0.85, 0.4))
	col.add_child(name_lbl)

	var delta_lbl := Label.new()
	delta_lbl.text = tr("+%s") % UITheme.format_number(int(info.get("amount", 0)))
	delta_lbl.add_theme_font_size_override("font_size", 17)
	delta_lbl.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.25))
	col.add_child(delta_lbl)

	# Spacer pushes the running total to the right edge.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(14, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	var total_lbl := Label.new()
	total_lbl.text = str(info.get("total_text", ""))
	total_lbl.add_theme_font_size_override("font_size", 11)
	total_lbl.add_theme_color_override("font_color", Color(0.55, 0.58, 0.66))
	total_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	total_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(total_lbl)

	return {"panel": panel, "delta_lbl": delta_lbl, "total_lbl": total_lbl,
		"accum": int(info.get("amount", 0)), "tween": null, "accent": accent}

# (Re)start a pill's life: full opacity → hold → fade → self-cleanup. Called on
# spawn and on every coalesce so an actively-ticking pill never expires.
func _reward_restart_life(key: String) -> void:
	if not _reward_pills.has(key): return
	var e = _reward_pills[key]
	var panel: Control = e["panel"]
	if not is_instance_valid(panel): return
	if e["tween"] and (e["tween"] as Tween).is_valid():
		e["tween"].kill()
	# Animate from the CURRENT alpha → 1.0: on spawn that's the 0→1 fade-in;
	# on coalesce it recovers a pill that may have been mid fade-out.
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	# Gain pills are short and glanceable, but 1.6s was still tight to read a
	# name + delta + running total. Coalescing resets this, so a live gather
	# keeps its pill up regardless.
	tw.tween_interval(2.6)
	tw.tween_property(panel, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func():
		_reward_pills.erase(key)
		if is_instance_valid(panel): panel.queue_free())
	e["tween"] = tw

# Quick scale-pop on the delta when a gain lands (white-hot for crit/jackpot).
func _reward_flash(lbl: Label, hot: bool) -> void:
	if not is_instance_valid(lbl): return
	lbl.pivot_offset = lbl.size * 0.5
	var base: Color = lbl.get_theme_color("font_color")
	var flash_col: Color = Color.WHITE if hot else base.lerp(Color.WHITE, 0.6)
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "scale", Vector2(1.22, 1.22) if hot else Vector2(1.12, 1.12), 0.08)
	tw.tween_property(lbl, "modulate", flash_col, 0.08)
	tw.chain().set_parallel(true)
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.18)
	tw.tween_property(lbl, "modulate", Color.WHITE, 0.25)

# Element symbols are often full words ("Dirt", "Bauxite"); the 26px chip shows
# a 2-char abbreviation. Real periodic symbols ("Fe", "Si") pass through whole.
func _chip_abbrev(sym: String) -> String:
	return sym if sym.length() <= 2 else sym.substr(0, 2)

# Cap the shared feed (reward pills + system toasts) at 5 visible entries.
func _prune_feed() -> void:
	var live: Array = []
	for c in notification_container.get_children():
		if not c.is_queued_for_deletion():
			live.append(c)
	# v139e: evict the oldest GAIN PILL first and only fall back to system
	# toasts when no pill is left. Toasts now hold a length-scaled reading
	# budget (up to ~9s for teaching text); with a blind oldest-first prune a
	# steady loot/XP stream would evict that toast within a second — the exact
	# "can't read it in time" failure the longer dwell exists to fix.
	while live.size() > 5:
		var victim = null
		for c in live:
			if _is_reward_pill(c):
				victim = c
				break
		if victim == null:
			victim = live[0]
		live.erase(victim)
		victim.queue_free()

func _is_reward_pill(node) -> bool:
	for key in _reward_pills:
		if _reward_pills[key]["panel"] == node:
			return true
	return false

# ── Claim Badges (Mission / Quest sidebar buttons) ──
func _init_claim_badges():
	mission_claim_badge = _build_claim_badge(Color(1.0, 0.40, 0.20))  # orange-red — story rewards
	mission_btn.add_child(mission_claim_badge)
	quest_claim_badge = _build_claim_badge(Color(1.0, 0.78, 0.22))   # gold — quest rewards
	quest_btn.add_child(quest_claim_badge)
	# v113 (NG+): "warp to breach Sector 11" nudge on the Warp button, lit after the
	# Z10 boss is cleared until the player warps (which unlocks Z11 + grants Cryo).
	warp_action_badge = _build_claim_badge(Color(0.55, 0.85, 1.0))
	if is_instance_valid(warp_btn):
		warp_btn.add_child(warp_action_badge)
	_update_claim_badges()

func _build_claim_badge(bg: Color) -> Control:
	# A right-edge circular pill carrying the claim count. Hidden when count == 0.
	var panel := PanelContainer.new()
	panel.name = "ClaimBadge"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	# Anchored to the right edge of the parent button, vertically centered.
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT, true)
	panel.position = Vector2(-32, -10)
	panel.custom_minimum_size = Vector2(22, 20)

	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(10)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	style.shadow_color = Color(bg.r, bg.g, bg.b, 0.45)
	style.shadow_size = 4
	panel.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.name = "CountLabel"
	lbl.text = "0"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)

	# Soft pulse to draw the eye without being obnoxious
	var tween := panel.create_tween().set_loops()
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 0.7), 0.9).set_trans(Tween.TRANS_SINE)
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 1.0), 0.9).set_trans(Tween.TRANS_SINE)

	return panel

func _update_claim_badges():
	var mm = GameState.mission_manager
	if mission_claim_badge and mm:
		var n = mm.count_claimable_missions()
		var lbl = mission_claim_badge.get_node_or_null("CountLabel")
		if lbl:
			lbl.text = str(n) if n < 99 else "99+"
		mission_claim_badge.visible = (n > 0)

	var qm = GameState.quest_manager
	if quest_claim_badge and qm:
		var n = qm.count_claimable()
		var lbl = quest_claim_badge.get_node_or_null("CountLabel")
		if lbl:
			lbl.text = str(n) if n < 99 else "99+"
		quest_claim_badge.visible = (n > 0) and quest_btn.visible

	# v113 (NG+): Warp nudge — lit while the Z10 boss is cleared but the player
	# hasn't warped yet (warping unlocks Z11). Auto-clears the moment they warp.
	if warp_action_badge and is_instance_valid(warp_btn):
		var wlbl = warp_action_badge.get_node_or_null("CountLabel")
		if wlbl:
			wlbl.text = "!"
		var needs_warp: bool = GameState.game_settings.get("z10_cleared", false) and not GameState.game_settings.get("z11_unlocked", false)
		warp_action_badge.visible = needs_warp and warp_btn.visible

# ── First-visit Coach Marks ──
func _init_coach_overlay():
	if not GameState.game_settings.has("coach_seen"):
		GameState.game_settings["coach_seen"] = {}
	coach_overlay = preload("res://scenes/ui/coach_overlay.tscn").instantiate()
	if modal_layer:
		modal_layer.add_child(coach_overlay)
	else:
		add_child(coach_overlay)
	coach_overlay.finished.connect(_on_coach_finished)

func _coach_active() -> bool:
	return coach_overlay != null and coach_overlay.is_active()

func _maybe_show_coach(page_name: String):
	if coach_overlay == null or _coach_active():
		return
	var seen: Dictionary = GameState.game_settings.get("coach_seen", {})
	if seen.get(page_name, false):
		return
	# Don't stack on top of the offline-summary modal on first boot; the player
	# will navigate again and the tour will trigger then.
	if offline_modal and is_instance_valid(offline_modal) and offline_modal.visible:
		return
	var steps: Array = CoachMarks.get_steps(page_name)
	if steps.is_empty():
		return
	var page_node = pages.get(page_name)
	stop_hint_pulse()  # don't fight the tour with the nav pulse
	coach_overlay.start(page_name, steps, page_node)

# v113 (NG+): anchor provider for the milestone coach (the warp-after-Z10 nudge),
# which spotlights a sidebar nav button rather than a page widget.
func get_coach_anchor(key: String) -> Control:
	if key == "warp_nav" and is_instance_valid(warp_btn):
		return warp_btn
	return null

# v113 (NG+): one-time coaching card after the Z10 boss falls, steering the player
# to Warp (the only path to Sector 11 + Cryo). Re-checked on the badge tick; fires
# once, only while Z10 is cleared but the player hasn't warped yet.
func _maybe_show_warp_coach() -> void:
	if coach_overlay == null or _coach_active():
		return
	var seen: Dictionary = GameState.game_settings.get("coach_seen", {})
	if seen.get("warp_milestone", false):
		return
	if not GameState.game_settings.get("z10_cleared", false):
		return
	if GameState.game_settings.get("z11_unlocked", false):
		return  # already warped past it
	if not (is_instance_valid(warp_btn) and warp_btn.visible):
		return
	if offline_modal and is_instance_valid(offline_modal) and offline_modal.visible:
		return
	var steps: Array = CoachMarks.get_steps("warp_milestone")
	if steps.is_empty():
		return
	stop_hint_pulse()
	coach_overlay.start("warp_milestone", steps, self)

# v128: one-time card on the first combat loss — teaches that losing degrades/destroys
# equipped modules (fired from combat_manager.lose_fight via the combat_lost signal).
func _maybe_show_combat_loss_coach() -> void:
	if coach_overlay == null or _coach_active():
		return
	var seen: Dictionary = GameState.game_settings.get("coach_seen", {})
	if seen.get("combat_loss", false):
		return
	if offline_modal and is_instance_valid(offline_modal) and offline_modal.visible:
		return
	var steps: Array = CoachMarks.get_steps("combat_loss")
	if steps.is_empty():
		return
	stop_hint_pulse()
	coach_overlay.start("combat_loss", steps, self)

# v131: staged Designer teachings. The old first-visit tour dumped 5 cards on a
# new player; now Matrix Cores / Set Bonuses fire as their own one-shot coaches
# on the first Designer visit AFTER the player owns the relevant item — teaching
# lands the moment it's actionable. Fires at most ONE stage per visit (matrix
# first), and never stacks on an active tour (that visit's stage waits its turn).
func _maybe_show_designer_stage_coach() -> void:
	if coach_overlay == null or _coach_active():
		return
	if offline_modal and is_instance_valid(offline_modal) and offline_modal.visible:
		return
	var seen: Dictionary = GameState.game_settings.get("coach_seen", {})
	if not seen.get("designer", false):
		return  # base tour hasn't run yet — basics come first
	var page_node = pages.get("designer")
	if not seen.get("designer_matrix", false) and _player_owns_matrix_core():
		stop_hint_pulse()
		coach_overlay.start("designer_matrix", CoachMarks.get_steps("designer_matrix"), page_node)
		return
	# v131: presets — taught once the player owns weapons of 2+ damage types
	# (mid damage-triangle arc), when hand-swapping loadouts becomes a chore.
	if not seen.get("designer_presets", false) and _player_owns_two_weapon_types():
		stop_hint_pulse()
		coach_overlay.start("designer_presets", CoachMarks.get_steps("designer_presets"), page_node)
		return
	if not seen.get("designer_sets", false) and _player_owns_set_module():
		stop_hint_pulse()
		coach_overlay.start("designer_sets", CoachMarks.get_steps("designer_sets"), page_node)

# v131: one-shot Shipyard card when Matrix Synthesis becomes craftable
# (zone_2_access). Cores have NO other source (no combat drops), so this is the
# system's front door. If the player already owns a core (old save / found it
# themselves), the flag is set silently — never teach what's already learned.
func _maybe_show_shipyard_matrix_coach() -> void:
	if coach_overlay == null or _coach_active():
		return
	if offline_modal and is_instance_valid(offline_modal) and offline_modal.visible:
		return
	var seen: Dictionary = GameState.game_settings.get("coach_seen", {})
	if seen.get("shipyard_matrix", false):
		return
	if not seen.get("shipyard", false):
		return  # base tour first
	if not GameState.research_manager.is_tech_unlocked("zone_2_access"):
		return
	if _player_owns_matrix_core():
		seen["shipyard_matrix"] = true  # already discovered it — skip silently
		GameState.game_settings["coach_seen"] = seen
		return
	stop_hint_pulse()
	coach_overlay.start("shipyard_matrix", CoachMarks.get_steps("shipyard_matrix"), pages.get("shipyard"))

func _player_owns_matrix_core() -> bool:
	for core_id in ElementDB.get_elements_in_category("matrix_cores"):
		if GameState.resources.get_element_amount(core_id) >= 1:
			return true
	return false

# v131: distinct weapon damage types owned (inventory + equipped) — customs carry
# their own stats, so checking the def's stats dict covers base AND custom rolls.
func _player_owns_two_weapon_types() -> bool:
	var sm = GameState.shipyard_manager
	if sm == null:
		return false
	var types := {}
	var owned: Array = sm.module_inventory.keys() + sm.loadout.values()
	for mid in owned:
		if mid == null or str(mid) == "":
			continue
		var def: Dictionary = sm.modules.get(str(mid), {})
		if str(def.get("slot_type", "")) != "weapon":
			continue
		var st: Dictionary = def.get("stats", {})
		if float(st.get("atk_kinetic", 0)) > 0: types["k"] = true
		elif float(st.get("atk_energy", 0)) > 0: types["e"] = true
		elif float(st.get("atk_explosive", 0)) > 0: types["x"] = true
		elif float(st.get("atk_cryo", 0)) > 0: types["c"] = true
		if types.size() >= 2:
			return true
	return false

# v134b: is a weapon of the given damage type currently EQUIPPED? (loadout only —
# owning it in the armory isn't enough to fight with it). sm.modules carries defs
# for base AND custom modules, so custom rolls are covered too.
func _has_weapon_type_equipped(wtype: String) -> bool:
	var sm = GameState.shipyard_manager
	if sm == null:
		return false
	for mid_v in sm.loadout.values():
		if mid_v == null or str(mid_v) == "":
			continue
		var def: Dictionary = sm.modules.get(str(mid_v), {})
		if str(def.get("slot_type", "")) != "weapon":
			continue
		var st: Dictionary = def.get("stats", {})
		var hit: bool = false
		match wtype:
			"kinetic": hit = float(st.get("atk_kinetic", 0)) > 0
			"energy": hit = float(st.get("atk_energy", 0)) > 0
			"explosive": hit = float(st.get("atk_explosive", 0)) > 0
			"cryo": hit = float(st.get("atk_cryo", 0)) > 0
		if hit:
			return true
	return false

# v134g: count (not just "any") weapons of a damage type in the active loadout.
# The dual-weapon onboarding (m015/m017a/m017c craft 2 of each) tells the player to
# equip BOTH slots; the router must keep directing until 2 are in, not stop at 1.
func _count_weapon_type_equipped(wtype: String) -> int:
	var sm = GameState.shipyard_manager
	if sm == null:
		return 0
	var n := 0
	for mid_v in sm.loadout.values():
		if mid_v == null or str(mid_v) == "":
			continue
		var def: Dictionary = sm.modules.get(str(mid_v), {})
		if str(def.get("slot_type", "")) != "weapon":
			continue
		var st: Dictionary = def.get("stats", {})
		var hit: bool = false
		match wtype:
			"kinetic": hit = float(st.get("atk_kinetic", 0)) > 0
			"energy": hit = float(st.get("atk_energy", 0)) > 0
			"explosive": hit = float(st.get("atk_explosive", 0)) > 0
			"cryo": hit = float(st.get("atk_cryo", 0)) > 0
		if hit:
			n += 1
	return n

func _player_owns_set_module() -> bool:
	var sm = GameState.shipyard_manager
	if sm == null:
		return false
	var owned: Array = sm.module_inventory.keys() + sm.loadout.values()
	for mid in owned:
		if mid == null or str(mid) == "":
			continue
		var def: Dictionary = sm.modules.get(str(mid), {})
		if str(def.get("set_id", "")) != "":
			return true
		# Custom rolls carry their base module's identity.
		var base: Dictionary = sm.modules.get(str(def.get("base_module", "")), {})
		if str(base.get("set_id", "")) != "":
			return true
	return false

func _on_coach_finished(page_name: String):
	var seen: Dictionary = GameState.game_settings.get("coach_seen", {})
	seen[page_name] = true
	GameState.game_settings["coach_seen"] = seen
	GameState.save_game()

func switch_to(page_name):
	if current_page_name == page_name: return

	for p_name in pages:
		pages[p_name].visible = (p_name == page_name)

	if page_name in pages:
		# Guard: Don't switch to pages that are currently hidden (gated)
		var btn = _get_btn_for_page(page_name)
		if btn and not btn.visible:
			return

		current_page_name = page_name
		# v135a (funnel, dev-only): player OPENED the warp screen. Paired with the
		# warp_performed event this measures open->commit conversion (the "sat on 25
		# shards, never clicked" failure). Invisible to the player.
		if page_name == "warp" and GameState.warp_manager:
			GameState.log_event({
				"type": "warp_opened",
				"score": GameState.warp_manager.get_progress_score(),
				"shards_available": GameState.warp_manager.calculate_warp_gains(),
				"shards_banked": GameState.warp_manager.warp_shards,
				"t": int(Time.get_unix_time_from_system()),
			})
		# P1 Onboarding hook: bump any active visit_page missions (e.g. m016c
		# "Combat Briefing") so the orientation step auto-completes the moment
		# the player navigates to the page it points at.
		if GameState.mission_manager:
			GameState.mission_manager._update_progress("visit_page", page_name, 1)
		_update_sidebar_styling()

		# SMART NAVIGATION: Notify page it's been opened
		if pages[page_name].has_method("on_page_enter"):
			pages[page_name].on_page_enter()

		# v71.1: Clear shipyard alert when entering designer
		if page_name == "designer":
			GameState.shipyard_manager.new_drops_alert = false

		# First-visit onboarding tour for this page
		_maybe_show_coach(page_name)
		# v131: staged designer teachings — advanced systems coach only once the
		# player actually owns the thing (Matrix Core / set piece). One per visit.
		if page_name == "designer":
			_maybe_show_designer_stage_coach()
		# v131: matrix-core ENTRY teaching — synthesis is the system's only source,
		# so coach it the moment the craft becomes available.
		if page_name == "shipyard":
			_maybe_show_shipyard_matrix_coach()

func _get_btn_for_page(page_name: String) -> Button:
	match page_name:
		"gathering": return gathering_btn
		"processing": return processing_btn
		"infrastructure": return infrastructure_btn
		"shipyard": return shipyard_btn
		"research": return research_btn
		"combat": return combat_btn
		"mission": return mission_btn
		"designer": return designer_btn
		"inventory": return inventory_btn
		"atlas": return atlas_btn
		"options": return options_btn

		"bounty": return bounty_btn
		"quest": return quest_btn
		"warp": return warp_btn
		"fleet": return fleet_btn
	return null

func _on_fleet_btn_pressed():
	switch_to("fleet")

func _on_shipyard_alert_changed(state: bool):
	if state and current_page_name != "designer":
		start_hint_pulse(designer_btn)
	elif not state:
		if pulsing_button == designer_btn:
			stop_hint_pulse()

func _update_sidebar_styling():
	UITheme.apply_sidebar_button_style(gathering_btn, current_page_name == "gathering")
	UITheme.apply_sidebar_button_style(processing_btn, current_page_name == "processing")
	UITheme.apply_sidebar_button_style(infrastructure_btn, current_page_name == "infrastructure")
	UITheme.apply_sidebar_button_style(shipyard_btn, current_page_name == "shipyard")
	UITheme.apply_sidebar_button_style(research_btn, current_page_name == "research")
	UITheme.apply_sidebar_button_style(combat_btn, current_page_name == "combat")
	UITheme.apply_sidebar_button_style(mission_btn, current_page_name == "mission")
	UITheme.apply_sidebar_button_style(designer_btn, current_page_name == "designer")
	UITheme.apply_sidebar_button_style(inventory_btn, current_page_name == "inventory")
	UITheme.apply_sidebar_button_style(atlas_btn, current_page_name == "atlas")
	UITheme.apply_sidebar_button_style(options_btn, current_page_name == "options")
	# v116: Main Menu was the only nav button missing the shared flat style, so it
	# kept Godot's default boxed button look. Always inactive (it changes scene).
	UITheme.apply_sidebar_button_style(menu_btn, false)

	UITheme.apply_sidebar_button_style(bounty_btn, current_page_name == "bounty")
	UITheme.apply_sidebar_button_style(quest_btn, current_page_name == "quest")
	UITheme.apply_sidebar_button_style(fleet_btn, current_page_name == "fleet")
	# Warp Core — the prestige marquee. Same sidebar rhythm as every other nav
	# button, distinguished by a purple identity accent (replaces the old default-
	# themed boxed button that clashed with the flat sidebar).
	UITheme.apply_sidebar_button_style(warp_btn, current_page_name == "warp", Color(0.78, 0.50, 1.00))
	
	# THEMATIC: Progressive Disclosure (Early & Mid-Game Gates)
	var has_basic_eng = GameState.research_manager.is_tech_unlocked("basic_engineering")
	var has_shipwright = GameState.research_manager.is_tech_unlocked("shipwright_1")
	
	# 1. Ship management & Combat become available at Applied Physics
	shipyard_btn.visible = has_basic_eng
	designer_btn.visible = has_basic_eng
	combat_btn.visible = has_basic_eng

	
	# v72.0: Bounty Board unlocks at the first real combat sector (Asteroid Belt).
	# P-onboard FIX: this was gated on "asteroid_clearance" — a tech defined NOWHERE,
	# so is_tech_unlocked() was always false and the (fully-built, ticking, save-
	# persisted) Bounty Board was permanently unreachable. The real Asteroid-Belt
	# access tech is zone_2_access (researched by mission m027).
	var has_asteroid_clearance = GameState.research_manager.is_tech_unlocked("zone_2_access")
	bounty_btn.visible = has_asteroid_clearance
	# Quests appear once the player has core gameplay loops available
	quest_btn.visible = has_basic_eng
	
	# 3. v138: Warp Core reveals with the FIRST SINGULARITY — a Zone-3+ boss kill
	# tears the rift open (combat_manager -> warp_manager.open_rift), which sets
	# warp_first_revealed and fires the fanfare via rift_opened. This gate also
	# reveals silently for saves that already prestiged / already earned a rift
	# (incl. pre-v138 saves migrated in game_state).
	var revealed: bool = GameState.game_settings.get("warp_first_revealed", false)
	if not revealed:
		var wm_ref = GameState.warp_manager
		if wm_ref.rift_open or wm_ref.total_warps > 0 or wm_ref.warp_shards > 0:
			revealed = true
		if revealed:
			GameState.game_settings["warp_first_revealed"] = true
	warp_btn.visible = revealed

	# Fleet Command reveals post-first-warp — v138: that's now the ZONE-3 Singularity,
	# so the fleet is a mid-game layer (costs re-sized accordingly in fleet_manager).
	# Soft role only: glut sink + passive combat accelerator. docs/FLEET_SIEGE_GATES.md.
	if is_instance_valid(fleet_btn):
		fleet_btn.visible = GameState.fleet_manager.is_unlocked() if GameState.fleet_manager else false
	


	

	
	# Style non-button sidebar elements
	for child in sidebar_list.get_children():
		if child is Label:
			if child.name == "LogoLabel":
				child.add_theme_font_size_override("font_size", 14)
				child.add_theme_color_override("font_color", Color(0.373, 0.878, 0.784))
				child.modulate = Color.WHITE
			else:
				child.add_theme_font_size_override("font_size", 9)
				child.add_theme_color_override("font_color", Color(0.28, 0.36, 0.52))
				child.modulate = Color.WHITE

	# (Warp Core's purple identity is now applied via apply_sidebar_button_style above.)

	if is_instance_valid(fleet_btn) and fleet_btn.visible:
		var fc := Color(0.40, 0.78, 1.00) if current_page_name != "fleet" else Color(0.72, 0.92, 1.00)
		fleet_btn.add_theme_color_override("font_color", fc)
		fleet_btn.add_theme_color_override("icon_normal_color", fc)

func _process(delta):
	# 1. Navigation Logic & Disclosure Check (Once per second is enough)
	if Engine.get_frames_drawn() % 60 == 0:
		_update_sidebar_styling()

	# 2. Tutorial Navigation Guidance
	_update_navigation_hints()

	# Keep the mission-hint arrow glued to its target every frame — it may scroll
	# inside a panel (e.g. equip-slot / armory lists), and the button glow follows
	# the widget but a free-floating arrow wouldn't without this.
	if pulsing_button and is_instance_valid(pulsing_button) and hint_arrow:
		_hint_arrow_phase += delta
		_position_hint_arrow()

	# 3. Claim badges (refresh ~4 Hz)
	_claim_badge_tick += delta
	if _claim_badge_tick >= 0.25:
		_claim_badge_tick = 0.0
		_update_claim_badges()
		_maybe_show_warp_coach()

# v161: an equip step is "live" only while it is active AND unfinished. Once the
# player equips the item the mission completes but lingers in active_missions
# until claimed — treating that as live is what stranded the Armory dim-filter.
func _equip_step_live(mission_id: String) -> bool:
	var mm = GameState.mission_manager
	if mm == null or not (mission_id in mm.active_missions):
		return false
	return not bool(mm.missions.get(mission_id, {}).get("completed", false))

func _update_navigation_hints():
	# A page tour owns the spotlight while it's open — don't double up.
	if _coach_active():
		stop_hint_pulse()
		return
	# v139j: the offline "welcome back" modal is a full-screen overlay; the game keeps
	# ticking behind it, but the gold directive arrow must not bleed onto that summary
	# (owner spotted it on the offline screen). Same guard the coach popups already use,
	# and mirrors the gain-feed toast suppression on that modal.
	if offline_modal and is_instance_valid(offline_modal) and offline_modal.visible:
		stop_hint_pulse()
		return
	var mm = GameState.mission_manager
	if not mm: return
	# v138d: never direct at a claimed mission — self-heal the active list first
	# (a stale claimed-but-active entry kept pointing the gold arrow at an
	# already-researched node; observed live on m025 -> Efficient Smelting).
	mm.purge_claimed_actives()

	var target_to_pulse: Control = null

	# 1. Claim Reminder (Top Priority)
	var can_claim_tutorial = false
	for mid in mm.missions:
		if mid.begins_with("m0") and mm.missions[mid]["completed"] and not mm.missions[mid]["claimed"]:
			can_claim_tutorial = true
			break
	
	if can_claim_tutorial:
		if current_page_name != "mission":
			target_to_pulse = mission_btn
	
	# 2. Contextual Guidance based on Active Mission
	elif "m001" in mm.active_missions:
		# Gather Dirt
		if current_page_name != "gathering": target_to_pulse = gathering_btn
		else:
			pages["gathering"].focus_action("gather_dirt")
			var widget = pages["gathering"].get_widget_by_aid("gather_dirt")
			if widget and not (GameState.gathering_manager.is_active and GameState.gathering_manager.current_action_id == "gather_dirt"):
				target_to_pulse = widget.btn
				
	elif "m002" in mm.active_missions:
		# Foundational Research: a single research now — Applied Physics + Fluid Dynamics
		# were folded into Basic Engineering. Pulse the Basic Engineering node.
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("basic_engineering")
			if widget: target_to_pulse = widget
			
	elif "m003" in mm.active_missions:
		# Orphan (in-flight saves): re-pointed to Basic Engineering.
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("basic_engineering")
			if widget: target_to_pulse = widget
			
	elif "m004" in mm.active_missions:
		# Gather Water
		if current_page_name != "gathering": target_to_pulse = gathering_btn
		else:
			pages["gathering"].focus_action("collect_water")
			var widget = pages["gathering"].get_widget_by_aid("collect_water")
			if widget and not (GameState.gathering_manager.is_active and GameState.gathering_manager.current_action_id == "collect_water"):
				target_to_pulse = widget.btn
				
	elif "m005" in mm.active_missions:
		# Processing: Si, Fe (Mineral Washing)
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("centrifuge_dirt")
			var widget = page.get_widget_by_aid("centrifuge_dirt")
			if widget and not (pm.is_active and pm.current_recipe_id == "centrifuge_dirt"):
				target_to_pulse = widget.btn
			
	elif "m005b" in mm.active_missions:
		# v134g: Shipyard — craft the Basic Battery (power-first onboarding)
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			var page = pages["shipyard"]
			page.focus_module_tab("z1_battery")
			target_to_pulse = page.get_module_widget("z1_battery")

	elif "m005c" in mm.active_missions:
		# v134g: Designer — equip the batteries (pulse the empty battery slot,
		# dim non-battery armory modules so the batteries pop).
		if current_page_name != "designer": target_to_pulse = designer_btn
		else:
			var dp = pages["designer"]
			if dp.has_method("set_equip_focus_filter"):
				dp.set_equip_focus_filter("battery")
			if dp.has_method("get_slot_widget"):
				dp.focus_slot("battery")
				target_to_pulse = dp.get_slot_widget("battery")

	elif "m007" in mm.active_missions:
		# Shipyard: Ion Thrusters
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			var page = pages["shipyard"]
			page.focus_module_tab("z1_engine")
			target_to_pulse = page.get_module_widget("z1_engine")

	elif "m007b" in mm.active_missions:
		# Designer: pulse the empty engine slot so the just-crafted Thruster
		# closes its arc with a visible "equip me" target. Also dim non-engine
		# modules in the Armory so the Thruster pops visually.
		if current_page_name != "designer": target_to_pulse = designer_btn
		else:
			var dp = pages["designer"]
			if dp.has_method("set_equip_focus_filter"):
				dp.set_equip_focus_filter("engine")
			if dp.has_method("get_slot_widget"):
				dp.focus_slot("engine")
				target_to_pulse = dp.get_slot_widget("engine")
			elif dp.has_method("get_coach_anchor"):
				target_to_pulse = dp.get_coach_anchor("schematic")

	elif "m008" in mm.active_missions:
		# Research: Materials Science Hub
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("materials_science")
			if widget: target_to_pulse = widget

	elif "m009" in mm.active_missions:
		# Gather Wood
		if current_page_name != "gathering": target_to_pulse = gathering_btn
		else:
			pages["gathering"].focus_action("gather_wood")
			var widget = pages["gathering"].get_widget_by_aid("gather_wood")
			if widget and not (GameState.gathering_manager.is_active and GameState.gathering_manager.current_action_id == "gather_wood"):
				target_to_pulse = widget.btn

	elif "m010" in mm.active_missions:
		# Research: Combustion
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("combustion")
			if widget: target_to_pulse = widget
			
	elif "m011" in mm.active_missions:
		# Processing: Carbon (Kiln)
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("charcoal_burning") # Updated to exact recipe ID
			var widget = page.get_widget_by_aid("charcoal_burning")
			if widget and not (pm.is_active and pm.current_recipe_id == "charcoal_burning"):
				target_to_pulse = widget.btn
				
	elif "m012" in mm.active_missions:
		# Gather Spodumene
		if current_page_name != "gathering": target_to_pulse = gathering_btn
		else:
			pages["gathering"].focus_action("extract_salts")
			var widget = pages["gathering"].get_widget_by_aid("extract_salts")
			if widget and not (GameState.gathering_manager.is_active and GameState.gathering_manager.current_action_id == "extract_salts"):
				target_to_pulse = widget.btn
				
	elif "m013" in mm.active_missions:
		# Processing: Refine Lithium
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("refine_lithium")
			var widget = page.get_widget_by_aid("refine_lithium")
			if widget and not (pm.is_active and pm.current_recipe_id == "refine_lithium"):
				target_to_pulse = widget.btn

	elif "m014" in mm.active_missions:
		# Research: Kinetics 101
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("kinetics_101")
			if widget: target_to_pulse = widget
				
	elif "m015" in mm.active_missions:
		# Shipyard: Mass Driver
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			var page = pages["shipyard"]
			page.focus_module_tab("z1_kinetic")
			target_to_pulse = page.get_module_widget("z1_kinetic")

	elif "m015b" in mm.active_missions:
		# Designer: pulse the empty weapon slot + highlight only KINETIC weapons.
		if current_page_name != "designer": target_to_pulse = designer_btn
		else:
			var dp = pages["designer"]
			if dp.has_method("set_equip_focus_filter"):
				dp.set_equip_focus_filter("weapon", "kinetic")   # v134g: only kinetic pulses
			if dp.has_method("get_slot_widget"):
				dp.focus_slot("weapon")
				target_to_pulse = dp.get_slot_widget("weapon")
			elif dp.has_method("get_coach_anchor"):
				target_to_pulse = dp.get_coach_anchor("schematic")

	elif "m016" in mm.active_missions:
		# Processing: Ferrite Rounds
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("craft_slug_t1")
			var widget = page.get_widget_by_aid("craft_slug_t1")
			if widget and not (pm.is_active and pm.current_recipe_id == "craft_slug_t1"):
				target_to_pulse = widget.btn
				
	elif "m017" in mm.active_missions:
		# Combat: Lunar Orbit Target
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("lunar_orbit")
			target_to_pulse = page.get_enemy_card("z1_lunar_drone")

	# v128: damage-triangle arcs — same routing as m015 (shipyard craft) / m017 (combat kill).
	elif "m017a" in mm.active_missions:
		# Shipyard: Pulse Laser Mk.I (energy leg)
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			var page = pages["shipyard"]
			page.focus_module_tab("z1_energy")
			target_to_pulse = page.get_module_widget("z1_energy")

	elif "m017a2" in mm.active_missions:
		# v134: Processing — produce Focus Crystals (the energy leg's ammo step)
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("craft_cell_t1")
			var widget = page.get_widget_by_aid("craft_cell_t1")
			if widget and not (pm.is_active and pm.current_recipe_id == "craft_cell_t1"):
				target_to_pulse = widget.btn

	elif "m017b" in mm.active_missions:
		# v134b: the mission is EQUIP the Pulse Laser, THEN fight. Pulsing Combat
		# while no energy weapon was equipped herded the player into the probe's
		# kinetic-resist wall with the wrong gun. Phase 1: Ship Designer until an
		# energy weapon is on the ship. Phase 2: Combat, Survey Probe.
		# v134g: the mission says equip BOTH Pulse Lasers — keep directing to the
		# weapon slot until TWO energy weapons are in, not stop at one (half DPS).
		if _count_weapon_type_equipped("energy") < 2:
			if current_page_name != "designer": target_to_pulse = designer_btn
			else:
				var dp = pages["designer"]
				# v134g: keep the ENERGY build in its OWN slot (Loadout 2) so the
				# Kinetic build in slot 1 survives — switch there first, then equip.
				# While still on the wrong slot, re-pulse the chip so a player who
				# equips over Loadout 1 is nudged back before clobbering the build.
				var _sm = GameState.shipyard_manager
				var _cur: int = int(_sm.active_preset_idx) if "active_preset_idx" in _sm else 1
				if _cur != 2 and dp.has_method("get_loadout_chip"):
					target_to_pulse = dp.get_loadout_chip(2)
				elif dp.has_method("get_slot_widget"):
					if dp.has_method("set_equip_focus_filter"):
						dp.set_equip_focus_filter("weapon", "energy")   # v134g: only energy pulses
					dp.focus_slot("weapon")
					target_to_pulse = dp.get_slot_widget("weapon")
				elif dp.has_method("get_coach_anchor"):
					target_to_pulse = dp.get_coach_anchor("schematic")
		elif current_page_name != "combat":
			target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("lunar_orbit")
			target_to_pulse = page.get_enemy_card("z1_survey_probe")

	elif "m017c" in mm.active_missions:
		# Shipyard: Micro-Missile Launcher (explosive leg)
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			var page = pages["shipyard"]
			page.focus_module_tab("z1_missile")
			target_to_pulse = page.get_module_widget("z1_missile")

	elif "m017c2" in mm.active_missions:
		# v134: Processing — produce HE Missiles (the explosive leg's ammo step)
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("craft_missile_t1")
			var widget = page.get_widget_by_aid("craft_missile_t1")
			if widget and not (pm.is_active and pm.current_recipe_id == "craft_missile_t1"):
				target_to_pulse = widget.btn

	elif "m017d" in mm.active_missions:
		# v134b: two-phase like m017b — Ship Designer until an explosive weapon
		# is equipped, then Combat for the explosive-weak Scrap Collector.
		# v134g: equip BOTH launchers — direct to the weapon slot until TWO are in.
		if _count_weapon_type_equipped("explosive") < 2:
			if current_page_name != "designer": target_to_pulse = designer_btn
			else:
				var dp = pages["designer"]
				# v134g: EXPLOSIVE build → its own slot (Loadout 3). Switch there
				# first so Kinetic (1) and Energy (2) survive, then equip. Re-pulse
				# the chip while on the wrong slot to guard the saved builds.
				var _sm = GameState.shipyard_manager
				var _cur: int = int(_sm.active_preset_idx) if "active_preset_idx" in _sm else 1
				if _cur != 3 and dp.has_method("get_loadout_chip"):
					target_to_pulse = dp.get_loadout_chip(3)
				elif dp.has_method("get_slot_widget"):
					if dp.has_method("set_equip_focus_filter"):
						dp.set_equip_focus_filter("weapon", "explosive")   # v134g: only explosive pulses
					dp.focus_slot("weapon")
					target_to_pulse = dp.get_slot_widget("weapon")
				elif dp.has_method("get_coach_anchor"):
					target_to_pulse = dp.get_coach_anchor("schematic")
		elif current_page_name != "combat":
			target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("lunar_orbit")
			target_to_pulse = page.get_enemy_card("z1_scrap_collector")

	elif "m018" in mm.active_missions:
		# Research: Industrial Logistics Hub
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("industrial_logistics")
			if widget: target_to_pulse = widget

	elif "m018b" in mm.active_missions:
		# v136: automated_logistics removed; orphan beat retargets to industrial_logistics.
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("industrial_logistics")
			if widget: target_to_pulse = widget
			
	elif "m018t1" in mm.active_missions:
		# Gather Cassiterite (tin ore) — pulse the mining action.
		if current_page_name != "gathering": target_to_pulse = gathering_btn
		else:
			pages["gathering"].focus_action("mine_cassiterite")
			var w = pages["gathering"].get_widget_by_aid("mine_cassiterite")
			if w and not (GameState.gathering_manager.is_active and GameState.gathering_manager.current_action_id == "mine_cassiterite"):
				target_to_pulse = w.btn

	elif "m018t2" in mm.active_missions:
		# Smelt Cassiterite -> Tin — pulse the Tin Smelting recipe.
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("refine_cassiterite")
			var w = page.get_widget_by_aid("refine_cassiterite")
			if w and not (pm.is_active and pm.current_recipe_id == "refine_cassiterite"):
				target_to_pulse = w.btn

	elif "m019" in mm.active_missions:
		# v134g: the Circuit recipe needs Tin (Sn) — a two-hop the earlier chain never
		# delivered. Route the intermediate need-aware (mirrors m024b): mine Cassiterite →
		# smelt Tin → then craft the Circuit, whichever the player currently lacks.
		var _sn: float = GameState.resources.get_element_amount("Sn")
		var _cass: float = GameState.resources.get_element_amount("Cassiterite")
		if _sn < 2 and _cass < 2:
			# No tin, no ore — pulse the Cassiterite mining action first.
			if current_page_name != "gathering": target_to_pulse = gathering_btn
			else:
				pages["gathering"].focus_action("mine_cassiterite")
				var w = pages["gathering"].get_widget_by_aid("mine_cassiterite")
				if w and not (GameState.gathering_manager.is_active and GameState.gathering_manager.current_action_id == "mine_cassiterite"):
					target_to_pulse = w.btn
		elif _sn < 2:
			# Have ore, no tin — pulse the Tin Smelting recipe.
			if current_page_name != "processing": target_to_pulse = processing_btn
			else:
				var pm = GameState.processing_manager
				var page = pages["processing"]
				page.focus_tab("refine_cassiterite")
				var w = page.get_widget_by_aid("refine_cassiterite")
				if w and not (pm.is_active and pm.current_recipe_id == "refine_cassiterite"):
					target_to_pulse = w.btn
		else:
			# Have tin — pulse the Circuit craft.
			if current_page_name != "processing": target_to_pulse = processing_btn
			else:
				var pm = GameState.processing_manager
				var page = pages["processing"]
				page.focus_tab("craft_circuit")
				var widget = page.get_widget_by_aid("craft_circuit")
				if widget and not (pm.is_active and pm.current_recipe_id == "craft_circuit"):
					target_to_pulse = widget.btn

	elif "m020" in mm.active_missions:
		# Research: Power Systems
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("power_systems")
			if widget: target_to_pulse = widget
				
	elif "m021" in mm.active_missions:
		# Processing: Batteries
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("craft_battery_t1")
			var widget = page.get_widget_by_aid("craft_battery_t1")
			if widget and not (pm.is_active and pm.current_recipe_id == "craft_battery_t1"):
				target_to_pulse = widget.btn
				
	elif "m022" in mm.active_missions:
		# Shipyard: Battery Module
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			var page = pages["shipyard"]
			page.focus_module_tab("z1_battery")
			target_to_pulse = page.get_module_widget("z1_battery")

	elif "m022b" in mm.active_missions:
		# Designer: pulse the empty battery slot + dim non-battery Armory cards.
		if current_page_name != "designer": target_to_pulse = designer_btn
		else:
			var dp = pages["designer"]
			if dp.has_method("set_equip_focus_filter"):
				dp.set_equip_focus_filter("battery")
			if dp.has_method("get_slot_widget"):
				dp.focus_slot("battery")
				target_to_pulse = dp.get_slot_widget("battery")
			elif dp.has_method("get_coach_anchor"):
				target_to_pulse = dp.get_coach_anchor("schematic")

	elif "m023" in mm.active_missions:
		# Research: Energy Shields
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("energy_shields")
			if widget: target_to_pulse = widget
			
	elif "m024" in mm.active_missions:
		# Shipyard: Deflector Shield
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			var page = pages["shipyard"]
			page.focus_module_tab("z1_shield")
			target_to_pulse = page.get_module_widget("z1_shield")

	elif "m024c" in mm.active_missions:
		# Designer: pulse the empty shield slot + dim non-shield Armory cards.
		if current_page_name != "designer": target_to_pulse = designer_btn
		else:
			var dp = pages["designer"]
			if dp.has_method("set_equip_focus_filter"):
				dp.set_equip_focus_filter("shield")
			if dp.has_method("get_slot_widget"):
				dp.focus_slot("shield")
				target_to_pulse = dp.get_slot_widget("shield")
			elif dp.has_method("get_coach_anchor"):
				target_to_pulse = dp.get_coach_anchor("schematic")

	elif "m024a1" in mm.active_missions:
		# Shipyard: Iron Plate (armor).
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			var page = pages["shipyard"]
			page.focus_module_tab("z1_armor")
			target_to_pulse = page.get_module_widget("z1_armor")

	elif "m024a2" in mm.active_missions:
		# Designer: pulse the empty armor slot + dim non-armor Armory cards.
		if current_page_name != "designer": target_to_pulse = designer_btn
		else:
			var dp = pages["designer"]
			if dp.has_method("set_equip_focus_filter"):
				dp.set_equip_focus_filter("armor")
			if dp.has_method("get_slot_widget"):
				dp.focus_slot("armor")
				target_to_pulse = dp.get_slot_widget("armor")
			elif dp.has_method("get_coach_anchor"):
				target_to_pulse = dp.get_coach_anchor("schematic")

	elif "m016c" in mm.active_missions:
		# Combat orientation — pulse the Combat tab until the player visits;
		# the visit_page hook in switch_to() auto-completes the mission.
		if current_page_name != "combat":
			target_to_pulse = combat_btn

	elif "m025" in mm.active_missions:
		# Research: Efficient Smelting — but its PARENT Organic Combustion is un-owned on
		# the live path (m010 is orphaned), so smelting is greyed and clicking it is inert.
		# v134h: need-aware — pulse combustion first, then smelting once it's owned (mirrors
		# the m019 two-hop router). The mission text already names both, in this order.
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var _rm = GameState.research_manager
			var _node := "smelting" if (_rm and _rm.is_tech_unlocked("combustion")) else "combustion"
			var widget = pages["research"].get_node_widget(_node)
			if widget: target_to_pulse = widget

	elif "m025a" in mm.active_missions:
		# v134: Processing — Water Electrolysis (stock Oxygen for the BOF steel step)
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("electrolysis")
			var widget = page.get_widget_by_aid("electrolysis")
			if widget and not (pm.is_active and pm.current_recipe_id == "electrolysis"):
				target_to_pulse = widget.btn

	elif "m026" in mm.active_missions:
		# Research: Shipwright I
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("shipwright_1")
			if widget: target_to_pulse = widget

	elif "m027" in mm.active_missions:
		# Research: Asteroid Belt Authorization (zone_2_access)
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("zone_2_access")
			if widget: target_to_pulse = widget

	elif "m028" in mm.active_missions:
		# v145: m028 now asks for smelted TIN, not raw Cassiterite (the ore had no
		# consumer for ~8 missions). Route need-aware, exactly like m019: no ore -> mine,
		# ore in hand -> pulse the Tin Smelting recipe.
		var _m028_cass: float = GameState.resources.get_element_amount("Cassiterite")
		if _m028_cass < 3:
			if current_page_name != "gathering": target_to_pulse = gathering_btn
			else:
				pages["gathering"].focus_action("mine_cassiterite")
				var widget = pages["gathering"].get_widget_by_aid("mine_cassiterite")
				if widget and not (GameState.gathering_manager.is_active and GameState.gathering_manager.current_action_id == "mine_cassiterite"):
					target_to_pulse = widget.btn
		else:
			if current_page_name != "processing": target_to_pulse = processing_btn
			else:
				var pm = GameState.processing_manager
				var page = pages["processing"]
				page.focus_tab("refine_cassiterite")
				var w = page.get_widget_by_aid("refine_cassiterite")
				if w and not (pm.is_active and pm.current_recipe_id == "refine_cassiterite"):
					target_to_pulse = w.btn

	elif "m029" in mm.active_missions:
		# Shipyard: Zone 2 Armor (Carbon Fiber Plate)
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			var page = pages["shipyard"]
			page.focus_module_tab("z2_armor")
			target_to_pulse = page.get_module_widget("z2_armor")

	elif "m030" in mm.active_missions:
		# Research: Shipwright II (Audit v15.0)
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("shipwright_2")
			if widget: target_to_pulse = widget
			
	elif "m030c" in mm.active_missions:
		# Shipyard: Escort Destroyer
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			pages["shipyard"].focus_hull_tab("destroyer_hull")
			target_to_pulse = pages["shipyard"].get_hull_widget("destroyer_hull")

	elif "m032b" in mm.active_missions:
		# Research: Beta Colony Charter (Sector Beta door) — v132 retarget
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("zone_6_access")
			if widget: target_to_pulse = widget
			
	elif "m032c" in mm.active_missions:
		# Shipyard: Battlecruiser
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			pages["shipyard"].focus_hull_tab("battlecruiser_hull")
			target_to_pulse = pages["shipyard"].get_hull_widget("battlecruiser_hull")
			
	elif "m033b" in mm.active_missions:
		# Research: Gamma Sector Clearance (Sector Gamma door) — v132 retarget
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("zone_7_access")
			if widget: target_to_pulse = widget
			
	elif "m033c" in mm.active_missions:
		# Shipyard: Dreadnought
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			pages["shipyard"].focus_hull_tab("dreadnought_hull")
			target_to_pulse = pages["shipyard"].get_hull_widget("dreadnought_hull")

	elif "m030d" in mm.active_missions:
		# v134h: Combat — Z2 boss farm for the zone_3_access core (Silicate Monolith).
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("asteroid_belt")
			target_to_pulse = page.get_enemy_card("z2_boss_monolith")

	elif "m030f2" in mm.active_missions:
		# v134h: Combat — Z3 boss farm for the zone_4_access cores (Martian Warmaster).
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("mars_debris")
			target_to_pulse = page.get_enemy_card("z3_boss_warmaster")

	elif "m030i" in mm.active_missions:
		# Combat: Overseer's Core (Z4 boss farm for zone_5_access cores) — v132
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("cryofield")   # Glacier Belt's zone id
			target_to_pulse = page.get_enemy_card("z4_boss_overseer")

	elif "m031" in mm.active_missions:
		# Research: Sector Alpha Decryption (the actual zone door) — v132 retarget
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("zone_5_access")
			if widget: target_to_pulse = widget

	elif "m032" in mm.active_missions:
		# Combat: Alpha Sector Dominance (Alien Frigate)
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("sector_alpha")
			target_to_pulse = page.get_enemy_card("z5_alien_frigate")

	elif "m032a" in mm.active_missions:
		# Combat: Harbinger Hunt (Z5 boss farm for zone_6_access cores) — v132
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("sector_alpha")
			target_to_pulse = page.get_enemy_card("z5_boss_harbinger")

	elif "m033" in mm.active_missions:
		# Combat: Beta Sector Expansion (Ore Guardian)
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("sector_beta")
			target_to_pulse = page.get_enemy_card("z6_ore_guardian")

	elif "m034" in mm.active_missions:
		# Combat: Break the Blockade (Beta Colossus farm for zone_7_access cores)
		# v132: the boss lives in Sector BETA — the old entry focused Gamma, a
		# zone the player can't even have unlocked yet, and found no enemy card.
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("sector_beta")
			target_to_pulse = page.get_enemy_card("z6_boss_colossus")

	# P-onboard: new teaching steps — pulse the nav button until the player visits
	# (visit_page auto-completes on navigation; both pages are always reachable).
	elif "m019b" in mm.active_missions:
		if current_page_name != "inventory": target_to_pulse = inventory_btn
	elif "m019c" in mm.active_missions:
		if current_page_name != "infrastructure": target_to_pulse = infrastructure_btn
	elif "m019d" in mm.active_missions:
		# v135: first directed building — pulse the page, then the first build card.
		if current_page_name != "infrastructure": target_to_pulse = infrastructure_btn
		else:
			var w_b = pages["infrastructure"].get_building_widget("solar_panel")
			if w_b: target_to_pulse = w_b
	elif "m027b" in mm.active_missions:
		if current_page_name != "bounty": target_to_pulse = bounty_btn

	# ── Previously-undirected tutorial steps ──
	# NOTE: the goal_002 Warp breadcrumb used to live here as an elif, but goal_002
	# reveals in PARALLEL with the linear chain — so any active endgame chain mission
	# won the elif ladder and the Warp pulse went dark. It now lives in a post-chain
	# fallback (below), guarded by target_to_pulse == null. v134g.
	elif "m002b" in mm.active_missions:
		# Orphan (in-flight saves): re-pointed to Basic Engineering.
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("basic_engineering")
			if widget: target_to_pulse = widget

	elif "m013b" in mm.active_missions:
		# Gathering: Malachite Ore
		if current_page_name != "gathering": target_to_pulse = gathering_btn
		else:
			pages["gathering"].focus_action("mine_malachite")
			var widget = pages["gathering"].get_widget_by_aid("mine_malachite")
			if widget and not (GameState.gathering_manager.is_active and GameState.gathering_manager.current_action_id == "mine_malachite"):
				target_to_pulse = widget.btn

	elif "m013c" in mm.active_missions:
		# Processing: Refine Copper
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("smelt_copper")
			var widget = page.get_widget_by_aid("smelt_copper")
			if widget and not (pm.is_active and pm.current_recipe_id == "smelt_copper"):
				target_to_pulse = widget.btn

	elif "m016b" in mm.active_missions:
		# Designer: pulse the exact empty slot to fill next (weapon, then shield)
		if current_page_name != "designer": target_to_pulse = designer_btn
		else:
			var sm = GameState.shipyard_manager
			var has_w := false
			var has_s := false
			for mid_v in sm.loadout.values():
				if mid_v and mid_v in sm.modules:
					var st: String = sm.modules[mid_v].get("slot_type", "")
					if st == "weapon": has_w = true
					elif st == "shield": has_s = true
			var dp = pages["designer"]
			var want := "weapon" if not has_w else ("shield" if not has_s else "")
			if want != "" and dp.has_method("get_slot_widget"):
				dp.focus_slot(want)
				target_to_pulse = dp.get_slot_widget(want)
			elif dp.has_method("get_coach_anchor"):
				target_to_pulse = dp.get_coach_anchor("schematic")

	elif "m024b" in mm.active_missions:
		# Processing: craft repair kits. Hull patches first; then Shield Boosters —
		# but the Booster recipe eats a Battery Cell (BatteryT1) each, and the
		# power-first reorder no longer teaches that on the main path. Route to the
		# cell craft until enough are stocked for the remaining boosters, THEN boosters.
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			var _res = GameState.resources
			var need_hull: bool = _res.get_element_amount("EmergencyPatch") < 5
			var need_booster: int = 5 - int(_res.get_element_amount("BasicBooster"))
			var have_cells: float = _res.get_element_amount("BatteryT1")
			var rid := ""
			if need_hull:
				rid = "craft_emergency_patch"
			elif need_booster > 0 and have_cells < need_booster:
				rid = "craft_battery_t1"   # make Battery Cells for the boosters first
			else:
				rid = "craft_basic_booster"
			page.focus_tab(rid)
			var widget = page.get_widget_by_aid(rid)
			if widget and not (pm.is_active and pm.current_recipe_id == rid):
				target_to_pulse = widget.btn

	elif "m024b2" in mm.active_missions:
		# Designer: pulse the exact empty consumable slot (hull, then shield)
		if current_page_name != "designer": target_to_pulse = designer_btn
		else:
			var sm = GameState.shipyard_manager
			var dp = pages["designer"]
			var want := "consumable_hull" if sm.consumable_hull_slot == "" else ("consumable_shield" if sm.consumable_shield_slot == "" else "")
			# v141: also arrow the consumable to grab in the Armory (hull first, then
			# shield). "consumable" filter + hull/shield sub-type dims the rest and
			# stamps the coach arrow on the right kit. m024b2 is in _any_equip_active
			# below so this filter survives the per-frame clear.
			if want != "" and dp.has_method("set_equip_focus_filter"):
				dp.set_equip_focus_filter("consumable", "hull" if want == "consumable_hull" else "shield")
			if want != "" and dp.has_method("get_slot_widget"):
				dp.focus_slot(want)
				target_to_pulse = dp.get_slot_widget(want)
			elif dp.has_method("get_coach_anchor"):
				target_to_pulse = dp.get_coach_anchor("consumables")

	elif "m025b" in mm.active_missions:
		# Processing: Smelt Steel
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("smelt_steel_basic")
			var widget = page.get_widget_by_aid("smelt_steel_basic")
			if widget and not (pm.is_active and pm.current_recipe_id == "smelt_steel_basic"):
				target_to_pulse = widget.btn

	elif "m026b" in mm.active_missions:
		# Shipyard: Construct Industrial Frigate
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			pages["shipyard"].focus_hull_tab("frigate_hull")
			target_to_pulse = pages["shipyard"].get_hull_widget("frigate_hull")

	elif "m026c" in mm.active_missions:
		# Combat: Farm a RARE drop in Lunar Orbit
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("lunar_orbit")
			target_to_pulse = page.get_enemy_card("z1_lunar_drone")

	elif "m026d" in mm.active_missions:
		# Designer: pulse the weapon slot to swap in a RARE+ weapon
		if current_page_name != "designer": target_to_pulse = designer_btn
		else:
			var dp = pages["designer"]
			if dp.has_method("get_slot_widget"):
				dp.focus_slot("weapon")
				target_to_pulse = dp.get_slot_widget("weapon")
			elif dp.has_method("get_coach_anchor"):
				target_to_pulse = dp.get_coach_anchor("schematic")

	elif "m026e" in mm.active_missions:
		# Combat: Defeat Rogue Architect (Lunar Orbit boss)
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("lunar_orbit")
			target_to_pulse = page.get_enemy_card("z1_boss_architect")

	# v134: the v107 AdvCircuit discovery beats (m029a1..a5) never had pulses —
	# every OTHER tutorial research/craft step glows its target. Complete the set.
	elif "m029a1" in mm.active_missions:
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("adv_materials")
			if widget: target_to_pulse = widget

	elif "m029a2" in mm.active_missions:
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("metallurgy_advanced")
			if widget: target_to_pulse = widget

	elif "m029a3" in mm.active_missions:
		# Processing: Structural Components
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("craft_structural_component")
			var widget = page.get_widget_by_aid("craft_structural_component")
			if widget and not (pm.is_active and pm.current_recipe_id == "craft_structural_component"):
				target_to_pulse = widget.btn

	elif "m029a5" in mm.active_missions:
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("automation")
			if widget: target_to_pulse = widget

	# v145 (H): the titanium beat. Both mine_dolomite and refine_titanium unlocked at
	# m029a1 and were never taught, so route the two hops need-aware (mirrors m019/m028):
	# no ore -> quarry Dolomite, ore in hand -> pulse Titanium Reduction.
	elif "m029a6t" in mm.active_missions:
		var _dol: float = GameState.resources.get_element_amount("Dolomite")
		if _dol < 2:
			if current_page_name != "gathering": target_to_pulse = gathering_btn
			else:
				pages["gathering"].focus_action("mine_dolomite")
				var w = pages["gathering"].get_widget_by_aid("mine_dolomite")
				if w and not (GameState.gathering_manager.is_active and GameState.gathering_manager.current_action_id == "mine_dolomite"):
					target_to_pulse = w.btn
		else:
			if current_page_name != "processing": target_to_pulse = processing_btn
			else:
				var pm = GameState.processing_manager
				var page = pages["processing"]
				page.focus_tab("refine_titanium")
				var w = page.get_widget_by_aid("refine_titanium")
				if w and not (pm.is_active and pm.current_recipe_id == "refine_titanium"):
					target_to_pulse = w.btn

	elif "m029b" in mm.active_missions:
		# Processing: Advanced Circuitry
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			page.focus_tab("craft_adv_circuit")
			var widget = page.get_widget_by_aid("craft_adv_circuit")
			if widget and not (pm.is_active and pm.current_recipe_id == "craft_adv_circuit"):
				target_to_pulse = widget.btn

	elif "m030e" in mm.active_missions:
		# Research: Mars Debris Clearance (zone_3_access)
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("zone_3_access")
			if widget: target_to_pulse = widget

	elif "m030f" in mm.active_missions:
		# Combat: Scavenger Mechs (Mars Debris)
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("mars_debris")
			target_to_pulse = page.get_enemy_card("z3_scavenger_mech")

	elif "m030g" in mm.active_missions:
		# Research: Glacier Belt Expedition (zone_4_access)
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("zone_4_access")
			if widget: target_to_pulse = widget

	elif "m030h" in mm.active_missions:
		# Combat: Ice Wraiths (Cryofield)
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("cryofield")
			target_to_pulse = page.get_enemy_card("z4_ice_wraith")

	elif "m032d" in mm.active_missions:
		# Combat: Void Artifacts from Sector Alpha ships
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("sector_alpha")
			target_to_pulse = page.get_enemy_card("z5_alien_frigate")

	# P1 Onboarding: clear the Designer's equip-mission Armory filter when
	# no equip mission is active. set_equip_focus_filter and
	# clear_equip_focus_filter are both idempotent so calling per-tick is cheap.
	# v161: "active" is not the same as "still needs doing". A finished-but-unclaimed
	# mission STAYS in active_missions, and the claim-reminder branch above wins the
	# elif chain the moment it completes — so the branch that set the focus filter
	# never runs again, and nothing cleared it. Result: the player equips the part,
	# the mission goes claimable, and the Armory is left permanently dimmed to one
	# slot type ("gear cards become dim"). Gate on _equip_step_live: active AND not
	# completed.
	var _any_equip_active: bool = (
		_equip_step_live("m005c")   # v134g: battery-equip step
		or _equip_step_live("m007b")
		or _equip_step_live("m015b")
		or _equip_step_live("m022b")
		or _equip_step_live("m024c")
		or _equip_step_live("m024a2")   # v140: armor-equip step (else its focus filter clears each frame → rebuild_storage thrash → armory unhoverable/undraggable)
		or _equip_step_live("m024b2")   # v141: consumable-equip step — same thrash guard
		# v134b: the damage-triangle fight steps have a designer EQUIP phase —
		# keep the weapon filter alive exactly while that phase sets it.
		or (_equip_step_live("m017b") and _count_weapon_type_equipped("energy") < 2)
		or (_equip_step_live("m017d") and _count_weapon_type_equipped("explosive") < 2)
	)
	if not _any_equip_active and pages.has("designer"):
		var _dp = pages["designer"]
		if _dp.has_method("clear_equip_focus_filter"):
			_dp.clear_equip_focus_filter()

	# P-onboard: deliberate hands-off stretch (Z5 → Z10). By the Sector chapter the
	# player has been shown every system; stop herding them with the per-step pulse —
	# these mid-game steps teach no NEW mechanic (just "clear zone N"). The Objective
	# chip + claim badge keep the floor safe, and the repair fallback below still fires.
	# (Tunable: edit this id list to move the hand-holding cutoff.)
	if target_to_pulse != null:
		for _wid in ["m031", "m032", "m032b", "m032c", "m033", "m033b", "m033c", "m034"]:
			if _wid in mm.active_missions:
				target_to_pulse = null
				break

	# P-onboard: the warp decision must NOT go dark. Re-assert the Warp Core pulse
	# HERE (not in the elif ladder) so a suppressed endgame chain mission — which the
	# hands-off block just NULLed above — can't shadow it. Fires only when nothing else
	# claimed the pulse, and takes priority over the repair nudge below (endgame > dent).
	if target_to_pulse == null and "goal_002" in mm.active_missions \
			and GameState.game_settings.get("z10_cleared", false):
		if current_page_name != "warp" and is_instance_valid(warp_btn) and warp_btn.visible:
			target_to_pulse = warp_btn

	# v141c: a mission DIRECTIVE is TUTORIAL-only. The explicit ladder above also
	# has branches for chapter/endgame ids (m027..m034 share the m0 id space but run
	# AFTER the tutorial, concurrently with [CORE GOAL] arcs), so it can point the
	# arrow at one of several simultaneously-active missions — arbitrarily. Once the
	# player is past onboarding those arcs are self-directed. If the ladder produced
	# a pulse but no tutorial mission is active, that pulse came from a non-tutorial
	# branch: drop it. The claim reminder (mission_btn) is exempt — it's a "collect
	# your reward" nudge, not a task directive, and has no page ambiguity.
	if not can_claim_tutorial and target_to_pulse != null and not _has_active_tutorial(mm):
		target_to_pulse = null

	# GENERIC fallback — route a TUTORIAL mission the hand-written ladder doesn't
	# name (belt-and-braces for onboarding steps added without a bespoke branch).
	# _generic_mission_pulse is itself tutorial-gated, so it never revives a
	# chapter/goal pulse the guard above just cleared.
	if target_to_pulse == null:
		target_to_pulse = _generic_mission_pulse(mm)

	# P1 Onboarding — Repair routing.
	# v125: repair moved OFF the Shipyard (its repair button was removed in v124) —
	# it's now the Combat-HUD HULL consumable button, which works out of combat too
	# (no cooldown when not fighting). So when no mission demands a pulse and the
	# hull is damaged, route to the COMBAT tab — but only if a hull repair kit is
	# actually equipped + stocked (otherwise there's nothing to tap there, so we
	# don't nudge to a dead end). Once on Combat, the page's own low-hull alarm
	# pulses the HULL kit. Mission pulses always win — this is a pure fallback.
	if target_to_pulse == null:
		var sm_ref = GameState.shipyard_manager
		var cm_ref = GameState.combat_manager
		# v134g: don't fire the repair nudge while the player is actively gathering
		# or crafting. An active skilling mission (e.g. m019 "craft 10 Circuits")
		# returns a NULL pulse mid-craft — pulsing the button they're already using
		# is pointless — but that null let this fallback hijack it and pulse COMBAT,
		# reading as "the mission wants combat" during a crafting step. The player is
		# busy on the right task; repair can wait until they're idle.
		var _busy_skilling: bool = (GameState.gathering_manager and GameState.gathering_manager.is_active) \
			or (GameState.processing_manager and GameState.processing_manager.is_active)
		# v141d: never fire the repair nudge while a TUTORIAL mission is active. The
		# generic pulse returns null when the player is already ON the active mission's
		# page (task in progress) — that null must NOT unleash a Combat repair nudge,
		# or a single atlas_lookup step ping-pongs atlas <-> combat. Repair only nudges
		# once onboarding is idle.
		if sm_ref and not _busy_skilling and not _has_active_tutorial(mm) \
				and sm_ref.current_hp < sm_ref.max_hp \
				and sm_ref.consumable_hull_slot != "" \
				and GameState.resources.get_element_amount(sm_ref.consumable_hull_slot) >= 1 \
				and current_page_name != "combat" \
				and not (cm_ref and cm_ref.in_combat):
			target_to_pulse = combat_btn

	# Apply final decision
	if target_to_pulse:
		start_hint_pulse(target_to_pulse)
	else:
		stop_hint_pulse()


# v141c: type-driven directive target for missions the explicit chain doesn't
# name. Returns null when the player is already where the mission wants them (or
# already doing the work), so it degrades to "no arrow" rather than nagging.
# v141c: is any [TUTORIAL]-tagged mission currently active? The tutorial is the
# single linear onboarding chain; goals/chapters/endgame run concurrently and
# are self-directed, so only this returning true licenses a mission arrow.
func _has_active_tutorial(mm) -> bool:
	for mid in mm.active_missions:
		var m: Dictionary = mm.missions.get(mid, {})
		if not m.is_empty() and not m.get("completed", false) and String(m.get("tag", "")) == "[TUTORIAL]":
			return true
	return false


func _generic_mission_pulse(mm) -> Control:
	# v141d: pick the SINGLE earliest-in-chain active TUTORIAL mission (definition
	# order — mm.missions preserves it) and route to its page. That one mission OWNS
	# the arrow. Two rules kill the ping-pong the old loop caused:
	#   • Already ON the mission's page? return null — the page's own coaching (search
	#     box, atlas glow/coach card, slot pulse) takes over. DON'T advance to a
	#     different tutorial mission (that made the arrow flip atlas <-> combat).
	#   • Unrouted type (discover) or a hidden target page? return null too.
	# The tutorial is meant to be a single linear chain; if two are somehow active,
	# the earliest deterministically wins instead of the arrow jumping every frame.
	# Frontier = the LAST (furthest-along) active tutorial mission in definition order.
	# A stale early beat — e.g. an atlas_lookup a mid-chain insert re-activated on an
	# old save (auto-completed by sync now, but belt-and-braces) — must never outrank
	# the player's real current step.
	var chosen := ""
	for mid in mm.missions:
		if not mid in mm.active_missions:
			continue
		var cm: Dictionary = mm.missions[mid]
		if cm.is_empty() or cm.get("completed", false) or String(cm.get("tag", "")) != "[TUTORIAL]":
			continue
		chosen = mid
	if chosen == "":
		return null
	var m: Dictionary = mm.missions[chosen]
	var page := ""
	match String(m.get("type", "")):
		"research":
			page = "research"
		"defeat", "drop_rarity":
			page = "combat"
		"build", "construct":
			page = "infrastructure"
		"craft", "craft_matrix":
			page = "shipyard"
		"loadout_check", "equip_consumables", "loadout_rare_weapon", \
		"loadout_rare_weapon_type", "hack_apply", "socket_check":
			page = "designer"
		"warp_perform":
			page = "warp"
		"overclock_install":
			page = "infrastructure"
		"atlas_lookup":
			page = "atlas"
		"visit_page":
			page = String(m.get("target", ""))
		"gather", "gather_multi":
			page = _skill_page_for_targets(m)
	# On the right page (task in progress there) or nowhere to send them → no arrow.
	if page == "" or page == current_page_name:
		return null
	var btn := _get_btn_for_page(page)
	# A hidden button is not a directive — pulsing an invisible node strands the arrow.
	return btn if (btn and btn.visible) else null


# "gather" missions cover BOTH mining and Engineering output (m011 "produce 50
# Carbon" is type gather). Decide by where the material actually comes from:
# a gathering loot table means Mine, a recipe output means Engineering.
func _skill_page_for_targets(m: Dictionary) -> String:
	var syms := []
	if String(m.get("type", "")) == "gather_multi":
		for s in (m.get("target", {}) as Dictionary):
			syms.append(String(s))
	else:
		syms.append(String(m.get("target", "")))

	var gm = GameState.gathering_manager
	var pm = GameState.processing_manager
	for sym in syms:
		if gm:
			for aid in gm.actions:
				for e in gm.actions[aid].get("loot_table", []):
					if String(e[0]) == sym:
						return "gathering"
		if pm:
			for rid in pm.recipes:
				if (pm.recipes[rid].get("output", {}) as Dictionary).has(sym):
					return "processing"
	return ""


var hint_tween: Tween
var pulsing_button: Control = null
var hint_arrow: TextureRect = null   # gold arrow that bobs at the nudged target
var _hint_arrow_phase: float = 0.0   # drives the bob; advanced per-frame in _process
var _pulse_base_scale: Vector2 = Vector2.ONE  # target's own scale (research nodes = 0.75); pulse relative to it

func start_hint_pulse(control: Control):
	# Same target as last frame: the per-frame tracker in _process keeps the arrow
	# glued to it (incl. scrolling), so there's nothing to re-do here.
	if pulsing_button == control: return

	stop_hint_pulse()
	pulsing_button = control

	# Set pivot to center for scale pulse
	control.pivot_offset = control.size / 2
	# Pulse RELATIVE to the target's own scale — research node widgets sit at 0.75, so a
	# hardcoded 1.0/1.03 pulse would inflate them ~33% and leave them stuck big.
	_pulse_base_scale = control.scale

	hint_tween = create_tween().set_loops()
	# Gentle glow now — the bobbing arrow (below) is the primary "go here" cue, so the
	# button just breathes softly instead of the old over-bright gold flash.
	var pulse_color = Color(1.22, 1.12, 0.72)
	hint_tween.parallel().tween_property(control, "modulate", pulse_color, 0.5).set_trans(Tween.TRANS_SINE)
	hint_tween.parallel().tween_property(control, "scale", _pulse_base_scale * 1.03, 0.5).set_trans(Tween.TRANS_SINE)

	hint_tween.parallel().tween_property(control, "modulate", Color.WHITE, 0.5).set_trans(Tween.TRANS_SINE).set_delay(0.5)
	hint_tween.parallel().tween_property(control, "scale", _pulse_base_scale, 0.5).set_trans(Tween.TRANS_SINE).set_delay(0.5)

	_show_hint_arrow(control)

func stop_hint_pulse():
	if hint_tween:
		hint_tween.kill()
		hint_tween = null

	if pulsing_button:
		pulsing_button.modulate = Color.WHITE
		pulsing_button.scale = _pulse_base_scale   # restore the target's own scale (e.g. 0.75 research nodes)
		pulsing_button = null

	if hint_arrow and is_instance_valid(hint_arrow):
		hint_arrow.visible = false

func _ensure_hint_arrow() -> void:
	if hint_arrow and is_instance_valid(hint_arrow):
		return
	hint_arrow = TextureRect.new()
	hint_arrow.name = "MissionHintArrow"
	hint_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_arrow.custom_minimum_size = Vector2(40, 40)
	hint_arrow.size = Vector2(40, 40)
	hint_arrow.pivot_offset = Vector2(20, 20)
	hint_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hint_arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hint_arrow.modulate = Color(1.0, 0.86, 0.32)   # gold
	hint_arrow.visible = false
	var atex := load("res://assets/icons/ui/coach_arrow.svg") as Texture2D
	if atex:
		hint_arrow.texture = atex
	# ModalLayer (CanvasLayer) → screen-space coords, draws above the sidebar.
	if modal_layer:
		modal_layer.add_child(hint_arrow)
	else:
		add_child(hint_arrow)

func _show_hint_arrow(_control: Control) -> void:
	_ensure_hint_arrow()
	_hint_arrow_phase = 0.0
	_position_hint_arrow()

# Re-run every frame (from _process) so the arrow follows a target that scrolls
# inside a panel, and hides when the target scrolls out of its ScrollContainer.
func _position_hint_arrow() -> void:
	if hint_arrow == null:
		return
	var control := pulsing_button
	if not (control and is_instance_valid(control) and control.is_visible_in_tree() and control.size.x > 1.0):
		hint_arrow.visible = false
		return
	var r := _visual_global_rect(control)
	# If the target lives inside a ScrollContainer and is scrolled out of view, hide
	# the arrow instead of pointing at empty space (or at a clipped ghost slot).
	var clip := _hint_clip_rect(control)
	if clip.size.x > 0.0:
		var vis := r.intersection(clip)
		if vis.size.x < 3.0 or vis.size.y < 3.0:
			hint_arrow.visible = false
			return
		r = vis   # aim at the still-visible slice of a partially-scrolled target
	var vp := get_viewport_rect().size
	var target_c := r.position + r.size * 0.5
	var aw := hint_arrow.size.x
	# The pulse targets both sidebar buttons and in-page widgets (enemy cards, equip
	# slots, research nodes). Pick a side that stays on-screen and clear of the target:
	# sidebar → right, pointing left; otherwise → above (or below) it.
	var acenter: Vector2
	if _is_in_sidebar(control):
		acenter = Vector2(r.end.x + 6.0 + aw * 0.5, target_c.y)          # right of sidebar btn, points left
	elif r.position.y - (aw + 10.0) >= 8.0:
		acenter = Vector2(target_c.x, r.position.y - 6.0 - aw * 0.5)     # above target, points down
	else:
		acenter = Vector2(target_c.x, r.end.y + 6.0 + aw * 0.5)          # below target, points up
	# Keep the whole arrow inside the viewport.
	acenter.x = clampf(acenter.x, aw * 0.5 + 2.0, vp.x - aw * 0.5 - 2.0)
	acenter.y = clampf(acenter.y, aw * 0.5 + 2.0, vp.y - aw * 0.5 - 2.0)
	var toward := target_c - acenter
	if toward.length() < 1.0:
		toward = Vector2(-1, 0)
	toward = toward.normalized()
	# Sine-driven bob toward the target (0..9px); phase advanced per-frame in _process.
	var bob: float = (sin(_hint_arrow_phase * 6.0) * 0.5 + 0.5) * 9.0
	hint_arrow.rotation = toward.angle()   # SVG points right at 0° → rotate to aim at the target
	hint_arrow.position = (acenter - hint_arrow.size * 0.5) + toward * bob
	hint_arrow.visible = true

# Visual on-screen rect of the target, accounting for its own scale + pivot. Research
# node widgets render at 0.75; get_global_rect() ignores scale and would sit off-target.
func _visual_global_rect(control: Control) -> Rect2:
	var xf := control.get_global_transform()
	var sz := control.size
	var p0 := xf * Vector2.ZERO
	var p1 := xf * Vector2(sz.x, 0.0)
	var p2 := xf * Vector2(0.0, sz.y)
	var p3 := xf * sz
	var mn := Vector2(minf(minf(p0.x, p1.x), minf(p2.x, p3.x)), minf(minf(p0.y, p1.y), minf(p2.y, p3.y)))
	var mx := Vector2(maxf(maxf(p0.x, p1.x), maxf(p2.x, p3.x)), maxf(maxf(p0.y, p1.y), maxf(p2.y, p3.y)))
	return Rect2(mn, mx - mn)

# True only for the left-rail nav buttons, so only they get right-of/point-left
# placement; every in-page target (cards, slots, research nodes) points from above/below.
func _is_in_sidebar(control: Control) -> bool:
	var sb := get_node_or_null("HBoxContainer/Sidebar")
	return sb != null and (sb as Node).is_ancestor_of(control)

# Intersection of all ScrollContainer ancestors' global rects = the region where
# `control` is actually on-screen. Empty Rect2 if it isn't inside any scroll view.
func _hint_clip_rect(control: Control) -> Rect2:
	var rect := Rect2()
	var has := false
	var n: Node = control.get_parent()
	while n != null:
		if n is ScrollContainer:
			var gr: Rect2 = (n as ScrollContainer).get_global_rect()
			if has:
				rect = rect.intersection(gr)
			else:
				rect = gr
				has = true
		n = n.get_parent()
	if has:
		return rect
	return Rect2()

func _on_gathering_btn_pressed(): switch_to("gathering")
func _on_processing_btn_pressed(): switch_to("processing")
func _on_infrastructure_btn_pressed(): switch_to("infrastructure")
func _on_shipyard_btn_pressed(): switch_to("shipyard")
func _on_research_btn_pressed(): switch_to("research")
func _on_combat_btn_pressed(): switch_to("combat")
func _on_mission_btn_pressed(): switch_to("mission")
func _on_designer_btn_pressed(): switch_to("designer")
func _on_inventory_btn_pressed(): switch_to("inventory")
func _on_atlas_btn_pressed():
	switch_to("atlas")

func _on_warp_btn_pressed():
	switch_to("warp")
func _on_options_btn_pressed(): switch_to("options")
func _on_bounty_btn_pressed(): switch_to("bounty")
func _on_quest_btn_pressed(): switch_to("quest")

func _on_menu_btn_pressed():
	GameState.save_game()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_game_resetted():
	switch_to("mission")
