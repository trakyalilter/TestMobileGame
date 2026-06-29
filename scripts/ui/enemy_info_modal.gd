extends Control

@onready var panel = $Panel
@onready var title_lbl = $Panel/VBoxContainer/TitleLabel
@onready var stats_lbl = $Panel/VBoxContainer/StatsLabel
@onready var loot_container = $Panel/VBoxContainer/ScrollContainer/LootContainer
@onready var btn_close = $Panel/VBoxContainer/CloseBtn

var enemy_data = {}

func _ready():
	visible = false
	btn_close.pressed.connect(close)
	UITheme.apply_modal_style(panel)
	UITheme.apply_premium_button_style(btn_close, "combat")

func setup(data):
	enemy_data = data

	# Title
	title_lbl.text = "Intel: " + data["name"]

	# Stats
	var hp = data["stats"]["hp"]
	var atk = data["stats"]["atk"]
	var df = data["stats"]["def"]
	var shield = data["stats"].get("max_shield", 0)

	stats_lbl.text = "HP: %d | Shield: %d\nATK: %d | DEF: %d" % [hp, shield, atk, df]

	# Clear Loot (must happen before adding new children)
	for c in loot_container.get_children():
		c.queue_free()

	# v87.0: Enemy Damage Type Display
	var e_dmg_type = data.get("dmg_type", "kinetic")
	var dmg_type_label = "KINETIC"
	var dmg_type_color = Color(0.6, 0.8, 1.0) # Steel Blue
	match e_dmg_type:
		"energy":
			dmg_type_label = "ENERGY"
			dmg_type_color = Color(1.0, 0.9, 0.3) # Gold
		"explosive":
			dmg_type_label = "EXPLOSIVE"
			dmg_type_color = Color(1.0, 0.5, 0.3) # Orange-Red
	add_header("Attacks With: %s" % dmg_type_label, dmg_type_color)

	# v86.0 / v111: Damage Type Resistances (incl. Cryo + Warp-Hardened)
	var rk = data.get("resist_k", 0.0)
	var re = data.get("resist_e", 0.0)
	var rx = data.get("resist_x", 0.0)
	var rc = data.get("resist_cryo", 0.0)

	if data.get("warp_hardened", false):
		# Z11+ Warp-Hardened: conventional damage is x0.02; only Cryo works.
		add_header("Damage Resistances", Color(0.8, 0.8, 0.9))
		add_item_label("❄ WARP-HARDENED — only Cryo damage works (conventional ×0.02)", Color(0.45, 0.85, 1.0))
		_add_resist_label("CRY", rc, Color(0.5, 0.9, 1.0))
		add_item_label("▶ BEST DAMAGE TYPE: CRYO", Color(0.45, 1.0, 0.55))
	elif rk != 0.0 or re != 0.0 or rx != 0.0 or rc != 0.0:
		add_header("Damage Resistances", Color(0.8, 0.8, 0.9))
		_add_resist_label("KIN", rk, Color(0.6, 0.8, 1.0))
		_add_resist_label("NRG", re, Color(1.0, 0.9, 0.3))
		_add_resist_label("EXP", rx, Color(1.0, 0.5, 0.3))
		if rc != 0.0:
			_add_resist_label("CRY", rc, Color(0.5, 0.9, 1.0))
		# Phase A: surface THE answer — the damage type with the lowest
		# resist (or strongest weakness) is the recommended attack type.
		var best_type = "KIN"
		var best_val = rk
		if re < best_val:
			best_type = "NRG"
			best_val = re
		if rx < best_val:
			best_type = "EXP"
			best_val = rx
		if rc != 0.0 and rc < best_val:
			best_type = "CRYO"
			best_val = rc
		add_item_label("▶ BEST DAMAGE TYPE: %s" % best_type, Color(0.45, 1.0, 0.55))

	# Guaranteed Loot Header
	add_header("Guaranteed Drops", Color.ORANGE)
	for item in data["loot"]:
		# format: [name, min, max]
		var d_name = ElementDB.get_display_name(item[0])
		var txt = "- %s: %d-%d" % [d_name, item[1], item[2]]
		add_item_label(txt, Color.WHITE)

	# v80.4: Guaranteed Boss Core
	var core_id = data.get("boss_core", "")
	if core_id != "":
		var core_name = ElementDB.get_display_name(core_id)
		add_item_label("★ BOSS DROP: %s" % core_name, Color.GOLD)


	# Rare Loot
	if "rare_loot" in data and not data["rare_loot"].is_empty():
		add_header("Rare Drops", Color.MAGENTA)
		for item in data["rare_loot"]:
			# format: [name, chance, min, max]
			var sm = GameState.shipyard_manager
			var d_name = item[0]
			var is_unique = false
			
			if sm and item[0] in sm.modules:
				var m_data = sm.modules[item[0]]
				d_name = m_data.get("name", item[0].replace("_", " ").capitalize())
				if m_data.get("rarity") == sm.Rarity.UNIQUE:
					is_unique = true
			else:
				var e_name = ElementDB.get_display_name(item[0])
				d_name = e_name if e_name != item[0] else item[0].replace("_", " ").capitalize()
				
			var chance = item[1] * 100.0
			var txt = "- %s: %.1f%% (%d-%d)" % [d_name, chance, item[2], item[3]]
			
			if is_unique:
				txt = "✦ " + txt
				add_item_label(txt, Color(1.0, 0.2, 0.8)) # Vivid Magenta
			else:
				add_item_label(txt, Color.LIGHT_BLUE)

	# Module Loot
	var module_pool = data.get("module_drop_pool", [])
	var base_drop_chance = data.get("module_drop_chance", 0.0)
	
	if base_drop_chance > 0 and module_pool.size() > 0:
		var sm = GameState.shipyard_manager
		var cm = GameState.combat_manager
		
		var effective_chance = base_drop_chance
		if cm and cm.has_method("get_effective_module_drop_chance"):
			effective_chance = cm.get_effective_module_drop_chance(data)
			
		add_header("Subspace Signal Detected", Color.GOLD)
		
		var chance_text = "Chance per kill: %.1f%%" % (effective_chance * 100.0)
		if abs(effective_chance - base_drop_chance) > 0.001:
			chance_text = "Chance: %.1f%% (Base: %.1f%%)" % [effective_chance * 100.0, base_drop_chance * 100.0]
			
		add_item_label(chance_text, Color(1.0, 0.9, 0.4))
		add_item_label("Contains variants for:", Color(0.7, 0.7, 0.8))
		
		for module_id in module_pool:
			var m_data = sm.modules.get(module_id, {}) if sm else {}
			var module_name = m_data.get("name", module_id.replace("_", " ").capitalize())
			var slot_type = m_data.get("slot_type", "module")
			
			# v72.1: Research Prerequisite Check
			var status = sm.can_equip_module(module_id)
			var lock_prefix = "🔒 " if not status["can_equip"] else ""
			var col = Color(0.275, 0.878, 0.627) if status["can_equip"] else Color(0.6, 0.6, 0.6)
			
			# Don't show UNIQUE items in subspace signal, they are already in Rare Drops
			if m_data.get("rarity") == sm.Rarity.UNIQUE:
				continue
				
			add_item_label("%s» %s [%s]" % [lock_prefix, module_name.to_upper(), slot_type.to_upper()], col)

	visible = true

func add_header(text, color):
	var l = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 14)
	loot_container.add_child(l)

func add_item_label(text, color):
	var l = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 12)
	loot_container.add_child(l)

func _add_resist_label(type_name: String, value: float, type_color: Color):
	var text = ""
	var color = Color.GRAY
	
	if value > 0.01:
		text = "  %s: +%d%% RESIST" % [type_name, int(value * 100)]
		color = Color(1.0, 0.4, 0.4) # Red = bad for player
	elif value < -0.01:
		text = "  %s: %d%% WEAK" % [type_name, int(value * 100)]
		color = Color(0.4, 1.0, 0.4) # Green = good for player
	else:
		text = "  %s: NEUTRAL" % type_name
		color = Color(0.5, 0.5, 0.5)
	
	add_item_label(text, color)

func close():
	visible = false
	queue_free()
