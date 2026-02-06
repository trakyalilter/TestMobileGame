extends Control

@onready var zone_list = $Dashboard/Visualizer/HUD/Overlays/SectorOverlay/VBox/ZoneList
@onready var enemy_container = $Dashboard/Visualizer/HUD/Overlays/TargetingOverlay/VBox/Scroll/EnemyList
@onready var log_list = $Dashboard/Visualizer/HUD/Overlays/BottomRegion/LogOverlay/VBox/LogList

# Arena Refs
@onready var visualizer = $Dashboard/Visualizer
@onready var radar_lines = $Dashboard/Visualizer/Background/RadarLines
@onready var radar_display = $Dashboard/Visualizer/RadarDisplay
@onready var threat_lbl = $Dashboard/Visualizer/HUD/CenterInfo/SectorThreat
@onready var scan_lbl = $Dashboard/Visualizer/HUD/CenterInfo/ScanningStatus
@onready var scan_line = $Dashboard/Visualizer/ScanLine

@onready var p_name_lbl = $Dashboard/Visualizer/HUD/Overlays/SectorOverlay/VBox/PlayerStats/NameLabel
@onready var p_stat_lbl = $Dashboard/Visualizer/HUD/Overlays/SectorOverlay/VBox/PlayerStats/StatsLabel
@onready var p_hp_lbl = $Dashboard/Visualizer/HUD/Overlays/SectorOverlay/VBox/PlayerStats/HealthLabel
@onready var p_sh_lbl = $Dashboard/Visualizer/HUD/Overlays/SectorOverlay/VBox/PlayerStats/ShieldLabel
@onready var p_heat_bar = $Dashboard/Visualizer/HUD/Overlays/SectorOverlay/VBox/PlayerStats/HeatBar
@onready var weapon_battery = $Dashboard/Visualizer/HUD/Overlays/SectorOverlay/VBox/PlayerStats/WeaponBattery
@onready var p_buff_container = $Dashboard/Visualizer/HUD/Overlays/SectorOverlay/VBox/PlayerStats/BuffContainer

var player_weapon_bars = []

@onready var e_name_lbl = $Dashboard/Visualizer/HUD/Overlays/TargetingOverlay/VBox/EnemyStats/NameLabel
@onready var e_stat_lbl = $Dashboard/Visualizer/HUD/Overlays/TargetingOverlay/VBox/EnemyStats/StatsLabel
@onready var e_hp_lbl = $Dashboard/Visualizer/HUD/Overlays/TargetingOverlay/VBox/EnemyStats/HealthLabel
@onready var e_sh_lbl = $Dashboard/Visualizer/HUD/Overlays/TargetingOverlay/VBox/EnemyStats/ShieldLabel
@onready var e_attack_pb = $Dashboard/Visualizer/HUD/Overlays/TargetingOverlay/VBox/EnemyStats/E_AttackBar

@onready var scanner_overlay = $Dashboard/Visualizer/HUD/Overlays/BottomRegion/StatusRow/ScannerOverlay
@onready var loot_lbl = $Dashboard/Visualizer/HUD/Overlays/BottomRegion/StatusRow/ScannerOverlay/VBox/Scroll/LootText

@onready var ammo_overlay = $Dashboard/Visualizer/HUD/Overlays/BottomRegion/StatusRow/AmmoOverlay
@onready var ammo_vbox = $Dashboard/Visualizer/HUD/Overlays/BottomRegion/StatusRow/AmmoOverlay/VBox/AmmoGroupVBox

# Controls
@onready var btn_retreat = $Dashboard/ViewportFooter/Margin/HBox/RetreatBtn
@onready var cons_opt = $Dashboard/ViewportFooter/Margin/HBox/ConsumableBay/OptionButton
@onready var cons_btn = $Dashboard/ViewportFooter/Margin/HBox/ConsumableBay/UseBtn
@onready var auto_btn = $Dashboard/ViewportFooter/Margin/HBox/ConsumableBay/AutoToggle

var manager: RefCounted

# Enemy List Item Prefab
# Enemy List Item Prefab
var enemy_card_scene = preload("res://scenes/ui/combat_enemy_card.tscn")
var floating_text_scene = preload("res://scenes/ui/floating_text.tscn")
var enemy_info_scene = preload("res://scenes/ui/enemy_info_modal.tscn")

func _ready():
	manager = GameState.combat_manager
	call_deferred("refresh_zones")
	GameState.game_loaded.connect(refresh_zones)
	
	# HUD Stress & Console Interaction
	
	# Initial Suppression
	
	UITheme.apply_premium_button_style(btn_retreat, "combat")
	UITheme.apply_premium_button_style(cons_btn, "engineering")
	
	UITheme.apply_progress_bar_style(e_attack_pb, "combat")
	
	# PHASE 47: DIEGETIC DE-BOXING
	UITheme.apply_holographic_projection($Dashboard/Visualizer/HUD/Overlays/SectorOverlay, "shipyard")
	UITheme.apply_holographic_projection($Dashboard/Visualizer/HUD/Overlays/TargetingOverlay, "combat")
	UITheme.apply_holographic_projection($Dashboard/Visualizer/HUD/Overlays/BottomRegion/LogOverlay, "ops")
	UITheme.apply_holographic_projection(ammo_overlay, "inventory")
	UITheme.apply_holographic_projection(scanner_overlay, "research")
	
	radar_display.draw.connect(_on_radar_draw)
	
	$Dashboard/Visualizer/HUD/Overlays/BottomRegion/LogOverlay/VBox/Header.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4)) # Terminal Green
	
	_refresh_consumable_options()

	# Explicit Signal Connections (Defensive)
	if not btn_retreat.is_connected("pressed", _on_retreat_btn_pressed): btn_retreat.pressed.connect(_on_retreat_btn_pressed)
	if not cons_btn.is_connected("pressed", _on_use_btn_pressed): cons_btn.pressed.connect(_on_use_btn_pressed)
	if not cons_opt.is_connected("item_selected", _on_option_button_item_selected): cons_opt.item_selected.connect(_on_option_button_item_selected)
	if not auto_btn.is_connected("toggled", _on_auto_btn_toggled): auto_btn.toggled.connect(_on_auto_btn_toggled)
	
	cons_opt.get_popup().about_to_popup.connect(_on_consumable_popup_about_to_show)
	


func refresh_zones():
	zone_list.clear()
	var zones = manager.get_available_zones()
	for z in zones:
		var idx = zone_list.add_item(z["data"]["name"])
		zone_list.set_item_metadata(idx, z["id"])

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
		
	if not zone_id in manager.zones: return
	
	var enemies = manager.zones[zone_id]["enemies"].duplicate()
	
	# Sort by HP (weakest to strongest)
	enemies.sort_custom(func(a, b):
		var hp_a = manager.enemy_db[a]["stats"].get("hp", 0)
		var hp_b = manager.enemy_db[b]["stats"].get("hp", 0)
		return hp_a < hp_b
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
	p_hp_lbl.text = "HULL: %s / %s  [Lv.%d +%.1f%% DMG]" % [UITheme.format_num(sm.current_hp), UITheme.format_num(sm.max_hp), manager.get_level(), manager.get_level() * 0.5]
	p_sh_lbl.text = "SHD: %s / %s" % [UITheme.format_num(manager.player_shield), UITheme.format_num(manager.player_max_shield)]
	
	# Update Heat Bar Modulate
	var heat_pct = manager.player_heat / manager.player_max_heat
	if manager.overheat_lock > 0:
		p_heat_bar.modulate = Color.RED
		p_heat_bar.modulate.a = 0.5 + (sin(Time.get_ticks_msec() * 0.02) * 0.5)
	elif heat_pct > 0.8:
		p_heat_bar.modulate = Color(1.0, 0.5, 0) # Warning Orange
	else:
		p_heat_bar.modulate = Color.WHITE
	
	# Enemy Stats
	if manager.in_combat and manager.current_enemy:
		var enemy = manager.current_enemy
		e_name_lbl.text = enemy["name"]
		e_stat_lbl.text = "ATK: %s | DEF: %s" % [UITheme.format_num(enemy.get("atk",0)), UITheme.format_num(enemy.get("def",0))]
		e_hp_lbl.text = "HULL: %s / %s" % [UITheme.format_num(manager.enemy_hp), UITheme.format_num(manager.enemy_max_hp)]
		e_sh_lbl.text = "SHD: %s / %s" % [UITheme.format_num(manager.enemy_shield), UITheme.format_num(manager.enemy_max_shield)]
		btn_retreat.disabled = false
	else:
		e_name_lbl.text = "No Target"
		e_stat_lbl.text = "ATK: - | DEF: -"
		e_hp_lbl.text = "HULL: - / -"
		e_sh_lbl.text = "SHD: - / -"
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
		else:
			e_attack_pb.visible = false
		# Expedition Yield
		_update_session_loot()
		scanner_overlay.visible = true
		
		# Ammo Tracking
		_update_ammo_display()
		ammo_overlay.visible = true
		
		# Periodically refresh consumable options? Or just when count changes.
		# For now, let's refresh if the first item (idle) is selected and we might have items now.
		if cons_opt.item_count <= 1:
			_refresh_consumable_options()
	else:
		for pb in player_weapon_bars: pb.visible = false
		e_attack_pb.visible = false
		scanner_overlay.visible = false
		ammo_overlay.visible = false
		scan_lbl.text = "SCANNING FOR ANOMALIES..."

	# Log
	# Inefficient to clear every frame, check size or dirty flag?
	# Using delta check or just simple dirty check
	if log_list.item_count != manager.combat_log.size():
		log_list.clear() # Primitive sync
		for msg in manager.combat_log:
			log_list.add_item(msg)
		log_list.ensure_current_is_visible() # scroll to bottom roughly
		if log_list.item_count > 0:
			log_list.select(log_list.item_count - 1)

	# Retreat Btn
	btn_retreat.disabled = not manager.in_combat

	# Consumables
	if manager.consumable_cooldown > 0:
		cons_btn.disabled = true
		cons_btn.text = "%.1fs" % manager.consumable_cooldown
	else:
		cons_btn.disabled = false
		cons_btn.text = "USE"

	# Auto Toggle Styling (The "Lamp" Effect)
	if manager.auto_consume_enabled:
		auto_btn.text = "AUTO [ON]"
		auto_btn.modulate = Color(0, 1, 1) # Cyan glow
	else:
		auto_btn.text = "AUTO [OFF]"
		auto_btn.modulate = Color(0.5, 0.5, 0.5) # Dim grey

	# Process Combat Events (Floating Text + Haptics)
	while manager.combat_events.size() > 0:
		var ev = manager.combat_events.pop_front()
		spawn_floating_text(ev)
		
		# TACTILE: Damage-induced System Glitch
		if ev.get("side") == "player" and ev.get("type", "") == "damage":
			_apply_hud_stress()
			if manager.haptics_enabled:
				Input.vibrate_handheld(100)
		
		# PARRY: Special feedback for successful reflection
		if ev.get("type") == "parry":
			UITheme.trigger_system_glitch(visualizer, 5.0)
			UITheme.trigger_ui_thud(self, 4.0)

func _apply_hud_stress():
	var hud = $Dashboard/Visualizer/HUD
	# PHASE 47: Visceral System Glitch
	UITheme.trigger_system_glitch(hud, 12.0)
	UITheme.trigger_ui_thud(self, 8.0)

func show_enemy_info(data):
	var dlg = enemy_info_scene.instantiate()
	self.add_child(dlg)
	dlg.setup(data)

func spawn_floating_text(ev):
	var txt = floating_text_scene.instantiate()
	# Parent to Visualizer to keep it contained in the middle area
	visualizer.add_child(txt)
	
	var local_pos = Vector2.ZERO
	if ev["side"] == "player":
		# Centralized Radar focus
		local_pos = visualizer.size / 2.0 + Vector2(-60, 20)
	else:
		if manager.in_combat:
			local_pos = visualizer.size / 2.0 + Vector2(60, -20)
		else:
			local_pos = Vector2(visualizer.size.x / 2, visualizer.size.y / 2)
	
	# Randomize slightly
	local_pos += Vector2(randf_range(-20, 20), randf_range(-20, 20))
	
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt.setup(ev["text"], ev["color"], local_pos)

func _on_radar_draw():
	var center = Vector2.ZERO # Local space of RadarDisplay (it's centered)
	var sm = GameState.shipyard_manager
	
	# --- PLAYER ARCS (Left) ---
	var p_hp_pct = float(sm.current_hp) / max(1.0, sm.max_hp)
	var p_sh_pct = float(manager.player_shield) / max(1.0, manager.player_max_shield)
	
	# HP Arc (Reddish)
	radar_display.draw_arc(center, 120, deg_to_rad(110), deg_to_rad(110 + (250-110)*p_hp_pct), 32, Color(1, 0.3, 0.3, 0.8), 5.0, true)
	# Shield Arc (Cyan)
	radar_display.draw_arc(center, 135, deg_to_rad(110), deg_to_rad(110 + (250-110)*p_sh_pct), 32, Color(0, 0.8, 1, 0.6), 4.0, true)

	# --- ENEMY ARCS (Right) ---
	if manager.in_combat and manager.current_enemy:
		var e_hp_pct = float(manager.enemy_hp) / max(1.0, manager.enemy_max_hp)
		var e_sh_pct = float(manager.enemy_shield) / max(1.0, manager.enemy_max_shield)
		
		# Enemy HP Arc
		_draw_arc_poly(center, 120, 130, -70, 70, Color(1, 0, 0, 0.2), Color(1, 0, 0, 0.8), e_hp_pct)
		# Enemy Shield Arc
		_draw_arc_poly(center, 135, 140, -70, 70, Color(0, 0.8, 1, 0.1), Color(0, 0.8, 1, 0.6), e_sh_pct)
		
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
	var fill_end_rad = start_rad + (end_rad - start_rad) * percent
	_draw_arc_section(center, inner_radius, outer_radius, start_rad, fill_end_rad, segments, fill_color)

func _draw_arc_section(center: Vector2, r_inner: float, r_outer: float, angle_start: float, angle_end: float, segments: int, color: Color):
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
			var item_name = ElementDB.get_display_name(item_id)
			tt += "[color=#32cd32]%s[/color] x %s\n" % [item_name, UITheme.format_num(qty)]
			
	tt += "[/center]"
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
	sb_ghost.border_color = Color(0,0,0)
	sb_ghost.corner_radius_top_left = 2
	sb_ghost.corner_radius_bottom_right = 2
	
	var ammo_list = [
		{"name": "Slug", "id": "SlugT1", "col": Color("#ffcc00"), "type": "kinetic"},
		{"name": "Sabot", "id": "SlugT2", "col": Color("#ffaa00"), "type": "kinetic"},
		{"name": "Titan", "id": "SlugT3", "col": Color("#ff8800"), "type": "kinetic"},
		{"name": "Focus", "id": "CellT1", "col": Color("#00ccff"), "type": "energy"},
		{"name": "Plasma", "id": "CellT2", "col": Color("#0099ff"), "type": "energy"},
		{"name": "Vapor", "id": "CellT3", "col": Color("#0066ff"), "type": "energy"}
	]
	
	var has_any = false
	for ammo in ammo_list:
		var qty = GameState.resources.get_element_amount(ammo["id"])
		var is_equipped = false
		for slot in sm.ammo_loadout:
			if sm.ammo_loadout[slot] == ammo["id"]:
				is_equipped = true
				break
		
		# We show if equipped OR has quantity (Stock)
		if is_equipped or qty > 0:
			has_any = true
			var group = VBoxContainer.new()
			group.add_theme_constant_override("separation", 1)
			group.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			ammo_vbox.add_child(group)
			
			var lbl = Label.new()
			lbl.add_theme_font_size_override("font_size", 8)
			lbl.text = ammo["name"].to_upper()
			lbl.modulate = Color(0.6,0.6,0.6)
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
		
		# Set style based on type
		var fill_color = Color("#00ccff") if w["type"] == "energy" else Color("#ffcc00")
		var sb_fill = StyleBoxFlat.new()
		sb_fill.bg_color = fill_color
		sb_fill.set_corner_radius_all(2)
		pb.add_theme_stylebox_override("fill", sb_fill)
		
		var sb_bg = StyleBoxFlat.new()
		sb_bg.bg_color = Color(0.1, 0.1, 0.1, 0.6)
		sb_bg.set_corner_radius_all(2)
		pb.add_theme_stylebox_override("background", sb_bg)
		
		pb.tooltip_text = w["name"]
		
		weapon_battery.add_child(pb)
		player_weapon_bars.append(pb)


func _refresh_consumable_options():
	var current_sel = cons_opt.get_item_metadata(cons_opt.selected) if cons_opt.selected > 0 else null
	cons_opt.clear()
	cons_opt.add_item("OFF / SELECT", 0)
	
	var items = ElementDB.get_elements_in_category("consumables")
	for id in items:
		var count = GameState.resources.get_element_amount(id)
		if count > 0:
			var idx = cons_opt.item_count
			var dname = ElementDB.get_display_name(id)
			cons_opt.add_item("%s (%d)" % [dname, count])
			cons_opt.set_item_metadata(idx, id)
			if id == current_sel:
				cons_opt.select(idx)

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
		var e_acc = manager.current_enemy.get("accuracy", 0)
		if e_acc > 10: # Only warn outside Tier 1
			var dodge_chance = float(sm.evasion) / (float(sm.evasion) + 150.0 * (1.0 + float(e_acc) / 100.0))
			if dodge_chance < 0.2 and sm.max_shield < 100:
				scan_lbl.text = "CAUTION: EVASION COMPROMISED - SHIELDS REQUIRED"
				scan_lbl.modulate = Color(1.0, 0.5, 0.0) # Warning Orange
		
		# TACTICAL: ScanLine Sweep
		var view_h = visualizer.size.y
		scan_line.visible = true
		scan_line.position.y += delta * 600.0 # High speed sweep
		if scan_line.position.y > view_h:
			scan_line.position.y = 0
	else:
		threat_lbl.text = "SCANNING SECTOR..."
		threat_lbl.text = "SECTOR THREAT: NOMINAL"
		threat_lbl.modulate = Color(1, 0.8, 0, 0.5) # Yellow cautious
		scan_line.visible = false

func _on_retreat_btn_pressed():
	manager.retreat()

func _on_use_btn_pressed():
	manager.use_consumable()
	_refresh_consumable_options()

func _on_option_button_item_selected(index):
	var id = cons_opt.get_item_metadata(index)
	manager.equip_consumable(id)

func _on_consumable_popup_about_to_show():
	var popup = cons_opt.get_popup()
	# Calculate position to show above the button
	# We use global_position of the button and subtract the popup height
	# Popup size might not be updated until shown, so we use min size as fallback
	var p_size = popup.get_contents_minimum_size()
	if p_size.y < 10: p_size.y = 150 # Fallback for expected height
	
	var global_pos = cons_opt.global_position
	popup.set_position(global_pos - Vector2(0, p_size.y + 4))

func _on_auto_btn_toggled(button_pressed):
	manager.toggle_auto_consume(button_pressed)
func _on_heat_changed(current: float, maximum: float):
	if p_heat_bar:
		p_heat_bar.max_value = maximum
		p_heat_bar.value = current
