extends Node
# ============================================================================
# LOCALIZATION SMOKE TEST (v140) — proves the runtime CSV loader still parses
# localization/strings.csv after it was rewritten programmatically, and that the
# keys added/renamed this version actually resolve in Turkish.
#
# Why this exists: strings.csv was regenerated wholesale by a Python csv.writer.
# Godot parses it with FileAccess.get_csv_line(), NOT Python's csv module — if the
# two disagree on quoting or on fields containing embedded newlines, translations
# fail silently and every string falls back to English. Row count + spot checks
# catch that immediately.
#   Godot --headless --path <root> res://scenes/tr_smoke.tscn
# ============================================================================

var fails := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond: fails += 1
	print("[TRSMOKE] %-46s %s %s" % [name, "OK" if cond else "*** FAIL", detail])


func _tr_differs(key: String) -> bool:
	# In TR a translated key must NOT come back as the English key itself.
	return tr(key) != key


func _ready() -> void:
	print("[TRSMOKE] ============ localization smoke ============")

	var loaded: int = int(Localization._row_count)
	print("[TRSMOKE]   rows parsed by Godot = %d" % loaded)
	_ok("CSV parsed (>2500 rows)", loaded > 2500, "%d" % loaded)

	TranslationServer.set_locale("tr")
	_ok("locale is tr", TranslationServer.get_locale().begins_with("tr"))

	# Pre-existing sanity anchors — if these break, the loader broke, not my rows.
	_ok("baseline: Research", tr("Research") == "Araştırma", tr("Research"))
	_ok("baseline: Exotic Matter", tr("Exotic Matter") == "Egzotik Madde", tr("Exotic Matter"))
	_ok("baseline: Locked", tr("Locked") == "Kilitli", tr("Locked"))

	# Warp-tree node card strings — these were never wrapped in tr() before v140.
	for k in ["ACQUIRED", "Shard", "Shards", "BUY · %d ◈", "UP · %d ◈",
			"SOON · %d ◈", "MAX · Lv %d", "Need %d ◈", "%s  ·  Lv %d"]:
		_ok("card string translated: %s" % k, _tr_differs(k), tr(k))

	# Strings whose English key CHANGED this version (research now resets).
	var keeps := "KEEPS  Exotic Matter · Warp Tree · Mastery · Storage          RESETS  Research · Ships · Liras · Buildings · Resources · Skill levels (30% XP)"
	_ok("warp ledger line translated", _tr_differs(keeps), tr(keeps).substr(0, 40))

	# A MULTI-LINE quoted field — the exact shape most likely to break a CSV rewrite.
	var reset_line := "[color=#f06b6b]RESET[/color]    Research · Ships & modules · Liras · Buildings · Resources · Skill levels  [color=#8b8f9c](keep %d%% XP)[/color]\n"
	_ok("multi-line row translated", _tr_differs(reset_line), tr(reset_line).substr(0, 40).replace("\n", "\\n"))
	# ...and it must still carry exactly one %d after translation, or % crashes.
	_ok("multi-line keeps its %d", tr(reset_line).count("%d") == 1, "%d found" % tr(reset_line).count("%d"))

	# Buffed node descriptions.
	_ok("ENG_S1 desc translated", _tr_differs("+10% gathering AND infrastructure yield per level."))
	_ok("ENG_S2 desc translated", _tr_differs("-3% processing duration per level (max -50%)."))
	_ok("REC_S1 desc translated", _tr_differs("+4% warp shards earned per level."))

	# Audit-found gaps.
	_ok("CLAIM: translated", _tr_differs("CLAIM: "), tr("CLAIM: "))
	_ok("Unequip translated", _tr_differs("Unequip"), tr("Unequip"))
	_ok("SHIELD REPAIR translated", _tr_differs("SHIELD REPAIR"), tr("SHIELD REPAIR"))

	# v141b/c yield-bonus tooltip (lives on the skill-level readout). "yield" has no
	# clean Turkish noun here — owner-mandated wording is "ekstra kaynak". v141c cut
	# the milestone ladder, so the card is now the flat + next step + cap.
	_ok("YIELD BONUS translated", tr("YIELD BONUS") == "EKSTRA KAYNAK", tr("YIELD BONUS"))
	_ok("yield flat row translated", _tr_differs("+%d flat yield  (+1 per 10 levels)"), tr("+%d flat yield  (+1 per 10 levels)"))
	_ok("yield next-step translated", _tr_differs("Next: Lv %d  →  +%d"), tr("Next: Lv %d  →  +%d"))
	_ok("yield cap row translated", _tr_differs("Lv 100  →  +10"), tr("Lv 100  →  +10"))
	_ok("yield primary-only note translated", _tr_differs("Primary drop only."), tr("Primary drop only."))
	# Two %d in order — a translator swapping them silently mislabels the ladder.
	_ok("next-step keeps both %d", tr("Next: Lv %d  →  +%d").count("%d") == 2)
	_ok("no 'getiri' in yield tooltip", not tr("+%d flat yield  (+1 per 10 levels)").to_lower().contains("getiri"))

	# English must still fall through to itself.
	TranslationServer.set_locale("en")
	_ok("en identity fallback", tr("ACQUIRED") == "ACQUIRED")

	print("[TRSMOKE] ============ %s ============" % ("ALL PASS" if fails == 0 else "%d FAIL(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
