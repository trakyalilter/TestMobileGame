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
	
	# v84.2: Research Navigation QoL
	UITheme.research_navigation_requested.connect(_on_research_navigation_requested)

	# v107: P0 Prestige Discovery Fanfare — detect the moment the player
	# crosses the warp shard threshold for the first time. We listen on
	# every currency_added because credits feed the progress_score formula.
	# v110: Warp Core reveals when Zone 6 research completes (a content
	# milestone) rather than at an arbitrary credit threshold. tech_unlocked
	# fires from research_manager.unlock_tech.
	GameState.research_manager.tech_unlocked.connect(_on_tech_unlocked_for_warp_reveal)

	# v109: Recursion discovery — the Recursion research tab is always visible
	# but easily missed, and is unusable until the player has Void Artifacts
	# (the shared gate item for every lane). Fire a one-shot pointer the first
	# time one is acquired.
	GameState.resources.element_added.connect(_on_element_added_for_recursion_reveal)

func _on_element_added_for_recursion_reveal(symbol: String, _amount: float) -> void:
	if symbol != "VoidArtifact":
		return
	if GameState.game_settings.get("recursion_revealed", false):
		return
	GameState.game_settings["recursion_revealed"] = true
	UITheme.show_notification(
		"⟨ RECURSION PROTOCOLS ONLINE ⟩  Spend Void Artifacts on the Research page's RECURSION tab for infinite, permanent global bonuses.",
		Color(0.55, 0.85, 1.0)
	)

func _on_tech_unlocked_for_warp_reveal(tech_id: String) -> void:
	# v110: Reveal the Warp Core when the player completes Zone 6 research.
	if tech_id != "zone_6_access":
		return
	if GameState.game_settings.get("warp_first_revealed", false):
		return
	GameState.game_settings["warp_first_revealed"] = true
	_update_sidebar_styling()  # makes the Warp tab appear immediately
	_fire_warp_reveal_fanfare()

func _fire_warp_reveal_fanfare() -> void:
	# Tell the player something happened AND what to do — the pulsing tab
	# alone doesn't read as an instruction. One self-contained notification
	# beats two-stage messaging.
	UITheme.show_notification(
		"⟨ WARP CORE RESONANCE DETECTED ⟩  A new prestige system is online — open the WARP tab to spend Exotic Matter Shards.",
		Color(0.85, 0.5, 1.0)
	)
	if is_instance_valid(warp_btn):
		var tween := create_tween().set_loops(4)
		tween.tween_property(warp_btn, "modulate", Color(1.5, 1.0, 1.7), 0.5)
		tween.tween_property(warp_btn, "modulate", Color.WHITE, 0.5)

func _on_research_navigation_requested(tech_id: String):
	switch_to("research")
	var res_page = pages.get("research")
	if res_page and res_page.has_method("focus_on_tech"):
		res_page.focus_on_tech(tech_id)

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
	
	atlas_btn.text = "  📖  Atlas"

	
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
	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.065, 0.10, 0.95)
	style.set_corner_radius_all(5)
	style.border_width_left = 3
	style.border_color = color
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 11)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	panel.add_child(margin)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var glyph = Label.new()
	glyph.text = _status_glyph(color)
	glyph.custom_minimum_size = Vector2(16, 0)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 15)
	glyph.add_theme_color_override("font_color", color)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(glyph)

	var msg = Label.new()
	msg.text = text
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.2))
	msg.add_theme_font_size_override("font_size", 13)
	msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(msg)

	notification_container.add_child(panel)
	_prune_feed()

	# Fade In (0.2s) -> Hold (1.6s) -> Fade Out (0.3s) -> free.
	panel.modulate.a = 0.0
	var tween = panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE)
	tween.tween_interval(1.6)
	tween.tween_property(panel, "modulate:a", 0.0, 0.3)
	tween.tween_callback(panel.queue_free)

# Status glyph inferred from the intent colour callers already pass:
# alert (red/orange) ! · info (cyan/blue/purple) i · success (green) ✓ ·
# state/neutral (gold/amber/grey) ›.
func _status_glyph(c: Color) -> String:
	if c.b > 0.7 and c.b >= c.r * 0.8: return "i"
	if c.g > 0.65 and c.r < 0.75: return "✓"
	if c.r > 0.7 and c.g < 0.6: return "!"
	return "›"

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
			e["delta_lbl"].text = "+%s" % UITheme.format_number(e["accum"])
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
	var chip_lbl := Label.new()
	chip_lbl.text = "★" if is_xp else _chip_abbrev(str(info.get("symbol", "?")))
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
	delta_lbl.text = "+%s" % UITheme.format_number(int(info.get("amount", 0)))
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
	tw.tween_interval(1.6)
	tw.tween_property(panel, "modulate:a", 0.0, 0.35)
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
	while live.size() > 5:
		var oldest = live.pop_front()
		oldest.queue_free()

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
	
	# THEMATIC: Progressive Disclosure (Early & Mid-Game Gates)
	var has_basic_eng = GameState.research_manager.is_tech_unlocked("applied_physics")
	var has_shipwright = GameState.research_manager.is_tech_unlocked("shipwright_1")
	
	# 1. Ship management & Combat become available at Applied Physics
	shipyard_btn.visible = has_basic_eng
	designer_btn.visible = has_basic_eng
	combat_btn.visible = has_basic_eng

	
	# v72.0: Bounty Board unlocks at Asteroid Clearance (first real combat sector)
	var has_asteroid_clearance = GameState.research_manager.is_tech_unlocked("asteroid_clearance")
	bounty_btn.visible = has_asteroid_clearance
	# Quests appear once the player has core gameplay loops available
	quest_btn.visible = has_basic_eng
	
	# 3. Warp Core reveals when Zone 6 research (zone_6_access) completes — a
	# content milestone, so the "Warp Core Resonance Detected" fanfare lands
	# at a deliberate point in progression. The transition fanfare fires from
	# _on_tech_unlocked_for_warp_reveal; this gate also reveals silently for
	# saves that already passed Zone 6 (or already prestiged) before v110.
	var revealed: bool = GameState.game_settings.get("warp_first_revealed", false)
	if not revealed:
		var wm_ref = GameState.warp_manager
		if GameState.research_manager.is_tech_unlocked("zone_6_access"):
			revealed = true
		elif wm_ref.total_warps > 0 or wm_ref.warp_shards > 0:
			revealed = true
		if revealed:
			GameState.game_settings["warp_first_revealed"] = true
	warp_btn.visible = revealed

	# Fleet Command reveals post-first-warp (alongside the Z11 endgame), where the
	# material glut exists to sink. See docs/FLEET_SIEGE_GATES.md.
	if is_instance_valid(fleet_btn):
		fleet_btn.visible = GameState.fleet_manager.is_unlocked() if GameState.fleet_manager else false
	


	

	
	# Style non-button sidebar elements
	for child in sidebar_list.get_children():
		if child is Label:
			if child.name == "LogoLabel":
				child.add_theme_font_size_override("font_size", 14)
				child.add_theme_color_override("font_color", Color(0.42, 0.84, 1.00))
				child.modulate = Color.WHITE
			else:
				child.add_theme_font_size_override("font_size", 9)
				child.add_theme_color_override("font_color", Color(0.28, 0.36, 0.52))
				child.modulate = Color.WHITE

	# Warp button keeps its purple accent
	if is_instance_valid(warp_btn) and warp_btn.visible:
		var wc := Color(0.78, 0.50, 1.00) if current_page_name != "warp" else Color(0.92, 0.72, 1.00)
		warp_btn.add_theme_color_override("font_color", wc)
		warp_btn.add_theme_color_override("icon_normal_color", wc)

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

	# 3. Claim badges (refresh ~4 Hz)
	_claim_badge_tick += delta
	if _claim_badge_tick >= 0.25:
		_claim_badge_tick = 0.0
		_update_claim_badges()
		_maybe_show_warp_coach()

func _update_navigation_hints():
	# A page tour owns the spotlight while it's open — don't double up.
	if _coach_active():
		stop_hint_pulse()
		return
	var mm = GameState.mission_manager
	if not mm: return
	
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
			var widget = pages["gathering"].get_widget_by_aid("gather_dirt")
			if widget and not (GameState.gathering_manager.is_active and GameState.gathering_manager.current_action_id == "gather_dirt"):
				target_to_pulse = widget.btn
				
	elif "m002" in mm.active_missions:
		# Research Basic Engineering
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("basic_engineering")
			if widget: target_to_pulse = widget
			
	elif "m003" in mm.active_missions:
		# Research Fluid Dynamics
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("fluid_dynamics")
			if widget: target_to_pulse = widget
			
	elif "m004" in mm.active_missions:
		# Gather Water
		if current_page_name != "gathering": target_to_pulse = gathering_btn
		else:
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
		# Designer: pulse the empty weapon slot + dim non-weapon Armory cards.
		if current_page_name != "designer": target_to_pulse = designer_btn
		else:
			var dp = pages["designer"]
			if dp.has_method("set_equip_focus_filter"):
				dp.set_equip_focus_filter("weapon")
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

	elif "m018" in mm.active_missions:
		# Research: Industrial Logistics Hub
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("industrial_logistics")
			if widget: target_to_pulse = widget

	elif "m018b" in mm.active_missions:
		# Research: Automated Logistics Hub
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("automated_logistics")
			if widget: target_to_pulse = widget
			
	elif "m019" in mm.active_missions:
		# Processing: Circuits
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

	elif "m016c" in mm.active_missions:
		# Combat orientation — pulse the Combat tab until the player visits;
		# the visit_page hook in switch_to() auto-completes the mission.
		if current_page_name != "combat":
			target_to_pulse = combat_btn

	elif "m025" in mm.active_missions:
		# Research: Smelting
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("smelting")
			if widget: target_to_pulse = widget

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
		# Gathering: Sector Alpha (Cassiterite)
		if current_page_name != "gathering": target_to_pulse = gathering_btn
		else:
			var widget = pages["gathering"].get_widget_by_aid("mine_cassiterite")
			if widget and not (GameState.gathering_manager.is_active and GameState.gathering_manager.current_action_id == "mine_cassiterite"):
				target_to_pulse = widget.btn

	elif "m029" in mm.active_missions:
		# Shipyard: Zone 2 Armor (Carbon Fiber Plate)
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			var page = pages["shipyard"]
			page.focus_module_tab("z2_armor")
			target_to_pulse = page.get_module_widget("z2_armor")

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
			target_to_pulse = pages["shipyard"].get_hull_widget("destroyer_hull")

	elif "m032b" in mm.active_missions:
		# Research: Deep Space Nav (Sector Beta)
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("deep_space_nav")
			if widget: target_to_pulse = widget
			
	elif "m032c" in mm.active_missions:
		# Shipyard: Battlecruiser
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			target_to_pulse = pages["shipyard"].get_hull_widget("battlecruiser_hull")
			
	elif "m033b" in mm.active_missions:
		# Research: Radiation Shielding (Sector Gamma)
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("radiation_shielding")
			if widget: target_to_pulse = widget
			
	elif "m033c" in mm.active_missions:
		# Shipyard: Dreadnought
		if current_page_name != "shipyard": target_to_pulse = shipyard_btn
		else:
			target_to_pulse = pages["shipyard"].get_hull_widget("dreadnought_hull")

	elif "m031" in mm.active_missions:
		# Research: Sector Alpha Decryption
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("sector_alpha_decryption")
			if widget: target_to_pulse = widget
			
	elif "m032" in mm.active_missions:
		# Combat: Alpha Sector Dominance (Alien Frigate)
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("sector_alpha")
			target_to_pulse = page.get_enemy_card("z5_alien_frigate")

	elif "m033" in mm.active_missions:
		# Combat: Beta Sector Expansion (Ore Guardian)
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("sector_beta")
			target_to_pulse = page.get_enemy_card("z6_ore_guardian")

	elif "m034" in mm.active_missions:
		# Combat: Gamma Sector Control (Gamma Colossus)
		if current_page_name != "combat": target_to_pulse = combat_btn
		else:
			var page = pages["combat"]
			page.focus_zone("sector_gamma")
			target_to_pulse = page.get_enemy_card("z6_boss_colossus")

	# ── Previously-undirected tutorial steps ──
	elif "m002b" in mm.active_missions:
		# Research: Applied Physics
		if current_page_name != "research": target_to_pulse = research_btn
		else:
			var widget = pages["research"].get_node_widget("applied_physics")
			if widget: target_to_pulse = widget

	elif "m013b" in mm.active_missions:
		# Gathering: Malachite Ore
		if current_page_name != "gathering": target_to_pulse = gathering_btn
		else:
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
		# Processing: craft repair kits (hull patches first, then shield boosters)
		if current_page_name != "processing": target_to_pulse = processing_btn
		else:
			var pm = GameState.processing_manager
			var page = pages["processing"]
			var need_hull = GameState.resources.get_element_amount("EmergencyPatch") < 5
			var rid = "craft_emergency_patch" if need_hull else "craft_basic_booster"
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
		# Research: Cryofield Expedition (zone_4_access)
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
	var _any_equip_active: bool = (
		"m007b" in mm.active_missions
		or "m015b" in mm.active_missions
		or "m022b" in mm.active_missions
		or "m024c" in mm.active_missions
	)
	if not _any_equip_active and pages.has("designer"):
		var _dp = pages["designer"]
		if _dp.has_method("clear_equip_focus_filter"):
			_dp.clear_equip_focus_filter()

	# P1 Onboarding — Repair routing.
	# When no mission demands a pulse, the hull is damaged, the player is on
	# another page, and they are not mid-combat, pulse the Shipyard sidebar
	# button so they know where to go. Once on Shipyard, the existing red-
	# pulsing Repair button (shipyard_page._update_repair_button) takes over.
	# Mission pulses always win — this is a pure fallback.
	if target_to_pulse == null:
		var sm_ref = GameState.shipyard_manager
		var cm_ref = GameState.combat_manager
		if sm_ref and sm_ref.current_hp < sm_ref.max_hp \
				and current_page_name != "shipyard" \
				and not (cm_ref and cm_ref.in_combat):
			target_to_pulse = shipyard_btn

	# Apply final decision
	if target_to_pulse:
		start_hint_pulse(target_to_pulse)
	else:
		stop_hint_pulse()


var hint_tween: Tween
var pulsing_button: Control = null

func start_hint_pulse(control: Control):
	if pulsing_button == control: return
	
	stop_hint_pulse()
	pulsing_button = control
	
	# Set pivot to center for scale pulse
	control.pivot_offset = control.size / 2
	
	hint_tween = create_tween().set_loops()
	# Vivid Golden Glow + Scale Pulse
	var pulse_color = Color(1.2, 0.9, 0.2) # Over-bright for HDR/Glow feel
	hint_tween.parallel().tween_property(control, "modulate", pulse_color, 0.4).set_trans(Tween.TRANS_SINE)
	hint_tween.parallel().tween_property(control, "scale", Vector2(1.05, 1.05), 0.4).set_trans(Tween.TRANS_SINE)
	
	hint_tween.parallel().tween_property(control, "modulate", Color.WHITE, 0.4).set_trans(Tween.TRANS_SINE).set_delay(0.4)
	hint_tween.parallel().tween_property(control, "scale", Vector2(1.0, 1.0), 0.4).set_trans(Tween.TRANS_SINE).set_delay(0.4)

func stop_hint_pulse():
	if hint_tween:
		hint_tween.kill()
		hint_tween = null
	
	if pulsing_button:
		pulsing_button.modulate = Color.WHITE
		pulsing_button.scale = Vector2(1.0, 1.0)
		pulsing_button = null

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
