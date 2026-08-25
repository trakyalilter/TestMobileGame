extends SceneTree
## Audit of what each mission SAYS against what it actually requires.
##
## The other mission sims check machinery: sim_tutorial_playthrough proves every
## beat can be done, sim_coach_loot proves every beat routes to a real page and
## card, sim_craft_mission_audit proves the materials exist in the right order.
## None of them reads the instruction. So a step can be perfectly functional and
## still tell the player the wrong thing — ask for 6 and say 5, name a recipe the
## coach does not ring, or never mention the item at all — and every existing
## check stays green.
##
## That failure mode is not hypothetical here: the coach used to point at
## "Rebuild Advanced Circuitry" while the text walked through the Advanced
## Circuitry ingredients, and the only reason it was caught is that someone
## played it.
##
## So this reads every beat's text and compares it to the beat's own data, and
## then to what the coach would put on screen for it.

var errs: Array = []
var warns: Array = []
var gs
var gd
var main

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s: String) -> void: errs.append(s)
func W(s: String) -> void: warns.append(s)

## Display name of whatever a mission points at, or "" when the target is not a
## named thing (a slot type, a rarity, a page id).
func _target_name(m: Dictionary) -> String:
	var ty := String(m.get("type", ""))
	var t = m.get("target", "")
	match ty:
		"gather":
			return gd.res_name(String(t))
		"craft":
			return String((gd.MODULES.get(String(t), {}) as Dictionary).get("name", ""))
		"research":
			return String((gd.RESEARCH.get(String(t), {}) as Dictionary).get("name", ""))
		"build":
			return String((gd.BUILDINGS.get(String(t), {}) as Dictionary).get("name", ""))
		"construct":
			return String((gd.HULLS.get(String(t), {}) as Dictionary).get("name", ""))
		"defeat", "defeat_retreat":
			return String((gd.ENEMIES.get(String(t), {}) as Dictionary).get("name", ""))
	return ""

## Every display name a multi-target beat needs to mention.
func _multi_names(m: Dictionary) -> Array:
	var out: Array = []
	var t = m.get("target", "")
	match String(m.get("type", "")):
		"gather_multi":
			if t is Dictionary:
				for sym in t:
					out.append(gd.res_name(String(sym)))
		"research_multi":
			if t is Array:
				for tech in t:
					out.append(String((gd.RESEARCH.get(String(tech), {}) as Dictionary).get("name", "")))
	return out

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	gs = root.get_node("GameState")
	gd = root.get_node("GameData")
	for n in range(1, gs.SLOT_COUNT + 1):
		gs.delete_slot(n)
	gs.new_character(1, "StepAuditor")
	if is_instance_valid(main._char_select):
		main._char_select.queue_free()
		main._char_select = null
	await process_frame
	# The coach picks a recipe partly by what is researched, so judging a late beat
	# against a brand-new character measures the wrong state: a player asked for
	# Advanced Circuits has long since unlocked Automation. Read every beat as
	# someone who has reached it.
	for rid in gd.RESEARCH:
		gs.unlocked_research[rid] = true

	var beats := 0
	var named := 0
	var quantified := 0
	for mid in gd.MISSION_ORDER:
		beats += 1
		var m: Dictionary = gd.MISSIONS[mid]
		var ty := String(m.get("type", ""))
		var desc := String(m.get("desc", ""))
		var low := desc.to_lower()
		var qty := int(m.get("qty", 1))

		# ---------- 1. it has to say something ----------
		if desc.strip_edges() == "":
			E("beat '%s' (%s) has no instruction text at all" % [mid, m.get("name", mid)])
			continue
		if desc.length() < 12:
			W("beat '%s' instruction is barely a sentence: \"%s\"" % [mid, desc])

		# ---------- 2. it has to name what it wants ----------
		# A step that never mentions its own target leaves the player reading the
		# card list looking for a match.
		var want := _target_name(m)
		var multi := _multi_names(m)
		# Proper nouns (a tech, an enemy, a hull) must appear EXACTLY — the player
		# hunts for that string in a list, and "Gamma Colossus" will not find the
		# Beta Colossus. Materials and modules are matched by word stem, because
		# prose legitimately pluralises and rephrases them ("Basic Batteries" for
		# Basic Battery, "Emergency Hull Patches" for Emergency Patch).
		var strict: bool = ty in ["research", "research_multi", "defeat", "defeat_retreat", "construct"]
		if want != "":
			if _mentions(low, want, strict):
				named += 1
			else:
				E("beat '%s' asks for %s but never names it: \"%s\"" % [mid, want, desc])
		elif not multi.is_empty():
			var missing: Array = []
			for nm in multi:
				if String(nm) != "" and not _mentions(low, String(nm), strict):
					missing.append(nm)
			if missing.is_empty():
				named += 1
			else:
				E("beat '%s' does not name %s: \"%s\"" % [mid, str(missing), desc])

		# ---------- 3. the number in the text has to be the number required ----------
		# Off-by-a-number text is the quietest kind of wrong: the step completes,
		# but the player counts to the figure they were given and finds it short.
		if qty > 1 and ty in ["gather", "craft", "build", "defeat", "defeat_retreat"]:
			if desc.find(str(qty)) >= 0:
				quantified += 1
			else:
				var other := _first_number(desc)
				if other > 0 and other != qty:
					E("beat '%s' requires %d but its text says %d: \"%s\"" % [mid, qty, other, desc])
				else:
					W("beat '%s' requires %d and never states the count: \"%s\"" % [mid, qty, desc])

		# ---------- 4. no raw ids on screen ----------
		# An id in the text is a leak unless the display name is right beside it
		# (m021 names "Basic Batteries (BatteryT1)" on purpose, which is fine).
		for token in _id_tokens(m):
			# Slot types and rarities are not ids — "SHIELD slot" is the real word
			# for the thing, not a leak.
			if _name_for_id(token) == "":
				continue
			if desc.find(token) >= 0:
				var nm2 := _name_for_id(token)
				if not _mentions(low, nm2, false):
					E("beat '%s' shows the raw id '%s' with no display name: \"%s\"" % [mid, token, desc])

		# ---------- 5. the coach must ring what the text describes ----------
		var res: Dictionary = main._coach_resolve(m)
		var page := String(res.get("page", ""))
		var card := String(res.get("card", ""))
		if page == "":
			E("beat '%s' (%s) routes nowhere — the coach has no page for it" % [mid, ty])
		elif not main.pages.has(page):
			E("beat '%s' routes to '%s', which is not a page" % [mid, page])
		# Prose describes the ACTION ("Gather 350 Dirt") while the card carries a
		# proper name ("Excavate Soil"), and that is fine. What is NOT fine is text
		# that names one specific recipe while the coach rings a different one —
		# the reclaim_advanced shape, where both make the material and the player
		# is told to follow one and shown the other.
		if card != "":
			var named_other := _other_card_named(m, card, low)
			if named_other != "":
				E("beat '%s' names \"%s\" in its text but the coach rings \"%s\": \"%s\""
					% [mid, named_other, _card_display_name(card), desc])

		# ---------- 6. the page it points at has to be one the player can reach ----------
		# "tap ☰ → Warp Core" is a dead end while the Warp page is still hidden.
		if page != "" and main.pages.has(page) and not main._nav_visible(page):
			W("beat '%s' points at '%s', which is hidden in the menu until its unlock"
				% [mid, page])

	print("mission steps: %d beats read, %d name their target, %d state their count"
		% [beats, named, quantified])

	print("")
	if errs.is_empty():
		print("ERRORS: none")
	else:
		print("--- ERRORS (%d) ---" % errs.size())
		for e in errs:
			print("  x %s" % e)
	if not warns.is_empty():
		print("--- WARNINGS (%d) ---" % warns.size())
		for w in warns:
			print("  ! %s" % w)
	print("MISSION_STEPS_AUDIT: %s" % ("FAIL" if not errs.is_empty() else "PASS"))
	quit()

## Does `low` (already lowercased) mention `name`? Exact substring when strict,
## otherwise every significant word matched on a 5-character stem, so plurals and
## rephrasings pass while a different thing does not.
func _mentions(low: String, name: String, strict: bool) -> bool:
	var n := name.to_lower()
	if low.find(n) >= 0:
		return true
	if strict:
		return false
	for word in n.split(" "):
		var w := String(word)
		if w.length() < 3:
			continue
		var stem := w.substr(0, mini(5, w.length()))
		if low.find(stem) < 0:
			return false
	return true

## A DIFFERENT card that both satisfies this beat and is named in the text.
func _other_card_named(m: Dictionary, chosen: String, low: String) -> String:
	var t = m.get("target", "")
	if not (t is String) or String(t) == "":
		return ""
	for rid in gd.CRAFT:
		if String(rid) == chosen:
			continue
		if not (gd.CRAFT[rid] as Dictionary).get("outputs", {}).has(String(t)):
			continue
		var nm := String((gd.CRAFT[rid] as Dictionary).get("name", ""))
		if nm != "" and low.find(nm.to_lower()) >= 0:
			return nm
	return ""

## The first standalone number in a sentence, or 0.
func _first_number(text: String) -> int:
	var cur := ""
	for i in text.length():
		var ch := text[i]
		if ch >= "0" and ch <= "9":
			cur += ch
		elif cur != "":
			return int(cur)
	return int(cur) if cur != "" else 0

## Ids this beat could leak into its own text.
func _id_tokens(m: Dictionary) -> Array:
	var out: Array = []
	var t = m.get("target", "")
	if t is String and String(t) != "":
		out.append(String(t))
	elif t is Dictionary:
		for k in t:
			out.append(String(k))
	elif t is Array:
		for k2 in t:
			out.append(String(k2))
	return out

func _name_for_id(id: String) -> String:
	if gd.RESOURCES.has(id):
		return gd.res_name(id)
	for table in [gd.MODULES, gd.RESEARCH, gd.BUILDINGS, gd.HULLS, gd.ENEMIES, gd.CRAFT]:
		if (table as Dictionary).has(id):
			return String(((table as Dictionary)[id] as Dictionary).get("name", ""))
	return ""

## What the ringed card calls itself.
func _card_display_name(card: String) -> String:
	for table in [gd.CRAFT, gd.GATHER, gd.MODULES, gd.RESEARCH, gd.BUILDINGS, gd.ENEMIES]:
		if (table as Dictionary).has(card):
			return String(((table as Dictionary)[card] as Dictionary).get("name", ""))
	return ""

## Other cards that would also satisfy this beat — named so a mismatch report
## says which one the text is actually describing.
func _alternatives_for(m: Dictionary, chosen: String) -> String:
	var t = m.get("target", "")
	if not (t is String):
		return ""
	var others: Array = []
	for rid in gd.CRAFT:
		if String(rid) == chosen:
			continue
		if (gd.CRAFT[rid] as Dictionary).get("outputs", {}).has(String(t)):
			others.append(String((gd.CRAFT[rid] as Dictionary).get("name", rid)))
	if others.is_empty():
		return ""
	return " (also makes it: %s)" % ", ".join(others)
