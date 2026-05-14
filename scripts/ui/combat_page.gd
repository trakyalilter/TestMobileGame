extends Control

@onready var zone_list = $Dashboard/HUD/TopHUD/NavPanel/VBox/ZoneList
@onready var enemy_container = $Dashboard/HUD/TopHUD/TargetPanel/VBox/Scroll/EnemyList

# Arena Refs
@onready var visualizer = $Dashboard/Visualizer
@onready var radar_lines = $Dashboard/Visualizer/Background/RadarLines
@onready var radar_display = $Dashboard/Visualizer/RadarDisplay
@onready var threat_lbl = $Dashboard/HUD/TopHUD/CenterInfo/SectorThreat
@onready var scan_lbl = $Dashboard/HUD/TopHUD/CenterInfo/ScanningStatus

@onready var p_name_lbl = $Dashboard/HUD/MidHUD/PlayerStatsOverlay/Margin/VBox/NameLabel
@onready var p_stat_lbl = $Dashboard/HUD/MidHUD/PlayerStatsOverlay/Margin/VBox/StatsLabel
@onready var p_hp_lbl = $Dashboard/HUD/MidHUD/PlayerStatsOverlay/Margin/VBox/Grid/HealthLabel
@onready var p_sh_lbl = $Dashboard/HUD/MidHUD/PlayerStatsOverlay/Margin/VBox/Grid/ShieldLabel
@onready var p_heat_bar = $Dashboard/HUD/MidHUD/PlayerStatsOverlay/Margin/VBox/HeatBar
@onready var weapon_battery = $Dashboard/HUD/MidHUD/PlayerStatsOverlay/Margin/VBox/WeaponBattery
@onready var p_buff_container = $Dashboard/HUD/MidHUD/PlayerStatsOverlay/Margin/VBox/BuffContainer

var player_weapon_bars = []

@onready var e_name_lbl = $Dashboard/HUD/MidHUD/EnemyStatsOverlay/Margin/VBox/NameLabel
@onready var e_stat_lbl = $Dashboard/HUD/MidHUD/EnemyStatsOverlay/Margin/VBox/StatsLabel
@onready var e_hp_lbl = $Dashboard/HUD/MidHUD/EnemyStatsOverlay/Margin/VBox/Grid/HealthLabel
@onready var e_sh_lbl = $Dashboard/HUD/MidHUD/EnemyStatsOverlay/Margin/VBox/Grid/ShieldLabel
@onready var e_attack_pb = $Dashboard/HUD/MidHUD/EnemyStatsOverlay/Margin/VBox/E_AttackBar

@onready var scanner_overlay = $Dashboard/HUD/BottomHUD/ScannerOverlay
@onready var loot_lbl = $Dashboard/HUD/BottomHUD/ScannerOverlay/Margin/VBox/Scroll/LootVBox/LootText

@onready var ammo_overlay = $Dashboard/HUD/BottomHUD/AmmoOverlay
@onready var ammo_vbox = $Dashboard/HUD/BottomHUD/AmmoOverlay/Margin/VBox/AmmoGroupVBox

# Controls
@onready var btn_retreat = $Dashboard/HUD/BottomHUD/RetreatContainer/RetreatBtn

@onready var consumable_container = $Dashboard/HUD/BottomHUD/ConsumablesContainer
@onready var btn_hull_cons = $Dashboard/HUD/BottomHUD/ConsumablesContainer/ConsHullBtn
@onready var btn_shd_cons = $Dashboard/HUD/BottomHUD/ConsumablesContainer/ConsShieldBtn

var manager: RefCounted

# Enemy List Item Prefab
var enemy_card_scene = preload("res://scenes/ui/combat_enemy_card.tscn")
var enemy_info_scene = preload("res://scenes/ui/enemy_info_modal.tscn")

func _ready():
	manager = GameState.combat_manager
	call_deferred("refresh_zones")
	GameState.game_loaded.connect(refresh_zones)
	if GameState.research_manager:
		GameState.research_manager.tech_unlocked.connect(func(_id): refresh_zones())
	
	# HUD Stress & Console Interaction
	
	# Initial Suppression
	
	UITheme.apply_premium_button_style(btn_retreat, "combat")
	
	UITheme.apply_progress_bar_style(e_attack_pb, "combat")
	
	UITheme.apply_card_style($Dashboard/HUD/TopHUD/NavPanel, "ops")
	UITheme.apply_card_style($Dashboard/HUD/TopHUD/TargetPanel, "combat")
	UITheme.apply_card_style($Dashboard/HUD/MidHUD/PlayerStatsOverlay, "shipyard")
	UITheme.apply_card_style($Dashboard/HUD/MidHUD/EnemyStatsOverlay, "combat")
	UITheme.apply_card_style(ammo_overlay, "inventory")
	UITheme.apply_card_style(scanner_overlay, "research")
	
	radar_display.draw.connect(_on_radar_draw)
	

	# PHASE 22: Inject XP Bar programmatically
	_setup_xp_bar()
	_setup_hp_bars()
	_setup_consumable_buttons()
	
	# Create Label for Heat Bar (which is already in scene)
	if p_heat_bar:
		p_heat_label = _create_centered_label(p_heat_bar)

	# Explicit Signal Connections (Defensive)
	if not btn_retreat.is_connected("pressed", _on_retreat_btn_pressed): btn_retreat.pressed.connect(_on_retreat_btn_pressed)
	
	if not manager.heat_changed.is_connected(_on_heat_changed):
		manager.heat_changed.connect(_on_heat_changed)
	
	# Initial Sync
	_on_heat_changed(manager.player_heat, manager.player_max_heat)
	
	_setup_loot_filter_button()

var p_xp_bar: ProgressBar
var p_xp_label: Label
var p_heat_label: Label
var p_hp_bar: HBoxContainer
var p_sh_bar: HBoxContainer
var e_hp_bar: HBoxContainer
var e_sh_bar: HBoxContainer

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

func _setup_xp_bar():
	# Create bar
	p_xp_bar = ProgressBar.new()
	p_xp_bar.custom_minimum_size = Vector2(0, 6) # Thin but visible
	p_xp_bar.show_percentage = false
	
	# Premium Style
	var sb_bg = StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	sb_bg.border_width_bottom = 1
	sb_bg.border_color = Color(0, 0, 0)
	
	var sb_fill = StyleBoxFlat.new()
	sb_fill.bg_color = Color(0.7, 0.4, 1.0) # Combat Purple/Veterancy
	sb_fill.set_corner_radius_all(1)
	
	p_xp_bar.add_theme_stylebox_override("background", sb_bg)
	p_xp_bar.add_theme_stylebox_override("fill", sb_fill)
	
	# Add to HUD
	var container = $Dashboard/HUD/MidHUD/PlayerStatsOverlay/Margin/VBox
	container.add_child(p_xp_bar)
	
	# Create Label for XP Bar
	p_xp_label = _create_centered_label(p_xp_bar)
	if p_xp_label: p_xp_label.add_theme_font_size_override("font_size", 8)

	container.move_child(p_xp_bar, 1)

func _setup_loot_filter_button():
	var btn = Button.new()
	btn.text = "▼ FILTER"
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
	zone_list.clear()
	var zones = manager.get_available_zones()
	for z in zones:
		var idx = zone_list.add_item(z["data"]["name"])
		zone_list.set_item_metadata(idx, z["id"])
		# v86.0: Color hazard zones differently
		if z.get("is_hazard", false):
			zone_list.set_item_custom_fg_color(idx, Color.YELLOW)
			if manager.hazard_clears.has(z["id"]):
				zone_list.set_item_custom_fg_color(idx, Color(0.6, 0.8, 0.2))
		# Recommended power tooltip: find boss stats for this zone
		var zone_data = z["data"]
		var enemy_list = zone_data.get("enemies", [])
		var boss_hp = 0
		var boss_atk = 0
		var boss_name = ""
		var toughest_hp = 0
		var toughest_atk = 0
		for eid in enemy_list:
			var edata = manager.enemy_db.get(eid, {})
			var estats = edata.get("stats", {})
			if edata.get("is_boss", false):
				boss_hp = estats.get("hp", 0)
				boss_atk = estats.get("atk", 0)
				boss_name = edata.get("name", "Boss")
			else:
				if estats.get("hp", 0) > toughest_hp:
					toughest_hp = estats.get("hp", 0)
					toughest_atk = estats.get("atk", 0)
		var rec_dps = int(boss_hp / 30.0) if boss_hp > 0 else int(toughest_hp / 15.0)
		var tooltip = "Zone %d\n" % zone_data.get("difficulty", 1)
		tooltip += "Strongest Enemy: %s HP | %s ATK\n" % [UITheme.format_num(toughest_hp), UITheme.format_num(toughest_atk)]
		if boss_hp > 0:
			tooltip += "%s: %s HP | %s ATK\n" % [boss_name, UITheme.format_num(boss_hp), UITheme.format_num(boss_atk)]
		tooltip += "Recommended DPS: ~%s" % UITheme.format_num(rec_dps)
		zone_list.set_item_tooltip(idx, tooltip)

func _on_zone_list_item_selected(index):
	var zid = zone_list.get_item_metadata(index)
	refresh_enemies(zid)

var last_refreshed_zone = ""

func refresh_enemies(zone_id):
	if last_refreshed_zone == zone_id and enemy_container.get_child_count() > 0:
		return
	last_refreshed_zone = zone_id
	
	if not enemy_container: return
	for child in enemy_container.get_children():
		child.queue_free()
	
	# v86.0: Handle hazard zones
	if zone_id in manager.hazard_zones:
		var hz = manager.hazard_zones[zone_id]
		var all_enemies = hz["enemy_pool"].duplicate()
		all_enemies.append(hz["elite_enemy"])
		all_enemies.append(hz["boss_enemy"])
		
		# Add info card about the hazard
		var info_label = Label.new()
		info_label.text = "⚠ HAZARD: %s\n%d Wave Gauntlet | Requires: %s\n%s" % [
			hz["hazard_type"].replace("_", " ").to_upper(),
			hz["max_waves"],
			GameState.shipyard_manager.modules.get(hz["counter_module"], {}).get("name", hz["counter_module"]),
			"✅ CLEARED" if manager.hazard_clears.has(zone_id) else "❌ NOT CLEARED"
		]
		info_label.add_theme_color_override("font_color", Color.YELLOW)
		info_label.add_theme_font_size_override("font_size", 11)
		info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		enemy_container.add_child(info_label)
		
		for eid in all_enemies:
			if eid in manager.enemy_db:
				var card = enemy_card_scene.instantiate()
				enemy_container.add_child(card)
				var edata = manager.enemy_db[eid]
				card.setup(eid, edata, self)
		return
	
	if not zone_id in manager.zones: return
	
	var enemies = manager.zones[zone_id]["enemies"].duplicate()
	
	# Sort weakest → strongest; boss always last regardless of stats
	enemies.sort_custom(func(a, b):
		var e_a = manager.enemy_db[a]
		var e_b = manager.enemy_db[b]
		var boss_a = e_a.get("is_boss", false)
		var boss_b = e_b.get("is_boss", false)
		if boss_a != boss_b:
			return not boss_a  # non-boss sorts before boss
		var score_a = (e_a["stats"].get("hp", 0) + e_a["stats"].get("max_shield", 0)) \
			* (1.0 + e_a["stats"].get("def", 0) / 100.0) \
			* (1.0 + e_a["stats"].get("atk", 0) / 50.0)
		var score_b = (e_b["stats"].get("hp", 0) + e_b["stats"].get("max_shield", 0)) \
			* (1.0 + e_b["stats"].get("def", 0) / 100.0) \
			* (1.0 + e_b["stats"].get("atk", 0) / 50.0)
		return score_a < score_b
	)
	
	for eid in enemies:
		var card = enemy_card_scene.instantiate()
		enemy_container.add_child(card)
		var edata = manager.enemy_db[eid]
		card.setup(eid, edata, self)

func get_enemy_card(enemy_id: String) -> Control:
	for child in enemy_container.get_children():
		if child.get("eid") == enemy_id:
			return child
	return null

func focus_zone(zone_id: String):
	for i in range(zone_list.item_count):
		if zone_list.get_item_metadata(i) == zone_id:
			if not zone_list.is_selected(i):
				zone_list.select(i)
				_on_zone_list_item_selected(i)
			return

func start_fight(enemy_id, zone_id):
	# Zone ID is needed for start_expedition? 
	# Manager's start_expedition takes zone_id
	# Manager's set_target_enemy takes enemy_id
	# We need both.
	# But refresh_enemies only has zone_id context if we store it
	manager.set_target_enemy(enemy_id)
	
	# If we are viewing a zone, that is the zone we want to fight in.
	# But wait, start_expedition sets current_zone.
	# If we just click "Fight" on an enemy card, we imply starting expedition in that zone?
	# Implementation detail: card needs to know zone? Or we pass it.
	pass

func request_fight(eid):
	# Find which zone this is? 
	# We can just use the currently selected zone from the list
	var items = zone_list.get_selected_items()
	if items.size() == 0: return
	var zid = zone_list.get_item_metadata(items[0])
	
	# v86.0: Route hazard zones to start_hazard (gauntlet mode)
	if zid in manager.hazard_zones:
		manager.start_hazard(zid)
		return
	
	manager.start_expedition(zid)
	manager.set_target_enemy(eid)

func _process(delta):
	update_ui()
	_update_atmosphere(delta)

func update_ui():
	# Update Haptics & Visualizer
	radar_display.queue_redraw()

	# Player Stats
	var sm = GameState.shipyard_manager
	var eva_bonus = manager.get_milestone_evasion_bonus()
	var crit_bonus = manager.get_milestone_crit_bonus()
	var total_eva = sm.evasion + eva_bonus
	var total_crit = (sm.crit_chance + crit_bonus) * 100.0
	
	p_stat_lbl.text = "ATK: %s | DEF: %s | EVA: %.0f | CRIT: %.0f%%" % [UITheme.format_num(sm.attack), UITheme.format_num(sm.defense), total_eva, total_crit]
	
	# Simplified Level Info
	var lvl_info = "[Lv.%d]" % manager.get_level()
	if manager.get_level() > 0:
		lvl_info += " +%.1f%% DMG" % (manager.get_level() * 0.5)
	
	var hull_name = sm.get_ship_name() if sm and sm.has_method("get_ship_name") else "USS HORIZON"
	p_name_lbl.text = "%s %s" % [hull_name.to_upper(), lvl_info]
	
	# Sync Block Bars
	_update_block_bar(p_hp_bar, float(sm.current_hp) / max(1.0, sm.max_hp))
	_update_block_bar(p_sh_bar, float(manager.player_shield) / max(1.0, manager.player_max_shield))
	p_sh_bar.visible = manager.player_max_shield > 0
	
	p_hp_lbl.text = "HULL: %s/%s" % [UITheme.format_num(sm.current_hp), UITheme.format_num(sm.max_hp)]
	p_sh_lbl.text = "SHD: %s/%s" % [UITheme.format_num(manager.player_shield), UITheme.format_num(manager.player_max_shield)]
	
	# ... (rest of logic)
	
	# Enemy Stats
	if manager.in_combat and manager.current_enemy:
		var enemy = manager.current_enemy
		e_name_lbl.text = enemy["name"]
		
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
		e_stat_lbl.text = "DMG: %s [%s] | DEF: %s" % [UITheme.format_num(enemy.get("atk", 0)), e_type_tag, UITheme.format_num(enemy.get("def", 0))]
		
		# v86.0: Show wave counter during hazard gauntlet
		if manager.hazard_state["active"]:
			var wave_text = "WAVE %d/%d" % [manager.hazard_state["wave"] + 1, manager.hazard_state["max_waves"]]
			e_name_lbl.text = "[%s] %s" % [wave_text, enemy["name"]]
		
		_update_block_bar(e_hp_bar, float(manager.enemy_hp) / max(1.0, manager.enemy_max_hp))
		_update_block_bar(e_sh_bar, float(manager.enemy_shield) / max(1.0, manager.enemy_max_shield))
		
		e_hp_lbl.text = "HULL: %s/%s" % [UITheme.format_num(manager.enemy_hp), UITheme.format_num(manager.enemy_max_hp)]
		e_sh_lbl.text = "SHD: %s/%s" % [UITheme.format_num(manager.enemy_shield), UITheme.format_num(manager.enemy_max_shield)]
		btn_retreat.disabled = false
	else:
		e_name_lbl.text = "NO TARGET"
		_update_block_bar(e_hp_bar, 0)
		_update_block_bar(e_sh_bar, 0)
		e_stat_lbl.text = "DMG: 0 | DEF: 0"
		btn_retreat.disabled = true
	
	# Attack Timers
	if manager.in_combat:
		# Sync Weapon Battery
		var w_states = manager.player_weapon_states
		if player_weapon_bars.size() != w_states.size():
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
		scanner_overlay.visible = false
		ammo_overlay.visible = false
		scan_lbl.text = "SCANNING FOR ANOMALIES..."

	# Log - DISABLED (User Request)
	# Log Removed

	# Retreat Btn
	btn_retreat.disabled = not manager.in_combat
	
	# Update Consumable Action Buttons
	_update_consumable_buttons()


	# Process Combat Events (Floating Text + Haptics)
	while manager.combat_events.size() > 0:
		var ev = manager.combat_events.pop_front()
		if is_visible_in_tree():
			UITheme.show_notification(ev["text"], ev["color"])
		
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
	_draw_arc_poly(center, 132, 138, 110, 250, Color(0, 0.8, 1, 0.1), Color(0, 0.8, 1, 0.6), p_sh_pct)

	# --- ENEMY ARCS (Right) ---
	if manager.in_combat and manager.current_enemy:
		var e_hp_pct = float(manager.enemy_hp) / max(1.0, manager.enemy_max_hp)
		var e_sh_pct = float(manager.enemy_shield) / max(1.0, manager.enemy_max_shield)
		
		# Enemy HP Arc - Radius 120-126 (Symmetrical)
		_draw_arc_poly(center, 120, 126, -70, 70, Color(1, 0, 0, 0.1), Color(1, 0, 0, 0.8), e_hp_pct)
		# Enemy Shield Arc - Radius 132-138 (Symmetrical)
		_draw_arc_poly(center, 132, 138, -70, 70, Color(0, 0.8, 1, 0.1), Color(0, 0.8, 1, 0.6), e_sh_pct)
		
	# --- RETICLE & DECORATION ---
	radar_display.draw_circle(center, 5, Color(1, 1, 1, 0.1)) # Center dot
	radar_display.draw_arc(center, 100, 0, TAU, 64, Color(1, 1, 1, 0.05), 1.0) # Inner guide ring

func _draw_arc_poly(center: Vector2, inner_radius: float, outer_radius: float, start_deg: float, end_deg: float, bg_color: Color, fill_color: Color, percent: float):
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

func _update_session_loot():
	var tt = "[center]"
	
	if manager.session_loot.is_empty():
		tt += "[color=#666666][ NO YIELD ][/color]"
	else:
		for item_id in manager.session_loot:
			var qty = manager.session_loot[item_id]
			var sm = GameState.shipyard_manager
			# v71.1: Custom modules use shipyard name + rarity color
			var str_id = str(item_id)
			if str_id.begins_with("custom_"):
				if sm.modules.has(str_id):
					var m_data = sm.modules[str_id]
					var rarity = int(m_data.get("rarity", sm.Rarity.COMMON))
					var rarity_hex = sm.RARITY_COLORS.get(rarity, Color.WHITE).to_html(false)
					tt += "[color=#%s]★ %s[/color] x %s\n" % [rarity_hex, m_data["name"], UITheme.format_num(qty)]
				else:
					# Fallback: Parse the base module name out of 'custom_basemodule_1234'
					var parts = str_id.split("_")
					var base_id = str_id.trim_prefix("custom_")
					# Remove the trailing timestamp number
					if parts.size() > 2 and parts[-1].is_valid_int():
						base_id = base_id.trim_suffix("_" + parts[-1])
					var base_name = sm.modules.get(base_id, {"name": base_id}).get("name", base_id)
					tt += "[color=#aaaaaa]★ %s (Data Lost)[/color] x %s\n" % [base_name, UITheme.format_num(qty)]
			else:
				var item_name = str_id
				if sm.modules.has(str_id):
					item_name = sm.modules[str_id].get("name", str_id)
				else:
					item_name = ElementDB.get_display_name(str_id)
					if item_name == str_id:
						item_name = str_id.replace("_", " ").capitalize()
				tt += "[color=#32cd32]%s[/color] x %s\n" % [item_name, UITheme.format_num(qty)]
			
	tt += "[/center]"
	
	if loot_lbl.text != tt:
		loot_lbl.text = tt

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
				more.text = "+%d" % (qty - capacity)
				more.modulate.a = 0.5
				flow.add_child(more)
	
	if not has_any:
		var lbl = Label.new()
		lbl.text = "MAGAZINES EMPTY"
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
		
		var sb_fill = StyleBoxFlat.new()
		sb_fill.bg_color = fill_color
		sb_fill.set_corner_radius_all(2)
		pb.add_theme_stylebox_override("fill", sb_fill)
		
		var sb_bg = StyleBoxFlat.new()
		sb_bg.bg_color = Color(0.1, 0.1, 0.1, 0.6)
		sb_bg.set_corner_radius_all(2)
		pb.add_theme_stylebox_override("background", sb_bg)
		
		pb.tooltip_text = "%s [%s]" % [w["name"], type_tag]
		
		weapon_battery.add_child(pb)
		player_weapon_bars.append(pb)


func _update_atmosphere(delta):
	# Pulse scanning label
	var time_ms = Time.get_ticks_msec()
	var pulse = (sin(time_ms * 0.005) + 1.0) * 0.5
	scan_lbl.modulate.a = 0.2 + (pulse * 0.4)
	
	# AMMO PULSE (OFFLINE/LOW)
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
						
	if manager.in_combat:
		scan_lbl.text = "TARGET LOCK CONFIRMED"
		threat_lbl.text = "SECTOR THREAT: ENGAGED"
		threat_lbl.modulate = Color(1, 0.3, 0.3, 0.8) # Red alert
		
		
		# Gearing Tip: Warn if Accuracy is making Evasion useless
		var sm = GameState.shipyard_manager
		if manager.current_enemy:
			var e_acc = manager.current_enemy.get("accuracy", 0)
			if e_acc > 10: # Only warn outside Tier 1
				var dodge_chance = float(sm.evasion) / (float(sm.evasion) + 150.0 * (1.0 + float(e_acc) / 100.0))
				if dodge_chance < 0.2 and sm.max_shield < 100:
					scan_lbl.text = "CAUTION: EVASION COMPROMISED - SHIELDS REQUIRED"
					scan_lbl.modulate = Color(1.0, 0.5, 0.0) # Warning Orange
	else:
		threat_lbl.text = "SECTOR THREAT: NOMINAL"
		threat_lbl.modulate = Color(1, 0.8, 0, 0.5) # Yellow cautious

func _on_retreat_btn_pressed():
	manager.retreat()

func _on_heat_changed(current: float, maximum: float):
	if p_heat_bar:
		p_heat_bar.max_value = maximum
		p_heat_bar.value = current
		
		# Update Heat Label
		if p_heat_label:
			var pct = 0.0
			if maximum > 0:
				pct = (current / maximum) * 100.0
			p_heat_label.text = "%.0f%%" % pct

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
	wrapper.add_child(inner_vbox)

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

	# Apply Premium styling
	UITheme.apply_instrument_style(btn_hull_cons, "shipyard")
	UITheme.apply_instrument_style(btn_shd_cons, "combat")

	for btn in [btn_hull_cons, btn_shd_cons]:
		btn.custom_minimum_size = Vector2(100, 45)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 10)
	
func _update_consumable_buttons():
	var sm = GameState.shipyard_manager
	var res = GameState.resources
	
	_update_cons_btn(btn_hull_cons, sm.consumable_hull_slot, "HULL", Color(0.4, 1.0, 0.4))
	_update_cons_btn(btn_shd_cons, sm.consumable_shield_slot, "SHLD", Color(0.4, 0.8, 1.0))

func _update_cons_btn(btn: Button, item_id: String, label: String, color: Color):
	if item_id == "" or item_id == null:
		btn.text = ""
		btn.disabled = true
		btn.modulate = Color(1, 1, 1, 0.2)
		btn.tooltip_text = "Equip a %s consumable in Ship Designer." % label
		
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
		
		holder.text = "[[ %s SLOT ]]\nSTANDBY" % label.to_upper()
		holder.show()
		return
	
	# If not empty, hide placeholder
	if btn.has_node("Placeholder"):
		btn.get_node("Placeholder").hide()
	
	var qty = GameState.resources.get_element_amount(item_id)
	var dname = ElementDB.get_display_name(item_id)
	
	# v66.0: Multi-line display
	btn.text = "%s\n%s\nx%s" % [label, dname.to_upper(), UITheme.format_number(qty)]
	btn.modulate = color if qty > 0 else Color(0.5, 0.5, 0.5, 0.8)
	btn.clip_text = false # Ensure we see it
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	# Disabled if 0 or cooldown active
	var cooldown = manager.consumable_cooldown
	btn.disabled = qty <= 0 or cooldown > 0
	
	if cooldown > 0:
		btn.tooltip_text = "Cooldown: %.1fs" % cooldown
	else:
		btn.tooltip_text = "Use %s to restore %s." % [dname, label]

func _on_consumable_pressed(type: String):
	manager.use_manual_consumable(type)
