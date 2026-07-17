extends Node

# Phase-0 localization pipeline verification: CSV loaded, tr() returns Turkish under
# the tr locale, English fallback for untranslated keys, and Turkish-aware casing.
# Run: tools/run_sim.ps1 -Scene "res://scenes/loc_pipeline_check.tscn"

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	print("[LOC] CSV rows loaded: %d" % Localization._row_count)
	print("[LOC] boot locale: %s" % TranslationServer.get_locale())
	print("[LOC] EN  tr('CONTINUE') = '%s'" % tr("CONTINUE"))

	# Switch to Turkish directly (no pref write — keep the app pref clean for the game).
	TranslationServer.set_locale("tr")
	print("[LOC] switched locale -> %s" % TranslationServer.get_locale())
	for k in ["CONTINUE", "NEW GAME", "EXIT", "SYSTEM CONFIGURATION",
			"Enable Offline Combat", "RETURN TO MENU",
			"DEEP SPACE OPERATIONS SYSTEM", "Language"]:
		print("[LOC]   tr('%s') = '%s'" % [k, tr(k)])

	# Untranslated key must fall back to the English source (the key itself).
	print("[LOC] fallback tr('Totally Untranslated String') = '%s'" % tr("Totally Untranslated String"))

	# Turkish-aware casing (the i -> İ trap).
	print("[LOC] tr_upper('birim') = '%s'  (expect BİRİM)" % UITheme.tr_upper("birim"))
	print("[LOC] tr_upper('ışık')  = '%s'  (expect IŞIK)" % UITheme.tr_upper("ışık"))

	TranslationServer.set_locale("en")
	print("[LOC] done")
	get_tree().quit(0)
