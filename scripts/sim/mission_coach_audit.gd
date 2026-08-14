extends Node
# ============================================================================
# MISSION COACHING AUDIT — deep sanity of every coaching surface.
# Complements mission_routing_check (types/sourcing/phrasing) with the classes
# that actually softlock or strand the arrow:
#  A. main.gd's EXPLICIT coaching calls (parsed from source) point at things
#     that exist: get_node_widget(tech) / focus_action(aid) / get_widget_by_aid
#     (recipe) / focus_module_tab(module) / get_enemy_card(enemy) / focus_zone.
#  B. tech coaching targets are in research_page's graphs ALLOWLIST — a tech in
#     tech_tree but not in any tab list renders INVISIBLE (firmware_hacking bug).
#  C. every mission target exists per type (research/craft/defeat/construct/
#     build/visit_page) + research targets are VISIBLE (allowlist).
#  D. chain integrity: every next_mission id exists.
#   Godot --headless --path <root> res://scenes/mission_coach_audit.tscn
#   (backup/restore the save around it — hard_reset)
# ============================================================================

var fails := 0
func _ok(name: String, cond: bool, detail = "") -> void:
	if not cond: fails += 1
	print("[COACH] %-52s %s %s" % [name, "OK" if cond else "*** FAIL", str(detail).substr(0, 300)])

func _extract(src: String, pattern: String) -> Array:
	var out := []
	var re := RegEx.new()
	re.compile(pattern)
	for m in re.search_all(src):
		var v := m.get_string(1)
		if not v in out: out.append(v)
	return out

func _ready() -> void:
	GameState.hard_reset()
	var mm = GameState.mission_manager
	var rm = GameState.research_manager
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var gm = GameState.gathering_manager
	var pm = GameState.processing_manager
	var im = GameState.infrastructure_manager
	print("[COACH] ============ mission coaching audit ============")

	# Research render allowlist (graphs) — bare .new() (no _ready, inline var ok).
	var rp = load("res://scripts/ui/research_page.gd").new()
	var visible_techs := {}
	for tab in rp.graphs:
		for nid in rp.graphs[tab]["nodes"]:
			visible_techs[String(nid)] = true
	rp.free()

	# ── A/B: parse main.gd's explicit coaching calls ──
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_ok("main.gd readable", src.length() > 1000)

	var bad := []
	for tech in _extract(src, 'get_node_widget\\("([A-Za-z0-9_]+)"\\)'):
		if not tech in rm.tech_tree: bad.append("no-tech:" + tech)
		elif not visible_techs.has(tech): bad.append("INVISIBLE-tech:" + tech)
	_ok("A/B main.gd tech coachings exist + visible", bad.is_empty(), bad)

	bad = []
	for aid in _extract(src, 'focus_action\\("([A-Za-z0-9_]+)"\\)'):
		if not aid in gm.actions: bad.append(aid)
	_ok("A main.gd gather-action coachings exist", bad.is_empty(), bad)

	bad = []
	for rid in _extract(src, 'get_widget_by_aid\\("([A-Za-z0-9_]+)"\\)'):
		if not (rid in pm.recipes or rid in gm.actions): bad.append(rid)
	_ok("A main.gd recipe coachings exist", bad.is_empty(), bad)

	bad = []
	for mid2 in _extract(src, 'focus_module_tab\\("([A-Za-z0-9_]+)"\\)'):
		if not mid2 in sm.modules: bad.append(mid2)
	_ok("A main.gd module coachings exist", bad.is_empty(), bad)

	bad = []
	for eid in _extract(src, 'get_enemy_card\\("([A-Za-z0-9_]+)"\\)'):
		if not eid in cm.enemy_db: bad.append(eid)
	_ok("A main.gd enemy-card coachings exist", bad.is_empty(), bad)

	bad = []
	for zid in _extract(src, 'focus_zone\\("([A-Za-z0-9_]+)"\\)'):
		if not zid in cm.zones: bad.append(zid)
	_ok("A main.gd zone coachings exist", bad.is_empty(), bad)

	# Known sidebar pages (from main.gd pages[...] literals) for visit_page checks.
	var pages := {}
	for p in _extract(src, 'pages\\["([a-z_]+)"\\]'):
		pages[p] = true

	# ── C/D: every mission's target + chain link ──
	var t_missing := []
	var t_invisible := []
	var chain_broken := []
	for mid in mm.missions:
		var m: Dictionary = mm.missions[mid]
		var mtype := String(m.get("type", ""))
		var tgt = m.get("target", "")
		match mtype:
			"research":
				if not String(tgt) in rm.tech_tree: t_missing.append("%s:tech:%s" % [mid, tgt])
				elif not visible_techs.has(String(tgt)): t_invisible.append("%s:%s" % [mid, tgt])
			"research_multi":
				for t in (tgt if tgt is Array else []):
					if not String(t) in rm.tech_tree: t_missing.append("%s:tech:%s" % [mid, t])
					elif not visible_techs.has(String(t)): t_invisible.append("%s:%s" % [mid, t])
			"craft":
				if not String(tgt) in sm.modules: t_missing.append("%s:module:%s" % [mid, tgt])
			"defeat":
				if not String(tgt) in cm.enemy_db: t_missing.append("%s:enemy:%s" % [mid, tgt])
			"construct":
				if not String(tgt) in sm.hulls: t_missing.append("%s:hull:%s" % [mid, tgt])
			"build":
				if im and not String(tgt) in im.building_db: t_missing.append("%s:building:%s" % [mid, tgt])
			"visit_page":
				if not pages.has(String(tgt)): t_missing.append("%s:page:%s" % [mid, tgt])
			"atlas_lookup":
				if not ElementDB.ELEMENT_NAMES.has(String(tgt)): t_missing.append("%s:material:%s" % [mid, tgt])
		var nid := String(m.get("next_mission", ""))
		if nid != "" and not nid in mm.missions:
			chain_broken.append("%s->%s" % [mid, nid])
	_ok("C mission targets all exist", t_missing.is_empty(), t_missing)
	_ok("C research targets all VISIBLE (allowlist)", t_invisible.is_empty(), t_invisible)
	_ok("D next_mission chain intact", chain_broken.is_empty(), chain_broken)

	print("[COACH] ============ %s ============" % ("ALL PASS" if fails == 0 else "%d FAIL(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
