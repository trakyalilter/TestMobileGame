extends Control

@onready var anim = $AnimationPlayer
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

	# Clear Loot
	for c in loot_container.get_children():
		c.queue_free()

	# Guaranteed Loot Header
	add_header("Guaranteed Drops", Color.ORANGE)
	for item in data["loot"]:
		# format: [name, min, max]
		var d_name = ElementDB.get_display_name(item[0])
		var txt = "- %s: %d-%d" % [d_name, item[1], item[2]]
		add_item_label(txt, Color.WHITE)

	# Rare Loot
	if "rare_loot" in data and not data["rare_loot"].is_empty():
		add_header("Rare Drops", Color.MAGENTA)
		for item in data["rare_loot"]:
			# format: [name, chance, min, max]
			var d_name = ElementDB.get_display_name(item[0])
			var chance = item[1] * 100.0
			var txt = "- %s: %.1f%% (%d-%d)" % [d_name, chance, item[2], item[3]]
			add_item_label(txt, Color.LIGHT_BLUE)

	# Module Loot
	var module_pool = data.get("module_drop_pool", [])
	var module_drop_chance = data.get("module_drop_chance", 0.0)
	if module_drop_chance > 0 and module_pool.size() > 0:
		var sm = GameState.shipyard_manager
		add_header("Subspace Signal Detected", Color.GOLD)
		add_item_label("Chance per kill: %.1f%%" % (module_drop_chance * 100.0), Color(1.0, 0.9, 0.4))
		add_item_label("Contains variants for:", Color(0.7, 0.7, 0.8))
		
		for module_id in module_pool:
			var m_data = sm.modules.get(module_id, {}) if sm else {}
			var module_name = m_data.get("name", module_id)
			var slot_type = m_data.get("slot_type", "module")
			
			# v72.1: Research Prerequisite Check
			var status = sm.can_equip_module(module_id)
			var lock_prefix = "🔒 " if not status["can_equip"] else ""
			var col = Color(0.0, 0.8, 1.0) if status["can_equip"] else Color(0.6, 0.6, 0.6)
			
			add_item_label("%s» %s [%s]" % [lock_prefix, module_name.to_upper(), slot_type.to_upper()], col)

	visible = true
	# Animation pop in?
	# anim.play("pop_in")

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

func close():
	visible = false
	queue_free()
