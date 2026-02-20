extends Control

@onready var bg = $ColorRect
@onready var boot_log = $CenterContainer/VBox/BootLog
@onready var yield_title = $CenterContainer/VBox/YieldTitle
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
	var lines = report_text.split("\n")
	for line in lines:
		if line.strip_edges().begins_with("+"):
			var parts = line.split(":")
			if parts.size() == 2:
				var item_name = parts[0].replace("+", "").strip_edges()
				var amount = parts[1].strip_edges()
				bbcode += "[color=#b0b0cc]> %s[/color]    [color=#00ffff]%s[/color]\n" % [item_name.to_upper(), amount]
	
	loot_display.text = bbcode

func _on_continue_pressed():
	var t = create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.5)
	t.tween_callback(func(): visible = false; modulate.a = 1.0)
