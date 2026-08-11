extends Node
# EVERY MISSION STRING A TURKISH PLAYER SEES MUST BE TRANSLATED (v175).
#
# Localization is ENGLISH-AS-KEY with an English fallback: tr() returns the Turkish when
# a row exists and the English key itself when it does not. That fallback is the right
# runtime behaviour and a terrible authoring signal — a missing row is not an error, not
# a warning, not a visible placeholder. It is just English text sitting in the middle of
# a Turkish UI, and nothing anywhere reports it.
#
# mission_widget renders BOTH the mission name and its description through tr(), so a
# missing row shows up as a whole English paragraph on the objective card.
#
# Measured under locale "tr" against the real TranslationServer, after Localization has
# loaded the CSV. A string is counted missing when translate() hands back the key
# unchanged. Identical-by-design strings (proper nouns, numbers, single symbols) would
# be false positives, so they are listed explicitly rather than silently skipped.
#
#   Godot --headless --path <root> res://scenes/mission_i18n_check.tscn
#   ... --dump    print the untranslated strings as CSV rows, ready to translate

# Strings that are legitimately identical in both languages. Keep this SHORT and
# justified — it is the one place this guard can be silenced.
const IDENTICAL_OK := []

var fails: int = 0

func _ready() -> void:
	await get_tree().process_frame
	GameState.set_process(false)
	var mm = GameState.mission_manager

	var dump := false
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if str(a) == "--dump":
			dump = true

	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale("tr")
	# Prove the instrument before trusting it: a string known to be translated must come
	# back different under "tr". If the CSV did not load, EVERYTHING would look missing
	# and this guard would report a catastrophe that is really a loader problem.
	var canary := "CONTINUE"
	var canary_tr := TranslationServer.translate(canary)
	if canary_tr == canary:
		print("[MI18N] ABORT: canary '%s' did not translate — the CSV did not load, so a" % canary)
		print("[MI18N]        'missing' verdict would be meaningless. Not reporting counts.")
		TranslationServer.set_locale(prev)
		get_tree().quit(1)
		return
	print("[MI18N] locale=tr, canary '%s' -> '%s' (CSV is live)" % [canary, canary_tr])

	# Walk the CHAIN, not the whole dictionary: these are the beats a player actually
	# reads, in the order they read them, so the report says where the gap starts.
	var seen: Dictionary = {}
	var order: Array = []
	var cur := "m001"
	var steps := 0
	while cur != "" and steps < 200:
		var m: Dictionary = mm.missions.get(cur, {})
		if m.is_empty():
			break
		if not seen.has(cur):
			seen[cur] = true
			order.append(cur)
		cur = str(m.get("next_mission", ""))
		steps += 1
	# Anything not on the spine still ships in the game, so check it too — just after.
	for mid in mm.missions:
		if not seen.has(mid):
			seen[mid] = true
			order.append(str(mid))

	var missing_rows: Array = []      # [english, kind, mission id, chain position]
	var checked := 0
	var beats_with_english: Dictionary = {}
	for i in range(order.size()):
		var mid2 := str(order[i])
		var m2: Dictionary = mm.missions.get(mid2, {})
		for kind in ["name", "description"]:
			var src := str(m2.get(kind, "")).strip_edges()
			if src == "" or src in IDENTICAL_OK:
				continue
			checked += 1
			if TranslationServer.translate(src) == src:
				missing_rows.append([src, kind, mid2, i])
				beats_with_english[mid2] = true
	TranslationServer.set_locale(prev)

	print("[MI18N] %d mission strings checked across %d beats" % [checked, order.size()])
	if missing_rows.size() > 0:
		var names := 0
		var descs := 0
		for r in missing_rows:
			if str(r[1]) == "name":
				names += 1
			else:
				descs += 1
		print("[MI18N] untranslated: %d (%d name(s), %d description(s)) across %d beat(s)" % [
			missing_rows.size(), names, descs, beats_with_english.size()])
		var first: Array = missing_rows[0]
		print("[MI18N] first gap: %s (%s) at chain position %d" % [first[2], first[1], first[3]])
		for r2 in missing_rows:
			print("[MI18N]   MISSING %-8s %-11s %s" % [r2[2], r2[1], str(r2[0]).substr(0, 90)])
		_fail("%d mission string(s) render as English inside the Turkish build" % missing_rows.size())

	if dump:
		print("[MI18N] --- CSV rows to translate (en column filled, tr column empty) ---")
		for r3 in missing_rows:
			print("[MI18NCSV] \"%s\",\"\"" % str(r3[0]).replace("\"", "\"\""))

	print("[MI18N] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _fail(msg: String) -> void:
	print("[MI18N] FAIL: %s" % msg)
	fails += 1
