extends Node
# Quick i18n resolution check for the reported mixed-string bugs (v139c).
#   Godot --headless --path <root> res://scenes/loc_check.tscn
func _ready() -> void:
	GameState.set_process(false)
	Localization.set_locale("tr")
	var fails := 0
	for pair in [["Combat", "Savaş"], ["Engineering", "Mühendislik"], ["Research", "Araştırma"],
			["Mining", "Madencilik"], ["Task", "Görev"], ["Space Dust Mite", "Uzay Tozu Akarı"]]:
		var got: String = tr(pair[0])
		var ok: bool = got == pair[1]
		if not ok: fails += 1
		print("[LOC] %-18s -> %-18s %s" % [pair[0], got, "OK" if ok else "*** FAIL want '%s'" % pair[1]])
	# The end-to-end templates the screenshots showed:
	print("[LOC] combat header : '%s'" % (tr("Combat: %s") % tr("Space Dust Mite")))
	print("[LOC] paused toast   : '%s'" % (tr("%s paused — now %s") % [tr("Combat"), tr("Engineering")]))
	print("[LOC] %s" % ("ALL PASS" if fails == 0 else "*** %d FAIL" % fails))
	get_tree().quit(1 if fails > 0 else 0)
