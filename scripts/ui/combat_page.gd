extends Control

# v124: sector AND target selection both live in the full-screen Sector Chart
# star-map overlay. The NavPanel is a compact current-sector readout + OPEN STAR
# CHART button; the old TargetPanel enemy-card list is gone (the chart's roster
# replaced it). selected_zone_id holds the engage zone; the manager auto-respawns
# the target after each kill, so no in-HUD list is needed to sustain combat.
# v134h: the NAVIGATION readout card was removed — only the Star Chart button remains.
@onready var open_chart_btn = $Dashboard/HUD/TopHUD/OpenChartBtn
var selected_zone_id: String = ""
var star_map = null
const STAR_MAP_SCRIPT = preload("res://scripts/ui/star_map_overlay.gd")

# Arena Refs
@onready var visualizer = $Dashboard/Visualizer
@onready var radar_lines = $Dashboard/Visualizer/Background/RadarLines
@onready var radar_display = $Dashboard/Visualizer/RadarDisplay
# v134h: SectorThreat / ScanningStatus flavor labels removed from the scene.

@onready var p_name_lbl = $Dashboard/HUD/MidHUD/PlayerStatsOverlay/Margin/VBox/NameLabel
@onready var p_stat_lbl = $Dashboard/HUD/MidHUD/PlayerStatsOverlay/Margin/VBox/StatsLabel
@onready var p_hp_lbl = $Dashboard/HUD/MidHUD/PlayerStatsOverlay/Margin/VBox/Grid/HealthLabel
@onready var p_sh_lbl = $Dashboard/HUD/MidHUD/PlayerStatsOverlay/Margin/VBox/Grid/ShieldLabel
@onready var weapon_battery = $Dashboard/HUD/MidHUD/PlayerStatsOverlay/Margin/VBox/WeaponBattery
@onready var p_buff_container = $Dashboard/HUD/MidHUD/PlayerStatsOverlay/Margin/VBox/BuffContainer

var player_weapon_bars = []
var _weapon_bar_sig: String = ""   # v134h: rebuild bars when weapon types change (loadout swap)

@onready var e_name_lbl = $Dashboard/HUD/MidHUD/EnemyStatsOverlay/Margin/VBox/NameLabel
@onready var e_stat_lbl = $Dashboard/HUD/MidHUD/EnemyStatsOverlay/Margin/VBox/StatsLabel
@onready var e_hp_lbl = $Dashboard/HUD/MidHUD/EnemyStatsOverlay/Margin/VBox/Grid/HealthLabel
@onready var e_sh_lbl = $Dashboard/HUD/MidHUD/EnemyStatsOverlay/Margin/VBox/Grid/ShieldLabel
@onready var e_attack_pb = $Dashboard/HUD/MidHUD/EnemyStatsOverlay/Margin/VBox/E_AttackBar

@onready var scanner_overlay = $Dashboard/HUD/BottomHUD/ScannerOverlay
@onready var loot_lbl = $Dashboard/HUD/BottomHUD/ScannerOverlay/Margin/VBox/Scroll/LootVBox/LootText
var _last_loot_sig: String = ""   # v134h: skip loot-grid rebuild when unchanged

@onready var ammo_overlay = $Dashboard/HUD/BottomHUD/AmmoOverlay
@onready var ammo_vbox = $Dashboard/HUD/BottomHUD/AmmoOverlay/Margin/VBox/AmmoGroupVBox

# Controls
@onready var btn_retreat = $Dashboard/HUD/BottomHUD/RetreatContainer/RetreatBtn

@onready var consumable_container = $Dashboard/HUD/BottomHUD/ConsumablesContainer
@onready var btn_hull_cons = $Dashboard/HUD/BottomHUD/ConsumablesContainer/ConsHullBtn
@onready var btn_shd_cons = $Dashboard/HUD/BottomHUD/ConsumablesContainer/ConsShieldBtn
# Shared consumable cooldown bar — both buttons gate on manager.consumable_cooldown.
var _cons_cd_bar: ProgressBar = null
var _cons_cd_lbl: Label = null

var manager: RefCounted

var enemy_info_scene = preload("res://scenes/ui/enemy_info_modal.tscn")

# NG+ step 3: map-mod picker (built programmatically to avoid blind .tscn edits;
# placement/styling is a first pass to refine in-app). Gated on the NG+ frontier.
var _mm_picker: Control = null
var _mm_toggles: Dictionary = {}
var _mm_loot_lbl: Label = null

func _ready():
	manager = GameState.combat_manager
	call_deferred("refresh_zones")
	call_deferred("_build_map_mod_picker")
	GameState.game_loaded.connect(refresh_zones)
	if GameState.research_manager:
		GameState.research_manager.tech_unlocked.connect(func(_id): refresh_zones())
	# v113 (NG+): flag-gated zones (Z11/Z12) unlock via game_settings, not research,
	# so they fire neither game_loaded nor tech_unlocked. Refresh on the dedicated
	# zones_changed signal (the moment a flag is set, even mid-combat) AND whenever
	# this page is shown (catch-all for warp / navigation).
	if manager and manager.has_signal("zones_changed") and not manager.zones_changed.is_connected(refresh_zones):
		manager.zones_changed.connect(refresh_zones)
	if not visibility_changed.is_connected(_on_combat_visibility_changed):
		visibility_changed.connect(_on_combat_visibility_changed)
	# v134g: the Sector Chart draws OBJECTIVE markers from the active "defeat"
	# missions (get_active_defeat_targets). When a mission advances (e.g. Combat
	# Briefing → Defeat Lunar Drone) while the chart is ALREADY open, nothing told
	# it to redraw — so the marker only appeared after a combat-page re-visit
	# (visibility_changed → refresh_zones). Rebuild the open chart on mission change.
	if GameState.mission_manager and GameState.mission_manager.has_signal("mission_updated") \
			and not GameState.mission_manager.mission_updated.is_connected(_on_mission_updated):
		GameState.mission_manager.mission_updated.connect(_on_mission_updated)

	# HUD Stress & Console Interaction
	
	# Initial Suppression
	
	UITheme.apply_premium_button_style(btn_retreat, "combat")
	
	UITheme.apply_progress_bar_style(e_attack_pb, "combat")
	
	# v134h: Star Chart is a compact SQUARE emblem button (drawn star-chart glyph) top-
	# left of the combat HUD — the old NAVIGATION card was removed.
	open_chart_btn.text = ""
	open_chart_btn.custom_minimum_size = Vector2(44, 44)
	open_chart_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	open_chart_btn.tooltip_text = tr("Open Star Chart")
	UITheme.apply_premium_button_style(open_chart_btn, "ops")
	if open_chart_btn.get_node_or_null("StarEmblem") == null:
		var _emb: Control = preload("res://scripts/ui/star_emblem.gd").new()
		_emb.name = "StarEmblem"
		_emb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_emb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		open_chart_btn.add_child(_emb)
	if not open_chart_btn.is_connected("pressed", _open_star_map):
		open_chart_btn.pressed.connect(_open_star_map)
	UITheme.apply_card_style($Dashboard/HUD/MidHUD/PlayerStatsOverlay, "shipyard")
	UITheme.apply_card_style($Dashboard/HUD/MidHUD/EnemyStatsOverlay, "combat")
	UITheme.apply_card_style(ammo_overlay, "inventory")
	UITheme.apply_card_style(scanner_overlay, "research")

	# v134h: radar HP/shield arcs removed (that info lives in the ship cards). The
	# RadarDisplay node stays as a positioning anchor but no longer draws.
	

	# v120: combat XP bar removed with combat leveling — it was dead UI (its value
	# was never updated and nothing listened to Skill.level_up).
	_setup_hp_bars()
	_setup_consumable_buttons()
	
	# Explicit Signal Connections (Defensive)
	if not btn_retreat.is_connected("pressed", _on_retreat_btn_pressed): btn_retreat.pressed.connect(_on_retreat_btn_pressed)
	
	_setup_loot_filter_button()
	# v131/v134h: the top-center flavor readout (SECTOR THREAT / TARGET LOCK / SCANNING)
	# is removed from the scene entirely, and the SESSION / LAST KILL timer row is not
	# built (so _refresh_combat_timers early-returns on its null guard). The LoadoutSwap
	# card in the same CenterInfo container is untouched (functional, kept).
	_build_loadout_swap_row()

var p_hp_bar: HBoxContainer
var p_sh_bar: HBoxContainer
var e_hp_bar: HBoxContainer
var e_sh_bar: HBoxContainer

# Combat-session HUD timers (built in _ready, refreshed from update_ui).
# Left: total combat duration since engage. Right: time since the last kill.
var combat_timer_row: HBoxContainer
var session_timer_lbl: Label
var kill_timer_lbl: Label

func _setup_hp_bars():
	p_hp_bar = _create_block_bar($Dashboard/HUD/MidHUD/PlayerStatsOverlay/Margin/VBox, p_hp_lbl.get_index() + 1, "combat")
	p_sh_bar = _create_block_bar($Dashboard/HUD/MidHUD/PlayerStatsOverlay/Margin/VBox, p_sh_lbl.get_index() + 1, "shipyard")
	
	e_hp_bar = _create_block_bar($Dashboard/HUD/MidHUD/EnemyStatsOverlay/Margin/VBox, e_hp_lbl.get_index() + 1, "combat")
	e_sh_bar = _create_block_bar($Dashboard/HUD/MidHUD/EnemyStatsOverlay/Margin/VBox, e_sh_lbl.get_index() + 1, "shipyard")

func _create_block_bar(parent: Control, index: int, category: String) -> HBoxContainer:
	var bar = HBoxContainer.new()
	bar.custom_minimum_size.y = 10
	bar.add_theme_constant_override("separation", 2)
	parent.add_child(bar)
	parent.move_child(bar, index)
	
	var accent = UITheme.CATEGORY_COLORS.get(category, Color.WHITE)
	for i in range(20): # 20 blocks for high resolution
		var block = ColorRect.new()
		block.custom_minimum_size = Vector2(8, 0)
		block.size_flags_vertical = Control.SIZE_EXPAND_FILL
		block.color = accent.lerp(Color.BLACK, 0.8) # Base off
		bar.add_child(block)
	
	bar.set_meta("accent", accent)
	return bar

func _update_block_bar(bar: HBoxContainer, percent: float):
	var accent = bar.get_meta("accent", Color.WHITE)
	var blocks = bar.get_children()
	var filled_count = int(blocks.size() * percent)
	
	for i in range(blocks.size()):
		if i < filled_count:
			blocks[i].color = accent
			blocks[i].modulate.a = 1.0
		else:
			blocks[i].color = accent.lerp(Color.BLACK, 0.9)
			blocks[i].modulate.a = 0.3

func _setup_loot_filter_button():
	var btn = Button.new()
	btn.text = tr("▼ FILTER")
	btn.name = "LootFilterBtn"
	btn.custom_minimum_size = Vector2(0, 22)
	btn.add_theme_font_size_override("font_size", 10)
	UITheme.apply_premium_button_style(btn, "ops")

	# Inject into ScannerOverlay header row, between Header and Scroll
	var vbox = $Dashboard/HUD/BottomHUD/ScannerOverlay/Margin/VBox
	vbox.add_child(btn)
	vbox.move_child(btn, 1) # After Header label, before Scroll

	btn.pressed.connect(_on_filter_btn_pressed)

func _on_filter_btn_pressed():
	# Since it's code-only, we just instantiate the script
	var script = load("res://scripts/ui/loot_filter_modal.gd")
	var dlg = Control.new()
	dlg.set_script(script)
	self.add_child(dlg)

func refresh_zones():
	# v124: the sector list is now the Sector Chart overlay. This keeps the
	# NavPanel readout in sync and validates the stored selection against the
	# currently-available zones (research / NG+ flags can add or gate sectors
	# at any time). If the selected sector vanished, fall back to a sensible
	# default.
	var avail: Array = manager.get_available_zones()
	var avail_ids := {}
	for z in avail:
		avail_ids[z["id"]] = true
	if selected_zone_id == "" or not avail_ids.has(selected_zone_id):
		selected_zone_id = _default_selected_zone(avail)
	_update_nav_readout()
	if star_map and is_instance_valid(star_map) and star_map.visible:
		star_map.rebuild()

# Prefer the player's current sector, then the deepest reachable one, else home.
func _default_selected_zone(avail: Array) -> String:
	var cur: String = manager.current_zone_id
	for z in avail:
		if z["id"] == cur:
			return cur
	var best := ""
	var bd := -1
	for z in avail:
		var d := int(z["data"].get("difficulty", 0))
		if d > bd:
			bd = d
			best = str(z["id"])
	return best

func _update_nav_readout() -> void:
	# v134h: the on-HUD NAVIGATION readout card was removed — sector name / threat /
	# position now live only in the Star Chart overlay. No-op kept because callers
	# (select_zone / refresh_zones) invoke it alongside their chart sync.
	pass

func _zone_data(zid: String) -> Dictionary:
	if manager.zones.has(zid):
		return manager.zones[zid]
	if manager.hazard_zones.has(zid):
		var hz = manager.hazard_zones[zid]
		return {"name": hz.get("name", ""), "difficulty": hz.get("zone_difficulty", 3)}
	return {}

func _zone_state(zid: String) -> String:
	if zid == manager.current_zone_id:
		return "current"
	if manager.hazard_zones.has(zid):
		return "cleared" if manager.hazard_clears.has(zid) else "available"
	var data = manager.zones.get(zid, {})
	var boss_id := ""
	for eid in data.get("enemies", []):
		if manager.enemy_db.get(eid, {}).get("is_boss", false):
			boss_id = str(eid)
			break
	if boss_id != "" and int(manager.boss_kills.get(boss_id, 0)) > 0:
		return "cleared"
	return "available"

func _open_star_map() -> void:
	if star_map == null or not is_instance_valid(star_map):
		star_map = STAR_MAP_SCRIPT.new()
		add_child(star_map)
		star_map.setup(manager, self)
	star_map.open()

# Selecting a sector (from the Sector Chart or coach focus) sets the engage
# target zone and syncs the NavPanel readout + chart highlight. Target picking
# now happens on the chart's roster, so there is no in-HUD list to populate.
func select_zone(zone_id: String) -> void:
	selected_zone_id = zone_id
	_update_nav_readout()
	if star_map and is_instance_valid(star_map):
		star_map.set_external_selection(zone_id)

# v124: engage straight from the Sector Chart — pick the zone + target on the
# map, then this starts the fight. The manager auto-respawns the target after
# each kill (spawn_enemy), so no in-HUD target list is needed to sustain combat.
# enemy_id "" routes hazards (start_hazard ignores the target).
func engage_from_map(zone_id: String, enemy_id: String) -> void:
	select_zone(zone_id)
	request_fight(enemy_id)

func _on_mission_updated() -> void:
	# v134g: redraw the open Sector Chart when the active mission set changes, so a
	# newly-active "defeat" objective (e.g. m017 Lunar Drone right after the Combat
	# Briefing) shows its marker immediately instead of only after a page re-visit.
	if star_map and is_instance_valid(star_map) and star_map.visible:
		star_map.rebuild()

func _on_combat_visibility_changed() -> void:
	# v113 (NG+): re-read available zones each time the Combat page is shown, so a
	# sector unlocked while elsewhere (e.g. Z11 on a Z10-boss kill, Z12 post-warp)
	# is present. refresh_zones preserves the current sector selection.
	if not is_visible_in_tree():
		return
	refresh_zones()
	# v134: clicking Combat now lands on the ship HUD, NOT the Sector Chart. The
	# chart opens on demand — via the "Open Chart" button (open_chart_btn) or by the
	# combat coach (coach_before_step opens it for the sector/target steps). So
	# mission + tutorial guidance to the chart still works (m016c's coach opens it;
	# "defeat in Sector X" missions mark objectives inside it) — it's just no longer
	# forced open on every idle visit. A fight already in progress shows the live HUD.

# v124: the in-HUD enemy-card list was removed (the Sector Chart roster replaced
# it). The coach (main.gd) still calls this to pulse an "engage this enemy" cue;
# with no cards, point it at the chart button so the tutorial directs the player
# to open the Sector Chart and pick the target there.
func get_enemy_card(enemy_id: String) -> Control:
	# v134g: if the player is ALREADY fighting this mission's target, the guidance
	# is satisfied — stop pulsing. Previously the "open the Sector Chart" nudge kept
	# beeping through the whole Lunar-Drone fight (chart closed during combat), even
	# though the player had already followed the steps and engaged the right enemy.
	if manager.in_combat and manager.current_enemy \
			and str(manager.current_enemy.get("id", "")) == enemy_id:
		return null
	# v128: mission/coach pulse target. Point at the chart button only when the chart
	# is CLOSED (nudge = "open the Sector Chart"). While it's open the player is already
	# in the selection UI and the button is hidden behind the overlay — pulsing it is
	# invisible, so return null (no pulse) and let focus_zone + the chart guide them.
	if star_map and is_instance_valid(star_map) and star_map.visible:
		return null
	return open_chart_btn

func get_coach_anchor(key: String) -> Control:
	# v128/v134: coach_before_step opens the Sector Chart for the sector/target steps
	# (it no longer auto-opens on a plain page visit), so those steps anchor INTO the
	# open chart — while it's open the open_chart_btn is hidden behind the overlay, so
	# highlighting it would draw an empty box over the scrim.
	if star_map and is_instance_valid(star_map) and star_map.visible and star_map.has_method("get_coach_anchor"):
		var a = star_map.get_coach_anchor(key)
		if a != null:
			return a
	match key:
		"zones", "enemies":
			return open_chart_btn
		"consumables":
			return consumable_container
	return null

# v128: prep the UI for each coach step. Sector/target steps anchor into the Sector
# Chart, so make sure it's open; the repair-kit step teaches HUD buttons, so close
# the chart to reveal them. Keeps the highlight on something actually on-screen.
func coach_before_step(page_name: String, _idx: int, anchor_key: String) -> void:
	if page_name != "combat":
		return
	var chart_open: bool = star_map and is_instance_valid(star_map) and star_map.visible
	if anchor_key == "consumables":
		if chart_open:
			star_map.close()
	elif anchor_key in ["zones", "enemies"]:
		if not manager.in_combat and not chart_open:
			_open_star_map()

func focus_zone(zone_id: String):
	# Coach hook: select the sector (syncs NavPanel + chart) without forcing the
	# Sector Chart open. Guard against ids not in the available set.
	select_zone(zone_id)

func request_fight(eid):
	# v124: the engage zone is the Sector Chart selection (was the ItemList).
	var zid = selected_zone_id
	if zid == "": return

	# v124: gate BEFORE committing combat. start_expedition() flips in_combat and
	# spawns immediately but has no whole-ship power gate (only set_target_enemy
	# does, and it runs AFTER) — so an unpowered/dead ship would enter combat
	# against a stale target with weapons that can't fire. Mirror the manager's
	# guards up front so the engage is cleanly blocked instead.
	var sm = GameState.shipyard_manager
	if sm:
		if sm.current_hp <= 0:
			UITheme.show_notification("HULL CRITICAL — repair before engaging.", Color(1.0, 0.45, 0.35))
			return
		if sm.energy_used > sm.energy_capacity:
			UITheme.show_notification("SHIP UNPOWERED — equip Battery modules to cover your power draw (%d / %d)." % [int(sm.energy_used), int(sm.energy_capacity)], Color(1.0, 0.45, 0.35))
			return

	# v111.16: every explicit ENGAGE press is a fresh run from the player's POV,
	# so wipe the Expedition Yield panel now. start_expedition() already clears
	# session_loot for a NEW zone, but it early-returns when you're already
	# fighting in the SAME zone and only re-targeting — that path left stale yield
	# on screen. Clearing here covers both expeditions and hazards uniformly, and
	# fires only on a deliberate ENGAGE (not on post-kill auto-retargeting).
	manager.session_loot.clear()

	# v86.0: Route hazard zones to start_hazard (gauntlet mode)
	if zid in manager.hazard_zones:
		manager.start_hazard(zid)
		return

	# v124: pre-set the target so start_expedition's spawn_enemy() spawns the
	# CHOSEN enemy, not a random/stale one; set_target_enemy then re-affirms it
	# and restores shields. Without this, a cross-zone engage briefly shows the
	# previous fight's enemy.
	if eid != "" and eid in manager.enemy_db:
		manager.target_enemy_id = eid
	manager.start_expedition(zid)
	manager.set_target_enemy(eid)

# NG+ step 3: build the map-mod picker programmatically (a PanelContainer of CheckButtons
# anchored top-right). Toggling calls set_active_map_mods; the cap-at-3 + validate live in
# the manager, so we re-sync the toggles to whatever was actually accepted.
func _build_map_mod_picker() -> void:
	if _mm_picker != null or manager == null: return
	var panel := PanelContainer.new()
	panel.name = "MapModPicker"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -252.0; panel.offset_top = 56.0; panel.offset_right = -8.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	var title := Label.new()
	title.text = tr("MAP MODS — juice the sector")
	vb.add_child(title)
	for mid in manager.MAP_MODS:
		var d: Dictionary = manager.MAP_MODS[mid]
		var cb := CheckButton.new()
		cb.text = tr("%s  ×%.1f") % [String(d.get("name", "")), float(d.get("loot_mult", 1.0))]
		cb.tooltip_text = String(d.get("desc", ""))
		cb.set_pressed_no_signal(String(mid) in manager.active_map_mods)
		cb.toggled.connect(func(_p): _on_map_mod_toggled())
		vb.add_child(cb)
		_mm_toggles[String(mid)] = cb
	_mm_loot_lbl = Label.new()
	_mm_loot_lbl.text = tr("Loot ×1.00 (stack up to %d)") % manager.MAX_MAP_MODS
	vb.add_child(_mm_loot_lbl)
	add_child(panel)
	_mm_picker = panel
	if UITheme:
		UITheme.apply_card_style(panel, "combat")
	_refresh_map_mod_picker()

func _on_map_mod_toggled() -> void:
	var sel: Array = []
	for mid in _mm_toggles:
		if _mm_toggles[mid].button_pressed: sel.append(mid)
	manager.set_active_map_mods(sel)   # validates + dedupes + caps at MAX_MAP_MODS
	_refresh_map_mod_picker()          # re-sync toggles to what was actually accepted

func _refresh_map_mod_picker() -> void:
	if _mm_picker == null: return
	# Pre-expedition only (mods bind at spawn); hidden during combat + before the NG+ frontier.
	_mm_picker.visible = GameState.game_settings.get("z11_unlocked", false) and not manager.in_combat
	if not _mm_picker.visible: return
	for mid in _mm_toggles:
		_mm_toggles[mid].set_pressed_no_signal(mid in manager.active_map_mods)
	if _mm_loot_lbl:
		_mm_loot_lbl.text = tr("Loot ×%.2f (stack up to %d)") % [manager.get_map_mod_loot_mult(), manager.MAX_MAP_MODS]

func _process(delta):
	update_ui()
	_update_atmosphere(delta)
	_refresh_map_mod_picker()

func update_ui():
	# v134h: radar draw removed — no queue_redraw here anymore.
	_refresh_combat_timers()
	_refresh_loadout_swap_row()

	# Player Stats
	var sm = GameState.shipyard_manager
	var eva_bonus = manager.get_milestone_evasion_bonus()
	var crit_bonus = manager.get_milestone_crit_bonus()
	var total_eva = sm.evasion + eva_bonus
	var total_crit = (sm.crit_chance + crit_bonus) * 100.0
	
	p_stat_lbl.text = tr("ATK: %s | DEF: %s | EVA: %.0f | CRIT: %.0f%%") % [UITheme.format_num(sm.attack), UITheme.format_num(sm.defense), total_eva, total_crit]
	# v131: the inline "RES K/N/X" readout was removed per design (too cryptic on
	# the stat line). resist_k/e/x still apply in combat — they just aren't shown here.
	# v112 Fleet P2: surface the fleet's live combat contribution so it reads as
	# power, not a dead roster number.
	if GameState.fleet_manager and GameState.fleet_manager.has_method("get_combat_bonus_pct"):
		var fb: int = GameState.fleet_manager.get_combat_bonus_pct()
		if fb > 0:
			p_stat_lbl.text += " | FLEET +%d%%" % fb
	
	# Title shows just the hull name — combat level + bonus-damage readout
	# removed from the card header per design (kept off to declutter the title).
	var hull_name = sm.get_ship_name() if sm and sm.has_method("get_ship_name") else "USS HORIZON"
	p_name_lbl.text = tr(hull_name).to_upper()
	
	# Sync Block Bars
	_update_block_bar(p_hp_bar, float(sm.current_hp) / max(1.0, sm.max_hp))
	_update_block_bar(p_sh_bar, float(manager.player_shield) / max(1.0, manager.player_max_shield))
	p_sh_bar.visible = manager.player_max_shield > 0
	
	p_hp_lbl.text = tr("HULL: %s/%s") % [UITheme.format_num(sm.current_hp), UITheme.format_num(sm.max_hp)]
	p_sh_lbl.text = tr("SHD: %s/%s") % [UITheme.format_num(manager.player_shield), UITheme.format_num(manager.player_max_shield)]
	
	# ... (rest of logic)
	
	# Enemy Stats
	if manager.in_combat and manager.current_enemy:
		var enemy = manager.current_enemy
		e_name_lbl.text = tr(enemy["name"])
		
		# v87.0: Show enemy damage type tag
		var e_type_tag = "KIN"
		var e_type_color = Color(0.6, 0.8, 1.0)
		match enemy.get("dmg_type", "kinetic"):
			"energy":
				e_type_tag = "NRG"
				e_type_color = Color(1.0, 0.9, 0.3)
			"explosive":
				e_type_tag = "EXP"
				e_type_color = Color(1.0, 0.5, 0.3)
		e_stat_lbl.text = tr("DMG: %s [%s] | DEF: %s") % [UITheme.format_num(enemy.get("atk", 0)), e_type_tag, UITheme.format_num(enemy.get("def", 0))]
		
		# v86.0: Show wave counter during hazard gauntlet
		if manager.hazard_state["active"]:
			var wave_text = "WAVE %d/%d" % [manager.hazard_state["wave"] + 1, manager.hazard_state["max_waves"]]
			e_name_lbl.text = "[%s] %s" % [wave_text, tr(enemy["name"])]
		
		_update_block_bar(e_hp_bar, float(manager.enemy_hp) / max(1.0, manager.enemy_max_hp))
		_update_block_bar(e_sh_bar, float(manager.enemy_shield) / max(1.0, manager.enemy_max_shield))
		
		e_hp_lbl.text = tr("HULL: %s/%s") % [UITheme.format_num(manager.enemy_hp), UITheme.format_num(manager.enemy_max_hp)]
		e_sh_lbl.text = tr("SHD: %s/%s") % [UITheme.format_num(manager.enemy_shield), UITheme.format_num(manager.enemy_max_shield)]
		btn_retreat.disabled = false
	else:
		e_name_lbl.text = tr("NO TARGET")
		_update_block_bar(e_hp_bar, 0)
		_update_block_bar(e_sh_bar, 0)
		e_stat_lbl.text = tr("DMG: 0 | DEF: 0")
		btn_retreat.disabled = true
	
	# Attack Timers
	if manager.in_combat:
		# Sync Weapon Battery. v134h: rebuild when the weapon TYPE composition changes,
		# not just the count — a loadout swap (e.g. 2 kinetic -> 2 energy) keeps the same
		# count but changes the per-type bar COLORS, which otherwise stayed stale.
		var w_states = manager.player_weapon_states
		var wsig := str(w_states.size())
		for _w in w_states:
			wsig += "|" + str(_w.get("type", ""))
		if wsig != _weapon_bar_sig:
			_weapon_bar_sig = wsig
			_rebuild_weapon_battery(w_states)
		
		for i in range(w_states.size()):
			var w = w_states[i]
			var pb = player_weapon_bars[i]
			pb.max_value = w["interval"]
			pb.value = w["timer"]
			pb.visible = true
			
			# AMMO STATUS FEEDBACK
			var ammo_id = sm.ammo_loadout.get(w["slot_idx"])
			var has_ammo = false
			if ammo_id and ammo_id != "":
				has_ammo = GameState.resources.get_element_amount(ammo_id) > 0
				
			if not has_ammo:
				pb.modulate = Color(0.5, 0.5, 0.5, 0.5) # Dimmed offline look
				pb.value = 0 # Forced to 0 when offline
			else:
				pb.modulate = Color.WHITE # Normal online status
		
		if manager.current_enemy:
			e_attack_pb.visible = true
			e_attack_pb.max_value = manager.current_enemy.get("atk_interval", 3.0)
			e_attack_pb.value = manager.enemy_attack_timer
			
			# v87.0: Color enemy attack bar by damage type (cached)
			var cur_dmg_type = manager.current_enemy.get("dmg_type", "kinetic")
			if e_attack_pb.get_meta("dmg_type", "") != cur_dmg_type:
				e_attack_pb.set_meta("dmg_type", cur_dmg_type)
				var e_bar_color = Color(0.6, 0.8, 1.0) # Kinetic: Steel Blue
				match cur_dmg_type:
					"energy": e_bar_color = Color(1.0, 0.9, 0.3) # Energy: Gold
					"explosive": e_bar_color = Color(1.0, 0.5, 0.3) # Explosive: Orange-Red
				var e_fill = StyleBoxFlat.new()
				e_fill.bg_color = e_bar_color
				e_fill.set_corner_radius_all(2)
				e_attack_pb.add_theme_stylebox_override("fill", e_fill)
		else:
			e_attack_pb.visible = false
		# Expedition Yield
		_update_session_loot()
		scanner_overlay.visible = true
		
		# Ammo Tracking
		_update_ammo_display()
		ammo_overlay.visible = true
		
	else:
		for pb in player_weapon_bars: pb.visible = false
		e_attack_pb.visible = false
		# v111.11 cockpit Stage 1: KEEP scanner_overlay (Expedition Yield) and
		# ammo_overlay (Ordnance Feed) visible when out of combat — they read as
		# fixed regions that sit empty/dim until combat fills them.

	# Log - DISABLED (User Request)
	# Log Removed

	# Retreat Btn
	btn_retreat.disabled = not manager.in_combat
	
	# Update Consumable Action Buttons
	_update_consumable_buttons()


	# Process Combat Events (Floating Text + Haptics)
	while manager.combat_events.size() > 0:
		var ev = manager.combat_events.pop_front()
		var ev_type: String = ev.get("type", "")
		# v111.11 Stage 2.1: per-hit damage no longer spams the global toast
		# stack (which piled bottom-right, colliding with RETREAT). Damage
		# now floats off the ship/target in the radar centre, where the hit
		# visually lands. Non-damage events (kills, loot, level) still toast.
		if ev_type == "damage":
			if is_visible_in_tree():
				_spawn_damage_float(str(ev["text"]), ev["color"], ev.get("side") == "player")
		else:
			# v122: kills / loot / heals / XP float up from the upper-centre too
			# — the global toast feed lives on the right edge, which in combat is
			# fully panelled (target panel, enemy stats, consumables + RETREAT),
			# so toasting there collided with the RETREAT button.
			if is_visible_in_tree():
				_spawn_event_float(str(ev["text"]), ev["color"])

		# TACTILE: Damage-induced System Glitch
		if ev.get("side") == "player" and ev.get("type", "") == "damage":
			if is_visible_in_tree():
				_apply_hud_stress()
				UITheme.trigger_damage_flash(p_hp_bar)
				UITheme.trigger_damage_flash(p_sh_bar)
			if manager.haptics_enabled:
				Input.vibrate_handheld(100)
		elif ev.get("side") == "enemy" and ev.get("type", "") == "damage":
			if is_visible_in_tree():
				UITheme.trigger_damage_flash(e_hp_bar)
				UITheme.trigger_damage_flash(e_sh_bar)
		
		# PARRY: Special feedback for successful reflection
		if ev.get("type") == "parry":
			UITheme.trigger_system_glitch(visualizer, 5.0)
			UITheme.trigger_ui_thud(self, 4.0)

func _apply_hud_stress():
	var hud = $Dashboard/HUD
	# PHASE 47: Visceral System Glitch
	UITheme.trigger_system_glitch(hud, 12.0)
	UITheme.trigger_ui_thud(self, 8.0)

# v111.11 Stage 2.1: Centered floating damage text. Spawns off the radar
# centre — left of centre for player-side hits, right for enemy-side — and
# rises + fades over ~0.9s. Replaces the toast spam that piled in the
# bottom-right corner over the RETREAT button.
func _spawn_damage_float(text: String, color: Color, player_side: bool) -> void:
	if not visualizer:
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 50
	visualizer.add_child(lbl)

	var vp: Vector2 = visualizer.size
	# Player hits float on the left third, enemy hits on the right third —
	# matching the radar's left=player / right=enemy arc convention.
	var base_x: float = vp.x * (0.40 if player_side else 0.60)
	var base_y: float = vp.y * 0.44
	lbl.position = Vector2(base_x + randf_range(-18.0, 18.0), base_y + randf_range(-8.0, 8.0))

	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 48.0, 0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(lbl.queue_free)

# v122: non-damage combat feedback (kills, loot, heals, XP) rises from the
# upper-centre and fades — keeps it off the global right-edge toast feed that
# overlapped the RETREAT button. Distinct height from damage floats so they
# don't stack on each other.
func _spawn_event_float(text: String, color: Color) -> void:
	if not visualizer:
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(160, 0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 51
	visualizer.add_child(lbl)

	var vp: Vector2 = visualizer.size
	lbl.position = Vector2(vp.x * 0.5 - 80.0, vp.y * 0.28 + randf_range(-10.0, 10.0))

	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 42.0, 1.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.2).set_delay(0.5)
	tw.chain().tween_callback(lbl.queue_free)

func show_enemy_info(data):
	var dlg = enemy_info_scene.instantiate()
	self.add_child(dlg)
	dlg.setup(data)

func _on_radar_draw():
	var center = Vector2.ZERO # Local space of RadarDisplay (it's centered)
	var sm = GameState.shipyard_manager
	
	# --- PLAYER ARCS (Left) ---
	var p_hp_pct = float(sm.current_hp) / max(1.0, sm.max_hp)
	var p_sh_pct = float(manager.player_shield) / max(1.0, manager.player_max_shield)
	
	# Player HP Arc (Reddish) - Radius 120-126
	_draw_arc_poly(center, 120, 126, 110, 250, Color(1, 0, 0, 0.1), Color(1, 0.3, 0.3, 0.8), p_hp_pct)
	# Player Shield Arc (Cyan) - Radius 132-138
	_draw_arc_poly(center, 132, 138, 110, 250, Color(0.427, 0.941, 0.847, 0.1), Color(0.427, 0.941, 0.847, 0.6), p_sh_pct)

	# --- ENEMY ARCS (Right) ---
	if manager.in_combat and manager.current_enemy:
		var e_hp_pct = float(manager.enemy_hp) / max(1.0, manager.enemy_max_hp)
		var e_sh_pct = float(manager.enemy_shield) / max(1.0, manager.enemy_max_shield)
		
		# Enemy HP Arc - Radius 120-126 (Symmetrical)
		_draw_arc_poly(center, 120, 126, -70, 70, Color(1, 0, 0, 0.1), Color(1, 0, 0, 0.8), e_hp_pct)
		# Enemy Shield Arc - Radius 132-138 (Symmetrical)
		_draw_arc_poly(center, 132, 138, -70, 70, Color(0.427, 0.941, 0.847, 0.1), Color(0.427, 0.941, 0.847, 0.6), e_sh_pct)
		
	# --- RETICLE & DECORATION ---
	radar_display.draw_circle(center, 5, Color(1, 1, 1, 0.1)) # Center dot
	radar_display.draw_arc(center, 100, 0, TAU, 64, Color(1, 1, 1, 0.05), 1.0) # Inner guide ring

func _draw_arc_poly(center: Vector2, inner_radius: float, outer_radius: float, start_deg: float, end_deg: float, bg_color: Color, fill_color: Color, percent: float):
	# Out-of-range data (e.g. shield 1.55K with max 0, or HP above max) must
	# never sweep the fill past its arc -- that wraps the polygon into the
	# jagged full ring. Clamp + reject NaN/inf.
	if not is_finite(percent):
		percent = 0.0
	percent = clampf(percent, 0.0, 1.0)
	var segments = 32
	var start_rad = deg_to_rad(start_deg)
	var end_rad = deg_to_rad(end_deg)
	
	# Draw Background
	_draw_arc_section(center, inner_radius, outer_radius, start_rad, end_rad, segments, bg_color)
	
	# Draw Fill
	if percent > 0.01:
		var fill_end_rad = start_rad + (end_rad - start_rad) * percent
		_draw_arc_section(center, inner_radius, outer_radius, start_rad, fill_end_rad, segments, fill_color)
		
		# SHARPNESS: Add thin lines on edges of fill for anti-aliasing feel
		radar_display.draw_arc(center, outer_radius, start_rad, fill_end_rad, segments, fill_color.lightened(0.2), 1.0, true)
		radar_display.draw_arc(center, inner_radius, start_rad, fill_end_rad, segments, fill_color.lightened(0.2), 1.0, true)

func _draw_arc_section(center: Vector2, r_inner: float, r_outer: float, angle_start: float, angle_end: float, segments: int, color: Color):
	# Safely skip zero-width polygons to prevent triangulation collapse
	if abs(angle_end - angle_start) < 0.05:
		return
		
	var points = PackedVector2Array()
	var angle_delta = (angle_end - angle_start) / segments
	
	# Outer circumference
	for i in range(segments + 1):
		var a = angle_start + i * angle_delta
		points.append(center + Vector2(cos(a), sin(a)) * r_outer)
	
	# Inner circumference (reverse to close loop)
	for i in range(segments, -1, -1):
		var a = angle_start + i * angle_delta
		points.append(center + Vector2(cos(a), sin(a)) * r_inner)
		
	radar_display.draw_polygon(points, PackedColorArray([color]))

# v134h: Expedition Yield is now a GRID of dropped-item icon TILES instead of a
# BBCode text list. loot_lbl (the old RichTextLabel) is reused only for the empty
# "[ NO YIELD ]" state; a GridContainer sibling holds the tiles.
func _update_session_loot():
	var loot_vbox: Control = loot_lbl.get_parent()
	var grid: GridContainer = loot_vbox.get_node_or_null("LootGrid")
	if grid == null:
		grid = GridContainer.new()
		grid.name = "LootGrid"
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 5)
		grid.add_theme_constant_override("v_separation", 5)
		loot_vbox.add_child(grid)
		loot_vbox.move_child(grid, 0)   # above the empty-state label / padding
	# v134h: this runs every combat frame — only rebuild the tiles when the loot set
	# actually changes, else we'd churn/flicker nodes 60x/sec.
	var sig := str(manager.session_loot.size())
	for k in manager.session_loot:
		sig += "|" + str(k) + ":" + str(manager.session_loot[k])
	if sig == _last_loot_sig:
		return
	_last_loot_sig = sig
	for c in grid.get_children():
		c.queue_free()

	if manager.session_loot.is_empty():
		grid.visible = false
		loot_lbl.visible = true
		var tt := "[center][color=#666666][ NO YIELD ][/color][/center]"
		if loot_lbl.text != tt:
			loot_lbl.text = tt
		return

	loot_lbl.visible = false
	grid.visible = true
	for item_id in manager.session_loot:
		grid.add_child(_build_loot_tile(str(item_id), manager.session_loot[item_id]))

func _build_loot_tile(str_id: String, qty) -> Control:
	var sm = GameState.shipyard_manager
	var name_txt := str_id
	var icon: Texture2D = null
	var tint := Color(0.40, 0.85, 0.45)
	var glyph := ""
	if str_id.begins_with("custom_") or sm.modules.has(str_id):
		# Dropped module — rarity-tinted ★ tile.
		var mid := str_id
		if str_id.begins_with("custom_") and not sm.modules.has(str_id):
			var parts := str_id.split("_")
			var base_id := str_id.trim_prefix("custom_")
			if parts.size() > 2 and parts[parts.size() - 1].is_valid_int():
				base_id = base_id.trim_suffix("_" + parts[parts.size() - 1])
			mid = base_id
		var m_data: Dictionary = sm.modules.get(mid, {"name": mid})
		name_txt = str(m_data.get("name", mid))
		var rarity := int(m_data.get("rarity", 0))
		# RARITY_COLORS is a const on shipyard_manager — access directly. (An `in sm`
		# guard would ALWAYS be false: GDScript's `in` checks properties, not consts.)
		tint = sm.RARITY_COLORS.get(rarity, Color(0.80, 0.70, 1.0))
		# v139: show the module's real icon (slot-type silhouette; weapons split by
		# damage family) rarity-tinted via modulate — same resolver the Designer
		# slots use. Text fallback only if the SVG isn't imported yet.
		icon = UITheme.module_type_icon(str(m_data.get("slot_type", "module")), m_data.get("stats", {}))
		if icon == null:
			glyph = "MOD"
	elif str_id == "credits":
		# v134h: the Lira currency uses its dedicated gold icon, not a "cred" glyph.
		icon = load("res://assets/icons/lira.svg")
		tint = Color(1.0, 0.82, 0.30)   # lira gold
		name_txt = "Liras"
	else:
		icon = ElementDB.get_material_icon(str_id)
		tint = ElementDB.get_material_tint(str_id)
		name_txt = ElementDB.get_display_name(str_id)
		if name_txt == str_id:
			name_txt = str_id.replace("_", " ").capitalize()
		if icon == null:
			glyph = str_id if str_id.length() <= 4 else str_id.substr(0, 4)

	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(46, 46)
	tile.tooltip_text = tr("%s  ×%s") % [name_txt, UITheme.format_num(qty)]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.10, 0.14, 0.92)
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	sb.border_color = Color(tint.r, tint.g, tint.b, 0.45)
	tile.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 1)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(vb)

	if icon != null:
		var tr := TextureRect.new()
		tr.texture = icon
		tr.modulate = tint
		tr.custom_minimum_size = Vector2(0, 20)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(tr)
	else:
		var g := Label.new()
		g.text = glyph
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		g.add_theme_font_size_override("font_size", 13)
		g.add_theme_color_override("font_color", tint)
		vb.add_child(g)

	var cnt := Label.new()
	cnt.text = tr("×%s") % UITheme.format_num(qty)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cnt.add_theme_font_size_override("font_size", 10)
	cnt.add_theme_color_override("font_color", Color(0.75, 0.80, 0.86))
	vb.add_child(cnt)
	return tile

func _update_ammo_display():
	var sm = GameState.shipyard_manager
	# Clear existing
	for child in ammo_vbox.get_children(): child.queue_free()
	
	# THEMATIC STYLEBOXES (Internalized for performance/isolation)
	var sb_ghost = StyleBoxFlat.new()
	sb_ghost.bg_color = Color(0.1, 0.1, 0.1, 0.6)
	sb_ghost.border_width_left = 1
	sb_ghost.border_width_top = 1
	sb_ghost.border_color = Color(0, 0, 0)
	sb_ghost.corner_radius_top_left = 2
	sb_ghost.corner_radius_bottom_right = 2
	
	var ammo_list = [
		{"name": "Slug", "id": "SlugT1", "col": Color("#ffcc00"), "type": "kinetic"},
		{"name": "Steel", "id": "SlugT1S", "col": Color("#ffeebb"), "type": "kinetic"},
		{"name": "Sabot", "id": "SlugT2", "col": Color("#ffaa00"), "type": "kinetic"},
		{"name": "Titan", "id": "SlugT3", "col": Color("#ff8800"), "type": "kinetic"},
		{"name": "Hyper", "id": "SlugT4", "col": Color("#cc0000"), "type": "kinetic"},
		{"name": "Focus", "id": "CellT1", "col": Color("#00ccff"), "type": "energy"},
		{"name": "Plasma", "id": "CellT2", "col": Color("#0099ff"), "type": "energy"},
		{"name": "Vapor", "id": "CellT3", "col": Color("#0066ff"), "type": "energy"},
		{"name": "Heavy", "id": "CellT4", "col": Color("#aa00ff"), "type": "energy"},
		{"name": "HE", "id": "MissileT1", "col": Color("#ff6633"), "type": "explosive"},
		{"name": "Seek", "id": "MissileT2", "col": Color("#ff4422"), "type": "explosive"},
		{"name": "Thermo", "id": "MissileT3", "col": Color("#ff2200"), "type": "explosive"},
		{"name": "Photon", "id": "MissileT4", "col": Color("#ff66cc"), "type": "explosive"}
	]
	
	var has_any = false
	for ammo in ammo_list:
		var qty = GameState.resources.get_element_amount(ammo["id"])
		var is_equipped = false
		for slot in sm.ammo_loadout:
			if sm.ammo_loadout[slot] == ammo["id"]:
				is_equipped = true
				break
		
		# We show only if equipped (User Request)
		if is_equipped:
			has_any = true
			var group = VBoxContainer.new()
			group.add_theme_constant_override("separation", 1)
			group.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			ammo_vbox.add_child(group)
			
			var lbl = Label.new()
			lbl.add_theme_font_size_override("font_size", 8)
			lbl.text = ammo["name"].to_upper()
			lbl.modulate = Color(0.6, 0.6, 0.6)
			group.add_child(lbl)
			
			var flow = HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 2)
			flow.add_theme_constant_override("v_separation", 2)
			group.add_child(flow)
			
			# Physical Profile Styles
			var sb_pip = StyleBoxFlat.new()
			sb_pip.bg_color = ammo["col"]
			if ammo["type"] == "kinetic":
				# SLUGS: Sharp and mechanical
				sb_pip.corner_radius_top_left = 1
				sb_pip.corner_radius_bottom_right = 3
			elif ammo["type"] == "explosive":
				# MISSILES: Warhead — pointed top, flat base
				sb_pip.corner_radius_top_left = 3
				sb_pip.corner_radius_top_right = 3
				sb_pip.corner_radius_bottom_left = 0
				sb_pip.corner_radius_bottom_right = 0
			else:
				# CELLS: Rounded energy capsules
				sb_pip.corner_radius_top_left = 3
				sb_pip.corner_radius_top_right = 3
				sb_pip.corner_radius_bottom_left = 3
				sb_pip.corner_radius_bottom_right = 3
			
			# Draw pips (Max 24 for a single row visual feel)
			var display_count = min(qty, 24)
			var capacity = 24 # Capacity of the "Rack" shown
			
			for i in range(capacity):
				var pip = Panel.new()
				pip.custom_minimum_size = Vector2(4, 9)
				if i < display_count:
					var p_style = sb_pip.duplicate()
					# Low ammo color shifts
					if qty < 10: p_style.bg_color = Color.RED
					elif qty < 30: p_style.bg_color = Color.YELLOW
					pip.add_theme_stylebox_override("panel", p_style)
					pip.name = "PIP_ACTIVE"
				else:
					pip.add_theme_stylebox_override("panel", sb_ghost)
				flow.add_child(pip)
			
			if qty > capacity:
				var more = Label.new()
				more.add_theme_font_size_override("font_size", 7)
				more.text = tr("+%d") % (qty - capacity)
				more.modulate.a = 0.5
				flow.add_child(more)
	
	if not has_any:
		var lbl = Label.new()
		lbl.text = tr("MAGAZINES EMPTY")
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.modulate = Color(1.0, 0.3, 0.3)
		ammo_vbox.add_child(lbl)

func _rebuild_weapon_battery(w_states):
	for child in weapon_battery.get_children(): child.queue_free()
	player_weapon_bars.clear()
	
	for w in w_states:
		var pb = ProgressBar.new()
		pb.custom_minimum_size = Vector2(0, 4)
		pb.show_percentage = false
		
		# v87.0: Color-coded by damage type
		var fill_color = Color(0.6, 0.8, 1.0) # Kinetic: Steel Blue
		var type_tag = "KIN"
		match w["type"]:
			"energy":
				fill_color = Color(1.0, 0.9, 0.3) # Energy: Gold
				type_tag = "NRG"
			"explosive":
				fill_color = Color(1.0, 0.5, 0.3) # Explosive: Orange-Red
				type_tag = "EXP"
			"cryo":
				fill_color = Color(0.45, 0.95, 0.95) # Cryo: Icy Cyan
				type_tag = "CRY"
		
		var sb_fill = StyleBoxFlat.new()
		sb_fill.bg_color = fill_color
		sb_fill.set_corner_radius_all(2)
		pb.add_theme_stylebox_override("fill", sb_fill)
		
		var sb_bg = StyleBoxFlat.new()
		sb_bg.bg_color = Color(0.1, 0.1, 0.1, 0.6)
		sb_bg.set_corner_radius_all(2)
		pb.add_theme_stylebox_override("background", sb_bg)
		
		pb.tooltip_text = tr("%s [%s]") % [w["name"], type_tag]
		
		weapon_battery.add_child(pb)
		player_weapon_bars.append(pb)


func _update_atmosphere(_delta):
	# v134h: sector-threat / scanning / target-lock flavor labels removed. Only the
	# ammo-pip danger pulse remains (low / offline ammo blinks red/yellow).
	var time_ms = Time.get_ticks_msec()
	var pulse = (sin(time_ms * 0.005) + 1.0) * 0.5
	var fast_pulse = (sin(time_ms * 0.012) + 1.0) * 0.5 # Faster for danger
	for group in ammo_vbox.get_children():
		var flow = group.get_child(1) if group.get_child_count() > 1 else null
		if flow:
			for pip in flow.get_children():
				if pip.name == "PIP_ACTIVE":
					var style = pip.get_theme_stylebox("panel")
					if style:
						if style.bg_color == Color.RED:
							pip.modulate.a = 0.3 + (fast_pulse * 0.7)
						elif style.bg_color == Color.YELLOW:
							pip.modulate.a = 0.6 + (pulse * 0.4)
						else:
							pip.modulate.a = 1.0

func _on_retreat_btn_pressed():
	manager.retreat()

func _create_centered_label(parent: Control) -> Label:
	var lbl = Label.new()
	lbl.layout_mode = 1 # Anchors
	lbl.anchors_preset = 15 # Full Rect
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 8) # Small font for bars
	lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.add_theme_constant_override("shadow_outline_size", 2)
	parent.add_child(lbl)
	return lbl

# v134h: quiet square tile look for a consumable button (dark bg + accent border),
# matching the loot-grid tiles. Base style only — active/pulse state is a modulate.
func _style_consumable_tile(btn: Button, accent: Color) -> void:
	for st in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		var bg := Color(0.07, 0.10, 0.14, 0.92)
		if st == "hover": bg = Color(0.10, 0.15, 0.20, 0.96)
		elif st == "pressed": bg = Color(0.13, 0.19, 0.25, 0.98)
		elif st == "disabled": bg = Color(0.06, 0.08, 0.11, 0.85)
		s.bg_color = bg
		s.set_corner_radius_all(3)
		s.set_border_width_all(1)
		var bd := accent
		bd.a = 0.45
		s.border_color = bd
		btn.add_theme_stylebox_override(st, s)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _setup_consumable_buttons():
	if not consumable_container: return

	# Build a styled panel matching the scanner/ammo panels.
	# Structure: wrapper(PanelContainer) → inner_vbox → [header, sep, consumable_container]
	var bottom_hud = $Dashboard/HUD/BottomHUD
	var slot = consumable_container.get_index()

	var inner_vbox = VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 5)

	var hdr = Label.new()
	hdr.text = "[ CONSUMABLES ]"
	hdr.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5, 1.0))
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner_vbox.add_child(hdr)

	var sep = HSeparator.new()
	sep.modulate = Color(0.5, 0.9, 0.5, 0.25)
	inner_vbox.add_child(sep)

	var wrapper = PanelContainer.new()
	wrapper.name = "ConsumablesPanel"
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# v134h: inset margin so the [ CONSUMABLES ] header + tiles clear the corner-bracket
	# chrome (the header was rendering under the top brackets).
	var cons_mc := MarginContainer.new()
	cons_mc.add_theme_constant_override("margin_left", 14)
	cons_mc.add_theme_constant_override("margin_right", 14)
	cons_mc.add_theme_constant_override("margin_top", 8)
	cons_mc.add_theme_constant_override("margin_bottom", 8)
	cons_mc.add_child(inner_vbox)
	wrapper.add_child(cons_mc)

	# Insert wrapper at the same position, then move consumable_container inside
	bottom_hud.add_child(wrapper)
	bottom_hud.move_child(wrapper, slot)
	consumable_container.reparent(inner_vbox)

	UITheme.apply_card_style(wrapper, "shipyard")

	# Connect signals
	if not btn_hull_cons.is_connected("pressed", _on_consumable_pressed):
		btn_hull_cons.pressed.connect(_on_consumable_pressed.bind("hull"))
	if not btn_shd_cons.is_connected("pressed", _on_consumable_pressed):
		btn_shd_cons.pressed.connect(_on_consumable_pressed.bind("shield"))

	# v134h: consumables are uniform TILES matching the Expedition Yield loot grid
	# (compact square, dark bg + accent border) instead of wide instrument buttons.
	# The row centers and can hold more tiles as future consumable types are added.
	consumable_container.alignment = BoxContainer.ALIGNMENT_CENTER
	consumable_container.add_theme_constant_override("separation", 6)
	_style_consumable_tile(btn_hull_cons, Color(0.40, 1.0, 0.55))   # hull = green
	_style_consumable_tile(btn_shd_cons, Color(0.40, 0.80, 1.0))    # shield = blue
	for btn in [btn_hull_cons, btn_shd_cons]:
		btn.custom_minimum_size = Vector2(54, 54)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.add_theme_font_size_override("font_size", 10)

	# Shared cooldown indicator (both consumables gate on the same timer).
	# Wrapped in a margined container so it doesn't run under the panel
	# chrome's corner brackets at the bottom edges.
	var cd_pad := MarginContainer.new()
	cd_pad.add_theme_constant_override("margin_left", 24)
	cd_pad.add_theme_constant_override("margin_right", 24)
	cd_pad.add_theme_constant_override("margin_bottom", 4)
	inner_vbox.add_child(cd_pad)
	var cd_box := VBoxContainer.new()
	cd_box.add_theme_constant_override("separation", 2)
	cd_pad.add_child(cd_box)

	_cons_cd_lbl = Label.new()
	_cons_cd_lbl.text = tr("READY")
	_cons_cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cons_cd_lbl.add_theme_font_size_override("font_size", 9)
	_cons_cd_lbl.modulate = Color(0.55, 1.0, 0.75)
	cd_box.add_child(_cons_cd_lbl)

	_cons_cd_bar = ProgressBar.new()
	_cons_cd_bar.min_value = 0
	_cons_cd_bar.max_value = manager.consumable_cooldown_max
	_cons_cd_bar.value = manager.consumable_cooldown_max  # full = ready
	_cons_cd_bar.show_percentage = false
	_cons_cd_bar.custom_minimum_size = Vector2(0, 8)
	UITheme.apply_progress_bar_style(_cons_cd_bar, "shipyard")
	cd_box.add_child(_cons_cd_bar)

func _update_consumable_buttons():
	var sm = GameState.shipyard_manager
	var res = GameState.resources
	
	_update_cons_btn(btn_hull_cons, sm.consumable_hull_slot, "HULL", Color(0.4, 1.0, 0.4))
	_update_cons_btn(btn_shd_cons, sm.consumable_shield_slot, "SHLD", Color(0.4, 0.8, 1.0))

	# Shared cooldown bar — fills up as it nears ready.
	if _cons_cd_bar and _cons_cd_lbl:
		var cd: float = max(0.0, manager.consumable_cooldown)
		var mx: float = max(0.01, manager.consumable_cooldown_max)
		_cons_cd_bar.max_value = mx
		_cons_cd_bar.value = mx - cd
		if cd <= 0.0:
			_cons_cd_lbl.text = tr("READY")
			_cons_cd_lbl.modulate = Color(0.55, 1.0, 0.75)
		else:
			_cons_cd_lbl.text = tr("Cooldown  %.1fs") % cd
			_cons_cd_lbl.modulate = Color(0.78, 0.82, 0.90)

	# Low-hull alarm: pulse the HULL kit so a new player can't miss that
	# they should heal (consumables are manual — nothing auto-saves them).
	if sm.max_hp > 0 and float(sm.current_hp) / float(sm.max_hp) < 0.30 and not btn_hull_cons.disabled:
		var p := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 140.0)
		btn_hull_cons.modulate = Color(1.0, 0.40, 0.30).lerp(Color(1.0, 0.95, 0.40), p)
		btn_hull_cons.tooltip_text = tr("HULL CRITICAL — tap to repair now!")

func _update_cons_btn(btn: Button, item_id: String, label: String, color: Color):
	btn.custom_minimum_size = Vector2(54, 54)   # v134h: uniform square tile
	if item_id == "" or item_id == null:
		btn.text = ""
		btn.disabled = true
		btn.modulate = Color(1, 1, 1, 0.2)
		btn.tooltip_text = tr("Equip a %s consumable in Ship Designer.") % label
		
		# Holographic Placeholder
		var overlay_name = "Placeholder"
		var holder = btn.get_node_or_null(overlay_name)
		if not holder:
			holder = Label.new()
			holder.name = overlay_name
			holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			holder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			holder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			holder.modulate = color
			holder.modulate.a = 0.3
			UITheme.apply_segmented_font(holder, color)
			btn.add_child(holder)
		
		holder.text = tr("%s\n+") % label.to_upper()   # v134h: compact empty-tile label
		holder.show()
		var empty_content = btn.get_node_or_null("ConsContent")
		if empty_content: empty_content.hide()
		return
	
	# If not empty, hide placeholder
	if btn.has_node("Placeholder"):
		btn.get_node("Placeholder").hide()
	
	var qty = GameState.resources.get_element_amount(item_id)
	var dname = ElementDB.get_display_name(item_id)

	# v122.1: ICON over COUNT via a manual centred layout. A Button can't stack
	# icon + text in 4.2 (centred icon_alignment drew the count ON TOP of the
	# icon), so the content is a child VBox that ignores mouse input — the click
	# still lands on the Button. Hull = warm patch icon, Shield = cool booster.
	btn.text = ""
	btn.icon = null
	var content = btn.get_node_or_null("ConsContent")
	if content == null:
		content = VBoxContainer.new()
		content.name = "ConsContent"
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override("separation", 1)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := TextureRect.new()
		ic.name = "Icon"
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(0, 30)
		ic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(ic)
		var cl := Label.new()
		cl.name = "Count"
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.add_theme_font_size_override("font_size", 12)
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(cl)
		btn.add_child(content)
	content.show()
	var icon_path := "res://assets/icons/modules/consumable_%s.svg" % ("hull" if label == "HULL" else "shield")
	(content.get_node("Icon") as TextureRect).texture = (load(icon_path) if ResourceLoader.exists(icon_path) else null)
	var count_lbl := content.get_node("Count") as Label
	count_lbl.text = tr("x%s") % UITheme.format_number(qty)
	count_lbl.add_theme_color_override("font_color", color)
	btn.modulate = Color(1, 1, 1) if qty > 0 else Color(0.5, 0.5, 0.5, 0.8)
	btn.clip_text = false
	
	# Disabled if 0 or cooldown active
	var cooldown = manager.consumable_cooldown
	btn.disabled = qty <= 0 or cooldown > 0
	
	if cooldown > 0:
		btn.tooltip_text = tr("Cooldown: %.1fs") % cooldown
	else:
		btn.tooltip_text = tr("Use %s to restore %s.") % [dname, label]

func _on_consumable_pressed(type: String):
	manager.use_manual_consumable(type)


# --------------------------------------------------------------------------
# Combat-session HUD timers
# --------------------------------------------------------------------------
# Two readouts injected into the top-center HUD:
#  · SESSION  — total combat time since engage; runs until retreat.
#  · LAST KILL — resets to 0 on every enemy_defeated; tracks current kill pace.
# Both read directly from combat_manager state vars, no extra signals needed.
func _build_combat_timers() -> void:
	var center = $Dashboard/HUD/TopHUD/CenterInfo
	if center == null:
		return

	combat_timer_row = HBoxContainer.new()
	combat_timer_row.name = "CombatTimers"
	combat_timer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	combat_timer_row.add_theme_constant_override("separation", 14)
	combat_timer_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(combat_timer_row)

	session_timer_lbl = _make_timer_label("SESSION  0:00", UITheme.CATEGORY_COLORS["combat"])
	combat_timer_row.add_child(session_timer_lbl)

	var dot := Label.new()
	dot.text = "·"
	dot.add_theme_color_override("font_color", Color(0.5, 0.52, 0.6))
	dot.add_theme_font_size_override("font_size", 12)
	combat_timer_row.add_child(dot)

	kill_timer_lbl = _make_timer_label("LAST KILL  0.0s", UITheme.CATEGORY_COLORS["shipyard"])
	combat_timer_row.add_child(kill_timer_lbl)

	combat_timer_row.visible = false


func _make_timer_label(initial: String, col: Color) -> Label:
	var l := Label.new()
	l.text = initial
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", 12)
	return l


func _refresh_combat_timers() -> void:
	if combat_timer_row == null:
		return
	if not manager.in_combat:
		if combat_timer_row.visible:
			combat_timer_row.visible = false
		return
	if not combat_timer_row.visible:
		combat_timer_row.visible = true
	session_timer_lbl.text = tr("SESSION  %s") % _fmt_session(manager.combat_session_time)
	kill_timer_lbl.text = tr("LAST KILL  %s") % _fmt_kill(manager.time_since_last_kill)


# v113 / v134h: loadout-swap selector — the Melvor-style equipment-set swap, so the
# player never has to trek to the Ship Designer to re-fit. Housed in its own bracketed
# [ LOADOUT ] card (matches the Nav/Enemy panels). BETWEEN fights it's freely available
# (pre-battle prep — the auto-battler's sanctioned expression point): tap a chip to swap
# your WHOLE ship. During a MULTI-PHASE boss the mid-fight swap stays live (the locked
# in-fight exception); a normal single-phase fight hides it (no mid-fight inputs).
# Chips show the player-assigned build NAME (from the Ship Designer), never an auto tag.
var loadout_swap_card: PanelContainer = null
var loadout_swap_row: HBoxContainer = null
var _swap_buttons: Array = []

func _build_loadout_swap_row() -> void:
	var center = $Dashboard/HUD/TopHUD/CenterInfo
	if center == null:
		return
	var card := PanelContainer.new()
	card.name = "LoadoutCard"
	card.size_flags_horizontal = Control.SIZE_SHRINK_END   # v134h: top-RIGHT, aligns with the enemy/consumables column
	UITheme.apply_card_style(card, "shipyard")   # bracketed chrome, matches the other panels
	center.add_child(card)
	loadout_swap_card = card

	# v134h: inset margin so the header + chips clear the corner-bracket chrome
	# (which paints over the card edges — text was running under the right bracket).
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 16)
	mc.add_theme_constant_override("margin_right", 16)
	mc.add_theme_constant_override("margin_top", 8)
	mc.add_theme_constant_override("margin_bottom", 10)
	card.add_child(mc)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	mc.add_child(vb)

	var header := Label.new()
	header.text = "[ LOADOUT ]"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS.get("shipyard", Color(0.45, 0.70, 1.0)))
	header.add_theme_font_size_override("font_size", 11)
	vb.add_child(header)

	var sep := HSeparator.new()
	vb.add_child(sep)

	loadout_swap_row = HBoxContainer.new()
	loadout_swap_row.name = "LoadoutSwap"
	loadout_swap_row.alignment = BoxContainer.ALIGNMENT_CENTER
	loadout_swap_row.add_theme_constant_override("separation", 6)
	vb.add_child(loadout_swap_row)

	_swap_buttons = []
	for i in [1, 2, 3, 4, 5]:
		var b := Button.new()
		b.text = tr("L%d") % i
		b.tooltip_text = tr("Swap to Loadout %d") % i
		b.custom_minimum_size = Vector2(40, 0)
		b.add_theme_font_size_override("font_size", 11)
		_style_loadout_chip(b)
		b.pressed.connect(_on_combat_swap_pressed.bind(i))
		loadout_swap_row.add_child(b)
		_swap_buttons.append(b)

	card.visible = false

# Quiet themed chip (shipyard accent) so the row reads as part of the console, not
# five default grey buttons. Base style only — active/empty state is a per-refresh modulate.
func _style_loadout_chip(btn: Button) -> void:
	var accent: Color = UITheme.CATEGORY_COLORS.get("shipyard", Color(0.45, 0.70, 1.0))
	for st in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		var bg := accent
		bg.a = 0.12
		if st == "hover": bg.a = 0.24
		elif st == "pressed": bg.a = 0.34
		elif st == "disabled": bg.a = 0.06
		s.bg_color = bg
		s.set_corner_radius_all(2)
		s.set_border_width_all(1)
		var bd := accent
		bd.a = 0.40
		s.border_color = bd
		s.content_margin_left = 8
		s.content_margin_right = 8
		s.content_margin_top = 3
		s.content_margin_bottom = 3
		btn.add_theme_stylebox_override(st, s)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", accent.lightened(0.35))
	btn.add_theme_color_override("font_disabled_color", Color(0.50, 0.52, 0.58))

func _refresh_loadout_swap_row() -> void:
	if loadout_swap_card == null:
		return
	var sm = GameState.shipyard_manager
	# v134h: show whenever there are 2+ builds to switch between — BETWEEN fights AND
	# mid-combat (swapping in any fight is now allowed; see can_swap_loadout_in_combat).
	var non_empty := 0
	for k in [1, 2, 3, 4, 5]:
		if not sm.is_loadout_preset_empty(k):
			non_empty += 1
	var show_row: bool = non_empty >= 2
	if loadout_swap_card.visible != show_row:
		loadout_swap_card.visible = show_row
	if not show_row:
		return
	var active: int = int(sm.active_preset_idx) if "active_preset_idx" in sm else 1
	for i in range(_swap_buttons.size()):
		var idx: int = i + 1
		var b: Button = _swap_buttons[i]
		var empty: bool = sm.is_loadout_preset_empty(idx)
		var pname := str(sm.loadout_presets.get(idx, {}).get("name", ""))
		var shown := pname if pname != "" else ("Loadout %d" % idx)
		var is_active: bool = (idx == active)
		b.disabled = empty
		if empty:
			b.text = tr("L%d") % idx   # v134h: compact so 5 chips fit without clipping
			b.tooltip_text = tr("Loadout %d — empty (build & name one in the Ship Designer).") % idx
			b.modulate = Color(1, 1, 1, 0.40)
		else:
			b.text = _truncate(shown, 10)
			b.tooltip_text = ("%s — active build." % shown) if is_active else ("Swap to %s." % shown)
			b.modulate = Color(1.40, 1.40, 1.20) if is_active else Color(1, 1, 1, 1)

func _truncate(s: String, n: int) -> String:
	return s if s.length() <= n else (s.substr(0, n - 1) + "…")

func _on_combat_swap_pressed(idx: int) -> void:
	var sm = GameState.shipyard_manager
	if sm.is_loadout_preset_empty(idx):
		return
	var pname := str(sm.loadout_presets.get(idx, {}).get("name", ""))
	var shown := pname if pname != "" else ("Loadout %d" % idx)
	var swapped := false
	if manager.in_combat:
		# v134h: mid-fight swap allowed in any active fight; resets weapon cooldowns.
		if manager.swap_loadout_in_combat(idx):
			swapped = true
			UITheme.show_notification("Swapped to %s" % shown, Color(0.70, 0.95, 1.0))
	else:
		# Between fights: free whole-ship swap via the designer's preset loader.
		var res = sm.load_loadout_preset(idx)
		if int(res.get("loaded", 0)) > 0:
			swapped = true
			UITheme.show_notification("%s equipped" % shown, Color(0.70, 0.95, 1.0))
	if swapped:
		# v134h: the new loadout has different weapons -> different ammo + consumables,
		# so refresh those panels immediately (update_ui only rebuilds ammo mid-combat).
		_update_ammo_display()
		_update_consumable_buttons()
		_refresh_loadout_swap_row()   # re-highlight the now-active chip


# Clock-style mm:ss (or h:mm:ss past an hour). Always shows a whole-second
# tick so the session readout doesn't jitter.
func _fmt_session(t: float) -> String:
	var s := int(t)
	var mm := s / 60
	var ss := s % 60
	if mm < 60:
		return "%d:%02d" % [mm, ss]
	var hh := mm / 60
	mm = mm % 60
	return "%d:%02d:%02d" % [hh, mm, ss]


# Sub-second precision under a minute (kill-pace cue), clock format after.
func _fmt_kill(t: float) -> String:
	if t < 60.0:
		return "%.1fs" % t
	var s := int(t)
	return "%d:%02d" % [s / 60, s % 60]
