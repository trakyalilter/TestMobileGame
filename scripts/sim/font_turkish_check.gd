extends Node

# Phase-0 de-risk for Turkish localization: does the project's default theme font
# actually contain the Turkish glyphs (ç ğ ı İ ö ş ü + uppercase)? And confirm the
# to_upper() casing trap. Run: tools/run_sim.ps1 -Scene "res://scenes/font_turkish_check.tscn"

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var lbl := Label.new()
	add_child(lbl)
	var font: Font = lbl.get_theme_font("font")
	print("[FC] default theme font: %s" % [font.get_font_name() if font else "NULL"])

	var chars := "çğıİöşüÇĞÖŞÜ"
	var missing := 0
	for i in chars.length():
		var cp: int = chars.unicode_at(i)
		var has: bool = font.has_char(cp) if font else false
		if not has:
			missing += 1
		print("[FC]   '%s' U+%04X : %s" % [chars[i], cp, "OK" if has else "MISSING"])
	print("[FC] MISSING GLYPHS: %d of %d" % [missing, chars.length()])

	# The casing trap: Godot to_upper() is NOT Turkish-locale-aware.
	print("[FC] casing: 'iğ'.to_upper() = '%s'  (Turkish-correct = 'İĞ')" % "iğ".to_upper())
	print("[FC] casing: 'ışık'.to_upper() = '%s'  (Turkish-correct = 'IŞIK')" % "ışık".to_upper())
	print("[FC] done")
	get_tree().quit(0)
