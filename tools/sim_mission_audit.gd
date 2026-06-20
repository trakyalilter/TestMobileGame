extends SceneTree
## Detailed sanity check of the mission chain: structure (links/cycles/orphans),
## target validity, reachability, research ORDERING along the chain, coach
## resolvability, and soft level-gate warnings.

var main
var gd
var errors: Array = []
var warns: Array = []
var unlocked := {}   # techs unlocked so far along the chain

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s): errors.append(s)
func W(s): warns.append(s)

func _gather_source(sym) -> bool:
	for gid in GameData.GATHER:
		for row in GameData.GATHER[gid].get("loot", []):
			if row[0] == sym: return true
	return false
func _enemy_source(sym) -> bool:
	for eid in GameData.ENEMIES:
		for row in GameData.ENEMIES[eid].get("loot", []):
			if row[0] == sym: return true
	return false
func _craft_recipes_for(sym) -> Array:
	var out := []
	for cid in GameData.CRAFT:
		if GameData.CRAFT[cid].get("outputs", {}).has(sym): out.append(cid)
	return out

# Is `sym` obtainable, considering research unlocked SO FAR? Returns one of:
# "gather"/"enemy"/"craft"/"craft_locked"/"none".
func _obtainable(sym) -> String:
	if _gather_source(sym): return "gather"
	if _enemy_source(sym): return "enemy"
	var recs := _craft_recipes_for(sym)
	if recs.is_empty(): return "none"
	for cid in recs:
		var rr: String = GameData.CRAFT[cid].get("research_req", "")
		if rr == "" or unlocked.has(rr): return "craft"
	return "craft_locked"

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	await process_frame
	gd = root.get_node("GameData")
	var M: Dictionary = GameData.MISSIONS

	# --- Structure: links, head, cycle/orphan detection on the m001 chain. ---
	var referenced := {}
	for mid in M:
		var nx: String = M[mid].get("next", "")
		if nx != "":
			if not M.has(nx):
				E("%s -> next '%s' does NOT exist" % [mid, nx])
			referenced[nx] = true
	var start := "m001" if M.has("m001") else ""
	if start == "":
		E("no m001 start mission")
	# Walk the chain.
	var chain := []
	var seen := {}
	var cur := start
	while cur != "" and M.has(cur):
		if seen.has(cur):
			E("CYCLE in chain at %s" % cur); break
		seen[cur] = true
		chain.append(cur)
		cur = M[cur].get("next", "")
	print("chain length from m001: %d" % chain.size())

	# Orphans: missions not on the chain and not a standalone core goal.
	for mid in M:
		var nm: String = M[mid].get("name", "")
		if not seen.has(mid) and not nm.begins_with("[CORE GOAL]"):
			W("orphan (not on m001 chain, not a core goal): %s '%s'" % [mid, nm])

	# --- Per-mission checks, in chain order (so research unlocks accumulate). ---
	for mid in chain:
		_check_mission(mid, M[mid])

	# Also validate target sanity for off-chain core goals (no research-order check).
	for mid in M:
		if not seen.has(mid):
			_check_target_only(mid, M[mid])

	# --- Report. ---
	print("\n===== MISSION AUDIT =====")
	print("missions: %d   on-chain: %d   errors: %d   warnings: %d" % [M.size(), chain.size(), errors.size(), warns.size()])
	if not warns.is_empty():
		print("\n--- WARNINGS (%d) ---" % warns.size())
		for w in warns: print("  ⚠ " + w)
	if not errors.is_empty():
		print("\n--- ERRORS (%d) ---" % errors.size())
		for e in errors: print("  ✗ " + e)
		print("\nMISSION_AUDIT: FAIL")
		quit(1)
	print("\nMISSION_AUDIT: PASS")
	quit()

func _check_target_only(mid, m) -> void:
	var t: String = m.get("type", "")
	var tgt = m.get("target", "")
	match t:
		"defeat":
			if not GameData.ENEMIES.has(tgt): E("%s defeat target enemy missing: %s" % [mid, tgt])
		"research":
			if not GameData.RESEARCH.has(tgt): E("%s research target tech missing: %s" % [mid, tgt])
		"construct":
			if not GameData.HULLS.has(tgt): E("%s construct target hull missing: %s" % [mid, tgt])

func _check_mission(mid, m) -> void:
	var t: String = m.get("type", "")
	var tgt = m.get("target", "")
	var nm: String = m.get("name", "")
	# Rewards present.
	if int(m.get("cr", 0)) < 0 or int(m.get("xp", 0)) < 0:
		E("%s negative reward" % mid)
	match t:
		"gather", "hull", "shield":
			var ob := _obtainable(tgt)
			if ob == "none":
				E("%s (%s) target '%s' has NO source (no gather/craft/enemy)" % [mid, t, tgt])
			elif ob == "craft_locked":
				E("%s (%s) needs '%s' but its only recipe's research isn't unlocked yet in the chain" % [mid, t, tgt])
		"gather_multi":
			if tgt is Dictionary:
				for sym in tgt:
					if _obtainable(sym) in ["none", "craft_locked"]:
						E("%s gather_multi material '%s' not obtainable yet" % [mid, sym])
		"craft":
			if not GameData.MODULES.has(tgt):
				E("%s craft target module missing: %s" % [mid, tgt])
			else:
				var rr: String = GameData.MODULES[tgt].get("research_req", "")
				if rr != "" and not unlocked.has(rr):
					E("%s crafts module '%s' but research '%s' not unlocked yet" % [mid, tgt, rr])
		"construct":
			if not GameData.HULLS.has(tgt):
				E("%s construct hull missing: %s" % [mid, tgt])
		"defeat":
			if not GameData.ENEMIES.has(tgt):
				E("%s defeat target enemy missing: %s" % [mid, tgt])
		"research":
			if not GameData.RESEARCH.has(tgt):
				E("%s research tech missing: %s" % [mid, tgt])
			else:
				unlocked[tgt] = true
		"research_multi":
			if tgt is Array:
				for tech in tgt:
					if not GameData.RESEARCH.has(tech): E("%s research_multi tech missing: %s" % [mid, tech])
					else: unlocked[tech] = true
		"visit_page":
			if not (String(tgt) in main.PAGE_IDS): E("%s visit_page target not a page: %s" % [mid, tgt])
		"loadout_check", "loadout_rare_weapon", "equip_consumables", "drop_rarity", "warp_perform", "discover":
			pass
		_:
			W("%s unknown mission type '%s'" % [mid, t])

	# Coach resolution must yield a real page + resolvable card.
	var res: Dictionary = main._coach_resolve(m)
	var page: String = res.get("page", "")
	var card: String = res.get("card", "")
	if page != "" and not (page in main.PAGE_IDS):
		E("%s coach page '%s' not a valid page" % [mid, page])
	if card != "":
		var card_ok := GameData.GATHER.has(card) or GameData.CRAFT.has(card) or GameData.ENEMIES.has(card) or GameData.RESEARCH.has(card) or GameData.MODULES.has(card) or GameData.HULLS.has(card)
		if not card_ok:
			W("%s coach card '%s' (page %s) not directly resolvable" % [mid, card, page])

	# Soft: flag a craft/gather step whose chosen recipe has a steep level gate.
	if t in ["gather", "hull", "shield"]:
		for cid in _craft_recipes_for(tgt):
			var lvl := int(GameData.CRAFT[cid].get("level_req", 1))
			if lvl >= 45:
				W("%s needs '%s' via %s (Lv %d fabrication) — verify the player can reach that level here" % [mid, tgt, cid, lvl])
				break
