extends Control

@onready var bg = $ColorRect
@onready var boot_log = $CenterContainer/VBox/BootLog
@onready var yield_title = $CenterContainer/VBox/YieldTitle
@onready var active_task_label = $CenterContainer/VBox/ActiveTaskLabel
@onready var loot_display: RichTextLabel = $CenterContainer/VBox/LootDisplay
@onready var footer = $CenterContainer/VBox/Footer
@onready var continue_btn = $CenterContainer/VBox/ContinueBtn

var report_text: String = ""

func _ready():
	visible = false
	bg.color = Color(0, 0, 0, 1)
	UITheme.apply_premium_button_style(continue_btn, "ops")
	continue_btn.pressed.connect(_on_continue_pressed)

func check_and_show():
	if GameState.offline_report and GameState.offline_report != "":
		report_text = GameState.offline_report
		GameState.offline_report = ""
		start_boot_sequence()

func start_boot_sequence():
	visible = true
	boot_log.text = ""
	yield_title.modulate.a = 0
	footer.modulate.a = 0
	continue_btn.hide()
	loot_display.text = ""
	loot_display.modulate.a = 0
	# Resume-hint setup based on active task
	var resume_info = _describe_active_task()
	if active_task_label:
		active_task_label.text = resume_info["label"]
		active_task_label.modulate.a = 0
	continue_btn.text = resume_info["button"]
	
	var tween = create_tween()
	
	# Phase 1: Reactor Kickstart
	tween.tween_callback(_log.bind("> INITIALIZING CORE REACTOR..."))
	tween.tween_interval(0.6)
	tween.tween_callback(func(): UITheme.trigger_ui_thud(self, 15.0))
	tween.tween_callback(_log.bind("> AUXILIARY POWER: [ OK ]"))
	tween.tween_interval(0.4)
	
	# Phase 2: Logistics Sync
	tween.tween_callback(_log.bind("> SYNCHRONIZING SECTOR LOGISTICS..."))
	tween.tween_interval(0.8)
	tween.tween_callback(_log.bind("> DATA PACKET INTEGRITY: 100%"))
	tween.tween_interval(0.4)
	
	# Phase 3: The Reveal
	tween.tween_callback(func():
		var t = create_tween()
		t.tween_property(yield_title, "modulate:a", 1.0, 0.5)
		t.parallel().tween_property(footer, "modulate:a", 1.0, 0.5)
		if active_task_label and active_task_label.text != "":
			t.parallel().tween_property(active_task_label, "modulate:a", 1.0, 0.5)
	)
	
	# Parse Report and show items
	tween.tween_callback(_parse_and_display_report)
	tween.tween_callback(func():
		create_tween().tween_property(loot_display, "modulate:a", 1.0, 0.4)
	)
	
	# Phase 4: Ready
	tween.tween_interval(1.0)
	tween.tween_callback(func():
		continue_btn.show()
		continue_btn.modulate.a = 0
		create_tween().tween_property(continue_btn, "modulate:a", 1.0, 0.5)
	)

func _log(msg: String):
	boot_log.text += msg + "\n"
	UITheme.trigger_ui_thud(boot_log, 1.0)

func _parse_and_display_report():
	var bbcode := ""
	for line in report_text.split("\n"):
		var s := line.strip_edges()
		if s == "":
			bbcode += "\n"
			continue
		if s.begins_with("+") or s.begins_with("-"):
			# Resource gain (+) or drain (-): "<sign> Name: amount"
			var neg := s.begins_with("-")
			var body := s.substr(1).strip_edges()
			var colon := body.find(":")
			if colon >= 0:
				var item_name := body.substr(0, colon).strip_edges()
				var amount := body.substr(colon + 1).strip_edges()
				if "_" in item_name:
					item_name = item_name.replace("_", " ")
				var val_color := "#ff8a7a" if neg else "#00ffff"
				bbcode += "[color=#b0b0cc]%s %s[/color]    [color=%s]%s[/color]\n" % ["–" if neg else ">", item_name.to_upper(), val_color, amount]
			else:
				bbcode += "[color=#b0b0cc]%s[/color]\n" % s
		else:
			# Headline / section header / cap notice — previously dropped entirely.
			bbcode += "[color=#ffd24a]%s[/color]\n" % s
	loot_display.text = bbcode

func _on_continue_pressed():
	var t = create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.5)
	t.tween_callback(func(): visible = false; modulate.a = 1.0)

# Build a short description of what the player was doing — shown above the loot block.
# Also picks a contextual Continue-button label so returning players know exactly where they'll land.
func _describe_active_task() -> Dictionary:
	var default = {"label": "", "button": "BRIDGE CONTROL"}

	if not GameState:
		return default

	# Combat takes priority — it's the most immediate ongoing engagement
	if GameState.combat_manager and GameState.combat_manager.in_combat:
		var zone_id = GameState.combat_manager.current_zone_id
		var zone_name = zone_id
		if zone_id in GameState.combat_manager.zones:
			zone_name = GameState.combat_manager.zones[zone_id].get("name", zone_id)
		return {
			"label": "▶  RESUMING COMBAT  —  %s" % zone_name.to_upper(),
			"button": "RETURN TO BATTLE"
		}

	if GameState.gathering_manager and GameState.gathering_manager.is_active:
		var aid = GameState.gathering_manager.current_action_id
		var a = GameState.gathering_manager.actions.get(aid, {})
		var name = a.get("name", aid)
		return {
			"label": "⛏  GATHERING IN PROGRESS  —  %s" % name.to_upper(),
			"button": "CONTINUE GATHERING"
		}

	if GameState.processing_manager and GameState.processing_manager.is_active:
		var rid = GameState.processing_manager.current_recipe_id
		var r = GameState.processing_manager.recipes.get(rid, {})
		var name = r.get("name", rid)
		return {
			"label": "⚙  PROCESSING  —  %s" % name.to_upper(),
			"button": "CONTINUE PROCESSING"
		}

	if GameState.research_manager and GameState.research_manager.is_active:
		var tid = GameState.research_manager.current_action
		var t = GameState.research_manager.tech_tree.get(tid, {}) if tid != "" else {}
		var name = t.get("name", tid)
		if name != "":
			return {
				"label": "🔬  RESEARCHING  —  %s" % name.to_upper(),
				"button": "CONTINUE RESEARCH"
			}

	# No active task — show a softer resume hint
	return {
		"label": "◇  STANDING BY  —  COMMAND DECK IDLE",
		"button": "BRIDGE CONTROL"
	}
