extends PanelContainer

@onready var report_label = $MarginContainer/VBoxContainer/ReportLabel
@onready var title_label = $MarginContainer/VBoxContainer/TitleLabel
@onready var sync_bar = $MarginContainer/VBoxContainer/SyncBar
@onready var sync_log = $MarginContainer/VBoxContainer/SyncLog
@onready var ack_btn = $MarginContainer/VBoxContainer/AckBtn

func _ready():
	visible = false
	UITheme.apply_modal_style(self)
	UITheme.apply_progress_bar_style(sync_bar, "engineering")
	UITheme.apply_premium_button_style(ack_btn, "inventory")

func check_and_show():
	if GameState.offline_report and GameState.offline_report != "":
		start_resync_sequence(GameState.offline_report)
		GameState.offline_report = ""

func start_resync_sequence(text: String):
	visible = true
	# Reset states
	sync_bar.show()
	sync_log.show()
	sync_bar.value = 0
	report_label.hide()
	ack_btn.hide()
	title_label.text = "SYNCING WITH SECTOR NETWORK..."
	
	UITheme.trigger_ui_thud(self, 8.0) # Establishing link thud
	
	var tween = create_tween()
	
	# Phase 1: Re-establishing Link
	tween.tween_property(sync_bar, "value", 40.0, 0.6).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_callback(func(): sync_log.text = "HANDSHAKE: [OK] | DECRYPTING PACKETS...")
	
	# Phase 2: Packet Processing
	tween.tween_property(sync_bar, "value", 90.0, 1.2).set_trans(Tween.TRANS_LINEAR).set_delay(0.2)
	tween.parallel().tween_callback(func(): sync_log.text = "RESOLVING TEMPORAL DRIFT...")
	
	# Phase 3: Manifest Reveal
	tween.tween_property(sync_bar, "value", 100.0, 0.2)
	tween.tween_callback(func(): 
		sync_bar.hide()
		sync_log.hide()
		title_label.text = "SYSTEM REPORT // OFFLINE LOG"
		_reveal_report(text)
	)

func _reveal_report(text: String):
	var formatted_text = ""
	var lines = text.split("\n")
	for line in lines:
		if line.strip_edges() == "": continue
		var sanitized_line = line
		# Assuming format + item_id: amount
		if line.strip_edges().begins_with("+"):
			var parts = line.split(":")
			if parts.size() == 2:
				var raw_item_name = parts[0].replace("+", "").strip_edges()
				var amount = parts[1].strip_edges()
				var item_name = raw_item_name
				if "_" in item_name:
					item_name = item_name.replace("_", " ").capitalize()
				sanitized_line = "+ " + item_name + ": " + amount
		formatted_text += sanitized_line + "\n"
		
	report_label.text = formatted_text
	report_label.show()
	ack_btn.show()
	
	# Flicker in effect
	report_label.modulate.a = 0
	var f_tween = create_tween()
	f_tween.tween_property(report_label, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_BOUNCE)
	
	UITheme.trigger_ui_thud(self, 3.0) # Data landing thud

func _on_ack_btn_pressed():
	visible = false
