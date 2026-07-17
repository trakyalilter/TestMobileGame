extends Node
# Runtime CSV localization (autoload: Localization).
#
# Why runtime-load instead of Godot's CSV import pipeline: this project builds all UI
# in code and runs headless verification a lot; a runtime loader is deterministic,
# needs no editor reimport, and lets us append strings.csv freely.
#
# Model: ENGLISH-AS-KEY. The English source text IS the message id. tr("CONTINUE")
# returns the Turkish when locale == "tr" and a mapping exists, otherwise the English
# key itself — so any un-translated string automatically falls back to English.
#
# CSV: res://localization/strings.csv, columns: en,tr  (first column = key = English).
# Locale preference persists app-level (user://locale.cfg), independent of the save,
# so it applies at the main menu before any save loads.

const CSV_PATH := "res://localization/strings.csv"
const PREF_PATH := "user://locale.cfg"
const SUPPORTED := ["en", "tr"]
const DEFAULT_LOCALE := "en"

var _row_count := 0

func _ready() -> void:
	_load_csv()
	# Apply the persisted preference (default en), overriding Godot's OS-locale guess
	# so behaviour is deterministic regardless of the player's system language.
	TranslationServer.set_locale(_read_pref())

func _load_csv() -> void:
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_warning("Localization: CSV not found at %s" % CSV_PATH)
		return
	var header := f.get_csv_line()  # ["en", "tr", ...]
	# Build one Translation per non-English locale column. English is the key, so it
	# needs no table (missing key returns itself = English).
	var col_locale := {}   # column index -> Translation
	for i in range(1, header.size()):
		var code := header[i].strip_edges()
		if code == "" or code == "en":
			continue
		var t := Translation.new()
		t.locale = code
		col_locale[i] = t
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.is_empty() or row[0] == "":
			continue
		var key: String = row[0]
		for i in col_locale:
			if i < row.size() and row[i] != "":
				col_locale[i].add_message(key, row[i])
		_row_count += 1
	f.close()
	for i in col_locale:
		TranslationServer.add_translation(col_locale[i])

func set_locale(code: String) -> void:
	if not code in SUPPORTED:
		return
	TranslationServer.set_locale(code)
	var cfg := ConfigFile.new()
	cfg.set_value("loc", "locale", code)
	cfg.save(PREF_PATH)

func get_locale() -> String:
	return TranslationServer.get_locale()

func is_turkish() -> bool:
	return TranslationServer.get_locale().begins_with("tr")

func _read_pref() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PREF_PATH) == OK:
		var code = str(cfg.get_value("loc", "locale", DEFAULT_LOCALE))
		if code in SUPPORTED:
			return code
	return DEFAULT_LOCALE
