extends Control

# PHASE 22: Ship Designer UI Overhaul
# Premium sci-fi aesthetic with expanded stats and module comparison

# Top info bar (full width, 1-line)
@onready var ship_name_lbl = $VBoxContainer/InfoPanel/MarginContainer/InfoHBox/ShipSpecs/ShipNameLabel
@onready var power_bar = $VBoxContainer/InfoPanel/MarginContainer/InfoHBox/ShipSpecs/SystemLoad/PowerBar
@onready var power_lbl = $VBoxContainer/InfoPanel/MarginContainer/InfoHBox/ShipSpecs/SystemLoad/PowerLabel
@onready var stats_grid = $VBoxContainer/InfoPanel/MarginContainer/InfoHBox/StatsGrid

# Storage
@onready var storage_grid = $VBoxContainer/MainLayout/RightPanel/Margin/VBox/Scroll/UnifiedStorageGrid

# Filter Buttons
@onready var f_all = $VBoxContainer/MainLayout/RightPanel/Margin/VBox/FilterStrip/AllBtn
@onready var f_wpn = $VBoxContainer/MainLayout/RightPanel/Margin/VBox/FilterStrip/WpnBtn
@onready var f_sys = $VBoxContainer/MainLayout/RightPanel/Margin/VBox/FilterStrip/SysBtn
@onready var f_ord = $VBoxContainer/MainLayout/RightPanel/Margin/VBox/FilterStrip/OrdBtn

var manager: RefCounted
var active_filter = "all"
var slot_widget_scene = preload("res://scenes/ui/designer_slot_widget.tscn")
var ammo_slot_scene = preload("res://scenes/ui/designer_ammo_slot_widget.tscn")

var draggable_icon_scene = preload("res://scenes/ui/module_card.tscn")

func _ready():
	manager = GameState.shipyard_manager
	visibility_changed.connect(_on_visibility_changed)
	GameState.game_loaded.connect(trigger_refresh)
	if GameState.warp_manager: GameState.warp_manager.warped.connect(_on_warp_refresh)
	manager.inventory_updated.connect(_on_inventory_updated)
	
	# Premium Styling
	UITheme.apply_card_style($VBoxContainer/InfoPanel, "shipyard")
	UITheme.apply_card_style($VBoxContainer/MainLayout/RightPanel, "engineering")
	
	$VBoxContainer/Label.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["shipyard"])
	
	f_all.pressed.connect(func(): _on_filter_changed("all"))
	f_wpn.pressed.connect(func(): _on_filter_changed("wpn"))
	f_sys.pressed.connect(func(): _on_filter_changed("sys"))
	f_ord.pressed.connect(func(): _on_filter_changed("ord"))
	
	
	trigger_refresh()

func _on_visibility_changed():
	if visible:
		trigger_refresh()

func _on_inventory_updated():
	if visible:
		rebuild_storage()
		update_header()

func _on_warp_refresh(_gains):
	trigger_refresh()

func trigger_refresh():
	update_header()
	rebuild_slots()
	rebuild_ammo_slots()
	rebuild_storage()

# ─────────────────────────────────────────────────
# EXPANDED STATS DISPLAY (PHASE 22)
# ─────────────────────────────────────────────────

func update_header():
	if manager.active_hull and manager.active_hull in manager.hulls:
		var h = manager.hulls[manager.active_hull]
		ship_name_lbl.text = h["name"].to_upper()
		
		# Calculate energy capacity
		var e_cap = 100
		if GameState.resources:
			e_cap = GameState.resources.max_energy
		var e_used = manager.energy_used
		
		# Update Power Bar
		power_bar.max_value = e_cap
		power_bar.value = e_used
		power_lbl.text = "%d / %d" % [e_used, e_cap]
		
		if e_used > e_cap:
			power_bar.modulate = Color(1.0, 0.3, 0.3)
			power_lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		elif e_used > e_cap * 0.8:
			power_bar.modulate = Color(1.0, 0.7, 0.2)
			power_lbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
		else:
			power_bar.modulate = UITheme.CATEGORY_COLORS.get("shipyard", Color.WHITE)
			power_lbl.add_theme_color_override("font_color", Color.WHITE)
			
		# Populate discrete stats grid
		var total_dps = _calculate_total_dps()
		var cm = GameState.combat_manager
		var total_eva = manager.evasion + cm.get_milestone_evasion_bonus()
		var total_crit = (manager.crit_chance + cm.get_milestone_crit_bonus()) * 100.0
		
		var stats = [
			{"label": "HP", "val": str(manager.max_hp), "color": Color(0.4, 0.9, 0.4)},
			{"label": "SHIELD", "val": UITheme.format_num(manager.max_shield), "color": Color(0, 0.8, 1)},
			{"label": "ATK", "val": UITheme.format_num(manager.attack), "color": Color(1, 0.6, 0.2)},
			{"label": "DEF", "val": UITheme.format_num(manager.defense), "color": Color(0.6, 0.6, 0.6)},
			{"label": "ACC", "val": str(manager.accuracy), "color": Color(0.8, 0.8, 1.0)},
			{"label": "CRIT", "val": "%.0f%%" % total_crit, "color": Color(1, 0.4, 0.4)},
			{"label": "EVA", "val": "%.0f" % total_eva, "color": Color(0.8, 1, 0.2)},
			{"label": "DPS", "val": UITheme.format_num(total_dps), "color": Color(1.0, 0.8, 0.2)}
		]
		
		for child in stats_grid.get_children():
			child.queue_free()
			
		for stat_data in stats:
			var stat_box = HBoxContainer.new()
			stat_box.add_theme_constant_override("separation", 5)
			
			var lbl_k = Label.new()
			lbl_k.text = stat_data["label"]
			lbl_k.add_theme_font_size_override("font_size", 10)
			lbl_k.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			lbl_k.custom_minimum_size.x = 45 # Alignment
			
			var lbl_v = Label.new()
			lbl_v.text = stat_data["val"]
			lbl_v.add_theme_font_size_override("font_size", 11)
			lbl_v.add_theme_color_override("font_color", stat_data["color"])
			
			stat_box.add_child(lbl_k)
			stat_box.add_child(lbl_v)
			stats_grid.add_child(stat_box)
			
	else:
		ship_name_lbl.text = "NO HULL SELECTED"
		power_lbl.text = "0 / 0"
		for child in stats_grid.get_children():
			child.queue_free()

func _calculate_total_dps() -> float:
	var total = 0.0
	
	var has_plasma_overcharger = false
	for s_idx in manager.loadout:
		if manager.loadout[s_idx] == "plasma_overcharger":
			has_plasma_overcharger = true
			break
			
	for s_idx in manager.loadout:
		var mid = manager.loadout[s_idx]
		if mid and mid in manager.modules:
			var m_data = manager.modules[mid]
			if m_data.get("slot_type") == "weapon":
				var stats = m_data.get("stats", {})
				var e_dmg = stats.get("atk_energy", 0)
				if has_plasma_overcharger:
					e_dmg *= 2.0
					
				var dmg = stats.get("atk_kinetic", 0) + e_dmg + stats.get("atk_explosive", 0)
				var interval = stats.get("atk_interval", 2.5)
				if interval > 0:
					total += float(dmg) / interval
	return total

# ─────────────────────────────────────────────────
# SLOT BLADES
# ─────────────────────────────────────────────────

func rebuild_slots():
	var s_cont = $VBoxContainer/MainLayout/SchematicArea/LayoutSplit/SlotListPanel/SlotScroll/SchematicContainer
	if s_cont:
		for child in s_cont.get_children():
			child.queue_free()
			
	if not manager.active_hull in manager.hulls: return
	
	var h_data = manager.hulls[manager.active_hull]
	var slots = h_data["slots"]
	
	# Categorize Slots
	var blades = {
		"Weapons": [],
		"Defense": [],
		"Armor": [],
		"Systems": [],
		"Utility": [],
		"Ammunition": []
	}
	
	for i in range(slots.size()):
		var s_type = slots[i]
		if s_type == "weapon":
			blades["Weapons"].append({"idx": i, "type": s_type})
			# Add ammo slot for every weapon slot
			blades["Ammunition"].append({"idx": i, "type": "ammo"})
		elif s_type == "shield":
			blades["Defense"].append({"idx": i, "type": s_type})
		elif s_type == "armor":
			blades["Armor"].append({"idx": i, "type": s_type})
		elif s_type == "engine" or s_type == "reactor" or s_type == "battery":
			blades["Systems"].append({"idx": i, "type": s_type})
		else:
			blades["Utility"].append({"idx": i, "type": s_type})
			
	# Create Blades in Order with premium colors
	_create_blade("🔥 Weapons", blades["Weapons"], s_cont, Color(1.0, 0.4, 0.4, 0.8))
	_create_blade("💥 Ammunition", blades["Ammunition"], s_cont, Color(1.0, 0.6, 0.3, 0.8), true)
	_create_blade("🛡 Defense", blades["Defense"], s_cont, Color(0.4, 0.6, 1.0, 0.8))
	_create_blade("🧱 Armor", blades["Armor"], s_cont, Color(0.6, 0.6, 0.6, 0.8))
	_create_blade("⚡ Systems", blades["Systems"], s_cont, Color(0.8, 1.0, 0.2, 0.8))
	_create_blade("🔧 Utility", blades["Utility"], s_cont, Color(0.6, 0.6, 0.6, 0.8))
	_create_consumable_blade(s_cont)

func _create_blade(title: String, slot_list: Array, parent: Node, color: Color = Color.WHITE, is_ammo: bool = false):
	if slot_list.is_empty(): return
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	parent.add_child(vbox)
	
	var label = Label.new()
	label.text = "[ %s ]" % title.to_upper()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	vbox.add_child(label)
	
	# Wrap slots inside an HFlowContainer rather than horizontal scrolling
	var flow = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	vbox.add_child(flow)
	
	for s_data in slot_list:
		var w
		if is_ammo:
			w = ammo_slot_scene.instantiate()
			flow.add_child(w)
			w.setup(s_data["idx"], self, manager)
		else:
			w = slot_widget_scene.instantiate()
			flow.add_child(w)
			w.setup(s_data["idx"], s_data["type"], self, manager)
			
	# Add separator
	var sep = HSeparator.new()
	sep.modulate = Color(color.r, color.g, color.b, 0.3)
	vbox.add_child(sep)

func _create_consumable_blade(parent: Node):
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	parent.add_child(vbox)
	
	var label = Label.new()
	label.text = "[ 💊 CONSUMABLES ]"
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.8, 0.8))
	vbox.add_child(label)
	
	# Wrap slots inside an HFlowContainer
	var flow = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	vbox.add_child(flow)
	
	# Hull Slot
	var w1 = slot_widget_scene.instantiate()
	flow.add_child(w1)
	w1.setup(-1, "consumable_hull", self, manager)
	
	# Shield Slot
	var w2 = slot_widget_scene.instantiate()
	flow.add_child(w2)
	w2.setup(-1, "consumable_shield", self, manager)
	
	# Separator
	var sep = HSeparator.new()
	sep.modulate = Color(1.0, 0.5, 0.8, 0.3)
	vbox.add_child(sep)


func rebuild_ammo_slots():
	pass # Integrated into blade system

# ─────────────────────────────────────────────────
# STORAGE GRID
# ─────────────────────────────────────────────────

func rebuild_storage():
	for child in storage_grid.get_children(): child.queue_free()
	
	# Modules Categorization & Sorting
	var inv = manager.module_inventory
	var sorted_mids = inv.keys()
	sorted_mids.sort_custom(func(a, b):
		var data_a = manager.modules.get(a, {})
		var data_b = manager.modules.get(b, {})
		return _get_module_power_score(a, data_a) < _get_module_power_score(b, data_b)
	)
	
	for mid in sorted_mids:
		var count = inv[mid]
		if count > 0 and mid in manager.modules:
			var data = manager.modules[mid]
			var type = data.get("slot_type", "weapon")
			
			var show = false
			if active_filter == "all": show = true
			elif active_filter == "wpn" and type == "weapon": show = true
			elif active_filter == "sys" and type in ["shield", "engine", "battery"]: show = true
			elif active_filter == "explosive" and type == "weapon" and data.get("stats", {}).get("atk_explosive", 0) > 0: show = true
			elif active_filter == "armor" and type == "armor": show = true
			
			if show:
				var item = draggable_icon_scene.instantiate()
				storage_grid.add_child(item)
				item.setup(mid, data, count)
			
	# Ammo
	if active_filter in ["all", "ord"]:
		var ammo_list = [
			{"id": "SlugT1"},
			{"id": "SlugT1S"},
			{"id": "SlugT2"},
			{"id": "SlugT3"},
			{"id": "SlugT4"},
			{"id": "CellT1"},
			{"id": "CellT2"},
			{"id": "CellT3"},
			{"id": "CellT4"},
			{"id": "Photon_Torpedo"}
		]
		for ammo in ammo_list:
			var qty = GameState.resources.get_element_amount(ammo["id"])
			if qty > 0:
				var card = draggable_icon_scene.instantiate()
				storage_grid.add_child(card)
				var dname = ElementDB.get_display_name(ammo["id"])
				var fake_data = {"name": dname, "slot_type": "ammo", "stats": {}}
				card.setup(ammo["id"], fake_data, qty)

	# Consumables
	if active_filter in ["all", "ord"]:
		var consumables = ElementDB.get_elements_in_category("consumables")
		for cid in consumables:
			var qty = GameState.resources.get_element_amount(cid)
			if qty > 0:
				var card = draggable_icon_scene.instantiate()
				storage_grid.add_child(card)
				var c_data = ElementDB.get_consumable_data(cid)
				var dname = c_data.get("name", cid)
				var c_type = c_data.get("type", "hull") # hull or shield
				var fake_data = {"name": dname, "slot_type": "consumable", "consumable_type": c_type, "stats": {"heal_pct": c_data.get("heal_pct", 0)}}
				card.setup(cid, fake_data, qty)

func rebuild_ammo_storage():
	pass # Unified into rebuild_storage

func _on_filter_changed(filter_id: String):
	active_filter = filter_id
	# Sync buttons
	f_all.button_pressed = (filter_id == "all")
	f_wpn.button_pressed = (filter_id == "wpn")
	f_sys.button_pressed = (filter_id == "sys")
	f_ord.button_pressed = (filter_id == "ord")
	
	rebuild_storage()

func get_module_widget(module_id: String) -> Control:
	for child in storage_grid.get_children():
		if child.get("mid") == module_id:
			return child
	return null

func _get_module_power_score(id: String, data: Dictionary) -> int:
	var score = 0
	var stats = data.get("stats", {})
	
	var cost = data.get("cost", {})
	var credits = cost.get("credits", 0)
	if credits > 0:
		score += int(log(credits) * 10)
	else:
		if "BatteryT1" in cost: score += 10
		elif "BatteryT2" in cost: score += 20
		elif "BatteryT3" in cost: score += 30
		else: score += 5
		
	if stats.get("atk_kinetic", 0) > 0: score += stats["atk_kinetic"]
	if stats.get("atk_energy", 0) > 0: score += stats["atk_energy"]
	if stats.get("atk_explosive", 0) > 0: score += stats["atk_explosive"]
	if stats.get("max_shield", 0) > 0: score += stats["max_shield"] / 5
	if stats.get("hp", 0) > 0: score += stats["hp"] / 10
	if stats.get("energy_capacity", 0) > 0: score += stats["energy_capacity"]
	if stats.get("eva", 0) > 0: score += stats["eva"] * 2
	if stats.get("atk_speed_bonus", 0) > 0: score += int(stats["atk_speed_bonus"] * 100)
	
	if id == "mining_laser_mk1": score = 10
	if id == "mining_laser_mk2": score = 50
	if id == "railgun_mk1": score = 20
	
	return score

# Circuit lines removed in redesign
