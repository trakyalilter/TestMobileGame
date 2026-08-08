extends Node
# ORDERS RENAME + BRIEFING TRANSLATION GUARD.
#
# localization is English-as-key with English fallback (localization.gd), so a
# missing row is silent: tr() hands back the English and the Turkish build just
# quietly ships English. Two things hid behind that:
#   - the whole 8-section HOW TO PLAY briefing had ZERO rows, and its "Income"
#     section still called the renamed Orders system "Quests", pointing new
#     players at a sidebar tab that no longer exists;
#   - the Orders first-visit coach body was rewritten during the rename and
#     never re-added, while the pre-rename body lingered as an orphan row.
#
#   Godot --headless --path <root> res://scenes/orders_i18n_check.tscn

const MAIN_MENU := preload("res://scripts/ui/main_menu.gd")
const COACH := preload("res://scripts/core/coach_marks.gd")

var fails: int = 0

func _ready() -> void:
	await get_tree().process_frame
	TranslationServer.set_locale("tr")
	await get_tree().process_frame
	print("[ORD] locale = %s" % TranslationServer.get_locale())

	# ---- 1. no player-facing surface may still say "Quest" ----------------
	for sec in MAIN_MENU.HOWTO_SECTIONS:
		for part in [String(sec[0]), String(sec[1])]:
			if "Quest" in part or "quest" in part:
				_fail("HOW TO PLAY still says Quest: \"%s\"" % part.substr(0, 70))
	for page in COACH.STEPS:
		for m in COACH.STEPS[page]:
			for k in ["title", "body"]:
				var t: String = String(m.get(k, ""))
				if "Quest" in t or (" quest" in t):
					_fail("coach mark [%s].%s still says Quest: \"%s\"" % [page, k, t.substr(0, 60)])

	# ---- 2. every briefing string must actually translate -----------------
	var untranslated: Array = []
	for sec in MAIN_MENU.HOWTO_SECTIONS:
		for part in [String(sec[0]), String(sec[1])]:
			if tr(part) == part:
				untranslated.append(part.substr(0, 45))
	print("[ORD] HOW TO PLAY: %d/%d strings translated" % [
		MAIN_MENU.HOWTO_SECTIONS.size() * 2 - untranslated.size(),
		MAIN_MENU.HOWTO_SECTIONS.size() * 2])
	for u in untranslated:
		_fail("HOW TO PLAY untranslated: \"%s...\"" % u)

	# ---- 3. the Orders coach tour must be fully translated ----------------
	for m in COACH.STEPS.get("quest", []):
		for k in ["title", "body"]:
			var t: String = String(m.get(k, ""))
			if t != "" and tr(t) == t:
				_fail("Orders coach %s untranslated: \"%s...\"" % [k, t.substr(0, 45)])

	# ---- 4. no stale Credits abbreviation on Orders surfaces --------------
	for key in ["REROLL BOARD (%s Liras)", "REROLL BOARD (2.5K Liras)"]:
		var t: String = tr(key)
		if t == key:
			_fail("reroll caption untranslated: %s" % key)
		elif "CR" in t.to_upper().replace("KR", ""):
			_fail("reroll caption still prices in CR: \"%s\"" % t)
	print("[ORD] reroll caption tr -> \"%s\"" % tr("REROLL BOARD (%s Liras)"))

	print("[ORD] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _fail(msg: String) -> void:
	print("[ORD] FAIL: %s" % msg)
	fails += 1
